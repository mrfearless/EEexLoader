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
;EEEX_FUNCTION_TIMERS EQU 1 ; comment out if we dont require timers
EEEX_LOGGING EQU 1 ; comment out if we dont require logging (exclude logging from EEexLua for example) 
;EEEX_LUALIB EQU 1 ; comment out to use lua function found in EE game. Otherwise use some lua functions from static lib


;DEBUG32 EQU 1
;IFDEF DEBUG32
;    PRESERVEXMMREGS equ 1
;    includelib M:\Masm32\lib\Debug32.lib
;    DBG32LIB equ 1
;    DEBUGEXE textequ <'M:\Masm32\DbgWin.exe'>
;    include M:\Masm32\include\debug32.inc
;ENDIF

CTEXT MACRO Text
    LOCAL szText
    .DATA
    szText DB Text, 0
    .CODE
    EXITM <Offset szText>   
ENDM


include EEex.inc
include EEexPattern.asm
include EEexIni.asm
include EEexLog.asm
include EEexLua.asm

.CODE


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


;------------------------------------------------------------------------------
; EEexInitDll - Intialize EEex.dll 
; Read ini file (if exists) for lua function address information and begin
; verifying / searching for lua function addresses, and patch address location.
; Returns: None
;------------------------------------------------------------------------------
EEexInitDll PROC USES EBX
    LOCAL bSearchFunctions:DWORD
    LOCAL bVerifyFunctions:DWORD
    LOCAL ptrNtHeaders:DWORD
    LOCAL ptrSections:DWORD
    LOCAL ptrCurrentSection:DWORD
    LOCAL CurrentSection:DWORD

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    mov T_EEexInitDll, eax     
    ENDIF

    Invoke EEexInitGlobals
    mov bVerifyFunctions, eax
    
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
                    .ELSEIF eax == 'adr.' || eax == 'ADR.'; .rda .RDA
                        mov eax, [ebx].IMAGE_SECTION_HEADER.SizeOfRawData
                        mov EEGameSectionRDATASize, eax
                        mov eax, [ebx].IMAGE_SECTION_HEADER.VirtualAddress
                        add eax, EEGameBaseAddress
                        mov EEGameSectionRDATAPtr, eax
                    .ELSEIF eax == 'tad.' || eax == 'TAD.' ; .dat .DAT
                        mov eax, [ebx].IMAGE_SECTION_HEADER.SizeOfRawData
                        mov EEGameSectionDATASize, eax
                        mov eax, [ebx].IMAGE_SECTION_HEADER.VirtualAddress
                        add eax, EEGameBaseAddress
                        mov EEGameSectionDATAPtr, eax
                    .ENDIF
                    add ptrCurrentSection, SIZEOF IMAGE_SECTION_HEADER
                    inc CurrentSection
                    mov eax, CurrentSection
                .ENDW
                ;--------------------------------------------------------------
                ; Finished Reading PE Sections
                ;--------------------------------------------------------------
                
                ;--------------------------------------------------------------
                ; Devnote: Currently only need .text/code
                ; But just in case, in future if we need a codecave in one of 
                ; the .data or .rdata section we have the info
                ; TODO, only read for 1 section to get .text/code - what if 
                ; section ordering is different for some reason?
                ;--------------------------------------------------------------
                
                ;--------------------------------------------------------------
                ; Continue Onwards To Verify / Search Stage
                ;--------------------------------------------------------------
            .ELSE ; IMAGE_NT_SIGNATURE Failed
                IFDEF EEEX_LOGGING
                Invoke LogOpen, FALSE
                Invoke LogMessage, Addr szErrorImageNtSig, LOG_ERROR, 0
                Invoke LogClose
                ENDIF
                ret ; Exit EEexInitDll
            .ENDIF
        .ELSE ; IMAGE_DOS_SIGNATURE Failed
            IFDEF EEEX_LOGGING
            Invoke LogOpen, FALSE
            Invoke LogMessage, Addr szErrorImageDosSig, LOG_ERROR, 0
            Invoke LogClose
            ENDIF
            ret ; Exit EEexInitDll
        .ENDIF        
    .ELSE ; GetModuleInformation Failed
        IFDEF EEEX_LOGGING
        Invoke LogOpen, FALSE
        Invoke LogMessage, Addr szErrorGetModuleInfo, LOG_ERROR, 0
        Invoke LogClose
        ENDIF
        ret ; Exit EEexInitDll
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished EE Game Module Info And Sections Stage
    ;--------------------------------------------------------------------------
    
    
    Invoke EEexLogInformation, INFO_DEBUG
    
    
    ;--------------------------------------------------------------------------
    ; Verify EE Game Lua Function Addresses / Search For Addresses
    ;--------------------------------------------------------------------------
    ; PatchLocation != 0 && Func_LuaL_loadstring != 0 && Func_Lua_pushnumber != 0 && Func_Lua_pushcclosure != 0 && Func_Lua_tolstring != 0 && Func_Lua_setglobal != 0 && Func_Lua_tonumberx != 0 && Func__ftol2_sse != 0    
    mov bSearchFunctions, TRUE ; Set to true to assume we will search for functions
    .IF bVerifyFunctions == TRUE ; only verify if all addresses were not 0
        IFDEF DEBUG32
        PrintText 'EEexVerifyFunctions'
        ENDIF
        Invoke EEexVerifyFunctions
        .IF eax == TRUE ; no need to search for function as we have verified them
            IFDEF DEBUG32
            PrintText 'EEexVerifyFunctions Success'
            ENDIF
            Invoke EEexLogInformation, INFO_VERIFIED
            mov bSearchFunctions, FALSE
        .ELSE
            IFDEF DEBUG32
            PrintText 'EEexVerifyFunctions Failed'
            ENDIF
        .ENDIF
        IFDEF EEEX_FUNCTION_TIMERS
        IFDEF EEEX_LOGGING
        Invoke LogMessageAndValue, CTEXT("EEexVerifyFunctions Execution Time (ms)"), T_EEexVerifyFunctions
        Invoke LogMessage, 0, LOG_CRLF, 0
        ENDIF
        ENDIF
    .ENDIF
    
    .IF bSearchFunctions == TRUE ; If we failed to verify functions or 1st run, or any single function was 0 then begin search
        IFDEF DEBUG32
        PrintText 'EEexSearchFunctions'
        ENDIF
        Invoke EEexSearchFunctions
        .IF eax == TRUE ; EE Game Lua Function Addresses Found - Write Info To Ini File
            IFDEF DEBUG32
            PrintText 'EEexSearchFunctions Success'
            ENDIF
            Invoke EEexLogInformation, INFO_SEARCHED
            IFDEF EEEX_FUNCTION_TIMERS
            IFDEF EEEX_LOGGING
            Invoke LogMessageAndValue, CTEXT("EEexSearchFunctions Execution Time (ms)"), T_EEexSearchFunctions
            Invoke LogMessage, 0, LOG_CRLF, 0
            ENDIF
            ENDIF
            Invoke IniClearFallbackSection
            Invoke EEexWriteFunctionsToIni
            ;------------------------------------------------------------------
            ; Continue Onwards To Apply Patch Stage
            ;------------------------------------------------------------------
        .ELSE ; EE Game Lua Function Addresses NOT VERIFIED OR FOUND!
            IFDEF DEBUG32
            PrintText 'EEexSearchFunctions Failed'
            PrintText 'EEexFallbackAddresses'
            ENDIF
            Invoke EEexFallbackAddresses ; check if any fallback addresses are in ini
            .IF eax == FALSE ; Have to tell user we dont have any addresses
                Invoke EEexLogInformation, INFO_SEARCHED
                IFDEF EEEX_FUNCTION_TIMERS
                IFDEF EEEX_LOGGING
                Invoke LogMessageAndValue, CTEXT("EEexSearchFunctions Execution Time (ms)"), T_EEexSearchFunctions
                Invoke LogMessage, 0, LOG_CRLF, 0
                ENDIF
                ENDIF            
                ; Error tell user that cannot find or verify functions - might be a new build
                IFDEF EEEX_LOGGING
                Invoke LogOpen, FALSE
                Invoke LogMessage, Addr szErrorSearchFunctions, LOG_ERROR, 0 ; CTEXT("Cannot find or verify EE game lua functions - might be an unsupported or new build of EE game.")
                Invoke LogClose
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
        PrintText 'EEexSearchFunctions Skipped'
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
        Invoke EEexApplyCallPatch, PatchLocation ; (call EEexLuaInit)
        .IF eax == TRUE ; Patch Success! - Write status to log and exit EEex.dll
            IFDEF EEEX_LOGGING
            Invoke LogMessage, CTEXT("EEexApplyCallPatch - applied patch"), LOG_INFO, 0
            ENDIF
            ;------------------------------------------------------------------  
            ; Note: Redirection from EE Game to our EEexLuaInit function occurs
            ; after EEex.dll:EEexInitDll returns to EE Game, during which time 
            ; it will eventually hit our patched instruction: call EEexLuaInit
            ;------------------------------------------------------------------
        .ELSE ; Patch Failure! - Write status to log and exit EEex.dll
            IFDEF EEEX_LOGGING
            Invoke LogMessage, CTEXT("EEexApplyCallPatch - failed to apply patch"), LOG_ERROR, 0
            Invoke LogClose
            ENDIF
        .ENDIF
    .ELSE
        IFDEF EEEX_LOGGING
        Invoke LogMessage, CTEXT("PatchLocation is NULL!"), LOG_ERROR, 0
        Invoke LogClose
        ENDIF
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished Apply Patch Stage
    ;--------------------------------------------------------------------------
    
    
    Invoke EEexGameGlobals ; get pointers to game globals

    
    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    sub eax, T_EEexInitDll
    mov T_EEexInitDll, eax
    IFDEF EEEX_LOGGING
    Invoke LogMessage, 0, LOG_CRLF, 0
    Invoke LogMessageAndValue, CTEXT("EEexInitDll Execution Time (ms)"), T_EEexInitDll
    ENDIF
    ENDIF        


    ;--------------------------------------------------------------------------
    ; EEex.DLL EXITS HERE - Execution continues with EE game
    ;--------------------------------------------------------------------------
    xor eax, eax
    ret
EEexInitDll ENDP


;------------------------------------------------------------------------------
; EEexInitGlobals - Initialize global variables & read ini file for addresses.
; Returns: Returns TRUE if all function addresses and global variables are set 
; to a value other than 0 (for EEexVerifyFunctions to handle) or FALSE 
; (for EEexSearchFunctions to handle instead)
;------------------------------------------------------------------------------
EEexInitGlobals PROC USES EBX
    LOCAL bVerifyFunctions:DWORD
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
    
    Invoke IniGetOptionLog
    mov gEEexLog, eax
    Invoke IniGetOptionLua ; TODO how to implement with patterns in .data? 
    mov gEEexLua, eax
    
    ; Read in addresses of functions if present in ini file
    Invoke IniGetPatchLocation, INI_NORMAL
    mov PatchLocation, eax
    IFDEF EEEX_LUALIB
        ; set function pointers to internal static lua library functions
        lea eax, lua_createtable
        mov Func_Lua_createtable, eax
        lea eax, lua_getglobal
        mov Func_Lua_getglobal, eax
        lea eax, lua_gettop
        mov Func_Lua_gettop, eax
        lea eax, lua_pcallk
        mov Func_Lua_pcallk, eax
        lea eax, lua_pushcclosure
        mov Func_Lua_pushcclosure, eax
        lea eax, lua_pushlightuserdata
        mov Func_Lua_pushlightuserdata, eax
        lea eax, lua_pushlstring
        mov Func_Lua_pushlstring, eax
        lea eax, lua_pushnumber
        mov Func_Lua_pushnumber, eax
        lea eax, lua_pushstring
        mov Func_Lua_pushstring, eax
        lea eax, lua_rawgeti
        mov Func_Lua_rawgeti, eax
        lea eax, lua_rawlen
        mov Func_Lua_rawlen, eax
        lea eax, lua_setfield
        mov Func_Lua_setfield, eax
        lea eax, lua_settable
        mov Func_Lua_settable, eax
        lea eax, lua_settop
        mov Func_Lua_settop, eax
        lea eax, lua_toboolean
        mov Func_Lua_toboolean, eax
        lea eax, lua_tolstring
        mov Func_Lua_tolstring, eax
        lea eax, lua_tonumberx
        mov Func_Lua_tonumberx, eax
        lea eax, lua_touserdata
        mov Func_Lua_touserdata, eax
        lea eax, lua_type
        mov Func_Lua_type, eax
        lea eax, lua_typename
        mov Func_Lua_typename, eax
        ; Get these functions if in ini 
        ; as the static lua lib ones crash.
        ; speeds up verify
        ;Invoke IniGetLua_setglobal
        lea eax, lua_setglobalx
        mov Func_Lua_setglobal, eax
        Invoke IniGetLuaL_loadstring, INI_NORMAL
        mov Func_LuaL_loadstring, eax
        Invoke IniGetftol2_sse, INI_NORMAL
        mov Func__ftol2_sse, eax
    ELSE ; or read all function pointers from ini file
        Invoke IniGetLua_createtable, INI_NORMAL
        mov Func_Lua_createtable, eax
        Invoke IniGetLua_getglobal, INI_NORMAL
        mov Func_Lua_getglobal, eax
        Invoke IniGetLua_gettop, INI_NORMAL
        mov Func_Lua_gettop, eax
        Invoke IniGetLua_pcallk, INI_NORMAL
        mov Func_Lua_pcallk, eax
        Invoke IniGetLua_pushcclosure, INI_NORMAL
        mov Func_Lua_pushcclosure, eax
        Invoke IniGetLua_pushlightuserdata, INI_NORMAL
        mov Func_Lua_pushlightuserdata, eax
        Invoke IniGetLua_pushlstring, INI_NORMAL
        mov Func_Lua_pushlstring, eax
        Invoke IniGetLua_pushnumber, INI_NORMAL
        mov Func_Lua_pushnumber, eax
        Invoke IniGetLua_pushstring, INI_NORMAL
        mov Func_Lua_pushstring, eax
        Invoke IniGetLua_rawgeti, INI_NORMAL
        mov Func_Lua_rawgeti, eax
        Invoke IniGetLua_rawlen, INI_NORMAL
        mov Func_Lua_rawlen, eax
        Invoke IniGetLua_setfield, INI_NORMAL
        mov Func_Lua_setfield, eax
        Invoke IniGetLua_setglobal, INI_NORMAL
        mov Func_Lua_setglobal, eax
        Invoke IniGetLua_settable, INI_NORMAL
        mov Func_Lua_settable, eax
        Invoke IniGetLua_settop, INI_NORMAL
        mov Func_Lua_settop, eax
        Invoke IniGetLua_toboolean, INI_NORMAL
        mov Func_Lua_toboolean, eax
        Invoke IniGetLua_tolstring, INI_NORMAL
        mov Func_Lua_tolstring, eax
        Invoke IniGetLua_tonumberx, INI_NORMAL
        mov Func_Lua_tonumberx, eax
        Invoke IniGetLua_touserdata, INI_NORMAL
        mov Func_Lua_touserdata, eax
        Invoke IniGetLua_type, INI_NORMAL
        mov Func_Lua_type, eax
        Invoke IniGetLua_typename, INI_NORMAL
        mov Func_Lua_typename, eax
        Invoke IniGetLuaL_loadstring, INI_NORMAL
        mov Func_LuaL_loadstring, eax
        Invoke IniGetftol2_sse, INI_NORMAL
        mov Func__ftol2_sse, eax
    ENDIF
    
    ; Read in pattern addresses of game globals if present in ini file
    Invoke IniGet_pp_pChitin, INI_NORMAL
    mov pp_pChitin, eax
    Invoke IniGet_pp_pBaldurChitin, INI_NORMAL
    mov pp_pBaldurChitin, eax
    Invoke IniGet_pp_backgroundMenu, INI_NORMAL
    mov pp_backgroundMenu, eax
    Invoke IniGet_pp_overlayMenu, INI_NORMAL
    mov pp_overlayMenu, eax


    ; if any addresses are 0 then we skip verify and go to search instead
    mov bVerifyFunctions, TRUE ; set to true to assume all verification will occur 
    .IF PatchLocation == 0
        mov bVerifyFunctions, FALSE
    .ENDIF
    .IF Func_Lua_createtable == 0
        mov bVerifyFunctions, FALSE    
    .ENDIF
    .IF Func_Lua_getglobal == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_gettop == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_pcallk == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_pushcclosure == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_pushlightuserdata == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_pushlstring == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_pushnumber == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_pushstring == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_rawgeti == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_rawlen == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_setfield == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_setglobal == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_settable == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_settop == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_toboolean == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_tolstring == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_tonumberx == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_touserdata == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_type == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_Lua_typename == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func_LuaL_loadstring == 0
        mov bVerifyFunctions, FALSE
    .ENDIF 
    .IF Func__ftol2_sse == 0
        mov bVerifyFunctions, FALSE
    .ENDIF

    .IF pp_pChitin == 0
        mov bVerifyFunctions, FALSE
    .ENDIF
    .IF pp_pBaldurChitin == 0
        mov bVerifyFunctions, FALSE
    .ENDIF
    .IF pp_backgroundMenu == 0
        mov bVerifyFunctions, FALSE
    .ENDIF
    .IF pp_overlayMenu == 0
        mov bVerifyFunctions, FALSE
    .ENDIF


    mov eax, bVerifyFunctions
    ret
EEexInitGlobals ENDP


;------------------------------------------------------------------------------
; EEexVerifyFunctions - Verify if function addresses contain their own byte 
; patterns, if they do match we set the bFound flag to TRUE in their pattern 
; structure. For those patterns that do not match a rescan will occur for those 
; patterns (during EEexSearchFunctions) that have bFound set to FALSE
; Returns: TRUE if all patterns where succesfully verified for each function or
; FALSE otherwise.
;------------------------------------------------------------------------------
EEexVerifyFunctions PROC USES EBX
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL PatAddress:DWORD
    LOCAL PatBytes:DWORD
    LOCAL PatLength:DWORD
    LOCAL VerAdj:DWORD
    LOCAL VerBytes:DWORD
    LOCAL VerLength:DWORD    
    LOCAL RetVal:DWORD

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    mov T_EEexVerifyFunctions, eax     
    ENDIF
    
    mov RetVal, TRUE
    
    lea ebx, Patterns
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        mov eax, [ebx].PATTERN.FuncAddress
        mov eax, [eax] ; FuncAddress is pointer to global var storing address
        .IF eax == 0 ; just in case
            IFDEF DEBUG32
            PrintText 'FuncAddress is pointer to global var is null'
            PrintDec nPattern
            ENDIF
            mov RetVal, FALSE
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
                .ENDIF
                mov [ebx].PATTERN.bFound, TRUE
                inc FoundPatterns
            .ELSE
                IFDEF DEBUG32
                PrintText 'Pattern found but not verified'
                PrintDec nPattern
                ENDIF
                mov [ebx].PATTERN.bFound, FALSE
                mov RetVal, FALSE
            .ENDIF
        .ELSE
            IFDEF DEBUG32
            PrintText 'Pattern not found'
            PrintDec nPattern
            ENDIF
            mov [ebx].PATTERN.bFound, FALSE
            mov RetVal, FALSE
        .ENDIF
        
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    sub eax, T_EEexVerifyFunctions
    mov T_EEexVerifyFunctions, eax
    ENDIF    
    
    mov eax, RetVal
    ret
EEexVerifyFunctions ENDP


;------------------------------------------------------------------------------
; EEexSearchFunctions - Search through memory for function addresses as defined
; by the array of pattern structures. Also find codecave location and codecave
; jmp entrypoint location. For functions that were already verified we ignore
; those functions (which have the bFound flag set in the pattern during the
; EEexVerifyFunctions call)
; Returns: TRUE if all patterns where succesfully found for each function or
; FALSE otherwise.
;------------------------------------------------------------------------------
EEexSearchFunctions PROC USES EBX ESI
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

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    mov T_EEexSearchFunctions, eax
    ENDIF
    
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

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    sub eax, T_EEexSearchFunctions
    mov T_EEexSearchFunctions, eax
    ENDIF
    
    mov eax, RetVal
    ret
EEexSearchFunctions ENDP


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
    LOCAL bFallbackAddresses:DWORD

    mov bFallbackAddresses, TRUE

    .IF PatchLocation == 0
        Invoke IniGetPatchLocation, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov PatchLocation, eax
        .ENDIF
    .ENDIF
    .IF Func_Lua_createtable == 0
        Invoke IniGetLua_createtable, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_createtable, eax
        .ENDIF
    .ENDIF
    .IF Func_Lua_getglobal == 0
        Invoke IniGetLua_getglobal, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_getglobal, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_gettop == 0
        Invoke IniGetLua_gettop, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_gettop, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_pcallk == 0
        Invoke IniGetLua_pcallk, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_pcallk, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_pushcclosure == 0
        Invoke IniGetLua_pushcclosure, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_pushcclosure, eax
        .ENDIF
    .ENDIF
    .IF Func_Lua_pushlightuserdata == 0
        Invoke IniGetLua_pushlightuserdata, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_pushlightuserdata, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_pushlstring == 0
        Invoke IniGetLua_pushlstring, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_pushlstring, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_pushnumber == 0
        Invoke IniGetLua_pushnumber, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_pushnumber, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_pushstring == 0
        Invoke IniGetLua_pushstring, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_pushstring, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_rawgeti == 0
        Invoke IniGetLua_rawgeti, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_rawgeti, eax 
        .ENDIF
    .ENDIF
    .IF Func_Lua_rawlen == 0
        Invoke IniGetLua_rawlen, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_rawlen, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_setfield == 0
         Invoke IniGetLua_setfield, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_setfield, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_setglobal == 0
        Invoke IniGetLua_setglobal, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_setglobal, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_settable == 0
        Invoke IniGetLua_settable, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_settable, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_settop == 0
        Invoke IniGetLua_settop, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_settop, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_toboolean == 0
        Invoke IniGetLua_toboolean, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_toboolean, eax 
        .ENDIF
    .ENDIF 
    .IF Func_Lua_tolstring == 0
        Invoke IniGetLua_tolstring, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_tolstring, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_tonumberx == 0
        Invoke IniGetLua_tonumberx, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_tonumberx, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_touserdata == 0
        Invoke IniGetLua_touserdata, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_touserdata, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_type == 0
        Invoke IniGetLua_type, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_type, eax
        .ENDIF
    .ENDIF 
    .IF Func_Lua_typename == 0
        Invoke IniGetLua_typename, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_Lua_typename, eax
        .ENDIF
    .ENDIF 
    .IF Func_LuaL_loadstring == 0
        Invoke IniGetLuaL_loadstring, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func_LuaL_loadstring, eax
        .ENDIF
    .ENDIF 
    .IF Func__ftol2_sse == 0
        Invoke IniGetftol2_sse, INI_FALLBACK
        .IF eax == 0
            mov bFallbackAddresses, FALSE
        .ELSE
            mov Func__ftol2_sse, eax
        .ENDIF
    .ENDIF    

    mov eax, bFallbackAddresses
    ret
EEexFallbackAddresses ENDP


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


;------------------------------------------------------------------------------
; Process game global variables - obtain pointers to the game globals from
; pattern addresses verified or searched for.
; Returns: none
;------------------------------------------------------------------------------
EEexGameGlobals PROC USES EBX
    mov ebx, PatchLocation
    sub ebx, 4d
    mov pp_lua, eax
    mov eax, [ebx] ; address of g_lua
    mov p_lua, eax
    .IF pp_pChitin != 0
        mov ebx, pp_pChitin
        mov eax, [ebx]
        mov p_pChitin, eax
    .ENDIF
    .IF pp_pBaldurChitin != 0
        mov ebx, pp_pBaldurChitin
        mov eax, [ebx]
        mov p_pBaldurChitin, eax
    .ENDIF    
    .IF pp_backgroundMenu != 0
        mov ebx, pp_backgroundMenu
        mov eax, [ebx]
        mov p_backgroundMenu, eax
    .ENDIF    
    .IF pp_overlayMenu != 0
        mov ebx, pp_overlayMenu
        mov eax, [ebx]
        mov p_overlayMenu, eax
    .ENDIF    
    ret
EEexGameGlobals ENDP


;------------------------------------------------------------------------------
; EEexLogInformation - Log some debug information to log.
; dwType: 0 all, 1 = game info, 2=debug info, 3=addresses 
; Returns: None
;------------------------------------------------------------------------------
EEexLogInformation PROC dwType:DWORD
    LOCAL wfad:WIN32_FILE_ATTRIBUTE_DATA
    LOCAL dwFilesizeLow:DWORD
    
    .IF gEEexLog == FALSE
        xor eax, eax
        ret
    .ENDIF
    
    Invoke LogOpen, FALSE
    
    .IF dwType == INFO_ALL || dwType == INFO_GAME
        Invoke LogMessage, CTEXT("Game Information:"), LOG_INFO, 0
        Invoke LogMessage, CTEXT("Filename: "), LOG_NONEWLINE, 0
        Invoke LogMessage, Addr EEexExeFile, LOG_STANDARD, 0
    
        Invoke GetFileAttributesEx, Addr EEexExeFile, 0, Addr wfad
        mov eax, wfad.nFileSizeLow
        mov dwFilesizeLow, eax
        Invoke LogMessageAndValue, CTEXT("Filesize"), dwFilesizeLow
        
        Invoke EEexEEFileInformation
        .IF eax == TRUE
            Invoke LogMessage, CTEXT("FileVersion: "), LOG_NONEWLINE, 0
            Invoke LogMessage, Addr szFileVersionBuffer, LOG_STANDARD, 0
            Invoke LogMessage, CTEXT("ProductName: "), LOG_NONEWLINE, 0
            Invoke LogMessage, Addr EEGameProductName, LOG_STANDARD, 0
            Invoke LogMessage, CTEXT("ProductVersion: "), LOG_NONEWLINE, 0
            Invoke LogMessage, Addr EEGameProductVersion, LOG_STANDARD, 0
        .ENDIF
        Invoke LogMessage, 0, LOG_CRLF, 0
        
        Invoke LogMessage, CTEXT("Options:"), LOG_INFO, 0
        Invoke LogMessageAndValue, CTEXT("Lua"), gEEexLua
        Invoke LogMessageAndValue, CTEXT("Hex"), gEEexHex
        Invoke LogMessage, 0, LOG_CRLF, 0
        
    .ENDIF
    
    .IF dwType == INFO_ALL || dwType == INFO_DEBUG
        Invoke LogMessage, CTEXT("Debug Information:"), LOG_INFO, 0
        Invoke LogMessageAndHexValue, CTEXT("hProcess"), hEEGameProcess
        Invoke LogMessageAndHexValue, CTEXT("hModule"), hEEGameModule
        Invoke LogMessageAndHexValue, CTEXT("OEP"), EEGameAddressEP
        Invoke LogMessageAndHexValue, CTEXT("BaseAddress"), EEGameBaseAddress
        Invoke LogMessageAndHexValue, CTEXT("ImageSize"), EEGameImageSize        
        Invoke LogMessageAndHexValue, CTEXT("AddressStart"), EEGameAddressStart
        Invoke LogMessageAndHexValue, CTEXT("AddressFinish"), EEGameAddressFinish
        Invoke LogMessage, 0, LOG_CRLF, 0
        Invoke LogMessageAndValue, CTEXT("Sections"), EEGameNoSections
        Invoke LogMessageAndHexValue, CTEXT(".text address"), EEGameSectionTEXTPtr
        Invoke LogMessageAndValue, CTEXT(".text size"), EEGameSectionTEXTSize
        Invoke LogMessageAndHexValue, CTEXT(".rdata address"), EEGameSectionRDATAPtr
        Invoke LogMessageAndValue, CTEXT(".rdata size"), EEGameSectionRDATASize
        Invoke LogMessageAndHexValue, CTEXT(".data address"), EEGameSectionDATAPtr
        Invoke LogMessageAndValue, CTEXT(".data size"), EEGameSectionDATASize
        Invoke LogMessage, 0, LOG_CRLF, 0
        Invoke LogMessageAndValue, CTEXT("Total patterns to match"), TotalPatterns
        
        .IF gEEexLuaLibDefined == TRUE && gEEexLua == TRUE
            Invoke LogMessage, CTEXT("Using static library for lua functions"), LOG_STANDARD, 0
        .ELSEIF gEEexLuaLibDefined == TRUE && gEEexLua == FALSE
            Invoke LogMessage, CTEXT("Using pattern matching for lua functions"), LOG_STANDARD, 0
        .ELSEIF gEEexLuaLibDefined == FALSE && gEEexLua == TRUE
            Invoke LogMessage, CTEXT("Lua option enabled, but Lua library not included. Using pattern matching for lua functions"), LOG_STANDARD, 0
        .ELSE ; .gEEexLuaLibDefined == FALSE && gEEexLua == FALSE
            Invoke LogMessage, CTEXT("Using pattern matching for lua functions"), LOG_STANDARD, 0
        .ENDIF
        Invoke LogMessage, 0, LOG_CRLF, 0  
    .ENDIF
    
    .IF dwType == INFO_ALL || dwType == INFO_VERIFIED || dwType == INFO_SEARCHED || dwType == INFO_FALLBACK
        .IF dwType == INFO_VERIFIED
            Invoke LogMessage, CTEXT("Addresses Verified:"), LOG_INFO, 0
        .ELSEIF dwType == INFO_SEARCHED
            Invoke LogMessage, CTEXT("Addresses Searched:"), LOG_INFO, 0
        .ELSEIF dwType == INFO_FALLBACK
            Invoke LogMessage, CTEXT("Addresses Searched + Fallbacks:"), LOG_INFO, 0
        .ENDIF
        Invoke LogMessageAndHexValue, CTEXT("PatchLocation"), PatchLocation
        Invoke LogMessageAndHexValue, CTEXT("Lua_createtable"), Func_Lua_createtable
        Invoke LogMessageAndHexValue, CTEXT("Lua_getglobal"), Func_Lua_getglobal
        Invoke LogMessageAndHexValue, CTEXT("Lua_gettop"), Func_Lua_gettop
        Invoke LogMessageAndHexValue, CTEXT("Lua_pcallk"), Func_Lua_pcallk
        Invoke LogMessageAndHexValue, CTEXT("Lua_pushcclosure"), Func_Lua_pushcclosure
        Invoke LogMessageAndHexValue, CTEXT("Lua_pushlightuserdata"), Func_Lua_pushlightuserdata
        Invoke LogMessageAndHexValue, CTEXT("Lua_pushlstring"), Func_Lua_pushlstring
        Invoke LogMessageAndHexValue, CTEXT("Lua_pushnumber"), Func_Lua_pushnumber
        Invoke LogMessageAndHexValue, CTEXT("Lua_pushstring"), Func_Lua_pushstring
        Invoke LogMessageAndHexValue, CTEXT("Lua_rawgeti"), Func_Lua_rawgeti
        Invoke LogMessageAndHexValue, CTEXT("Lua_rawlen"), Func_Lua_rawlen
        Invoke LogMessageAndHexValue, CTEXT("Lua_setfield"), Func_Lua_setfield
        Invoke LogMessageAndHexValue, CTEXT("Lua_setglobal"), Func_Lua_setglobal  
        Invoke LogMessageAndHexValue, CTEXT("Lua_settable"), Func_Lua_settable
        Invoke LogMessageAndHexValue, CTEXT("Lua_settop"), Func_Lua_settop
        Invoke LogMessageAndHexValue, CTEXT("Lua_toboolean"), Func_Lua_toboolean
        Invoke LogMessageAndHexValue, CTEXT("Lua_tolstring"), Func_Lua_tolstring
        Invoke LogMessageAndHexValue, CTEXT("Lua_tonumberx"), Func_Lua_tonumberx
        Invoke LogMessageAndHexValue, CTEXT("Lua_touserdata"), Func_Lua_touserdata
        Invoke LogMessageAndHexValue, CTEXT("Lua_type"), Func_Lua_type
        Invoke LogMessageAndHexValue, CTEXT("Lua_typename"), Func_Lua_typename
        Invoke LogMessageAndHexValue, CTEXT("LuaL_loadstring"), Func_LuaL_loadstring
        Invoke LogMessageAndHexValue, CTEXT("_ftol2_sse"), Func__ftol2_sse
        Invoke LogMessage, 0, LOG_CRLF, 0
        Invoke LogMessage, CTEXT("Game Globals Addresses:"), LOG_INFO, 0
        
        mov eax, PatchLocation
        sub eax, 4d
        mov pp_lua, eax        
        Invoke LogMessageAndHexValue, CTEXT("pp_lua"), pp_lua
        Invoke LogMessageAndHexValue, CTEXT("pp_pChitin"), pp_pChitin
        Invoke LogMessageAndHexValue, CTEXT("pp_pBaldurChitin"), pp_pBaldurChitin
        Invoke LogMessageAndHexValue, CTEXT("pp_backgroundMenu"), pp_backgroundMenu
        Invoke LogMessageAndHexValue, CTEXT("pp_overlayMenu"), pp_overlayMenu
        Invoke LogMessage, 0, LOG_CRLF, 0
    .ENDIF
    
    xor eax, eax
    ret
EEexLogInformation ENDP


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
                        Invoke lstrcpyn, Addr EEGameProductVersion, lpszProductVersion, SIZEOF EEGameProductVersion
                        
                        ; Get ProductName String
                        mov ebx, pBuffer
                        movzx eax,[ebx.LANGANDCODEPAGE].wLanguage
                        movzx ebx,[ebx.LANGANDCODEPAGE].wCodepage   
                        Invoke wsprintf, Addr szProductNameBuffer, Addr szProductName, eax, ebx
                        Invoke VerQueryValue, verData, Addr szProductNameBuffer, Addr lpszProductName, addr lenBuffer
                        Invoke lstrcpyn, Addr EEGameProductName, lpszProductName, SIZEOF EEGameProductName
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


;------------------------------------------------------------------------------
; EEexWriteFunctionsToIni - Write lua function locations to ini file
; Returns: None
;------------------------------------------------------------------------------
EEexWriteFunctionsToIni PROC
    Invoke IniSetPatchLocation, PatchLocation
    
    IFDEF EEEX_LUALIB
    Invoke IniSetLua_createtable, 0
    Invoke IniSetLua_getglobal, 0
    Invoke IniSetLua_gettop, 0
    Invoke IniSetLua_pcallk, 0
    Invoke IniSetLua_pushcclosure, 0
    Invoke IniSetLua_pushlightuserdata, 0
    Invoke IniSetLua_pushlstring, 0
    Invoke IniSetLua_pushnumber, 0
    Invoke IniSetLua_pushstring, 0
    Invoke IniSetLua_rawgeti, 0
    Invoke IniSetLua_rawlen, 0
    Invoke IniSetLua_setfield, 0
    Invoke IniSetLua_setglobal, Func_Lua_setglobal
    Invoke IniSetLua_settable, 0
    Invoke IniSetLua_settop, 0
    Invoke IniSetLua_toboolean, 0
    Invoke IniSetLua_tolstring, 0
    Invoke IniSetLua_tonumberx, 0
    Invoke IniSetLua_touserdata, 0
    Invoke IniSetLua_type, 0
    Invoke IniSetLua_typename, 0
    Invoke IniSetLuaL_loadstring, Func_LuaL_loadstring
    Invoke IniSetftol2_sse, Func__ftol2_sse
    ELSE
    Invoke IniSetLua_createtable, Func_Lua_createtable
    Invoke IniSetLua_getglobal, Func_Lua_getglobal
    Invoke IniSetLua_gettop, Func_Lua_gettop
    Invoke IniSetLua_pcallk, Func_Lua_pcallk
    Invoke IniSetLua_pushcclosure, Func_Lua_pushcclosure
    Invoke IniSetLua_pushlightuserdata, Func_Lua_pushlightuserdata
    Invoke IniSetLua_pushlstring, Func_Lua_pushlstring
    Invoke IniSetLua_pushnumber, Func_Lua_pushnumber
    Invoke IniSetLua_pushstring, Func_Lua_pushstring
    Invoke IniSetLua_rawgeti, Func_Lua_rawgeti
    Invoke IniSetLua_rawlen, Func_Lua_rawlen
    Invoke IniSetLua_setfield, Func_Lua_setfield
    Invoke IniSetLua_setglobal, Func_Lua_setglobal
    Invoke IniSetLua_settable, Func_Lua_settable
    Invoke IniSetLua_settop, Func_Lua_settop
    Invoke IniSetLua_toboolean, Func_Lua_toboolean
    Invoke IniSetLua_tolstring, Func_Lua_tolstring
    Invoke IniSetLua_tonumberx, Func_Lua_tonumberx
    Invoke IniSetLua_touserdata, Func_Lua_touserdata
    Invoke IniSetLua_type, Func_Lua_type
    Invoke IniSetLua_typename, Func_Lua_typename
    Invoke IniSetLuaL_loadstring, Func_LuaL_loadstring
    Invoke IniSetftol2_sse, Func__ftol2_sse
    ENDIF

    Invoke IniSet_pp_pChitin, pp_pChitin
    Invoke IniSet_pp_pBaldurChitin, pp_pBaldurChitin
    Invoke IniSet_pp_backgroundMenu, pp_backgroundMenu
    Invoke IniSet_pp_overlayMenu, pp_overlayMenu


    xor eax, eax
    ret
EEexWriteFunctionsToIni ENDP




;TODO? add EEex lua files to resources, extract to override folder if they dont already exist? 


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexDwordToAscii - Paul Dixon's utoa_ex function. unsigned dword to ascii.
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














