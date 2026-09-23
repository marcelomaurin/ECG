# Maurinsoft ECG Monitor (Lazarus / Free Pascal)

Aplicação desktop profissional para monitoramento, filtragem digital de sinais (DSP), detecção de complexo QRS/BPM e telemetria inteligente de eletrocardiograma (ECG), baseada no sensor analógico **AD8232** com Arduino.

Este projeto foi construído integrado à suíte de componentes do projeto **[CHATGPT](file:///D:/projetos/maurinsoft/CHATGPT)** (Maurinsoft).

---

## Recursos e Destaques

- **Interface de Monitor Hospitalar**:
  - Tela escura de alto contraste com grade milimétrica médica (1mm / 5mm).
  - Traçado suave com efeito *sweep bar* (varredura contínua sem flicker, usando double-buffer `TBitmap`).
  - Indicação visual e sonora para eletrodos desconectados (*Leads-Off*).
  - Marcador gráfico sobre cada pico R detectado.
- **Integração com a Suíte CHATGPT**:
  - **`soundfilters.pas`**:
    - `THighPassFilter` (Passa-Altas 0.5 Hz): remove a oscilação da linha de base (*baseline wander* decorrente de respiração e movimentos).
    - `TLowPassFilter` (Passa-Baixas 40 Hz): atenua ruídos de 60 Hz da rede elétrica e interferências musculares.
    - `TAverageFilter`: suavização de média móvel para estabilização de batimentos.
  - **`numps.pas`**:
    - Vetorização `TNumPS` para cálculo estatístico rápido do sinal (Média, Desvio Padrão, Amplitude Pico-a-Pico e Variabilidade RR).
  - **`funcoes.pas`**:
    - Utilitários de sistema, logs, manipulação de texto e exportação.
- **Comunicação Serial & Modo Simulação**:
  - Thread desacoplada de alta performance (`TECGAcquisitionThread`) usando `serial` do RTL Free Pascal (`rtl-extra`).
  - Suporte a 9600 e 115200 baud.
  - **Modo Simulação Embutido**: gera onda cardíaca sintética completa (P-Q-R-S-T) para testes e demonstrações imediatas, mesmo sem o circuito ligado.
- **Telemetria & IA**:
  - Geração de relatório automatizado de telemetria cardíaca.
  - Exportação completa dos dados para **CSV** e **JSON**.

---

## Estrutura dos Arquivos

- [ECGMonitor.lpi](file:///D:/projetos/maurinsoft/ECG/Lazarus/ECGMonitor.lpi) - Configuração do projeto Lazarus
- [ECGMonitor.lpr](file:///D:/projetos/maurinsoft/ECG/Lazarus/ECGMonitor.lpr) - Ponto de entrada do programa
- [main.pas](file:///D:/projetos/maurinsoft/ECG/Lazarus/main.pas) / [main.lfm](file:///D:/projetos/maurinsoft/ECG/Lazarus/main.lfm) - Formulário e interface gráfica
- [ecgdsp.pas](file:///D:/projetos/maurinsoft/ECG/Lazarus/ecgdsp.pas) - Pipeline DSP conectando `soundfilters.pas` e `numps.pas`
- [ecgserial.pas](file:///D:/projetos/maurinsoft/ECG/Lazarus/ecgserial.pas) - Thread de comunicação serial e gerador de sinal P-Q-R-S-T
- [ecgaireport.pas](file:///D:/projetos/maurinsoft/ECG/Lazarus/ecgaireport.pas) - Gerador de relatórios e exportador CSV/JSON
- [ecgtypes.pas](file:///D:/projetos/maurinsoft/ECG/Lazarus/ecgtypes.pas) - Definições de tipos e enumeração de portas COM

---

## Como Abrir e Compilar

1. Abra o Lazarus IDE.
2. Acesse `Projeto` -> `Abrir Projeto...` e selecione `D:\projetos\maurinsoft\ECG\Lazarus\ECGMonitor.lpi`.
3. Pressione `F9` (Executar).
4. Ou compile via linha de comando com `lazbuild`:
   ```cmd
   C:\lazarus\lazbuild.exe D:\projetos\maurinsoft\ECG\Lazarus\ECGMonitor.lpi
   ```
