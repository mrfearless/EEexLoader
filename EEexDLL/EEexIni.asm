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
IniGetPatchLocation     PROTO
IniSetPatchLocation     PROTO :DWORD

IniGetLua_pushclosure   PROTO
IniSetLua_pushclosure   PROTO :DWORD
IniGetLua_pushnumber    PROTO
IniSetLua_pushnumber    PROTO :DWORD
IniGetLua_setglobal     PROTO
IniSetLua_setglobal     PROTO :DWORD
IniGetLua_tolstring     PROTO
IniSetLua_tolstring     PROTO :DWORD
IniGetLua_tonumberx     PROTO
IniSetLua_tonumberx     PROTO :DWORD
IniGetLuaL_loadstring   PROTO
IniSetLuaL_loadstring   PROTO :DWORD
IniGetftol2_sse         PROTO
IniSetftol2_sse         PROTO :DWORD

IniValueToString        TEXTEQU <EEexDwordToAscii> ; EEexDwordToAscii is in EEex.asm


.DATA
szIni                   DB "ini",0
szIniEEex               DB "EEex",0
szIniValueZero          DB "0",0
szIniPatchLocation      DB "PatchLocation",0
szIniLuaL_loadstring    DB "LuaL_loadstring",0
szIniLua_pushnumber     DB "Lua_pushnumber",0
szIniLua_pushclosure    DB "Lua_pushclosure",0
szIniLua_tolstring      DB "Lua_tolstring",0
szIniLua_setglobal      DB "Lua_setglobal",0
szIniLua_tonumberx      DB "Lua_tonumberx",0
szIniftol2_sse          DB "ftol2_sse",0

szIniValueString        DB 32 DUP (0)


.CODE


;------------------------------------------------------------------------------
; Read ini file for EntryPoint for CodeCave jmp location
;------------------------------------------------------------------------------
IniGetPatchLocation PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniPatchLocation, 0, Addr EEexIniFile
    ret
IniGetPatchLocation ENDP


;------------------------------------------------------------------------------
; Write EntryPoint for CodeCave jmp to ini file
;------------------------------------------------------------------------------
IniSetPatchLocation PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniPatchLocation, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniPatchLocation, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetPatchLocation ENDP


;------------------------------------------------------------------------------
; Read ini file for LuaL_loadstring function location
;------------------------------------------------------------------------------
IniGetLuaL_loadstring PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniLuaL_loadstring, 0, Addr EEexIniFile
    ret
IniGetLuaL_loadstring ENDP


;------------------------------------------------------------------------------
; Write LuaL_loadstring function location to ini file
;------------------------------------------------------------------------------
IniSetLuaL_loadstring PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLuaL_loadstring, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLuaL_loadstring, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetLuaL_loadstring ENDP


;------------------------------------------------------------------------------
; Read ini file for Lua_pushnumber function location
;------------------------------------------------------------------------------
IniGetLua_pushnumber PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniLua_pushnumber, 0, Addr EEexIniFile
    ret
IniGetLua_pushnumber ENDP


;------------------------------------------------------------------------------
; Write Lua_pushnumber function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushnumber PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_pushnumber, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_pushnumber, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetLua_pushnumber ENDP


;------------------------------------------------------------------------------
; Read ini file for Lua_pushclosure function location
;------------------------------------------------------------------------------
IniGetLua_pushclosure PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniLua_pushclosure, 0, Addr EEexIniFile
    ret
IniGetLua_pushclosure ENDP


;------------------------------------------------------------------------------
; Write Lua_pushclosure function location to ini file
;------------------------------------------------------------------------------
IniSetLua_pushclosure PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_pushclosure, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_pushclosure, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetLua_pushclosure ENDP


;------------------------------------------------------------------------------
; Read ini file for Lua_tolstring function location
;------------------------------------------------------------------------------
IniGetLua_tolstring PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniLua_tolstring, 0, Addr EEexIniFile
    ret
IniGetLua_tolstring ENDP


;------------------------------------------------------------------------------
; Write Lua_tolstring function location to ini file
;------------------------------------------------------------------------------
IniSetLua_tolstring PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_tolstring, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_tolstring, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetLua_tolstring ENDP


;------------------------------------------------------------------------------
; Read ini file for Lua_setglobal function location
;------------------------------------------------------------------------------
IniGetLua_setglobal PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniLua_setglobal, 0, Addr EEexIniFile
    ret
IniGetLua_setglobal ENDP


;------------------------------------------------------------------------------
; Write Lua_setglobal function location to ini file
;------------------------------------------------------------------------------
IniSetLua_setglobal PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_setglobal, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_setglobal, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetLua_setglobal ENDP


;------------------------------------------------------------------------------
; Read ini file for Lua_tonumberx function location
;------------------------------------------------------------------------------
IniGetLua_tonumberx PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniLua_tonumberx, 0, Addr EEexIniFile
    ret
IniGetLua_tonumberx ENDP


;------------------------------------------------------------------------------
; Write Lua_tonumberx function location to ini file
;------------------------------------------------------------------------------
IniSetLua_tonumberx PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_tonumberx, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniLua_tonumberx, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetLua_tonumberx ENDP


;------------------------------------------------------------------------------
; Read ini file for _ftol2_sse function location
;------------------------------------------------------------------------------
IniGetftol2_sse PROC
    Invoke GetPrivateProfileInt, Addr szIniEEex, Addr szIniftol2_sse, 0, Addr EEexIniFile
    ret
IniGetftol2_sse ENDP


;------------------------------------------------------------------------------
; Write _ftol2_sse function location to ini file
;------------------------------------------------------------------------------
IniSetftol2_sse PROC dwValue:DWORD
    .IF dwValue == 0
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniftol2_sse, Addr szIniValueZero, Addr EEexIniFile
    .ELSE
        Invoke IniValueToString, dwValue, Addr szIniValueString
        Invoke WritePrivateProfileString, Addr szIniEEex, Addr szIniftol2_sse, Addr szIniValueString, Addr EEexIniFile
    .ENDIF
    ret
IniSetftol2_sse ENDP














