unit uTopView;

{ Top view (plan) window: looking down on the winder. Horizontal = across
  the web (OS left, DS right), vertical = machine direction (web comes in
  from the bottom, winder at the top). True scale in both directions.
  Roll surface colour = density of the layer being wound across the width.
  The tension roll lies below the contact roll: where it is covered it is
  drawn as a dashed hidden line. Built in code, drawn with BGRABitmap. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls,
  BGRABitmap, BGRABitmapTypes, uWinderModel, uWinderDraw;

type

  { TfrmTop }

  TfrmTop = class(TForm)
  private
    FSim: TWinderSim;
    FBmp: TBGRABitmap;
    PBox: TPaintBox;
    procedure PBoxPaint(Sender: TObject);
  public
    Phase: Double;   // web motion phase [m], advanced by the main form
    constructor CreateTop(AOwner: TComponent; ASim: TWinderSim);
    destructor Destroy; override;
  end;

procedure RenderTop(bmp: TBGRABitmap; Sim: TWinderSim; Phase: Double);

implementation

procedure Box(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel;
  const s: string = ''; tc: Integer = 10);
begin
  bmp.FillRoundRectAntialias(x1, y1, x2, y2, 3, 3, c);
  bmp.RoundRectAntialias(x1, y1, x2, y2, 3, 3, BGRA(20, 22, 26), 1);
  if s <> '' then
    Txt(bmp, (x1 + x2) / 2, (y1 + y2) / 2 - tc * 0.6, s, tc, BGRA(15, 18, 24), True, taCenter);
end;

procedure HGrad(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c1, c2: TBGRAPixel);
var
  i, n: Integer;
  ya, yb: Single;
begin
  // shading across the machine direction: a cylinder seen from above
  n := Max(2, Round((y2 - y1) / 2));
  for i := 0 to n - 1 do
  begin
    ya := y1 + (y2 - y1) * i / n;
    yb := y1 + (y2 - y1) * (i + 1) / n;
    bmp.FillRectAntialias(x1, ya, x2, yb + 0.6, LerpC(c1, c2, Sin(Pi * (i + 0.5) / n)));
  end;
end;

procedure DashRect(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel);
begin
  bmp.PenStyle := psDash;
  bmp.RectangleAntialias(x1, y1, x2, y2, c, 1.3);
  bmp.PenStyle := psSolid;
end;

procedure VDim(bmp: TBGRABitmap; x, y1, y2: Single; const s: string; c: TBGRAPixel);
begin
  if Abs(y2 - y1) < 2 then Exit;
  bmp.DrawLineAntialias(x, y1, x, y2, c, 1);
  bmp.DrawLineAntialias(x - 5, y1, x + 5, y1, c, 1);
  bmp.DrawLineAntialias(x - 5, y2, x + 5, y2, c, 1);
  Badge(bmp, x + 8, (y1 + y2) / 2 - 7, s, c);
end;

procedure RenderTop(bmp: TBGRABitmap; Sim: TWinderSim; Phase: Double);
const
  INFO_W = 270;
var
  Wd, Ht, i, n, j: Integer;
  L, Wm, Rmax, Rc, R, s, sm, xc, yW, yC, yT, yTop, yBot, frameW, u, k, yy, ph: Double;
  g: TGeo;
  cd: TCDProfile;
  air: TAirInfo;
  c: TBGRAPixel;
  info: TStringList;
  sMode: string;

  function PX(m: Double): Single;    // across the web, from web centre
  begin
    Result := xc + m * s;
  end;

  function PY(x: Double): Single;    // machine direction, geometry x (winder = 0)
  begin
    Result := yW - x * sm;            // x < 0 (infeed side) -> lower on screen
  end;

begin
  Wd := bmp.Width;
  Ht := bmp.Height;
  bmp.Fill(C_BG);
  Txt(bmp, 12, 8, 'Top View (มองจากด้านบน)  –  ฟิล์มเข้าจากด้านล่าง, Winder ด้านบน, OS ซ้าย / DS ขวา',
    17, C_TEXT, True);

  Wm := Sim.W;
  L := Wm + Sim.P.BearingExtraMm * 1e-3;
  Rmax := Sim.PredictDia(Sim.P.LengthM, 0.95) / 2;
  Rc := Sim.RContact;
  R := Sim.ROuterComp;
  g := Sim.Geo(R);
  cd := Sim.CDProfile(81);
  air := Sim.AirAt(Sim.RWound, Sim.TensionAt(Sim.RWound), Sim.NipAt(Sim.RWound));

  bmp.FillRoundRectAntialias(10, 40, Wd - INFO_W - 18, Ht - 10, 8, 8, C_PANEL);
  // machine direction extent: winder top edge .. servo motors behind the tension roll
  s := Min((Wd - INFO_W - 60) / (L + 1.4),
    (Ht - 150) / (2 * Rmax + 2 * Rc + Sim.P.RetractMm * 1e-3 + 0.15 + 0.55));
  // machine-direction scale may be stretched (schematic): web 5 m wide, depth < 2 m
  sm := Min(2.5 * s, (Ht - 150) / (2 * Rmax + 2 * Rc + Sim.P.RetractMm * 1e-3 + 0.15 + 0.55));
  xc := 10 + (Wd - INFO_W - 28) / 2;
  yW := 40 + 46 + Rmax * sm;
  yC := PY(g.Cx);
  yT := PY(g.Tx);
  yTop := yW - (Rmax + 0.12) * sm;
  yBot := Ht - 60;
  frameW := Max(8, 0.08 * s);

  // side frames (OS / DS) along the machine direction
  bmp.FillRectAntialias(PX(-L / 2) - frameW, yTop, PX(-L / 2), yBot, BGRA(64, 72, 88));
  bmp.FillRectAntialias(PX(L / 2), yTop, PX(L / 2) + frameW, yBot, BGRA(64, 72, 88));
  Txt(bmp, PX(-L / 2) - frameW / 2, yTop - 18, 'OS', 13, C_ACCENT, True, taCenter);
  Txt(bmp, PX(L / 2) + frameW / 2, yTop - 18, 'DS', 13, C_ACCENT, True, taCenter);

  // incoming web (lowest level, under the tension roll) with moving chevrons
  bmp.FillRectAntialias(PX(-Wm / 2), yT, PX(Wm / 2), yBot, BGRA(255, 190, 90, 70));
  bmp.DrawLineAntialias(PX(-Wm / 2), yT, PX(-Wm / 2), yBot, C_FILM, 1.5);
  bmp.DrawLineAntialias(PX(Wm / 2), yT, PX(Wm / 2), yBot, C_FILM, 1.5);
  ph := Frac(Phase / 0.25) * 0.25 * sm;
  yy := yBot - ph;
  while yy > yT + 10 do
  begin
    for j := -2 to 2 do
    begin
      u := j * Wm / 5;
      bmp.DrawPolyLineAntialias([PointF(PX(u) - 10, yy + 6), PointF(PX(u), yy),
        PointF(PX(u) + 10, yy + 6)], BGRA(255, 200, 110, 150), 2);
    end;
    yy := yy - 0.25 * sm;
  end;

  // linear motor tracks (inside the frames) along the machine direction
  for j := -1 to 1 do
    if j <> 0 then
    begin
      u := j * (Wm / 2 + 0.13);
      bmp.FillRectAntialias(PX(u) - 0.035 * s, PY(-(Sim.R0 + Rc) + 0.05), PX(u) + 0.035 * s,
        PY(-(Rmax + Rc + 0.25)), BGRA(48, 54, 66));
      yy := PY(-(Sim.R0 + Rc) + 0.05);
      i := 0;
      while yy < PY(-(Rmax + Rc + 0.25)) - 4 do
      begin
        if Odd(i) then c := BGRA(200, 70, 70) else c := BGRA(70, 110, 200);
        bmp.FillRectAntialias(PX(u) - 0.03 * s, yy, PX(u) + 0.03 * s, yy + 3, c);
        yy := yy + 5;
        Inc(i);
      end;
    end;

  // servo ball screws (outside the frames) with motors at the back
  for j := -1 to 1 do
    if j <> 0 then
    begin
      u := j * (L / 2 + 0.18);
      bmp.DrawLineAntialias(PX(u), PY(-(Sim.R0 + Rc) + 0.1), PX(u), yBot - 34,
        BGRA(170, 176, 186), 4);
      Box(bmp, PX(u) - 0.09 * s, yBot - 36, PX(u) + 0.09 * s, yBot - 4,
        BGRA(235, 190, 60), 'SERVO', 9);
    end;

  // tension roll (lower level) – visible part
  HGrad(bmp, PX(-Wm / 2 - 0.05), yT - Rc * sm, PX(Wm / 2 + 0.05), yT + Rc * sm,
    BGRA(110, 116, 126), BGRA(225, 230, 238));
  for j := -1 to 1 do
    if j <> 0 then
    begin
      // journals to the screw nuts + load cells
      bmp.FillRectAntialias(Min(PX(j * (Wm / 2 + 0.05)), PX(j * (L / 2 + 0.18))), yT - 0.025 * sm,
        Max(PX(j * (Wm / 2 + 0.05)), PX(j * (L / 2 + 0.18))), yT + 0.025 * sm, BGRA(190, 196, 206));
      Box(bmp, PX(j * (Wm / 2 + 0.09)) - 0.03 * s, yT - 0.045 * sm, PX(j * (Wm / 2 + 0.09)) + 0.03 * s,
        yT + 0.045 * sm, BGRA(250, 200, 60));
      Box(bmp, PX(j * (L / 2 + 0.18)) - 0.06 * s, yT - 0.06 * sm, PX(j * (L / 2 + 0.18)) + 0.06 * s,
        yT + 0.06 * sm, BGRA(200, 160, 60), 'NUT', 8);
    end;

  // winder: shaft, drive, core ends, roll surface coloured by density across the width
  bmp.FillRectAntialias(PX(-L / 2) - frameW - 0.08 * s, yW - 0.05 * sm, PX(L / 2 + 0.75),
    yW + 0.05 * sm, BGRA(150, 156, 166));
  Box(bmp, PX(L / 2) + frameW + 0.04 * s, yW - 0.14 * sm, PX(L / 2) + frameW + 0.3 * s,
    yW + 0.14 * sm, BGRA(120, 170, 120), 'GEAR', 9);
  Box(bmp, PX(L / 2) + frameW + 0.32 * s, yW - 0.17 * sm, PX(L / 2 + 0.78), yW + 0.17 * sm,
    BGRA(90, 150, 210), 'M', 12);
  bmp.FillRectAntialias(PX(-Wm / 2 - 0.06), yW - Sim.R0 * sm, PX(Wm / 2 + 0.06),
    yW + Sim.R0 * sm, BGRA(120, 128, 140));
  if Sim.Count > 0 then
  begin
    n := Length(cd.X);
    for i := 0 to n - 2 do
    begin
      k := (cd.KOut[i] + cd.KOut[i + 1]) / 2;
      bmp.FillRectAntialias(PX(cd.X[i] / 1000), yW - R * sm, PX(cd.X[i + 1] / 1000) + 0.6,
        yW + R * sm, DensityColor(k));
    end;
    // cylinder shading over the density colour
    for i := 0 to 23 do
    begin
      yy := yW - R * sm + 2 * R * sm * i / 24;
      bmp.FillRectAntialias(PX(-Wm / 2), yy, PX(Wm / 2), yy + 2 * R * sm / 24 + 0.6,
        BGRA(0, 0, 0, Round(120 * (1 - Sin(Pi * (i + 0.5) / 24)))));
    end;
    bmp.RectangleAntialias(PX(-Wm / 2), yW - R * sm, PX(Wm / 2), yW + R * sm, C_FILM, 1.5);
  end;
  Box(bmp, PX(-Wm / 2 - 0.14), yW - 0.09 * sm, PX(-Wm / 2 - 0.05), yW + 0.09 * sm,
    BGRA(170, 176, 186), 'CH', 8);
  Box(bmp, PX(Wm / 2 + 0.05), yW - 0.09 * sm, PX(Wm / 2 + 0.14), yW + 0.09 * sm,
    BGRA(170, 176, 186), 'CH', 8);
  Badge(bmp, PX(0), yW - 8, 'WINDER  Ø' + FF(Sim.CurDia * 1000, 1) + ' mm  ×  ' +
    FF(Sim.P.WidthMm, 0) + ' mm   (สีผิว = ρ ชั้นที่กำลังม้วน)', C_TEXT, taCenter);

  // contact roll (upper level, on the winder centre line) + linear motor forcers
  if g.NipActive then
    HGrad(bmp, PX(-Wm / 2 - 0.05), yC - Rc * sm, PX(Wm / 2 + 0.05), yC + Rc * sm,
      BGRA(25, 25, 30), BGRA(100, 100, 110))
  else
    HGrad(bmp, PX(-Wm / 2 - 0.05), yC - Rc * sm, PX(Wm / 2 + 0.05), yC + Rc * sm,
      BGRA(25, 25, 30, 200), BGRA(100, 100, 110, 200));
  for j := -1 to 1 do
    if j <> 0 then
    begin
      u := j * (Wm / 2 + 0.13);
      Box(bmp, PX(u) - 0.06 * s, yC - 0.08 * sm, PX(u) + 0.06 * s, yC + 0.08 * sm,
        BGRA(90, 130, 190), 'LM', 9);
    end;
  // tension roll hidden under the contact roll: dashed outline
  DashRect(bmp, PX(-Wm / 2 - 0.05), yT - Rc * sm, PX(Wm / 2 + 0.05), yT + Rc * sm,
    BGRA(230, 235, 245));
  if Sim.P.ContactMode = CM_PRESS then sMode := 'PRESS' else sMode := 'RETRACT';
  Badge(bmp, PX(0), yC - 8, 'Contact roll Ø' + FF(Sim.P.ContactDiaMm, 0) + '  [' +
    sMode + ']  N ' +
    FF(Sim.NipAt(Sim.RWound), 0) + ' N/m', C_TEXT, taCenter);
  if Abs(yT - yC) > 2 * Rc * sm - 4 then
    Badge(bmp, PX(0), yT - 8, 'Tension roll  lead ' + FF(g.Lead * 1000, 1) + ' mm', C_TEXT,
      taCenter)
  else
    Badge(bmp, PX(Wm / 2) - 6, yT + Rc * sm + 4, 'Tension roll (อยู่ใต้ – เส้นประ)  lead ' +
      FF(g.Lead * 1000, 1) + ' mm', BGRA(230, 235, 245), taRightJustify);

  // nip line along the width
  if g.NipActive then
  begin
    bmp.PenStyle := psDash;
    bmp.DrawLineAntialias(PX(-Wm / 2), PY(-R), PX(Wm / 2), PY(-R), C_WARN, 2.5);
    bmp.PenStyle := psSolid;
    Badge(bmp, PX(-Wm / 2) + 6, PY(-R) - 22, 'NIP line', C_WARN);
  end;

  // dimensions
  if sm > s * 1.01 then
    Txt(bmp, xc, Ht - 30, 'สเกลแนว MD (ขึ้น-ลง) ×' + FF(sm / s, 1) + ' (ขยายให้เห็นชัด)', 12, C_DIM, False, taCenter);
  bmp.DrawLineAntialias(PX(-Wm / 2), yTop - 4, PX(Wm / 2), yTop - 4, C_ACCENT, 1);
  Badge(bmp, PX(0), yTop - 20, 'W = ' + FF(Sim.P.WidthMm, 0) + ' mm', C_ACCENT, taCenter);
  VDim(bmp, PX(Wm / 2 + 0.3) + frameW + 4, yW, yC, FF((-g.Cx) * 1000, 0) + ' mm', C_DIM);
  VDim(bmp, PX(-L / 2) - frameW - 40, yC, yT, 'lead ' + FF(g.Lead * 1000, 0), C_DIM);

  // info column
  bmp.FillRoundRectAntialias(Wd - INFO_W - 8, 40, Wd - 10, Ht - 10, 8, 8, C_PANEL);
  info := TStringList.Create;
  try
    info.Add('ตำแหน่งแกน (จากศูนย์ Winder)');
    info.Add('  Contact roll X  ' + FF(-g.Cx * 1000, 1) + ' mm');
    info.Add('  Tension roll X  ' + FF(-g.Tx * 1000, 1) + ' mm');
    info.Add('  Gap LM          ' + FF(Sim.GapAct * 1000, 1) + ' mm');
    info.Add('  Lead servo      ' + FF(g.Lead * 1000, 1) + ' mm');
    if g.Limited then info.Add('  ! LIMIT (ชนม้วน)');
    info.Add('');
    info.Add('ฟิล์ม');
    info.Add('  W × t           ' + FF(Sim.P.WidthMm, 0) + ' × ' + FF(Sim.P.ThickUm, 1) + ' µm');
    info.Add('  V               ' + FF(Sim.P.SpeedMpm, 0) + ' m/min');
    info.Add('  F tension       ' + FF(Sim.TensionAt(Sim.RWound) * Wm, 0) + ' N');
    info.Add('  มุมฟิล์ม φ        ' + FF(g.FilmAngle * 180 / Pi, 1) + '°');
    info.Add('');
    info.Add('แรงต่อข้าง (OS / DS)');
    info.Add('  Load cell       ' + FF(Sim.LoadCellN / 2, 0) + ' N');
    info.Add('  Linear motor    ' + FF(Sim.LinForceN / 2, 0) + ' N');
    info.Add('  Servo torque    ' + FF(Sim.ServoTorqueNm / 2, 2) + ' N·m');
    info.Add('');
    info.Add('NIP ตามหน้ากว้าง');
    info.Add('  min / max       ' + FF(cd.NMin, 0) + ' / ' + FF(cd.NMax, 0) + ' N/m');
    info.Add('  δmax roll       ' + FF(cd.DeflMax, 3) + ' mm');
    info.Add('');
    info.Add('ม้วน');
    info.Add('  ρ avg           ' + FF(Sim.RhoAvg / 1000, 4) + ' g/cm³');
    info.Add('  ความยาว         ' + FF(Sim.WoundLen, 0) + ' m');
    if air.NoNip then info.Add('  ! NO NIP');
    for i := 0 to info.Count - 1 do
      if (info[i] <> '') and (info[i][1] <> ' ') then
        Txt(bmp, Wd - INFO_W + 4, 52 + i * 18, info[i], 13, C_ACCENT, True)
      else
        Txt(bmp, Wd - INFO_W + 4, 52 + i * 18, info[i], 12, C_TEXT);
  finally
    info.Free;
  end;
  // density legend
  for i := 0 to 159 do
    bmp.FillRectAntialias(Wd - INFO_W + 8 + i, Ht - 52, Wd - INFO_W + 9 + i, Ht - 40,
      DensityColor(K_LO + (K_HI - K_LO) * i / 159));
  Txt(bmp, Wd - INFO_W + 8, Ht - 36, FF(K_LO * Sim.P.RhoFilm / 1000, 3), 11, C_DIM);
  Txt(bmp, Wd - INFO_W + 168, Ht - 36, FF(K_HI * Sim.P.RhoFilm / 1000, 3), 11, C_DIM, False,
    taRightJustify);
  Txt(bmp, Wd - INFO_W + 8, Ht - 70, 'สีผิวม้วน ρ (g/cm³)', 12, C_TEXT, True);
end;

{ TfrmTop }

constructor TfrmTop.CreateTop(AOwner: TComponent; ASim: TWinderSim);
begin
  inherited CreateNew(AOwner, 1);
  FSim := ASim;
  Caption := 'Winder Density Simulator 3 – Top View';
  Width := Min(1300, Screen.WorkAreaWidth);
  Height := Min(760, Screen.WorkAreaHeight);
  Position := poDefaultPosOnly;
  Color := RGBToColor(22, 26, 33);
  FBmp := TBGRABitmap.Create(16, 16);
  PBox := TPaintBox.Create(Self);
  PBox.Parent := Self;
  PBox.Align := alClient;
  PBox.OnPaint := @PBoxPaint;
end;

destructor TfrmTop.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

procedure TfrmTop.PBoxPaint(Sender: TObject);
begin
  if (PBox.Width < 50) or (PBox.Height < 50) then Exit;
  if (FBmp.Width <> PBox.Width) or (FBmp.Height <> PBox.Height) then
    FBmp.SetSize(PBox.Width, PBox.Height);
  RenderTop(FBmp, FSim, Phase);
  FBmp.Draw(PBox.Canvas, 0, 0, True);
end;

end.
