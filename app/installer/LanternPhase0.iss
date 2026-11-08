#define AppName "Lantern Phase 0 (Preview)"
#define AppVersion "0.1.0"
#define AppExe "lantern-mock.exe"

[Setup]
AppId={{9AB7A02C-6B22-4BC0-8C55-68B6A1D0F2C8}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Lantern
DefaultDirName={localappdata}\Programs\Lantern Phase 0
DefaultGroupName=Lantern Phase 0
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
Uninstallable=yes
OutputDir=..\dist
OutputBaseFilename=Lantern-Phase0-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\target\release\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Lantern Phase 0"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Lantern Phase 0"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch Lantern Phase 0"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
