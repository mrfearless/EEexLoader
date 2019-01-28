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



;------------------------------------------------------------------------------
; EEex.dll Prototypes
;------------------------------------------------------------------------------
EEexInitDll             PROTO
EEexInitGlobals         PROTO
EEexInitLog             PROTO
EEexVerifyFunctions     PROTO
EEexVerifyPattern       PROTO :DWORD, :DWORD, :DWORD
EEexSearchFunctions     PROTO
EEexApplyCallPatch      PROTO :DWORD
EEexWriteFunctionsToIni PROTO
EEexLogInformation      PROTO :DWORD
EEexEEFileInformation   PROTO
EEexDwordToAscii        PROTO :DWORD, :DWORD


;------------------------------------------------------------------------------
; Other Function Prototypes (Lua)
;------------------------------------------------------------------------------
Lua_pushnumberProto     TYPEDEF PROTO C ptr_lua_State:DWORD, lua_Number:DWORD
Lua_pushnumberPtr       TYPEDEF PTR Lua_pushnumberProto
Lua_pushclosureProto    TYPEDEF PROTO C ptr_lua_State:DWORD, lua_CFunction:DWORD, n:DWORD
Lua_pushclosurePtr      TYPEDEF PTR Lua_pushclosureProto
Lua_tolstringProto      TYPEDEF PROTO C ptr_lua_State:DWORD, index:DWORD, ptr_len:DWORD
Lua_tolstringPtr        TYPEDEF PTR Lua_tolstringProto
Lua_setglobalProto      TYPEDEF PROTO C ptr_lua_State:DWORD, ptr_name:DWORD
Lua_setglobalPtr        TYPEDEF PTR Lua_setglobalProto
Lua_tonumberxProto      TYPEDEF PROTO C ptr_lua_State:DWORD, index:DWORD, ptr_isnum:DWORD
Lua_tonumberxPtr        TYPEDEF PTR Lua_tonumberxProto
LuaL_loadstringProto    TYPEDEF PROTO C ptr_lua_State:DWORD, ptr_string:DWORD
LuaL_loadstringPtr      TYPEDEF PTR LuaL_loadstringProto
ftol2_sseProto          TYPEDEF PROTO C
ftol2_ssePtr            TYPEDEF PTR ftol2_sseProto



;------------------------------------------------------------------------------
; EEex.dll Structures
;------------------------------------------------------------------------------
IFNDEF PATTERN
PATTERN                 STRUCT
    bFound              DD 0 ; Found flag, used to skip patterns already found and verified
    PatBytes            DD 0 ; Pointer to pattern bytes to match (required)
    PatLength           DD 0 ; Length of PatBytes (required)
    VerBytes            DD 0 ; Pointer to verify bytes to match (can be 0)
    VerLength           DD 0 ; Length of VerLength (required if VerBytes != 0, otherwise 0)
    PatAdj              DD 0 ; +/- if PatBytes matched to get address to return (can be 0)
    VerAdj              DD 0 ; +/- from PatBytes matched address to get address of VerBytes to verify (can be 0)
    FuncAddress         DD 0 ; Pointer to global var to store address of function if pattern bytes match and verify bytes match
PATTERN                 ENDS
ENDIF

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
INFO_ADDRESSES          EQU 3


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


;---------------------------
; Byte Search Patterns
;---------------------------
ALIGN 1
P_PatchLocation         DB 83h,0C4h,30h,85h,0C0h,75h,14h,50h,50h,50h,6Ah,0FFh,50h,0FFh,35h
P_PatchLocationLen      EQU $-P_PatchLocation
V_PatchLocation         DB 83h,0C4h,18h,6Ah,00h
V_PatchLocationLen      EQU $-V_PatchLocation
P_Lua_pushnumber        DB 55h,8Bh,0ECh,8Bh,4Dh,08h,0DDh,45h,0Ch,8Bh,51h,08h,0DDh,1Ah,8Bh,42h,04h,25h,00h,0FFh,0FFh,7Fh,3Dh,00h,0A5h,0F7h,7Fh,74h,08h,8Dh,42h,08h,89h,41h,08h,5Dh,0C3h
P_Lua_pushnumberLen     EQU $-P_Lua_pushnumber
;V_Lua_pushnumber       DB 0
V_Lua_pushnumberLen     EQU 0 ; $-V_Lua_pushnumber
P_Lua_pushclosure       DB 55h,8Bh,0ECh,83h,0E4h,0F8h,56h,57h,8Bh,7Dh,10h,85h,0FFh,75h,1Ch,8Bh,55h,08h,8Bh,45h,0Ch,8Bh,4Ah,08h,89h,01h,0C7h,41h,04h,16h,0A5h,0F7h,7Fh,83h,42h,08h,08h,5Fh,5Eh,8Bh,0E5h,5Dh,0C3h
P_Lua_pushclosureLen    EQU $-P_Lua_pushclosure
;V_Lua_pushclosure      DB 0
V_Lua_pushclosureLen    EQU 0 ; $-V_Lua_pushclosure
P_Lua_tolstring         DB 55h,8Bh,0ECh,83h,0E4h,0F8h,51h,8Bh,55h,0Ch,56h,8Bh,75h,08h,8Bh,0CEh
P_Lua_tolstringLen      EQU $-P_Lua_tolstring
V_Lua_tolstring         DB 0
V_Lua_tolstringLen      EQU 0 ; $-V_Lua_tolstring
P_Lua_setglobal         DB 55h,8Bh,0ECh,53h,56h,8Bh,75h,08h,0BAh,02h,00h,00h,00h,57h,8Bh,46h,0Ch,8Bh,48h,28h
P_Lua_setglobalLen      EQU $-P_Lua_setglobal
V_Lua_setglobal         DB 83h,46h,08h,0F0h
V_Lua_setglobalLen      EQU $-V_Lua_setglobal
P_Lua_tonumberx         DB 83h,0C4h,04h,85h,0C0h,74h,28h,0DDh,44h,24h,08h,8Dh,44h,24h,08h,0DDh,5Ch,24h,08h,85h,0F6h,74h,06h,0C7h,06h,01h,00h,00h,00h,0DDh,00h,5Eh,8Bh,4Ch,24h,10h,33h,0CCh
P_Lua_tonumberxLen      EQU $-P_Lua_tonumberx
;V_Lua_tonumberx        DB 0
V_Lua_tonumberxLen      EQU 0 ; $-V_Lua_tonumberx
P__ftol2_sse            DB 74h,2Dh,55h,8Bh,0ECh,83h,0ECh,08h,83h,0E4h,0F8h,0DDh,1Ch,24h,0F2h,0Fh,2Ch,04h,24h,0C9h,0C3h
P__ftol2_sseLen         EQU $-P__ftol2_sse
;V__ftol2_sse           DB 0
V__ftol2_sseLen         EQU 0 ; $-V__ftol2_sse
P_LuaL_loadstring       DB 8Bh,55h,0Ch,8Bh,0C2h,56h,8Bh,75h,08h,57h,8Dh,78h,01h,8Ah,08h,40h,84h,0C9h
P_LuaL_loadstringLen    EQU $-P_LuaL_loadstring
;V_LuaL_loadstring      DB 0
V_LuaL_loadstringLen    EQU 0 ; $-V_LuaL_loadstring


ALIGN 16
;---------------------------
; Global Addresses
;---------------------------
PatchLocation           DD 0
Func_Lua_pushclosure    Lua_pushclosurePtr 0
Func_Lua_pushnumber     Lua_pushnumberPtr 0
Func_Lua_setglobal      Lua_setglobalPtr 0
Func_Lua_tolstring      Lua_tolstringPtr 0
Func_Lua_tonumberx      Lua_tonumberxPtr 0
Func_LuaL_loadstring    LuaL_loadstringPtr 0
Func__ftol2_sse         ftol2_ssePtr 0


;---------------------------
; Pattern Array
;---------------------------
; PATTERN Structure:     bFound PatBytes                  PatLength             VerBytes                VerLength            PAdj VAdj  FuncAddress
Patterns                \
PATTERN                 <FALSE, Offset P_PatchLocation,    P_PatchLocationLen,    Offset V_PatchLocation,  V_PatchLocationLen,     -5,  24, Offset PatchLocation>
PATTERN                 <FALSE, Offset P_Lua_pushnumber,  P_Lua_pushnumberLen,  0,                      V_Lua_pushnumberLen,    0,   0, Offset Func_Lua_pushnumber>
PATTERN                 <FALSE, Offset P_Lua_pushclosure, P_Lua_pushclosureLen, 0,                      V_Lua_pushclosureLen,   0,   0, Offset Func_Lua_pushclosure>
PATTERN                 <FALSE, Offset P_Lua_tolstring,   P_Lua_tolstringLen,   0,                      V_Lua_tolstringLen,     0,   0, Offset Func_Lua_tolstring>
PATTERN                 <FALSE, Offset P_Lua_setglobal,   P_Lua_setglobalLen,   Offset V_Lua_setglobal, V_Lua_setglobalLen,     0, 103, Offset Func_Lua_setglobal>
PATTERN                 <FALSE, Offset P_Lua_tonumberx,   P_Lua_tonumberxLen,   0,                      V_Lua_tonumberxLen,   -83,   0, Offset Func_Lua_tonumberx>
PATTERN                 <FALSE, Offset P__ftol2_sse,      P__ftol2_sseLen,      0,                      V__ftol2_sseLen,       -7,   0, Offset Func__ftol2_sse>
PATTERN                 <FALSE, Offset P_LuaL_loadstring, P_LuaL_loadstringLen, 0,                      V_LuaL_loadstringLen, -20,   0, Offset Func_LuaL_loadstring>

PatternsSize            EQU $-Patterns
TotalPatterns           DD (PatternsSize / SIZEOF PATTERN)


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










