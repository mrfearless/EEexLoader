;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; EEexLua Prototypes
;------------------------------------------------------------------------------
EEexLuaInit             PROTO C :DWORD, :DWORD  ; LuaState, lpszString
EEexLuaRegisterFunction PROTO   :DWORD, :DWORD  ; lpFuncAddress, lpszFuncName

;------------------------------------------------------------------------------
; LUA Function Prototypes
;------------------------------------------------------------------------------
EEex_Init               PROTO C :VARARG         ; void
EEex_WriteByte          PROTO C :VARARG         ; Address, Byte
EEex_ExposeToLua        PROTO C :VARARG         ; FunctionAddress, FunctionName


.DATA
szEEex_Init             DB "EEex_Init",0        ; string for function name
szEEex_WriteByte        DB "EEex_WriteByte",0   ; string for function name
szEEex_ExposeToLua      DB "EEex_ExposeToLua",0 ; string for function name

p_lua                   DD 0 ; pointer to global lua variable
g_lua                   DD 0 ; actual content of global lua variable


.CODE


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
EEexLuaInit PROC C LuaState:DWORD, lpszString:DWORD
    mov eax, p_lua
    mov eax, [eax]
    mov g_lua, eax
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("EEexLuaInit:"), LOG_INFO, 0
    Invoke LogMessage, CTEXT("g_lua"), LOG_NONEWLINE, 1
    Invoke LogMessageAndValue, 0, g_lua
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_Init, Addr szEEex_Init
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function: EEex_Init"), LOG_STANDARD, 1
    ENDIF
    Invoke Func_LuaL_loadstring, LuaState, lpszString
    ret
EEexLuaInit ENDP


;------------------------------------------------------------------------------
; EEexLuaRegisterFunction: Registers LUA Functions in EE Game
; Devnote: This function is PROTO STDCALL
;------------------------------------------------------------------------------
EEexLuaRegisterFunction PROC lpFunctionAddress:DWORD, lpszFunctionName:DWORD
    Invoke Func_Lua_pushclosure, g_lua, lpFunctionAddress, 0
    Invoke Func_Lua_setglobal, g_lua, lpszFunctionName
    ret
EEexLuaRegisterFunction ENDP


;------------------------------------------------------------------------------
; [LUA] EEex_Init: Registers LUA Functions and allocates global memory for EEex
; 
; EEex_Init()
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
ALIGN 16
EEex_Init PROC C arg:VARARG
    push ebp
    mov ebp, esp
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("EEex_Init:"), LOG_INFO, 0
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_WriteByte, Addr szEEex_WriteByte
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function: EEex_WriteByte"), LOG_STANDARD, 1
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_ExposeToLua, Addr szEEex_ExposeToLua
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function: EEex_ExposeToLua"), LOG_STANDARD, 1
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


;------------------------------------------------------------------------------
; [LUA] EEex_WriteByte: Writes byte at address
;
; EEex_WriteByte(Address, Byte)
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
ALIGN 16
EEex_WriteByte PROC C arg:VARARG
    push ebp
    mov ebp, esp
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


;------------------------------------------------------------------------------
; [LUA] EEex_ExposeToLua: Expose EE Internal Function to LUA
;
; EEex_ExposeToLua(FunctionAddress, FunctionName)
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
ALIGN 16
EEex_ExposeToLua PROC C arg:VARARG
    push ebp
    mov ebp, esp
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("EEex_ExposeToLua"), LOG_STANDARD, 0
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
    call Func_Lua_pushclosure
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










