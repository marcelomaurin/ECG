# Simulador didático: dez ritmos

Na Etapa 2, selecione **Simulação Didática**, escolha o ritmo e clique em **Iniciar Simulação**. Não é necessário Arduino para este modo. A aquisição continua a 500 Hz e passa pelo DSP do aplicativo. O aviso de simulação permanece visível.

| Ritmo | Código | Padrão inicial | Representação |
|---|---|---|---|
| Ritmo sinusal normal | N | 72 BPM | P–QRS–T e variação sinusal suave |
| Bradicardia sinusal | BRADY | 48 BPM | P–QRS–T com intervalos prolongados |
| Taquicardia sinusal | TACHY | 130 BPM | P–QRS–T com RR e QT menores |
| Fibrilação atrial | AFIB | Média alvo de 95 BPM | RR irregular, ausência de P organizada e atividade atrial ondulatória |
| Flutter atrial | AFLUT | 75 BPM ventricular | Ondas em serra a 300/min, condução fixa 4:1 |
| Taquicardia supraventricular | SVT | 180 BPM | Regular, QRS estreito, P oculta neste exemplo |
| Extrassístole atrial | PAC | Base de 78 BPM | P alterada, QRS estreito precoce e pausa incompleta |
| Extrassístole ventricular | PVC | Base de 75 BPM | Complexo largo precoce e pausa compensatória |
| Taquicardia ventricular | VT | 180 BPM | Complexos largos monomórficos, sem P vinculada |
| Fibrilação ventricular | VFIB | Sem BPM organizado | Atividade contínua com amplitude/frequência variáveis, sem modelo P–QRS–T |

São morfologias representativas para ensino e testes, não todas as variantes clínicas e nem reprodução calibrada da imagem. A escala é arbitrária. A implementação usa superposição de gaussianas, atividade atrial periódica e osciladores modulados; não é uma implementação do modelo diferencial ECGSYN.

## Geração e parâmetros

- O relógio deriva do índice de amostra: timestamps 0, 2000, 4000… microssegundos.
- A frequência editável é ventricular. No flutter 4:1, a frequência atrial é quatro vezes esse valor. Na FV o controle de BPM fica desabilitado.
- Ritmos possuem limites de frequência didáticos para manter as características do preset.
- Qualidade, oscilação de linha de base e interferência de 60 Hz continuam disponíveis.
- PAC/PVC são precedidos por intervalos de 0,68/0,62 do RR basal e seguidos por 1,15/1,38, respectivamente. `PVCFrequency` indica quantos ciclos normais há entre eventos e também controla PAC.
- A superposição mantém caudas da onda T e ondas P antecipadas entre ciclos. Gaussianas possuem caudas; o parâmetro de duração não equivale a uma medição clínica exata da largura.
- O marcador sintético indica uma única ativação R nominal por batimento. Não representa a saída do detector DSP. FV nunca emite esse marcador.
- A semente opcional do gerador permite reprodução independente por instância. Alterar o ritmo conserva a monotonicidade temporal. Trocar ritmo durante gravação encerra o exame corrente.

## Exportação

**Gerar Dataset Sintético** produz 20 exemplos para cada um dos dez ritmos: 200 pares CSV/JSON.

O CSV mantém as cinco colunas iniciais e acrescenta `expected_rhythm` e `r_peak`. `expected_class` agora identifica o batimento sintético (N/S/V/Q); `expected_rhythm` identifica o ritmo (N/BRADY/TACHY/AFIB/AFLUT/SVT/PAC/PVC/VT/VFIB). Para FV, Q indica atividade sem batimento organizado, não um rótulo de batimento AAMI validado. As classes de batimento não devem ser confundidas com as dez categorias de ritmo.

`filtered_val` é a referência sintética limpa, anterior ao DSP do aplicativo; `raw_adc` inclui os artefatos configurados e é limitado a 0…1023. Não são valores calibrados em mV. O JSON usa esquema 2, inclui semente, código de ritmo, parâmetros e `is_simulated`. O antigo campo ambíguo `expected_class` no JSON foi substituído por `rhythm_code`. Valores numéricos usam ponto decimal independentemente da configuração regional; `heart_rate` é nulo para FV. O gerador rejeita taxas diferentes de 500 Hz em vez de gerar metadados incompatíveis.

## Detecção e gravação

Adicionar ritmos ao gerador não treina nem amplia o classificador. Para AFLUT/SVT/VT/VFIB, o painel informa que a classificação ainda não foi implementada. O traçado pode ser visualizado, gravado e estudado; os classificadores Pascal/Python existentes não são executados sobre esses novos exames sintéticos. Na FV não são exibidos BPM ou marcadores R derivados de simples cruzamento de limiar; o BPM do exame fica nulo. O banco também deixa de preencher uma medida ausente com 72 BPM.

## Verificação automatizada

Em PowerShell, a partir da raiz do projeto:

```powershell
.\tests\run_simulator_tests.ps1
```

O script usa Free Pascal instalado em `C:\lazarus`, gera resultados em uma pasta temporária e informa a localização. Cobre 30 segundos por ritmo, timestamps, amplitude finita, regularidade/irregularidade RR, prematuridade e pausas, larguras relativas de QRS, atividade atrial 4:1, ausência de picos na FV, repetibilidade, extremos de BPM, artefatos, troca de ritmo, geração em thread e JSON em localidade com vírgula decimal. Não substitui validação clínica.

## Referências

- Imagem fornecida pelo usuário, com crédito NRSNG e título “EKG Interpretation”: lista dos dez padrões.
- [McSharry et al., ECGSYN / PhysioNet](https://archive.physionet.org/physiotools/ecgsyn/): referência científica sobre parametrização de morfologia e variabilidade de ECG sintético, sem reutilização de código.
- [A comparative study… based on McSharry mathematical model, 2019](https://pubmed.ncbi.nlm.nih.gov/30941635/): síntese de morfologias de arritmias por parametrização.
- [ACC/AHA/HRS, diretriz de taquicardia supraventricular, 2015](https://www.ahajournals.org/doi/pdf/10.1161/cir.0000000000000311): referência para atividade atrial em serra do flutter; o preset 4:1 é uma escolha didática.
