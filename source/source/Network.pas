unit Network;

interface

uses
  SysUtils,
{$if defined(WINDOWS)}
  WinSock2,
{$elseif defined(UNIX)}
{$endif}
  Sockets,
  Classes;

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

type TUNet = class (TThread)
private
  var _Port: UInt16;
  var _Socket: Int32;
  procedure Search;
  procedure Listen;
  function GetIsConnected: Boolean;
public
  property Port: UInt16 read _Port write _Port;
  property IsConnected: Boolean read GetIsConnected;
  class function GetMyName: String;
  class function GetMyIP: TInAddr;
  class function Run(const APort: UInt16 = 6667): TUNet;
  class procedure Test;
  procedure Execute; override;
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
    InterlockedDecrement(Counter^);
  end;
end;

type TListenThread = class (TThread)
public
  var ListenSocket: Int32;
  var Socket: Int32;
  var Port: UInt16;
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
    WriteLn(NetAddrToStr(ClientAddr.sin_addr));
  finally
    CloseSocket(ListenSocket);
    ListenSocket := -1;
  end;
end;
procedure TListenThread.Abort;
begin
  CloseSocket(ListenSocket);
end;

procedure TUNet.Search;
  var BaseIP: TInAddr;
  var i, n: Int32;
  var SearchThread: TSearchThread;
  var SearchThreads: array of TSearchThread;
begin
  BaseIP := GetMyIP;
  if BaseIP.s_addr = 0 then
  begin
    BaseIP := StrToHostAddr('127.0.0.1');
    Exit;
  end;
  SearchThreads := nil;
  for i := 1 to 255 do
  begin
    BaseIP.s_bytes[4] := i;
    SearchThread := TSearchThread.Create(True);
    SearchThread.Addr := BaseIP;
    SearchThread.Port := Port;
    SearchThread.Counter := @n;
    SetLength(SearchThreads, Length(SearchThreads));
    SearchThreads[High(SearchThreads)] := SearchThread;
    InterlockedIncrement(n);
    SearchThread.Start;
  end;
  while n > 0 do Sleep(100);
  for i := 0 to High(SearchThreads) do
  begin
    if (_Socket = -1)
    and (SearchThreads[i].Socket > -1) then
    begin
      _Socket := SearchThreads[i].Socket;
      WriteLn(NetAddrToStr(SearchThreads[i].Addr));
    end;
    SearchThreads[i].Free;
  end;
end;

procedure TUNet.Listen;
  var ListenThread: TListenThread;
begin
  ListenThread := TListenThread.Create(True);
  try
    ListenThread.Port := Port;
    ListenThread.Start;
    while not ListenThread.Finished do
    begin
      Sleep(100);
    end;
    _Socket := ListenThread.Socket;
  finally
    ListenThread.Free;
  end;
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
{
  WriteLn(NetAddrToStr(GetMyIP));
  Exit;
  r := GetIfAddrs(@IfAddrs);
  if r <> 0 then Exit;
  a := IfAddrs;
  while Assigned(a) do
  begin
    if Assigned(a^.ifa_addr) then
    begin
      WriteLn(NetAddrToStr(a^.ifa_addr^.sin_addr));
    end;
    a := a^.ifa_next;
  end;
  FreeIfAddrs(IfAddrs);
  Exit;
  GetHostName(@Buffer, SizeOf(Buffer));
  HostName := Buffer;
  WriteLn(HostName);
  HostEnt := GetHostByName(PAnsiChar(HostName));
  AddrArr := PInAddrArr(HostEnt^.h_Addr_List^);
  i := 0;
  while AddrArr^[i].S_addr <> 0 do
  begin
    Addr := Sockets.PInAddr(@AddrArr^[i].S_addr)^;
    //specialize UArrAppend<Sockets.TInAddr>(_Addresses, Addr);
    s := NetAddrToStr(Addr);
    WriteLn(s);
    Inc(i);
  end;
  //LibHandle := PlatformLibOpen('libc.so.6', 1);
  //ProcFreeAddrInfo := TFreeAddrInfo(PlatformLibAddress(LibHandle, 'freeaddrinfo'));
  //ProcGetAddrInfo := TGetAddrInfo(PlatformLibAddress(LibHandle, 'getaddrinfo'));
  FillChar(Hints, SizeOf(Hints), 0);
  Hints.ai_family := AF_UNSPEC;
  Hints.ai_socktype := SOCK_STREAM;
  //Hints.ai_flags := AI_PASSIVE;
  //r := ProcGetAddrInfo('www.example.net', '3490', @Hints, @Info);
  //WriteLn(r);
  r := GetAddrInfo(PAnsiChar(HostName), nil, @Hints, @Info);
  if r <> 0 then Exit;
  p := Info;
  while (Assigned(p)) do
  begin
    if p^.ai_family = AF_INET then
    begin
      WriteLn(NetAddrToStr(p^.ai_addr^.sin_addr));
    end
    else
    begin
      WriteLn('ip6 address');
    end;
    p := p^.ai_next;
  end;
  //ProcFreeAddrInfo(Info);
  FreeAddrInfo(Info);
  //PlatformLibClose(LibHandle);
  }
end;

procedure TUNet.Execute;
begin
  _Socket := -1;
  while not Terminated do
  begin
    Search;

  end;
end;

end.
