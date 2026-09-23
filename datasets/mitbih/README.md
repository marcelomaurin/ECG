# Dataset MIT-BIH Arrhythmia Database

O **MIT-BIH Arrhythmia Database** contém 48 registros de eletrocardiograma de duas derivações, com 30 minutos de duração cada, amostrados a 360 Hz e anotados por cardiologistas.

---

## Mapeamento de Classes (Padrão AAMI / YOLO 1D)

| Código | Descrição AAMI | Classes Originais MIT-BIH |
| :---: | :--- | :--- |
| **N** | Batimento Normal / Não ectópico | N, L, R, e, j |
| **S** | Ectopia Supraventricular | A, a, J, S |
| **V** | Ectopia Ventricular (PVC) | V, E |
| **F** | Batimento de Fusão | F |
| **Q** | Desconhecido / Não classificável | /, f, Q |

---

## Download dos Dados

1. Instale o pacote `wfdb`:
   ```bash
   pip install wfdb
   ```
2. Baixe os registros públicos diretamente do PhysioNet:
   ```python
   import wfdb
   wfdb.dl_database("mitdb", "datasets/mitbih")
   ```
3. O script de preparação `ai/yolo1d/dataset.py` faz o reamostramento de 360 Hz para 500 Hz (padrão do AD8232) e gera janelas de 10 segundos (5000 amostras) com anotações de início, fim e classe.
