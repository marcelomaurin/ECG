unit ecgdatabase;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, sqldb, sqlite3conn, sqlite3dyn, DB,
  ecgsource;

type
  { TECGDatabase }
  TECGDatabase = class
  private
    FConn: TSQLite3Connection;
    FTrans: TSQLTransaction;
    FDBPath: String;
    FCurrentExamId: Int64;
    FIsOpen: Boolean;
    FLock: TCriticalSection;

    procedure CreateTables;
  public
    constructor Create(const ADBPath: String);
    destructor Destroy; override;

    procedure Open;
    procedure Close;

    function StartExam(const APaciente: String = 'Anonimo'; const ANotas: String = ''): Int64;
    procedure FinishExam(const AExamId: Int64; const ADuracaoSeg: Double; const ABpmMedio: Double);

    procedure InsertSamplesBatch(const AExamId: Int64; const ASamples: array of TECGSample; ACount: Integer);
    function LoadExamSamples(const AExamId: Int64; var ASamples: array of Double; out ACount: Integer): Boolean;

    property CurrentExamId: Int64 read FCurrentExamId;
    property IsOpen: Boolean read FIsOpen;
    property DBPath: String read FDBPath;
  end;

implementation

constructor TECGDatabase.Create(const ADBPath: String);
begin
  inherited Create;
  FDBPath := ADBPath;
  FIsOpen := False;
  FCurrentExamId := 0;
  FLock := TCriticalSection.Create;

  // Localiza a biblioteca sqlite3.dll na mesma pasta do executavel
  SQLiteDefaultLibrary := ExtractFilePath(ParamStr(0)) + 'sqlite3.dll';
  if not FileExists(SQLiteDefaultLibrary) then
    SQLiteDefaultLibrary := 'sqlite3.dll';

  FConn := TSQLite3Connection.Create(nil);
  FTrans := TSQLTransaction.Create(nil);
  FConn.Transaction := FTrans;
  FConn.DatabaseName := FDBPath;
end;

destructor TECGDatabase.Destroy;
begin
  Close;
  FTrans.Free;
  FConn.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TECGDatabase.Open;
begin
  if FIsOpen then Exit;
  FLock.Acquire;
  try
    try
      FConn.Open;
      FTrans.StartTransaction;
      CreateTables;
      FTrans.CommitRetaining;
      FIsOpen := True;
    except
      on E: Exception do
      begin
        if FTrans.Active then
          try FTrans.Rollback; except end;
        FIsOpen := False;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TECGDatabase.Close;
begin
  if not FIsOpen then Exit;
  FLock.Acquire;
  try
    try
      if FTrans.Active then
        FTrans.Commit;
      FConn.Close;
    except
    end;
    FIsOpen := False;
  finally
    FLock.Release;
  end;
end;

procedure TECGDatabase.CreateTables;
begin
  FConn.ExecuteDirect(
    'CREATE TABLE IF NOT EXISTS exames (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  data_hora TEXT NOT NULL,' +
    '  taxa_amostragem INTEGER DEFAULT 500,' +
    '  duracao_seg REAL DEFAULT 0.0,' +
    '  paciente TEXT,' +
    '  notas TEXT,' +
    '  bpm_medio REAL DEFAULT 0.0' +
    ');'
  );

  FConn.ExecuteDirect(
    'CREATE TABLE IF NOT EXISTS amostras (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  exame_id INTEGER NOT NULL,' +
    '  timestamp_us INTEGER NOT NULL,' +
    '  raw_adc REAL NOT NULL,' +
    '  filtered_val REAL NOT NULL,' +
    '  lead_off INTEGER DEFAULT 0,' +
    '  r_peak INTEGER DEFAULT 0' +
    ');'
  );

  FConn.ExecuteDirect(
    'CREATE TABLE IF NOT EXISTS eventos_yolo (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  exame_id INTEGER NOT NULL,' +
    '  start_s REAL NOT NULL,' +
    '  end_s REAL NOT NULL,' +
    '  duration_ms REAL NOT NULL,' +
    '  class_code TEXT NOT NULL,' +
    '  class_name TEXT NOT NULL,' +
    '  confidence REAL NOT NULL' +
    ');'
  );

  FConn.ExecuteDirect('CREATE INDEX IF NOT EXISTS idx_amostras_exame ON amostras(exame_id);');
  FConn.ExecuteDirect('CREATE INDEX IF NOT EXISTS idx_eventos_exame ON eventos_yolo(exame_id);');

  // PRAGMAs para desempenho maximo e concorrencia segura no SQLite
  try FConn.ExecuteDirect('PRAGMA journal_mode = WAL;'); except end;
  try FConn.ExecuteDirect('PRAGMA synchronous = NORMAL;'); except end;
end;

function TECGDatabase.StartExam(const APaciente: String; const ANotas: String): Int64;
var
  Q: TSQLQuery;
  DataHoraStr: String;
begin
  Result := 0;
  if not FIsOpen then Open;
  if not FIsOpen then Exit;

  FLock.Acquire;
  try
    try
      if not FTrans.Active then
        FTrans.StartTransaction;

      DataHoraStr := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
      Q := TSQLQuery.Create(nil);
      try
        Q.DataBase := FConn;
        Q.Transaction := FTrans;
        Q.SQL.Text := 'INSERT INTO exames (data_hora, taxa_amostragem, paciente, notas) ' +
                      'VALUES (:data_hora, 500, :paciente, :notas);';
        Q.Params.ParamByName('data_hora').AsString := DataHoraStr;
        Q.Params.ParamByName('paciente').AsString := APaciente;
        Q.Params.ParamByName('notas').AsString := ANotas;
        Q.ExecSQL;
        FTrans.CommitRetaining;

        Q.SQL.Text := 'SELECT last_insert_rowid() AS last_id;';
        Q.Open;
        if not Q.EOF then
          Result := Q.FieldByName('last_id').AsLargeInt;
        Q.Close;

        FCurrentExamId := Result;
      finally
        Q.Free;
      end;
    except
      on E: Exception do
      begin
        if FTrans.Active then
          try FTrans.Rollback; except end;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TECGDatabase.FinishExam(const AExamId: Int64; const ADuracaoSeg: Double; const ABpmMedio: Double);
var
  Q: TSQLQuery;
begin
  if (AExamId <= 0) or not FIsOpen then Exit;

  FLock.Acquire;
  try
    try
      if not FTrans.Active then
        FTrans.StartTransaction;

      Q := TSQLQuery.Create(nil);
      try
        Q.DataBase := FConn;
        Q.Transaction := FTrans;
        Q.SQL.Text := 'UPDATE exames SET duracao_seg = :duracao, bpm_medio = :bpm WHERE id = :id;';
        Q.Params.ParamByName('duracao').AsFloat := ADuracaoSeg;
        Q.Params.ParamByName('bpm').AsFloat := ABpmMedio;
        Q.Params.ParamByName('id').AsLargeInt := AExamId;
        Q.ExecSQL;
        FTrans.CommitRetaining;
      finally
        Q.Free;
      end;
    except
      on E: Exception do
      begin
        if FTrans.Active then
          try FTrans.Rollback; except end;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

procedure TECGDatabase.InsertSamplesBatch(const AExamId: Int64; const ASamples: array of TECGSample; ACount: Integer);
var
  Q: TSQLQuery;
  I: Integer;
begin
  if (AExamId <= 0) or (ACount <= 0) or not FIsOpen then Exit;

  FLock.Acquire;
  try
    try
      if not FTrans.Active then
        FTrans.StartTransaction;

      Q := TSQLQuery.Create(nil);
      try
        Q.DataBase := FConn;
        Q.Transaction := FTrans;
        Q.SQL.Text := 'INSERT INTO amostras (exame_id, timestamp_us, raw_adc, filtered_val, lead_off, r_peak) ' +
                      'VALUES (:exame_id, :timestamp_us, :raw_adc, :filtered_val, :lead_off, :r_peak);';

        for I := 0 to ACount - 1 do
        begin
          Q.Params.ParamByName('exame_id').AsLargeInt := AExamId;
          Q.Params.ParamByName('timestamp_us').AsLargeInt := ASamples[I].TimestampUS;
          Q.Params.ParamByName('raw_adc').AsFloat := ASamples[I].RawValue;
          Q.Params.ParamByName('filtered_val').AsFloat := ASamples[I].FilteredValue;
          Q.Params.ParamByName('lead_off').AsInteger := Ord(ASamples[I].LeadOff);
          Q.Params.ParamByName('r_peak').AsInteger := Ord(ASamples[I].IsPeak);
          Q.ExecSQL;
        end;
        FTrans.CommitRetaining;
      finally
        Q.Free;
      end;
    except
      on E: Exception do
      begin
        if FTrans.Active then
          try FTrans.Rollback; except end;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TECGDatabase.LoadExamSamples(const AExamId: Int64; var ASamples: array of Double; out ACount: Integer): Boolean;
var
  Q: TSQLQuery;
  MaxSamples: Integer;
begin
  Result := False;
  ACount := 0;
  MaxSamples := Length(ASamples);
  if (AExamId <= 0) or not FIsOpen then Exit;

  FLock.Acquire;
  try
    try
      if not FTrans.Active then
        FTrans.StartTransaction;

      Q := TSQLQuery.Create(nil);
      try
        Q.DataBase := FConn;
        Q.Transaction := FTrans;
        Q.SQL.Text := 'SELECT filtered_val FROM amostras WHERE exame_id = :id ORDER BY id ASC LIMIT :max_s;';
        Q.Params.ParamByName('id').AsLargeInt := AExamId;
        Q.Params.ParamByName('max_s').AsInteger := MaxSamples;
        Q.Open;
        while not Q.EOF and (ACount < MaxSamples) do
        begin
          ASamples[ACount] := Q.FieldByName('filtered_val').AsFloat;
          Inc(ACount);
          Q.Next;
        end;
        Q.Close;
        Result := (ACount > 0);
      finally
        Q.Free;
      end;
    except
      on E: Exception do
      begin
        if FTrans.Active then
          try FTrans.Rollback; except end;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

end.
