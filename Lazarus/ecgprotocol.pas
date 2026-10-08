unit ecgprotocol;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  TECGSerialFrame = record
    TimestampUS: Int64;
    ADC: Integer;
    LeadOff, Discontinuity: Boolean;
  end;
  TECGProtocol = class
  private
    FLine: String;
    FDiscard, FHavePrevious, FPendingGap: Boolean;
    FVersion: Integer;
    FPrevious: Int64;
    FTime: Int64;
    function Parse(out Frame: TECGSerialFrame): Boolean;
  public
    function Feed(C: Char; out Frame: TECGSerialFrame): Boolean;
  end;
implementation
function Decimal(const S: String; out V: Int64): Boolean;
var I: Integer;
begin
  Result := False;
  if (Length(S)=0) or (Length(S)>10) then Exit;
  for I := 1 to Length(S) do if not (S[I] in ['0'..'9']) then Exit;
  Result := TryStrToInt64(S,V);
end;
function TECGProtocol.Parse(out Frame: TECGSerialFrame): Boolean;
var P, Q: Integer; Seq, ADC, Lead, Delta, Step: Int64; Tail: String;
begin
  Result := False;
  if FLine = '#START' then
  begin FHavePrevious := False; FPendingGap := True; FVersion := 0; Exit; end;
  if Pos('#ECG,', FLine)=1 then
  begin
    if FLine = '#ECG,VERSION=3,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000' then FVersion := 3
    else if (FLine = '#ECG,VERSION=2,SAMPLE_RATE=500') or (FLine = '#ECG,VERSION=2,SAMPLE_RATE=500,ADC_BITS=10,VREF_MV=5000') then FVersion := 2
    else begin FVersion := 0; FPendingGap := True; end;
    Exit;
  end;
  if (FLine='') or (FLine[1]='#') then Exit;
  FPendingGap := True;
  if FVersion=0 then Exit;
  P := Pos(',',FLine); if P=0 then Exit;
  Tail := Copy(FLine,P+1,Length(FLine)); Q := Pos(',',Tail); if Q=0 then Exit;
  if not Decimal(Copy(FLine,1,P-1),Seq) or not Decimal(Copy(Tail,1,Q-1),ADC)
     or not Decimal(Copy(Tail,Q+1,Length(Tail)),Lead) then Exit;
  if (Seq>4294967295) or (ADC>1023) or (Lead>1) then Exit;
  if FVersion=3 then Step := 1 else Step := 2000;
  Frame.Discontinuity := not FHavePrevious;
  if FHavePrevious then
  begin
    Delta := Seq-FPrevious;
    if Delta < -2147483648 then Delta := Delta+4294967296;
    if Delta<=0 then begin FPendingGap := True; Exit; end;
    if FVersion=3 then Frame.Discontinuity := Delta<>Step
    else Frame.Discontinuity := (Delta<1800) or (Delta>2200);
    if FVersion=3 then FTime := FTime+Delta*2000 else FTime := FTime+Delta;
  end
  else FTime := FTime+2000;
  FPrevious := Seq; FHavePrevious := True;
  Frame.TimestampUS := FTime; Frame.ADC := ADC; Frame.LeadOff := Lead=1;
  FPendingGap := False;
  Result := True;
end;
function TECGProtocol.Feed(C: Char; out Frame: TECGSerialFrame): Boolean;
var HadGap: Boolean;
begin
  Result := False;
  if C=#13 then Exit;
  if C=#10 then
  begin
    HadGap := FPendingGap;
    if not FDiscard then Result := Parse(Frame);
    if Result then Frame.Discontinuity := Frame.Discontinuity or HadGap;
    FLine := ''; FDiscard := False;
  end
  else if not FDiscard then
    if Length(FLine)<160 then FLine := FLine+C
    else begin FDiscard := True; FLine := ''; FPendingGap := True; end;
end;
end.
