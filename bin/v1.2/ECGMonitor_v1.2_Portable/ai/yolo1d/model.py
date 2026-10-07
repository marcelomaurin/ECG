"""
Modelo YOLO 1D para Deteccao Temporal de Eventos e Arritmias em Sinais de ECG.
Inspirado nos trabalhos ECGyolo e YOLO-ECG (2026).
"""

import math
import torch
import torch.nn as nn
import torch.nn.functional as F


class ConvBlock1D(nn.Module):
    """Bloco Convolucional 1D com Conv1d + BatchNorm1d + SiLU (Swish)."""
    def __init__(self, in_channels, out_channels, kernel_size=7, stride=1, padding=None):
        super().__init__()
        if padding is None:
            padding = kernel_size // 2
        self.conv = nn.Conv1d(in_channels, out_channels, kernel_size, stride=stride, padding=padding, bias=False)
        self.bn = nn.BatchNorm1d(out_channels)
        self.act = nn.SiLU()

    def forward(self, x):
        return self.act(self.bn(self.conv(x)))


class ResidualBlock1D(nn.Module):
    """Bloco Residual 1D com conexao de atalho."""
    def __init__(self, channels):
        super().__init__()
        mid_channels = channels // 2
        self.cv1 = ConvBlock1D(channels, mid_channels, kernel_size=1)
        self.cv2 = ConvBlock1D(mid_channels, channels, kernel_size=7)

    def forward(self, x):
        return x + self.cv2(self.cv1(x))


class Backbone1D(nn.Module):
    """
    Backbone Convolucional 1D para extracao de caracteristicas temporais.
    Entrada: (B, 1, L) onde L = 5000 amostras (10 segundos a 500 Hz).
    """
    def __init__(self, in_channels=1, base_channels=32):
        super().__init__()
        # Stem
        self.stem = ConvBlock1D(in_channels, base_channels, kernel_size=9, stride=2)  # L/2 = 2500
        
        # Estagio 1
        self.stage1 = nn.Sequential(
            ConvBlock1D(base_channels, base_channels * 2, kernel_size=7, stride=2),  # L/4 = 1250
            ResidualBlock1D(base_channels * 2),
            ResidualBlock1D(base_channels * 2)
        )
        
        # Estagio 2
        self.stage2 = nn.Sequential(
            ConvBlock1D(base_channels * 2, base_channels * 4, kernel_size=7, stride=2),  # L/8 = 625
            ResidualBlock1D(base_channels * 4),
            ResidualBlock1D(base_channels * 4)
        )
        
        # Estagio 3
        self.stage3 = nn.Sequential(
            ConvBlock1D(base_channels * 4, base_channels * 8, kernel_size=7, stride=2),  # L/16 = 312
            ResidualBlock1D(base_channels * 8),
            ResidualBlock1D(base_channels * 8)
        )

    def forward(self, x):
        x = self.stem(x)
        c1 = self.stage1(x)  # stride 4
        c2 = self.stage2(c1) # stride 8
        c3 = self.stage3(c2) # stride 16
        return c1, c2, c3


class YOLOHead1D(nn.Module):
    """
    Cabecote YOLO 1D para predicao de bounding boxes temporais.
    Para cada celula do grid 1D e para cada anchor:
      - center_offset: deslocamento no tempo
      - width: largura do evento temporal (QRS)
      - objectness: confianca de que ha um batimento
      - class_probs: probabilidades das classes (N, S, V, F, Q)
    """
    def __init__(self, in_channels, num_anchors=3, num_classes=5):
        super().__init__()
        self.num_anchors = num_anchors
        self.num_classes = num_classes
        # 1 (center) + 1 (width) + 1 (obj) + num_classes
        self.out_dim = num_anchors * (3 + num_classes)
        self.head = nn.Conv1d(in_channels, self.out_dim, kernel_size=1)

    def forward(self, x):
        # x: (B, C, G) -> (B, num_anchors * (3 + num_classes), G)
        out = self.head(x)
        B, _, G = out.shape
        # Reshape para (B, num_anchors, 3 + num_classes, G) e permuta para (B, num_anchors, G, 3 + num_classes)
        out = out.view(B, self.num_anchors, 3 + self.num_classes, G).permute(0, 1, 3, 2)
        return out


class ECGYOLO1D(nn.Module):
    """
    Rede Neural Completa YOLO 1D para Eletrocardiograma.
    Localiza complexos QRS e classifica batimentos diretamente no sinal temporal.
    """
    def __init__(self, in_channels=1, num_classes=5, anchors=[0.016, 0.028, 0.045]):
        super().__init__()
        self.num_classes = num_classes
        self.anchors = torch.tensor(anchors, dtype=torch.float32)
        self.num_anchors = len(anchors)

        self.backbone = Backbone1D(in_channels=in_channels, base_channels=32)

        # FPN 1D (Feature Pyramid Network)
        self.lateral3 = ConvBlock1D(256, 128, kernel_size=1)
        self.lateral2 = ConvBlock1D(128, 128, kernel_size=1)
        self.smooth2 = ConvBlock1D(128, 128, kernel_size=5)

        # Cabecote preditor na escala refinada (stride 8 -> 625 celulas no tempo)
        self.head = YOLOHead1D(in_channels=128, num_anchors=self.num_anchors, num_classes=num_classes)

    def forward(self, x):
        # x: (B, 1, 5000)
        _, c2, c3 = self.backbone(x)
        
        # Fusao top-down FPN 1D
        p3 = self.lateral3(c3)
        p3_upsampled = F.interpolate(p3, size=c2.shape[-1], mode='linear', align_corners=False)
        p2 = self.lateral2(c2) + p3_upsampled
        p2 = self.smooth2(p2)

        # Predicao no grid de 625 celulas
        out = self.head(p2)  # (B, num_anchors, Grid, 3 + num_classes)
        return out

    def decode(self, raw_preds, conf_thresh=0.6):
        """
        Decodifica as saidas brutas do modelo para caixas temporais normalizadas [0, 1].
        Retorna lista de tensores: [center, width, objectness, class_id, class_score]
        """
        device = raw_preds.device
        anchors = self.anchors.to(device)

        B, num_anchors, G, _ = raw_preds.shape
        grid_indices = torch.arange(G, device=device).float().unsqueeze(0).unsqueeze(0) # (1, 1, G)

        # Sigmoid nas probabilidades e offsets
        center_offset = torch.sigmoid(raw_preds[..., 0]) # (B, A, G)
        center = (grid_indices + center_offset) / G     # centro normalizado [0, 1]

        width_raw = raw_preds[..., 1]
        anchor_tensor = anchors.view(1, num_anchors, 1).expand(B, num_anchors, G)
        width = anchor_tensor * torch.exp(torch.clamp(width_raw, -3.0, 3.0))

        objectness = torch.sigmoid(raw_preds[..., 2])
        class_probs = torch.softmax(raw_preds[..., 3:], dim=-1)
        max_class_score, class_id = torch.max(class_probs, dim=-1)

        confidence = objectness * max_class_score

        # Start e End normalizados [0, 1]
        start = torch.clamp(center - (width / 2.0), 0.0, 1.0)
        end = torch.clamp(center + (width / 2.0), 0.0, 1.0)

        # Flatten para (B, A*G, ...)
        start = start.reshape(B, -1)
        end = end.reshape(B, -1)
        confidence = confidence.reshape(B, -1)
        class_id = class_id.reshape(B, -1)

        batch_detections = []
        for b in range(B):
            mask = confidence[b] >= conf_thresh
            if mask.sum() == 0:
                batch_detections.append(torch.empty((0, 4), device=device))
                continue

            b_start = start[b, mask]
            b_end = end[b, mask]
            b_conf = confidence[b, mask]
            b_cls = class_id[b, mask].float()

            boxes = torch.stack([b_start, b_end, b_conf, b_cls], dim=-1)
            # Aplica Non-Maximum Suppression 1D
            keep = nms_1d(boxes[:, 0], boxes[:, 1], boxes[:, 2], iou_thresh=0.3)
            batch_detections.append(boxes[keep])

        return batch_detections


def calculate_iou_1d(start1, end1, start2, end2):
    """Calcula a Intersection over Union (IoU) para intervalos temporais unidimensionais."""
    inter_start = torch.max(start1, start2)
    inter_end = torch.min(end1, end2)
    inter_len = torch.clamp(inter_end - inter_start, min=0.0)

    len1 = torch.clamp(end1 - start1, min=1e-6)
    len2 = torch.clamp(end2 - start2, min=1e-6)
    union_len = len1 + len2 - inter_len

    return inter_len / union_len


def nms_1d(starts, ends, scores, iou_thresh=0.3):
    """Non-Maximum Suppression (NMS) em 1 Dimensao Temporal."""
    if starts.numel() == 0:
        return torch.empty(0, dtype=torch.long, device=starts.device)

    order = scores.argsort(descending=True)
    keep = []

    while order.numel() > 0:
        i = order[0].item()
        keep.append(i)
        if order.numel() == 1:
            break

        others = order[1:]
        ious = calculate_iou_1d(starts[i], ends[i], starts[others], ends[others])
        remaining = others[ious <= iou_thresh]
        order = remaining

    return torch.tensor(keep, dtype=torch.long, device=starts.device)
