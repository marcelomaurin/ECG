unit ecgcalibration;
{$mode objfpc}{$H+}
interface
uses SysUtils, Math;
const
  ECG_CALIBRATION_MS = 8000;
  ECG_CALIBRATION_SETTLE_MS = 1000;
  ECG_SERIAL_GAP_MS = 1000;
  ECG_MIN_DSP_RATE = 125.0;
type
  // Counts complete ADC frames at receive-batch boundaries, never inter-byte times.
  // Call also on read timeouts so silence cannot complete a calibration.
  TECGRateCalibration = class
  private
    FStarted, FMeasuring: Boolean;
    FStart, FLastData, FHalfTime: QWord;
    FCount, FHalfCount: Int64;
    FRate: Double;
    FText, FReason: String;
    procedure Restart(const Reason: String);
  public
    procedure Reset;
    procedure Observe(NowMs: QWord; Count: Integer; LeadOff, Gap: Boolean);
    property Rate: Double read FRate;
    property StatusText: String read FText;
  end;
  // Uniform estimated time axis; batch delivery must not create duplicate times.
  TECGSampleClock = class
  private
    FOrigin: Int64;
    FIndex: Int64;
    FRate: Double;
  public
    procedure Start(OriginUS: Int64; Rate: Double);
    function Next: Int64;
  end;
implementation
procedure TECGSampleClock.Start(OriginUS: Int64; Rate: Double);
begin FOrigin := OriginUS; FRate := Rate; FIndex := 0; end;
function TECGSampleClock.Next: Int64;
begin Result := FOrigin + Round(FIndex * 1000000.0 / FRate); Inc(FIndex); end;
procedure TECGRateCalibration.Restart(const Reason: String);
begin
  FStarted := False; FMeasuring := False; FRate := 0;
  FCount := 0; FHalfCount := 0; FHalfTime := 0;
  FReason := Reason; FText := Reason;
end;
procedure TECGRateCalibration.Reset;
begin Restart('Calibracao: aguardando amostras ADC'); end;
procedure TECGRateCalibration.Observe(NowMs: QWord; Count: Integer; LeadOff, Gap: Boolean);
var Elapsed: QWord; Estimate, FirstRate, SecondRate: Double;
begin
  if LeadOff then
  begin Restart('Eletrodos soltos: calibracao suspensa'); Exit; end;
  if Gap then
  begin Restart('Fluxo interrompido: recalibrando'); Exit; end;
  if FStarted and (NowMs - FLastData > ECG_SERIAL_GAP_MS) then
    Restart('Sem dados / fluxo interrompido: recalibrando');
  if Count <= 0 then Exit;
  if not FStarted then
  begin
    FStarted := True; FStart := NowMs; FLastData := NowMs;
    Exit; // Discard the first buffered burst after connect/recovery.
  end;
  FLastData := NowMs;
  Elapsed := NowMs - FStart;
  if not FMeasuring then
  begin
    FText := FReason + ' | estabilizando serial';
    if Elapsed < ECG_CALIBRATION_SETTLE_MS then Exit;
    FStart := NowMs; FMeasuring := True;
    FCount := 0; FHalfCount := 0; FHalfTime := 0;
    Exit; // Exclude the batch establishing the measurement boundary.
  end;
  Inc(FCount, Count);
  if (FHalfTime = 0) and (Elapsed >= ECG_CALIBRATION_MS div 2) then
  begin FHalfTime := Elapsed; FHalfCount := FCount; end;
  if FRate = 0 then
    FText := FReason + Format(' | medindo %.1f / 8 s', [Elapsed / 1000.0]);
  if Elapsed < ECG_CALIBRATION_MS then Exit;
  Estimate := FCount * 1000.0 / Elapsed;
  if (FHalfTime = 0) or (Elapsed <= FHalfTime) then
  begin Restart('Janela incompleta: recalibrando'); Exit; end;
  FirstRate := FHalfCount * 1000.0 / FHalfTime;
  SecondRate := (FCount - FHalfCount) * 1000.0 / (Elapsed - FHalfTime);
  // Long windows tolerate USB bursts; compare halves to reject drifting/stalled input.
  if (Abs(FirstRate - SecondRate) > Estimate * 0.10) or
     ((FRate > 0) and (Abs(Estimate - FRate) > FRate * 0.10)) then
  begin Restart('Taxa instavel: recalibrando'); Exit; end;
  if Estimate < ECG_MIN_DSP_RATE then
  begin Restart(Format('Taxa %.1f Hz insuficiente para DSP (min. 125 Hz)', [Estimate])); Exit; end;
  if FRate = 0 then FRate := Estimate;
  FText := Format('Taxa efetiva estimada: %.2f Hz (janela 8 s)', [FRate]);
  // Continue checking stability without changing the time axis or coefficients.
  FStart := NowMs; FCount := 0; FHalfCount := 0; FHalfTime := 0;
end;
end.
