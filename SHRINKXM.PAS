{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,P-,Q-,R-,S+,T-,V+,X+,Y+}
{$M 16384,0,655360}

Uses
  Dos,
  Crt,
  Strings;

Const
  MaxPatterns      = 255;
  MaxInstruments   = 128;
  MaxSamples       = 16;
  MaxNote          = 96;
  SizeOfFileBuffer = $2000;
  TempFileName     = '~temp~.bak';

Type
  XMHeader = RECORD
    ID          : Array [0..16] Of Char;   { ID text: 'Extended module: '                                                  }
    SongName    : Array [0..19] Of Char;   { Module name, padded with zeroes and 0x1a at the end                           }
    Always1Ah   : Byte;
    TrackerName : Array [1..20] Of Char;   { Tracker name                                                                  }
    Version     : Word;                    { (word) Version number, hi-byte major and low-byte minor                       }
    Size        : LongInt;                 { Header size                                                                   }
    SongLength  : Word;                    { (word) Song length (in patten order table)                                    }
    Restart     : Word;                    { (word) Restart position                                                       }
    NumChn      : Word;                    { (word) Number of channels (2,4,6,8,10,...,32)                                 }
    NumPat      : Word;                    { (word) Number of patterns (max 256)                                           }
    NumIns      : Word;                    { (word) Number of instruments (max 128)                                        }
    Flags       : Word;                    { (word) Flags: bit 0: 0 = Amiga frequency table 1 = Linear frequency table     }
    Tempo       : Word;                    { (word) Default tempo                                                          }
    BMP         : Word;                    { (word) Default BPM                                                            }
    Order       : Array [0..MaxPatterns] Of Byte;
  End;                                     { (byte) Pattern order table                                                    }

  XMPattHeader = Record
    Size     : LongInt;                    { (dword) Pattern header length                                                }
    Packing  : Byte;                       { (byte) Packing type (always 0)                                               }
    NumRows  : Word;                       { (word) Number of rows in pattern (1..256)                                    }
    PackSize : Word;                       { (word) Packed patterndata size                                               }
  End;

  XMNoteType = Record
    Note ,
    Ins  ,
    Vol  ,
    Eff  ,
    Dat  : Byte;
  End;

  XMInsHeader = Record
    Size     : LongInt;                    { (dword) Instrument size                                                      }
    Name     : Array [1..22] Of Char;      { (char) Instrument name                                                       }
    InsType  : Byte;                       { (byte) Instrument type (always 0)                                            }
    NumSmp   : Word;                       { (word) Number of samples in instrument                                       }
    SmpSize  : LongInt;                    { (dword) Sample header size                                                   }
  End;

  XMPatchHeader = Record
{    SmpNum   : Array [0..MaxNote] Of Byte; { (byte) Sample number for all notes                                           }
    SmpNum   : Array [1..MaxNote] Of Byte; { (byte) Sample number for all notes                                           }
    VolEnv   : Array [1..48] Of Byte;      { (byte) Points for volume envelope                                            }
    PanEnv   : Array [1..48] Of Byte;      { (byte) Points for panning envelope                                           }
    NumVol   : Byte;                       { (byte) Number of volume points                                               }
    NumPan   : Byte;                       { (byte) Number of panning points                                              }
    VolSus   : Byte;                       { (byte) Volume sustain point                                                  }
    VolLsp   : Byte;                       { (byte) Volume loop start point                                               }
    VolLep   : Byte;                       { (byte) Volume loop end point                                                 }
    PanSus   : Byte;                       { (byte) Panning sustain point                                                 }
    PanLsp   : Byte;                       { (byte) Panning loop start point                                              }
    PanLep   : Byte;                       { (byte) Panning loop end point                                                }
    VolTyp   : Byte;                       { (byte) Volume type: bit 0: On; 1: Sustain; 2: Loop                           }
    PanTyp   : Byte;                       { (byte) Panning type: bit 0: On; 1: Sustain; 2: Loop                          }
    VibTyp   : Byte;                       { (byte) Vibrato type                                                          }
    VibSweep : Byte;                       { (byte) Vibrato sweep                                                         }
    VibDepth : Byte;                       { (byte) Vibrato depth                                                         }
    Vibrate  : Byte;                       { (byte) Vibrato rate                                                          }
    VolFade  : Word;                       { (word) Volume fadeout                                                        }
    reserved : array [1..11] of Word;                       { (word) Reserved                                             }
  End;

  XMSmpHeader = Record
    Size       : LongInt;                  { (dword) Sample length                                                        }
    LoopStart  : LongInt;                  { (dword) Sample loop start                                                    }
    LoopLength : LongInt;                  { (dword) Sample loop length                                                   }
    Volume     : Byte;                     { (byte) Volume                                                                }
    FineTune   : Byte;                     { (byte) Finetune (signed byte -16..+15)                                       }
    WavType    : Byte;                     { (byte) Type: Bit 0-1: 0 = No loop, 1 = Forward loop, 2 = Ping-pong loop;     }
                                           {                    4: 16-bit sampledata                                      }
    Panning    : Byte;                     { (byte) Panning (0-255)                                                       }
    RelNote    : Byte;                     { (byte) Relative note number (signed byte)                                    }
    Reserved   : Byte;                     { (byte) Reserved                                                              }
    SampleName : Array [0..21] Of Char;    { (char) Sample name                                                           }
  End;

  UserInfoType = Record
    Patterns   ,
    Instruments,
    Samples    ,
    PatternData,
    SampleData ,
    SizeOfFile : LongInt;
  End;

Var
  InFile     ,
  OutFile    : File;
  MemStart   : LongInt;
  DoOptimizePatterns    ,
  DoOptimizeSamples     ,
  DoOptimizeSampleData  ,
  DoBackup              : Boolean;
  UserInfo   : Array[1..4] Of UserInfoType;

  {Mem cleaner starts here !}
  MemCleanStart : Byte;
  FileBuffer : Array[1..SizeOfFileBuffer] Of Byte;
  ProcessBar : Byte;
  XMHdr      : ^XMHeader;
  XMHdrNew   : ^XMHeader;

  XMPattHdr  : Array[0..MaxPatterns] Of ^XMPattHeader;
  XMPatt     : Array[0..MaxPatterns] Of Pointer;
  XMPattUsed : Array[0..MaxPatterns] Of Boolean;

  XMInsHdr   : Array[1..MaxInstruments] Of ^XMInsHeader;
  XMPatchHdr : Array[1..MaxInstruments] Of ^XMPatchHeader;

  XMSmpHdr   : Array[1..MaxInstruments, 1..MaxSamples] Of ^XMSmpHeader;
  XMSmpUsed  : Array[1..MaxInstruments, 1..MaxSamples] Of Boolean;
  XMSmpPos   : Array[1..MaxInstruments, 1..MaxSamples] Of LongInt;
  MemCleanEnd : Byte;
  {Mem cleaner ends here !}

Procedure ShowTestColor;
Var
  Ct : Byte;
Begin
  For Ct := 0 to 15 Do Begin
    TextColor(Ct);
    Write ('* ');
  End
End;

Procedure ShowCursor;
Var
  Reg : Registers;

Begin
  Reg.ah := 1;
  Reg.cx := $0607;
  Intr ($10, reg);
End;

Procedure HideCursor;
Var
  Reg : Registers;

Begin
  Reg.ah := 1;
  Reg.cx := $2000;
  Intr ($10, reg);
End;

Procedure MakeWindow (X1, Y1, Wide, Hight, BackColor, ForColor, TopColor : Byte; TopText : String);
Const
  Frame2 : String[7] = '╔╗║═╚╝';
  Frame : String[7] = '┌┐│─└┘';

Var
  Ct  ,
  Ct2 : Byte;

Begin
  Window (X1, Y1, X1+Wide, Y1+Hight);
  TextColor (ForColor);
  TextBackground (BackColor);
  Clrscr;
  Window (X1, Y1, X1+Wide+1, Y1+Hight);
  For Ct := 2 To Wide Do Begin
    GotoXY (Ct, 1);        Write (Frame[4]);
    GotoXY (Ct, Hight+1);  Write (Frame[4]);
  End;

  For Ct := 2 To Hight Do Begin
    GotoXY (1, Ct);        Write (Frame[3]);
    GotoXY (Wide+1, Ct);   Write (Frame[3]);
  End;

  GotoXY (1,1);            Write (Frame[1]);
  GotoXY (Wide+1,1);       Write (Frame[2]);
  GotoXY (1,Hight+1);      Write (Frame[5]);
  GotoXY (Wide+1,Hight+1); Write (Frame[6]);

  GotoXY (Wide - ((Wide + Length (TopText)) DIV 2), 1);
  TextColor (TopColor);
  Write (' '+TopText+' ');
  Window (X1+1, Y1+1, X1+Wide-1, Y1+Hight+1);
End;

Procedure InitWindow(X1, Y1, Wide, Hight, BackColor, ForColor, TopColor : Byte; TopText : String);
Begin
  MakeWindow(X1, Y1, Wide, Hight, BackColor, ForColor, TopColor, TopText);
  TextColor(LightCyan);
{  For Ct := 1 To 9 Do
    WriteLn('▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒');
  GotoXY(1, 2);
  WriteLn('▒      ▒▒▒                    ▒       ▒▒▒▒                    ▒▒▒▒▒▒▒▒▒');
  WriteLn('▒        ▒  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒          ▒   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒');
  WriteLn('▒▒▒▒▒▒▒▒▒▒        ▒           ▒       ▒           ▒          ▒        ▒');
  WriteLn('▒      ▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒   ▒▒▒▒▒       ▒▒▒▒       ▒▒       ▒');
  WriteLn('▒     ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒   ▒▒▒▒▒       ▒▒▒▒       ▒▒       ▒');
  WriteLn('▒     ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒   ▒▒▒▒▒       ▒▒▒▒       ▒▒       ▒');
  WriteLn('▒                 ▒   ▒▒                    ▒   ▒▒                ▒   ▒');
  Write  ('▒           ▒▒▒▒      ▒▒           ▒▒▒▒▒▒▒      ▒▒         ▒          ▒');}
  TextColor(White);
  GotoXY(02, 02); Write('MODULE');
  GotoXY(32, 02); Write('TRACKER');
  GotoXY(02, 04); Write('CHANNELS');
  GotoXY(32, 04); Write('SONGLENGTH');
  GotoXY(11, 06); Write('PATTERNS');
  GotoXY(20, 06); Write('INSTRUMENTS');
  GotoXY(32, 06); Write('SAMPLES');
  GotoXY(40, 06); Write('PATTERNDATA');
  GotoXY(52, 06); Write('SAMPLEDATA');
  GotoXY(63, 06); Write('FILESIZE');
  GotoXY(02, 08); Write('BEFORE');
  GotoXY(02, 10); Write('AFTER');
  GotoXY(02, 12); Write('SAVED');
{  WriteLn; Write(' ---------------------------------------------------------------------');}
  GotoXY(02, 14); Write('TOTAL SAVED');
{  WriteLn; Write(' =====================================================================');}
  GotoXY(02, 16); Write('MAKE BACKUPS [ ]   OPTIMIZE : PATTERNS [ ] SAMPLEDATA [ ] SAMPLES [ ]');
  GotoXY(02, 18); Write('MEMORY FREE');
  GotoXY(21, 18); Write('KB');
  GotoXY(25, 18); Write('MEMORY USED');
  GotoXY(47, 18); Write('KB');
  GotoXY(51, 18); Write('PROCESSED');
  Window (X1+1, Y1+1, X1+Wide-1, Y1+Hight-1);
End;

Procedure RestoreWindow;
Begin
  Window (1, 1, 80, 25);
  NormVideo;
End;

Procedure UpdateFreeMem;
Var
  X ,
  Y : Byte;

Begin
  X := WhereX;
  Y := WhereY;
  GotoXY(17, 18);
  Write (MemAvail DIV 1024:3);
  GotoXY(43, 18);
  Write ((MemStart - MemAvail) DIV 1024:3);
  GotoXY(X, Y);
End;

Procedure UpdateUserInfo (DoSub : Boolean);
Var
  Ct : Byte;

Begin
  If DoSub Then Begin
    UserInfo[3].Patterns    := UserInfo[1].Patterns    - UserInfo[2].Patterns;
    UserInfo[3].Instruments := UserInfo[1].Instruments - UserInfo[2].Instruments;
    UserInfo[3].Samples     := UserInfo[1].Samples     - UserInfo[2].Samples;
    UserInfo[3].Patterndata := UserInfo[1].Patterndata - UserInfo[2].Patterndata;
    UserInfo[3].Sampledata  := UserInfo[1].Sampledata  - UserInfo[2].Sampledata;
    UserInfo[3].SizeOfFile  := UserInfo[1].SizeOfFile  - UserInfo[2].SizeOfFile;

    Inc(UserInfo[4].Patterns   , UserInfo[3].Patterns);
    Inc(UserInfo[4].Instruments, UserInfo[3].Instruments);
    Inc(UserInfo[4].Samples    , UserInfo[3].Samples);
    Inc(UserInfo[4].Patterndata, UserInfo[3].Patterndata);
    Inc(UserInfo[4].Sampledata , UserInfo[3].Sampledata);
    Inc(UserInfo[4].SizeOfFile , UserInfo[3].SizeOfFile);
  End;
  For Ct := 1 To 4 Do Begin
    GotoXY(16, (Ct-1)*2+8); Write(UserInfo[Ct].Patterns:3);
    GotoXY(28, (Ct-1)*2+8); Write(UserInfo[Ct].Instruments:3);
    GotoXY(36, (Ct-1)*2+8); Write(UserInfo[Ct].Samples:3);
    GotoXY(44, (Ct-1)*2+8); Write(UserInfo[Ct].Patterndata:7);
    GotoXY(55, (Ct-1)*2+8); Write(UserInfo[Ct].Sampledata:7);
    GotoXY(64, (Ct-1)*2+8); Write(UserInfo[Ct].SizeOfFile:7);
  End;
End;

Function UpStr(InStr : String; DoFix : Boolean) : String;
Var
  Ct : Byte;

Begin
  For Ct := 1 To Length(InStr) Do
    If (InStr[Ct] = '/') AND DoFix Then
      InStr[Ct] := '-'
    Else
      InStr[Ct] := Upcase(InStr[Ct]);
  UpStr := InStr;
End;

Procedure UpdateProcessBar;
Var
  Ct : Byte;

Begin
  Inc (ProcessBar);
  GotoXY(61, 18);
  For Ct := 1 To ProcessBar Do Write('■');
End;

Procedure CleanUp (DelFile : Boolean);
Begin
  Close (InFile);
  Close (OutFile);
  If DelFile Then Erase (OutFile);
  ShowCursor;
End;

Procedure LastInitText;
Var
  TheY : Byte;

Begin
  WriteLn;
  TheY := WhereY;
  MakeWindow (8, WhereY, 64, 4, LightBlue, White, Yellow+blink, 'How to FRELLY register this product');
  TextColor (White     );  Write   ('To register this program, please fill out the form ');
  TextColor (LightGreen);  Write   ('REGISTER.TXT');
  TextColor (White     );  Write   ('and sent it via E-mail to ');
  TextColor (LightGreen);  Write   ('_BUGSY@USA.NET');
  TextColor (White     );  Write   (', goto our home page at');
  TextColor (LightGreen);  Write   ('WWW.CYBERNET.DK/USERS/BUGSY ');
  TextColor (White     );  Write   ('or just send me a nice ');
  TextColor (LightGreen);  Write   ('POSTCARD !!!');
  Window(1, 1, 80, 25);
  NormVideo;
  GotoXY (18, TheY + 5);
  TextColor (LightRed);  Write   ('See the file ');
  TextColor (LightBlue); Write   ('SHRINKXM.TXT ');
  TextColor (LightRed);  WriteLn ('for more detailes.');
  WriteLn;
End;

Procedure Error (Err : Byte);
Begin
  WriteLn;
  If Err > 1 Then Begin
    RestoreWindow;
    GotoXY(1, 23);
  End;
  TextColor(White);
  Write ('   ERROR (',Err,') : ');
  Case Err Of
    0 : WriteLn ('No XM files found !');
    1 : Begin
          GotoXY (1, WhereY);
          WriteLn ('USAGE : SHRINKXM.EXE xmfilename [-NP] [-NS] [-NSL] [-NB]');
          WriteLn;
          WriteLn ('-NP  Do NOT remove unused patterns');
          WriteLn ('-NS  Do NOT remove unused samples');
          WriteLn ('-NSL Do NOT clip at end of sampleloops');
          WriteLn ('-NB  Do NOT make any backup files');
          WriteLn;
          WriteLn('Wildcards are allowed in the xmfilename.');
          WriteLn('Like : SHRINKXM.EXE jz-*.xm');
          TextColor (LightRed);
          LastInitText;
        End;
    2 : WriteLn ('Can''t open xmfile');
    3 : WriteLn ('Can''t create tempfile');
    4 : WriteLn ('Can''t read XM header');
    5 : WriteLn ('This file is not an XM file');
    6 : WriteLn ('No patterns found');
    7 : WriteLn ('Can''t read pattern');
    8 : WriteLn ('No instruments found');
    9 : WriteLn ('Can''t read instrument');
   10 : WriteLn ('Can''t write XM header');
   11 : WriteLn ('Can''t write XM pattern header');
   12 : WriteLn ('Can''t write XM pattern');
   14 : WriteLn ('Can''t write instrument header');
   15 : WriteLn ('Can''t write instrument patch');
   16 : WriteLn ('Can''t write sample header');
   17 : WriteLn ('Can''t read sample data');
   18 : WriteLn ('Can''t write sample data');
   20 : WriteLn ('Can''t read sample header');
   21 : WriteLn ('Can''t make backup file');
   22 : WriteLn ('Can''t rename optimized file');
   23 : WriteLn ('Can''t erase original xmfile file');
  Else
    WriteLn ('Can ''t find error text, programmer is a jerk!');
  End;
  CleanUp (True);
  Halt (Err);
End;

Function HeapErrorTest (Size: Word): Integer; far;
Begin
  { If Size <> 0 then it doesn't matter what you return, since }
  { size is only <> 0 when an allocate error occures !         }
  If Size <> 0 Then Begin
    RestoreWindow;
    GotoXY(1, 23);
    TextColor(White);
    WriteLn ('   ERROR : Can''t allocate ',Size ,' bytes. Not enough memory. Halting program.');
    CleanUp (True);
    Halt (100);
  End;
  UpdateFreeMem;        {Is this just smart or what ? :-) }
End;

Procedure ReadHeader;
Var
  Count : Word;

Begin
  New (XMHdr);
  New (XMHdrNew);
  BlockRead (InFile, XMHdr^, SizeOf(XMHeader), Count);
  If Count <> SizeOf(XMHeader) Then Error (4);
  Move (XMHdr^, XMHdrNew^, SizeOf (XMHeader));

  If XMHdr^.ID <> 'Extended Module: ' Then Error (5);
  XMHdr^.Always1Ah := 0; {Make a ZERO at the end of SongName ;-) }
  GotoXY(11, 02); Write (StrPas(XMHdr^.SongName));
  GotoXY(43, 02); Write (Copy (XMHdr^.TrackerName, 1 ,20));
  GotoXY(11, 04); Write (XMHdr^.NumChn:2);
  GotoXY(43, 04); Write (XMHdr^.SongLength:3);

  UserInfo[1].Patterns    := XMHdr^.NumPat;
  UserInfo[1].Instruments := XMHdr^.NumIns;
  UserInfo[2].Instruments := XMHdr^.NumIns;    {INS WILL NOT BE OPTIMIZED YET}
  UserInfo[1].SizeOfFile  := FileSize(InFile);
  UpdateUserInfo (False);
End;

Procedure ReadPatterns;
Var
  PatCt ,
  Count : Word;

Begin
  If XMHdr^.NumPat = 0 Then Error (6);
  For PatCt := 0 To XMHdr^.NumPat-1 Do Begin
    New (XMPattHdr[PatCt]);
    BlockRead (InFile, XMPattHdr[PatCt]^, SizeOf (XMPattHeader), Count);
    If Count <> SizeOf (XMPattHeader) Then Error (7);
    If XMPattHdr[PatCt]^.PackSize <> 0 Then Begin
      Inc (UserInfo[1].PatternData, XMPattHdr[PatCt]^.PackSize);
      UpdateUserInfo (False);
      GetMem (XMPatt[PatCt], XMPattHdr[PatCt]^.PackSize);
      BlockRead (InFile, XMPatt[PatCt]^, XMPattHdr[PatCt]^.PackSize, Count);
      If Count <> XMPattHdr[PatCt]^.PackSize Then Error (7);
    End
    Else
      XMPatt[PatCt] := NIL;
  End;
End;

Procedure ReadInstruments;
Var
  InsCt ,
  SmpCt ,
  Count : Word;

Begin
  If XMHdr^.NumIns = 0 Then Error (8);
  For InsCt := 1 To XMHdr^.NumIns Do Begin
    New (XMInsHdr[InsCt]);
    BlockRead (InFile, XMInsHdr[InsCt]^, SizeOf (XMInsHeader), Count);
    If Count <> SizeOf (XMInsHeader) Then Error (9);
    If XMInsHdr[InsCt]^.NumSmp <> 0 Then Begin
      UpdateUserInfo (False);
      New (XMPatchHdr[InsCt]);
      BlockRead (InFile, XMPatchHdr[InsCt]^, SizeOf (XMPatchHeader), Count);
      If Count <> SizeOf (XMPatchHeader) Then Error (9);
      For SmpCt := 1 To XMInsHdr[InsCt]^.NumSmp Do Begin
        New (XMSmpHdr[InsCt][SmpCt]);
        BlockRead (InFile, XMSmpHdr[InsCt][SmpCt]^, SizeOf (XMSmpHeader), Count);
        If Count <> SizeOf (XMSmpHeader) Then Error (20);
        Inc(UserInfo[1].Samples, Byte(XMSmpHdr[InsCt][SmpCt]^.Size <> 0));
        Inc(UserInfo[1].Sampledata, XMSmpHdr[InsCt][SmpCt]^.Size);
        UpdateUserInfo (False);
        If NOT DoOptimizeSamples Then XMSmpUsed[InsCt][SmpCt] := True;
      End;
      For SmpCt := 1 To XMInsHdr[InsCt]^.NumSmp Do Begin
        XMSmpPos[InsCt][SmpCt] := FilePos(InFile);
        Seek(InFile, FilePos(InFile) + XMSmpHdr[InsCt][SmpCt]^.Size); {Step over sampledata}
      End;
    End;
  End;

  BlockRead (InFile, InsCt, SizeOf(InsCt), Count);
  If Count <> 0 Then Begin
    Write ('WARNING       : XM was larger than expected ');
    TextColor (White + Blink);
    WriteLn ('!');
    TextColor (White);
  End;
End;

Procedure OptimizePatterns;
Var
  PatCt    ,
  OrderCt  ,
  NewPos   : Word;

Begin
  NewPos := 0;

  If DoOptimizePatterns Then {Mark used patterns}
    For PatCt := 0 To XMHdr^.SongLength-1 Do
      XMPattUsed[XMHdr^.Order[PatCt]] := True
  Else
    For PatCt := 0 To XMHdr^.NumPat-1 Do
      XMPattUsed[PatCt] := True;

  For OrderCt := 0 To XMHdr^.SongLength-1 Do
    If XMPattHdr[XMHdr^.Order[OrderCt]] = NIL Then
      XMPattUsed[XMHdr^.Order[OrderCt]] := False;

  For PatCt := 0 To MaxPatterns Do
    If XMPattUsed[PatCt] Then Begin
      For OrderCt := 0 To XMHdrNew^.SongLength-1 Do
        If XMHdr^.Order[OrderCt] = PatCt Then
          XMHdrNew^.Order[OrderCt] := NewPos;
      Inc (NewPos);
      UserInfo[2].Patterns := NewPos;
      Inc (UserInfo[2].Patterndata, XMPattHdr[PatCt]^.PackSize);
      UpdateUserInfo (False);
    End;

  {To eleminate zero patterns at end of song, yet still make them playable}
  While XMPattHdr[NewPos-1] = NIL Do
    Dec(NewPos);

  XMHdrNew^.NumPat := NewPos;
  UserInfo[2].Patterns := XMHdrNew^.NumPat;
  UpdateUserInfo (False);
End;

Procedure OptimizeInstruments;
Type
  PPtr = Array[1.. 32{channels} * 256{patternlength} * 5 {notesize}] Of Byte;

Var
  PatCt  ,
  Ct     ,
  Ct2    ,
  TempCt : Word;
  PP     : ^PPtr; {Total smart, don't you agree ?}
  TempPP : Byte;
  XMNote : XMNoteType;

Begin
  For PatCt := 0 To XMHdr^.NumPat-1 Do
    If XMPattUsed[PatCt] AND (XMPattHdr[PatCt]^.PackSize > 0) Then Begin
      PP := XMPatt[PatCt];
      Ct := 1;
      Repeat
        FillChar (XMNote, SizeOf(XMNote), 0);
        TempPP := PP^[Ct];
        If TempPP AND $80 = $80 Then Begin
          inc (Ct);
          If TempPP AND  1 =  1 Then Begin XMNote.Note := PP^[Ct] ; Inc (Ct); End;
          If TempPP AND  2 =  2 Then Begin XMNote.Ins  := PP^[Ct] ; Inc (Ct); End;
          If TempPP AND  4 =  4 Then Begin XMNote.Vol  := PP^[Ct] ; Inc (Ct); End;
          If TempPP AND  8 =  8 Then Begin XMNote.Eff  := PP^[Ct] ; Inc (Ct); End;
          If TempPP AND 16 = 16 Then Begin XMNote.Dat  := PP^[Ct] ; Inc (Ct); End;
        End
        Else Begin
          XMNote.Note := PP^[Ct];
          XMNote.Ins  := PP^[Ct+1];
          XMNote.Vol  := PP^[Ct+2];
          XMNote.Eff  := PP^[Ct+3];
          XMNote.Dat  := PP^[Ct+4];
          Inc (Ct,5);
        End;
             {Play sample ?}       {Any samples found in the patch ?}      {Is it a VALID note ?}
        If (DoOptimizeSamples) AND
           (XMNote.Ins <> 0) AND
           (XMNote.Note > 0) AND
           (XMNote.Note <= MaxNote) AND {Doc says MaxNote is 0-71, that's wrong; It's 1-96 !!}
           (XMInsHdr[XMNote.Ins] <> NIL) AND
           (XMInsHdr[XMNote.Ins]^.NumSmp <> 0) AND
           (XMPatchHdr[XMNote.Ins]^.SmpNum[XMNote.Note]+1 <= XMInsHdr[XMNote.Ins]^.NumSmp) AND
           (XMSmpHdr[XMNote.Ins][XMPatchHdr[XMNote.Ins]^.SmpNum[XMNote.Note]+1]^.Size <> 0)
        Then
           XMSmpUsed[XMNote.Ins][XMPatchHdr[XMNote.Ins]^.SmpNum[XMNote.Note]+1] := True;
      Until Ct >= XMPattHdr[PatCt]^.PackSize;
    End;

  For Ct := 1 To MaxInstruments Do Begin
    TempCt := 0;
    For Ct2 := 1 To MaxSamples Do
      If XMSmpUsed[Ct][Ct2] Then Inc(TempCt);
    Inc (UserInfo[2].Samples, TempCt);
{    If TempCt <> 0 Then Inc(UserInfo[2].Instruments);}
    UpdateUserInfo (False);
  End;
End;

Procedure OptimizeSampleData;
Var
  InsCt ,
  SmpCt : Word;

Begin
  If DoOptimizeSampleData Then Begin
    For InsCt := 1 To MaxInstruments Do
      For SmpCt := 1 To MaxSamples Do
        If XMSmpUsed[InsCt][SmpCt] Then Begin
          If (XMSmpHdr[InsCt][SmpCt]^.WavType OR ($FF-$03) <> ($FF-$03)) Then
            XMSmpHdr[InsCt][SmpCt]^.Size := XMSmpHdr[InsCt][SmpCt]^.LoopStart + XMSmpHdr[InsCt][SmpCt]^.LoopLength;
          UpdateUserInfo (False);
          Inc (UserInfo[2].Sampledata, XMSmpHdr[InsCt][SmpCt]^.Size);
        End;
  End Else
    UserInfo[2].Sampledata := UserInfo[1].Sampledata;

  UpdateUserInfo (False);
End;

Procedure WriteHeader;
Var
  Count : Word;

Begin
  XMHdr^.Always1Ah := $1A;      {Restore it :-) }
  BlockWrite (OutFile, XMHdrNew^, SizeOf(XMHeader), Count);
  If Count <> SizeOf(XMHeader) Then Error (10);
End;

Procedure WritePatterns;
Var
  Ct    ,
  Count : Word;

Begin
  For Ct := 0 To MaxPatterns Do
    If XMPattUsed[Ct] Then Begin
      BlockWrite (OutFile, XMPattHdr[Ct]^, SizeOf (XMPattHeader), Count);
      If Count <> SizeOf(XMPattHeader) Then Error (11);
      If XMPatt[Ct] <> NIL Then Begin
        BlockWrite (OutFile, XMPatt[Ct]^, XMPattHdr[Ct]^.PackSize, Count);
        If Count <> XMPattHdr[Ct]^.PackSize Then Error (12);
      End;
    End;
End;

Procedure WriteInstruments;
Var
  Ct           ,
  Ct2          ,
  Count        ,
  Written      : Word;
  SamplePos    : LongInt;

Begin
  For Ct := 1 To XMHdr^.NumIns Do Begin
    BlockWrite (OutFile, XMInsHdr[Ct]^, SizeOf(XMInsHeader), Count);
    If Count <> SizeOf(XMInsHeader) Then Error (14);
    If XMInsHdr[Ct]^.NumSmp <> 0 Then Begin
      BlockWrite (OutFile, XMPatchHdr[Ct]^, SizeOf(XMPatchHeader), Count);
      If Count <> SizeOf(XMPatchHeader) Then Error (15);
      For Ct2 := 1 To XMInsHdr[Ct]^.NumSmp Do Begin
        If NOT XMSmpUsed[Ct][Ct2] Then XMSmpHdr[Ct][Ct2]^.Size := 0;
        BlockWrite (OutFile, XMSmpHdr[Ct][Ct2]^, SizeOf(XMSmpHeader), Count);
        If Count <> SizeOf(XMSmpHeader) Then Error (16);
      End;
      For Ct2 := 1 To XMInsHdr[Ct]^.NumSmp Do
        If XMSmpUsed[Ct][Ct2] Then Begin
          SamplePos := 0;
          Seek (InFile, XMSmpPos[Ct][Ct2]);
          Repeat
            If XMSmpHdr[Ct][Ct2]^.Size - SamplePos >= SizeOfFileBuffer Then Begin
              BlockRead(InFile, FileBuffer, SizeOfFileBuffer, Count);
              If Count <> SizeOfFileBuffer Then Error (17);
            End Else Begin
              BlockRead(InFile, FileBuffer, XMSmpHdr[Ct][Ct2]^.Size - SamplePos, Count);
              If Count <> XMSmpHdr[Ct][Ct2]^.Size - SamplePos Then Error (17);
            End;
            BlockWrite (OutFile, FileBuffer, Count, Written);
            If Count <> Written Then Error (18);
            SamplePos := SamplePos + Written;
          Until SamplePos >= XMSmpHdr[Ct][Ct2]^.Size;
        End;
    End;
  End;
End;

Procedure ShrinkXM(Path : String; FileName : String);
Var
  DelFile : File;
  TempStr : String;

Begin
  Assign (InFile, Path + FileName);
  Assign (OutFile,Path + TempFileName);
  FileMode := 0;
  Reset (InFile, 1);
  If IOResult <> 0 Then Error (2);
  FileMode := 2;
  ReWrite (OutFile, 1);
  If IOResult <> 0 Then Error (3);

  UpdateProcessBar;
  ReadHeader;          UpdateProcessBar;
  ReadPatterns;        UpdateProcessBar;
  ReadInstruments;     UpdateProcessBar;

  OptimizePatterns;    UpdateProcessBar;
  OptimizeInstruments; UpdateProcessBar;
  OptimizeSampleData;  UpdateProcessBar;

  WriteHeader;         UpdateProcessBar;
  WritePatterns;       UpdateProcessBar;
  WriteInstruments;    UpdateProcessBar;

  UserInfo[2].SizeOfFile := FileSize(OutFile);
  UpdateUserInfo (True);
  RestoreWindow;
  CleanUp (False);

  If DoBackup Then Begin
    TempStr := Path + Copy(FileName,1,Pos('.',FileName))+'BAK';
    Assign (DelFile, TempStr);
    Erase  (DelFile);
    If (IOResult <> 0) Then; {Just reads the IOResult, otherwise an error occures in next file command}

    Assign (DelFile, Path + FileName);
    Rename (DelFile, TempStr);
    If (IOResult <> 0) Then Error(21);
  End Else Begin
    Assign (DelFile, Path + FileName);
    Erase (DelFile);
    If (IOResult <> 0) Then Error(23);
  End;

  Assign (DelFile, Path + TempFileName);
  Rename (DelFile, Path + FileName);
  If IOResult <> 0 Then Error(22);
  GotoXY(1, 23);
End;

Procedure Init;
Var
  Param : String;
  Ct    : Word;

Begin
  Clrscr;
  Write('  ');
  TextBackGround(Red);
  TextColor (White);
  Write ('─┼──');
  NormVideo;
  TextColor (LightBlue);
  Write (' FAST TRACKER XM OPTIMIZER v1.2 CARDWARE 1997 by ');
{  Write (' FAST TRACKER XM OPTIMIZER v1.1 ');
  TextColor (LightRed);
  Write ('BETA');
  TextColor (LightBlue);
  Write (' CARDWARE 1997 by ');}
  TextColor (Yellow);
  Write ('BUGSY/OBSESSiON ');
  TextBackGround(Red);
  TextColor (White);
  WriteLn ('─┼──'#10#13);
  NormVideo;
  TextColor(White);
  If ParamCount < 1 Then Error (1);

  Param := '';
  For Ct := 2 To ParamCount Do Param := Param + UpStr(ParamStr(Ct), True);
  DoOptimizePatterns   := Pos('-NP', Param)  = 0;
  DoOptimizeSampleData := Pos('-NSL', Param) = 0;
  DoOptimizeSamples    := Pos('-NS', Param)  = 0;
  DoBackup             := Pos('-NB', Param)  = 0;
  Delete(Param, Pos('-NP' , Param), 3);
  Delete(Param, Pos('-NSL', Param), 4);
  Delete(Param, Pos('-NS' , Param), 3);
  Delete(Param, Pos('-NB' , Param), 3);
  If Length(Param) <> 0 Then Error(1);
  HeapError  := @HeapErrorTest;
End;

Procedure InitScreen(InStr : String);
Begin
  HideCursor;
  InitWindow (4, 3, 72, 19, LightBlue, White, LightGreen, InStr);
  TextColor(Yellow);
  If DoBackup              Then Begin GotoXY(16, 16); Write('X'); End;
  If DoOptimizePatterns    Then Begin GotoXY(42, 16); Write('X'); End;
  If DoOptimizeSampleData  Then Begin GotoXY(57, 16); Write('X'); End;
  If DoOptimizeSamples     Then Begin GotoXY(69, 16); Write('X'); End;
  MemStart   := MemAvail;
  UpdateFreeMem;
End;

Procedure InitMem;
Begin
  FillChar(UserInfo, SizeOf(UserInfoType)*3,0);
  FillChar(MemCleanStart, Ofs(MemCleanEnd) - Ofs(MemCleanStart),0);
End;

Procedure DoIt;
Type
  DirDataType = Record
    PrevPtr : Pointer;
    FileName : String[12];
  End;

Var
  DirInfo : SearchRec;
  P     : PathStr;
  D     : DirStr;
  N     : NameStr;
  E     : ExtStr;
  HeapState : Pointer;
  DirData : ^DirDataType;
  OldPtr : Pointer;

Begin
  OldPtr := Nil;
  DirData := Nil;
  FSplit(ParamStr(1), D, N, E);
  FindFirst(Paramstr(1), AnyFile, DirInfo);
  InitScreen('Reading Directory');
  While DosError = 0 Do Begin
    If (DirInfo.Attr AND (Hidden+SysFile+VolumeID+Directory)=0) AND (Pos(DirInfo.name,'.BAK') = 0) Then
    Begin
      New (DirData);
      DirData^.PrevPtr := OldPtr;
      OldPtr := DirData;
      DirData^.FileName := DirInfo.Name;
    End;
    FindNext(DirInfo);
  End;
  If DirData = Nil Then Error (0);

  Mark(HeapState); {Mark heap position so we can restore it in next optimize}
  Repeat
    InitMem;
    InitScreen('Optimizing XM file : ' + UpStr(DirData^.FileName, False));
    ShrinkXM(D,DirData^.FileName);
    Release(HeapState);
    DirData := DirData^.PrevPtr;
  Until DirData = Nil;
  WriteLn ('   All files done !');
End;

Begin
  Init;
  DoIt;
End.
