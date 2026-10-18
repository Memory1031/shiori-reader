; Compiled from the same verified payload as the portable ZIP.
#ifndef Payload
  #error Payload must be supplied
#endif
#define InstallationId "{317FAF26-80D6-47B9-A5EF-14B3829374B3}"
#ifndef GroupName
  #define GroupName "Shiori"
#endif

[Setup]
AppId={{317FAF26-80D6-47B9-A5EF-14B3829374B3}
AppName=Shiori
AppVersion={#Version}
AppPublisher=Shiori
AppPublisherURL=https://memory1031.github.io/shiori-reader/
DefaultDirName={localappdata}\Programs\Shiori
DefaultGroupName={#GroupName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#Output}
OutputBaseFilename={#Filename}
SetupIconFile={#Icon}
UninstallDisplayIcon={app}\shiori.exe
VersionInfoVersion={#FileVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
AlwaysRestart=no
UsePreviousAppDir=yes
Uninstallable=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; Never delete user directories or recursively clear the application directory.

[Icons]
Name: "{group}\Shiori"; Filename: "{app}\shiori.exe"
Name: "{autodesktop}\Shiori"; Filename: "{app}\shiori.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{{317FAF26-80D6-47B9-A5EF-14B3829374B3}_is1"; ValueType: string; ValueName: "InstallLocation"; ValueData: "{app}"

[Run]
Filename: "{app}\shiori.exe"; Description: "{cm:LaunchProgram,Shiori}"; Flags: nowait postinstall skipifsilent

[Code]
var PreviousFiles: TArrayOfString;
function GetFileAttributes(Path: String): Cardinal;
  external 'GetFileAttributesW@kernel32.dll stdcall';

function UnlinkedPath(const Path: String): Boolean;
var Part: String; Attributes: Cardinal;
begin
  Result := False;
  Part := Path;
  while Length(Part) > 3 do begin
    Attributes := GetFileAttributes(Part);
    if (Attributes <> $FFFFFFFF) and ((Attributes and $400) <> 0) then exit;
    Part := ExtractFileDir(Part);
  end;
  Result := True;
end;

function OwnedInstallation(const Directory: String): Boolean;
var Marker: AnsiString; Location: String;
begin
  Result := LoadStringFromFile(AddBackslash(Directory) + '.shiori-install', Marker)
    and (Marker = '{#InstallationId}' + #10)
    and RegQueryStringValue(HKCU64, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#InstallationId}_is1', 'InstallLocation', Location)
    and (CompareText(RemoveBackslashUnlessRoot(Location), RemoveBackslashUnlessRoot(Directory)) = 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not UnlinkedPath(ExpandConstant('{app}')) then begin
    Result := 'Shiori cannot install through a symbolic link or junction.';
    exit;
  end;
  if ExpandConstant('{param:SHIORIUPDATE|0}') = '1' then
    if not OwnedInstallation(ExpandConstant('{app}')) then begin
      Result := 'Shiori installation identity does not match. Reinstall manually.';
      exit;
    end;
  if FileExists(ExpandConstant('{app}\.shiori-install')) and not OwnedInstallation(ExpandConstant('{app}')) then begin
    Result := 'Shiori installation registration does not match this directory.';
    exit;
  end;
  if OwnedInstallation(ExpandConstant('{app}')) then
    LoadStringsFromFile(ExpandConstant('{app}\program-files.txt'), PreviousFiles);
end;

function SafeManagedPath(const Value: String): Boolean;
var Parts: TArrayOfString; I: Integer; Name: String;
begin
  Result := False;
  if (Value = '') or (Length(Value) > 1024) or (Pos('\', Value) > 0)
    or (Pos(':', Value) > 0) or (Pos('*', Value) > 0) or (Pos('?', Value) > 0) then exit;
  Parts := StringSplit(Value, ['/'], stAll);
  for I := 0 to GetArrayLength(Parts) - 1 do begin
    Name := Parts[I];
    if (Name = '') or (Name = '.') or (Name = '..')
      or (Name[Length(Name)] = '.') or (Name[Length(Name)] = ' ') then exit;
  end;
  if (CompareText(Copy(Value, 1, 5), 'unins') = 0) or (Value = '.shiori-install') then exit;
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var CurrentFiles: TArrayOfString; I, J: Integer; Found: Boolean; Relative, Path: String;
begin
  if CurStep = ssPostInstall then begin
    if not SaveStringToFile(ExpandConstant('{app}\.shiori-install'), '{#InstallationId}' + #10, False) then
      RaiseException('Cannot record Shiori installation identity.');
    LoadStringsFromFile(ExpandConstant('{app}\program-files.txt'), CurrentFiles);
    for I := 0 to GetArrayLength(PreviousFiles) - 1 do begin
      Relative := PreviousFiles[I];
      if SafeManagedPath(Relative) then begin
        Found := False;
        for J := 0 to GetArrayLength(CurrentFiles) - 1 do
          if CompareText(CurrentFiles[J], Relative) = 0 then Found := True;
        if not Found then begin
          StringChangeEx(Relative, '/', '\', True);
          Path := AddBackslash(ExpandConstant('{app}')) + Relative;
          if UnlinkedPath(Path) then
            if not DeleteFile(Path) and FileExists(Path) then Log('Could not remove obsolete program file: ' + Relative);
        end;
      end;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    if OwnedInstallation(ExpandConstant('{app}')) then DeleteFile(ExpandConstant('{app}\.shiori-install'));
end;
