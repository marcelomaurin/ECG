# Atualizacao automatica do ECGMonitor (Windows)

O ECGMonitor verifica em segundo plano a ultima **Release estavel** do repositorio GitHub `marcelomaurin/ECG` ao iniciar, caso o pacote de instalacao inclua `updates/ecg_update.ps1`.

## Publicar uma versao

1. Compile o ECGMonitor Lazarus com as dependencias Windows.
2. Atualize a versao instalada em `Lazarus/main.pas` (parametro `-CurrentVersion`) e no script Inno Setup.
3. Publique uma GitHub Release com tag numerica `vX.Y.Z`.
4. Anexe um instalador Inno Setup nomeado exatamente `ECGMonitor_vX.Y.Z_Setup.exe`.
5. Anexe `SHA256SUMS.txt` com uma linha de SHA-256 no formato `<64 hex>  ECGMonitor_vX.Y.Z_Setup.exe`.
6. Instale a nova versao e confirme o funcionamento do atualizador antes da proxima Release.

O codigo **nao instala commits da branch main**: o fonte precisa ser compilado, empacotado e publicado como Release. Enquanto nao existir Release, nenhuma atualizacao sera aplicada.

## Operacao

O checador nao bloqueia a interface. So considera releases nao-draft e nao-prerelease. Baixa o instalador (limite 300 MiB), valida o hash SHA-256 e aguarda o encerramento natural da aplicacao por ate 24 horas antes de executar o instalador em modo silencioso. Nao encerra aquisicao nem finaliza o processo do ECG.

Os arquivos baixados e logs ficam em `%LOCALAPPDATA%\ECGMonitor\`. A instalacao segue as permissoes do Windows: se a pasta exigir privilegios administrativos, UAC pode solicitar elevacao e a instalacao pode falhar em ambiente nao interativo.

**Seguranca:** o SHA-256 detecta corrupcao mas nao substitui assinatura Authenticode; recomenda-se assinar os instaladores. O download depende da integridade do GitHub Release e da conexao HTTPS. Nao habilite atualizacoes de forks ou repositorios desconhecidos.

## Limitacoes e validacao pendente

- O mecanismo atual e para **Windows/Inno Setup**; Linux exige atualizador especifico.
- O processo checa a versao na inicializacao, nao monitora a internet continuamente.
- O instalador deve incluir o script. Instalacoes anteriores necessitam uma atualizacao manual inicial.
- A Release e o arquivo SHA256SUMS devem ser criados no fluxo de publicacao; atualmente o repositorio nao possui Releases publicadas.
- Pendente compilar com Lazarus e verificar instalacao silenciosa, UAC, atualizacao e rollback no Windows. Nao utilizar em ambiente clinico antes de validar.

