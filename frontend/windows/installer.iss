; Inno Setup script — zabalí Flutter Windows release do instalátoru, který
; přepíše předchozí instalaci (čistá aktualizace bez ručního kopírování složky).
; Verze se předává z CI: ISCC.exe /DAppVersion=v1.1.0 windows\installer.iss
; Lokálně lze spustit i bez /D (použije se DefaultVersion níže).

#ifndef AppVersion
  #define AppVersion "v0.0.0"
#endif
; Odstraň případné vedoucí "v" (tag vX.Y.Z → X.Y.Z)
#if Copy(AppVersion, 1, 1) == "v"
  #define NumVersion Copy(AppVersion, 2, Len(AppVersion) - 1)
#else
  #define NumVersion AppVersion
#endif

#define AppName "Ucpávky"
#define AppExe "ucpavky.exe"
#define Publisher "UNIFAST"

[Setup]
; Stálé AppId → instalátor pozná předchozí verzi a přepíše ji.
AppId={{B7A9F1E2-3C4D-4E5F-9A0B-0C1D2E3F4A5B}}
AppName={#AppName}
AppVersion={#NumVersion}
AppPublisher={#Publisher}
DefaultDirName={autopf}\Ucpavky
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=ucpavky-setup-{#NumVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 64bit aplikace (Flutter x64 release)
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Files]
; Celá Release složka (exe + DLL + data\) musí zůstat pohromadě.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Vytvořit zástupce na ploše"; GroupDescription: "Zástupci:"

[Run]
Filename: "{app}\{#AppExe}"; Description: "Spustit {#AppName}"; Flags: nowait postinstall skipifsilent
