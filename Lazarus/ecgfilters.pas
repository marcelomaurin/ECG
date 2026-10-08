unit ecgfilters;
{$mode objfpc}{$H+}
interface
uses Math;
type
  TFilterKind = (fkHighPass, fkLowPass, fkNotch);
  TECGBiquad = class
  private
    B0, B1, B2, A1, A2, Z1, Z2: Double;
  public
    constructor Create(Kind: TFilterKind; Rate, Frequency, Q: Double);
    procedure Reset;
    function Process(X: Double): Double;
  end;
implementation
constructor TECGBiquad.Create(Kind: TFilterKind; Rate, Frequency, Q: Double);
var W, C, Alpha, A0: Double;
begin
  inherited Create;
  W := 2 * Pi * Frequency / Rate;
  C := Cos(W); Alpha := Sin(W) / (2 * Q); A0 := 1 + Alpha;
  case Kind of
    fkHighPass: begin B0 := (1+C)/2; B1 := -(1+C); B2 := B0; end;
    fkLowPass: begin B0 := (1-C)/2; B1 := 1-C; B2 := B0; end;
    fkNotch: begin B0 := 1; B1 := -2*C; B2 := 1; end;
  end;
  A1 := -2*C/A0; A2 := (1-Alpha)/A0;
  B0 := B0/A0; B1 := B1/A0; B2 := B2/A0;
  Reset;
end;
procedure TECGBiquad.Reset;
begin Z1 := 0; Z2 := 0; end;
function TECGBiquad.Process(X: Double): Double;
begin
  Result := B0*X + Z1;
  Z1 := B1*X - A1*Result + Z2;
  Z2 := B2*X - A2*Result;
end;
end.
