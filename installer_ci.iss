#ifndef AppVersion
#define AppVersion "1.3.0"
#endif
#ifndef RepoRoot
#define RepoRoot "."
#endif
#ifndef OutputDir
#define OutputDir "release"
#endif
[Setup]
AppId={{D8F9A3B1-2C4E-4567-9A10-123456789ABC}
AppName=ECG Monitor
AppVersion={#AppVersion}
DefaultDirName={autopf}\Maurinsoft\ECGMonitor
DefaultGroupName=Maurinsoft\ECG Monitor
OutputDir={#OutputDir}
OutputBaseFilename=ECGMonitor_v{#AppVersion}_Setup
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
[Files]
Source: "{#RepoRoot}\Lazarus\ECGMonitor.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\Lazarus\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\Lazarus\updates\ecg_update.ps1"; DestDir: "{app}\updates"; Flags: ignoreversion
Source: "{#RepoRoot}\Lazarus\img\*"; DestDir: "{app}\img"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#RepoRoot}\models\*"; DestDir: "{app}\models"; Flags: ignoreversion recursesubdirs createallsubdirs skipifsourcedoesntexist
Source: "{#RepoRoot}\ai\*"; DestDir: "{app}\ai"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\ECG Monitor"; Filename: "{app}\ECGMonitor.exe"
