# Revisão da comunicação Nano ↔ ECGMonitor

**Conclusão:** o firmware v3 e o leitor serial são compatíveis durante aquisição contínua a 115200 baud. A recuperação de falhas ainda precisa de ajustes. Revisão em 08/10/2026; não houve comunicação com uma placa física nesta análise, nem alteração dos fontes do projeto.

## Achados

### 1. Reinício sem a mensagem `#START` pode interromper a recepção por muito tempo — prioridade alta

Em `D:/projetos/maurinsoft/ECG/Lazarus/ecgprotocol.pas`, linhas 35–42 e 58, somente `#START` reinicializa o estado da sequência. Cabeçalhos periódicos confirmam a versão, mas mantêm o contador anterior. Uma sequência menor é descartada, exceto no caso de volta de 32 bits.

Reprodução no parser real: receber sequência 300000; reiniciar o Nano e perder a linha `#START`; receber o cabeçalho válido e as sequências 0 a 2999. **Resultado: zero das 3000 novas amostras foi aceita**, mesmo repetindo o cabeçalho. Nesse exemplo, a recepção só voltaria quando o contador ultrapassasse 300000, cerca de dez minutos depois, ou quando a aplicação recriasse a fonte serial. O problema depende de perder/corromper a mensagem de início; o reinício com `#START` recebido funciona.

Correção recomendada: estabelecer uma sincronização explícita de sessão, com resposta identificável à solicitação do PC, ou um procedimento de resincronização após timeout que confirme o novo fluxo e marque a lacuna. Não reinicializar simplesmente em todo cabeçalho: ele é transmitido a cada cinco segundos durante funcionamento normal.

### 2. Porta aberta é tratada como aquisição ativa, mesmo sem dados — prioridade média

Em `D:/projetos/maurinsoft/ECG/Lazarus/ecgsource.pas`, linhas 291–293, a fonte fica ativa após abrir/configurar a porta, sem aguardar um cabeçalho e uma amostra válidos. Em `D:/projetos/maurinsoft/ECG/Lazarus/main.pas`, linhas 694 e 902, a barra de status anuncia aquisição ativa. Após um segundo sem dados, o BPM é corretamente limpo e outro rótulo avisa que não há dados, porém a barra continua dizendo “Aquisição ativa”.

Correção recomendada: distinguir porta aberta, aguardando firmware, recebendo, sem dados e desconectado. Anunciar aquisição somente após validar o fluxo; retirar esse estado quando expirar o prazo de recepção.

### 3. Erro de leitura não encerra a conexão e pode consumir CPU — prioridade média

Em `D:/projetos/maurinsoft/ECG/Lazarus/ecgsource.pas`, linhas 207–210, uma leitura vazia repete imediatamente o ciclo. O código da biblioteca FPC instalada (`serial.pp`, função `SerReadTimeout`, linha 455) devolve zero tanto no timeout quanto na falha de `ReadFile`. Se a falha retornar imediatamente após retirar o USB, o ciclo pode girar sem espera. Não há tratamento de erro, encerramento da fonte nem reconexão nesse caminho.

Correção recomendada: distinguir falha do sistema de timeout, aplicar espera limitada quando não houver dados, atualizar o estado e permitir reconectar. Se o estado de execução for alterado pela thread, adaptar também `Stop` para sempre liberar thread e handle, independentemente desse estado.

### 4. A interface permite uma velocidade incompatível — prioridade baixa

`D:/projetos/maurinsoft/ECG/Lazarus/main.lfm`, linha 442, oferece 9600 baud, enquanto o firmware usa exclusivamente 115200 (`firmware/arduino_ad8232/arduino_ad8232.ino`, linha 19). A seleção padrão está correta, mas escolher 9600 impede interpretar as mensagens. Para este equipamento, fixar 115200 ou rejeitar a opção incompatível antes de conectar.

## O que está correto

| Item | Resultado da revisão |
|---|---|
| Formato | Ambos usam `sequencia,adc,lead_off` no protocolo v3 |
| Configuração serial | 115200 baud, 8 bits, sem paridade, 1 stop bit, sem controle de fluxo |
| Delimitação | Firmware envia CRLF; parser acumula bytes, ignora CR e conclui a linha em LF |
| Leituras parciais | A linha é preservada entre chamadas; não depende de receber um pacote inteiro de uma vez |
| Taxa nominal | 500 amostras/s; sequência convertida em passos de 2000 µs |
| Capacidade | Pior linha de dados tem 19 bytes: 9500 bytes/s. Em 8N1 são 95.000 bit/s, abaixo dos 115.200 disponíveis, antes da pequena carga de metadados |
| Validação | ADC de 0 a 1023, flag 0/1, três campos e tamanho limitado; mensagens malformadas não viram valores inventados |
| Perdas | Saltos de sequência marcam descontinuidade; fila cheia no PC também marca perda |
| Contadores | Volta de 32 bits tratada no v3 e no timestamp do v2 |
| Eletrodos | LO+ ou LO− ativo vira `lead_off=1`; a aplicação invalida a amostra e reinicializa o processamento |
| Separação aquisição/serial | ADC disparado por Timer1, com fila no firmware; o processamento visual não dita o instante das conversões |

A capacidade calculada não substitui medir estabilidade do relógio, driver USB e tempo de aquisição no equipamento.

## Observabilidade e integridade

O firmware envia `#STAT,DROPPED=...`, mas o software ignora essa estatística. Os saltos de sequência ainda detectam perdas durante o fluxo; falta apresentar um contador de perdas ao usuário e guardar os diagnósticos de comunicação.

O protocolo não possui checksum. A validação atual detecta erros de formato e faixa, mas uma alteração de dígito que continue válida pode passar despercebida. CRC é uma melhoria de integridade possível, não um requisito para que a comunicação básica funcione.

O PC envia `?` apenas uma vez ao abrir a porta e não verifica a resposta. O firmware ignora esse comando nos primeiros 250 ms e pode demorar até o próximo cabeçalho periódico, em cinco segundos, caso os cabeçalhos iniciais se percam. Uma negociação com repetição limitada e timeout explícito melhoraria o início da conexão.

## Testes executados

- Compilação do teste contra **o parser atual do projeto**, com verificações de faixa e overflow.
- 15.000 amostras consecutivas, representando 30 segundos a 500 Hz, com cabeçalhos e estatísticas periódicos: todas aceitas, tempo crescente e nenhum falso salto.
- Perda de amostra e eletrodo desconectado: marcados corretamente.
- Reinício com `#START`: recuperação correta.
- Reinício sem `#START`: defeito reproduzido conforme achado 1.
- Suíte existente de aquisição: protocolo, voltas de contador, filtros, recuperação de BPM e persistência/qualidade passaram.

Os testes alimentam o software com bytes sintéticos. **Não verificam a UART física, o conversor USB do Nano ou um AD8232 conectado.** A consulta ao registro de portas seriais não retornou uma porta COM nesta sessão. Para concluir a validação física, é necessário identificar a porta e confirmar que o firmware v3 foi gravado; então medir amostras por segundo, perdas e resposta a reinício e desconexão reais.
