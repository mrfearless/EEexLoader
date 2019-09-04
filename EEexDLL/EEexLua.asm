;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------

EEEX_LOGLUACALLS        EQU 1 ; comment out to disable logging of the lua calls
                              ; requires gEEexLog >= LOGLEVEL_DEBUG if using
                              
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
EEex_Call               PROTO C :VARARG         ; (lua_State)

EEex_AddressList        PROTO C :DWORD          ; (lua_State)
;EEex_ReadDWORD          PROTO C :DWORD, :DWORD  ; (lua_State), dwAddress

IFDEF EEEX_LUALIB       ; use this internal one rather than static version as it crashes
lua_setglobalx          PROTO C :DWORD, :DWORD  ; (lua_State), Name
ENDIF



;------------------------------------------------------------------------------
; EEexLua Structures
;------------------------------------------------------------------------------
ALENTRY                 STRUCT ; Address List entry for pAddressList array
    lpszName            DD 0
    dwAddress           DD 0
ALENTRY                 ENDS


.CONST
IFDEF EEEX_LOGLUACALLS
EEEX_WRITEBYTE_LOGCOUNT EQU 2048                ; logs EEex_WriteByte every x calls
ENDIF

.DATA
szEEex_Init             DB "EEex_Init",0        
szEEex_WriteByte        DB "EEex_WriteByte",0   
szEEex_ExposeToLua      DB "EEex_ExposeToLua",0
szEEex_Call             DB "EEex_Call",0
szEEex_AddressList      DB "EEex_AddressList",0
;szEEex_ReadDWORD        DB "EEex_ReadDWORD",0

pAddressList            DD 0 ; points to array of ALENTRY entries x TotalPatterns 

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

    IFDEF DEBUG32
    PrintText 'EEexLuaInit'
    ENDIF

    ; Get g_lua from p_lua whilst game is running
    ; g_lua is used in lua function calls in EEexLua.asm
    mov eax, p_lua
    .IF eax != 0
        mov eax, [eax]
        mov g_lua, eax
        IFDEF DEBUG32
        PrintDec p_lua
        PrintDec g_lua
        ENDIF
    .ELSE
        IFDEF EEEX_LOGGING
        .IF gEEexLog >= LOGLEVEL_DEBUG
            Invoke LogMessage, CTEXT("Cannot get g_lua value."), LOG_ERROR, 0
        .ENDIF
        ENDIF
        Invoke F_LuaL_loadstring, lua_State, lpszString ; EE lua function
        ret
    .ENDIF    
    
    ; 04/09/2019 - add in other lua libraries
    Invoke luaL_requiref, g_lua, CTEXT("io"), Addr luaopen_io, 1
    Invoke lua_settop, g_lua, -2
    
    Invoke luaL_requiref, g_lua, CTEXT("os"), Addr luaopen_os, 1
    Invoke lua_settop, g_lua, -2
    
    Invoke luaL_requiref, g_lua, CTEXT("package"), Addr luaopen_package, 1
    Invoke lua_settop, g_lua, -2
    
    ;---------------------------
    ; For prototype of no params
    ;---------------------------
    mov eax, F_Lua_createtable
    mov F_Lua_createtablex, eax
    
    IFDEF EEEX_LOGGING
    ;--------------------------------------------------------------------------
    ; Log some EE game globals
    ;--------------------------------------------------------------------------
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("EEexLuaInit:"), LOG_INFO, 0
        Invoke LogMessage, CTEXT("p_lua"), LOG_NONEWLINE, 1
        Invoke LogMessageAndHexValue, 0, p_lua
        Invoke LogMessage, CTEXT("g_lua"), LOG_NONEWLINE, 1
        Invoke LogMessageAndHexValue, 0, g_lua    
        Invoke LogMessage, 0, LOG_CRLF, 0
    .ENDIF
    ENDIF

    ;--------------------------------------------------------------------------
    ; Register the Lua EEex_Init
    ;--------------------------------------------------------------------------
    Invoke EEexLuaRegisterFunction, Addr EEex_Init, Addr szEEex_Init
    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("Register Function -  EEex_Init"), LOG_NONEWLINE, 1
        Invoke LogMessageAndHexValue, 0, Addr EEex_Init
    .ENDIF    
    ENDIF    
    Invoke F_LuaL_loadstring, lua_State, lpszString ; EE lua function
    ret
EEexLuaInit ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; EEexLuaRegisterFunction: Registers LUA Functions in EE Game
; Devnote: This function is PROTO STDCALL
;------------------------------------------------------------------------------
EEexLuaRegisterFunction PROC lpFunctionAddress:DWORD, lpszFunctionName:DWORD
    Invoke F_Lua_pushcclosure, g_lua, lpFunctionAddress, 0
    Invoke F_Lua_setglobal, g_lua, lpszFunctionName
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

    IFDEF DEBUG32
    PrintText 'EEex_Init'
    ENDIF
    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, 0, LOG_CRLF, 0
        Invoke LogMessage, CTEXT("EEex_Init:"), LOG_INFO, 0
    .ENDIF
    ENDIF
    
    Invoke EEexLuaRegisterFunction, Addr EEex_WriteByte, Addr szEEex_WriteByte
    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("Register Function -  EEex_WriteByte"), LOG_NONEWLINE, 1
        Invoke LogMessageAndHexValue, 0, Addr EEex_WriteByte
    .ENDIF
    ENDIF
    Invoke EEexLuaRegisterFunction, Addr EEex_ExposeToLua, Addr szEEex_ExposeToLua
    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("Register Function -  EEex_ExposeToLua"), LOG_NONEWLINE, 1
        Invoke LogMessageAndHexValue, 0, Addr EEex_ExposeToLua
    .ENDIF
    ENDIF
    
    Invoke EEexLuaRegisterFunction, Addr EEex_Call, Addr szEEex_Call
    IFDEF EEEX_LOGGING
    Invoke LogMessage, CTEXT("Register Function -  EEex_Call"), LOG_NONEWLINE, 1
    Invoke LogMessageAndHexValue, 0, Addr EEex_Call
    ENDIF

    Invoke EEexLuaRegisterFunction, Addr EEex_AddressList, Addr szEEex_AddressList
    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("Register Function -  EEex_AddressList"), LOG_NONEWLINE, 1
        Invoke LogMessageAndHexValue, 0, Addr EEex_AddressList
    .ENDIF
    ENDIF

;    Invoke EEexLuaRegisterFunction, Addr EEex_ReadDWORD, Addr szEEex_ReadDWORD
;    IFDEF EEEX_LOGGING
;    .IF gEEexLog >= LOGLEVEL_DEBUG
;        Invoke LogMessage, CTEXT("Register Function -  EEex_ReadDWORD"), LOG_NONEWLINE, 1
;        Invoke LogMessageAndHexValue, 0, Addr EEex_ReadDWORD
;    .ENDIF
;    ENDIF
    
;    Invoke EEexLuaRegisterFunction, Addr EEex_AddressListAsm, Addr szEEex_AddressListAsm
;    IFDEF EEEX_LOGGING
;    .IF gEEexLog >= LOGLEVEL_DEBUG
;        Invoke LogMessage, CTEXT("Register Function -  EEex_AddressListAsm"), LOG_NONEWLINE, 1
;        Invoke LogMessageAndHexValue, 0, Addr EEex_AddressListAsm
;    .ENDIF
;    ENDIF    
;    
;    Invoke EEexLuaRegisterFunction, Addr EEex_AddressListCount, Addr szEEex_AddressListCount
;    IFDEF EEEX_LOGGING
;    .IF gEEexLog >= LOGLEVEL_DEBUG
;        Invoke LogMessage, CTEXT("Register Function -  EEex_AddressListCount"), LOG_NONEWLINE, 1
;        Invoke LogMessageAndHexValue, 0, Addr EEex_AddressListCount
;    .ENDIF
;    ENDIF      

    IFDEF EEEX_LOGGING
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, 0, LOG_CRLF, 0
        Invoke LogMessage, CTEXT("VirtualAlloc 4096 bytes"), LOG_INFO, 0
        Invoke LogMessage, 0, LOG_CRLF, 0
    .ENDIF
    IFDEF EEEX_LOGLUACALLS
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, CTEXT("EEex Lua Functions: "), LOG_INFO, 0
    .ENDIF
    ENDIF
    ENDIF
    
    IFDEF DEBUG32
    PrintText 'VirtualAlloc'
    ENDIF    
    
    Invoke VirtualAlloc, 0, 1000h, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE
    push eax
    fild dword ptr [esp]
    sub esp, 4h
    fstp qword ptr [esp]
    push dword ptr [ebp+8h]
    call F_Lua_pushnumber
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
    .IF gEEexLog >= LOGLEVEL_DEBUG
        .IF EEex_WriteByte_Count == 0
            IFDEF DEBUG32
            PrintText 'EEex_WriteByte'
            ENDIF             
            Invoke LogMessage, Addr szEEex_WriteByte, LOG_STANDARD, 1
        .ENDIF
        inc EEex_WriteByte_Count
        mov eax, EEex_WriteByte_Count
        .IF eax >= EEEX_WRITEBYTE_LOGCOUNT
            mov EEex_WriteByte_Count, 0
        .ENDIF
    .ENDIF
    ENDIF
    ENDIF
    push 0h
    push 1h
    push dword ptr [ebp+8h]
    call F_Lua_tonumberx
    add esp, 0Ch
    call F__ftol2_sse
    mov edi, eax
    push 0h
    push 2h
    push dword ptr [ebp+8h]
    call F_Lua_tonumberx
    add esp, 0Ch
    call F__ftol2_sse
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
    
    IFDEF DEBUG32
    PrintText 'EEex_ExposeToLua'
    ENDIF        
    
    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, Addr szEEex_ExposeToLua, LOG_STANDARD, 1
    .ENDIF
    ENDIF
    ENDIF    
    push 0h
    push 1h
    push dword ptr [ebp+8h]
    call F_Lua_tonumberx
    add esp, 0Ch
    call F__ftol2_sse
    push 0h
    push eax
    push dword ptr [g_lua]
    call F_Lua_pushcclosure
    add esp, 0Ch
    push 0h
    push 2h
    push dword ptr [ebp+8h]
    call F_Lua_tolstring
    add esp, 0Ch
    push eax
    push dword ptr [g_lua]
    call F_Lua_setglobal
    add esp, 8h
    mov eax, 0h
    pop ebp
    ret 
EEex_ExposeToLua ENDP
OPTION PROLOGUE:PrologueDef
OPTION EPILOGUE:EpilogueDef


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_Call: Calls an internal function at the given address.
;
; EEex_Call(number address, table stackArgs, number ecx, number popSize)
;------------------------------------------------------------------------------
OPTION PROLOGUE:NONE
OPTION EPILOGUE:NONE
EEex_Call PROC C arg:VARARG
    push ebp
    mov ebp, esp
	push 2h
	push dword ptr [ebp+8h]
	call F_Lua_rawlen
	add esp, 8h
	test eax, eax
	je no_args
	mov edi, eax
	mov esi, 1;#01
arg_loop:
	push esi
	push 2h
	push dword ptr [ebp+8h]
	call F_Lua_rawgeti
	add esp, 0Ch
	push 0h
	push 0FFh
	push dword ptr [ebp+8h]
	call F_Lua_tonumberx
	add esp, 0Ch
	call F__ftol2_sse
	push eax
	push 0FEh
	push dword ptr [ebp+8h]
	call F_Lua_settop
	add esp, 8h
	inc esi
	cmp esi, edi
	jle arg_loop
no_args:
	push 0h
	push 3h
	push dword ptr [ebp+8h]
	call F_Lua_tonumberx
	add esp, 0Ch
	call F__ftol2_sse
	push eax
	push 0h
	push 1h
	push dword ptr [ebp+8h]
	call F_Lua_tonumberx
	add esp, 0Ch
	call F__ftol2_sse
	pop ecx
	call eax
	push eax
	fild dword ptr [esp]
	sub esp, 4h
	fstp qword ptr [esp]
	push dword ptr [ebp+8h]
	call F_Lua_pushnumber
	add esp, 0Ch
	push 0h
	push 4h
	push dword ptr [ebp+8h]
	call F_Lua_tonumberx
	add esp, 0Ch
	call F__ftol2_sse
	add esp, eax
	mov eax, 1;#01
    pop ebp
    ret 
EEex_Call ENDP
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
; [LUA] EEex_AddressList: Return a table of function and global addresses
;
; EEex_AddressList()
;------------------------------------------------------------------------------
EEex_AddressList PROC C USES EBX lua_State:DWORD
    LOCAL nPattern:DWORD
    LOCAL ptrCurrentPattern:DWORD
    LOCAL lpszPatternName:DWORD
    LOCAL dwPatternAddress:DWORD
    LOCAL nTotal:DWORD
    LOCAL nCount:DWORD
    LOCAL pT2Array:DWORD
    LOCAL pT2Entry:DWORD
    LOCAL qwAddress:QWORD
    LOCAL qwIndex:QWORD
    
    IFDEF EEEX_LOGGING
    IFDEF EEEX_LOGLUACALLS
    .IF gEEexLog >= LOGLEVEL_DEBUG
        Invoke LogMessage, Addr szEEex_AddressList, LOG_STANDARD, 1
    .ENDIF
    ENDIF
    ENDIF
    
    mov eax, TotalPatterns
    add eax, 3 ; for extra at end
    Invoke F_Lua_createtable, lua_State, 0, eax

    mov ebx, PatternsDatabase
    mov ptrCurrentPattern, ebx
    mov nPattern, 0
    mov eax, 0
    .WHILE eax < TotalPatterns
        .IF [ebx].PATTERN.bFound == TRUE
            mov eax, [ebx].PATTERN.PatName
            mov lpszPatternName, eax
            
            .IF [ebx].PATTERN.PatType == 2
                ;--------------------------------------------------------------
                ; Handle type 2 pattern: name=table/array of addresses
                ;--------------------------------------------------------------
                mov eax, [ebx].PATTERN.VerAdj ; used to store count of array entries
                mov nTotal, eax
                mov eax, [ebx].PATTERN.PatAddress ; used to store pointer to array
                .IF eax != NULL && nTotal != 0
                    mov pT2Array, eax
                    mov pT2Entry, eax
                    
                    Invoke F_Lua_pushstring, lua_State, lpszPatternName
                    Invoke F_Lua_createtable, lua_State, 0, nCount
                    mov nCount, 0
                    mov eax, 0
                    .WHILE eax < nTotal
                        mov ebx, pT2Entry
                        mov eax, [ebx]
                        mov dwPatternAddress, eax
                        
                        inc nCount ; for lua 1 based indexes
                        fild nCount
                        dec nCount ; restore nCount to its proper value for loop condition
                        fstp qword ptr [qwIndex]
                        Invoke F_Lua_pushnumber, lua_State, qwIndex
                        fild dwPatternAddress
                        fstp qword ptr [qwAddress]            
                        Invoke F_Lua_pushnumber, lua_State, qwAddress ; dwPatternAddress
                        Invoke F_Lua_settable, lua_State, -3
                        
                        add pT2Entry, SIZEOF DWORD
                        inc nCount
                        mov eax, nCount
                    .ENDW
                    Invoke F_Lua_settable, lua_State, -3
                    
                .ENDIF
                
            .ELSE
                ;--------------------------------------------------------------
                ; Handle all other pattern types: name=address / var=value
                ;--------------------------------------------------------------
                mov eax, [ebx].PATTERN.PatAddress
                mov dwPatternAddress, eax
                Invoke F_Lua_pushstring, lua_State, lpszPatternName
                fild dwPatternAddress
                fstp qword ptr [qwAddress]            
                Invoke F_Lua_pushnumber, lua_State, qwAddress ; dwPatternAddress
                Invoke F_Lua_settable, lua_State, -3
            .ENDIF
            
        .ENDIF
        add ptrCurrentPattern, SIZEOF PATTERN
        mov ebx, ptrCurrentPattern
        inc nPattern
        mov eax, nPattern
    .ENDW

    ; handle special cases, like GetProcAddress, LoadLibrary etc
    Invoke F_Lua_pushstring, lua_State, Addr szGetProcAddress
    fild F_GetProcAddress
    fstp qword ptr [qwAddress]      
    Invoke F_Lua_pushnumber, lua_State, qwAddress ; F_GetProcAddress
    Invoke F_Lua_settable, lua_State, -3
    
    Invoke F_Lua_pushstring, lua_State, Addr szLoadLibrary
    fild F_LoadLibrary
    fstp qword ptr [qwAddress]     
    Invoke F_Lua_pushnumber, lua_State, qwAddress ; F_LoadLibrary
    Invoke F_Lua_settable, lua_State, -3
    
    Invoke F_Lua_pushstring, lua_State, Addr szSDL_Free
    fild F_SDL_free
    fstp qword ptr [qwAddress]      
    Invoke F_Lua_pushnumber, lua_State, qwAddress ; F_SDL_free
    Invoke F_Lua_settable, lua_State, -3
    
    ;Invoke F_Lua_setglobal, lua_State, Addr szEEex_LuaAddressList
    
    mov eax, 1
    ret
EEex_AddressList ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_ReadDWORD: Read DWORD at address
;
; EEex_ReadDWORD(Address)
;------------------------------------------------------------------------------
EEex_ReadDWORD PROC C USES EBX lua_State:DWORD, dwAddress:DWORD
;    LOCAL qwAddressContent:QWORD
;    LOCAL dwAddressContent:DWORD
;    
;    .IF dwAddress == 0
;        xor eax, eax
;        ret
;    .ENDIF
;    
;    mov ebx, dwAddress
;    mov eax, [ebx]
;    mov dwAddressContent, eax
;    
;    fild dwAddressContent
;    fstp qword ptr [qwAddressContent]            
;    Invoke F_Lua_pushnumber, lua_State, qwAddressContent
;    mov eax, 1
;    ret
EEex_ReadDWORD ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_AddressListAsm: Return an array of function and global addresses
;
; EEex_AddressListAsm()
;
; Returns: pointer to address list array or 0 if fail
;------------------------------------------------------------------------------
EEex_AddressListAsm PROC C USES EBX EDX lua_State:DWORD
;    LOCAL nPattern:DWORD
;    LOCAL ptrCurrentPattern:DWORD
;    LOCAL ptrCurrentALEntry:DWORD
;    LOCAL lpszPatternName:DWORD
;    LOCAL dwPatternAddress:DWORD
;    LOCAL qwAddress:QWORD
;    
;    ;--------------------------------------------------------------------------
;    ; Create pAddressList if it doesnt exist, otherwise return address of it
;    ;--------------------------------------------------------------------------
;    .IF pAddressList == 0 
;        mov eax, TotalPatterns
;        add eax, 4 ; 3 extras + one last entry, which will be null - in case not using count
;        mov ebx, SIZEOF ALENTRY
;        mul ebx
;        Invoke GlobalAlloc, GMEM_FIXED or GMEM_ZEROINIT, eax
;        .IF eax == NULL
;            ret
;        .ENDIF
;        mov pAddressList, eax
;        mov ptrCurrentALEntry, eax
;        mov edx, eax
;
;        mov ebx, PatternsDatabase
;        mov ptrCurrentPattern, ebx
;        mov nPattern, 0
;        mov eax, 0
;        .WHILE eax < TotalPatterns
;            .IF [ebx].PATTERN.bFound == TRUE
;                ; copy pointer to name and address from 
;                ; current PATTERN entry to ALENTRY entry
;                mov eax, [ebx].PATTERN.PatName
;                mov [edx].ALENTRY.lpszName, eax
;                mov eax, [ebx].PATTERN.PatAddress
;                mov [edx].ALENTRY.dwAddress, eax                
;            .ENDIF
;            add ptrCurrentALEntry, SIZEOF ALENTRY
;            add ptrCurrentPattern, SIZEOF PATTERN
;            mov ebx, ptrCurrentPattern
;            mov edx, ptrCurrentALEntry
;            inc nPattern
;            mov eax, nPattern
;        .ENDW        
;    .ENDIF
;    
;    ; Handle extras like GetProcAddress, LoadLibrary etc
;    lea eax, szGetProcAddress
;    mov [edx].ALENTRY.lpszName, eax
;    mov eax, F_GetProcAddress
;    mov [edx].ALENTRY.dwAddress, eax
;    add edx, SIZEOF ALENTRY
;    
;    lea eax, szLoadLibrary
;    mov [edx].ALENTRY.lpszName, eax
;    mov eax, F_LoadLibrary
;    mov [edx].ALENTRY.dwAddress, eax
;    add edx, SIZEOF ALENTRY
;    
;    lea eax, szSDL_Free
;    mov [edx].ALENTRY.lpszName, eax
;    mov eax, F_SDL_free
;    mov [edx].ALENTRY.dwAddress, eax
; 
;    ;mov eax, pAddressList
;    fild pAddressList
;    fstp qword ptr [qwAddress]
;    Invoke F_Lua_pushnumber, lua_State, qwAddress
;    
;    mov eax, 1
    ret
EEex_AddressListAsm ENDP


EEEX_ALIGN
;------------------------------------------------------------------------------
; [LUA] EEex_AddressListCount: Return a count of entries in pAddressList
;
; EEex_AddressListCountAsm()
;------------------------------------------------------------------------------
EEex_AddressListCount PROC C lua_State:DWORD
;    LOCAL dwCount:DWORD
;    LOCAL qwAddress:QWORD
;    
;    mov eax, TotalPatterns
;    add eax, 3 ; for extra patterns: GetProcAddress, LoadLibrary etc
;    mov dwCount, eax
;    fild dwCount
;    fstp qword ptr [qwAddress]
;    Invoke F_Lua_pushnumber, lua_State, qwAddress
;    
;    mov eax, 1
    ret
EEex_AddressListCount ENDP



