;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; EEexPattern Prototypes
;------------------------------------------------------------------------------
PatternVerify           PROTO :DWORD,:DWORD,:DWORD               ; lpdwAddress, lpdwPatternBytes, dwPatternLength
PatternMaskVerify       PROTO :DWORD,:DWORD,:DWORD,:DWORD,:DWORD ; lpdwAddress, lpdwPatternBytes, dwPatternLength, lpdwMasks, dwNoMasks


;---------------------------
; EE function typedef prototypes:
;---------------------------
Lua_createtableProto    TYPEDEF PROTO C luastate:DWORD, narr:DWORD, nrec:DWORD
Lua_createtablePtr      TYPEDEF PTR Lua_createtableProto
Lua_createtablexProto   TYPEDEF PROTO C luastate:DWORD ; override for no narr and nrec params of lua_createtable
Lua_createtablexPtr     TYPEDEF PTR Lua_createtablexProto
Lua_getglobalProto      TYPEDEF PROTO C luastate:DWORD, ptr_name:DWORD
Lua_getglobalPtr        TYPEDEF PTR Lua_getglobalProto
Lua_gettopProto         TYPEDEF PROTO C luastate:DWORD
Lua_gettopPtr           TYPEDEF PTR Lua_gettopProto
Lua_pcallkProto         TYPEDEF PROTO C luastate:DWORD, nargs:DWORD, nresults:DWORD, msgh:DWORD, lua_KContext_ctx:DWORD, lua_KFunction_k:DWORD
Lua_pcallkPtr           TYPEDEF PTR Lua_pcallkProto
Lua_pushcclosureProto   TYPEDEF PROTO C luastate:DWORD, lua_CFunction:DWORD, n:DWORD
Lua_pushcclosurePtr     TYPEDEF PTR Lua_pushcclosureProto
Lua_pushlightuserdataProto TYPEDEF PROTO C luastate:DWORD, p:DWORD
Lua_pushlightuserdataPtr TYPEDEF PTR Lua_pushlightuserdataProto
Lua_pushlstringProto    TYPEDEF PROTO C luastate:DWORD, ptr_string:DWORD, stringlen:DWORD
Lua_pushlstringPtr      TYPEDEF PTR Lua_pushlstringProto
Lua_pushnumberProto     TYPEDEF PROTO C luastate:DWORD, lua_Number:DWORD
Lua_pushnumberPtr       TYPEDEF PTR Lua_pushnumberProto
Lua_pushstringProto     TYPEDEF PROTO C luastate:DWORD, ptr_string:DWORD
Lua_pushstringPtr       TYPEDEF PTR Lua_pushstringProto
Lua_rawgetiProto        TYPEDEF PROTO C luastate:DWORD, index:DWORD, n:DWORD
Lua_rawgetiPtr          TYPEDEF PTR Lua_rawgetiProto
Lua_rawlenProto         TYPEDEF PROTO C luastate:DWORD, index:DWORD
Lua_rawlenPtr           TYPEDEF PTR Lua_rawlenProto
Lua_setfieldProto       TYPEDEF PROTO C luastate:DWORD, index:DWORD, ptr_string:DWORD
Lua_setfieldPtr         TYPEDEF PTR Lua_setfieldProto
Lua_setglobalProto      TYPEDEF PROTO C luastate:DWORD, ptr_name:DWORD
Lua_setglobalPtr        TYPEDEF PTR Lua_setglobalProto
Lua_settableProto       TYPEDEF PROTO C luastate:DWORD, index:DWORD
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
LuaL_loadstringProto    TYPEDEF PROTO C luastate:DWORD, ptr_string:DWORD
LuaL_loadstringPtr      TYPEDEF PTR LuaL_loadstringProto
ftol2_sseProto          TYPEDEF PROTO C :VARARG
ftol2_ssePtr            TYPEDEF PTR ftol2_sseProto


;------------------------------------------------------------------------------
; Devnote: 
;  
; Passing back via array function name and pointers from a lua function to lua scripts?
; 
; Masked patterns to allow for ??. Bitmask? 32bits for 32 bytes of masks
; Pattern: 83h,0C4h,30h,85h,0C0h,75h,14h,50h,50h,50h,6Ah,??,50h,0FFh,35h = 15 bytes
; Bits: 31               14             0
; Mask:  xxxxxxxxxxxxxxxxx111111111110111 -> 4th bit for mask of ??
;
; mov eax, patpos
; shr eax, 05h ; div by 32
; mov maskoffset, eax ; get index to mask dword array
; lea ebx, mask
; lea eax, [ebx+eax*4] ; get ptr to current mask dword value: maskbase + index * SIZEOF(DWORD)
; mov eax, [eax] ; get current mask dword value (xxxxxxxxxxxxxxxxx111111111110111)
; mov curmask, eax
; .IF curmask == 0FFFFFFFFh ; skip mask check as all set to 1
;    mov eax, TRUE
; .ELSE
;    mov ebx, patpos
;    and ebx, 31 (a && (b-1) = patpos mod 32)
;    mov patposmod, ebx
;    mov eax, curmask
;    shr eax, ebx ; shift mask value by mod of patpos, example pos 4 =  000xxxxxxxxxxxxxxxxx111111111110
;    and eax, 1 ; mask off bit 1 from current mask dword value
;    .IF eax == 1
;        mov eax, TRUE ; can compare this byte with patbyte
;    .ELSE
;        mov eax, FALSE ; can ignore this byte and skip to next one. 
;    .ENDIF
; .ENDIF
;------------------------------------------------------------------------------


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
    FuncAddress         DD 0 ; Pointer to global var to store address of function if pattern bytes match and verify bytes match
PATTERN                 ENDS
ENDIF


.DATA
;---------------------------
; Byte Search Patterns
;---------------------------
ALIGN 4
P_PatchLocation         DB 83h,0C4h,30h,85h,0C0h,75h,14h,50h,50h,50h,6Ah,0FFh,50h,0FFh,35h
P_PatchLocationLen      EQU $-P_PatchLocation
V_PatchLocation         DB 83h,0C4h,18h,6Ah,00h
V_PatchLocationLen      EQU $-V_PatchLocation

; Byte Search Patterns For Lua Functions
P_Lua_createtable       DB 83h, 46h, 08h, 08h, 8Bh, 4Dh, 10h
P_Lua_createtableLen    EQU $-P_Lua_createtable

P_Lua_getglobal         DB 55h,8Bh,0ECh,53h,56h,8Bh,75h,08h,0BAh,02h,00h,00h,00h,57h,8Bh,46h,0Ch,8Bh,48h,28h
P_Lua_getglobalLen      EQU $-P_Lua_getglobal
V_Lua_getglobal         DB 83h,0C0h,0F8h
V_Lua_getglobalLen      EQU $-V_Lua_getglobal
P_Lua_gettop            DB 55h, 8Bh, 0ECh, 8Bh, 45h, 08h, 8Bh, 48h, 10h, 8Bh, 40h, 08h, 2Bh, 01h, 83h, 0E8h, 08h, 0C1h, 0F8h, 03h, 5Dh, 0C3h
P_Lua_gettopLen         EQU $-P_Lua_gettop
P_Lua_pcallk            DB 8Bh, 55h, 14h, 53h, 8Bh, 5Dh, 0Ch, 56h, 8Bh, 75h, 08h, 57h, 85h, 0D2h
P_Lua_pcallkLen         EQU $-P_Lua_pcallk
P_Lua_pushcclosure      DB 55h,8Bh,0ECh,83h,0E4h,0F8h,56h,57h,8Bh,7Dh,10h,85h,0FFh,75h,1Ch,8Bh,55h,08h,8Bh,45h,0Ch,8Bh,4Ah,08h,89h,01h,0C7h,41h,04h,16h,0A5h,0F7h,7Fh,83h,42h,08h,08h,5Fh,5Eh,8Bh,0E5h,5Dh,0C3h
P_Lua_pushcclosureLen   EQU $-P_Lua_pushcclosure
V_Lua_pushcclosure      DB 0,0,0,0
V_Lua_pushcclosureLen   EQU 0 ; $-V_Lua_pushcclosure
P_Lua_pushlightuserdata DB 55h, 8Bh, 0ECh, 8Bh, 55h, 08h, 8Bh, 45h, 0Ch, 8Bh, 4Ah, 08h, 89h, 01h, 0C7h, 41h, 04h, 02h, 0A5h, 0F7h, 7Fh, 83h, 42h, 08h, 08h, 5Dh, 0C3h
P_Lua_pushlightuserdataLen EQU $-P_Lua_pushlightuserdata
P_Lua_pushlstring       DB 55h, 8Bh, 0ECh, 83h, 0E4h, 0F8h, 51h, 53h, 56h, 57h, 8Bh, 0F9h, 8Bh, 0DAh, 8Bh, 77h, 0Ch, 83h, 7Eh, 0Ch, 00h, 7Eh, 1Fh, 80h, 7Eh, 37h, 00h, 74h, 07h
P_Lua_pushlstringLen    EQU $-P_Lua_pushlstring
P_Lua_pushnumber        DB 55h,8Bh,0ECh,8Bh,4Dh,08h,0DDh,45h,0Ch,8Bh,51h,08h,0DDh,1Ah,8Bh,42h,04h,25h,00h,0FFh,0FFh,7Fh,3Dh,00h,0A5h,0F7h,7Fh,74h,08h,8Dh,42h,08h,89h,41h,08h,5Dh,0C3h
P_Lua_pushnumberLen     EQU $-P_Lua_pushnumber
P_Lua_pushstring        DB 55h, 8Bh, 0ECh, 83h, 0E4h, 0F8h, 56h, 57h, 8Bh, 7Dh, 0Ch, 85h, 0FFh
P_Lua_pushstringLen     EQU $-P_Lua_pushstring
P_Lua_rawgeti           DB 8Bh, 56h, 08h, 8Bh, 08h, 89h, 0Ah, 8Bh, 40h, 04h, 89h, 42h, 04h, 83h, 46h, 08h, 08h, 5Eh, 5Dh, 0C3h
P_Lua_rawgetiLen        EQU $-P_Lua_rawgeti
V_Lua_rawgeti           DB 8Bh,55h,10h,8Bh,08h
V_Lua_rawgetiLen        EQU 0 ; $-V_Lua_rawgeti
P_Lua_rawlen            DB 8Bh, 50h, 04h, 8Bh, 0CAh, 81h, 0E1h, 00h, 0FFh, 0FFh, 7Fh, 81h, 0F9h, 00h, 0A5h, 0F7h, 7Fh, 0B9h, 03h, 00h, 00h, 00h, 75h, 03h, 0Fh, 0B6h, 0CAh, 83h, 0E1h, 0Fh, 83h, 0E9h, 04h
P_Lua_rawlenLen         EQU $-P_Lua_rawlen
V_Lua_rawlen            DB 0CCh,55h
V_Lua_rawlenLen         EQU 0 ; $-V_Lua_rawlen
P_Lua_setfield          DB 8Bh, 7Eh, 08h, 8Bh, 0D8h, 8Bh, 55h, 10h, 8Dh, 4Fh, 08h, 89h, 4Eh, 08h
P_Lua_setfieldLen       EQU $-P_Lua_setfield
P_Lua_setglobal         DB 55h,8Bh,0ECh,53h,56h,8Bh,75h,08h,0BAh,02h,00h,00h,00h,57h,8Bh,46h,0Ch,8Bh,48h,28h
P_Lua_setglobalLen      EQU $-P_Lua_setglobal
V_Lua_setglobal         DB 83h,46h,08h,0F0h
V_Lua_setglobalLen      EQU $-V_Lua_setglobal
P_Lua_settable          DB 8Bh, 75h, 08h, 8Bh, 4Eh, 08h, 8Dh, 41h, 0F8h
P_Lua_settableLen       EQU $-P_Lua_settable
P_Lua_settop            DB 55h, 8Bh, 0ECh, 8Bh, 45h, 08h, 8Bh, 48h, 10h, 8Bh, 11h, 8Bh, 4Dh, 0Ch, 85h, 0C9h
P_Lua_settopLen         EQU $-P_Lua_settop
P_Lua_toboolean         DB 8Bh, 48h, 04h, 81h, 0F9h, 00h, 0A5h, 0F7h, 7Fh, 74h, 14h, 81h, 0F9h, 01h, 0A5h, 0F7h, 7Fh, 75h, 05h, 83h, 38h, 00h, 74h, 07h, 0B8h, 01h, 00h, 00h, 00h, 5Dh, 0C3h, 33h, 0C0h, 5Dh, 0C3h
P_Lua_tobooleanLen      EQU $-P_Lua_toboolean
P_Lua_tolstring         DB 55h,8Bh,0ECh,83h,0E4h,0F8h,51h,8Bh,55h,0Ch,56h,8Bh,75h,08h,8Bh,0CEh
P_Lua_tolstringLen      EQU $-P_Lua_tolstring
P_Lua_tonumberx         DB 83h,0C4h,04h,85h,0C0h,74h,28h,0DDh,44h,24h,08h,8Dh,44h,24h,08h,0DDh,5Ch,24h,08h,85h,0F6h,74h,06h,0C7h,06h,01h,00h,00h,00h,0DDh,00h,5Eh,8Bh,4Ch,24h,10h,33h,0CCh
P_Lua_tonumberxLen      EQU $-P_Lua_tonumberx
P_Lua_touserdata        DB 8Bh, 50h, 04h, 8Bh, 0CAh, 81h, 0E1h, 00h, 0FFh, 0FFh, 7Fh, 81h, 0F9h, 00h, 0A5h, 0F7h, 7Fh, 0B9h, 03h, 00h, 00h, 00h, 75h, 03h, 0Fh, 0B6h, 0CAh, 83h, 0E1h, 0Fh, 83h, 0E9h, 02h, 74h, 10h, 83h, 0E9h, 05h, 74h, 04h, 33h, 0C0h, 5Dh
P_Lua_touserdataLen     EQU $-P_Lua_touserdata
P_Lua_type              DB 8Bh, 48h, 04h, 8Bh, 0C1h, 25h, 00h, 0FFh, 0FFh, 7Fh, 3Dh, 00h, 0A5h, 0F7h, 7Fh, 0B8h, 03h, 00h, 00h, 00h, 75h, 03h, 0Fh, 0B6h, 0C1h, 83h, 0E0h, 0Fh, 5Dh
P_Lua_typeLen           EQU $-P_Lua_type
P_Lua_typename          DB 55h, 8Bh, 0ECh, 8Bh, 45h, 0Ch, 8Bh, 04h, 85h
P_Lua_typenameLen       EQU $-P_Lua_typename
P_LuaL_loadstring       DB 8Bh,55h,0Ch,8Bh,0C2h,56h,8Bh,75h,08h,57h,8Dh,78h,01h,8Ah,08h,40h,84h,0C9h
P_LuaL_loadstringLen    EQU $-P_LuaL_loadstring
V_LuaL_loadstring       DB 0,0,0,0
V_LuaL_loadstringLen    EQU 0 ; $-V_LuaL_loadstring
P__ftol2_sse            DB 74h,2Dh,55h,8Bh,0ECh,83h,0ECh,08h,83h,0E4h,0F8h,0DDh,1Ch,24h,0F2h,0Fh,2Ch,04h,24h,0C9h,0C3h
P__ftol2_sseLen         EQU $-P__ftol2_sse
V__ftol2_sse            DB 0,0,0,0
V__ftol2_sseLen         EQU 0 ; $-V__ftol2_sse

; Byte Search Patterns for EE game variables:
P_g_pChitin             DB 98h, 69h, 0D8h, 98h, 00h, 00h, 00h, 6Ah, 14h, 03h, 1Dh, 0B8h, 0FDh, 93h, 00h
P_g_pChitinLen          EQU $-P_g_pChitin
P_g_pBaldurChitin       DB 66h, 83h, 0F8h, 0FFh, 0Fh, 84h, 0F5h, 00h, 00h, 00h, 0A1h
P_g_pBaldurChitinLen    EQU $-P_g_pBaldurChitin

P_g_backgroundMenu      DB 8Bh, 0F0h, 83h, 0C4h, 14h, 85h, 0F6h, 74h, 2Ah, 6Ah, 00h, 68h, 0FFh, 0FFh, 0FFh, 7Fh, 6Ah, 00h, 6Ah, 05h, 6Ah, 00h, 83h, 0ECh, 08h
P_g_backgroundMenuLen   EQU $-P_g_backgroundMenu
P_g_overlayMenu         DB 8Bh, 0F0h, 83h, 0C4h, 14h, 85h, 0F6h, 74h, 2Ah, 6Ah, 00h, 68h, 0FFh, 0FFh, 0FFh, 7Fh, 6Ah, 00h, 6Ah, 05h, 6Ah, 00h, 83h, 0ECh, 08h
P_g_overlayMenuLen      EQU $-P_g_overlayMenu

;---------------------------
; Patch Location Address 
;---------------------------
PatchLocation           DD 0 ; call XXXEEgame:luaL_loadstring replaced with call EEex.dll:EEexLuaInit


;---------------------------
; Global EE Variables 
;---------------------------
pp_lua                  DD 0 ; pattern address of p_lua
p_lua                   DD 0 ; pointer to global lua variable
g_lua                   DD 0 ; actual content of global lua variable
pp_pChitin              DD 0 ; pattern address of p_pChitin
p_pChitin               DD 0 ; pointer to global chitin variable
g_pChitin               DD 0 ; actual content of global chitin variable
pp_pBaldurChitin        DD 0 ; pattern address of p_pBaldurChitin
p_pBaldurChitin         DD 0 ; pointer to global baldur chitin variable
g_pBaldurChitin         DD 0 ; actual content of global baldur chitin variable
pp_backgroundMenu       DD 0 ; pattern address of p_backgroundMenu
p_backgroundMenu        DD 0 ; pointer to global backgroundMenu variable
g_backgroundMenu        DD 0 ; actual content of backgroundMenu variable
pp_overlayMenu          DD 0 ; pattern address of p_overlayMenu
p_overlayMenu           DD 0 ; pointer to global overlayMenu variable
g_overlayMenu           DD 0 ; actual content of overlayMenu variable
g_biffs                 DD 0 ; 
g_crashReportFunction   DD 0 ; 
g_cursorColor           DD 0 ; 
g_drawBackend           DD 0 ; 

g_pRegisteredFonts      DD 0 ; 
g_tooltipSnd            DD 0 ; 


;---------------------------
; EE function pointers:
;---------------------------
Func_Lua_createtable    Lua_createtablePtr 0
Func_Lua_createtablex   Lua_createtablexPtr 0 ; override for no params of lua_createtable
Func_Lua_getglobal      Lua_getglobalPtr 0
Func_Lua_gettop         Lua_gettopPtr 0
Func_Lua_pcallk         Lua_pcallkPtr 0
Func_Lua_pushcclosure   Lua_pushcclosurePtr 0
Func_Lua_pushlightuserdata Lua_pushlightuserdataPtr 0
Func_Lua_pushlstring    Lua_pushlstringPtr 0
Func_Lua_pushnumber     Lua_pushnumberPtr 0
Func_Lua_pushstring     Lua_pushstringPtr 0
Func_Lua_rawgeti        Lua_rawgetiPtr 0
Func_Lua_rawlen         Lua_rawlenPtr 0
Func_Lua_setfield       Lua_setfieldPtr 0
Func_Lua_setglobal      Lua_setglobalPtr 0
Func_Lua_settable       Lua_settablePtr 0
Func_Lua_settop         Lua_settopPtr 0
Func_Lua_toboolean      Lua_tobooleanPtr 0
Func_Lua_tolstring      Lua_tolstringPtr 0
Func_Lua_tonumberx      Lua_tonumberxPtr 0
Func_Lua_touserdata     Lua_touserdataPtr 0
Func_Lua_type           Lua_typePtr 0
Func_Lua_typename       Lua_typenamePtr 0
Func_LuaL_loadstring    LuaL_loadstringPtr 0
Func__ftol2_sse         ftol2_ssePtr 0


ALIGN 16
;---------------------------
; Pattern Array
;---------------------------
IFDEF EEEX_LUALIB
; PATTERN Structure:     F  T  PatBytes                   PatLength              VerBytes                VerLength              PAdj VAdj FuncAddress
Patterns                \
PATTERN                 <0, 0, Offset P_PatchLocation,    P_PatchLocationLen,    Offset V_PatchLocation, V_PatchLocationLen,     -5,  24, Offset PatchLocation>
PATTERN                 <0, 0, Offset P_Lua_setglobal,    P_Lua_setglobalLen,    Offset V_Lua_setglobal, V_Lua_setglobalLen,      0, 103, Offset Func_Lua_setglobal> ; comment out to use lua_setglobalx
PATTERN                 <0, 0, Offset P_LuaL_loadstring,  P_LuaL_loadstringLen,  0,                      V_LuaL_loadstringLen,  -20,   0, Offset Func_LuaL_loadstring>
PATTERN                 <0, 0, Offset P__ftol2_sse,       P__ftol2_sseLen,       0,                      V__ftol2_sseLen,        -7,   0, Offset Func__ftol2_sse>

PATTERN                 <0, 1, Offset P_g_pChitin,        P_g_pChitinLen,        0,                      0,                      11,   0, Offset p_pChitin>
PATTERN                 <0, 1, Offset P_g_pBaldurChitin,  P_g_pBaldurChitinLen,  0,                      0,                      11,   0, Offset p_pBaldurChitin>
PATTERN                 <0, 1, Offset P_g_backgroundMenu, P_g_backgroundMenuLen, 0,                      0,                     -23,   0, Offset p_backgroundMenu>
PATTERN                 <0, 1, Offset P_g_overlayMenu,    P_g_overlayMenuLen,    0,                      0,                     -13,   0, Offset p_overlayMenu>
ELSE

; PATTERN Structure:     F  T  PatBytes                   PatLength              VerBytes                VerLength              PAdj VAdj FuncAddress
Patterns                \
PATTERN                 <0, 0, Offset P_PatchLocation,    P_PatchLocationLen,    Offset V_PatchLocation, V_PatchLocationLen,     -5,  24, Offset PatchLocation>
PATTERN                 <0, 0, Offset P_Lua_createtable,  P_Lua_createtableLen,  0,                      0,                     -75,   0, Offset Func_Lua_createtable>
PATTERN                 <0, 0, Offset P_Lua_getglobal,    P_Lua_getglobalLen,    Offset V_Lua_getglobal, V_Lua_getglobalLen,      0,  87, Offset Func_Lua_getglobal>
PATTERN                 <0, 0, Offset P_Lua_gettop,       P_Lua_gettopLen,       0,                      0,                       0,   0, Offset Func_Lua_gettop>
PATTERN                 <0, 0, Offset P_Lua_pcallk,       P_Lua_pcallkLen,       0,                      0,                     -20,   0, Offset Func_Lua_pcallk>
PATTERN                 <0, 0, Offset P_Lua_pushcclosure, P_Lua_pushcclosureLen, 0,                      0,                       0,   0, Offset Func_Lua_pushcclosure>
PATTERN                 <0, 0, Offset P_Lua_pushlightuserdata, P_Lua_pushlightuserdataLen, 0,            0,                       0,   0, Offset Func_Lua_pushlightuserdata>
PATTERN                 <0, 0, Offset P_Lua_pushlstring,  P_Lua_pushlstringLen,  0,                      0,                       0,   0, Offset Func_Lua_pushlstring>
PATTERN                 <0, 0, Offset P_Lua_pushnumber,   P_Lua_pushnumberLen,   0,                      0,                       0,   0, Offset Func_Lua_pushnumber>
PATTERN                 <0, 0, Offset P_Lua_pushstring,   P_Lua_pushstringLen,   0,                      0,                       0,   0, Offset Func_Lua_pushstring>
PATTERN                 <0, 0, Offset P_Lua_rawgeti,      P_Lua_rawgetiLen,      Offset V_Lua_rawgeti,   V_Lua_rawgetiLen,      -27, -10, Offset Func_Lua_rawgeti>
PATTERN                 <0, 0, Offset P_Lua_rawlen,       P_Lua_rawlenLen,       Offset V_Lua_rawlen,    V_Lua_rawlenLen,       -14, -15, Offset Func_Lua_rawlen>
PATTERN                 <0, 0, Offset P_Lua_setfield,     P_Lua_setfieldLen,     0,                      0,                     -19,   0, Offset Func_Lua_setfield>
PATTERN                 <0, 0, Offset P_Lua_setglobal,    P_Lua_setglobalLen,    Offset V_Lua_setglobal, V_Lua_setglobalLen,      0, 103, Offset Func_Lua_setglobal>
PATTERN                 <0, 0, Offset P_Lua_settable,     P_Lua_settableLen,     0,                      0,                      -7,   0, Offset Func_Lua_settable>
PATTERN                 <0, 0, Offset P_Lua_settop,       P_Lua_settopLen,       0,                      0,                       0,   0, Offset Func_Lua_settop>
PATTERN                 <0, 0, Offset P_Lua_toboolean,    P_Lua_tobooleanLen,    0,                      0,                     -14,   0, Offset Func_Lua_toboolean>
PATTERN                 <0, 0, Offset P_Lua_tolstring,    P_Lua_tolstringLen,    0,                      0,                       0,   0, Offset Func_Lua_tolstring>
PATTERN                 <0, 0, Offset P_Lua_tonumberx,    P_Lua_tonumberxLen,    0,                      0,                     -83,   0, Offset Func_Lua_tonumberx>
PATTERN                 <0, 0, Offset P_Lua_touserdata,   P_Lua_touserdataLen,   0,                      0,                     -14,   0, Offset Func_Lua_touserdata>
PATTERN                 <0, 0, Offset P_Lua_type,         P_Lua_typeLen,         0,                      0,                     -21,   0, Offset Func_Lua_type>
PATTERN                 <0, 0, Offset P_Lua_typename,     P_Lua_typenameLen,     0,                      0,                       0,   0, Offset Func_Lua_typename>
PATTERN                 <0, 0, Offset P_LuaL_loadstring,  P_LuaL_loadstringLen,  0,                      V_LuaL_loadstringLen,  -20,   0, Offset Func_LuaL_loadstring>
PATTERN                 <0, 0, Offset P__ftol2_sse,       P__ftol2_sseLen,       0,                      0,                      -7,   0, Offset Func__ftol2_sse>

PATTERN                 <0, 1, Offset P_g_pChitin,        P_g_pChitinLen,        0,                      0,                      11,   0, Offset pp_pChitin>
PATTERN                 <0, 1, Offset P_g_pBaldurChitin,  P_g_pBaldurChitinLen,  0,                      0,                      11,   0, Offset pp_pBaldurChitin>
PATTERN                 <0, 1, Offset P_g_backgroundMenu, P_g_backgroundMenuLen, 0,                      0,                     -23,   0, Offset pp_backgroundMenu>
PATTERN                 <0, 1, Offset P_g_overlayMenu,    P_g_overlayMenuLen,    0,                      0,                     -13,   0, Offset pp_overlayMenu>



ENDIF

PatternsSize            EQU $-Patterns
TotalPatterns           DD (PatternsSize / SIZEOF PATTERN)
FoundPatterns           DD 0


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


EEEX_ALIGN
;------------------------------------------------------------------------------
; PatternMaskVerify - Verify a pattern that uses a mask (for wildcard)
; that matches at the specified address.
; 
; lpdwMasks is a pointer to an array of DWORD mask values.
; dwNoMasks is number of DWORDs in the mask array pointed to by lpdwMasks.
;
; Bits set to 1 for each byte position in the pattern are compared normally
; Bits set to 0 for each byte position in the pattern are skipped, which is the
; equivalant of ?? for the byte.
;
; Note: Visually when defining bit masks - masks are in reverse order of the
; bytes they represent the mask for. 

; 83h,0C4h,"?",85h - byte in pos 3 is wildcard (byte value doesnt matter)
;
; Bits: 31               14             0
;        --------------------------------
; Mask:  xxxxxxxxxxxxxxxxxxxxxxxxxxxx1011 -> 3rd bit is 0 (x = ignore)
;
; Bit value in mask: 0 = wildcard (ignore byte), 1 = compare byte
; Mask of 0FFFFFFFFh is all set to 1
; lpdwMasks mask array must be DWORDS. dwMasksLength will be a multiple of 4.
;
; if mask array DWORDS are less than total number of pattern bytes that they
; represent, then anything greater than that is considered to require normal
; pattern byte match and compare. For example if a pattern was greater than 32
; bytes long and had a single DWORD mask (32 bits) then anything after pos 31 
; will be compared, as per normal (assumes mask is 0FFFFFFFFh from that point 
; on in the pattern essentially)
;
; Returns: TRUE if it matches, FALSE if it doesnt.
;------------------------------------------------------------------------------
PatternMaskVerify PROC USES EBX ECX EDI ESI lpdwAddress:DWORD, lpdwPatternBytes:DWORD, dwPatternLength:DWORD, lpdwMasks:DWORD, dwNoMasks:DWORD
    LOCAL pos:DWORD
    
    .IF lpdwAddress == 0 || lpdwPatternBytes == 0 || dwPatternLength == 0
        mov eax, TRUE ; if pattern bytes is 0 then basically mark it as found and skip
        ret
    .ENDIF
    
    .IF lpdwMasks == 0 || dwNoMasks == 0 ; in no mask then do basic verify instead 
        Invoke PatternVerify, lpdwAddress, lpdwPatternBytes, dwPatternLength
        ret
    .ENDIF
    
    mov esi, lpdwAddress
    mov edi, lpdwPatternBytes
    mov pos, 0
    mov eax, 0
    .WHILE eax < dwPatternLength
        mov eax, pos
        shr eax, 05h ; div by 32 to get index into mask array
        .IF eax > dwNoMasks ; we assume anything > total masks in array is ok to compare
            movzx eax, byte ptr [esi]
            movzx ebx, byte ptr [edi]
            .IF al != bl
                mov eax, FALSE
                ret
            .ENDIF
        .ELSE
            mov ebx, lpdwMasks
            lea eax, [ebx+eax*SIZEOF(DWORD)] ; get ptr to current mask dword value: maskbase + index * 4
            mov eax, [eax] ; get current mask dword value (xxxxxxxxxxxxxxxxx111111111110111)
            .IF eax == 0FFFFFFFFh ; skip mask check as all set to 1 - do normal compare
                movzx eax, byte ptr [esi]
                movzx ebx, byte ptr [edi]
                .IF al != bl
                    mov eax, FALSE
                    ret
                .ENDIF
            .ELSE
                ; eax is mask
                mov ecx, pos
                and ecx, 31d ; (a && (b-1) = patpos mod 32) to get bit position in mask
                shr eax, cl ; shift mask value by mod 32 of pos to get bit into lowest part of register
                and eax, 1 ; mask off bit 1 from current mask dword
                .IF eax == 1 ; do normal compare
                    movzx eax, byte ptr [esi]
                    movzx ebx, byte ptr [edi]
                    .IF al != bl
                        mov eax, FALSE
                        ret
                    .ENDIF
                .ELSE ; found a wildcard so skip this byte
                    inc esi
                    inc edi
                    inc pos
                    mov eax, pos
                    .IF eax >= dwPatternLength
                        .BREAK
                    .ENDIF
                .ENDIF
            .ENDIF
        .ENDIF
        inc esi
        inc edi
        inc pos
        mov eax, pos
    .ENDW
    mov eax, TRUE    

    ret
PatternMaskVerify ENDP






















