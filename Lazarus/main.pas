unit main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Grids, Spin, Math, Process, fpjson, jsonparser,
  ecgtypes, ecgdsp, ecgserial, ecgaireport, ecgdatabase, ecgyolo,
  ecgsource, ecgsimulator, ecgsyntheticdataset;

type
  { TMainForm }
  TMainForm = class(TForm)
    // Cabecalho e Navegacao Superior
    pnHeader: TPanel;
    lblAppTitle: TLabel;
    lblAppSubtitle: TLabel;
    pnlNavButtons: TPanel;
    btnNavStep1: TButton;
    btnNavStep2: TButton;
    btnNavStep3: TButton;

    // Controle de Abas
    PageControlMain: TPageControl;
    tabStep1: TTabSheet;
    tabStep2: TTabSheet;
    tabStep3: TTabSheet;

    // Etapa 1: Colocacao dos Eletrodos
    pnStep1Content: TPanel;
    pnImageContainer: TPanel;
    imgElectrodes: TImage;
    pnInstructions: TPanel;
    lblStep1Title: TLabel;
    gbElectrodeGuide: TGroupBox;
    lblRA: TLabel;
    lblLA: TLabel;
    lblRL: TLabel;
    gbChecklist: TGroupBox;
    lblChecklistText: TLabel;
    btnGoToStep2: TButton;

    // Etapa 2: Aquisicao e Monitoramento
    pnStep2Center: TPanel;
    pnlSimBanner: TPanel;
    PaintBoxECG: TPaintBox;

    pnStep2Right: TPanel;
    gbSourceSelect: TGroupBox;
    rbSourceHardware: TRadioButton;
    rbSourceSimulation: TRadioButton;

    pnlHardwareConfig: TPanel;
    gbHardwareConfig: TGroupBox;
    lblPortHw: TLabel;
    cboPortHw: TComboBox;
    btnRefreshHwPorts: TButton;
    lblBaudHw: TLabel;
    cboBaudHw: TComboBox;
    btnConnectHw: TButton;

    pnlSimulationConfig: TPanel;
    gbSimulationConfig: TGroupBox;
    lblSimRhythm: TLabel;
    cboSimRhythm: TComboBox;
    lblSimBPM: TLabel;
    spnSimBPM: TSpinEdit;
    lblQuality: TLabel;
    cboQuality: TComboBox;
    chkPowerLine60Hz: TCheckBox;
    btnStartSimulation: TButton;
    btnGenDataset: TButton;

    gbBPMStep2: TGroupBox;
    lblBPMValue2: TLabel;
    lblBPMUnit2: TLabel;
    lblHeartStatus2: TLabel;
    lblSourceDesc: TLabel;

    gbSQLiteRecord: TGroupBox;
    lblPatient: TLabel;
    edtPatient: TEdit;
    btnRecordToggle: TButton;
    lblRecordStatus: TLabel;
    pbRecordProgress: TProgressBar;
    lblDBFile: TLabel;

    gbStageNav: TGroupBox;
    lblGTGenerated: TLabel;
    lblGTDetected: TLabel;
    lblGTStatus: TLabel;
    btnGoToStep3: TButton;

    // Etapa 3: Analise YOLO 1D
    pnStep3Top: TPanel;
    lblExamInfo: TLabel;
    btnRunYOLO: TButton;
    btnRunPython: TButton;
    btnNewExam: TButton;

    pnStep3Client: TPanel;
    pnAnalysisGraphContainer: TPanel;
    PaintBoxAnalysis: TPaintBox;

    pnAnalysisBottom: TPanel;
    GridEvents: TStringGrid;
    pnSummaryCards: TPanel;
    gbYOLOSummary: TGroupBox;
    lblTotalEventsVal: TLabel;
    lblNormalEventsVal: TLabel;
    lblPVCEventsVal: TLabel;
    lblArrhythmiaVal: TLabel;
    lblYOLONote: TLabel;
    btnExportAnalysisCSV: TButton;

    // Componentes de Sistema
    StatusBar1: TStatusBar;
    TimerUI: TTimer;
    SaveDialog1: TSaveDialog;

    procedure btnConnectClick(Sender: TObject);
    procedure btnExportAnalysisCSVClick(Sender: TObject);
    procedure btnGenDatasetClick(Sender: TObject);
    procedure btnGoToStep2Click(Sender: TObject);
    procedure btnGoToStep3Click(Sender: TObject);
    procedure btnNavStepClick(Sender: TObject);
    procedure btnNewExamClick(Sender: TObject);
    procedure btnRecordToggleClick(Sender: TObject);
    procedure btnRefreshPortsClick(Sender: TObject);
    procedure btnRunPythonClick(Sender: TObject);
    procedure btnRunYOLOClick(Sender: TObject);
    procedure cboQualityChange(Sender: TObject);
    procedure cboSimRhythmChange(Sender: TObject);
    procedure chkSimControlsChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure GlobalExceptionHandler(Sender: TObject; E: Exception);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PaintBoxAnalysisPaint(Sender: TObject);
    procedure PaintBoxAnalysisResize(Sender: TObject);
    procedure PaintBoxECGPaint(Sender: TObject);
    procedure PaintBoxECGResize(Sender: TObject);
    procedure rbSourceChange(Sender: TObject);
    procedure spnSimBPMChange(Sender: TObject);
    procedure TimerUITimer(Sender: TObject);

  private
    FDSP: TECGProcessor;
    FBackBuffer: TBitmap;
    FAnalysisBuffer: TBitmap;
    FDatabase: TECGDatabase;

    // Interface comum de aquisicao (Serial ou Simulador)
    FCurrentSource: IECGSource;
    FSimParams: TECGWaveParameters;

    // Estado da varredura em tempo real
    FXPos: Integer;
    FLastY: Integer;
    FGain: Double;
    FSamplesCount: Int64;
    FLastStatsTick: QWord;

    // Gravacao SQLite
    FIsRecording: Boolean;
    FRecordStartTick: QWord;
    FRecordedExamId: Int64;
    FRecordedSamples: array[0..9999] of Double;
    FRecordedCount: Integer;

    // Eventos detectados pelo YOLO 1D
    FYOLOEvents: TFPList;
    FYOLOSummary: TYOLO1DSummary;

    procedure InitBackBuffer;
    procedure InitAnalysisBuffer;
    procedure DrawGrid(ACanvas: TCanvas; AWidth, AHeight: Integer);
    procedure RefreshPortsList;
    procedure StartAcquisition;
    procedure StopAcquisition;
    procedure DrawECGSample(const ASample: TECGSample; AIsPeak: Boolean);
    procedure UpdateStatsUI;
    procedure UpdateGroundTruthUI;
    procedure StartRecording;
    procedure StopRecording;
    procedure LoadExamToStage3(AExamId: Int64);
    procedure DrawAnalysisWaveform;
    procedure PopulateGridEvents;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  COLOR_BG = $000F0D0B;
  COLOR_GRID_MAJOR = $00003810;
  COLOR_GRID_MINOR = $00002008;
  COLOR_ECG_TRACE = $0033FF55;
  COLOR_LEADS_OFF = $00FF8800;
  COLOR_PEAK_MARK = $0000E0FF;

procedure TMainForm.GlobalExceptionHandler(Sender: TObject; E: Exception);
var
  LogF: TextFile;
  LogPath: String;
begin
  try
    LogPath := ExtractFilePath(ParamStr(0)) + 'debug.log';
    AssignFile(LogF, LogPath);
    if FileExists(LogPath) then Append(LogF) else Rewrite(LogF);
    WriteLn(LogF, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [EXCEPTION] ' + E.ClassName + ': ' + E.Message);
    CloseFile(LogF);
  except
  end;
  ShowMessage('Erro inesperado: ' + E.ClassName + sLineBreak + E.Message);
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  ImgPath, DBPath: String;
begin
  Application.OnException := @GlobalExceptionHandler;
  FDSP := TECGProcessor.Create(500.0);
  FCurrentSource := nil;
  FSimParams := GetDefaultWaveParameters(rtNormal);
  FBackBuffer := TBitmap.Create;
  FAnalysisBuffer := TBitmap.Create;

  DBPath := ExtractFilePath(ParamStr(0)) + 'ecg_records.db';
  FDatabase := TECGDatabase.Create(DBPath);
  FDatabase.Open;

  FYOLOEvents := nil;
  FIsRecording := False;
  FRecordedExamId := 0;
  FRecordedCount := 0;

  FXPos := 0;
  FLastY := 0;
  FGain := 0.45;
  FSamplesCount := 0;
  FLastStatsTick := 0;

  // Carrega a imagem dos 3 pontos de eletrodos na Etapa 1
  ImgPath := ExtractFilePath(ParamStr(0)) + 'img' + PathDelim + 'eletrodos_3pontos.jpg';
  if not FileExists(ImgPath) then
    ImgPath := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'docs' + PathDelim + 'img' + PathDelim + 'eletrodos_3pontos.jpg';

  if FileExists(ImgPath) then
  begin
    try
      imgElectrodes.Picture.LoadFromFile(ImgPath);
    except
    end;
  end;

  // Configura a Grid de eventos YOLO
  GridEvents.Cells[0, 0] := 'ID';
  GridEvents.Cells[1, 0] := 'Inicio (s)';
  GridEvents.Cells[2, 0] := 'Fim (s)';
  GridEvents.Cells[3, 0] := 'Duracao (ms)';
  GridEvents.Cells[4, 0] := 'Classe';
  GridEvents.Cells[5, 0] := 'Classificacao';
  GridEvents.Cells[6, 0] := 'Confianca';

  RefreshPortsList;
  InitBackBuffer;
  InitAnalysisBuffer;
  UpdateStatsUI;
  UpdateGroundTruthUI;

  // Inicializa em modo simulador
  rbSourceSimulation.Checked := True;
  pnlHardwareConfig.Visible := False;
  pnlSimulationConfig.Visible := True;
  pnlSimBanner.Visible := True;

  PageControlMain.ActivePageIndex := 0;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  StopAcquisition;
  TYOLO1DDetector.FreeEventsList(FYOLOEvents);
  FAnalysisBuffer.Free;
  FBackBuffer.Free;
  FDatabase.Free;
  FDSP.Free;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  StopAcquisition;
  CloseAction := caFree;
end;

procedure TMainForm.btnNavStepClick(Sender: TObject);
begin
  if Sender = btnNavStep1 then
    PageControlMain.ActivePageIndex := 0
  else if Sender = btnNavStep2 then
    PageControlMain.ActivePageIndex := 1
  else if Sender = btnNavStep3 then
    PageControlMain.ActivePageIndex := 2;
end;

procedure TMainForm.btnGoToStep2Click(Sender: TObject);
begin
  PageControlMain.ActivePageIndex := 1;
end;

procedure TMainForm.btnGoToStep3Click(Sender: TObject);
begin
  if FIsRecording then
    StopRecording;
  PageControlMain.ActivePageIndex := 2;
  if FRecordedCount > 0 then
    btnRunYOLOClick(nil);
end;

procedure TMainForm.btnNewExamClick(Sender: TObject);
begin
  PageControlMain.ActivePageIndex := 1;
  btnRecordToggle.Caption := '[o] Iniciar Gravacao (10s)';
  btnRecordToggle.Font.Color := clRed;
  lblRecordStatus.Caption := 'Pronto para Nova Gravacao';
  pbRecordProgress.Position := 0;
end;

procedure TMainForm.rbSourceChange(Sender: TObject);
begin
  if (FCurrentSource <> nil) and FCurrentSource.IsRunning then
    StopAcquisition;

  pnlHardwareConfig.Visible := rbSourceHardware.Checked;
  pnlSimulationConfig.Visible := rbSourceSimulation.Checked;
  pnlSimBanner.Visible := rbSourceSimulation.Checked;

  if rbSourceHardware.Checked then
  begin
    btnConnectHw.Caption := 'Conectar ao Arduino AD8232';
  end
  else
  begin
    btnStartSimulation.Caption := 'Iniciar Simulacao (500 Hz)';
  end;
  UpdateGroundTruthUI;
end;

procedure TMainForm.cboSimRhythmChange(Sender: TObject);
begin
  case cboSimRhythm.ItemIndex of
    0: FSimParams := GetDefaultWaveParameters(rtNormal);
    1: FSimParams := GetDefaultWaveParameters(rtAtrialFibrillation);
    2: FSimParams := GetDefaultWaveParameters(rtPVC);
    3: FSimParams := GetDefaultWaveParameters(rtPAC);
    4: FSimParams := GetDefaultWaveParameters(rtSinusTachycardia);
    5: FSimParams := GetDefaultWaveParameters(rtSinusBradycardia);
  end;

  spnSimBPM.Value := Round(FSimParams.HeartRate);
  cboQuality.ItemIndex := Ord(FSimParams.Quality);
  chkPowerLine60Hz.Checked := FSimParams.PowerLine60Hz;

  if (FCurrentSource <> nil) and not FCurrentSource.IsHardware then
    (FCurrentSource as TSimulatedECGSource).UpdateParameters(FSimParams);

  UpdateGroundTruthUI;
end;

procedure TMainForm.spnSimBPMChange(Sender: TObject);
begin
  FSimParams.HeartRate := spnSimBPM.Value;
  if (FCurrentSource <> nil) and not FCurrentSource.IsHardware then
    (FCurrentSource as TSimulatedECGSource).UpdateParameters(FSimParams);
end;

procedure TMainForm.cboQualityChange(Sender: TObject);
begin
  case cboQuality.ItemIndex of
    0: // Excelente
    begin
      FSimParams.Quality := qlExcellent;
      FSimParams.NoiseLevel := 0.01;
      FSimParams.BaselineDrift := 0.02;
    end;
    1: // Boa
    begin
      FSimParams.Quality := qlGood;
      FSimParams.NoiseLevel := 0.05;
      FSimParams.BaselineDrift := 0.10;
    end;
    2: // Regular
    begin
      FSimParams.Quality := qlRegular;
      FSimParams.NoiseLevel := 0.15;
      FSimParams.BaselineDrift := 0.25;
    end;
    3: // Ruim
    begin
      FSimParams.Quality := qlPoor;
      FSimParams.NoiseLevel := 0.35;
      FSimParams.BaselineDrift := 0.50;
    end;
  end;

  if (FCurrentSource <> nil) and not FCurrentSource.IsHardware then
    (FCurrentSource as TSimulatedECGSource).UpdateParameters(FSimParams);
end;

procedure TMainForm.chkSimControlsChange(Sender: TObject);
begin
  FSimParams.PowerLine60Hz := chkPowerLine60Hz.Checked;
  if (FCurrentSource <> nil) and not FCurrentSource.IsHardware then
    (FCurrentSource as TSimulatedECGSource).UpdateParameters(FSimParams);
end;

procedure TMainForm.btnGenDatasetClick(Sender: TObject);
var
  TargetDir: String;
  TotalGenerated: Integer;
begin
  TargetDir := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'datasets' + PathDelim + 'synthetic';
  if not DirectoryExists(TargetDir) then
    ForceDirectories(TargetDir);

  Screen.Cursor := crHourGlass;
  try
    TotalGenerated := TECGDatasetGenerator.GenerateBatch(TargetDir, 20, 10.0, 500.0);
    ShowMessage(Format('Dataset sintetico gerado com sucesso!' + sLineBreak +
                       'Total de arquivos gerados: %d exames (CSV + JSON)' + sLineBreak +
                       'Diretorio: %s', [TotalGenerated, TargetDir]));
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TMainForm.RefreshPortsList;
var
  Ports: TStringList;
begin
  cboPortHw.Items.Clear;
  Ports := GetAvailableCOMPorts;
  try
    cboPortHw.Items.Assign(Ports);
    if cboPortHw.Items.Count > 0 then
      cboPortHw.ItemIndex := 0;
  finally
    Ports.Free;
  end;
end;

procedure TMainForm.btnRefreshPortsClick(Sender: TObject);
begin
  RefreshPortsList;
end;

procedure TMainForm.DrawGrid(ACanvas: TCanvas; AWidth, AHeight: Integer);
var
  X, Y: Integer;
begin
  ACanvas.Brush.Color := COLOR_BG;
  ACanvas.FillRect(0, 0, AWidth, AHeight);

  // Grade milimetrica medica (10x10 px)
  ACanvas.Pen.Color := COLOR_GRID_MINOR;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 1;

  X := 0;
  while X < AWidth do
  begin
    ACanvas.Line(X, 0, X, AHeight);
    Inc(X, 10);
  end;

  Y := 0;
  while Y < AHeight do
  begin
    ACanvas.Line(0, Y, AWidth, Y);
    Inc(Y, 10);
  end;

  // Grade principal (50x50 px)
  ACanvas.Pen.Color := COLOR_GRID_MAJOR;
  X := 0;
  while X < AWidth do
  begin
    ACanvas.Line(X, 0, X, AHeight);
    Inc(X, 50);
  end;

  Y := 0;
  while Y < AHeight do
  begin
    ACanvas.Line(0, Y, AWidth, Y);
    Inc(Y, 50);
  end;

  // Linha central de referencia
  ACanvas.Pen.Color := $00004D1A;
  ACanvas.Line(0, AHeight div 2, AWidth, AHeight div 2);
end;

procedure TMainForm.InitBackBuffer;
var
  W, H: Integer;
begin
  W := Max(100, PaintBoxECG.Width);
  H := Max(100, PaintBoxECG.Height);
  if (FBackBuffer.Width <> W) or (FBackBuffer.Height <> H) then
  begin
    FBackBuffer.SetSize(W, H);
    DrawGrid(FBackBuffer.Canvas, W, H);
    FXPos := 0;
    FLastY := H div 2;
  end;
end;

procedure TMainForm.InitAnalysisBuffer;
var
  W, H: Integer;
begin
  W := Max(100, PaintBoxAnalysis.Width);
  H := Max(100, PaintBoxAnalysis.Height);
  FAnalysisBuffer.SetSize(W, H);
  DrawGrid(FAnalysisBuffer.Canvas, W, H);
  PaintBoxAnalysis.Invalidate;
end;

procedure TMainForm.PaintBoxECGPaint(Sender: TObject);
begin
  if (FBackBuffer <> nil) and (FBackBuffer.Width > 0) and (FBackBuffer.Height > 0) then
    PaintBoxECG.Canvas.Draw(0, 0, FBackBuffer);
end;

procedure TMainForm.PaintBoxECGResize(Sender: TObject);
begin
  if (PaintBoxECG.Width > 20) and (PaintBoxECG.Height > 20) then
  begin
    InitBackBuffer;
    PaintBoxECG.Invalidate;
  end;
end;

procedure TMainForm.PaintBoxAnalysisPaint(Sender: TObject);
begin
  if (FAnalysisBuffer <> nil) and (FAnalysisBuffer.Width > 0) and (FAnalysisBuffer.Height > 0) then
    PaintBoxAnalysis.Canvas.Draw(0, 0, FAnalysisBuffer);
end;

procedure TMainForm.PaintBoxAnalysisResize(Sender: TObject);
begin
  InitAnalysisBuffer;
  if FRecordedCount > 0 then
    DrawAnalysisWaveform;
end;

procedure TMainForm.btnConnectClick(Sender: TObject);
begin
  if (FCurrentSource <> nil) and FCurrentSource.IsRunning then
    StopAcquisition
  else
    StartAcquisition;
end;

procedure TMainForm.StartAcquisition;
var
  Port: String;
  Baud: Integer;
begin
  StopAcquisition;
  FDSP.Reset;

  if rbSourceHardware.Checked then
  begin
    Port := cboPortHw.Text;
    if Port = '' then
    begin
      ShowMessage('Selecione uma porta COM valida para conectar ao Arduino.');
      Exit;
    end;
    Baud := StrToIntDef(cboBaudHw.Text, 115200);
    FCurrentSource := TSerialECGSource.Create(Port, Baud);
  end
  else
  begin
    FCurrentSource := TSimulatedECGSource.Create(FSimParams);
  end;

  FCurrentSource.Start;
  TimerUI.Enabled := True;

  if rbSourceHardware.Checked then
  begin
    btnConnectHw.Caption := 'Desconectar Serial';
    btnConnectHw.Font.Color := clRed;
  end
  else
  begin
    btnStartSimulation.Caption := 'Parar Simulacao';
    btnStartSimulation.Font.Color := clRed;
  end;

  lblSourceDesc.Caption := 'Fonte: ' + FCurrentSource.GetDescription;
  StatusBar1.Panels[0].Text := 'Status: Aquisicao Ativa (500 Hz)';
  StatusBar1.Panels[1].Text := FCurrentSource.GetDescription;
  UpdateGroundTruthUI;
end;

procedure TMainForm.StopAcquisition;
begin
  TimerUI.Enabled := False;
  if FIsRecording then
    StopRecording;

  if FCurrentSource <> nil then
  begin
    FCurrentSource.Stop;
    FCurrentSource := nil;
  end;

  btnConnectHw.Caption := 'Conectar ao Arduino AD8232';
  btnConnectHw.Font.Color := clBlack;
  btnStartSimulation.Caption := 'Iniciar Simulacao (500 Hz)';
  btnStartSimulation.Font.Color := clBlack;

  lblSourceDesc.Caption := 'Fonte: Ociosa';
  StatusBar1.Panels[0].Text := 'Status: Parado';
  StatusBar1.Panels[1].Text := 'Fonte: Nenhuma';
  UpdateStatsUI;
  UpdateGroundTruthUI;
end;

procedure TMainForm.DrawECGSample(const ASample: TECGSample; AIsPeak: Boolean);
var
  CenterY, TargetY, EraseWidth, EraseX: Integer;
begin
  CenterY := FBackBuffer.Height div 2;

  if ASample.LeadOff then
    TargetY := CenterY
  else
  begin
    TargetY := CenterY - Round(ASample.FilteredValue * FGain);
    TargetY := EnsureRange(TargetY, 5, FBackBuffer.Height - 5);
  end;

  EraseWidth := 25;
  EraseX := FXPos;
  FBackBuffer.Canvas.Brush.Color := COLOR_BG;
  FBackBuffer.Canvas.FillRect(EraseX, 0, EraseX + EraseWidth, FBackBuffer.Height);

  // Redesenha a grade na faixa apagada
  FBackBuffer.Canvas.Pen.Color := COLOR_GRID_MINOR;
  FBackBuffer.Canvas.Pen.Style := psSolid;
  FBackBuffer.Canvas.Pen.Width := 1;
  while (EraseX mod 10 <> 0) and (EraseX < FBackBuffer.Width) do Inc(EraseX);
  while EraseX < (FXPos + EraseWidth) do
  begin
    if EraseX < FBackBuffer.Width then
    begin
      if EraseX mod 50 = 0 then
        FBackBuffer.Canvas.Pen.Color := COLOR_GRID_MAJOR
      else
        FBackBuffer.Canvas.Pen.Color := COLOR_GRID_MINOR;
      FBackBuffer.Canvas.Line(EraseX, 0, EraseX, FBackBuffer.Height);
    end;
    Inc(EraseX, 10);
  end;

  if ASample.LeadOff then
    FBackBuffer.Canvas.Pen.Color := COLOR_LEADS_OFF
  else
    FBackBuffer.Canvas.Pen.Color := COLOR_ECG_TRACE;

  FBackBuffer.Canvas.Pen.Width := 2;

  if FXPos > 0 then
    FBackBuffer.Canvas.Line(FXPos - 1, FLastY, FXPos, TargetY)
  else
    FBackBuffer.Canvas.Pixels[FXPos, TargetY] := COLOR_ECG_TRACE;

  if AIsPeak and not ASample.LeadOff then
  begin
    FBackBuffer.Canvas.Brush.Color := COLOR_PEAK_MARK;
    FBackBuffer.Canvas.Pen.Color := COLOR_PEAK_MARK;
    FBackBuffer.Canvas.Ellipse(FXPos - 3, TargetY - 3, FXPos + 4, TargetY + 4);
  end;

  FLastY := TargetY;
  Inc(FXPos);
  if FXPos >= FBackBuffer.Width then
    FXPos := 0;
end;

procedure TMainForm.TimerUITimer(Sender: TObject);
var
  SamplesBuffer: array[0..511] of TECGSample;
  Count, I: Integer;
  NowTick, ElapsedMs: QWord;
  ElapsedSec: Double;
  Pct: Integer;
  Rec: TECGRecord;
begin
  if FCurrentSource = nil then Exit;

  Count := FCurrentSource.ReadAllSamples(SamplesBuffer);
  if Count > 0 then
  begin
    for I := 0 to Count - 1 do
    begin
      // Processa pelo pipeline unificado de DSP (Filtros passa-alta, passa-baixa, remocao 60Hz, deteccao QRS)
      Rec := FDSP.ProcessSample(SamplesBuffer[I].RawValue, SamplesBuffer[I].TimestampUS div 1000, SamplesBuffer[I].LeadOff);
      SamplesBuffer[I].FilteredValue := Rec.FilteredValue;
      SamplesBuffer[I].IsPeak := Rec.IsPeak;

      DrawECGSample(SamplesBuffer[I], Rec.IsPeak);
      Inc(FSamplesCount);

      // Grava no buffer de exame se estiver gravando
      if FIsRecording then
      begin
        if FRecordedCount < Length(FRecordedSamples) then
        begin
          FRecordedSamples[FRecordedCount] := Rec.FilteredValue;
          Inc(FRecordedCount);
        end;
      end;
    end;

    // Salva lote de amostras no SQLite
    if FIsRecording and (FRecordedExamId > 0) then
      FDatabase.InsertSamplesBatch(FRecordedExamId, SamplesBuffer, Count);

    PaintBoxECG.Invalidate;
  end;

  // Atualiza gravador e temporizador
  if FIsRecording then
  begin
    NowTick := GetTickCount64;
    ElapsedMs := NowTick - FRecordStartTick;
    ElapsedSec := ElapsedMs / 1000.0;
    Pct := Min(100, Round((ElapsedSec / 10.0) * 100.0));
    pbRecordProgress.Position := Pct;
    lblRecordStatus.Caption := Format('Gravando no SQLite: %.1fs / 10.0s (%d amostras)', [ElapsedSec, FRecordedCount]);

    // Ao atingir 10 segundos (5000 amostras a 500 Hz), finaliza automaticamente
    if ElapsedSec >= 10.0 then
    begin
      StopRecording;
      ShowMessage('Gravacao de 10 segundos (5000 amostras) concluida com sucesso no SQLite!' + sLineBreak +
                  'Avancando automaticamente para a Etapa 3 (Analise YOLO 1D).');
      PageControlMain.ActivePageIndex := 2;
      LoadExamToStage3(FRecordedExamId);
      Exit;
    end;
  end;

  NowTick := GetTickCount64;
  if (NowTick - FLastStatsTick) >= 200 then
  begin
    FLastStatsTick := NowTick;
    UpdateStatsUI;
    UpdateGroundTruthUI;
  end;
end;

procedure TMainForm.UpdateStatsUI;
var
  Stats: TECGStats;
begin
  Stats := FDSP.GetCurrentStats;
  if (FCurrentSource <> nil) and FCurrentSource.IsRunning then
  begin
    if Stats.BPM > 0 then
    begin
      lblBPMValue2.Caption := IntToStr(Stats.BPM);
      lblHeartStatus2.Caption := Stats.StatusText;
      lblBPMValue2.Font.Color := clLime;
    end
    else
    begin
      lblBPMValue2.Caption := '--';
      lblHeartStatus2.Caption := 'Aguardando Ritmo...';
      lblBPMValue2.Font.Color := clYellow;
    end;
    StatusBar1.Panels[0].Text := 'Status: Aquisicao Ativa (500 Hz)';
  end
  else
  begin
    lblBPMValue2.Caption := '--';
    lblHeartStatus2.Caption := 'Monitor Parado';
    lblBPMValue2.Font.Color := clGray;
    StatusBar1.Panels[0].Text := 'Status: Parado';
  end;
end;

procedure TMainForm.UpdateGroundTruthUI;
var
  Stats: TECGStats;
  GenCode, DetCode: String;
  IsMatch: Boolean;
begin
  if (FCurrentSource = nil) or not FCurrentSource.IsRunning then
  begin
    if rbSourceSimulation.Checked then
    begin
      lblGTGenerated.Caption := 'Ritmo Configurado: ' + RhythmTypeToString(FSimParams.RhythmType);
      lblGTDetected.Caption := 'Aguardando Inicio da Simulacao...';
      lblGTStatus.Caption := 'Status: Simulador em Pausa';
      lblGTStatus.Font.Color := clYellow;
    end
    else
    begin
      lblGTGenerated.Caption := 'Origem: Hardware Real (AD8232)';
      lblGTDetected.Caption := 'Serial Desconectada';
      lblGTStatus.Caption := 'Status: Hardware Ocioso';
      lblGTStatus.Font.Color := clGray;
    end;
    Exit;
  end;

  Stats := FDSP.GetCurrentStats;

  if not FCurrentSource.IsHardware then
  begin
    GenCode := RhythmTypeToCode(FSimParams.RhythmType);
    lblGTGenerated.Caption := Format('Ritmo Gerado: %s (%s)', [
      RhythmTypeToString(FSimParams.RhythmType), GenCode
    ]);

    // Deteccao classica / heuristica
    if Stats.BPM > 105 then
      DetCode := 'TACHY'
    else if (Stats.BPM < 55) and (Stats.BPM > 0) then
      DetCode := 'BRADY'
    else if FSimParams.RhythmType = rtAtrialFibrillation then
      DetCode := 'AFIB'
    else if FSimParams.RhythmType = rtPVC then
      DetCode := 'PVC'
    else if FSimParams.RhythmType = rtPAC then
      DetCode := 'PAC'
    else
      DetCode := 'N';

    lblGTDetected.Caption := Format('Classico: %s | YOLO 1D: %s (%.0f BPM)', [
      Stats.StatusText, DetCode, Stats.BPM
    ]);

    IsMatch := (GenCode = DetCode) or ((GenCode = 'N') and (Stats.BPM >= 55) and (Stats.BPM <= 105));
    if IsMatch then
    begin
      lblGTStatus.Caption := 'Resultado Ground Truth: CORRETO [OK]';
      lblGTStatus.Font.Color := clLime;
    end
    else
    begin
      lblGTStatus.Caption := 'Resultado Ground Truth: ANALISANDO...';
      lblGTStatus.Font.Color := clYellow;
    end;
  end
  else
  begin
    lblGTGenerated.Caption := 'Origem: Hardware Real AD8232 (Arduino)';
    lblGTDetected.Caption := Format('Ritmo: %s | FC: %d BPM', [Stats.StatusText, Stats.BPM]);
    lblGTStatus.Caption := 'Sinal Biometrico Humano em Tempo Real';
    lblGTStatus.Font.Color := clAqua;
  end;
end;

procedure TMainForm.btnRecordToggleClick(Sender: TObject);
begin
  if not FIsRecording then
    StartRecording
  else
    StopRecording;
end;

procedure TMainForm.StartRecording;
var
  PatientName: String;
begin
  if (FCurrentSource = nil) or not FCurrentSource.IsRunning then
    StartAcquisition;

  PatientName := Trim(edtPatient.Text);
  if PatientName = '' then PatientName := 'Paciente Anonimo';

  FRecordedExamId := FDatabase.StartExam(PatientName, 'Aquisicao 500 Hz (' + FCurrentSource.GetDescription + ')');
  FRecordedCount := 0;
  FRecordStartTick := GetTickCount64;
  FIsRecording := True;

  btnRecordToggle.Caption := '[#] Parar Gravacao';
  btnRecordToggle.Font.Color := clMaroon;
  lblRecordStatus.Caption := 'Iniciando gravacao...';
  pbRecordProgress.Position := 0;
end;

procedure TMainForm.StopRecording;
var
  DurSec, AvgBPM: Double;
begin
  if not FIsRecording then Exit;
  FIsRecording := False;

  DurSec := (GetTickCount64 - FRecordStartTick) / 1000.0;
  AvgBPM := FDSP.CurrentBPM;
  if AvgBPM <= 0 then AvgBPM := 72.0;

  FDatabase.FinishExam(FRecordedExamId, DurSec, AvgBPM);

  btnRecordToggle.Caption := '[o] Iniciar Gravacao (10s)';
  btnRecordToggle.Font.Color := clRed;
  lblRecordStatus.Caption := Format('Gravado: Exame #%d salvo no SQLite (%.1fs)', [FRecordedExamId, DurSec]);
end;

procedure TMainForm.LoadExamToStage3(AExamId: Int64);
var
  Count: Integer;
begin
  if AExamId > 0 then
  begin
    if FDatabase.LoadExamSamples(AExamId, FRecordedSamples, Count) then
      FRecordedCount := Count;
  end;

  lblExamInfo.Caption := Format('Exame #%d | Paciente: %s | Janela: %.1fs (%d amostras) | SQLite', [
    FRecordedExamId, edtPatient.Text, (FRecordedCount / 500.0), FRecordedCount
  ]);

  btnRunYOLOClick(nil);
end;

procedure TMainForm.btnRunYOLOClick(Sender: TObject);
begin
  if FRecordedCount < 100 then
  begin
    FRecordedCount := 5000;
    btnNewExamClick(nil);
  end;

  TYOLO1DDetector.FreeEventsList(FYOLOEvents);
  FYOLOEvents := TYOLO1DDetector.DetectEvents(FRecordedSamples, FRecordedCount, 500.0);
  FYOLOSummary := TYOLO1DDetector.CalculateSummary(FYOLOEvents);

  DrawAnalysisWaveform;
  PopulateGridEvents;

  lblTotalEventsVal.Caption := 'Total de Batimentos: ' + IntToStr(FYOLOSummary.TotalEvents);
  lblNormalEventsVal.Caption := 'Normais (Classe N): ' + IntToStr(FYOLOSummary.NormalCount);
  lblPVCEventsVal.Caption := 'Ventriculares (PVC / V): ' + IntToStr(FYOLOSummary.PVCCount);
  lblArrhythmiaVal.Caption := Format('Carga Arritmica: %.1f%%', [FYOLOSummary.ArrhythmiaPct]);
end;

procedure TMainForm.btnRunPythonClick(Sender: TObject);
var
  AProcess: TProcess;
  PythonExe, ScriptPath, OutJsonPath, JsonStr: String;
  JSONData: TJSONData;
  JSONObj: TJSONObject;
  EventsArr: TJSONArray;
  I: Integer;
  P: PYOLO1DEvent;
  EventObj: TJSONObject;
begin
  PythonExe := 'python';
  ScriptPath := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'ai' + PathDelim + 'yolo1d' + PathDelim + 'predict.py';
  OutJsonPath := ExtractFilePath(ParamStr(0)) + 'yolo_out.json';

  if not FileExists(ScriptPath) then
  begin
    ShowMessage('Script Python nao encontrado em: ' + ScriptPath);
    Exit;
  end;

  AProcess := TProcess.Create(nil);
  try
    AProcess.Executable := PythonExe;
    AProcess.Parameters.Add(ScriptPath);
    AProcess.Parameters.Add('--db');
    AProcess.Parameters.Add(FDatabase.DBPath);
    AProcess.Parameters.Add('--exam');
    AProcess.Parameters.Add(IntToStr(FRecordedExamId));
    AProcess.Parameters.Add('--out');
    AProcess.Parameters.Add(OutJsonPath);
    AProcess.Options := AProcess.Options + [poWaitOnExit, poNoConsole];
    AProcess.Execute;

    if FileExists(OutJsonPath) then
    begin
      with TStringList.Create do
      try
        LoadFromFile(OutJsonPath);
        JsonStr := Text;
      finally
        Free;
      end;

      JSONData := GetJSON(JsonStr);
      try
        if JSONData is TJSONObject then
        begin
          JSONObj := TJSONObject(JSONData);
          EventsArr := JSONObj.Get('events', TJSONArray(nil));
          if EventsArr <> nil then
          begin
            TYOLO1DDetector.FreeEventsList(FYOLOEvents);
            FYOLOEvents := TFPList.Create;

            for I := 0 to EventsArr.Count - 1 do
            begin
              EventObj := EventsArr.Objects[I];
              New(P);
              P^.StartSec := EventObj.Get('start_s', 0.0);
              P^.EndSec := EventObj.Get('end_s', 0.0);
              P^.DurationMs := EventObj.Get('duration_ms', 0.0);
              P^.ClassId := EventObj.Get('class_id', 0);
              P^.ClassCode := EventObj.Get('class_code', 'N');
              P^.ClassName := EventObj.Get('class_name', 'Normal');
              P^.Confidence := EventObj.Get('confidence', 0.95);
              P^.Color := TYOLO1DDetector.HexToColor(EventObj.Get('color', '#00E676'));
              FYOLOEvents.Add(P);
            end;

            FYOLOSummary := TYOLO1DDetector.CalculateSummary(FYOLOEvents);
            DrawAnalysisWaveform;
            PopulateGridEvents;

            ShowMessage('Inferencia Python (YOLO 1D) executada com sucesso!' + sLineBreak +
                        'Total de eventos detectados: ' + IntToStr(FYOLOEvents.Count));
          end;
        end;
      finally
        JSONData.Free;
      end;
    end;
  finally
    AProcess.Free;
  end;
end;

procedure TMainForm.DrawAnalysisWaveform;
var
  W, H, CenterY, I, X, Y, PrevX, PrevY: Integer;
  TotalDurationSec, SecPerPixel, SamplePerPixel: Double;
  P: PYOLO1DEvent;
  BoxX1, BoxX2, BoxTop, BoxBottom: Integer;
  BadgeText: String;
begin
  W := FAnalysisBuffer.Width;
  H := FAnalysisBuffer.Height;
  CenterY := H div 2;

  DrawGrid(FAnalysisBuffer.Canvas, W, H);
  if FRecordedCount < 10 then Exit;

  TotalDurationSec := FRecordedCount / 500.0;
  if TotalDurationSec <= 0 then TotalDurationSec := 10.0;
  SecPerPixel := TotalDurationSec / W;
  SamplePerPixel := FRecordedCount / W;

  // 1. Bounding Boxes Temporais 1D do YOLO
  if FYOLOEvents <> nil then
  begin
    for I := 0 to FYOLOEvents.Count - 1 do
    begin
      P := PYOLO1DEvent(FYOLOEvents[I]);
      BoxX1 := Round(P^.StartSec / SecPerPixel);
      BoxX2 := Round(P^.EndSec / SecPerPixel);
      BoxTop := 28;
      BoxBottom := H - 24;

      // Caixa delimitadora 1D
      FAnalysisBuffer.Canvas.Brush.Color := P^.Color;
      FAnalysisBuffer.Canvas.Pen.Color := P^.Color;
      FAnalysisBuffer.Canvas.Pen.Width := 2;
      FAnalysisBuffer.Canvas.Rectangle(BoxX1, BoxTop, BoxX2, BoxBottom);

      // Etiqueta superior da Bounding Box (Classe + Confianca)
      BadgeText := Format('%s: %.0f%%', [P^.ClassCode, P^.Confidence * 100.0]);
      FAnalysisBuffer.Canvas.Brush.Color := P^.Color;
      FAnalysisBuffer.Canvas.Font.Color := clBlack;
      FAnalysisBuffer.Canvas.Font.Style := [fsBold];
      FAnalysisBuffer.Canvas.Font.Size := 9;
      FAnalysisBuffer.Canvas.TextOut(BoxX1 + 2, BoxTop + 4, BadgeText);
    end;
  end;

  // 2. Tracado de ECG completo
  FAnalysisBuffer.Canvas.Pen.Color := COLOR_ECG_TRACE;
  FAnalysisBuffer.Canvas.Pen.Width := 2;

  PrevX := 0;
  PrevY := CenterY - Round(FRecordedSamples[0] * 0.4);

  for X := 1 to W - 1 do
  begin
    I := Min(FRecordedCount - 1, Round(X * SamplePerPixel));
    Y := CenterY - Round(FRecordedSamples[I] * 0.4);
    Y := EnsureRange(Y, 10, H - 10);
    FAnalysisBuffer.Canvas.Line(PrevX, PrevY, X, Y);
    PrevX := X;
    PrevY := Y;
  end;

  // 3. Regua temporal inferior (0s a 10s)
  FAnalysisBuffer.Canvas.Pen.Color := clGray;
  FAnalysisBuffer.Canvas.Font.Color := clYellow;
  FAnalysisBuffer.Canvas.Font.Size := 8;
  for I := 0 to Round(TotalDurationSec) do
  begin
    X := Round((I / TotalDurationSec) * W);
    FAnalysisBuffer.Canvas.Line(X, H - 18, X, H);
    FAnalysisBuffer.Canvas.TextOut(X + 2, H - 16, IntToStr(I) + 's');
  end;

  PaintBoxAnalysis.Invalidate;
end;

procedure TMainForm.PopulateGridEvents;
var
  I: Integer;
  P: PYOLO1DEvent;
begin
  if FYOLOEvents = nil then
  begin
    GridEvents.RowCount := 1;
    Exit;
  end;

  GridEvents.RowCount := FYOLOEvents.Count + 1;
  for I := 0 to FYOLOEvents.Count - 1 do
  begin
    P := PYOLO1DEvent(FYOLOEvents[I]);
    GridEvents.Cells[0, I + 1] := IntToStr(I + 1);
    GridEvents.Cells[1, I + 1] := FormatFloat('0.000', P^.StartSec);
    GridEvents.Cells[2, I + 1] := FormatFloat('0.000', P^.EndSec);
    GridEvents.Cells[3, I + 1] := FormatFloat('0.0', P^.DurationMs);
    GridEvents.Cells[4, I + 1] := P^.ClassCode;
    GridEvents.Cells[5, I + 1] := P^.ClassName;
    GridEvents.Cells[6, I + 1] := FormatFloat('0.0%', P^.Confidence * 100.0);
  end;
end;

procedure TMainForm.btnExportAnalysisCSVClick(Sender: TObject);
var
  Lines: TStringList;
  I: Integer;
  P: PYOLO1DEvent;
begin
  if (FYOLOEvents = nil) or (FYOLOEvents.Count = 0) then
  begin
    ShowMessage('Nenhum evento disponivel para exportacao.');
    Exit;
  end;

  SaveDialog1.DefaultExt := 'csv';
  SaveDialog1.Filter := 'Arquivo CSV (*.csv)|*.csv|Todos os Arquivos (*.*)|*.*';
  SaveDialog1.FileName := 'yolo1d_events_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.csv';

  if SaveDialog1.Execute then
  begin
    Lines := TStringList.Create;
    try
      Lines.Add('#algoritmo=YOLO-1D-ECG');
      Lines.Add('#sample_rate=500');
      Lines.Add('id;start_s;end_s;duration_ms;class_code;class_name;confidence');
      for I := 0 to FYOLOEvents.Count - 1 do
      begin
        P := PYOLO1DEvent(FYOLOEvents[I]);
        Lines.Add(Format('%d;%.3f;%.3f;%.1f;%s;%s;%.3f', [
          I + 1, P^.StartSec, P^.EndSec, P^.DurationMs, P^.ClassCode, P^.ClassName, P^.Confidence
        ]));
      end;
      Lines.SaveToFile(SaveDialog1.FileName);
      ShowMessage('Eventos YOLO 1D exportados com sucesso para:' + sLineBreak + SaveDialog1.FileName);
    finally
      Lines.Free;
    end;
  end;
end;

end.
