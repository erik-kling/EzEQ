#define AppName "EzEQ"
[Setup]
AppId=EzEQ.Windows
AppName={#AppName}
AppVersion={#Version}
AppPublisher=EzEQ
DefaultDirName={autopf}\EzEQ
DefaultGroupName=EzEQ
UninstallDisplayIcon={app}\EzEQ.exe
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.22000
PrivilegesRequired=admin
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir=..\dist
OutputBaseFilename=EzEQ-Windows-11-Intel-AMD-x64-Setup
InfoBeforeFile=VB-CABLE.txt
CloseApplications=yes
RestartApplications=no

[Files]
Source: "vendor\VBCABLE_Driver_Pack45.zip"; Flags: dontcopy
Source: "check-cable.ps1"; Flags: dontcopy
Source: "..\dist\EzEQ\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "VB-CABLE.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\EzEQ"; Filename: "{app}\EzEQ.exe"

[Run]
Filename: "{app}\EzEQ.exe"; Description: "Open EzEQ"; Flags: postinstall nowait skipifsilent runasoriginaluser; Check: CanLaunch

[Code]
var
  CableNeedsRestart: Boolean;

function PowerShell(const Arguments: String; var ExitCode: Integer): Boolean;
begin
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoLogo -NoProfile -NonInteractive ' + Arguments, '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
end;

function CableStatus: Integer;
var
  ExitCode: Integer;
begin
  Result := -1;
  if PowerShell('-ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\check-cable.ps1') + '"', ExitCode) then
    Result := ExitCode;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode, Count, Status: Integer;
  Staging: String;
begin
  Result := '';
  ExtractTemporaryFile('check-cable.ps1');
  Status := CableStatus;
  if Status = 0 then exit;
  if (Status < 0) or (Status = 3) then
  begin
    Result := 'Setup could not check the Windows audio devices. Run this installer again as an administrator.';
    exit;
  end;

  if Status <> 2 then
  begin
    ExtractTemporaryFile('VBCABLE_Driver_Pack45.zip');
    Staging := ExpandConstant('{tmp}\VB-CABLE');
    if not PowerShell('-ExecutionPolicy Bypass -File "' +
      ExpandConstant('{tmp}\check-cable.ps1') + '" -Unpack', ExitCode) or (ExitCode <> 0) then
    begin
      Result := 'The bundled VB-CABLE package could not be unpacked. Download the EzEQ installer again and retry.';
      exit;
    end;
    if not Exec(Staging + '\VBCABLE_Setup_x64.exe', '', Staging, SW_SHOW,
      ewWaitUntilTerminated, ExitCode) then
    begin
      Result := 'VB-CABLE Setup could not start. Run this EzEQ installer again to retry.';
      exit;
    end;
    for Count := 1 to 5 do
    begin
      Status := CableStatus;
      if (Status = 0) or (Status = 2) then break;
      Sleep(500);
    end;
    if (Status <> 0) and (Status <> 2) then
    begin
      Result := 'VB-CABLE was not installed. Run this EzEQ installer again and choose Install Driver in VB-CABLE Setup.';
      exit;
    end;
  end;
  CableNeedsRestart := True;
end;

function NeedRestart: Boolean;
begin
  Result := CableNeedsRestart;
end;

function CanLaunch: Boolean;
begin
  Result := not CableNeedsRestart;
end;
