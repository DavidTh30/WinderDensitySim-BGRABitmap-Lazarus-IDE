unit uExportTab;

{ "Export PNG / GIF" tab of the developer window.
  The main form registers the views it can render (graphics, cross view ...);
  the developer window itself is always the last choice. PNG = one frame,
  GIF = animated, either recorded live while the machine runs or as a
  time-lapse that winds the roll to the end. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, BGRABitmap, BGRABitmapTypes, BGRAAnimatedGif,
  BGRAPalette, BGRAColorQuantization, uWinderModel;

type
  TViewRenderEvent = procedure(View: Integer; bmp: TBGRABitmap) of object;
  TViewSizeEvent = function(View: Integer): TPoint of object;

  { TExportPanel }

  TExportPanel = class(TComponent)
  private
    FSim: TWinderSim;
    FForm: TForm;                 // developer window (for its own screenshot)
    FRender: TViewRenderEvent;
    FSize: TViewSizeEvent;
    FOnSimAdvanced: TNotifyEvent;
    CbView, CbSize: TComboBox;
    RgMode: TRadioGroup;
    SeDur, SeFps, SeFrames: TSpinEdit;
    BtnPng, BtnGif, BtnCancel: TButton;
    LblStatus: TLabel;
    PBar: TProgressBar;
    DlgPng, DlgGif: TSaveDialog;
    Timer: TTimer;
    FGif: TBGRAAnimatedGif;
    FGifFile: string;
    FFramesWanted, FFrames: Integer;
    FCancel: Boolean;
    function AddLabel(AParent: TWinControl; X, Y: Integer; const S: string): TLabel;
    function IsDevView: Boolean;
    function RenderFrame: TBGRABitmap;
    procedure AddGifFrame(bmp: TBGRABitmap; DelayMs: Integer);
    procedure FinishGif;
    procedure SetBusy(Busy: Boolean);
    procedure BtnPngClick(Sender: TObject);
    procedure BtnGifClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure RgModeClick(Sender: TObject);
    procedure TimeLapse;
  public
    constructor CreatePanel(AOwner: TComponent; AParent: TWinControl; AForm: TForm;
      ASim: TWinderSim);
    destructor Destroy; override;
    procedure SetViews(const Names: array of string; ARender: TViewRenderEvent;
      ASize: TViewSizeEvent);
    // used by the buttons and by command-line tests
    procedure ExportPngFile(View: Integer; const FN: string);
    procedure ExportTimeLapseFile(View, Frames: Integer; const FN: string);
    property OnSimAdvanced: TNotifyEvent read FOnSimAdvanced write FOnSimAdvanced;
  end;

implementation

{ TExportPanel }

constructor TExportPanel.CreatePanel(AOwner: TComponent; AParent: TWinControl;
  AForm: TForm; ASim: TWinderSim);
var
  gb: TGroupBox;
begin
  inherited Create(AOwner);
  FSim := ASim;
  FForm := AForm;

  gb := TGroupBox.Create(Self);
  gb.Parent := AParent;
  gb.SetBounds(10, 10, 560, 120);
  gb.Caption := ' เลือกหน้าที่จะ Export ';
  AddLabel(gb, 12, 14, 'หน้า / หน้าต่าง:');
  CbView := TComboBox.Create(Self);
  CbView.Parent := gb;
  CbView.SetBounds(150, 10, 390, 26);
  CbView.Style := csDropDownList;
  CbView.Items.Add('Developer window (หน้านี้)');
  CbView.ItemIndex := 0;
  AddLabel(gb, 12, 52, 'ขนาดภาพ:');
  CbSize := TComboBox.Create(Self);
  CbSize.Parent := gb;
  CbSize.SetBounds(150, 48, 390, 26);
  CbSize.Style := csDropDownList;
  CbSize.Items.Add('เท่าหน้าต่างจริง');
  CbSize.Items.Add('960 × 540');
  CbSize.Items.Add('1280 × 720');
  CbSize.Items.Add('1600 × 900');
  CbSize.Items.Add('1920 × 1080');
  CbSize.ItemIndex := 0;
  AddLabel(gb, 12, 80, '(Developer window ใช้ขนาดหน้าต่างจริงเสมอ)').Font.Color := clGray;

  gb := TGroupBox.Create(Self);
  gb.Parent := AParent;
  gb.SetBounds(10, 140, 560, 70);
  gb.Caption := ' PNG (ภาพนิ่ง) ';
  BtnPng := TButton.Create(Self);
  BtnPng.Parent := gb;
  BtnPng.SetBounds(12, 8, 200, 32);
  BtnPng.Caption := 'Export PNG...';
  BtnPng.OnClick := @BtnPngClick;

  gb := TGroupBox.Create(Self);
  gb.Parent := AParent;
  gb.SetBounds(10, 220, 560, 230);
  gb.Caption := ' GIF (ภาพเคลื่อนไหว) ';
  RgMode := TRadioGroup.Create(Self);
  RgMode.Parent := gb;
  RgMode.SetBounds(12, 4, 530, 66);
  RgMode.Caption := '';
  RgMode.Items.Add('บันทึกสด ขณะเดินเครื่อง (Live)');
  RgMode.Items.Add('Time-lapse: เดินม้วนจากตอนนี้จนจบม้วน (ม้วนจะเดินจนจบ)');
  RgMode.ItemIndex := 0;
  RgMode.OnClick := @RgModeClick;
  AddLabel(gb, 12, 82, 'Live: ระยะเวลา [s]');
  SeDur := TSpinEdit.Create(Self);
  SeDur.Parent := gb;
  SeDur.SetBounds(150, 78, 70, 26);
  SeDur.MinValue := 1; SeDur.MaxValue := 120; SeDur.Value := 8;
  AddLabel(gb, 240, 82, 'fps');
  SeFps := TSpinEdit.Create(Self);
  SeFps.Parent := gb;
  SeFps.SetBounds(270, 78, 60, 26);
  SeFps.MinValue := 1; SeFps.MaxValue := 25; SeFps.Value := 10;
  AddLabel(gb, 12, 116, 'Time-lapse: จำนวนเฟรม');
  SeFrames := TSpinEdit.Create(Self);
  SeFrames.Parent := gb;
  SeFrames.SetBounds(150, 112, 70, 26);
  SeFrames.MinValue := 5; SeFrames.MaxValue := 300; SeFrames.Value := 60;
  BtnGif := TButton.Create(Self);
  BtnGif.Parent := gb;
  BtnGif.SetBounds(12, 150, 200, 32);
  BtnGif.Caption := 'Export GIF...';
  BtnGif.OnClick := @BtnGifClick;
  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := gb;
  BtnCancel.SetBounds(222, 150, 120, 32);
  BtnCancel.Caption := 'หยุด / ยกเลิก';
  BtnCancel.Enabled := False;
  BtnCancel.OnClick := @BtnCancelClick;
  PBar := TProgressBar.Create(Self);
  PBar.Parent := gb;
  PBar.SetBounds(352, 156, 190, 20);
  LblStatus := AddLabel(AParent, 14, 460, 'พร้อม');
  LblStatus.Font.Style := [fsBold];
  AddLabel(AParent, 14, 486,
    'Live GIF จะเริ่มบันทึกทันทีหลังเลือกไฟล์ – กด Start ที่หน้าต่างหลักให้เครื่องเดินเพื่อให้ภาพเคลื่อนไหว').Font.Color := clGray;

  DlgPng := TSaveDialog.Create(Self);
  DlgPng.Filter := 'PNG image (*.png)|*.png';
  DlgPng.DefaultExt := 'png';
  DlgPng.Options := DlgPng.Options + [ofOverwritePrompt];
  DlgGif := TSaveDialog.Create(Self);
  DlgGif.Filter := 'GIF animation (*.gif)|*.gif';
  DlgGif.DefaultExt := 'gif';
  DlgGif.Options := DlgGif.Options + [ofOverwritePrompt];

  Timer := TTimer.Create(Self);
  Timer.Enabled := False;
  Timer.OnTimer := @TimerTick;
  RgModeClick(nil);
end;

destructor TExportPanel.Destroy;
begin
  Timer.Enabled := False;
  FGif.Free;
  inherited Destroy;
end;

function TExportPanel.AddLabel(AParent: TWinControl; X, Y: Integer; const S: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := S;
end;

procedure TExportPanel.SetViews(const Names: array of string; ARender: TViewRenderEvent;
  ASize: TViewSizeEvent);
var
  i: Integer;
begin
  FRender := ARender;
  FSize := ASize;
  CbView.Items.Clear;
  for i := 0 to High(Names) do
    CbView.Items.Add(Names[i]);
  CbView.Items.Add('Developer window (หน้านี้)');
  CbView.ItemIndex := 0;
end;

function TExportPanel.IsDevView: Boolean;
begin
  Result := CbView.ItemIndex = CbView.Items.Count - 1;
end;

function TExportPanel.RenderFrame: TBGRABitmap;
var
  sz: TPoint;
  bm: TBitmap;
begin
  if IsDevView or not Assigned(FRender) then
  begin
    bm := FForm.GetFormImage;
    try
      Result := TBGRABitmap.Create(bm);
    finally
      bm.Free;
    end;
    Exit;
  end;
  case CbSize.ItemIndex of
    1: sz := Point(960, 540);
    2: sz := Point(1280, 720);
    3: sz := Point(1600, 900);
    4: sz := Point(1920, 1080);
  else
    if Assigned(FSize) then sz := FSize(CbView.ItemIndex) else sz := Point(1280, 720);
  end;
  // window not shown yet / too small -> use a standard size
  if (sz.X < 300) or (sz.Y < 200) then sz := Point(1280, 720);
  Result := TBGRABitmap.Create(sz.X, sz.Y);
  FRender(CbView.ItemIndex, Result);
end;

procedure TExportPanel.AddGifFrame(bmp: TBGRABitmap; DelayMs: Integer);
begin
  if FGif = nil then
  begin
    FGif := TBGRAAnimatedGif.Create;
    FGif.SetSize(bmp.Width, bmp.Height);
    FGif.LoopCount := 0;   // loop forever
  end;
  // the GIF takes ownership of the frame
  FGif.AddFullFrame(bmp, DelayMs, True, dmSetExceptTransparent, True);
  Inc(FFrames);
end;

procedure TExportPanel.FinishGif;
begin
  Timer.Enabled := False;
  if (FGif <> nil) and (FFrames > 0) then
  begin
    LblStatus.Caption := 'กำลังบันทึก GIF (' + IntToStr(FFrames) + ' เฟรม)...';
    Application.ProcessMessages;
    Screen.Cursor := crHourGlass;
    try
      FGif.SaveToFile(FGifFile);
    finally
      Screen.Cursor := crDefault;
    end;
    LblStatus.Caption := 'บันทึกแล้ว: ' + FGifFile + '  (' + IntToStr(FFrames) + ' เฟรม, ' +
      IntToStr(FGif.Width) + '×' + IntToStr(FGif.Height) + ')';
  end
  else
    LblStatus.Caption := 'ยกเลิก – ไม่มีเฟรม';
  FreeAndNil(FGif);
  SetBusy(False);
end;

procedure TExportPanel.SetBusy(Busy: Boolean);
begin
  BtnPng.Enabled := not Busy;
  BtnGif.Enabled := not Busy;
  CbView.Enabled := not Busy;
  CbSize.Enabled := not Busy;
  RgMode.Enabled := not Busy;
  BtnCancel.Enabled := Busy;
  if not Busy then PBar.Position := 0;
end;

procedure TExportPanel.RgModeClick(Sender: TObject);
begin
  SeDur.Enabled := RgMode.ItemIndex = 0;
  SeFps.Enabled := RgMode.ItemIndex = 0;
  SeFrames.Enabled := RgMode.ItemIndex = 1;
end;

procedure TExportPanel.BtnPngClick(Sender: TObject);
var
  bmp: TBGRABitmap;
begin
  DlgPng.FileName := 'winder_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.png';
  if not DlgPng.Execute then Exit;
  bmp := RenderFrame;
  try
    bmp.SaveToFile(DlgPng.FileName);
    LblStatus.Caption := 'บันทึกแล้ว: ' + DlgPng.FileName + '  (' + IntToStr(bmp.Width) +
      '×' + IntToStr(bmp.Height) + ')';
  finally
    bmp.Free;
  end;
end;

procedure TExportPanel.ExportPngFile(View: Integer; const FN: string);
var
  bmp: TBGRABitmap;
begin
  CbView.ItemIndex := EnsureRange(View, 0, CbView.Items.Count - 1);
  bmp := RenderFrame;
  try
    bmp.SaveToFile(FN);
  finally
    bmp.Free;
  end;
end;

procedure TExportPanel.ExportTimeLapseFile(View, Frames: Integer; const FN: string);
begin
  CbView.ItemIndex := EnsureRange(View, 0, CbView.Items.Count - 1);
  SeFrames.Value := Frames;
  FGifFile := FN;
  FreeAndNil(FGif);
  FFrames := 0;
  FCancel := False;
  SetBusy(True);
  TimeLapse;
end;

procedure TExportPanel.BtnGifClick(Sender: TObject);
begin
  DlgGif.FileName := 'winder_' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.gif';
  if not DlgGif.Execute then Exit;
  FGifFile := DlgGif.FileName;
  FreeAndNil(FGif);
  FFrames := 0;
  FCancel := False;
  SetBusy(True);
  if RgMode.ItemIndex = 0 then
  begin
    FFramesWanted := SeDur.Value * SeFps.Value;
    PBar.Max := FFramesWanted;
    Timer.Interval := Max(40, 1000 div SeFps.Value);
    LblStatus.Caption := 'กำลังบันทึก Live...';
    Timer.Enabled := True;
  end
  else
    TimeLapse;
end;

procedure TExportPanel.BtnCancelClick(Sender: TObject);
begin
  FCancel := True;
  if Timer.Enabled then FinishGif;  // live: keep what was recorded so far
end;

procedure TExportPanel.TimerTick(Sender: TObject);
begin
  AddGifFrame(RenderFrame, Timer.Interval);
  PBar.Position := FFrames;
  LblStatus.Caption := 'กำลังบันทึก Live... ' + IntToStr(FFrames) + ' / ' +
    IntToStr(FFramesWanted);
  if FFrames >= FFramesWanted then FinishGif;
end;

procedure TExportPanel.TimeLapse;
var
  i, n: Integer;
  L0, Lk: Double;
begin
  if FSim.Finished then
  begin
    LblStatus.Caption := 'ม้วนเสร็จแล้ว – กด Reset ก่อนทำ Time-lapse';
    SetBusy(False);
    Exit;
  end;
  n := SeFrames.Value;
  PBar.Max := n;
  L0 := FSim.WoundLen;
  AddGifFrame(RenderFrame, 100);
  for i := 1 to n do
  begin
    if FCancel then Break;
    Lk := L0 + (FSim.P.LengthM - L0) * i / n;
    while (FSim.WoundLen < Lk - 1e-6) and not FSim.Finished do
      FSim.Step((Lk - FSim.WoundLen) / FSim.U + 1e-6, False);
    FSim.Solve;
    if Assigned(FOnSimAdvanced) then FOnSimAdvanced(Self);
    if i = n then
      AddGifFrame(RenderFrame, 2500)   // hold the last frame
    else
      AddGifFrame(RenderFrame, 100);
    PBar.Position := i;
    LblStatus.Caption := 'Time-lapse ' + IntToStr(i) + ' / ' + IntToStr(n) + '   L = ' +
      FF(FSim.WoundLen, 0) + ' m';
    Application.ProcessMessages;
  end;
  FinishGif;
end;

initialization
  // GIF saving needs a colour quantizer (256-colour palette per frame)
  BGRAColorQuantizerFactory := TBGRAColorQuantizer;

end.
