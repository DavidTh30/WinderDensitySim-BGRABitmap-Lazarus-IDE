unit uWinderModel;

{ Physics model (program 3) of a centre winder with a contact (lay-on) roll
  winding BOPA (Nylon) film onto a mill roll.

  Layout: winder (mill roll) on the right. Contact roll on the left at the
  same horizontal centre line, driven forward/back by a LINEAR MOTOR in
  force control (sets the nip load) or retracted. Tension (load-cell) roll
  below the contact roll, same diameter, driven forward/back by a SERVO
  ball-screw axis. Its position is a "lead" relative to the contact roll:
    lead < 0 : tension roll behind  -> web wraps the contact roll into the nip
    lead = 0 : web runs vertically straight into the nip
    lead > 0 : tension roll ahead   -> web touches the winder BEFORE the nip
                                       (pre-wrap, entrains extra air)
  Model chain per wound layer:
    1. Web tension with hyperbolic taper      Tw(R)
    2. Nip load with taper (0 when retracted) N(R)
    3. Wound-in-tension                       WIT = Tw + mu*N
    4. Entrained air: nip foil bearing + pre-wrap air, or tension-only air
    5. Radial pressure from outer layers       P_i = alpha * Sum(WIT_j / R_j)
    6. Gap compression: air (Boyle) + asperities (exponential)
    7. Local packing ratio k = t/(t+gap)  -> rho = k*rho_film
  Geometry uses winder centre as origin, x to the right, y DOWN (screen).
  All units SI inside the model (m, N, Pa, s, kg). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  CM_PRESS = 0;     // contact roll forward, force control
  CM_RETRACT = 1;   // contact roll backward, position control

type
  TWinderParams = record
    // film (BOPA / Nylon 6)
    ThickUm, WidthMm, LengthM, RhoFilm, EFilmMPa, YieldMPa, RqUm, COF: Double;
    // machine
    CoreDiaMm: Double;      // mill roll diameter [mm]
    ContactDiaMm: Double;   // contact roll diameter [mm] (= tension roll)
    RollGapMm: Double;      // vertical surface gap contact <-> tension roll [mm]
    TRollWallMm: Double;    // tension roll shell wall [mm]
    RubberEMPa, RubberNu: Double;
    SpeedMpm: Double;       // line speed [m/min]
    TensionNm, TaperPct: Double;
    NipNm, NipTaperPct: Double;
    // contact roll linear motor
    ContactMode: Integer;   // CM_PRESS / CM_RETRACT
    RetractMm: Double;      // retract distance from roll surface [mm]
    LinKf: Double;          // force constant [N/A]
    LinKm: Double;          // motor constant [N/sqrt(W)]
    LinMassKg: Double;      // moving mass (forcer + contact roll) [kg]
    LinVmax: Double;        // [m/s]
    LinAcc: Double;         // [m/s2]
    LinFmaxN: Double;       // continuous force rating [N]
    // tension roll servo axis (ball screw)
    LeadCmdMm: Double;      // commanded lead vs contact roll [mm], + = ahead
    ScrewLeadMm: Double;    // screw pitch [mm/rev]
    ScrewEta: Double;       // screw efficiency [-]
    ServoMassKg: Double;    // moving mass [kg]
    ServoVmax: Double;      // [m/s]
    ServoAcc: Double;       // [m/s2]
    ServoRatedNm: Double;   // rated motor torque [N.m]
    GuideMu: Double;        // linear guide friction [-]
    ClearMm: Double;        // min clearance tension roll <-> winder [mm]
    // cross-machine (width) data of the contact roll
    CRollWallMm: Double;    // steel shell wall of the contact roll [mm]
    RubberThkMm: Double;    // rubber cover thickness [mm]
    CrownMm: Double;        // diameter crown of the contact roll (centre - edge) [mm]
    BearingExtraMm: Double; // bearing span - web width [mm]
    // physics coefficients
    AirVisc, Patm: Double;
    NipAirFactor: Double;   // Kn
    PreWrapAir: Double;     // Kw: share of pre-wrap air the nip cannot expel
    PreWrapBeta0Deg: Double;// beta0: pre-wrap saturation angle [deg]
    NoNipAir: Double;       // Kb: share of tension-only air kept without nip
    PressAtten: Double;     // alpha
    AspPressKPa: Double;    // Pasp
    // warning limits
    MaxCorePressMPa, MaxStressRatio: Double;
  end;

  TLayer = record
    R, LCum, Tw, Nip, WIT, HAir, P, Gap, K, Rc: Double;
  end;

  TAirInfo = record
    U, REq, TEff: Double;
    HTension: Double; // Knox-Sweeney, tension only, winder radius [m]
    HFoil: Double;    // Knox-Sweeney with Tw+N at the nip [m]
    HBase: Double;    // Kn*HFoil [m]
    HPre: Double;     // extra air from pre-wrap [m]
    HNip: Double;     // effective entering air [m]
    HCrit: Double;    // 3*Rq [m]
    HTrapped: Double; // trapped air layer [m]
    NoNip: Boolean;
  end;

  TNipInfo = record
    REq, EStar, HalfB, PMax, PMean: Double;
  end;

  // web path geometry for one roll radius
  TGeo = record
    R, Rc, Rt: Double;
    Cx, Cy, Tx, Ty: Double;      // roll centres [m]
    Gap: Double;                 // contact roll gap to roll surface [m]
    Lead, LeadMax: Double;       // actual / allowed lead [m]
    Limited: Boolean;            // servo lead clamped by collision
    NipActive: Boolean;
    PathType: Integer;           // 1 T->C->nip, 2 T->W pre-wrap, 3 T->W, 4 T->C->W
    TA0, TA1: Double;            // tension roll arc (in, out) [rad]
    HasC: Boolean;
    CA0, CA1: Double;            // contact roll arc (in, out)
    WA0: Double;                 // first web contact angle on winder
    S1x0, S1y0, S1x1, S1y1: Double; // first free span
    HasS2: Boolean;
    S2x0, S2y0, S2x1, S2y1: Double; // second free span (retract with wrap)
    D1x, D1y, D2x, D2y: Double;  // span directions
    ThetaT, BetaC, BetaW: Double;// wraps [rad]
    FilmAngle: Double;           // first span from vertical, + toward winder [rad]
    SpanLen: Double;             // total free span [m]
  end;

  // contact roll nip profile across the web width
  TCDProfile = record
    X: array of Double;      // position from web centre [mm]
    Nip: array of Double;    // local nip load [N/m]
    Defl: array of Double;   // contact roll deflection [mm]
    KOut: array of Double;   // packing ratio of the layer being wound [-]
    Span, EI, KFound: Double;// bearing span [m], bending stiffness [N.m2], rubber foundation [N/m2]
    DeflMax: Double;         // max deflection [mm]
    NMin, NMax, NAvg: Double;
  end;

  { TWinderSim }

  TWinderSim = class
  private
    procedure AddLayer;
  public
    P: TWinderParams;
    Layers: array of TLayer;
    Count: Integer;
    WoundLen, PartLen, SimTime, RWound: Double;
    Finished: Boolean;
    ROuterComp, KAvg, RhoAvg, PCore, KOuter, KMin: Double;
    // axes (actual)
    GapAct, GapVel: Double;      // contact roll gap [m], [m/s]
    LeadAct, LeadVel: Double;    // tension roll lead [m], [m/s]
    constructor Create;
    procedure SetDefaults;
    procedure Reset;
    procedure Step(dt: Double; DoSolve: Boolean = True);
    procedure RunToEnd;
    procedure Solve;
    procedure UpdateAxes(dt: Double);
    function AxesMoving: Boolean;
    // basic quantities
    function T: Double;
    function W: Double;
    function R0: Double;
    function RContact: Double;
    function RTension: Double;
    function U: Double;
    function GapRough0: Double;
    function TensionAt(R: Double): Double;
    function NipSet(R: Double): Double;
    function NipActive: Boolean;
    function NipAt(R: Double): Double;
    function Geo(R: Double): TGeo;
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
    function FollowSpeed: Double;
    // tension roll / load cell / servo
    function LoadCellN: Double;
    function TRollFx: Double;
    function TRollRpm: Double;
    function TRollMassKg: Double;
    function TRollInertia: Double;
    function SpanStrain: Double;
    function ServoAxialN: Double;
    function ServoTorqueNm: Double;
    function ServoRpm: Double;
    // contact roll linear motor
    function ContactFilmFx: Double;
    function LinForceN: Double;
    function LinCurrentA: Double;
    function LinCopperW: Double;
    function CDProfile(n: Integer): TCDProfile;
    procedure GetWarnings(SL: TStrings);
  end;

var
  FSDot: TFormatSettings;

function FF(v: Double; d: Integer): string;
function HMS(sec: Double): string;
function NormAng(a: Double): Double;

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

function NormAng(a: Double): Double;
begin
  // -> [0, 2pi)
  Result := a - 2 * Pi * Floor(a / (2 * Pi));
  if Result > 2 * Pi - 1e-9 then Result := 0;
end;

{ Tangent between circle 1 and circle 2 for a web running from 1 to 2.
  Side +1 = roll centre on the LEFT of the travel direction (web wraps it
  counter-clockwise on screen), -1 = centre on the RIGHT (clockwise).
  nA = d rotated by +90deg: point = centre + r*side*nA. }
procedure Tangent(P1x, P1y, r1, s1, P2x, P2y, r2, s2: Double;
  out dx, dy, q1x, q1y, q2x, q2y: Double);
var
  Dxx, Dyy, L, h, ang: Double;
begin
  Dxx := P2x - P1x;
  Dyy := P2y - P1y;
  L := Max(1e-9, Hypot(Dxx, Dyy));
  h := r1 * s1 - r2 * s2;
  if Abs(h) >= L then h := Sign(h) * L * 0.999;
  ang := ArcTan2(Dyy, Dxx) - ArcSin(h / L);
  dx := Cos(ang);
  dy := Sin(ang);
  q1x := P1x + r1 * s1 * (-dy);
  q1y := P1y + r1 * s1 * dx;
  q2x := P2x + r2 * s2 * (-dy);
  q2y := P2y + r2 * s2 * dx;
end;

function SegDist(px, py, ax, ay, bx, by: Double): Double;
var
  vx, vy, wx, wy, c1, c2, b: Double;
begin
  vx := bx - ax; vy := by - ay;
  wx := px - ax; wy := py - ay;
  c1 := vx * wx + vy * wy;
  c2 := vx * vx + vy * vy;
  if (c1 <= 0) or (c2 <= 0) then Exit(Hypot(px - ax, py - ay));
  if c1 >= c2 then Exit(Hypot(px - bx, py - by));
  b := c1 / c2;
  Result := Hypot(px - (ax + b * vx), py - (ay + b * vy));
end;

procedure MoveAxis(var pos, vel: Double; target, vmax, amax, dt: Double);
var
  err, vdes: Double;
begin
  err := target - pos;
  if (Abs(err) < 2e-5) and (Abs(vel) < 1e-3) then
  begin
    pos := target;
    vel := 0;
    Exit;
  end;
  // trapezoidal profile: braking speed sqrt(2*a*|err|)
  vdes := Sign(err) * Min(vmax, Sqrt(2 * amax * Abs(err)));
  if vel < vdes then vel := Min(vdes, vel + amax * dt)
  else vel := Max(vdes, vel - amax * dt);
  pos := pos + vel * dt;
  if ((target - pos) * err < 0) then
  begin
    pos := target;
    vel := 0;
  end;
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
    RubberEMPa := 6;
    RubberNu := 0.49;
    SpeedMpm := 200;
    TensionNm := 100;
    TaperPct := 25;
    NipNm := 300;
    NipTaperPct := 0;
    ContactMode := CM_PRESS;
    RetractMm := 50;
    LinKf := 150;
    LinKm := 45;
    LinMassKg := 180;
    LinVmax := 0.20;
    LinAcc := 1.0;
    LinFmaxN := 3000;
    LeadCmdMm := 0;
    ScrewLeadMm := 10;
    ScrewEta := 0.90;
    ServoMassKg := 90;
    ServoVmax := 0.05;
    ServoAcc := 0.25;
    ServoRatedNm := 2.4;
    GuideMu := 0.01;
    ClearMm := 10;
    CRollWallMm := 20;
    RubberThkMm := 15;
    CrownMm := 0.50;
    BearingExtraMm := 400;
    AirVisc := 1.81e-5;
    Patm := 101325;
    NipAirFactor := 0.15;
    PreWrapAir := 0.02;
    PreWrapBeta0Deg := 10;
    NoNipAir := 0.05;
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

function TWinderSim.RTension: Double;
begin
  Result := RContact;
end;

function TWinderSim.U: Double;
begin
  Result := P.SpeedMpm / 60;
end;

function TWinderSim.GapRough0: Double;
begin
  Result := 2 * P.RqUm * 1e-6;
end;

function TWinderSim.TensionAt(R: Double): Double;
begin
  Result := P.TensionNm * (1 - P.TaperPct / 100 * (1 - R0 / R));
end;

function TWinderSim.NipSet(R: Double): Double;
begin
  Result := P.NipNm * (1 - P.NipTaperPct / 100 * (1 - R0 / R));
end;

function TWinderSim.NipActive: Boolean;
begin
  Result := (P.ContactMode = CM_PRESS) and (GapAct < 1e-4);
end;

function TWinderSim.NipAt(R: Double): Double;
begin
  if NipActive then Result := NipSet(R) else Result := 0;
end;

procedure TWinderSim.UpdateAxes(dt: Double);
var
  g: TGeo;
  tgt: Double;
begin
  if dt <= 0 then Exit;
  if P.ContactMode = CM_PRESS then tgt := 0 else tgt := P.RetractMm * 1e-3;
  MoveAxis(GapAct, GapVel, tgt, P.LinVmax, P.LinAcc, dt);
  g := Geo(ROuterComp);
  tgt := Min(P.LeadCmdMm * 1e-3, g.LeadMax);
  MoveAxis(LeadAct, LeadVel, tgt, P.ServoVmax, P.ServoAcc, dt);
end;

function TWinderSim.AxesMoving: Boolean;
begin
  Result := (Abs(GapVel) > 1e-6) or (Abs(LeadVel) > 1e-6);
end;

function TWinderSim.Geo(R: Double): TGeo;
var
  dx, dy, q1x, q1y, q2x, q2y, dx2, dy2, a, b, c, e, f: Double;
begin
  Result := Default(TGeo);
  Result.R := R;
  Result.Rc := RContact;
  Result.Rt := RTension;
  Result.Gap := GapAct;
  Result.NipActive := NipActive;
  Result.Cx := -(R + RContact + GapAct);
  Result.Cy := 0;
  Result.Ty := 2 * RContact + P.RollGapMm * 1e-3;
  // collision limit tension roll <-> winder
  c := R + RTension + P.ClearMm * 1e-3;
  if Result.Ty >= c then
    Result.LeadMax := 1e9
  else
    Result.LeadMax := -Sqrt(Sqr(c) - Sqr(Result.Ty)) - Result.Cx;
  Result.Lead := Min(LeadAct, Result.LeadMax);
  Result.Limited := LeadAct > Result.LeadMax + 1e-6;
  Result.Tx := Result.Cx + Result.Lead;
  Result.TA0 := Pi / 2;   // web comes in horizontally under the tension roll

  if Result.NipActive and (Result.Lead <= 1e-6) then
  begin
    // T -> contact roll (wrap) -> nip
    Result.PathType := 1;
    Tangent(Result.Tx, Result.Ty, Result.Rt, 1, Result.Cx, Result.Cy, Result.Rc, 1,
      dx, dy, q1x, q1y, q2x, q2y);
    Result.HasC := True;
    Result.CA0 := ArcTan2(q2y - Result.Cy, q2x - Result.Cx);
    Result.CA1 := 0;
    Result.BetaC := NormAng(Result.CA0 - Result.CA1);
    if Result.BetaC > Pi then Result.BetaC := 0;
    Result.WA0 := Pi;
  end
  else
  begin
    // T -> winder directly
    Tangent(Result.Tx, Result.Ty, Result.Rt, 1, 0, 0, R, -1,
      dx, dy, q1x, q1y, q2x, q2y);
    if Result.NipActive then
      Result.PathType := 2
    else
      Result.PathType := 3;
    if (not Result.NipActive) and
      (SegDist(Result.Cx, Result.Cy, q1x, q1y, q2x, q2y) < Result.Rc) then
    begin
      // retracted contact roll still in the way: web wraps it
      Result.PathType := 4;
      Tangent(Result.Tx, Result.Ty, Result.Rt, 1, Result.Cx, Result.Cy, Result.Rc, 1,
        dx, dy, q1x, q1y, q2x, q2y);
      Result.HasC := True;
      Result.CA0 := ArcTan2(q2y - Result.Cy, q2x - Result.Cx);
      Tangent(Result.Cx, Result.Cy, Result.Rc, 1, 0, 0, R, -1,
        dx2, dy2, a, b, e, f);
      Result.CA1 := ArcTan2(b - Result.Cy, a - Result.Cx);
      Result.BetaC := NormAng(Result.CA0 - Result.CA1);
      Result.HasS2 := True;
      Result.S2x0 := a; Result.S2y0 := b;
      Result.S2x1 := e; Result.S2y1 := f;
      Result.D2x := dx2; Result.D2y := dy2;
      Result.WA0 := ArcTan2(f, e);
    end
    else
      Result.WA0 := ArcTan2(q2y, q2x);
    if Result.NipActive then
    begin
      Result.BetaW := NormAng(Pi - NormAng(Result.WA0));
      if Result.BetaW > Pi then Result.BetaW := 0;
    end;
  end;
  Result.S1x0 := q1x; Result.S1y0 := q1y;
  Result.S1x1 := q2x; Result.S1y1 := q2y;
  Result.D1x := dx; Result.D1y := dy;
  Result.TA1 := ArcTan2(q1y - Result.Ty, q1x - Result.Tx);
  Result.ThetaT := NormAng(Result.TA0 - Result.TA1);
  Result.FilmAngle := ArcTan2(dx, -dy);
  Result.SpanLen := Hypot(q2x - q1x, q2y - q1y);
  if Result.HasS2 then
    Result.SpanLen := Result.SpanLen + Hypot(Result.S2x1 - Result.S2x0,
      Result.S2y1 - Result.S2y0);
end;

function TWinderSim.AirAt(R, Tw, Nip: Double): TAirInfo;
var
  g: TGeo;
begin
  Result := Default(TAirInfo);
  Result.U := U;
  Result.REq := R * RContact / (R + RContact);
  Result.HCrit := 3 * P.RqUm * 1e-6;
  // web wrapping the winder under tension only (Knox-Sweeney, R = roll)
  Result.HTension := 0.643 * R * Power(12 * P.AirVisc * Result.U / Max(1, Tw), 2 / 3);
  if Nip > 0 then
  begin
    Result.TEff := Tw + Nip;
    Result.HFoil := 0.643 * Result.REq *
      Power(12 * P.AirVisc * Result.U / Result.TEff, 2 / 3);
    Result.HBase := P.NipAirFactor * Result.HFoil;
    g := Geo(R);
    Result.HPre := P.PreWrapAir * Result.HTension *
      (1 - Exp(-g.BetaW / (Max(0.1, P.PreWrapBeta0Deg) * Pi / 180)));
    Result.HNip := Result.HBase + Result.HPre;
  end
  else
  begin
    Result.NoNip := True;
    Result.TEff := Max(1, Tw);
    Result.HNip := P.NoNipAir * Result.HTension;
  end;
  Result.HTrapped := Max(0, Result.HNip - Result.HCrit);
end;

function TWinderSim.NipCalc(R, Nip: Double): TNipInfo;
begin
  Result.REq := R * RContact / (R + RContact);
  Result.EStar := P.RubberEMPa * 1e6 / (1 - Sqr(P.RubberNu));
  Result.HalfB := Sqrt(Max(0, 4 * Nip * Result.REq / (Pi * Result.EStar)));
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
  pr := 0;
  for i := Count - 1 downto 0 do
  begin
    Layers[i].P := pr;
    pr := pr + alpha * Layers[i].WIT / (Layers[i].R + 0.5 * T);
  end;
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
      // area conservation: each wrap occupies len*(t+gap) of cross-section
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

function TWinderSim.FollowSpeed: Double;
begin
  // contact roll follows roll growth: dR/dt = t*U / (2*pi*R*k)
  Result := T * U / (2 * Pi * Max(0.01, ROuterComp) * Max(0.5, KAvg));
end;

function TWinderSim.LoadCellN: Double;
var
  g: TGeo;
begin
  // F = Tw*W*|u_up + u_out|, u_up = (-1,0) toward the infeed
  g := Geo(ROuterComp);
  Result := TensionAt(RWound) * W * Hypot(g.D1x - 1, g.D1y);
end;

function TWinderSim.TRollFx: Double;
var
  g: TGeo;
begin
  // horizontal web force on the tension roll (+ = toward winder)
  g := Geo(ROuterComp);
  Result := TensionAt(RWound) * W * (g.D1x - 1);
end;

function TWinderSim.TRollRpm: Double;
begin
  Result := P.SpeedMpm / (Pi * 2 * RTension);
end;

function TWinderSim.TRollMassKg: Double;
var
  ri: Double;
begin
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

function TWinderSim.ServoAxialN: Double;
begin
  // web force + guide friction (+ m*a while the axis is moving)
  Result := Abs(TRollFx) + P.GuideMu * P.ServoMassKg * 9.81;
  if Abs(LeadVel) > 1e-6 then
    Result := Result + P.ServoMassKg * P.ServoAcc;
end;

function TWinderSim.ServoTorqueNm: Double;
begin
  // T = F * pitch / (2*pi*eta)
  Result := ServoAxialN * P.ScrewLeadMm * 1e-3 / (2 * Pi * Max(0.1, P.ScrewEta));
end;

function TWinderSim.ServoRpm: Double;
begin
  // servo follows the contact roll (electronic gearing) plus its own move
  Result := (Abs(LeadVel) + FollowSpeed) / (P.ScrewLeadMm * 1e-3) * 60;
end;

function TWinderSim.ContactFilmFx: Double;
var
  g: TGeo;
begin
  // horizontal web force on the contact roll (+ = toward winder)
  g := Geo(ROuterComp);
  case g.PathType of
    1: Result := TensionAt(RWound) * W * (-g.D1x);          // in: -d1, out: up
    4: Result := TensionAt(RWound) * W * (g.D2x - g.D1x);
  else
    Result := 0;
  end;
end;

function TWinderSim.LinForceN: Double;
begin
  // motor force = nip force - web force pushing the roll + friction/accel
  Result := NipAt(RWound) * W - ContactFilmFx + P.GuideMu * P.LinMassKg * 9.81;
  if Abs(GapVel) > 1e-6 then
    Result := Result + P.LinMassKg * P.LinAcc;
end;

function TWinderSim.LinCurrentA: Double;
begin
  Result := Abs(LinForceN) / Max(1, P.LinKf);
end;

function TWinderSim.LinCopperW: Double;
begin
  Result := Sqr(LinForceN / Max(1, P.LinKm));
end;

function TWinderSim.CDProfile(n: Integer): TCDProfile;
var
  i: Integer;
  L, ro, ri, q, x, uc, dMean, cMean, crown, nsum, Tw, k: Double;
  nipi: TNipInfo;
  air: TAirInfo;
  c: array of Double;
begin
  Result := Default(TCDProfile);
  n := Max(3, n);
  SetLength(Result.X, n);
  SetLength(Result.Nip, n);
  SetLength(Result.Defl, n);
  SetLength(Result.KOut, n);
  SetLength(c, n);
  L := W + P.BearingExtraMm * 1e-3;
  Result.Span := L;
  // steel shell under the rubber cover
  ro := Max(0.01, RContact - P.RubberThkMm * 1e-3);
  ri := Max(0, ro - P.CRollWallMm * 1e-3);
  Result.EI := 210e9 * Pi / 4 * (Power(ro, 4) - Power(ri, 4));
  q := NipAt(RWound);
  nipi := NipCalc(RWound, NipSet(RWound));
  // rubber cover as an elastic foundation: k = Er * 2b / h_r
  Result.KFound := P.RubberEMPa * 1e6 * 2 * Max(1e-4, nipi.HalfB) /
    Max(1e-3, P.RubberThkMm * 1e-3);
  dMean := 0;
  cMean := 0;
  for i := 0 to n - 1 do
  begin
    uc := (i / (n - 1) - 0.5) * W;          // from web centre [m] (U is the speed)
    x := uc + L / 2;                        // from bearing [m]
    Result.X[i] := uc * 1000;
    // simply supported beam, uniform line load q
    Result.Defl[i] := q * x * (L * L * L - 2 * L * x * x + x * x * x) / (24 * Result.EI);
    crown := 0.5 * P.CrownMm * 1e-3 * (1 - Sqr(2 * uc / W)); // radius crown
    c[i] := crown;
    dMean := dMean + Result.Defl[i];
    cMean := cMean + crown;
  end;
  dMean := dMean / n;
  cMean := cMean / n;
  nsum := 0;
  for i := 0 to n - 1 do
  begin
    // more rubber squeeze where the roll bends less / has more crown
    Result.Nip[i] := Max(0, q + Result.KFound * ((dMean - Result.Defl[i]) + (c[i] - cMean)));
    nsum := nsum + Result.Nip[i];
  end;
  if nsum > 0 then
    for i := 0 to n - 1 do
      Result.Nip[i] := Result.Nip[i] * q * n / nsum;  // keep total nip force
  Tw := TensionAt(RWound);
  Result.NMin := 1e30;
  Result.NMax := -1e30;
  Result.DeflMax := 0;
  for i := 0 to n - 1 do
  begin
    air := AirAt(RWound, Tw, Result.Nip[i]);
    k := T / (T + air.HTrapped + GapRough0);
    Result.KOut[i] := k;
    Result.NMin := Min(Result.NMin, Result.Nip[i]);
    Result.NMax := Max(Result.NMax, Result.Nip[i]);
    Result.DeflMax := Max(Result.DeflMax, Result.Defl[i] * 1000);
    Result.Defl[i] := Result.Defl[i] * 1000;
  end;
  Result.NAvg := q;
end;

procedure TWinderSim.GetWarnings(SL: TStrings);
var
  air: TAirInfo;
  nip: TNipInfo;
  g: TGeo;
  cd: TCDProfile;
begin
  SL.Clear;
  air := AirAt(RWound, TensionAt(RWound), NipAt(RWound));
  nip := NipCalc(RWound, NipAt(RWound));
  g := Geo(ROuterComp);
  if not NipActive then
    SL.Add('[NO NIP] Contact roll is not pressing -> air wound in, very soft roll.');
  if air.HTrapped > 0 then
    SL.Add(Format('[AIR] Entering air %s um > 3Rq %s um -> air trapped. ' +
      'Increase nip, reduce speed or pre-wrap.',
      [FF(air.HNip * 1e6, 3), FF(air.HCrit * 1e6, 3)]));
  if g.BetaW > 0.02 then
    SL.Add(Format('[PRE-WRAP] Web touches the roll %s deg before the nip ' +
      '(tension roll ahead) -> extra air %s um.',
      [FF(g.BetaW * 180 / Pi, 1), FF(air.HPre * 1e6, 3)]));
  if g.Limited then
    SL.Add('[SERVO] Tension roll lead limited by roll diameter (collision guard).');
  if NipActive then
  begin
    cd := CDProfile(41);
    if cd.NMin < 0.7 * cd.NAvg then
      SL.Add(Format('[CD] Nip across width %s..%s N/m (avg %s) -> soft centre/edges, ' +
        'check contact roll crown.', [FF(cd.NMin, 0), FF(cd.NMax, 0), FF(cd.NAvg, 0)]));
  end;
  if LinForceN > P.LinFmaxN then
    SL.Add(Format('[LM] Linear motor force %s N > rated %s N.',
      [FF(LinForceN, 0), FF(P.LinFmaxN, 0)]));
  if ServoTorqueNm > P.ServoRatedNm then
    SL.Add(Format('[SERVO] Torque %s N.m > rated %s N.m.',
      [FF(ServoTorqueNm, 2), FF(P.ServoRatedNm, 2)]));
  if WindStressMPa > P.MaxStressRatio * P.YieldMPa then
    SL.Add(Format('[TENSION] Winding stress %s MPa > %s%% of yield.',
      [FF(WindStressMPa, 2), FF(P.MaxStressRatio * 100, 0)]));
  if PCore > P.MaxCorePressMPa * 1e6 then
    SL.Add(Format('[CORE] Core pressure %s MPa > %s MPa -> blocking / core crush risk.',
      [FF(PCore * 1e-6, 2), FF(P.MaxCorePressMPa, 2)]));
  if (Count > 100) and (KOuter < 0.95) then
    SL.Add(Format('[SOFT] Outer layer packing k = %s < 0.95.', [FF(KOuter, 4)]));
  if TensionAt(RWound) < 0.3 * P.TensionNm then
    SL.Add('[TAPER] Tension below 30% of start tension -> wrinkle risk.');
  if nip.PMax > 1e6 then
    SL.Add(Format('[NIP] Peak nip pressure %s kPa high -> pressure marks.',
      [FF(nip.PMax * 1e-3, 0)]));
  if SL.Count = 0 then
    SL.Add('OK - no warnings.');
end;

initialization
  FSDot := DefaultFormatSettings;
  FSDot.DecimalSeparator := '.';
  FSDot.ThousandSeparator := ',';

end.
