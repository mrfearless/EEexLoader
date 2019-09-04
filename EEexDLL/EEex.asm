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
                Invoke TerminateProcess, hEEGameProcess, NULL
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
            Invoke TerminateProcess, hEEGameProcess, NULL
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
        Invoke TerminateProcess, hEEGameProcess, NULL
        ret ; Exit EEexInitDll
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished EE Game Module Info And Sections Stage
    ;--------------------------------------------------------------------------

    Invoke EEexLogInformation, INFO_DEBUG

    ;--------------------------------------------------------------------------
    ; Import Patterns Database
    ;--------------------------------------------------------------------------

    Invoke EEexImportPatterns
    Invoke EEexLogInformation, INFO_IMPORTED
 
    ;--------------------------------------------------------------------------
    ; Verify Pattern Addresses
    ;--------------------------------------------------------------------------
    mov bSearchPatterns, TRUE ; Set to true to assume we will search for all patterns
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
        Invoke EEexSearchPatterns
        .IF eax == TRUE ; EE Game Lua Function Addresses Found - Write Info To Ini File
            IFDEF DEBUG32
            PrintText 'EEexSearchPatterns Success'
            ENDIF
            Invoke EEexLogInformation, INFO_SEARCHED
            Invoke EEexWriteAddressesToIni
            ;------------------------------------------------------------------
            ; Continue Onwards To Apply Patch Stage
            ;------------------------------------------------------------------
        .ELSE ; EE Game Lua Function Addresses NOT VERIFIED OR FOUND!
            IFDEF DEBUG32
            PrintText 'EEexSearchPatterns Failed'
            ENDIF
            Invoke EEexLogInformation, INFO_SEARCHED
            ; Error tell user that cannot find or verify functions - might be a new build
            IFDEF EEEX_LOGGING
            .IF gEEexLog > LOGLEVEL_NONE
                Invoke LogOpen, FALSE
                Invoke LogMessage, Addr szErrorSearchFunctions, LOG_ERROR, 0 ; CTEXT("Cannot find or verify EE game lua functions - might be an unsupported or new build of EE game.")
                Invoke LogClose
            .ENDIF
            ENDIF
            .IF gEEexMsg == TRUE
                Invoke MessageBox, 0, Addr szErrorSearchFunctions, Addr AppName, MB_OK
            .ENDIF
            ;--------------------------------------------------------------
            ; EEex.DLL EXITS HERE
            ;--------------------------------------------------------------
            Invoke TerminateProcess, hEEGameProcess, NULL
            ret ; Exit EEexInitDll
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
    Invoke EEexPatchLocation
    mov PatchLocation, eax
    .IF PatchLocation != 0
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
            .IF gEEexMsg == TRUE
                Invoke MessageBox, 0, Addr szErrorPatchFailure, Addr AppName, MB_OK
            .ENDIF
            ;------------------------------------------------------------------
            ; EEex.DLL EXITS HERE
            ;------------------------------------------------------------------
            Invoke TerminateProcess, hEEGameProcess, NULL
            ret ; Exit EEexInitDll                   
        .ENDIF
    .ELSE
        IFDEF EEEX_LOGGING
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogMessage, CTEXT("PatchLocation is NULL!"), LOG_ERROR, 0
            Invoke LogClose
        .ENDIF
        ENDIF
        .IF gEEexMsg == TRUE
            Invoke MessageBox, 0, Addr szErrorPatchLocation, Addr AppName, MB_OK
        .ENDIF
        ;----------------------------------------------------------------------
        ; EEex.DLL EXITS HERE
        ;----------------------------------------------------------------------
        Invoke TerminateProcess, hEEGameProcess, NULL
        ret ; Exit EEexInitDll        
    .ENDIF
    ;--------------------------------------------------------------------------
    ; Finished Apply Patch Stage
    ;--------------------------------------------------------------------------

    Invoke EEexFunctionAddresses ; get function address for lua functions etc
    Invoke EEexVariableValues ; get pointers to game globals
    Invoke EEexLogInformation, INFO_ADDRESSES ; lists function and resolved global addresses

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
    Invoke lstrcpy, Addr EEexPatFile, Addr EEexIniFile
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
    
    ; Construct patterns database filename
    lea ebx, EEexPatFile
    add ebx, nLength
    sub ebx, 3 ; move back past 'dll' extention
    mov byte ptr [ebx], 0 ; null so we can use lstrcat
    Invoke lstrcat, ebx, Addr szPatDB ; add 'db' to end of string instead    

    Invoke EEexEEFileInformation
    .IF eax == TRUE
        Invoke EEexEEGameInformation
        IFDEF DEBUG32
        PrintDec gEEGameType
        PrintString EEexPatFile
        ENDIF
    .ENDIF

    Invoke IniGetOptionLog
    mov gEEexLog, eax
    Invoke IniGetOptionLua
    mov gEEexLua, eax
    Invoke IniGetOptionHex
    mov gEEexHex, eax
    Invoke IniGetOptionMsg
    mov gEEexMsg, eax
    
    Invoke IniSetOptionLog, gEEexLog
    Invoke IniSetOptionLua, gEEexLua
    Invoke IniSetOptionHex, gEEexHex
    Invoke IniSetOptionMsg, gEEexMsg

    ;--------------------------------------------------------------------------
    ; Get addresses of win32 api functions
    ;--------------------------------------------------------------------------
    Invoke GetModuleHandle, Addr szKernel32Dll
    mov hKernel32, eax
    Invoke GetProcAddress, hKernel32, Addr szGetProcAddressProc
    mov F_GetProcAddress, eax
    Invoke GetProcAddress, hKernel32, Addr szLoadLibraryProc
    mov F_LoadLibrary, eax
    Invoke GetProcAddress, 0, Addr szSDL_FreeExport
    mov F_SDL_free, eax
    
    IFDEF DEBUG32
    PrintText 'Api calls and exports'
    PrintDec F_GetProcAddress
    PrintDec F_LoadLibrary
    PrintDec F_SDL_free
    ENDIF

    xor eax, eax
    ret
EEexInitGlobals ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexImportPatterns - Import patterns from patterns database file: EEex.db
; Returns: TRUE if all patterns were imported without errors, FALSE otherwise
; Note: FALSE can indicate some patterns were skipped due to missing PatBytes
; or could be other errors. PatAdj field will hold an integer repesenting
; the IMP_ERR_xxxxx status of the PATTERN entry that had an error. 
;------------------------------------------------------------------------------
EEexImportPatterns PROC USES EBX
    LOCAL lpszPatternName:DWORD
    LOCAL lpszPatBytesText:DWORD
    LOCAL lpszVerBytesText:DWORD
    LOCAL dwLenPatBytesText:DWORD
    LOCAL dwLenVerBytesText:DWORD
    LOCAL lpPatBytes:DWORD
    LOCAL lpVerBytes:DWORD
    LOCAL dwPatLength:DWORD
    LOCAL dwVerLength:DWORD
    LOCAL dwPatAdj:DWORD
    LOCAL dwVerAdj:DWORD
    LOCAL dwPatType:DWORD
    LOCAL nPattern:DWORD
    LOCAL pPatternEntry:DWORD
    LOCAL dwImportError:DWORD
    
    IFDEF DEBUG32
    PrintText 'EEexImportPatterns'
    ENDIF
    
    ;--------------------------------------------------------------------------
    ; Get pattern names and pattern count from external patterns database file
    ;--------------------------------------------------------------------------
    Invoke IniGetPatternNames ; returns count of pattern names in szIniPatternNames
    .IF eax == -1 ; too many pattern names to fit into max buffer size
        IFDEF EEEX_LOGGING
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogOpen, FALSE
            Invoke LogMessage, Addr szErrorPatternsToMany, LOG_ERROR, 0
            Invoke LogMessage, 0, LOG_CRLF, 0
        .ENDIF
        ENDIF
        mov eax, FALSE
        ret
    .ELSEIF eax == 0 ; no patterns
        IFDEF EEEX_LOGGING
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogOpen, FALSE
            Invoke LogMessage, Addr szErrorPatternsNone, LOG_ERROR, 0
            Invoke LogMessage, 0, LOG_CRLF, 0
        .ENDIF
        ENDIF
        mov eax, FALSE
        ret
    .ELSE
        ; else eax contains total patterns from return of IniGetPatternNames
    .ENDIF
    mov TotalPatterns, eax
    mov TotalPatternsToImport, eax
    .IF eax > INI_MAXSECTIONS
        ; some sort of warning to user?
    .ENDIF
    
    IFDEF DEBUG32
    PrintDec TotalPatternsToImport
    ENDIF
    
    ;--------------------------------------------------------------------------
    ; Allocate memory for patterns to import to array of PATTERN structures
    ;--------------------------------------------------------------------------
    mov eax, TotalPatternsToImport
    add eax, 4
    mov ebx, SIZEOF PATTERN
    mul ebx
    Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, eax
    .IF eax == NULL ; failed to alloc mem
        IFDEF EEEX_LOGGING
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogOpen, FALSE
            Invoke LogMessage, Addr szErrorPatternsAlloc, LOG_ERROR, 0
            Invoke LogMessage, 0, LOG_CRLF, 0
        .ENDIF
        ENDIF
        mov eax, FALSE
        ret
    .ENDIF
    mov PatternsDatabase, eax
    mov pPatternEntry, eax
    
    
    ;--------------------------------------------------------------------------
    ; Loop through each pattern name (section name) from pattern database file
    ; Convert PatBytes from text hexidecimal to raw bytes and get length
    ; Convert VerBytes from text hexidecimal to raw bytes and get length
    ; Alloc space for PatBytes and VerBytes
    ; Get PatAdj, VerAdj and Type
    ; Fill in PATTERN structure for pattern entry with pointers to pattern name
    ; (section name), pointers to PatBytes and VerBytes, and values for
    ; PatAdj, VerAdj and Type
    ;--------------------------------------------------------------------------
    mov dwImportError, 0
    mov lpPatBytes, 0
    mov lpVerBytes, 0
    mov dwPatLength, 0
    mov dwVerLength, 0
    mov dwPatAdj, 0
    mov dwVerAdj, 0
    mov dwPatType, 0
    mov nPattern, 0
    mov ebx, pPatternEntry
    
    Invoke IniGetNextPatternName
    .WHILE eax != 0
        mov lpszPatternName, eax ; store pointer to pattern name
        
        IFDEF DEBUG32
        ;PrintStringByAddr lpszPatternName
        ENDIF
        
        ;----------------------------------------------------------------------
        ; Get PatBytes hex text chars for <PatternName>
        ;----------------------------------------------------------------------     
        Invoke IniGetPatBytesText, lpszPatternName, Addr lpszPatBytesText
        .IF eax == 0 ; PatBytes entry is empty
            mov dwImportError, IMP_ERR_PATBYTES_EMPTY
            mov lpPatBytes, 0
        .ELSE
            ;------------------------------------------------------------------
            ; Convert PatBytes entry from text hex chars to raw byte pattern
            ;------------------------------------------------------------------
            mov dwLenPatBytesText, eax
            shr eax, 1 ; div by 2
            add eax, 4
            mov dwPatLength, eax
             Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, dwPatLength
            .IF eax == NULL
                mov dwImportError, IMP_ERR_PATBYTES_ALLOC
                mov lpPatBytes, 0
            .ELSE
                mov lpPatBytes, eax
                Invoke EEexHexStringToRaw, lpszPatBytesText, lpPatBytes
                .IF eax == 0
                    mov dwImportError, IMP_ERR_PATBYTES_NOTHEX
                    mov lpPatBytes, 0
                .ELSE
                    mov dwPatLength, eax ; update the correct pattern lenght
                .ENDIF
            .ENDIF
            
            .IF lpPatBytes != 0
                ;--------------------------------------------------------------
                ; Get VerBytes hex text chars for <PatternName>
                ;--------------------------------------------------------------
                Invoke IniGetVerBytesText, lpszPatternName, Addr lpszVerBytesText
                .IF eax == 0 ; VerBytes entry is empty - which is allowed
                    mov lpVerBytes, 0
                    mov dwVerLength, 0
                    mov dwVerAdj, 0
                    mov dwImportError, IMP_ERR_VERBYTES_EMPTY ; this is allowed
                .ELSE
                    ;----------------------------------------------------------
                    ; Convert VerBytes entry from text hex chars to raw byte pattern
                    ;----------------------------------------------------------
                    mov dwLenVerBytesText, eax
                    shr eax, 1 ; div by 2
                    add eax, 4
                    mov dwVerLength, eax
                    Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, dwVerLength
                    .IF eax == NULL
                        .IF lpPatBytes!= 0
                            mov eax, lpPatBytes
                            Invoke GlobalFree, eax
                        .ENDIF
                        mov dwImportError, IMP_ERR_VERBYTES_ALLOC
                        mov lpPatBytes, 0
                    .ELSE
                        mov lpVerBytes, eax
                        Invoke EEexHexStringToRaw, lpszVerBytesText, lpVerBytes
                        .IF eax == 0
                            mov dwImportError, IMP_ERR_VERBYTES_NOTHEX
                            mov lpPatBytes, 0
                        .ELSE
                            mov dwVerLength, eax ; update the correct pattern lenght
                        .ENDIF                        
                    .ENDIF
                .ENDIF
            .ENDIF
            
            ;------------------------------------------------------------------
            ; Get PatAdj, VerAdj and PatType values for <PatternName>
            ;------------------------------------------------------------------
            .IF lpPatBytes != 0
                Invoke IniGetPatAdj, lpszPatternName
                mov dwPatAdj, eax
                Invoke IniGetVerAdj, lpszPatternName
                mov dwVerAdj, eax
                Invoke IniGetPatType, lpszPatternName
                mov dwPatType, eax
            .ENDIF
        .ENDIF
        
        ;----------------------------------------------------------------------  
        ; Add information to PATTERN entry
        ;----------------------------------------------------------------------  
        .IF lpPatBytes != 0
        
            IFDEF DEBUG32
            ;PrintText 'Pattern imported to PatternDatabase'
            ;PrintDec nPattern
            ENDIF        
        
            mov ebx, pPatternEntry
            mov eax, lpPatBytes
            mov [ebx].PATTERN.PatBytes, eax
            mov eax, lpVerBytes
            mov [ebx].PATTERN.VerBytes, eax
            mov eax, dwPatLength
            mov [ebx].PATTERN.PatLength, eax
            mov eax, dwVerLength
            mov [ebx].PATTERN.VerLength, eax
            mov eax, dwPatAdj
            mov [ebx].PATTERN.PatAdj, eax
            mov eax, dwVerAdj
            mov [ebx].PATTERN.VerAdj, eax
            mov eax, dwPatType
            mov [ebx].PATTERN.PatType, eax
            mov eax, lpszPatternName
            mov [ebx].PATTERN.PatName, eax
            
            .IF gEEexLua == TRUE
                Invoke EEexIsStaticLua, lpszPatternName ; See if pattern name matches static lua address
                .IF eax != 0 ; matches known lua static
                    mov ebx, pPatternEntry
                    mov [ebx].PATTERN.bFound, TRUE ; set to true to skip verification
                    mov [ebx].PATTERN.PatAddress, eax
                    inc SkippedImportedPatterns
                .ELSE
                    .IF dwPatType == 2
                        ; Get type 2 <PatternName> Count= from EEex.ini and store in veradj
                        Invoke IniReadValue, lpszPatternName, Addr szIniCount, 0
                        mov ebx, pPatternEntry
                        mov [ebx].PATTERN.VerAdj, eax
                    .ELSE
                        ; Get <PatternName> from EEex.ini - if it exists, which will speed up verification
                        Invoke IniReadValue, Addr szIniEEex, lpszPatternName, 0
                        mov ebx, pPatternEntry
                        mov [ebx].PATTERN.PatAddress, eax
                    .ENDIF
                    inc ImportedPatterns
                .ENDIF
            .ELSE
                .IF dwPatType == 2
                    ; Get type 2 <PatternName> Count= from EEex.ini and store in veradj
                    Invoke IniReadValue, lpszPatternName, Addr szIniCount, 0
                    mov ebx, pPatternEntry
                    mov [ebx].PATTERN.VerAdj, eax
                .ELSE            
                    ; Get <PatternName> from EEex.ini - if it exists, which will speed up verification
                    Invoke IniReadValue, Addr szIniEEex, lpszPatternName, 0
                    mov ebx, pPatternEntry
                    mov [ebx].PATTERN.PatAddress, eax
                .ENDIF
                inc ImportedPatterns
            .ENDIF

        .ELSE

            IFDEF DEBUG32
            PrintText 'Pattern import issue'
            PrintDec nPattern
            PrintDec dwImportError
            ENDIF
            
            ; Add pattern name at least and set some field to indicate error reason
            mov ebx, pPatternEntry
            mov eax, lpszPatternName
            mov [ebx].PATTERN.PatName, eax
            mov [ebx].PATTERN.PatBytes, 0
            mov [ebx].PATTERN.PatAddress, 0
            mov eax, dwImportError
            mov [ebx].PATTERN.PatAdj, eax
            inc NotImportedPatterns
        .ENDIF
        
        ;----------------------------------------------------------------------  
        ; Setup for next pattern entry
        ;----------------------------------------------------------------------
        inc nPattern
        add pPatternEntry, SIZEOF PATTERN
        Invoke IniGetNextPatternName
    .ENDW

    mov eax, ImportedPatterns
    add eax, SkippedImportedPatterns
    .IF eax == TotalPatternsToImport && TotalPatternsToImport != 0; imported all patterns!
        mov eax, TRUE
    .ELSE
        mov eax, FALSE
    .ENDIF    
    
    ret
EEexImportPatterns ENDP


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
    LOCAL dwAddress:DWORD
    LOCAL dwAddressMax:DWORD
    LOCAL PatAddress:DWORD
    LOCAL PatBytes:DWORD
    LOCAL PatLength:DWORD
    LOCAL VerAdj:DWORD
    LOCAL VerBytes:DWORD
    LOCAL VerLength:DWORD

    IFDEF DEBUG32
    PrintText 'EEexVerifyPatterns'
    ENDIF

    ;mov eax, EEGameSectionTEXTPtr
    ;add eax, EEGameSectionTEXTSize
    ;mov dwAddressMax, eax

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        mov eax, [ebx].PATTERN.PatAddress
        .IF eax == 0 || [ebx].PATTERN.PatType == 2 ;|| eax > dwAddressMax ; just in case
            .IF [ebx].PATTERN.PatType == 2
                inc SkippedVerifyPatterns ; verify type 2 patterns elsewhere
            .ENDIF
            inc NotVerifiedPatterns
            
            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
            .CONTINUE
        .ENDIF
        
        ;PrintText 'EEexVerifyPatterns - pattern has address'
        ;PrintDec nPattern
        ;PrintDec eax
        
        mov PatAddress, eax
        mov ebx, ptrCurrentPattern
        sub eax, [ebx].PATTERN.PatAdj ; subtract adjustment to get pattern
        mov dwAddress, eax

        mov eax, [ebx].PATTERN.PatBytes
        .IF eax != NULL
            mov PatBytes, eax
            mov eax, [ebx].PATTERN.PatLength
            mov PatLength, eax
    
            ; check pattern matches
            Invoke PatternVerify, dwAddress, PatBytes, PatLength
            mov ebx, ptrCurrentPattern
            .IF eax == TRUE
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
        .ELSE
            inc SkippedVerifyPatterns
        .ENDIF
        
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW
    
    ;PrintDec VerifiedPatterns
    ;PrintDec SkippedVerifyPatterns
    ;PrintDec TotalPatterns
    
    mov eax, VerifiedPatterns
    add eax, SkippedVerifyPatterns
    .IF eax == TotalPatterns && TotalPatterns != 0
        ;.IF SkippedVerifyPatterns > 0
            Invoke EEexVerifyType2Patterns ; check and verify for type 2 patterns
        ;.ELSE
        ;    mov eax, TRUE
        ;.ENDIF    
    .ELSE
        mov eax, FALSE
    .ENDIF

    ret
EEexVerifyPatterns ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexVerifyType2Patterns - Verify type 2 patterns. Type 2 patterns have a
; section in the EEex.ini named after the pattern. The section has one key value
; 'Count=' that stores the number of address entries in the section. The address
; entries are enumerated as '1=0x1234ABCD', '2=ABCD1234' etc up to the value 
; obtained from the 'Count=' key.
;
; Returns: TRUE if all type 2 patterns where succesfully verified or FALSE.
;------------------------------------------------------------------------------
EEexVerifyType2Patterns PROC USES EBX
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL nTotal:DWORD
    LOCAL nCount:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL PatBytes:DWORD
    LOCAL PatLength:DWORD
    LOCAL PatAddress:DWORD
    LOCAL pType2Array:DWORD
    LOCAL pCurrentType2Entry:DWORD
    LOCAL RetVal:DWORD
    
    IFDEF DEBUG32
    PrintText 'EEexVerifyType2Patterns'
    ENDIF    
    
    mov RetVal, TRUE
    
    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        .IF [ebx].PATTERN.PatType == 2
            
            mov eax, [ebx].PATTERN.VerAdj ; VerAdj is used to store 'Count=' of keys for type2 patterns
            .IF eax != 0
                mov nTotal, eax

                mov eax, [ebx].PATTERN.PatBytes
                .IF eax != NULL
                    mov PatBytes, eax
                    mov eax, [ebx].PATTERN.PatLength
                    mov PatLength, eax
                    mov eax, [ebx].PATTERN.PatName
                    mov lpszPatternName, eax
                    
                    ;----------------------------------------------------------
                    ; Alloc array for type 2 entries - array address will
                    ; be stored in PatAddress field for type 2 patterns
                    ;----------------------------------------------------------
                    mov eax, nTotal
                    inc eax ; add extra 1 to null last entry
                    mov ebx, SIZEOF DWORD
                    mul ebx
                    Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, eax
                    .IF eax == NULL
                        .BREAK
                    .ENDIF
                    mov pType2Array, eax
                    mov pCurrentType2Entry, eax
                    
                    ;----------------------------------------------------------
                    ; loop through <PatternName> section in EEex.ini and fetch
                    ; 1=x, 2=x, 3=x and so on for each x address up to total
                    ; count and verify each address contains PatBytes
                    ;----------------------------------------------------------
                    mov nCount, 0
                    mov eax, 0
                    .WHILE eax < nTotal
                        
                        Invoke EEexDwordToAscii, nCount, Addr szIniEnumString ; convert n integer to string 'n'
                        Invoke IniReadValue, lpszPatternName, Addr szIniEnumString, 0 ; n=0x1234ABCD
                        .IF eax != 0
                            mov PatAddress, eax
                            Invoke PatternVerify, PatAddress, PatBytes, PatLength
                            .IF eax == FALSE
                                .BREAK ; if any are 0 then have to fail this type 2 pattern
                            .ENDIF
                            ; Verified, so store in our array
                            mov ebx, pCurrentType2Entry
                            mov eax, PatAddress
                            mov [ebx], eax
                        .ELSE
                            .BREAK ; if any are 0 then have to fail this type 2 pattern
                        .ENDIF
                        
                        add pCurrentType2Entry, SIZEOF DWORD
                        inc nCount
                        mov eax, nCount
                    .ENDW
                    
                    ;----------------------------------------------------------
                    ; After coming out of loop decide how to proceed
                    ;----------------------------------------------------------
                    mov ebx, ptrCurrentPattern
                    IFDEF DEBUG32
                    PrintDec nCount
                    PrintDec nTotal
                    ENDIF
                    mov eax, nCount
                    .IF eax == nTotal ; looped through all successfully
                        mov [ebx].PATTERN.bFound, TRUE
                        mov eax, pType2Array
                        mov [ebx].PATTERN.PatAddress, eax ; array of these addresses are stored in PatAddress field
                        .IF NotVerifiedPatterns > 0
                            ;dec SkippedVerifyPatterns
                            dec NotVerifiedPatterns
                        .ENDIF
                        inc VerifiedPatterns
                        
                    .ELSE ; broke out early coz we had a 0 address for one of the keys in the type2 pattern section in EEex.ini
                        mov [ebx].PATTERN.bFound, FALSE
                        mov eax, pType2Array
                        .IF eax != 0
                            Invoke GlobalFree, eax ; free array as we cant use it, as its incomplete
                        .ENDIF
                        mov RetVal, FALSE ; any not verified will trigger FALSE return value
                    .ENDIF
                    
                .ENDIF
            .ELSE
                ; nothing to verify, first run of type2 pattern?
                mov RetVal, FALSE
            .ENDIF
        .ENDIF
    
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW
    
    mov eax, RetVal
    ret
EEexVerifyType2Patterns ENDP


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
    LOCAL dwPatAddress:DWORD
    LOCAL PatAdj:DWORD
    LOCAL PatBytes:DWORD
    LOCAL PatLength:DWORD
    LOCAL PatType:DWORD
    LOCAL VerAdj:DWORD
    LOCAL VerBytes:DWORD
    LOCAL VerLength:DWORD
    LOCAL pType2Array:DWORD
    LOCAL nCount:DWORD
    LOCAL RetVal:DWORD

    IFDEF DEBUG32
    PrintText 'EEexSearchPatterns'
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

        mov ebx, PatternsDatabase
        mov ptrCurrentPattern, ebx
        mov nPattern, 0
        mov eax, 0
        .WHILE eax < TotalPatterns
            .IF [ebx].PATTERN.bFound == FALSE
                mov eax, [ebx].PATTERN.PatBytes
                .IF eax != NULL
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
                                .IF [ebx].PATTERN.PatType == 2
                                    IFDEF DEBUG32
                                    PrintText 'EEexSearchPatterns - Type 2 pattern found'
                                    ENDIF
                                    ;------------------------------------------
                                    ; Handle type 2 patterns
                                    ; Note: cant set to TRUE as we have to 
                                    ; search for more type 2 occurances
                                    ;------------------------------------------                                
                                    mov eax, [ebx].PATTERN.PatAddress ; pointer to array
                                    .IF eax == 0 ; No array has been allocated mem yet
                                        IFDEF DEBUG32
                                        PrintText 'EEexSearchPatterns - Type 2 array initial alloc'
                                        ENDIF                                    
                                        Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, TYPE2_ARRAY_INITIAL_SIZE
                                        .IF eax != NULL
                                            mov pType2Array, eax
                                            mov ebx, eax
                                            mov eax, dwAddress
                                            mov [ebx], eax ; save address to pType2Array[0] 
                                            
                                            mov ebx, ptrCurrentPattern
                                            mov eax, pType2Array
                                            mov [ebx].PATTERN.PatAddress, eax
                                            mov [ebx].PATTERN.VerAdj, 1
                                        .ELSE ; error could not allocate memory
                                            mov ebx, ptrCurrentPattern
                                            mov [ebx].PATTERN.PatAddress, 0
                                            mov [ebx].PATTERN.VerAdj, 0
                                        .ENDIF 
                                    .ELSE ; existing array already stored in PatAddress
                                        mov pType2Array, eax
                                        
                                        mov eax, [ebx].PATTERN.VerAdj
                                        mov nCount, eax
                                        inc eax
                                        and eax, 63d ; nCount mod 64 - realloc mem if nCount mod 64 == 0
                                        .IF eax == 0 ; time to realloc. Every 64 entries we had another 64
                                            IFDEF DEBUG32
                                            PrintText 'EEexSearchPatterns - Type 2 array re-alloc'
                                            ENDIF                                          
                                            mov eax, nCount
                                            add eax, 64d 
                                            mov ebx, SIZEOF DWORD
                                            mul ebx ; add (64 x 4) for additional 64 array entries
                                            Invoke GlobalReAlloc, pType2Array, eax, GMEM_ZEROINIT or GMEM_MOVEABLE
                                            .IF eax != NULL ; save changed array mem location back to PatAddress
                                                mov pType2Array, eax
                                                mov ebx, ptrCurrentPattern
                                                mov eax, pType2Array
                                                mov [ebx].PATTERN.PatAddress, eax                                                
                                            .ELSE ; error could not re-allocate memory
                                                mov ebx, ptrCurrentPattern
                                                mov [ebx].PATTERN.PatAddress, 0
                                                mov [ebx].PATTERN.VerAdj, 0
                                                mov pType2Array, 0
                                            .ENDIF
                                        .ENDIF
                                        .IF pType2Array != 0
                                            mov eax, nCount
                                            mov ebx, SIZEOF DWORD
                                            mul ebx
                                            mov ebx, pType2Array
                                            add ebx, eax
                                            mov eax, dwAddress
                                            mov [ebx], eax ; save address to pType2Array[nCount]
                                            
                                            ; increment count of type 2 pattern
                                            inc nCount
                                            mov eax, nCount
                                            mov ebx, ptrCurrentPattern
                                            mov [ebx].PATTERN.VerAdj, eax                                            
                                            
                                        .ENDIF
                                    .ENDIF
                                .ELSE
                                    ;------------------------------------------
                                    ; Handle all other patterns types
                                    ;------------------------------------------  
                                    mov [ebx].PATTERN.bFound, TRUE
                                    mov eax, dwAddress
                                    add eax, [ebx].PATTERN.PatAdj
                                    mov dwPatAddress, eax 
                                    mov [ebx].PATTERN.PatAddress, eax
                                    inc FoundPatterns ; PatternsFound
                                    
                                    ; Free pattern memory as we dont need it anymore
                                    mov ebx, ptrCurrentPattern
                                    mov eax, [ebx].PATTERN.PatBytes
                                    .IF eax != NULL && [ebx].PATTERN.PatLength != 0
                                        Invoke GlobalFree, eax
                                    .ENDIF
                                    mov ebx, ptrCurrentPattern
                                    mov eax, [ebx].PATTERN.VerBytes
                                    .IF eax != NULL && [ebx].PATTERN.VerLength != 0
                                        Invoke GlobalFree, eax
                                    .ENDIF
                                .ENDIF
                                
                            .ELSE ; pattern is similar to another but wasnt found and verified yet: A Get/Set function with minor differences?
                            .ENDIF
                        .ENDIF
                    .ENDIF
                .ELSE
                    inc SkippedFoundPatterns
                .ENDIF
            .ENDIF

            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
        .ENDW

        mov eax, FoundPatterns ; PatternsFound
        add eax, SkippedFoundPatterns
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
        mov ebx, PatternsDatabase
        mov ptrCurrentPattern, ebx
        mov nPattern, 0
        mov eax, 0
        .WHILE eax < TotalPatterns
            .IF [ebx].PATTERN.bFound == FALSE
            
                .IF [ebx].PATTERN.PatType == 2 && [ebx].PATTERN.VerAdj != 0
                    mov [ebx].PATTERN.bFound, TRUE
                    inc FoundPatterns
                    ; Free pattern memory as we dont need it anymore
                    mov ebx, ptrCurrentPattern
                    mov eax, [ebx].PATTERN.PatBytes
                    .IF eax != NULL && [ebx].PATTERN.PatLength != 0
                        Invoke GlobalFree, eax
                    .ENDIF                    
                .ELSE
                    inc NotFoundPatterns
                    IFDEF DEBUG32
                    PrintDec nPattern
                    ENDIF
                    mov [ebx].PATTERN.PatAddress, 0
                    
                    ; Free pattern memory as we dont need it anymore
                    mov ebx, ptrCurrentPattern
                    mov eax, [ebx].PATTERN.PatBytes
                    .IF eax != NULL && [ebx].PATTERN.PatLength != 0
                        Invoke GlobalFree, eax
                    .ENDIF
                    mov ebx, ptrCurrentPattern
                    mov eax, [ebx].PATTERN.VerBytes
                    .IF eax != NULL && [ebx].PATTERN.VerLength != 0
                        Invoke GlobalFree, eax
                    .ENDIF                    
                .ENDIF
            .ENDIF
            add ptrCurrentPattern, SIZEOF PATTERN
            mov ebx, ptrCurrentPattern
            inc nPattern
            mov eax, nPattern
        .ENDW
    .ENDIF
    
    ; Double check again - in case we found type 2 patterns with count > 0
    mov eax, FoundPatterns ; PatternsFound
    add eax, SkippedFoundPatterns
    .IF eax == TotalPatterns ; found all patterns!
        mov RetVal, TRUE
    .ENDIF

    mov eax, RetVal
    ret
EEexSearchPatterns ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexPatchLocation - Get patch location address from pattern database
; should be first entry in database!
; Returns: in eax the address of PatchLocation or 0 if not found
;------------------------------------------------------------------------------
EEexPatchLocation PROC USES EBX
    LOCAL pPatternEntry:DWORD
    LOCAL nPattern:DWORD
    
    IFDEF DEBUG32
    PrintText 'EEexPatchLocation'
    ENDIF    
    
    mov ebx, PatternsDatabase
    mov pPatternEntry, ebx    
    
    mov eax, [ebx].PATTERN.PatName
    .IF eax != 0
        mov ebx, eax
        mov eax, [ebx]
        mov ebx, [ebx+4]
        .IF eax == 'ctaP' && ebx == 'coLh' ; Patc hLoc
            mov ebx, pPatternEntry
            mov eax, [ebx].PATTERN.PatAddress
        .ELSE
            mov eax, 0
        .ENDIF
    .ELSE
        mov eax, 0
    .ENDIF
    
    .IF eax == 0 ; do a full search of pattern database, in case PatchLocation is not at position 0
        mov ebx, PatternsDatabase
        mov pPatternEntry, ebx
        
        mov nPattern, 0
        mov eax, 0
        .WHILE eax < TotalPatterns
            mov ebx, pPatternEntry
            mov eax, [ebx].PATTERN.PatName
            .IF eax != 0
                mov ebx, eax
                mov eax, [ebx]
                mov ebx, [ebx+4]
                .IF eax == 'ctaP' && ebx == 'coLh' ; Patc hLoc
                    mov ebx, pPatternEntry
                    mov eax, [ebx].PATTERN.PatAddress
                    ret ; return with patch address location
                .ENDIF
            .ENDIF
            add pPatternEntry, SIZEOF PATTERN
            inc nPattern
            mov eax, nPattern
        .ENDW
        mov eax, 0 ; didnt find patch location at all in whole pattern database
    .ENDIF
    
    ret
EEexPatchLocation ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexIsStaticLua - Returns address of static lua function if <PatternName>
; matches, otherwise returns 0
;------------------------------------------------------------------------------
EEexIsStaticLua PROC USES EBX lpszPatternName:DWORD

    IFDEF DEBUG32
    PrintText 'EEexIsStaticLua'
    ENDIF
    
    IFDEF EEEX_LUALIB
    .IF lpszPatternName == NULL
        xor eax, eax
        ret
    .ENDIF
    
    mov ebx, lpszPatternName
    mov eax, [ebx]
    .IF eax != 'aul_' ; _lua
        xor eax, eax
        ret
    .ENDIF
    
    Invoke lstrcmp, lpszPatternName, Addr szLua_createtable ; CTEXT("_lua_createtable")
    .IF eax == 0 ; match
        lea eax, lua_createtable
        mov F_Lua_createtable, eax
        ret
    .ENDIF
    Invoke lstrcmp, lpszPatternName, Addr szLua_pushcclosure ; CTEXT("_lua_pushcclosure")
    .IF eax == 0 ; match
        lea eax, lua_pushcclosure
        mov F_Lua_pushcclosure, eax
        ret
    .ENDIF
    Invoke lstrcmp, lpszPatternName, Addr szLua_pushnumber ; CTEXT("_lua_pushnumber")
    .IF eax == 0 ; match
        lea eax, lua_pushnumber
        mov F_Lua_pushnumber, eax
        ret
    .ENDIF                
    Invoke lstrcmp, lpszPatternName, Addr szLua_pushstring ; CTEXT("_lua_pushstring")
    .IF eax == 0 ; match
        lea eax, lua_pushstring
        mov F_Lua_pushstring, eax
        ret
    .ENDIF                
    Invoke lstrcmp, lpszPatternName, Addr szLua_rawlen ; CTEXT("_lua_rawlen")
    .IF eax == 0 ; match
        lea eax, lua_rawlen
        mov F_Lua_rawlen, eax
        ret
    .ENDIF
    Invoke lstrcmp, lpszPatternName, Addr szLua_rawgeti ; CTEXT("_lua_rawgeti")
    .IF eax == 0 ; match
        lea eax, lua_rawgeti
        mov F_Lua_rawgeti, eax
        ret
    .ENDIF
    Invoke lstrcmp, lpszPatternName, Addr szLua_setglobal ; CTEXT("_lua_setglobal")
    .IF eax == 0 ; match
        lea eax, lua_setglobalx
        mov F_Lua_setglobal, eax
        ret
    .ENDIF
    Invoke lstrcmp, lpszPatternName, Addr szLua_settable ; CTEXT("_lua_settable")
    .IF eax == 0 ; match
        lea eax, lua_settable
        mov F_Lua_settable, eax
        ret
    .ENDIF
    Invoke lstrcmp, lpszPatternName, Addr szLua_tolstring ; CTEXT("_lua_tolstring")
    .IF eax == 0 ; match
        lea eax, lua_tolstring
        mov F_Lua_tolstring, eax
        ret
    .ENDIF                
    Invoke lstrcmp, lpszPatternName, Addr szLua_tonumberx ; CTEXT("_lua_tonumberx")
    .IF eax == 0 ; match
        lea eax, lua_tonumberx
        mov F_Lua_tonumberx, eax
        ret
    .ENDIF
    ENDIF
    
    xor eax, eax ; else
    ret
EEexIsStaticLua ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexFunctionAddresses - Get lua function addresses - used internally
; Looks for __ftol2_sse, lua_createtable, luaL_loadstring, lua_pushcclosure,
; lua_setglobal, lua_pushnumber, lua_tonumberx, lua_tolstring, lua_rawlen, 
; lua_rawgeti, lua_pushstring, lua_settable
; Returns: None 
;------------------------------------------------------------------------------
EEexFunctionAddresses PROC USES EBX
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternAddress:DWORD

    IFDEF DEBUG32
    PrintText 'EEexFunctionAddresses'
    ENDIF  

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        .IF [ebx].PATTERN.bFound == TRUE
            mov eax, [ebx].PATTERN.PatAddress
            mov dwPatternAddress, eax
            mov eax, [ebx].PATTERN.PatName
            mov lpszPatternName, eax
            .IF gEEexLua == FALSE || gEEexLuaLibDefined == FALSE
                mov ebx, lpszPatternName
                mov eax, [ebx]
                .IF eax == 'aul_' ; _lua
                    Invoke lstrcmp, lpszPatternName, Addr szLua_createtable ; CTEXT("_lua_createtable")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_createtable, eax
                        jmp getnextpattern
                    .ENDIF
                    Invoke lstrcmp, lpszPatternName, Addr szLua_pushcclosure ; CTEXT("_lua_pushcclosure")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_pushcclosure, eax
                        jmp getnextpattern
                    .ENDIF
                    Invoke lstrcmp, lpszPatternName, Addr szLua_pushnumber ; CTEXT("_lua_pushnumber")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_pushnumber, eax
                        jmp getnextpattern
                    .ENDIF                
                    Invoke lstrcmp, lpszPatternName, Addr szLua_pushstring ; CTEXT("_lua_pushstring")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_pushstring, eax
                        jmp getnextpattern
                    .ENDIF                
                    Invoke lstrcmp, lpszPatternName, Addr szLua_rawlen ; CTEXT("_lua_rawlen")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_rawlen, eax
                        jmp getnextpattern
                    .ENDIF
                    Invoke lstrcmp, lpszPatternName, Addr szLua_rawgeti ; CTEXT("_lua_rawgeti")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_rawgeti, eax
                        jmp getnextpattern
                    .ENDIF
                    Invoke lstrcmp, lpszPatternName, Addr szLua_setglobal ; CTEXT("_lua_setglobal")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_setglobal, eax
                        jmp getnextpattern
                    .ENDIF
                    Invoke lstrcmp, lpszPatternName, Addr szLua_settable ; CTEXT("_lua_settable")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_settable, eax
                        jmp getnextpattern
                    .ENDIF
                    Invoke lstrcmp, lpszPatternName, Addr szLua_tolstring ; CTEXT("_lua_tolstring")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_tolstring, eax
                        jmp getnextpattern
                    .ENDIF                
                    Invoke lstrcmp, lpszPatternName, Addr szLua_tonumberx ; CTEXT("_lua_tonumberx")
                    .IF eax == 0 ; match
                        mov eax, dwPatternAddress
                        mov F_Lua_tonumberx, eax
                        jmp getnextpattern
                    .ENDIF
                .ENDIF
            .ENDIF
            
            mov ebx, lpszPatternName
            mov eax, [ebx]
            .IF eax == 'aul_' || eax == 'tf__'  ; _lua  || __ft            
                ; have to get this _luaL_loadstring from game regardless of static libs being used
                Invoke lstrcmp, lpszPatternName, Addr szLuaL_loadstring ; CTEXT("_luaL_loadstring")
                .IF eax == 0 ; match
                    mov eax, dwPatternAddress
                    mov F_LuaL_loadstring, eax
                    jmp getnextpattern
                .ENDIF
                ; have to always get this
                Invoke lstrcmp, lpszPatternName, Addr sz_ftol2_sse ; CTEXT("__ftol2_sse")
                .IF eax == 0 ; match
                    mov eax, dwPatternAddress
                    mov F__ftol2_sse, eax
                .ENDIF              
            .ENDIF
            
        .ENDIF

getnextpattern:
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW
    
    IFDEF DEBUG32
    PrintDec F_Lua_createtable
    PrintDec F_Lua_pushcclosure
    PrintDec F_Lua_pushnumber
    PrintDec F_Lua_pushstring
    PrintDec F_Lua_rawlen
    PrintDec F_Lua_rawgeti
    PrintDec F_Lua_setglobal
    PrintDec F_Lua_settable
    PrintDec F_Lua_tolstring
    PrintDec F_Lua_tonumberx
    PrintDec F_LuaL_loadstring
    PrintDec F__ftol2_sse
    ENDIF
    
    
    xor eax, eax
    ret
EEexFunctionAddresses ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexApplyCallPatch - Patches EE Game to Call EEexLuaInit
; Returns: TRUE if succesful or FALSE otherwise.
;------------------------------------------------------------------------------
EEexApplyCallPatch PROC USES EBX ESI dwAddressToPatch:DWORD
    LOCAL dwDistance:DWORD
    LOCAL dwOldProtect:DWORD

    IFDEF DEBUG32
    PrintText 'EEexApplyCallPatch'
    ENDIF  

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
; EEexVariableValues - Process game global variables and other variables - 
; Type 1, 3 and 4 patterns. Read byte, word or dword value at pattern address 
; p_lua ("_g_lua") is used internally in lua function calls in EEexLua.asm 
; Returns: none
;------------------------------------------------------------------------------
EEexVariableValues PROC USES EBX
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternAddress:DWORD

    IFDEF DEBUG32
    PrintText 'EEexVariableValues'
    ENDIF  

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        .IF [ebx].PATTERN.bFound == TRUE && [ebx].PATTERN.PatType == 1 ; read dword
            mov eax, [ebx].PATTERN.PatAddress
            mov dwPatternAddress, eax
            mov eax, [ebx].PATTERN.PatName
            mov lpszPatternName, eax
            
            ; Get this one for our own internal usage
            Invoke lstrcmp, lpszPatternName, CTEXT("_g_lua")
            .IF eax == 0 ; match
                mov eax, dwPatternAddress
                .IF eax != 0
                    mov eax, [eax]
                    mov p_lua, eax
                .ELSE
                    mov p_lua, eax
                .ENDIF
            .ENDIF
            
            ; update type 1 pattern - a game global variable to point to actual content
            mov eax, dwPatternAddress
            .IF eax != 0
                mov ebx, ptrCurrentPattern
                mov eax, [eax]
                mov [ebx].PATTERN.PatAddress, eax
            .ENDIF
        
        .ELSEIF [ebx].PATTERN.bFound == TRUE && [ebx].PATTERN.PatType == 3 ; read byte
            mov eax, [ebx].PATTERN.PatAddress
            .IF eax != 0
                mov ebx, ptrCurrentPattern
                movzx eax, byte ptr [eax]
                mov [ebx].PATTERN.PatAddress, eax
            .ENDIF
            
        .ELSEIF [ebx].PATTERN.bFound == TRUE && [ebx].PATTERN.PatType == 4 ; read word
            mov eax, [ebx].PATTERN.PatAddress
            mov dwPatternAddress, eax
            .IF eax != 0
                mov ebx, ptrCurrentPattern
                movzx eax, word ptr [eax]
                mov [ebx].PATTERN.PatAddress, eax
            .ENDIF
            
        .ENDIF
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW

    ret
EEexVariableValues ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLogInformation - Output some information to the log.
; dwType: 
;
;  INFO_ALL                EQU 0
;  INFO_GAME               EQU 1
;  INFO_DEBUG              EQU 2
;  INFO_IMPORTED           EQU 3
;  INFO_VERIFIED           EQU 4
;  INFO_SEARCHED           EQU 5
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

;    IFDEF DEBUG32
;    PrintText 'EEexLogInformation'
;    PrintDec dwType
;    ENDIF  

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
        Invoke LogMessageAndValue, CTEXT("Msg"), gEEexMsg
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
    ; Log patterns that we were not imported
    ;--------------------------------------------------------------------------
    .IF dwType == INFO_IMPORTED
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogMessage, CTEXT("Patterns Imported:"), LOG_INFO, 0
            ; x patterns imported out of x patterns
            Invoke EEexDwordToAscii, ImportedPatterns, Addr szImportedNo
            Invoke lstrcpy, Addr szPatternMessageBuffer, Addr szImportedNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szImported
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szPatternsOutOf
            Invoke EEexDwordToAscii, TotalPatterns, Addr szTotalPatternNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szTotalPatternNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szPatterns
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            ; x patterns not imported
            Invoke EEexDwordToAscii, NotImportedPatterns, Addr szNotImportedNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szNotImportedNo
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szNotImported
            Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            ; x patterns skipped
            .IF SkippedImportedPatterns > 0
                Invoke EEexDwordToAscii, SkippedImportedPatterns, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkipped
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            .ENDIF
            Invoke LogMessage, Addr szPatternMessageBuffer, LOG_STANDARD, 0    
        .ENDIF
        .IF gEEexLog >= LOGLEVEL_DETAIL        
            .IF NotImportedPatterns > 0 || ImportedPatterns == 0
                Invoke LogMessage, CTEXT("Patterns Not Imported:"), LOG_STANDARD, 0
                Invoke EEexLogImportPatterns, TRUE
                Invoke LogMessage, 0, LOG_CRLF, 0
            .ENDIF
        .ENDIF
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
            .IF SkippedVerifyPatterns > 0
                Invoke EEexDwordToAscii, SkippedVerifyPatterns, Addr szSkippedNo
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
            mov eax, VerifiedPatterns ; show list of patterns if some verified
            .IF eax != TotalPatterns && TotalPatterns != 0 ; coz we skip searching, otherwise none shown
                Invoke LogMessage, CTEXT("Patterns Verified:"), LOG_STANDARD, 0
                Invoke EEexLogPatterns, TRUE
                Invoke LogMessage, 0, LOG_CRLF, 0
            .ENDIF
        .ENDIF
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Log patterns that we searched and found (or used fallbacks for)
    ;--------------------------------------------------------------------------
    .IF dwType == INFO_SEARCHED
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
            .IF SkippedFoundPatterns > 0
                Invoke EEexDwordToAscii, SkippedFoundPatterns, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkippedNo
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szSkipped
                Invoke lstrcat, Addr szPatternMessageBuffer, Addr szLog_CRLF
            .ENDIF
        .ENDIF
        Invoke LogMessage, Addr szPatternMessageBuffer, LOG_STANDARD, 0
        .IF gEEexLog >= LOGLEVEL_DETAIL
            .IF dwType == INFO_SEARCHED
                Invoke LogMessage, CTEXT("Patterns Found:"), LOG_STANDARD, 0
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

    .IF dwType == INFO_ADDRESSES
        .IF gEEexLog > LOGLEVEL_NONE
            Invoke LogMessage, CTEXT("Address List:"), LOG_INFO, 0
            Invoke EEexLogPatterns, TRUE
            
            ; Handle extras like GetProcAddress, LoadLibrary etc
            Invoke LogMessage, Addr szGetProcAddress, LOG_NONEWLINE, 1
            Invoke LogMessageAndHexValue, 0, F_GetProcAddress
            Invoke LogMessage, Addr szLoadLibrary, LOG_NONEWLINE, 1
            Invoke LogMessageAndHexValue, 0, F_LoadLibrary
            Invoke LogMessage, Addr szSDL_Free, LOG_NONEWLINE, 1
            Invoke LogMessageAndHexValue, 0, F_SDL_free

            Invoke LogMessage, 0, LOG_CRLF, 0
        .ENDIF
    .ENDIF

    xor eax, eax
    ret
EEexLogInformation ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLogImportPatterns - Log import pattern - <PatternName> and error
; Called from EEexLogInformation
; Returns: None
;------------------------------------------------------------------------------
EEexLogImportPatterns PROC USES EBX bImportError:DWORD
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternError:DWORD

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        mov eax, [ebx].PATTERN.PatBytes
        .IF bImportError == TRUE
            .IF eax == 0
                mov eax, TRUE
            .ELSE
                mov eax, FALSE
            .ENDIF
        .ELSE
            .IF eax != 0
                mov eax, TRUE
            .ELSE
                mov eax, FALSE
            .ENDIF
        .ENDIF
        .IF eax == TRUE
            mov eax, [ebx].PATTERN.PatName
            mov lpszPatternName, eax

            .IF bImportError == TRUE
                ; get error no stored in PatAdj
                mov eax, [ebx].PATTERN.PatAdj
                mov dwPatternError, eax
                Invoke LogMessage, lpszPatternName, LOG_NONEWLINE, 1
                mov eax, dwPatternError
                .IF eax == IMP_ERR_PATBYTES_EMPTY ; PatBytes entry is empty of text
                    Invoke LogMessage, CTEXT("PatBytes entry is empty of text"), LOG_STANDARD, 1
                .ELSEIF eax == IMP_ERR_PATBYTES_SIZE  ; PatBytes entry has text but length is not multiple of 2 (for paired hex chars)
                    Invoke LogMessage, CTEXT("PatBytes entry has text but length is not multiple of 2 (for paired hex chars)"), LOG_STANDARD, 1
                .ELSEIF eax == IMP_ERR_PATBYTES_ALLOC ; Could not allocate memory for PatBytes conversion to raw pattern bytes
                    Invoke LogMessage, CTEXT("Could not allocate memory for PatBytes conversion to raw pattern bytes"), LOG_STANDARD, 1
                .ELSEIF eax == IMP_ERR_VERBYTES_EMPTY ; VerBytes entry is empty of text (which is allowed - just providing this incase future use)
                    Invoke LogMessage, CTEXT("VerBytes entry is empty of text (which is allowed - just providing this incase future use)"), LOG_STANDARD, 1
                .ELSEIF eax == IMP_ERR_VERBYTES_SIZE  ; VerBytes entry has text but length is not multiple of 2 (for paired hex chars)
                    Invoke LogMessage, CTEXT("VerBytes entry has text but length is not multiple of 2 (for paired hex chars)"), LOG_STANDARD, 1
                .ELSEIF eax == IMP_ERR_VERBYTES_ALLOC ; Could not allocate memory for VerBytes conversion to raw pattern bytes
                    Invoke LogMessage, CTEXT("Could not allocate memory for VerBytes conversion to raw pattern bytes"), LOG_STANDARD, 1
                .ENDIF
            .ELSE
                Invoke LogMessage, lpszPatternName, LOG_STANDARD, 1
            .ENDIF
        .ENDIF
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW
     ret
EEexLogImportPatterns ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLogPatterns - Log pattern address, found or missing.
; Called from EEexLogInformation
; Returns: None
;------------------------------------------------------------------------------
EEexLogPatterns PROC USES EBX bFoundPattern:DWORD
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternAddress:DWORD
    LOCAL dwPatType:DWORD

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        mov eax, [ebx].PATTERN.PatType
        mov dwPatType, eax
        mov eax, [ebx].PATTERN.bFound
        .IF eax == bFoundPattern
            mov eax, [ebx].PATTERN.PatAddress
            mov dwPatternAddress, eax
            mov eax, [ebx].PATTERN.PatName
            mov lpszPatternName, eax
            .IF bFoundPattern == TRUE && dwPatType != 2
                Invoke LogMessage, lpszPatternName, LOG_NONEWLINE, 1
                Invoke LogMessageAndHexValue, 0, dwPatternAddress
            .ELSE
                .IF dwPatType == 2
                    Invoke LogMessage, lpszPatternName, LOG_NONEWLINE, 1
                    Invoke LogMessage, Addr szType2Pattern, LOG_STANDARD, 0
                .ELSE
                    Invoke LogMessage, lpszPatternName, LOG_STANDARD, 1
                .ENDIF
            .ENDIF
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
EEexWriteAddressesToIni PROC USES EBX
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternAddress:DWORD
    LOCAL pType2Array:DWORD
    LOCAL pCurrentType2Entry:DWORD
    LOCAL nTotal:DWORD
    LOCAL nCount:DWORD

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        .IF [ebx].PATTERN.bFound == TRUE
            .IF [ebx].PATTERN.PatType == 2
                ;--------------------------------------------------------------
                ; Handle type 2 patterns
                ;--------------------------------------------------------------            
                mov eax, [ebx].PATTERN.PatName
                mov lpszPatternName, eax
                ; clear any previous existing section
                Invoke IniClearSection, lpszPatternName
                
                mov ebx, ptrCurrentPattern
                mov eax, [ebx].PATTERN.PatAddress
                .IF eax != 0 ; array location?
                    mov pType2Array, eax
                    mov pCurrentType2Entry, eax
                    mov eax, [ebx].PATTERN.VerAdj
                    mov nTotal, eax
                    
                    ; Write Count= to section name
                    Invoke IniSetType2Count, lpszPatternName, nTotal
                    
                    ; Loop through pType2Array and get each address and write to ini file
                    ; 1=0x1234ABCD, 2=0xABCD1234 etc
                    mov ebx, pCurrentType2Entry
                    mov nCount, 0
                    mov eax, 0
                    .WHILE eax < nTotal
                        mov eax, [ebx]
                        mov dwPatternAddress, eax
                        Invoke EEexDwordToAscii, nCount, Addr szIniEnumString ; convert n integer to string 'n'
                        Invoke IniWriteValue, lpszPatternName, Addr szIniEnumString, dwPatternAddress ; n=0x1234ABCD
                        add pCurrentType2Entry, SIZEOF DWORD
                        mov ebx, pCurrentType2Entry
                        inc nCount
                        mov eax, nCount
                    .ENDW

                .ENDIF
            .ELSE
                ;--------------------------------------------------------------
                ; Handle all other patterns
                ;--------------------------------------------------------------  
                mov eax, [ebx].PATTERN.PatAddress
                mov dwPatternAddress, eax
                mov eax, [ebx].PATTERN.PatName
                mov lpszPatternName, eax
                Invoke IniWriteValue, Addr szIniEEex, lpszPatternName, dwPatternAddress
            .ENDIF
        .ENDIF
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW

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


EEEX_ALIGN
;-------------------------------------------------------------------------------------
; Convert a human readable hex based string to raw bytes
; lpRaw should be at least half the size of the lpszAsciiHexString
; Returns: On success eax contains size of raw bytes in lpRaw, or 0 if failure.
;-------------------------------------------------------------------------------------
EEexHexStringToRaw PROC USES EBX EDI ESI lpszAsciiHexString:DWORD, lpRaw:DWORD
    LOCAL pos:DWORD
    LOCAL dwLenHexString:DWORD
    LOCAL dwLenRaw:DWORD
    
    .IF lpRaw == NULL || lpszAsciiHexString == NULL
        mov eax, 0
        ret
    .ENDIF

    Invoke lstrlen, lpszAsciiHexString
    .IF eax == 0
        ret
    .ENDIF
    mov dwLenHexString, eax

    xor ebx, ebx
    mov dwLenRaw, 0
    mov pos, 0d
    mov edi, lpRaw
    mov esi, lpszAsciiHexString
    mov eax, 0
    .WHILE eax < dwLenHexString
        ; first ascii char
        movzx eax, byte ptr [esi]
        .IF al >= 48 && al <=57d
            sub al, 48d
        .ELSEIF al >= 65d && al <= 90d
            sub al, 55d
        .ELSEIF al >= 97d && al <= 122d
            sub al, 87d
        .ELSEIF al == ' '           ; skip space character
            inc esi
            inc pos
            mov eax, pos
            .CONTINUE
        .ELSEIF al == 0             ; null
            .BREAK                  ; exit as we hit null
        .ELSE
            mov dwLenRaw, 0         ; set to 0 for error
            .BREAK                  ; exit as not 0-9, a-f, A-F
        .ENDIF

        shl al, 4
        mov bl, al
        inc esi

        ; second ascii char
        movzx eax, byte ptr [esi]
        .IF al >= 48 && al <=57d
            sub al, 48d
        .ELSEIF al >= 65d && al <= 90d
            sub al, 55d
        .ELSEIF al >= 97d && al <= 122d
            sub al, 87d
        .ELSEIF al == ' '           ; skip space character
            mov byte ptr [edi], al  ; store the asciihex(AL) in the raw buffer 
            inc dwLenRaw
            inc edi
            inc esi
            inc pos
            mov eax, pos
            .CONTINUE               ; loop again to get next chars
        .ELSEIF al == 0             ; null
            mov byte ptr [edi], al  ; store the asciihex(AL) in the raw buffer
            inc dwLenRaw
            .BREAK                  ; exit as we hit null
        .ELSE
            mov dwLenRaw, 0         ; set to 0 for error
            .BREAK                  ; exit as not 0-9, a-f, A-F
        .ENDIF
        
        add al, bl
        mov byte ptr [edi], al      ; store the asciihex(AL) in the raw buffer   
        
        inc dwLenRaw
        inc edi
        inc esi
        inc pos
        mov eax, pos
    .ENDW

    mov eax, dwLenRaw
    ret
EEexHexStringToRaw ENDP


EEEX_ALIGN
;-------------------------------------------------------------------------------------
; Convert raw bytes to a human readable hex based string
; lpszAsciiHexString should be at least twice the size of dwRawSize +1 byte for null
; Returns: TRUE if success, FALSE otherwise
;-------------------------------------------------------------------------------------
EEexRawToHexString PROC USES EDI ESI lpRaw:DWORD, dwRawSize:DWORD, lpszAsciiHexString:DWORD, bUpperCase:DWORD
    LOCAL pos:DWORD
    
    .IF lpRaw == NULL || dwRawSize == 0 || lpszAsciiHexString == NULL
        mov eax, FALSE
        ret
    .ENDIF

    mov pos, 0d
    mov edi, lpszAsciiHexString
    mov esi, lpRaw
    mov eax, 0
    .WHILE eax < dwRawSize
        movzx eax, byte ptr [esi]
        mov ah,al
        ror al, 4                   ; shift in next hex digit
        and al, 0FH                 ; get digit
        .IF al < 10
            add al, "0"             ; convert digits 0-9 to ascii
        .ELSE
            .IF bUpperCase == TRUE
                add al, ("A"-10)    ; convert digits 0Ah to 0Fh to uppercase ascii A-F
            .ELSE
                add al, ("a"-10)    ; convert digits 0Ah to 0Fh to lowercase ascii a-f
            .ENDIF
        .ENDIF
        mov byte ptr [edi], al      ; store the asciihex(AL) in the string   
        inc edi
        mov al,ah
        
        and al, 0FH                 ; get digit
        .IF al < 10
            add al, "0"             ; convert digits 0-9 to ascii
        .ELSE
            .IF bUpperCase == TRUE
                add al, ("A"-10)    ; convert digits 0Ah to 0Fh to uppercase ascii A-F
            .ELSE
                add al, ("a"-10)    ; convert digits 0Ah to 0Fh to lowercase ascii a-f
            .ENDIF
        .ENDIF
        mov byte ptr [edi], al      ; store the asciihex(AL) in the string   

        inc edi
        inc esi
        inc pos
        mov eax, pos
    .ENDW
    mov byte ptr [edi], 0
    
    mov eax, TRUE
    ret
EEexRawToHexString ENDP


END DllEntry














