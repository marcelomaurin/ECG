# Avaliação integrada — ECG / AD8232 / Arduino / Lazarus

Data: 7 de outubro de 2026.

## Resultado e escopo

O conjunto tem uma base aproveitável para monitoramento experimental de uma derivação a 500 Hz. Os ajustes prioritários estão tanto no aplicativo quanto no firmware: qualidade e validade dos dados, filtros, detecção de QRS, temporização e preservação da linha temporal. A aparência de um traçado suave, isoladamente, não comprova aquisição correta.

Esta avaliação combina leitura estática dos fontes, cálculo da resposta dos filtros e pesquisa em fontes primárias. Não houve alteração nos projetos ECG ou CHATGPT, compilação, aquisição física, medição elétrica ou validação do detector com bases anotadas. O modelo exato da placa, o esquema do módulo e um registro real ainda precisam ser confirmados. As considerações sobre ADC de 10 bits/5 V se aplicam ao Uno/Nano clássico com ATmega328P e referência padrão, não a toda a família Arduino.

## Problemas confirmados e ajustes

| Prioridade | Evidência no código | Consequência | Ajuste proposto |
|---|---|---|---|
| Alta | `D:\projetos\maurinsoft\ECG\Lazarus\ecgdsp.pas:66` pede 0,5 Hz; `D:\projetos\maurinsoft\CHATGPT\pacote\AI Filtros Sonoros\soundfilters.pas:247` força qualquer corte abaixo de 1 Hz para 1 Hz. | A filtragem aplicada difere da documentada e atenua mais o conteúdo lento do traçado. | Implementar filtros próprios do ECG que aceitem cortes sub-hertz ou corrigir a biblioteca compartilhada com verificação de seus outros consumidores. |
| Alta | `D:\projetos\maurinsoft\ECG\Lazarus\ecgdsp.pas:126` retorna imediatamente em leads-off sem invalidar BPM, histórico RR ou estado dos filtros. | O último BPM pode permanecer durante toda a desconexão; a reconexão reutiliza estados antigos. | Invalidar as medidas na perda do sinal; reinicializar filtros/detector na transição de reconexão e aguardar estabilização. Não resetar repetidamente a cada amostra desconectada. |
| Alta | `D:\projetos\maurinsoft\ECG\Lazarus\main.pas:951` usa o último BPM como média; na linha 952 substitui valor não positivo por 72. | O exame pode conter uma frequência que não foi medida; a suposta média também não é uma média do exame. | Salvar ausência de medida como nulo/indisponível, calcular estatística apenas dos intervalos válidos e registrar cobertura válida. |
| Alta | `D:\projetos\maurinsoft\ECG\Lazarus\ecgdsp.pas:157` detecta cruzamento positivo de limiar, inicialmente 80 unidades ADC, e marca esse instante como pico. | Pode ignorar QRS negativos ou de baixa amplitude; o instante marcado não é necessariamente o pico R. A redução do limiar por ausência de batimento só ocorre depois de já ter existido um pico. | Detector baseado em energia/derivada, estimativa adaptativa de sinal e ruído, período refratário e localização posterior do extremo do QRS no traçado. |
| Alta | `D:\projetos\maurinsoft\ECG\firmware\arduino_ad8232\ecg.ino:38` agenda no loop, e a transmissão está no mesmo ciclo. | Atrasos podem aproximar duas aquisições ou descartar períodos, sem contagem explícita. | Aquisição acionada por temporizador, preferencialmente com disparo do ADC por hardware no AVR; fila curta; transmissão no loop; contador de perdas. Nenhuma impressão serial dentro da interrupção. |
| Alta | `D:\projetos\maurinsoft\ECG\Lazarus\ecgsource.pas:191` aceita diretamente o timestamp de 32 bits do Arduino. | Após aproximadamente 71,6 minutos o relógio recebido volta a zero; o DSP pode deixar de aceitar picos enquanto o tempo não alcança o valor antigo. Reset da placa também quebra a continuidade. | Reconstruir tempo monotônico em 64 bits; distinguir overflow de reinicialização; abrir um novo segmento quando houver reset. |
| Alta | `D:\projetos\maurinsoft\ECG\Lazarus\ecgsource.pas` ignora o cabeçalho, converte campos inválidos em valores padrão e sobrescreve a amostra mais antiga quando a fila enche. | Taxa real não é validada; texto corrompido pode virar uma amostra aparentemente válida; perdas ficam invisíveis. | Validar campos e faixas, limitar tamanho da linha, rejeitar mensagens inválidas, interpretar versão/taxa, contabilizar descartes e detectar ausência de dados. |
| Média | `D:\projetos\maurinsoft\ECG\Lazarus\main.pas:783` encerra pela passagem de 10 segundos no relógio do PC. | Não garante 5.000 amostras contíguas; a mensagem de conclusão afirma uma quantidade não verificada. | Definir janela pela sequência e pelo tempo da aquisição, conferir quantidade e continuidade, sinalizar gravações incompletas. |
| Média | `D:\projetos\maurinsoft\ECG\Lazarus\main.pas:767` grava no SQLite dentro do evento da interface. | Latência de disco compete com processamento e desenho; a fila de aquisição é finita. | Gravação em worker com fila limitada e métricas de atraso; desenho em lotes. |
| Média | `D:\projetos\maurinsoft\ECG\Lazarus\main.pas:725` avança um pixel por amostra e usa ganho fixo na linha 678. | A janela temporal depende da largura da tela; a grade não está calibrada em segundos e mV. O desenho limita amplitudes às bordas, ocultando o tamanho real da excursão. | Eixo temporal explícito, ganho identificado e indicação de corte visual; para redução de pontos, preservar mínimo/máximo por coluna para não apagar QRS. |

Também é necessário verificar sucesso de `FCurrentSource.Start` antes de anunciar aquisição ativa ou iniciar um exame; atualmente `StartAcquisition` atualiza a interface sem essa confirmação.

## Filtros e detecção

Os componentes compartilhados implementam filtros de primeira ordem. Para o passa-baixas atual, com frequência configurada de 40 Hz e amostragem a 500 Hz:

- `alpha = dt / (RC + dt) = 0,334511`.
- A magnitude digital em 60 Hz é aproximadamente 0,48657: atenuação de **6,26 dB**, calculada diretamente da equação implementada.
- Isso se refere somente ao filtro digital; a atenuação total depende dos filtros analógicos do módulo, ainda não identificados.

A Analog Devices distingue uma faixa voltada à detecção de frequência cardíaca (7–25 Hz) de uma faixa de monitoramento da forma do ECG (0,5–40 Hz). Essa distinção justifica dois caminhos de processamento: um para desenhar/preservar morfologia e outro para detectar QRS. Esses valores são pontos de partida, não prova de adequação diagnóstica. [Orientação do fabricante](https://ez.analog.com/amplifiers/a/documents/do10157/filter-requirements-for-ad8232).

Proposta para este projeto:

1. Preservar ADC bruto, tempo, sequência e indicadores de validade.
2. Inicializar a linha de base a partir das primeiras amostras válidas, evitando o transiente criado pelo estado inicial zero dos filtros.
3. Para visualização, projetar a resposta digital considerando também o módulo analógico. Corrigir primeiro o corte de 0,5 Hz. Avaliar biquads de segunda ordem com resposta conhecida, sem simplesmente acumular filtros.
4. Disponibilizar rejeita-faixa estreito de 50/60 Hz selecionável e aplicá-lo quando a interferência estiver presente. Verificar atenuação, oscilação transitória e alteração do QRS; não usar filtragem para encobrir saturação ou mau contato.
5. Para QRS, avaliar uma implementação de Pan–Tompkins ou variante publicada, recalculada para 500 Hz. Não copiar coeficientes destinados a outra frequência de amostragem. A detecção e a marcação final do pico precisam considerar o atraso dos filtros. [Pan e Tompkins, 1985](https://pubmed.ncbi.nlm.nih.gov/3997178/); [variante AMPT, 2023](https://pubmed.ncbi.nlm.nih.gov/36772665/).
6. Impedir medidas durante desconexão, perda de transporte, saturação ou estabilização; preservar esses períodos como inválidos no registro.

## Hardware, referência e amplitude

O AD8232 é um condicionador analógico; resistores e capacitores do módulo determinam seu ganho e sua banda. O circuito de monitoramento apresentado no datasheet usa passa-altas de dois polos em 0,5 Hz, passa-baixas de dois polos em 40 Hz e eletrodo acionado por RLD. Isso não identifica automaticamente os componentes da placa do usuário. RLD é uma saída ativa para reduzir interferência em modo comum: não deve ser descrita simplesmente como aterramento de proteção. Três eletrodos nesse arranjo não significam três derivações adquiridas. [Datasheet AD8232, configuração de monitoramento](https://www.analog.com/media/en/technical-documentation/data-sheets/ad8232.pdf).

Na hipótese de módulo a 3,3 V, saída centralizada perto de 1,65 V e ADC com referência de 5 V:

- Centro esperado: cerca de **338 contagens**, não 512.
- Limite superior analógico próximo de 3,3 V: cerca de **676 contagens**, antes de considerar a excursão real do amplificador.
- Uma contagem representa aproximadamente 4,88 mV na entrada do ADC. Para converter em tensão equivalente nos eletrodos, ainda é necessário conhecer o ganho da cadeia.

O campo `FilteredValue := RawVal - 512` de `ecgsource.pas` é sobrescrito pelo DSP na execução principal. Portanto, a constante 512 não é a causa direta de um deslocamento permanente nesse caminho com passa-altas ativo. Entretanto, ela é um pressuposto inadequado para calibração, mensagens inválidas e caminhos sem filtragem.

Não recomendo alterar AREF antes de identificar a placa e o circuito. A referência padrão de 5 V já foi utilizada em um protótipo publicado com AD8232 e Nano; uma referência externa pode melhorar aproveitamento de escala, mas exige projeto e configuração elétrica corretos. [Estudo de fabricação e validação, 2020](https://mdpi-res.com/d_attachment/sensors/sensors-20-05962/article_deploy/sensors-20-05962-v2.pdf).

Para ensaios com eletrodos no corpo, a conexão elétrica com o computador também faz parte do sistema: a SparkFun recomenda alimentação por bateria. Isso não equivale a uma certificação de segurança do conjunto. Os testes iniciais de precisão podem ser feitos com simulador de ECG. [Orientação da SparkFun](https://www.sparkfun.com/sparkfun-single-lead-heart-rate-monitor-ad8232.html).

## Firmware e protocolo propostos

Manter inicialmente 500 Hz e o formato v2 evita uma migração desnecessária enquanto os erros de software são corrigidos. A carga máxima do formato atual é 19 bytes por amostra, incluindo CR/LF; em 8N1, são 95.000 bits/s para 500 amostras/s, aproximadamente 82,5% da taxa nominal de 115200 bps.

Para robustez posterior, proponho uma versão explícita do protocolo com sequência, identificação da sessão, taxa, resolução do ADC, referência configurada e contadores de perda. É preciso recalcular a vazão antes de acrescentar campos: não há grande margem no CSV atual. Pacotes binários em blocos são uma opção; aumentar baud depende de validar erro de clock e o conversor USB/serial específico.

Não acrescentar uma quarta coluna silenciosamente: o leitor atual compara todo o restante após a segunda vírgula com `1`, e isso quebraria a interpretação de leads-off. Atualizar firmware e parser juntos, preservando suporte ao v2 quando necessário. Interrupções e buffer devem respeitar a pouca RAM do ATmega328P.

## Integridade da análise posterior

`D:\projetos\maurinsoft\ECG\Lazarus\ecgyolo.pas` implementa regras morfológicas para classes N/S/V, com pontuações calculadas por fórmulas. O caminho principal chama esse detector; não é inferência de uma rede YOLO treinada. A análise não deve apresentar essas pontuações como probabilidades calibradas de diagnóstico.

O carregamento do exame em `D:\projetos\maurinsoft\ECG\Lazarus\ecgdatabase.pas:312` recupera somente valores filtrados, perdendo tempo e flags de validade no caminho de análise. Em Python, `D:\projetos\maurinsoft\ECG\ai\yolo1d\predict.py` também lê apenas o sinal, ordena pelo timestamp e completa janelas curtas com zeros. É necessário carregar a linha temporal e a máscara de validade, rejeitando ou segmentando lacunas em vez de tratá-las como ECG contínuo.

Há um arquivo de pesos no repositório. Sua presença não comprova treinamento ou desempenho. O carregador Python pode continuar mesmo se a leitura dos pesos falhar; deve informar falha explicitamente. Avaliar classificação é uma etapa posterior à confiabilidade da aquisição.

## Referências e aplicação prática

| Referência | O que contribui | Limitação para este projeto |
|---|---|---|
| [SparkFun — AD8232 Heart Rate Monitor, hardware e exemplo](https://github.com/sparkfun/AD8232_Heart_Rate_Monitor) | Projeto aberto com o mesmo front-end; referência para pinagem, esquema e leads-off. | O exemplo é uma demonstração de leitura e transmissão, não validação da regularidade a 500 Hz. |
| [How2Electronics — AD8232 e Arduino](https://how2electronics.com/ecg-monitoring-with-ad8232-ecg-sensor-arduino/) | É a referência citada no README; mostra A0, pinos 10/11 e visualização. | Usa 9600 baud e `delay(1)`; esse atraso não estabelece sozinho a frequência real. Não copiar esse agendamento para o pipeline atual. |
| [Fabricating a Portable ECG Device Using AD823X Analog Front-End Microchips and Open-Source Development Validation — Sensors, 2020, 20, 5962](https://mdpi-res.com/d_attachment/sensors/sensors-20-05962/article_deploy/sensors-20-05962-v2.pdf) | Estudo com AD8232 e Arduino Nano; verifica gravações a 360/500 Hz e emprega buffer duplo para absorver latência da memória. Fundamenta medir perda de amostras. | Resultados pertencem ao protótipo estudado; não validam automaticamente este circuito/aplicativo. |
| [AD8232 to Biopotentials Sensors: Open Source Project and Benchmark — Electronics, 2023, 12, 833](https://www.mdpi.com/2079-9292/12/4/833) | Mostra como o mesmo CI é configurado para diferentes biopotenciais e filtros; reforça identificar a topologia do módulo. | Não se deve assumir que módulos comerciais ou clones reproduzem o circuito do artigo. |
| [Pan e Tompkins — A real-time QRS detection algorithm, 1985](https://pubmed.ncbi.nlm.nih.gov/3997178/) | Referência clássica para substituir o simples cruzamento de limiar por detector de QRS estruturado. | Exige implementação, adaptação da taxa e avaliação própria. |
| [Algorithm for Mobile Platform-Based Real-Time QRS Detection — AMPT, 2023](https://pubmed.ncbi.nlm.nih.gov/36772665/) | Variante publicada avaliada em bases públicas e voltada a execução eficiente. | Não elimina a necessidade de testar sinal ruim, polaridade e morfologias distintas. |
| [PhysioNet — MIT-BIH Noise Stress Test Database](https://physionet.org/content/nstdb/1.0.0/) | Ruídos de linha de base, atividade muscular e movimento de eletrodo, com registros anotados para avaliar detecção. | Valida o algoritmo em dados de referência; não substitui ensaio elétrico do hardware. |

Algumas páginas de artigos limitaram o acesso automatizado ao texto integral. O estudo de 2020 foi consultado pelo PDF do editor; para o artigo de 2023 sobre biopotenciais foram usados trechos indexados da página do editor. Não foram extrapoladas métricas clínicas para o projeto.

## Ordem de execução e critérios de verificação

1. **Validade dos dados:** corrigir leads-off, timeout serial, BPM fictício, parser e contagem de perdas. Verificar desconexão/reconexão, linhas inválidas e falha de abertura da porta; nenhuma dessas condições deve produzir medida válida inventada.
2. **DSP e visualização:** corrigir corte sub-hertz, inicialização, escalas e detector. Medir resposta com senóides conhecidas e testar traçados sintéticos com diferentes amplitudes, polaridades e ruído de rede. Separar ganho visual de amplitude armazenada.
3. **Temporização do firmware:** implementar temporizador/ADC e buffer; medir distribuição dos intervalos com instrumento ou timestamps. Ensaio contínuo de pelo menos 90 minutos para atravessar o overflow, além de teste explícito de reset. Espera-se contagem consistente e toda perda identificada.
4. **Gravação:** para uma janela íntegra de 10 segundos a 500 Hz, obter 5.000 amostras consecutivas e equivalência entre aquisição e SQLite. Se houver lacuna, sinalizar incompletude; não prometer contiguidade baseada apenas no relógio do PC.
5. **Validação do detector:** usar MIT-BIH e NSTDB, documentando reamostragem, transformação das anotações, sensibilidade, valor preditivo positivo, erro temporal dos picos e resultados por tipo de ruído. Se houver treino de modelo, separar pacientes entre treino e avaliação.
6. **Bancada:** confirmar placa, referência ADC, alimentação, ganho/banda do módulo, polaridade, saturação e funcionamento do leads-off com um sinal conhecido. Só então atribuir um problema remanescente ao contato dos eletrodos ou ao sinal real.

Recomendação: começar pelas correções de validade e DSP no aplicativo. Elas independem de trocar hardware e evitam que o software apresente como confiável um sinal ausente, corrompido ou mal processado.
