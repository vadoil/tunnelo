; Установщик Tunnelo для Windows.
;
; Собирается в CI компилятором Inno Setup: ISCC.exe tunnelo.iss
; Версия и путь к собранному приложению приходят снаружи через /D.
;
; Права администратора обязательны: приложение создаёт сетевой адаптер
; для туннеля, а без повышенных прав это невозможно. Ставим в Program
; Files, поэтому установщик и так потребует их у системы.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef IconFile
  #define IconFile "..\runner\resources\app_icon.ico"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName "Tunnelo"
#define AppPublisher "Tunnelo"
#define AppUrl "https://tunello.online"
#define AppExe "Tunnelo.exe"

[Setup]
AppId={{319F468D-AB9A-4E82-890D-505B4EB2B577}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/contacts
AppUpdatesURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputBaseFilename=Tunnelo-Setup-{#AppVersion}
SetupIconFile={#IconFile}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Туннелю нужны права администратора — ставим для всех пользователей.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; \
  GroupDescription: "Дополнительно:"; Flags: unchecked
Name: "autostart"; Description: "Запускать при входе в систему"; \
  GroupDescription: "Дополнительно:"; Flags: unchecked

[Files]
; Всё содержимое сборки целиком: рядом с exe лежат ядро, драйвер
; сетевого адаптера и плагины — без них приложение не запустится.
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Удалить {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Приложение требует прав администратора, а такие программы Windows из
; папки автозагрузки не запускает. Поэтому автозапуск — задача планировщика
; с наивысшими правами: стартует при входе без запроса UAC.
Filename: "schtasks"; Parameters: "/Create /F /TN ""{#AppName}"" /SC ONLOGON /RL HIGHEST /TR ""\""{app}\{#AppExe}\"""""; \
  Flags: runhidden; Tasks: autostart
Filename: "{app}\{#AppExe}"; Description: "Запустить {#AppName}"; WorkingDir: "{app}"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM {#AppExe}"; \
  Flags: runhidden; RunOnceId: "TunneloKill"
Filename: "schtasks"; Parameters: "/Delete /F /TN ""{#AppName}"""; \
  Flags: runhidden; RunOnceId: "TunneloAutostartTask"

[Code]
// Обновление поверх работающего Tunnelo: старый процесс держит DLL и порт
// ядра, и первый запуск новой версии падает. Гасим его до копирования файлов.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  R: Integer;
begin
  Exec('taskkill.exe', '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, R);
  Result := '';
end;

[UninstallDelete]
; Настройки и журналы приложение держит рядом с собой — убираем за собой.
Type: filesandordirs; Name: "{app}\data"
