unit Network;

interface

uses
  SysUtils,
{$if defined(WINDOWS)}
  WinSock2,
{$elseif defined(UNIX)}
{$endif}
  Sockets;

type
  {
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
  }

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
): Int32; cdecl; external 'libc' name 'getifaddrs';
procedure FreeIfAddrs(
  const IfaAdrs: PIfAddrs
); cdecl; external 'libc' name 'freeifaddrs';
function GetAddrInfo(
  const Node: PAnsiChar;
  const Service: PAnsiChar;
  const Hints: PAddrInfo;
  const Results: PPAddrInfo
): Integer; cdecl; external 'libc' name 'getaddrinfo';
procedure FreeAddrInfo(
  const AddrInfo: PAddrInfo
); cdecl; external 'libc' name 'freeaddrinfo';
function GetHostName(
  const Name: PAnsiChar;
  const Len: Integer
): Integer; external 'libc' name 'gethostname';
function GetHostByName(
  const Name: PAnsiChar
): PHostEnt; external 'libc' name 'gethostbyname';

function PlatformLibOpen(Name: PAnsiChar; Flags: LongInt): TLibHandle; cdecl; external 'dl' name 'dlopen';
function PlatformLibClose(Handle: TLibHandle): LongInt; cdecl; external 'dl' name 'dlclose';
function PlatformLibAddress(Handle: TLibHandle; ProcName: PAnsiChar): Pointer; cdecl; external 'dl' name 'dlsym';
{$endif}

type TUNet = class
public
  class function GetMyName: String;
  class function GetMyIP: TInAddr;
  class procedure Test;
end;

implementation

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
  Result.s_addr := $00000000;
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
  begin
    if Assigned(a^.ifa_addr) then
    begin
      Addr := a^.ifa_addr^.sin_addr;
      if (Result.s_addr = 0)
      or (Addr.s_bytes[1] = 192) then
      begin
        Result := Addr;
      end;
      //s := NetAddrToStr(Addr);
      //WriteLn(s);
    end;
    a := a^.ifa_next;
  end;
  FreeIfAddrs(IfAddrs);
{$endif}
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
  //192.168.1.129
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

end.
