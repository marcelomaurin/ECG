program test_ecg_calibration;
{$mode objfpc}{$H+}
uses SysUtils, Math, ecgcalibration, ecgsource, ecgdsp, ecgtypes, ecgfilters;
var
  C: TECGRateCalibration;
  Source: TSerialECGSource;
  S, Previous: TECGSample;
  D: TECGProcessor;
  B: TECGBiquad;
  Clock: TECGSampleClock;
  I, J, N: Integer;
  T, Origin: Int64;
  Rate, Energy, Y: Double;
  R: TECGRecord;
procedure Check(Value: Boolean; const Msg: String);
begin if not Value then raise Exception.Create(Msg); end;
procedure Feed(const Text: String; Tick: QWord);
var Bytes: array of Byte; K: Integer;
begin
  SetLength(Bytes, Length(Text));
  for K := 1 to Length(Text) do Bytes[K-1] := Ord(Text[K]);
  Check(Length(Bytes)<=256, 'Test batch fits real serial buffer');
  Source.ReceiveBytes(Bytes, Length(Bytes), Tick);
end;
function ADCs(Count: Integer): String;
var K: Integer;
begin Result := ''; for K := 1 to Count do Result := Result+'512'+#13#10; end;
begin
  Previous := Default(TECGSample);
  C := TECGRateCalibration.Create;
  try
    // Monotonic origin well beyond 32-bit tick rollover, fractional rate.
    Origin := Int64(High(LongWord))+123456;
    C.Reset;
    for I := 0 to 113 do C.Observe(Origin+I*80,15,False,False);
    Check(Abs(C.Rate-187.5)<0.001, 'Fractional rate across tick rollover');
    C.Observe(Origin+12000,0,False,False);
    Check((C.Rate=0) and (Pos('Sem dados',C.StatusText)>0), 'Silence invalidates rate');
    C.Reset;
    for I := 0 to 90 do
    begin
      if I<=50 then N:=20 else N:=30;
      C.Observe(I*100,N,False,False);
    end;
    Check((C.Rate=0) and (Pos('instavel',C.StatusText)>0), 'Unequal halves rejected');
    C.Reset;
    for I := 0 to 90 do C.Observe(I*100,10,False,False);
    Check((C.Rate=0) and (Pos('insuficiente',C.StatusText)>0), 'Low rate does not configure invalid DSP');
    C.Reset;
    for I := 0 to 90 do C.Observe(I*100,20,False,False);
    Check(Abs(C.Rate-200)<0.001,'Stable calibration');
    for I := 91 to 170 do C.Observe(I*100,28,False,False);
    Check((C.Rate=0) and (Pos('instavel',C.StatusText)>0), 'Ongoing rate drift warning');
  finally C.Free; end;

  Source := TSerialECGSource.Create('TEST');
  try
    Check(Source.GetSampleRate=0,'No nominal rate before calibration');
    // Startup backlog must not bias the measurement; later bursts are 200 Hz.
    Feed(ADCs(50),0);
    for I := 1 to 35 do
    begin
      Feed(ADCs(50),I*250);
      Check(not Source.ReadSample(S),'No calibration samples published');
    end;
    Feed(ADCs(50),9000);
    Check(Abs(Source.GetSampleRate-200)<0.001,'Burst rate measured');
    Check(not Source.ReadSample(S),'Completion batch stays outside DSP');
    Feed(ADCs(50),9250);
    N:=0;
    while Source.ReadSample(S) do
    begin
      Check(S.SampleRateHz=200,'Rate travels with queued sample');
      if N=0 then Check(S.Discontinuity,'First calibrated sample resets DSP')
      else Check((S.TimestampUS-Previous.TimestampUS=5000) and not S.Discontinuity,
        'Bursts have uniform calibrated timestamps');
      Previous:=S; Inc(N);
    end;
    Check(N=50,'All burst samples retained');
    // Partial lines and CRLF must count exactly once. Invalid lines are not ADCs.
    Feed('51',9300); Feed('2'+#13,9300); Feed(#10,9300);
    Check(Source.ReadSample(S) and (S.RawValue=512),'Split CRLF frame');
    Feed('bad'+#10+'1024'+#10+ADCs(1),9350);
    Check((Source.GetSampleRate=0) and not Source.ReadSample(S),'Malformed ADC invalidates window');
    for I:=0 to 90 do Feed(ADCs(20),9500+I*100);
    Check(Source.GetSampleRate=200,'Recovery recalibrates');
    Feed(ADCs(20),18600);
    Feed('!'+#13#10+ADCs(10),18700);
    Check((Source.GetSampleRate=0) and not Source.ReadSample(S),'Lead-off flushes stale queue');
    Check(Pos('Eletrodos',Source.GetDescription)>0,'Lead-off visible in UI status');
    // Shorter ! frames have a different serial throughput; never count them.
    for I:=1 to 40 do Feed('!'+#10,18700+I*100);
    Check(Source.GetSampleRate=0,'Lead-off cannot calibrate');
    for I:=0 to 90 do Feed(ADCs(16),23000+I*100);
    Check(Abs(Source.GetSampleRate-160)<0.001,'New rate after electrodes reconnect');
    Feed(ADCs(16),32100);
    Source.ReceiveBytes([],0,34000);
    Check((Source.GetSampleRate=0) and not Source.ReadSample(S),'Read timeouts invalidate calibrated source');
  finally Source.Free; end;
  Source:=TSerialECGSource.Create('TEST');
  try
    Feed('#ECG,VERSION=3,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000'+#10,0);
    Feed('0,512,0'+#10+'1,512,0'+#10,10);
    Check(Source.GetSampleRate=500,'Timestamp protocol rate preserved');
    Check(Source.ReadSample(Previous) and Source.ReadSample(S) and
      (S.TimestampUS-Previous.TimestampUS=2000),'Timestamp protocol time preserved');
  finally Source.Free; end;
  Clock:=TECGSampleClock.Create;
  try
    Clock.Start(123456,187.5);
    Origin:=Clock.Next;
    for I:=1 to 18750 do T:=Clock.Next;
    Check(T-Origin=100000000,'Fractional sample clock does not accumulate period rounding');
  finally Clock.Free; end;
  // Verify actual biquad frequency response and QRS timing at measured rates.
  for J:=0 to 2 do
  begin
    case J of 0: Rate:=160; 1: Rate:=187.5; else Rate:=200; end;
    B:=TECGBiquad.Create(fkLowPass,Rate,40,Sqrt(0.5)); Energy:=0;
    try
      for I:=0 to 9999 do
      begin
        Y:=B.Process(Sin(2*Pi*40*I/Rate));
        if I>=5000 then Energy:=Energy+Y*Y;
      end;
      Check(Abs(Sqrt(Energy/2500)-Sqrt(0.5))<0.01,'Measured-rate LP cutoff');
    finally B.Free; end;
    B:=TECGBiquad.Create(fkHighPass,Rate,0.5,Sqrt(0.5)); Energy:=0;
    try
      for I:=0 to 29999 do
      begin
        Y:=B.Process(Sin(2*Pi*0.5*I/Rate));
        if I>=20000 then Energy:=Energy+Y*Y;
      end;
      Check(Abs(Sqrt(Energy/5000)-Sqrt(0.5))<0.02,'Measured-rate HP cutoff');
    finally B.Free; end;
    B:=TECGBiquad.Create(fkNotch,Rate,60,30); Energy:=0;
    try
      for I:=0 to 9999 do
      begin
        Y:=B.Process(Sin(2*Pi*60*I/Rate));
        if I>=5000 then Energy:=Energy+Y*Y;
      end;
      Check(Sqrt(Energy/5000)<0.001,'Measured-rate 60 Hz notch');
    finally B.Free; end;
    D:=TECGProcessor.Create(Rate);
    try
      for I:=0 to Round(Rate*20) do
      begin
        T:=Round(I*1000/Rate);
        Y:=337+250*Exp(-Sqr((Frac(T/1000.0)-0.35)/0.018));
        R:=D.ProcessSample(Y,T,False);
      end;
      Check(D.SignalValid and (Abs(D.CurrentBPM-60)<=1),'Measured-rate BPM and settling');
    finally D.Free; end;
  end;
  WriteLn('PASS: calibration, fractional rates, bursts, partial frames, lead-off, silence, drift, DSP and timestamp protocol');
end.
