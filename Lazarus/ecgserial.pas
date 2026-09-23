unit ecgserial;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, syncobjs,
  serial, ecgtypes, ecgdsp;

type
  { TECGAcquisitionThread }
  TECGAcquisitionThread = class(TThread)
  private
    FPortName: String;
    FBaudRate: Integer;
    FMode: TECGMode;
    FSimBPM: Integer;

    FSerialHandle: TSerialHandle;
    FIsConnected: Boolean;
    FLock: TCriticalSection;
    FDSP: TECGProcessor;

    // Buffer circular interno de amostras
    FQueue: array[0..2047] of TECGRecord;
    FQueueHead: Integer;
    FQueueTail: Integer;

    // Estado da simulação
    FSimPhase: Double;
    FSimLastTick: QWord;

    function GenerateSimulatedSample(const NowMs: QWord): TECGRecord;
    procedure PushSample(const ASample: TECGRecord);
    procedure OpenPort;
    procedure ClosePort;
    procedure ReadSerialData;

  protected
    procedure Execute; override;

  public
    constructor Create(const APort: String; ABaud: Integer; AMode: TECGMode; ADSP: TECGProcessor);
    destructor Destroy; override;

    function PopSample(out ASample: TECGRecord): Boolean;
    function PopAllSamples(var AList: array of TECGRecord; out ACount: Integer): Integer;

    property IsConnected: Boolean read FIsConnected;
    property Mode: TECGMode read FMode write FMode;
    property SimBPM: Integer read FSimBPM write FSimBPM;
  end;

implementation

constructor TECGAcquisitionThread.Create(const APort: String; ABaud: Integer; AMode: TECGMode; ADSP: TECGProcessor);
begin
  inherited Create(True); // Cria suspenso
  FreeOnTerminate := False;
  FPortName := APort;
  FBaudRate := ABaud;
  FMode := AMode;
  FDSP := ADSP;
  FSimBPM := 75;
  FSimPhase := 0.0;
  FSimLastTick := GetTickCount64;

  FLock := TCriticalSection.Create;
  FQueueHead := 0;
  FQueueTail := 0;
  FIsConnected := False;
  FSerialHandle := 0;
end;

destructor TECGAcquisitionThread.Destroy;
begin
  Terminate;
  WaitFor;
  ClosePort;
  FLock.Free;
  inherited Destroy;
end;

procedure TECGAcquisitionThread.PushSample(const ASample: TECGRecord);
var
  NextHead: Integer;
begin
  FLock.Acquire;
  try
    NextHead := (FQueueHead + 1) mod Length(FQueue);
    if NextHead <> FQueueTail then
    begin
      FQueue[FQueueHead] := ASample;
      FQueueHead := NextHead;
    end
    else
    begin
      // Fila cheia: descarta o mais antigo para manter tempo real
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
      FQueue[FQueueHead] := ASample;
      FQueueHead := NextHead;
    end;
  finally
    FLock.Release;
  end;
end;

function TECGAcquisitionThread.PopSample(out ASample: TECGRecord): Boolean;
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

function TECGAcquisitionThread.PopAllSamples(var AList: array of TECGRecord; out ACount: Integer): Integer;
var
  MaxItems: Integer;
begin
  ACount := 0;
  MaxItems := Length(AList);
  FLock.Acquire;
  try
    while (FQueueHead <> FQueueTail) and (ACount < MaxItems) do
    begin
      AList[ACount] := FQueue[FQueueTail];
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
      Inc(ACount);
    end;
    Result := ACount;
  finally
    FLock.Release;
  end;
end;

procedure TECGAcquisitionThread.OpenPort;
var
  CleanPort: String;
begin
  CleanPort := Trim(FPortName);
  {$IFDEF MSWINDOWS}
  if (Pos('\\.\', CleanPort) <> 1) and (Length(CleanPort) > 4) then
    CleanPort := '\\.\' + CleanPort;
  {$ENDIF}

  try
    FSerialHandle := SerOpen(CleanPort);
    if FSerialHandle > 0 then
    begin
      // 8 data bits, no parity, 1 stop bit
      SerSetParams(FSerialHandle, FBaudRate, 8, NoneParity, 1, []);
      FIsConnected := True;
    end
    else
      FIsConnected := False;
  except
    FIsConnected := False;
  end;
end;

procedure TECGAcquisitionThread.ClosePort;
begin
  if FIsConnected and (FSerialHandle > 0) then
  begin
    try
      SerClose(FSerialHandle);
    except
    end;
    FSerialHandle := 0;
    FIsConnected := False;
  end;
end;

function TECGAcquisitionThread.GenerateSimulatedSample(const NowMs: QWord): TECGRecord;
var
  BeatDurationMs, ElapsedMs: Double;
  Val, Noise, Baseline: Double;
  P, Q, R, S, T: Double;
begin
  BeatDurationMs := 60000.0 / Max(30, FSimBPM);
  ElapsedMs := NowMs - FSimLastTick;
  FSimLastTick := NowMs;

  FSimPhase := FSimPhase + (ElapsedMs / BeatDurationMs);
  if FSimPhase >= 1.0 then
    FSimPhase := FSimPhase - Int(FSimPhase);

  // Modelo sintético de traçado eletrocardiográfico (P-Q-R-S-T)
  // Onda P (despolarização atrial)
  P := 35.0 * Exp(-Sqr((FSimPhase - 0.15) / 0.035));
  // Complexo QRS (despolarização ventricular)
  Q := -25.0 * Exp(-Sqr((FSimPhase - 0.32) / 0.015));
  R := 360.0 * Exp(-Sqr((FSimPhase - 0.35) / 0.018));
  S := -70.0 * Exp(-Sqr((FSimPhase - 0.38) / 0.016));
  // Onda T (repolarização ventricular)
  T := 75.0 * Exp(-Sqr((FSimPhase - 0.58) / 0.065));

  // Deriva de linha de base (respiração a ~0.25 Hz)
  Baseline := 20.0 * Sin(2.0 * Pi * 0.25 * (NowMs / 1000.0));
  // Ruído de alta frequência (60Hz + ruído branco)
  Noise := (Random - 0.5) * 8.0 + 10.0 * Sin(2.0 * Pi * 60.0 * (NowMs / 1000.0));

  Val := 512.0 + P + Q + R + S + T + Baseline + Noise;

  // Processamento através do módulo DSP
  if Assigned(FDSP) then
    Result := FDSP.ProcessSample(Val, NowMs, False)
  else
  begin
    Result.RawValue := Val;
    Result.FilteredValue := Val - 512.0;
    Result.TimestampMs := NowMs;
    Result.LeadsOff := False;
    Result.IsPeak := False;
  end;
end;

procedure TECGAcquisitionThread.ReadSerialData;
var
  Buffer: array[0..255] of Char;
  BytesRead, I: Integer;
  LineBuffer: String;
  NowMs: QWord;
  SampleRec: TECGRecord;
  RawVal: Double;
  LeadsOff: Boolean;
  P1, P2: Integer;
  Part2: String;
begin
  LineBuffer := '';
  while not Terminated and FIsConnected do
  begin
    BytesRead := SerReadTimeout(FSerialHandle, Buffer, 10);
    if BytesRead > 0 then
    begin
      for I := 0 to BytesRead - 1 do
      begin
        if (Buffer[I] = #10) or (Buffer[I] = #13) then
        begin
          LineBuffer := Trim(LineBuffer);
          if LineBuffer <> '' then
          begin
            NowMs := GetTickCount64;
            // Ignora linhas de comentario ou cabecalho
            if (LineBuffer <> '') and (LineBuffer[1] = '#') then
            begin
              LineBuffer := '';
              Continue;
            end;

            // Protocolo v2: timestamp_us,adc,lead_off
            if Pos(',', LineBuffer) > 0 then
            begin
              P1 := Pos(',', LineBuffer);
              Part2 := Copy(LineBuffer, P1 + 1, Length(LineBuffer));
              P2 := Pos(',', Part2);
              if P2 > 0 then
              begin
                RawVal := StrToFloatDef(Copy(Part2, 1, P2 - 1), 512.0);
                LeadsOff := (Trim(Copy(Part2, P2 + 1, Length(Part2))) = '1');
              end
              else
              begin
                RawVal := StrToFloatDef(Part2, 512.0);
                LeadsOff := False;
              end;
            end
            else if LineBuffer = '!' then
            begin
              LeadsOff := True;
              RawVal := 512.0;
            end
            else
            begin
              LeadsOff := False;
              RawVal := StrToFloatDef(LineBuffer, 512.0);
            end;

            if Assigned(FDSP) then
              SampleRec := FDSP.ProcessSample(RawVal, NowMs, LeadsOff)
            else
            begin
              SampleRec.RawValue := RawVal;
              SampleRec.FilteredValue := RawVal - 512.0;
              SampleRec.TimestampMs := NowMs;
              SampleRec.LeadsOff := LeadsOff;
              SampleRec.IsPeak := False;
            end;

            PushSample(SampleRec);
            LineBuffer := '';
          end;
        end
        else
          LineBuffer := LineBuffer + Buffer[I];
      end;
    end
    else
      Sleep(2);
  end;
end;

procedure TECGAcquisitionThread.Execute;
var
  NowMs: QWord;
  SimSample: TECGRecord;
begin
  if FMode = emHardware then
  begin
    OpenPort;
    if FIsConnected then
      ReadSerialData;
  end
  else
  begin
    // Modo Simulação: Gera amostras a ~100 Hz (a cada 10ms)
    FIsConnected := True;
    while not Terminated do
    begin
      NowMs := GetTickCount64;
      SimSample := GenerateSimulatedSample(NowMs);
      PushSample(SimSample);
      Sleep(10);
    end;
  end;
end;

end.
