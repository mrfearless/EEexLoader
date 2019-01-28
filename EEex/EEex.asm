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

CHECK_EXE_FILEVERSION       EQU 1 ; uncomment for exe file version checks
CHECK_EEexDLL_EXISTS        EQU 1 ; uncomment to check if EEex.dll exists
CHECK_OVERRIDE_FILES        EQU 1 ; uncomment to check if override files exists

.code

start:

    Invoke GetModuleHandle, NULL
    mov hInstance, eax
    Invoke GetCommandLine
    mov CommandLine, eax

    Invoke WinMain, hInstance, NULL, CommandLine, SW_SHOWDEFAULT
    Invoke ExitProcess, eax

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
    
    mov bMissingOverrides, FALSE
    mov bEEGameFound, FALSE
    mov lpszEEGame, 0
    
    mov eax, SIZEOF STARTUPINFO
    mov startinfo.cb, eax
    
    
    ;--------------------------------------------------------------------------
    ; Check EE game is not already running
    ;--------------------------------------------------------------------------
    mov dwEEGameRunning, FALSE
    Invoke EnumWindows, Addr EnumWindowsProc, Addr dwEEGameRunning
    .IF dwEEGameRunning == TRUE
        Invoke DisplayErrorMessage, Addr szErrorEEGameRunning, 0
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
            Invoke DisplayErrorMessage, Addr szErrorBeamdog_BGEE, 0
            ret
        .ENDIF
        ENDIF
        mov bEEGameFound, TRUE
        lea eax, szBeamdog_BGEE
        mov lpszEEGame, eax
    .ENDIF
    IFDEF DEBUG32
    PrintText 'No BGEE'
    ENDIF
    
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
                Invoke DisplayErrorMessage, Addr szErrorBeamdog_BG2EE, 0
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_BG2EE
            mov lpszEEGame, eax
        .ENDIF
    .ENDIF
    IFDEF DEBUG32
    PrintText 'No BG2EE'
    ENDIF
    
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
                Invoke DisplayErrorMessage, Addr szErrorBeamdog_BGSOD, 0
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_BGSOD
            mov lpszEEGame, eax
        .ENDIF
    .ENDIF
    IFDEF DEBUG32
    PrintText 'No BGSOD'
    ENDIF
    
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
                Invoke DisplayErrorMessage, Addr szErrorBeamdog_IWDEE, 0
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_IWDEE
            mov lpszEEGame, eax
        .ENDIF
    .ENDIF
    IFDEF DEBUG32
    PrintText 'No IWDEE'
    ENDIF
    
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
                Invoke DisplayErrorMessage, Addr szErrorBeamdog_PSTEE, 0
                ret
            .ENDIF
            ENDIF
            mov bEEGameFound, TRUE
            lea eax, szBeamdog_PSTEE
            mov lpszEEGame, eax
        .ENDIF
    .ENDIF
    IFDEF DEBUG32
    PrintText 'No PSTEE'
    ENDIF
    
    
    ;--------------------------------------------------------------------------
    ; Have we found any EE game exe? Display error message and exit if not
    ;--------------------------------------------------------------------------
    .IF bEEGameFound == FALSE
        IFDEF DEBUG32
        PrintText 'No EE game'
        ENDIF
        Invoke DisplayErrorMessage, Addr szErrorEEGameEXE, 0
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
        Invoke DisplayErrorMessage, Addr szErrorEEexDLLFind, 0
        ret
    .ENDIF
    ENDIF
    
    
    ;--------------------------------------------------------------------------
    ; check UI.menu, TRIGGER.ids, OBJECT.ids and ACTION.ids in override folder
    ;--------------------------------------------------------------------------
    IFDEF CHECK_OVERRIDE_FILES
    Invoke GetCurrentDirectory, SIZEOF szCurrentFolder, Addr szCurrentFolder
    Invoke lstrcpy, Addr szEEGameOverrideFolder, Addr szCurrentFolder
    Invoke lstrcat, Addr szEEGameOverrideFolder, Addr szOverride
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
        Invoke DisplayErrorMessage, Addr szErrorEEOverrideFiles, 0
        ret
    .ELSE
        IFDEF DEBUG32
        PrintText 'Override files located: UI.menu, TRIGGER.ids, OBJECT.ids and ACTION.ids'
        ENDIF
    .ENDIF
    ENDIF
    
    
    ;--------------------------------------------------------------------------
    ; Launch EE game's executable, ready for injection of our EEex.dll
    ;--------------------------------------------------------------------------
    IFDEF DEBUG32
    PrintText 'Launch EE games executable'
    ENDIF
    Invoke CreateProcess, lpszEEGame, NULL, NULL, NULL, FALSE, CREATE_SUSPENDED, NULL, NULL, Addr startinfo, Addr pi
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
        Invoke InjectDLL, pi.hProcess, Addr szEEexDLL
        mov dwExitCode, eax
        Invoke ResumeThread, pi.hThread
        Invoke CloseHandle, pi.hThread
        Invoke CloseHandle, pi.hProcess
        .IF dwExitCode != TRUE
            ret
        .ENDIF
    .ELSE ; CreateProcess failed
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorEEGameExecute, eax
        ret
    .ENDIF    

    mov eax, 0
    ret
WinMain ENDP


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


;------------------------------------------------------------------------------
; Displays Error Messages
;------------------------------------------------------------------------------
DisplayErrorMessage PROC USES EDX szMessage:DWORD, dwError:DWORD
    LOCAL lpError:DWORD
    LOCAL nFormatLength:DWORD
    LOCAL nMessageLength:DWORD
    LOCAL szFormat[255]:BYTE
    LOCAL pMessage[255]:BYTE
    LOCAL dwLanguageId:DWORD

    .IF dwError != 0
        xor edx, edx
        mov dl, SUBLANG_DEFAULT
        shl edx, 10
        or edx, LANG_NEUTRAL
        mov dwLanguageId, edx ; dwLanguageId
        Invoke FormatMessage, FORMAT_MESSAGE_ALLOCATE_BUFFER or FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS, NULL, dwError, edx, Addr lpError, 0, NULL
        Invoke wsprintf, Addr szErrorMessage, Addr szFormatErrorMessage, lpError
        Invoke MessageBox, NULL, Addr szErrorMessage, Addr AppName, MB_OK
        Invoke LocalFree, lpError
    .ELSE
        Invoke MessageBox, NULL, szMessage, Addr AppName, MB_OK
    .ENDIF
    xor eax, eax
    ret
DisplayErrorMessage ENDP


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
    
    Invoke lstrlen, szDLLPath
    mov szLibPathSize, eax

    Invoke VirtualAllocEx, hProcess, NULL, szLibPathSize, MEM_COMMIT, PAGE_READWRITE
    mov lpLibAddress, eax
    .IF eax == NULL
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorVirtualAllocEx, eax
        mov eax, FALSE
        ret
    .ENDIF
    
    Invoke WriteProcessMemory, hProcess, lpLibAddress, szDLLPath, szLibPathSize, Addr BytesWritten
    .IF eax == 0
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorWriteProcessMem, eax
        mov eax, FALSE
        ret
    .ENDIF

    Invoke GetModuleHandle, 0
    mov hMod, eax
    Invoke GetModuleHandle, Addr szKernel32Dll
    mov hKernel32, eax
    .IF eax == NULL
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorGetModuleHandle, eax
        mov eax, FALSE
        ret
    .ENDIF

    Invoke GetProcAddress, hKernel32, Addr szLoadLibraryProc
    mov lpStartRoutine, eax        
    .IF eax == NULL
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorGetProcAddress, eax
        mov eax, FALSE
        ret
    .ENDIF

    Invoke CreateRemoteThread, hProcess, NULL, 0, lpStartRoutine, lpLibAddress, 0, Addr dwRemoteThreadID
    mov hRemoteThread, eax
    
    .IF eax == NULL
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorRemoteThread, eax
        mov eax, FALSE
        ret
    .ENDIF

    Invoke WaitForSingleObject, hRemoteThread, INFINITE

    .IF eax == WAIT_ABANDONED
        
    .ELSEIF eax == WAIT_OBJECT_0

    .ELSEIF eax == WAIT_TIMEOUT
    
    .ELSEIF eax == WAIT_FAILED
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorWaitSingleObj, eax
        mov eax, FALSE
        ret    
    .ELSE    
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorWaitSingleInv, 0
        mov eax, FALSE
        ret               
    .ENDIF

    Invoke GetExitCodeThread, hRemoteThread, Addr dwExitCode
    .IF eax == 0
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorExitCodeThread, 0
        mov eax, FALSE
        ret   
    .ENDIF

    .IF dwExitCode == STILL_ACTIVE
        Invoke GetLastError
        Invoke DisplayErrorMessage, Addr szErrorThreadActive, 0
        mov eax, FALSE
        ret       
    .ENDIF
    
    Invoke CloseHandle, hRemoteThread
    Invoke VirtualFreeEx, hProcess, lpLibAddress, 0, MEM_RELEASE

    mov eax, dwExitCode    
    ret
InjectDLL endp


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


end start


