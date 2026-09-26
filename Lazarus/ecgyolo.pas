unit ecgyolo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Math, Process, fpjson, jsonparser;

type
  { TYOLO1DEvent }
  PYOLO1DEvent = ^TYOLO1DEvent;
  TYOLO1DEvent = record
    StartSec: Double;
    EndSec: Double;
    DurationMs: Double;
    ClassId: Integer;
    ClassCode: String;
    ClassName: String;
    Confidence: Double;
    Color: TColor;
  end;

  { TYOLO1DSummary }
  TYOLO1DSummary = record
    TotalEvents: Integer;
    NormalCount: Integer;
    PVCCount: Integer;
    SupraCount: Integer;
    FusionCount: Integer;
    UnknownCount: Integer;
    ArrhythmiaPct: Double;
  end;

  { TYOLO1DDetector }
  TYOLO1DDetector = class
  public
    class function DetectEvents(const ASamples: array of Double; ACount: Integer; ASampleRate: Double = 500.0): TFPList;
    class function CalculateSummary(AEvents: TFPList): TYOLO1DSummary;
    class procedure FreeEventsList(var AList: TFPList);
    class function HexToColor(const AHex: String): TColor;
  end;

implementation

class function TYOLO1DDetector.HexToColor(const AHex: String): TColor;
var
  CleanHex: String;
  R, G, B: Integer;
begin
  CleanHex := StringReplace(AHex, '#', '', [rfReplaceAll]);
  if Length(CleanHex) = 6 then
  begin
    R := StrToIntDef('$' + Copy(CleanHex, 1, 2), 0);
    G := StrToIntDef('$' + Copy(CleanHex, 3, 2), 255);
    B := StrToIntDef('$' + Copy(CleanHex, 5, 2), 0);
    Result := RGBToColor(R, G, B);
  end
  else
    Result := clLime;
end;

class procedure TYOLO1DDetector.FreeEventsList(var AList: TFPList);
var
  I: Integer;
  P: PYOLO1DEvent;
begin
  if AList = nil then Exit;
  for I := 0 to AList.Count - 1 do
  begin
    P := PYOLO1DEvent(AList[I]);
    Dispose(P);
  end;
  FreeAndNil(AList);
end;

class function TYOLO1DDetector.DetectEvents(const ASamples: array of Double; ACount: Integer; ASampleRate: Double): TFPList;
var
  I, J, MinDist, WindowLen, PeakIdx, MaxWin: Integer;
  TotalDurationSec: Double;
  Diff: array of Double;
  Integrated: array of Double;
  Sum, MeanVal, StdVal, Thresh: Double;
  Peaks: array of Integer;
  PeakCount: Integer;
  P: PYOLO1DEvent;
  CenterSec, DurSec, DurMs, StartSec, EndSec: Double;
  QOnsetIdx, SOffsetIdx: Integer;
  PeakAmp, BaselineThresh: Double;
  CurrRR, MeanRR, SumRR: Double;
  RRCountValid: Integer;
  IsPremature, IsWidened, IsPVC, IsPAC: Boolean;
begin
  Result := TFPList.Create;
  if ACount < 200 then Exit;

  TotalDurationSec := ACount / ASampleRate;
  SetLength(Diff, ACount - 1);
  for I := 0 to ACount - 2 do
    Diff[I] := Sqr(ASamples[I + 1] - ASamples[I]);

  // Integrador de janela movel (~80 ms)
  WindowLen := Max(1, Round(ASampleRate * 0.08));
  SetLength(Integrated, Length(Diff));
  Sum := 0.0;
  for I := 0 to High(Diff) do
  begin
    Sum := Sum + Diff[I];
    if I >= WindowLen then
      Sum := Sum - Diff[I - WindowLen];
    Integrated[I] := Sum / WindowLen;
  end;

  // Calculo de media e desvio padrao
  MeanVal := 0.0;
  for I := 0 to High(Integrated) do
    MeanVal := MeanVal + Integrated[I];
  MeanVal := MeanVal / Length(Integrated);

  StdVal := 0.0;
  for I := 0 to High(Integrated) do
    StdVal := StdVal + Sqr(Integrated[I] - MeanVal);
  StdVal := Sqrt(StdVal / Length(Integrated));

  Thresh := MeanVal + 1.2 * StdVal;
  MinDist := Round(ASampleRate * 0.24); // 240ms periodo refratario

  SetLength(Peaks, 200);
  PeakCount := 0;

  I := 0;
  while I < Length(Integrated) do
  begin
    if Integrated[I] > Thresh then
    begin
      MaxWin := Min(ACount - 1, I + Round(ASampleRate * 0.12));
      PeakIdx := I;
      for PeakIdx := I to MaxWin do
      begin
        if ASamples[PeakIdx] > ASamples[I] then
          I := PeakIdx;
      end;

      if PeakCount < Length(Peaks) then
      begin
        Peaks[PeakCount] := I;
        Inc(PeakCount);
      end;
      I := I + MinDist;
    end
    else
      Inc(I);
  end;

  if PeakCount = 0 then Exit;

  // 1. Calcula intervalo RR medio para deteccao de prematuridade real
  MeanRR := 0.80; // Valor padrao ~75 BPM
  SumRR := 0.0;
  RRCountValid := 0;
  for I := 1 to PeakCount - 1 do
  begin
    CurrRR := (Peaks[I] - Peaks[I - 1]) / ASampleRate;
    if (CurrRR >= 0.25) and (CurrRR <= 2.2) then
    begin
      SumRR := SumRR + CurrRR;
      Inc(RRCountValid);
    end;
  end;
  if RRCountValid > 0 then
    MeanRR := SumRR / RRCountValid;

  // 2. Analise Morfologica Individual de cada batimento (Largura QRS e Ritmo)
  for I := 0 to PeakCount - 1 do
  begin
    CenterSec := Peaks[I] / ASampleRate;
    PeakAmp := abs(ASamples[Peaks[I]]);
    BaselineThresh := Max(15.0, PeakAmp * 0.12);

    // Medicao real do inicio da onda Q (limite anterior ~80ms)
    QOnsetIdx := Peaks[I];
    J := Peaks[I] - 1;
    while (J >= 0) and ((Peaks[I] - J) <= Round(ASampleRate * 0.080)) do
    begin
      if abs(ASamples[J]) <= BaselineThresh then
      begin
        QOnsetIdx := J;
        Break;
      end;
      QOnsetIdx := J;
      Dec(J);
    end;

    // Medicao real do termino da onda S / ponto J (limite posterior ~120ms)
    SOffsetIdx := Peaks[I];
    J := Peaks[I] + 1;
    while (J < ACount) and ((J - Peaks[I]) <= Round(ASampleRate * 0.120)) do
    begin
      if abs(ASamples[J]) <= BaselineThresh then
      begin
        SOffsetIdx := J;
        Break;
      end;
      SOffsetIdx := J;
      Inc(J);
    end;

    DurSec := (SOffsetIdx - QOnsetIdx) / ASampleRate;
    if DurSec < 0.055 then DurSec := 0.075; // Limiar fisiologico minimo
    DurMs := DurSec * 1000.0;

    StartSec := Max(0.0, QOnsetIdx / ASampleRate);
    EndSec := Min(TotalDurationSec, SOffsetIdx / ASampleRate);

    // Avaliacao de Intervalo RR anterior
    if I > 0 then
      CurrRR := (Peaks[I] - Peaks[I - 1]) / ASampleRate
    else if PeakCount > 1 then
      CurrRR := (Peaks[1] - Peaks[0]) / ASampleRate
    else
      CurrRR := MeanRR;

    // Criterios Fisiologicos AAMI / Diretrizes Clinicas:
    // - Batimento prematuro: intervalo RR < 82% do RR medio basal
    // - Complexo QRS alargado: duracao >= 115ms (ou >= 105ms com amplitude aberrante)
    IsPremature := (I > 0) and (CurrRR < (MeanRR * 0.82));
    IsWidened := (DurMs >= 115.0) or ((PeakAmp > 400.0) and (DurMs >= 105.0));

    IsPVC := IsWidened and (IsPremature or (PeakAmp > 380.0));
    IsPAC := IsPremature and not IsWidened;

    New(P);
    P^.StartSec := StartSec;
    P^.EndSec := EndSec;
    P^.DurationMs := DurMs;

    if IsPVC then
    begin
      P^.ClassId := 2;
      P^.ClassCode := 'V';
      P^.ClassName := 'Ectopia Ventricular (PVC)';
      P^.Color := RGBToColor(255, 23, 68); // Vermelho vivo
      // Confianca baseada na magnitude do alargamento e aberracao
      P^.Confidence := EnsureRange(0.85 + Min(0.12, (DurMs - 110.0) / 100.0), 0.75, 0.98);
    end
    else if IsPAC then
    begin
      P^.ClassId := 1;
      P^.ClassCode := 'S';
      P^.ClassName := 'Ectopia Supraventricular (PAC)';
      P^.Color := RGBToColor(255, 145, 0); // Laranja
      // Confianca baseada no grau de prematuridade com QRS estreito
      P^.Confidence := EnsureRange(0.82 + Min(0.14, (MeanRR - CurrRR) / MeanRR), 0.70, 0.96);
    end
    else
    begin
      P^.ClassId := 0;
      P^.ClassCode := 'N';
      P^.ClassName := 'Batimento Normal';
      P^.Color := RGBToColor(0, 230, 118); // Verde vivo
      // Confianca baseada na proximidade com o QRS padrao normal (~85-95ms)
      P^.Confidence := EnsureRange(0.92 + Min(0.06, 1.0 - abs(DurMs - 88.0) / 120.0), 0.80, 0.99);
    end;

    Result.Add(P);
  end;
end;

class function TYOLO1DDetector.CalculateSummary(AEvents: TFPList): TYOLO1DSummary;
var
  I: Integer;
  P: PYOLO1DEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  if AEvents = nil then Exit;

  Result.TotalEvents := AEvents.Count;
  for I := 0 to AEvents.Count - 1 do
  begin
    P := PYOLO1DEvent(AEvents[I]);
    case P^.ClassCode of
      'N': Inc(Result.NormalCount);
      'V': Inc(Result.PVCCount);
      'S': Inc(Result.SupraCount);
      'F': Inc(Result.FusionCount);
    else
      Inc(Result.UnknownCount);
    end;
  end;

  if Result.TotalEvents > 0 then
    Result.ArrhythmiaPct := ((Result.PVCCount + Result.SupraCount + Result.FusionCount) / Result.TotalEvents) * 100.0
  else
    Result.ArrhythmiaPct := 0.0;
end;

end.
