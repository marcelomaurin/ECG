@echo off
title Instalador de Dependencias Python - ECG Monitor v1.2
echo ========================================================
echo       ECG MONITOR v1.2 - INSTALACAO DE DEPENDENCIAS
echo ========================================================
echo.
echo Verificando se o Python esta instalado no sistema...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERRO] Python nao foi encontrado no PATH do sistema.
    echo Por favor, instale o Python 3.10, 3.11 ou 3.12 (marcando "Add Python to PATH").
    echo Download em: https://www.python.org/downloads/
    echo.
    pause
    exit /b 1
)

echo [OK] Python detectado!
echo Instalando bibliotecas leves para CPU (PyTorch, NumPy, PyYAML)...
echo.
pip install --extra-index-url https://download.pytorch.org/whl/cpu torch numpy pyyaml
if %errorlevel% neq 0 (
    echo.
    echo [AVISO] Falha ao instalar via indice CPU. Tentando pip padrao...
    pip install torch numpy pyyaml
)

echo.
echo ========================================================
echo   INSTALACAO CONCLUIDA COM SUCESSO!
echo   Voce ja pode abrir o ECGMonitor.exe e usar a IA.
echo ========================================================
echo.
pause
