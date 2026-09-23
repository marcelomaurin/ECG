"""
Dataset para treinamento e avaliacao do YOLO 1D em sinais de ECG.
Suporta dados gravados em SQLite, arquivos .npy/.csv e geracao de ECG sintetico anotado.
"""

import numpy as np
import torch
from torch.utils.data import Dataset


class ECGDataset1D(Dataset):
    """
    Dataset de janelas de 10 segundos (5000 amostras a 500 Hz).
    Cada anotacao contem: [classe, center_normalizado, width_normalizado].
    """
    def __init__(self, signals=None, annotations=None, window_size=5000):
        self.window_size = window_size
        self.signals = signals if signals is not None else []
        self.annotations = annotations if annotations is not None else []

    def __len__(self):
        return len(self.signals)

    def __getitem__(self, idx):
        sig = torch.tensor(self.signals[idx], dtype=torch.float32).unsqueeze(0) # (1, 5000)
        ann = torch.tensor(self.annotations[idx], dtype=torch.float32)          # (M, 3)
        return sig, ann


def generate_synthetic_ecg_window(sample_rate=500, duration_sec=10, bpm=75, pvc_ratio=0.15):
    """
    Gera uma janela de ECG sintetico de 10 segundos com anotacoes de ground truth
    para classes N (Normal, 0) e V (Ventricular/PVC, 2).
    """
    total_samples = sample_rate * duration_sec
    time = np.linspace(0, duration_sec, total_samples, endpoint=False)
    signal = np.zeros(total_samples, dtype=np.float32)

    annotations = [] # lista de [class_id, center_norm, width_norm]

    # Intervalo entre batimentos (segundos)
    rr_sec = 60.0 / bpm
    current_time = 0.5 + np.random.uniform(0.0, 0.2)

    while current_time < (duration_sec - 0.4):
        is_pvc = (np.random.random() < pvc_ratio)
        class_id = 2 if is_pvc else 0  # 2: Ventricular (PVC), 0: Normal (N)

        # Duracao aproximada do QRS (80ms a 140ms)
        qrs_duration_sec = 0.14 if is_pvc else 0.09
        half_qrs = qrs_duration_sec / 2.0

        start_time = max(0.0, current_time - half_qrs)
        end_time = min(duration_sec, current_time + half_qrs)

        center_norm = current_time / duration_sec
        width_norm = qrs_duration_sec / duration_sec

        annotations.append([class_id, center_norm, width_norm])

        # Gera morfologia da onda no sinal
        dt = time - current_time

        if is_pvc:
            # Morfologia aberrante de PVC (alargada e bifasica invertida)
            signal += 1.4 * np.exp(-((dt / 0.035) ** 2))
            signal -= 0.6 * np.exp(-(((dt - 0.05) / 0.04) ** 2))
            # Onda T invertida
            signal -= 0.4 * np.exp(-(((dt - 0.15) / 0.08) ** 2))
        else:
            # Onda P
            signal += 0.15 * np.exp(-(((dt + 0.16) / 0.03) ** 2))
            # Complexo QRS normal
            signal -= 0.12 * np.exp(-(((dt + 0.02) / 0.012) ** 2)) # Q
            signal += 1.10 * np.exp(-((dt / 0.018) ** 2))           # R
            signal -= 0.25 * np.exp(-(((dt - 0.025) / 0.015) ** 2))# S
            # Onda T
            signal += 0.28 * np.exp(-(((dt - 0.20) / 0.06) ** 2))

        # Proximo batimento (com leve variabilidade sinusal)
        variability = np.random.uniform(-0.04, 0.04)
        current_time += (rr_sec + variability)

    # Adiciona ruido de linha de base (respiracao ~0.25 Hz)
    signal += 0.08 * np.sin(2 * np.pi * 0.25 * time)
    # Adiciona leve ruido de alta frequencia
    signal += 0.02 * np.random.randn(total_samples)

    # Normalizacao z-score
    signal = (signal - np.mean(signal)) / (np.std(signal) + 1e-6)

    return signal.astype(np.float32), np.array(annotations, dtype=np.float32)


def create_synthetic_dataset(num_samples=100, window_size=5000):
    """Cria um dataset sintetico de treinamento."""
    signals = []
    annotations = []
    for _ in range(num_samples):
        bpm = np.random.randint(55, 110)
        pvc_ratio = np.random.uniform(0.05, 0.25)
        sig, ann = generate_synthetic_ecg_window(sample_rate=500, duration_sec=10, bpm=bpm, pvc_ratio=pvc_ratio)
        signals.append(sig)
        annotations.append(ann)

    return ECGDataset1D(signals, annotations, window_size=window_size)
