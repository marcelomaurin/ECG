# ECG - Monitoramento Cardíaco, Simulação Didática e Análise com YOLO 1D

Projeto de monitoramento de eletrocardiograma (ECG) de 1 canal utilizando o sensor analógico **AD8232**, **Arduino** a **500 Hz**, gravação em **SQLite**, aplicativo desktop profissional em **Lazarus / Free Pascal** estruturado em **3 etapas de fluxo de trabalho**, e classificação de arritmias com **YOLO 1D temporal**.

O software implementa **dois modos de aquisição claramente separados** através da interface unificada `IECGSource`, garantindo que todo o pipeline a jusante (filtros DSP, detecção de QRS, gravação SQLite, visualização e inteligência artificial) processe os sinais de forma idêntica e agnóstica à origem física dos dados.

---

## Arquitetura Geral

```text
                           ECG ANALYZER
                                │
                       ┌────────┴────────┐
                       │                 │
                 MODO REAL          MODO SIMULAÇÃO
                       │                 │
                Porta serial       Gerador de ECG (Gaussianas)
                  AD8232                 │
                       │          ┌──────┴───────┐
                       │          │              │
                       │       NORMAL         ANORMAL
                       │                         │
                       │                 5 padrões patológicos
                       │                         │
                       └────────────┬────────────┘
                                    │
                              Buffer de ECG
                                    │
                               Filtros DSP
                                    │
                           Detecção de QRS
                                    │
                             BPM / RR / IA
                                    │
                           Gráfico e Relatório
```

---

## As 3 Etapas do Aplicativo Desktop (Lazarus)

1. **Etapa 1 — Colocação do Equipamento:**
   - Guia ilustrado do posicionamento dos 3 eletrodos no tórax (Triângulo de Einthoven derivado):
     - **RA (Vermelho):** Abaixo da clavícula direita.
     - **LA (Amarelo):** Abaixo da clavícula esquerda.
     - **RL (Verde):** Crista ilíaca direita ou abdômen inferior (Terra de referência).
   - Checklist de preparação do paciente (limpeza da pele, eliminação de interferência de rede).

2. **Etapa 2 — Leitura, Monitoramento e Registro (SQLite):**
   - **Dois Modos de Operação:**
     - **Dispositivo / Serial:** Conexão com Arduino AD8232 a 115200 baud, detecção de Leads-Off (LO+/LO-).
     - **Simulação Didática:** Síntese contínua a 500 Hz baseada em curvas gaussianas (ondas P, Q, R, S, T), ruído estocástico, baseline drift respiratório (0.25 Hz) e interferência de 60 Hz.
     - **Faixa de Alerta:** Exibição destacada `MODO DE SIMULAÇÃO ATIVO - NÃO REPRESENTA UM PACIENTE`.
     - **Painel Ground Truth:** Comparação em tempo real entre o ritmo sintético gerado e o detectado.
     - **Gravação em SQLite:** Gravação automatizada de janelas de 10 segundos (5000 amostras a 500 Hz) na base `ecg_records.db`.
     - **Gerador de Datasets:** Exportação em lote de amostras sintéticas anotadas (`datasets/synthetic/`) em formatos CSV e JSON.

3. **Etapa 3 — Análise do Sinal e Arritmias com YOLO 1D:**
   - Exibição de **Bounding Boxes Temporais 1D** delimitando cada batimento cardíaco e evento patológico diretamente no traçado contínuo.
   - Classificação conforme o padrão AAMI EC57 em 5 classes:
     - **N (Normal):** Batimentos sinusais normais.
     - **S (Supraventricular / PAC):** Batimentos prematuros atriais.
     - **V (Ventricular / PVC):** Extrassístoles ventriculares (QRS largo, aberrante e pausa compensatória).
     - **F (Fusão):** Batimentos de fusão ventricular.
     - **Q (Não classificado / Ruído):** Ritmos indeterminados e artefatos.
   - Grade detalhada com `ID`, `Início (s)`, `Fim (s)`, `Duração (ms)`, `Classe`, `Classificação` e `Confiança`.
   - Cálculo automático da **Carga Arrítmica (%)** e exportação do laudo em CSV/JSON.
   - Suporte a inferência nativa em Pascal e integração com modelo PyTorch (`ai/yolo1d/predict.py`).

---

## Os 6 Ritmos do Simulador Didático

| Ritmo | Código Ground Truth | Características Eletrocardiográficas Simuladas |
|---|---|---|
| **Ritmo Normal** | `N` | Onda P positiva (160ms PR), QRS estreito (90ms), onda T arredondada, 72 BPM |
| **Fibrilação Atrial** | `AFIB` | Ausência de onda P organizada, linha de base oscilatória, intervalos RR caóticos (420–1100ms) |
| **Extrassístole Ventricular** | `PVC` | Batimento prematuro com QRS alargado (>120ms), morfologia aberrante e pausa compensatória |
| **Extrassístole Atrial** | `PAC` | Batimento atrial precoce com P prematura/deformada, QRS estreito e intervalo RR encurtado |
| **Taquicardia Sinusal** | `TACHY` | Ritmo sinusal acelerado (100–160 BPM, padrão 130 BPM), intervalos RR reduzidos |
| **Bradicardia Sinusal** | `BRADY` | Ritmo sinusal lentificado (40–55 BPM, padrão 48 BPM), intervalos RR alargados |

---

## Estrutura do Repositório

```text
.
├── firmware/
│   └── arduino_ad8232/
│       └── ecg.ino             # Firmware Arduino a 500 Hz e 115200 bps (sem delay)
├── desktop/
│   └── processing/
│       └── pc.pde              # Aplicação legado em Processing (115200 bps, protocolo v2)
├── Lazarus/                    # Aplicação Desktop Profissional em Lazarus / Free Pascal
│   ├── ECGMonitor.lpi          # Projeto Lazarus
│   ├── ECGMonitor.lpr          # Programa principal
│   ├── main.pas / main.lfm     # Interface com 3 etapas, dual source e visualizador YOLO 1D
│   ├── ecgsource.pas           # Interface IECGSource, TSerialECGSource e TECGSample
│   ├── ecgsimulator.pas        # Simulador TSimulatedECGSource com curvas gaussianas
│   ├── ecgsyntheticdataset.pas # Gerador de lotes sintéticos em CSV e JSON
│   ├── ecgdatabase.pas         # Banco SQLite (tabelas exames, amostras e eventos_yolo)
│   ├── ecgyolo.pas             # Detector temporal 1D e renderizador de Bounding Boxes
│   ├── ecgdsp.pas              # DSP com filtros da suíte CHATGPT (soundfilters / numps)
│   ├── ecgtypes.pas            # Estruturas e registros compartilhados
│   ├── ecgserial.pas           # Thread serial de suporte
│   ├── ecgaireport.pas         # Relatório e exportador CSV/JSON
│   └── sqlite3.dll             # Driver SQLite para Windows
├── ai/
│   └── yolo1d/
│       ├── model.py            # Arquitetura PyTorch ECGYOLO1D (Conv1D + FPN 1D + YOLOHead 1D)
│       ├── dataset.py          # Loader de dados e janelas de 10s (5000 amostras)
│       ├── predict.py          # Script de inferência em lote ou via SQLite
│       ├── train.py            # Script de treinamento com perda CIoU e Cross-Entropy
│       ├── evaluate.py         # Métricas de validação (Precision, Recall, F1)
│       └── config.yaml         # Configuração de classes e hiperparâmetros
├── datasets/
│   ├── synthetic/              # Amostras sintéticas em CSV e JSON com metadados de simulação
│   └── mitbih/                 # Instruções e mapeador para banco MIT-BIH Arrhythmia
├── docs/
│   ├── HARDWARE.md             # Guia completo de pinagem, ligações e segurança elétrica
│   └── img/
│       └── eletrodos_3pontos.jpg # Imagem do guia de colocação dos eletrodos
├── hardware/                   # Esquemas e modelos de circuito
├── signal_processing/          # Módulos de processamento digital de sinais
└── tests/                      # Scripts e casos de teste
```

---

## Especificações da Aquisição (Protocolo v2)

- **Frequência de Amostragem:** `500 Hz` (intervalo de `2000 µs` temporizado via `micros()`, sem `delay()`)
- **Velocidade Serial:** `115200 bps` (8N1)
- **Formato das Mensagens:**
  - Inicialização: `#ECG,VERSION=2,SAMPLE_RATE=500`
  - Amostras contínuas:
    ```text
    timestamp_us,adc,lead_off
    ```
    - `timestamp_us`: carimbo de tempo em microssegundos (`micros()`)
    - `adc`: leitura analógica de 10 bits (`0 a 1023`)
    - `lead_off`: `1` se algum eletrodo estiver desconectado e `0` se o contato estiver adequado.

Para detalhes completos de conexões elétricas e posicionamento de eletrodos, veja [docs/HARDWARE.md](docs/HARDWARE.md).

---

## Compilação do Aplicativo Lazarus

Para compilar o aplicativo de desktop:

```bash
cd Lazarus
C:\lazarus\lazbuild.exe --build-all ECGMonitor.lpi
```

O binário gerado estará localizado em `Lazarus/ECGMonitor.exe`.

---

## Execução da Inteligência Artificial (YOLO 1D)

Para executar a inferência sobre as amostras gravadas no SQLite pelo aplicativo:

```bash
python ai/yolo1d/predict.py --db Lazarus/ecg_records.db --exam 1 --out Lazarus/yolo_out.json
```

Para avaliar o modelo com métricas completas de sensibilidade e especificidade:

```bash
python ai/yolo1d/evaluate.py
```

---

# Portuguese
## Agradecimentos

Este trabalho é baseado no trabalho:
https://how2electronics.com/ecg-monitoring-with-ad8232-ecg-sensor-arduino/

Gostaria de agradecer imensamente ao colega, que muito contribuiu com seu material:
https://how2electronics.com/ecg-monitoring-with-ad8232-ecg-sensor-arduino/

Meu artigo sobre ECG:
https://maurinsoft.com.br/wp/leitor-ecg/

---

# English 
## ECG

## Special Thanks
This work is based on the work:
https://how2electronics.com/ecg-monitoring-with-ad8232-ecg-sensor-arduino/

I would like to thank my colleague immensely, who contributed a lot with his material:
https://how2electronics.com/ecg-monitoring-with-ad8232-ecg-sensor-arduino/

My article about ECG:
https://maurinsoft.com.br/wp/leitor-ecg/
