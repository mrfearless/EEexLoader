;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------

EEEX_LOGLUACALLS        EQU 1 ; comment out to disable logging of the lua calls

;------------------------------------------------------------------------------
; Devnote: Static lua lib functions that dont work/crash:
; luaL_loadstring, lua_setglobal
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; EEexLua Prototypes
;------------------------------------------------------------------------------
EEexLuaInit             PROTO C :DWORD, :DWORD  ; (lua_State), lpszString
EEexLuaRegisterFunction PROTO   :DWORD, :DWORD  ; lpFuncAddress, lpszFuncName

;------------------------------------------------------------------------------
; LUA Function Prototypes
;------------------------------------------------------------------------------
EEex_Init               PROTO C :VARARG         ; (lua_State)
EEex_WriteByte          PROTO C :VARARG         ; (lua_State), Address, Byte
EEex_ExposeToLua        PROTO C :VARARG         ; (lua_State), FunctionAddress, FunctionName

EEex_LuaFunctions       PROTO C :DWORD          ; (lua_State)
EEex_GameFunctions      PROTO C :DWORD          ; (lua_State)
EEex_GameGlobals        PROTO C :DWORD          ; (lua_State)

IFDEF EEEX_LUALIB       ; use this internal one rather than static version as it crashes
lua_setglobalx          PROTO C :DWORD, :DWORD  ; (lua_State), Name
ENDIF


.CONST
IFDEF EEEX_LOGLUACALLS
EEEX_WRITEBYTE_LOGCOUNT EQU 2048                ; logs EEex_WriteByte every x calls
ENDIF

.DATA
szEEex_Init             DB "EEex_Init",0        
szEEex_WriteByte        DB "EEex_WriteByte",0   
szEEex_ExposeToLua      DB "EEex_ExposeToLua",0 
szEEex_LuaFunctions     DB "EEex_LuaFunctions",0
szEEex_GameFunctions    DB "EEex_GameFunctions",0
szEEex_GameGlobals      DB "EEex_GameGlobals",0


IFDEF EEEX_LOGLUACALLS
EEex_WriteByte_Count    DD 0
ENDIF


.CODE


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLuaInit: Initialize EEex for the EE Game
; Registers EEex_Init LUA Function and retrieves g_lua variable from p_lua
;
; Execution in EE Game is redirected to this function at PatchAddress when
; EEex.DLL is loaded by EE Game (via injection by EEex.exe loader) and applies
; the patch during EEExInitDll (EEexApplyCallPatch)
;
; call XXXEEgame:luaL_loadstring replaced with call EEex.dll:EEexLuaInit
; Devnote: This function must be PROTO C
;------------------------------------------------------------------------------
EEexLuaInit PROC C lua_State:DWORD, lpszString:DWORD
    
    ;---------------------------
    ; Get EE game globals from 
    ; pointers. Some globals are 
    ; not available at main menu
    ; only once game starts.
    ;---------------------------
    mov eax, p_lua
    .IF eax != 0
        mov eax, [eax]
        mov g_lua, eax
    .ENDIF    
    mov eax, p_pChitin
    .IF eax != 0
        mov eax, [eax]
        mov g_pChitin, eax
    .ENDIF
    mov eax, p_pBaldurChitin
    .IF eax != 0
        mov eax, [eax]
        mov g_pBaldurChitin, eax
    .ENDIF
    mov eax, p_backgroundMenu
    .IF eax != 0
        mov eax, [eax]
        mov g_backgroundMenu, eax
    .ENDIF
    mov eax, p_overlayMenu
    .IF eax != 0
        mov eax, [eax]
        mov g_overlayMenu, eax
    .ENDIF    
    
    ;---------------------------
    ; For prototype of no params
    ;---------------------------
    mov eax, Func_Lua_createtable
    mov Func_Lua_createtablex, eax
    
    IFDEF EEEX_LOGGING
    ;---------------------------
    ; Log some EE game globals
    ;---------------------------
    Invoke LogMessage, CTEXT("EEexLuaInit:"), LOG_INFO, 0
    
    Invoke LogMessage, CTEXT("p_lua"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, p_lua
    Invoke LogMessage, CTEXT("g_lua"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, g_lua    
    Invoke LogMessage, CTEXT("p_pChitin"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, p_pChitin
    Invoke LogMessage, CTEXT("g_pChitin"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, g_pChitin
    Invoke LogMessage, CTEXT("p_pBaldurChitin"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, p_pBaldurChitin
    Invoke LogMessage, CTEXT("g_pBaldurChitin"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, g_pBaldurChitin
    Invoke LogMessage, CTEXT("p_backgroundMenu"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, p_backgroundMenu
    Invoke LogMessage, CTEXT("g_backgroundMenu"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, g_backgroundMenu
    Invoke LogMessage, CTEXT("p_overlayMenu"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, p_overlayMenu
    Invoke LogMessage, CTEXT("g_overlayMenu"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, g_overlayMenu    
    ENDIF
    
    ;---------------------------
    ; Register the Lua EEex_Init
    ;---------------------------
    Invoke EEexLuaRegisterFunction, Addr EEex_Init, Addr szEEex_Init
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_Init"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_Init    
    ;Invoke LogMessage, CTEXT("Register Function: EEex_Init"), LOG_STANDARD, 1
    ENDIF
    Invoke Func_LuaL_loadstring, lua_State, lpszString ; EE lua function
    ret
EEexLuaInit ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLuaRegisterFunction: Registers LUA Functions in EE Game
; Devnote: This function is PROTO STDCALL
;------------------------------------------------------------------------------
EEexLuaRegisterFunction PROC lpFunctionAddress:DWORD, lpszFunctionName:DWORD
    Invoke Func_Lua_pushcclosure, g_lua, lpFunctionAddress, 0
    Invoke Func_Lua_setglobal, g_lua, lpszFunctionName
    ret
EEexLuaRegisterFunction ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_Init: Registers LUA Functions and allocates global memory for EEex
; 
; EEex_Init()
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
EEex_Init PROC C arg:VARARG
    push ebp
    mov ebp, esp
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("EEex_Init:"), LOG_INFO, 0
    ENDIF
    
    Invoke EEexLuaRegisterFunction, Addr EEex_WriteByte, Addr szEEex_WriteByte
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_WriteByte"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_WriteByte
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_ExposeToLua, Addr szEEex_ExposeToLua
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_ExposeToLua"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_ExposeToLua
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_LuaFunctions, Addr szEEex_LuaFunctions
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_LuaFunctions"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_LuaFunctions
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_GameFunctions, Addr szEEex_GameFunctions
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_GameFunctions"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_GameFunctions
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_GameGlobals, Addr szEEex_GameGlobals
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_GameGlobals"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_GameGlobals
    ENDIF
    
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("VirtualAlloc 4096 bytes"), LOG_INFO, 0
    IFDEF EEEX_LOGLUACALLS
    Invoke LogMessage, CTEXT("EEex Lua Functions: "), LOG_INFO, 0
    ENDIF
    ENDIF
    
    Invoke VirtualAlloc, 0, 1000h, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE
    push eax
    fild dword ptr [esp]
    sub esp, 4h
    fstp qword ptr [esp]
    push dword ptr [ebp+8h]
    call Func_Lua_pushnumber
    add esp,0Ch
    mov eax,1h
    pop ebp
    ret
EEex_Init ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_WriteByte: Writes byte at address
;
; EEex_WriteByte(Address, Byte)
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
EEex_WriteByte PROC C arg:VARARG
    push ebp
    mov ebp, esp
    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    .IF EEex_WriteByte_Count == 0
        Invoke LogMessage, CTEXT("EEex_WriteByte"), LOG_STANDARD, 1
    .ENDIF
    inc EEex_WriteByte_Count
    mov eax, EEex_WriteByte_Count
    .IF eax >= EEEX_WRITEBYTE_LOGCOUNT
        mov EEex_WriteByte_Count, 0
    .ENDIF
    ENDIF
    ENDIF
    push 0h
    push 1h
    push dword ptr [ebp+8h]
    call Func_Lua_tonumberx
    add esp, 0Ch
    call Func__ftol2_sse
    mov edi, eax
    push 0h
    push 2h
    push dword ptr [ebp+8h]
    call Func_Lua_tonumberx
    add esp, 0Ch
    call Func__ftol2_sse
    mov byte ptr [edi], al
    mov eax, 0h
    pop ebp
    ret 
EEex_WriteByte ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_ExposeToLua: Expose EE Internal Function to LUA
;
; EEex_ExposeToLua(FunctionAddress, FunctionName)
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
EEex_ExposeToLua PROC C arg:VARARG
    push ebp
    mov ebp, esp
    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    Invoke LogMessage, CTEXT("EEex_ExposeToLua"), LOG_STANDARD, 1
    ENDIF
    ENDIF    
    push 0h
    push 1h
    push dword ptr [ebp+8h]
    call Func_Lua_tonumberx
    add esp, 0Ch
    call Func__ftol2_sse
    push 0h
    push eax
    push dword ptr [g_lua]
    call Func_Lua_pushcclosure
    add esp, 0Ch
    push 0h
    push 2h
    push dword ptr [ebp+8h]
    call Func_Lua_tolstring
    add esp, 0Ch
    push eax
    push dword ptr [g_lua]
    call Func_Lua_setglobal
    add esp, 8h
    mov eax, 0h
    pop ebp
    ret 
EEex_ExposeToLua ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef


;------------------------------------------------------------------------------
; [LUA] lua_setglobalx: Alternative version of lua_setglobal
;
; lua_setglobalx(luastate, name)
;------------------------------------------------------------------------------
IFDEF EEEX_LUALIB
EEEX_ALIGN
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
lua_setglobalx PROC C USES EBX ESI lua_State:DWORD, lpname:DWORD
    push ebp
    mov ebp,esp
    push ebx
    push esi
    mov esi, lua_State
    mov edx,2h
    push edi
    mov eax,dword ptr [esi+0Ch]
    mov ecx,dword ptr [eax+28h]
    call luaH_getint
    mov edi,dword ptr [esi+8h]
    mov ebx,eax
    mov edx, dword ptr [lpname]
    lea ecx,dword ptr [edi+8h]
    mov dword ptr [esi+8h],ecx
    mov ecx,edx
    lea eax,dword ptr [ecx+1h]
    mov [lua_State], eax
    nop 
    
LABEL_1:
    mov al,byte ptr [ecx]
    inc ecx
    test al,al
    jne LABEL_1
    sub ecx, lua_State
    push ecx
    mov ecx,esi
    call luaS_newlstr
    mov dword ptr [edi],eax
    mov edx,ebx
    movzx eax,byte ptr [eax+4h]
    or eax,7FF7A540h
    mov dword ptr [edi+4h],eax
    mov ecx,dword ptr [esi+8h]
    lea eax,dword ptr [ecx-10h]
    push eax
    lea eax,dword ptr [ecx-8h]
    mov ecx,esi
    push eax
    call luaV_settable
    add esp,0Ch
    add dword ptr [esi+8h],0FFFFFFF0h
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret     
lua_setglobalx ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef
ENDIF


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_LuaFunctions: Return a table of EE lua function addresses
;
; EEex_LuaFunctions()
;------------------------------------------------------------------------------
EEex_LuaFunctions PROC C lua_State:DWORD

    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    Invoke LogMessage, CTEXT("EEex_LuaFunctions"), LOG_STANDARD, 1
    ENDIF
    ENDIF

    Invoke Func_Lua_createtablex, lua_State
    
    Invoke Func_Lua_pushnumber, lua_State, PatchLocation
    Invoke Func_Lua_pushstring, lua_State, CTEXT("PatchLocation")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_createtable
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_createtable")
    Invoke Func_Lua_settable, lua_State, -3  
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_getglobal
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_getglobal")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_gettop
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_gettop")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_pcallk
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_pcallk")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_pushcclosure
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_pushcclosure")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_pushlightuserdata
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_pushlightuserdata")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_pushlstring
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_pushlstring")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_pushnumber
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_pushnumber")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_pushstring
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_pushstring")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_rawgeti
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_rawgeti")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_rawlen
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_rawlen")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_setfield
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_setfield")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_setglobal
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lLua_setglobal")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_settable
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_settable")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_settop
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_settop")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_toboolean
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_toboolean")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_tolstring
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_tolstring")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_tonumberx
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_tonumberx")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_touserdata
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_touserdata")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_type
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_type")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_Lua_typename
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_lua_typename")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func_LuaL_loadstring
    Invoke Func_Lua_pushstring, lua_State, CTEXT("_luaL_loadstring")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, Func__ftol2_sse
    Invoke Func_Lua_pushstring, lua_State, CTEXT("__ftol2_sse")
    Invoke Func_Lua_settable, lua_State, -3

    mov eax, 1
    ret
EEex_LuaFunctions ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_GameFunctions: Return a table of EE game function addresses
;
; EEex_GameFunctions()
;------------------------------------------------------------------------------
EEex_GameFunctions PROC C lua_State:DWORD
    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    Invoke LogMessage, CTEXT("EEex_GameFunctions"), LOG_STANDARD, 1
    ENDIF
    ENDIF
    
    Invoke Func_Lua_createtablex, lua_State
    
    ; placeholder, put actual game functions here
    Invoke Func_Lua_pushnumber, lua_State, PatchLocation
    Invoke Func_Lua_pushstring, lua_State, CTEXT("PatchLocation")
    Invoke Func_Lua_settable, lua_State, -3    
    
    mov eax, 1
    ret
EEex_GameFunctions ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_GameGlobals: Return a table of EE game global addresses and values
;
; EEex_GameGlobals()
;------------------------------------------------------------------------------
EEex_GameGlobals PROC C lua_State:DWORD
    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    Invoke LogMessage, CTEXT("EEex_GameGlobals"), LOG_STANDARD, 1
    ENDIF
    ENDIF

    Invoke Func_Lua_createtablex, lua_State

    Invoke Func_Lua_pushnumber, lua_State, p_lua
    Invoke Func_Lua_pushstring, lua_State, CTEXT("p_lua")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, g_lua
    Invoke Func_Lua_pushstring, lua_State, CTEXT("g_lua")
    Invoke Func_Lua_settable, lua_State, -3
    
    Invoke Func_Lua_pushnumber, lua_State, p_pChitin
    Invoke Func_Lua_pushstring, lua_State, CTEXT("p_pChitin")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, g_pChitin
    Invoke Func_Lua_pushstring, lua_State, CTEXT("g_pChitin")
    Invoke Func_Lua_settable, lua_State, -3
    
    Invoke Func_Lua_pushnumber, lua_State, p_pBaldurChitin
    Invoke Func_Lua_pushstring, lua_State, CTEXT("p_pBaldurChitin")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, g_pBaldurChitin
    Invoke Func_Lua_pushstring, lua_State, CTEXT("g_pBaldurChitin")
    Invoke Func_Lua_settable, lua_State, -3
    
    Invoke Func_Lua_pushnumber, lua_State, p_backgroundMenu
    Invoke Func_Lua_pushstring, lua_State, CTEXT("p_backgroundMenu")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, g_backgroundMenu
    Invoke Func_Lua_pushstring, lua_State, CTEXT("g_backgroundMenu")
    Invoke Func_Lua_settable, lua_State, -3
    
    Invoke Func_Lua_pushnumber, lua_State, p_overlayMenu
    Invoke Func_Lua_pushstring, lua_State, CTEXT("p_overlayMenu")
    Invoke Func_Lua_settable, lua_State, -3
    Invoke Func_Lua_pushnumber, lua_State, g_overlayMenu
    Invoke Func_Lua_pushstring, lua_State, CTEXT("g_overlayMenu")
    Invoke Func_Lua_settable, lua_State, -3
    
    mov eax, 1
    ret
EEex_GameGlobals ENDP












