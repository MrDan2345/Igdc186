unit GameUnit;

{$modeswitch advancedrecords}
{$modeswitch typehelpers}
{$optimization autoinline}

interface

uses
  Math,
  Gen2MP,
  G2Types,
  G2Math,
  G2Utils,
  G2DataManager,
  G2Scene2D,
  Types,
  Classes,
  SysUtils,
  box2d,
  G2PerlinNoise;

type TGridCell = record
  Bounce: Boolean;
  Valid: Boolean;
end;

type TPlayer = record
  Score: Int32;
end;

type TMove = array[0..1] of TPoint;

type TGrid = record
  Cells: array [-5..5, -4..4] of TGridCell;
  Moves: array of TMove;
  InvalidMoves: array of TMove;
  Ball: TPoint;
  function IsValidCell(const x, y: Int32): Boolean;
  function IsValidMove(const x1, y1, x2, y2: Int32): Boolean;
  function IsWin: Int32;
  function CurPos: TPoint;
  function Action: Boolean;
  function ActionAt(const p: TPoint): Boolean;
  procedure Setup;
  procedure AddBounce(const x, y: Int32);
  procedure Draw;
  procedure DebugDraw;
end;

type TMenuButton = record
  Caption: String;
  Action: TG2ProcObj;
end;

type TMenu = record
  Buttons: array of TMenuButton;
  Spacing: TG2Float;
  function PointInButton(const x, y: TG2Float): Int32;
  function Click(x, y: TG2Float): Boolean;
  procedure AddButton(const Caption: String; const Action: TG2ProcObj = nil);
  procedure Setup;
  procedure Render;
end;

type TGameMode = (gm_pvp, gm_pvg);

type TAI = record
  UpdateTime: TG2Float;
  Path: array of TPoint;
  procedure Setup;
  function MakeMove(const TargetX: Int32 = -5; const TargetY: Int32 = 0): Boolean;
  function Update: Boolean;
  procedure DebugDraw;
end;

type TGame = class
public
  var Font1: TG2Font;
  var Display: TG2Display2D;
  var DebugDrawEnabled: Boolean;
  var Grid: TGrid;
  var Players: array[0..1] of TPlayer;
  var CurPlayer: Int32;
  var Msg: String;
  var MsgTime: TG2Float;
  var MsgDuration: TG2Float;
  var IsMenu: Boolean;
  var Menu: TMenu;
  var Mode: TGameMode;
  var AI: TAI;
  constructor Create;
  destructor Destroy; override;
  procedure Initialize;
  procedure Finalize;
  procedure Update;
  procedure Render;
  procedure KeyDown(const Key: Integer);
  procedure KeyUp(const Key: Integer);
  procedure MouseDown(const Button, x, y: Integer);
  procedure MouseUp(const Button, x, y: Integer);
  procedure Scroll(const y: Integer);
  procedure Print(const c: AnsiChar);
  procedure DrawLine(const x1, y1, x2, y2: TG2Float; const Color: TG2Color; const Width: TG2Float = 0.1);
  procedure ShowMessage(const Message: String; const Duration: TG2Float = 2);
  procedure SwapPlayers;
  procedure OnAction(const Swap: Boolean);
  procedure OnStartPvP;
  procedure OnStartPvG;
end;

var Game: TGame;

const PlayerColors: array[0..1] of UInt32 = ($ffff0000, $ff0000ff);
const Dirs: array [0..7] of TPoint = (
  (X: -1; Y: 0), (X: -1; Y: -1), (X: 0; Y: -1), (X: 1; Y: -1),
  (X: 1; Y: 0), (X: 1; Y: 1), (X: 0; Y: 1), (X: -1; Y: 1)
);

implementation

function TGrid.IsValidCell(const x, y: Int32): Boolean;
  var ax, ay: Int32;
begin
  ax := Abs(x);
  ay := Abs(y);
  Result := ((ay <= 4) and (ax <= 4)) or ((ax <= 5) and (ay = 0));
  Result := Result and not ((ax = 4) and (ay = 4));
end;

function TGrid.IsValidMove(const x1, y1, x2, y2: Int32): Boolean;
  var i, n: Int32;
begin
  if (x1 = x2) and (y1 = y2) then Exit(False);
  if not IsValidCell(x1, y1) then Exit(False);
  if not IsValidCell(x2, y2) then Exit(False);
  if Abs(x1 - x2) > 1 then Exit(False);
  if Abs(y1 - y2) > 1 then Exit(False);
  if not Cells[x2, y2].Valid then Exit(False);
  for i := 0 to High(InvalidMoves) do
  for n := 0 to 1 do
  begin
    if (InvalidMoves[i][n].x = x1)
    and (InvalidMoves[i][n].y = y1)
    and (InvalidMoves[i][(n + 1) mod 2].x = x2)
    and (InvalidMoves[i][(n + 1) mod 2].y = y2) then Exit(False);
  end;
  for i := 0 to High(Moves) do
  for n := 0 to 1 do
  begin
    if (Moves[i][n].x = x1)
    and (Moves[i][n].y = y1)
    and (Moves[i][(n + 1) mod 2].x = x2)
    and (Moves[i][(n + 1) mod 2].y = y2) then Exit(False);
  end;
  Result := True;
end;

function TGrid.IsWin: Int32;
begin
  if Ball.y <> 0 then Exit(-1);
  if Ball.x = -5 then Exit(1);
  if Ball.x = 5 then Exit(0);
  Result := -1;
end;

function TGrid.CurPos: TPoint;
  var mp: TG2Vec2;
begin
  mp := Game.Display.CoordToDisplay(g2.MousePos);
  Result.x := Round(mp.x);
  Result.y := Round(mp.y);
end;

function TGrid.Action: Boolean;
begin
  Result := ActionAt(CurPos);
end;

function TGrid.ActionAt(const p: TPoint): Boolean;
  var i: Int32;
begin
  if not IsValidMove(Ball.x, Ball.y, p.x, p.y) then
  begin
    Game.ShowMessage('Invalid Move');
    Exit(False);
  end;
  i := Length(Moves);
  SetLength(Moves, i + 1);
  Moves[i][0] := Ball;
  Moves[i][1] := p;
  Result := not Cells[p.x, p.y].Bounce;
  AddBounce(Ball.x, Ball.y);
  AddBounce(p.x, p.y);
  Ball := p;
end;

procedure TGrid.Setup;
  procedure AddInvalidMove(const x1, y1, x2, y2: Int32);
    var i: Int32;
  begin
    i := Length(InvalidMoves);
    SetLength(InvalidMoves, i + 1);
    InvalidMoves[i][0].x := x1;
    InvalidMoves[i][0].y := y1;
    InvalidMoves[i][1].x := x2;
    InvalidMoves[i][1].y := y2;
  end;
  var x, y, i, n: Int32;
begin
  for x := Low(Cells) to High(Cells) do
  for y := Low(Cells[x]) to High(Cells[x]) do
  begin
    Cells[x, y].Bounce := False;
    Cells[x, y].Valid := True;
  end;
  Moves := nil;
  InvalidMoves := nil;
  for i := -4 to 3 do
  begin
    AddInvalidMove(0, i, 0, i + 1);
    AddInvalidMove(i, -4, i + 1, -4);
    AddInvalidMove(i, 4, i + 1, 4);
  end;
  for i := 1 to 3 do
  begin
    AddInvalidMove(-4, i, -4, i + 1);
    AddInvalidMove(4, i, 4, i + 1);
    AddInvalidMove(-4, -i, -4, -(i + 1));
    AddInvalidMove(4, -i, 4, -(i + 1));
  end;
  for i := 0 to 1 do
  begin
    if i = 0 then n := -1 else n := 1;
    AddInvalidMove(0, n, n, n);
    AddInvalidMove(0, -n, n, -n);
    AddInvalidMove(n, n, n, 0);
    AddInvalidMove(-n, n, -n, 0);
  end;
  for i := -4 to 4 do
  begin
    AddBounce(i, -4);
    AddBounce(i, 4);
    if Abs(i) = 0 then n := 5 else n := 4;
    AddBounce(-n, i);
    AddBounce(n, i);
    AddBounce(0, i);
  end;
  for i := -1 to 1 do
  for n := -1 to 1 do
  begin
    AddBounce(i, n);
  end;
  Ball := Point(0, 0);
end;

procedure TGrid.AddBounce(const x, y: Int32);
  var i, n: Int32;
begin
  if not IsValidCell(x, y) then Exit;
  Cells[x, y].Bounce := True;
  n := 0;
  for i := 0 to High(Dirs) do
  begin
    if not Game.Grid.IsValidMove(x, y, x + Dirs[i].x, y + Dirs[i].y) then Continue;
    Inc(n);
    if n >= 2 then Exit;
  end;
  Cells[x, y].Valid := False;
end;

procedure TGrid.Draw;
  procedure DrawField;
  begin
    Game.Display.PrimRect(-4, -4, 8, 8, $ffffffff);
    Game.Display.PrimRect(-5, -1, 1, 2, $ffffffff);
    Game.Display.PrimRect(4, -1, 1, 2, $ffffffff);
  end;
  procedure DrawBorder;
    const LeftGate = $ff800000;
    const RightGame = $ff000080;
  begin
    Game.DrawLine(-4, -1, -4, -4, $ff000000);
    Game.DrawLine(-4, 1, -4, 4, $ff000000);
    Game.DrawLine(4, -1, 4, -4, $ff000000);
    Game.DrawLine(4, 1, 4, 4, $ff000000);
    Game.DrawLine(-4, -4, 4, -4, $ff000000);
    Game.DrawLine(-4, 4, 4, 4, $ff000000);
    //left gate
    Game.DrawLine(-5, -1, -5, 1, LeftGate);
    Game.DrawLine(-5, -1, -4, -1, LeftGate);
    Game.DrawLine(-5, 1, -4, 1, LeftGate);
    //right gate
    Game.DrawLine(5, -1, 5, 1, RightGame);
    Game.DrawLine(5, -1, 4, -1, RightGame);
    Game.DrawLine(5, 1, 4, 1, RightGame);
  end;
  procedure DrawLining;
    var i, n: Int32;
    const Color = $ffc0c0c0;
  begin
    for i := -4 to 4 do
    begin
      if i = 0 then n := 5 else n := 4;
      Game.Display.PrimLine(-n, i, n, i, Color);
      Game.Display.PrimLine(i, -4, i, 4, Color);
    end;
    Game.DrawLine(0, -4, 0, 4, Color);
    Game.DrawLine(-1, -1, 1, -1, Color);
    Game.DrawLine(1, -1, 1, 1, Color);
    Game.DrawLine(1, 1, -1, 1, Color);
    Game.DrawLine(-1, 1, -1, -1, Color);
  end;
  procedure DrawBall;
    const c = $ffff0000;
    var c1: TG2Color;
  begin
    c1 := c;
    c1.a := 0;
    Game.Display.PrimCircleCol(Ball.x, Ball.y, 0.2, c, c);
    Game.Display.PrimCircleCol(Ball.x, Ball.y, 0.2 + Abs(Sin(G2TimeInterval())) * 0.2, c, c1);
  end;
  procedure DrawNextMove;
    var p: TPoint;
  begin
    p := CurPos;
    if IsValidMove(Ball.x, Ball.y, p.x, p.y) then
    begin
      Game.DrawLine(
        Ball.x, Ball.y, p.x, p.y,
        G2Color(
          0, $c0, 0,
          50 + Trunc((Sin(G2TimeInterval() * G2TwoPi) * 0.5 + 0.5) * 200)
        )
      );
      Game.Display.PrimCircleCol(p, 0.1, $ff0000ff, $ff0000ff);
    end;
  end;
  procedure DrawMoves;
    var i: Int32;
  begin
    for i := 0 to High(Moves) do
    begin
      Game.DrawLine(
        Moves[i][0].x, Moves[i][0].y,
        Moves[i][1].x, Moves[i][1].y,
        $ff606060
      );
    end;
  end;
begin
  DrawField;
  DrawLining;
  DrawBorder;
  DrawMoves;
  if (Game.Mode <> gm_pvg)
  or (Game.CurPlayer = 0) then
  begin
    DrawNextMove;
  end;
  DrawBall;
end;

procedure TGrid.DebugDraw;
  procedure DrawBounces;
    var x, y: Int32;
  begin
    for x := Low(Cells) to High(Cells) do
    for y := Low(Cells[x]) to High(Cells[x]) do
    begin
      if not IsValidCell(x, y) then Continue;
      if not Cells[x, y].Bounce then Continue;
      Game.Display.PrimCircleCol(
        x, y, 0.2, $ffff0000, $ffff0000
      );
    end;
  end;
  procedure DrawMouse;
    var mp: TG2Vec2;
  begin
    mp := Game.Display.CoordToDisplay(g2.MousePos);
    Game.Display.PrimCircleCol(mp, 0.1, $ff0000ff, $ff0000ff);
  end;
  procedure DrawInvalidMoves;
    var i: Int32;
  begin
    for i := 0 to High(InvalidMoves) do
    begin
      Game.DrawLine(
        InvalidMoves[i][0].x, InvalidMoves[i][0].y,
        InvalidMoves[i][1].x, InvalidMoves[i][1].y,
        $ffff0000
      );
    end;
  end;
begin
  //DrawInvalidMoves;
end;

function TMenu.PointInButton(const x, y: TG2Float): Int32;
  var i: Int32;
  var tx, ty, dy: TG2Float;
  var w, h: TG2Float;
begin
  h := Game.Font1.TextHeight('A');
  dy := h + Spacing;
  ty := (g2.Params.Height - (dy * Length(Buttons))) * 0.5;
  for i := 0 to High(Buttons) do
  begin
    w := Game.Font1.TextWidth(Buttons[i].Caption);
    tx := (g2.Params.Width - Game.Font1.TextWidth(Buttons[i].Caption)) * 0.5;
    if G2Vec2InRect(G2Vec2(x, y), G2Rect(tx, ty, w, h)) then Exit(i);
    ty += dy;
  end;
  Result := -1;
end;

function TMenu.Click(x, y: TG2Float): Boolean;
  var btn: Int32;
begin
  btn := PointInButton(x, y);
  if btn = -1 then Exit;
  if not Assigned(Buttons[btn].Action) then Exit;
  Buttons[btn].Action();
end;

procedure TMenu.AddButton(const Caption: String; const Action: TG2ProcObj);
  var i: Int32;
begin
  i := Length(Buttons);
  SetLength(Buttons, i + 1);
  Buttons[i].Caption := Caption;
  Buttons[i].Action := Action;
end;

procedure TMenu.Setup;
begin
  Spacing := g2.Params.Height * 0.1;
  AddButton('Player vs Player', @Game.OnStartPvP);
  AddButton('Player vs AI', @Game.OnStartPvG);
end;

procedure TMenu.Render;
  var i: Int32;
  var s: String;
  var y, dy: TG2Float;
  var hov: Int32;
  var mc: TPoint;
  var c: TG2Color;
begin
  mc := g2.MousePos;
  hov := PointInButton(mc.x, mc.y);
  g2.Clear($ff202020);
  dy := Game.Font1.TextHeight('A') + Spacing;
  y := (g2.Params.Height - (dy * Length(Buttons))) * 0.5;
  for i := 0 to High(Buttons) do
  begin
    if hov = i then c := $ffffffff else c := $ffa0a0a0;
    s := Buttons[i].Caption;
    Game.Font1.Print(
      (g2.Params.Width - Game.Font1.TextWidth(s)) * 0.5,
      y, 1, 1, c, s, bmNormal, tfPoint
    );
    y += dy;
  end;
end;

procedure TAI.Setup;
begin
  UpdateTime := 1;
end;

function TAI.MakeMove(const TargetX: Int32; const TargetY: Int32): Boolean;
  var LastPath: array of TPoint;
  procedure DebugPath(const p: TPoint);
    var i: Int32;
  begin
    i := Length(LastPath);
    SetLength(LastPath, i + 1);
    LastPath[i] := p;
  end;
  var Tgt: TG2Vec2;
  var CheckedMoves: array of TPoint;
  function AddCheckedMove(const m: TPoint): Boolean;
    var i: Int32;
  begin
    for i := 0 to High(CheckedMoves) do
    begin
      if (CheckedMoves[i].x = m.x)
      and (CheckedMoves[i].y = m.y) then Exit(False);
    end;
    i := Length(CheckedMoves);
    SetLength(CheckedMoves, i + 1);
    CheckedMoves[i] := m;
    Result := True;
  end;
  function CheckMove(const m: TPoint): TG2Float;
    var i: Int32;
    var p: TPoint;
  begin
    Result := 100;
    if not AddCheckedMove(m) then Exit;
    Result := G2Min(Result, (G2Vec2(m) - Tgt).Len + (Random - 0.5));
    DebugPath(m);
    if (m.x = TargetX) and (m.y = TargetY) then Exit(0);
    if not Game.Grid.Cells[m.x, m.y].Bounce then Exit;
    for i := 0 to High(Dirs) do
    begin
      p := Point(m.x + Dirs[i].x, m.y + Dirs[i].y);
      if not Game.Grid.IsValidMove(m.x, m.y, p.x, p.y) then Continue;
      Result := G2Min(Result, CheckMove(p));
    end;
  end;
  var BestMove: TPoint;
  var BestMoveDist, d: TG2Float;
  var AnyMoveFound: Boolean;
  var cp, p: TPoint;
  var i: Int32;
begin
  Tgt := G2Vec2(TargetX, TargetY);
  BestMoveDist := 1000;
  AnyMoveFound := False;
  cp := Point(Game.Grid.Ball.x, Game.Grid.Ball.y);
  AddCheckedMove(cp);
  for i := 0 to High(Dirs) do
  begin
    LastPath := nil;
    DebugPath(cp);
    p := Point(cp.x + Dirs[i].x, cp.y + Dirs[i].y);
    if not Game.Grid.IsValidMove(cp.x, cp.y, p.x, p.y) then Continue;
    d := CheckMove(p);
    if (p.x = -TargetX) and (p.y = TargetY) then d := 99;
    if d >= BestMoveDist then Continue;
    Path := LastPath;
    BestMoveDist := d;
    BestMove := p;
    AnyMoveFound := True;
    if (p.x = TargetX) and (p.y = TargetY) then Break;
  end;
  if not AnyMoveFound then Exit;
  Result := Game.Grid.ActionAt(BestMove);
end;

function TAI.Update: Boolean;
begin
  UpdateTime -= g2.DeltaTimeSec;
  if UpdateTime > 0 then Exit(False);
  UpdateTime := 1;
  Result := MakeMove;
end;

procedure TAI.DebugDraw;
  var i, j: Int32;
begin
  for i := 0 to High(Path) - 1 do
  begin
    j := i + 1;
    Game.DrawLine(
      Path[i].x, Path[i].y,
      Path[j].x, Path[j].y,
      $ffff0000
    );
  end;
end;

//TGame BEGIN
constructor TGame.Create;
begin
  Randomize;
  g2.CallbackInitializeAdd(@Initialize);
  g2.CallbackFinalizeAdd(@Finalize);
  g2.CallbackUpdateAdd(@Update);
  g2.CallbackRenderAdd(@Render);
  g2.CallbackKeyDownAdd(@KeyDown);
  g2.CallbackKeyUpAdd(@KeyUp);
  g2.CallbackMouseDownAdd(@MouseDown);
  g2.CallbackMouseUpAdd(@MouseUp);
  g2.CallbackScrollAdd(@Scroll);
  g2.CallbackPrintAdd(@Print);
  g2.Params.MaxFPS := 100;
  g2.Params.Width := 1000;
  g2.Params.Height := 600;
  g2.Params.ScreenMode := smWindow;
  DebugDrawEnabled := False;
end;

destructor TGame.Destroy;
begin
  g2.CallbackInitializeRemove(@Initialize);
  g2.CallbackFinalizeRemove(@Finalize);
  g2.CallbackUpdateRemove(@Update);
  g2.CallbackRenderRemove(@Render);
  g2.CallbackKeyDownRemove(@KeyDown);
  g2.CallbackKeyUpRemove(@KeyUp);
  g2.CallbackMouseDownRemove(@MouseDown);
  g2.CallbackMouseUpRemove(@MouseUp);
  g2.CallbackScrollRemove(@Scroll);
  g2.CallbackPrintRemove(@Print);
  inherited Destroy;
end;

procedure TGame.Initialize;
  var i: Int32;
begin
  g2.Window.Caption := 'Soccer Strats';
  Font1 := TG2Font.Create;
  Font1.Load('font1.g2f');
  Display := TG2Display2D.Create;
  Display.Width := 10;
  Display.Height := 10;
  Display.Position := G2Vec2;
  IsMenu := True;
  Menu.Setup;
  Grid.Setup;
  AI.Setup;
  for i := 0 to High(Players) do
  begin
    Players[i].Score := 0;
  end;
  CurPlayer := 0;
end;

procedure TGame.Finalize;
begin
  Display.Free;
  Font1.Free;
  Free;
end;

procedure TGame.Update;
begin
  if MsgTime < MsgDuration then MsgTime += g2.DeltaTimeSec;
  if (Mode = gm_pvg) and (CurPlayer = 1) then
  begin
    OnAction(AI.Update);
  end;
end;

procedure TGame.Render;
  var i: Int32;
  var x: TG2Float;
  var s: String;
  var c: TG2Color;
begin
  if IsMenu then
  begin
    Menu.Render;
    Exit;
  end;
  g2.Clear($ffa0a0a0);
  Grid.Draw;
  Grid.DebugDraw;
  //if Mode = gm_pvg then AI.DebugDraw;
  for i := 0 to High(Players) do
  begin
    s := 'Player ' + IntToStr(i + 1) + ': ' + IntToStr(Players[i].Score);
    if i = 0 then x := g2.Params.Width * 0.05
    else x := g2.Params.Width - Font1.TextWidth(s) - g2.Params.Width * 0.05;
    Font1.Print(x, 0, 1, 1, PlayerColors[i], s, bmNormal, tfPoint);
  end;
  s := 'Player ' + IntToStr(CurPlayer + 1);
  Font1.Print(
    (g2.Params.Width - Font1.TextWidth(s)) * 0.5, 0,
    1, 1, PlayerColors[CurPlayer], s, bmNormal, tfPoint
  );
  if MsgTime < MsgDuration then
  begin
    c := 0;
    c.a := Trunc((Power(1 - Abs((MsgDuration * 0.5) - MsgTime), 0.7)) * 255);
    Font1.Print(
      (g2.Params.Width - Font1.TextWidth(Msg)) * 0.5,
      g2.Params.Height - Font1.TextHeight(Msg),
      1, 1, c, Msg, bmNormal, tfPoint
    );
  end;
  //Font1.Print(10, 10, 0.75, 0.75, 'FPS: ' + IntToStr(g2.FPS), bmNormal, tfLinear);
end;

procedure TGame.KeyDown(const Key: Integer);
begin
  case Key of
    G2K_G: DebugDrawEnabled := not DebugDrawEnabled;
  end;
end;

procedure TGame.KeyUp(const Key: Integer);
begin

end;

procedure TGame.MouseDown(const Button, x, y: Integer);
begin
  if IsMenu then
  begin
    Menu.Click(x, y);
    Exit;
  end;
  if (Mode = gm_pvg)
  and (CurPlayer = 1) then Exit;
  OnAction(Grid.Action);
end;

procedure TGame.MouseUp(const Button, x, y: Integer);
begin

end;

procedure TGame.Scroll(const y: Integer);
begin

end;

procedure TGame.Print(const c: AnsiChar);
begin

end;

procedure TGame.DrawLine(
  const x1, y1, x2, y2: TG2Float;
  const Color: TG2Color;
  const Width: TG2Float
);
  var v0, v1, r0, r1, r2, r3, n, n1: TG2Vec2;
  var hw: TG2Float;
begin
  v0.SetValue(x1, y1);
  v1.SetValue(x2, y2);
  n := v1 - v0;
  if n.Len < G2EPS then Exit;
  n := n.Norm * (Width * 0.5);
  n1 := n.Perp;
  Display.PrimQuad(
    v0 - n - n1, v1 + n - n1,
    v0 - n + n1, v1 + n + n1,
    Color
  );
end;

procedure TGame.ShowMessage(const Message: String; const Duration: TG2Float);
begin
  Msg := Message;
  MsgDuration := Duration;
  MsgTime := 0;
end;

procedure TGame.SwapPlayers;
begin
  CurPlayer := (CurPlayer + 1) mod 2;
  ShowMessage('Player ' + IntToStr(CurPlayer + 1) + ' turn');
end;

procedure TGame.OnAction(const Swap: Boolean);
  var w, i: Int32;
  var p: TPoint;
  var ValidState: Boolean;
begin
  w := Grid.IsWin;
  if w = -1 then
  begin
    if Swap then SwapPlayers;
    ValidState := False;
    for i := 0 to High(Dirs) do
    begin
      p := Point(Grid.Ball.x + Dirs[i].x, Grid.Ball.y + Dirs[i].y);
      if Grid.IsValidMove(Grid.Ball.x, Grid.Ball.y, p.x, p.y) then
      begin
        ValidState := True;
        Break;
      end;
    end;
    if not ValidState then
    begin
      ShowMessage('Draw...');
      Grid.Setup;
    end;
    Exit;
  end;
  ShowMessage('Player ' + IntToStr(w + 1) + ' wins!');
  Inc(Players[w].Score);
  Grid.Setup;
end;

procedure TGame.OnStartPvP;
begin
  IsMenu := False;
  Mode := gm_pvp;
end;

procedure TGame.OnStartPvG;
begin
  IsMenu := False;
  Mode := gm_pvg;
end;
//TGame END

end.
