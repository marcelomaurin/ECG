unit ecgdsp;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  soundfilters, numps, ecgtypes;

type
  { Filtro passa-altas de 1a ordem sub-hertz independente para remocao de baseline wander }
  TECGHighPass05 = class
  private
    FSampleRate: Double;
    FCutoffHz: Double;
    FAlpha: Double;
    FLastInput: Double;
    FLastOutput: Double;
    procedure Recalculate;
  public
    constructor Create(ASampleRate: Double = 500.0; ACutoffHz: Double = 0.5);
    procedure Reset;
    function Process(const AInput: Double): Double;
    property SampleRate: Double read FSampleRate write FSampleRate;
    property CutoffHz: Double read FCutoffHz write FCutoffHz;
  end;

  { TECGProcessor }
  TECGProcessor = class
  private
    FHighPass: TECGHighPass05;
    FLowPass: TLowPassFilter;
    FBpmAverager: TAverageFilter;
    FNumPS: TNumPS;

    FEnableHighPass: Boolean;
    FEnableLowPass: Boolean;
    FEnableBpmAverage: Boolean;

    FSampleRate: Double;
    FLastPeakTimeMs: Int64;
    FLastPeakVal: Double;
    FThreshold: Double;
    FBelowThreshold: Boolean;
    FCurrentBPM: Integer;
    FInstantBPM: Double;
    FLastRRIntervalMs: Double;
    FRRHistory: array[0..15] of Double;
    FRRIndex: Integer;
    FRRCount: Integer;

    FRecentBuffer: array[0..255] of Double;
    FRecentIdx: Integer;
    FRecentFull: Boolean;

    FWasLeadsOff: Boolean;

  public
    constructor Create(ASampleRate: Double = 100.0);
    destructor Destroy; override;

    procedure Reset;
    function ProcessSample(const ARawValue: Double; const ATimestampMs: Int64; const ALeadsOff: Boolean): TECGRecord;
    function GetCurrentStats: TECGStats;

    property EnableHighPass: Boolean read FEnableHighPass write FEnableHighPass;
    property EnableLowPass: Boolean read FEnableLowPass write FEnableLowPass;
    property EnableBpmAverage: Boolean read FEnableBpmAverage write FEnableBpmAverage;
    property SampleRate: Double read FSampleRate write FSampleRate;
    property CurrentBPM: Integer read FCurrentBPM;
    property Threshold: Double read FThreshold write FThreshold;
  end;

implementation

{ TECGHighPass05 }

constructor TECGHighPass05.Create(ASampleRate: Double; ACutoffHz: Double);
begin
  inherited Create;
  FSampleRate := ASampleRate;
  if FSampleRate < 10.0 then FSampleRate := 500.0;
  FCutoffHz := ACutoffHz;
  if FCutoffHz < 0.05 then FCutoffHz := 0.5;
  Recalculate;
  Reset;
end;

procedure TECGHighPass05.Recalculate;
var
  RC, dt: Double;
begin
  if (FSampleRate > 0) and (FCutoffHz > 0) then
  begin
    RC := 1.0 / (2.0 * Pi * FCutoffHz);
    dt := 1.0 / FSampleRate;
    FAlpha := RC / (RC + dt);
  end
  else
    FAlpha := 0.0;
end;

procedure TECGHighPass05.Reset;
begin
  FLastInput := 0.0;
  FLastOutput := 0.0;
end;

function TECGHighPass05.Process(const AInput: Double): Double;
begin
  FLastOutput := FAlpha * FLastOutput + FAlpha * (AInput - FLastInput);
  FLastInput := AInput;
  Result := FLastOutput;
end;

{ TECGProcessor }

constructor TECGProcessor.Create(ASampleRate: Double = 100.0);
begin
  inherited Create;
  FSampleRate := ASampleRate;
  if FSampleRate < 10.0 then FSampleRate := 500.0;

  FHighPass := TECGHighPass05.Create(FSampleRate, 0.5); // Elimina oscilacao da linha de base (<0.5 Hz)

  FLowPass := TLowPassFilter.Create(nil);
  FLowPass.SampleRate := FSampleRate;
  FLowPass.CutoffFrequency := 40.0; // Elimina ruidos de alta frequencia (>40 Hz)

  FBpmAverager := TAverageFilter.Create(nil);
  FBpmAverager.WindowSize := 8; // Media movel curta para resposta rapida

  FNumPS := TNumPS.Create(nil);

  FEnableHighPass := True;
  FEnableLowPass := True;
  FEnableBpmAverage := True;

  Reset;
end;

destructor TECGProcessor.Destroy;
begin
  FHighPass.Free;
  FLowPass.Free;
  FBpmAverager.Free;
  FNumPS.Free;
  inherited Destroy;
end;

procedure TECGProcessor.Reset;
begin
  FHighPass.Reset;
  FLowPass.Reset;
  FBpmAverager.Reset;

  FLastPeakTimeMs := 0;
  FLastPeakVal := 0.0;
  FThreshold := 80.0;
  FBelowThreshold := True;
  FCurrentBPM := 0;
  FInstantBPM := 0.0;
  FLastRRIntervalMs := 0.0;
  FRRIndex := 0;
  FRRCount := 0;
  FillChar(FRRHistory, SizeOf(FRRHistory), 0);

  FRecentIdx := 0;
  FRecentFull := False;
  FillChar(FRecentBuffer, SizeOf(FRecentBuffer), 0);
  FWasLeadsOff := False;
end;

function TECGProcessor.ProcessSample(const ARawValue: Double; const ATimestampMs: Int64; const ALeadsOff: Boolean): TECGRecord;
var
  Filtered: Double;
  TimeDiff: Int64;
  CalculatedBPM: Double;
begin
  Result.RawValue := ARawValue;
  Result.TimestampMs := ATimestampMs;
  Result.LeadsOff := ALeadsOff;
  Result.IsPeak := False;

  if ALeadsOff then
  begin
    Result.FilteredValue := 0.0;
    FCurrentBPM := 0;
    FInstantBPM := 0.0;
    FLastRRIntervalMs := 0.0;
    FRRCount := 0;
    FWasLeadsOff := True;
    Exit;
  end;

  // Ao reconectar apos perda de eletrodo, reinicializa filtros e detector para evitar transiente falso
  if FWasLeadsOff then
  begin
    FHighPass.Reset;
    FLowPass.Reset;
    FBpmAverager.Reset;
    FLastPeakTimeMs := ATimestampMs;
    FBelowThreshold := True;
    FWasLeadsOff := False;
  end;

  Filtered := ARawValue;

  // 1. Filtro Passa-Altas com corte em 0.5 Hz (remove drift / baseline wander)
  if FEnableHighPass then
    Filtered := FHighPass.Process(Filtered);

  // 2. Filtro Passa-Baixas com corte em 40 Hz (remove ruidos de 60Hz e contracoes musculares)
  if FEnableLowPass then
    Filtered := FLowPass.Process(Filtered);

  Result.FilteredValue := Filtered;

  // Armazena no buffer recente para estatisticas com TNumPS
  FRecentBuffer[FRecentIdx] := Filtered;
  Inc(FRecentIdx);
  if FRecentIdx > High(FRecentBuffer) then
  begin
    FRecentIdx := 0;
    FRecentFull := True;
  end;

  // 3. Deteccao de Complexo QRS / Pico R
  // Periodo refratario: no minimo 250ms entre batimentos (limite superior fisiologico ~240 bpm)
  TimeDiff := ATimestampMs - FLastPeakTimeMs;

  if FBelowThreshold and (Filtered > FThreshold) and (TimeDiff > 250) then
  begin
    Result.IsPeak := True;
    FBelowThreshold := False;
    FLastPeakVal := Filtered;

    if FLastPeakTimeMs > 0 then
    begin
      FLastRRIntervalMs := TimeDiff;
      CalculatedBPM := 60000.0 / TimeDiff;

      // Filtra batimentos fisiologicamente validos (30 a 240 bpm)
      if (CalculatedBPM >= 30.0) and (CalculatedBPM <= 240.0) then
      begin
        FInstantBPM := CalculatedBPM;

        if FEnableBpmAverage then
          FCurrentBPM := Round(FBpmAverager.Process(CalculatedBPM))
        else
          FCurrentBPM := Round(CalculatedBPM);

        FRRHistory[FRRIndex] := FLastRRIntervalMs;
        FRRIndex := (FRRIndex + 1) mod 16;
        if FRRCount < 16 then Inc(FRRCount);
      end;
    end;

    FLastPeakTimeMs := ATimestampMs;

    // Atualizacao adaptativa do limiar: ajusta suavemente ao pico detectado
    FThreshold := (FThreshold * 0.85) + (Filtered * 0.45 * 0.15);
    if FThreshold < 30.0 then FThreshold := 30.0;
    if FThreshold > 400.0 then FThreshold := 400.0;
  end
  else if not FBelowThreshold and (Filtered < (FThreshold * 0.6)) then
  begin
    FBelowThreshold := True;
  end;

  // Se passou mais de 3 segundos sem batimento, o BPM decai
  if (FLastPeakTimeMs > 0) and ((ATimestampMs - FLastPeakTimeMs) > 3000) then
  begin
    FCurrentBPM := 0;
    FInstantBPM := 0.0;
    FThreshold := Max(30.0, FThreshold * 0.98);
  end;
end;

function TECGProcessor.GetCurrentStats: TECGStats;
var
  DataSize, I: Integer;
  Arr: TArray;
begin
  Result.BPM := FCurrentBPM;
  Result.InstantBPM := FInstantBPM;
  Result.RRIntervalMs := FLastRRIntervalMs;
  Result.RRStdDev := 0.0;
  Result.MinVal := 0.0;
  Result.MaxVal := 0.0;
  Result.MeanVal := 0.0;
  Result.Amplitude := 0.0;

  if FRecentFull then
    DataSize := Length(FRecentBuffer)
  else
    DataSize := FRecentIdx;

  if DataSize > 1 then
  begin
    SetLength(Arr, DataSize);
    for I := 0 to DataSize - 1 do
      Arr[I] := FRecentBuffer[I];

    Result.MinVal := FNumPS.Min(Arr);
    Result.MaxVal := FNumPS.Max(Arr);
    Result.MeanVal := FNumPS.Mean(Arr);
    Result.Amplitude := Result.MaxVal - Result.MinVal;
  end;

  if FRRCount > 2 then
  begin
    SetLength(Arr, FRRCount);
    for I := 0 to FRRCount - 1 do
      Arr[I] := FRRHistory[I];
    Result.RRStdDev := FNumPS.Std(Arr);
  end;

  if FCurrentBPM = 0 then
  begin
    Result.Status := hsDisconnected;
    Result.StatusText := 'Aguardando Sinal / Leads Off';
  end
  else if FCurrentBPM < 60 then
  begin
    Result.Status := hsBradycardia;
    Result.StatusText := 'Bradicardia';
  end
  else if FCurrentBPM > 100 then
  begin
    Result.Status := hsTachycardia;
    Result.StatusText := 'Taquicardia';
  end
  else
  begin
    Result.Status := hsNormal;
    Result.StatusText := 'Ritmo Normal';
  end;
end;

end.
