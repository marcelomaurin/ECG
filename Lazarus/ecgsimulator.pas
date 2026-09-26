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

    // Estado interno da geracao continua com base de tempo fisiologica real (ms)
    FBeatTimeMs: Double;        // Tempo decorrido no batimento atual (ms)
    FCurrentRRMs: Double;       // Duracao do ciclo atual (intervalo RR em ms)
    FCurrentBeatIndex: Integer; // Contador de batimentos
    FCurrentClass: String;      // Rotulo do batimento: 'N', 'V', 'S', etc.
    FIsCurrentPVC: Boolean;
    FIsCurrentPAC: Boolean;
    FPrevWasPVC: Boolean;
    FPrevWasPAC: Boolean;
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
    function ReadAllSamples(var AList: array of TECGSample): Integer;
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
      if (NowMs - NextSampleTime) > 60 then
        NextSampleTime := NowMs + 2;
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

  FBeatTimeMs := 0.0;
  FCurrentBeatIndex := 0;
  FCurrentRRMs := 60000.0 / Max(30.0, FParams.HeartRate);
  FCurrentClass := 'N';
  FIsCurrentPVC := False;
  FIsCurrentPAC := False;
  FPrevWasPVC := False;
  FPrevWasPAC := False;
  FLastTickMs := GetTickCount64;
  FTotalSamplesGenerated := 0;
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
  Sec, BasalRR: Double;
  DeltaT, P, Q, R, S, T: Double;
  Baseline, Noise, PowerLine: Double;
  RawVal, FilteredVal: Double;
  RPeakTimeMs: Double;
  IsPVC, IsPAC: Boolean;
begin
  BasalRR := 60000.0 / Max(30.0, FParams.HeartRate);
  RPeakTimeMs := 180.0; // O pico R ocorre estavelmente a 180ms do inicio do ciclo

  // Avanco estrito a 500 Hz (2.0 ms por amostra)
  FBeatTimeMs := FBeatTimeMs + 2.0;

  // Final do ciclo cardiaco atual -> Transicao para o proximo batimento
  if FBeatTimeMs >= FCurrentRRMs then
  begin
    FBeatTimeMs := FBeatTimeMs - FCurrentRRMs;
    Inc(FCurrentBeatIndex);

    FPrevWasPVC := FIsCurrentPVC;
    FPrevWasPAC := FIsCurrentPAC;
    FIsCurrentPVC := False;
    FIsCurrentPAC := False;

    case FParams.RhythmType of
      rtNormal:
      begin
        FCurrentClass := 'N';
        // Variabilidade sinusal respiratoria fisiologica suave (+-3.5%)
        FCurrentRRMs := BasalRR * (1.0 + (Sin(FCurrentBeatIndex * 0.35) * 0.035));
      end;

      rtSinusTachycardia:
      begin
        FCurrentClass := 'TACHY';
        FCurrentRRMs := BasalRR;
      end;

      rtSinusBradycardia:
      begin
        FCurrentClass := 'BRADY';
        FCurrentRRMs := BasalRR;
      end;

      rtAtrialFibrillation:
      begin
        FCurrentClass := 'AFIB';
        // Fibrilacao Atrial: Intervalos RR caoticos entre 420ms e 1050ms
        FCurrentRRMs := 420.0 + (Random * 630.0);
      end;

      rtPVC:
      begin
        // Se o batimento anterior foi o PVC, agora ocorre o batimento de PAUSA COMPENSATORIA
        if FPrevWasPVC then
        begin
          FCurrentClass := 'N';
          // Pausa compensatoria completa: intervalo longo ate o proximo sinusal
          FCurrentRRMs := BasalRR * 1.38;
        end
        // Se alcancou a frequencia de disparo, ESTE eh o batimento PREMATURO de PVC
        else if (FCurrentBeatIndex mod Max(2, FParams.PVCFrequency) = 0) then
        begin
          FIsCurrentPVC := True;
          FCurrentClass := 'V';
          // Acoplamento precoce: o intervalo ANTERIOR a este batimento foi encurtado
          FCurrentRRMs := BasalRR * 0.62;
        end
        else
        begin
          FCurrentClass := 'N';
          FCurrentRRMs := BasalRR;
        end;
      end;

      rtPAC:
      begin
        // Se o batimento anterior foi PAC, intervalo de pausa nao-compensatoria
        if FPrevWasPAC then
        begin
          FCurrentClass := 'N';
          FCurrentRRMs := BasalRR * 1.25;
        end
        else if (FCurrentBeatIndex mod Max(2, FParams.PVCFrequency) = 0) then
        begin
          FIsCurrentPAC := True;
          FCurrentClass := 'S';
          FCurrentRRMs := BasalRR * 0.68; // Batimento atrial prematuro
        end
        else
        begin
          FCurrentClass := 'N';
          FCurrentRRMs := BasalRR;
        end;
      end;
    end;
  end;

  IsPVC := FIsCurrentPVC;
  IsPAC := FIsCurrentPAC;
  DeltaT := FBeatTimeMs - RPeakTimeMs; // Tempo relativo ao centro do pico R em ms

  // --- MORFOLOGIA DAS ONDAS EM MILISSEGUNDOS REAIS (INDEPENDENTE DO RR) ---

  if IsPVC then
  begin
    // MORFOLOGIA DE EXTRASSISTOLE VENTRICULAR (PVC):
    // 1. Ausencia completa de onda P (origem ectopica ventricular)
    P := 0.0;
    Q := 0.0;
    // 2. QRS aberrante e alargado (>130ms): sigma = 30ms produz base > 130ms
    R := 440.0 * Exp(-0.5 * Sqr(DeltaT / 30.0));
    // 3. Onda S profunda e alargada
    S := -220.0 * Exp(-0.5 * Sqr((DeltaT - 38.0) / 26.0));
    // 4. Onda T invertida (discordancia ventricular classica)
    T := -120.0 * Exp(-0.5 * Sqr((DeltaT - 180.0) / 55.0));
  end
  else if IsPAC then
  begin
    // MORFOLOGIA DE EXTRASSISTOLE ATRIAL (PAC):
    // Onda P precoce e bifasica/deformada
    P := -25.0 * Exp(-0.5 * Sqr((DeltaT + 155.0) / 16.0)) + 38.0 * Exp(-0.5 * Sqr((DeltaT + 130.0) / 16.0));
    // QRS estreito normal (conducao ventricular normal ~85ms)
    Q := FParams.QAmplitude * Exp(-0.5 * Sqr((DeltaT + 24.0) / 8.0));
    R := FParams.RAmplitude * Exp(-0.5 * Sqr(DeltaT / 14.0));
    S := FParams.SAmplitude * Exp(-0.5 * Sqr((DeltaT - 22.0) / 10.0));
    T := FParams.TAmplitude * Exp(-0.5 * Sqr((DeltaT - 200.0) / 45.0));
  end
  else if FParams.RhythmType = rtAtrialFibrillation then
  begin
    // MORFOLOGIA DE FIBRILACAO ATRIAL:
    // Sem onda P organizada (P=0), QRS estreito e estavel (~85ms)
    P := 0.0;
    Q := FParams.QAmplitude * Exp(-0.5 * Sqr((DeltaT + 24.0) / 8.0));
    R := FParams.RAmplitude * Exp(-0.5 * Sqr(DeltaT / 14.0));
    S := FParams.SAmplitude * Exp(-0.5 * Sqr((DeltaT - 22.0) / 10.0));
    T := FParams.TAmplitude * Exp(-0.5 * Sqr((DeltaT - 200.0) / 45.0));
  end
  else
  begin
    // MORFOLOGIA NORMAL / TAQUICARDIA / BRADICARDIA (RITMO SINUSAL):
    // P normal (~80ms), QRS estreito (~85ms), T normal
    P := FParams.PAmplitude * Exp(-0.5 * Sqr((DeltaT + 140.0) / 22.0));
    Q := FParams.QAmplitude * Exp(-0.5 * Sqr((DeltaT + 24.0) / 8.0));
    R := FParams.RAmplitude * Exp(-0.5 * Sqr(DeltaT / 14.0));
    S := FParams.SAmplitude * Exp(-0.5 * Sqr((DeltaT - 22.0) / 10.0));
    T := FParams.TAmplitude * Exp(-0.5 * Sqr((DeltaT - 200.0) / 45.0));
  end;

  Sec := FTotalSamplesGenerated / 500.0;
  Inc(FTotalSamplesGenerated);

  // Deriva de linha de base respiratoria (~0.25 Hz)
  Baseline := FParams.BaselineDrift * 35.0 * Sin(2.0 * Pi * 0.25 * Sec);

  // Ondulacoes caoticas de fibrilacao atrial na linha de base ('f' waves multi-frequenciais)
  if FParams.RhythmType = rtAtrialFibrillation then
  begin
    Baseline := Baseline +
      14.0 * Sin(2.0 * Pi * 4.1 * Sec) +
      11.0 * Cos(2.0 * Pi * 5.7 * Sec) +
       9.0 * Sin(2.0 * Pi * 7.3 * Sec) +
       6.0 * Cos(2.0 * Pi * 8.8 * Sec);
  end;

  // Ruido estocastico de alta frequencia
  Noise := (Random - 0.5) * (FParams.NoiseLevel * 50.0);

  // Interferencia da rede eletrica de 60 Hz
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
  Result.ExpectedClass := FCurrentClass;
  Result.IsPeak := (abs(DeltaT) <= 2.0); // Marca o pico R no topo da onda R
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

function TSimulatedECGSource.ReadAllSamples(var AList: array of TECGSample): Integer;
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
