[Setup]
AppName=Lions Club App
AppVersion=3.0.1
AppPublisher=Lions Club
AppPublisherURL=https://github.com/ianehyndman-max/Lions_App
DefaultDirName={autopf}\LionsClubApp
DefaultGroupName=Lions Club App
OutputDir=.
OutputBaseFilename=LionsClubApp_Setup_v3.0.1
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayIcon={app}\lions_app_3.exe

[Files]
Source: "..\build\windows\x64\runner\Release\lions_app_3.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\images\lions_icon.png"; DestDir: "{app}"; Flags: ignoreversion

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\lions_app_3.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Lions Club App"; Filename: "{app}\lions_app_3.exe"
Name: "{autodesktop}\Lions Club App"; Filename: "{app}\lions_app_3.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\lions_app_3.exe"; Description: "{cm:LaunchProgram,Lions Club App}"; Flags: nowait postinstall skipifsilent
