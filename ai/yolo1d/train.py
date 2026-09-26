"""
Script de Treinamento Real do Modelo YOLO 1D para Sinais de ECG.
Calcula perdas reais de deteccao de caixas temporais, presenca de objeto (QRS) e classes AAMI.
"""

import os
import argparse
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch.utils.data import DataLoader

from ai.yolo1d.model import ECGYOLO1D
from ai.yolo1d.dataset import create_synthetic_dataset


def build_targets(annotations_list, grid_size=625, num_anchors=3, anchors=None, device="cpu"):
    """
    Mapeia anotacoes temporais de cada amostra do lote para os alvos do grid YOLO 1D.
    annotations_list: lista de tensores [M, 3] onde cada linha eh [class_id, center_norm, width_norm].
    """
    if anchors is None:
        anchors = torch.tensor([0.016, 0.028, 0.045], device=device)
    else:
        anchors = anchors.to(device)

    B = len(annotations_list)
    G = grid_size
    A = num_anchors

    target_obj = torch.zeros((B, A, G), dtype=torch.float32, device=device)
    target_offset = torch.zeros((B, A, G), dtype=torch.float32, device=device)
    target_width = torch.zeros((B, A, G), dtype=torch.float32, device=device)
    target_cls = torch.zeros((B, A, G), dtype=torch.long, device=device)
    obj_mask = torch.zeros((B, A, G), dtype=torch.bool, device=device)

    for b, ann in enumerate(annotations_list):
        if ann.numel() == 0:
            continue
        for row in ann:
            cls_id = int(row[0].item())
            center_norm = float(row[1].item())
            width_norm = float(row[2].item())

            grid_pos = center_norm * G
            g_idx = int(grid_pos)
            if 0 <= g_idx < G:
                # Escolhe o anchor de melhor correspondencia de largura
                diff = torch.abs(anchors - width_norm)
                best_a = int(torch.argmin(diff).item())

                offset = grid_pos - g_idx # entre 0 e 1
                offset = max(1e-4, min(1.0 - 1e-4, offset))

                # Inverso do sigmoid para loss logit
                logit_offset = float(np.log(offset / (1.0 - offset)))
                ratio_w = max(1e-3, width_norm / float(anchors[best_a].item()))
                log_w = float(np.log(ratio_w))

                target_obj[b, best_a, g_idx] = 1.0
                target_offset[b, best_a, g_idx] = logit_offset
                target_width[b, best_a, g_idx] = log_w
                target_cls[b, best_a, g_idx] = cls_id
                obj_mask[b, best_a, g_idx] = True

    return target_obj, target_offset, target_width, target_cls, obj_mask


def collate_fn_ecg(batch):
    signals = torch.stack([item[0] for item in batch])
    annotations = [item[1] for item in batch]
    return signals, annotations


def train_yolo1d(epochs=25, batch_size=16, lr=0.001, save_path="models/ecg_yolo/ecg_yolo1d_best.pt"):
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Iniciando Treinamento Real do YOLO 1D no dispositivo: {device}")

    # Dataset sintetico variado de alta fidelidade
    train_dataset = create_synthetic_dataset(num_samples=240, window_size=5000)
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True, collate_fn=collate_fn_ecg)

    model = ECGYOLO1D(in_channels=1, num_classes=5).to(device)
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)

    criterion_obj = nn.BCEWithLogitsLoss(pos_weight=torch.tensor([6.0], device=device))
    criterion_box = nn.SmoothL1Loss()
    criterion_cls = nn.CrossEntropyLoss()

    best_loss = float("inf")
    model.train()

    for epoch in range(1, epochs + 1):
        total_loss = 0.0
        batches = 0

        for signals, annotations in train_loader:
            signals = signals.to(device)
            optimizer.zero_grad()

            preds = model(signals) # (B, num_anchors, G, 8)
            B, A, G, C = preds.shape

            target_obj, target_offset, target_width, target_cls, obj_mask = build_targets(
                annotations, grid_size=G, num_anchors=A, anchors=model.anchors, device=device
            )

            # Perda de presenca de evento (objectness)
            loss_obj = criterion_obj(preds[..., 2], target_obj)

            if obj_mask.sum() > 0:
                # Perda de localizacao temporal (offset de centro)
                pred_offset = preds[..., 0][obj_mask]
                loss_offset = criterion_box(pred_offset, target_offset[obj_mask])

                # Perda de largura do QRS (width)
                pred_width = preds[..., 1][obj_mask]
                loss_width = criterion_box(pred_width, target_width[obj_mask])

                # Perda de classificacao (N, S, V, F, Q)
                pred_cls = preds[..., 3:][obj_mask]
                loss_cls = criterion_cls(pred_cls, target_cls[obj_mask])

                loss = (2.0 * loss_obj) + (1.2 * loss_offset) + (1.0 * loss_width) + (1.5 * loss_cls)
            else:
                loss = loss_obj

            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
            optimizer.step()

            total_loss += loss.item()
            batches += 1

        scheduler.step()
        avg_loss = total_loss / max(1, batches)

        if epoch % 5 == 0 or epoch == epochs:
            print(f"Epoch [{epoch:02d}/{epochs:02d}] - Loss Media Real: {avg_loss:.4f}")

        if avg_loss < best_loss:
            best_loss = avg_loss
            torch.save(model.state_dict(), save_path)

    print(f"Treinamento real concluido com sucesso! Pesos salvos em: {save_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Treino Real YOLO 1D ECG")
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--save", type=str, default="models/ecg_yolo/ecg_yolo1d_best.pt")
    args = parser.parse_args()

    train_yolo1d(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr, save_path=args.save)
