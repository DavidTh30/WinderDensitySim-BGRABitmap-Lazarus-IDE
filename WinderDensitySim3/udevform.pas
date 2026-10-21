unit uDevForm;

{ Developer window: live variables, formulas, per-layer table, editable
  physics coefficients and CSV export. Built in code (no .lfm). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, ExtCtrls, StdCtrls, ComCtrls,
  Grids, ValEdit, Dialogs, uWinderModel, uExportTab;

type

  { TfrmDev }

  TfrmDev = class(TForm)
  private
    FSim: TWinderSim;
    Pages: TPageControl;
    MemoLive, MemoFormula: TMemo;
    Grid: TStringGrid;
    VLE: TValueListEditor;
    BtnApply, BtnDefaults, BtnExport, BtnRefresh: TButton;
    SaveDlg: TSaveDialog;
    FOnParamsChanged: TNotifyEvent;
    FExport: TExportPanel;
    function NewTab(const ACaption: string): TTabSheet;
    function NewMemo(AParent: TWinControl): TMemo;
    procedure FillFormulas;
    procedure FillLive;
    procedure FillGrid;
    procedure BtnApplyClick(Sender: TObject);
    procedure BtnDefaultsClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure BtnRefreshClick(Sender: TObject);
  public
    constructor CreateDev(AOwner: TComponent; ASim: TWinderSim);
    procedure RefreshData;
    procedure ShowExportTab;
    procedure ShowTab(Index: Integer);
    procedure LoadCoefs;
    property ExportPanel: TExportPanel read FExport;
    property OnParamsChanged: TNotifyEvent read FOnParamsChanged write FOnParamsChanged;
  end;

implementation

const
  KEY_RHO = 'ρ film density [kg/m3]';
  KEY_E = 'E film modulus MD [MPa]';
  KEY_Y = 'Film yield stress [MPa]';
  KEY_RQ = 'Rq combined roughness [um]';
  KEY_COF = 'μ COF film/film [-]';
  KEY_ER = 'E rubber (contact roll) [MPa]';
  KEY_NUR = 'ν rubber Poisson [-]';
  KEY_MU = 'μair air viscosity [Pa.s]';
  KEY_PATM = 'Patm atmospheric [Pa]';
  KEY_KN = 'Kn nip air factor [-]';
  KEY_ALPHA = 'α pressure attenuation [-]';
  KEY_PASP = 'Pasp asperity constant [kPa]';
  KEY_PCMAX = 'Warn: max core pressure [MPa]';
  KEY_SRMAX = 'Warn: max σw/yield [-]';
  KEY_GAP = 'Gap contact/tension roll [mm]';
  KEY_WALL = 'Tension roll shell wall [mm]';
  KEY_KW = 'Kw pre-wrap air share [-]';
  KEY_B0 = 'β0 pre-wrap saturation [deg]';
  KEY_KB = 'Kb air share without nip [-]';
  KEY_CLR = 'Clearance tension roll/roll [mm]';
  KEY_LKF = 'LM force constant Kf [N/A]';
  KEY_LKM = 'LM motor constant Km [N/sqrtW]';
  KEY_LM = 'LM moving mass [kg]';
  KEY_LV = 'LM max speed [m/s]';
  KEY_LA = 'LM acceleration [m/s2]';
  KEY_LF = 'LM rated force [N]';
  KEY_SP = 'Servo screw pitch [mm/rev]';
  KEY_SE = 'Servo screw efficiency [-]';
  KEY_SM = 'Servo moving mass [kg]';
  KEY_SV = 'Servo max speed [m/s]';
  KEY_SA = 'Servo acceleration [m/s2]';
  KEY_ST = 'Servo rated torque [N.m]';
  KEY_GM = 'Linear guide friction μg [-]';
  KEY_CW = 'Contact roll steel wall [mm]';
  KEY_RT = 'Contact roll rubber thickness [mm]';
  KEY_CR = 'Contact roll crown (dia) [mm]';
  KEY_BX = 'Bearing span - web width [mm]';

{ TfrmDev }

constructor TfrmDev.CreateDev(AOwner: TComponent; ASim: TWinderSim);
var
  ts: TTabSheet;
  pnl: TPanel;
begin
  inherited CreateNew(AOwner, 1);
  FSim := ASim;
  Caption := 'Winder Density Simulator 3 – Developer data';
  Width := 900;
  Height := 760;
  Position := poDefaultPosOnly;

  pnl := TPanel.Create(Self);
  pnl.Parent := Self;
  pnl.Align := alBottom;
  pnl.Height := 40;
  pnl.BevelOuter := bvNone;

  BtnRefresh := TButton.Create(Self);
  BtnRefresh.Parent := pnl;
  BtnRefresh.SetBounds(8, 6, 120, 28);
  BtnRefresh.Caption := 'Refresh';
  BtnRefresh.OnClick := @BtnRefreshClick;

  BtnExport := TButton.Create(Self);
  BtnExport.Parent := pnl;
  BtnExport.SetBounds(136, 6, 200, 28);
  BtnExport.Caption := 'Export layers CSV...';
  BtnExport.OnClick := @BtnExportClick;

  SaveDlg := TSaveDialog.Create(Self);
  SaveDlg.Filter := 'CSV (*.csv)|*.csv';
  SaveDlg.DefaultExt := 'csv';
  SaveDlg.FileName := 'winder_layers.csv';

  Pages := TPageControl.Create(Self);
  Pages.Parent := Self;
  Pages.Align := alClient;
  Pages.OnChange := @BtnRefreshClick;

  ts := NewTab('Live data');
  MemoLive := NewMemo(ts);

  ts := NewTab('Formulas (สูตรคำนวณ)');
  MemoFormula := NewMemo(ts);

  ts := NewTab('Layer table');
  Grid := TStringGrid.Create(Self);
  Grid.Parent := ts;
  Grid.Align := alClient;
  Grid.FixedCols := 0;
  Grid.ColCount := 13;
  Grid.RowCount := 2;
  Grid.DefaultColWidth := 66;
  Grid.Options := Grid.Options + [goColSizing] - [goRangeSelect];
  Grid.Font.Name := 'Consolas';
  Grid.Font.Size := 9;

  ts := NewTab('Coefficients');
  pnl := TPanel.Create(Self);
  pnl.Parent := ts;
  pnl.Align := alBottom;
  pnl.Height := 40;
  pnl.BevelOuter := bvNone;
  BtnApply := TButton.Create(Self);
  BtnApply.Parent := pnl;
  BtnApply.SetBounds(8, 6, 220, 28);
  BtnApply.Caption := 'Apply (รีเซ็ตม้วน)';
  BtnApply.OnClick := @BtnApplyClick;
  BtnDefaults := TButton.Create(Self);
  BtnDefaults.Parent := pnl;
  BtnDefaults.SetBounds(236, 6, 220, 28);
  BtnDefaults.Caption := 'Load defaults';
  BtnDefaults.OnClick := @BtnDefaultsClick;
  VLE := TValueListEditor.Create(Self);
  VLE.Parent := ts;
  VLE.Align := alClient;
  VLE.TitleCaptions.Clear;
  VLE.TitleCaptions.Add('Coefficient');
  VLE.TitleCaptions.Add('Value');
  VLE.ColWidths[0] := 320;

  ts := NewTab('Export PNG / GIF');
  FExport := TExportPanel.CreatePanel(Self, ts, Self, FSim);

  FillFormulas;
  LoadCoefs;
end;

function TfrmDev.NewTab(const ACaption: string): TTabSheet;
begin
  Result := Pages.AddTabSheet;
  Result.Caption := ACaption;
end;

function TfrmDev.NewMemo(AParent: TWinControl): TMemo;
begin
  Result := TMemo.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.ScrollBars := ssBoth;
  Result.WordWrap := False;
  Result.Font.Name := 'Consolas';
  Result.Font.Size := 10;
end;

procedure TfrmDev.LoadCoefs;
begin
  VLE.Strings.Clear;
  with FSim.P do
  begin
    VLE.Strings.Add(KEY_RHO + '=' + FF(RhoFilm, 1));
    VLE.Strings.Add(KEY_E + '=' + FF(EFilmMPa, 0));
    VLE.Strings.Add(KEY_Y + '=' + FF(YieldMPa, 1));
    VLE.Strings.Add(KEY_RQ + '=' + FF(RqUm, 4));
    VLE.Strings.Add(KEY_COF + '=' + FF(COF, 3));
    VLE.Strings.Add(KEY_ER + '=' + FF(RubberEMPa, 2));
    VLE.Strings.Add(KEY_NUR + '=' + FF(RubberNu, 3));
    VLE.Strings.Add(KEY_MU + '=' + FloatToStrF(AirVisc, ffExponent, 4, 2, FSDot));
    VLE.Strings.Add(KEY_PATM + '=' + FF(Patm, 0));
    VLE.Strings.Add(KEY_KN + '=' + FF(NipAirFactor, 3));
    VLE.Strings.Add(KEY_ALPHA + '=' + FF(PressAtten, 3));
    VLE.Strings.Add(KEY_PASP + '=' + FF(AspPressKPa, 1));
    VLE.Strings.Add(KEY_PCMAX + '=' + FF(MaxCorePressMPa, 2));
    VLE.Strings.Add(KEY_SRMAX + '=' + FF(MaxStressRatio, 3));
    VLE.Strings.Add(KEY_GAP + '=' + FF(RollGapMm, 1));
    VLE.Strings.Add(KEY_WALL + '=' + FF(TRollWallMm, 1));
    VLE.Strings.Add(KEY_KW + '=' + FF(PreWrapAir, 4));
    VLE.Strings.Add(KEY_B0 + '=' + FF(PreWrapBeta0Deg, 1));
    VLE.Strings.Add(KEY_KB + '=' + FF(NoNipAir, 4));
    VLE.Strings.Add(KEY_CLR + '=' + FF(ClearMm, 1));
    VLE.Strings.Add(KEY_LKF + '=' + FF(LinKf, 1));
    VLE.Strings.Add(KEY_LKM + '=' + FF(LinKm, 1));
    VLE.Strings.Add(KEY_LM + '=' + FF(LinMassKg, 1));
    VLE.Strings.Add(KEY_LV + '=' + FF(LinVmax, 3));
    VLE.Strings.Add(KEY_LA + '=' + FF(LinAcc, 3));
    VLE.Strings.Add(KEY_LF + '=' + FF(LinFmaxN, 0));
    VLE.Strings.Add(KEY_SP + '=' + FF(ScrewLeadMm, 1));
    VLE.Strings.Add(KEY_SE + '=' + FF(ScrewEta, 3));
    VLE.Strings.Add(KEY_SM + '=' + FF(ServoMassKg, 1));
    VLE.Strings.Add(KEY_SV + '=' + FF(ServoVmax, 3));
    VLE.Strings.Add(KEY_SA + '=' + FF(ServoAcc, 3));
    VLE.Strings.Add(KEY_ST + '=' + FF(ServoRatedNm, 2));
    VLE.Strings.Add(KEY_GM + '=' + FF(GuideMu, 3));
    VLE.Strings.Add(KEY_CW + '=' + FF(CRollWallMm, 1));
    VLE.Strings.Add(KEY_RT + '=' + FF(RubberThkMm, 1));
    VLE.Strings.Add(KEY_CR + '=' + FF(CrownMm, 3));
    VLE.Strings.Add(KEY_BX + '=' + FF(BearingExtraMm, 0));
  end;
end;

procedure TfrmDev.BtnApplyClick(Sender: TObject);

  function V(const Key: string; Def: Double): Double;
  begin
    Result := StrToFloatDef(Trim(VLE.Values[Key]), Def, FSDot);
  end;

begin
  with FSim.P do
  begin
    RhoFilm := Max(100, V(KEY_RHO, RhoFilm));
    EFilmMPa := Max(1, V(KEY_E, EFilmMPa));
    YieldMPa := Max(1, V(KEY_Y, YieldMPa));
    RqUm := Max(0, V(KEY_RQ, RqUm));
    COF := Max(0, V(KEY_COF, COF));
    RubberEMPa := Max(0.1, V(KEY_ER, RubberEMPa));
    RubberNu := EnsureRange(V(KEY_NUR, RubberNu), 0, 0.499);
    AirVisc := Max(1e-7, V(KEY_MU, AirVisc));
    Patm := Max(1000, V(KEY_PATM, Patm));
    NipAirFactor := Max(0, V(KEY_KN, NipAirFactor));
    PressAtten := Max(0, V(KEY_ALPHA, PressAtten));
    AspPressKPa := Max(1, V(KEY_PASP, AspPressKPa));
    MaxCorePressMPa := Max(0.01, V(KEY_PCMAX, MaxCorePressMPa));
    MaxStressRatio := Max(0.01, V(KEY_SRMAX, MaxStressRatio));
    RollGapMm := Max(5, V(KEY_GAP, RollGapMm));
    TRollWallMm := Max(1, V(KEY_WALL, TRollWallMm));
    PreWrapAir := Max(0, V(KEY_KW, PreWrapAir));
    PreWrapBeta0Deg := Max(0.1, V(KEY_B0, PreWrapBeta0Deg));
    NoNipAir := Max(0, V(KEY_KB, NoNipAir));
    ClearMm := Max(0, V(KEY_CLR, ClearMm));
    LinKf := Max(1, V(KEY_LKF, LinKf));
    LinKm := Max(1, V(KEY_LKM, LinKm));
    LinMassKg := Max(1, V(KEY_LM, LinMassKg));
    LinVmax := Max(0.001, V(KEY_LV, LinVmax));
    LinAcc := Max(0.001, V(KEY_LA, LinAcc));
    LinFmaxN := Max(1, V(KEY_LF, LinFmaxN));
    ScrewLeadMm := Max(0.5, V(KEY_SP, ScrewLeadMm));
    ScrewEta := EnsureRange(V(KEY_SE, ScrewEta), 0.1, 1);
    ServoMassKg := Max(1, V(KEY_SM, ServoMassKg));
    ServoVmax := Max(0.001, V(KEY_SV, ServoVmax));
    ServoAcc := Max(0.001, V(KEY_SA, ServoAcc));
    ServoRatedNm := Max(0.01, V(KEY_ST, ServoRatedNm));
    GuideMu := Max(0, V(KEY_GM, GuideMu));
    CRollWallMm := Max(2, V(KEY_CW, CRollWallMm));
    RubberThkMm := Max(1, V(KEY_RT, RubberThkMm));
    CrownMm := Max(0, V(KEY_CR, CrownMm));
    BearingExtraMm := Max(0, V(KEY_BX, BearingExtraMm));
  end;
  LoadCoefs;
  if Assigned(FOnParamsChanged) then FOnParamsChanged(Self);
  RefreshData;
end;

procedure TfrmDev.BtnDefaultsClick(Sender: TObject);
var
  keep: TWinderParams;
begin
  // restore only the coefficients, keep the slider (process) values
  keep := FSim.P;
  FSim.SetDefaults;
  with FSim.P do
  begin
    ThickUm := keep.ThickUm;
    WidthMm := keep.WidthMm;
    LengthM := keep.LengthM;
    CoreDiaMm := keep.CoreDiaMm;
    ContactDiaMm := keep.ContactDiaMm;
    SpeedMpm := keep.SpeedMpm;
    TensionNm := keep.TensionNm;
    TaperPct := keep.TaperPct;
    NipNm := keep.NipNm;
    NipTaperPct := keep.NipTaperPct;
    ContactMode := keep.ContactMode;
    RetractMm := keep.RetractMm;
    LeadCmdMm := keep.LeadCmdMm;
  end;
  LoadCoefs;
  if Assigned(FOnParamsChanged) then FOnParamsChanged(Self);
  RefreshData;
end;

procedure TfrmDev.BtnRefreshClick(Sender: TObject);
begin
  RefreshData;
end;

procedure TfrmDev.BtnExportClick(Sender: TObject);
var
  SL: TStringList;
  i: Integer;
begin
  if not SaveDlg.Execute then Exit;
  SL := TStringList.Create;
  try
    SL.Add('layer,R_wound_mm,R_comp_mm,L_cum_m,Tw_N_m,Nip_N_m,WIT_N_m,P_kPa,' +
      'h_air0_um,gap_um,k,rho_g_cm3');
    for i := 0 to FSim.Count - 1 do
      with FSim.Layers[i] do
        SL.Add(Format('%d,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s',
          [i + 1, FF(R * 1000, 4), FF(Rc * 1000, 4), FF(LCum, 2), FF(Tw, 2),
          FF(Nip, 2), FF(WIT, 2), FF(P * 1e-3, 3), FF(HAir * 1e6, 4),
          FF(Gap * 1e6, 4), FF(K, 6), FF(K * FSim.P.RhoFilm / 1000, 5)]));
    SL.SaveToFile(SaveDlg.FileName);
  finally
    SL.Free;
  end;
end;

procedure TfrmDev.ShowTab(Index: Integer);
begin
  Show;
  Pages.ActivePageIndex := EnsureRange(Index, 0, Pages.PageCount - 1);
  RefreshData;
end;

procedure TfrmDev.ShowExportTab;
begin
  Show;
  Pages.ActivePageIndex := Pages.PageCount - 1;
end;

procedure TfrmDev.RefreshData;
begin
  if not Visible then Exit;
  FillLive;
  if Pages.ActivePageIndex = 2 then FillGrid;
end;

procedure TfrmDev.FillLive;
var
  S, Wn: TStringList;
  air: TAirInfo;
  nip: TNipInfo;
  g: TGeo;
  cd: TCDProfile;
  Rw, Tw, Nn, vol: Double;
  sPath: string;
  i: Integer;

  procedure Add(const Name, Sym, Val, Un: string);
  begin
    S.Add(Format('  %-34s %-10s = %14s  %s', [Name, Sym, Val, Un]));
  end;

begin
  Rw := FSim.RWound;
  Tw := FSim.TensionAt(Rw);
  Nn := FSim.NipAt(Rw);
  air := FSim.AirAt(Rw, Tw, Nn);
  nip := FSim.NipCalc(Rw, Nn);
  g := FSim.Geo(FSim.ROuterComp);
  case g.PathType of
    1: sPath := '1 T -> contact roll wrap -> nip';
    2: sPath := '2 T -> winder pre-wrap -> nip';
    3: sPath := '3 T -> winder (no nip)';
  else
    sPath := '4 T -> contact roll -> winder (no nip)';
  end;
  S := TStringList.Create;
  Wn := TStringList.Create;
  try
    S.Add('=== INPUT : FILM (BOPA / Nylon 6) ===');
    Add('Thickness', 't', FF(FSim.P.ThickUm, 2), 'um');
    Add('Width', 'W', FF(FSim.P.WidthMm, 0), 'mm');
    Add('Target length', 'L', FF(FSim.P.LengthM, 0), 'm');
    Add('Film density', 'ρf', FF(FSim.P.RhoFilm, 1), 'kg/m3');
    Add('Modulus MD', 'E', FF(FSim.P.EFilmMPa, 0), 'MPa');
    Add('Yield stress', 'σy', FF(FSim.P.YieldMPa, 1), 'MPa');
    Add('Roughness combined', 'Rq', FF(FSim.P.RqUm, 4), 'um');
    Add('COF film/film', 'μ', FF(FSim.P.COF, 3), '-');
    S.Add('');
    S.Add('=== INPUT : MACHINE ===');
    Add('Mill roll (core) dia', 'D0', FF(FSim.P.CoreDiaMm, 0), 'mm');
    Add('Contact roll dia', 'Dc', FF(FSim.P.ContactDiaMm, 0), 'mm');
    Add('Tension roll dia (= Dc)', 'Dt', FF(FSim.P.ContactDiaMm, 0), 'mm');
    Add('Gap contact/tension roll', 'g', FF(FSim.P.RollGapMm, 1), 'mm');
    Add('Rubber modulus / Poisson', 'Er / ν', FF(FSim.P.RubberEMPa, 2) + ' / ' +
      FF(FSim.P.RubberNu, 3), 'MPa / -');
    Add('Line speed', 'V', FF(FSim.P.SpeedMpm, 0), 'm/min');
    Add('Tension at core', 'Tw0', FF(FSim.P.TensionNm, 1), 'N/m');
    Add('Tension taper', 'kT', FF(FSim.P.TaperPct, 1), '%');
    Add('Nip load at core', 'N0', FF(FSim.P.NipNm, 1), 'N/m');
    Add('Nip taper', 'kN', FF(FSim.P.NipTaperPct, 1), '%');
    Add('Nip air factor', 'Kn', FF(FSim.P.NipAirFactor, 3), '-');
    Add('Pressure attenuation', 'α', FF(FSim.P.PressAtten, 3), '-');
    Add('Asperity pressure const', 'Pasp', FF(FSim.P.AspPressKPa, 1), 'kPa');
    S.Add('');
    S.Add('=== STATE ===');
    Add('Process time', 't_sim', HMS(FSim.SimTime), 'h:m:s');
    Add('Remaining time', 't_rem', HMS(FSim.TimeRemain), 'h:m:s');
    Add('Total winding time', 't_tot', HMS(FSim.TimeTotal), 'h:m:s');
    Add('Wound length', 'Lw', FF(FSim.WoundLen, 1), 'm');
    Add('Progress', '', FF(FSim.WoundLen / FSim.P.LengthM * 100, 2), '%');
    Add('Layers (wraps)', 'n', IntToStr(FSim.Count), '');
    Add('As-wound outer radius', 'Rw', FF(Rw * 1000, 3), 'mm');
    Add('Compressed outer dia', 'D', FF(FSim.CurDia * 1000, 2), 'mm');
    Add('Ideal dia (k=1)', 'Did', FF(FSim.IdealDia(FSim.WoundLen) * 1000, 2), 'mm');
    Add('Predicted full-roll dia', 'Dend', FF(FSim.PredictDia(FSim.P.LengthM,
      IfThen(FSim.Count > 0, FSim.KAvg, 1)) * 1000, 1), 'mm');
    S.Add('');
    S.Add('=== KINEMATICS / DRIVE ===');
    Add('Surface speed', 'U', FF(FSim.U, 4), 'm/s');
    Add('Winding roll speed', 'n_r', FF(FSim.RollRpm, 2), 'rpm');
    Add('Winding roll angular speed', 'ω_r', FF(FSim.U / FSim.ROuterComp, 3), 'rad/s');
    Add('Contact roll speed', 'n_c', FF(FSim.ContactRpm, 2), 'rpm');
    Add('Total web tension', 'F', FF(Tw * FSim.W, 1), 'N');
    Add('Centre drive torque', 'M', FF(FSim.TorqueNm, 2), 'N.m');
    Add('Tension power', 'Pw', FF(FSim.PowerW / 1000, 3), 'kW');
    S.Add('');
    S.Add('=== TENSION / STRESS (current layer) ===');
    Add('Web tension (tapered)', 'Tw', FF(Tw, 2), 'N/m');
    Add('Nip load (tapered)', 'N', FF(Nn, 2), 'N/m');
    Add('Wound-in-tension', 'WIT', FF(Tw + FSim.P.COF * Nn, 2), 'N/m');
    Add('Winding stress', 'σw', FF(FSim.WindStressMPa, 3), 'MPa');
    Add('Stress / yield', 'σw/σy', FF(FSim.WindStressMPa / FSim.P.YieldMPa * 100, 2), '%');
    Add('Web strain', 'ε', FF(FSim.WindStressMPa / FSim.P.EFilmMPa * 100, 4), '%');
    S.Add('');
    S.Add('=== WEB PATH GEOMETRY (origin = winder centre, y down) ===');
    Add('Path type', '', sPath, '');
    Add('Contact roll centre x', 'Cx', FF(g.Cx * 1000, 1), 'mm');
    Add('Tension roll centre x / y', 'Tx/Ty', FF(g.Tx * 1000, 1) + ' / ' +
      FF(g.Ty * 1000, 1), 'mm');
    Add('Tension lead command', 'lead_cmd', FF(FSim.P.LeadCmdMm, 1), 'mm');
    Add('Tension lead actual', 'lead', FF(g.Lead * 1000, 2), 'mm');
    Add('Max lead (collision guard)', 'lead_max', FF(Min(9999, g.LeadMax * 1000), 1), 'mm');
    Add('Lead limited', '', BoolToStr(g.Limited, 'YES', 'no'), '');
    Add('Web angle from vertical', 'φ', FF(g.FilmAngle * 180 / Pi, 2), 'deg');
    Add('Wrap on tension roll', 'θT', FF(g.ThetaT * 180 / Pi, 2), 'deg');
    Add('Wrap on contact roll', 'βC', FF(g.BetaC * 180 / Pi, 2), 'deg');
    Add('Pre-wrap on winder', 'βW', FF(g.BetaW * 180 / Pi, 2), 'deg');
    Add('Pre-wrap arc length', 'sW', FF(g.BetaW * FSim.ROuterComp * 1000, 1), 'mm');
    Add('Free span length', 'Ls', FF(g.SpanLen * 1000, 1), 'mm');
    Add('Span time constant', 'τ', FF(g.SpanLen / FSim.U * 1000, 1), 'ms');
    S.Add('');
    S.Add('=== TENSION ROLL / LOAD CELL ===');
    Add('Tension roll speed', 'n_t', FF(FSim.TRollRpm, 2), 'rpm');
    Add('Load cell resultant force', 'F_LC', FF(FSim.LoadCellN, 1), 'N');
    Add('Load cell per side (2 cells)', 'F_LC/2', FF(FSim.LoadCellN / 2, 1), 'N');
    Add('Horizontal web force on roll', 'Fx', FF(FSim.TRollFx, 1), 'N');
    Add('Tension roll shell mass', 'm_t', FF(FSim.TRollMassKg, 1), 'kg');
    Add('Tension roll inertia', 'J_t', FF(FSim.TRollInertia, 4), 'kg.m2');
    Add('Web strain in span', 'ε', FF(FSim.SpanStrain * 100, 4), '%');
    S.Add('');
    S.Add('=== TENSION ROLL SERVO (ball screw) ===');
    Add('Axis velocity (own move)', 'v_s', FF(FSim.LeadVel * 1000, 2), 'mm/s');
    Add('Follow speed (roll growth)', 'v_f', FF(FSim.FollowSpeed * 60000, 3), 'mm/min');
    Add('Axial load', 'F_ax', FF(FSim.ServoAxialN, 1), 'N');
    Add('Motor torque', 'T_s', FF(FSim.ServoTorqueNm, 3), 'N.m');
    Add('Torque / rated', '', FF(FSim.ServoTorqueNm / FSim.P.ServoRatedNm * 100, 1), '%');
    Add('Motor speed', 'n_s', FF(FSim.ServoRpm, 2), 'rpm');
    S.Add('');
    S.Add('=== CONTACT ROLL LINEAR MOTOR ===');
    if FSim.P.ContactMode = CM_PRESS then
      Add('Mode', '', 'PRESS (force control)', '')
    else
      Add('Mode', '', 'RETRACT (position control)', '');
    Add('Gap to roll surface', 'gap', FF(FSim.GapAct * 1000, 2), 'mm');
    Add('Axis velocity', 'v_lm', FF(FSim.GapVel * 1000, 2), 'mm/s');
    Add('Nip force N·W', 'F_nip', FF(Nn * FSim.W, 1), 'N');
    Add('Web force on contact roll', 'Fx_c', FF(FSim.ContactFilmFx, 1), 'N');
    Add('Motor force', 'F_lm', FF(FSim.LinForceN, 1), 'N');
    Add('Force / rated', '', FF(FSim.LinForceN / FSim.P.LinFmaxN * 100, 1), '%');
    Add('Motor current', 'I', FF(FSim.LinCurrentA, 3), 'A');
    Add('Copper loss', 'P_cu', FF(FSim.LinCopperW, 1), 'W');
    Add('Stroke from core position', 's', FF((FSim.ROuterComp - FSim.R0) * 1000 +
      FSim.GapAct * 1000, 1), 'mm');
    S.Add('');    cd := FSim.CDProfile(41);
    S.Add('=== CROSS-MACHINE (WIDTH) NIP PROFILE ===');
    Add('Bearing span', 'Lb', FF(cd.Span * 1000, 0), 'mm');
    Add('Contact roll bending stiffness', 'EI', FF(cd.EI * 1e-6, 3), 'MN.m2');
    Add('Rubber foundation modulus', 'kf', FF(cd.KFound * 1e-6, 3), 'MN/m2');
    Add('Max deflection', 'δmax', FF(cd.DeflMax, 4), 'mm');
    Add('Crown (diameter)', 'C', FF(FSim.P.CrownMm, 3), 'mm');
    Add('Nip min / avg / max', 'N', FF(cd.NMin, 0) + ' / ' + FF(cd.NAvg, 0) + ' / ' +
      FF(cd.NMax, 0), 'N/m');
    if cd.NAvg > 0 then
      Add('Nip uniformity min/avg', '', FF(cd.NMin / cd.NAvg * 100, 1), '%');
    S.Add('');
    S.Add('=== NIP (Hertz line contact) ===');
    Add('Equivalent radius', 'Req', FF(nip.REq * 1000, 2), 'mm');
    Add('Contact modulus', 'E*', FF(nip.EStar * 1e-6, 3), 'MPa');
    Add('Nip width', '2b', FF(nip.HalfB * 2000, 3), 'mm');
    Add('Peak nip pressure', 'Pmax', FF(nip.PMax * 1e-3, 1), 'kPa');
    Add('Mean nip pressure', 'Pmean', FF(nip.PMean * 1e-3, 1), 'kPa');
    S.Add('');
    S.Add('=== AIR ENTRAINMENT ===');
    Add('Effective tension', 'Teff', FF(air.TEff, 1), 'N/m');
    Add('Knox-Sweeney air film', 'h0', FF(air.HFoil * 1e6, 4), 'um');
    Add('Air film tension only (KS)', 'hT', FF(air.HTension * 1e6, 4), 'um');
    Add('Air under nip Kn·h0', 'hb', FF(air.HBase * 1e6, 4), 'um');
    Add('Extra air from pre-wrap', 'hp', FF(air.HPre * 1e6, 4), 'um');
    Add('Effective entering air', 'he', FF(air.HNip * 1e6, 4), 'um');
    Add('Bleed limit 3Rq', 'hc', FF(air.HCrit * 1e6, 4), 'um');
    Add('Trapped air per layer', 'ha', FF(air.HTrapped * 1e6, 4), 'um');
    Add('Asperity gap (uncompressed)', 'gr0', FF(FSim.GapRough0 * 1e6, 4), 'um');
    S.Add('');
    S.Add('=== ROLL DENSITY RESULT ===');
    Add('Average packing ratio', 'k_avg', FF(FSim.KAvg, 5), '-');
    Add('Average roll density', 'ρ_avg', FF(FSim.RhoAvg / 1000, 5), 'g/cm3');
    Add('Air volume in roll', 'φair', FF((1 - FSim.KAvg) * 100, 3), '%');
    Add('Min local packing', 'k_min', FF(FSim.KMin, 5), '-');
    Add('Outer layers packing', 'k_out', FF(FSim.KOuter, 5), '-');
    Add('Core pressure', 'P_core', FF(FSim.PCore * 1e-3, 2), 'kPa');
    Add('Film mass wound', 'm', FF(FSim.FilmMassKg(FSim.WoundLen), 2), 'kg');
    Add('Film mass full roll', 'm_end', FF(FSim.FilmMassKg(FSim.P.LengthM), 2), 'kg');
    if FSim.Count > 0 then
    begin
      vol := Pi * (Sqr(FSim.ROuterComp) - Sqr(FSim.R0)) * FSim.W;
      Add('Roll film-zone volume', 'Vr', FF(vol, 5), 'm3');
    end;
    S.Add('');
    S.Add('=== WARNINGS ===');
    FSim.GetWarnings(Wn);
    for i := 0 to Wn.Count - 1 do
      S.Add('  ' + Wn[i]);
    // update in place so the memo keeps its scroll position
    if MemoLive.Lines.Count <> S.Count then
      MemoLive.Lines.Assign(S)
    else
      for i := 0 to S.Count - 1 do
        if MemoLive.Lines[i] <> S[i] then MemoLive.Lines[i] := S[i];
  finally
    S.Free;
    Wn.Free;
  end;
end;

procedure TfrmDev.FillGrid;
const
  Hdr: array[0..12] of string = ('#', 'Layer', 'R wound mm', 'R comp mm', 'L cum m',
    'Tw N/m', 'Nip N/m', 'WIT N/m', 'P kPa', 'h_air0 um', 'gap um', 'k', 'ρ g/cm3');
var
  stp, rows, row, i, c: Integer;
begin
  stp := Max(1, FSim.Count div 300);
  rows := (FSim.Count + stp - 1) div stp;
  Grid.BeginUpdate;
  try
    Grid.RowCount := Max(2, rows + 1);
    for c := 0 to 12 do Grid.Cells[c, 0] := Hdr[c];
    if rows = 0 then
      for c := 0 to 12 do Grid.Cells[c, 1] := '';
    row := 1;
    i := 0;
    while i < FSim.Count do
    begin
      with FSim.Layers[i] do
      begin
        Grid.Cells[0, row] := IntToStr(row);
        Grid.Cells[1, row] := IntToStr(i + 1);
        Grid.Cells[2, row] := FF(R * 1000, 3);
        Grid.Cells[3, row] := FF(Rc * 1000, 3);
        Grid.Cells[4, row] := FF(LCum, 1);
        Grid.Cells[5, row] := FF(Tw, 2);
        Grid.Cells[6, row] := FF(Nip, 1);
        Grid.Cells[7, row] := FF(WIT, 2);
        Grid.Cells[8, row] := FF(P * 1e-3, 2);
        Grid.Cells[9, row] := FF(HAir * 1e6, 4);
        Grid.Cells[10, row] := FF(Gap * 1e6, 4);
        Grid.Cells[11, row] := FF(K, 5);
        Grid.Cells[12, row] := FF(K * FSim.P.RhoFilm / 1000, 4);
      end;
      Inc(row);
      Inc(i, stp);
    end;
  finally
    Grid.EndUpdate;
  end;
end;

procedure TfrmDev.FillFormulas;
var
  M: TStrings;
begin
  M := MemoFormula.Lines;
  M.BeginUpdate;
  try
    M.Clear;
    M.Add('WINDER DENSITY SIMULATOR 3 — MODEL & FORMULAS');
    M.Add('All internal units are SI (m, N, Pa, s, kg). Tension/nip are per metre of width (N/m).');
    M.Add('');
    M.Add('0. GEOMETRY / ASSUMPTIONS');
    M.Add('   Mill roll = winding core/spool, D0 = 450 mm (default), on the RIGHT, fixed.');
    M.Add('   Contact roll Dc on the LEFT, centre on the same horizontal line as the winder.');
    M.Add('   Tension roll Dt = Dc directly BELOW the contact roll (gap g between surfaces).');
    M.Add('   Contact roll: LINEAR MOTOR axis, forward = press (force control, sets N),');
    M.Add('                 backward = retract by a set distance (position control).');
    M.Add('   Tension roll: SERVO ball-screw axis, position = lead relative to contact roll');
    M.Add('                 (+ = ahead toward the winder). It follows the contact roll.');
    M.Add('   Web: horizontal infeed under the tension roll -> wrap -> free span ->');
    M.Add('        lead<0 : wraps contact roll, enters nip from the contact roll side');
    M.Add('        lead=0 : vertical span straight into the nip');
    M.Add('        lead>0 : touches the winder before the nip (pre-wrap βW)');
    M.Add('   Nip is always on the winder centre line: x_nip = -R(t).');
    M.Add('   R0 = D0/2 , Rc = Dc/2 , t = film thickness , W = web width');
    M.Add('');
    M.Add('1. KINEMATICS');
    M.Add('   U      = V/60                         [m/s] surface speed');
    M.Add('   n_roll = V / (π·D)                    [rpm] winding roll speed (falls as D grows)');
    M.Add('   n_c    = V / (π·Dc)                   [rpm] contact roll speed (constant)');
    M.Add('   t_tot  = L / U                        [s]   winding time');
    M.Add('');
    M.Add('2. ROLL BUILD-UP');
    M.Add('   Ideal (k = 1):  D(L) = sqrt( D0² + 4·L·t / π )');
    M.Add('   Real  (k < 1):  D(L) = sqrt( D0² + 4·L·t / (π·k_avg) )');
    M.Add('   Per wrap i  :  circumference  C_i = 2π·(R_i + t/2)');
    M.Add('                  R_(i+1) = R_i + t + h_air,i + g_r0      (as-wound)');
    M.Add('   Layers       :  n ≈ (D - D0) / (2·(t + gap))');
    M.Add('');
    M.Add('3. TENSION TAPER (hyperbolic)');
    M.Add('   Tw(R) = Tw0 · [ 1 - kT·(1 - R0/R) ]           kT = taper/100');
    M.Add('   N(R)  = N0  · [ 1 - kN·(1 - R0/R) ]');
    M.Add('   σw    = Tw / t      [Pa]   winding stress;   ε = σw / E');
    M.Add('   F     = Tw · W      [N]    total web tension');
    M.Add('   M     = F · R       [N·m]  centre drive torque;   P = F · U  [W]');
    M.Add('');
    M.Add('4. WOUND-IN-TENSION (Pfeiffer / Good, nip induced tension)');
    M.Add('   WIT = Tw + μ · N                                 [N/m]');
    M.Add('');
    M.Add('5. NIP CONTACT (Hertz line contact, rubber covered contact roll)');
    M.Add('   Req = R·Rc / (R + Rc)');
    M.Add('   E*  = Er / (1 - ν²)        (roll stack >> rubber stiffness)');
    M.Add('   b   = sqrt( 4·N·Req / (π·E*) )        half contact width,  nip width = 2b');
    M.Add('   Pmax = 2N / (π·b) ,  Pmean = N / (2b)');
    M.Add('');
    M.Add('6. AIR ENTRAINMENT');
    M.Add('   Knox-Sweeney foil bearing :  h0 = 0.643 · Req · ( 12·μair·U / Teff )^(2/3)');
    M.Add('   Teff = Tw + N');
    M.Add('   Under nip                 :  hn = Kn · h0          (Kn empirical, default 0.15)');
    M.Add('   Air bleed through roughness (Good criterion):  hc = 3·Rq');
    M.Add('   Trapped air               :  ha = max(0, hn - hc)');
    M.Add('   -> higher speed V  => more air => lower density');
    M.Add('   -> higher nip load N / tension => less air => higher density');
    M.Add('');
    M.Add('7. RADIAL (INTERLAYER) PRESSURE');
    M.Add('   Each outer wrap adds hoop-to-radial pressure WIT/R (membrane / thin ring).');
    M.Add('   P_i = α · Σ_(j>i)  WIT_j / (R_j + t/2)            [Pa]');
    M.Add('   α = attenuation factor accounting for stack compliance & hoop relaxation');
    M.Add('       (simplified Hakiel/Altmann behaviour, default 0.20).');
    M.Add('');
    M.Add('8. GAP COMPRESSION');
    M.Add('   Air (isothermal Boyle) :  h_air(P) = ha · Patm / (Patm + P)');
    M.Add('   Asperities             :  g_r(P)   = g_r0 · exp( -P / Pasp ),   g_r0 = 2·Rq');
    M.Add('   gap_i = h_air(P_i) + g_r(P_i)');
    M.Add('');
    M.Add('9. DENSITY');
    M.Add('   Local packing ratio : k_i  = t / (t + gap_i)');
    M.Add('   Local density       : ρ_i  = k_i · ρf');
    M.Add('   Compressed radius   : Rc_i = sqrt( R0² + Σ_(j<=i) ℓ_j·(t + gap_j) / π )');
    M.Add('                         ℓ_j = film length of wrap j (area conservation)');
    M.Add('   Average packing     : k_avg = L·t / ( π·(Rout² - R0²) )');
    M.Add('   Average density     : ρ_avg = k_avg · ρf = m / V_roll');
    M.Add('   Air volume fraction : φ = 1 - k_avg');
    M.Add('   Film mass           : m = ρf · t · W · L');
    M.Add('');
    M.Add('6b. AIR WITH PRE-WRAP / WITHOUT NIP');
    M.Add('   Web wrapping the winder, tension only (Knox-Sweeney, R = roll radius):');
    M.Add('        hT = 0.643 · R · ( 12·μair·U / Tw )^(2/3)');
    M.Add('   Nip pressing  : he = Kn·h0 + Kw · hT · (1 - exp(-βW/β0))');
    M.Add('   No nip        : he = Kb · hT          (retracted contact roll)');
    M.Add('   ha = max(0, he - 3Rq)   (Kw, β0, Kb empirical)');
    M.Add('');
    M.Add('6c. NIP ACROSS THE WEB WIDTH (contact roll deflection)');
    M.Add('   Steel shell: ro = Dc/2 - h_rubber , ri = ro - wall');
    M.Add('   EI = 210e9 · π/4 · (ro⁴ - ri⁴)');
    M.Add('   Simply supported, span Lb = W + extra, line load q = N:');
    M.Add('        δ(x) = q·x·(Lb³ - 2·Lb·x² + x³) / (24·EI)');
    M.Add('   Crown (radius) c(u) = C/2 · (1 - (2u/W)²) , u from web centre');
    M.Add('   Rubber as elastic foundation: kf = Er · 2b / h_rubber');
    M.Add('   N(u) = N + kf·[(δ̄ - δ(u)) + (c(u) - c̄)] , clipped >= 0, scaled so mean = N');
    M.Add('   Outer layer density across width: k(u) = t / (t + ha(N(u)) + 2Rq)');
    M.Add('');
    M.Add('10a. WEB PATH GEOMETRY (tangent between two rolls)');
    M.Add('   Origin winder centre, y down. Cx = -(R + Rc + gap), Cy = 0');
    M.Add('   Tx = Cx + lead , Ty = 2Rc + g');
    M.Add('   Collision guard: |T| >= R + Rt + clr  ->  lead_max = -sqrt((R+Rt+clr)² - Ty²) - Cx');
    M.Add('   Tangent roll1 -> roll2, side s = +1 (centre left of web) / -1 (right):');
    M.Add('        D = P2 - P1 , h = r1·s1 - r2·s2');
    M.Add('        angle(d) = atan2(Dy,Dx) - asin(h/|D|) , n = (-dy, dx)');
    M.Add('        Q1 = P1 + r1·s1·n , Q2 = P2 + r2·s2·n');
    M.Add('   φ  = atan2(dx, -dy)          web angle from vertical');
    M.Add('   θT = π/2 - angle(Q1 - T)     wrap on tension roll');
    M.Add('   βC = angle(Q2 - C)           wrap on contact roll (lead < 0)');
    M.Add('   βW = π - angle(Q2)           pre-wrap on winder (lead > 0)');
    M.Add('');
    M.Add('10b. TENSION ROLL / LOAD CELL');
    M.Add('   F_LC = Tw·W·| (-1,0) + d |  = 2·Tw·W·sin(θT/2)');
    M.Add('   Fx   = Tw·W·(dx - 1)        horizontal load on the servo axis');
    M.Add('   m_t  = 7850·π·(Ro² - Ri²)·(W + 0.2) ,  J_t = m_t·(Ro² + Ri²)/2');
    M.Add('');
    M.Add('10c. SERVO BALL SCREW');
    M.Add('   F_ax = |Fx| + μg·m·g (+ m·a while moving)');
    M.Add('   T_s  = F_ax · p / (2π·η)          p = screw pitch');
    M.Add('   n_s  = (v_s + v_f) / p · 60 ,   v_f = dR/dt = t·U / (2π·R·k)');
    M.Add('   Motion: trapezoidal, v = sign(e)·min(vmax, sqrt(2·a·|e|))');
    M.Add('');
    M.Add('10d. CONTACT ROLL LINEAR MOTOR');
    M.Add('   F_nip = N·W');
    M.Add('   Web force on roll: lead<0  Fx_c = -Tw·W·dx');
    M.Add('   F_lm  = F_nip - Fx_c + μg·m·g (+ m·a while moving)');
    M.Add('   I = F_lm / Kf ,   P_cu = (F_lm / Km)²');
    M.Add('');    M.Add('10. WARNING RULES');
    M.Add('   hn > 3Rq                 -> air trapped (soft roll, telescoping)');
    M.Add('   σw > ratio·σy            -> over-tension (stretch, gauge bands, core crush)');
    M.Add('   P_core > limit           -> blocking / core crush, increase taper');
    M.Add('   k_outer < 0.95           -> soft outer layers');
    M.Add('   Tw < 30% Tw0             -> wrinkles');
    M.Add('   Pmax nip > 1 MPa         -> pressure marks');
    M.Add('   no nip                   -> air wound in');
    M.Add('   βW > 0                   -> pre-wrap air');
    M.Add('   lead > lead_max          -> servo limited (collision guard)');
    M.Add('   F_lm > rated, T_s > rated -> motor overload');
    M.Add('');
    M.Add('11. TYPICAL BOPA (Nylon 6) DATA');
    M.Add('   ρf = 1.14–1.16 g/cm³ , E(MD) ≈ 2–4 GPa , σy ≈ 60–100 MPa , μ film/film 0.3–0.6');
    M.Add('   Typical winding stress 4–12 MPa (Tw ≈ 60–180 N/m for 15 µm)');
    M.Add('   Contact roll rubber 60–80 Shore A  ->  Er ≈ 4–9 MPa');
    M.Add('');
    M.Add('NOTE: Kn, α and Pasp are empirical calibration constants. Tune them against');
    M.Add('      measured roll diameter / weight (ρ_avg = m / V) from the real winder.');
  finally
    M.EndUpdate;
  end;
end;

end.
