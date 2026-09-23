program ECGMonitor;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, main, ecgtypes, ecgdsp, ecgserial, ecgaireport, ecgdatabase, ecgyolo,
  ecgsource, ecgsimulator, ecgsyntheticdataset;

{$R *.res}

begin
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
