unit Network;

interface

uses
  SysUtils,
{$if defined(WINDOWS)}
  WinSock2,
{$elseif defined(UNIX)}
{$endif}
  Sockets,
  Classes,
  CommonUtils;

type
{$if not defined(WINDOWS)}
  PAddrInfo = ^TAddrInfo;
  PPAddrInfo = ^PAddrInfo;
  TAddrInfo = record
    ai_flags: Int32;
    ai_family: Int32;
    ai_socktype: Int32;
    ai_protocol: Int32;
    ai_addrlen: Int32;
    ai_addr: PSockAddr;
    ai_canonname: PAnsiChar;
    ai_next: PAddrInfo;
  end;

  PHostEnt = ^THostEnt;
  THostEnt = record
    h_name: PAnsiChar;
    h_aliases: ^PAnsiChar;
    h_addrtype: LongInt;
    h_length: LongInt;
    h_addr_list: ^PAnsiChar;
  end;
{$endif}

  PPIfAddrs = ^PIfAddrs;
  PIfAddrs = ^TIfAddrs;
  TIfAddrs = record
    ifa_next: PIfAddrs;
    ifa_name: PAnsiChar;
    ifa_flags: UInt32;
    ifa_addr: PSockAddr;
    ifa_netmask: PSockAddr;
    ifa_ifu: PSockAddr;
    ifa_data: Pointer;
  end;

const
  AI_PASSIVE = 1;

{$if not defined(WINDOWS)}
function GetIfAddrs(
  const IfAddrs: PPIfAddrs
): Int32; cdecl; external 'c' name 'getifaddrs';
procedure FreeIfAddrs(
  const IfaAdrs: PIfAddrs
); cdecl; external 'c' name 'freeifaddrs';
function GetAddrInfo(
  const Node: PAnsiChar;
  const Service: PAnsiChar;
  const Hints: PAddrInfo;
  const Results: PPAddrInfo
): Integer; cdecl; external 'c' name 'getaddrinfo';
procedure FreeAddrInfo(
  const AddrInfo: PAddrInfo
); cdecl; external 'c' name 'freeaddrinfo';
function GetHostName(
  const Name: PAnsiChar;
  const Len: Integer
): Integer; external 'c' name 'gethostname';
function GetHostByName(
  const Name: PAnsiChar
): PHostEnt; external 'c' name 'gethostbyname';

function PlatformLibOpen(Name: PAnsiChar; Flags: LongInt): TLibHandle; cdecl; external 'dl' name 'dlopen';
function PlatformLibClose(Handle: TLibHandle): LongInt; cdecl; external 'dl' name 'dlclose';
function PlatformLibAddress(Handle: TLibHandle; ProcName: PAnsiChar): Pointer; cdecl; external 'dl' name 'dlsym';
{$endif}

type TUNetStatus = (ns_idle, ns_connecting, ns_connected);

type TUNet = class (TThread)
private
  var _Status: TUNetStatus;
  var _Port: UInt16;
  var _Socket: Int32;
  var _Lock: TUCriticalSection;
  var _Messages: array of String;
  function Loopback: Boolean;
  function Connect(const Addr: TInAddr): Boolean;
  function ReceiveMessages: Int32;
  function GetIsConnected: Boolean;
public
  property Status: TUNetStatus read _Status write _Status;
  property Port: UInt16 read _Port write _Port;
  property IsConnected: Boolean read GetIsConnected;
  class function GetMyName: String;
  class function GetMyIP: TInAddr;
  class function Run(const APort: UInt16 = 6667): TUNet;
  class procedure Test;
  procedure AfterConstruction; override;
  procedure Execute; override;
  procedure Send(const Msg: String);
  function Receive: TStringArray;
end;

implementation

type TSearchThread = class (TThread)
public
  var Socket: Int32;
  var Addr: TInAddr;
  var Port: UInt16;
  var Counter: PInt32;
  procedure Execute; override;
end;

procedure TSearchThread.Execute;
  var SockAddr: TInetSockAddr;
begin
  Socket := FpSocket(AF_INET, SOCK_STREAM, 0);
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_addr := Addr;
  SockAddr.sin_port := htons(Port);
  try
    if FpConnect(Socket, @SockAddr, SizeOf(SockAddr)) = 0 then Exit;
    CloseSocket(Socket);
    Socket := -1;
  finally
    WriteLn(NetAddrToStr(Addr));
    InterlockedDecrement(Counter^);
  end;
end;

type TListenThread = class (TThread)
public
  var ListenSocket: Int32;
  var Socket: Int32;
  var Port: UInt16;
  var Addr: TInAddr;
  procedure Execute; override;
  procedure Abort;
end;

procedure TListenThread.Execute;
  var SockAddr, ClientAddr: TInetSockAddr;
  var n: Int32;
begin
  ListenSocket := FpSocket(AF_INET, SOCK_STREAM, 0);
  try
    SockAddr.sin_family := AF_INET;
    SockAddr.sin_port := htons(Port);
    SockAddr.sin_addr := StrToNetAddr('0.0.0.0');
    n := SizeOf(SockAddr);
    if FpBind(ListenSocket, @SockAddr, n) <> 0 then Exit;
    if FpListen(ListenSocket, 8) <> 0 then Exit;
    n := SizeOf(ClientAddr);
    ClientAddr := Default(TInetSockAddr);
    Socket := FpAccept(ListenSocket, @ClientAddr, @n);
    if Socket < 0 then Exit;
    Addr := ClientAddr.sin_addr;
    WriteLn(NetAddrToStr(Addr));
  finally
    CloseSocket(ListenSocket);
    ListenSocket := -1;
  end;
end;

procedure TListenThread.Abort;
begin
  Terminate;
  CloseSocket(ListenSocket);
end;

type TBeaconThread = class (TThread)
public
  var Port: UInt16;
  var ListenSocket: Int32;
  var Address: TInAddr;
  const BeaconId: Uint32 = (Ord('S') shl 24) or (Ord('S') shl 16) or (Ord('N') shl 8) or (Ord('B'));
  procedure Execute; override;
  procedure Abort;
  procedure Broadcast;
end;

procedure TBeaconThread.Execute;
  var Buffer: UInt32;
  var SockAddr, OtherAddr: TInetSockAddr;
  var n, r: Int32;
begin
  Address.s_addr := 0;
  ListenSocket := FpSocket(AF_INET, SOCK_DGRAM, 0);
  try
    SockAddr.sin_family := AF_INET;
    SockAddr.sin_port := htons(Port);
    SockAddr.sin_addr := StrToNetAddr('0.0.0.0');
    n := SizeOf(SockAddr);
    if FpBind(ListenSocket, @SockAddr, n) <> 0 then Exit;
    r := 0;
    while not Terminated do
    begin
      n := SizeOf(OtherAddr);
      r := FpRecvFrom(ListenSocket, @Buffer, SizeOf(Buffer), 0, @OtherAddr, @n);
      if Buffer <> BeaconId then Break;
      WriteLn('Beacon: ', NetAddrToStr(OtherAddr.sin_addr));
      Address := OtherAddr.sin_addr;
      Break;
    end;
  finally
    CloseSocket(ListenSocket);
  end;
end;

procedure TBeaconThread.Abort;
begin
  Terminate;
  FpShutDown(ListenSocket, SHUT_RDWR);
  CloseSocket(ListenSocket);
end;

procedure TBeaconThread.Broadcast;
  var Socket: Int32;
  var MyAddr, Addr: TInAddr;
  var i: Int32;
begin
  MyAddr := TUNet.GetMyIP;
  Addr := MyAddr;
  Socket := FpSocket(AF_INET, SOCK_DGRAM, 0);
  try
    for i := 1 to 255 do
    begin
      if i = MyAddr.s_bytes[4] then Continue;
      Addr.s_bytes[4] := i;
      FpSendTo(Socket, @BeaconId, SizeOf(BeaconId), 0, @Addr, SizeOf(Addr));
    end;
    WriteLn('Beacon Broadcast Complete');
  finally
    CloseSocket(Socket);
  end;
end;

function TUNet.Loopback: Boolean;
  var Addr: TInAddr;
  var Socket: Int32;
  var SockAddr: TInetSockAddr;
begin
  Addr := StrToNetAddr('127.0.0.1');
  Result := Connect(Addr);
end;

function TUNet.Connect(const Addr: TInAddr): Boolean;
  var Socket: Int32;
  var SockAddr: TInetSockAddr;
begin
  Socket := FpSocket(AF_INET, SOCK_STREAM, 0);
  SockAddr.sin_family := AF_INET;
  SockAddr.sin_port := htons(Port);
  SockAddr.sin_addr := Addr;
  if FpConnect(Socket, @SockAddr, SizeOf(SockAddr)) = 0 then
  begin
    _Socket := Socket;
    Exit(True);
  end;
  CloseSocket(Socket);
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
    r := FpRecv(_Socket, @Buffer, SizeOf(Buffer), 0);
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
  var Buffer: array[0..255] of AnsiChar;
begin
  GetHostName(@Buffer, SizeOf(Buffer));
  Result := Buffer;
end;

class function TUNet.GetMyIP: TInAddr;
{$if defined(WINDOWS)}
  type TInAddrArr = array[UInt32] of TInAddr;
  type PInAddrArr = ^TInAddrArr;
  var AddrArr: PInAddrArr;
  var Host: PHostEnt;
{$else}
  var r: Int32;
  var IfAddrs, a: PIfAddrs;
{$endif}
  var Addr: Sockets.TInAddr;
  var s: String;
  var i: Int32;
begin
  Result.s_addr := 0;
{$if defined(WINDOWS)}
  Host := GetHostByName(PAnsiChar(GetMyName));
  if not Assigned(Host) then Exit;
  AddrArr := PInAddrArr(Host^.h_Addr_List^);
  i := 0;
  while AddrArr^[i].S_addr <> 0 do
  try
    Addr := Sockets.PInAddr(@AddrArr^[i].S_addr)^;
    if (Result.s_addr = 0)
    or (Addr.s_bytes[1] = 192) then
    begin
      Result := Addr;
    end;
    //s := NetAddrToStr(Addr);
    //WriteLn(s);
  finally
    Inc(i);
  end;
{$else}
  r := GetIfAddrs(@IfAddrs);
  if r <> 0 then Exit;
  a := IfAddrs;
  while Assigned(a) do
  try
    if not Assigned(a^.ifa_addr) then Continue;
    Addr := a^.ifa_addr^.sin_addr;
    if (Result.s_addr = 0)
    or (Addr.s_bytes[1] = 192) then
    begin
      Result := Addr;
    end;
    //s := NetAddrToStr(Addr);
    //WriteLn(s);
  finally
    a := a^.ifa_next;
  end;
  FreeIfAddrs(IfAddrs);
{$endif}
end;

class function TUNet.Run(const APort: UInt16): TUNet;
begin
  Result := TUNet.Create(True);
  Result.Port := APort;
  Result.Start;
end;

class procedure TUNet.Test;
  {
  type TInAddrArr = array[UInt32] of TInAddr;
  type PInAddrArr = ^TInAddrArr;
  var Hints: TAddrInfo;
  var Info: PAddrInfo;
  var p: PAddrInfo;
  var LibHandle: TLibHandle;
  var ProcAddr: Pointer;
  var i, r: Int32;
  var Buffer: array[0..255] of AnsiChar;
  var HostName, s: String;
  var HostEnt: PHostEnt;
  var AddrArr: PInAddrArr;
  var Addr: Sockets.TInAddr;
  var IfAddrs, a: PIfAddrs;
  }
begin
  WriteLn(GetMyName);
  WriteLn(NetAddrToStr(GetMyIP));
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
    var MyAddr: TInAddr;
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
          if Beacon.Address.s_addr = 0 then
          begin
            Beacon.Free;
            Beacon := TBeaconThread.Create(True);
            Beacon.Port := Port;
            Beacon.Start;
            Continue;
          end;
          if Beacon.Address.s_addr > MyAddr.s_addr then Continue;
          if Connect(Beacon.Address) then Exit(True);
        end;
        Sleep(2000);
      end;
    finally
      WriteLn('Socket: ', _Socket);
      WriteLn('Finished connecting');
      Beacon.Abort;
      WriteLn('Beacon.Abort');
      Beacon.WaitFor;
      WriteLn('Beacon.WaitFor');
      Beacon.Free;
      WriteLn('Beacon.Free');
      Listen.Abort;
      WriteLn('Listen.Abort');
      Listen.WaitFor;
      WriteLn('Listen.WaitFor');
      Listen.Free;
      WriteLn('Listen.Free');
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
    CloseSocket(_Socket);
  end;
end;

procedure TUNet.Send(const Msg: String);
  var i: Int32;
begin
  if not IsConnected then Exit;
  i := 1;
  while i < Length(Msg) + 1 do
  begin
    i += FpSend(_Socket, @Msg[i], Length(Msg) + 2 - i, 0);
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
