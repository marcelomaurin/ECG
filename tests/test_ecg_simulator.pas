program test_ecg_simulator;
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, ecgsource, ecgsimulator, ecgsyntheticdataset, fpjson, jsonparser;

type
  TSignal = array of Double;
  TPeaks = array of Int64;
  TLabels = array of String;
var
  Wave: array[TECGRhythmType] of TSignal;
  Peaks: array[TECGRhythmType] of TPeaks;
  Labels: array[TECGRhythmType] of TLabels;
  R: TECGRhythmType;
  P: TECGWaveParameters;
  Source, Other: TSimulatedECGSource;
  S, T: TECGSample;
  I, J, N, K, LowRate, HighRate: Integer;
  D, MinRR, MaxRR, MeanRR, WidthNormal, WidthSVT, WidthVT: Double;
  CSV: TStringList;
  FS: TFormatSettings;
  OutDir: String;
  Meta: TJSONData;
  LastTime: Int64;
  Buffer: array[0..511] of TECGSample;

procedure Check(Condition: Boolean; const MessageText: String);
begin
  if not Condition then raise Exception.Create(MessageText);
end;

function PeakWidth(Rhythm: TECGRhythmType): Double;
var Center, LeftIdx, RightIdx, StartIdx, EndIdx, Z: Integer; Height: Double;
begin
  Center := Peaks[Rhythm][2] div 2000;
  StartIdx := Center - 40;
  EndIdx := Center + 40;
  for Z := StartIdx to EndIdx do
    if Wave[Rhythm][Z] > Wave[Rhythm][Center] then Center := Z;
  Height := Wave[Rhythm][Center] * 0.5;
  LeftIdx := Center;
  RightIdx := Center;
  while (LeftIdx > StartIdx) and (Wave[Rhythm][LeftIdx] > Height) do Dec(LeftIdx);
  while (RightIdx < EndIdx) and (Wave[Rhythm][RightIdx] > Height) do Inc(RightIdx);
  Result := (RightIdx - LeftIdx) * 2;
end;

begin
  try
    OutDir := ParamStr(1);
    if OutDir = '' then OutDir := 'simulator-test-output';
    ForceDirectories(OutDir);
    FS := DefaultFormatSettings;
    FS.DecimalSeparator := '.';
    for R := Low(TECGRhythmType) to High(TECGRhythmType) do
    begin
      P := GetDefaultWaveParameters(R);
      P.NoiseLevel := 0;
      P.BaselineDrift := 0;
      Source := TSimulatedECGSource.Create(P, 42);
      CSV := TStringList.Create;
      try
        SetLength(Wave[R], 15000); // 30 seconds
        CSV.Add('time_s,signal,raw_adc,r_peak,beat_class,rhythm');
        for I := 0 to High(Wave[R]) do
        begin
          S := Source.ComputeNextSample(999); // irregular wall-time must not affect timebase
          Check(S.TimestampUS = Int64(I) * 2000, 'Timestamp: ' + RhythmTypeToCode(R));
          Check(S.IsSimulated and not S.LeadOff, 'Source flags');
          Check(S.ExpectedRhythm = RhythmTypeToCode(R), 'Rhythm label');
          Check(not IsNan(S.RawValue) and not IsInfinite(S.RawValue), 'Non-finite sample');
          Check((S.RawValue >= 0) and (S.RawValue <= 1023), 'ADC bounds');
          Wave[R][I] := S.FilteredValue;
          if S.IsPeak then
          begin
            K := Length(Peaks[R]);
            SetLength(Peaks[R], K + 1);
            SetLength(Labels[R], K + 1);
            Peaks[R][K] := S.TimestampUS;
            Labels[R][K] := S.ExpectedClass;
          end;
          if I < 5000 then CSV.Add(Format('%.3f,%.6f,%.6f,%d,%s,%s',
            [I / 500.0, S.FilteredValue, S.RawValue, Ord(S.IsPeak), S.ExpectedClass, S.ExpectedRhythm], FS));
        end;
        CSV.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + RhythmDatasetFolder(R) + '.csv');
      finally CSV.Free; Source.Free; end;
      if R = rtVentricularFibrillation then
      begin
        Check(Length(Peaks[R]) = 0, 'VF must not have R markers');
        Check(S.ExpectedClass = 'Q', 'VF unclassified activity');
        D := 0;
        for I := 1000 to 4999 do D := D + Sqr(Wave[R][I] - Wave[R][I-167]);
        Check(Sqrt(D / 4000) > 50, 'VF must not repeat a regular 180 BPM template');
      end
      else
      begin
        Check(Length(Peaks[R]) > 10, 'Missing beats: ' + RhythmTypeToCode(R));
        MinRR := 1e9; MaxRR := 0; MeanRR := 0;
        for I := 1 to High(Peaks[R]) do
        begin
          D := (Peaks[R][I] - Peaks[R][I-1]) / 1000.0;
          MinRR := Min(MinRR, D); MaxRR := Max(MaxRR, D); MeanRR := MeanRR + D;
          Check(D > 200, 'Duplicate R marker');
        end;
        MeanRR := MeanRR / High(Peaks[R]);
        if R = rtAtrialFibrillation then Check(MaxRR - MinRR > 250, 'AF must be irregular');
        if R in [rtSinusBradycardia, rtSinusTachycardia, rtAtrialFlutter,
          rtSupraventricularTachycardia, rtVentricularTachycardia] then
        begin
          Check(MaxRR - MinRR <= 2.1, 'Regular rhythm jitter');
          Check(Abs(60000 / MeanRR - P.HeartRate) < 1, 'Rate mismatch');
        end;
        if R in [rtPVC, rtPAC] then
        begin
          N := 0;
          for I := 1 to High(Peaks[R])-1 do
            if Labels[R][I] <> 'N' then
            begin
              Inc(N);
              D := (Peaks[R][I] - Peaks[R][I-1]) / 1000.0;
              Check(D < 0.75 * 60000/P.HeartRate, 'Ectopic beat is not premature');
              D := (Peaks[R][I+1] - Peaks[R][I]) / 1000.0;
              Check(D > 1.1 * 60000/P.HeartRate, 'Missing post-ectopic pause');
              D := (Peaks[R][I+1] - Peaks[R][I-1]) / 1000.0;
              if R = rtPVC then Check(Abs(D - 2*60000/P.HeartRate) <= 2.1, 'PVC full compensatory pause')
              else Check(D < 1.95*60000/P.HeartRate, 'PAC incomplete pause');
            end;
          Check(N >= 3, 'Not enough ectopic beats');
        end;
      end;
      WriteLn('PASS ', RhythmTypeToCode(R), ': ', Length(Wave[R]), ' samples, ', Length(Peaks[R]), ' R activations');
    end;
    WidthNormal := PeakWidth(rtNormal);
    WidthSVT := PeakWidth(rtSupraventricularTachycardia);
    WidthVT := PeakWidth(rtVentricularTachycardia);
    Check(WidthSVT < WidthNormal, 'SVT must have narrow complexes');
    Check(WidthVT > WidthNormal * 1.5, 'VT must have broad complexes');
    WriteLn('PASS QRS morphology widths: ', WidthSVT:0:1, '/', WidthNormal:0:1, '/', WidthVT:0:1, ' ms (half amplitude)');

    P := GetDefaultWaveParameters(rtAtrialFlutter);
    P.PAmplitude := 0; P.QAmplitude := 0; P.RAmplitude := 0; P.SAmplitude := 0; P.TAmplitude := 0;
    P.NoiseLevel := 0; P.BaselineDrift := 0;
    Source := TSimulatedECGSource.Create(P);
    try
      for I := 0 to 999 do
      begin
        S := Source.ComputeNextSample(0);
        Wave[rtAtrialFlutter][I] := S.FilteredValue;
        if I >= 100 then Check(Abs(S.FilteredValue - Wave[rtAtrialFlutter][I-100]) < 0.0001, 'Flutter 300/min periodicity');
      end;
      Check(Abs(Wave[rtAtrialFlutter][12]) > 10, 'Missing flutter waves');
    finally Source.Free; end;
    WriteLn('PASS flutter 4:1 atrial activity');

    P := GetDefaultWaveParameters(rtAtrialFibrillation);
    Source := TSimulatedECGSource.Create(P, 1234);
    Other := TSimulatedECGSource.Create(P, 1234);
    try
      for I := 0 to 4999 do
      begin
        S := Source.ComputeNextSample(I);
        T := Other.ComputeNextSample(99999);
        Check(S.RawValue = T.RawValue, 'Seed reproducibility');
      end;
      LastTime := S.TimestampUS;
      Source.UpdateParameters(GetDefaultWaveParameters(rtVentricularFibrillation));
      S := Source.ComputeNextSample(0);
      Check(S.TimestampUS = LastTime + 2000, 'Time resets on rhythm change');
      Check((S.ExpectedRhythm = 'VFIB') and not S.IsPeak, 'Stale rhythm after change');
      for R := Low(TECGRhythmType) to High(TECGRhythmType) do
      begin
        GetRhythmRateLimits(R, LowRate, HighRate);
        for J := 0 to 1 do
        begin
          P := GetDefaultWaveParameters(R);
          if J = 0 then P.HeartRate := LowRate else P.HeartRate := HighRate;
          P.Quality := qlPoor; P.NoiseLevel := 0.35; P.BaselineDrift := 0.5; P.PowerLine60Hz := True;
          Source.UpdateParameters(P);
          for I := 1 to 1500 do
          begin
            T := Source.ComputeNextSample(0);
            Check(T.TimestampUS = S.TimestampUS + 2000, 'Rate edge continuity');
            Check((T.RawValue >= 0) and (T.RawValue <= 1023) and not IsNan(T.RawValue), 'Rate edge amplitude');
            S := T;
          end;
        end;
      end;
    finally Source.Free; Other.Free; end;
    WriteLn('PASS reproducibility, all rate limits, noise and rhythm switching');

    Source := TSimulatedECGSource.Create(GetDefaultWaveParameters(rtNormal));
    try
      Source.Start;
      Sleep(300);
      Source.Stop;
      N := Source.ReadAllSamples(Buffer);
      Check(N > 0, 'Worker produced no samples');
      for I := 1 to N-1 do Check(Buffer[I].TimestampUS - Buffer[I-1].TimestampUS = 2000, 'Worker timebase');
    finally Source.Free; end;
    WriteLn('PASS threaded generation');

    DefaultFormatSettings.DecimalSeparator := ',';
    N := TECGDatasetGenerator.GenerateBatch(IncludeTrailingPathDelimiter(OutDir) + 'dataset', 1, 1.0, 500);
    Check(N = 10, 'Dataset missing rhythms');
    CSV := TStringList.Create;
    try
      for R := Low(TECGRhythmType) to High(TECGRhythmType) do
      begin
        CSV.LoadFromFile(IncludeTrailingPathDelimiter(OutDir) + 'dataset' + PathDelim +
          RhythmDatasetFolder(R) + PathDelim + 'ecg_' + RhythmDatasetFolder(R) + '_0001.json');
        Meta := GetJSON(CSV.Text);
        try
          Check(Meta.FindPath('samples_count').AsInteger = 500, 'Dataset sample count');
          Check(Meta.FindPath('rhythm_code').AsString = RhythmTypeToCode(R), 'Dataset rhythm');
          if R = rtVentricularFibrillation then Check(Meta.FindPath('heart_rate').JSONType = jtNull, 'VF BPM must be null');
        finally Meta.Free; end;
      end;
    finally CSV.Free; end;
    WriteLn('PASS dataset: 10 rhythms, JSON valid with comma locale');
    WriteLn('ALL TESTS PASSED');
  except
    on E: Exception do begin WriteLn('FAIL: ', E.Message); Halt(1); end;
  end;
end.
