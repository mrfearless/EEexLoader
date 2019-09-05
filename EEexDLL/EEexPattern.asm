;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; Pattern information: 
; 
; Information is stored in a 'Patterns' array/table. This allows the search or 
; verification of patterns to be data driven. Each entry/record in this blob
; of data is a PATTERN structure. The PATTERN structure consists of pointers
; and integers. The pointers are typically pointing to a series of defined
; bytes for a pattern. The integers are used to adjust the location of the 
; found pattern or subpattern to resolve the correct address we require.
;
; The lua functions have a typedef to allow us to use them in EEexLua.asm
; Using the 'F_' function pointers we can call functions with these, for 
; example: call F_Lua_pushstring
; 
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; EEexPattern Prototypes
;------------------------------------------------------------------------------
PatternVerify           PROTO :DWORD,:DWORD,:DWORD ; lpdwAddress, lpdwPatternBytes, dwPatternLength


;------------------------------------------------------------------------------
; EEexPattern Structures
;------------------------------------------------------------------------------
IFNDEF PATTERN
PATTERN                 STRUCT
    bFound              DD 0 ; Found flag, used to skip patterns already found and verified
    PatType             DD 0 ; Pattern search type: 0 = function address, 1 = variable
    PatBytes            DD 0 ; Pointer to pattern bytes to match (required)
    PatLength           DD 0 ; Length of PatBytes (required)
    VerBytes            DD 0 ; Pointer to verify bytes to match (can be 0)
    VerLength           DD 0 ; Length of VerLength (required if VerBytes != 0, otherwise 0)
    PatAdj              DD 0 ; +/- if PatBytes matched to get address to return (can be 0)
    VerAdj              DD 0 ; +/- from PatBytes matched address to get address of VerBytes to verify (can be 0)
    PatName             DD 0 ; Pointer to zero terminated string that contains pattern function or global variable name
    PatAddress          DD 0 ; Address of function or global if pattern bytes match and verify bytes match
PATTERN                 ENDS
ENDIF


.CONST
IMP_ERR_NONE            EQU  0 ;
IMP_ERR_PATBYTES_EMPTY  EQU -1 ; PatBytes entry is empty of text
IMP_ERR_PATBYTES_SIZE   EQU -2 ; PatBytes entry has text but length is not multiple of 2 (for paired hex chars)
IMP_ERR_PATBYTES_ALLOC  EQU -3 ; Could not allocate memory for PatBytes conversion to raw pattern bytes
IMP_ERR_VERBYTES_EMPTY  EQU -4 ; VerBytes entry is empty of text (which is allowed - just providing this incase future use)
IMP_ERR_VERBYTES_SIZE   EQU -5 ; VerBytes entry has text but length is not multiple of 2 (for paired hex chars)
IMP_ERR_VERBYTES_ALLOC  EQU -6 ; Could not allocate memory for VerBytes conversion to raw pattern bytes
IMP_ERR_PATBYTES_NOTHEX EQU -7 ; Non hex characters found in PatBytes pattern hex text chars (allowed: 0-9,a-z,A-Z and space)
IMP_ERR_VERBYTES_NOTHEX EQU -8 ; Non hex characters found in VerBytes pattern hex text chars (allowed: 0-9,a-z,A-Z and space)

TYPE2_ARRAY_INITIAL_COUNT EQU 64
TYPE2_ARRAY_INITIAL_SIZE EQU (TYPE2_ARRAY_INITIAL_COUNT * SIZEOF DWORD)


.DATA
;---------------------------
; Patch location address 
;---------------------------
PatchLocation           DD 0 ; call XXXEEgame:luaL_loadstring replaced with call EEex.dll:EEexLuaInit


;---------------------------
; Lua Function pointers
;---------------------------
; typedef prototypes:
Lua_createtableProto    TYPEDEF PROTO C :VARARG ;luastate:DWORD, narr:DWORD, nrec:DWORD
Lua_createtablePtr      TYPEDEF PTR Lua_createtableProto
Lua_createtablexProto   TYPEDEF PROTO C :VARARG ;luastate:DWORD ; override for no narr and nrec params of lua_createtable
Lua_createtablexPtr     TYPEDEF PTR Lua_createtablexProto
Lua_getglobalProto      TYPEDEF PROTO C luastate:DWORD, ptr_name:DWORD
Lua_getglobalPtr        TYPEDEF PTR Lua_getglobalProto
Lua_gettopProto         TYPEDEF PROTO C luastate:DWORD
Lua_gettopPtr           TYPEDEF PTR Lua_gettopProto
Lua_pcallkProto         TYPEDEF PROTO C luastate:DWORD, nargs:DWORD, nresults:DWORD, msgh:DWORD, lua_KContext_ctx:DWORD, lua_KFunction_k:DWORD
Lua_pcallkPtr           TYPEDEF PTR Lua_pcallkProto
Lua_pushcclosureProto   TYPEDEF PROTO C :VARARG ;luastate:DWORD, lua_CFunction:DWORD, n:DWORD
Lua_pushcclosurePtr     TYPEDEF PTR Lua_pushcclosureProto
Lua_pushlightuserdataProto TYPEDEF PROTO C luastate:DWORD, p:DWORD
Lua_pushlightuserdataPtr TYPEDEF PTR Lua_pushlightuserdataProto
Lua_pushlstringProto    TYPEDEF PROTO C luastate:DWORD, ptr_string:DWORD, stringlen:DWORD
Lua_pushlstringPtr      TYPEDEF PTR Lua_pushlstringProto
Lua_pushnumberProto     TYPEDEF PROTO C :VARARG ;luastate:DWORD, lua_Number:DWORD
Lua_pushnumberPtr       TYPEDEF PTR Lua_pushnumberProto
Lua_pushstringProto     TYPEDEF PROTO C :VARARG ;luastate:DWORD, ptr_string:DWORD
Lua_pushstringPtr       TYPEDEF PTR Lua_pushstringProto
Lua_rawgetiProto        TYPEDEF PROTO C luastate:DWORD, index:DWORD, n:DWORD
Lua_rawgetiPtr          TYPEDEF PTR Lua_rawgetiProto
Lua_rawlenProto         TYPEDEF PROTO C luastate:DWORD, index:DWORD
Lua_rawlenPtr           TYPEDEF PTR Lua_rawlenProto
Lua_setfieldProto       TYPEDEF PROTO C luastate:DWORD, index:DWORD, ptr_string:DWORD
Lua_setfieldPtr         TYPEDEF PTR Lua_setfieldProto
Lua_setglobalProto      TYPEDEF PROTO C :VARARG ;luastate:DWORD, ptr_name:DWORD
Lua_setglobalPtr        TYPEDEF PTR Lua_setglobalProto
Lua_settableProto       TYPEDEF PROTO C :VARARG ;luastate:DWORD, index:DWORD
Lua_settablePtr         TYPEDEF PTR Lua_settableProto
Lua_settopProto         TYPEDEF PROTO C luastate:DWORD, index:DWORD
Lua_settopPtr           TYPEDEF PTR Lua_settopProto
Lua_tobooleanProto      TYPEDEF PROTO C luastate:DWORD, index:DWORD
Lua_tobooleanPtr        TYPEDEF PTR Lua_tobooleanProto
Lua_tolstringProto      TYPEDEF PROTO C luastate:DWORD, index:DWORD, ptr_len:DWORD
Lua_tolstringPtr        TYPEDEF PTR Lua_tolstringProto
Lua_tonumberxProto      TYPEDEF PROTO C luastate:DWORD, index:DWORD, ptr_isnum:DWORD
Lua_tonumberxPtr        TYPEDEF PTR Lua_tonumberxProto
Lua_touserdataProto     TYPEDEF PROTO C luastate:DWORD, index:DWORD
Lua_touserdataPtr       TYPEDEF PTR Lua_touserdataProto
Lua_typeProto           TYPEDEF PROTO C luastate:DWORD, index:DWORD
Lua_typePtr             TYPEDEF PTR Lua_typeProto
Lua_typenameProto       TYPEDEF PROTO C luastate:DWORD, tp:DWORD
Lua_typenamePtr         TYPEDEF PTR Lua_typenameProto
LuaL_loadstringProto    TYPEDEF PROTO C :VARARG ;luastate:DWORD, ptr_string:DWORD
LuaL_loadstringPtr      TYPEDEF PTR LuaL_loadstringProto
ftol2_sseProto          TYPEDEF PROTO C :VARARG
ftol2_ssePtr            TYPEDEF PTR ftol2_sseProto
; Lua function pointers
F_Lua_createtable       Lua_createtablePtr 0
F_Lua_createtablex      Lua_createtablexPtr 0 ; override for no params of lua_createtable
F_Lua_getglobal         Lua_getglobalPtr 0
F_Lua_gettop            Lua_gettopPtr 0
F_Lua_pcallk            Lua_pcallkPtr 0
F_Lua_pushcclosure      Lua_pushcclosurePtr 0
F_Lua_pushlightuserdata Lua_pushlightuserdataPtr 0
F_Lua_pushlstring       Lua_pushlstringPtr 0
F_Lua_pushnumber        Lua_pushnumberPtr 0
F_Lua_pushstring        Lua_pushstringPtr 0
F_Lua_rawgeti           Lua_rawgetiPtr 0
F_Lua_rawlen            Lua_rawlenPtr 0
F_Lua_setfield          Lua_setfieldPtr 0
F_Lua_setglobal         Lua_setglobalPtr 0
F_Lua_settable          Lua_settablePtr 0
F_Lua_settop            Lua_settopPtr 0
F_Lua_toboolean         Lua_tobooleanPtr 0
F_Lua_tolstring         Lua_tolstringPtr 0
F_Lua_tonumberx         Lua_tonumberxPtr 0
F_Lua_touserdata        Lua_touserdataPtr 0
F_Lua_type              Lua_typePtr 0
F_Lua_typename          Lua_typenamePtr 0
F_LuaL_loadstring       LuaL_loadstringPtr 0


;---------------------------
; Other function pointers
;---------------------------
F__ftol2_sse            ftol2_ssePtr 0
F_GetProcAddress        DD 0 ; 
F_LoadLibrary           DD 0 ;
F_SDL_free              DD 0 ; SDL Export
F_SDL_Log               DD 0 ; SDL Export

;---------------------------
; EE game global variables: 
;---------------------------
p_lua                   DD 0 ; pointer to global lua variable
g_lua                   DD 0 ; actual content of global lua variable


;---------------------------
; Pattern array and stats
;---------------------------
PatternsDatabase        DD 0 ; Pointer to array of PATTERN structures - built by EEexImportPatterns

TotalPatterns           DD 0 ; 
TotalPatternsToImport   DD 0 ; 

VerifiedPatterns        DD 0 ; Total verified patterns by EEexVerifyPatterns
NotVerifiedPatterns     DD 0 ; Total patterns NOT verified by EEexVerifyPatterns
SkippedVerifyPatterns   DD 0 ; 
FoundPatterns           DD 0 ; Total searched and found patterns by EEexSearchPatterns
NotFoundPatterns        DD 0 ; Total patterns NOT found by EEexSearchPatterns
SkippedFoundPatterns    DD 0 ; 
ImportedPatterns        DD 0 ; Total patterns imported by EEexImportPatterns
NotImportedPatterns     DD 0 ; Total patterns NOT imported by EEexImportPatterns
SkippedImportedPatterns DD 0 ; 


.CODE


EEEX_ALIGN
;------------------------------------------------------------------------------
; PatternVerify - Verify a pattern matches at the specified address
; Returns: TRUE if it matches, FALSE if it doesnt.
;------------------------------------------------------------------------------
PatternVerify PROC USES EBX EDI ESI lpdwAddress:DWORD, lpdwPatternBytes:DWORD, dwPatternLength:DWORD
    LOCAL pos:DWORD
    
    .IF lpdwAddress == 0 || lpdwPatternBytes == 0 || dwPatternLength == 0
        mov eax, TRUE ; if pattern bytes is 0 then basically mark it as found and skip
        ret
    .ENDIF
    
    mov esi, lpdwAddress
    mov edi, lpdwPatternBytes
    mov pos, 0
    mov eax, 0
    .WHILE eax < dwPatternLength
        movzx eax, byte ptr [esi]
        movzx ebx, byte ptr [edi]
        .IF al != bl
            mov eax, FALSE
            ret
        .ENDIF
        inc esi
        inc edi
        inc pos
        mov eax, pos
    .ENDW
    mov eax, TRUE
    ret
PatternVerify ENDP

















