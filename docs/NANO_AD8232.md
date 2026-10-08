# Nano clássico + AD8232 — aquisição e simulação

Atualizado em 08/10/2026. Alvo: Arduino Nano clássico, ATmega328P, 16 MHz, lógica de 5 V. Não é o firmware do Nano Every, Nano 33 ou ESP32.

## Ligações

| AD8232 | Arduino Nano | Função |
|---|---|---|
| 3.3V / +VS | 3V3 | Alimentação do módulo; **não ligar a 5V** |
| GND | GND | Referência comum |
| OUTPUT / OUT | A0 | ECG analógico |
| LO+ | D10 | Detecção de eletrodo desconectado |
| LO− | D11 | Detecção de eletrodo desconectado |
| SDN | 3V3 | Mantém o AD8232 ligado; não deixar flutuante |

AREF permanece sem ligação externa: a referência do ADC é AVCC, nominalmente 5 V. A saída central do módulo, aproximadamente 1,65 V, resulta em cerca de 338 contagens, não 512. O software mede o nível inicial e remove a componente contínua; não assume que o sinal real esteja centrado em 512.

O desenho `nano-ad8232-pinos.svg` representa conexões lógicas, não a posição física dos terminais. Confira os nomes impressos no seu módulo. Timer1 é reservado; não utilizar Servo ou PWM de Timer1 simultaneamente. D10 continua como entrada, com a saída OC1B desconectada.

Eletrodos: RA e LA são as entradas diferenciais; RL é o eletrodo conduzido pelo circuito RLD, não aterramento de proteção. Para uma configuração semelhante à derivação II, RA fica na região superior direita do tórax e LA na inferior esquerda; RL na inferior direita. Identifique RA/LA/RL pelo cabo/módulo: cores podem variar. Use simulador elétrico para os primeiros testes. Ao conectar eletrodos a uma pessoa, utilize alimentação isolada apropriada; USB de computador ligado à rede não fornece isolamento médico. Este conjunto é experimental.

## Gravar o firmware

1. Abra `firmware/arduino_ad8232/arduino_ad8232.ino` na Arduino IDE. O arquivo `ecg.ino` na mesma pasta é apenas uma nota de compatibilidade, sem funções duplicadas.
2. Selecione **Arduino Nano**, **ATmega328P**, a porta COM e envie. Clones antigos podem exigir **ATmega328P (Old Bootloader)**. O programa compilado é o mesmo; muda o procedimento de upload.
3. Feche o Monitor Serial antes de conectar o ECGMonitor. Selecione **115200 baud** na aplicação.
4. Verifique o traçado e espere dois segundos de dados contínuos antes de iniciar uma gravação.

Nenhum upload foi executado automaticamente. O arquivo HEX fornecido contém somente a aplicação, sem bootloader. Compilação verificada com Arduino AVR Core 1.8.6 e avr-gcc 7.3.0: 5.162 bytes de programa e 716 bytes estáticos de RAM.

## Aquisição

Timer1 dispara o ADC a cada 2 ms (500 Hz nominal, dependente da tolerância do oscilador). ADC de 10 bits a 125 kHz. A primeira conversão de inicialização é descartada. Uma fila com 63 posições úteis desacopla aquisição e transmissão; estouros incrementam o contador de perdas. O Nano envia amostras brutas, sem filtros digitais.

Serial 115200, 8N1, protocolo v3:

```text
#START
#ECG,VERSION=3,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000
0,338,0
1,340,0
#STAT,DROPPED=0
```

Cada linha de dados é `sequencia,adc,lead_off`. Sequência de 32 bits incrementada em toda conversão, inclusive quando uma amostra se perde na fila. `lead_off=1` significa LO+ ou LO− ativo. Cabeçalho/estatística reaparecem a cada cinco segundos; `?` solicita uma atualização. O LED interno acende quando o firmware detecta eletrodo solto.

O software reconstrói tempo de 64 bits a partir da sequência, trata sua volta a zero, rejeita valores e linhas inválidas e marca descontinuidades. `#START` indica reinicialização da placa. Continua aceitando o protocolo v2 anterior, explicitamente identificado pelo cabeçalho, incluindo a volta de `micros()` a zero. Não aceita linhas avulsas do Serial Plotter como se fossem esse protocolo. Firmware antigo v2 pode exigir reiniciar a placa para reenviar seu cabeçalho.

`VREF_MV=5000` é nominal, não uma calibração. O gráfico e os arquivos continuam em contagens de ADC. Converter para milivolts na pele exige medir AVCC e conhecer o ganho e os componentes do módulo.

## Filtros e qualidade

Fluxo: ADC bruto → remoção do nível inicial → passa-altas Butterworth de segunda ordem a **0,5 Hz** → passa-baixas Butterworth de segunda ordem a **40 Hz** → notch de **60 Hz**, Q=30, somente se habilitado.

O notch inicia desligado e pode ser ativado na configuração do hardware quando houver interferência de rede. O passa-baixas reduz frequências altas, mas não substitui o notch. Os filtros analógicos do AD8232 também influenciam o traçado; filtros digitais não recuperam componentes já eliminadas pelo módulo, nem corrigem aliasing já adquirido.

Essa faixa é destinada à visualização e estudo de ritmo, não à preservação integral de ECG diagnóstico, segmento ST ou avaliação de marcapasso. A filtragem causal também modifica fase e morfologia. O banco guarda tanto ADC bruto quanto sinal filtrado.

BPM é uma estimativa por limiar adaptativo, com período refratário e média, não um diagnóstico de arritmia. É limpo durante eletrodo solto, lacunas, saturação do ADC e ausência de dados. Há dois segundos de estabilização após reinício dos filtros. Gravações com falhas preservam seus dados, mas não são entregues à análise como uma sequência contínua válida. Novas colunas `signal_invalid` e `discontinuity` registram isso; registros antigos são preservados e identificados como sem avaliação de qualidade.

## Os dez ritmos

| Seleção | Configuração padrão e características verificadas |
|---|---|
| Sinusal normal | 72 bpm, sequência P–QRS–T, pequena variação respiratória de RR |
| Bradicardia sinusal | 48 bpm, P–QRS–T preservado, RR longo |
| Taquicardia sinusal | 130 bpm, P–QRS–T e intervalos encurtados |
| Fibrilação atrial | RR irregular, ausência de P sinusal, atividade fibrilatória |
| Flutter atrial | 300 ondas atriais/min, condução 4:1, ventrículos a 75 bpm |
| Taquicardia supraventricular | Exemplo regular a 180 bpm, QRS estreito, P não visível |
| Extrassístole atrial | Batimento precoce, P diferente, QRS estreito e pausa incompleta |
| Extrassístole ventricular | Batimento precoce largo, sem P associada, T discordante e pausa compensatória completa |
| Taquicardia ventricular | Exemplo monomórfico regular a 180 bpm, complexos largos |
| Fibrilação ventricular | Atividade desorganizada, sem QRS organizado ou indicação de BPM |

São modelos didáticos de uma derivação, gerados por componentes gaussianas, programação dos intervalos e atividade oscilatória. Não são uma implementação das equações diferenciais ECGSYN nem uma reprodução clinicamente validada de cada arritmia. A imagem de referência não fornece escala e medidas suficientes para reconstrução exata. Flutter variável, TV polimórfica, variantes de TSV e todas as morfologias possíveis não estão representados. Larguras gaussianas são parâmetros do modelo, não medidas clínicas certificadas de QRS.

Os controles permitem estudar variações de forma; restaurar/selecionar o preset repõe a morfologia de referência. P sinusal não é acrescentada a FA, flutter ou TSV pelo controle de amplitude. A classe do ritmo é separada da classe do batimento. O classificador existente não foi treinado novamente. A análise nativa que não suporta os novos ritmos é identificada como não implementada. A análise complementar em Python já presente no projeto foi preservada; suas regras heurísticas não foram clinicamente validadas por estes testes.

## Verificações e limites

- Compilação do firmware para ATmega328P e da aplicação Lazarus/Windows.
- Parser: campos, limites, linhas extensas, perdas, duplicação, reset, protocolos v2/v3 e volta dos contadores a zero.
- Resposta medida dos filtros: corte em 0,5 e 40 Hz, rejeição de 60 Hz; sinal constante não cria pico de inicialização.
- BPM de referência e limpeza após falhas; persistência e bloqueio de análise de gravação inválida.
- 15.000 amostras por ritmo, intervalos, pausas, largura relativa, flutter 4:1, ausência de QRS em FV, semente reproduzível, mudanças de ritmo e exportação de dez classes.
- Teste automatizado da interface alternando os dez presets.

Não foi medido sinal físico do seu Nano/AD8232 nem validado desempenho clínico. Próxima verificação de bancada: frequência real de amostragem, níveis de tensão, perdas, LO+/LO−, ruído e ganho do módulo específico, usando uma fonte de ECG de referência.

## Referências

- [Arduino Nano: mapa oficial de pinos](https://docs.arduino.cc/resources/pinouts/A000005-full-pinout.pdf).
- [Analog Devices: datasheet AD8232](https://www.analog.com/media/en/technical-documentation/data-sheets/ad8232.pdf), alimentação, SDN, RLD e circuitos de condicionamento.
- [Microchip: ATmega328P](https://ww1.microchip.com/downloads/aemDocuments/documents/MCU08/ProductDocuments/DataSheets/Atmel-7810-Automotive-Microcontrollers-ATmega328P_Datasheet.pdf), ADC auto-trigger e Timer1.
- [SparkFun: projeto aberto AD8232](https://github.com/sparkfun/AD8232_Heart_Rate_Monitor), hardware e exemplo de leitura.
- [McSharry et al., IEEE TBME 2003 — ECGSYN](https://physionet.org/files/ecgsyn/1.0.0/paper/index.shtml): referência para separar morfologia e dinâmica RR; não é o algoritmo implementado aqui.
- [Modelo de ondas gaussianas](https://pmc.ncbi.nlm.nih.gov/articles/PMC3148951/): referência de modelagem sintética, sem equivalência de validação com este código.
- [AHA/ACC/HRS — diretriz de fibrilação atrial](https://pmc.ncbi.nlm.nih.gov/articles/PMC4676081/): características de FA/flutter.
- [Estudo sobre FA, flutter e taquicardia atrial no ECG](https://pmc.ncbi.nlm.nih.gov/articles/PMC6261787/): limites da distinção por regularidade e atividade atrial.

O endereço Maurinsoft indicado pelo usuário não pôde ser consultado com sucesso nesta sessão; nenhum trecho ou circuito específico desse artigo foi presumido.
