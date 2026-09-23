unit ecgsource;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs,
  serial, ecgtypes;

type
  { Tipos de Ritmo Simulados }
  TECGRhythmType = (
    rtNormal,
    rtAtrialFibrillation,
    rtPVC,
    rtPAC,
    rtSinusTachycardia,
    rtSinusBradycardia
  );

  { Nivel de Qualidade de Sinal }
  TECGQualityLevel = (
    qlExcellent,
    qlGood,
    qlRegular,
    qlPoor
  );

  { Estrutura Padronizada da Amostra (Hardware e Simulador) }
  TECGSample = record
    TimestampUS: Int64;
    RawValue: Double;
    FilteredValue: Double;
    LeadOff: Boolean;
    IsSimulated: Boolean;
    ExpectedClass: String; // Ground truth: "N", "AFIB", "PVC", "PAC", "TACHY", "BRADY"
    IsPeak: Boolean;
  end;

  PECGSample = ^TECGSample;

  { Parametros Didaticos da Onda ECG }
  TECGWaveParameters = record
    RhythmType: TECGRhythmType;
    HeartRate: Double;
    PAmplitude: Double;
    PDuration: Double;
    PRInterval: Double;
    QAmplitude: Double;
    RAmplitude: Double;
    SAmplitude: Double;
    QRSDuration: Double;
    TAmplitude: Double;
    TDuration: Double;
    QTInterval: Double;
    NoiseLevel: Double;        // 0.0 a 1.0
    BaselineDrift: Double;     // 0.0 a 1.0
    PowerLine60Hz: Boolean;    // Ruido de rede 60 Hz
    Quality: TECGQualityLevel;
    PVCFrequency: Integer;     // Batimentos normais entre PVCs (ex: 6)
  end;

  { Interface Comum para Aquisicao de Dados }
  IECGSource = interface
    ['{789A5F12-3D2E-4A6B-91C0-7456789ABCDE}']
    procedure Start;
    procedure Stop;
    function ReadSample(out ASample: TECGSample): Boolean;
    function ReadAllSamples(var AList: array of TECGSample): Integer;
    function IsRunning: Boolean;
    function GetSampleRate: Double;
    function GetDescription: String;
    function IsHardware: Boolean;
  end;

  { Implementacao de Aquisicao Serial (Hardware Real AD8232) }
  TSerialECGSource = class(TInterfacedObject, IECGSource)
  private
    FPortName: String;
    FBaudRate: Integer;
    FSerialHandle: TSerialHandle;
    FIsRunning: Boolean;
    FLock: TCriticalSection;
    FThread: TThread;

    FQueue: array[0..4095] of TECGSample;
    FQueueHead: Integer;
    FQueueTail: Integer;

    procedure PushSample(const S: TECGSample);
  public
    constructor Create(const APort: String; ABaud: Integer = 115200);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    function ReadSample(out ASample: TECGSample): Boolean;
    function ReadAllSamples(var AList: array of TECGSample): Integer;
    function IsRunning: Boolean;
    function GetSampleRate: Double;
    function GetDescription: String;
    function IsHardware: Boolean;
  end;

function RhythmTypeToString(RT: TECGRhythmType): String;
function RhythmTypeToCode(RT: TECGRhythmType): String;

implementation

function RhythmTypeToString(RT: TECGRhythmType): String;
begin
  case RT of
    rtNormal: Result := 'Ritmo Normal (Sinusal)';
    rtAtrialFibrillation: Result := 'Fibrilacao Atrial (AFib)';
    rtPVC: Result := 'Extrassistole Ventricular (PVC)';
    rtPAC: Result := 'Extrassistole Atrial (PAC)';
    rtSinusTachycardia: Result := 'Taquicardia Sinusal';
    rtSinusBradycardia: Result := 'Bradicardia Sinusal';
  else
    Result := 'Desconhecido';
  end;
end;

function RhythmTypeToCode(RT: TECGRhythmType): String;
begin
  case RT of
    rtNormal: Result := 'N';
    rtAtrialFibrillation: Result := 'AFIB';
    rtPVC: Result := 'V';
    rtPAC: Result := 'S';
    rtSinusTachycardia: Result := 'TACHY';
    rtSinusBradycardia: Result := 'BRADY';
  else
    Result := 'Q';
  end;
end;

{ Thread Interna de Leitura da Porta Serial }
type
  TSerialWorkerThread = class(TThread)
  private
    FOwner: TSerialECGSource;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TSerialECGSource);
  end;

constructor TSerialWorkerThread.Create(AOwner: TSerialECGSource);
begin
  inherited Create(True);
  FOwner := AOwner;
  FreeOnTerminate := False;
end;

procedure TSerialWorkerThread.Execute;
var
  Buffer: array[0..255] of Char;
  BytesRead, I: Integer;
  LineBuffer, Part2: String;
  P1, P2: Integer;
  RawVal: Double;
  LeadsOff: Boolean;
  Sample: TECGSample;
  Timestamp: Int64;
begin
  LineBuffer := '';
  while not Terminated and FOwner.FIsRunning do
  begin
    BytesRead := SerReadTimeout(FOwner.FSerialHandle, Buffer, 10);
    if BytesRead > 0 then
    begin
      for I := 0 to BytesRead - 1 do
      begin
        if (Buffer[I] = #10) or (Buffer[I] = #13) then
        begin
          LineBuffer := Trim(LineBuffer);
          if LineBuffer <> '' then
          begin
            if LineBuffer[1] <> '#' then
            begin
              Timestamp := GetTickCount64 * 1000;
              LeadsOff := False;
              RawVal := 512.0;

              // Protocolo v2: timestamp_us,adc,lead_off
              if Pos(',', LineBuffer) > 0 then
              begin
                P1 := Pos(',', LineBuffer);
                Timestamp := StrToInt64Def(Copy(LineBuffer, 1, P1 - 1), Timestamp);
                Part2 := Copy(LineBuffer, P1 + 1, Length(LineBuffer));
                P2 := Pos(',', Part2);
                if P2 > 0 then
                begin
                  RawVal := StrToFloatDef(Copy(Part2, 1, P2 - 1), 512.0);
                  LeadsOff := (Trim(Copy(Part2, P2 + 1, Length(Part2))) = '1');
                end
                else
                  RawVal := StrToFloatDef(Part2, 512.0);
              end
              else if LineBuffer = '!' then
              begin
                LeadsOff := True;
                RawVal := 512.0;
              end
              else
                RawVal := StrToFloatDef(LineBuffer, 512.0);

              Sample.TimestampUS := Timestamp;
              Sample.RawValue := RawVal;
              Sample.FilteredValue := RawVal - 512.0;
              Sample.LeadOff := LeadsOff;
              Sample.IsSimulated := False;
              Sample.ExpectedClass := 'REAL';
              Sample.IsPeak := False;

              FOwner.PushSample(Sample);
            end;
            LineBuffer := '';
          end;
        end
        else
          LineBuffer := LineBuffer + Buffer[I];
      end;
    end
    else
      Sleep(1);
  end;
end;

{ TSerialECGSource }

constructor TSerialECGSource.Create(const APort: String; ABaud: Integer);
begin
  inherited Create;
  FPortName := APort;
  FBaudRate := ABaud;
  FSerialHandle := 0;
  FIsRunning := False;
  FLock := TCriticalSection.Create;
  FQueueHead := 0;
  FQueueTail := 0;
  FThread := nil;
end;

destructor TSerialECGSource.Destroy;
begin
  Stop;
  FLock.Free;
  inherited Destroy;
end;

procedure TSerialECGSource.PushSample(const S: TECGSample);
var
  NextHead: Integer;
begin
  FLock.Acquire;
  try
    NextHead := (FQueueHead + 1) mod Length(FQueue);
    if NextHead <> FQueueTail then
    begin
      FQueue[FQueueHead] := S;
      FQueueHead := NextHead;
    end
    else
    begin
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
      FQueue[FQueueHead] := S;
      FQueueHead := NextHead;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TSerialECGSource.Start;
var
  CleanPort: String;
begin
  if FIsRunning then Exit;

  CleanPort := Trim(FPortName);
  {$IFDEF MSWINDOWS}
  if (Pos('\\.\', CleanPort) <> 1) and (Length(CleanPort) > 4) then
    CleanPort := '\\.\' + CleanPort;
  {$ENDIF}

  FSerialHandle := SerOpen(CleanPort);
  if FSerialHandle > 0 then
  begin
    SerSetParams(FSerialHandle, FBaudRate, 8, NoneParity, 1, []);
    FIsRunning := True;
    FThread := TSerialWorkerThread.Create(Self);
    FThread.Start;
  end;
end;

procedure TSerialECGSource.Stop;
begin
  if FIsRunning then
  begin
    FIsRunning := False;
    if FThread <> nil then
    begin
      FThread.Terminate;
      FThread.WaitFor;
      FreeAndNil(FThread);
    end;
    if FSerialHandle > 0 then
    begin
      SerClose(FSerialHandle);
      FSerialHandle := 0;
    end;
  end;
end;

function TSerialECGSource.ReadSample(out ASample: TECGSample): Boolean;
begin
  Result := False;
  FLock.Acquire;
  try
    if FQueueHead <> FQueueTail then
    begin
      ASample := FQueue[FQueueTail];
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
      Result := True;
    end;
  finally
    FLock.Release;
  end;
end;

function TSerialECGSource.ReadAllSamples(var AList: array of TECGSample): Integer;
var
  MaxItems: Integer;
begin
  Result := 0;
  MaxItems := Length(AList);
  FLock.Acquire;
  try
    while (FQueueHead <> FQueueTail) and (Result < MaxItems) do
    begin
      AList[Result] := FQueue[FQueueTail];
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
      Inc(Result);
    end;
  finally
    FLock.Release;
  end;
end;

function TSerialECGSource.IsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TSerialECGSource.GetSampleRate: Double;
begin
  Result := 500.0;
end;

function TSerialECGSource.GetDescription: String;
begin
  Result := 'Hardware Serial AD8232 (' + FPortName + ' @ ' + IntToStr(FBaudRate) + ' bps)';
end;

function TSerialECGSource.IsHardware: Boolean;
begin
  Result := True;
end;

end.
