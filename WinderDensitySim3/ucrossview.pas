unit uCrossView;

{ Cross-machine view window: front elevation of the winder across the web
  width (OS left, DS right) with a half section of the roll showing the
  density layers, plus nip / deflection / packing profiles across the width.
  Built in code (no .lfm), drawn with BGRABitmap. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls,
  BGRABitmap, BGRABitmapTypes, uWinderModel, uWinderDraw;

type

  { TfrmCross }

  TfrmCross = class(TForm)
  private
    FSim: TWinderSim;
    FBmp: TBGRABitmap;
    PBox: TPaintBox;
    procedure PBoxPaint(Sender: TObject);
  public
    constructor CreateCross(AOwner: TComponent; ASim: TWinderSim);
    destructor Destroy; override;
  end;

procedure RenderCross(bmp: TBGRABitmap; Sim: TWinderSim);

implementation

procedure Box(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c: TBGRAPixel;
  const s: string = ''; tc: Integer = 0);
begin
  bmp.FillRoundRectAntialias(x1, y1, x2, y2, 3, 3, c);
  bmp.RoundRectAntialias(x1, y1, x2, y2, 3, 3, BGRA(20, 22, 26), 1);
  if s <> '' then
  begin
    if tc = 0 then tc := 11;
    Txt(bmp, (x1 + x2) / 2, (y1 + y2) / 2 - tc * 0.6, s, tc, BGRA(15, 18, 24), True, taCenter);
  end;
end;

procedure VGrad(bmp: TBGRABitmap; x1, y1, x2, y2: Single; c1, c2: TBGRAPixel);
var
  i, n: Integer;
  ya, yb: Single;
begin
  // vertical shading to suggest a cylinder seen from the front
  n := Max(2, Round((y2 - y1) / 2));
  for i := 0 to n - 1 do
  begin
    ya := y1 + (y2 - y1) * i / n;
    yb := y1 + (y2 - y1) * (i + 1) / n;
    bmp.FillRectAntialias(x1, ya, x2, yb + 0.6,
      LerpC(c1, c2, Sin(Pi * (i + 0.5) / n)));
  end;
end;

procedure DimLine(bmp: TBGRABitmap; x1, x2, y: Single; const s: string; c: TBGRAPixel);
begin
  bmp.DrawLineAntialias(x1, y, x2, y, c, 1);
  bmp.DrawLineAntialias(x1, y - 6, x1, y + 6, c, 1);
  bmp.DrawLineAntialias(x2, y - 6, x2, y + 6, c, 1);
  bmp.FillPolyAntialias([PointF(x1, y), PointF(x1 + 9, y - 4), PointF(x1 + 9, y + 4)], c);
  bmp.FillPolyAntialias([PointF(x2, y), PointF(x2 - 9, y - 4), PointF(x2 - 9, y + 4)], c);
  Badge(bmp, (x1 + x2) / 2, y - 8, s, c, taCenter);
end;

procedure RenderCross(bmp: TBGRABitmap; Sim: TWinderSim);
var
  Wd, Ht, areaTop, areaH, i, nb, b, i0, i1, cw, ch, gy: Integer;
  L, Wm, Rmax, Rc, gapM, R, s, sv, xc, y0, yT, xl, xr, floorY, frameW, ksum, r1: Double;
  cd: TCDProfile;
  g: TGeo;
  air: TAirInfo;
  S1: array[0..1] of TSeries;
  S2: array[0..0] of TSeries;
  S3: array[0..0] of TSeries;
  ymin, ymax: Double;

  function PX(m: Double): Single;     // metres from web centre -> px (horizontal)
  begin
    Result := xc + m * s;
  end;

begin
  Wd := bmp.Width;
  Ht := bmp.Height;
  bmp.Fill(C_BG);
  Txt(bmp, 12, 8, 'ภาพแนวขวาง (Cross-machine view)  –  มองจากด้านฟิล์มเข้า: OS ซ้าย / DS ขวา',
    17, C_TEXT, True);

  Wm := Sim.W;
  L := Wm + Sim.P.BearingExtraMm * 1e-3;
  Rmax := Sim.PredictDia(Sim.P.LengthM, 0.95) / 2;
  Rc := Sim.RContact;
  gapM := Sim.P.RollGapMm * 1e-3;
  R := Sim.ROuterComp;
  g := Sim.Geo(R);
  cd := Sim.CDProfile(61);
  air := Sim.AirAt(Sim.RWound, Sim.TensionAt(Sim.RWound), Sim.NipAt(Sim.RWound));

  areaTop := 40;
  areaH := Round(Ht * 0.60) - areaTop;
  bmp.FillRoundRectAntialias(10, areaTop, Wd - 10, areaTop + areaH, 8, 8, C_PANEL);
  // horizontal scale s (true widths); vertical scale sv may be stretched because
  // the web is ~5 m wide while the rolls are < 1.1 m in diameter (schematic)
  s := Min((Wd - 60) / (L + 1.6), (areaH - 110) / (Rmax + 3 * Rc + gapM + 0.12));
  sv := Min(2.5 * s, (areaH - 110) / (Rmax + 3 * Rc + gapM + 0.12));
  xc := (Wd - 60) / 2 + 30 - 0.05 * s;
  y0 := areaTop + 56 + Rmax * sv;
  yT := y0 + (2 * Rc + gapM) * sv;
  floorY := Max(y0 + Rmax * sv, yT + Rc * sv) + 14;
  frameW := Max(8, 0.08 * s);
  xl := PX(-L / 2);
  xr := PX(L / 2);

  // floor and side frames
  bmp.FillRectAntialias(16, floorY, Wd - 16, floorY + 5, BGRA(70, 78, 92));
  bmp.FillRectAntialias(xl - frameW, y0 - Rmax * sv - 14, xl, floorY, BGRA(64, 72, 88));
  bmp.FillRectAntialias(xr, y0 - Rmax * sv - 14, xr + frameW, floorY, BGRA(64, 72, 88));
  Txt(bmp, xl - frameW / 2, y0 - Rmax * sv - 32, 'OS', 13, C_ACCENT, True, taCenter);
  Txt(bmp, xr + frameW / 2, y0 - Rmax * sv - 32, 'DS', 13, C_ACCENT, True, taCenter);

  // winder shaft and drive (DS)
  bmp.FillRectAntialias(xl - frameW - 0.08 * s, y0 - 0.05 * sv, PX(L / 2 + 0.75), y0 + 0.05 * sv,
    BGRA(150, 156, 166));
  Box(bmp, xr + frameW + 0.04 * s, y0 - 0.14 * sv, xr + frameW + 0.32 * s, y0 + 0.14 * sv,
    BGRA(120, 170, 120), 'GEAR', 10);
  Box(bmp, xr + frameW + 0.34 * s, y0 - 0.17 * sv, PX(L / 2 + 0.78), y0 + 0.17 * sv,
    BGRA(90, 150, 210), 'M', 12);
  Badge(bmp, PX(L / 2 + 0.5), y0 - 0.17 * sv - 42, FF(Sim.RollRpm, 1) + ' rpm  ' +
    FF(Sim.TorqueNm, 0) + ' N·m', C_TEXT, taCenter);

  // mill roll core (slightly wider than the web) + chucks
  bmp.FillRectAntialias(PX(-Wm / 2 - 0.06), y0 - Sim.R0 * sv, PX(Wm / 2 + 0.06), y0 + Sim.R0 * sv,
    BGRA(120, 128, 140));
  Box(bmp, PX(-Wm / 2 - 0.14), y0 - 0.09 * sv, PX(-Wm / 2 - 0.05), y0 + 0.09 * sv,
    BGRA(170, 176, 186), 'CH', 9);
  Box(bmp, PX(Wm / 2 + 0.05), y0 - 0.09 * sv, PX(Wm / 2 + 0.14), y0 + 0.09 * sv,
    BGRA(170, 176, 186), 'CH', 9);

  // wound film: upper half = section A-A (density layers), lower half = roll surface
  if Sim.Count > 0 then
  begin
    nb := Min(120, Sim.Count);
    for b := nb - 1 downto 0 do
    begin
      i0 := Int64(b) * Sim.Count div nb;
      i1 := Int64(b + 1) * Sim.Count div nb - 1;
      ksum := 0;
      for i := i0 to i1 do ksum := ksum + Sim.Layers[i].K;
      r1 := Sim.Layers[i1].Rc;
      bmp.FillRectAntialias(PX(-Wm / 2), y0 - r1 * sv, PX(Wm / 2), y0 - Sim.R0 * sv,
        DensityColor(ksum / (i1 - i0 + 1)));
    end;
    VGrad(bmp, PX(-Wm / 2), y0, PX(Wm / 2), y0 + R * sv, BGRA(150, 110, 50),
      BGRA(255, 205, 120));
    bmp.RectangleAntialias(PX(-Wm / 2), y0 - R * sv, PX(Wm / 2), y0 + R * sv, C_FILM, 1.2);
  end;
  // core wall in section
  bmp.FillRectAntialias(PX(-Wm / 2 - 0.06), y0 - Sim.R0 * sv, PX(Wm / 2 + 0.06),
    y0 - Sim.R0 * sv + Max(3, 0.02 * sv), BGRA(90, 96, 108));
  bmp.DrawLineAntialias(PX(-Wm / 2 - 0.2), y0, PX(Wm / 2 + 0.2), y0, C_DIM, 1);
  Badge(bmp, PX(-Wm / 2) + 6, y0 - R * sv + 4, 'ภาพตัด A-A : ชั้นฟิล์มตามความหนาแน่น',
    C_TEXT);
  Badge(bmp, PX(Wm / 2) - 6, y0 - R * sv + 4, 'Ø' + FF(Sim.CurDia * 1000, 1) +
    ' mm   ρ ' + FF(Sim.RhoAvg / 1000, 4) + ' g/cm³', C_TEXT, taRightJustify);

  // web running up from the tension roll into the nip (behind the rolls)
  bmp.FillRectAntialias(PX(-Wm / 2), y0, PX(Wm / 2), yT, BGRA(255, 190, 90, 90));
  bmp.DrawLineAntialias(PX(-Wm / 2), y0, PX(-Wm / 2), yT, C_FILM, 1.5);
  bmp.DrawLineAntialias(PX(Wm / 2), y0, PX(Wm / 2), yT, C_FILM, 1.5);

  // contact roll (in front of the winder) with linear motors inside the frames
  if g.NipActive then
    VGrad(bmp, PX(-Wm / 2 - 0.05), y0 - Rc * sv, PX(Wm / 2 + 0.05), y0 + Rc * sv,
      BGRA(25, 25, 30), BGRA(95, 95, 105))
  else
    VGrad(bmp, PX(-Wm / 2 - 0.05), y0 - Rc * sv, PX(Wm / 2 + 0.05), y0 + Rc * sv,
      BGRA(25, 25, 30, 170), BGRA(95, 95, 105, 170));
  bmp.FillRectAntialias(xl, y0 - 0.03 * sv, PX(-Wm / 2 - 0.05), y0 + 0.03 * sv, BGRA(190, 196, 206));
  bmp.FillRectAntialias(PX(Wm / 2 + 0.05), y0 - 0.03 * sv, xr, y0 + 0.03 * sv, BGRA(190, 196, 206));
  Box(bmp, xl + 2, y0 - 0.1 * sv, xl + Max(26, 0.12 * s), y0 + 0.1 * sv, BGRA(90, 130, 190), 'LM', 10);
  Box(bmp, xr - Max(26, 0.12 * s), y0 - 0.1 * sv, xr - 2, y0 + 0.1 * sv, BGRA(90, 130, 190), 'LM', 10);
  Badge(bmp, PX(0), y0 - 8, 'Contact roll Ø' + FF(Sim.P.ContactDiaMm, 0) + ' × ' +
    FF((Wm + 0.1) * 1000, 0) + ' mm   N = ' + FF(Sim.NipAt(Sim.RWound), 0) + ' N/m   gap ' +
    FF(Sim.GapAct * 1000, 1) + ' mm', C_TEXT, taCenter);
  Badge(bmp, xl - frameW - 6, y0 - 26, 'LM-OS ' + FF(Sim.LinForceN / 2, 0) + ' N',
    BGRA(140, 180, 240), taRightJustify);
  Badge(bmp, xr + frameW + 6, y0 - 0.17 * sv - 22, 'LM-DS ' + FF(Sim.LinForceN / 2, 0) + ' N',
    BGRA(140, 180, 240));

  // tension roll with load cells and two synchronised servo axes
  VGrad(bmp, PX(-Wm / 2 - 0.05), yT - Rc * sv, PX(Wm / 2 + 0.05), yT + Rc * sv,
    BGRA(110, 116, 126), BGRA(225, 230, 238));
  bmp.FillRectAntialias(xl, yT - 0.03 * sv, PX(-Wm / 2 - 0.05), yT + 0.03 * sv, BGRA(190, 196, 206));
  bmp.FillRectAntialias(PX(Wm / 2 + 0.05), yT - 0.03 * sv, xr, yT + 0.03 * sv, BGRA(190, 196, 206));
  Box(bmp, PX(-Wm / 2 - 0.12), yT - 0.05 * sv, PX(-Wm / 2 - 0.06), yT + 0.05 * sv,
    BGRA(250, 200, 60));
  Box(bmp, PX(Wm / 2 + 0.06), yT - 0.05 * sv, PX(Wm / 2 + 0.12), yT + 0.05 * sv,
    BGRA(250, 200, 60));
  Box(bmp, xl - frameW - Max(40, 0.3 * s), yT - 0.09 * sv, xl - frameW, yT + 0.09 * sv,
    BGRA(235, 190, 60), 'SERVO', 10);
  Box(bmp, xr + frameW, yT - 0.09 * sv, xr + frameW + Max(40, 0.3 * s), yT + 0.09 * sv,
    BGRA(235, 190, 60), 'SERVO', 10);
  Badge(bmp, PX(0), yT - 8, 'Tension roll Ø' + FF(Sim.P.ContactDiaMm, 0) + '   lead ' +
    FF(g.Lead * 1000, 1) + ' mm   φ ' + FF(g.FilmAngle * 180 / Pi, 1) + '°', C_TEXT, taCenter);
  Badge(bmp, PX(-Wm / 2 - 0.09), yT + 0.05 * sv + 6, 'LC-OS ' + FF(Sim.LoadCellN / 2, 0) + ' N',
    BGRA(250, 200, 60), taCenter);
  Badge(bmp, PX(Wm / 2 + 0.09), yT + 0.05 * sv + 6, 'LC-DS ' + FF(Sim.LoadCellN / 2, 0) + ' N',
    BGRA(250, 200, 60), taCenter);
  Badge(bmp, xl - frameW - 4, yT + 0.09 * sv + 6, FF(Sim.ServoTorqueNm / 2, 2) + ' N·m',
    C_DIM, taRightJustify);
  Badge(bmp, xr + frameW + 4, yT + 0.09 * sv + 6, FF(Sim.ServoTorqueNm / 2, 2) + ' N·m', C_DIM);

  // dimensions + header data
  DimLine(bmp, PX(-Wm / 2), PX(Wm / 2), floorY + 26, 'หน้ากว้างฟิล์ม W = ' +
    FF(Sim.P.WidthMm, 0) + ' mm', C_ACCENT);
  DimLine(bmp, xl, xr, floorY + 50, 'ระยะ bearing L = ' + FF(L * 1000, 0) + ' mm', C_DIM);
  Txt(bmp, Wd - 20, areaTop + 8, 'แรงตึงรวม F = ' + FF(Sim.TensionAt(Sim.RWound) * Wm, 0) +
    ' N   มวลฟิล์ม ' + FF(Sim.FilmMassKg(Sim.WoundLen), 0) + ' kg', 12, C_TEXT, False,
    taRightJustify);
  Txt(bmp, 20, areaTop + 8, 'δmax contact roll = ' + FF(cd.DeflMax, 3) + ' mm   crown ' +
    FF(Sim.P.CrownMm, 2) + ' mm   EI = ' + FF(cd.EI * 1e-6, 2) + ' MN·m²', 12, C_TEXT);
  if sv > s * 1.01 then
    Txt(bmp, Wd / 2, areaTop + 8, 'สเกลแนวตั้ง ×' + FF(sv / s, 1) + ' (ขยายให้เห็นชัด)', 12,
      C_DIM, False, taCenter);

  // profiles across the width
  gy := areaTop + areaH + 8;
  cw := (Wd - 20 - 16) div 3;
  ch := Ht - gy - 10;
  for i := 0 to 1 do S1[i] := Default(TSeries);
  S2[0] := Default(TSeries);
  S3[0] := Default(TSeries);
  S1[0].X := Copy(cd.X); S1[0].Y := Copy(cd.Nip);
  S1[0].Color := BGRA(240, 200, 80); S1[0].Fill := True; S1[0].Name := 'N(x)';
  SetLength(S1[1].X, 2); SetLength(S1[1].Y, 2);
  S1[1].X[0] := cd.X[0]; S1[1].X[1] := cd.X[High(cd.X)];
  S1[1].Y[0] := cd.NAvg; S1[1].Y[1] := cd.NAvg;
  S1[1].Color := C_DIM; S1[1].Dashed := True; S1[1].Name := 'avg';
  ymax := Max(10, cd.NMax * 1.15);
  DrawChart(bmp, 10, gy, 10 + cw, gy + ch, 'แรงกด nip ตามหน้ากว้าง', 'ตำแหน่งจากกลางฟิล์ม [mm]',
    'N [N/m]', S1, cd.X[0], cd.X[High(cd.X)], 0, ymax);

  S2[0].X := Copy(cd.X); S2[0].Y := Copy(cd.Defl);
  S2[0].Color := BGRA(90, 200, 255); S2[0].Name := 'δ(x)';
  DrawChart(bmp, 18 + cw, gy, 18 + 2 * cw, gy + ch, 'การแอ่นตัว Contact roll',
    'ตำแหน่งจากกลางฟิล์ม [mm]', 'δ [mm]', S2, cd.X[0], cd.X[High(cd.X)], 0,
    Max(0.01, cd.DeflMax * 1.2));

  S3[0].X := Copy(cd.X);
  SetLength(S3[0].Y, Length(cd.KOut));
  ymin := 1;
  for i := 0 to High(cd.KOut) do
  begin
    S3[0].Y[i] := cd.KOut[i] * Sim.P.RhoFilm / 1000;
    ymin := Min(ymin, S3[0].Y[i]);
  end;
  S3[0].Color := BGRA(180, 120, 255); S3[0].Fill := True; S3[0].Name := 'ρ ชั้นนอก';
  DrawChart(bmp, 26 + 2 * cw, gy, Wd - 10, gy + ch, 'ρ ชั้นที่กำลังม้วน ตามหน้ากว้าง',
    'ตำแหน่งจากกลางฟิล์ม [mm]', 'ρ [g/cm³]', S3, cd.X[0], cd.X[High(cd.X)],
    Min(ymin, Sim.P.RhoFilm / 1000) - 0.01, Sim.P.RhoFilm / 1000 * 1.005);
  if air.NoNip then
    Txt(bmp, Wd - 24, gy + 8, 'NO NIP', 13, C_WARN, True, taRightJustify);
end;

{ TfrmCross }

constructor TfrmCross.CreateCross(AOwner: TComponent; ASim: TWinderSim);
begin
  inherited CreateNew(AOwner, 1);
  FSim := ASim;
  Caption := 'Winder Density Simulator 3 – Cross view';
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

destructor TfrmCross.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

procedure TfrmCross.PBoxPaint(Sender: TObject);
begin
  if (PBox.Width < 50) or (PBox.Height < 50) then Exit;
  if (FBmp.Width <> PBox.Width) or (FBmp.Height <> PBox.Height) then
    FBmp.SetSize(PBox.Width, PBox.Height);
  RenderCross(FBmp, FSim);
  FBmp.Draw(PBox.Canvas, 0, 0, True);
end;

end.
