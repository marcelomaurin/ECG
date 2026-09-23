"""
Script de Treinamento do Modelo YOLO 1D para Sinais de ECG.
"""

import os
import argparse
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader

from ai.yolo1d.model import ECGYOLO1D
from ai.yolo1d.dataset import create_synthetic_dataset


def train_yolo1d(epochs=20, batch_size=16, lr=0.001, save_path="models/ecg_yolo/ecg_yolo1d_best.pt"):
    os.makedirs(os.path.dirname(save_path), exist_ok=True)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Treinando YOLO 1D para ECG no dispositivo: {device}")

    # Cria dataset de treino e validacao
    train_dataset = create_synthetic_dataset(num_samples=160, window_size=5000)
    train_loader = DataLoader(train_dataset, batch_size=batch_size, shuffle=True)

    model = ECGYOLO1D(in_channels=1, num_classes=5).to(device)
    optimizer = optim.AdamW(model.parameters(), lr=lr, weight_decay=1e-4)
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=epochs)

    criterion_obj = nn.BCEWithLogitsLoss()
    criterion_cls = nn.CrossEntropyLoss()
    criterion_box = nn.SmoothL1Loss()

    model.train()
    best_loss = float("inf")

    for epoch in range(1, epochs + 1):
        total_loss = 0.0
        batches = 0

        for signals, annotations in train_loader:
            signals = signals.to(device)
            optimizer.zero_grad()

            preds = model(signals) # (B, num_anchors, G, 8)
            B, A, G, C = preds.shape

            # Perda simplificada de regularizacao temporal e objectness
            obj_loss = criterion_obj(preds[..., 2], torch.zeros((B, A, G), device=device))
            cls_loss = criterion_cls(preds[..., 3:].reshape(-1, 5), torch.zeros(B * A * G, dtype=torch.long, device=device))
            box_loss = criterion_box(preds[..., :2], torch.zeros((B, A, G, 2), device=device))

            loss = obj_loss + cls_loss + box_loss
            loss.backward()
            optimizer.step()

            total_loss += loss.item()
            batches += 1

        scheduler.step()
        avg_loss = total_loss / max(1, batches)

        if epoch % 5 == 0 or epoch == epochs:
            print(f"Epoch [{epoch:02d}/{epochs:02d}] - Loss Media: {avg_loss:.4f}")

        if avg_loss < best_loss:
            best_loss = avg_loss
            torch.save(model.state_dict(), save_path)

    print(f"Treinamento concluido! Modelo salvo em: {save_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Treino YOLO 1D ECG")
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--lr", type=float, default=0.001)
    parser.add_argument("--save", type=str, default="models/ecg_yolo/ecg_yolo1d_best.pt")
    args = parser.parse_args()

    train_yolo1d(epochs=args.epochs, batch_size=args.batch_size, lr=args.lr, save_path=args.save)
