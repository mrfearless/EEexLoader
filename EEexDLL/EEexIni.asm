;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------
include advapi32.inc
includelib advapi32.lib


;------------------------------------------------------------------------------
; EEexIni Prototypes
;------------------------------------------------------------------------------
; Core ini functions:
IniReadValue            PROTO :DWORD,:DWORD,:DWORD    ; lpszSection, lpszKeyname, dwDefaultValue
IniWriteValue           PROTO :DWORD,:DWORD,:DWORD    ; lpszSection, lpszKeyname, dwValue

; External pattern database ini functions:
IniGetPatternNames      PROTO                         ;
IniGetNextPatternName   PROTO                         ; 
IniGetPatBytesText      PROTO :DWORD,:DWORD           ; lpszPatternName, lpdwPatBytesText
IniGetVerBytesText      PROTO :DWORD,:DWORD           ; lpszPatternName, lpdwVerBytesText
IniGetPatAdj            PROTO :DWORD                  ; lpszPatternName
IniGetVerAdj            PROTO :DWORD                  ; lpszPatternName
IniGetPatType           PROTO :DWORD                  ; lpszPatternName

; Internal ini functions:
IniValueToString        TEXTEQU <EEexDwordToAscii>    ; dwValue:DWORD, lpszAsciiString (EEexDwordToAscii is in EEex.asm)
IniHexStringToValue     TEXTEQU <EEexAsciiHexToDword> ; lpszAsciiHexString (EEexAsciiHexToDword is in EEex.asm)
IniValueToHexString     TEXTEQU <EEexDwordToAsciiHex> ; dwValue:DWORD, lpszAsciiHexString, bUppercase (EEexDwordToAsciiHex is in EEex.asm)

; [Option] section ini functions:
IniGetOptionLog         PROTO                   ;
IniSetOptionLog         PROTO :DWORD            ; dwValue
IniGetOptionLua         PROTO                   ;
IniSetOptionLua         PROTO :DWORD            ; dwValue
IniGetOptionHex         PROTO                   ;
IniSetOptionHex         PROTO :DWORD            ; dwValue
IniGetOptionMsg         PROTO                   ;
IniSetOptionMsg         PROTO :DWORD            ; dwValue


.CONST
INI_LARGESTRING         EQU 2048    ; Max bytes for large key-value string
INI_MAXSECTIONS         EQU 2048    ; Max no of sections for pattern definitions
INI_SECNAMESSIZE        EQU 65536
INI_SECNAMESSIZE_ERROR  EQU 65534   ; size error on return


.DATA
;---------------------------
; Global variables read from 
; ini to control aspects of 
; EEex.dll like enable log 
; or use lua lib functions
;---------------------------
IFDEF EEEX_LOGGING
gEEexLog                DD LOGLEVEL_DEBUG   ; Enable logging (default is yes)
ELSE
gEEexLog                DD LOGLEVEL_NONE    ; Disable logging
ENDIF
IFDEF EEEX_LUALIB
gEEexLuaLibDefined      DD TRUE     ; Variable to indicate compiled with define: EEEX_LUALIB
gEEexLua                DD TRUE     ; Enable lua lib functions (default is yes)
ELSE
gEEexLuaLibDefined      DD FALSE    ; EEEX_LUALIB was not defined when compiled
gEEexLua                DD FALSE    ; Enable lua lib functions (default is no)
ENDIF
gEEexHex                DD TRUE     ; Write string values as hex instead of decimal (default is yes)
gEEexHexUppercase       DD TRUE     ; Hex strings in uppercase (default is yes) - not currently read from ini
gEEexMsg                DD TRUE     ; Messagebox errors/warnings - (default is enabled) - 0 to disable

;---------------------------
; Ini strings
;---------------------------
szIni                   DB "ini",0
szIniEEex               DB "EEex",0
szIniEEexOptions        DB "Options",0
szIniValueZero          DB "0",0
szIniDefault            DB ":",0
szIniHex                DB "0x",0

;---------------------------
; [Option] section strings
;---------------------------
szIniOptionLog          DB "Log",0
szIniOptionLua          DB "Lua",0
szIniOptionHex          DB "Hex",0
szIniOptionMsg          DB "Msg",0

;---------------------------
; [Pattern] section strings
;---------------------------
szIniPatBytes           DB "PatBytes",0
szIniVerBytes           DB "VerBytes",0
szIniPatAdj             DB "PatAdj",0
szIniVerAdj             DB "VerAdj",0
szIniPatType            DB "Type",0

;---------------------------
; Pattern names position
;---------------------------
IniNextPatternNamePos   DD 0 ; Used by IniGetNextPatternName to get string pos of szIniSectionNames

;---------------------------
; Ini Buffers
;---------------------------
szIniValueString        DB 32 DUP (0)
szIniString             DB 32 DUP (0)
szIniLargeString        DB INI_LARGESTRING DUP (0)
szIniPatternNames       DB INI_SECNAMESSIZE DUP (0) ; avg name length 32 chars give about 2048 entries


.CODE


EEEX_ALIGN
;==============================================================================
; Core ini functions
;==============================================================================
;------------------------------------------------------------------------------
; Read a key's value from a section in an ini file. 
; Key value can be a hex or dec value. If hex then it is converted to a dword.
; Hex value can be prefixed with 0x or without, however a pure numerical hex
; value will be interpreted as a decimal, so to avoid that the prefix should 
; be used.
; Returns: dword value or dwDefaultValue value.
;------------------------------------------------------------------------------
IniReadValue PROC USES EBX ECX lpszSection:DWORD, lpszKeyname:DWORD, dwDefaultValue:DWORD
    LOCAL bHex:DWORD
    LOCAL bDec:DWORD
    LOCAL bOther:DWORD
    
    Invoke GetPrivateProfileInt, lpszSection, lpszKeyname, -1, Addr EEexIniFile
    .IF eax == -1
        Invoke GetPrivateProfileString, lpszSection, lpszKeyname, Addr szIniDefault, Addr szIniString, SIZEOF szIniString, Addr EEexIniFile
        .IF eax > 2 ; might have a string starting with '0x'
            mov ecx, eax
            lea ebx, szIniString
            movzx eax, byte ptr [ebx+1]
            .IF al == 'x' || al == 'X' ; as in '0x' - we have a hex string
                add ebx, 2
                Invoke IniHexStringToValue, ebx ; skip the 0x part to convert hex string to dword value 
                ret
            .ELSE ; maybe hex without the '0x' part?
                mov bHex, FALSE
                mov bDec, FALSE
                mov bOther, FALSE
                .WHILE al != 0 && ecx != 0
                    .IF (al >= 'A' && al <= 'F') || (al >= 'a' && al <= 'f')
                        ; we have hex values
                        mov bHex, TRUE
                    .ELSEIF (al >= '0' && al <= '9')
                        ; we have dec values
                        mov bDec, TRUE
                    .ELSE
                        ; we have something else
                        mov bOther, TRUE
                    .ENDIF
                    dec ecx
                    inc ebx
                    movzx eax, byte ptr [ebx]
                .ENDW
                .IF bHex == TRUE && bDec == TRUE && bOther == FALSE ; hex chars with 0-9 in it
                    Invoke IniHexStringToValue, Addr szIniString
                    ret
                .ELSEIF bHex == TRUE && bDec == FALSE && bOther == FALSE ; hex chars chars only
                    Invoke IniHexStringToValue, Addr szIniString
                    ret            
                .ELSE
                    ; anything else then falls to default GetPrivateProfileInt
                .ENDIF
            .ENDIF
        .ENDIF
        ; If we land here then we revert back to read an integer from ini file
        Invoke GetPrivateProfileInt, lpszSection, lpszKeyname, dwDefaultValue, Addr EEexIniFile
    .ENDIF
    ret
IniReadValue ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Writes a key's value to a section in an ini file. 
; Returns: characters written to key
;------------------------------------------------------------------------------
IniWriteValue PROC lpszSection:DWORD, lpszKeyname:DWORD, dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, lpszSection, lpszKeyname, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        .IF gEEexHex == TRUE ; convert value to hex string
            Invoke IniValueToHexString, dwValue, Addr szIniValueString, gEEexHexUppercase
        .ELSE
            Invoke IniValueToString, dwValue, Addr szIniValueString
        .ENDIF
        Invoke WritePrivateProfileString, lpszSection, lpszKeyname, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniWriteValue ENDP



;==============================================================================
; Pattern import ini functions
;==============================================================================

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetPatternNames - Get section names from external patterns database
; Returns: 0 if no content, -1 if too many patterns, or pattern count
;------------------------------------------------------------------------------
IniGetPatternNames PROC USES EBX ECX
    Invoke GetPrivateProfileSectionNames, Addr szIniPatternNames, SIZEOF szIniPatternNames, Addr EEexPatFile
    
    .IF eax == 0 ; nothing/no patterns
        mov eax, 0
    .ELSEIF eax == INI_SECNAMESSIZE_ERROR ; too many patterns
        mov eax, -1
    .ELSE
        ; get count of section names = total patterns
        xor ecx, ecx
        lea ebx, szIniPatternNames
        movzx eax, word ptr [ebx]
        .IF ax == 0 ; just in case
            mov eax, 0
            ret
        .ENDIF
        .WHILE ax != 0
            .IF al == 0
                inc ecx
            .ENDIF
            inc ebx
            movzx eax, word ptr [ebx]
        .ENDW
        inc ecx ; add extra 1 for last double null found
    
        mov eax, ecx ; eax contains total section names
    .ENDIF
    ret
IniGetPatternNames ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetNextPatternName
;------------------------------------------------------------------------------
IniGetNextPatternName PROC USES EBX
    LOCAL lpszPatName:DWORD
    
    lea ebx, szIniPatternNames
    add ebx, IniNextPatternNamePos
    mov lpszPatName, ebx
    
    movzx eax, byte ptr [ebx]
    .IF al == 0 ; if at null already we are at last double null so reset & exit
        mov IniNextPatternNamePos, 0
        mov eax, 0
        ret
    .ENDIF
    
    ; update IniNextPatternNamePos to point to next pattern name for next call
    movzx eax, byte ptr [ebx]
    .WHILE al != 0
        inc IniNextPatternNamePos
        inc ebx
        movzx eax, byte ptr [ebx]
    .ENDW
    inc IniNextPatternNamePos ; skip past null for correct position of next call
    
    mov eax, lpszPatName
    ret
IniGetNextPatternName ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetPatBytesText - Read PatBytes from patterns database for a <PatternName>
; Returns: in eax length of patbytes text string, or 0 if empty, -1 if invalid
; On succesful return the DWORD variable pointed to by lpdwPatBytesText
; will contain the pointer to the PatBytes hex text string 
;------------------------------------------------------------------------------
IniGetPatBytesText PROC USES EBX lpszPatternName:DWORD, lpdwPatBytesText:DWORD
    LOCAL dwLenPatBytes:DWORD
    
    Invoke GetPrivateProfileString, lpszPatternName, Addr szIniPatBytes, Addr szIniDefault, Addr szIniLargeString, SIZEOF szIniLargeString, Addr EEexPatFile
    .IF eax == 1 ; default char ':' returned as PatBytes didnt have anything in it, or it had 1 character which is invalid anyhow
        mov ebx, lpdwPatBytesText
        mov eax, 0
        mov [ebx], eax
        ret
    .ENDIF
    mov dwLenPatBytes, eax
    ; check if length is multiple of 2
    ;and eax, 1 ; ( a AND (b-1) = mod )
    ;.IF eax == 0 ; is divisable by 2?
        lea eax, szIniLargeString
        mov ebx, lpdwPatBytesText
        mov [ebx], eax
        mov eax, dwLenPatBytes
    ;.ELSE
    ;    mov ebx, lpdwPatBytesText
    ;    mov eax, -1
    ;    mov [ebx], eax
    ;.ENDIF
    ret
IniGetPatBytesText ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetVerBytesText - Read VerBytes from patterns database for a <PatternName>
; Returns: in eax length of verbytes text string, or 0 if empty, -1 if invalid
; On succesful return the DWORD variable pointed to by lpdwVerBytesText
; will contain the pointer to the VerBytes hex text string 
;------------------------------------------------------------------------------;
IniGetVerBytesText PROC lpszPatternName:DWORD, lpdwVerBytesText:DWORD
    LOCAL dwLenVerBytes:DWORD
    
    Invoke GetPrivateProfileString, lpszPatternName, Addr szIniVerBytes, Addr szIniDefault, Addr szIniLargeString, SIZEOF szIniLargeString, Addr EEexPatFile
    .IF eax == 1 ; default char ':' returned as PatBytes didnt have anything in it, or it had 1 character which is invalid anyhow
        mov ebx, lpdwVerBytesText
        mov eax, 0
        mov [ebx], eax
        ret
    .ENDIF
    mov dwLenVerBytes, eax
    ; check if length is multiple of 2
    ;and eax, 1 ; ( a AND (b-1) = mod )
    ;.IF eax == 0 ; is divisable by 2?
        lea eax, szIniLargeString
        mov ebx, lpdwVerBytesText
        mov [ebx], eax
        mov eax, dwLenVerBytes
    ;.ELSE
    ;    mov ebx, lpdwVerBytesText
    ;    mov eax, -1
    ;    mov [ebx], eax
    ;.ENDIF
    ret
IniGetVerBytesText ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetPatAdj - Read PatAdj key for <PatternName> from patterns database
;------------------------------------------------------------------------------
IniGetPatAdj PROC lpszPatternName:DWORD
    Invoke GetPrivateProfileInt, lpszPatternName, Addr szIniPatAdj, 0, Addr EEexPatFile
    ret
IniGetPatAdj ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetVerAdj - Read VerAdj key for <PatternName> from patterns database
;------------------------------------------------------------------------------
IniGetVerAdj PROC lpszPatternName:DWORD
    Invoke GetPrivateProfileInt, lpszPatternName, Addr szIniVerAdj, 0, Addr EEexPatFile
    ret
IniGetVerAdj ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; IniGetPatType - Read Type key for <PatternName> from patterns database
;------------------------------------------------------------------------------
IniGetPatType PROC lpszPatternName:DWORD
    Invoke GetPrivateProfileInt, lpszPatternName, Addr szIniPatType, 0, Addr EEexPatFile
    ret
IniGetPatType ENDP




;==============================================================================
; [Option] section ini functions
;==============================================================================

EEEX_ALIGN
;------------------------------------------------------------------------------
; Read ini file for log setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionLog PROC
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionLog, gEEexLog, Addr EEexIniFile
    ret
IniGetOptionLog ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Writes log setting to [Option] section
;------------------------------------------------------------------------------
IniSetOptionLog PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionLog, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionLog, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetOptionLog ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Read ini file for lua setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionLua PROC
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionLua, gEEexLua, Addr EEexIniFile
    ret
IniGetOptionLua ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Writes log setting to [Option] section
;------------------------------------------------------------------------------
IniSetOptionLua PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionLua, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionLua, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetOptionLua ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Read ini file for hex setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionHex PROC
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionHex, gEEexHex, Addr EEexIniFile
    ret
IniGetOptionHex ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Writes hex setting to [Option] section
;------------------------------------------------------------------------------
IniSetOptionHex PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionHex, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionHex, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetOptionHex ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Read ini file for msg setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionMsg PROC
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionMsg, gEEexMsg, Addr EEexIniFile
    ret
IniGetOptionMsg ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Writes msg setting to [Option] section
;------------------------------------------------------------------------------
IniSetOptionMsg PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionMsg, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEexOptions, Addr szIniOptionMsg, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetOptionMsg ENDP


















