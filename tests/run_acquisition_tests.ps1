param(
    [string]$Lazarus = 'C:\lazarus',
    [string]$SharedUnits = '',
    [string]$OutputDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('ecg-acquisition-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (!$SharedUnits) { $SharedUnits = Join-Path (Split-Path -Parent $projectRoot) 'CHATGPT' }
$compiler = Join-Path $Lazarus 'fpc\3.2.2\bin\i386-win32\fpc.exe'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDirectory).Path
& $compiler ('-Fu' + (Join-Path $projectRoot 'Lazarus')) `
  ('-Fu' + (Join-Path $SharedUnits 'pacote\AI Filtros Sonoros')) `
  ('-Fu' + (Join-Path $SharedUnits 'pacote\AI Math')) `
  ('-Fu' + (Join-Path $Lazarus 'lcl\units\i386-win32')) `
  ('-Fu' + (Join-Path $Lazarus 'components\lazutils\lib\i386-win32')) `
  ('-FU' + $outputPath) ('-FE' + $outputPath) -gl -Cr -Co -Ci `
  (Join-Path $PSScriptRoot 'test_ecg_acquisition.pas')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar testes de aquisicao.' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'Lazarus\sqlite3.dll') -Destination $outputPath
& (Join-Path $outputPath 'test_ecg_acquisition.exe') (Join-Path $outputPath 'test.db')
if ($LASTEXITCODE -ne 0) { throw 'Falha nos testes de aquisicao.' }
