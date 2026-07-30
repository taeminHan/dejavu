#define MyAppName "dejavu"
#define MyAppVersion "0.9.0"
#define MyAppDisplayVersion "0.9.0-rc.1"
#define MyAppPublisher "taeminHan"
#define MyAppExeName "dejavu.exe"

[Setup]
AppId={{8D51C102-A0C8-4FA7-A03E-E9746DD3F3F2}
AppName={#MyAppName}
AppVersion={#MyAppDisplayVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\..\outputs
OutputBaseFilename=dejavu-Setup-{#MyAppDisplayVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
CloseApplicationsFilter=dejavu.exe
RestartApplications=no
AppMutex=Local\dejavu.SingleInstance
MinVersion=10.0.22000
UninstallDisplayName=dejavu
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\assets\dejavu.ico
VersionInfoVersion={#MyAppVersion}.0
VersionInfoProductName={#MyAppName}
VersionInfoDescription=Claude and Codex usage monitor for Windows 11
VersionInfoCompany={#MyAppPublisher}
VersionInfoCopyright=Copyright (C) 2026 taeminHan and contributors
SetupLogging=yes

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕화면 바로가기 만들기"; GroupDescription: "추가 바로가기:"; Flags: unchecked

[Files]
Source: "..\..\..\outputs\dejavu-0.9.0-rc.1\dejavu.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\PRIVACY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SECURITY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\CHANGELOG.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\dejavu"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\dejavu"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "dejavu 실행"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "dejavu"; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "UsageBarForClaude"; Flags: deletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "ClaudeUsageTray"; Flags: deletevalue

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /IM dejavu.exe /F"; Flags: runhidden waituntilterminated; RunOnceId: "StopDejavu"
