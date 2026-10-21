unit uWinderDraw;

{ BGRABitmap rendering of the winder scene, KPI tiles and charts. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes, uWinderModel;

type
  TSeries = record
    X, Y: array of Double;
    Color: TBGRAPixel;
    Name: string;
    Dashed: Boolean;
    Fill: Boolean;
  end;

const
  K_LO = 0.90;   // packing ratio at the low end of the colour scale
  K_HI = 1.00;

function DensityColor(K: Double): TBGRAPixel;
procedure RenderScene(bmp: TBGRABitmap; Sim: TWinderSim; AngRoll, AngContact,
  SimMult: Double; Running: Boolean);
// shared drawing helpers (also used by the cross view and manual panel)
function LerpC(a, b: TBGRAPixel; t: Double): TBGRAPixel;
procedure Txt(bmp: TBGRABitmap; x, y: Single; const s: string; h: Integer;
  c: TBGRAPixel; bold: Boolean = False; align: TAlignment = taLeftJustify);
procedure DrawChart(bmp: TBGRABitmap; x1, y1, x2, y2: Integer; const Title, XLab,
  YLab: string; const S: array of TSeries; XMin, XMax, YMin, YMax: Double);
procedure DrawSpokes(bmp: TBGRABitmap; cx, cy, r, ang: Single; n: Integer;
  c: TBGRAPixel; w: Single);
procedure MetalDisc(bmp: TBGRABitmap; cx, cy, r: Single; base: TBGRAPixel);
procedure Arrow(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; w: Single);
procedure Badge(bmp: TBGRABitmap; x, y: Single; const s: string; c: TBGRAPixel;
  align: TAlignment = taLeftJustify);

var
  C_BG, C_PANEL, C_PANEL2, C_TEXT, C_DIM, C_GRID, C_ACCENT, C_FILM, C_WARN: TBGRAPixel;

implementation

function LerpC(a, b: TBGRAPixel; t: Double): TBGRAPixel;
begin
  t := EnsureRange(t, 0, 1);
  Result := BGRA(Round(a.red + (b.red - a.red) * t),
    Round(a.green + (b.green - a.green) * t),
    Round(a.blue + (b.blue - a.blue) * t),
    Round(a.alpha + (b.alpha - a.alpha) * t));
end;

function DensityColor(K: Double): TBGRAPixel;
const
  // viridis-like ramp: low density = yellow, high density = deep purple
  Stops: array[0..4] of array[0..2] of Byte = (
    (253, 231, 37), (94, 201, 98), (33, 145, 140), (59, 82, 139), (68, 1, 84));
var
  t, f: Double;
  i: Integer;
begin
  t := EnsureRange((K - K_LO) / (K_HI - K_LO), 0, 1) * 4;
  i := Min(3, Trunc(t));
  f := t - i;
  Result := LerpC(BGRA(Stops[i][0], Stops[i][1], Stops[i][2]),
    BGRA(Stops[i + 1][0], Stops[i + 1][1], Stops[i + 1][2]), f);
end;

procedure Txt(bmp: TBGRABitmap; x, y: Single; const s: string; h: Integer;
  c: TBGRAPixel; bold: Boolean; align: TAlignment);
begin
  bmp.FontName := 'Tahoma';
  bmp.FontHeight := h;
  bmp.FontQuality := fqSystemClearType;
  if bold then bmp.FontStyle := [fsBold] else bmp.FontStyle := [];
  bmp.TextOut(x, y, s, c, align);
end;

function NiceStep(range: Double; n: Integer): Double;
var
  raw, mag, f: Double;
begin
  if range <= 0 then Exit(1);
  raw := range / n;
  mag := Power(10, Floor(Log10(raw)));
  f := raw / mag;
  if f < 1.5 then f := 1
  else if f < 3 then f := 2
  else if f < 7 then f := 5
  else f := 10;
  Result := f * mag;
end;

function TickStr(v, stp: Double): string;
begin
  if stp >= 1 then Result := FF(v, 0)
  else if stp >= 0.1 then Result := FF(v, 1)
  else if stp >= 0.01 then Result := FF(v, 2)
  else if stp >= 0.001 then Result := FF(v, 3)
  else Result := FF(v, 4);
end;

procedure DrawChart(bmp: TBGRABitmap; x1, y1, x2, y2: Integer; const Title, XLab,
  YLab: string; const S: array of TSeries; XMin, XMax, YMin, YMax: Double);
var
  px1, py1, px2, py2, i, j, n: Integer;
  stp, v: Double;
  pts: array of TPointF;
  lx: Single;

  function MX(x: Double): Single;
  begin
    Result := px1 + (x - XMin) / (XMax - XMin) * (px2 - px1);
  end;

  function MY(y: Double): Single;
  begin
    Result := py2 - (y - YMin) / (YMax - YMin) * (py2 - py1);
  end;

begin
  bmp.FillRoundRectAntialias(x1, y1, x2, y2, 8, 8, C_PANEL);
  Txt(bmp, x1 + 10, y1 + 6, Title, 14, C_TEXT, True);
  px1 := x1 + 58; py1 := y1 + 30; px2 := x2 - 14; py2 := y2 - 38;
  if (px2 - px1 < 20) or (py2 - py1 < 20) then Exit;
  if XMax <= XMin then XMax := XMin + 1;
  if YMax <= YMin then YMax := YMin + 1;
  bmp.FillRectAntialias(px1, py1, px2, py2, C_PANEL2);
  // grid + ticks
  stp := NiceStep(XMax - XMin, 6);
  v := Ceil(XMin / stp) * stp;
  while v <= XMax + stp * 1e-6 do
  begin
    bmp.DrawLineAntialias(MX(v), py1, MX(v), py2, C_GRID, 1);
    Txt(bmp, MX(v), py2 + 4, TickStr(v, stp), 11, C_DIM, False, taCenter);
    v := v + stp;
  end;
  stp := NiceStep(YMax - YMin, 5);
  v := Ceil(YMin / stp) * stp;
  while v <= YMax + stp * 1e-6 do
  begin
    bmp.DrawLineAntialias(px1, MY(v), px2, MY(v), C_GRID, 1);
    Txt(bmp, px1 - 4, MY(v) - 7, TickStr(v, stp), 11, C_DIM, False, taRightJustify);
    v := v + stp;
  end;
  bmp.RectangleAntialias(px1, py1, px2, py2, C_GRID, 1);
  Txt(bmp, (px1 + px2) / 2, py2 + 20, XLab, 12, C_DIM, False, taCenter);
  bmp.FontHeight := 12;
  bmp.TextOutAngle(x1 + 6, (py1 + py2) / 2 + bmp.TextSize(YLab).cx / 2, 900, YLab, C_DIM);
  // series (clipped to plot area)
  bmp.ClipRect := Rect(px1, py1, px2 + 1, py2 + 1);
  for i := 0 to High(S) do
  begin
    n := Min(Length(S[i].X), Length(S[i].Y));
    if n < 2 then Continue;
    if S[i].Fill then
    begin
      SetLength(pts, n + 2);
      for j := 0 to n - 1 do pts[j] := PointF(MX(S[i].X[j]), MY(S[i].Y[j]));
      pts[n] := PointF(MX(S[i].X[n - 1]), py2);
      pts[n + 1] := PointF(MX(S[i].X[0]), py2);
      bmp.FillPolyAntialias(pts, BGRA(S[i].Color.red, S[i].Color.green,
        S[i].Color.blue, 60));
    end;
    SetLength(pts, n);
    for j := 0 to n - 1 do pts[j] := PointF(MX(S[i].X[j]), MY(S[i].Y[j]));
    if S[i].Dashed then bmp.PenStyle := psDash;
    bmp.DrawPolyLineAntialias(pts, S[i].Color, 2);
    bmp.PenStyle := psSolid;
  end;
  bmp.NoClip;
  // legend
  lx := px2 - 6;
  for i := High(S) downto 0 do
    if S[i].Name <> '' then
    begin
      bmp.FontHeight := 11;
      lx := lx - bmp.TextSize(S[i].Name).cx;
      Txt(bmp, lx, py1 + 4, S[i].Name, 11, C_TEXT);
      bmp.FillRectAntialias(lx - 16, py1 + 9, lx - 4, py1 + 12, S[i].Color);
      lx := lx - 26;
    end;
end;

procedure DrawSpokes(bmp: TBGRABitmap; cx, cy, r, ang: Single; n: Integer;
  c: TBGRAPixel; w: Single);
var
  i: Integer;
  a: Single;
begin
  for i := 0 to n - 1 do
  begin
    a := ang + i * 2 * Pi / n;
    bmp.DrawLineAntialias(cx + Cos(a) * r * 0.25, cy + Sin(a) * r * 0.25,
      cx + Cos(a) * r, cy + Sin(a) * r, c, w);
  end;
end;

procedure MetalDisc(bmp: TBGRABitmap; cx, cy, r: Single; base: TBGRAPixel);
var
  i: Integer;
begin
  for i := 0 to 5 do
    bmp.FillEllipseAntialias(cx - r * 0.08 * i / 5, cy - r * 0.08 * i / 5,
      r * (1 - i * 0.12), r * (1 - i * 0.12), LerpC(base, BGRA(235, 238, 242), i / 7));
  bmp.EllipseAntialias(cx, cy, r, r, BGRA(20, 22, 26), 1.5);
end;

procedure Tile(bmp: TBGRABitmap; x1, y1, x2, y2: Single; const Cap, Val, Sub: string;
  ValColor: TBGRAPixel);
begin
  bmp.FillRoundRectAntialias(x1, y1, x2, y2, 6, 6, C_PANEL);
  Txt(bmp, x1 + 8, y1 + 5, Cap, 12, C_DIM);
  Txt(bmp, x1 + 8, y1 + 22, Val, 16, ValColor, True);
  Txt(bmp, x1 + 8, y1 + 45, Sub, 11, C_DIM);
end;

procedure Arrow(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel; w: Single);
var
  dx, dy, l: Single;
begin
  dx := x2 - x1; dy := y2 - y1;
  l := Sqrt(dx * dx + dy * dy);
  if l < 1 then Exit;
  dx := dx / l; dy := dy / l;
  bmp.DrawLineAntialias(x1, y1, x2 - dx * 8, y2 - dy * 8, c, w);
  bmp.FillPolyAntialias([PointF(x2, y2), PointF(x2 - dx * 11 - dy * 6, y2 - dy * 11 + dx * 6),
    PointF(x2 - dx * 11 + dy * 6, y2 - dy * 11 - dx * 6)], c);
end;

procedure Badge(bmp: TBGRABitmap; x, y: Single; const s: string; c: TBGRAPixel;
  align: TAlignment);
var
  w: Single;
begin
  bmp.FontHeight := 11;
  bmp.FontStyle := [];
  w := bmp.TextSize(s).cx;
  case align of
    taRightJustify: x := x - w;
    taCenter: x := x - w / 2;
  end;
  bmp.FillRoundRectAntialias(x - 4, y - 1, x + w + 4, y + 15, 3, 3, BGRA(18, 22, 28, 215));
  Txt(bmp, x, y, s, 11, c);
end;

procedure DrawMachine(bmp: TBGRABitmap; Sim: TWinderSim; ax, ay, aw, ah: Integer;
  AngRoll, AngContact: Double; Running: Boolean);
var
  g: TGeo;
  RmaxEst, Rc, gapM, s, cx, cy, rCore, rOut, rcs, ccx, ccy, tcx, tcy: Double;
  nx, ny, fy, floorY, a, ksum, xEnd, mx, my, x: Double;
  nb, b, i0, i1, i, n: Integer;
  air: TAirInfo;
  nip: TNipInfo;
  pts: array of TPointF;
  wedge: array[0..2] of TPointF;
  sMode: string;

  function SX(v: Double): Single;
  begin
    Result := cx + v * s;
  end;

  function SY(v: Double): Single;
  begin
    Result := cy + v * s;
  end;

  procedure AddPt(px, py: Single);
  begin
    SetLength(pts, Length(pts) + 1);
    pts[High(pts)] := PointF(px, py);
  end;

  procedure AddArc(ocx, ocy, r, a0, sweep: Double; steps: Integer);
  var
    j: Integer;
    aa: Double;
  begin
    for j := 0 to steps do
    begin
      aa := a0 + sweep * j / steps;
      AddPt(ocx + Cos(aa) * r, ocy + Sin(aa) * r);
    end;
  end;

begin
  bmp.FillRoundRectAntialias(ax, ay, ax + aw, ay + ah, 8, 8, C_PANEL);
  RmaxEst := Sim.PredictDia(Sim.P.LengthM, 0.95) / 2;
  Rc := Sim.RContact;
  gapM := Sim.P.RollGapMm * 1e-3;
  s := Min((aw - 190) / (2 * RmaxEst + 2 * Rc + 0.05),
    (ah - 195) / Max(2 * RmaxEst, RmaxEst + 3 * Rc + gapM));
  cx := ax + aw - 20 - RmaxEst * s;
  cy := ay + 80 + RmaxEst * s + Max(0, ((ah - 195) -
    Max(2 * RmaxEst, RmaxEst + 3 * Rc + gapM) * s) / 2);
  rCore := Sim.R0 * s;
  rOut := Sim.ROuterComp * s;
  rcs := Rc * s;
  g := Sim.Geo(Sim.ROuterComp);
  ccx := SX(g.Cx); ccy := SY(g.Cy);
  tcx := SX(g.Tx); tcy := SY(g.Ty);
  nx := cx - rOut; ny := cy;
  fy := tcy + rcs;
  floorY := Max(cy + RmaxEst * s, fy + 22) + 8;
  xEnd := SX(-(Sim.R0 + Rc)) + 30;

  // floor + winder stand
  bmp.FillRectAntialias(ax + 8, floorY, ax + aw - 8, floorY + 5, BGRA(70, 78, 92));
  bmp.FillPolyAntialias([PointF(cx - rCore * 0.25, cy), PointF(cx + rCore * 0.25, cy),
    PointF(cx + rCore * 0.6, floorY), PointF(cx - rCore * 0.6, floorY)], BGRA(58, 66, 80));
  Txt(bmp, cx, cy - RmaxEst * s - 20, 'WINDER (center drive)', 12, C_TEXT, True, taCenter);
  bmp.PenStyle := psDot;
  bmp.EllipseAntialias(cx, cy, RmaxEst * s, RmaxEst * s, C_DIM, 1);
  bmp.PenStyle := psSolid;
  Txt(bmp, ax + 14, ay + 62, '◌ Ø เต็มม้วนโดยประมาณ ' +
    FF(Sim.PredictDia(Sim.P.LengthM, Max(Sim.KAvg, 0.9)) * 1000, 0) + ' mm', 11, C_DIM);

  // linear motor magnet track (contact roll axis)
  bmp.FillRectAntialias(ax + 14, ccy - 6, xEnd, ccy + 6, BGRA(48, 54, 66));
  x := ax + 16;
  i := 0;
  while x < xEnd - 8 do
  begin
    if Odd(i) then
      bmp.FillRectAntialias(x, ccy - 5, x + 7, ccy + 5, BGRA(200, 70, 70))
    else
      bmp.FillRectAntialias(x, ccy - 5, x + 7, ccy + 5, BGRA(70, 110, 200));
    x := x + 9;
    Inc(i);
  end;
  Badge(bmp, ax + 14, ccy - 30, 'LINEAR MOTOR', C_DIM);
  // forcer
  bmp.FillRoundRectAntialias(ccx - rcs - 44, ccy - 16, ccx - rcs + 4, ccy + 16, 4, 4,
    BGRA(90, 130, 190));
  Txt(bmp, ccx - rcs - 20, ccy - 8, 'LM', 12, BGRA(15, 20, 30), True, taCenter);
  bmp.DrawLineAntialias(ccx - rcs, ccy, ccx, ccy, BGRA(190, 196, 206), 6);
  if Abs(Sim.GapVel) > 1e-6 then
    Arrow(bmp, ccx - rcs - 20, ccy - 26, ccx - rcs - 20 + Sign(-Sim.GapVel) * 34,
      ccy - 26, BGRA(90, 220, 120), 2.5);

  // servo ball-screw axis (tension roll)
  bmp.FillRoundRectAntialias(ax + 14, tcy - 17, ax + 70, tcy + 17, 4, 4, BGRA(235, 190, 60));
  Txt(bmp, ax + 42, tcy - 8, 'SERVO', 11, BGRA(20, 20, 24), True, taCenter);
  bmp.DrawLineAntialias(ax + 70, tcy, xEnd, tcy, BGRA(170, 176, 186), 5);
  x := ax + 74;
  while x < xEnd do
  begin
    bmp.DrawLineAntialias(x, tcy - 3, x + 3, tcy + 3, BGRA(110, 116, 126), 1);
    x := x + 5;
  end;
  bmp.FillRoundRectAntialias(tcx - rcs - 44, tcy - 16, tcx - rcs + 4, tcy + 16, 4, 4,
    BGRA(200, 160, 60));
  Txt(bmp, tcx - rcs - 20, tcy - 8, 'NUT', 11, BGRA(20, 20, 24), True, taCenter);
  bmp.DrawLineAntialias(tcx - rcs, tcy, tcx, tcy, BGRA(190, 196, 206), 6);
  if Abs(Sim.LeadVel) > 1e-6 then
    Arrow(bmp, tcx - rcs - 20, tcy - 26, tcx - rcs - 20 + Sign(Sim.LeadVel) * 34,
      tcy - 26, BGRA(90, 220, 120), 2.5);

  // density rings of the wound film (outer to inner)
  if Sim.Count > 0 then
  begin
    nb := Min(90, Sim.Count);
    for b := nb - 1 downto 0 do
    begin
      i0 := Int64(b) * Sim.Count div nb;
      i1 := Int64(b + 1) * Sim.Count div nb - 1;
      ksum := 0;
      for i := i0 to i1 do ksum := ksum + Sim.Layers[i].K;
      bmp.FillEllipseAntialias(cx, cy, Sim.Layers[i1].Rc * s, Sim.Layers[i1].Rc * s,
        DensityColor(ksum / (i1 - i0 + 1)));
    end;
    bmp.EllipseAntialias(cx, cy, rOut, rOut, C_FILM, 1.5);
    bmp.DrawLineAntialias(cx + Cos(AngRoll) * (rOut - 10), cy + Sin(AngRoll) * (rOut - 10),
      cx + Cos(AngRoll) * rOut, cy + Sin(AngRoll) * rOut, BGRAWhite, 3);
  end;

  // mill roll (core)
  MetalDisc(bmp, cx, cy, rCore, BGRA(120, 128, 140));
  DrawSpokes(bmp, cx, cy, rCore * 0.85, AngRoll, 4, BGRA(60, 66, 76), 4);
  bmp.FillEllipseAntialias(cx, cy, rCore * 0.18, rCore * 0.18, BGRA(40, 44, 52));
  bmp.FillRoundRectAntialias(cx - 40, cy + rCore * 0.35, cx + 40, cy + rCore * 0.35 + 30,
    4, 4, BGRA(20, 24, 30, 200));
  Txt(bmp, cx, cy + rCore * 0.35 + 1, 'Mill roll', 12, C_TEXT, True, taCenter);
  Txt(bmp, cx, cy + rCore * 0.35 + 15, 'Ø' + FF(Sim.P.CoreDiaMm, 0) + ' mm', 11, C_DIM,
    False, taCenter);

  // contact roll (rubber covered) + tension roll (chrome, load cell)
  bmp.FillEllipseAntialias(ccx, ccy, rcs, rcs, BGRA(45, 45, 50));
  MetalDisc(bmp, ccx, ccy, rcs * 0.82, BGRA(140, 146, 156));
  DrawSpokes(bmp, ccx, ccy, rcs * 0.7, AngContact, 3, BGRA(70, 76, 86), 3);
  bmp.FillEllipseAntialias(ccx, ccy, rcs * 0.14, rcs * 0.14, BGRA(40, 44, 52));
  MetalDisc(bmp, tcx, tcy, rcs, BGRA(165, 172, 184));
  DrawSpokes(bmp, tcx, tcy, rcs * 0.75, AngContact, 3, BGRA(80, 86, 96), 3);
  bmp.FillRectAntialias(tcx - 9, tcy - 7, tcx + 9, tcy + 7, BGRA(250, 200, 60));
  Txt(bmp, tcx, tcy - 6, 'LC', 9, BGRA(20, 20, 24), True, taCenter);
  Arrow(bmp, tcx, tcy, tcx + (g.D1x - 1) * rcs * 0.75, tcy + g.D1y * rcs * 0.75, C_WARN, 2.5);

  // pre-wrap zone on the winder (web touches the roll before the nip)
  if g.BetaW > 0.005 then
  begin
    SetLength(pts, 0);
    AddArc(cx, cy, rOut + 2, g.WA0, g.BetaW, 16);
    bmp.DrawPolyLineAntialias(pts, BGRA(255, 80, 60, 170), 7);
  end;

  // web path
  SetLength(pts, 0);
  AddPt(ax + 4, fy + 1.5);
  AddPt(tcx, fy + 1.5);
  n := Max(4, Round(g.ThetaT * 12));
  AddArc(tcx, tcy, rcs + 1.5, g.TA0, -g.ThetaT, n);
  if g.HasC then
    AddArc(ccx, ccy, rcs + 1.5, g.CA0, -g.BetaC, Max(2, Round(g.BetaC * 12)));
  if g.PathType = 1 then
    AddArc(cx, cy, rOut + 1.5, Pi, 0.5, 10)
  else
    AddArc(cx, cy, rOut + 1.5, g.WA0, g.BetaW + 0.5, 12);
  bmp.DrawPolyLineAntialias(pts, C_FILM, 3);
  Arrow(bmp, ax + 30, fy + 1.5, ax + 70, fy + 1.5, C_ACCENT, 2);
  mx := (SX(g.S1x0) + SX(g.S1x1)) / 2;
  my := (SY(g.S1y0) + SY(g.S1y1)) / 2;
  Arrow(bmp, mx - g.D1x * 16, my - g.D1y * 16, mx + g.D1x * 16, my + g.D1y * 16, C_ACCENT, 2);
  Badge(bmp, ax + 14, fy + 8, FF(Sim.P.SpeedMpm, 0) + ' m/min  Tw ' +
    FF(Sim.TensionAt(Sim.RWound), 0) + ' N/m', C_ACCENT);
  Badge(bmp, mx + 10, my - 7, 'φ ' + FF(g.FilmAngle * 180 / Pi, 1) + '°', C_FILM);

  // nip + entrained air wedge
  air := Sim.AirAt(Sim.RWound, Sim.TensionAt(Sim.RWound), Sim.NipAt(Sim.RWound));
  nip := Sim.NipCalc(Sim.RWound, Sim.NipAt(Sim.RWound));
  if g.NipActive then
  begin
    wedge[0] := PointF(nx, ny);
    wedge[1] := PointF(nx + 1, ny + 26);
    wedge[2] := PointF(nx + 11, ny + 24);
    if air.HTrapped > 0 then
      bmp.FillPolyAntialias(wedge, BGRA(255, 80, 60, 200))
    else
      bmp.FillPolyAntialias(wedge, BGRA(120, 200, 255, 120));
    bmp.FillEllipseAntialias(nx, ny, 4, 4, C_WARN);
  end;

  // labels
  if Sim.P.ContactMode = CM_PRESS then sMode := 'กดฟิล์ม' else sMode := 'ถอยออก';
  Badge(bmp, ccx, ccy - rcs - 34, 'Contact roll Ø' + FF(Sim.P.ContactDiaMm, 0) + '  [' +
    sMode + ']', C_TEXT, taCenter);
  Badge(bmp, ccx, ccy - rcs - 17, 'gap ' + FF(Sim.GapAct * 1000, 1) + ' mm | N ' +
    FF(Sim.NipAt(Sim.RWound), 0) + ' N/m', C_DIM, taCenter);
  Badge(bmp, tcx + rcs + 8, tcy + 4, 'Tension roll  lead ' + FF(g.Lead * 1000, 1) + ' mm',
    C_TEXT);
  if g.Limited then
    Badge(bmp, tcx + rcs + 8, tcy + 21, 'LIMIT: ชนม้วน (cmd ' +
      FF(Sim.P.LeadCmdMm, 0) + ')', C_WARN)
  else
    Badge(bmp, tcx + rcs + 8, tcy + 21, 'Load cell ' + FF(Sim.LoadCellN, 0) + ' N',
      BGRA(250, 200, 60));

  // text block
  Txt(bmp, ax + 12, ay + ah - 78, 'LM: F = ' + FF(Sim.LinForceN, 0) + ' N  I = ' +
    FF(Sim.LinCurrentA, 2) + ' A   NIP 2b = ' + FF(nip.HalfB * 2e3, 2) + ' mm  Pmax = ' +
    FF(nip.PMax * 1e-3, 0) + ' kPa', 11, C_TEXT);
  if air.HTrapped > 0 then
    Txt(bmp, ax + 12, ay + ah - 61, 'AIR: h = ' + FF(air.HNip * 1e6, 3) + ' µm (nip ' +
      FF(air.HBase * 1e6, 3) + ' + pre-wrap ' + FF(air.HPre * 1e6, 3) +
      ') > 3Rq -> ติดค้าง ' + FF(air.HTrapped * 1e6, 3) + ' µm', 11, BGRA(255, 120, 100))
  else
    Txt(bmp, ax + 12, ay + ah - 61, 'AIR: h = ' + FF(air.HNip * 1e6, 3) +
      ' µm ≤ 3Rq -> อากาศระบายออกได้', 11, BGRA(130, 210, 255));
  if g.HasC then
    Txt(bmp, ax + 12, ay + ah - 44, 'SERVO: lead ' + FF(g.Lead * 1000, 1) + ' mm  φ = ' +
      FF(g.FilmAngle * 180 / Pi, 1) + '°  θT = ' + FF(g.ThetaT * 180 / Pi, 1) +
      '°  βC = ' + FF(g.BetaC * 180 / Pi, 1) + '°  T = ' + FF(Sim.ServoTorqueNm, 2) +
      ' N·m', 11, C_TEXT)
  else
    Txt(bmp, ax + 12, ay + ah - 44, 'SERVO: lead ' + FF(g.Lead * 1000, 1) + ' mm  φ = ' +
      FF(g.FilmAngle * 180 / Pi, 1) + '°  θT = ' + FF(g.ThetaT * 180 / Pi, 1) +
      '°  βW = ' + FF(g.BetaW * 180 / Pi, 1) + '°  T = ' + FF(Sim.ServoTorqueNm, 2) +
      ' N·m', 11, C_TEXT);
  Txt(bmp, ax + 12, ay + ah - 27, 'ม้วน Ø' + FF(Sim.CurDia * 1000, 1) + ' mm   ' +
    FF(Sim.RollRpm, 1) + ' rpm   ชั้นฟิล์ม ' + IntToStr(Sim.Count) +
    '   (ภาพหมุนช้าลง 5x)', 11, C_TEXT);

  // density colour legend
  for i := 0 to 159 do
    bmp.FillRectAntialias(ax + 14 + i, ay + 30, ax + 15 + i, ay + 42,
      DensityColor(K_LO + (K_HI - K_LO) * i / 159));
  Txt(bmp, ax + 14, ay + 8, 'ความหนาแน่นเฉพาะที่ (g/cm³)', 12, C_TEXT, True);
  Txt(bmp, ax + 14, ay + 44, FF(K_LO * Sim.P.RhoFilm / 1000, 3), 11, C_DIM);
  Txt(bmp, ax + 174, ay + 44, FF(K_HI * Sim.P.RhoFilm / 1000, 3), 11, C_DIM, False,
    taRightJustify);
  if Running then
    Txt(bmp, ax + aw - 12, ay + 8, '● RUN', 14, BGRA(90, 220, 120), True, taRightJustify)
  else if Sim.Finished then
    Txt(bmp, ax + aw - 12, ay + 8, '■ DONE', 14, C_ACCENT, True, taRightJustify)
  else
    Txt(bmp, ax + aw - 12, ay + 8, '❚❚ STOP', 14, C_WARN, True, taRightJustify);
end;

procedure RenderScene(bmp: TBGRABitmap; Sim: TWinderSim; AngRoll, AngContact,
  SimMult: Double; Running: Boolean);
var
  Wd, Ht, mw, cw, ch, gx, gy, n, stp, i, j, ty, tw: Integer;
  S1: array[0..1] of TSeries;
  S2: array[0..0] of TSeries;
  S3: array[0..2] of TSeries;
  S4: array[0..1] of TSeries;
  rMinMm, rMaxMm, ymin, ymax, dIdeal: Double;
  prog: Double;
begin
  Wd := bmp.Width;
  Ht := bmp.Height;
  bmp.Fill(C_BG);
  Txt(bmp, 12, 8, 'Winder Density Simulation 3  –  BOPA / Nylon film ' +
    FF(Sim.P.ThickUm, 1) + ' µm × ' + FF(Sim.P.WidthMm, 0) + ' mm × ' +
    FF(Sim.P.LengthM, 0) + ' m', 17, C_TEXT, True);
  Txt(bmp, Wd - 12, 11, 'Sim ×' + FF(SimMult, 0), 13, C_DIM, False, taRightJustify);

  mw := Round(Wd * 0.47);
  DrawMachine(bmp, Sim, 10, 40, mw - 15, Ht - 40 - 132, AngRoll, AngContact, Running);

  // KPI tiles
  ty := Ht - 124;
  tw := (mw - 15 - 5 * 6) div 6;
  Tile(bmp, 10, ty, 10 + tw, ty + 66, 'ความยาวม้วน', FF(Sim.WoundLen, 0) + ' m',
    '/ ' + FF(Sim.P.LengthM, 0) + ' m', C_TEXT);
  Tile(bmp, 10 + (tw + 6), ty, 10 + (tw + 6) + tw, ty + 66, 'Ø ม้วน', FF(Sim.CurDia * 1000, 1),
    'ideal ' + FF(Sim.IdealDia(Sim.WoundLen) * 1000, 1) + ' mm', C_TEXT);
  Tile(bmp, 10 + 2 * (tw + 6), ty, 10 + 2 * (tw + 6) + tw, ty + 66, 'รอบม้วน',
    FF(Sim.RollRpm, 1) + ' rpm', FF(Sim.TorqueNm, 0) + ' N·m', C_TEXT);
  Tile(bmp, 10 + 3 * (tw + 6), ty, 10 + 3 * (tw + 6) + tw, ty + 66, 'ρ เฉลี่ย',
    FF(Sim.RhoAvg / 1000, 4), 'k = ' + FF(Sim.KAvg * 100, 2) + ' %', C_TEXT);
  bmp.FillRoundRectAntialias(10 + 3 * (tw + 6) + tw - 16, ty + 6, 10 + 3 * (tw + 6) + tw - 6,
    ty + 16, 2, 2, DensityColor(Sim.KAvg));
  Tile(bmp, 10 + 4 * (tw + 6), ty, 10 + 4 * (tw + 6) + tw, ty + 66, 'P แกน',
    FF(Sim.PCore * 1e-3, 0) + ' kPa', 'σw ' + FF(Sim.WindStressMPa, 1) + ' MPa', C_TEXT);
  Tile(bmp, 10 + 5 * (tw + 6), ty, mw - 5, ty + 66, 'เวลา', HMS(Sim.SimTime),
    'เหลือ ' + HMS(Sim.TimeRemain), C_TEXT);
  // progress bar
  prog := Sim.WoundLen / Sim.P.LengthM;
  bmp.FillRoundRectAntialias(10, ty + 76, mw - 5, ty + 96, 5, 5, C_PANEL);
  bmp.FillRoundRectAntialias(10, ty + 76, 10 + (mw - 15) * prog, ty + 96, 5, 5, C_ACCENT);
  Txt(bmp, (mw + 5) / 2, ty + 78, FF(prog * 100, 1) + ' %   มวลฟิล์ม ' +
    FF(Sim.FilmMassKg(Sim.WoundLen), 0) + ' kg', 12, BGRA(20, 20, 24), True, taCenter);
  Txt(bmp, 10, ty + 102, 'ปุ่ม: เริ่ม/หยุด, รีเซ็ต, จำลองจนจบ  •  ข้อมูลสูตรและตัวแปรอยู่ในหน้าต่าง Developer',
    11, C_DIM);

  // charts 2x2
  gx := mw + 5;
  gy := 40;
  cw := (Wd - gx - 10 - 8) div 2;
  ch := (Ht - gy - 10 - 8) div 2;
  rMinMm := Sim.R0 * 1000;
  rMaxMm := Sim.PredictDia(Sim.P.LengthM, 0.95) * 500;
  n := Sim.Count;
  stp := Max(1, n div 400);

  for i := 0 to High(S1) do S1[i] := Default(TSeries);
  for i := 0 to High(S2) do S2[i] := Default(TSeries);
  for i := 0 to High(S3) do S3[i] := Default(TSeries);
  for i := 0 to High(S4) do S4[i] := Default(TSeries);
  j := (n + stp - 1) div stp;
  SetLength(S1[0].X, j); SetLength(S1[0].Y, j);
  SetLength(S2[0].X, j); SetLength(S2[0].Y, j);
  SetLength(S3[0].X, j); SetLength(S3[0].Y, j);
  SetLength(S3[1].X, j); SetLength(S3[1].Y, j);
  SetLength(S3[2].X, j); SetLength(S3[2].Y, j);
  SetLength(S4[0].X, j); SetLength(S4[0].Y, j);
  j := 0;
  ymin := Sim.P.RhoFilm / 1000;
  i := 0;
  while i < n do
  begin
    with Sim.Layers[i] do
    begin
      S1[0].X[j] := Rc * 1000;
      S1[0].Y[j] := K * Sim.P.RhoFilm / 1000;
      if S1[0].Y[j] < ymin then ymin := S1[0].Y[j];
      S2[0].X[j] := Rc * 1000;
      S2[0].Y[j] := P * 1e-3;
      S3[0].X[j] := 2 * R * 1000;
      S3[0].Y[j] := Tw;
      S3[1].X[j] := 2 * R * 1000;
      S3[1].Y[j] := WIT;
      S3[2].X[j] := 2 * R * 1000;
      S3[2].Y[j] := Nip;
      S4[0].X[j] := LCum / 1000;
      S4[0].Y[j] := 2 * Rc * 1000;
    end;
    Inc(j);
    Inc(i, stp);
  end;

  S1[0].Color := BGRA(180, 120, 255); S1[0].Fill := True; S1[0].Name := 'ρ(r)';
  SetLength(S1[1].X, 2); SetLength(S1[1].Y, 2);
  S1[1].X[0] := rMinMm; S1[1].X[1] := rMaxMm;
  S1[1].Y[0] := Sim.P.RhoFilm / 1000; S1[1].Y[1] := Sim.P.RhoFilm / 1000;
  S1[1].Color := C_DIM; S1[1].Dashed := True; S1[1].Name := 'ρ film';
  ymin := Min(ymin, K_LO * Sim.P.RhoFilm / 1000);
  DrawChart(bmp, gx, gy, gx + cw, gy + ch, 'ความหนาแน่นเฉพาะที่ ρ(r)', 'รัศมี r [mm]',
    'ρ [g/cm³]', S1, rMinMm, rMaxMm, ymin, Sim.P.RhoFilm / 1000 * 1.005);

  S2[0].Color := BGRA(255, 150, 70); S2[0].Fill := True; S2[0].Name := 'P(r)';
  ymax := Max(10, Sim.PCore * 1e-3 * 1.1);
  DrawChart(bmp, gx + cw + 8, gy, gx + 2 * cw + 8, gy + ch, 'แรงดันระหว่างชั้น (Radial pressure)',
    'รัศมี r [mm]', 'P [kPa]', S2, rMinMm, rMaxMm, 0, ymax);

  S3[0].Color := BGRA(90, 200, 255); S3[0].Name := 'Tw';
  S3[1].Color := BGRA(120, 230, 140); S3[1].Name := 'WIT';
  S3[2].Color := BGRA(240, 200, 80); S3[2].Name := 'Nip'; S3[2].Dashed := True;
  ymax := Max(Sim.P.TensionNm + Sim.P.COF * Sim.P.NipNm, Sim.P.NipNm) * 1.15;
  DrawChart(bmp, gx, gy + ch + 8, gx + cw, gy + 2 * ch + 8, 'แรงตึง / Wound-in-tension vs Ø',
    'Ø ม้วน [mm]', '[N/m]', S3, rMinMm * 2, rMaxMm * 2, 0, ymax);

  S4[0].Color := BGRA(255, 110, 150); S4[0].Name := 'Ø จริง (k<1)';
  SetLength(S4[1].X, 41); SetLength(S4[1].Y, 41);
  for i := 0 to 40 do
  begin
    S4[1].X[i] := Sim.P.LengthM / 1000 * i / 40;
    dIdeal := Sim.IdealDia(S4[1].X[i] * 1000) * 1000;
    S4[1].Y[i] := dIdeal;
  end;
  S4[1].Color := C_DIM; S4[1].Dashed := True; S4[1].Name := 'Ø ideal (k=1)';
  DrawChart(bmp, gx + cw + 8, gy + ch + 8, gx + 2 * cw + 8, gy + 2 * ch + 8,
    'เส้นผ่านศูนย์กลาง vs ความยาว', 'ความยาวฟิล์ม [km]', 'Ø [mm]', S4,
    0, Sim.P.LengthM / 1000, rMinMm * 2, rMaxMm * 2);
end;

initialization
  C_BG := BGRA(22, 26, 33);
  C_PANEL := BGRA(34, 40, 50);
  C_PANEL2 := BGRA(27, 32, 40);
  C_TEXT := BGRA(225, 230, 238);
  C_DIM := BGRA(140, 150, 165);
  C_GRID := BGRA(55, 63, 76);
  C_ACCENT := BGRA(80, 190, 255);
  C_FILM := BGRA(255, 190, 90);
  C_WARN := BGRA(255, 90, 80);

end.
