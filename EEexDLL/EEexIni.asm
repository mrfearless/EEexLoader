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
IniGetOptionLua         PROTO                   ;
IniGetOptionHex         PROTO                   ;

; [EEex] section ini functions:
IniGetPatchLocation     PROTO :DWORD            ; bFallback
IniSetPatchLocation     PROTO :DWORD            ; dwValue
IniGetLua_createtable   PROTO :DWORD            ; bFallback
IniSetLua_createtable   PROTO :DWORD            ; dwValue
IniGetLua_getglobal     PROTO :DWORD            ; bFallback
IniSetLua_getglobal     PROTO :DWORD            ; dwValue
IniGetLua_gettop        PROTO :DWORD            ; bFallback
IniSetLua_gettop        PROTO :DWORD            ; dwValue
IniGetLua_pcallk        PROTO :DWORD            ; bFallback
IniSetLua_pcallk        PROTO :DWORD            ; dwValue
IniGetLua_pushcclosure  PROTO :DWORD            ; bFallback
IniSetLua_pushcclosure  PROTO :DWORD            ; dwValue
IniGetLua_pushlightuserdata PROTO :DWORD            ; bFallback
IniSetLua_pushlightuserdata PROTO :DWORD        ; dwValue
IniGetLua_pushlstring   PROTO :DWORD            ; bFallback
IniSetLua_pushlstring   PROTO :DWORD            ; dwValue
IniGetLua_pushnumber    PROTO :DWORD            ; bFallback
IniSetLua_pushnumber    PROTO :DWORD            ; dwValue
IniGetLua_pushstring    PROTO :DWORD            ; bFallback
IniSetLua_pushstring    PROTO :DWORD            ; dwValue
IniGetLua_rawgeti       PROTO :DWORD            ; bFallback
IniSetLua_rawgeti       PROTO :DWORD            ; dwValue
IniGetLua_rawlen        PROTO :DWORD            ; bFallback
IniSetLua_rawlen        PROTO :DWORD            ; dwValue
IniGetLua_setfield      PROTO :DWORD            ; bFallback
IniSetLua_setfield      PROTO :DWORD            ; dwValue
IniGetLua_setglobal     PROTO :DWORD            ; bFallback
IniSetLua_setglobal     PROTO :DWORD            ; dwValue
IniGetLua_settable      PROTO :DWORD            ; bFallback
IniSetLua_settable      PROTO :DWORD            ; dwValue
IniGetLua_settop        PROTO :DWORD            ; bFallback
IniSetLua_settop        PROTO :DWORD            ; dwValue
IniGetLua_toboolean     PROTO :DWORD            ; bFallback
IniSetLua_toboolean     PROTO :DWORD            ; dwValue
IniGetLua_tolstring     PROTO :DWORD            ; bFallback
IniSetLua_tolstring     PROTO :DWORD            ; dwValue
IniGetLua_tonumberx     PROTO :DWORD            ; bFallback
IniSetLua_tonumberx     PROTO :DWORD            ; dwValue
IniGetLua_touserdata    PROTO :DWORD            ; bFallback
IniSetLua_touserdata    PROTO :DWORD            ; dwValue
IniGetLua_type          PROTO :DWORD            ; bFallback
IniSetLua_type          PROTO :DWORD            ; dwValue
IniGetLua_typename      PROTO :DWORD            ; bFallback
IniSetLua_typename      PROTO :DWORD            ; dwValue
IniGetLuaL_loadstring   PROTO :DWORD            ; bFallback
IniSetLuaL_loadstring   PROTO :DWORD            ; dwValue
IniGetftol2_sse         PROTO :DWORD            ; bFallback
IniSetftol2_sse         PROTO :DWORD            ; dwValue

; Ini functions for game globals pattern address:
IniGet_pp_pChitin       PROTO :DWORD            ; bFallback
IniSet_pp_pChitin       PROTO :DWORD            ; dwValue
IniGet_pp_pBaldurChitin PROTO :DWORD            ; bFallback
IniSet_pp_pBaldurChitin PROTO :DWORD            ; dwValue
IniGet_pp_backgroundMenu PROTO :DWORD            ; bFallback
IniSet_pp_backgroundMenu PROTO :DWORD            ; dwValue
IniGet_pp_overlayMenu   PROTO :DWORD            ; bFallback
IniSet_pp_overlayMenu   PROTO :DWORD            ; dwValue




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
gEEexLog                DD TRUE     ; Enable logging (default is yes)
ELSE
gEEexLog                DD FALSE    ; Enable logging (default is no)
ENDIF
IFDEF EEEX_LUALIB
gEEexLuaLibDefined      DD TRUE     ; Variable to indicate compiled with define: EEEX_LUALIB
gEEexLua                DD TRUE     ; Enable lua lib functions (default is yes)
ELSE
gEEexLuaLibDefined      DD FALSE    ; EEEX_LUALIB was not defined when compiled
gEEexLua                DD FALSE    ; Enable lua lib functions (default is no)
ENDIF
gEEexHex                DD TRUE     ; Write string values as hex instead of decimal (default is yes)
gEEexHexUppercase       DD FALSE    ; Hex strings in uppercase (default is no) - not currently read from ini

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
szIniPatchLocation      DB "PatchLocation",0
szIniLua_createtable    DB "Lua_createtable",0
szIniLua_getglobal      DB "Lua_getglobal",0
szIniLua_gettop         DB "Lua_gettop",0
szIniLua_pcallk         DB "Lua_pcallk",0
szIniLua_pushcclosure   DB "Lua_pushcclosure",0
szIniLua_pushlightuserdata DB "Lua_pushlightuserdata",0
szIniLua_pushlstring    DB "Lua_pushlstring",0
szIniLua_pushnumber     DB "Lua_pushnumber",0
szIniLua_pushstring     DB "Lua_pushstring",0
szIniLua_rawgeti        DB "Lua_rawgeti",0
szIniLua_rawlen         DB "Lua_rawlen",0
szIniLua_setfield       DB "Lua_setfield",0
szIniLua_setglobal      DB "Lua_setglobal",0
szIniLua_settable       DB "Lua_settable",0
szIniLua_settop         DB "Lua_settop",0
szIniLua_toboolean      DB "Lua_toboolean",0
szIniLua_tolstring      DB "Lua_tolstring",0
szIniLua_tonumberx      DB "Lua_tonumberx",0
szIniLua_touserdata     DB "Lua_touserdata",0
szIniLua_type           DB "Lua_type",0
szIniLua_typename       DB "Lua_typename",0
szIniLuaL_loadstring    DB "LuaL_loadstring",0
szIni_ftol2_sse         DB "_ftol2_sse",0

; Game globals pattern address
szIni_pp_pChitin        DB "pp_pChitin",0
szIni_pp_pBaldurChitin  DB "pp_pBaldurChitin",0
szIni_pp_backgroundMenu DB "pp_backgroundMenu",0
szIni_pp_overlayMenu    DB "pp_overlayMenu",0


;---------------------------
; Ini Buffers
;---------------------------
szIniValueString        DB 32 DUP (0)
szIniString             DB 32 DUP (0)

.CODE


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

;------------------------------------------------------------------------------
; Read ini file for lua setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionLua PROC
    IFDEF EEEX_LUALIB
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionLua, gEEexLua, Addr EEexIniFile
    ELSE
    mov eax, FALSE
    ENDIF
    ret
IniGetOptionLua ENDP

;------------------------------------------------------------------------------
; Read ini file for hex setting from [Option] section
;------------------------------------------------------------------------------
IniGetOptionHex PROC
    Invoke GetPrivateProfileInt, Addr szIniEEexOptions, Addr szIniOptionHex, gEEexHex, Addr EEexIniFile
    ret
IniGetOptionHex ENDP


;==============================================================================
; [EEex] section ini functions for reading and writing EE game addresses 
;==============================================================================
;------------------------------------------------------------------------------
; Read ini file for EntryPoint for CodeCave jmp location
;------------------------------------------------------------------------------
IniGetPatchLocation PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniPatchLocation, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniPatchLocation, 0
    .ENDIF
    ret
IniGetPatchLocation ENDP

;------------------------------------------------------------------------------
; Write EntryPoint for CodeCave jmp to ini file
;------------------------------------------------------------------------------
IniSetPatchLocation PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniPatchLocation, dwValue
    ret
IniSetPatchLocation ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_createtable function location
;------------------------------------------------------------------------------
IniGetLua_createtable PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_createtable, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_createtable, 0
    .ENDIF
    ret
IniGetLua_createtable ENDP

;------------------------------------------------------------------------------
; Write Lua_createtable function location to ini file
;------------------------------------------------------------------------------
IniSetLua_createtable PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_createtable, dwValue
    ret
IniSetLua_createtable ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_getglobal function location
;------------------------------------------------------------------------------
IniGetLua_getglobal PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_getglobal, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_getglobal, 0
    .ENDIF
    ret
IniGetLua_getglobal ENDP

;------------------------------------------------------------------------------
; Write Lua_getglobal function location to ini file
;------------------------------------------------------------------------------
IniSetLua_getglobal PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_getglobal, dwValue
    ret
IniSetLua_getglobal ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_gettop function location
;------------------------------------------------------------------------------
IniGetLua_gettop PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_gettop, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_gettop, 0
    .ENDIF
    ret
IniGetLua_gettop ENDP

;------------------------------------------------------------------------------
; Write Lua_gettop function location to ini file
;------------------------------------------------------------------------------
IniSetLua_gettop PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_gettop, dwValue
    ret
IniSetLua_gettop ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_pcallk function location
;------------------------------------------------------------------------------
IniGetLua_pcallk PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_pcallk, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_pcallk, 0
    .ENDIF
    ret
IniGetLua_pcallk ENDP

;------------------------------------------------------------------------------
; Write Lua_pcallk function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pcallk PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_pcallk, dwValue
    ret
IniSetLua_pcallk ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_pushcclosure function location
;------------------------------------------------------------------------------
IniGetLua_pushcclosure PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_pushcclosure, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_pushcclosure, 0
    .ENDIF
    ret
IniGetLua_pushcclosure ENDP

;------------------------------------------------------------------------------
; Write Lua_pushcclosure function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushcclosure PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_pushcclosure, dwValue
    ret
IniSetLua_pushcclosure ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_pushlightuserdata function location
;------------------------------------------------------------------------------
IniGetLua_pushlightuserdata PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_pushlightuserdata, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_pushlightuserdata, 0
    .ENDIF
    ret
IniGetLua_pushlightuserdata ENDP

;------------------------------------------------------------------------------
; Write Lua_pushlightuserdata function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushlightuserdata PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_pushlightuserdata, dwValue
    ret
IniSetLua_pushlightuserdata ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_pushlstring function location
;------------------------------------------------------------------------------
IniGetLua_pushlstring PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_pushlstring, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_pushlstring, 0
    .ENDIF
    ret
IniGetLua_pushlstring ENDP

;------------------------------------------------------------------------------
; Write Lua_pushlstring function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushlstring PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_pushlstring, dwValue
    ret
IniSetLua_pushlstring ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_pushnumber function location function location
;------------------------------------------------------------------------------
IniGetLua_pushnumber PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_pushnumber, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_pushnumber, 0
    .ENDIF
    ret
IniGetLua_pushnumber ENDP

;------------------------------------------------------------------------------
; Write Lua_pushnumber function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushnumber PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_pushnumber, dwValue
    ret
IniSetLua_pushnumber ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_pushstring function location
;------------------------------------------------------------------------------
IniGetLua_pushstring PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_pushstring, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_pushstring, 0
    .ENDIF
    ret
IniGetLua_pushstring ENDP

;------------------------------------------------------------------------------
; Write Lua_pushstring function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushstring PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_pushstring, dwValue
    ret
IniSetLua_pushstring ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_rawgeti function location
;------------------------------------------------------------------------------
IniGetLua_rawgeti PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_rawgeti, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_rawgeti, 0
    .ENDIF
    ret
IniGetLua_rawgeti ENDP

;------------------------------------------------------------------------------
; Write Lua_rawgeti function location to ini file
;------------------------------------------------------------------------------
IniSetLua_rawgeti PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_rawgeti, dwValue
    ret
IniSetLua_rawgeti ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_rawlen function location
;------------------------------------------------------------------------------
IniGetLua_rawlen PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_rawlen, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_rawlen, 0
    .ENDIF
    ret
IniGetLua_rawlen ENDP

;------------------------------------------------------------------------------
; Write Lua_rawlen function location to ini file
;------------------------------------------------------------------------------
IniSetLua_rawlen PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_rawlen, dwValue
    ret
IniSetLua_rawlen ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_setfield function location
;------------------------------------------------------------------------------
IniGetLua_setfield PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_setfield, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_setfield, 0
    .ENDIF
    ret
IniGetLua_setfield ENDP

;------------------------------------------------------------------------------
; Write Lua_setfield function location to ini file
;------------------------------------------------------------------------------
IniSetLua_setfield PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_setfield, dwValue
    ret
IniSetLua_setfield ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_setglobal function location
;------------------------------------------------------------------------------
IniGetLua_setglobal PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_setglobal, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_setglobal, 0
    .ENDIF
    ret
IniGetLua_setglobal ENDP

;------------------------------------------------------------------------------
; Write Lua_setglobal function location to ini file
;------------------------------------------------------------------------------
IniSetLua_setglobal PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_setglobal, dwValue
    ret
IniSetLua_setglobal ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_settable function location
;------------------------------------------------------------------------------
IniGetLua_settable PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_settable, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_settable, 0
    .ENDIF
    ret
IniGetLua_settable ENDP

;------------------------------------------------------------------------------
; Write Lua_settable function location to ini file
;------------------------------------------------------------------------------
IniSetLua_settable PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_settable, dwValue
    ret
IniSetLua_settable ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_settop function location
;------------------------------------------------------------------------------
IniGetLua_settop PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_settop, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_settop, 0
    .ENDIF
    ret
IniGetLua_settop ENDP

;------------------------------------------------------------------------------
; Write Lua_settop function location to ini file
;------------------------------------------------------------------------------
IniSetLua_settop PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_settop, dwValue
    ret
IniSetLua_settop ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_toboolean function location
;------------------------------------------------------------------------------
IniGetLua_toboolean PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_toboolean, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_toboolean, 0
    .ENDIF
    ret
IniGetLua_toboolean ENDP

;------------------------------------------------------------------------------
; Write Lua_toboolean function location to ini file
;------------------------------------------------------------------------------
IniSetLua_toboolean PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_toboolean, dwValue
    ret
IniSetLua_toboolean ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_tolstring function location
;------------------------------------------------------------------------------
IniGetLua_tolstring PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_tolstring, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_tolstring, 0
    .ENDIF
    ret
IniGetLua_tolstring ENDP

;------------------------------------------------------------------------------
; Write Lua_tolstring function location to ini file
;------------------------------------------------------------------------------
IniSetLua_tolstring PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_tolstring, dwValue
    ret
IniSetLua_tolstring ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_tonumberx function location
;------------------------------------------------------------------------------
IniGetLua_tonumberx PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_tonumberx, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_tonumberx, 0
    .ENDIF
    ret
IniGetLua_tonumberx ENDP

;------------------------------------------------------------------------------
; Write Lua_tonumberx function location to ini file
;------------------------------------------------------------------------------
IniSetLua_tonumberx PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_tonumberx, dwValue
    ret
IniSetLua_tonumberx ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_touserdata function location
;------------------------------------------------------------------------------
IniGetLua_touserdata PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_touserdata, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_touserdata, 0
    .ENDIF
    ret
IniGetLua_touserdata ENDP

;------------------------------------------------------------------------------
; Write Lua_touserdata function location to ini file
;------------------------------------------------------------------------------
IniSetLua_touserdata PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_touserdata, dwValue
    ret
IniSetLua_touserdata ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_type function location
;------------------------------------------------------------------------------
IniGetLua_type PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_type, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_type, 0
    .ENDIF
    ret
IniGetLua_type ENDP

;------------------------------------------------------------------------------
; Write Lua_type function location to ini file
;------------------------------------------------------------------------------
IniSetLua_type PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_type, dwValue
    ret
IniSetLua_type ENDP

;------------------------------------------------------------------------------
; Read ini file for Lua_typename function location
;------------------------------------------------------------------------------
IniGetLua_typename PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLua_typename, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLua_typename, 0
    .ENDIF
    ret
IniGetLua_typename ENDP

;------------------------------------------------------------------------------
; Write Lua_typename function location to ini file
;------------------------------------------------------------------------------
IniSetLua_typename PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLua_typename, dwValue
    ret
IniSetLua_typename ENDP

;------------------------------------------------------------------------------
; Read ini file for LuaL_loadstring function location
;------------------------------------------------------------------------------
IniGetLuaL_loadstring PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIniLuaL_loadstring, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIniLuaL_loadstring, 0
    .ENDIF
    ret
IniGetLuaL_loadstring ENDP

;------------------------------------------------------------------------------
; Write LuaL_loadstring function location to ini file
;------------------------------------------------------------------------------
IniSetLuaL_loadstring PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIniLuaL_loadstring, dwValue
    ret
IniSetLuaL_loadstring ENDP

;------------------------------------------------------------------------------
; Read ini file for _ftol2_sse function location
;------------------------------------------------------------------------------
IniGetftol2_sse PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIni_ftol2_sse, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIni_ftol2_sse, 0
    .ENDIF
    ret
IniGetftol2_sse ENDP

;------------------------------------------------------------------------------
; Write _ftol2_sse function location to ini file
;------------------------------------------------------------------------------
IniSetftol2_sse PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIni_ftol2_sse, dwValue
    ret
IniSetftol2_sse ENDP




;==============================================================================
; [EEex] section ini functions for reading and writing EE game globals
;==============================================================================
;------------------------------------------------------------------------------
; Read ini file for pp_pChitin pattern address location for p_pChitin
;------------------------------------------------------------------------------
IniGet_pp_pChitin PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIni_pp_pChitin, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIni_pp_pChitin, 0
    .ENDIF
    ret
IniGet_pp_pChitin ENDP

;------------------------------------------------------------------------------
; Write pp_pChitin pattern address location to ini file
;------------------------------------------------------------------------------
IniSet_pp_pChitin PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIni_pp_pChitin, dwValue
    ret
IniSet_pp_pChitin ENDP

;------------------------------------------------------------------------------
; Read ini file for pp_pBaldurChitin pattern address location for p_pBaldurChitin
;------------------------------------------------------------------------------
IniGet_pp_pBaldurChitin PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIni_pp_pBaldurChitin, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIni_pp_pBaldurChitin, 0
    .ENDIF
    ret
IniGet_pp_pBaldurChitin ENDP

;------------------------------------------------------------------------------
; Write pp_pBaldurChitin pattern address location to ini file
;------------------------------------------------------------------------------
IniSet_pp_pBaldurChitin PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIni_pp_pBaldurChitin, dwValue
    ret
IniSet_pp_pBaldurChitin ENDP

;------------------------------------------------------------------------------
; Read ini file for pp_backgroundMenu pattern address location for p_backgroundMenu
;------------------------------------------------------------------------------
IniGet_pp_backgroundMenu PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIni_pp_backgroundMenu, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIni_pp_backgroundMenu, 0
    .ENDIF
    ret
IniGet_pp_backgroundMenu ENDP

;------------------------------------------------------------------------------
; Write pp_backgroundMenu pattern address location to ini file
;------------------------------------------------------------------------------
IniSet_pp_backgroundMenu PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIni_pp_backgroundMenu, dwValue
    ret
IniSet_pp_backgroundMenu ENDP

;------------------------------------------------------------------------------
; Read ini file for pp_overlayMenu pattern address location for p_overlayMenu
;------------------------------------------------------------------------------
IniGet_pp_overlayMenu PROC bFallback:DWORD
    .IF bFallback == TRUE
        Invoke IniReadValue, Addr szIniEEexFallback, Addr szIni_pp_overlayMenu, 0
    .ELSE
        Invoke IniReadValue, Addr szIniEEex, Addr szIni_pp_overlayMenu, 0
    .ENDIF
    ret
IniGet_pp_overlayMenu ENDP

;------------------------------------------------------------------------------
; Write pp_overlayMenu pattern address location to ini file
;------------------------------------------------------------------------------
IniSet_pp_overlayMenu PROC dwValue:DWORD
    Invoke IniWriteValue, Addr szIniEEex, Addr szIni_pp_overlayMenu, dwValue
    ret
IniSet_pp_overlayMenu ENDP







