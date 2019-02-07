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
IniClearFallbackSection PROTO                         ;

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

; [EEex] section ini functions:
IniGetPatchLocation     PROTO :DWORD            ; bFallback
IniSetPatchLocation     PROTO :DWORD            ; dwValue




.CONST
INI_NORMAL              EQU 0       ; Read [EEex] section
INI_FALLBACK            EQU 1       ; Read [Fallback] section


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

;---------------------------
; Ini strings
;---------------------------
szIni                   DB "ini",0
szIniEEex               DB "EEex",0
szIniEEexOptions        DB "Options",0
szIniEEexFallback       DB "Fallback",0
szIniValueZero          DB "0",0
szIniDefault            DB ":",0
szIniHex                DB "0x",0

;---------------------------
; [Option] section strings
;---------------------------
szIniOptionLog          DB "Log",0
szIniOptionLua          DB "Lua",0
szIniOptionHex          DB "Hex",0



;---------------------------
; [EEex] section strings
;---------------------------
szIniCAIObjectTypeOpEqu2 DB "CAIObjectType::operator-equequ",0 ; CAIObjectType::operator==
szIniCAIObjectTypeOpEqu  DB "CAIObjectType::operator-equ",0 ; CAIObjectType::operator=
szIniCStringOpPlus       DB "CString::operator-plus",0 ; operator+
szIniCResRefOpEqu        DB "CResRef::operator-equ",0 ; operator= 
szIniCResRefOpNotEqu     DB "CResRef::operator-notequ",0 ; operator!=
;---------------------------
; Ini Buffers
;---------------------------
szIniValueString        DB 32 DUP (0)
szIniString             DB 32 DUP (0)

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


EEEX_ALIGN
;------------------------------------------------------------------------------
; Clears the [Fallback] section in the ini file. The fallback section can
; contain function addresses to fallback on, if the pattern's searched for fail
; in this case if a fallback section keyvalue is found, this alternative
; address (typically from a specific build of an exe) can be used. 
;
; After a newer build/update for the EEex loader and dll, when patterns are 
; found again, then this [Fallback] section is cleared to prevent newer EE game
; builds in future from triggering the read of now (possibly) invalid fallback 
; addresses.
;
; Typical scenario for usage is that info from a forum post etc will indicate
; the raw hardcoded addresses to use. User then edits EEex.ini to add a
; [Fallback] section and the function addresses, or paste info.
;
; [Fallback]
; lua_pushnumber=0x1234ABCD
;
;------------------------------------------------------------------------------
IniClearFallbackSection PROC
    Invoke WritePrivateProfileString, Addr szIniEEexFallback, NULL, NULL, Addr EEexIniFile
    ret
IniClearFallbackSection ENDP


EEEX_ALIGN
;==============================================================================
; [Option] section ini functions
;==============================================================================
;------------------------------------------------------------------------------
; Read ini file for log setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionLog PROC
    IFDEF EEEX_LOGGING
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionLog, gEEexLog, Addr EEexIniFile
    ELSE
    mov eax, FALSE
    ENDIF
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
; Read ini file for PatchLocation
;------------------------------------------------------------------------------
IniGetPatchLocation PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szPatchLocation, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szPatchLocation, 0
    .ENDIF
    ret
IniGetPatchLocation ENDP

EEEX_ALIGN
;------------------------------------------------------------------------------
; Write PatchLocation to ini file
;------------------------------------------------------------------------------
IniSetPatchLocation PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szPatchLocation, dwValue
    ret
IniSetPatchLocation ENDP



















