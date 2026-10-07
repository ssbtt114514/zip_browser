; Zip Browser Windows 安装器（Inno Setup）
; 用法（在 CI 中，先 flutter build windows --release）：
;   ISCC.exe .tooling\installer.iss /DAppVersion=0.7.0
; 输入：build\windows\x64\runner\Release\*（Flutter 构建产物）
; 输出：dist\zip-browser-windows-x64-setup.exe
;
; 注意：Inno Setup 的相对路径以 .iss 脚本所在目录（.tooling/）为基准，
;       所以脚本内一律写 ..\ 前缀指回仓库根。

#define MyAppName "Zip Browser"
#ifndef AppVersion
  #define AppVersion "0.7.0"
#endif
#define MyAppPublisher "ssbtt114514"
#define MyAppExeName "zip_browser.exe"
#define AppBuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{4C2F6B8A-9D3E-4A11-8F7B-2E5A1C9D3F6E}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Zip Browser
DefaultGroupName=Zip Browser
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\dist
OutputBaseFilename=zip-browser-windows-x64-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
; Flutter 默认应用图标（CI 里由 flutter create 生成，相对仓库根）
SetupIconFile=..\windows\runner\resources\app_icon.ico
WizardStyle=modern
DisableProgramGroupPage=yes

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"

[Files]
Source: "{#AppBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent
