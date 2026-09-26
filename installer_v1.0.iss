; Script Inno Setup para ECG Monitor v1.0
; Maurinsoft

#define MyAppName "ECG Monitor"
#define MyAppVersion "1.0"
#define MyAppPublisher "Maurinsoft"
#define MyAppURL "https://maurinsoft.com.br"
#define MyAppExeName "ECGMonitor.exe"

[Setup]
AppId={{D8F9A3B1-2C4E-4567-9A10-123456789ABC}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Maurinsoft\ECGMonitor
DefaultGroupName=Maurinsoft\ECG Monitor
AllowNoIcons=yes
OutputDir=D:\projetos\maurinsoft\ECG\bin
OutputBaseFilename=ECGMonitor_v1.0_Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "D:\projetos\maurinsoft\ECG\Lazarus\ECGMonitor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\Lazarus\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\Lazarus\img\*"; DestDir: "{app}\img"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "D:\projetos\maurinsoft\ECG\models\ecg_yolo\ecg_yolo1d_best.pt"; DestDir: "{app}\models\ecg_yolo"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\ai\yolo1d\predict.py"; DestDir: "{app}\ai\yolo1d"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\ai\yolo1d\model.py"; DestDir: "{app}\ai\yolo1d"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\ai\yolo1d\dataset.py"; DestDir: "{app}\ai\yolo1d"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\ai\yolo1d\config.yaml"; DestDir: "{app}\ai\yolo1d"; Flags: ignoreversion
Source: "D:\projetos\maurinsoft\ECG\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
