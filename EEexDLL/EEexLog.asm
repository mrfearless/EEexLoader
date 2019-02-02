;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; EEexLog Prototypes
;------------------------------------------------------------------------------
LogOpen                 PROTO :DWORD                 ; bAppend
LogClose                PROTO                        ;
LogMessage              PROTO :DWORD, :DWORD, :DWORD ; lpszLogMessage, LogMsgType, IndentLevel
LogMessageAndValue      PROTO :DWORD, :DWORD         ; lpszLogMessage, dwLogValue
LogMessageAndHexValue   PROTO :DWORD, :DWORD         ;
 
LogValueToString        TEXTEQU <EEexDwordToAscii>   ; dwValue:DWORD, lpszAsciiString (EEexDwordToAscii is in EEex.asm)
LogValueToHexString     TEXTEQU <EEexDwordToAsciiHex>; dwValue:DWORD, lpszAsciiHexString, bUppercase (EEexDwordToAsciiHex is in EEex.asm)

.CONST
;---------------------------
; LogMessage LogMsgType Enum:
;---------------------------
LOG_STANDARD            EQU 0
LOG_INFO                EQU 1
LOG_ERROR               EQU 2
LOG_HDRBREAK            EQU 3
LOG_NONEWLINE           EQU 4
LOG_CRLF                EQU 5
LOG_MSGVALUE            EQU 6
LOG_VALUE               EQU 7
LOG_OPEN                EQU 8
LOG_CLOSE               EQU 9


.DATA
hLogFile                DD -1

szLog                   DB "log",0
szLog_Backslash         DB "\",0
szLog_NULL              DB 0,0
szLog_CRLF              DB 13d,10d,0
szLog_Tab               DB 09d,0
szLog_Space             DB 32d,0
szLog_Zero              DB "0",0
szLog_Slash             DB "/",0
szLog_Colon             DB ":",0
szLog_Dash              DB "-",0

szLog_LogOpened         DB "EEex Log opened",0
szLog_LogClosed         DB "EEex Log closed",0
szLog_HeaderBreak       DB "--------------------------------------------------------------------------------",0
szLog_LogInfo           DB "[*] ",0
szLog_LogError          DB "[!] ",0
szLog_LogValue          DB "[=] ",0

;---------------------------
; Log Buffers
;---------------------------
szLog_Day               DB 4 DUP (0)
szLog_Month             DB 4 DUP (0)
szLog_Year              DB 8 DUP (0)
szLog_Hour              DB 4 DUP (0)
szLog_Minute            DB 4 DUP (0)
szLog_Second            DB 4 DUP (0)
szLogDate               DB 32 DUP (0)
szLogTime               DB 32 DUP (0)
szLogValue              DB 32 DUP (0)
szLogEntry              DB 512 DUP (0)


.CODE


;------------------------------------------------------------------------------
; LogOpen - opens the log file with optional append to existing log
; Returns: handle to log file
;------------------------------------------------------------------------------
LogOpen PROC bAppend:DWORD
    .IF gEEexLog == FALSE
        ret
    .ENDIF
    .IF hLogFile != INVALID_HANDLE_VALUE ; log already opened?
        ret
    .ENDIF
    .IF bAppend == TRUE
        Invoke CreateFile, Addr EEexLogFile, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_WRITE or FILE_SHARE_READ, NULL, OPEN_ALWAYS, 0, NULL
        .IF eax != INVALID_HANDLE_VALUE
            push eax
            Invoke SetFilePointer, eax, 0, 0, FILE_END
            pop eax
        .ELSE
            Invoke CreateFile, Addr EEexLogFile, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_WRITE or FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL
        .ENDIF
    .ELSE
        Invoke CreateFile, Addr EEexLogFile, GENERIC_READ or GENERIC_WRITE, FILE_SHARE_WRITE or FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL
    .ENDIF
    mov hLogFile, eax
    Invoke LogMessage, 0, LOG_OPEN, 0
    mov eax, hLogFile
    ret
LogOpen ENDP


;------------------------------------------------------------------------------
; LogClose - close log file
; Returns: none
;------------------------------------------------------------------------------
LogClose PROC
    .IF gEEexLog == FALSE
        ret
    .ENDIF
    Invoke LogMessage, 0, LOG_CLOSE, 0
    .IF hLogFile != INVALID_HANDLE_VALUE
        Invoke CloseHandle, hLogFile
    .ENDIF
    mov hLogFile, INVALID_HANDLE_VALUE
    xor eax, eax
    ret
LogClose ENDP


;--------------------------------------------------------------------------------------
; LogDateTime
;--------------------------------------------------------------------------------------
LogDateTime PROC USES EBX lpszDate:DWORD, lpszTime:DWORD 
    LOCAL DateTime:SYSTEMTIME
    LOCAL dwDay:DWORD
    LOCAL dwMonth:DWORD
    LOCAL dwYear:DWORD
    LOCAL dwHour:DWORD
    LOCAL dwMinute:DWORD
    LOCAL dwSecond:DWORD

    Invoke GetLocalTime, Addr DateTime
    lea ebx, DateTime
    movzx eax, [ebx].SYSTEMTIME.wDay
    mov dwDay, eax
    lea ebx, DateTime
    movzx eax, [ebx].SYSTEMTIME.wMonth
    mov dwMonth, eax
    movzx eax, [ebx].SYSTEMTIME.wYear
    mov dwYear, eax
    movzx eax, [ebx].SYSTEMTIME.wHour
    mov dwHour, eax
    movzx eax, [ebx].SYSTEMTIME.wMinute
    mov dwMinute, eax
    movzx eax, [ebx].SYSTEMTIME.wSecond
    mov dwSecond, eax
    
    Invoke LogValueToString, dwDay, Addr szLog_Day
    Invoke LogValueToString, dwMonth, Addr szLog_Month
    Invoke LogValueToString, dwYear, Addr szLog_Year
    Invoke LogValueToString, dwHour, Addr szLog_Hour
    Invoke LogValueToString, dwMinute, Addr szLog_Minute
    Invoke LogValueToString, dwSecond, Addr szLog_Second
    
    .IF dwDay < 10
        Invoke lstrcpy, lpszDate, Addr szLog_Zero
        Invoke lstrcat, lpszDate, Addr szLog_Day
    .ELSE
        Invoke lstrcpy, lpszDate, Addr szLog_Day
    .ENDIF
    Invoke lstrcat, lpszDate, Addr szLog_Slash
    
    .IF dwMonth < 10
        Invoke lstrcat, lpszDate, Addr szLog_Zero
        Invoke lstrcat, lpszDate, Addr szLog_Month
    .ELSE
        Invoke lstrcat, lpszDate, Addr szLog_Month
    .ENDIF
    Invoke lstrcat, lpszDate, Addr szLog_Slash
    Invoke lstrcat, lpszDate, Addr szLog_Year
    
    ; Time
    .IF dwHour < 10
        Invoke lstrcpy, lpszTime, Addr szLog_Zero
        Invoke lstrcat, lpszTime, Addr szLog_Hour
    .ELSE
        Invoke lstrcpy, lpszTime, Addr szLog_Hour
    .ENDIF
    Invoke lstrcat, lpszTime, Addr szLog_Colon
    
    .IF dwMinute < 10
        Invoke lstrcat, lpszTime, Addr szLog_Zero
        Invoke lstrcat, lpszTime, Addr szLog_Minute
    .ELSE
        Invoke lstrcat, lpszTime, Addr szLog_Minute
    .ENDIF
    Invoke lstrcat, lpszTime, Addr szLog_Colon

    .IF dwSecond < 10
        Invoke lstrcat, lpszTime, Addr szLog_Zero
        Invoke lstrcat, lpszTime, Addr szLog_Second
    .ELSE
        Invoke lstrcat, lpszTime, Addr szLog_Second
    .ENDIF
    
    xor eax, eax
    ret
LogDateTime endp


;--------------------------------------------------------------------------------------
; LogMessage
;--------------------------------------------------------------------------------------
LogMessage PROC lpszLogMessage:DWORD, LogMsgType:DWORD, IndentLevel:DWORD
    LOCAL BytesToWrite:DWORD
    LOCAL BytesWritten:DWORD
    LOCAL Indent:DWORD
    
    .IF gEEexLog == FALSE
        ret
    .ENDIF
    .IF hLogFile == INVALID_HANDLE_VALUE
        ret
    .ENDIF
    
    mov eax, LogMsgType
    .IF eax == LOG_STANDARD
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_NULL
    .ELSEIF eax == LOG_NONEWLINE
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_NULL
    .ELSEIF eax == LOG_MSGVALUE
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_NULL
    .ELSEIF eax == LOG_VALUE
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_LogValue
    .ELSEIF eax == LOG_INFO
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_LogInfo
    .ELSEIF eax == LOG_ERROR
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_LogError
    .ELSEIF eax == LOG_HDRBREAK
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_HeaderBreak
    .ELSEIF eax == LOG_CRLF
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_NULL
    .ENDIF

    .IF IndentLevel > 0
        mov eax, 0
        mov Indent, 0
        .WHILE eax < IndentLevel
            Invoke lstrcat, Addr szLogEntry, Addr szLog_Tab
            inc Indent
            mov eax, Indent
        .ENDW
    .ENDIF

    .IF LogMsgType == LOG_MSGVALUE
        Invoke lstrcat, Addr szLogEntry, Addr szLog_Colon
        Invoke lstrcat, Addr szLogEntry, Addr szLog_Space
    .ENDIF
    
    .IF lpszLogMessage != 0
        Invoke lstrcat, Addr szLogEntry, lpszLogMessage
    .ENDIF
    
    mov eax, LogMsgType
    .IF eax != LOG_NONEWLINE && eax != LOG_OPEN && eax != LOG_CLOSE
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
    .ENDIF

    .IF LogMsgType == LOG_OPEN
        Invoke LogDateTime, Addr szLogDate, Addr szLogTime
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_HeaderBreak
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
        Invoke lstrcat, Addr szLogEntry, Addr szLog_LogOpened
        Invoke lstrcat, Addr szLogEntry, Addr szLog_Space
        Invoke lstrcat, Addr szLogEntry, Addr szLog_Dash
        Invoke lstrcat, Addr szLogEntry, Addr szLog_Space
        Invoke lstrcat, Addr szLogEntry, Addr szLogDate
        Invoke lstrcat, Addr szLogEntry, Addr szLog_Space
        Invoke lstrcat, Addr szLogEntry, Addr szLogTime
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
        Invoke lstrcat, Addr szLogEntry, Addr szLog_HeaderBreak        
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
        ;Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
    .ENDIF

    .IF LogMsgType == LOG_CLOSE
        Invoke lstrcpy, Addr szLogEntry, Addr szLog_HeaderBreak
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
        Invoke lstrcat, Addr szLogEntry, Addr szLog_LogClosed
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
        Invoke lstrcat, Addr szLogEntry, Addr szLog_HeaderBreak
        Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
        ;Invoke lstrcat, Addr szLogEntry, Addr szLog_CRLF
    .ENDIF
    
    Invoke lstrlen, Addr szLogEntry
    mov BytesToWrite, eax

    Invoke WriteFile, hLogFile, Addr szLogEntry, BytesToWrite, Addr BytesWritten, NULL

    xor eax, eax
    ret
LogMessage endp


;--------------------------------------------------------------------------------------
; LogMessageAndValue
;--------------------------------------------------------------------------------------
LogMessageAndValue PROC lpszLogMessage:DWORD, dwLogValue:DWORD
    .IF gEEexLog == FALSE
        ret
    .ENDIF
    .IF lpszLogMessage != 0
        Invoke LogMessage, lpszLogMessage, LOG_NONEWLINE, 0
    .ENDIF
    Invoke LogValueToString, dwLogValue, Addr szLogValue
    Invoke LogMessage, Addr szLogValue, LOG_MSGVALUE, 0
    xor eax, eax
    ret
LogMessageAndValue ENDP


;--------------------------------------------------------------------------------------
; LogMessageAndHexValue
;--------------------------------------------------------------------------------------
LogMessageAndHexValue PROC lpszLogMessage:DWORD, dwLogValue:DWORD
    .IF gEEexLog == FALSE
        ret
    .ENDIF
    .IF lpszLogMessage != 0
        Invoke LogMessage, lpszLogMessage, LOG_NONEWLINE, 0
    .ENDIF
    .IF gEEexHex == TRUE
        Invoke LogValueToHexString, dwLogValue, Addr szLogValue, gEEexHexUppercase
    .ELSE
        Invoke LogValueToString, dwLogValue, Addr szLogValue
    .ENDIF
    Invoke LogMessage, Addr szLogValue, LOG_MSGVALUE, 0
    xor eax, eax
    ret
LogMessageAndHexValue ENDP







