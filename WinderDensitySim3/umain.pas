unit uMain;

{ Graphics window: winder animation, KPI tiles, charts and parameter sliders.
  Built entirely in code (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, LCLType, Forms, Controls, Graphics, ExtCtrls, StdCtrls,
  ComCtrls, BGRABitmap, BGRABitmapTypes, uWinderModel, uWinderDraw, uDevForm, uCrossView,
  uManualPanel, uTopView;

type
  TParamSlider = class
    Lbl: TLabel;
    TB: TTrackBar;
    Caption, UnitStr: string;
    Scale: Double;
    Decimals: Integer;
    Structural: Boolean;   // change requires a new roll (reset)
    LogScale: Boolean;     // label shows 10^(pos/10)
    function Value: Double;
    procedure SetValue(v: Double);
    procedure UpdateLabel;
  end;

  { TfrmMain }

  TfrmMain = class(TForm)
  private
    FSim: TWinderSim;
    FBmp: TBGRABitmap;
    FDev: TfrmDev;
    FCross: TfrmCross;
    FPanel: TfrmPanel;
    FTop: TfrmTop;
    FEStop: Boolean;
    BtnCross, BtnPanel, BtnTop: TButton;
    PanelLeft: TScrollBox;
    PBox: TPaintBox;
    Timer: TTimer;
    BtnRun, BtnReset, BtnEnd, BtnDev: TButton;
    LblHint: TLabel;
    SlThick, SlLen, SlWidth, SlCore, SlContact, SlSpeed, SlTension, SlTaper,
      SlNip, SlNipTaper, SlSim, SlRetract, SlLead: TParamSlider;
    BtnPress, BtnRetract, BtnJogBack, BtnJogFwd: TButton;
    FSliders: TList;
    FY: Integer;
    FRunning, FLoading: Boolean;
    FAngRoll, FAngContact: Double;
    FLastTick: QWord;
    FTickCount: Integer;
    function AddSlider(const ACaption, AUnit: string; AMin, AMax: Integer;
      AScale: Double; ADec: Integer; AStructural: Boolean): TParamSlider;
    function AddButton(const ACaption: string; AClick: TNotifyEvent): TButton;
    procedure AddHeader(const ACaption: string);
    procedure SliderChange(Sender: TObject);
    procedure ParamsToSim;
    procedure SimToSliders;
    function SimMult: Double;
    procedure TimerTick(Sender: TObject);
    procedure PBoxPaint(Sender: TObject);
    procedure BtnRunClick(Sender: TObject);
    procedure BtnResetClick(Sender: TObject);
    procedure BtnEndClick(Sender: TObject);
    procedure BtnDevClick(Sender: TObject);
    procedure DevParamsChanged(Sender: TObject);
    procedure UpdateRunButton;
    procedure RenderView(View: Integer; bmp: TBGRABitmap);
    function ViewSize(View: Integer): TPoint;
    procedure DevSimAdvanced(Sender: TObject);
    procedure UpdateModeButtons;
    procedure AddButtonPair(const C1, C2: string; E1, E2: TNotifyEvent;
      out B1, B2: TButton);
    procedure BtnPressClick(Sender: TObject);
    procedure BtnRetractClick(Sender: TObject);
    procedure BtnJogClick(Sender: TObject);
    procedure ApplyCmdLine;
    procedure BtnCrossClick(Sender: TObject);
    procedure BtnPanelClick(Sender: TObject);
    procedure BtnTopClick(Sender: TObject);
    procedure DoPanelCmd(Cmd: Integer);
    procedure RefreshSideWindows;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  frmMain: TfrmMain;

implementation

{ TParamSlider }

function TParamSlider.Value: Double;
begin
  Result := TB.Position * Scale;
end;

procedure TParamSlider.SetValue(v: Double);
begin
  TB.Position := Round(v / Scale);
end;

procedure TParamSlider.UpdateLabel;
begin
  if LogScale then
    Lbl.Caption := Caption + ':  ' + FF(Power(10, TB.Position / 10), 0) + ' ' + UnitStr
  else
    Lbl.Caption := Caption + ':  ' + FF(Value, Decimals) + ' ' + UnitStr;
end;

{ TfrmMain }

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'Winder Density Simulator 3 – Graphics';
  Width := Min(1500, Screen.WorkAreaWidth);
  Height := Min(900, Screen.WorkAreaHeight);
  Position := poScreenCenter;
  WindowState := wsMaximized;
  Color := RGBToColor(22, 26, 33);
  KeyPreview := True;

  FSim := TWinderSim.Create;
  FBmp := TBGRABitmap.Create(16, 16);
  FSliders := TList.Create;

  PanelLeft := TScrollBox.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 285;
  PanelLeft.HorzScrollBar.Visible := False;
  PanelLeft.Color := RGBToColor(240, 242, 245);

  PBox := TPaintBox.Create(Self);
  PBox.Parent := Self;
  PBox.Align := alClient;
  PBox.OnPaint := @PBoxPaint;

  FY := 8;
  BtnRun := AddButton('▶ เริ่มม้วน (Start)', @BtnRunClick);
  BtnReset := AddButton('⟲ รีเซ็ต / ม้วนใหม่ (Reset)', @BtnResetClick);
  BtnEnd := AddButton('⏭ จำลองจนจบม้วน (Run to end)', @BtnEndClick);
  BtnDev := AddButton('🛈 หน้าต่างนักพัฒนา (Developer)', @BtnDevClick);
  BtnCross := AddButton('▭ ภาพแนวขวาง (Cross view)', @BtnCrossClick);
  BtnPanel := AddButton('🎛 Manual Panel', @BtnPanelClick);
  BtnTop := AddButton('⊞ Top View (มองจากด้านบน)', @BtnTopClick);
  SlSim := AddSlider('ความเร็วจำลอง (Sim ×)', 'เท่า', 0, 40, 1, 0, False);
  SlSim.LogScale := True;

  AddHeader('ฟิล์ม Nylon (BOPA)  * เปลี่ยนแล้วรีเซ็ต');
  SlThick := AddSlider('ความหนาฟิล์ม', 'µm', 20, 50, 0.5, 1, True);
  SlLen := AddSlider('ความยาวฟิล์ม', 'm', 50, 100, 500, 0, True);
  SlWidth := AddSlider('หน้ากว้างฟิล์ม', 'mm', 50, 600, 10, 0, True);

  AddHeader('อุปกรณ์ Winder  * เปลี่ยนแล้วรีเซ็ต');
  SlCore := AddSlider('Ø Mill roll', 'mm', 30, 60, 10, 0, True);
  SlContact := AddSlider('Ø Contact = Tension roll', 'mm', 15, 40, 10, 0, True);

  AddHeader('เงื่อนไขการม้วน (ปรับได้ขณะเดินเครื่อง)');
  SlSpeed := AddSlider('Line speed', 'm/min', 120, 250, 1, 0, False);
  SlTension := AddSlider('แรงตึง Tw0', 'N/m', 6, 60, 5, 0, False);
  SlTaper := AddSlider('Tension taper', '%', 0, 60, 1, 0, False);

  AddHeader('Contact roll – Linear motor');
  AddButtonPair('◀ ถอยหลัง (Retract)', 'เดินหน้า กด ▶ (Press)', @BtnRetractClick,
    @BtnPressClick, BtnRetract, BtnPress);
  SlNip := AddSlider('แรงกดฟิล์ม N0', 'N/m', 5, 150, 10, 0, False);
  SlNipTaper := AddSlider('Nip taper', '%', 0, 60, 1, 0, False);
  SlRetract := AddSlider('ระยะถอย', 'mm', 2, 30, 5, 0, False);

  AddHeader('Tension roll – Servo motor');
  AddButtonPair('◀ ถอย 10 mm', 'ล้ำหน้า 10 mm ▶', @BtnJogClick, @BtnJogClick,
    BtnJogBack, BtnJogFwd);
  SlLead := AddSlider('ระยะล้ำหน้า Contact roll (lead)', 'mm', -30, 30, 5, 0, False);

  LblHint := TLabel.Create(Self);
  LblHint.Parent := PanelLeft;
  LblHint.Left := 10;
  LblHint.Top := FY + 6;
  LblHint.Width := 255;
  LblHint.WordWrap := True;
  LblHint.AutoSize := True;
  LblHint.Font.Color := clGray;
  LblHint.Caption := 'ค่าสัมประสิทธิ์ทางฟิสิกส์ (ρ, E, Rq, μ, Kn, α, Pasp ...) ' +
    'แก้ไขได้ในหน้าต่าง Developer > Coefficients' + LineEnding +
    'lead < 0 : ฟิล์มพัน Contact roll ก่อนเข้า nip' + LineEnding +
    'lead > 0 : ฟิล์มแตะม้วนก่อน nip (pre-wrap) อากาศเข้ามากขึ้น' + LineEnding +
    'Space = เริ่ม/หยุด,  R = รีเซ็ต,  E = จำลองจนจบ,  F12 = Developer,  F9 = Top View,  F10 = Cross view,  F11 = Manual Panel';

  SimToSliders;
  SlSim.TB.Position := 20;  // x100
  SlSim.UpdateLabel;

  FDev := TfrmDev.CreateDev(Self, FSim);
  FDev.OnParamsChanged := @DevParamsChanged;
  FCross := TfrmCross.CreateCross(Self, FSim);
  FPanel := TfrmPanel.CreatePanel(Self, FSim);
  FPanel.OnCommand := @DoPanelCmd;
  FTop := TfrmTop.CreateTop(Self, FSim);
  FDev.ExportPanel.SetViews(['Graphics (หน้าต่างหลัก)', 'Cross view (ภาพแนวขวาง)',
    'Top View (มองจากด้านบน)', 'Manual Panel'], @RenderView, @ViewSize);
  FDev.ExportPanel.OnSimAdvanced := @DevSimAdvanced;

  OnKeyDown := @FormKeyDown;
  Timer := TTimer.Create(Self);
  Timer.Interval := 33;
  Timer.OnTimer := @TimerTick;
  FLastTick := GetTickCount64;
  Timer.Enabled := True;
  UpdateRunButton;
  UpdateModeButtons;
  ApplyCmdLine;
end;

destructor TfrmMain.Destroy;
var
  i: Integer;
begin
  Timer.Enabled := False;
  for i := 0 to FSliders.Count - 1 do
    TParamSlider(FSliders[i]).Free;
  FSliders.Free;
  FBmp.Free;
  inherited Destroy;
  FSim.Free;   // dev form (owned) is gone now
end;

procedure TfrmMain.AddHeader(const ACaption: string);
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := PanelLeft;
  L.Left := 10;
  L.Top := FY + 8;
  L.Font.Style := [fsBold];
  L.Font.Color := RGBToColor(20, 90, 160);
  L.Caption := ACaption;
  Inc(FY, 32);
end;

function TfrmMain.AddButton(const ACaption: string; AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := PanelLeft;
  Result.Left := 10;
  Result.Top := FY;
  Result.Width := 250;
  Result.Height := 30;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Inc(FY, 34);
end;

function TfrmMain.AddSlider(const ACaption, AUnit: string; AMin, AMax: Integer;
  AScale: Double; ADec: Integer; AStructural: Boolean): TParamSlider;
begin
  Result := TParamSlider.Create;
  Result.Caption := ACaption;
  Result.UnitStr := AUnit;
  Result.Scale := AScale;
  Result.Decimals := ADec;
  Result.Structural := AStructural;
  Result.Lbl := TLabel.Create(Self);
  Result.Lbl.Parent := PanelLeft;
  Result.Lbl.Left := 12;
  Result.Lbl.Top := FY;
  Result.TB := TTrackBar.Create(Self);
  Result.TB.Parent := PanelLeft;
  Result.TB.Left := 6;
  Result.TB.Top := FY + 16;
  Result.TB.Width := 256;
  Result.TB.Height := 28;
  Result.TB.TickStyle := tsNone;
  Result.TB.Min := AMin;
  Result.TB.Max := AMax;
  Result.TB.Tag := FSliders.Count;
  Result.TB.OnChange := @SliderChange;
  FSliders.Add(Result);
  Result.UpdateLabel;
  Inc(FY, 48);
end;

function TfrmMain.SimMult: Double;
begin
  // 0..40 -> 1x .. 10000x (log scale)
  Result := Power(10, SlSim.TB.Position / 10);
end;

procedure TfrmMain.SimToSliders;
begin
  FLoading := True;
  try
    SlThick.SetValue(FSim.P.ThickUm);
    SlLen.SetValue(FSim.P.LengthM);
    SlWidth.SetValue(FSim.P.WidthMm);
    SlCore.SetValue(FSim.P.CoreDiaMm);
    SlContact.SetValue(FSim.P.ContactDiaMm);
    SlSpeed.SetValue(FSim.P.SpeedMpm);
    SlTension.SetValue(FSim.P.TensionNm);
    SlTaper.SetValue(FSim.P.TaperPct);
    SlNip.SetValue(FSim.P.NipNm);
    SlNipTaper.SetValue(FSim.P.NipTaperPct);
    SlRetract.SetValue(FSim.P.RetractMm);
    SlLead.SetValue(FSim.P.LeadCmdMm);
  finally
    FLoading := False;
  end;
end;

procedure TfrmMain.ParamsToSim;
begin
  FSim.P.ThickUm := SlThick.Value;
  FSim.P.LengthM := SlLen.Value;
  FSim.P.WidthMm := SlWidth.Value;
  FSim.P.CoreDiaMm := SlCore.Value;
  FSim.P.ContactDiaMm := SlContact.Value;
  FSim.P.SpeedMpm := SlSpeed.Value;
  FSim.P.TensionNm := SlTension.Value;
  FSim.P.TaperPct := SlTaper.Value;
  FSim.P.NipNm := SlNip.Value;
  FSim.P.NipTaperPct := SlNipTaper.Value;
  FSim.P.RetractMm := SlRetract.Value;
  FSim.P.LeadCmdMm := SlLead.Value;
end;

procedure TfrmMain.SliderChange(Sender: TObject);
var
  S: TParamSlider;
begin
  S := TParamSlider(FSliders[TTrackBar(Sender).Tag]);
  S.UpdateLabel;
  if FLoading or (S = SlSim) then
  begin
    PBox.Invalidate;
    Exit;
  end;
  ParamsToSim;
  if S.Structural then
  begin
    FRunning := False;
    FSim.Reset;
    UpdateRunButton;
  end
  else
    FSim.Solve;
  PBox.Invalidate;
end;

procedure TfrmMain.DevParamsChanged(Sender: TObject);
begin
  FRunning := False;
  FSim.Reset;
  SimToSliders;
  UpdateRunButton;
  UpdateModeButtons;
  PBox.Invalidate;
end;

procedure TfrmMain.RenderView(View: Integer; bmp: TBGRABitmap);
begin
  case View of
    1: RenderCross(bmp, FSim);
    2: RenderTop(bmp, FSim, FTop.Phase);
    3:
      begin
        FPanel.Running := FRunning;
        FPanel.EStop := FEStop;
        FPanel.SimMult := SimMult;
        FPanel.RenderTo(bmp);
      end;
  else
    RenderScene(bmp, FSim, FAngRoll, FAngContact, SimMult, FRunning);
  end;
end;

function TfrmMain.ViewSize(View: Integer): TPoint;
begin
  case View of
    1: Result := Point(FCross.ClientWidth, FCross.ClientHeight);
    2: Result := Point(FTop.ClientWidth, FTop.ClientHeight);
    3: Result := Point(FPanel.ClientWidth, FPanel.ClientHeight);
  else
    Result := Point(PBox.Width, PBox.Height);
  end;
end;

procedure TfrmMain.DevSimAdvanced(Sender: TObject);
begin
  // time-lapse export moved the roll forward
  UpdateRunButton;
  PBox.Invalidate;
  RefreshSideWindows;
end;
procedure TfrmMain.UpdateRunButton;
begin
  if FRunning then
    BtnRun.Caption := '❚❚ หยุด (Pause)'
  else if FSim.Finished then
    BtnRun.Caption := '✔ ม้วนเสร็จแล้ว'
  else
    BtnRun.Caption := '▶ เริ่มม้วน (Start)';
end;

procedure TfrmMain.AddButtonPair(const C1, C2: string; E1, E2: TNotifyEvent;
  out B1, B2: TButton);
begin
  B1 := AddButton(C1, E1);
  B1.Width := 123;
  Dec(FY, 34);
  B2 := AddButton(C2, E2);
  B2.Left := 137;
  B2.Width := 123;
end;

procedure TfrmMain.UpdateModeButtons;
begin
  BtnPress.Font.Style := [];
  BtnRetract.Font.Style := [];
  if FSim.P.ContactMode = CM_PRESS then
    BtnPress.Font.Style := [fsBold]
  else
    BtnRetract.Font.Style := [fsBold];
end;

procedure TfrmMain.BtnPressClick(Sender: TObject);
begin
  FSim.P.ContactMode := CM_PRESS;
  UpdateModeButtons;
end;

procedure TfrmMain.BtnRetractClick(Sender: TObject);
begin
  FSim.P.ContactMode := CM_RETRACT;
  UpdateModeButtons;
end;

procedure TfrmMain.ApplyCmdLine;
var
  i: Integer;
  a: string;
begin
  // developer test options: lead=<mm>  retract  end  dev  cross  panel  top
  //   devtab=<n>  devexport  png:<view>:<file>  gif:<view>:<file>
  for i := 1 to ParamCount do
  begin
    a := LowerCase(ParamStr(i));
    if Copy(a, 1, 5) = 'lead=' then
    begin
      SlLead.SetValue(StrToFloatDef(Copy(a, 6, 20), 0, FSDot));
      FSim.LeadAct := FSim.P.LeadCmdMm * 1e-3;
    end
    else if a = 'retract' then
    begin
      BtnRetractClick(nil);
      FSim.GapAct := FSim.P.RetractMm * 1e-3;
    end
    else if a = 'end' then
      BtnEndClick(nil)
    else if a = 'dev' then
      BtnDevClick(nil)
    else if a = 'cross' then
      BtnCrossClick(nil)
    else if a = 'panel' then
      BtnPanelClick(nil)
    else if a = 'top' then
      BtnTopClick(nil)
    else if a = 'devexport' then
      FDev.ShowExportTab
    else if Copy(a, 1, 7) = 'devtab=' then
      FDev.ShowTab(StrToIntDef(Copy(a, 8, 3), 0))
    else if Copy(a, 1, 4) = 'png:' then
      // png:<view>:<file>
      FDev.ExportPanel.ExportPngFile(StrToIntDef(Copy(a, 5, 1), 0), Copy(ParamStr(i), 7, 1000))
    else if Copy(a, 1, 4) = 'gif:' then
      // gif:<view>:<file>  time-lapse, 20 frames
      FDev.ExportPanel.ExportTimeLapseFile(StrToIntDef(Copy(a, 5, 1), 0), 20, Copy(ParamStr(i), 7, 1000));
  end;
end;

procedure TfrmMain.BtnCrossClick(Sender: TObject);
begin
  FCross.Show;
  FCross.BringToFront;
  FCross.Invalidate;
end;

procedure TfrmMain.BtnPanelClick(Sender: TObject);
begin
  FPanel.Show;
  FPanel.BringToFront;
  RefreshSideWindows;
end;

procedure TfrmMain.BtnTopClick(Sender: TObject);
begin
  FTop.Show;
  FTop.BringToFront;
  FTop.Invalidate;
end;

procedure TfrmMain.RefreshSideWindows;
begin
  if FCross.Visible then FCross.Invalidate;
  if FTop.Visible then FTop.Invalidate;
  if FPanel.Visible then
  begin
    FPanel.Running := FRunning;
    FPanel.EStop := FEStop;
    FPanel.SimMult := SimMult;
    FPanel.Invalidate;
  end;
end;

procedure TfrmMain.DoPanelCmd(Cmd: Integer);
begin
  case Cmd of
    PC_START:
      if not (FEStop or FSim.Finished) then FRunning := True;
    PC_STOP: FRunning := False;
    PC_RESET: BtnResetClick(nil);
    PC_RUNEND: if not FEStop then BtnEndClick(nil);
    PC_PRESS: if not FEStop then BtnPressClick(nil);
    PC_RETRACT: BtnRetractClick(nil);
    PC_LM_BACK:
      if FSim.P.ContactMode = CM_PRESS then BtnRetractClick(nil)
      else SlRetract.SetValue(SlRetract.Value + 10);
    PC_LM_FWD:
      if FSim.P.ContactMode = CM_RETRACT then
      begin
        if SlRetract.Value > 10 then SlRetract.SetValue(SlRetract.Value - 10)
        else if not FEStop then BtnPressClick(nil);
      end;
    PC_NIP_UP: SlNip.SetValue(SlNip.Value + 10);
    PC_NIP_DN: SlNip.SetValue(SlNip.Value - 10);
    PC_SRV_BACK: SlLead.SetValue(SlLead.Value - 10);
    PC_SRV_FWD: SlLead.SetValue(SlLead.Value + 10);
    PC_SRV_HOME: SlLead.SetValue(0);
    PC_SPD_UP: SlSpeed.SetValue(SlSpeed.Value + 5);
    PC_SPD_DN: SlSpeed.SetValue(SlSpeed.Value - 5);
    PC_TEN_UP: SlTension.SetValue(SlTension.Value + 5);
    PC_TEN_DN: SlTension.SetValue(SlTension.Value - 5);
    PC_TAP_UP: SlTaper.SetValue(SlTaper.Value + 5);
    PC_TAP_DN: SlTaper.SetValue(SlTaper.Value - 5);
    PC_SIM_UP: SlSim.TB.Position := SlSim.TB.Position + 5;
    PC_SIM_DN: SlSim.TB.Position := SlSim.TB.Position - 5;
    PC_ESTOP:
      begin
        // emergency stop: stop winding and pull the contact roll back
        FRunning := False;
        FEStop := True;
        BtnRetractClick(nil);
      end;
  end;
  UpdateRunButton;
  PBox.Invalidate;
  RefreshSideWindows;
  if FDev.Visible then FDev.RefreshData;
end;

procedure TfrmMain.BtnJogClick(Sender: TObject);
begin
  if Sender = BtnJogFwd then
    SlLead.SetValue(SlLead.Value + 10)
  else
    SlLead.SetValue(SlLead.Value - 10);
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_SPACE: begin BtnRunClick(nil); Key := 0; end;
    VK_R: begin BtnResetClick(nil); Key := 0; end;
    VK_E: begin BtnEndClick(nil); Key := 0; end;
    VK_F12: begin BtnDevClick(nil); Key := 0; end;
    VK_F10: begin BtnCrossClick(nil); Key := 0; end;
    VK_F11: begin BtnPanelClick(nil); Key := 0; end;
    VK_F9: begin BtnTopClick(nil); Key := 0; end;
  end;
end;

procedure TfrmMain.BtnRunClick(Sender: TObject);
begin
  if FSim.Finished or FEStop then Exit;
  FRunning := not FRunning;
  UpdateRunButton;
end;

procedure TfrmMain.BtnResetClick(Sender: TObject);
begin
  FRunning := False;
  FEStop := False;
  ParamsToSim;
  FSim.Reset;
  UpdateRunButton;
  PBox.Invalidate;
  if FDev.Visible then FDev.RefreshData;
end;

procedure TfrmMain.BtnEndClick(Sender: TObject);
begin
  Screen.Cursor := crHourGlass;
  try
    FSim.RunToEnd;
  finally
    Screen.Cursor := crDefault;
  end;
  FRunning := False;
  UpdateRunButton;
  PBox.Invalidate;
  if FDev.Visible then FDev.RefreshData;
end;

procedure TfrmMain.BtnDevClick(Sender: TObject);
begin
  FDev.Show;
  FDev.BringToFront;
  FDev.RefreshData;
end;

procedure TfrmMain.TimerTick(Sender: TObject);
var
  now: QWord;
  dt, wRoll: Double;
begin
  now := GetTickCount64;
  dt := Min(0.2, (now - FLastTick) / 1000);
  FLastTick := now;
  if FRunning then
  begin
    FSim.Step(dt * SimMult);
    // visual rotation slowed down 5x to avoid stroboscopic aliasing
    wRoll := FSim.U / Max(0.01, FSim.ROuterComp);
    FAngRoll := FAngRoll + wRoll * dt * 0.2;
    FAngContact := FAngContact - FSim.U / FSim.RContact * dt * 0.2;
    FTop.Phase := FTop.Phase + FSim.U * dt * 0.2;
    if FSim.Finished then
    begin
      FRunning := False;
      UpdateRunButton;
    end;
    PBox.Invalidate;
  end;
  // linear motor + servo axes move in real time, also while stopped
  if FSim.AxesMoving or (FSim.GapAct <> IfThen(FSim.P.ContactMode = CM_PRESS, 0,
    FSim.P.RetractMm * 1e-3)) or (Abs(FSim.LeadAct - FSim.P.LeadCmdMm * 1e-3) > 1e-6) then
  begin
    FSim.UpdateAxes(dt);
    if not FRunning then PBox.Invalidate;
  end;
  Inc(FTickCount);
  if FRunning or FSim.AxesMoving then
  begin
    if FTickCount mod 3 = 0 then RefreshSideWindows;
  end
  else if FTickCount mod 15 = 0 then
    RefreshSideWindows;
  if (FTickCount mod 15 = 0) and FDev.Visible and FRunning then
    FDev.RefreshData;
end;

procedure TfrmMain.PBoxPaint(Sender: TObject);
begin
  if (PBox.Width < 50) or (PBox.Height < 50) then Exit;
  if (FBmp.Width <> PBox.Width) or (FBmp.Height <> PBox.Height) then
    FBmp.SetSize(PBox.Width, PBox.Height);
  RenderScene(FBmp, FSim, FAngRoll, FAngContact, SimMult, FRunning);
  FBmp.Draw(PBox.Canvas, 0, 0, True);
end;

end.
