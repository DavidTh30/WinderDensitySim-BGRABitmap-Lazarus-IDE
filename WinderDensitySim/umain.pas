unit uMain;

{ Graphics window: winder animation, KPI tiles, charts and parameter sliders.
  Built entirely in code (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, LCLType, Forms, Controls, Graphics, ExtCtrls, StdCtrls,
  ComCtrls, BGRABitmap, BGRABitmapTypes, uWinderModel, uWinderDraw, uDevForm;

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
    PanelLeft: TScrollBox;
    PBox: TPaintBox;
    Timer: TTimer;
    BtnRun, BtnReset, BtnEnd, BtnDev: TButton;
    LblHint: TLabel;
    SlThick, SlLen, SlWidth, SlCore, SlContact, SlSpeed, SlTension, SlTaper,
      SlNip, SlNipTaper, SlSim: TParamSlider;
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
    procedure ApplyCmdLine;
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
  Caption := 'Winder Density Simulator – Graphics';
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
  SlSim := AddSlider('ความเร็วจำลอง (Sim ×)', 'เท่า', 0, 40, 1, 0, False);
  SlSim.LogScale := True;

  AddHeader('ฟิล์ม Nylon (BOPA)  * เปลี่ยนแล้วรีเซ็ต');
  SlThick := AddSlider('ความหนาฟิล์ม', 'µm', 20, 50, 0.5, 1, True);
  SlLen := AddSlider('ความยาวฟิล์ม', 'm', 50, 100, 500, 0, True);
  SlWidth := AddSlider('หน้ากว้างฟิล์ม', 'mm', 50, 600, 10, 0, True);

  AddHeader('อุปกรณ์ Winder  * เปลี่ยนแล้วรีเซ็ต');
  SlCore := AddSlider('Ø Mill roll', 'mm', 30, 60, 10, 0, True);
  SlContact := AddSlider('Ø Contact roll', 'mm', 15, 40, 10, 0, True);

  AddHeader('เงื่อนไขการม้วน (ปรับได้ขณะเดินเครื่อง)');
  SlSpeed := AddSlider('Line speed', 'm/min', 120, 250, 1, 0, False);
  SlTension := AddSlider('แรงตึง Tw0', 'N/m', 6, 60, 5, 0, False);
  SlTaper := AddSlider('Tension taper', '%', 0, 60, 1, 0, False);
  SlNip := AddSlider('แรงกด Contact roll N0', 'N/m', 5, 150, 10, 0, False);
  SlNipTaper := AddSlider('Nip taper', '%', 0, 60, 1, 0, False);

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
    'Space = เริ่ม/หยุด,  R = รีเซ็ต,  E = จำลองจนจบ,  F12 = Developer';

  SimToSliders;
  SlSim.TB.Position := 20;  // x100
  SlSim.UpdateLabel;

  FDev := TfrmDev.CreateDev(Self, FSim);
  FDev.OnParamsChanged := @DevParamsChanged;
  FDev.ExportPanel.SetViews(['Graphics (หน้าต่างหลัก)'], @RenderView, @ViewSize);
  FDev.ExportPanel.OnSimAdvanced := @DevSimAdvanced;

  OnKeyDown := @FormKeyDown;
  Timer := TTimer.Create(Self);
  Timer.Interval := 33;
  Timer.OnTimer := @TimerTick;
  FLastTick := GetTickCount64;
  Timer.Enabled := True;
  UpdateRunButton;
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
  PBox.Invalidate;
end;

procedure TfrmMain.RenderView(View: Integer; bmp: TBGRABitmap);
begin
  RenderScene(bmp, FSim, FAngRoll, FAngContact, SimMult, FRunning);
end;

function TfrmMain.ViewSize(View: Integer): TPoint;
begin
  Result := Point(PBox.Width, PBox.Height);
end;

procedure TfrmMain.DevSimAdvanced(Sender: TObject);
begin
  // time-lapse export moved the roll forward
  UpdateRunButton;
  PBox.Invalidate;
end;
procedure TfrmMain.ApplyCmdLine;
var
  i: Integer;
  a: string;
begin
  // developer test options: end  dev  devtab=<n>  devexport  png:<view>:<file>  gif:<view>:<file>
  for i := 1 to ParamCount do
  begin
    a := LowerCase(ParamStr(i));
    if a = 'end' then
      BtnEndClick(nil)
    else if a = 'dev' then
      BtnDevClick(nil)
    else if Copy(a, 1, 7) = 'devtab=' then
      FDev.ShowTab(StrToIntDef(Copy(a, 8, 3), 0))
    else if a = 'devexport' then
      FDev.ShowExportTab
    else if Copy(a, 1, 4) = 'png:' then
      FDev.ExportPanel.ExportPngFile(StrToIntDef(Copy(a, 5, 1), 0), Copy(ParamStr(i), 7, 1000))
    else if Copy(a, 1, 4) = 'gif:' then
      FDev.ExportPanel.ExportTimeLapseFile(StrToIntDef(Copy(a, 5, 1), 0), 20, Copy(ParamStr(i), 7, 1000));
  end;
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

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_SPACE: begin BtnRunClick(nil); Key := 0; end;
    VK_R: begin BtnResetClick(nil); Key := 0; end;
    VK_E: begin BtnEndClick(nil); Key := 0; end;
    VK_F12: begin BtnDevClick(nil); Key := 0; end;
  end;
end;

procedure TfrmMain.BtnRunClick(Sender: TObject);
begin
  if FSim.Finished then Exit;
  FRunning := not FRunning;
  UpdateRunButton;
end;

procedure TfrmMain.BtnResetClick(Sender: TObject);
begin
  FRunning := False;
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
    if FSim.Finished then
    begin
      FRunning := False;
      UpdateRunButton;
    end;
    PBox.Invalidate;
  end;
  Inc(FTickCount);
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
