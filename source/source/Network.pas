unit Network;

interface

uses
  SysUtils,
  Classes,
  CommonUtils,
  NetUtils;

type TUNetStatus = (ns_idle, ns_connecting, ns_connected);

type TUNet = class (TThread)
private
  var _Status: TUNetStatus;
  var _Port: UInt16;
  var _Socket: Int32;
  var _Lock: TUCriticalSection;
  var _Messages: array of String;
  function Loopback: Boolean;
  function Connect(const Addr: TUInAddr): Boolean;
  function ReceiveMessages: Int32;
  function GetIsConnected: Boolean;
public
  property Status: TUNetStatus read _Status write _Status;
  property Port: UInt16 read _Port write _Port;
  property IsConnected: Boolean read GetIsConnected;
  class function GetMyName: String;
  class function GetMyIP: TUInAddr;
  class function Run(const APort: UInt16 = 6667): TUNet;
  class procedure Test;
  procedure AfterConstruction; override;
  procedure Execute; override;
  procedure Send(const Msg: String);
  function Receive: TStringArray;
end;

implementation

type TListenThread = class (TThread)
public
  var ListenSocket: TUSocket;
  var Socket: Int32;
  var Port: UInt16;
  var Addr: TUInAddr;
  procedure Execute; override;
  procedure Abort;
end;

procedure TListenThread.Execute;
  var SockAddr, ClientAddr: TUInetSockAddr;
  var n: Int32;
begin
  ListenSocket := TUSocket.CreateTCP();
  try
    SockAddr.sin_family := AF_INET;
    SockAddr.sin_port := htons(Port);
    SockAddr.sin_addr := TUInAddr.Zero;
    n := SizeOf(SockAddr);
    if ListenSocket.Bind(@SockAddr, n) <> 0 then Exit;
    if ListenSocket.Listen(8) <> 0 then Exit;
    n := SizeOf(ClientAddr);
    ClientAddr := TUInetSockAddr.Default;
    Socket := ListenSocket.Accept(@ClientAddr, @n);
    if Socket < 0 then Exit;
    Addr := ClientAddr.sin_addr;
    WriteLn(UNetNetAddrToStr(Addr));
  finally
    ListenSocket.Shutdown();
    ListenSocket.Close;
  end;
end;

procedure TListenThread.Abort;
begin
  Terminate;
  if ListenSocket = -1 then Exit;
  ListenSocket.Shutdown();
  ListenSocket.Close;
end;

type TBeaconThread = class (TThread)
public
  var Port: UInt16;
  var ListenSocket: TUSocket;
  var Address: TUInAddr;
  var BroadcastTime: UInt64;
  const BeaconId: Uint32 = (Ord('S') shl 24) or (Ord('S') shl 16) or (Ord('N') shl 8) or (Ord('B'));
  procedure Execute; override;
  procedure Abort;
  procedure Broadcast;
end;

procedure TBeaconThread.Execute;
  var Buffer: UInt32;
  var SockAddr, OtherAddr: TUInetSockAddr;
  var n, r: Int32;
  var MyAddr: TUInAddr;
begin
  MyAddr := TUNet.GetMyIP;
  Address := TUInAddr.Zero;
  ListenSocket := TUSocket.CreateUDP();
  try
    SockAddr.sin_family := AF_INET;
    SockAddr.sin_port := htons(Port);
    SockAddr.sin_addr := TUInAddr.Zero;
    n := SizeOf(SockAddr);
    if ListenSocket.Bind(@SockAddr, n) <> 0 then Exit;
    r := 0;
    while not Terminated do
    begin
      n := SizeOf(OtherAddr);
      r := ListenSocket.RecvFrom(@Buffer, SizeOf(Buffer), 0, @OtherAddr, @n);
      if MyAddr.Addr32 = OtherAddr.sin_addr.Addr32 then Continue;
      if Buffer <> BeaconId then Continue;
      WriteLn('Beacon: ', UNetNetAddrToStr(OtherAddr.sin_addr));
      Address := OtherAddr.sin_addr;
      Break;
    end;
  finally
    ListenSocket.Shutdown();
    ListenSocket.Close;
  end;
end;

procedure TBeaconThread.Abort;
begin
  Terminate;
  if ListenSocket = -1 then Exit;
  ListenSocket.Shutdown();
  ListenSocket.Close;
end;

procedure TBeaconThread.Broadcast;
  var Socket: TUSocket;
  var MyAddr: TUInAddr;
  var Addr: TUInetSockAddr;
  var i: Int32;
  var NewTime: UInt64;
begin
  NewTime := GetTickCount64;
  if NewTime - BroadcastTime < 5000 then Exit;
  BroadcastTime := NewTime;
  MyAddr := TUNet.GetMyIP;
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(Port);
  Addr.sin_addr := MyAddr;
  Socket := TUSocket.CreateUDP();
  try
    for i := 1 to 255 do
    begin
      if i = MyAddr.Addr8[3] then Continue;
      Addr.sin_addr.Addr8[3] := i;
      Socket.SendTo(@BeaconId, SizeOf(BeaconId), 0, @Addr, SizeOf(Addr));
    end;
    WriteLn('Beacon Broadcast Complete');
  finally
    Socket.Close;
  end;
end;

function TUNet.Loopback: Boolean;
  var Addr: TUInAddr;
begin
  Addr := TUInAddr.LocalhostN;
  Result := Connect(Addr);
end;

function TUNet.Connect(const Addr: TUInAddr): Boolean;
  var Socket: Int32;
  var SockAddr: TUInetSockAddr;
begin
  Socket := TUSocket.CreateTCP();
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := HToNs(Port);
  SockAddr.sin_addr := Addr;
  if Socket.Connect(@SockAddr, SizeOf(SockAddr)) = 0 then
  begin
    _Socket := Socket;
    Exit(True);
  end;
  Socket.Close;
  Result := False;
end;

function TUNet.ReceiveMessages: Int32;
  var i, r: Int32;
  var Buffer: array[0..1023] of UInt8;
  var Received: array of UInt8;
  var s: String;
begin
  Received := nil;
  while not Terminated do
  begin
    r := _Socket.Recv(@Buffer, SizeOf(Buffer), 0);
    if r <= 0 then Exit(r);
    i := Length(Received);
    SetLength(Received, i + r);
    Move(Buffer, Received[i], r);
    _Lock.Enter;
    try
      i := 0;
      while i < Length(Received) do
      begin
        if Received[i] = 0 then
        begin
          s := '';
          if i > 0 then
          begin
            SetLength(s, i);
            Move(Received[0], s[1], i);
          end;
          r := Length(Received) - (i + 1);
          Move(Received[i + 1], Received[0], r);
          SetLength(Received, r);
          SetLength(_Messages, Length(_Messages) + 1);
          _Messages[High(_Messages)] := s;
          WriteLn(s);
          i := -1;
        end;
        Inc(i);
      end;
    finally
      _Lock.Leave;
    end;
  end;
  Result := 0;
end;

function TUNet.GetIsConnected: Boolean;
begin
  Result := _Socket > -1;
end;

class function TUNet.GetMyName: String;
begin
  Result := UNetHostName;
end;

class function TUNet.GetMyIP: TUInAddr;
begin
  Result := UNetLocalAddr;
end;

class function TUNet.Run(const APort: UInt16): TUNet;
begin
  Result := TUNet.Create(True);
  Result.Port := APort;
  Result.Start;
end;

class procedure TUNet.Test;
begin
  WriteLn(GetMyName);
  WriteLn(UNetNetAddrToStr(GetMyIP));
end;

procedure TUNet.AfterConstruction;
begin
  inherited AfterConstruction;
  _Socket := -1;
  _Status := ns_idle;
end;

procedure TUNet.Execute;
  function TryConnect: Boolean;
    var Listen: TListenThread;
    var Beacon: TBeaconThread;
    var MyAddr: TUInAddr;
  begin
    Result := False;
    MyAddr := GetMyIP;
    if Loopback then Exit(True);
    Listen := TListenThread.Create(True);
    Listen.Port := Port;
    Beacon := TBeaconThread.Create(True);
    Beacon.Port := Port;
    Listen.Start;
    Beacon.Start;
    try
      while True do
      begin
        Beacon.Broadcast;
        if Listen.Finished then
        begin
          _Socket := Listen.Socket;
          Exit(True);
        end;
        if Beacon.Finished then
        begin
          if Beacon.Address.Addr32 = 0 then
          begin
            Beacon.Free;
            Beacon := TBeaconThread.Create(True);
            Beacon.Port := Port;
            Beacon.Start;
            Continue;
          end;
          if Beacon.Address.Addr32 > MyAddr.Addr32 then Continue;
          if Connect(Beacon.Address) then Exit(True);
        end;
        Sleep(2000);
      end;
    finally
      WriteLn('Socket: ', _Socket);
      Beacon.Abort;
      Beacon.WaitFor;
      Beacon.Free;
      Listen.Abort;
      Listen.WaitFor;
      Listen.Free;
      WriteLn('Finished connecting');
    end;
  end;
begin
  _Socket := -1;
  _Status := ns_connecting;
  while not Terminated do
  begin
    if TryConnect then Break;
    Sleep(1000);
  end;
  if not IsConnected then Exit;
  _Status := ns_connected;
  try
    ReceiveMessages;
  finally
    _Socket.Close;
  end;
end;

procedure TUNet.Send(const Msg: String);
  var i, r: Int32;
begin
  if not IsConnected then Exit;
  i := 0;
  while i < Length(Msg) + 1 do
  begin
    r := _Socket.Send(@Msg[i + 1], Length(Msg) + 1 - i, 0);
    if r <= 0 then Exit;
    i += r;
  end;
end;

function TUNet.Receive: TStringArray;
  var i: Int32;
begin
  _Lock.Enter;
  try
    if Length(_Messages) = 0 then Exit(nil);
    SetLength(Result, Length(_Messages));
    for i := 0 to High(_Messages) do
    begin
      Result[i] := _Messages[i];
    end;
    _Messages := nil;
  finally
    _Lock.Leave;
  end;
end;

end.
