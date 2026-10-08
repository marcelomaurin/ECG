program test_ecg_acquisition;
{$mode objfpc}{$H+}
uses SysUtils, Math, ecgprotocol, ecgfilters, ecgdsp, ecgtypes, ecgsource, ecgsimulator, ecgdatabase;
var P: TECGProtocol; F: TECGSerialFrame; D: TECGProcessor; R: TECGRecord;
    I, N: Integer; T: Int64; X, V, Sum: Double;
    Filter: TECGBiquad; Src: TSimulatedECGSource; S: TECGSample;
    Database: TECGDatabase; Exam: Int64; Batch: array[0..2] of TECGSample;
    Values: array[0..10] of Double;
procedure Check(B: Boolean; const Msg: String);
begin if not B then raise Exception.Create(Msg); end;
function Line(const L: String): Boolean;
var C: Char;
begin
  Result := False;
  for C in L+#10 do if P.Feed(C,F) then Result := True;
end;
function Gain(Kind: TFilterKind; Cutoff, Hz: Double): Double;
var J: Integer; Y, Energy: Double; B: TECGBiquad;
begin
  B := TECGBiquad.Create(Kind,500,Cutoff, Sqrt(0.5));
  Energy := 0;
  try
    for J := 0 to 29999 do
    begin
      Y := B.Process(Sin(2*Pi*Hz*J/500));
      if J>=20000 then Energy := Energy+Y*Y;
    end;
    Result := Sqrt(Energy/5000);
  finally B.Free; end;
end;
begin
  P := TECGProtocol.Create;
  try
    Check(not Line('0,500,0'), 'Reject unannounced protocol');
    Line('#ECG,VERSION=3,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000');
    Check(Line('4294967294,337,0') and F.Discontinuity, 'First sample');
    T := F.TimestampUS;
    Check(Line('4294967295,340,0') and not F.Discontinuity, 'Consecutive sample');
    Check(Line('0,340,0') and not F.Discontinuity and (F.TimestampUS=T+4000), 'Sequence wrap');
    Check(Line('2,340,0') and F.Discontinuity, 'Lost frame');
    Check(not Line('3,garbage,0'), 'Malformed ADC');
    Check(not Line('3,1024,0'), 'ADC range');
    Check(not Line('3,340,2'), 'Lead flag range');
    Check(not Line('3,340,0,extra'), 'Field count');
    Check(Line('3,340,0') and F.Discontinuity, 'Recovery marked');
    Check(not Line('3,340,0'), 'Duplicate rejected');
    Line(StringOfChar('x',300));
    Check(Line('4,340,1') and F.Discontinuity and F.LeadOff, 'Oversize recovery');
    T := F.TimestampUS; Line('#START');
    Line('#ECG,VERSION=3,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000');
    Check(Line('0,340,0') and F.Discontinuity and (F.TimestampUS>T), 'Board reset');
    Line('#ECG,VERSION=3,SAMPLE_RATE=250,ADC_BITS=10,VREF_MV=5000');
    Check(not Line('1,340,0'), 'Unsupported rate');
  finally P.Free; end;
  P := TECGProtocol.Create;
  try
    Line('#ECG,VERSION=2,SAMPLE_RATE=500'); Line('4294966000,333,0'); T := F.TimestampUS;
    Check(Line('704,333,0') and not F.Discontinuity and (F.TimestampUS=T+2000), 'Legacy microsecond wrap');
  finally P.Free; end;
  Check(Abs(Gain(fkHighPass,0.5,0.5)-Sqrt(0.5))<0.01, 'HP actual 0.5 Hz cutoff');
  Check(Gain(fkHighPass,0.5,0.05)<0.02, 'Baseline attenuation');
  Check(Abs(Gain(fkLowPass,40,40)-Sqrt(0.5))<0.01, 'LP 40 Hz cutoff');
  Check(Gain(fkLowPass,40,150)<0.05, 'High-frequency attenuation');
  Filter := TECGBiquad.Create(fkNotch,500,60,30); Sum := 0;
  for I:=0 to 9999 do
  begin V := Filter.Process(Sin(2*Pi*60*I/500)); if I>5000 then Sum:=Sum+Sqr(V); end;
  Check(Sqrt(Sum/5000)<0.001,'60 Hz rejection'); Filter.Free;
  D := TECGProcessor.Create(500);
  try
    for I:=0 to 1999 do R:=D.ProcessSample(337,I*2,False);
    Check(Abs(R.FilteredValue)<1e-8,'DC initialization without spike');
    Check(D.CurrentBPM=0,'DC must not create BPM');
    D.Reset; Src := TSimulatedECGSource.Create(GetDefaultWaveParameters(rtNormal));
    try
      for I:=0 to 9999 do
      begin S:=Src.ComputeNextSample(0); R:=D.ProcessSample(S.RawValue,S.TimestampUS div 1000,False); end;
    finally Src.Free; end;
    Check(Abs(D.CurrentBPM-72)<5,'Normal rhythm BPM');
    R:=D.ProcessSample(337,20000,True);
    Check((D.CurrentBPM=0) and not D.SignalValid, 'Lead-off clears stale BPM');
    R:=D.ProcessSample(337,20002,False);
    Check(not D.SignalValid,'Reconnect settling');
    R:=D.ProcessSample(337,23000,False);
    Check(not D.SignalValid,'Gap restarts settling');
    R:=D.ProcessSample(1023,23002,False);
    Check(not D.SignalValid,'ADC saturation');
  finally D.Free; end;
  if ParamStr(1)<>'' then
  begin
    Database:=TECGDatabase.Create(ParamStr(1));
    try
      Database.Open; Check(Database.IsOpen,'SQLite open / migration');
      Exam:=Database.StartExam('TEST','acquisition validation');
      for I:=0 to 2 do
      begin Batch[I]:=Default(TECGSample); Batch[I].TimestampUS:=I*2000; Batch[I].RawValue:=337; end;
      Database.InsertSamplesBatch(Exam,Batch,3);
      Check(Database.LoadExamSamples(Exam,Values,N) and (N=3),'Valid recording reload');
      Batch[0].Discontinuity:=True; Database.InsertSamplesBatch(Exam,Batch,1);
      Check(not Database.LoadExamSamples(Exam,Values,N) and (N=0),'Refuse gap for analysis');
    finally Database.Free; end;
  end;
  WriteLn('PASS: protocol, wraps, gaps, filters, BPM recovery and recording quality');
end.
