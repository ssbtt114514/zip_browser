; Zip Browser Windows 安装器（Inno Setup）
; 用法（在 CI 中，先 flutter build windows --release）：
;   ISCC.exe .tooling\installer.iss /DAppVersion=0.7.0
; 输入：build\windows\x64\runner\Release\*（Flutter 构建产物）
;       build\installer-prereqs\VC_redist.x64.exe            （tool/fetch_installer_prereqs.py 下载）
;       build\installer-prereqs\MicrosoftEdgeWebview2Setup.exe（同上）
; 输出：dist\zip-browser-windows-x64-setup.exe
;
; 注意：Inno Setup 的相对路径以 .iss 脚本所在目录（.tooling/）为基准，
;       所以脚本内一律写 ..\ 前缀指回仓库根。
;
; 修复「安装后无法运行」：
;   1. 干净系统缺少 VC++ 运行库（VCRUNTIME140.dll 等）→ 双击 exe 报
;      「丢失 VCRUNTIME140.dll」，应用根本起不来 → 安装时静默装 VC redist；
;   2. LTSC / Server / 精简系统缺 WebView2 Runtime → 内核初始化失败 →
;      检测注册表，缺了就静默安装微软官方常青版引导器。

#define MyAppName "Zip Browser"
#ifndef AppVersion
  #define AppVersion "0.7.0"
#endif
#ifndef Flavor
  #define Flavor "full"
#endif

#if Flavor == "single"
  #define NameSuffix "（单内核版）"
  #define FileSuffix "-single"
  #define DirSuffix " Single"
  #define AppIdValue "{{4C2F6B8A-9D3E-4A11-8F7B-2E5A1C9D3F70}"
#elif Flavor == "none"
  #define NameSuffix "（无内核版）"
  #define FileSuffix "-no-kernel"
  #define DirSuffix " NoKernel"
  #define AppIdValue "{{4C2F6B8A-9D3E-4A11-8F7B-2E5A1C9D3F71}"
#else
  #define NameSuffix ""
  #define FileSuffix ""
  #define DirSuffix ""
  #define AppIdValue "{{4C2F6B8A-9D3E-4A11-8F7B-2E5A1C9D3F6E}"
#endif

#define MyAppPublisher "ssbtt114514"
#define MyAppExeName "zip_browser.exe"
#define AppBuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={#AppIdValue}
AppName={#MyAppName}{#NameSuffix}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Zip Browser{#DirSuffix}
DefaultGroupName=Zip Browser{#DirSuffix}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=..\dist
OutputBaseFilename=zip-browser-windows-x64{#FileSuffix}-setup
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
; —— 运行时依赖（仅打包进安装器，装完即弃；存放在 build/installer-prereqs，
;      不能放进 Release 目录，否则会被上面的 recursesubdirs 装进 {app}）——
Source: "..\build\installer-prereqs\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall
Source: "..\build\installer-prereqs\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}{#NameSuffix}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\卸载 {#MyAppName}{#NameSuffix}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}{#NameSuffix}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  // WebView2 Runtime 的 EdgeUpdate 客户端 GUID（微软官方文档）
  WebView2Guid = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

// 是否已装有 WebView2 Runtime（覆盖 64 位视图 / 32 位视图 / 每用户三种安装位）
function WebView2Installed(): Boolean;
var
  Pv: String;
begin
  Result :=
    (RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Guid, 'pv', Pv) and (Pv <> '')) or
    (RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\' + WebView2Guid, 'pv', Pv) and (Pv <> '')) or
    (RegQueryStringValue(HKCU, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\' + WebView2Guid, 'pv', Pv) and (Pv <> ''));
end;

// 静默执行 {tmp} 里的安装器并等待结束
function ExecSilent(const ExeName, Params: String): Integer;
var
  ResultCode: Integer;
  Path: String;
begin
  Path := ExpandConstant('{tmp}\' + ExeName);
  if not FileExists(Path) then begin
    Log(Format('%s 不存在，跳过（CI 下载失败时兜底）', [ExeName]));
    Result := -1;
    Exit;
  end;
  Log(Format('执行 %s %s', [ExeName, Params]));
  if not Exec(Path, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode) then
    ResultCode := -1;
  Result := ResultCode;
end;

// 开始安装文件前先装运行时依赖
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  Result := '';  // 空 = 继续

  // 1) VC++ x64 运行库：其产品码随小版本变化难以可靠检测，而
  //    vc_redist 对已装机器是快速 no-op，因此总是静默重跑一遍
  Code := ExecSilent('VC_redist.x64.exe', '/install /quiet /norestart');
  case Code of
    0:     Log('VC++ 运行库安装/已存在：成功');
    1638:  Log('VC++ 运行库：系统已有更新版本，跳过');
    3010:  begin
             Log('VC++ 运行库安装成功，需要重启才能完全生效');
             NeedsRestart := False;  // 不强制重启，VC 运行库对首次启动一般已生效
           end;
    -1:    Log('VC redist 包缺失（CI 下载失败），跳过静默安装');
  else
    Log(Format('VC++ 运行库安装返回 %d，继续安装（应用可能仍可运行）', [Code]));
  end;

  // 2) WebView2 Runtime：仅在系统完全没有时才装
  if WebView2Installed() then begin
    Log('检测到 WebView2 Runtime 已安装，跳过');
  end else begin
    Log('未检测到 WebView2 Runtime，开始静默安装（常青版）');
    Code := ExecSilent('MicrosoftEdgeWebview2Setup.exe', '/silent /install');
    if Code = 0 then
      Log('WebView2 Runtime 安装成功')
    else if Code = 3010 then
      Log('WebView2 Runtime 安装成功，需重启生效')
    else begin
      Log(Format('WebView2 Runtime 安装返回 %d（可能是网络不可达），继续安装', [Code]));
      MsgBox(
        '未能自动安装 WebView2 浏览器内核（可能原因：网络不可达）。' + #13#10 +
        '浏览器仍会安装，但没有该内核将无法加载网页。' + #13#10 + #13#10 +
        '可稍后手动下载安装：https://developer.microsoft.com/microsoft-edge/webview2/',
        mbConfirmation, MB_OK);
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  // 安装完成后清理 {tmp} 里的依赖包由 deleteafterinstall 标记自动完成
end;
