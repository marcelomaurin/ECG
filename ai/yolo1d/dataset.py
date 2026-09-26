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
    Gera uma janela de ECG sintetico de 10 segundos com acoplamento prematuro e pausa
    compensatoria reais para classes N (Normal, 0) e V (Ventricular/PVC, 2).
    """
    total_samples = sample_rate * duration_sec
    time = np.linspace(0, duration_sec, total_samples, endpoint=False)
    signal = np.zeros(total_samples, dtype=np.float32)

    annotations = [] # lista de [class_id, center_norm, width_norm]

    rr_sec = 60.0 / bpm
    current_time = 0.5 + np.random.uniform(0.0, 0.2)
    prev_was_pvc = False

    while current_time < (duration_sec - 0.4):
        if prev_was_pvc:
            is_pvc = False
            prev_was_pvc = False
            # Pausa compensatoria apos o PVC
            next_step = rr_sec * 1.38
        else:
            is_pvc = (np.random.random() < pvc_ratio)
            if is_pvc:
                prev_was_pvc = True
                # Acoplamento prematuro antes do PVC
                next_step = rr_sec * 0.62
            else:
                next_step = rr_sec + np.random.uniform(-0.02, 0.02)

        class_id = 2 if is_pvc else 0
        qrs_duration_sec = 0.14 if is_pvc else 0.088
        half_qrs = qrs_duration_sec / 2.0

        center_norm = current_time / duration_sec
        width_norm = qrs_duration_sec / duration_sec
        annotations.append([class_id, center_norm, width_norm])

        dt = time - current_time

        if is_pvc:
            # Morfologia aberrante alargada de PVC (>130ms)
            signal += 1.45 * np.exp(-0.5 * ((dt / 0.030) ** 2))
            signal -= 0.70 * np.exp(-0.5 * (((dt - 0.038) / 0.026) ** 2))
            # Onda T invertida discordante
            signal -= 0.40 * np.exp(-0.5 * (((dt - 0.180) / 0.055) ** 2))
        else:
            # Onda P
            signal += 0.15 * np.exp(-0.5 * (((dt + 0.140) / 0.022) ** 2))
            # QRS estreito fisiologico (~85ms)
            signal -= 0.14 * np.exp(-0.5 * (((dt + 0.024) / 0.008) ** 2))
            signal += 1.20 * np.exp(-0.5 * ((dt / 0.014) ** 2))
            signal -= 0.28 * np.exp(-0.5 * (((dt - 0.022) / 0.010) ** 2))
            # Onda T
            signal += 0.30 * np.exp(-0.5 * (((dt - 0.200) / 0.045) ** 2))

        current_time += next_step

    # Deriva respiratoria (0.25 Hz)
    signal += 0.08 * np.sin(2 * np.pi * 0.25 * time)
    # Ruido estocastico
    signal += 0.015 * np.random.randn(total_samples)
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
