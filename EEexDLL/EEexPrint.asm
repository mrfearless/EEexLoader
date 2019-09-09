;------------------------------------------------------------------------------
; EEex.DLL - Loader for EEex to inject EEex.dll by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
;
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; EEexPrint Prototypes
;------------------------------------------------------------------------------
EEexSDL_Log                 PROTO C arg:VARARG
EEexSDL_LogMessageV         PROTO C category:DWORD, priority:DWORD, fmt:DWORD, ap:DWORD
EEexSDL_LogOutput           PROTO C priority:DWORD, message:DWORD


.CONST
SDL_LOG_PRIORITY_VERBOSE    EQU 1
SDL_LOG_PRIORITY_DEBUG      EQU 2
SDL_LOG_PRIORITY_INFO       EQU 3
SDL_LOG_PRIORITY_WARN       EQU 4
SDL_LOG_PRIORITY_ERROR      EQU 5
SDL_LOG_PRIORITY_CRITICAL   EQU 6
SDL_NUM_LOG_PRIORITIES      EQU 7
SDL_MAX_LOG_MESSAGE         EQU 4096

.DATA
szLogMessageBuffer      DB SDL_MAX_LOG_MESSAGE DUP (0)
szLogOutputBuffer       DB SDL_MAX_LOG_MESSAGE DUP (0)
consoleAttached         DD 0
stderrHandle            DD NULL
szLogOutputFmt          DB "%s: %s",13,10,0,0,0,0
szPriorityPrefixInfo    DB "INFO",0,0,0,0


.CODE


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexSDL_Log
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
EEexSDL_Log PROC C arg:VARARG
    ;Invoke EEexSDL_LogMessageV, 0, SDL_LOG_PRIORITY_INFO, lpszFmt, lpszString
    push ebp
    mov ebp, esp
    lea eax,dword ptr [ebp+0Ch] 
    push eax 
    push dword ptr [ebp+8] 
    push 3
    push 0
    call EEexSDL_LogMessageV
    add esp,10h
    pop ebp
    ret
EEexSDL_Log ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef

EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexSDL_LogMessageV
;------------------------------------------------------------------------------
EEexSDL_LogMessageV PROC C USES EBX category:DWORD, priority:DWORD, fmt:DWORD, ap:DWORD
    LOCAL len:DWORD
    
    .IF sdword ptr priority < 0 || priority >= SDL_NUM_LOG_PRIORITIES
        ret
    .ENDIF
    
    Invoke F_SDL_vsnprintf, Addr szLogMessageBuffer, SDL_MAX_LOG_MESSAGE, fmt, ap
    
    Invoke lstrlen, Addr szLogMessageBuffer
    mov len, eax
    .IF eax > 0
        lea ebx, szLogMessageBuffer
        add ebx, len
        dec ebx
        movzx eax, byte ptr [ebx]
        .IF al == 10d
            mov byte ptr [ebx], 0h
        .ENDIF
        dec ebx
        movzx eax, byte ptr [ebx]
        .IF al == 13d
            mov byte ptr [ebx], 0h
        .ENDIF
    .ENDIF
    
    Invoke EEexSDL_LogOutput, priority, Addr szLogMessageBuffer

    ret
EEexSDL_LogMessageV ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexSDL_LogOutput
;------------------------------------------------------------------------------
EEexSDL_LogOutput PROC C USES EBX ECX priority:DWORD, message:DWORD
    LOCAL attachResult:DWORD
    LOCAL attachError:DWORD
    LOCAL charsToWrite:DWORD
    LOCAL charsWritten:DWORD
    LOCAL consoleMode:DWORD
    LOCAL lpszPriority:DWORD
    
    mov eax, consoleAttached
    .IF eax == 0
        
        Invoke AttachConsole, ATTACH_PARENT_PROCESS
        mov attachResult, eax
        
        .IF attachResult != TRUE
            Invoke  GetLastError
            mov attachError, eax
            .IF eax == ERROR_INVALID_HANDLE
                IFDEF DEBUG32
                PrintText 'Parent process has no console'
                ENDIF
                mov consoleAttached, -1
            .ELSEIF eax == ERROR_GEN_FAILURE
                IFDEF DEBUG32
                PrintText 'Could not attach to console of parent process'
                ENDIF
                mov consoleAttached, -1
            .ELSEIF eax == ERROR_ACCESS_DENIED
                IFDEF DEBUG32
                PrintText 'Already attached'
                ENDIF
                mov consoleAttached, 1
            .ELSE
                IFDEF DEBUG32
                PrintText 'Error attaching console'
                ENDIF
                mov consoleAttached, -1
            .ENDIF
            
        .ELSE
            IFDEF DEBUG32
            PrintText 'Newly attached'
            ENDIF
            mov consoleAttached, 1
        .ENDIF
        
        .IF consoleAttached == 1
            Invoke GetStdHandle, STD_ERROR_HANDLE
            mov stderrHandle, eax
        .ENDIF

    .ELSEIF eax == -1
        IFDEF EEEX_LOGGING
        .IF gEEexLog >= LOGLEVEL_DETAIL
            Invoke wsprintf, Addr szLogOutputBuffer, Addr szLogOutputFmt, Addr szPriorityPrefixInfo, message ; lpszPriority
            Invoke LogMessage, Addr szLogOutputBuffer, LOG_NONEWLINE, 0
        .ENDIF
        ENDIF
        ret
    .ENDIF
    
    ; Get priority text
;    mov ecx, priority
;    lea ebx, szPriorityPrefixes
;    lea eax, [ebx+ecx*4]
;    mov eax, [eax]
;    mov lpszPriority, eax
    
    ;Invoke RtlZeroMemory, Addr szLogOutputBuffer, 4096d
    Invoke wsprintf, Addr szLogOutputBuffer, Addr szLogOutputFmt, Addr szPriorityPrefixInfo, message ; lpszPriority

    .IF consoleAttached == 1
        Invoke lstrlen, Addr szLogOutputBuffer
        mov charsToWrite, eax
        Invoke WriteFile, stderrHandle, Addr szLogOutputBuffer, charsToWrite, Addr charsWritten, NULL
    .ENDIF
    
    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DETAIL
        Invoke LogMessage, Addr szLogOutputBuffer, LOG_NONEWLINE, 0
    .ENDIF
    ENDIF
    
    ret
EEexSDL_LogOutput ENDP



