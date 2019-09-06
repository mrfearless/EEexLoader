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
;include lua52.inc
;includelib lua523.lib ; nil value for lua_setglobal
;includelib msvcrt12.lib
ENDIF

;------------------------------------------------------------------------------
; EEex.dll Prototypes
;------------------------------------------------------------------------------
EEexInitDll             PROTO                            ;
EEexInitGlobals         PROTO                            ;
EEexImportPatterns      PROTO                            ;
EEexVerifyPatterns      PROTO                            ;
EEexVerifyType2Patterns PROTO                            ;
EEexSearchPatterns      PROTO                            ;

EEexPatchLocation       PROTO                            ;
EEexFunctionAddresses   PROTO                            ;
EEexApplyCallPatch      PROTO :DWORD,:DWORD,:DWORD       ; dwAddressToPatch, dwRedirectToFunction, bReturn
EEexVariableValues      PROTO                            ;

EEexLogInformation      PROTO :DWORD                     ; dwType
EEexLogImportPatterns   PROTO :DWORD                     ; bImportError
EEexLogPatterns         PROTO :DWORD                     ; bFoundPattern
EEexEEFileInformation   PROTO                            ;
EEexEEGameInformation   PROTO                            ;
EEexWriteAddressesToIni PROTO                            ;

EEexIsStaticLua         PROTO :DWORD                     ; lpszPatternName

EEexDwordToAscii        PROTO :DWORD,:DWORD              ; dwValue, lpszAsciiString
EEexAsciiHexToDword     PROTO :DWORD                     ; lpszAsciiHexString
EEexDwordToAsciiHex     PROTO :DWORD,:DWORD,:DWORD       ; dwValue, lpszAsciiHexString, bUppercase

EEexRawToHexString      PROTO :DWORD,:DWORD,:DWORD,:DWORD; lpRaw, dwRawSize, lpszAsciiHexString, bUpperCase
EEexHexStringToRaw      PROTO :DWORD,:DWORD              ; lpszAsciiHexString, lpRaw

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
INFO_IMPORTED           EQU 3
INFO_VERIFIED           EQU 4
INFO_SEARCHED           EQU 5
INFO_ADDRESSES          EQU 6

; Beamdog EE Game Type:
GAME_UNKNOWN            EQU 0h
GAME_BGEE               EQU 1h
GAME_BG2EE              EQU 2h
GAME_BGSOD              EQU 4h
GAME_IWDEE              EQU 8h
GAME_PSTEE              EQU 10h


.DATA
;------------------------------------------------------------------------------
; EEex.dll Initialized Data
;------------------------------------------------------------------------------
AppName                 DB "EEex.dll",0
szBeamdog_BGEE          DB "BALDUR.EXE",0
szBeamdog_BG2EE         DB "BALDUR.EXE",0
szBeamdog_BGSOD         DB "SIEGEOFDRAGONSPEAR.EXE",0
szBeamdog_IWDEE         DB "ICEWIND.EXE",0
szBeamdog_IWD2EE        DB "ICEWIND.EXE",0
szBeamdog_PSTEE         DB "TORMENT.EXE",0
szBeamdog_BG2EE_Name    DB "Baldur's Gate II: Enhanced Edition",0
gEEGameType             DD 0 ; Beamdog EE Game Type

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

szErrorPatternsNone     DB "No patterns found in the external pattern database.",0
szErrorPatternsToMany   DB "Too many patterns stored in the external pattern database.",0
szErrorPatternsAlloc    DB "Failed to allocate memory for importing external pattern database.",0
szErrorPatchLocation    DB "Patch location could not be located or is null.",13,10
                        DB "The game will continue to launch, but EEex will not be enabled.",0
szErrorPatchFailure     DB "Failed to apply patch to EE game!",13,10
                        DB "The game will continue to launch, but EEex will not be enabled.",0
                        
;---------------------------
; Pattern message strings
;---------------------------
szImported              DB " patterns imported",0
szNotImported           DB " patterns not imported",0
szVerified              DB " patterns verified,",0
szNotVerified           DB " patterns not verified",0
szFound                 DB " patterns found,",0
szNotFound              DB " patterns not found",0
szSkipped               DB " patterns skipped",0
szToSearchFor           DB " patterns left to search for",0
szPatternsOutOf         DB " out of ",0
szPatterns              DB " patterns",0
szPattern               DB "Pattern",0
szPatDB                 DB "db",0,0
szType2Pattern          DB " (Pattern Type 2)",0

;---------------------------
; Functions/globals names:
;---------------------------
; Lua Functions
szLua_createtable               DB "_lua_createtable",0
szLua_createtablex              DB "_lua_createtablex",0
szLua_getglobal                 DB "_lua_getglobal",0
szLua_gettop                    DB "_lua_gettop",0
szLua_pcallk                    DB "_lua_pcallk",0
szLua_pushcclosure              DB "_lua_pushcclosure",0
szLua_pushlightuserdata         DB "_lua_pushlightuserdata",0
szLua_pushlstring               DB "_lua_pushlstring",0
szLua_pushnumber                DB "_lua_pushnumber",0
szLua_pushstring                DB "_lua_pushstring",0
szLua_rawgeti                   DB "_lua_rawgeti",0
szLua_rawlen                    DB "_lua_rawlen",0
szLua_setfield                  DB "_lua_setfield",0
szLua_setglobal                 DB "_lua_setglobal",0
szLua_settable                  DB "_lua_settable",0
szLua_settop                    DB "_lua_settop",0
szLua_toboolean                 DB "_lua_toboolean",0
szLua_tolstring                 DB "_lua_tolstring",0
szLua_tonumberx                 DB "_lua_tonumberx",0
szLua_touserdata                DB "_lua_touserdata",0
szLua_type                      DB "_lua_type",0
szLua_typename                  DB "_lua_typename",0
szLuaL_loadstring               DB "_luaL_loadstring",0
; Other functions
sz_ftol2_sse                    DB "__ftol2_sse",0
szGetProcAddress                DB "__imp__GetProcAddress",0
szLoadLibrary                   DB "__imp__LoadLibraryA",0
szGetProcAddressProc            DB "GetProcAddress",0
szLoadLibraryProc               DB "LoadLibraryA",0
szSDL_Free                      DB "_SDL_free",0
szSDL_FreeExport                DB "SDL_free",0
szSDL_LogExport                 DB "SDL_Log",0
szSDL_vsnprintfExport           DB "SDL_vsnprintf",0
szKernel32Dll                   DB "kernel32.dll",0


;---------------------------
; Module and section info
;---------------------------
hKernel32               DD 0
hModule                 DD 0
hEEGameModule           DD 0
hEEGameProcess          DD 0
EEGameBaseAddress       DD 0
EEGameImageSize         DD 0
EEGameNoSections        DD 0
EEGameSectionTEXTSize   DD 0
EEGameSectionTEXTPtr    DD 0
EEGameAddressEP         DD 0
EEGameAddressStart      DD 0
EEGameAddressFinish     DD 0
modinfo                 MODULEINFO <>

;---------------------------
; Filenames 
;---------------------------
EEexExeFile             DB MAX_PATH DUP (0)
EEexIniFile             DB MAX_PATH DUP (0)
EEexLogFile             DB MAX_PATH DUP (0)
EEexPatFile             DB MAX_PATH DUP (0)

;---------------------------
; Version buffers 
;---------------------------
EEGameProductVersion    DB 64 DUP (0)
EEGameProductName       DB 128 DUP (0)
EEGameExeName           DB 64 DUP (0)

;---------------------------
; Pattern message buffers 
;---------------------------
szImportedNo            DB 16 DUP (0)
szNotImportedNo         DB 16 DUP (0)
szVerifiedNo            DB 16 DUP (0)
szNotVerifiedNo         DB 16 DUP (0)
szFoundNo               DB 16 DUP (0)
szNotFoundNo            DB 16 DUP (0)
szSkippedNo             DB 16 DUP (0)
szTotalPatternNo        DB 16 DUP (0)
szPatternMessageBuffer  DB 128 DUP (0)


.DATA?
;------------------------------------------------------------------------------
; EEex.dll Uninitialized Data
;------------------------------------------------------------------------------
hInstance               DD ?
hWnd                    DD ?
szFileVersionBuffer     DB 32 DUP (?)
szProductVersionBuffer  DB MAX_PATH DUP (?)
szProductNameBuffer     DB MAX_PATH DUP (?)










