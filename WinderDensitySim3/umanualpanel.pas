unit uManualPanel;

{ Manual operator panel window (HMI style) drawn with BGRABitmap.
  Buttons send commands to the main form through OnCommand; lamps and
  displays read the simulation directly. Layout is designed on a
  1000 x 600 canvas and scaled to the window. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls,
  BGRABitmap, BGRABitmapTypes, uWinderModel, uWinderDraw;

const
  PC_START = 1;
  PC_STOP = 2;
  PC_RESET = 3;
  PC_RUNEND = 4;
  PC_PRESS = 5;
  PC_RETRACT = 6;
  PC_LM_BACK = 7;
  PC_LM_FWD = 8;
  PC_NIP_UP = 9;
  PC_NIP_DN = 10;
  PC_SRV_BACK = 11;
  PC_SRV_FWD = 12;
  PC_SRV_HOME = 13;
  PC_SPD_UP = 14;
  PC_SPD_DN = 15;
  PC_TEN_UP = 16;
  PC_TEN_DN = 17;
  PC_TAP_UP = 18;
  PC_TAP_DN = 19;
  PC_SIM_UP = 20;
  PC_SIM_DN = 21;
  PC_ESTOP = 22;

type
  TPanelCmdEvent = procedure(Cmd: Integer) of object;

  TPBtn = record
    X1, Y1, X2, Y2: Single;   // design coordinates
    Cmd: Integer;
    Caption: string;
    Color: TBGRAPixel;
  end;

  { TfrmPanel }

  TfrmPanel = class(TForm)
  private
    FSim: TWinderSim;
    FBmp: TBGRABitmap;
    PBox: TPaintBox;
    FBtns: array of TPBtn;
    FPressed: Integer;
    FSc, FOx, FOy: Single;
    FOnCommand: TPanelCmdEvent;
    procedure AddBtn(ax1, ay1, ax2, ay2: Single; ACmd: Integer; const ACap: string;
      AColor: TBGRAPixel);
    function HitTest(X, Y: Integer): Integer;
    function Lit(Cmd: Integer): Boolean;
    procedure PBoxPaint(Sender: TObject);
    procedure PBoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure PBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure DoRender(ABmp: TBGRABitmap);
  public
    Running: Boolean;
    EStop: Boolean;
    SimMult: Double;
    procedure RenderTo(ABmp: TBGRABitmap);
    constructor CreatePanel(AOwner: TComponent; ASim: TWinderSim);
    destructor Destroy; override;
    property OnCommand: TPanelCmdEvent read FOnCommand write FOnCommand;
  end;

implementation

var
  GREEN, RED, BLUE, GREY, AMBER: TBGRAPixel;

{ TfrmPanel }

constructor TfrmPanel.CreatePanel(AOwner: TComponent; ASim: TWinderSim);
begin
  inherited CreateNew(AOwner, 1);
  FSim := ASim;
  Caption := 'Winder Density Simulator 3 – Manual Panel';
  Width := Min(1000, Screen.WorkAreaWidth);
  Height := Min(620, Screen.WorkAreaHeight);
  Position := poDefaultPosOnly;
  Color := RGBToColor(40, 44, 50);
  FBmp := TBGRABitmap.Create(16, 16);
  FPressed := -1;
  SimMult := 1;
  PBox := TPaintBox.Create(Self);
  PBox.Parent := Self;
  PBox.Align := alClient;
  PBox.OnPaint := @PBoxPaint;
  PBox.OnMouseDown := @PBoxMouseDown;
  PBox.OnMouseUp := @PBoxMouseUp;

  // WINDER
  AddBtn(24, 90, 104, 140, PC_START, 'START', GREEN);
  AddBtn(114, 90, 194, 140, PC_STOP, 'STOP', RED);
  AddBtn(204, 90, 304, 140, PC_RESET, 'RESET', BLUE);
  AddBtn(24, 150, 304, 186, PC_RUNEND, 'RUN TO END (จำลองจนจบ)', GREY);
  // CONTACT ROLL - LINEAR MOTOR
  AddBtn(352, 90, 492, 136, PC_PRESS, 'PRESS กด', GREEN);
  AddBtn(502, 90, 642, 136, PC_RETRACT, 'RETRACT ถอย', AMBER);
  AddBtn(352, 146, 492, 186, PC_LM_BACK, '◀ JOG BACK', GREY);
  AddBtn(502, 146, 642, 186, PC_LM_FWD, 'JOG FWD ▶', GREY);
  AddBtn(352, 196, 412, 230, PC_NIP_DN, 'N ▼', GREY);
  AddBtn(582, 196, 642, 230, PC_NIP_UP, 'N ▲', GREY);
  // TENSION ROLL - SERVO
  AddBtn(684, 90, 784, 136, PC_SRV_BACK, '◀ BACK', GREY);
  AddBtn(794, 90, 874, 136, PC_SRV_HOME, 'HOME 0', BLUE);
  AddBtn(884, 90, 976, 136, PC_SRV_FWD, 'AHEAD ▶', GREY);
  // SETPOINTS
  AddBtn(24, 440, 74, 474, PC_SPD_DN, '▼', GREY);
  AddBtn(204, 440, 254, 474, PC_SPD_UP, '▲', GREY);
  AddBtn(264, 440, 314, 474, PC_TEN_DN, '▼', GREY);
  AddBtn(444, 440, 494, 474, PC_TEN_UP, '▲', GREY);
  AddBtn(24, 520, 74, 554, PC_TAP_DN, '▼', GREY);
  AddBtn(204, 520, 254, 554, PC_TAP_UP, '▲', GREY);
  AddBtn(264, 520, 314, 554, PC_SIM_DN, '▼', GREY);
  AddBtn(444, 520, 494, 554, PC_SIM_UP, '▲', GREY);
  // E-STOP
  AddBtn(870, 440, 970, 540, PC_ESTOP, 'E-STOP', RED);
end;

destructor TfrmPanel.Destroy;
begin
  FBmp.Free;
  inherited Destroy;
end;

procedure TfrmPanel.AddBtn(ax1, ay1, ax2, ay2: Single; ACmd: Integer; const ACap: string;
  AColor: TBGRAPixel);
begin
  SetLength(FBtns, Length(FBtns) + 1);
  with FBtns[High(FBtns)] do
  begin
    X1 := ax1; Y1 := ay1; X2 := ax2; Y2 := ay2;
    Cmd := ACmd;
    Caption := ACap;
    Color := AColor;
  end;
end;

function TfrmPanel.HitTest(X, Y: Integer): Integer;
var
  i: Integer;
  dx, dy: Single;
begin
  Result := -1;
  if FSc <= 0 then Exit;
  dx := (X - FOx) / FSc;
  dy := (Y - FOy) / FSc;
  for i := 0 to High(FBtns) do
    if (dx >= FBtns[i].X1) and (dx <= FBtns[i].X2) and (dy >= FBtns[i].Y1) and
      (dy <= FBtns[i].Y2) then
      Exit(i);
end;

function TfrmPanel.Lit(Cmd: Integer): Boolean;
begin
  case Cmd of
    PC_START: Result := Running;
    PC_STOP: Result := (not Running) and (not FSim.Finished);
    PC_PRESS: Result := FSim.P.ContactMode = CM_PRESS;
    PC_RETRACT: Result := FSim.P.ContactMode = CM_RETRACT;
    PC_SRV_HOME: Result := Abs(FSim.P.LeadCmdMm) < 0.01;
    PC_ESTOP: Result := EStop;
  else
    Result := False;
  end;
end;

procedure TfrmPanel.PBoxMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FPressed := HitTest(X, Y);
  PBox.Invalidate;
end;

procedure TfrmPanel.PBoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  i := HitTest(X, Y);
  if (i >= 0) and (i = FPressed) and Assigned(FOnCommand) then
    FOnCommand(FBtns[i].Cmd);
  FPressed := -1;
  PBox.Invalidate;
end;

procedure TfrmPanel.RenderTo(ABmp: TBGRABitmap);
var
  sc, ox, oy: Single;
begin
  // export render: keep the on-screen scale used for button hit tests
  sc := FSc; ox := FOx; oy := FOy;
  DoRender(ABmp);
  FSc := sc; FOx := ox; FOy := oy;
end;

procedure TfrmPanel.DoRender(ABmp: TBGRABitmap);
var
  bmp: TBGRABitmap;
  i: Integer;
  b: TPBtn;
  c: TBGRAPixel;
  g: TGeo;
  wn: TStringList;

  function SX(v: Single): Single;
  begin
    Result := FOx + v * FSc;
  end;

  function SY(v: Single): Single;
  begin
    Result := FOy + v * FSc;
  end;

  function FS(h: Single): Integer;
  begin
    Result := Max(7, Round(h * FSc));
  end;

  procedure Section(x1, y1, x2, y2: Single; const Title: string);
  begin
    bmp.FillRoundRectAntialias(SX(x1), SY(y1), SX(x2), SY(y2), 8 * FSc, 8 * FSc,
      BGRA(58, 63, 72));
    bmp.RoundRectAntialias(SX(x1), SY(y1), SX(x2), SY(y2), 8 * FSc, 8 * FSc,
      BGRA(100, 108, 120), 1.5);
    bmp.FillRoundRectAntialias(SX(x1), SY(y1), SX(x2), SY(y1 + 26), 8 * FSc, 8 * FSc,
      BGRA(30, 60, 100));
    Txt(bmp, SX(x1 + 10), SY(y1 + 5), Title, FS(14), BGRA(230, 236, 245), True);
  end;

  procedure Lamp(x, y: Single; const Cap: string; OnC: TBGRAPixel; IsOn: Boolean);
  begin
    if IsOn then
    begin
      bmp.FillEllipseAntialias(SX(x), SY(y), 14 * FSc, 14 * FSc,
        BGRA(OnC.red, OnC.green, OnC.blue, 90));
      bmp.FillEllipseAntialias(SX(x), SY(y), 9 * FSc, 9 * FSc, OnC);
      bmp.FillEllipseAntialias(SX(x - 3), SY(y - 3), 3 * FSc, 3 * FSc, BGRA(255, 255, 255, 160));
    end
    else
      bmp.FillEllipseAntialias(SX(x), SY(y), 9 * FSc, 9 * FSc,
        LerpC(OnC, BGRA(20, 20, 24), 0.75));
    bmp.EllipseAntialias(SX(x), SY(y), 9 * FSc, 9 * FSc, BGRA(15, 15, 18), 1.5);
    Txt(bmp, SX(x), SY(y + 13), Cap, FS(10), BGRA(200, 206, 216), False, taCenter);
  end;

  procedure Disp(x1, y1, x2: Single; const Cap, Val, Un: string);
  begin
    Txt(bmp, SX(x1), SY(y1), Cap, FS(11), BGRA(190, 196, 206));
    bmp.FillRoundRectAntialias(SX(x1), SY(y1 + 16), SX(x2), SY(y1 + 44), 4 * FSc, 4 * FSc,
      BGRA(8, 20, 12));
    bmp.FontName := 'Consolas';
    bmp.FontHeight := FS(19);
    bmp.FontStyle := [fsBold];
    bmp.TextOut(SX(x2 - 6 - 30), SY(y1 + 19), Val, BGRA(90, 255, 130), taRightJustify);
    Txt(bmp, SX(x2 - 32), SY(y1 + 25), Un, FS(10), BGRA(90, 200, 120));
  end;

begin
  bmp := ABmp;
  bmp.Fill(BGRA(40, 44, 50));
  FSc := Min(bmp.Width / 1000, bmp.Height / 600);
  FOx := (bmp.Width - 1000 * FSc) / 2;
  FOy := (bmp.Height - 600 * FSc) / 2;
  g := FSim.Geo(FSim.ROuterComp);

  Txt(bmp, SX(14), SY(10), 'MANUAL PANEL  –  WINDER 3  (Linear-motor contact roll / Servo tension roll)',
    FS(17), BGRA(235, 240, 248), True);
  Txt(bmp, SX(986), SY(14), FormatDateTime('hh:nn:ss', Now), FS(13), BGRA(160, 168, 180),
    False, taRightJustify);

  Section(10, 50, 320, 380, 'WINDER');
  Section(338, 50, 656, 380, 'CONTACT ROLL – LINEAR MOTOR');
  Section(670, 50, 990, 380, 'TENSION ROLL – SERVO');
  Section(10, 394, 506, 590, 'SETPOINTS');
  Section(520, 394, 990, 590, 'ALARMS');

  // winder displays + lamps
  Disp(24, 196, 164, 'LENGTH', FF(FSim.WoundLen, 0), 'm');
  Disp(174, 196, 304, 'Ø ROLL', FF(FSim.CurDia * 1000, 1), 'mm');
  Disp(24, 252, 164, 'ROLL SPEED', FF(FSim.RollRpm, 1), 'rpm');
  Disp(174, 252, 304, 'ρ AVG', FF(FSim.RhoAvg / 1000, 4), 'g/cc');
  Disp(24, 308, 164, 'TIME', HMS(FSim.SimTime), '');
  Lamp(200, 336, 'RUN', BGRA(60, 230, 90), Running);
  Lamp(248, 336, 'DONE', BGRA(70, 160, 255), FSim.Finished);
  Lamp(292, 336, 'E-STOP', BGRA(255, 60, 50), EStop);

  // linear motor
  Disp(420, 196, 574, 'NIP SET', FF(FSim.NipSet(FSim.RWound), 0), 'N/m');
  Disp(352, 252, 492, 'GAP', FF(FSim.GapAct * 1000, 1), 'mm');
  Disp(502, 252, 642, 'FORCE', FF(FSim.LinForceN, 0), 'N');
  Disp(352, 308, 470, 'CURRENT', FF(FSim.LinCurrentA, 2), 'A');
  Lamp(505, 336, 'NIP ON', BGRA(60, 230, 90), FSim.NipActive);
  Lamp(563, 336, 'MOVING', BGRA(255, 190, 40), Abs(FSim.GapVel) > 1e-6);
  Lamp(622, 336, 'OVERLOAD', BGRA(255, 60, 50), FSim.LinForceN > FSim.P.LinFmaxN);

  // servo
  Disp(684, 146, 826, 'LEAD CMD', FF(FSim.P.LeadCmdMm, 0), 'mm');
  Disp(836, 146, 976, 'LEAD ACT', FF(g.Lead * 1000, 1), 'mm');
  Disp(684, 202, 826, 'WEB ANGLE φ', FF(g.FilmAngle * 180 / Pi, 1), '°');
  Disp(836, 202, 976, 'LOAD CELL', FF(FSim.LoadCellN, 0), 'N');
  Disp(684, 258, 826, 'TORQUE', FF(FSim.ServoTorqueNm, 2), 'N·m');
  Disp(836, 258, 976, 'WRAP θT', FF(g.ThetaT * 180 / Pi, 1), '°');
  Lamp(730, 336, 'MOVING', BGRA(255, 190, 40), Abs(FSim.LeadVel) > 1e-6);
  Lamp(800, 336, 'LIMIT', BGRA(255, 60, 50), g.Limited);
  Lamp(870, 336, 'OVERLOAD', BGRA(255, 60, 50), FSim.ServoTorqueNm > FSim.P.ServoRatedNm);
  Lamp(940, 336, 'PRE-WRAP', BGRA(255, 120, 60), g.BetaW > 0.005);

  // setpoints
  Disp(84, 424, 194, 'SPEED', FF(FSim.P.SpeedMpm, 0), 'm/m');
  Disp(324, 424, 434, 'TENSION Tw0', FF(FSim.P.TensionNm, 0), 'N/m');
  Disp(84, 504, 194, 'TAPER', FF(FSim.P.TaperPct, 0), '%');
  Disp(324, 504, 434, 'SIM ×', FF(SimMult, 0), '');

  // alarms from the model warnings
  wn := TStringList.Create;
  try
    FSim.GetWarnings(wn);
    Lamp(560, 440, 'NO NIP', BGRA(255, 60, 50), Pos('[NO NIP]', wn.Text) > 0);
    Lamp(625, 440, 'AIR', BGRA(255, 120, 60), Pos('[AIR]', wn.Text) > 0);
    Lamp(690, 440, 'CORE P', BGRA(255, 60, 50), Pos('[CORE]', wn.Text) > 0);
    Lamp(755, 440, 'CD NIP', BGRA(255, 190, 40), Pos('[CD]', wn.Text) > 0);
    Lamp(820, 440, 'SOFT', BGRA(255, 190, 40), Pos('[SOFT]', wn.Text) > 0);
    Lamp(560, 500, 'TENSION', BGRA(255, 60, 50), Pos('[TENSION]', wn.Text) > 0);
    Lamp(625, 500, 'TAPER', BGRA(255, 190, 40), Pos('[TAPER]', wn.Text) > 0);
    Lamp(690, 500, 'NIP MARK', BGRA(255, 190, 40), Pos('[NIP]', wn.Text) > 0);
    Lamp(755, 500, 'LM OVL', BGRA(255, 60, 50), Pos('[LM]', wn.Text) > 0);
    Lamp(820, 500, 'SRV', BGRA(255, 60, 50), Pos('[SERVO]', wn.Text) > 0);
    if wn.Count > 0 then
      Txt(bmp, SX(540), SY(556), Copy(wn[0], 1, 70), FS(10), BGRA(255, 200, 120));
  finally
    wn.Free;
  end;

  // buttons
  for i := 0 to High(FBtns) do
  begin
    b := FBtns[i];
    c := b.Color;
    if b.Cmd = PC_ESTOP then
    begin
      // yellow collar + red mushroom
      bmp.FillEllipseAntialias(SX((b.X1 + b.X2) / 2), SY((b.Y1 + b.Y2) / 2),
        (b.X2 - b.X1) / 2 * FSc, (b.Y2 - b.Y1) / 2 * FSc, BGRA(250, 210, 40));
      if i = FPressed then c := LerpC(c, BGRA(0, 0, 0), 0.35);
      if Lit(b.Cmd) then c := BGRA(255, 40, 30);
      bmp.FillEllipseAntialias(SX((b.X1 + b.X2) / 2), SY((b.Y1 + b.Y2) / 2),
        (b.X2 - b.X1) / 2.8 * FSc, (b.Y2 - b.Y1) / 2.8 * FSc, c);
      Txt(bmp, SX((b.X1 + b.X2) / 2), SY((b.Y1 + b.Y2) / 2 - 7), b.Caption, FS(12),
        BGRAWhite, True, taCenter);
      Continue;
    end;
    if not Lit(b.Cmd) then
      c := LerpC(c, BGRA(30, 32, 36), 0.45);
    if i = FPressed then
      c := LerpC(c, BGRA(0, 0, 0), 0.35);
    bmp.FillRoundRectAntialias(SX(b.X1) + 2, SY(b.Y1) + 3, SX(b.X2) + 2, SY(b.Y2) + 3,
      6 * FSc, 6 * FSc, BGRA(0, 0, 0, 120));
    bmp.FillRoundRectAntialias(SX(b.X1), SY(b.Y1), SX(b.X2), SY(b.Y2), 6 * FSc, 6 * FSc, c);
    bmp.RoundRectAntialias(SX(b.X1), SY(b.Y1), SX(b.X2), SY(b.Y2), 6 * FSc, 6 * FSc,
      LerpC(c, BGRAWhite, 0.4), 1.2);
    Txt(bmp, SX((b.X1 + b.X2) / 2), SY((b.Y1 + b.Y2) / 2) - FS(13) * 0.6, b.Caption, FS(13),
      BGRAWhite, True, taCenter);
  end;
end;

procedure TfrmPanel.PBoxPaint(Sender: TObject);
begin
  if (PBox.Width < 50) or (PBox.Height < 50) then Exit;
  if (FBmp.Width <> PBox.Width) or (FBmp.Height <> PBox.Height) then
    FBmp.SetSize(PBox.Width, PBox.Height);
  DoRender(FBmp);
  FBmp.Draw(PBox.Canvas, 0, 0, True);
end;

initialization
  GREEN := BGRA(60, 170, 70);
  RED := BGRA(200, 50, 50);
  BLUE := BGRA(50, 120, 200);
  GREY := BGRA(95, 100, 110);
  AMBER := BGRA(230, 160, 40);

end.
