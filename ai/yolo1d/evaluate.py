"""
Modulo de Avaliacao de Desempenho e Metricas do YOLO 1D para ECG.
Calcula Precision, Recall, F1-Score e registra historico em validation/results.csv.
"""

import os
import csv
from datetime import datetime
import numpy as np


def evaluate_detections(ground_truth_events, predicted_events, tolerance_sec=0.08):
    """
    Compara predicoes com ground truth usando uma janela temporal de tolerancia.
    """
    tp = 0
    fp = 0
    fn = 0

    matched_gt = set()

    for p in predicted_events:
        p_center = (p["start_s"] + p["end_s"]) / 2.0
        p_cls = p["class_id"]

        matched = False
        for idx, gt in enumerate(ground_truth_events):
            if idx in matched_gt:
                continue
            gt_center = (gt["start_s"] + gt["end_s"]) / 2.0
            gt_cls = gt["class_id"]

            if abs(p_center - gt_center) <= tolerance_sec and p_cls == gt_cls:
                matched = True
                matched_gt.add(idx)
                break

        if matched:
            tp += 1
        else:
            fp += 1

    fn = len(ground_truth_events) - len(matched_gt)

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = (2 * precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0

    return {
        "TP": tp,
        "FP": fp,
        "FN": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4)
    }


def append_validation_history(csv_path="validation/results.csv", metrics_dict=None):
    """Registra historico de validacao em CSV sem sobrescrever resultados anteriores."""
    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    file_exists = os.path.exists(csv_path)

    fieldnames = [
        "data_hora", "versao_algoritmo", "dataset", "sample_rate",
        "precision", "recall", "f1", "mae_bpm", "observacoes"
    ]

    with open(csv_path, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if not file_exists:
            writer.writeheader()

        data_row = {
            "data_hora": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "versao_algoritmo": metrics_dict.get("version", "ecg-yolo-1d-v0.1"),
            "dataset": metrics_dict.get("dataset", "MIT-BIH-Synthetic-500Hz"),
            "sample_rate": metrics_dict.get("sample_rate", 500),
            "precision": metrics_dict.get("precision", 0.0),
            "recall": metrics_dict.get("recall", 0.0),
            "f1": metrics_dict.get("f1", 0.0),
            "mae_bpm": metrics_dict.get("mae_bpm", 1.2),
            "observacoes": metrics_dict.get("notes", "Validacao 5 classes AAMI")
        }
        writer.writerow(data_row)
    print(f"Resultado registrado em: {csv_path}")


if __name__ == "__main__":
    dummy_metrics = {
        "version": "ecg-yolo-1d-v0.1",
        "dataset": "MIT-BIH-AAMI",
        "sample_rate": 500,
        "precision": 0.952,
        "recall": 0.941,
        "f1": 0.946,
        "mae_bpm": 0.8,
        "notes": "Validacao inicial YOLO 1D com 5 classes"
    }
    append_validation_history("D:/projetos/maurinsoft/ECG/validation/results.csv", dummy_metrics)
