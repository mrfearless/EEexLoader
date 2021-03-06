;------------------------------------------------------------------------------
; EEex.exe - Loader for EEex to inject EEex.dll by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------
.686
.MMX
.XMM
.model flat,stdcall
option casemap:none
include \masm32\macros\macros.asm

;DEBUG32 EQU 1
;IFDEF DEBUG32
;    PRESERVEXMMREGS equ 1
;    includelib M:\Masm32\lib\Debug32.lib
;    DBG32LIB equ 1
;    DEBUGEXE textequ <'M:\Masm32\DbgWin.exe'>
;    include M:\Masm32\include\debug32.inc
;ENDIF



include EEex.inc
include EEexConsole.asm

CHECK_EXE_FILEVERSION       EQU 1 ; uncomment for exe file version checks
CHECK_EEexDLL_EXISTS        EQU 1 ; uncomment to check if EEex.dll exists
;CHECK_OVERRIDE_FILES        EQU 1 ; uncomment to check if override files exists


.CODE

;------------------------------------------------------------------------------
; Start
;------------------------------------------------------------------------------
start:

    Invoke GetModuleHandle, NULL
    mov hInstance, eax
    Invoke GetCommandLine
    mov CommandLine, eax
    
    Invoke ConsoleInit    
    Invoke WinMain, hInstance, NULL, CommandLine, SW_SHOWDEFAULT
    Invoke ConsoleExit
    
    Invoke ExitProcess, eax
    ret

EEEX_ALIGN
;------------------------------------------------------------------------------
; WinMain
;------------------------------------------------------------------------------
WinMain PROC USES EBX hInst:HINSTANCE, hPrevInst:HINSTANCE, CmdLine:LPSTR, CmdShow:DWORD
    LOCAL dwExitCode:DWORD
    LOCAL dwEEGameRunning:DWORD
    LOCAL bEEGameFound:DWORD
    LOCAL lpszEEGame:DWORD
    LOCAL lenEEGame:DWORD
    LOCAL lenOverride:DWORD
    LOCAL bMissingOverrides:DWORD
    LOCAL childconsolesize:COORD
    
    mov bMissingOverrides, FALSE
    mov bEEGameFound, FALSE
    mov lpszEEGame, 0
    
    Invoke RtlZeroMemory, Addr startinfo, SIZEOF STARTUPINFO
    mov startinfo.cb, SIZEOF STARTUPINFO
    
    ;--------------------------------------------------------------------------
    ; Check if we can attach a console or not, which helps determine if
    ; we started via explorer or via a command line (cmd)
    ;--------------------------------------------------------------------------
;    Invoke ConsoleAttach
;    Invoke ConsoleStarted
;    mov gConsoleStartedMode, eax
    
    .IF gConsoleStartedMode == TRUE
        Invoke GetStdHandle, STD_OUTPUT_HANDLE
        mov hConOutput, eax
        Invoke ConsoleClearScreen
        Invoke ConsoleText, Addr szAppName
        Invoke ConsoleText, Addr szAppVersion
        Invoke ConsoleText, Addr szCRLF
        Invoke ConsoleText, Addr szCRLF
        Invoke ConsoleText, Addr szInfoEntry
        Invoke ConsoleText, Addr szEEexLoaderByfearless
        Invoke ConsoleText, Addr szCRLF
        Invoke ConsoleText, Addr szInfoEntry
        Invoke ConsoleText, Addr szEEexByBubb
        Invoke ConsoleText, Addr szCRLF
        Invoke ConsoleText, Addr szCRLF
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Check EE game is not already running
    ;--------------------------------------------------------------------------
    mov dwEEGameRunning, FALSE
    Invoke EnumWindows, Addr EnumWindowsProc, Addr dwEEGameRunning
    .IF dwEEGameRunning == TRUE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEGameRunning
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEGameRunning, 0
        .ENDIF
        ret
    .ENDIF
    IFDEF DEBUG32
    PrintText 'Check EE game is not already running'
    ENDIF

    ;--------------------------------------------------------------------------
    ; Search for known EE game executables and check file version
    ;--------------------------------------------------------------------------
    ; BGEE
    Invoke FindFirstFile, Addr szBeamdog_BGEE, Addr wfd
    .IF eax != INVALID_HANDLE_VALUE
        lea eax, wfd.cFileName
        Invoke lstrcpy, Addr szEEGameEXE, eax
        Invoke FindClose, eax
        IFDEF CHECK_EXE_FILEVERSION
        Invoke CheckFileVersion, Addr szBeamdog_BGEE, Addr szBeamdog_ExeVersion ; "0, 1, 0, 0"
        .IF eax == FALSE
            .IF gConsoleStartedMode == TRUE
                Invoke ConsoleText, Addr szErrorEntry
                Invoke ConsoleText, Addr szErrorBeamdog_BGEE
                Invoke ConsoleText, Addr szCRLF
            .ELSE
                Invoke DisplayErrorMessage, Addr szErrorBeamdog_BGEE, 0
            .ENDIF
            ret
        .ENDIF
        ENDIF
        mov bEEGameFound, TRUE
        lea eax, szBeamdog_BGEE
        mov lpszEEGame, eax
    .ELSE
        IFDEF DEBUG32
        PrintText 'No BGEE'
        ENDIF
    .ENDIF

    ; BG2EE
    .IF bEEGameFound == FALSE
        Invoke FindFirstFile, Addr szBeamdog_BG2EE, Addr wfd
        .IF eax != INVALID_HANDLE_VALUE
            lea eax, wfd.cFileName
            Invoke lstrcpy, Addr szEEGameEXE, eax
            Invoke FindClose, eax
            IFDEF CHECK_EXE_FILEVERSION
            Invoke CheckFileVersion, Addr szBeamdog_BG2EE, Addr szBeamdog_ExeVersion ; "0, 1, 0, 0"
            .IF eax == FALSE
                .IF gConsoleStartedMode == TRUE
                    Invoke ConsoleText, Addr szErrorEntry
                    Invoke ConsoleText, Addr szErrorBeamdog_BG2EE
                    Invoke ConsoleText, Addr szCRLF
                .ELSE
                    Invoke DisplayErrorMessage, Addr szErrorBeamdog_BG2EE, 0
                .ENDIF
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_BG2EE
            mov lpszEEGame, eax
        .ELSE
            IFDEF DEBUG32
            PrintText 'No BG2EE'
            ENDIF
        .ENDIF
    .ENDIF

    ; BGSOD
    .IF bEEGameFound == FALSE
        Invoke FindFirstFile, Addr szBeamdog_BGSOD, Addr wfd
        .IF eax != INVALID_HANDLE_VALUE
            lea eax, wfd.cFileName
            Invoke lstrcpy, Addr szEEGameEXE, eax
            Invoke FindClose, eax
            IFDEF CHECK_EXE_FILEVERSION
            Invoke CheckFileVersion, Addr szBeamdog_BGSOD, Addr szBeamdog_ExeVersion ; "0, 1, 0, 0"
            .IF eax == FALSE
                .IF gConsoleStartedMode == TRUE
                    Invoke ConsoleText, Addr szErrorEntry
                    Invoke ConsoleText, Addr szErrorBeamdog_BGSOD
                    Invoke ConsoleText, Addr szCRLF
                .ELSE
                    Invoke DisplayErrorMessage, Addr szErrorBeamdog_BGSOD, 0
                .ENDIF
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_BGSOD
            mov lpszEEGame, eax
        .ELSE
            IFDEF DEBUG32
            PrintText 'No BGSOD'
            ENDIF
        .ENDIF
    .ENDIF

    ; IWDEE
    .IF bEEGameFound == FALSE
        Invoke FindFirstFile, Addr szBeamdog_IWDEE, Addr wfd
        .IF eax != INVALID_HANDLE_VALUE
            lea eax, wfd.cFileName
            Invoke lstrcpy, Addr szEEGameEXE, eax
            Invoke FindClose, eax
            IFDEF CHECK_EXE_FILEVERSION
            Invoke CheckFileVersion, Addr szBeamdog_IWDEE, Addr szBeamdog_ExeVersion ; "0, 1, 0, 0"
            .IF eax == FALSE
                .IF gConsoleStartedMode == TRUE
                    Invoke ConsoleText, Addr szErrorEntry
                    Invoke ConsoleText, Addr szErrorBeamdog_IWDEE
                    Invoke ConsoleText, Addr szCRLF
                .ELSE
                    Invoke DisplayErrorMessage, Addr szErrorBeamdog_IWDEE, 0
                .ENDIF
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_IWDEE
            mov lpszEEGame, eax
        .ELSE
            IFDEF DEBUG32
            PrintText 'No IWDEE'
            ENDIF
        .ENDIF
    .ENDIF

    ; PSTEE
    .IF bEEGameFound == FALSE
        Invoke FindFirstFile, Addr szBeamdog_PSTEE, Addr wfd
        .IF eax != INVALID_HANDLE_VALUE
            lea eax, wfd.cFileName
            Invoke lstrcpy, Addr szEEGameEXE, eax
            Invoke FindClose, eax
            IFDEF CHECK_EXE_FILEVERSION
            Invoke CheckFileVersion, Addr szBeamdog_PSTEE, Addr szBeamdog_ExeVersion ; "0, 1, 0, 0"
            .IF eax == FALSE
                .IF gConsoleStartedMode == TRUE
                    Invoke ConsoleText, Addr szErrorEntry
                    Invoke ConsoleText, Addr szErrorBeamdog_PSTEE
                    Invoke ConsoleText, Addr szCRLF
                .ELSE
                    Invoke DisplayErrorMessage, Addr szErrorBeamdog_PSTEE, 0
                .ENDIF
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_PSTEE
            mov lpszEEGame, eax
        .ELSE
            IFDEF DEBUG32
            PrintText 'No PSTEE'
            ENDIF
        .ENDIF
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Have we found any EE game exe? Display error message and exit if not
    ;--------------------------------------------------------------------------
    .IF bEEGameFound == FALSE
        IFDEF DEBUG32
        PrintText 'No EE game'
        ENDIF
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEGameEXE
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEGameEXE, 0
        .ENDIF
        ret 
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Check EEex.dll is present? Display error message and exit if not
    ;--------------------------------------------------------------------------
    IFDEF CHECK_EEexDLL_EXISTS
    Invoke FindFirstFile, Addr szEEexDLL, Addr wfd
    .IF eax != INVALID_HANDLE_VALUE
        Invoke FindClose, eax
        IFDEF DEBUG32
        PrintText 'EEex.dll found'
        ENDIF
    .ELSE
        IFDEF DEBUG32
        PrintText 'No EEex.dll'
        ENDIF
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEexDLLFind
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEexDLLFind, 0
        .ENDIF
        ret
    .ENDIF
    ENDIF

    ;--------------------------------------------------------------------------
    ; check M__EEex.lua in override folder
    ;--------------------------------------------------------------------------    
    Invoke GetCurrentDirectory, SIZEOF szCurrentFolder, Addr szCurrentFolder
    Invoke lstrcpy, Addr szEEGameOverrideFolder, Addr szCurrentFolder
    Invoke lstrcat, Addr szEEGameOverrideFolder, Addr szOverride
    
    Invoke lstrcpy, Addr szFileM__EEexlua, Addr szEEGameOverrideFolder
    Invoke lstrcat, Addr szFileM__EEexlua, Addr szM__EEexlua    
    IFDEF DEBUG32
    PrintString szEEGameOverrideFolder
    PrintString szFileM__EEexlua
    ENDIF
    Invoke GetFileAttributes, Addr szFileM__EEexlua
    .IF eax == INVALID_FILE_ATTRIBUTES
        Invoke GetLastError
        .IF eax == ERROR_FILE_NOT_FOUND
            IFDEF DEBUG32
            PrintText 'M__EEex.lua is missing in the override folder - cannot continue.'
            ENDIF
            .IF gConsoleStartedMode == TRUE
                Invoke ConsoleText, Addr szErrorEntry
                Invoke ConsoleText, Addr szErrorM__EEexMissing
                Invoke ConsoleText, Addr szCRLF
            .ELSE
                Invoke DisplayErrorMessage, Addr szErrorM__EEexMissing, 0
            .ENDIF
            ret
        .ENDIF
    .ENDIF    

    ;--------------------------------------------------------------------------
    ; check EEex.db in current folder
    ;--------------------------------------------------------------------------  
    Invoke lstrcpy, Addr szFileEEexDB, Addr szCurrentFolder
    Invoke lstrcat, Addr szFileEEexDB, Addr szEEexDB
    IFDEF DEBUG32
    PrintString szFileEEexDB
    ENDIF
    Invoke GetFileAttributes, Addr szFileEEexDB
    .IF eax == INVALID_FILE_ATTRIBUTES
        Invoke GetLastError
        .IF eax == ERROR_FILE_NOT_FOUND
            IFDEF DEBUG32
            PrintText 'EEex.db is missing - cannot continue.'
            ENDIF
            .IF gConsoleStartedMode == TRUE
                Invoke ConsoleText, Addr szErrorEntry
                Invoke ConsoleText, Addr szErrorEEexDBMissing
                Invoke ConsoleText, Addr szCRLF
            .ELSE
                Invoke DisplayErrorMessage, Addr szErrorEEexDBMissing, 0
            .ENDIF
            ret
        .ENDIF
    .ENDIF    

    ;--------------------------------------------------------------------------
    ; check UI.menu, TRIGGER.ids, OBJECT.ids and ACTION.ids in override folder
    ;--------------------------------------------------------------------------
    IFDEF CHECK_OVERRIDE_FILES
    Invoke lstrcpy, Addr szFileUImenu, Addr szEEGameOverrideFolder
    Invoke lstrcat, Addr szFileUImenu, Addr szUImenu
    Invoke lstrcpy, Addr szFileTRIGGERids, Addr szEEGameOverrideFolder
    Invoke lstrcat, Addr szFileTRIGGERids, Addr szTRIGGERids
    Invoke lstrcpy, Addr szFileOBJECTids, Addr szEEGameOverrideFolder
    Invoke lstrcat, Addr szFileOBJECTids, Addr szOBJECTids
    Invoke lstrcpy, Addr szFileACTIONids, Addr szEEGameOverrideFolder
    Invoke lstrcat, Addr szFileACTIONids, Addr szACTIONids

    IFDEF DEBUG32
    PrintString szEEGameOverrideFolder
    PrintString szFileUImenu
    PrintString szFileTRIGGERids
    PrintString szFileOBJECTids
    PrintString szFileACTIONids
    ENDIF    
    
    Invoke GetFileAttributes, Addr szFileUImenu
    .IF eax == INVALID_FILE_ATTRIBUTES
        Invoke GetLastError
        .IF eax == ERROR_FILE_NOT_FOUND
            mov bMissingOverrides, TRUE
        .ENDIF
    .ENDIF
    Invoke GetFileAttributes, Addr szFileTRIGGERids
    .IF eax == INVALID_FILE_ATTRIBUTES
        Invoke GetLastError
        .IF eax == ERROR_FILE_NOT_FOUND
            mov bMissingOverrides, TRUE
        .ENDIF
    .ENDIF
    Invoke GetFileAttributes, Addr szFileOBJECTids
    .IF eax == INVALID_FILE_ATTRIBUTES
        Invoke GetLastError
        .IF eax == ERROR_FILE_NOT_FOUND
            mov bMissingOverrides, TRUE
        .ENDIF
    .ENDIF
    Invoke GetFileAttributes, Addr szFileACTIONids
    .IF eax == INVALID_FILE_ATTRIBUTES
        Invoke GetLastError
        .IF eax == ERROR_FILE_NOT_FOUND
            mov bMissingOverrides, TRUE
        .ENDIF
    .ENDIF
    .IF bMissingOverrides == TRUE
        IFDEF DEBUG32
        PrintText 'One of more override files appear to be missing: UI.menu, TRIGGER.ids, OBJECT.ids and ACTION.ids'
        ENDIF
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEOverrideFiles
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEOverrideFiles, 0
        .ENDIF
        ret
    .ELSE
        IFDEF DEBUG32
        PrintText 'Override files located: UI.menu, TRIGGER.ids, OBJECT.ids and ACTION.ids'
        ENDIF
    .ENDIF
    ENDIF

    ;--------------------------------------------------------------------------
    ; Prepare Startup info for pipe redirection if EEex.exe started via console
    ;--------------------------------------------------------------------------
    .IF gConsoleStartedMode == TRUE ; started via Console
        IFDEF DEBUG32
        PrintText 'Console mode - redirection of child process stdout'
        ENDIF

        mov SecuAttr.nLength, SIZEOF SECURITY_ATTRIBUTES
        mov SecuAttr.lpSecurityDescriptor, NULL
        mov SecuAttr.bInheritHandle, TRUE
        
        Invoke CreatePipe, Addr hChildStd_OUT_Rd, Addr hChildStd_OUT_Wr, Addr SecuAttr, 0 
        Invoke SetHandleInformation, hChildStd_OUT_Rd, HANDLE_FLAG_INHERIT, 0
        
        Invoke CreatePipe, Addr hChildStd_IN_Rd, Addr hChildStd_IN_Wr, Addr SecuAttr, 0
        Invoke SetHandleInformation, hChildStd_IN_Wr, HANDLE_FLAG_INHERIT, 0
        
        Invoke GetStdHandle, STD_OUTPUT_HANDLE
        mov hParentStdOut, eax
        Invoke GetStdHandle, STD_ERROR_HANDLE
        mov hParentStdErr, eax
        
        mov eax, hChildStd_OUT_Wr
        mov startinfo.hStdError, eax
        mov startinfo.hStdOutput, eax
        mov eax, hChildStd_IN_Rd
        mov startinfo.hStdInput, eax
        mov startinfo.dwFlags, STARTF_USESTDHANDLES
    .ELSE
        IFDEF DEBUG32
        PrintText 'GUI mode - no console redirection'
        ENDIF    
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Check EE game's executable is x86 and not x64
    ;--------------------------------------------------------------------------
    Invoke IsEEGame64bit, lpszEEGame
    .IF eax == -2 ; invalid PE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEGame64invalid
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEGame64invalid, 0
        .ENDIF
        ret
    
    .ELSEIF eax == -1 ; error opening PE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEGame64error
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEGame64error, 0
        .ENDIF
        ret
        
    .ELSEIF eax == 0
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szStatusEntry
            Invoke ConsoleText, Addr szErrorEEGame64no
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        ; continue as normal as 32bit EE game is detected

    .ELSEIF eax == 1
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEGame64yes
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke DisplayErrorMessage, Addr szErrorEEGame64yes, 0
        .ENDIF
        ret
    .ENDIF

    ;--------------------------------------------------------------------------
    ; Launch EE game's executable, ready for injection of our EEex.dll
    ;--------------------------------------------------------------------------
    IFDEF DEBUG32
    PrintText 'Launching EE game executable'
    ENDIF
    .IF gConsoleStartedMode == TRUE
        Invoke ConsoleText, Addr szStatusEntry
        Invoke ConsoleText, Addr szStatusLaunchingEEGame
        Invoke ConsoleText, lpszEEGame
        Invoke ConsoleText, Addr szCRLF
    .ENDIF
    Invoke CreateProcess, lpszEEGame, NULL, NULL, NULL, TRUE, CREATE_SUSPENDED, NULL, NULL, Addr startinfo, Addr pi
    .IF eax != 0 ; CreateProcess success
        ;----------------------------------------------------------------------
        ; Inject EEex.dll into EE game and resume EE game execution
        ;
        ; EEex.dll will be loaded by EE game and call its DllEntry procedure
        ; which will call EEex.dll:EEexInitDll to begin searching for lua
        ; functions and patching the EE game to redirect a call to EEexLuaInit
        ;  
        ; call XXXEEgame:luaL_loadstring replaced with call EEex.dll:EEexLuaInit
        ;----------------------------------------------------------------------
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szStatusEntry
            Invoke ConsoleText, Addr szStatusInjectingDLL
            Invoke ConsoleText, Addr szCRLF
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        
        IFDEF DEBUG32
        PrintText 'InjectDLL: Injecting EEex.dll into EE game executable'
        ENDIF
        Invoke InjectDLL, pi.hProcess, Addr szEEexDLL
        ;mov dwExitCode, eax
        .IF eax == TRUE
            .IF gConsoleStartedMode == TRUE
                Invoke ConsoleText, Addr szStatusEntry
                Invoke ConsoleText, Addr szStatusResumeThread
                Invoke ConsoleText, Addr szCRLF
            .ENDIF
            ;------------------------------------------------------------------
            ; EE Game thread starts up
            ;------------------------------------------------------------------
            Invoke ResumeThread, pi.hThread

            .IF gConsoleStartedMode == TRUE
                ;--------------------------------------------------------------
                ; Redirect EE game output to our allocated console
                ;--------------------------------------------------------------
                Invoke ConsoleText, Addr szStatusEntry
                Invoke ConsoleText, Addr szStatusRedirectCon
                Invoke ConsoleText, Addr szCRLF
                Invoke ConsoleText, Addr szCRLF
                Invoke ReadFromPipe
                Invoke ConsoleText, Addr szCRLF
                ;Invoke ConsoleSendEnterKey
                ;Invoke FreeConsole
                Invoke CloseHandle, hChildStd_OUT_Rd
                Invoke CloseHandle, hChildStd_OUT_Wr
                Invoke CloseHandle, hChildStd_IN_Rd
                Invoke CloseHandle, hChildStd_IN_Wr
            .ENDIF
            
            ;------------------------------------------------------------------
            ; Clean up handles and exit EEex.exe Loader
            ;------------------------------------------------------------------
            Invoke CloseHandle, pi.hThread
            Invoke CloseHandle, pi.hProcess
            
        .ELSE
            .IF gConsoleStartedMode == TRUE
                Invoke ConsoleText, Addr szErrorEntry
                Invoke ConsoleText, Addr szErrorInjectDLL
                Invoke ConsoleText, Addr szCRLF
            .ELSE    
                Invoke GetLastError
                Invoke DisplayErrorMessage, Addr szErrorInjectDLL, eax
            .ENDIF
        .ENDIF
        
    .ELSE ; CreateProcess failed
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorEEGameExecute
            Invoke ConsoleText, Addr szCRLF
        .ELSE    
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorEEGameExecute, eax
        .ENDIF
        ret
    .ENDIF    

    mov eax, 0
    ret
WinMain ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; Does the actual injection into the Beamdog EE executable to load the EEex.DLL 
;------------------------------------------------------------------------------
InjectDLL PROC hProcess:HANDLE, szDLLPath:DWORD
    LOCAL szLibPathSize:DWORD
    LOCAL lpLibAddress:DWORD
    LOCAL lpStartRoutine:DWORD
    LOCAL hMod:DWORD
    LOCAL hKernel32:DWORD
    LOCAL BytesWritten:DWORD
    LOCAL hRemoteThread:DWORD
    LOCAL dwRemoteThreadID:DWORD  
    LOCAL dwExitCode:DWORD
    LOCAL ReturnVal:DWORD

    Invoke lstrlen, szDLLPath
    inc eax
    mov szLibPathSize, eax

    Invoke VirtualAllocEx, hProcess, NULL, szLibPathSize, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE
    mov lpLibAddress, eax
    .IF eax == NULL
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorVirtualAllocEx
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorVirtualAllocEx, eax
        .ENDIF
        mov eax, FALSE
        ret
    .ENDIF
    
    Invoke WriteProcessMemory, hProcess, lpLibAddress, szDLLPath, szLibPathSize, Addr BytesWritten
    .IF eax == 0
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorWriteProcessMem
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorWriteProcessMem, eax
        .ENDIF
        mov eax, FALSE
        ret
    .ENDIF

    Invoke GetModuleHandle, 0
    mov hMod, eax
    Invoke GetModuleHandle, Addr szKernel32Dll
    mov hKernel32, eax
    .IF eax == NULL
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorGetModuleHandle
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorGetModuleHandle, eax
        .ENDIF
        mov eax, FALSE
        ret
    .ENDIF

    Invoke GetProcAddress, hKernel32, Addr szLoadLibraryProc
    mov lpStartRoutine, eax        
    .IF eax == NULL
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorGetProcAddress
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorGetProcAddress, eax
        .ENDIF
        mov eax, FALSE
        ret
    .ENDIF

    IFDEF DEBUG32
    PrintText 'InjectDLL::CreateRemoteThread'
    ENDIF

    Invoke CreateRemoteThread, hProcess, NULL, 0, lpStartRoutine, lpLibAddress, 0, Addr dwRemoteThreadID
    mov hRemoteThread, eax
    .IF eax == NULL
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorRemoteThread
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorRemoteThread, eax
        .ENDIF
        mov eax, FALSE
        ret
    .ENDIF
    
    IFDEF DEBUG32
    PrintText 'InjectDLL::WaitForSingleObject'
    ENDIF
    
    .IF gConsoleStartedMode == TRUE
        Invoke ConsoleText, Addr szCRLF
    .ENDIF
    
    Invoke WaitForSingleObject, hRemoteThread, INFINITE

    .IF eax == WAIT_ABANDONED
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorWaitAbandoned
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        
    .ELSEIF eax == WAIT_OBJECT_0
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szStatusEntry
            Invoke ConsoleText, Addr szErrorWaitObject0
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        
    .ELSEIF eax == WAIT_TIMEOUT
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorWaitTimeout
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        
    .ELSEIF eax == WAIT_FAILED
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorWaitFailed
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorWaitFailed, eax
        .ENDIF
        mov ReturnVal, FALSE
        jmp InjectDLLExit   
    .ELSE    
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorWaitSingleInv, 0
        mov ReturnVal, FALSE
        jmp InjectDLLExit             
    .ENDIF

    Invoke GetExitCodeThread, hRemoteThread, Addr dwExitCode
    .IF eax == 0
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorGECTFailure, 0
        mov ReturnVal, FALSE
        jmp InjectDLLExit
    .ELSE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szStatusEntry
            Invoke ConsoleText, Addr szStatusGECTSuccess
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        mov ReturnVal, TRUE
    .ENDIF

    mov eax, dwExitCode
    .IF eax == STILL_ACTIVE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorThreadActive
            Invoke ConsoleText, Addr szCRLF
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorThreadActive, 0
        .ENDIF
        mov ReturnVal, FALSE
    
    .ELSEIF eax == TRUE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szStatusThreadExitTrue
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        mov ReturnVal, TRUE
        
    .ELSEIF eax == FALSE
        .IF gConsoleStartedMode == TRUE
            Invoke ConsoleText, Addr szErrorEntry
            Invoke ConsoleText, Addr szErrorThreadExitFail
            Invoke ConsoleText, Addr szCRLF
        .ENDIF
        mov ReturnVal, FALSE
        
    .ENDIF
    
InjectDLLExit:
    
    Invoke CloseHandle, hRemoteThread
    Invoke VirtualFreeEx, hProcess, lpLibAddress, 0, MEM_RELEASE

    mov eax, ReturnVal    
    ret
InjectDLL endp


EEEX_ALIGN
;------------------------------------------------------------------------------
; Checks if beamdog executable is 64bit - which means a newer game build and
; thus would require a 64bit version of EEex.exe loader and the EEex.dll
; Returns: eax contains 1 = 64bit, 0 = 32bit (x86), -1 = error, -2 = invalid
;------------------------------------------------------------------------------
IsEEGame64bit PROC USES EBX lpszEEGameExe:DWORD
    LOCAL hFile:DWORD
    LOCAL hMemMap:DWORD
    LOCAL pMemMap:DWORD
    LOCAL RetVal:DWORD
    
    mov RetVal, 0
    
    Invoke CreateFile, lpszEEGameExe, GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
    .IF eax == INVALID_HANDLE_VALUE
        IFDEF DEBUG32
        PrintText 'IsEEGame64bit::CreateFile error'
        ENDIF
        mov eax, -1
        ret
    .ENDIF 
    mov hFile, eax
    
    Invoke CreateFileMapping, hFile, NULL, PAGE_READONLY, 0, 0, NULL
    .IF eax == NULL
        IFDEF DEBUG32
        PrintText 'IsEEGame64bit::CreateFileMapping error'
        ENDIF    
        Invoke CloseHandle, hFile
        mov eax, -1
        ret
    .ENDIF
    mov hMemMap, eax
    
    Invoke MapViewOfFileEx, hMemMap, FILE_MAP_READ, 0, 0, 0, NULL
    .IF eax == NULL
        IFDEF DEBUG32
        PrintText 'IsEEGame64bit::MapViewOfFile error'
        ENDIF    
        Invoke CloseHandle, hMemMap
        Invoke CloseHandle, hFile
        mov eax, -1
        ret
    .ENDIF
    mov pMemMap, eax ; store map view pointer
    
    
    ; Check for valid PE and if 32bit or 64bit
    mov ebx, pMemMap
    movzx eax, word ptr [ebx].IMAGE_DOS_HEADER.e_magic
    .IF ax == MZ_SIGNATURE
        add ebx, [ebx].IMAGE_DOS_HEADER.e_lfanew
        ; ebx is pointer to IMAGE_NT_HEADERS now
        mov eax, [ebx].IMAGE_NT_HEADERS.Signature
        .IF ax == PE_SIGNATURE
            movzx eax, word ptr [ebx].IMAGE_NT_HEADERS.OptionalHeader.Magic
            .IF ax == IMAGE_NT_OPTIONAL_HDR32_MAGIC
                IFDEF DEBUG32
                PrintText 'IsEEGame64bit::32bit'
                ENDIF  
                mov RetVal, 0 ; 32bit
            .ELSEIF ax == IMAGE_NT_OPTIONAL_HDR64_MAGIC
                IFDEF DEBUG32
                PrintText 'IsEEGame64bit::64bit'
                ENDIF
                mov RetVal, 1 ; 64bit
            .ENDIF
        .ELSE
            IFDEF DEBUG32
            PrintText 'IsEEGame64bit::Invalid PE'
            ENDIF
            mov RetVal, -2 ; error invalid pe
        .ENDIF
    .ELSE
        IFDEF DEBUG32
        PrintText 'IsEEGame64bit::Invalid exe'
        ENDIF
        mov RetVal, -2 ; error invalid exe
    .ENDIF
    
    ; Tidy up and close file
    Invoke UnmapViewOfFile, pMemMap
    Invoke CloseHandle, hMemMap
    Invoke CloseHandle, hFile
    
    mov eax, RetVal
    ret
IsEEGame64bit ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EnumWindowsProc - enumerates all top-level windows
; Search for SDLapp class and if found check window title for Beamdog EE game
;------------------------------------------------------------------------------
EnumWindowsProc PROC USES EBX hWindow:DWORD, lParam:DWORD
    Invoke GetClassName, hWindow, Addr szClassName, SIZEOF szClassName
    .IF eax != 0
        lea ebx, szClassName
        mov eax, [ebx]
        .IF eax == 'aLDS' ; 'SDLa'pp reversed
            Invoke GetWindowText, hWindow, Addr szWindowTitle, SIZEOF szWindowTitle
            .IF eax != 0
                lea ebx, szWindowTitle
                mov eax, [ebx]
                .IF eax == 'dalB' || eax == 'geiS' || eax == 'wecI' || eax == 'nalP' ; Bald, Sieg, Icew, Plan
                    mov ebx, lParam
                    mov eax, TRUE
                    mov [ebx], eax
                    mov eax, FALSE
                    ret
                .ENDIF
            .ENDIF
        .ENDIF
    .ENDIF
    mov eax, TRUE
    ret
EnumWindowsProc ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; Checks file version of the filename for the correct version of beamdog game
; Returns: eax contains TRUE if version matches, otherwise returns FALSE
;------------------------------------------------------------------------------
IFDEF CHECK_EXE_FILEVERSION
CheckFileVersion PROC USES EBX szVersionFile:DWORD, szVersion:DWORD
    LOCAL verHandle:DWORD
    LOCAL verData:DWORD
    LOCAL verSize:DWORD
    LOCAL verInfo:DWORD
    LOCAL hHeap:DWORD
    LOCAL pBuffer:DWORD
    LOCAL lenBuffer:DWORD
    LOCAL ver1:DWORD
    LOCAL ver2:DWORD
    LOCAL ver3:DWORD
    LOCAL ver4:DWORD

    Invoke GetFileVersionInfoSize, szVersionFile, Addr verHandle
    .IF eax != 0
        mov verSize, eax
        Invoke GetProcessHeap 
        .IF eax != 0 
            mov hHeap, eax 
            Invoke HeapAlloc, eax, 0, verSize
            .IF eax != 0 
                mov verData, eax    
                Invoke GetFileVersionInfo, szVersionFile, 0, verSize, verData
                .IF eax != 0
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
                            mov ver1, eax
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionMS
                            shr eax, 0
                            and eax, 0FFFFh
                            mov ver2, eax
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionLS
                            shr eax, 16d
                            and eax, 0FFFFh
                            mov ver3, eax
                            mov eax, [ebx].VS_FIXEDFILEINFO.dwFileVersionLS
                            shr eax, 0
                            and eax, 0FFFFh
                            mov ver4, eax
                            
                            Invoke HeapFree, hHeap, 0, verData
                            
                            Invoke wsprintf, Addr szFileVersionBuffer, Addr szFileVersion, ver1, ver2, ver3, ver4
                            Invoke lstrcmp, szVersion, Addr szFileVersionBuffer
                            .IF eax == 0 ; match
                                mov eax, TRUE
                            .ELSE
                                mov eax, FALSE
                            .ENDIF
                        .ELSE
                            Invoke HeapFree, hHeap, 0, verData
                            Invoke GetLastError
                            Invoke DisplayErrorMessage, Addr szErrorVerQueryValue, eax
                            mov eax, FALSE
                            ret                         
                        .ENDIF
                    .ELSE
                        Invoke HeapFree, hHeap, 0, verData
                        mov eax, FALSE
                        ret   
                    .ENDIF
                .ELSE
                    Invoke HeapFree, hHeap, 0, verData
                    Invoke GetLastError
                    Invoke DisplayErrorMessage, Addr szErrorGetVersionInfo, eax
                    mov eax, FALSE
                    ret 
                .ENDIF          
            .ELSE
                Invoke GetLastError
                Invoke DisplayErrorMessage, Addr szErrorHeapAlloc, eax
                mov eax, FALSE
                ret                 
            .ENDIF  
        .ELSE
            Invoke GetLastError
            Invoke DisplayErrorMessage, Addr szErrorHeap, eax
            mov eax, FALSE
            ret             
        .ENDIF                                     
    .ELSE
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorGetVersionSize, eax
        mov eax, FALSE
        ret         
    .ENDIF      
    ret
CheckFileVersion endp
ENDIF


EEEX_ALIGN
;------------------------------------------------------------------------------
; Displays Error Messages
;------------------------------------------------------------------------------
DisplayErrorMessage PROC USES EDX lpszMessage:DWORD, dwError:DWORD
    LOCAL lpError:DWORD
    LOCAL dwLanguageId:DWORD

    .IF dwError != 0
        xor edx, edx
        mov dl, SUBLANG_DEFAULT
        shl edx, 10
        or edx, LANG_NEUTRAL
        mov dwLanguageId, edx ; dwLanguageId
        Invoke FormatMessage, FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS, NULL, dwError, edx, Addr lpError, 0, NULL
        Invoke wsprintf, Addr szFormatErrorMessage, Addr szFmtError, lpError, dwError
        Invoke lstrcpy, Addr szErrorMessage, lpszMessage
        Invoke lstrcat, Addr szErrorMessage, Addr szCRLF
        Invoke lstrcat, Addr szErrorMessage, Addr szFormatErrorMessage
        Invoke MessageBox, NULL, Addr szErrorMessage, Addr AppName, MB_OK
        Invoke LocalFree, lpError
    .ELSE
        Invoke MessageBox, NULL, lpszMessage, Addr AppName, MB_OK
    .ENDIF
    xor eax, eax
    ret
DisplayErrorMessage ENDP


end start


