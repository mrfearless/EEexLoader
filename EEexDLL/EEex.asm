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

;EEEX_FUNCTION_TIMERS EQU 1 ; comment out if we dont require timers
EEEX_LOGGING EQU 1 ; comment out if we dont require logging (exclude logging from EEexLua for example) 

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
    LOCAL ptrNtHeaders:DWORD
    LOCAL ptrSections:DWORD
    LOCAL ptrCurrentSection:DWORD
    LOCAL CurrentSection:DWORD

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    mov T_EEexInitDll, eax     
    ENDIF

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
                Invoke LogOpen, FALSE
                Invoke LogMessage, Addr szErrorImageNtSig, LOG_ERROR, 0
                Invoke LogClose
                ret ; Exit EEexInitDll
            .ENDIF
        .ELSE ; IMAGE_DOS_SIGNATURE Failed
            Invoke LogOpen, FALSE
            Invoke LogMessage, Addr szErrorImageDosSig, LOG_ERROR, 0
            Invoke LogClose
            ret ; Exit EEexInitDll
        .ENDIF        
    .ELSE ; GetModuleInformation Failed
        Invoke LogOpen, FALSE
        Invoke LogMessage, Addr szErrorGetModuleInfo, LOG_ERROR, 0
        Invoke LogClose
        ret ; Exit EEexInitDll
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished EE Game Module Info And Sections Stage
    ;--------------------------------------------------------------------------
    
    
    Invoke EEexLogInformation, INFO_DEBUG
    
    
    ;--------------------------------------------------------------------------
    ; Verify EE Game Lua Function Addresses / Search For Addresses
    ;--------------------------------------------------------------------------
    mov bSearchFunctions, TRUE ; Set to true to assume we will search for functions
    .IF PatchLocation != 0 && Func_LuaL_loadstring != 0 && Func_Lua_pushnumber != 0 && Func_Lua_pushclosure != 0 && Func_Lua_tolstring != 0 && Func_Lua_setglobal != 0 && Func_Lua_tonumberx != 0 && Func__ftol2_sse != 0 
        Invoke EEexVerifyFunctions
        .IF eax == TRUE ; no need to search for function as we have verified them
            Invoke EEexLogInformation, INFO_ADDRESSES
            mov bSearchFunctions, FALSE
        .ENDIF
        IFDEF EEEX_FUNCTION_TIMERS
        Invoke LogMessageAndValue, CTEXT("EEexVerifyFunctions Execution Time (ms)"), T_EEexVerifyFunctions
        Invoke LogMessage, 0, LOG_CRLF, 0
        ENDIF
    .ENDIF
    
    .IF bSearchFunctions == TRUE ; If we failed to verify functions or 1st run then begin search
        Invoke EEexSearchFunctions
        .IF eax == TRUE ; EE Game Lua Function Addresses Found - Write Info To Ini File
            Invoke EEexLogInformation, INFO_ADDRESSES
            IFDEF EEEX_FUNCTION_TIMERS
            Invoke LogMessageAndValue, CTEXT("EEexSearchFunctions Execution Time (ms)"), T_EEexSearchFunctions
            Invoke LogMessage, 0, LOG_CRLF, 0
            ENDIF
            Invoke EEexWriteFunctionsToIni
            ;------------------------------------------------------------------
            ; Continue Onwards To Apply Patch Stage
            ;------------------------------------------------------------------
        .ELSE ; EE Game Lua Function Addresses NOT VERIFIED OR FOUND!
            Invoke EEexLogInformation, INFO_ADDRESSES
            IFDEF EEEX_FUNCTION_TIMERS
            Invoke LogMessageAndValue, CTEXT("EEexSearchFunctions Execution Time (ms)"), T_EEexSearchFunctions
            Invoke LogMessage, 0, LOG_CRLF, 0
            ENDIF            
            ; Error tell user that cannot find or verify functions - might be a new build
            Invoke LogOpen, FALSE
            Invoke LogMessage, CTEXT("Cannot find or verify EE game lua functions - might be an unsupported or new build of EE game."), LOG_ERROR, 0
            Invoke LogClose
            ;------------------------------------------------------------------
            ; EEex.DLL EXITS HERE - Execution continues with EE game
            ;------------------------------------------------------------------
            ret ; Exit EEexInitDll
        .ENDIF
    .ELSE ; Functions verified, no need for search
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
        ; Get g_lua address and store in p_lua
        mov ebx, PatchLocation
        sub ebx, 4d
        mov eax, [ebx] ; address of g_lua
        mov p_lua, eax
        ;Invoke LogMessageAndValue, CTEXT("p_lua"), p_lua
        ;PrintDec p_lua        
        Invoke EEexApplyCallPatch, PatchLocation ; (call EEexLuaInit)
        .IF eax == TRUE ; Patch Success! - Write status to log and exit EEex.dll
            Invoke LogMessage, CTEXT("EEexApplyCallPatch - applied patch"), LOG_INFO, 0
            ;------------------------------------------------------------------  
            ; Note: Redirection from EE Game to our EEexLuaInit function occurs
            ; after EEex.dll:EEexInitDll returns to EE Game, during which time 
            ; it will eventually hit our patched instruction: call EEexLuaInit
            ;------------------------------------------------------------------
        .ELSE ; Patch Failure! - Write status to log and exit EEex.dll
            Invoke LogMessage, CTEXT("EEexApplyCallPatch - failed to apply patch"), LOG_ERROR, 0
            Invoke LogClose
        .ENDIF
    .ELSE
        Invoke LogMessage, CTEXT("PatchLocation is NULL!"), LOG_ERROR, 0
        Invoke LogClose
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished Apply Patch Stage
    ;--------------------------------------------------------------------------
    
    
    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    sub eax, T_EEexInitDll
    mov T_EEexInitDll, eax
    Invoke LogMessage, 0, LOG_CRLF, 0
    Invoke LogMessageAndValue, CTEXT("EEexInitDll Execution Time (ms)"), T_EEexInitDll
    ENDIF        
    
    
    
    
    ;--------------------------------------------------------------------------
    ; EEex.DLL EXITS HERE - Execution continues with EE game
    ;--------------------------------------------------------------------------
    xor eax, eax
    ret
EEexInitDll ENDP


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

    ; Read in addresses of functions if present in ini file
    Invoke IniGetPatchLocation
    mov PatchLocation, eax
    Invoke IniGetLua_pushclosure
    mov Func_Lua_pushclosure, eax
    Invoke IniGetLua_pushnumber
    mov Func_Lua_pushnumber, eax
    Invoke IniGetLua_setglobal
    mov Func_Lua_setglobal, eax
    Invoke IniGetLua_tonumberx
    mov Func_Lua_tonumberx, eax
    Invoke IniGetLua_tolstring
    mov Func_Lua_tolstring, eax
    Invoke IniGetLuaL_loadstring
    mov Func_LuaL_loadstring, eax
    Invoke IniGetftol2_sse
    mov Func__ftol2_sse, eax

    xor eax, eax
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
        Invoke EEexVerifyPattern, PatAddress, PatBytes, PatLength
        mov ebx, ptrCurrentPattern
        .IF eax == TRUE
            mov eax, [ebx].PATTERN.VerLength
            .IF eax != 0 ; Check VerBytes pattern if it exists as well
                mov VerLength, eax
                mov eax, [ebx].PATTERN.VerBytes
                mov VerBytes, eax
                mov eax, PatAddress
                add eax, [ebx].PATTERN.VerAdj
                Invoke EEexVerifyPattern, eax, VerBytes, VerLength
            .ELSE
                mov eax, TRUE ; No verbytes to check so set to TRUE
            .ENDIF
            
            mov ebx, ptrCurrentPattern
            .IF eax == TRUE ; No verbytes to check or verbytes matched 
                mov [ebx].PATTERN.bFound, TRUE
            .ELSE
                mov [ebx].PATTERN.bFound, FALSE
                mov RetVal, FALSE
            .ENDIF
        .ELSE
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
; EEexVerifyPattern - Verify a pattern matches at the specified address
; Returns: TRUE if it matches, FALSE if it doesnt.
;------------------------------------------------------------------------------
EEexVerifyPattern PROC USES EBX EDI ESI lpdwAddress:DWORD, lpdwPatternBytes:DWORD, dwPatternLength:DWORD
    LOCAL pos:DWORD
    
    .IF lpdwAddress == 0 || lpdwPatternBytes == 0 || dwPatternLength == 0
        mov eax, FALSE
        ret
    .ENDIF
    
    mov esi, lpdwAddress
    mov edi, lpdwPatternBytes
    mov pos, 0
    mov eax, 0
    .WHILE eax < dwPatternLength
        movzx eax, byte ptr [esi]
        movzx ebx, byte ptr [edi]
        .IF al != bl
            mov eax, FALSE
            ret
        .ENDIF
        inc esi
        inc edi
        inc pos
        mov eax, pos
    .ENDW
    mov eax, TRUE
    ret
EEexVerifyPattern ENDP


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
    LOCAL PatternsFound:DWORD
    LOCAL RetVal:DWORD

    IFDEF EEEX_FUNCTION_TIMERS
    Invoke GetTickCount
    mov T_EEexSearchFunctions, eax
    ENDIF
    
    mov RetVal, FALSE
    mov PatternsFound, 0

    mov eax, EEGameSectionTEXTPtr
    mov dwAddress, eax
    add eax, EEGameSectionTEXTSize
    mov dwAddressFinish, eax

    ; get count of verified patterns to add to total already found
    lea ebx, Patterns
    mov ptrCurrentPattern, ebx
    mov nPattern, 0        
    mov eax, 0
    .WHILE eax < TotalPatterns
        .IF [ebx].PATTERN.bFound == TRUE
            inc PatternsFound
        .ENDIF
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW

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
                    Invoke EEexVerifyPattern, dwAddress, PatBytes, PatLength
                    .IF eax == TRUE ; Matched a pattern
                        mov ebx, ptrCurrentPattern
                        mov eax, [ebx].PATTERN.VerLength
                        .IF eax != 0 ; Check VerBytes pattern if it exists as well
                            mov VerLength, eax
                            mov eax, [ebx].PATTERN.VerBytes
                            mov VerBytes, eax
                            mov eax, dwAddress
                            add eax, [ebx].PATTERN.VerAdj
                            Invoke EEexVerifyPattern, eax, VerBytes, VerLength
                        .ELSE
                            mov eax, TRUE ; No verbytes to check so set to TRUE
                        .ENDIF
                        
                        .IF eax == TRUE ; No verbytes to check or verbytes matched 
                            mov ebx, ptrCurrentPattern
                            mov [ebx].PATTERN.bFound, TRUE
                            mov eax, dwAddress
                            add eax, [ebx].PATTERN.PatAdj
                            mov ebx, [ebx].PATTERN.FuncAddress ; Offset to global var to set for address
                            .IF ebx != 0
                                mov [ebx], eax ; store address in global var
                            .ENDIF
                            inc PatternsFound
                        .ENDIF
                        
                    .ENDIF                    
                .ENDIF
            .ENDIF
            
            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
        .ENDW    
    
        mov eax, PatternsFound
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
; EEexWriteFunctionsToIni - Write lua function locations to ini file
; Returns: None
;------------------------------------------------------------------------------
EEexWriteFunctionsToIni PROC
    Invoke IniSetPatchLocation, PatchLocation
    Invoke IniSetLua_pushclosure, Func_Lua_pushclosure
    Invoke IniSetLua_pushnumber, Func_Lua_pushnumber
    Invoke IniSetLua_setglobal, Func_Lua_setglobal
    Invoke IniSetLua_tonumberx, Func_Lua_tonumberx
    Invoke IniSetLua_tolstring, Func_Lua_tolstring
    Invoke IniSetLuaL_loadstring, Func_LuaL_loadstring
    Invoke IniSetftol2_sse, Func__ftol2_sse
    xor eax, eax
    ret
EEexWriteFunctionsToIni ENDP


;------------------------------------------------------------------------------
; EEexLogInformation - Log some debug information to log.
; dwType: 0 all, 1 = game info, 2=debug info, 3=addresses 
; Returns: None
;------------------------------------------------------------------------------
EEexLogInformation PROC dwType:DWORD
    LOCAL wfad:WIN32_FILE_ATTRIBUTE_DATA
    LOCAL dwFilesizeLow:DWORD
    
    Invoke LogOpen, FALSE
    
    .IF dwType == 0 || dwType == 1
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
    .ENDIF
    
    .IF dwType == 0 || dwType == 2
        Invoke LogMessage, CTEXT("Debug Information:"), LOG_INFO, 0
        Invoke LogMessageAndValue, CTEXT("hEEGameProcess"), hEEGameProcess
        Invoke LogMessageAndValue, CTEXT("hEEGameModule"), hEEGameModule
        Invoke LogMessageAndValue, CTEXT("EEGameBaseAddress"), EEGameBaseAddress
        Invoke LogMessageAndValue, CTEXT("EEGameAddressEP"), EEGameAddressEP
        Invoke LogMessageAndValue, CTEXT("EEGameAddressStart"), EEGameAddressStart
        Invoke LogMessageAndValue, CTEXT("EEGameAddressFinish"), EEGameAddressFinish
        Invoke LogMessageAndValue, CTEXT("EEGameImageSize"), EEGameImageSize
        Invoke LogMessageAndValue, CTEXT("EEGameNoSections"), EEGameNoSections
        Invoke LogMessageAndValue, CTEXT("EEGameSectionTEXTSize"), EEGameSectionTEXTSize
        Invoke LogMessageAndValue, CTEXT("EEGameSectionTEXTPtr"), EEGameSectionTEXTPtr
        Invoke LogMessageAndValue, CTEXT("EEGameSectionRDATASize"), EEGameSectionRDATASize
        Invoke LogMessageAndValue, CTEXT("EEGameSectionRDATAPtr"), EEGameSectionRDATAPtr
        Invoke LogMessageAndValue, CTEXT("EEGameSectionDATASize"), EEGameSectionDATASize
        Invoke LogMessageAndValue, CTEXT("EEGameSectionDATAPtr"), EEGameSectionDATAPtr
        Invoke LogMessage, 0, LOG_CRLF, 0
    .ENDIF
    
    .IF dwType == 0 || dwType == 3
        Invoke LogMessage, CTEXT("Function Addresses:"), LOG_INFO, 0
        Invoke LogMessageAndValue, CTEXT("PatchLocation"), PatchLocation
        Invoke LogMessageAndValue, CTEXT("Lua_pushclosure"), Func_Lua_pushclosure
        Invoke LogMessageAndValue, CTEXT("Lua_pushnumber"), Func_Lua_pushnumber
        Invoke LogMessageAndValue, CTEXT("Lua_setglobal"), Func_Lua_setglobal    
        Invoke LogMessageAndValue, CTEXT("Lua_tonumberx"), Func_Lua_tonumberx
        Invoke LogMessageAndValue, CTEXT("Lua_tolstring"), Func_Lua_tolstring
        Invoke LogMessageAndValue, CTEXT("LuaL_loadstring"), Func_LuaL_loadstring
        Invoke LogMessageAndValue, CTEXT("_ftol2_sse"), Func__ftol2_sse
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



;TODO? add EEex lua files to resources, extract to override folder if they dont already exist? 


;------------------------------------------------------------------------------
; EEexDwordToAscii - Paul Dixon's utoa_ex function. unsigned dword to ascii.
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
ALIGN 16
EEexDwordToAscii PROC uvar:DWORD, pbuffer:DWORD
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



END DllEntry














