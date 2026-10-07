unit ecgsyntheticdataset;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, fpjson, ecgsource, ecgsimulator;

type
  TECGDatasetGenerator = class
  public
    class function GenerateBatch(const AOutputDir: String;
      const ACountPerClass: Integer = 20; const ADurationSec: Double = 10.0;
      const ASampleRate: Double = 500.0): Integer;
  end;

implementation

class function TECGDatasetGenerator.GenerateBatch(const AOutputDir: String;
  const ACountPerClass: Integer; const ADurationSec: Double; const ASampleRate: Double): Integer;
var
  R, I, S, TotalSamples, MinRate, MaxRate: Integer;
  TargetDir, BaseName: String;
  Params: TECGWaveParameters;
  Source: TSimulatedECGSource;
  Sample: TECGSample;
  Lines: TStringList;
  Meta: TJSONObject;
  FS: TFormatSettings;
  Seed: LongWord;
begin
  if ASampleRate <> ECG_SAMPLE_RATE then
    raise EArgumentException.Create('O simulador gera amostras a 500 Hz.');
  if (ACountPerClass < 1) or (ADurationSec <= 0) then
    raise EArgumentException.Create('Quantidade e duracao devem ser positivas.');
  Result := 0;
  TotalSamples := Round(ADurationSec * ECG_SAMPLE_RATE);
  if TotalSamples < 1 then raise EArgumentException.Create('Duracao inferior a uma amostra.');
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FS.ThousandSeparator := #0;
  for R := Low(ECG_RHYTHMS) to High(ECG_RHYTHMS) do
  begin
    TargetDir := IncludeTrailingPathDelimiter(AOutputDir) + RhythmDatasetFolder(ECG_RHYTHMS[R]);
    if not ForceDirectories(TargetDir) then raise EInOutError.Create('Nao foi possivel criar ' + TargetDir);
    for I := 1 to ACountPerClass do
    begin
      Params := GetDefaultWaveParameters(ECG_RHYTHMS[R]);
      GetRhythmRateLimits(Params.RhythmType, MinRate, MaxRate);
      Params.HeartRate := EnsureRange(Params.HeartRate + (I mod 7 - 3) * 2.0, Double(MinRate), Double(MaxRate));
      Params.NoiseLevel := 0.02 + (I mod 5) * 0.02;
      Params.BaselineDrift := 0.05 + (I mod 5) * 0.04;
      Params.PowerLine60Hz := Odd(I);
      Seed := 1 + R * 100000 + I;
      Source := TSimulatedECGSource.Create(Params, Seed);
      Lines := TStringList.Create;
      Meta := TJSONObject.Create;
      try
        BaseName := IncludeTrailingPathDelimiter(TargetDir) + Format('ecg_%s_%.4d', [RhythmDatasetFolder(Params.RhythmType), I]);
        Lines.Add('timestamp_us;raw_adc;filtered_val;lead_off;expected_class;expected_rhythm;r_peak');
        for S := 0 to TotalSamples - 1 do
        begin
          Sample := Source.ComputeNextSample(0);
          Lines.Add(Format('%d;%.6f;%.6f;%d;%s;%s;%d', [Sample.TimestampUS,
            Sample.RawValue, Sample.FilteredValue, Ord(Sample.LeadOff),
            Sample.ExpectedClass, Sample.ExpectedRhythm, Ord(Sample.IsPeak)], FS));
        end;
        Lines.SaveToFile(BaseName + '.csv');
        Meta.Add('source', 'Maurinsoft ECG Simulator');
        Meta.Add('schema_version', 2);
        Meta.Add('is_simulated', True);
        Meta.Add('sample_rate', ECG_SAMPLE_RATE);
        Meta.Add('duration_seconds', TotalSamples / Double(ECG_SAMPLE_RATE));
        Meta.Add('rhythm_type', RhythmTypeToString(Params.RhythmType));
        Meta.Add('rhythm_code', RhythmTypeToCode(Params.RhythmType));
        Meta.Add('beat_class_semantics', 'N/S/V/Q synthetic beat labels; rhythm_code identifies the rhythm');
        Meta.Add('filtered_val_semantics', 'Clean synthetic reference before application DSP');
        if Params.RhythmType = rtVentricularFibrillation then Meta.Add('heart_rate', TJSONNull.Create)
        else Meta.Add('heart_rate', Params.HeartRate);
        if Params.RhythmType = rtAtrialFlutter then
        begin
          Meta.Add('av_conduction_ratio', 4);
          Meta.Add('atrial_rate', Params.HeartRate * 4);
        end;
        Meta.Add('noise_level', Params.NoiseLevel);
        Meta.Add('baseline_drift', Params.BaselineDrift);
        Meta.Add('powerline_60hz', Params.PowerLine60Hz);
        Meta.Add('seed', Int64(Seed));
        Meta.Add('samples_count', TotalSamples);
        Lines.Text := Meta.FormatJSON;
        Lines.SaveToFile(BaseName + '.json');
        Inc(Result);
      finally
        Meta.Free;
        Lines.Free;
        Source.Free;
      end;
    end;
  end;
end;

end.
