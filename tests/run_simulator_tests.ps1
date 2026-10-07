param(
    [string]$Compiler = 'C:\lazarus\fpc\3.2.2\bin\i386-win32\fpc.exe',
    [string]$OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ('ecg-simulator-' + [guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDirectory).Path
& $Compiler ('-Fu' + (Join-Path $projectRoot 'Lazarus')) ('-FU' + $outputPath) ('-FE' + $outputPath) -gl -Cr -Co -Ci (Join-Path $PSScriptRoot 'test_ecg_simulator.pas')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar os testes.' }
& (Join-Path $outputPath 'test_ecg_simulator.exe') (Join-Path $outputPath 'samples')
if ($LASTEXITCODE -ne 0) { throw 'Falha nos testes do simulador.' }
Write-Host ('Resultados em: ' + $outputPath)
