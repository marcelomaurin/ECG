unit ecgaireport;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils,
  ecgtypes, numps, funcoes;

type
  { TECGAIReportGenerator }
  TECGAIReportGenerator = class
  public
    class function GenerateReport(const AStats: TECGStats; const AHistory: array of TECGRecord; ACount: Integer): String;
    class procedure ExportToCSV(const AFileName: String; const AHistory: array of TECGRecord; ACount: Integer);
    class procedure ExportToJSON(const AFileName: String; const AStats: TECGStats; const AHistory: array of TECGRecord; ACount: Integer);
  end;

implementation

class function TECGAIReportGenerator.GenerateReport(const AStats: TECGStats; const AHistory: array of TECGRecord; ACount: Integer): String;
var
  SB: TStrings;
  NumPS: TNumPS;
  Arr: TArray;
  I: Integer;
  PeakCount: Integer;
  LeadsOffCount: Integer;
  LeadsOffPct: Double;
  SignalStd: Double;
  Assessment: String;
begin
  SB := TStringList.Create;
  NumPS := TNumPS.Create(nil);
  try
    PeakCount := 0;
    LeadsOffCount := 0;

    if ACount > 0 then
    begin
      SetLength(Arr, ACount);
      for I := 0 to ACount - 1 do
      begin
        Arr[I] := AHistory[I].FilteredValue;
        if AHistory[I].IsPeak then Inc(PeakCount);
        if AHistory[I].LeadsOff then Inc(LeadsOffCount);
      end;
      SignalStd := NumPS.Std(Arr);
      LeadsOffPct := (LeadsOffCount / ACount) * 100.0;
    end
    else
    begin
      SignalStd := 0.0;
      LeadsOffPct := 0.0;
    end;

    // Análise e diagnóstico preliminar baseado nas métricas
    if LeadsOffPct > 30.0 then
      Assessment := 'ALERTA: Mais de 30% do traçado apresentou perda de contato de eletrodos (Leads-Off). O exame deve ser repetido com melhor fixação dos eletrodos.'
    else if AStats.BPM = 0 then
      Assessment := 'Sinal insuficiente para determinação estável da frequência cardíaca.'
    else if AStats.BPM < 50 then
      Assessment := 'BRADICARDIA SEVERA: Frequência cardíaca muito reduzida. Recomenda-se acompanhamento clínico imediato se sintomático.'
    else if AStats.BPM < 60 then
      Assessment := 'BRADICARDIA SINUSAL LEVE: Ritmo abaixo de 60 bpm. Pode ser fisiológico em atletas ou secundário a medicação/sono.'
    else if AStats.BPM > 120 then
      Assessment := 'TAQUICARDIA SIGNIFICATIVA: Frequência cardíaca acentuada (> 120 bpm). Recomenda-se investigação de causas metabólicas, estresse ou arritmia.'
    else if AStats.BPM > 100 then
      Assessment := 'TAQUICARDIA SINUSAL LEVE: Frequência cardíaca entre 100 e 120 bpm.'
    else
    begin
      if AStats.RRStdDev > 120.0 then
        Assessment := 'RITMO IRREGULAR / VARIABILIDADE ELEVADA: Variação acentuada nos intervalos RR. Sugere arritmia sinusal respiratória ou extrassistolia.'
      else
        Assessment := 'RITMO SINUSAL REGULAR: Frequência cardíaca e intervalos RR dentro dos padrões de normalidade fisiológica.'
    end;

    SB.Add('================================================================');
    SB.Add('       MAURINSOFT ECG MONITOR - RELATÓRIO DE TELEMETRIA / IA    ');
    SB.Add('================================================================');
    SB.Add('Data/Hora da Análise: ' + FormatDateTime('dd/mm/yyyy hh:nn:ss', Now));
    SB.Add('Amostras Avaliadas  : ' + IntToStr(ACount));
    SB.Add('----------------------------------------------------------------');
    SB.Add('1. PARÂMETROS HEMODINÂMICOS');
    SB.Add('   - Frequência Cardíaca (BPM)   : ' + IntToStr(AStats.BPM) + ' bpm');
    SB.Add('   - BPM Instantâneo             : ' + FormatFloat('0.0', AStats.InstantBPM) + ' bpm');
    SB.Add('   - Intervalo RR Médio          : ' + FormatFloat('0.0', AStats.RRIntervalMs) + ' ms');
    SB.Add('   - Variabilidade RR (Desv.Padr): ' + FormatFloat('0.0', AStats.RRStdDev) + ' ms');
    SB.Add('   - Classificação do Ritmo      : ' + AStats.StatusText);
    SB.Add('');
    SB.Add('2. MORFOLOGIA DO SINAL (Processamento TNumPS)');
    SB.Add('   - Amplitude Pico-a-Pico (mV)  : ' + FormatFloat('0.0', AStats.Amplitude));
    SB.Add('   - Nível Médio do Traçado      : ' + FormatFloat('0.0', AStats.MeanVal));
    SB.Add('   - Desvio Padrão do Sinal      : ' + FormatFloat('0.0', SignalStd));
    SB.Add('   - Batimentos Detectados (QRS) : ' + IntToStr(PeakCount));
    SB.Add('   - Desconexão de Eletrodos (%) : ' + FormatFloat('0.0', LeadsOffPct) + '%');
    SB.Add('');
    SB.Add('3. PARECER PRELIMINAR AUTOMATIZADO');
    SB.Add('   ' + Assessment);
    SB.Add('----------------------------------------------------------------');
    SB.Add('Aviso: Este relatório é gerado automaticamente por algoritmos de');
    SB.Add('processamento de sinais do projeto CHATGPT / Maurinsoft e destina-se');
    SB.Add('a fins de engenharia biomédica e monitoramento. Não substitui parecer');
    SB.Add('médico especializado.');
    SB.Add('================================================================');

    Result := SB.Text;
    AdicionarLog('Relatório de ECG gerado com sucesso: ' + IntToStr(AStats.BPM) + ' BPM');
  finally
    NumPS.Free;
    SB.Free;
  end;
end;

class procedure TECGAIReportGenerator.ExportToCSV(const AFileName: String; const AHistory: array of TECGRecord; ACount: Integer);
var
  Lines: TStringList;
  I: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('TimestampMs;RawValue;FilteredValue;LeadsOff;IsPeak');
    for I := 0 to ACount - 1 do
    begin
      Lines.Add(Format('%d;%.2f;%.2f;%s;%s', [
        AHistory[I].TimestampMs,
        AHistory[I].RawValue,
        AHistory[I].FilteredValue,
        BoolToStr(AHistory[I].LeadsOff, '1', '0'),
        BoolToStr(AHistory[I].IsPeak, '1', '0')
      ]));
    end;
    Lines.SaveToFile(AFileName);
    AdicionarLog('Traçado de ECG exportado para CSV: ' + AFileName);
  finally
    Lines.Free;
  end;
end;

class procedure TECGAIReportGenerator.ExportToJSON(const AFileName: String; const AStats: TECGStats; const AHistory: array of TECGRecord; ACount: Integer);
var
  Lines: TStringList;
  I: Integer;
  SampleStr: String;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('{');
    Lines.Add('  "timestamp": "' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + '",');
    Lines.Add('  "bpm": ' + IntToStr(AStats.BPM) + ',');
    Lines.Add('  "status": "' + AStats.StatusText + '",');
    Lines.Add('  "amplitude": ' + FormatFloat('0.00', AStats.Amplitude) + ',');
    Lines.Add('  "rr_interval_ms": ' + FormatFloat('0.00', AStats.RRIntervalMs) + ',');
    Lines.Add('  "samples_count": ' + IntToStr(ACount) + ',');
    Lines.Add('  "samples": [');
    for I := 0 to ACount - 1 do
    begin
      SampleStr := Format('    {"t": %d, "raw": %.1f, "filtered": %.1f, "peak": %s}', [
        AHistory[I].TimestampMs,
        AHistory[I].RawValue,
        AHistory[I].FilteredValue,
        BoolToStr(AHistory[I].IsPeak, 'true', 'false')
      ]);
      if I < ACount - 1 then
        SampleStr := SampleStr + ',';
      Lines.Add(SampleStr);
    end;
    Lines.Add('  ]');
    Lines.Add('}');
    Lines.SaveToFile(AFileName);
    AdicionarLog('Traçado de ECG exportado para JSON: ' + AFileName);
  finally
    Lines.Free;
  end;
end;

end.
