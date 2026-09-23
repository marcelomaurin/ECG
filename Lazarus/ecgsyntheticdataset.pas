unit ecgsyntheticdataset;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Math,
  ecgsource, ecgsimulator;

type
  { TECGDatasetGenerator }
  TECGDatasetGenerator = class
  public
    class function GenerateBatch(
      const AOutputDir: String;
      const ACountPerClass: Integer = 20;
      const ADurationSec: Double = 10.0;
      const ASampleRate: Double = 500.0
    ): Integer;
  end;

implementation

class function TECGDatasetGenerator.GenerateBatch(
  const AOutputDir: String;
  const ACountPerClass: Integer;
  const ADurationSec: Double;
  const ASampleRate: Double
): Integer;
var
  Rhythms: array[0..5] of TECGRhythmType = (
    rtNormal, rtAtrialFibrillation, rtPVC, rtPAC, rtSinusTachycardia, rtSinusBradycardia
  );
  Folders: array[0..5] of String = (
    'normal', 'afib', 'pvc', 'pac', 'tachycardia', 'bradycardia'
  );
  R, I, S, TotalSamples: Integer;
  TargetDir, BaseName, CsvPath, JsonPath: String;
  Params: TECGWaveParameters;
  Source: TSimulatedECGSource;
  Sample: TECGSample;
  CsvLines, JsonLines: TStringList;
  StartTimeUS: Int64;
begin
  Result := 0;
  TotalSamples := Round(ADurationSec * ASampleRate);

  for R := 0 to High(Rhythms) do
  begin
    TargetDir := AOutputDir + PathDelim + Folders[R];
    ForceDirectories(TargetDir);

    for I := 1 to ACountPerClass do
    begin
      Params := GetDefaultWaveParameters(Rhythms[R]);
      // Variações aleatórias naturais para robustez do dataset
      Params.HeartRate := Params.HeartRate + (Random * 12.0 - 6.0);
      Params.NoiseLevel := 0.02 + (Random * 0.08);
      Params.BaselineDrift := 0.05 + (Random * 0.20);
      Params.PowerLine60Hz := (Random > 0.5);

      Source := TSimulatedECGSource.Create(Params);
      CsvLines := TStringList.Create;
      JsonLines := TStringList.Create;
      try
        BaseName := Format('ecg_%s_%04d', [Folders[R], I]);
        CsvPath := TargetDir + PathDelim + BaseName + '.csv';
        JsonPath := TargetDir + PathDelim + BaseName + '.json';

        CsvLines.Add('timestamp_us;raw_adc;filtered_val;lead_off;expected_class');

        StartTimeUS := GetTickCount64 * 1000;
        for S := 0 to TotalSamples - 1 do
        begin
          Sample := Source.ComputeNextSample(StartTimeUS div 1000 + Round(S * (1000.0 / ASampleRate)));
          CsvLines.Add(Format('%d;%.2f;%.2f;%s;%s', [
            Sample.TimestampUS,
            Sample.RawValue,
            Sample.FilteredValue,
            BoolToStr(Sample.LeadOff, '1', '0'),
            Sample.ExpectedClass
          ]));
        end;

        CsvLines.SaveToFile(CsvPath);

        JsonLines.Add('{');
        JsonLines.Add('  "source": "Maurinsoft ECG Simulator",');
        JsonLines.Add('  "sample_rate": ' + IntToStr(Round(ASampleRate)) + ',');
        JsonLines.Add('  "duration_seconds": ' + FormatFloat('0.0', ADurationSec) + ',');
        JsonLines.Add('  "rhythm_type": "' + RhythmTypeToString(Rhythms[R]) + '",');
        JsonLines.Add('  "expected_class": "' + RhythmTypeToCode(Rhythms[R]) + '",');
        JsonLines.Add('  "heart_rate": ' + FormatFloat('0.0', Params.HeartRate) + ',');
        JsonLines.Add('  "noise_level": ' + FormatFloat('0.000', Params.NoiseLevel) + ',');
        JsonLines.Add('  "baseline_drift": ' + FormatFloat('0.000', Params.BaselineDrift) + ',');
        JsonLines.Add('  "powerline_60hz": ' + LowerCase(BoolToStr(Params.PowerLine60Hz, 'true', 'false')) + ',');
        JsonLines.Add('  "samples_count": ' + IntToStr(TotalSamples));
        JsonLines.Add('}');
        JsonLines.SaveToFile(JsonPath);

        Inc(Result);
      finally
        JsonLines.Free;
        CsvLines.Free;
        Source.Free;
      end;
    end;
  end;
end;

end.
