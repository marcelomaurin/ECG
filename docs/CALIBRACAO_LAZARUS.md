# Calibracao automatica do ECG serial legado

Ao iniciar uma conexao real, o Lazarus conserva o baud escolhido (padrao 9600, 8N1). Nao envia comandos nem modifica o firmware. Linhas ADC inteiras de 0 a 1023 sao as unicas amostras contadas; comentarios, linhas vazias e mensagens invalidas nao entram na estimativa.

## Medicao

- O worker serial usa GetTickCount64 (monotonico de 64 bits, em ms), independentemente do timer da interface.
- Descarta o primeiro lote e aguarda 1 segundo de fluxo para esvaziar buffers iniciais.
- Conta frames completos por janela de aproximadamente 8 segundos: Fs = N * 1000 / tempo_decorrido_ms. A fronteira fica no lote recebido, sem repartir artificialmente um burst. Com intervalos aceitos de ate 1 segundo, a janela termina entre 8 e 9 segundos.
- Compara as taxas das duas metades (tolerancia de 10%). A contagem usa lotes inteiros, sem interpretar intervalos entre leituras como intervalos entre conversoes.
- O primeiro lote que estabelece a fronteira e o lote que encerra a calibracao nao sao enviados ao DSP. A interface mostra o progresso e, ao concluir, a taxa efetiva estimada.
- Repete a verificacao em janelas de 8 segundos. Variacao acima de 10%, frames invalidos, reinicio do protocolo ou silencio superior a 1 segundo suspendem o processamento e iniciam nova calibracao. Nao altera coeficientes continuamente por pequenas flutuacoes.
- Um `!` suspende a calibracao e limpa a fila. A contagem recomeca somente com dados ADC conectados, porque mensagens `!` mais curtas podem produzir outra taxa de chegada.
- Taxas abaixo de 125 Hz sao informadas, mas nao liberam o processamento: os filtros existentes incluem notch de 60 Hz e exigem esse minimo.

Sem timestamps no firmware, esta e uma estimativa da taxa media de chegada serial, dependente do tamanho textual dos valores ADC. Nao recupera os instantes exatos das conversoes nem consegue identificar toda perda silenciosa de dados.

## DSP e tempo

Cada amostra publicada carrega a taxa medida. A interface recria os filtros passa-altas 0,5 Hz, passa-baixas 40 Hz e notch opcional 60 Hz antes de processar o primeiro lote daquela taxa. Uma descontinuidade reinicia o DSP e seu periodo de estabilizacao de 2 segundos; BPM e gravacao nao usam amostras de calibracao.

O receptor gera timestamps uniformes por indice de amostra, com arredondamento apenas no timestamp final. Assim, um burst nao cria timestamps duplicados e taxas fracionarias nao acumulam erro por arredondamento do periodo.

O grafico ao vivo usa timestamps a 250 pixels/s (quadrado principal de 50 pixels = 200 ms). A gravacao guarda a taxa fracionaria no SQLite, e a analise nativa Lazarus e a exportacao usam a taxa do exame. A afinidade INTEGER dos bancos antigos SQLite tambem aceita valores REAL, sem arredondamento.

O modelo Python atual exige entrada de 500 Hz: a interface impede essa analise em exames de outra taxa, com orientacao para o detector Lazarus. Nao realiza reamostragem implicita para o modelo.

O simulador continua em 500 Hz. Protocolos anunciados v2/v3 preservam seus timestamps e taxa de 500 Hz.

## Validacao reproduzivel

Compile e execute `tests/test_ecg_calibration.pas`, `tests/test_ecg_acquisition.pas` e `tests/test_ecg_simulator.pas` com o Free Pascal. Inclua no caminho de units a pasta `Lazarus`, os componentes `AI Filtros Sonoros` e `AI Math` do projeto CHATGPT, e as units compiladas de LCL e LazUtils da mesma arquitetura.

O teste de aquisicao aceita um caminho de banco temporario como primeiro argumento para verificar SQLite e a persistencia da taxa fracionaria de 187,5 Hz. A DLL SQLite deve corresponder a arquitetura do executavel. O teste de simulador aceita um diretorio temporario para os datasets.

A suite de calibracao injeta bytes e tempos monotonicos no mesmo metodo ReceiveBytes utilizado pelo worker real. Cobre bursts, backlog inicial, fragmentacao/CRLF, ADC invalido, leads-off, silencio, instabilidade, recuperacao com outra taxa, taxa fracionaria, rollover de 32 bits, protocolos v3 e resposta do DSP/BPM.

Teste fisico pendente: conectar Arduino legado/AD8232 em 9600, observar a estimativa, retirar/recolocar eletrodos e reconectar a porta. Confirmar o tempo do tracado e a frequencia contra uma referencia conhecida.
