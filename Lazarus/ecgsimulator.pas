unit ecgsimulator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, syncobjs, ecgsource;

type
  TSyntheticBeat = record
    PeakTimeMs: Double;
    BeatClass: String;
  end;

  { Educational morphology generator, not a diagnostic model. }
  TSimulatedECGSource = class(TInterfacedObject, IECGSource)
  private
    FParams: TECGWaveParameters;
    FIsRunning: Boolean;
    FLock: TCriticalSection;
    FThread: TThread;
    FQueue: array[0..4095] of TECGSample;
    FQueueHead, FQueueTail: Integer;
    FPreviousBeat, FCurrentBeat, FNextBeat: TSyntheticBeat;
    FBeatIndex: Integer;
    FTotalSamplesGenerated: Int64;
    FRandomState: LongWord;
    function NextRandom: Double;
    function BeatClass(AIndex: Integer): String;
    function NextBeat(const APrevious: TSyntheticBeat; AIndex: Integer): TSyntheticBeat;
    function BeatWave(const ABeat: TSyntheticBeat; ATimeMs: Double): Double;
    procedure ResetBeats;
    procedure PushSample(const S: TECGSample);
    function GetParams: TECGWaveParameters;
  public
    constructor Create(const AParams: TECGWaveParameters; ASeed: LongWord = 1);
    destructor Destroy; override;
    // One call advances the sample clock by exactly 2 ms, independent of wall time.
    function ComputeNextSample(const NowTickMs: QWord): TECGSample;
    procedure Start;
    procedure Stop;
    function ReadSample(out ASample: TECGSample): Boolean;
    function ReadAllSamples(var AList: array of TECGSample): Integer;
    function IsRunning: Boolean;
    function GetSampleRate: Double;
    function GetDescription: String;
    function IsHardware: Boolean;
    procedure UpdateParameters(const AParams: TECGWaveParameters);
    property Params: TECGWaveParameters read GetParams write UpdateParameters;
  end;

function GetDefaultWaveParameters(Rhythm: TECGRhythmType): TECGWaveParameters;
procedure GetRhythmRateLimits(Rhythm: TECGRhythmType; out AMin, AMax: Integer);

implementation

procedure GetRhythmRateLimits(Rhythm: TECGRhythmType; out AMin, AMax: Integer);
begin
  AMin := 35;
  AMax := 220;
  case Rhythm of
    rtNormal: begin AMin := 60; AMax := 100; end;
    rtSinusBradycardia: AMax := 59;
    rtSinusTachycardia: begin AMin := 101; AMax := 160; end;
    rtAtrialFlutter: begin AMin := 65; AMax := 87; end; // 4:1, atrial 260..348/min
    rtSupraventricularTachycardia: AMin := 150;
    rtVentricularTachycardia: AMin := 120;
    rtVentricularFibrillation: begin AMin := 0; AMax := 0; end;
  end;
end;

function GetDefaultWaveParameters(Rhythm: TECGRhythmType): TECGWaveParameters;
begin
  Result.RhythmType := Rhythm;
  Result.HeartRate := 72;
  Result.NoiseLevel := 0.05;
  Result.BaselineDrift := 0.15;
  Result.PowerLine60Hz := False;
  Result.Quality := qlGood;
  Result.PVCFrequency := 6; // normal beats between premature beats
  Result.PAmplitude := 35;
  Result.PDuration := 0.080;
  Result.PRInterval := 0.160;
  Result.QAmplitude := -25;
  Result.RAmplitude := 360;
  Result.SAmplitude := -70;
  Result.QRSDuration := 0.090;
  Result.TAmplitude := 75;
  Result.TDuration := 0.140;
  Result.QTInterval := 0.380;
  case Rhythm of
    rtSinusBradycardia:
      begin Result.HeartRate := 48; Result.QTInterval := 0.440; end;
    rtSinusTachycardia:
      begin Result.HeartRate := 130; Result.QTInterval := 0.280; Result.TDuration := 0.110; end;
    rtAtrialFibrillation:
      begin Result.HeartRate := 95; Result.PAmplitude := 0; end;
    rtAtrialFlutter:
      begin Result.HeartRate := 75; Result.PAmplitude := 0; Result.RAmplitude := 300; end;
    rtSupraventricularTachycardia:
      begin
        Result.HeartRate := 180;
        Result.PAmplitude := 0; // representative regular narrow-complex SVT
        Result.QRSDuration := 0.070;
        Result.QTInterval := 0.230;
        Result.TDuration := 0.100;
      end;
    rtPAC: Result.HeartRate := 78;
    rtPVC: Result.HeartRate := 75;
    rtVentricularTachycardia:
      begin
        Result.HeartRate := 180;
        Result.PAmplitude := 0;
        Result.QRSDuration := 0.160;
        Result.RAmplitude := 330;
        Result.SAmplitude := -220;
        Result.TAmplitude := -70;
        Result.QTInterval := 0.270;
      end;
    rtVentricularFibrillation:
      begin
        Result.HeartRate := 0; // no organized ventricular rate
        Result.PAmplitude := 0;
        Result.RAmplitude := 0;
      end;
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
var NowMs, NextSampleTime: QWord;
begin
  NextSampleTime := GetTickCount64;
  while not Terminated do
  begin
    NowMs := GetTickCount64;
    if NowMs >= NextSampleTime then
    begin
      FOwner.PushSample(FOwner.ComputeNextSample(NowMs));
      NextSampleTime := NextSampleTime + 2;
      // Compare before subtracting: QWord subtraction used to underflow here.
      if NowMs > NextSampleTime + 60 then NextSampleTime := NowMs + 2;
    end
    else Sleep(1);
  end;
end;

constructor TSimulatedECGSource.Create(const AParams: TECGWaveParameters; ASeed: LongWord);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRandomState := ASeed;
  if FRandomState = 0 then FRandomState := 1;
  FParams := AParams;
  UpdateParameters(AParams);
  ResetBeats;
end;

destructor TSimulatedECGSource.Destroy;
begin
  Stop;
  FLock.Free;
  inherited Destroy;
end;

function TSimulatedECGSource.NextRandom: Double;
begin
  // Per-source PRNG: reproducible exports, no shared Random state across threads.
  FRandomState := FRandomState xor (FRandomState shl 13);
  FRandomState := FRandomState xor (FRandomState shr 17);
  FRandomState := FRandomState xor (FRandomState shl 5);
  Result := FRandomState / 4294967296.0;
end;

function TSimulatedECGSource.BeatClass(AIndex: Integer): String;
begin
  Result := 'N';
  case FParams.RhythmType of
    rtVentricularFibrillation: Result := 'Q';
    rtVentricularTachycardia: Result := 'V';
    rtPVC, rtPAC:
      if (AIndex > 0) and (AIndex mod (Max(2, FParams.PVCFrequency) + 1) = 0) then
        if FParams.RhythmType = rtPVC then Result := 'V' else Result := 'S';
  end;
end;

function TSimulatedECGSource.NextBeat(const APrevious: TSyntheticBeat; AIndex: Integer): TSyntheticBeat;
var RR: Double;
begin
  Result.BeatClass := BeatClass(AIndex);
  RR := 60000.0 / Max(30.0, FParams.HeartRate);
  case FParams.RhythmType of
    rtNormal: RR := RR * (1 + 0.035 * Sin(AIndex * 0.35));
    rtAtrialFibrillation: RR := RR * (0.60 + 0.80 * NextRandom);
    rtPVC:
      if Result.BeatClass = 'V' then RR := RR * 0.62
      else if APrevious.BeatClass = 'V' then RR := RR * 1.38;
    rtPAC:
      if Result.BeatClass = 'S' then RR := RR * 0.68
      else if APrevious.BeatClass = 'S' then RR := RR * 1.15;
  end;
  // The short interval precedes the ectopic beat, the pause follows it.
  Result.PeakTimeMs := APrevious.PeakTimeMs + RR;
end;

procedure TSimulatedECGSource.ResetBeats;
begin
  FBeatIndex := 0;
  FCurrentBeat.PeakTimeMs := FTotalSamplesGenerated * 2.0 + 300;
  FCurrentBeat.BeatClass := BeatClass(0);
  FPreviousBeat := FCurrentBeat;
  FPreviousBeat.PeakTimeMs := FCurrentBeat.PeakTimeMs - 10000;
  FNextBeat := NextBeat(FCurrentBeat, 1);
end;

function Gaussian(X, Center, Sigma: Double): Double;
begin
  Result := Exp(-0.5 * Sqr((X - Center) / Max(1.0, Sigma)));
end;

function TSimulatedECGSource.BeatWave(const ABeat: TSyntheticBeat; ATimeMs: Double): Double;
var D, WidthScale, PCenter, TCenter, P: Double;
begin
  D := ATimeMs - ABeat.PeakTimeMs;
  if (D < -500) or (D > 800) then Exit(0);
  if FParams.RhythmType = rtVentricularTachycardia then
    Exit(-70 * Gaussian(D, -50, 22) + FParams.RAmplitude * Gaussian(D, 0, 36) +
      FParams.SAmplitude * Gaussian(D, 45, 32) + FParams.TAmplitude * Gaussian(D, 140, 38));
  if ABeat.BeatClass = 'V' then
    Exit(440 * Gaussian(D, 0, 30) - 220 * Gaussian(D, 38, 26) - 120 * Gaussian(D, 180, 55));
  WidthScale := FParams.QRSDuration / 0.090;
  PCenter := -1000 * (FParams.PRInterval + FParams.QRSDuration / 2 - FParams.PDuration / 2);
  TCenter := 1000 * (FParams.QTInterval - FParams.QRSDuration / 2 - FParams.TDuration / 2);
  P := FParams.PAmplitude * Gaussian(D, PCenter, FParams.PDuration * 250);
  if FParams.RhythmType in [rtAtrialFibrillation, rtAtrialFlutter, rtSupraventricularTachycardia] then P := 0;
  if ABeat.BeatClass = 'S' then
    P := -25 * Gaussian(D, -130, 16) + 38 * Gaussian(D, -105, 16);
  Result := P + FParams.QAmplitude * Gaussian(D, -24 * WidthScale, 8 * WidthScale) +
    FParams.RAmplitude * Gaussian(D, 0, 14 * WidthScale) +
    FParams.SAmplitude * Gaussian(D, 22 * WidthScale, 10 * WidthScale) +
    FParams.TAmplitude * Gaussian(D, TCenter, FParams.TDuration * 250);
end;

function TSimulatedECGSource.ComputeNextSample(const NowTickMs: QWord): TECGSample;
var
  Sec, TimeMs, Wave, Baseline, Noise, PowerLine, Phase, Envelope: Double;
  H: Integer;
  Nearest: TSyntheticBeat;
begin
  FLock.Acquire;
  try
    Sec := FTotalSamplesGenerated / ECG_SAMPLE_RATE;
    TimeMs := FTotalSamplesGenerated * 2.0;
    Result.TimestampUS := FTotalSamplesGenerated * 2000;
    Result.ExpectedRhythm := RhythmTypeToCode(FParams.RhythmType);
    Result.IsSimulated := True;
    Result.LeadOff := False;
    Result.Discontinuity := False;
    Result.SignalInvalid := False;
    Result.IsPeak := False;
    if FParams.RhythmType = rtVentricularFibrillation then
    begin
      // Continuous modulated activity, without P/QRS/T templates or R markers.
      Envelope := 0.72 + 0.18 * Sin(2 * Pi * 0.31 * Sec) + 0.10 * Sin(2 * Pi * 0.73 * Sec);
      Wave := Envelope * (155 * Sin(2 * Pi * 4.7 * Sec + 1.8 * Sin(2 * Pi * 0.37 * Sec)) +
        90 * Sin(2 * Pi * 6.9 * Sec + 1.2 * Sin(2 * Pi * 0.23 * Sec)) +
        45 * Sin(2 * Pi * 9.3 * Sec + 0.7 * Sin(2 * Pi * 0.61 * Sec)));
      Result.ExpectedClass := 'Q';
    end
    else
    begin
      while TimeMs >= FNextBeat.PeakTimeMs do
      begin
        FPreviousBeat := FCurrentBeat;
        FCurrentBeat := FNextBeat;
        Inc(FBeatIndex);
        FNextBeat := NextBeat(FCurrentBeat, FBeatIndex + 1);
      end;
      // Superposition preserves T tails and early P waves at cycle boundaries.
      Wave := BeatWave(FPreviousBeat, TimeMs) + BeatWave(FCurrentBeat, TimeMs) + BeatWave(FNextBeat, TimeMs);
      Nearest := FCurrentBeat;
      if Abs(TimeMs - FNextBeat.PeakTimeMs) < Abs(TimeMs - Nearest.PeakTimeMs) then Nearest := FNextBeat;
      Result.ExpectedClass := Nearest.BeatClass;
      Result.IsPeak := (TimeMs >= FCurrentBeat.PeakTimeMs) and (TimeMs - FCurrentBeat.PeakTimeMs < 2);
      case FParams.RhythmType of
        rtAtrialFibrillation:
          Wave := Wave + 14 * Sin(2 * Pi * 4.1 * Sec) + 11 * Cos(2 * Pi * 5.7 * Sec) +
            9 * Sin(2 * Pi * 7.3 * Sec) + 6 * Cos(2 * Pi * 8.8 * Sec);
        rtAtrialFlutter:
          begin
            Phase := 2 * Pi * (FParams.HeartRate * 4 / 60) * Sec;
            // Band-limited sawtooth: four atrial waves per ventricular complex.
            for H := 1 to 8 do Wave := Wave - 26 * Sin(H * Phase) / H;
          end;
      end;
    end;
    Baseline := FParams.BaselineDrift * 35 * Sin(2 * Pi * 0.25 * Sec);
    Noise := (NextRandom - 0.5) * FParams.NoiseLevel * 50;
    PowerLine := 0;
    if FParams.PowerLine60Hz then PowerLine := 25 * Sin(2 * Pi * 60 * Sec);
    Result.RawValue := EnsureRange(512 + Wave + Baseline + Noise + PowerLine, 0.0, 1023.0);
    Result.FilteredValue := Wave; // ideal reference; UI processes RawValue through DSP
    Inc(FTotalSamplesGenerated);
  finally FLock.Release; end;
end;

procedure TSimulatedECGSource.UpdateParameters(const AParams: TECGWaveParameters);
var TimingChanged: Boolean; MinRate, MaxRate: Integer;
begin
  FLock.Acquire;
  try
    TimingChanged := (AParams.RhythmType <> FParams.RhythmType) or
      (AParams.HeartRate <> FParams.HeartRate) or (AParams.PVCFrequency <> FParams.PVCFrequency);
    FParams := AParams;
    GetRhythmRateLimits(FParams.RhythmType, MinRate, MaxRate);
    FParams.HeartRate := EnsureRange(FParams.HeartRate, Double(MinRate), Double(MaxRate));
    FParams.QRSDuration := Max(0.040, FParams.QRSDuration);
    if TimingChanged then
    begin
      ResetBeats; // preserve monotonic sample time
      FQueueTail := FQueueHead;
    end;
  finally FLock.Release; end;
end;

function TSimulatedECGSource.GetParams: TECGWaveParameters;
begin
  FLock.Acquire;
  try Result := FParams; finally FLock.Release; end;
end;

procedure TSimulatedECGSource.PushSample(const S: TECGSample);
var NextHead: Integer;
begin
  FLock.Acquire;
  try
    if S.ExpectedRhythm <> RhythmTypeToCode(FParams.RhythmType) then Exit;
    NextHead := (FQueueHead + 1) mod Length(FQueue);
    if NextHead = FQueueTail then FQueueTail := (FQueueTail + 1) mod Length(FQueue);
    FQueue[FQueueHead] := S;
    FQueueHead := NextHead;
  finally FLock.Release; end;
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
  if not FIsRunning then Exit;
  FIsRunning := False;
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

function TSimulatedECGSource.ReadSample(out ASample: TECGSample): Boolean;
begin
  FLock.Acquire;
  try
    Result := FQueueHead <> FQueueTail;
    if Result then
    begin
      ASample := FQueue[FQueueTail];
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
    end;
  finally FLock.Release; end;
end;

function TSimulatedECGSource.ReadAllSamples(var AList: array of TECGSample): Integer;
begin
  Result := 0;
  FLock.Acquire;
  try
    while (FQueueHead <> FQueueTail) and (Result < Length(AList)) do
    begin
      AList[Result] := FQueue[FQueueTail];
      FQueueTail := (FQueueTail + 1) mod Length(FQueue);
      Inc(Result);
    end;
  finally FLock.Release; end;
end;

function TSimulatedECGSource.IsRunning: Boolean;
begin Result := FIsRunning; end;

function TSimulatedECGSource.GetSampleRate: Double;
begin Result := ECG_SAMPLE_RATE; end;

function TSimulatedECGSource.GetDescription: String;
var P: TECGWaveParameters;
begin
  P := GetParams;
  Result := 'Simulador Didatico: ' + RhythmTypeToString(P.RhythmType);
  if P.RhythmType = rtVentricularFibrillation then Result := Result + ' (sem BPM organizado)'
  else Result := Result + ' (' + FormatFloat('0', P.HeartRate) + ' BPM)';
end;

function TSimulatedECGSource.IsHardware: Boolean;
begin Result := False; end;

end.
