unit uWinderModel;

{ Physics model (program 2) of a centre winder with contact (lay-on) roll
  winding BOPA (Nylon) film onto a mill roll.

  Layout: winder (mill roll) on the right, contact roll on the left at the
  same horizontal centre line, tension (load-cell) roll directly below the
  contact roll with the same diameter. The web runs horizontally under the
  tension roll, wraps it 90 deg, then goes vertically up into the nip where
  the contact roll presses it onto the winder. Contact + tension roll sit on
  one carriage that a pneumatic cylinder pushes against the growing roll.

  Model chain per wound layer:
    1. Web tension with hyperbolic taper      Tw(R)
    2. Nip load with hyperbolic taper          N(R)
    3. Wound-in-tension (Pfeiffer / Good)      WIT = Tw + mu*N
    4. Entrained air (Knox-Sweeney foil bearing, reduced by nip)
    5. Radial pressure from outer layers       P_i = alpha * Sum(WIT_j / R_j), j>i
    6. Gap compression: air (Boyle) + asperities (exponential)
    7. Local packing ratio k = t/(t+gap) -> local density rho = k*rho_film
  All units SI inside the model (m, N, Pa, s, kg). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  TWinderParams = record
    // film (BOPA / Nylon 6)
    ThickUm: Double;        // film thickness [um] 10..25
    WidthMm: Double;        // web width [mm]
    LengthM: Double;        // target roll length [m] 25000..50000
    RhoFilm: Double;        // film density [kg/m3]
    EFilmMPa: Double;       // MD tensile modulus [MPa]
    YieldMPa: Double;       // yield stress [MPa]
    RqUm: Double;           // combined surface roughness Rq (both faces) [um]
    COF: Double;            // film/film coefficient of friction [-]
    // machine
    CoreDiaMm: Double;      // mill roll (winding core) diameter [mm]
    ContactDiaMm: Double;   // contact roll diameter [mm] (= tension roll diameter)
    RollGapMm: Double;      // surface gap contact roll <-> tension roll [mm]
    TRollWallMm: Double;    // tension roll steel shell wall [mm]
    CylBoreMm: Double;      // carriage cylinder bore [mm]
    CylCount: Double;       // number of cylinders (one per side)
    RubberEMPa: Double;     // contact roll rubber cover modulus [MPa]
    RubberNu: Double;       // rubber Poisson ratio [-]
    SpeedMpm: Double;       // line speed [m/min] 120..250
    TensionNm: Double;      // web tension at core [N/m width]
    TaperPct: Double;       // tension taper [%]
    NipNm: Double;          // nip load at core [N/m width]
    NipTaperPct: Double;    // nip load taper [%]
    // physics coefficients
    AirVisc: Double;        // air dynamic viscosity [Pa.s]
    Patm: Double;           // atmospheric pressure [Pa]
    NipAirFactor: Double;   // Kn: air film reduction by nip [-] (empirical)
    PressAtten: Double;     // alpha: radial pressure attenuation [-] (empirical)
    AspPressKPa: Double;    // Pasp: asperity compression constant [kPa]
    // warning limits
    MaxCorePressMPa: Double;
    MaxStressRatio: Double; // winding stress / yield
  end;

  TLayer = record
    R: Double;      // as-wound inner radius of the layer [m]
    LCum: Double;   // cumulative wound length at end of layer [m]
    Tw: Double;     // web tension [N/m]
    Nip: Double;    // nip load [N/m]
    WIT: Double;    // wound-in tension [N/m]
    HAir: Double;   // trapped air film at winding [m]
    P: Double;      // radial (interlayer) pressure [Pa]
    Gap: Double;    // interlayer gap after compression [m]
    K: Double;      // packing ratio t/(t+gap) [-]
    Rc: Double;     // compressed outer radius of the layer [m]
  end;

  TAirInfo = record
    U: Double;        // surface speed [m/s]
    REq: Double;      // equivalent radius [m]
    TEff: Double;     // effective tension Tw+N [N/m]
    HFoil: Double;    // Knox-Sweeney air film [m]
    HNip: Double;     // air film under nip [m]
    HCrit: Double;    // 3*Rq, air bleeds through asperities below this [m]
    HTrapped: Double; // trapped air layer [m]
  end;

  TNipInfo = record
    REq: Double;      // equivalent radius [m]
    EStar: Double;    // contact modulus [Pa]
    HalfB: Double;    // Hertz half contact width [m]
    PMax: Double;     // peak nip pressure [Pa]
    PMean: Double;    // mean nip pressure [Pa]
  end;

  { TWinderSim }

  TWinderSim = class
  private
    procedure AddLayer;
  public
    P: TWinderParams;
    Layers: array of TLayer;
    Count: Integer;
    WoundLen: Double;   // wound length [m]
    PartLen: Double;    // length in the current (incomplete) wrap [m]
    SimTime: Double;    // process time [s]
    RWound: Double;     // as-wound outer radius [m]
    Finished: Boolean;
    // solved summary
    ROuterComp: Double; // compressed outer radius [m]
    KAvg: Double;       // average packing ratio
    RhoAvg: Double;     // average roll density [kg/m3]
    PCore: Double;      // pressure on first layer [Pa]
    KOuter: Double;     // packing ratio of outer layers
    KMin: Double;
    constructor Create;
    procedure SetDefaults;
    procedure Reset;
    procedure Step(dt: Double; DoSolve: Boolean = True);
    procedure RunToEnd;
    procedure Solve;
    // basic quantities
    function T: Double;
    function W: Double;
    function R0: Double;
    function RContact: Double;
    function U: Double;
    function GapRough0: Double;
    function TensionAt(R: Double): Double;
    function NipAt(R: Double): Double;
    function AirAt(R, Tw, Nip: Double): TAirInfo;
    function NipCalc(R, Nip: Double): TNipInfo;
    function IdealDia(L: Double): Double;
    function PredictDia(L, K: Double): Double;
    function CurDia: Double;
    function RollRpm: Double;
    function ContactRpm: Double;
    function TorqueNm: Double;
    function PowerW: Double;
    function FilmMassKg(L: Double): Double;
    function TimeTotal: Double;
    function TimeRemain: Double;
    function WindStressMPa: Double;
    // tension roll / span / carriage (program 2)
    function RTension: Double;
    function WrapRad: Double;
    function SpanM: Double;
    function LoadCellN: Double;
    function TRollRpm: Double;
    function TRollMassKg: Double;
    function TRollInertia: Double;
    function SpanStrain: Double;
    function SpanTimeConst: Double;
    function CylForceN: Double;
    function CylPressBar: Double;
    function CarriageStrokeMm: Double;
    procedure GetWarnings(SL: TStrings);
  end;

var
  FSDot: TFormatSettings;

function FF(v: Double; d: Integer): string;
function HMS(sec: Double): string;

implementation

function FF(v: Double; d: Integer): string;
begin
  Result := FloatToStrF(v, ffFixed, 15, d, FSDot);
end;

function HMS(sec: Double): string;
var
  s: Int64;
begin
  if sec < 0 then sec := 0;
  s := Round(sec);
  Result := Format('%d:%.2d:%.2d', [s div 3600, (s mod 3600) div 60, s mod 60]);
end;

{ TWinderSim }

constructor TWinderSim.Create;
begin
  inherited Create;
  SetDefaults;
  Reset;
end;

procedure TWinderSim.SetDefaults;
begin
  with P do
  begin
    ThickUm := 15;
    WidthMm := 5120;
    LengthM := 40000;
    RhoFilm := 1150;
    EFilmMPa := 3000;
    YieldMPa := 90;
    RqUm := 0.07;
    COF := 0.40;
    CoreDiaMm := 450;
    ContactDiaMm := 250;
    RollGapMm := 60;
    TRollWallMm := 8;
    CylBoreMm := 80;
    CylCount := 2;
    RubberEMPa := 6;
    RubberNu := 0.49;
    SpeedMpm := 200;
    TensionNm := 100;
    TaperPct := 25;
    NipNm := 300;
    NipTaperPct := 0;
    AirVisc := 1.81e-5;
    Patm := 101325;
    NipAirFactor := 0.15;
    PressAtten := 0.20;
    AspPressKPa := 300;
    MaxCorePressMPa := 3.0;
    MaxStressRatio := 0.25;
  end;
end;

procedure TWinderSim.Reset;
begin
  Count := 0;
  SetLength(Layers, 0);
  WoundLen := 0;
  PartLen := 0;
  SimTime := 0;
  RWound := R0;
  Finished := False;
  Solve;
end;

function TWinderSim.T: Double;
begin
  Result := P.ThickUm * 1e-6;
end;

function TWinderSim.W: Double;
begin
  Result := P.WidthMm * 1e-3;
end;

function TWinderSim.R0: Double;
begin
  Result := P.CoreDiaMm * 0.5e-3;
end;

function TWinderSim.RContact: Double;
begin
  Result := P.ContactDiaMm * 0.5e-3;
end;

function TWinderSim.U: Double;
begin
  Result := P.SpeedMpm / 60;
end;

function TWinderSim.GapRough0: Double;
begin
  // uncompressed asperity separation ~ 2*Rq
  Result := 2 * P.RqUm * 1e-6;
end;

function TWinderSim.TensionAt(R: Double): Double;
begin
  // hyperbolic taper: T = T0 * (1 - taper*(1 - R0/R))
  Result := P.TensionNm * (1 - P.TaperPct / 100 * (1 - R0 / R));
end;

function TWinderSim.NipAt(R: Double): Double;
begin
  Result := P.NipNm * (1 - P.NipTaperPct / 100 * (1 - R0 / R));
end;

function TWinderSim.AirAt(R, Tw, Nip: Double): TAirInfo;
begin
  Result.U := U;
  Result.REq := R * RContact / (R + RContact);
  Result.TEff := Tw + Nip;
  if Result.TEff < 1 then Result.TEff := 1;
  // Knox-Sweeney: h0 = 0.643 * R * (12*mu*U / T)^(2/3)
  Result.HFoil := 0.643 * Result.REq *
    Power(12 * P.AirVisc * Result.U / Result.TEff, 2 / 3);
  Result.HNip := P.NipAirFactor * Result.HFoil;
  Result.HCrit := 3 * P.RqUm * 1e-6;
  Result.HTrapped := Max(0, Result.HNip - Result.HCrit);
end;

function TWinderSim.NipCalc(R, Nip: Double): TNipInfo;
begin
  Result.REq := R * RContact / (R + RContact);
  // roll stack is far stiffer than rubber: E* = E_r/(1-nu^2)
  Result.EStar := P.RubberEMPa * 1e6 / (1 - Sqr(P.RubberNu));
  // Hertz line contact
  Result.HalfB := Sqrt(4 * Nip * Result.REq / (Pi * Result.EStar));
  if Result.HalfB > 0 then
  begin
    Result.PMax := 2 * Nip / (Pi * Result.HalfB);
    Result.PMean := Nip / (2 * Result.HalfB);
  end
  else
  begin
    Result.PMax := 0;
    Result.PMean := 0;
  end;
end;

procedure TWinderSim.AddLayer;
var
  air: TAirInfo;
begin
  if Count >= Length(Layers) then
    SetLength(Layers, Max(1024, Count * 2));
  with Layers[Count] do
  begin
    R := RWound;
    LCum := WoundLen;
    Tw := TensionAt(RWound);
    Nip := NipAt(RWound);
    WIT := Tw + Self.P.COF * Nip;
    air := AirAt(RWound, Tw, Nip);
    HAir := air.HTrapped;
    P := 0;
    Gap := HAir + GapRough0;
    K := T / (T + Gap);
    Rc := 0;
  end;
  RWound := RWound + T + Layers[Count].HAir + GapRough0;
  Inc(Count);
end;

procedure TWinderSim.Step(dt: Double; DoSolve: Boolean);
var
  dL, circ, rem: Double;
begin
  if Finished or (dt <= 0) then Exit;
  dL := U * dt;
  if WoundLen + dL >= P.LengthM then
  begin
    dL := P.LengthM - WoundLen;
    dt := dL / U;
  end;
  SimTime := SimTime + dt;
  while dL > 1e-9 do
  begin
    circ := 2 * Pi * (RWound + 0.5 * T);
    rem := circ - PartLen;
    if dL >= rem then
    begin
      dL := dL - rem;
      WoundLen := WoundLen + rem;
      PartLen := 0;
      AddLayer;
    end
    else
    begin
      PartLen := PartLen + dL;
      WoundLen := WoundLen + dL;
      dL := 0;
    end;
  end;
  if WoundLen >= P.LengthM - 1e-6 then
  begin
    WoundLen := P.LengthM;
    if PartLen > 0 then AddLayer;
    PartLen := 0;
    Finished := True;
  end;
  if DoSolve then Solve;
end;

procedure TWinderSim.RunToEnd;
begin
  while not Finished do
    Step(10, False);
  Solve;
end;

procedure TWinderSim.Solve;
var
  i, n0: Integer;
  pr, rr, alpha, pasp, g0, ksum, patm, area, prevL: Double;
begin
  patm := P.Patm;
  if Count = 0 then
  begin
    ROuterComp := R0;
    KAvg := 1;
    RhoAvg := P.RhoFilm;
    PCore := 0;
    KOuter := 1;
    KMin := 1;
    Exit;
  end;
  alpha := P.PressAtten;
  pasp := Max(1, P.AspPressKPa * 1000);
  g0 := GapRough0;
  // radial pressure: accumulate from the outermost layer inward
  pr := 0;
  for i := Count - 1 downto 0 do
  begin
    Layers[i].P := pr;
    pr := pr + alpha * Layers[i].WIT / (Layers[i].R + 0.5 * T);
  end;
  // compressed gaps and radii from the core outward
  rr := R0;
  area := 0;
  prevL := 0;
  KMin := 1;
  for i := 0 to Count - 1 do
    with Layers[i] do
    begin
      // Layers[i].P shadows Self.P inside this with-block, so use patm
      Gap := HAir * patm / (patm + P) + g0 * Exp(-P / pasp);
      K := T / (T + Gap);
      if K < KMin then KMin := K;
      // area conservation: each wrap occupies len*(t+gap) of cross-section,
      // so the film length is kept when the gaps compress
      // (rr, not r: inside this with-block r would bind to Layers[i].R)
      area := area + (LCum - prevL) * (T + Gap);
      prevL := LCum;
      rr := Sqrt(Sqr(R0) + area / Pi);
      Rc := rr;
    end;
  ROuterComp := rr;
  if rr > R0 then
    KAvg := Min(1, WoundLen * T / (Pi * (Sqr(rr) - Sqr(R0))))
  else
    KAvg := 1;
  RhoAvg := KAvg * P.RhoFilm;
  PCore := Layers[0].P;
  n0 := Max(0, Count - Max(20, Count div 100));
  ksum := 0;
  for i := n0 to Count - 1 do
    ksum := ksum + Layers[i].K;
  KOuter := ksum / (Count - n0);
end;

function TWinderSim.IdealDia(L: Double): Double;
begin
  // k = 1 : D = sqrt(D0^2 + 4*L*t/pi)
  Result := Sqrt(Sqr(2 * R0) + 4 * L * T / Pi);
end;

function TWinderSim.PredictDia(L, K: Double): Double;
begin
  if K <= 0 then K := 1;
  Result := Sqrt(Sqr(2 * R0) + 4 * L * T / (Pi * K));
end;

function TWinderSim.CurDia: Double;
begin
  Result := 2 * ROuterComp;
end;

function TWinderSim.RollRpm: Double;
begin
  Result := P.SpeedMpm / (Pi * CurDia);
end;

function TWinderSim.ContactRpm: Double;
begin
  Result := P.SpeedMpm / (Pi * 2 * RContact);
end;

function TWinderSim.TorqueNm: Double;
begin
  // centre drive torque to hold web tension: M = Tw*W*R
  Result := TensionAt(RWound) * W * ROuterComp;
end;

function TWinderSim.PowerW: Double;
begin
  Result := TensionAt(RWound) * W * U;
end;

function TWinderSim.FilmMassKg(L: Double): Double;
begin
  Result := P.RhoFilm * T * W * L;
end;

function TWinderSim.TimeTotal: Double;
begin
  Result := P.LengthM / U;
end;

function TWinderSim.TimeRemain: Double;
begin
  Result := (P.LengthM - WoundLen) / U;
end;

function TWinderSim.WindStressMPa: Double;
begin
  Result := TensionAt(RWound) / T * 1e-6;
end;

function TWinderSim.RTension: Double;
begin
  Result := RContact;   // same diameter as the contact roll
end;

function TWinderSim.WrapRad: Double;
begin
  // horizontal infeed -> vertical outfeed
  Result := Pi / 2;
end;

function TWinderSim.SpanM: Double;
begin
  // free span from tension roll tangent point up to the nip
  // = centre distance tension roll <-> contact roll
  Result := 2 * RContact + P.RollGapMm * 1e-3;
end;

function TWinderSim.LoadCellN: Double;
begin
  // resultant web force on the roll: F = 2*T*W*sin(wrap/2)
  Result := 2 * TensionAt(RWound) * W * Sin(WrapRad / 2);
end;

function TWinderSim.TRollRpm: Double;
begin
  Result := P.SpeedMpm / (Pi * 2 * RTension);
end;

function TWinderSim.TRollMassKg: Double;
var
  ri: Double;
begin
  // steel shell, face = web width + 200 mm
  ri := Max(0, RTension - P.TRollWallMm * 1e-3);
  Result := 7850 * Pi * (Sqr(RTension) - Sqr(ri)) * (W + 0.2);
end;

function TWinderSim.TRollInertia: Double;
var
  ri: Double;
begin
  ri := Max(0, RTension - P.TRollWallMm * 1e-3);
  Result := 0.5 * TRollMassKg * (Sqr(RTension) + Sqr(ri));
end;

function TWinderSim.SpanStrain: Double;
begin
  Result := TensionAt(RWound) / (P.EFilmMPa * 1e6 * T);
end;

function TWinderSim.SpanTimeConst: Double;
begin
  // web span transport time constant tau = L/V
  Result := SpanM / U;
end;

function TWinderSim.CylForceN: Double;
begin
  Result := NipAt(RWound) * W;
end;

function TWinderSim.CylPressBar: Double;
begin
  Result := CylForceN / (Max(1, P.CylCount) * Pi / 4 * Sqr(P.CylBoreMm * 1e-3)) / 1e5;
end;

function TWinderSim.CarriageStrokeMm: Double;
begin
  Result := (ROuterComp - R0) * 1000;
end;

procedure TWinderSim.GetWarnings(SL: TStrings);
var
  air: TAirInfo;
  nip: TNipInfo;
begin
  SL.Clear;
  air := AirAt(RWound, TensionAt(RWound), NipAt(RWound));
  nip := NipCalc(RWound, NipAt(RWound));
  if air.HTrapped > 0 then
    SL.Add(Format('[AIR] Air film under nip %s um > 3Rq %s um -> air trapped, ' +
      'soft roll / telescoping risk. Increase nip load or reduce speed.',
      [FF(air.HNip * 1e6, 3), FF(air.HCrit * 1e6, 3)]));
  if WindStressMPa > P.MaxStressRatio * P.YieldMPa then
    SL.Add(Format('[TENSION] Winding stress %s MPa > %s%% of yield (%s MPa) -> ' +
      'film stretch / gauge band / core crush risk.',
      [FF(WindStressMPa, 2), FF(P.MaxStressRatio * 100, 0), FF(P.YieldMPa, 0)]));
  if PCore > P.MaxCorePressMPa * 1e6 then
    SL.Add(Format('[CORE] Core pressure %s MPa > %s MPa -> blocking / core crush risk. ' +
      'Increase tension taper.', [FF(PCore * 1e-6, 2), FF(P.MaxCorePressMPa, 2)]));
  if (Count > 100) and (KOuter < 0.95) then
    SL.Add(Format('[SOFT] Outer layer packing k = %s < 0.95 -> soft outer layers, ' +
      'handling damage risk.', [FF(KOuter, 4)]));
  if TensionAt(RWound) < 0.3 * P.TensionNm then
    SL.Add('[TAPER] Tension dropped below 30% of start tension -> wrinkle risk.');
  if nip.PMax > 1e6 then
    SL.Add(Format('[NIP] Peak nip pressure %s kPa high -> pressure marks.',
      [FF(nip.PMax * 1e-3, 0)]));
  if CylPressBar > 6 then
    SL.Add(Format('[CYL] Cylinder pressure %s bar > 6 bar plant air -> use larger bore.',
      [FF(CylPressBar, 2)]));
  if SL.Count = 0 then
    SL.Add('OK - no warnings.');
end;

initialization
  FSDot := DefaultFormatSettings;
  FSDot.DecimalSeparator := '.';
  FSDot.ThousandSeparator := ',';

end.
