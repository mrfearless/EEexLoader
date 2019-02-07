;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------
.686
.MMX
.XMM
.model flat,stdcall
option casemap:none


EEEX_ALIGN TEXTEQU <ALIGN 16>
EEEX_LOGGING EQU 1 ; comment out if we dont require logging
;EEEX_LUALIB EQU 1 ; comment out to use lua function found in EE game. Otherwise use some lua functions from static lib


;DEBUG32 EQU 1
;IFDEF DEBUG32
;    PRESERVEXMMREGS equ 1
;    includelib M:\Masm32\lib\Debug32.lib
;    DBG32LIB equ 1
;    DEBUGEXE textequ <'M:\Masm32\DbgWin.exe'>
;    include M:\Masm32\include\debug32.inc
;ENDIF

CTEXT MACRO Text        ; Macro for defining text in place 
    LOCAL szText
    .DATA
    szText DB Text, 0
    .CODE
    EXITM <Offset szText>
ENDM


include EEex.inc        ; Basic include file. Error messages, strings for function names, buffers etc
include EEexPattern.asm ; Pattern array/table, function pointers, game globals, 
include EEexIni.asm     ; Ini functions, strings for sections and key names
include EEexLog.asm     ; Log functions, strings for logging output
include EEexLua.asm     ; EEexLuaInit, EEex_Init and other Lua functions used by EEex


.CODE


EEEX_ALIGN
;------------------------------------------------------------------------------
; DllEntry - Main entry function
;------------------------------------------------------------------------------
DllEntry PROC hInst:HINSTANCE, reason:DWORD, reserved:DWORD
    .IF reason == DLL_PROCESS_ATTACH
        mov eax, hInst
        mov hInstance, eax
        mov hEEGameModule, eax
        Invoke EEexInitDll
    .ENDIF
    mov eax,TRUE
    ret
DllEntry Endp


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexInitDll - Intialize EEex.dll
; Read ini file (if exists) for saved pattern address information and begin
; verifying / searching for function addresses or game global address.
;
; Patchs a specific address location to forward a call to our EEexLuaInit.
; Returns: None
;------------------------------------------------------------------------------
EEexInitDll PROC USES EBX
    LOCAL bSearchPatterns:DWORD
    LOCAL ptrNtHeaders:DWORD
    LOCAL ptrSections:DWORD
    LOCAL ptrCurrentSection:DWORD
    LOCAL CurrentSection:DWORD

    Invoke EEexInitGlobals

    Invoke EEexLogInformation, INFO_GAME


    ;--------------------------------------------------------------------------
    ; EE Game Module Info And Sections Stage
    ;--------------------------------------------------------------------------
    Invoke GetCurrentProcess
    mov hEEGameProcess, eax
    Invoke GetModuleInformation, hEEGameProcess, 0, Addr modinfo, SIZEOF MODULEINFO
    .IF eax != 0
        mov eax, modinfo.SizeOfImage
        mov EEGameImageSize, eax
        mov eax, modinfo.EntryPoint
        mov EEGameAddressEP, eax
        add eax, EEGameAddressStart
        mov EEGameAddressFinish, eax
        mov eax, modinfo.lpBaseOfDll
        .IF eax == 0
            mov eax, 00400000h
        .ENDIF
        mov EEGameBaseAddress, eax
        mov EEGameAddressStart, eax
        add eax, EEGameImageSize
        mov EEGameAddressFinish, eax

        mov ebx, EEGameBaseAddress
        .IF [ebx].IMAGE_DOS_HEADER.e_magic == IMAGE_DOS_SIGNATURE
            mov eax, [ebx].IMAGE_DOS_HEADER.e_lfanew
            add ebx, eax ; ebx ptr to IMAGE_NT_HEADERS32
            .IF [ebx].IMAGE_NT_HEADERS32.Signature == IMAGE_NT_SIGNATURE
                ;--------------------------------------------------------------
                ; Read PE Sections .text, .rdata and .data
                ;--------------------------------------------------------------
                movzx eax, word ptr [ebx].IMAGE_NT_HEADERS32.FileHeader.NumberOfSections
                mov EEGameNoSections, eax
                mov eax, SIZEOF IMAGE_NT_HEADERS32
                add ebx, eax ; ebx ptr to IMAGE_SECTION_HEADER
                mov ptrCurrentSection, ebx
                mov CurrentSection, 0
                mov eax, 0
                .WHILE eax < EEGameNoSections
                    mov ebx, ptrCurrentSection
                    lea eax, [ebx].IMAGE_SECTION_HEADER.Name1
                    mov eax, [eax]
                    .IF eax == 'xet.' || eax == 'XET.' || eax == 'doc.' || eax == 'DOC.'; .tex .cod .TEX .COD
                        mov eax, [ebx].IMAGE_SECTION_HEADER.SizeOfRawData
                        mov EEGameSectionTEXTSize, eax
                        mov eax, [ebx].IMAGE_SECTION_HEADER.VirtualAddress
                        add eax, EEGameBaseAddress
                        mov EEGameSectionTEXTPtr, eax
                        .BREAK
                    .ENDIF
                    add ptrCurrentSection, SIZEOF IMAGE_SECTION_HEADER
                    inc CurrentSection
                    mov eax, CurrentSection
                .ENDW
                ;--------------------------------------------------------------
                ; Finished Reading PE Sections
                ;--------------------------------------------------------------

                ;--------------------------------------------------------------
                ; Continue Onwards To Verify / Search Stage
                ;--------------------------------------------------------------
            .ELSE ; IMAGE_NT_SIGNATURE Failed
                IFDEF EEEX_LOGGING
                .IF gEEexLog > LOGLEVEL_NONE
                    Invoke LogOpen, FALSE
                    Invoke LogMessage, Addr szErrorImageNtSig, LOG_ERROR, 0
                    Invoke LogClose
                .ENDIF
                ENDIF
                ret ; Exit EEexInitDll
            .ENDIF
        .ELSE ; IMAGE_DOS_SIGNATURE Failed
            IFDEF EEEX_LOGGING
            .IF gEEexLog > LOGLEVEL_NONE
                Invoke LogOpen, FALSE
                Invoke LogMessage, Addr szErrorImageDosSig, LOG_ERROR, 0
                Invoke LogClose
            .ENDIF
            ENDIF
            ret ; Exit EEexInitDll
        .ENDIF
    .ELSE ; GetModuleInformation Failed
        IFDEF EEEX_LOGGING
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogOpen, FALSE
            Invoke LogMessage, Addr szErrorGetModuleInfo, LOG_ERROR, 0
            Invoke LogClose
        .ENDIF
        ENDIF
        ret ; Exit EEexInitDll
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished EE Game Module Info And Sections Stage
    ;--------------------------------------------------------------------------


    Invoke EEexLogInformation, INFO_DEBUG


    ;--------------------------------------------------------------------------
    ; Verify Pattern Addresses
    ;--------------------------------------------------------------------------
    mov bSearchPatterns, TRUE ; Set to true to assume we will search for all patterns
    IFDEF DEBUG32
    PrintText 'EEexVerifyPatterns'
    ENDIF
    Invoke EEexVerifyPatterns
    .IF eax == TRUE ; no need to search for patterns as we have verified them all
        IFDEF DEBUG32
        PrintText 'EEexVerifyPatterns Success'
        ENDIF
        mov bSearchPatterns, FALSE
    .ELSE
        IFDEF DEBUG32
        PrintText 'EEexVerifyPatterns Failed'
        ENDIF
    .ENDIF

    Invoke EEexLogInformation, INFO_VERIFIED

    ;--------------------------------------------------------------------------
    ; Search For Pattern Addresses
    ;--------------------------------------------------------------------------
    .IF bSearchPatterns == TRUE ; If we failed to verify some or all patterns, search for remainder
        IFDEF DEBUG32
        PrintText 'EEexSearchPatterns'
        ENDIF
        Invoke EEexSearchPatterns
        .IF eax == TRUE ; EE Game Lua Function Addresses Found - Write Info To Ini File
            IFDEF DEBUG32
            PrintText 'EEexSearchPatterns Success'
            ENDIF
            Invoke EEexLogInformation, INFO_SEARCHED
            Invoke IniClearFallbackSection
            Invoke EEexWriteAddressesToIni
            ;------------------------------------------------------------------
            ; Continue Onwards To Apply Patch Stage
            ;------------------------------------------------------------------

        .ELSE ; EE Game Lua Function Addresses NOT VERIFIED OR FOUND!
            IFDEF DEBUG32
            PrintText 'EEexSearchPatterns Failed'
            PrintText 'EEexFallbackAddresses'
            ENDIF
            Invoke EEexFallbackAddresses ; check if any fallback addresses are in ini
            .IF eax == FALSE ; Have to tell user we dont have any addresses
                Invoke EEexLogInformation, INFO_SEARCHED
                ; Error tell user that cannot find or verify functions - might be a new build
                IFDEF EEEX_LOGGING
                .IF gEEexLog > LOGLEVEL_NONE
                    Invoke LogOpen, FALSE
                    Invoke LogMessage, Addr szErrorSearchFunctions, LOG_ERROR, 0 ; CTEXT("Cannot find or verify EE game lua functions - might be an unsupported or new build of EE game.")
                    Invoke LogClose
                .ENDIF
                ENDIF
                Invoke MessageBox, 0, Addr szErrorSearchFunctions, Addr AppName, MB_OK
                ;--------------------------------------------------------------
                ; EEex.DLL EXITS HERE - Execution continues with EE game
                ;--------------------------------------------------------------
                ret ; Exit EEexInitDll

            .ELSE
                IFDEF DEBUG32
                PrintText 'Using Fallback addresses'
                ENDIF
                Invoke EEexLogInformation, INFO_FALLBACK
                ;--------------------------------------------------------------
                ; Using Fallback addresses - could still crash!
                ;--------------------------------------------------------------

            .ENDIF
        .ENDIF
    .ELSE ; Functions verified, no need for search
        IFDEF DEBUG32
        PrintText 'EEexSearchPatterns Skipped'
        ENDIF
        ;----------------------------------------------------------------------
        ; Continue Onwards To Apply Patch Stage
        ;----------------------------------------------------------------------
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished Verify / Search Stage
    ;--------------------------------------------------------------------------


    ;--------------------------------------------------------------------------
    ; Apply Patch Stage (Call EEexLuaInit) - At PatchLocation In EE Game
    ;--------------------------------------------------------------------------
    .IF PatchLocation != 0
        IFDEF DEBUG32
        PrintText 'EEexApplyCallPatch'
        ENDIF
        Invoke EEexApplyCallPatch, PatchLocation ; (call EEexLuaInit)
        .IF eax == TRUE ; Patch Success! - Write status to log and exit EEex.dll
            IFDEF DEBUG32
            PrintText 'EEexApplyCallPatch Success'
            ENDIF
            IFDEF EEEX_LOGGING
            .IF gEEexLog >= LOGLEVEL_DETAIL
                Invoke LogMessage, CTEXT("EEexApplyCallPatch:"), LOG_INFO, 0
                Invoke LogMessageAndHexValue, CTEXT("Applied patch at"), PatchLocation
                Invoke LogMessage, 0, LOG_CRLF, 0
            .ENDIF
            ENDIF
            ;------------------------------------------------------------------
            ; Note: Redirection from EE Game to our EEexLuaInit function occurs
            ; after EEex.dll:EEexInitDll returns to EE Game, during which time
            ; it will eventually hit our patched instruction: call EEexLuaInit
            ;------------------------------------------------------------------
        .ELSE ; Patch Failure! - Write status to log and exit EEex.dll
            IFDEF DEBUG32
            PrintText 'EEexApplyCallPatch Failure'
            ENDIF
            IFDEF EEEX_LOGGING
            .IF gEEexLog > LOGLEVEL_NONE
                Invoke LogMessage, CTEXT("EEexApplyCallPatch:"), LOG_ERROR, 0
                Invoke LogMessageAndHexValue, CTEXT("Failed to apply patch at"), PatchLocation
                Invoke LogMessage, 0, LOG_CRLF, 0
                Invoke LogClose
            .ENDIF
            ENDIF
        .ENDIF
    .ELSE
        IFDEF EEEX_LOGGING
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogMessage, CTEXT("PatchLocation is NULL!"), LOG_ERROR, 0
            Invoke LogClose
        .ENDIF
        ENDIF
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished Apply Patch Stage
    ;--------------------------------------------------------------------------


    Invoke EEexGameGlobals ; get pointers to game globals


    ;--------------------------------------------------------------------------
    ; EEex.DLL EXITS HERE - Execution continues with EE game
    ;--------------------------------------------------------------------------
    xor eax, eax
    ret
EEexInitDll ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexInitGlobals - Initialize global variables & read ini file for addresses.
; Returns: None
;------------------------------------------------------------------------------
EEexInitGlobals PROC USES EBX
    LOCAL nLength:DWORD

    ; Construct ini filename
    Invoke GetModuleFileName, 0, Addr EEexExeFile, SIZEOF EEexExeFile
    Invoke GetModuleFileName, hInstance, Addr EEexIniFile, SIZEOF EEexIniFile
    Invoke lstrcpy, Addr EEexLogFile, Addr EEexIniFile
    Invoke lstrlen, Addr EEexIniFile
    mov nLength, eax
    lea ebx, EEexIniFile
    add ebx, eax
    sub ebx, 3 ; move back past 'dll' extention
    mov byte ptr [ebx], 0 ; null so we can use lstrcat
    Invoke lstrcat, ebx, Addr szIni ; add 'ini' to end of string instead

    ; Construct log filename
    lea ebx, EEexLogFile
    add ebx, nLength
    sub ebx, 3 ; move back past 'dll' extention
    mov byte ptr [ebx], 0 ; null so we can use lstrcat
    Invoke lstrcat, ebx, Addr szLog ; add 'log' to end of string instead

    Invoke EEexEEFileInformation
    .IF eax == TRUE
        Invoke EEexEEGameInformation
        IFDEF DEBUG32
        PrintDec gEEGameType
        ENDIF
    .ENDIF

    Invoke IniGetOptionLog
    mov gEEexLog, eax
    Invoke IniGetOptionLua ; TODO how to implement with patterns in .data?
    mov gEEexLua, eax
    Invoke IniGetOptionHex
    mov gEEexHex, eax
    
    Invoke IniSetOptionLog, gEEexLog
    Invoke IniSetOptionLua, gEEexLua
    Invoke IniSetOptionHex, gEEexHex

    ;--------------------------------------------------------------------------
    ; Get addresses of win32 api functions
    ;--------------------------------------------------------------------------
    lea eax, GetProcAddress
    mov F_GetProcAddress, eax
    lea eax, LoadLibrary
    mov F_LoadLibrary, eax
    Invoke GetProcAddress, 0, Addr szSDL_FreeExport
    mov F_SDL_free, eax
    
    IFDEF DEBUG32
    PrintText 'Api calls and exports'
    PrintDec F_GetProcAddress
    PrintDec F_LoadLibrary
    PrintDec F_SDL_free
    ENDIF

    ;--------------------------------------------------------------------------
    ; Read in pattern addresses of Lua functions if present in ini file
    ;--------------------------------------------------------------------------
    Invoke IniGetPatchLocation, INI_NORMAL
    mov PatchLocation, eax
    IFDEF EEEX_LUALIB
        .IF gEEexLua == TRUE
            ; set function pointers to internal static lua library functions
            lea eax, lua_createtable
            mov F_Lua_createtable, eax
            lea eax, lua_getglobal
            mov F_Lua_getglobal, eax
            lea eax, lua_gettop
            mov F_Lua_gettop, eax
            lea eax, lua_pcallk
            mov F_Lua_pcallk, eax
            lea eax, lua_pushcclosure
            mov F_Lua_pushcclosure, eax
            lea eax, lua_pushlightuserdata
            mov F_Lua_pushlightuserdata, eax
            lea eax, lua_pushlstring
            mov F_Lua_pushlstring, eax
            lea eax, lua_pushnumber
            mov F_Lua_pushnumber, eax
            lea eax, lua_pushstring
            mov F_Lua_pushstring, eax
            lea eax, lua_rawgeti
            mov F_Lua_rawgeti, eax
            lea eax, lua_rawlen
            mov F_Lua_rawlen, eax
            lea eax, lua_setfield
            mov F_Lua_setfield, eax
            lea eax, lua_settable
            mov F_Lua_settable, eax
            lea eax, lua_settop
            mov F_Lua_settop, eax
            lea eax, lua_toboolean
            mov F_Lua_toboolean, eax
            lea eax, lua_tolstring
            mov F_Lua_tolstring, eax
            lea eax, lua_tonumberx
            mov F_Lua_tonumberx, eax
            lea eax, lua_touserdata
            mov F_Lua_touserdata, eax
            lea eax, lua_type
            mov F_Lua_type, eax
            lea eax, lua_typename
            mov F_Lua_typename, eax
            ; Get these functions if in ini
            ; as the static lua lib ones crash.
            ; speeds up verify
            ;IniReadValue, Addr szIniEEex, Addr szIniLua_setglobal
            lea eax, lua_setglobalx
            mov F_Lua_setglobal, eax
            Invoke IniReadValue, Addr szIniEEex, Addr szLuaL_loadstring, 0
            mov F_LuaL_loadstring, eax
        .ENDIF
    ENDIF
    
    .IF gEEexLua == FALSE || gEEexLuaLibDefined == FALSE ; or read all function pointers from ini file
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_createtable, 0
        mov F_Lua_createtable, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_getglobal, 0
        mov F_Lua_getglobal, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_gettop, 0
        mov F_Lua_gettop, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_pcallk, 0
        mov F_Lua_pcallk, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_pushcclosure, 0
        mov F_Lua_pushcclosure, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_pushlightuserdata, 0
        mov F_Lua_pushlightuserdata, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_pushlstring, 0
        mov F_Lua_pushlstring, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_pushnumber, 0
        mov F_Lua_pushnumber, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_pushstring, 0
        mov F_Lua_pushstring, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_rawgeti, 0
        mov F_Lua_rawgeti, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_rawlen, 0
        mov F_Lua_rawlen, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_setfield, 0
        mov F_Lua_setfield, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_setglobal, 0
        mov F_Lua_setglobal, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_settable, 0
        mov F_Lua_settable, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_settop, 0
        mov F_Lua_settop, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_toboolean, 0
        mov F_Lua_toboolean, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_tolstring, 0
        mov F_Lua_tolstring, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_tonumberx, 0
        mov F_Lua_tonumberx, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_touserdata, 0
        mov F_Lua_touserdata, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_type, 0
        mov F_Lua_type, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLua_typename, 0
        mov F_Lua_typename, eax
        Invoke IniReadValue, Addr szIniEEex, Addr szLuaL_loadstring, 0
        mov F_LuaL_loadstring, eax
    .ENDIF


    ;--------------------------------------------------------------------------
    ; Read in pattern addresses of game functions if present in ini file
    ;--------------------------------------------------------------------------
    ; CAIObjectType
    Invoke IniReadValue, Addr szIniEEex, Addr szCAIObjectTypeDecode, 0
    mov F_EE_CAIObjectTypeDecode, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCAIObjectTypeRead, 0
    mov F_EE_CAIObjectTypeRead, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCAIObjectTypeSet, 0
    mov F_EE_CAIObjectTypeSet, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCAIObjectTypeSSC, 0
    mov F_EE_CAIObjectTypeSSC, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szIniCAIObjectTypeOpEqu, 0
    mov F_EE_CAIObjectTypeOpEqu, eax
    ; CDerivedStats
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsGetAtOffset, 0
    mov F_EE_CDerivedStatsGetAtOffset, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsGetLevel, 0
    mov F_EE_CDerivedStatsGetLevel, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsSetLevel, 0
    mov F_EE_CDerivedStatsSetLevel, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsGetSpellState, 0
    mov F_EE_CDerivedStatsGetSpellState, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsSetSpellState, 0
    mov F_EE_CDerivedStatsSetSpellState, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsGetWarriorLevel, 0
    mov F_EE_CDerivedStatsGetWarriorLevel, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCDerivedStatsReload, 0
    mov F_EE_CDerivedStatsReload, eax
    ; CGameSprite
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteCGameSprite, 0
    mov F_EE_CGameSpriteCGameSprite, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteAddKnownSpell, 0
    mov F_EE_CGameSpriteAddKnownSpell, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteAddKnownSpellMage, 0
    mov F_EE_CGameSpriteAddKnownSpellMage, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteAddKnownSpellPriest, 0
    mov F_EE_CGameSpriteAddKnownSpellPriest, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteAddNewSA, 0
    mov F_EE_CGameSpriteAddNewSA, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteGetActiveStats, 0
    mov F_EE_CGameSpriteGetActiveStats, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteGetActiveProficiency, 0
    mov F_EE_CGameSpriteGetActiveProficiency, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteGetKit, 0
    mov F_EE_CGameSpriteGetKit, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteGetName, 0
    mov F_EE_CGameSpriteGetName, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteGetQuickButtons, 0
    mov F_EE_CGameSpriteGetQuickButtons, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpell, 0
    mov F_EE_CGameSpriteMemorizeSpell, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpellMage, 0
    mov F_EE_CGameSpriteMemorizeSpellMage, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpellPriest, 0
    mov F_EE_CGameSpriteMemorizeSpellPriest, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpellInnate, 0
    mov F_EE_CGameSpriteMemorizeSpellInnate, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteReadySpell, 0
    mov F_EE_CGameSpriteReadySpell, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpell, 0
    mov F_EE_CGameSpriteRemoveKnownSpell, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpellMage, 0
    mov F_EE_CGameSpriteRemoveKnownSpellMage, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpellPriest, 0
    mov F_EE_CGameSpriteRemoveKnownSpellPriest, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpellInnate, 0
    mov F_EE_CGameSpriteRemoveKnownSpellInnate, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteRemoveNewSA, 0
    mov F_EE_CGameSpriteRemoveNewSA, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteRenderHealthBar, 0
    mov F_EE_CGameSpriteRenderHealthBar, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteSetCTT, 0
    mov F_EE_CGameSpriteSetCTT, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteSetColor, 0
    mov F_EE_CGameSpriteSetColor, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteShatter, 0
    mov F_EE_CGameSpriteShatter, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteUnmemorizeSpellMage, 0
    mov F_EE_CGameSpriteUnmemorizeSpellMage, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteUnmemorizeSpellPriest, 0
    mov F_EE_CGameSpriteUnmemorizeSpellPriest, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameSpriteUnmemorizeSpellInnate, 0
    mov F_EE_CGameSpriteUnmemorizeSpellInnate, eax
    ; CInfinity
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfinityDrawLine, 0
    mov F_EE_CInfinityDrawLine, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfinityDrawRectangle, 0
    mov F_EE_CInfinityDrawRectangle, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfinityRenderAOE, 0
    mov F_EE_CInfinityRenderAOE, eax
    ; CInfGame
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfGameAddCTA, 0
    mov F_EE_CInfGameAddCTA, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfGameAddCTF, 0
    mov F_EE_CInfGameAddCTF, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfGameGetCharacterId, 0
    mov F_EE_CInfGameGetCharacterId, eax
    ; CObList
    Invoke IniReadValue, Addr szIniEEex, Addr szCObListRemoveAll, 0
    mov F_EE_CObListRemoveAll, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCObListRemoveHead, 0
    mov F_EE_CObListRemoveHead, eax
    ; CResRef
    Invoke IniReadValue, Addr szIniEEex, Addr szCResRefGetResRefStr, 0
    mov F_EE_CResRefGetResRefStr, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCResRefIsValid, 0
    mov F_EE_CResRefIsValid, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCResRefCResRef, 0
    mov F_EE_CResRefCResRef, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szIniCResRefOpEqu, 0
    mov F_EE_CResRefOpEqu, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szIniCResRefOpNotEqu, 0
    mov F_EE_CResRefOpNotEqu, eax
    ; CString
    Invoke IniReadValue, Addr szIniEEex, Addr szIniCStringOpPlus, 0
    mov F_EE_CStringOpPlus, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCStringCString, 0
    mov F_EE_CStringCString, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCStringFindIndex, 0
    mov F_EE_CStringFindIndex, eax
    ; CInfButtonArray
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfButtonArraySetState, 0
    mov F_EE_CInfButtonArraySetState, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfButtonArrayUpdateButtons, 0
    mov F_EE_CInfButtonArrayUpdateButtons, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCInfButtonArraySTT, 0
    mov F_EE_CInfButtonArraySTT, eax
    ; CGameEffect
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameEffectCGameEffect, 0
    mov F_EE_CGameEffectCGameEffect, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameEffectCopyFromBase, 0
    mov F_EE_CGameEffectCopyFromBase, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameEffectGetItemEffect, 0
    mov F_EE_CGameEffectGetItemEffect, eax
    ; Misc
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameObjectArrayGetDeny, 0
    mov F_EE_CGameObjectArrayGetDeny, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameEffectFireSpell, 0
    mov F_EE_CGameEffectFireSpell, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameAIBaseFireSpellPoint, 0
    mov F_EE_CGameAIBaseFireSpellPoint, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szdimmGetResObject, 0
    mov F_EE_dimmGetResObject, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCAIActionDecode, 0
    mov F_EE_CAIActionDecode, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCGameObjectArrayGetDeny, 0
    mov F_EE_CGameObjectArrayGetDeny, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCListRemoveAt, 0
    mov F_EE_CListRemoveAt, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCRuleTablesMapCSTS, 0
    mov F_EE_CRuleTablesMapCSTS, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szoperator_new, 0
    mov F_EE_operator_new, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szCAIScriptCAIScript, 0
    mov F_EE_CAIScriptCAIScript, eax
    ; Other functions
    Invoke IniReadValue, Addr szIniEEex, Addr sz_ftol2_sse, 0
    mov F__ftol2_sse, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_mbscmp, 0
    mov F__mbscmp, eax
    Invoke IniReadValue, Addr szIniEEex, Addr szp_malloc, 0
    mov F_p_malloc, eax


    ;--------------------------------------------------------------------------
    ; Read in pattern addresses of game globals if present in ini file
    ;--------------------------------------------------------------------------
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_pChitin, 0
    mov pp_pChitin, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_pBaldurChitin, 0
    mov pp_pBaldurChitin, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_backgroundMenu, 0
    mov pp_backgroundMenu, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_overlayMenu, 0
    mov pp_overlayMenu, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_timer_ups, 0
    mov pp_timer_ups, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_aB_1, 0
    mov pp_aB_1, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_CGameSprite_vftable, 0
    mov pp_CGameSprite_vftable, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_CAIObjectTypeANYONE, 0
    mov pp_CAIObjectTypeANYONE, eax
    Invoke IniReadValue, Addr szIniEEex, Addr sz_pp_VersionString_Push, 0
    mov pp_VersionString_Push, eax
    xor eax, eax
    ret
EEexInitGlobals ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexVerifyPatterns - Verify if pattern addresses contain their own byte
; patterns, if they do match we set the bFound flag to TRUE in their pattern
; structure. 
;
; For those patterns that do not match, a rescan will occur for those patterns 
; (during EEexSearchPatterns) that have bFound set to FALSE.
; Returns: TRUE if all patterns where succesfully verified or FALSE otherwise.
;------------------------------------------------------------------------------
EEexVerifyPatterns PROC USES EBX
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL PatAddress:DWORD
    LOCAL PatBytes:DWORD
    LOCAL PatLength:DWORD
    LOCAL VerAdj:DWORD
    LOCAL VerBytes:DWORD
    LOCAL VerLength:DWORD

    lea ebx, Patterns
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        mov eax, [ebx].PATTERN.FuncAddress
        mov eax, [eax] ; FuncAddress is pointer to global var storing address - no GetIni for pattern address yet?
        .IF eax == 0 ; just in case
            IFDEF DEBUG32
            PrintText 'FuncAddress is pointer to global var is null.'
            PrintDec nPattern
            ENDIF
            inc NotVerifiedPatterns
            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
            .CONTINUE
        .ENDIF

        mov ebx, ptrCurrentPattern
        sub eax, [ebx].PATTERN.PatAdj ; subtract adjustment to get pattern
        mov PatAddress, eax

        mov eax, [ebx].PATTERN.PatBytes
        mov PatBytes, eax
        mov eax, [ebx].PATTERN.PatLength
        mov PatLength, eax

        ; check pattern matches
        Invoke PatternVerify, PatAddress, PatBytes, PatLength
        mov ebx, ptrCurrentPattern
        .IF eax == TRUE
            mov eax, [ebx].PATTERN.VerLength
            .IF eax != 0 ; Check VerBytes pattern if it exists as well
                mov VerLength, eax
                mov eax, [ebx].PATTERN.VerBytes
                mov VerBytes, eax
                mov eax, PatAddress
                add eax, [ebx].PATTERN.VerAdj
                Invoke PatternVerify, eax, VerBytes, VerLength
            .ELSE
                mov eax, TRUE ; No verbytes to check so set to TRUE
            .ENDIF

            mov ebx, ptrCurrentPattern
            .IF eax == TRUE ; No verbytes to check or verbytes matched
                .IF [ebx].PATTERN.PatType == 1 ; global/variable, so read it
                    IFDEF DEBUG32
                    PrintText 'Pattern address for a global found'
                    PrintDec nPattern
                    ENDIF
                .ELSEIF [ebx].PATTERN.PatType == 2 ; call x type pattern, so read it
                    IFDEF DEBUG32
                    PrintText 'Pattern address for a call x found'
                    PrintDec nPattern
                    ENDIF
                .ENDIF
                mov [ebx].PATTERN.bFound, TRUE
                inc VerifiedPatterns
                inc FoundPatterns
            .ELSE
                IFDEF DEBUG32
                PrintText 'Pattern found but not verified'
                PrintDec nPattern
                ENDIF
                mov [ebx].PATTERN.bFound, FALSE
            .ENDIF
        .ELSE
            inc NotVerifiedPatterns
            IFDEF DEBUG32
            PrintText 'Pattern not found'
            PrintDec nPattern
            ENDIF
            mov [ebx].PATTERN.bFound, FALSE
         .ENDIF

        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW

    mov eax, VerifiedPatterns
    add eax, SkippedPatterns
    .IF eax != TotalPatterns
        mov eax, FALSE
    .ELSE
        mov eax, TRUE
    .ENDIF

    ret
EEexVerifyPatterns ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexSearchPatterns - Search through memory for function addresses as defined
; by the array of pattern structures. 
;
; For patterns that were already verified we ignore those - which have the 
; bFound flag set in the pattern during the EEexVerifyPatterns call.
; Returns: TRUE if all patterns where succesfully found for each function or
; FALSE otherwise.
;------------------------------------------------------------------------------
EEexSearchPatterns PROC USES EBX ESI
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL dwAddress:DWORD
    LOCAL dwAddressFinish:DWORD
    LOCAL dwAddressValue:DWORD
    LOCAL PatAddress:DWORD
    LOCAL PatAddressValue:DWORD
    LOCAL PatAdj:DWORD
    LOCAL PatBytes:DWORD
    LOCAL PatLength:DWORD
    LOCAL VerAdj:DWORD
    LOCAL VerBytes:DWORD
    LOCAL VerLength:DWORD
    LOCAL RetVal:DWORD

    mov RetVal, FALSE

    mov eax, EEGameSectionTEXTPtr
    mov dwAddress, eax
    add eax, EEGameSectionTEXTSize
    mov dwAddressFinish, eax

    mov esi, dwAddress
    .WHILE esi < dwAddressFinish
        mov eax, [esi]
        mov dwAddressValue, eax

        lea ebx, Patterns
        mov ptrCurrentPattern, ebx
        mov nPattern, 0
        mov eax, 0
        .WHILE eax < TotalPatterns
            .IF [ebx].PATTERN.bFound == FALSE
                mov eax, [ebx].PATTERN.PatBytes
                mov PatBytes, eax
                mov eax, [eax]
                .IF eax == dwAddressValue ; might have a start of a pattern
                    mov eax, [ebx].PATTERN.PatLength
                    mov PatLength, eax
                    Invoke PatternVerify, dwAddress, PatBytes, PatLength
                    .IF eax == TRUE ; Matched a pattern
                        mov ebx, ptrCurrentPattern
                        mov eax, [ebx].PATTERN.VerLength
                        .IF eax != 0 ; Check VerBytes pattern if it exists as well
                            mov VerLength, eax
                            mov eax, [ebx].PATTERN.VerBytes
                            mov VerBytes, eax
                            mov eax, dwAddress
                            add eax, [ebx].PATTERN.VerAdj
                            Invoke PatternVerify, eax, VerBytes, VerLength
                        .ELSE
                            mov eax, TRUE ; No verbytes to check so set to TRUE
                        .ENDIF

                        .IF eax == TRUE ; No verbytes to check or verbytes matched
                            mov ebx, ptrCurrentPattern
                            mov [ebx].PATTERN.bFound, TRUE
                            mov eax, dwAddress
                            add eax, [ebx].PATTERN.PatAdj
                            ;.IF [ebx].PATTERN.PatType == 1 ; global/variable
                            ;    PrintDec eax
                            ;    mov eax, [eax] ; read dword to get pointer to EE game global
                            ;    PrintDec eax
                            ;.ENDIF
                            mov ebx, [ebx].PATTERN.FuncAddress ; Offset to internal global var to set for address
                            .IF ebx != 0
                                mov [ebx], eax ; store address in our internal global var
                            .ENDIF
                            inc FoundPatterns ; PatternsFound
                        .ELSE ; pattern is similar to another but wasnt found and verified yet: A Get/Set function with minor differences?
                            IFDEF DEBUG32
                            PrintText 'EEexSearchPatterns - Failed to verify pattern'
                            PrintDec nPattern
                            ENDIF
                            ;mov ebx, ptrCurrentPattern
                            ;mov eax, 0
                            ;mov ebx, [ebx].PATTERN.FuncAddress ; Offset to internal global var to set for address
                            ;mov [ebx], eax ; store address in our internal global var
                            ;inc FoundPatterns ; PatternsFound
                        .ENDIF

                    .ENDIF
                .ENDIF
            .ENDIF

            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
        .ENDW

        mov eax, FoundPatterns ; PatternsFound
        .IF eax == TotalPatterns ; found all patterns!
            mov RetVal, TRUE
            .BREAK
        .ENDIF

        inc dwAddress
        mov esi, dwAddress
    .ENDW

    ; Check for no of missing patterns
    .IF RetVal == FALSE
        IFDEF DEBUG32
        PrintText '-----------------'
        PrintText 'Missing patterns:'
        PrintDec TotalPatterns
        PrintDec FoundPatterns
        ENDIF
        lea ebx, Patterns
        mov ptrCurrentPattern, ebx
        mov nPattern, 0
        mov eax, 0
        .WHILE eax < TotalPatterns
            .IF [ebx].PATTERN.bFound == FALSE
                inc NotFoundPatterns
                IFDEF DEBUG32
                PrintDec nPattern
                ENDIF
                mov eax, 0 ; set to 0 so we dont use existing value read from ini
                mov ebx, [ebx].PATTERN.FuncAddress ; Offset to internal global var to set for address
                mov [ebx], eax                
            .ENDIF
            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
        .ENDW
    .ENDIF

    mov eax, RetVal
    ret
EEexSearchPatterns ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexFallbackAddresses - Checks ini file to for functions addresses manually
; set in the [Fallback] section.
;
; These address values for functions can be used in cases where a new EE game
; build is released and pattern match fails. These fallback hardcoded address
; values can be used instead - specific to a particular build of the EE game.
;
; After a newer build/update for the EEex loader and dll, when patterns are
; found again, then the [Fallback] section is cleared to prevent newer EE game
; builds in future from triggering the read of now (possibly) invalid fallback
; addresses.
;
; Typical scenario for usage is that info from a forum post etc will indicate
; the raw hardcoded addresses to use. User then edits EEex.ini to add a
; [Fallback] section and the function addresses.
;
; Returns: TRUE if all functions have address values. FALSE otherwise.
;
; NOTE: EE Game will crash if incorrect fallback addresses are specified.
; Users should only add these fallback addresses if instructed to do so, and
; only for a temporary fix until a new EEex loader build is released.

;------------------------------------------------------------------------------
EEexFallbackAddresses PROC

    .IF PatchLocation == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szPatchLocation, 0
        mov PatchLocation, eax
    .ENDIF
    
    .IF gEEexLua == FALSE
        ;--------------------------------------------------------------------------
        ; Read in FALLBACK pattern addresses of Lua functions if present in ini file
        ;--------------------------------------------------------------------------    
        .IF F_Lua_createtable == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_createtable, 0
            mov F_Lua_createtable, eax
        .ENDIF
        .IF F_Lua_getglobal == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_getglobal, 0
            mov F_Lua_getglobal, eax
        .ENDIF
        .IF F_Lua_gettop == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_gettop, 0
            mov F_Lua_gettop, eax
        .ENDIF
        .IF F_Lua_pcallk == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_pcallk, 0
            mov F_Lua_pcallk, eax
        .ENDIF
        .IF F_Lua_pushcclosure == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_pushcclosure, 0
            mov F_Lua_pushcclosure, eax
        .ENDIF
        .IF F_Lua_pushlightuserdata == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_pushlightuserdata, 0
            mov F_Lua_pushlightuserdata, eax
        .ENDIF
        .IF F_Lua_pushlstring == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_pushlstring, 0
            mov F_Lua_pushlstring, eax
        .ENDIF
        .IF F_Lua_pushnumber == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_pushnumber, 0
            mov F_Lua_pushnumber, eax
        .ENDIF
        .IF F_Lua_pushstring == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_pushstring, 0
            mov F_Lua_pushstring, eax
        .ENDIF
        .IF F_Lua_rawgeti == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_rawgeti, 0
            mov F_Lua_rawgeti, eax
        .ENDIF
        .IF F_Lua_rawlen == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_rawlen, 0
            mov F_Lua_rawlen, eax
        .ENDIF
        .IF F_Lua_setfield == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_setfield, 0
            mov F_Lua_setfield, eax
        .ENDIF
        .IF F_Lua_setglobal == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_setglobal, 0
            mov F_Lua_setglobal, eax
        .ENDIF
        .IF F_Lua_settable == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_settable, 0
            mov F_Lua_settable, eax
        .ENDIF
        .IF F_Lua_settop == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_settop, 0
            mov F_Lua_settop, eax
        .ENDIF
        .IF F_Lua_toboolean == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_toboolean, 0
            mov F_Lua_toboolean, eax
        .ENDIF
        .IF F_Lua_tolstring == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_tolstring, 0
            mov F_Lua_tolstring, eax
        .ENDIF
        .IF F_Lua_tonumberx == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_tonumberx, 0
            mov F_Lua_tonumberx, eax
        .ENDIF
        .IF F_Lua_touserdata == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_touserdata, 0
            mov F_Lua_touserdata, eax
        .ENDIF
        .IF F_Lua_type == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_type, 0
            mov F_Lua_type, eax
        .ENDIF
        .IF F_Lua_typename == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLua_typename, 0
            mov F_Lua_typename, eax
        .ENDIF
        .IF F_LuaL_loadstring == 0
            Invoke IniReadValue, Addr szIniEEexFallback, Addr szLuaL_loadstring, 0
            mov F_LuaL_loadstring, eax
        .ENDIF
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Read in FALLBACK pattern addresses of game functions if present in ini file
    ;--------------------------------------------------------------------------
    ; CAIObjectType
    .IF F_EE_CAIObjectTypeDecode == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCAIObjectTypeDecode, 0
        mov F_EE_CAIObjectTypeDecode, eax
    .ENDIF
    .IF F_EE_CAIObjectTypeRead == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCAIObjectTypeRead, 0
        mov F_EE_CAIObjectTypeRead, eax
    .ENDIF
    .IF F_EE_CAIObjectTypeSet == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCAIObjectTypeSet, 0
        mov F_EE_CAIObjectTypeSet, eax
    .ENDIF
    .IF F_EE_CAIObjectTypeSSC == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCAIObjectTypeSSC, 0
        mov F_EE_CAIObjectTypeSSC, eax
    .ENDIF
    .IF F_EE_CAIObjectTypeOpEqu == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniCAIObjectTypeOpEqu, 0
        mov F_EE_CAIObjectTypeOpEqu, eax
    .ENDIF
    ; CDerivedStats
    .IF F_EE_CDerivedStatsGetAtOffset == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsGetAtOffset, 0
        mov F_EE_CDerivedStatsGetAtOffset, eax
    .ENDIF
    .IF F_EE_CDerivedStatsGetLevel == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsGetLevel, 0
        mov F_EE_CDerivedStatsGetLevel, eax
    .ENDIF
    .IF F_EE_CDerivedStatsSetLevel == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsSetLevel, 0
        mov F_EE_CDerivedStatsSetLevel, eax
    .ENDIF
    .IF F_EE_CDerivedStatsGetSpellState == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsGetSpellState, 0
        mov F_EE_CDerivedStatsGetSpellState, eax
    .ENDIF
    .IF F_EE_CDerivedStatsSetSpellState == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsSetSpellState, 0
        mov F_EE_CDerivedStatsSetSpellState, eax
    .ENDIF
    .IF F_EE_CDerivedStatsGetWarriorLevel == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsGetWarriorLevel, 0
        mov F_EE_CDerivedStatsGetWarriorLevel, eax
    .ENDIF
    .IF F_EE_CDerivedStatsReload == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCDerivedStatsReload, 0
        mov F_EE_CDerivedStatsReload, eax
    .ENDIF
    ; CGameSprite
    .IF F_EE_CGameSpriteCGameSprite == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteCGameSprite, 0
        mov F_EE_CGameSpriteCGameSprite, eax
    .ENDIF
    .IF F_EE_CGameSpriteAddKnownSpell == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteAddKnownSpell, 0
        mov F_EE_CGameSpriteAddKnownSpell, eax
    .ENDIF
    .IF F_EE_CGameSpriteAddKnownSpellMage == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteAddKnownSpellMage, 0
        mov F_EE_CGameSpriteAddKnownSpellMage, eax
    .ENDIF
    .IF F_EE_CGameSpriteAddKnownSpellPriest == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteAddKnownSpellPriest, 0
        mov F_EE_CGameSpriteAddKnownSpellPriest, eax
    .ENDIF
    .IF F_EE_CGameSpriteAddNewSA == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteAddNewSA, 0
        mov F_EE_CGameSpriteAddNewSA, eax
    .ENDIF
    .IF F_EE_CGameSpriteGetActiveStats == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteGetActiveStats, 0
        mov F_EE_CGameSpriteGetActiveStats, eax
    .ENDIF
    .IF F_EE_CGameSpriteGetActiveProficiency == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteGetActiveProficiency, 0
        mov F_EE_CGameSpriteGetActiveProficiency, eax
    .ENDIF
    .IF F_EE_CGameSpriteGetKit == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteGetKit, 0
        mov F_EE_CGameSpriteGetKit, eax
    .ENDIF
    .IF F_EE_CGameSpriteGetName == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteGetName, 0
        mov F_EE_CGameSpriteGetName, eax
    .ENDIF
    .IF F_EE_CGameSpriteGetQuickButtons == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteGetQuickButtons, 0
        mov F_EE_CGameSpriteGetQuickButtons, eax
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpell == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteMemorizeSpell, 0
        mov F_EE_CGameSpriteMemorizeSpell, eax
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpellMage == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteMemorizeSpellMage, 0
        mov F_EE_CGameSpriteMemorizeSpellMage, eax
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpellPriest == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteMemorizeSpellPriest, 0
        mov F_EE_CGameSpriteMemorizeSpellPriest, eax
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpellInnate == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteMemorizeSpellInnate, 0
        mov F_EE_CGameSpriteMemorizeSpellInnate, eax
    .ENDIF
    .IF F_EE_CGameSpriteReadySpell == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteReadySpell, 0
        mov F_EE_CGameSpriteReadySpell, eax
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpell == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteRemoveKnownSpell, 0
        mov F_EE_CGameSpriteRemoveKnownSpell, eax
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpellMage == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteRemoveKnownSpellMage, 0
        mov F_EE_CGameSpriteRemoveKnownSpellMage, eax
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpellPriest == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteRemoveKnownSpellPriest, 0
        mov F_EE_CGameSpriteRemoveKnownSpellPriest, eax
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpellInnate == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteRemoveKnownSpellInnate, 0
        mov F_EE_CGameSpriteRemoveKnownSpellInnate, eax
    .ENDIF
    .IF F_EE_CGameSpriteRemoveNewSA == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteRemoveNewSA, 0
        mov F_EE_CGameSpriteRemoveNewSA, eax
    .ENDIF
    .IF F_EE_CGameSpriteRenderHealthBar == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteRenderHealthBar, 0
        mov F_EE_CGameSpriteRenderHealthBar, eax
    .ENDIF
    .IF F_EE_CGameSpriteSetCTT == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteSetCTT, 0
        mov F_EE_CGameSpriteSetCTT, eax
    .ENDIF
    .IF F_EE_CGameSpriteSetColor == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteSetColor, 0
        mov F_EE_CGameSpriteSetColor, eax
    .ENDIF
    .IF F_EE_CGameSpriteShatter == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteShatter, 0
        mov F_EE_CGameSpriteShatter, eax
    .ENDIF
    .IF F_EE_CGameSpriteUnmemorizeSpellMage == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteUnmemorizeSpellMage, 0
        mov F_EE_CGameSpriteUnmemorizeSpellMage, eax
    .ENDIF
    .IF F_EE_CGameSpriteUnmemorizeSpellPriest == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteUnmemorizeSpellPriest, 0
        mov F_EE_CGameSpriteUnmemorizeSpellPriest, eax
    .ENDIF
    .IF F_EE_CGameSpriteUnmemorizeSpellInnate == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameSpriteUnmemorizeSpellInnate, 0
        mov F_EE_CGameSpriteUnmemorizeSpellInnate, eax
    .ENDIF
    ; CInfinity
    .IF F_EE_CInfinityDrawLine == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfinityDrawLine, 0
        mov F_EE_CInfinityDrawLine, eax
    .ENDIF
    .IF F_EE_CInfinityDrawRectangle == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfinityDrawRectangle, 0
        mov F_EE_CInfinityDrawRectangle, eax
    .ENDIF
    .IF F_EE_CInfinityRenderAOE == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfinityRenderAOE, 0
        mov F_EE_CInfinityRenderAOE, eax
    .ENDIF
    ; CInfGame
    .IF F_EE_CInfGameAddCTA == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfGameAddCTA, 0
        mov F_EE_CInfGameAddCTA, eax
    .ENDIF
    .IF F_EE_CInfGameAddCTF == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfGameAddCTF, 0
        mov F_EE_CInfGameAddCTF, eax
    .ENDIF
    .IF F_EE_CInfGameGetCharacterId == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfGameGetCharacterId, 0
        mov F_EE_CInfGameGetCharacterId, eax
    .ENDIF
    ; CObList
    .IF F_EE_CObListRemoveAll == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCObListRemoveAll, 0
        mov F_EE_CObListRemoveAll, eax
    .ENDIF
    .IF F_EE_CObListRemoveHead == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCObListRemoveHead, 0
        mov F_EE_CObListRemoveHead, eax
    .ENDIF
    ; CResRef
    .IF F_EE_CResRefGetResRefStr == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCResRefGetResRefStr, 0
        mov F_EE_CResRefGetResRefStr, eax
    .ENDIF
    .IF F_EE_CResRefIsValid == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCResRefIsValid, 0
        mov F_EE_CResRefIsValid, eax
    .ENDIF
    .IF F_EE_CResRefCResRef == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCResRefCResRef, 0
        mov F_EE_CResRefCResRef, eax
    .ENDIF
    .IF F_EE_CResRefOpEqu == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniCResRefOpEqu, 0
        mov F_EE_CResRefOpEqu, eax
    .ENDIF
    .IF F_EE_CResRefOpNotEqu == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniCResRefOpNotEqu, 0
        mov F_EE_CResRefOpNotEqu, eax
    .ENDIF
    ; CString
    .IF F_EE_CStringOpPlus == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniCStringOpPlus, 0
        mov F_EE_CStringOpPlus, eax
    .ENDIF
    .IF F_EE_CStringCString == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCStringCString, 0
        mov F_EE_CStringCString, eax
    .ENDIF
    .IF F_EE_CStringFindIndex == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCStringFindIndex, 0
        mov F_EE_CStringFindIndex, eax
    .ENDIF
    ; CInfButtonArray
    .IF F_EE_CInfButtonArraySetState == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfButtonArraySetState, 0
        mov F_EE_CInfButtonArraySetState, eax
    .ENDIF
    .IF F_EE_CInfButtonArrayUpdateButtons == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfButtonArrayUpdateButtons, 0
        mov F_EE_CInfButtonArrayUpdateButtons, eax
    .ENDIF
    .IF F_EE_CInfButtonArraySTT == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCInfButtonArraySTT, 0
        mov F_EE_CInfButtonArraySTT, eax
    .ENDIF
    ; CGameEffect
    .IF F_EE_CGameEffectCGameEffect == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameEffectCGameEffect, 0
        mov F_EE_CGameEffectCGameEffect, eax
    .ENDIF
    .IF F_EE_CGameEffectCopyFromBase == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameEffectCopyFromBase, 0
        mov F_EE_CGameEffectCopyFromBase, eax
    .ENDIF
    .IF F_EE_CGameEffectGetItemEffect == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameEffectGetItemEffect, 0
        mov F_EE_CGameEffectGetItemEffect, eax
    .ENDIF
    ; Misc
    .IF F_EE_CGameObjectArrayGetDeny == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameObjectArrayGetDeny, 0
        mov F_EE_CGameObjectArrayGetDeny, eax
    .ENDIF
    .IF F_EE_CGameEffectFireSpell == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameEffectFireSpell, 0
        mov F_EE_CGameEffectFireSpell, eax
    .ENDIF
    .IF F_EE_CGameAIBaseFireSpellPoint == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameAIBaseFireSpellPoint, 0
        mov F_EE_CGameAIBaseFireSpellPoint, eax
    .ENDIF
    .IF F_EE_dimmGetResObject == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szdimmGetResObject, 0
        mov F_EE_dimmGetResObject, eax
    .ENDIF
    .IF F_EE_CAIActionDecode == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCAIActionDecode, 0
        mov F_EE_CAIActionDecode, eax
    .ENDIF
    .IF F_EE_CGameObjectArrayGetDeny == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCGameObjectArrayGetDeny, 0
        mov F_EE_CGameObjectArrayGetDeny, eax
    .ENDIF
    .IF F_EE_CListRemoveAt == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCListRemoveAt, 0
        mov F_EE_CListRemoveAt, eax
    .ENDIF
    .IF F_EE_CRuleTablesMapCSTS == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCRuleTablesMapCSTS, 0
        mov F_EE_CRuleTablesMapCSTS, eax
    .ENDIF
    .IF F_EE_operator_new == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szoperator_new, 0
        mov F_EE_operator_new, eax
    .ENDIF
    .IF F_EE_CAIScriptCAIScript == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szCAIScriptCAIScript, 0
        mov F_EE_CAIScriptCAIScript, eax
    .ENDIF
    ; Other functions
    .IF F__ftol2_sse == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_ftol2_sse, 0
        mov F__ftol2_sse, eax
    .ENDIF
    .IF F__mbscmp == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_mbscmp, 0
        mov F__mbscmp, eax
    .ENDIF
    .IF F_p_malloc == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szp_malloc, 0
        mov F_p_malloc, eax
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Read in FALLBACK pattern addresses of game globals if present in ini file
    ;--------------------------------------------------------------------------
    .IF pp_pChitin == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_pChitin, 0
        mov pp_pChitin, eax
    .ENDIF
    .IF pp_pBaldurChitin == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_pBaldurChitin, 0
        mov pp_pBaldurChitin, eax
    .ENDIF
    .IF pp_backgroundMenu == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_backgroundMenu, 0
        mov pp_backgroundMenu, eax
    .ENDIF
    .IF pp_overlayMenu == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_overlayMenu, 0
        mov pp_overlayMenu, eax
    .ENDIF
    .IF pp_timer_ups == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_timer_ups, 0
        mov pp_timer_ups, eax
    .ENDIF
    .IF pp_aB_1 == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_aB_1, 0
        mov pp_aB_1, eax
    .ENDIF
    .IF pp_CGameSprite_vftable == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_CGameSprite_vftable, 0
        mov pp_CGameSprite_vftable, eax
    .ENDIF
    .IF pp_CAIObjectTypeANYONE == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_CAIObjectTypeANYONE, 0
        mov pp_CAIObjectTypeANYONE, eax
    .ENDIF
    .IF pp_VersionString_Push == 0
        Invoke IniReadValue, Addr szIniEEexFallback, Addr sz_pp_VersionString_Push, 0
        mov pp_VersionString_Push, eax
    .ENDIF


    ; Todo: Add option to return TRUE to continue regardless of missing functions? prob not safe to do so

    ;--------------------------------------------------------------------------
    ; After all that we check if any are still 0 if so we return FALSE
    ;--------------------------------------------------------------------------    
    .IF gEEexLua == FALSE
        ; Check FALLBACK pattern addresses of Lua functions are not null
        .IF F_Lua_createtable == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_getglobal == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_gettop == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_pcallk == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_pushcclosure == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_pushlightuserdata == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_pushlstring == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_pushnumber == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_pushstring == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_rawgeti == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_rawlen == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_setfield == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_setglobal == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_settable == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_settop == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_toboolean == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_tolstring == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_tonumberx == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_touserdata == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_type == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_Lua_typename == 0
            mov eax, FALSE
            ret
        .ENDIF
        .IF F_LuaL_loadstring == 0
            mov eax, FALSE
            ret
        .ENDIF
    .ENDIF

    ; Check FALLBACK pattern addresses of game functions are not null

    ; CAIObjectType
    .IF F_EE_CAIObjectTypeDecode == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CAIObjectTypeRead == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CAIObjectTypeSet == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CAIObjectTypeSSC == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CAIObjectTypeOpEqu == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CDerivedStats
    .IF F_EE_CDerivedStatsGetAtOffset == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CDerivedStatsGetLevel == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CDerivedStatsSetLevel == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CDerivedStatsGetSpellState == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CDerivedStatsSetSpellState == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CDerivedStatsGetWarriorLevel == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CDerivedStatsReload == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CGameSprite
    .IF F_EE_CGameSpriteCGameSprite == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteAddKnownSpell == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteAddKnownSpellMage == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteAddKnownSpellPriest == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteAddNewSA == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteGetActiveStats == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteGetActiveProficiency == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteGetKit == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteGetName == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteGetQuickButtons == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpell == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpellMage == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpellPriest == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteMemorizeSpellInnate == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteReadySpell == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpell == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpellMage == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpellPriest == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteRemoveKnownSpellInnate == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteRemoveNewSA == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteRenderHealthBar == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteSetCTT == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteSetColor == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteShatter == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteUnmemorizeSpellMage == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteUnmemorizeSpellPriest == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameSpriteUnmemorizeSpellInnate == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CInfinity
    .IF F_EE_CInfinityDrawLine == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CInfinityDrawRectangle == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CInfinityRenderAOE == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CInfGame
    .IF F_EE_CInfGameAddCTA == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CInfGameAddCTF == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CInfGameGetCharacterId == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CObList
    .IF F_EE_CObListRemoveAll == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CObListRemoveHead == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CResRef
    .IF F_EE_CResRefGetResRefStr == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CResRefIsValid == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CResRefCResRef == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CResRefOpEqu == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CResRefOpNotEqu == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CString
    .IF F_EE_CStringOpPlus == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CStringCString == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CStringFindIndex == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CInfButtonArray
    .IF F_EE_CInfButtonArraySetState == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CInfButtonArrayUpdateButtons == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CInfButtonArraySTT == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; CGameEffect
    .IF F_EE_CGameEffectCGameEffect == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameEffectCopyFromBase == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameEffectGetItemEffect == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; Misc
    .IF F_EE_CGameObjectArrayGetDeny == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameEffectFireSpell == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameAIBaseFireSpellPoint == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_dimmGetResObject == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CAIActionDecode == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CGameObjectArrayGetDeny == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CListRemoveAt == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CRuleTablesMapCSTS == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_operator_new == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_EE_CAIScriptCAIScript == 0
        mov eax, FALSE
        ret
    .ENDIF
    ; Other functions
    .IF F__ftol2_sse == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F__mbscmp == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF F_p_malloc == 0
        mov eax, FALSE
        ret
    .ENDIF

    ; Check FALLBACK pattern addresses of game globals are not null
    .IF pp_pChitin == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_pBaldurChitin == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_backgroundMenu == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_overlayMenu == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_timer_ups == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_aB_1 == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_CGameSprite_vftable == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_CAIObjectTypeANYONE == 0
        mov eax, FALSE
        ret
    .ENDIF
    .IF pp_VersionString_Push == 0
        mov eax, FALSE
        ret
    .ENDIF    



    mov eax, TRUE
    ret
EEexFallbackAddresses ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexApplyCallPatch - Patches EE Game to Call EEexLuaInit
; Returns: TRUE if succesful or FALSE otherwise.
;------------------------------------------------------------------------------
EEexApplyCallPatch PROC USES EBX ESI dwAddressToPatch:DWORD
    LOCAL dwDistance:DWORD
    LOCAL dwOldProtect:DWORD

    .IF dwAddressToPatch == 0
        mov eax, FALSE
        ret
    .ENDIF

    lea eax, EEexLuaInit
    mov ebx, dwAddressToPatch
    sub eax, ebx
    .IF eax == 0
        mov eax, FALSE
        ret
    .ENDIF
    mov dwDistance, eax

    .IF sdword ptr dwDistance <= 7FFFFFFFh
        mov eax, dwDistance
        sub eax, 5
    .ELSE
        mov eax, dwDistance
    .ENDIF
    mov dwDistance, eax

    ; VirtualProtect to write to address
    Invoke VirtualProtectEx, hEEGameProcess, dwAddressToPatch, 5, PAGE_EXECUTE_READWRITE, Addr dwOldProtect
    .IF eax != NULL
        mov esi, dwAddressToPatch
        mov byte ptr [esi], 0E8h ; call opcode
        inc esi
        mov eax, dwDistance
        mov [esi], eax
        Invoke FlushInstructionCache, hEEGameProcess, NULL, NULL
        Invoke VirtualProtectEx, hEEGameProcess, dwAddressToPatch, 5, dwOldProtect, Addr dwOldProtect
        mov eax, TRUE
    .ELSE
        mov eax, FALSE
    .ENDIF
    ret
EEexApplyCallPatch ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; Process game global variables - obtain pointers to the game globals from
; pattern addresses verified or searched for.
; Returns: none
;------------------------------------------------------------------------------
EEexGameGlobals PROC USES EBX

    ; handle type 1 patterns:
    mov ebx, PatchLocation
    sub ebx, 4d
    mov pp_lua, eax
    mov eax, [ebx] ; address of g_lua
    mov p_lua, eax
    .IF pp_pChitin != 0
        mov ebx, pp_pChitin
        mov p_pChitin, ebx
        mov eax, [ebx]
        mov g_pChitin, eax
    .ENDIF
    .IF pp_pBaldurChitin != 0
        mov ebx, pp_pBaldurChitin
        mov p_pBaldurChitin, ebx
        mov eax, [ebx]
        mov g_pBaldurChitin, eax
    .ENDIF
    .IF pp_backgroundMenu != 0
        mov ebx, pp_backgroundMenu
        mov p_backgroundMenu, ebx
        mov eax, [ebx]
        mov g_backgroundMenu, eax
    .ENDIF
    .IF pp_overlayMenu != 0
        mov ebx, pp_overlayMenu
        mov p_overlayMenu, ebx
        mov eax, [ebx]
        mov g_overlayMenu, eax
    .ENDIF
    .IF pp_timer_ups != 0
        mov ebx, pp_timer_ups
        mov p_timer_ups, ebx
        mov eax, [ebx]
        mov timer_ups, eax
    .ENDIF
    .IF pp_aB_1 != 0
        mov ebx, pp_aB_1
        mov p_aB_1, ebx
        mov eax, [ebx]
        mov aB_1, eax
    .ENDIF
    .IF pp_CGameSprite_vftable != 0
        mov ebx, pp_CGameSprite_vftable
        mov p_CGameSprite_vftable, ebx
        mov eax, [ebx]
        mov CGameSprite_vftable, eax
    .ENDIF
    .IF pp_CAIObjectTypeANYONE != 0
        mov ebx, pp_CAIObjectTypeANYONE
        mov p_CAIObjectTypeANYONE, ebx
        mov eax, [ebx]
        mov CAIObjectTypeANYONE, eax
    .ENDIF
    .IF pp_VersionString_Push != 0
        mov ebx, pp_VersionString_Push
        mov p_VersionString_Push, ebx
        mov eax, [ebx]
        mov VersionString_Push, eax    
    .ENDIF
    
    
;    ; Handle type 2 patterns: call offsets
;    .IF pF_EE_CGameSpriteSetCTT != 0
;        mov ebx, pF_EE_CGameSpriteSetCTT
;        mov eax, [ebx]
;        add ebx, 4 ; for offset part of call x instruction
;        add ebx, eax ; add call offset to get address of function
;        mov F_EE_CGameSpriteSetCTT, ebx
;        IFDEF DEBUG32
;        PrintDec F_EE_CGameSpriteSetCTT
;        ENDIF
;    .ELSE
;        IFDEF DEBUG32
;        PrintText 'pF_EE_CGameSpriteSetCTT == 0'
;        ENDIF
;    .ENDIF

    ret
EEexGameGlobals ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLogInformation - Output some information to the log.
; dwType: 
;
;  INFO_ALL                EQU 0
;  INFO_GAME               EQU 1
;  INFO_DEBUG              EQU 2
;  INFO_VERIFIED           EQU 3
;  INFO_SEARCHED           EQU 4
;  INFO_FALLBACK           EQU 5
;
; Calls EEexLogPatterns
; Returns: None
;------------------------------------------------------------------------------
EEexLogInformation PROC dwType:DWORD
    LOCAL wfad:WIN32_FILE_ATTRIBUTE_DATA
    LOCAL dwFilesizeLow:DWORD

    .IF gEEexLog == LOGLEVEL_NONE
        xor eax, eax
        ret
    .ENDIF

    Invoke LogOpen, FALSE
    ;--------------------------------------------------------------------------
    ; Log basic game information
    ;--------------------------------------------------------------------------
    .IF dwType == INFO_GAME && gEEexLog > LOGLEVEL_NONE
        Invoke LogMessage, CTEXT("Game Information:"), LOG_INFO, 0
        Invoke LogMessage, CTEXT("Filename: "), LOG_NONEWLINE, 0
        Invoke LogMessage, Addr EEexExeFile, LOG_STANDARD, 0
        Invoke GetFileAttributesEx, Addr EEexExeFile, 0, Addr wfad
        mov eax, wfad.nFileSizeLow
        mov dwFilesizeLow, eax
        Invoke LogMessageAndValue, CTEXT("Filesize"), dwFilesizeLow
        Invoke LogMessage, CTEXT("FileVersion: "), LOG_NONEWLINE, 0
        Invoke LogMessage, Addr szFileVersionBuffer, LOG_STANDARD, 0
        Invoke LogMessage, CTEXT("ProductName: "), LOG_NONEWLINE, 0
        Invoke LogMessage, Addr EEGameProductName, LOG_STANDARD, 0
        Invoke LogMessage, CTEXT("ProductVersion: "), LOG_NONEWLINE, 0
        Invoke LogMessage, Addr EEGameProductVersion, LOG_STANDARD, 0
        Invoke LogMessage, 0, LOG_CRLF, 0
        Invoke LogMessage, CTEXT("Options:"), LOG_INFO, 0
        Invoke LogMessageAndValue, CTEXT("Log"), gEEexLog
        Invoke LogMessageAndValue, CTEXT("Lua"), gEEexLua
        Invoke LogMessageAndValue, CTEXT("Hex"), gEEexHex
        Invoke LogMessage, 0, LOG_CRLF, 0
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Log debugging information
    ;--------------------------------------------------------------------------
    .IF dwType == INFO_DEBUG && gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("Debug Information:"), LOG_INFO, 0
        Invoke LogMessageAndHexValue, CTEXT("hProcess"), hEEGameProcess
        Invoke LogMessageAndHexValue, CTEXT("hModule"), hEEGameModule
        Invoke LogMessageAndHexValue, CTEXT("OEP"), EEGameAddressEP
        Invoke LogMessageAndHexValue, CTEXT("BaseAddress"), EEGameBaseAddress
        Invoke LogMessageAndHexValue, CTEXT("ImageSize"), EEGameImageSize
        Invoke LogMessageAndHexValue, CTEXT("AddressStart"), EEGameAddressStart
        Invoke LogMessageAndHexValue, CTEXT("AddressFinish"), EEGameAddressFinish
        Invoke LogMessageAndValue,    CTEXT("PE Sections"), EEGameNoSections
        Invoke LogMessageAndHexValue, CTEXT(".text address"), EEGameSectionTEXTPtr
        Invoke LogMessageAndHexValue, CTEXT(".text size"), EEGameSectionTEXTSize
        Invoke LogMessage, 0, LOG_CRLF, 0
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Log patterns that we partially verified/not verified or all if all verified
    ;--------------------------------------------------------------------------
    .IF dwType == INFO_VERIFIED
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogMessage, CTEXT("Patterns Verify:"), LOG_INFO, 0
            .IF gEEexLog >= LOGLEVEL_DEBUG
                .IF gEEexLuaLibDefined == TRUE && gEEexLua == TRUE
                    Invoke LogMessage, CTEXT("Using static library for lua functions"), LOG_STANDARD, 0
                .ELSEIF gEEexLuaLibDefined == TRUE && gEEexLua == FALSE
                    Invoke LogMessage, CTEXT("Using pattern matching for lua functions"), LOG_STANDARD, 0
                .ELSEIF gEEexLuaLibDefined == FALSE && gEEexLua == TRUE
                    Invoke LogMessage, CTEXT("Lua option enabled, but Lua library not included. Using pattern matching for lua functions"), LOG_STANDARD, 0
                .ELSE ; .gEEexLuaLibDefined == FALSE && gEEexLua == FALSE
                    Invoke LogMessage, CTEXT("Using pattern matching for lua functions"), LOG_STANDARD, 0
                .ENDIF
            .ENDIF        
            ; x patterns verified out of x patterns
            Invoke EEexDwordToAscii, VerifiedPatterns, Addr szVerifiedNo
            Invoke lstrcpy, Addr szPatternMessageBuffer, Addr szVerifiedNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szVerified
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szPatternsOutOf
            Invoke EEexDwordToAscii, TotalPatterns, Addr szTotalPatternNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szTotalPatternNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szPatterns
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            ; x patterns not verified
            Invoke EEexDwordToAscii, NotVerifiedPatterns, Addr szNotVerifiedNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szNotVerifiedNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szNotVerified
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            ; x patterns skipped
            .IF SkippedPatterns > 0
                Invoke EEexDwordToAscii, SkippedPatterns, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkipped
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            .ENDIF
            Invoke LogMessage, Addr szPatternMessageBuffer, LOG_STANDARD, 0
        .ENDIF
        .IF gEEexLog >= LOGLEVEL_DETAIL
            .IF NotVerifiedPatterns > 0
                Invoke LogMessage, CTEXT("Patterns Not Verified:"), LOG_STANDARD, 0
                Invoke EEexLogPatterns, FALSE
                Invoke LogMessage, 0, LOG_CRLF, 0
            .ENDIF
            mov eax, VerifiedPatterns ; show list of all patterns if all verified
            .IF eax == TotalPatterns ; coz we skip searching, otherwise none shown
                Invoke LogMessage, CTEXT("Patterns Verified:"), LOG_STANDARD, 0
                Invoke EEexLogPatterns, TRUE
                Invoke LogMessage, 0, LOG_CRLF, 0
            .ENDIF
        .ENDIF
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Log patterns that we searched and found (or used fallbacks for)
    ;--------------------------------------------------------------------------
    .IF dwType == INFO_SEARCHED || dwType == INFO_FALLBACK
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogMessage, CTEXT("Patterns Search:"), LOG_INFO, 0
            .IF NotVerifiedPatterns > 0
                Invoke EEexDwordToAscii, NotVerifiedPatterns, Addr szNotVerifiedNo
                Invoke lstrcpy, Addr szPatternMessageBuffer, Addr szNotVerifiedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szToSearchFor
                Invoke LogMessage, Addr szPatternMessageBuffer, LOG_STANDARD, 0
            .ENDIF
            ; x patterns found out of x patterns
            Invoke EEexDwordToAscii, FoundPatterns, Addr szFoundNo
            Invoke lstrcpy, Addr szPatternMessageBuffer, Addr szFoundNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szFound
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szPatternsOutOf
            Invoke EEexDwordToAscii, TotalPatterns, Addr szTotalPatternNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szTotalPatternNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szPatterns
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            ; x patterns not found
            Invoke EEexDwordToAscii, NotFoundPatterns, Addr szNotFoundNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szNotFoundNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szNotFound
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            ; x patterns skipped
            .IF SkippedPatterns > 0
                Invoke EEexDwordToAscii, SkippedPatterns, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkipped
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            .ENDIF
        .ENDIF
        Invoke LogMessage, Addr szPatternMessageBuffer, LOG_STANDARD, 0
        .IF gEEexLog >= LOGLEVEL_DETAIL
            .IF dwType == INFO_SEARCHED
                Invoke LogMessage, CTEXT("Patterns Found:"), LOG_STANDARD, 0
            .ELSEIF dwType == INFO_FALLBACK
                Invoke LogMessage, CTEXT("Patterns Found + Fallbacks:"), LOG_STANDARD, 0
            .ENDIF
            Invoke EEexLogPatterns, TRUE
            Invoke LogMessage, 0, LOG_CRLF, 0
            .IF NotFoundPatterns > 0
                Invoke LogMessage, CTEXT("Patterns Not Found:"), LOG_STANDARD, 0
                Invoke EEexLogPatterns, FALSE
                Invoke LogMessage, 0, LOG_CRLF, 0
            .ENDIF
        .ENDIF
    .ENDIF

    xor eax, eax
    ret
EEexLogInformation ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLogPatterns - Log pattern address, found or missing.
; Called from EEexLogInformation
; Returns: None
;------------------------------------------------------------------------------
EEexLogPatterns PROC bFoundPattern:DWORD
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternAddress:DWORD
    LOCAL szPatternName[32]:BYTE
    LOCAL szPatternNo[16]:BYTE

    lea ebx, Patterns
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        mov eax, [ebx].PATTERN.bFound
        .IF eax == bFoundPattern
            mov eax, [ebx].PATTERN.FuncAddress
            .IF eax != 0
                mov eax, [eax]
            .ELSE
                mov eax, 0
            .ENDIF
            mov dwPatternAddress, eax
            mov eax, [ebx].PATTERN.PatName
            .IF eax == 0 ; use fallback of 'PatternX' if no name found
                Invoke EEexDwordToAscii, nPattern, Addr szPatternNo
                Invoke lstrcpy, Addr szPatternName, Addr szPattern
                Invoke lstrcat, Addr szPatternName, Addr szPatternNo
                lea eax, szPatternName ;szPattern
            .ENDIF
            mov lpszPatternName, eax

            .IF bFoundPattern == TRUE
                Invoke LogMessage, lpszPatternName, LOG_NONEWLINE, 1
                Invoke LogMessageAndHexValue, 0, dwPatternAddress
            .ELSE
                Invoke LogMessage, lpszPatternName, LOG_STANDARD, 1
            .ENDIF

            ;Invoke LogMessageAndHexValue, lpszPatternName, dwPatternAddress
        .ENDIF
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW
     ret
EEexLogPatterns ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexEEFileInformation - Get EE File ProductVersion, ProductName & FileVersion
; Returns: TRUE if successful or FALSE otherwise
;------------------------------------------------------------------------------
EEexEEFileInformation PROC USES EBX
    LOCAL verHandle:DWORD
    LOCAL verData:DWORD
    LOCAL verSize:DWORD
    LOCAL verInfo:DWORD
    LOCAL hHeap:DWORD
    LOCAL pBuffer:DWORD
    LOCAL lenBuffer:DWORD
    LOCAL lpszProductVersion:DWORD
    LOCAL lpszProductName:DWORD
    LOCAL FileVersion1:DWORD
    LOCAL FileVersion2:DWORD
    LOCAL FileVersion3:DWORD
    LOCAL FileVersion4:DWORD

    Invoke GetFileVersionInfoSize, Addr EEexExeFile, Addr verHandle
    .IF eax != 0
        mov verSize, eax
        Invoke GetProcessHeap
        .IF eax != 0
            mov hHeap, eax
            Invoke HeapAlloc, eax, 0, verSize
            .IF eax != 0
                mov verData, eax
                Invoke GetFileVersionInfo, Addr EEexExeFile, 0, verSize, verData
                .IF eax != 0

                    Invoke VerQueryValue, verData, Addr szLang, Addr pBuffer, Addr lenBuffer
                    .IF eax != 0 && lenBuffer != 0
                        ; Get ProductVersion String
                        mov ebx, pBuffer
                        movzx eax,[ebx.LANGANDCODEPAGE].wLanguage
                        movzx ebx,[ebx.LANGANDCODEPAGE].wCodepage
                        Invoke wsprintf, Addr szProductVersionBuffer, Addr szProductVersion, eax, ebx
                        Invoke VerQueryValue, verData, Addr szProductVersionBuffer, Addr lpszProductVersion, addr lenBuffer
                        .IF eax != 0 && lenBuffer != 0
                            Invoke lstrcpyn, Addr EEGameProductVersion, lpszProductVersion, SIZEOF EEGameProductVersion
                        .ENDIF

                        ; Get ProductName String
                        mov ebx, pBuffer
                        movzx eax,[ebx.LANGANDCODEPAGE].wLanguage
                        movzx ebx,[ebx.LANGANDCODEPAGE].wCodepage
                        Invoke wsprintf, Addr szProductNameBuffer, Addr szProductName, eax, ebx
                        Invoke VerQueryValue, verData, Addr szProductNameBuffer, Addr lpszProductName, addr lenBuffer
                        .IF eax != 0 && lenBuffer != 0
                            Invoke lstrcpyn, Addr EEGameProductName, lpszProductName, SIZEOF EEGameProductName
                        .ENDIF
                    .ELSE
                        Invoke HeapFree, hHeap, 0, verData
                        mov eax, FALSE
                        ret
                    .ENDIF
                    ; Get FILEVERSION
                    Invoke VerQueryValue, verData, Addr szVerRoot, Addr pBuffer, Addr lenBuffer
                    .IF eax != 0 && lenBuffer != 0
                        lea ebx, pBuffer
                        mov eax, [ebx]
                        mov verInfo, eax
                        mov ebx, eax
                        .IF [ebx].VS_FIXEDFILEINFO.dwSignature == 0FEEF04BDh
                            mov ebx, verInfo
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionMS
                            shr eax, 16d
                            and eax, 0FFFFh
                            mov FileVersion1, eax
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionMS
                            shr eax, 0
                            and eax, 0FFFFh
                            mov FileVersion2, eax
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionLS
                            shr eax, 16d
                            and eax, 0FFFFh
                            mov FileVersion3, eax
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionLS
                            shr eax, 0
                            and eax, 0FFFFh
                            mov FileVersion4, eax
                            Invoke wsprintf, Addr szFileVersionBuffer, Addr szFileVersion, FileVersion1, FileVersion2, FileVersion3, FileVersion4
                        .ENDIF
                    .ELSE
                        Invoke HeapFree, hHeap, 0, verData
                        mov eax, FALSE
                        ret
                    .ENDIF
                    ; Free Heap after getting information
                    Invoke HeapFree, hHeap, 0, verData
                    mov eax, TRUE
                    ret

                .ELSE
                    Invoke HeapFree, hHeap, 0, verData
                    mov eax, FALSE
                    ret
                .ENDIF
            .ELSE
                mov eax, FALSE
                ret
            .ENDIF
        .ELSE
            mov eax, FALSE
            ret
        .ENDIF
    .ELSE
        mov eax, FALSE
        ret
    .ENDIF
    ret
EEexEEFileInformation ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexEEGameInformation - Determine EE game type and stores it in gEEGameType
; Returns: eax will contain Beamdog EE Game Type:
;
;  GAME_UNKNOWN            EQU 0h
;  GAME_BGEE               EQU 1h
;  GAME_BG2EE              EQU 2h
;  GAME_BGSOD              EQU 4h
;  GAME_IWDEE              EQU 8h
;  GAME_PSTEE              EQU 10h
;
; Devnote: Defined as a bit mask - might be used in future for combining game 
; types in a pattern field to include/exclude specific patterns based on game?
;------------------------------------------------------------------------------
EEexEEGameInformation PROC USES ECX EDI ESI
    ; walk backwards filepath to get the \ or / and get just the filename.exe
    Invoke lstrlen, Addr EEexExeFile
    lea edi, EEGameExeName
    lea esi, EEexExeFile
    add esi, eax
    mov ecx, eax
    .WHILE ecx != 0
        movzx eax, byte ptr [esi]
        .IF al == '\' || al == '/'
            inc esi
            movzx eax, byte ptr [esi] ; copy bytes onwards
            .WHILE al != 0
                .IF al >= 'a' && al <= 'z'
                    sub al, 32 ; convert to uppercase
                .ENDIF
                mov byte ptr [edi], al
                inc edi
                inc esi
                movzx eax, byte ptr [esi]
            .ENDW
            .BREAK
        .ENDIF
        dec esi
        dec ecx
    .ENDW
    mov byte ptr [edi], 0 ; null end of EEGameExeName string

    Invoke lstrlen, Addr EEGameExeName
    .IF eax != 0
        Invoke lstrcmp, Addr EEGameExeName, Addr szBeamdog_BGEE
        .IF eax == 0 ; found match
            ;  do additional check to decide which it is BGEE or BG2EE
            Invoke lstrcmp, Addr szBeamdog_BG2EE_Name, Addr EEGameProductName
            .IF eax == 0 ; found match
                mov gEEGameType, GAME_BG2EE
            .ELSE
                mov gEEGameType, GAME_BGEE
            .ENDIF
            ret
        .ENDIF
        Invoke lstrcmpi, Addr EEGameExeName, Addr szBeamdog_BGSOD
        .IF eax == 0 ; found match
            mov gEEGameType, GAME_BGSOD
            ret
        .ENDIF
        Invoke lstrcmpi, Addr EEGameExeName, Addr szBeamdog_IWDEE
        .IF eax == 0 ; found match
            mov gEEGameType, GAME_IWDEE
            ret
        .ENDIF
        Invoke lstrcmpi, Addr EEGameExeName, Addr szBeamdog_PSTEE
        .IF eax == 0 ; found match
            mov gEEGameType, GAME_PSTEE
            ret
        .ENDIF
    .ENDIF
    mov gEEGameType, GAME_UNKNOWN
    ret
EEexEEGameInformation ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexWriteAddressesToIni - Write pattern functions or globals addresses to ini
; Returns: None
;------------------------------------------------------------------------------
EEexWriteAddressesToIni PROC

    Invoke IniSetPatchLocation, PatchLocation

    .IF gEEexLua == TRUE && gEEexLuaLibDefined == TRUE
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_createtable, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_getglobal, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_gettop, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pcallk, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushcclosure, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushlightuserdata, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushlstring, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushnumber, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushstring, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_rawgeti, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_rawlen, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_setfield, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_setglobal, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_settable, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_settop, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_toboolean, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_tolstring, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_tonumberx, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_touserdata, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_type, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_typename, 0
        Invoke IniWriteValue, Addr szIniEEex, Addr szLuaL_loadstring, 0
    .ELSE ; gEEexLua == FALSE
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_createtable, F_Lua_createtable
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_getglobal, F_Lua_getglobal
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_gettop, F_Lua_gettop
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pcallk, F_Lua_pcallk
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushcclosure, F_Lua_pushcclosure
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushlightuserdata, F_Lua_pushlightuserdata
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushlstring, F_Lua_pushlstring
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushnumber, F_Lua_pushnumber
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_pushstring, F_Lua_pushstring
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_rawgeti, F_Lua_rawgeti
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_rawlen, F_Lua_rawlen
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_setfield, F_Lua_setfield
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_setglobal, F_Lua_setglobal
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_settable, F_Lua_settable
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_settop, F_Lua_settop
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_toboolean, F_Lua_toboolean
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_tolstring, F_Lua_tolstring
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_tonumberx, F_Lua_tonumberx
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_touserdata, F_Lua_touserdata
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_type, F_Lua_type
        Invoke IniWriteValue, Addr szIniEEex, Addr szLua_typename, F_Lua_typename
        Invoke IniWriteValue, Addr szIniEEex, Addr szLuaL_loadstring, F_LuaL_loadstring
    .ENDIF


    ;--------------------------------------------------------------------------
    ; Write out pattern addresses of game functions to ini file
    ;--------------------------------------------------------------------------
    ; CAIObjectType
    Invoke IniWriteValue, Addr szIniEEex, Addr szCAIObjectTypeDecode, F_EE_CAIObjectTypeDecode
    Invoke IniWriteValue, Addr szIniEEex, Addr szCAIObjectTypeRead, F_EE_CAIObjectTypeRead
    Invoke IniWriteValue, Addr szIniEEex, Addr szCAIObjectTypeSet, F_EE_CAIObjectTypeSet
    Invoke IniWriteValue, Addr szIniEEex, Addr szCAIObjectTypeSSC, F_EE_CAIObjectTypeSSC
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniCAIObjectTypeOpEqu, F_EE_CAIObjectTypeOpEqu
    ; CDerivedStats
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsGetAtOffset, F_EE_CDerivedStatsGetAtOffset
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsGetLevel, F_EE_CDerivedStatsGetLevel
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsSetLevel, F_EE_CDerivedStatsSetLevel
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsGetSpellState, F_EE_CDerivedStatsGetSpellState
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsSetSpellState, F_EE_CDerivedStatsSetSpellState
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsGetWarriorLevel, F_EE_CDerivedStatsGetWarriorLevel
    Invoke IniWriteValue, Addr szIniEEex, Addr szCDerivedStatsReload, F_EE_CDerivedStatsReload
    ; CGameSprite
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteCGameSprite, F_EE_CGameSpriteCGameSprite
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteAddKnownSpell, F_EE_CGameSpriteAddKnownSpell
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteAddKnownSpellMage, F_EE_CGameSpriteAddKnownSpellMage
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteAddKnownSpellPriest, F_EE_CGameSpriteAddKnownSpellPriest
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteAddNewSA, F_EE_CGameSpriteAddNewSA
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteGetActiveStats, F_EE_CGameSpriteGetActiveStats
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteGetActiveProficiency, F_EE_CGameSpriteGetActiveProficiency
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteGetKit, F_EE_CGameSpriteGetKit
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteGetName, F_EE_CGameSpriteGetName
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteGetQuickButtons, F_EE_CGameSpriteGetQuickButtons
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpell, F_EE_CGameSpriteMemorizeSpell
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpellMage, F_EE_CGameSpriteMemorizeSpellMage
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpellPriest, F_EE_CGameSpriteMemorizeSpellPriest
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteMemorizeSpellInnate, F_EE_CGameSpriteMemorizeSpellInnate
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteReadySpell, F_EE_CGameSpriteReadySpell
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpell, F_EE_CGameSpriteRemoveKnownSpell
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpellMage, F_EE_CGameSpriteRemoveKnownSpellMage
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpellPriest, F_EE_CGameSpriteRemoveKnownSpellPriest
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteRemoveKnownSpellInnate, F_EE_CGameSpriteRemoveKnownSpellInnate
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteRemoveNewSA, F_EE_CGameSpriteRemoveNewSA
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteRenderHealthBar, F_EE_CGameSpriteRenderHealthBar
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteSetCTT, F_EE_CGameSpriteSetCTT
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteSetColor, F_EE_CGameSpriteSetColor
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteShatter, F_EE_CGameSpriteShatter
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteUnmemorizeSpellMage, F_EE_CGameSpriteUnmemorizeSpellMage
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteUnmemorizeSpellPriest, F_EE_CGameSpriteUnmemorizeSpellPriest
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameSpriteUnmemorizeSpellInnate, F_EE_CGameSpriteUnmemorizeSpellInnate
    ; CInfinity
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfinityDrawLine, F_EE_CInfinityDrawLine
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfinityDrawRectangle, F_EE_CInfinityDrawRectangle
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfinityRenderAOE, F_EE_CInfinityRenderAOE
    ; CInfGame
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfGameAddCTA, F_EE_CInfGameAddCTA
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfGameAddCTF, F_EE_CInfGameAddCTF
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfGameGetCharacterId, F_EE_CInfGameGetCharacterId
    ; CObList
    Invoke IniWriteValue, Addr szIniEEex, Addr szCObListRemoveAll, F_EE_CObListRemoveAll
    Invoke IniWriteValue, Addr szIniEEex, Addr szCObListRemoveHead, F_EE_CObListRemoveHead
    ; CResRef
    Invoke IniWriteValue, Addr szIniEEex, Addr szCResRefGetResRefStr, F_EE_CResRefGetResRefStr
    Invoke IniWriteValue, Addr szIniEEex, Addr szCResRefIsValid, F_EE_CResRefIsValid
    Invoke IniWriteValue, Addr szIniEEex, Addr szCResRefCResRef, F_EE_CResRefCResRef
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniCResRefOpEqu, F_EE_CResRefOpEqu
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniCResRefOpNotEqu, F_EE_CResRefOpNotEqu
    ; CString
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniCStringOpPlus, F_EE_CStringOpPlus
    Invoke IniWriteValue, Addr szIniEEex, Addr szCStringCString, F_EE_CStringCString
    Invoke IniWriteValue, Addr szIniEEex, Addr szCStringFindIndex, F_EE_CStringFindIndex
    ; CInfButtonArray
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfButtonArraySetState, F_EE_CInfButtonArraySetState
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfButtonArrayUpdateButtons, F_EE_CInfButtonArrayUpdateButtons
    Invoke IniWriteValue, Addr szIniEEex, Addr szCInfButtonArraySTT, F_EE_CInfButtonArraySTT
    ; CGameEffect
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameEffectCGameEffect, F_EE_CGameEffectCGameEffect
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameEffectCopyFromBase, F_EE_CGameEffectCopyFromBase
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameEffectGetItemEffect, F_EE_CGameEffectGetItemEffect
     ; Misc
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameObjectArrayGetDeny, F_EE_CGameObjectArrayGetDeny
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameEffectFireSpell, F_EE_CGameEffectFireSpell
    Invoke IniWriteValue, Addr szIniEEex, Addr szCGameAIBaseFireSpellPoint, F_EE_CGameAIBaseFireSpellPoint
    Invoke IniWriteValue, Addr szIniEEex, Addr szdimmGetResObject, F_EE_dimmGetResObject
    Invoke IniWriteValue, Addr szIniEEex, Addr szCAIActionDecode, F_EE_CAIActionDecode
    Invoke IniWriteValue, Addr szIniEEex, Addr szCListRemoveAt, F_EE_CListRemoveAt
    Invoke IniWriteValue, Addr szIniEEex, Addr szCRuleTablesMapCSTS, F_EE_CRuleTablesMapCSTS
    Invoke IniWriteValue, Addr szIniEEex, Addr szoperator_new, F_EE_operator_new
    Invoke IniWriteValue, Addr szIniEEex, Addr szCAIScriptCAIScript, F_EE_CAIScriptCAIScript
    ; Other functions
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_ftol2_sse, F__ftol2_sse
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_mbscmp, F__mbscmp
    Invoke IniWriteValue, Addr szIniEEex, Addr szp_malloc, F_p_malloc

    ;--------------------------------------------------------------------------
    ; Write out pattern addresses of game globals to ini file
    ;--------------------------------------------------------------------------
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_pChitin, pp_pChitin
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_pBaldurChitin, pp_pBaldurChitin
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_backgroundMenu, pp_backgroundMenu
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_overlayMenu, pp_overlayMenu
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_timer_ups, pp_timer_ups
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_aB_1, pp_aB_1
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_CGameSprite_vftable, pp_CGameSprite_vftable
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_CAIObjectTypeANYONE, pp_CAIObjectTypeANYONE
    Invoke IniWriteValue, Addr szIniEEex, Addr sz_pp_VersionString_Push, pp_VersionString_Push
 
    xor eax, eax
    ret
EEexWriteAddressesToIni ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexDwordToAscii - Paul Dixon's utoa_ex function. unsigned dword to ascii.
; Returns: Buffer pointed to by lpszAsciiString will contain ascii string
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
EEexDwordToAscii PROC dwValue:DWORD, lpszAsciiString:DWORD
    mov eax, [esp+4]                ; uvar      : unsigned variable to convert
    mov ecx, [esp+8]                ; pbuffer   : pointer to result buffer

    push esi
    push edi

    jmp udword

  align 4
  chartab:
    dd "00","10","20","30","40","50","60","70","80","90"
    dd "01","11","21","31","41","51","61","71","81","91"
    dd "02","12","22","32","42","52","62","72","82","92"
    dd "03","13","23","33","43","53","63","73","83","93"
    dd "04","14","24","34","44","54","64","74","84","94"
    dd "05","15","25","35","45","55","65","75","85","95"
    dd "06","16","26","36","46","56","66","76","86","96"
    dd "07","17","27","37","47","57","67","77","87","97"
    dd "08","18","28","38","48","58","68","78","88","98"
    dd "09","19","29","39","49","59","69","79","89","99"

  udword:
    mov esi, ecx                    ; get pointer to answer
    mov edi, eax                    ; save a copy of the number

    mov edx, 0D1B71759h             ; =2^45\10000    13 bit extra shift
    mul edx                         ; gives 6 high digits in edx

    mov eax, 68DB9h                 ; =2^32\10000+1

    shr edx, 13                     ; correct for multiplier offset used to give better accuracy
    jz short skiphighdigits         ; if zero then don't need to process the top 6 digits

    mov ecx, edx                    ; get a copy of high digits
    imul ecx, 10000                 ; scale up high digits
    sub edi, ecx                    ; subtract high digits from original. EDI now = lower 4 digits

    mul edx                         ; get first 2 digits in edx
    mov ecx, 100                    ; load ready for later

    jnc short next1                 ; if zero, supress them by ignoring
    cmp edx, 9                      ; 1 digit or 2?
    ja   ZeroSupressed              ; 2 digits, just continue with pairs of digits to the end

    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dh                   ; but only write the 1 we need, supress the leading zero
    inc esi                         ; update pointer by 1
    jmp  ZS1                        ; continue with pairs of digits to the end

  align 16
  next1:
    mul ecx                         ; get next 2 digits
    jnc short next2                 ; if zero, supress them by ignoring
    cmp edx, 9                      ; 1 digit or 2?
    ja   ZS1a                       ; 2 digits, just continue with pairs of digits to the end

    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dh                   ; but only write the 1 we need, supress the leading zero
    add esi, 1                      ; update pointer by 1
    jmp  ZS2                        ; continue with pairs of digits to the end

  align 16
  next2:
    mul ecx                         ; get next 2 digits
    jnc short next3                 ; if zero, supress them by ignoring
    cmp edx, 9                      ; 1 digit or 2?
    ja   ZS2a                       ; 2 digits, just continue with pairs of digits to the end

    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dh                   ; but only write the 1 we need, supress the leading zero
    add esi, 1                      ; update pointer by 1
    jmp  ZS3                        ; continue with pairs of digits to the end

  align 16
  next3:

  skiphighdigits:
    mov eax, edi                    ; get lower 4 digits
    mov ecx, 100

    mov edx, 28F5C29h               ; 2^32\100 +1
    mul edx
    jnc short next4                 ; if zero, supress them by ignoring
    cmp edx, 9                      ; 1 digit or 2?
    ja  short ZS3a                  ; 2 digits, just continue with pairs of digits to the end

    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dh                   ; but only write the 1 we need, supress the leading zero
    inc esi                         ; update pointer by 1
    jmp short  ZS4                  ; continue with pairs of digits to the end

  align 16
  next4:
    mul ecx                         ; this is the last pair so don; t supress a single zero
    cmp edx, 9                      ; 1 digit or 2?
    ja  short ZS4a                  ; 2 digits, just continue with pairs of digits to the end

    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dh                   ; but only write the 1 we need, supress the leading zero
    mov byte ptr [esi+1], 0         ; zero terminate string

    pop edi
    pop esi
    ret 8

  align 16
  ZeroSupressed:
    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dx
    add esi, 2                      ; write them to answer

  ZS1:
    mul ecx                         ; get next 2 digits
  ZS1a:
    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dx                   ; write them to answer
    add esi, 2

  ZS2:
    mul ecx                         ; get next 2 digits
  ZS2a:
    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dx                   ; write them to answer
    add esi, 2

  ZS3:
    mov eax, edi                    ; get lower 4 digits
    mov edx, 28F5C29h               ; 2^32\100 +1
    mul edx                         ; edx= top pair
  ZS3a:
    mov edx, chartab[edx*4]         ; look up 2 digits
    mov [esi], dx                   ; write to answer
    add esi, 2                      ; update pointer

  ZS4:
    mul ecx                         ; get final 2 digits
  ZS4a:
    mov edx, chartab[edx*4]         ; look them up
    mov [esi], dx                   ; write to answer

    mov byte ptr [esi+2], 0         ; zero terminate string

  sdwordend:

    pop edi
    pop esi
    ret 8
EEexDwordToAscii ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef
;------------------------------------------------------------------------------


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexAsciiHexToDword - Masm32 htodw function. hex string into dword value.
; Returns: dword value of the decoded hex string.
;------------------------------------------------------------------------------
EEexAsciiHexToDword PROC lpszAsciiHexString:DWORD
    ; written by Alexander Yackubtchik

    push ebx
    push ecx
    push edx
    push edi
    push esi

    mov edi, lpszAsciiHexString
    mov esi, lpszAsciiHexString

    ALIGN 4

again:
    mov al,[edi]
    inc edi
    or  al,al
    jnz again
    sub esi,edi
    xor ebx,ebx
    add edi,esi
    xor edx,edx
    not esi             ;esi = lenth

    .WHILE esi != 0
        mov al, [edi]
        cmp al,'A'
        jb figure
        sub al,'a'-10
        adc dl,0
        shl dl,5            ;if cf set we get it bl 20h else - 0
        add al,dl
        jmp next
    figure:
        sub al,'0'
    next:
        lea ecx,[esi-1]
        and eax, 0Fh
        shl ecx,2           ;mul ecx by log 16(2)
        shl eax,cl          ;eax * 2^ecx
        add ebx, eax
        inc edi
        dec esi
    .ENDW

    mov eax,ebx

    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx

    ret
EEexAsciiHexToDword ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexDwordToAsciiHex - Convert dword to ascii hex string.
; lpszAsciiHexString must be at least 11 bytes long.
; Returns: Buffer pointed to by lpszAsciiHexString will contain ascii hex string
;------------------------------------------------------------------------------
EEexDwordToAsciiHex PROC USES EDI dwValue:DWORD, lpszAsciiHexString:DWORD, bUppercase:DWORD
    LOCAL dwVal:DWORD
    LOCAL lpHexStart:DWORD

    mov edi, lpszAsciiHexString
    mov byte ptr [edi], '0'     ; 0
    mov byte ptr [edi+1], 'x'   ; x
    mov eax, edi
    add eax, 2
    mov lpHexStart, eax
    add edi, 10d
    mov byte ptr [edi], 0       ; null string
    dec edi

    mov eax, dwValue
    mov dwVal, eax

convert:
    mov eax, dwVal
    and eax, 0Fh                ; get digit
    .IF al < 10
        add al, "0"             ; convert digits 0-9 to ascii
    .ELSE
        .IF bUppercase == TRUE
            add al, ("A"-10)    ; convert digits 0Ah to 0Fh to uppercase ascii A-F
        .ELSE
            add al, ("a"-10)    ; convert digits 0Ah to 0Fh to lowercase ascii a-f
        .ENDIF
    .ENDIF
    mov byte ptr [edi], al
    dec edi
    ror dwVal, 4
    cmp edi, lpHexStart
    jae convert
    ret
EEexDwordToAsciiHex ENDP



END DllEntry














