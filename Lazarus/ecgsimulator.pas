unit ecgsimulator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, syncobjs,
  ecgsource;

type
  { TSimulatedECGSource }
  TSimulatedECGSource = class(TInterfacedObject, IECGSource)
  private
    FParams: TECGWaveParameters;
    FIsRunning: Boolean;
    FLock: TCriticalSection;
    FThread: TThread;

    // Fila circular de amostras geradas
    FQueue: array[0..4095] of TECGSample;
    FQueueHead: Integer;
    FQueueTail: Integer;

    // Estado interno da geracao continua
    FPhase: Double;             // Fase do batimento atual (0.0 a 1.0)
    FBeatDurationMs: Double;    // Duracao do ciclo atual
    FCurrentBeatIndex: Integer; // Contador de batimentos para injecao periodica
    FNextIsPVC: Boolean;
    FNextIsPAC: Boolean;
    FAFibNextIntervalMs: Double;
    FLastTickMs: QWord;
    FTotalSamplesGenerated: Int64;

    procedure PushSample(const S: TECGSample);
  public
    function ComputeNextSample(const NowTickMs: QWord): TECGSample;
    constructor Create(const AParams: TECGWaveParameters);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;
    function ReadSample(out ASample: TECGSample): Boolean;
    function ReadAllSamples(var AList: array of TECGSample; out ACount: Integer): Integer;
    function IsRunning: Boolean;
    function GetSampleRate: Double;
    function GetDescription: String;
    function IsHardware: Boolean;

    procedure UpdateParameters(const AParams: TECGWaveParameters);
    property Params: TECGWaveParameters read FParams write UpdateParameters;
  end;

function GetDefaultWaveParameters(Rhythm: TECGRhythmType): TECGWaveParameters;

implementation

function GetDefaultWaveParameters(Rhythm: TECGRhythmType): TECGWaveParameters;
begin
  Result.RhythmType := Rhythm;
  Result.NoiseLevel := 0.05;
  Result.BaselineDrift := 0.15;
  Result.PowerLine60Hz := False;
  Result.Quality := qlGood;
  Result.PVCFrequency := 6;

  // Parametros morfologicos padrao
  Result.PAmplitude := 35.0;
  Result.PDuration := 0.040;
  Result.PRInterval := 0.160;

  Result.QAmplitude := -25.0;
  Result.RAmplitude := 360.0;
  Result.SAmplitude := -70.0;
  Result.QRSDuration := 0.090;

  Result.TAmplitude := 75.0;
  Result.TDuration := 0.070;
  Result.QTInterval := 0.380;

  case Rhythm of
    rtNormal:
      Result.HeartRate := 72.0;

    rtSinusTachycardia:
    begin
      Result.HeartRate := 130.0;
      Result.QTInterval := 0.280; // Encurtamento fisiologico do QT
    end;

    rtSinusBradycardia:
    begin
      Result.HeartRate := 48.0;
      Result.QTInterval := 0.440; // Alongamento fisiologico do QT
    end;

    rtAtrialFibrillation:
    begin
      Result.HeartRate := 95.0;
      Result.PAmplitude := 0.0;  // Ausencia completa de onda P
      Result.NoiseLevel := 0.12; // Ondas 'f' de fibrilacao
    end;

    rtPVC:
      Result.HeartRate := 75.0;

    rtPAC:
      Result.HeartRate := 78.0;
  end;
end;

type
  TSimulatorWorkerThread = class(TThread)
  private
    FOwner: TSimulatedECGSource;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TSimulatedECGSource);
  end;

constructor TSimulatorWorkerThread.Create(AOwner: TSimulatedECGSource);
begin
  inherited Create(True);
  FOwner := AOwner;
  FreeOnTerminate := False;
end;

procedure TSimulatorWorkerThread.Execute;
var
  Sample: TECGSample;
  NowMs: QWord;
  NextSampleTime: QWord;
begin
  NowMs := GetTickCount64;
  NextSampleTime := NowMs;

  while not Terminated and FOwner.FIsRunning do
  begin
    NowMs := GetTickCount64;
    // Produz amostras na frequencia de 500 Hz (1 a cada 2 ms)
    if NowMs >= NextSampleTime then
    begin
      Sample := FOwner.ComputeNextSample(NowMs);
      FOwner.PushSample(Sample);
      NextSampleTime := NextSampleTime + 2; // +2ms = 500 Hz
    end
    else
      Sleep(1);
  end;
end;

constructor TSimulatedECGSource.Create(const AParams: TECGWaveParameters);
begin
  inherited Create;
  FParams := AParams;
  FIsRunning := False;
  FLock := TCriticalSection.Create;
  FQueueHead := 0;
  FQueueTail := 0;
  FThread := nil;

  FPhase := 0.0;
  FCurrentBeatIndex := 0;
  FNextIsPVC := False;
  FNextIsPAC := False;
  FAFibNextIntervalMs := 600.0;
  FLastTickMs := GetTickCount64;
  FTotalSamplesGenerated := 0;
  FBeatDurationMs := 60000.0 / Max(30.0, FParams.HeartRate);
end;

destructor TSimulatedECGSource.Destroy;
begin
  Stop;
  FLock.Free;
  inherited Destroy;
end;

procedure TSimulatedECGSource.UpdateParameters(const AParams: TECGWaveParameters);
begin
  FLock.Acquire;
  try
    FParams := AParams;
    FBeatDurationMs := 60000.0 / Max(30.0, FParams.HeartRate);
  finally
    FLock.Release;
  end;
end;

procedure TSimulatedECGSource.PushSample(const S: TECGSample);
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

function TSimulatedECGSource.ComputeNextSample(const NowTickMs: QWord): TECGSample;
var
  ElapsedMs, Sec: Double;
  P, Q, R, S, T: Double;
  Baseline, Noise, PowerLine: Double;
  RawVal, FilteredVal: Double;
  CurrentClass: String;
  IsPVCBeat, IsPACBeat: Boolean;
  PhaseStep: Double;
begin
  ElapsedMs := 2.0; // 500 Hz = 2ms por amostra
  PhaseStep := ElapsedMs / Max(150.0, FBeatDurationMs);
  FPhase := FPhase + PhaseStep;

  // Final do ciclo cardíaco -> Prepara próximo ciclo
  if FPhase >= 1.0 then
  begin
    FPhase := FPhase - 1.0;
    Inc(FCurrentBeatIndex);

    // Ajusta o intervalo para o próximo batimento de acordo com o ritmo
    case FParams.RhythmType of
      rtNormal:
      begin
        // Leve arritmia sinusal respiratória natural (+-3%)
        FBeatDurationMs := (60000.0 / FParams.HeartRate) * (1.0 + (Sin(FCurrentBeatIndex * 0.4) * 0.035));
        FNextIsPVC := False;
        FNextIsPAC := False;
      end;

      rtSinusTachycardia:
      begin
        FBeatDurationMs := 60000.0 / Max(100.0, FParams.HeartRate);
        FNextIsPVC := False;
        FNextIsPAC := False;
      end;

      rtSinusBradycardia:
      begin
        FBeatDurationMs := 60000.0 / Min(55.0, FParams.HeartRate);
        FNextIsPVC := False;
        FNextIsPAC := False;
      end;

      rtAtrialFibrillation:
      begin
        // Fibrilação Atrial: Intervalos RR caóticos entre 420ms e 1100ms
        FBeatDurationMs := 420.0 + (Random * 680.0);
        FNextIsPVC := False;
        FNextIsPAC := False;
      end;

      rtPVC:
      begin
        // Injecao de PVC a cada N batimentos
        if (FCurrentBeatIndex mod Max(2, FParams.PVCFrequency) = 0) then
        begin
          FNextIsPVC := True;
          // Batimento prematuro (encurtado em 35%)
          FBeatDurationMs := (60000.0 / FParams.HeartRate) * 0.65;
        end
        else if FNextIsPVC then
        begin
          // Pausa compensatória após o PVC (+40%)
          FNextIsPVC := False;
          FBeatDurationMs := (60000.0 / FParams.HeartRate) * 1.35;
        end
        else
        begin
          FBeatDurationMs := 60000.0 / FParams.HeartRate;
          FNextIsPVC := False;
        end;
      end;

      rtPAC:
      begin
        // Extrassístole Atrial (PAC)
        if (FCurrentBeatIndex mod Max(2, FParams.PVCFrequency) = 0) then
        begin
          FNextIsPAC := True;
          FBeatDurationMs := (60000.0 / FParams.HeartRate) * 0.70;
        end
        else if FNextIsPAC then
        begin
          FNextIsPAC := False;
          FBeatDurationMs := (60000.0 / FParams.HeartRate) * 1.25;
        end
        else
        begin
          FBeatDurationMs := 60000.0 / FParams.HeartRate;
          FNextIsPAC := False;
        end;
      end;
    end;
  end;

  IsPVCBeat := (FParams.RhythmType = rtPVC) and FNextIsPVC;
  IsPACBeat := (FParams.RhythmType = rtPAC) and FNextIsPAC;

  // --- MODELAGEM DAS ONDAS POR CURVAS GAUSSIANAS ---

  if IsPVCBeat then
  begin
    // MORFOLOGIA DE PVC:
    // Sem onda P, complexo QRS aberrante, largo (>120ms), polaridade invertida e onda T oposta
    P := 0.0;
    Q := 0.0;
    R := 420.0 * Exp(-Sqr((FPhase - 0.32) / 0.038)); // R largo e precoce
    S := -180.0 * Exp(-Sqr((FPhase - 0.38) / 0.035)); // S profundo
    T := -110.0 * Exp(-Sqr((FPhase - 0.58) / 0.075)); // Onda T invertida
    CurrentClass := 'V';
  end
  else if IsPACBeat then
  begin
    // MORFOLOGIA DE PAC:
    // Onda P precoce e bifásica, QRS estreito e normal
    P := -25.0 * Exp(-Sqr((FPhase - 0.12) / 0.025)) + 40.0 * Exp(-Sqr((FPhase - 0.15) / 0.025));
    Q := FParams.QAmplitude * Exp(-Sqr((FPhase - 0.35) / 0.012));
    R := FParams.RAmplitude * Exp(-Sqr((FPhase - 0.37) / 0.016));
    S := FParams.SAmplitude * Exp(-Sqr((FPhase - 0.40) / 0.014));
    T := FParams.TAmplitude * Exp(-Sqr((FPhase - 0.60) / 0.060));
    CurrentClass := 'S';
  end
  else if FParams.RhythmType = rtAtrialFibrillation then
  begin
    // MORFOLOGIA DE FIBRILAÇÃO ATRIAL:
    // Sem onda P organizada (P=0), QRS estreito, ondas 'f' contínuas
    P := 0.0;
    Q := FParams.QAmplitude * Exp(-Sqr((FPhase - 0.33) / 0.012));
    R := FParams.RAmplitude * Exp(-Sqr((FPhase - 0.35) / 0.016));
    S := FParams.SAmplitude * Exp(-Sqr((FPhase - 0.38) / 0.014));
    T := FParams.TAmplitude * Exp(-Sqr((FPhase - 0.58) / 0.060));
    CurrentClass := 'AFIB';
  end
  else
  begin
    // MORFOLOGIA NORMAL / TAQUICARDIA / BRADICARDIA (RITMO SINUSAL):
    P := FParams.PAmplitude * Exp(-Sqr((FPhase - 0.15) / FParams.PDuration));
    Q := FParams.QAmplitude * Exp(-Sqr((FPhase - 0.32) / 0.015));
    R := FParams.RAmplitude * Exp(-Sqr((FPhase - 0.35) / 0.018));
    S := FParams.SAmplitude * Exp(-Sqr((FPhase - 0.38) / 0.016));
    T := FParams.TAmplitude * Exp(-Sqr((FPhase - 0.58) / FParams.TDuration));

    if FParams.RhythmType = rtSinusTachycardia then
      CurrentClass := 'TACHY'
    else if FParams.RhythmType = rtSinusBradycardia then
      CurrentClass := 'BRADY'
    else
      CurrentClass := 'N';
  end;

  Sec := FTotalSamplesGenerated / 500.0;
  Inc(FTotalSamplesGenerated);

  // Deriva de linha de base (respiração a ~0.25 Hz)
  Baseline := FParams.BaselineDrift * 35.0 * Sin(2.0 * Pi * 0.25 * Sec);

  // Ondulações de fibrilação atrial na linha de base
  if FParams.RhythmType = rtAtrialFibrillation then
    Baseline := Baseline + 18.0 * Sin(2.0 * Pi * 6.5 * Sec) + 12.0 * Cos(2.0 * Pi * 4.2 * Sec);

  // Ruído de alta frequência
  Noise := (Random - 0.5) * (FParams.NoiseLevel * 50.0);

  // Interferência de 60 Hz da rede elétrica
  if FParams.PowerLine60Hz then
    PowerLine := 25.0 * Sin(2.0 * Pi * 60.0 * Sec)
  else
    PowerLine := 0.0;

  FilteredVal := P + Q + R + S + T;
  RawVal := 512.0 + FilteredVal + Baseline + Noise + PowerLine;

  Result.TimestampUS := Round(Sec * 1000000.0);
  Result.RawValue := RawVal;
  Result.FilteredValue := FilteredVal;
  Result.LeadOff := False;
  Result.IsSimulated := True;
  Result.ExpectedClass := CurrentClass;
  Result.IsPeak := (FPhase >= 0.34) and (FPhase <= 0.36);
end;

procedure TSimulatedECGSource.Start;
begin
  if FIsRunning then Exit;
  FIsRunning := True;
  FThread := TSimulatorWorkerThread.Create(Self);
  FThread.Start;
end;

procedure TSimulatedECGSource.Stop;
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
  end;
end;

function TSimulatedECGSource.ReadSample(out ASample: TECGSample): Boolean;
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

function TSimulatedECGSource.ReadAllSamples(var AList: array of TECGSample; out ACount: Integer): Integer;
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

function TSimulatedECGSource.IsRunning: Boolean;
begin
  Result := FIsRunning;
end;

function TSimulatedECGSource.GetSampleRate: Double;
begin
  Result := 500.0;
end;

function TSimulatedECGSource.GetDescription: String;
begin
  Result := 'Simulador Didatico: ' + RhythmTypeToString(FParams.RhythmType) +
            ' (' + FormatFloat('0', FParams.HeartRate) + ' BPM)';
end;

function TSimulatedECGSource.IsHardware: Boolean;
begin
  Result := False;
end;

end.
