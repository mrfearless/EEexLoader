;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------
include windows.inc

include user32.inc
include kernel32.inc
include psapi.inc
include version.inc

includelib user32.lib
includelib kernel32.lib
includelib psapi.lib
includelib version.lib

IFDEF EEEX_LUALIB
include lua52.inc
includelib lua523.lib ; nil value for lua_setglobal
includelib msvcrt12.lib
ENDIF

;------------------------------------------------------------------------------
; EEex.dll Prototypes
;------------------------------------------------------------------------------
EEexInitDll             PROTO                       ;
EEexInitGlobals         PROTO                       ;
EEexVerifyFunctions     PROTO                       ;
EEexSearchFunctions     PROTO                       ;
EEexFallbackAddresses   PROTO                       ;
EEexApplyCallPatch      PROTO :DWORD                ; dwAddressToPatch
EEexGameGlobals         PROTO                       ;

EEexLogInformation      PROTO :DWORD                ; dwType
EEexEEFileInformation   PROTO                       ;
EEexWriteFunctionsToIni PROTO                       ;

EEexDwordToAscii        PROTO :DWORD, :DWORD        ; dwValue, lpszAsciiString
EEexAsciiHexToDword     PROTO :DWORD                ; lpszAsciiHexString
EEexDwordToAsciiHex     PROTO :DWORD, :DWORD, :DWORD; dwValue, lpszAsciiHexString, bUppercase


;------------------------------------------------------------------------------
; EEex.dll Structures
;------------------------------------------------------------------------------
IFNDEF MODULEINFO
MODULEINFO              STRUCT
    lpBaseOfDll         LPVOID ?
    SizeOfImage         DWORD ?
    EntryPoint          LPVOID ?
MODULEINFO              ENDS  
ENDIF

IFNDEF LANGANDCODEPAGE
LANGANDCODEPAGE         STRUCT
   wLanguage            DW ?
   wCodepage            DW ?
LANGANDCODEPAGE         ENDS
ENDIF


.CONST
; EEexLogInformation dwType:
INFO_ALL                EQU 0
INFO_GAME               EQU 1
INFO_DEBUG              EQU 2
INFO_VERIFIED           EQU 3
INFO_SEARCHED           EQU 4
INFO_FALLBACK           EQU 5


.DATA
;------------------------------------------------------------------------------
; EEex.dll Initialized Data
;------------------------------------------------------------------------------
AppName                 DB "EEex.dll",0

;---------------------------
; Version Info
;---------------------------
szVerRoot               DB "\\",0
szLang                  DB "\VarFileInfo\Translation",0
szProductVersion        DB "\StringFileInfo\%04x%04x\ProductVersion",0
szProductName           DB "\StringFileInfo\%04x%04x\ProductName",0
szFileVersion           DB "%d.%d.%d.%d",0

;---------------------------
; Error Log Messages
;---------------------------
szErrorGetModuleInfo    DB "GetModuleInformation Failed",0
szErrorImageDosSig      DB "IMAGE_DOS_SIGNATURE Failed",0
szErrorImageNtSig       DB "IMAGE_NT_SIGNATURE Failed",0
szErrorSearchFunctions  DB "Cannot find or verify EE game lua functions and/or global variables.",13,10
                        DB "Possible unsupported version or a new build.",13,10
                        DB "The game will continue to launch, but EEex will not be enabled.",0

;---------------------------
; Module And Section Info
;---------------------------
hEEGameModule           DD 0
hEEGameProcess          DD 0
EEGameBaseAddress       DD 0
EEGameImageSize         DD 0

EEGameNoSections        DD 0
EEGameSectionTEXTSize   DD 0
EEGameSectionTEXTPtr    DD 0
EEGameSectionRDATASize  DD 0
EEGameSectionRDATAPtr   DD 0
EEGameSectionDATASize   DD 0
EEGameSectionDATAPtr    DD 0

EEGameAddressEP         DD 0
EEGameAddressStart      DD 0
EEGameAddressFinish     DD 0
modinfo                 MODULEINFO <>


;---------------------------
; Function Timers
;---------------------------
IFDEF EEEX_FUNCTION_TIMERS
T_EEexInitDll           DD 0
T_EEexSearchFunctions   DD 0
T_EEexVerifyFunctions   DD 0
ENDIF


;---------------------------
; Filenames 
;---------------------------
EEexExeFile             DB MAX_PATH DUP (0)
EEexIniFile             DB MAX_PATH DUP (0)
EEexLogFile             DB MAX_PATH DUP (0)


;---------------------------
; Version Buffers 
;---------------------------
EEGameProductVersion    DB 64 DUP (0)
EEGameProductName       DB 128 DUP (0)



.DATA?
;------------------------------------------------------------------------------
; EEex.dll Uninitialized Data
;------------------------------------------------------------------------------
hInstance               DD ?
hWnd                    DD ?
szFileVersionBuffer     DB 32 DUP (?)
szProductVersionBuffer  DB MAX_PATH DUP (?)
szProductNameBuffer     DB MAX_PATH DUP (?)










