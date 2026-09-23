unit ecgtypes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils
  {$IFDEF MSWINDOWS}
  , Windows, Registry
  {$ENDIF}
  ;

type
  TECGMode = (emHardware, emSimulation);

  TECGHeartStatus = (hsNormal, hsBradycardia, hsTachycardia, hsDisconnected);

  TECGRecord = record
    RawValue: Double;
    FilteredValue: Double;
    TimestampMs: Int64;
    LeadsOff: Boolean;
    IsPeak: Boolean;
  end;

  PECGRecord = ^TECGRecord;

  TECGStats = record
    BPM: Integer;
    InstantBPM: Double;
    RRIntervalMs: Double;
    RRStdDev: Double;
    MinVal: Double;
    MaxVal: Double;
    MeanVal: Double;
    Amplitude: Double;
    Status: TECGHeartStatus;
    StatusText: String;
  end;

function GetAvailableCOMPorts: TStringList;
function HeartStatusToString(Status: TECGHeartStatus): String;

implementation

function HeartStatusToString(Status: TECGHeartStatus): String;
begin
  case Status of
    hsNormal: Result := 'Ritmo Normal';
    hsBradycardia: Result := 'Bradicardia (< 60 bpm)';
    hsTachycardia: Result := 'Taquicardia (> 100 bpm)';
    hsDisconnected: Result := 'Eletrodo Solto (Leads Off)';
  else
    Result := 'Desconhecido';
  end;
end;

function GetAvailableCOMPorts: TStringList;
{$IFDEF MSWINDOWS}
var
  Reg: TRegistry;
  ValueNames: TStringList;
  I: Integer;
  PortName: String;
{$ENDIF}
begin
  Result := TStringList.Create;
  {$IFDEF MSWINDOWS}
  Reg := TRegistry.Create;
  ValueNames := TStringList.Create;
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('HARDWARE\DEVICEMAP\SERIALCOMM') then
    begin
      Reg.GetValueNames(ValueNames);
      for I := 0 to ValueNames.Count - 1 do
      begin
        PortName := Reg.ReadString(ValueNames[I]);
        if PortName <> '' then
          Result.Add(PortName);
      end;
      Reg.CloseKey;
    end;
  finally
    ValueNames.Free;
    Reg.Free;
  end;

  // Fallback se registro não listar nenhuma porta: testar COM1..COM16
  if Result.Count = 0 then
  begin
    for I := 1 to 16 do
      Result.Add('COM' + IntToStr(I));
  end;
  {$ELSE}
  Result.Add('/dev/ttyUSB0');
  Result.Add('/dev/ttyUSB1');
  Result.Add('/dev/ttyACM0');
  {$ENDIF}
end;

end.
