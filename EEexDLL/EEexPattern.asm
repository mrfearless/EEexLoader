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
; Patterns are prefixed with a 'P_'. Subpatterns used to verify/confirm that 
; the pattern is the correct one are prefixed with a 'V_'. The length of byte 
; patterns are constants (EQU) rather than assiging more variables. The length
; of patterns are calculated with the $-var assembly trick.  
;
; The FuncAddress field of the PATTERN structure stores a pointer to a 
; variable that will hold a value. These values are either function address
; locations or game global variable locations. 

; When verifying pattern addresses saved to the ini file and read back in at
; startup, the address is adjusted in reverse - back from where the function
; location or game global variable location is - to the location of the actual
; pattern, so we can perform a byte match verification with the pattern in our
; PATTERN entry vs the bytes read in from the game exe. Any checks on any 
; subpatterns will also occur. 
;
; Variables used to store the function pointers are prefixed with a 'F_', and 
; variables used to store game globals are prefixed with a 'pp_'. The pp stands
; for pattern pointer as game globals are usually read from a DWORD value in the
; game code (from push instructions typically). 

; The address of the pattern location that points to the DWORD to read are 
; stored in these 'pp_' variables. The EEexGameGlobals resolves some of these 
; values as the game launches. The EEexLuaInit further resolves the values if 
; needed (? for now it does).
; 
; Function string names or global string names are stored as a pointer to the 
; actual string in the PatName field - used for logging and debug purposes.
;
; The ini string name used to read and write the pattern name may be different
; so that the ini file can read it properly: operator-equ vs operator= 
; due to the way ini files can fail to read key values correctly if using = in
; the keyname.
;
; The lua functions have a typedef to allow us to use them in EEexLua.asm
; Using the 'F_' function pointers we can call functions with these, for 
; example: call F_Lua_pushstring
; 
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; EEexPattern Prototypes
;------------------------------------------------------------------------------
PatternVerify           PROTO :DWORD,:DWORD,:DWORD               ; lpdwAddress, lpdwPatternBytes, dwPatternLength
PatternMaskVerify       PROTO :DWORD,:DWORD,:DWORD,:DWORD,:DWORD ; lpdwAddress, lpdwPatternBytes, dwPatternLength, lpdwMasks, dwNoMasks


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
    PatName             DD 0 ; Pointer to zero terminated string that contains pattern function or global variable name
PATTERN                 ENDS
ENDIF


.DATA

;---------------------------
; Byte search patterns
;---------------------------
ALIGN 4
P_PatchLocation         DB 83h,0C4h,30h,85h,0C0h,75h,14h,50h,50h,50h,6Ah,0FFh,50h,0FFh,35h
P_PatchLocationLen      EQU $-P_PatchLocation
V_PatchLocation         DB 83h,0C4h,18h,6Ah,00h
V_PatchLocationLen      EQU $-V_PatchLocation

;---------------------------
; Lua functions patterns
;---------------------------
P_Lua_createtable       DB 83h, 46h, 08h, 08h, 8Bh, 4Dh, 10h
P_Lua_createtableLen    EQU $-P_Lua_createtable

P_Lua_getglobal         DB 55h,8Bh,0ECh,53h,56h,8Bh,75h,08h,0BAh,02h,00h,00h,00h,57h,8Bh,46h,0Ch,8Bh,48h,28h
P_Lua_getglobalLen      EQU $-P_Lua_getglobal
V_Lua_getglobal         DB 83h,0C0h,0F8h
V_Lua_getglobalLen      EQU $-V_Lua_getglobal
P_Lua_gettop            DB 55h,8Bh,0ECh,8Bh,45h,08h,8Bh,48h,10h,8Bh,40h,08h,2Bh,01h,83h,0E8h,08h,0C1h,0F8h,03h,5Dh,0C3h
P_Lua_gettopLen         EQU $-P_Lua_gettop
P_Lua_pcallk            DB 8Bh,55h,14h,53h,8Bh,5Dh,0Ch,56h,8Bh,75h,08h,57h,85h,0D2h
P_Lua_pcallkLen         EQU $-P_Lua_pcallk
P_Lua_pushcclosure      DB 55h,8Bh,0ECh,83h,0E4h,0F8h,56h,57h,8Bh,7Dh,10h,85h,0FFh,75h,1Ch,8Bh,55h,08h,8Bh,45h,0Ch,8Bh,4Ah,08h
                        DB 89h,01h,0C7h,41h,04h,16h,0A5h,0F7h,7Fh,83h,42h,08h,08h,5Fh,5Eh,8Bh,0E5h,5Dh,0C3h
P_Lua_pushcclosureLen   EQU $-P_Lua_pushcclosure
V_Lua_pushcclosure      DB 0,0,0,0
V_Lua_pushcclosureLen   EQU 0 ; $-V_Lua_pushcclosure
P_Lua_pushlightuserdata DB 55h,8Bh,0ECh,8Bh,55h,08h,8Bh,45h,0Ch,8Bh,4Ah,08h,89h,01h,0C7h,41h,04h,02h,0A5h,0F7h,7Fh,83h,42h,08h,08h,5Dh,0C3h
P_Lua_pushlightuserdataLen EQU $-P_Lua_pushlightuserdata
P_Lua_pushlstring       DB 55h,8Bh,0ECh,83h,0E4h,0F8h,51h,53h,56h,57h,8Bh,0F9h,8Bh,0DAh,8Bh,77h,0Ch,83h,7Eh,0Ch,00h,7Eh,1Fh,80h,7Eh,37h,00h,74h,07h
P_Lua_pushlstringLen    EQU $-P_Lua_pushlstring
P_Lua_pushnumber        DB 55h,8Bh,0ECh,8Bh,4Dh,08h,0DDh,45h,0Ch,8Bh,51h,08h,0DDh,1Ah,8Bh,42h,04h,25h,00h,0FFh,0FFh,7Fh,3Dh,00h
                        DB 0A5h,0F7h,7Fh,74h,08h,8Dh,42h,08h,89h,41h,08h,5Dh,0C3h
P_Lua_pushnumberLen     EQU $-P_Lua_pushnumber
P_Lua_pushstring        DB 55h,8Bh,0ECh,83h,0E4h,0F8h,56h,57h,8Bh,7Dh,0Ch,85h,0FFh
P_Lua_pushstringLen     EQU $-P_Lua_pushstring
P_Lua_rawgeti           DB 8Bh,56h,08h,8Bh,08h,89h,0Ah,8Bh,40h,04h,89h,42h,04h,83h,46h,08h,08h,5Eh,5Dh,0C3h
P_Lua_rawgetiLen        EQU $-P_Lua_rawgeti
V_Lua_rawgeti           DB 8Bh,55h,10h,8Bh,08h
V_Lua_rawgetiLen        EQU 0 ; $-V_Lua_rawgeti
P_Lua_rawlen            DB 8Bh,50h,04h,8Bh,0CAh,81h,0E1h,00h,0FFh,0FFh,7Fh,81h,0F9h,00h,0A5h,0F7h,7Fh,0B9h,03h,00h,00h,00h,75h,03h
                        DB 0Fh,0B6h,0CAh,83h,0E1h,0Fh,83h,0E9h,04h
P_Lua_rawlenLen         EQU $-P_Lua_rawlen
V_Lua_rawlen            DB 0CCh,55h
V_Lua_rawlenLen         EQU 0 ; $-V_Lua_rawlen
P_Lua_setfield          DB 8Bh,7Eh,08h,8Bh,0D8h,8Bh,55h,10h,8Dh,4Fh,08h,89h,4Eh,08h
P_Lua_setfieldLen       EQU $-P_Lua_setfield
P_Lua_setglobal         DB 55h,8Bh,0ECh,53h,56h,8Bh,75h,08h,0BAh,02h,00h,00h,00h,57h,8Bh,46h,0Ch,8Bh,48h,28h
P_Lua_setglobalLen      EQU $-P_Lua_setglobal
V_Lua_setglobal         DB 83h,46h,08h,0F0h
V_Lua_setglobalLen      EQU $-V_Lua_setglobal
P_Lua_settable          DB 8Bh,75h,08h,8Bh,4Eh,08h,8Dh,41h,0F8h
P_Lua_settableLen       EQU $-P_Lua_settable
P_Lua_settop            DB 55h,8Bh,0ECh,8Bh,45h,08h,8Bh,48h,10h,8Bh,11h,8Bh,4Dh,0Ch,85h,0C9h
P_Lua_settopLen         EQU $-P_Lua_settop
P_Lua_toboolean         DB 8Bh,48h,04h,81h,0F9h,00h,0A5h,0F7h,7Fh,74h,14h,81h,0F9h,01h,0A5h,0F7h,7Fh,75h,05h,83h,38h,00h,74h,07h,0B8h
                        DB 01h,00h,00h,00h,5Dh,0C3h,33h,0C0h,5Dh,0C3h
P_Lua_tobooleanLen      EQU $-P_Lua_toboolean
P_Lua_tolstring         DB 55h,8Bh,0ECh,83h,0E4h,0F8h,51h,8Bh,55h,0Ch,56h,8Bh,75h,08h,8Bh,0CEh
P_Lua_tolstringLen      EQU $-P_Lua_tolstring
P_Lua_tonumberx         DB 83h,0C4h,04h,85h,0C0h,74h,28h,0DDh,44h,24h,08h,8Dh,44h,24h,08h,0DDh,5Ch,24h,08h,85h,0F6h,74h,06h,0C7h,06h
                        DB 01h,00h,00h,00h,0DDh,00h,5Eh,8Bh,4Ch,24h,10h,33h,0CCh
P_Lua_tonumberxLen      EQU $-P_Lua_tonumberx
P_Lua_touserdata        DB 8Bh,50h,04h,8Bh,0CAh,81h,0E1h,00h,0FFh,0FFh,7Fh,81h,0F9h,00h,0A5h,0F7h,7Fh,0B9h,03h,00h,00h,00h,75h,03h,0Fh
                        DB 0B6h,0CAh,83h,0E1h,0Fh,83h,0E9h,02h,74h,10h,83h,0E9h,05h,74h,04h,33h,0C0h,5Dh
P_Lua_touserdataLen     EQU $-P_Lua_touserdata
P_Lua_type              DB 8Bh,48h,04h,8Bh,0C1h,25h,00h,0FFh,0FFh,7Fh,3Dh,00h,0A5h,0F7h,7Fh,0B8h,03h,00h,00h,00h,75h,03h,0Fh,0B6h,0C1h,83h,0E0h,0Fh,5Dh
P_Lua_typeLen           EQU $-P_Lua_type
P_Lua_typename          DB 55h,8Bh,0ECh,8Bh,45h,0Ch,8Bh,04h,85h
P_Lua_typenameLen       EQU $-P_Lua_typename
P_LuaL_loadstring       DB 8Bh,55h,0Ch,8Bh,0C2h,56h,8Bh,75h,08h,57h,8Dh,78h,01h,8Ah,08h,40h,84h,0C9h
P_LuaL_loadstringLen    EQU $-P_LuaL_loadstring
;---------------------------
; Other functions patterns
;---------------------------
P__ftol2_sse            DB 74h,2Dh,55h,8Bh,0ECh,83h,0ECh,08h,83h,0E4h,0F8h,0DDh,1Ch,24h,0F2h,0Fh,2Ch,04h,24h,0C9h,0C3h
P__ftol2_sseLen         EQU $-P__ftol2_sse
P__mbscmp               DB 55h,8Bh,0ECh,6Ah,00h,0FFh,75h,0Ch,0FFh,75h,08h,0E8h,05h,00h,00h,00h,83h,0C4h,0Ch,5Dh,0C3h,55h,8Bh,0ECh
                        DB 83h,0ECh,10h,8Dh,4Dh,0F0h,53h,56h,57h,0FFh,75h,10h
P__mbscmpLen            EQU $-P__mbscmp
P_p_malloc              DB 55h,8Bh,0ECh,56h,8Bh,75h,08h,83h,0FEh,0E0h,77h,6Fh,53h,57h
P_p_mallocLen           EQU $-P_p_malloc
;---------------------------
; EE game functions patterns
;---------------------------
; CAIObjectType
P_CAIObjectTypeDecode   DB 53h,56h,57h,8Bh,7Dh,08h,8Bh,0D9h,53h,8Dh,8Dh,34h,0FFh,0FFh,0FFh,89h,0BDh,40h,0FFh,0FFh,0FFh,89h,45h,0E8h
                        DB 33h,0F6h,0C7h,45h,0ECh,00h,00h,00h,00h,66h,0C7h,45h,0F9h,00h,00h,0C6h,45h,0FBh,00h,0C7h,45h,0F0h,0FFh,0FFh
                        DB 0FFh,0FFh,0C7h,45h,0F4h,00h,00h,00h,00h,0C6h,45h,0F8h,00h
P_CAIObjectTypeDecodeLen EQU $-P_CAIObjectTypeDecode
P_CAIObjectTypeRead     DB 89h,45h,0C8h,8Bh,0F1h,8Dh,45h,0F8h,50h,8Dh,45h,0F4h,50h,8Dh,45h,0F0h,50h,8Dh,45h,0ECh,50h,8Dh,45h,0E8h,50h,8Dh
                        DB 45h,0E4h,50h,8Dh,45h,0E0h,50h,8Dh,45h,0DCh,50h,8Dh,45h,0D8h,50h,8Dh,45h,0D4h,50h,8Dh,45h,0D0h,50h,8Dh,45h,0CCh,50h
P_CAIObjectTypeReadLen  EQU $-P_CAIObjectTypeRead
P_CAIObjectTypeSet      DB 55h,8Bh,0ECh,8Bh,55h,08h,0Fh,0B6h,42h,04h,88h,41h,04h,0Fh,0B6h,42h,05h,88h,41h,05h,0Fh,0B6h,42h,06h,88h,41h
                        DB 06h,0Fh,0B6h,42h,07h,88h,41h,07h,0Fh,0B6h,42h,11h,88h,41h,11h,0Fh,0B6h,42h,12h,88h,41h,12h,0Fh,0B6h,42h,13h
                        DB 88h,41h,13h,8Bh,42h,08h,89h,41h,08h,8Bh,42h,0Ch,89h,41h,0Ch,0Fh,0B6h,42h,10h,88h,41h,10h,89h,55h,08h,5Dh
P_CAIObjectTypeSetLen   EQU $-P_CAIObjectTypeSet
P_CAIObjectTypeSSC      DB 8Bh,55h,08h,0Fh,0B6h,02h,88h,41h,0Ch,0Fh,0B6h,42h,01h,88h,41h,0Dh,0Fh,0B6h,42h,02h,88h,41h,0Eh,0Fh
                        DB 0B6h,42h,03h,88h,41h,0Fh,0Fh,0B6h,42h,04h,88h,41h,10h
P_CAIObjectTypeSSCLen   EQU $-P_CAIObjectTypeSSC
P_CAIObjectTypeOpEqu2   DB 55h,8Bh,0ECh,8Bh,55h,08h,8Ah,41h,04h,3Ah,42h,04h,75h,41h,8Ah,41h,05h,3Ah,42h,05h,75h,39h,8Ah,41h,06h,3Ah
                        DB 42h,06h,75h,31h,8Ah,41h,07h,3Ah,42h,07h,75h,29h,8Ah,41h,11h,3Ah,42h,11h,75h,21h,8Ah,41h,13h,3Ah,42h,13h,75h
                        DB 19h,8Ah,41h,12h,3Ah,42h,12h,75h,11h,8Bh,41h,08h,3Bh,42h,08h,75h,09h,0B8h,01h,00h,00h,00h,5Dh,0C2h,04h,00h
                        DB 33h,0C0h,5Dh,0C2h,04h,00h
P_CAIObjectTypeOpEqu2Len EQU $-P_CAIObjectTypeOpEqu2

P_CAIObjectTypeOpEqu    DB 55h,8Bh,0ECh,56h,0FFh,75h,08h,8Bh,0F1h,0E8h
P_CAIObjectTypeOpEquLen EQU $-P_CAIObjectTypeOpEqu
V_CAIObjectTypeOpEqu    DB 8Bh,0C6h,5Eh,5Dh,0C2h,04h,00h
V_CAIObjectTypeOpEquLen EQU $-V_CAIObjectTypeOpEqu
; CDerivedStats
P_CDerivedStatsGetAtOffset DB 0Fh,0BFh,41h,04h,5Dh,0C2h,04h,00h,0Fh,0BFh,41h,06h
P_CDerivedStatsGetAtOffsetLen EQU $-P_CDerivedStatsGetAtOffset
P_CDerivedStatsGetLevel DB 55h,8Bh,0ECh,51h,8Dh,45h,0FCh,50h,0FFh,75h,0Ch,0FFh,75h,08h
P_CDerivedStatsGetLevelLen EQU $-P_CDerivedStatsGetLevel
V_CDerivedStatsGetLevel DB 8Ah,00h
V_CDerivedStatsGetLevelLen EQU $-V_CDerivedStatsGetLevel
P_CDerivedStatsSetLevel DB 55h,8Bh,0ECh,51h,8Dh,45h,0FCh,50h,0FFh,75h,0Ch,0FFh,75h,08h
P_CDerivedStatsSetLevelLen EQU $-P_CDerivedStatsSetLevel
V_CDerivedStatsSetLevel DB 0Fh,0B6h,0C8h
V_CDerivedStatsSetLevelLen EQU $-V_CDerivedStatsSetLevel
P_CDerivedStatsGetSpellState DB 0F7h, 0D8h, 5Eh, 1Bh, 0C0h, 0F7h, 0D8h, 5Dh, 0C2h, 04h, 00h
P_CDerivedStatsGetSpellStateLen EQU $-P_CDerivedStatsGetSpellState
P_CDerivedStatsSetSpellState DB 81h,0F9h,00h,01h,00h,00h,72h,07h,33h,0C0h,5Eh,5Dh,0C2h,04h,00h,8Bh,0C1h,0BAh,01h,00h,00h,00h,0C1h
                             DB 0E8h,05h,83h,0E1h,1Fh,0D3h,0E2h,8Dh,0Ch,86h
P_CDerivedStatsSetSpellStateLen EQU $-P_CDerivedStatsSetSpellState
P_CDerivedStatsGetWarriorLevel DB 55h, 8Bh, 0ECh, 8Bh, 55h, 08h, 0Fh, 0B6h, 0C2h, 83h, 0C0h, 0FEh, 83h, 0F8h, 12h
P_CDerivedStatsGetWarriorLevelLen EQU $-P_CDerivedStatsGetWarriorLevel
P_CDerivedStatsReload   DB 8Bh,7Dh,08h,89h,75h,0E8h,8Bh,47h,18h,89h,06h,0Fh,0B7h,47h,1Eh
P_CDerivedStatsReloadLen EQU $-P_CDerivedStatsReload
; CGameSprite
P_CGameSpriteCGameSprite DB 8Dh, 0A4h, 24h, 00h, 00h, 00h, 00h, 8Bh, 5Fh, 08h, 8Bh, 3Fh, 85h, 0DBh ; CGameSprite::~CGameSprite
P_CGameSpriteCGameSpriteLen EQU $-P_CGameSpriteCGameSprite ; for BG2EE, IWDEE, BGSOD PatAdj and VerAdj is -95, for PSTEE it is -94. Torment requires its own specific pattern entry to be excluded if game != torment
P_CGameSpriteAddKnownSpell DB 8Dh,4Dh,0C0h,53h,8Bh,5Dh,08h,56h,57h,8Bh,7Dh,10h,89h,7Dh,98h,89h,45h,0BCh
P_CGameSpriteAddKnownSpellLen EQU $-P_CGameSpriteAddKnownSpell
P_CGameSpriteAddKnownSpellMage DB 55h,8Bh,0ECh,8Bh,55h,0Ch,6Ah,01h,8Dh,04h,0D5h,00h,00h,00h,00h,2Bh,0C2h,05h,0D2h,01h,00h,00h
P_CGameSpriteAddKnownSpellMageLen EQU $-P_CGameSpriteAddKnownSpellMage
P_CGameSpriteAddKnownSpellPriest DB 55h,8Bh,0ECh,8Bh,55h,0Ch,6Ah,00h,8Dh,04h,0D5h,00h,00h,00h,00h,2Bh,0C2h,05h,0A1h,01h,00h,00h
P_CGameSpriteAddKnownSpellPriestLen EQU $-P_CGameSpriteAddKnownSpellPriest
P_CGameSpriteAddNewSA DB 0Fh,0B6h,0C0h,8Bh,0CBh,66h,2Bh,0F0h,0Fh,0B7h,0C6h,50h,6Ah,0Bh ; CGameSpriteAddNewSpecialAbilities
P_CGameSpriteAddNewSALen EQU $-P_CGameSpriteAddNewSA
V_CGameSpriteAddNewSA DB 0C2h,08h,00h
V_CGameSpriteAddNewSALen EQU $-V_CGameSpriteAddNewSA
P_CGameSpriteGetActiveStats DB 83h,0B9h,48h,37h,00h,00h,00h,8Dh,81h,30h,0Bh,00h,00h,75h,06h,8Dh,81h,54h,14h,00h,00h,0C3h
P_CGameSpriteGetActiveStatsLen EQU $-P_CGameSpriteGetActiveStats
P_CGameSpriteGetActiveProficiency DB 55h,8Bh,0ECh,8Bh,55h,08h,8Dh,42h,0A7h,83h,0F8h,2Dh,77h,2Fh,83h,0B9h,48h,37h,00h,00h,00h
P_CGameSpriteGetActiveProficiencyLen EQU $-P_CGameSpriteGetActiveProficiency
P_CGameSpriteGetKit     DB 0C1h, 0E0h, 10h, 0Bh, 0C1h, 0C3h
P_CGameSpriteGetKitLen  EQU $-P_CGameSpriteGetKit
P_CGameSpriteGetName    DB 89h,45h,0FCh,56h,8Bh,0F1h,83h,0BEh,1Ch,04h,00h,00h,0FFh
P_CGameSpriteGetNameLen EQU $-P_CGameSpriteGetName
P_CGameSpriteGetQuickButtons DB 8Dh,0B7h,80h,0Ah,00h,00h,33h,0DBh,89h,75h,88h,8Bh,0F7h,8Bh,7Dh,88h,89h,5Dh,84h,8Dh,49h,00h
P_CGameSpriteGetQuickButtonsLen EQU $-P_CGameSpriteGetQuickButtons
P_CGameSpriteMemorizeSpell DB 8Bh,5Dh,18h,89h,45h,0E4h,8Bh,45h,0Ch,56h,8Bh,0F1h,89h,45h,0E8h
P_CGameSpriteMemorizeSpellLen EQU $-P_CGameSpriteMemorizeSpell
P_CGameSpriteMemorizeSpellMage DB 8Dh,04h,0D5h,00h,00h,00h,00h,2Bh,0C2h,05h,0D2h,01h,00h,00h,8Dh,04h,86h,50h
P_CGameSpriteMemorizeSpellMageLen EQU $-P_CGameSpriteMemorizeSpellMage
P_CGameSpriteMemorizeSpellPriest DB 8Dh,04h,0D5h,00h,00h,00h,00h,2Bh,0C2h,05h,0A1h,01h,00h,00h,8Dh,04h,86h,50h
P_CGameSpriteMemorizeSpellPriestLen EQU $-P_CGameSpriteMemorizeSpellPriest
P_CGameSpriteMemorizeSpellInnate DB 8Dh,04h,0F5h,00h,00h,00h,00h,2Bh,0C6h,05h,11h,02h,00h,00h,8Dh,04h,81h,50h
P_CGameSpriteMemorizeSpellInnateLen EQU $-P_CGameSpriteMemorizeSpellInnate
P_CGameSpriteReadySpell DB 89h,85h,30h,0FFh,0FFh,0FFh,8Bh,46h,14h,0F6h,40h,0Ch,04h
P_CGameSpriteReadySpellLen EQU $-P_CGameSpriteReadySpell
P_CGameSpriteRemoveKnownSpell DB 85h,0F6h,74h,23h,8Bh,7Dh,08h,8Bh,5Eh,08h,8Dh,4Dh,0F4h,53h
P_CGameSpriteRemoveKnownSpellLen EQU $-P_CGameSpriteRemoveKnownSpell
P_CGameSpriteRemoveKnownSpellMage DB 55h,8Bh,0ECh,8Bh,45h,0Ch,8Dh,14h,0C5h,00h,00h,00h,00h,2Bh,0D0h,8Dh,81h,48h,07h,00h,00h,8Dh,04h,90h,89h,45h,0Ch,5Dh
P_CGameSpriteRemoveKnownSpellMageLen EQU $-P_CGameSpriteRemoveKnownSpellMage
P_CGameSpriteRemoveKnownSpellPriest DB 55h,8Bh,0ECh,8Bh,45h,0Ch,8Dh,14h,0C5h,00h,00h,00h,00h,2Bh,0D0h,8Dh,81h,84h,06h,00h,00h,8Dh,04h,90h,89h,45h,0Ch,5Dh
P_CGameSpriteRemoveKnownSpellPriestLen EQU $-P_CGameSpriteRemoveKnownSpellPriest
P_CGameSpriteRemoveKnownSpellInnate DB 55h,8Bh,0ECh,8Bh,45h,0Ch,8Dh,14h,0C5h,00h,00h,00h,00h,2Bh,0D0h,8Dh,81h,44h,08h,00h,00h,8Dh,04h,90h,89h,45h,0Ch,5Dh
P_CGameSpriteRemoveKnownSpellInnateLen EQU $-P_CGameSpriteRemoveKnownSpellInnate
P_CGameSpriteRemoveNewSA DB 0Fh,0B6h,0C0h,8Bh,0CBh,66h,2Bh,0F0h,0Fh,0B7h,0C6h,50h,6Ah,0Bh
P_CGameSpriteRemoveNewSALen EQU $-P_CGameSpriteRemoveNewSA
V_CGameSpriteRemoveNewSA DB 0C2h,04h,00h
V_CGameSpriteRemoveNewSALen EQU $-V_CGameSpriteRemoveNewSA
P_CGameSpriteRenderHealthBar DB 8Bh,4Bh,14h,8Bh,0F8h,8Dh,85h,98h,0FEh,0FFh,0FFh,50h,8Dh,85h,0F4h,0FEh,0FFh,0FFh
P_CGameSpriteRenderHealthBarLen EQU $-P_CGameSpriteRenderHealthBar
P_CGameSpriteSetCTT     DB 0Fh,0B6h,0C0h,8Bh,0CEh,6Ah,03h,89h,45h,0D8h
P_CGameSpriteSetCTTLen  EQU $-P_CGameSpriteSetCTT
P_CGameSpriteSetColor   DB 8Bh,5Dh,08h,56h,57h,8Bh,0F9h,8Dh,43h,0FFh,83h,0F8h,05h
P_CGameSpriteSetColorLen EQU $-P_CGameSpriteSetColor
P_CGameSpriteShatter    DB 8Dh,55h,0C8h,0FFh,76h,10h,0B8h,40h,02h,00h,00h
P_CGameSpriteShatterLen EQU $-P_CGameSpriteShatter
P_CGameSpriteUnmemorizeSpellMage DB 8Bh,0BCh,81h,7Ch,08h,00h,00h,8Dh,50h,56h
P_CGameSpriteUnmemorizeSpellMageLen EQU $-P_CGameSpriteUnmemorizeSpellMage
P_CGameSpriteUnmemorizeSpellPriest DB 8Bh,0BCh,81h,60h,08h,00h,00h,8Dh,50h,4Fh
P_CGameSpriteUnmemorizeSpellPriestLen EQU $-P_CGameSpriteUnmemorizeSpellPriest
P_CGameSpriteUnmemorizeSpellInnate DB 8Bh,0BCh,81h,0A0h,08h,00h,00h,8Dh,50h,5Fh
P_CGameSpriteUnmemorizeSpellInnateLen EQU $-P_CGameSpriteUnmemorizeSpellInnate
; CInfinity
P_CInfinityDrawLine     DB 0DBh,45h,0FCh,89h,45h,18h,8Bh,45h,1Ch,50h,0Dh,00h,00h,00h,0AAh
P_CInfinityDrawLineLen EQU $-P_CInfinityDrawLine
P_CInfinityDrawRectangle DB 8Bh,4Dh,14h,8Bh,0F8h,89h,4Dh,0C4h,0B8h,56h,55h,55h,55h,8Bh,4Dh,18h,0C1h,0E1h,02h,0F7h
                         DB 0E9h,0B8h,56h,55h,55h,55h,8Bh,0CAh,0C1h,0E9h,1Fh,03h,0CAh
P_CInfinityDrawRectangleLen EQU $-P_CInfinityDrawRectangle
P_CInfinityRenderAOE    DB 8Bh,46h,58h,2Bh,86h,0A0h,00h,00h,00h,8Bh,56h,5Ch,2Bh,96h,0A4h,00h,00h,00h,03h,45h,0E8h,03h,55h,0ECh,89h,45h,0F8h,89h,55h,0FCh
P_CInfinityRenderAOELen EQU $-P_CInfinityRenderAOE
; CInfGame
P_CInfGameAddCTA        DB 55h,8Bh,0ECh,56h,8Bh,75h,08h,57h,8Bh,0F9h,83h,0FEh,0FFh,74h,15h
P_CInfGameAddCTALen     EQU $-P_CInfGameAddCTA
V_CInfGameAddCTA        DB 53h
V_CInfGameAddCTALen     EQU $-V_CInfGameAddCTA
P_CInfGameAddCTF        DB 55h,8Bh,0ECh,56h,8Bh,75h,08h,57h,8Bh,0F9h,83h,0FEh,0FFh,74h,15h
P_CInfGameAddCTFLen     EQU $-P_CInfGameAddCTF
V_CInfGameAddCTF        DB 6Ah
V_CInfGameAddCTFLen     EQU $-V_CInfGameAddCTF
P_CInfGameGetCharacterId DB 55h,8Bh,0ECh,66h,8Bh,45h,08h,66h,3Bh,81h,08h,3Eh,00h,00h,7Ch,07h,83h,0C8h,0FFh
P_CInfGameGetCharacterIdLen EQU $-P_CInfGameGetCharacterId
; CObList
P_CObListRemoveAll      DB 56h,8Bh,0F1h,8Bh,4Eh,14h,0C7h,46h,0Ch,00h,00h,00h,00h,0C7h,46h,10h,00h,00h,00h,00h,0C7h
                        DB 46h,08h,00h,00h,00h,00h,0C7h,46h,04h,00h,00h,00h,00h,0E8h
P_CObListRemoveAllLen   EQU $-P_CObListRemoveAll
P_CObListRemoveHead     DB 55h,8Bh,0ECh,51h,56h,8Bh,0F1h,57h,8Bh,4Eh,04h,8Bh,01h,8Bh,79h,08h,89h,46h,04h,85h,0C0h
P_CObListRemoveHeadLen  EQU $-P_CObListRemoveHead
; CResRef
P_CResRefGetResRefStr   DB 56h,8Bh,75h,08h,0C6h,45h,0F8h,00h,89h,06h,8Dh,45h,0F0h,8Bh,11h,8Bh,49h,04h,89h,4Dh,0F4h,8Bh,0CEh,50h,89h,55h,0F0h
P_CResRefGetResRefStrLen EQU $-P_CResRefGetResRefStr
P_CResRefIsValid        DB 33h,0C0h,38h,01h,0Fh,95h,0C0h,0C3h
P_CResRefIsValidLen     EQU $-P_CResRefIsValid
P_CResRefCResRef        DB 33h,0C0h,89h,01h,89h,41h,04h,8Bh,0C1h,0C3h ; ~CResRef
P_CResRefCResRefLen     EQU $-P_CResRefCResRef
P_CResRefOpEqu          DB 55h,8Bh,0ECh,51h,8Bh,45h,0Ch,53h,56h,8Bh,0D9h,33h,0C9h,8Bh,30h,8Bh,46h,0F8h,89h,0Bh,89h,45h,0Ch,89h,4Bh,04h,85h,0C0h,7Eh,72h ; operator= \*
P_CResRefOpEquLen       EQU $-P_CResRefOpEqu
P_CResRefOpNotEqu       DB 55h,8Bh,0ECh,56h,57h,8Bh,7Dh,08h,33h,0F6h,2Bh,0F9h,8Dh,64h,24h,00h,8Ah,04h,0Fh,3Ch,61h,7Ch
                        DB 0Ch,3Ch,7Ah,7Fh,08h,0Fh,0BEh,0C0h,83h,0E8h,20h,0EBh,03h,0Fh,0BEh,0C0h,8Ah,11h,80h,0FAh,61h
                        DB 72h,0Dh,80h,0FAh,7Ah,77h,08h,0Fh,0B6h,0D2h,83h,0EAh,20h,0EBh,03h,0Fh,0B6h,0D2h,3Bh,0C2h,75h,13h
P_CResRefOpNotEquLen    EQU $-P_CResRefOpNotEqu
; CString
P_CStringOpPlus         DB 2Bh,0F1h,8Bh,45h,0Ch,8Bh,00h,89h,45h,10h,8Bh,40h,0F8h,89h,45h,08h,03h,0C6h ; operator+
P_CStringOpPlusLen      EQU $-P_CStringOpPlus
P_CStringCString        DB 56h,8Bh,0F1h,8Bh,0Eh,8Dh,41h,0F4h,3Bh,05h ; ~CString
P_CStringCStringLen     EQU $-P_CStringCString
P_CStringFindIndex      DB 55h,8Bh,0ECh,8Bh,55h,08h,3Bh,51h,0Ch,7Dh,12h,85h,0D2h,78h,0Eh,8Bh,41h,04h,74h,0Bh,8Bh,00h
                        DB 4Ah,75h,0FBh,5Dh,0C2h,04h,00h,33h,0C0h,5Dh,0C2h,04h,00h ; CList::FindIndex
P_CStringFindIndexLen   EQU $-P_CStringFindIndex
; CInfButtonArray
P_CInfButtonArraySetState DB 8Bh,87h,74h,14h,00h,00h,89h,87h,78h,14h,00h,00h,0C7h,87h,74h,14h,00h,00h,6Eh,00h,00h,00h
P_CInfButtonArraySetStateLen EQU $-P_CInfButtonArraySetState
P_CInfButtonArrayUpdateButtons DB 33h,0F6h,33h,0DBh,89h,85h,0D4h,0FDh,0FFh,0FFh,0C7h,85h,0E0h,0FDh,0FFh,0FFh,01h,00h
                               DB 00h,00h,89h,0B5h,0E4h,0FDh,0FFh,0FFh,89h,85h,0F0h,0FDh,0FFh,0FFh,89h,9Dh,0ECh,0FDh,0FFh,0FFh
P_CInfButtonArrayUpdateButtonsLen EQU $-P_CInfButtonArrayUpdateButtons
P_CInfButtonArraySTT    DB 55h,8Bh,0ECh,83h,0ECh,0Ch,83h,0B9h,74h,14h,00h,00h,00h
P_CInfButtonArraySTTLen EQU $-P_CInfButtonArraySTT
; CGameEffect
P_CGameEffectCGameEffect DB 8Bh,0F1h,57h,8Bh,7Dh,08h,8Dh,4Eh,04h
P_CGameEffectCGameEffectLen EQU $-P_CGameEffectCGameEffect
P_CGameEffectCopyFromBase DB 8Bh,5Dh,08h,8Dh,45h,0F4h
P_CGameEffectCopyFromBaseLen EQU $-P_CGameEffectCopyFromBase
P_CGameEffectGetItemEffect DB 8Bh,0F0h,83h,0C4h,04h,33h,0C0h,8Dh,4Eh,14h
P_CGameEffectGetItemEffectLen EQU $-P_CGameEffectGetItemEffect
; Misc
P_CGameObjectArrayGetDeny DB 0C7h,02h,00h,00h,00h,00h,83h,0F8h,0FFh,74h,40h,8Bh,0C8h,0C1h,0F9h,10h,81h,0E1h,0FFh,7Fh,00h,00h ; CGameObjectArray::GetShare 
P_CGameObjectArrayGetDenyLen EQU $-P_CGameObjectArrayGetDeny
P_CGameEffectFireSpell  DB 89h,4Dh,0B4h,89h,5Dh,0A8h,89h,45h,0A4h,56h,8Bh,75h,08h,85h,0DBh
P_CGameEffectFireSpellLen EQU $-P_CGameEffectFireSpell
P_CGameAIBaseFireSpellPoint DB 89h,45h,0FCh,8Bh,45h,08h,53h,56h,8Bh,75h,18h,8Bh,0D9h,89h,45h,0F0h,8Bh,45h,0Ch,57h,89h
                            DB 45h,0A4h,8Bh,45h,14h,6Ah,0Ch,89h,5Dh,0B8h,89h,45h,0B0h,89h,75h,0ACh
P_CGameAIBaseFireSpellPointLen EQU $-P_CGameAIBaseFireSpellPoint
P_dimmGetResObject      DB 55h,8Bh,0ECh,83h,0ECh,44h,56h,57h,8Dh,4Dh,0BCh
P_dimmGetResObjectLen   EQU $-P_dimmGetResObject
P_CAIActionDecode       DB 55h,8Bh,0ECh,56h,8Bh,75h,08h,57h,8Bh,0F9h,56h,8Dh,4Fh,04h
P_CAIActionDecodeLen    EQU $-P_CAIActionDecode
P_CListRemoveAt         DB 55h,8Bh,0ECh,8Bh,55h,08h,56h,8Bh,0F1h,8Bh,02h,3Bh,56h,04h,75h,05h,89h,46h,04h,0EBh,05h,8Bh,4Ah,04h
P_CListRemoveAtLen      EQU $-P_CListRemoveAt
P_CRuleTablesMapCSTS    DB 55h,8Bh,0ECh,8Bh,45h,08h,0Fh,0B7h,0C0h,3Dh,00h,04h,00h,00h,7Fh,43h,74h,3Bh,3Dh,80h,00h,00h,00h
P_CRuleTablesMapCSTSLen EQU $-P_CRuleTablesMapCSTS
P_operator_new          DB 69h,48h,14h,0FDh,43h,03h,00h,81h,0C1h,0C3h,9Eh,26h,00h,89h,48h,14h,0C1h,0E9h,10h,81h,0E1h,0FFh,7Fh,00h,00h,8Bh,0C1h,0C3h
P_operator_newLen       EQU $-P_operator_new
P_CAIScriptCAIScript    DB 8Bh,45h,08h,8Bh,0CBh,89h,45h,0F4h,8Bh,45h,0Ch,89h,45h,0F8h,8Dh,45h,0F4h,50h,8Dh,45h,0ECh
P_CAIScriptCAIScriptLen EQU $-P_CAIScriptCAIScript

;---------------------------
; EE game variable patterns
;---------------------------
P_g_pChitin             DB 98h,69h,0D8h,98h,00h,00h,00h,6Ah,14h,03h,1Dh
P_g_pChitinLen          EQU $-P_g_pChitin
P_g_pBaldurChitin       DB 66h,83h,0F8h,0FFh,0Fh,84h,0B6h,00h,00h,00h,0A1h
P_g_pBaldurChitinLen    EQU $-P_g_pBaldurChitin

P_g_backgroundMenu      DB 8Bh,0F0h,83h,0C4h,14h,85h,0F6h,74h,2Ah,6Ah,00h,68h,0FFh,0FFh,0FFh,7Fh,6Ah,00h
P_g_backgroundMenuLen   EQU $-P_g_backgroundMenu
P_g_overlayMenu         DB 85h,0C0h,74h,04h,8Bh,40h,10h,0C3h,33h,0C0h,0C3h
P_g_overlayMenuLen      EQU $-P_g_overlayMenu

P_CChitin_timer_ups     DB 5Fh,5Eh,83h,0F8h,0Ah,72h,05h,83h,0F8h,5Ah,76h,0Ah,0C7h,05h
P_CChitin_timer_upsLen  EQU $-P_CChitin_timer_ups
P_aB_1                  DB 83h,0C4h,08h,5Dh,0C3h,57h,8Bh,7Dh,0Ch,85h,0FFh,75h,15h
P_aB_1Len               EQU $-P_aB_1
P_CGameSprite_vftable   DB 55h,8Bh,0ECh,51h,53h,56h,8Bh,0F1h,57h,8Bh,0BEh,48h,33h,00h,00h,0C7h,06h
P_CGameSprite_vftableLen EQU $-P_CGameSprite_vftable
P_CAIObjectTypeANYONE   DB 8Dh,81h,14h,01h,00h,00h,0E9h,27h,0FFh,0FFh,0FFh
P_CAIObjectTypeANYONELen EQU $-P_CAIObjectTypeANYONE
P_VersionString_Push    DB 56h,8Bh,75h,08h,89h,06h,0FFh,35h;8Bh,77h,5Ch,85h,0F6h,74h,12h,8Bh,4Eh,08h,8Bh,36h,85h,0C9h
P_VersionString_PushLen EQU $-P_VersionString_Push
V_VersionString_Push    DB 83h,0C4h,18h,8Bh,0C6h,5Eh,5Dh,0C3h
V_VersionString_PushLen EQU $-V_VersionString_Push

;---------------------------
; Patch location address 
;---------------------------
PatchLocation           DD 0 ; call XXXEEgame:luaL_loadstring replaced with call EEex.dll:EEexLuaInit

;---------------------------
; Lua Function pointers
;---------------------------
; typedef prototypes:
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
F__mbscmp               DD 0 ; 
F_p_malloc              DD 0 ; Malloc

;---------------------------
; EE game function pointers
;---------------------------
; CAIObjectType
F_EE_CAIObjectTypeDecode         DD 0
F_EE_CAIObjectTypeRead           DD 0
F_EE_CAIObjectTypeSet            DD 0
F_EE_CAIObjectTypeSSC            DD 0 ; P_CAIObjectType::SetSpecialCase
F_EE_CAIObjectTypeOpEqu2         DD 0 ; CAIObjectType::operator==
F_EE_CAIObjectTypeOpEqu          DD 0 ; CAIObjectType::operator=
; CDerivedStats
F_EE_CDerivedStatsGetAtOffset    DD 0
F_EE_CDerivedStatsGetLevel       DD 0
F_EE_CDerivedStatsSetLevel       DD 0
F_EE_CDerivedStatsGetSpellState  DD 0
F_EE_CDerivedStatsSetSpellState  DD 0
F_EE_CDerivedStatsGetWarriorLevel DD 0
F_EE_CDerivedStatsReload         DD 0
; CGameSprite
F_EE_CGameSpriteCGameSprite      DD 0 ; CGameSprite::~CGameSprite
F_EE_CGameSpriteAddKnownSpell    DD 0
F_EE_CGameSpriteAddKnownSpellMage DD 0
F_EE_CGameSpriteAddKnownSpellPriest DD 0
F_EE_CGameSpriteAddNewSA         DD 0 ; CGameSprite::AddNewSpecialAbilities
F_EE_CGameSpriteGetActiveStats   DD 0
F_EE_CGameSpriteGetActiveProficiency DD 0
F_EE_CGameSpriteGetKit           DD 0
F_EE_CGameSpriteGetName          DD 0
F_EE_CGameSpriteGetQuickButtons  DD 0
F_EE_CGameSpriteMemorizeSpell    DD 0
F_EE_CGameSpriteMemorizeSpellMage DD 0
F_EE_CGameSpriteMemorizeSpellPriest DD 0
F_EE_CGameSpriteMemorizeSpellInnate DD 0
F_EE_CGameSpriteReadySpell       DD 0
F_EE_CGameSpriteRemoveKnownSpell DD 0
F_EE_CGameSpriteRemoveKnownSpellMage DD 0
F_EE_CGameSpriteRemoveKnownSpellPriest DD 0
F_EE_CGameSpriteRemoveKnownSpellInnate DD 0
F_EE_CGameSpriteRemoveNewSA      DD 0 ; CGameSprite::RemoveNewSpecialAbilities
F_EE_CGameSpriteRenderHealthBar  DD 0
F_EE_CGameSpriteSetCTT           DD 0 ; CGameSprite::SetCharacterToolTip
F_EE_CGameSpriteSetColor         DD 0
F_EE_CGameSpriteShatter          DD 0
F_EE_CGameSpriteUnmemorizeSpellMage DD 0
F_EE_CGameSpriteUnmemorizeSpellPriest DD 0
F_EE_CGameSpriteUnmemorizeSpellInnate DD 0
; CInfinity
F_EE_CInfinityDrawLine           DD 0
F_EE_CInfinityDrawRectangle      DD 0
F_EE_CInfinityRenderAOE          DD 0
; CInfGame
F_EE_CInfGameAddCTA              DD 0
F_EE_CInfGameAddCTF              DD 0
F_EE_CInfGameGetCharacterId      DD 0
; CObList
F_EE_CObListRemoveAll            DD 0
F_EE_CObListRemoveHead           DD 0
; CResRef
F_EE_CResRefGetResRefStr         DD 0
F_EE_CResRefIsValid              DD 0
F_EE_CResRefCResRef              DD 0 ; ~CResRef
F_EE_CResRefOpEqu                DD 0 ; operator=
F_EE_CResRefOpNotEqu             DD 0 ; operator!=
; CString
F_EE_CStringOpPlus               DD 0 ; operator+
F_EE_CStringCString              DD 0 ; ~CString
F_EE_CStringFindIndex            DD 0 ; CList::FindIndex
; CInfButtonArray
F_EE_CInfButtonArraySetState     DD 0
F_EE_CInfButtonArrayUpdateButtons DD 0
F_EE_CInfButtonArraySTT          DD 0 ; CInfButtonArray::SetTooltip
; CGameEffect
F_EE_CGameEffectCGameEffect      DD 0
F_EE_CGameEffectCopyFromBase     DD 0
F_EE_CGameEffectGetItemEffect    DD 0
; Misc
F_EE_CGameObjectArrayGetDeny     DD 0 ; CGameObjectArray::GetShare
F_EE_CGameEffectFireSpell        DD 0
F_EE_CGameAIBaseFireSpellPoint   DD 0
F_EE_dimmGetResObject            DD 0
F_EE_CAIActionDecode             DD 0
F_EE_CListRemoveAt               DD 0
F_EE_CRuleTablesMapCSTS          DD 0
F_EE_operator_new                DD 0
F_EE_CAIScriptCAIScript          DD 0

;---------------------------
; EE game global variables: 
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
pp_timer_ups            DD 0 ; pattern address of p_timer_ups
p_timer_ups             DD 0 ; pointer to global timer_ups variable
timer_ups               DD 0 ; actual content of CChitin::TIMER_UPDATES_PER_SECOND variable
pp_aB_1                 DD 0
p_aB_1                  DD 0
aB_1                    DD 0
pp_CGameSprite_vftable  DD 0
p_CGameSprite_vftable   DD 0
CGameSprite_vftable     DD 0
pp_CAIObjectTypeANYONE  DD 0
p_CAIObjectTypeANYONE   DD 0
CAIObjectTypeANYONE     DD 0
pp_VersionString_Push   DD 0
p_VersionString_Push    DD 0
VersionString_Push      DD 0

g_biffs                 DD 0 ; 
g_crashReportFunction   DD 0 ; 
g_cursorColor           DD 0 ; 
g_drawBackend           DD 0 ; 

g_pRegisteredFonts      DD 0 ; 
g_tooltipSnd            DD 0 ; 


ALIGN 16
;---------------------------
; Pattern Array / Table
;---------------------------
IFDEF EEEX_LUALIB ; If using static lua library we dont have to search for the lua functions

;-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; PATTERN: F  T  PatBytes                   PatLength              VerBytes                VerLength              PAdj VAdj FuncAddress                      PatName
;-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Patterns  \
PATTERN   <0, 0, Offset P_PatchLocation,    P_PatchLocationLen,    Offset V_PatchLocation, V_PatchLocationLen,     -5,  24, Offset PatchLocation>
;PATTERN   <0, 0, Offset P_Lua_setglobal,    P_Lua_setglobalLen,    Offset V_Lua_setglobal, V_Lua_setglobalLen,      0, 103, Offset F_Lua_setglobal> ; comment out to use lua_setglobalx?
PATTERN   <0, 0, Offset P_LuaL_loadstring,  P_LuaL_loadstringLen,  0,                      0,                     -20,   0, Offset F_LuaL_loadstring>
; CAIAction
PATTERN   <0, 0, Offset P_CAIActionDecode,  P_CAIActionDecodeLen,  0,                      0,                       0,   0, Offset F_EE_CAIActionDecode,     Offset szCAIActionDecode>
; CAIObjectType                                                                                                                                                
PATTERN   <0, 0, Offset P_CAIObjectTypeDecode, P_CAIObjectTypeDecodeLen,0,                 0,                       0,   0, Offset F_EE_CAIObjectTypeDecode, Offset szCAIObjectTypeDecode>
PATTERN   <0, 0, Offset P_CAIObjectTypeRead,P_CAIObjectTypeReadLen,0,                      0,                     -22,   0, Offset F_EE_CAIObjectTypeRead,   Offset szCAIObjectTypeRead>
PATTERN   <0, 0, Offset P_CAIObjectTypeSSC, P_CAIObjectTypeSSCLen, 0,                      0,                       0,   0, Offset F_EE_CAIObjectTypeSSC,    Offset szCAIObjectTypeSSC>
PATTERN   <0, 0, Offset P_CAIObjectTypeSet, P_CAIObjectTypeSetLen, 0,                      0,                       0,   0, Offset F_EE_CAIObjectTypeSet,    Offset szCAIObjectTypeSet>
PATTERN   <0, 0, Offset P_CAIObjectTypeOpEqu, P_CAIObjectTypeOpEquLen, Offset V_CAIObjectTypeOpEqu, V_CAIObjectTypeOpEquLen, 0, 14, Offset F_EE_CAIObjectTypeOpEqu,    Offset szCAIObjectTypeOpEqu>
; CDerivedStats
PATTERN   <0, 0, Offset P_CDerivedStatsGetAtOffset, P_CDerivedStatsGetAtOffsetLen,0,       0,                     -26,   0, Offset F_EE_CDerivedStatsGetAtOffset, Offset szCDerivedStatsGetAtOffset>
PATTERN   <0, 0, Offset P_CDerivedStatsGetLevel, P_CDerivedStatsGetLevelLen, Offset V_CDerivedStatsGetLevel,  V_CDerivedStatsGetLevelLen, 0, 22, Offset F_EE_CDerivedStatsGetLevel, Offset szCDerivedStatsGetLevel>
PATTERN   <0, 0, Offset P_CDerivedStatsSetLevel, P_CDerivedStatsSetLevelLen, Offset V_CDerivedStatsSetLevel,  V_CDerivedStatsSetLevelLen, 0, 22, Offset F_EE_CDerivedStatsSetLevel, Offset szCDerivedStatsSetLevel>
PATTERN   <0, 0, Offset P_CDerivedStatsGetSpellState, P_CDerivedStatsGetSpellStateLen, 0,  0,                     -46,   0, Offset F_EE_CDerivedStatsGetSpellState, Offset szCDerivedStatsGetSpellState>
PATTERN   <0, 0, Offset P_CDerivedStatsSetSpellState, P_CDerivedStatsSetSpellStateLen, 0 , 0,                      -9,   0, Offset F_EE_CDerivedStatsSetSpellState, Offset szCDerivedStatsSetSpellState>
PATTERN   <0, 0, Offset P_CDerivedStatsGetWarriorLevel, P_CDerivedStatsGetWarriorLevelLen, 0, 0,                    0,   0, Offset F_EE_CDerivedStatsGetWarriorLevel, Offset szCDerivedStatsGetWarriorLevel>
PATTERN   <0, 0, Offset P_CDerivedStatsReload, P_CDerivedStatsReloadLen, 0,                0,                     -21,   0, Offset F_EE_CDerivedStatsReload, Offset szCDerivedStatsReload>
; CGameSprite
PATTERN   <0, 0, Offset P_CGameSpriteGetActiveProficiency, P_CGameSpriteGetActiveProficiencyLen,0,0,                0,   0, Offset F_EE_CGameSpriteGetActiveProficiency, Offset szCGameSpriteGetActiveProficiency>
PATTERN   <0, 0, Offset P_CGameSpriteGetActiveStats, P_CGameSpriteGetActiveStatsLen, 0,    0,                       0,   0, Offset F_EE_CGameSpriteGetActiveStats, Offset szCGameSpriteGetActiveStats>
PATTERN   <0, 0, Offset P_CGameSpriteAddKnownSpell, P_CGameSpriteAddKnownSpellLen, 0,      0,                     -21,   0, Offset F_EE_CGameSpriteAddKnownSpell, Offset szCGameSpriteAddKnownSpell>
PATTERN   <0, 0, Offset P_CGameSpriteAddKnownSpellMage, P_CGameSpriteAddKnownSpellMageLen, 0, 0,                    0,   0, Offset F_EE_CGameSpriteAddKnownSpellMage, Offset szCGameSpriteAddKnownSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteAddKnownSpellPriest, P_CGameSpriteAddKnownSpellPriestLen, 0, 0,                0,   0, Offset F_EE_CGameSpriteAddKnownSpellPriest, Offset szCGameSpriteAddKnownSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteAddNewSA, P_CGameSpriteAddNewSALen, Offset V_CGameSpriteAddNewSA, V_CGameSpriteAddNewSALen, -92, 25, Offset F_EE_CGameSpriteAddNewSA, Offset szCGameSpriteAddNewSA>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpell, P_CGameSpriteMemorizeSpellLen, 0,      0,                     -20,   0, Offset F_EE_CGameSpriteMemorizeSpell, Offset szCGameSpriteMemorizeSpell>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpellMage, P_CGameSpriteMemorizeSpellMageLen, 0, 0,                  -68,   0, Offset F_EE_CGameSpriteMemorizeSpellMage, Offset szCGameSpriteMemorizeSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpellPriest, P_CGameSpriteMemorizeSpellPriestLen, 0, 0,              -68,   0, Offset F_EE_CGameSpriteMemorizeSpellPriest, Offset szCGameSpriteMemorizeSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpellInnate, P_CGameSpriteMemorizeSpellInnateLen, 0, 0,              -32,   0, Offset F_EE_CGameSpriteMemorizeSpellInnate, Offset szCGameSpriteMemorizeSpellInnate>
PATTERN   <0, 0, Offset P_CGameSpriteReadySpell, P_CGameSpriteReadySpellLen, 0,            0,                     -51,   0, Offset F_EE_CGameSpriteReadySpell,Offset szCGameSpriteReadySpell>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpell, P_CGameSpriteRemoveKnownSpellLen, 0,0,                     -28,   0, Offset F_EE_CGameSpriteRemoveKnownSpell, Offset szCGameSpriteRemoveKnownSpell>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpellMage, P_CGameSpriteRemoveKnownSpellMageLen, 0,0,               0,   0, Offset F_EE_CGameSpriteRemoveKnownSpellMage, Offset szCGameSpriteRemoveKnownSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpellPriest, P_CGameSpriteRemoveKnownSpellPriestLen, 0,0,           0,   0, Offset F_EE_CGameSpriteRemoveKnownSpellPriest, Offset szCGameSpriteRemoveKnownSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpellInnate, P_CGameSpriteRemoveKnownSpellInnateLen,0,0,            0,   0, Offset F_EE_CGameSpriteRemoveKnownSpellInnate, Offset szCGameSpriteRemoveKnownSpellInnate>
PATTERN   <0, 0, Offset P_CGameSpriteUnmemorizeSpellMage, P_CGameSpriteUnmemorizeSpellMageLen,0,0,                -11,   0, Offset F_EE_CGameSpriteUnmemorizeSpellMage, Offset szCGameSpriteUnmemorizeSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteUnmemorizeSpellPriest, P_CGameSpriteUnmemorizeSpellPriestLen,0,0,            -11,   0, Offset F_EE_CGameSpriteUnmemorizeSpellPriest, Offset szCGameSpriteUnmemorizeSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteUnmemorizeSpellInnate, P_CGameSpriteUnmemorizeSpellInnateLen,0,0,            -11,   0, Offset F_EE_CGameSpriteUnmemorizeSpellInnate, Offset szCGameSpriteUnmemorizeSpellInnate>
PATTERN   <0, 0, Offset P_CGameSpriteShatter,P_CGameSpriteShatterLen, 0,                   0,                     -38,   0, Offset F_EE_CGameSpriteShatter,  Offset szCGameSpriteShatter>  
PATTERN   <0, 0, Offset P_CGameSpriteRemoveNewSA, P_CGameSpriteRemoveNewSALen, Offset V_CGameSpriteRemoveNewSA, V_CGameSpriteRemoveNewSALen, -89, 25, Offset F_EE_CGameSpriteRemoveNewSA, Offset szCGameSpriteRemoveNewSA>
PATTERN   <0, 0, Offset P_CGameSpriteRenderHealthBar, P_CGameSpriteRenderHealthBarLen, 0,  0,                    -155,   0, Offset F_EE_CGameSpriteRenderHealthBar, Offset szCGameSpriteRenderHealthBar>
PATTERN   <0, 0, Offset P_CGameSpriteSetColor, P_CGameSpriteSetColorLen,0,                 0,                      -7,   0, Offset F_EE_CGameSpriteSetColor, Offset szCGameSpriteSetColor>
PATTERN   <0, 0, Offset P_CGameSpriteGetKit,P_CGameSpriteGetKitLen, 0,                     0,                     -14,   0, Offset F_EE_CGameSpriteGetKit,   Offset szCGameSpriteGetKit>
PATTERN   <0, 0, Offset P_CGameSpriteGetName, P_CGameSpriteGetNameLen, 0,                  0,                     -13,   0, Offset F_EE_CGameSpriteGetName,  Offset szCGameSpriteGetName>
PATTERN   <0, 0, Offset P_CGameSpriteGetQuickButtons, P_CGameSpriteGetQuickButtonsLen, 0,  0,                    -138,   0, Offset F_EE_CGameSpriteGetQuickButtons, Offset szCGameSpriteGetQuickButtons>
PATTERN   <0, 0, Offset P_CGameSpriteCGameSprite, P_CGameSpriteCGameSpriteLen,0,           0,                     -25,   0, Offset F_EE_CGameSpriteCGameSprite, Offset szCGameSpriteCGameSprite>
PATTERN   <0, 0, Offset P_CGameSpriteSetCTT,P_CGameSpriteSetCTTLen,0,                      0,                     -95,   0, Offset F_EE_CGameSpriteSetCTT,   Offset szCGameSpriteSetCTT>
; CInfinity
PATTERN   <0, 0, Offset P_CInfinityDrawLine,P_CInfinityDrawLineLen, 0,                     0,                    -209,   0, Offset F_EE_CInfinityDrawLine,   Offset szCInfinityDrawLine>
PATTERN   <0, 0, Offset P_CInfinityDrawRectangle, P_CInfinityDrawRectangleLen, 0,          0,                    -137,   0, Offset F_EE_CInfinityDrawRectangle, Offset szCInfinityDrawRectangle>
PATTERN   <0, 0, Offset P_CInfinityRenderAOE, P_CInfinityRenderAOELen, 0,                  0,                     -41,   0, Offset F_EE_CInfinityRenderAOE,  Offset szCInfinityRenderAOE>
; CInfGame
PATTERN   <0, 0, Offset P_CInfGameAddCTA,   P_CInfGameAddCTALen, Offset V_CInfGameAddCTA, V_CInfGameAddCTALen,        0,  36, Offset F_EE_CInfGameAddCTA,      Offset szCInfGameAddCTA>
PATTERN   <0, 0, Offset P_CInfGameAddCTF,   P_CInfGameAddCTFLen, Offset V_CInfGameAddCTF, V_CInfGameAddCTFLen,        0,  36, Offset F_EE_CInfGameAddCTF,      Offset szCInfGameAddCTF>
PATTERN   <0, 0, Offset P_CInfGameGetCharacterId, P_CInfGameGetCharacterIdLen, 0,          0,                       0,   0, Offset F_EE_CInfGameGetCharacterId, Offset szCInfGameGetCharacterId>
; CObList
PATTERN   <0, 0, Offset P_CObListRemoveAll, P_CObListRemoveAllLen, 0,                      0,                       0,   0, Offset F_EE_CObListRemoveAll,    Offset szCObListRemoveAll>
PATTERN   <0, 0, Offset P_CObListRemoveHead, P_CObListRemoveHeadLen,0,                     0,                       0,   0, Offset F_EE_CObListRemoveHead,   Offset szCObListRemoveHead>
; CResRef
PATTERN   <0, 0, Offset P_CResRefGetResRefStr, P_CResRefGetResRefStrLen, 0,                0,                     -21,   0, Offset F_EE_CResRefGetResRefStr, Offset szCResRefGetResRefStr>
PATTERN   <0, 0, Offset P_CResRefIsValid,   P_CResRefIsValidLen,   0,                      0,                       0,   0, Offset F_EE_CResRefIsValid,      Offset szCResRefIsValid>
PATTERN   <0, 0, Offset P_CResRefOpEqu,     P_CResRefOpEquLen,     0,                      0,                       0,   0, Offset F_EE_CResRefOpEqu,        Offset szCResRefOpEqu>
PATTERN   <0, 0, Offset P_CResRefOpNotEqu,  P_CResRefOpNotEquLen,  0,                      0,                       0,   0, Offset F_EE_CResRefOpNotEqu,     Offset szCResRefOpNotEqu>
PATTERN   <0, 0, Offset P_CResRefCResRef,   P_CResRefCResRefLen,   0,                      0,                       0,   0, Offset F_EE_CResRefCResRef,      Offset szCResRefCResRef>
; CString
PATTERN   <0, 0, Offset P_CStringOpPlus,    P_CStringOpPlusLen,    0,                      0,                     -39,   0, Offset F_EE_CStringOpPlus,       Offset szCStringOpPlus>
PATTERN   <0, 0, Offset P_CStringCString,   P_CStringCStringLen,   0,                      0,                       0,   0, Offset F_EE_CStringCString,      Offset szCStringCString>
PATTERN   <0, 0, Offset P_CStringFindIndex, P_CStringFindIndexLen, 0,                      0,                       0,   0, Offset F_EE_CStringFindIndex,    Offset szCStringFindIndex>
; CInfButtonArray
PATTERN   <0, 0, Offset P_CInfButtonArraySetState, P_CInfButtonArraySetStateLen,0,         0,                    -127,   0, Offset F_EE_CInfButtonArraySetState, Offset szCInfButtonArraySetState>
PATTERN   <0, 0, Offset P_CInfButtonArrayUpdateButtons, P_CInfButtonArrayUpdateButtonsLen,0,0,                    -51,   0, Offset F_EE_CInfButtonArrayUpdateButtons, Offset szCInfButtonArrayUpdateButtons>
PATTERN   <0, 0, Offset P_CInfButtonArraySTT, P_CInfButtonArraySTTLen, 0,                  0,                       0,   0, Offset F_EE_CInfButtonArraySTT,  Offset szCInfButtonArraySTT>
; Misc
PATTERN   <0, 0, Offset P_CGameObjectArrayGetDeny, P_CGameObjectArrayGetDenyLen, 0,        0,                      -9,   0, Offset F_EE_CGameObjectArrayGetDeny,  Offset szCGameObjectArrayGetDeny>
PATTERN   <0, 0, Offset P_CGameEffectFireSpell, P_CGameEffectFireSpellLen, 0,              0,                     -31,   0, Offset F_EE_CGameEffectFireSpell,Offset szCGameEffectFireSpell>
PATTERN   <0, 0, Offset P_CGameAIBaseFireSpellPoint, P_CGameAIBaseFireSpellPointLen, 0,    0,                     -16,   0, Offset F_EE_CGameAIBaseFireSpellPoint, Offset szCGameAIBaseFireSpellPoint>
PATTERN   <0, 0, Offset P_CListRemoveAt,    P_CListRemoveAtLen,    0,                      0,                       0,   0, Offset F_EE_CListRemoveAt,       Offset szCListRemoveAt>
PATTERN   <0, 0, Offset P_CRuleTablesMapCSTS, P_CRuleTablesMapCSTSLen, 0,                  0,                       0,   0, Offset F_EE_CRuleTablesMapCSTS,  Offset szCRuleTablesMapCSTS>
PATTERN   <0, 0, Offset P_dimmGetResObject, P_dimmGetResObjectLen, 0,                      0,                       0,   0, Offset F_EE_dimmGetResObject,    Offset szdimmGetResObject>
PATTERN   <0, 0, Offset P_operator_new,     P_operator_newLen,     0,                      0,                    -123,   0, Offset F_EE_operator_new,        Offset szoperator_new>
PATTERN   <0, 0, Offset P_CAIScriptCAIScript, P_CAIScriptCAIScriptLen, 0,                  0,                     -37,   0, Offset F_EE_CAIScriptCAIScript,  Offset szCAIScriptCAIScript>
; CGameEffect
PATTERN   <0, 0, Offset P_CGameEffectCGameEffect, P_CGameEffectCGameEffectLen, 0,          0,                     -17,   0, Offset F_EE_CGameEffectCGameEffect, Offset szCGameEffectCGameEffect>
PATTERN   <0, 0, Offset P_CGameEffectCopyFromBase, P_CGameEffectCopyFromBaseLen, 0,        0,                     -17,   0, Offset F_EE_CGameEffectCopyFromBase, Offset szCGameEffectCopyFromBase>
PATTERN   <0, 0, Offset P_CGameEffectGetItemEffect, P_CGameEffectGetItemEffectLen, 0,      0,                     -11,   0, Offset F_EE_CGameEffectGetItemEffect, Offset szCGameEffectGetItemEffect>
; Others
PATTERN   <0, 0, Offset P__ftol2_sse,       P__ftol2_sseLen,       0,                      0,                      -7,   0, Offset F__ftol2_sse,             Offset sz_ftol2_sse>
PATTERN   <0, 0, Offset P_p_malloc,         P_p_mallocLen,         0,                      0,                       0,   0, Offset F_p_malloc,               Offset szp_malloc>
PATTERN   <0, 0, Offset P__mbscmp,          P__mbscmpLen,          0,                      0,                       0,   0, Offset F__mbscmp,                Offset sz_mbscmp>
 ; Globals
PATTERN   <0, 1, Offset P_g_pChitin,        P_g_pChitinLen,        0,                      0,                      11,   0, Offset pp_pChitin,               Offset sz_pp_pChitin>
PATTERN   <0, 1, Offset P_g_pBaldurChitin,  P_g_pBaldurChitinLen,  0,                      0,                      34,   0, Offset pp_pBaldurChitin,         Offset sz_pp_pBaldurChitin>
PATTERN   <0, 1, Offset P_g_backgroundMenu, P_g_backgroundMenuLen, 0,                      0,                     -23,   0, Offset pp_backgroundMenu,        Offset sz_pp_backgroundMenu>
PATTERN   <0, 1, Offset P_g_overlayMenu,    P_g_overlayMenuLen,    0,                      0,                      -4,   0, Offset pp_overlayMenu,           Offset sz_pp_overlayMenu>
PATTERN   <0, 1, Offset P_CChitin_timer_ups,P_CChitin_timer_upsLen,0,                      0,                      14,   0, Offset pp_timer_ups,             Offset sz_pp_timer_ups>
PATTERN   <0, 1, Offset P_aB_1,             P_aB_1Len,             0,                      0,                      14,   0, Offset pp_aB_1,                  Offset sz_pp_aB_1>
PATTERN   <0, 1, Offset P_CGameSprite_vftable, P_CGameSprite_vftableLen, 0,                0,                      17,   0, Offset pp_CGameSprite_vftable,   Offset sz_pp_CGameSprite_vftable>
PATTERN   <0, 1, Offset P_CAIObjectTypeANYONE, P_CAIObjectTypeANYONELen, 0,                0,                      12,   0, Offset pp_CAIObjectTypeANYONE,   Offset sz_pp_CAIObjectTypeANYONE>
PATTERN   <0, 1, Offset P_VersionString_Push, P_VersionString_PushLen, Offset V_VersionString_Push, V_VersionString_PushLen, 31, 41, Offset pp_VersionString_Push, Offset sz_pp_VersionString_Push>

ELSE ; not using static lua library, so we check for all patterns including lua functions

;-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
; PATTERN: F  T  PatBytes                   PatLength              VerBytes                VerLength              PAdj VAdj FuncAddress                      PatName
;-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Patterns  \
PATTERN   <0, 0, Offset P_PatchLocation,    P_PatchLocationLen,    Offset V_PatchLocation, V_PatchLocationLen,     -5,  24, Offset PatchLocation,            Offset szPatchLocation>
PATTERN   <0, 0, Offset P_Lua_createtable,  P_Lua_createtableLen,  0,                      0,                     -75,   0, Offset F_Lua_createtable,        Offset szLua_createtable>
PATTERN   <0, 0, Offset P_Lua_getglobal,    P_Lua_getglobalLen,    Offset V_Lua_getglobal, V_Lua_getglobalLen,      0,  87, Offset F_Lua_getglobal,          Offset szLua_getglobal>
PATTERN   <0, 0, Offset P_Lua_gettop,       P_Lua_gettopLen,       0,                      0,                       0,   0, Offset F_Lua_gettop,             Offset szLua_gettop>
PATTERN   <0, 0, Offset P_Lua_pcallk,       P_Lua_pcallkLen,       0,                      0,                     -20,   0, Offset F_Lua_pcallk,             Offset szLua_pcallk>
PATTERN   <0, 0, Offset P_Lua_pushcclosure, P_Lua_pushcclosureLen, 0,                      0,                       0,   0, Offset F_Lua_pushcclosure,       Offset szLua_pushcclosure>
PATTERN   <0, 0, Offset P_Lua_pushlightuserdata, P_Lua_pushlightuserdataLen, 0,            0,                       0,   0, Offset F_Lua_pushlightuserdata,  Offset szLua_pushlightuserdata>
PATTERN   <0, 0, Offset P_Lua_pushlstring,  P_Lua_pushlstringLen,  0,                      0,                       0,   0, Offset F_Lua_pushlstring,        Offset szLua_pushlstring>
PATTERN   <0, 0, Offset P_Lua_pushnumber,   P_Lua_pushnumberLen,   0,                      0,                       0,   0, Offset F_Lua_pushnumber,         Offset szLua_pushnumber>
PATTERN   <0, 0, Offset P_Lua_pushstring,   P_Lua_pushstringLen,   0,                      0,                       0,   0, Offset F_Lua_pushstring,         Offset szLua_pushstring>
PATTERN   <0, 0, Offset P_Lua_rawgeti,      P_Lua_rawgetiLen,      Offset V_Lua_rawgeti,   V_Lua_rawgetiLen,      -27, -10, Offset F_Lua_rawgeti,            Offset szLua_rawgeti>
PATTERN   <0, 0, Offset P_Lua_rawlen,       P_Lua_rawlenLen,       Offset V_Lua_rawlen,    V_Lua_rawlenLen,       -14, -15, Offset F_Lua_rawlen,             Offset szLua_rawlen>
PATTERN   <0, 0, Offset P_Lua_setfield,     P_Lua_setfieldLen,     0,                      0,                     -19,   0, Offset F_Lua_setfield,           Offset szLua_setfield>
PATTERN   <0, 0, Offset P_Lua_setglobal,    P_Lua_setglobalLen,    Offset V_Lua_setglobal, V_Lua_setglobalLen,      0, 103, Offset F_Lua_setglobal,          Offset szLua_setglobal>
PATTERN   <0, 0, Offset P_Lua_settable,     P_Lua_settableLen,     0,                      0,                      -7,   0, Offset F_Lua_settable,           Offset szLua_settable>
PATTERN   <0, 0, Offset P_Lua_settop,       P_Lua_settopLen,       0,                      0,                       0,   0, Offset F_Lua_settop,             Offset szLua_settop>
PATTERN   <0, 0, Offset P_Lua_toboolean,    P_Lua_tobooleanLen,    0,                      0,                     -14,   0, Offset F_Lua_toboolean,          Offset szLua_toboolean>
PATTERN   <0, 0, Offset P_Lua_tolstring,    P_Lua_tolstringLen,    0,                      0,                       0,   0, Offset F_Lua_tolstring,          Offset szLua_tolstring>
PATTERN   <0, 0, Offset P_Lua_tonumberx,    P_Lua_tonumberxLen,    0,                      0,                     -83,   0, Offset F_Lua_tonumberx,          Offset szLua_tonumberx>
PATTERN   <0, 0, Offset P_Lua_touserdata,   P_Lua_touserdataLen,   0,                      0,                     -14,   0, Offset F_Lua_touserdata,         Offset szLua_touserdata>
PATTERN   <0, 0, Offset P_Lua_type,         P_Lua_typeLen,         0,                      0,                     -21,   0, Offset F_Lua_type,               Offset szLua_type>
PATTERN   <0, 0, Offset P_Lua_typename,     P_Lua_typenameLen,     0,                      0,                       0,   0, Offset F_Lua_typename,           Offset szLua_typename>
PATTERN   <0, 0, Offset P_LuaL_loadstring,  P_LuaL_loadstringLen,  0,                      0,                     -20,   0, Offset F_LuaL_loadstring,        Offset szLuaL_loadstring>
; CAIAction
PATTERN   <0, 0, Offset P_CAIActionDecode,  P_CAIActionDecodeLen,  0,                      0,                       0,   0, Offset F_EE_CAIActionDecode,     Offset szCAIActionDecode>
; CAIObjectType                                                                                                                                                  
PATTERN   <0, 0, Offset P_CAIObjectTypeDecode, P_CAIObjectTypeDecodeLen,0,                 0,                       0,   0, Offset F_EE_CAIObjectTypeDecode, Offset szCAIObjectTypeDecode>
PATTERN   <0, 0, Offset P_CAIObjectTypeRead,P_CAIObjectTypeReadLen,0,                      0,                     -22,   0, Offset F_EE_CAIObjectTypeRead,   Offset szCAIObjectTypeRead>
PATTERN   <0, 0, Offset P_CAIObjectTypeSSC, P_CAIObjectTypeSSCLen, 0,                      0,                       0,   0, Offset F_EE_CAIObjectTypeSSC,    Offset szCAIObjectTypeSSC>
PATTERN   <0, 0, Offset P_CAIObjectTypeSet, P_CAIObjectTypeSetLen, 0,                      0,                       0,   0, Offset F_EE_CAIObjectTypeSet,    Offset szCAIObjectTypeSet>
PATTERN   <0, 0, Offset P_CAIObjectTypeOpEqu, P_CAIObjectTypeOpEquLen, Offset V_CAIObjectTypeOpEqu, V_CAIObjectTypeOpEquLen, 0, 14, Offset F_EE_CAIObjectTypeOpEqu,    Offset szCAIObjectTypeOpEqu>
; CDerivedStats
PATTERN   <0, 0, Offset P_CDerivedStatsGetAtOffset, P_CDerivedStatsGetAtOffsetLen,0,       0,                     -26,   0, Offset F_EE_CDerivedStatsGetAtOffset, Offset szCDerivedStatsGetAtOffset>
PATTERN   <0, 0, Offset P_CDerivedStatsGetLevel, P_CDerivedStatsGetLevelLen, Offset V_CDerivedStatsGetLevel,  V_CDerivedStatsGetLevelLen, 0, 22, Offset F_EE_CDerivedStatsGetLevel, Offset szCDerivedStatsGetLevel>
PATTERN   <0, 0, Offset P_CDerivedStatsSetLevel, P_CDerivedStatsSetLevelLen, Offset V_CDerivedStatsSetLevel,  V_CDerivedStatsSetLevelLen, 0, 22, Offset F_EE_CDerivedStatsSetLevel, Offset szCDerivedStatsSetLevel>
PATTERN   <0, 0, Offset P_CDerivedStatsGetSpellState, P_CDerivedStatsGetSpellStateLen, 0,  0,                     -46,   0, Offset F_EE_CDerivedStatsGetSpellState, Offset szCDerivedStatsGetSpellState>
PATTERN   <0, 0, Offset P_CDerivedStatsSetSpellState, P_CDerivedStatsSetSpellStateLen, 0 , 0,                      -9,   0, Offset F_EE_CDerivedStatsSetSpellState, Offset szCDerivedStatsSetSpellState>
PATTERN   <0, 0, Offset P_CDerivedStatsGetWarriorLevel, P_CDerivedStatsGetWarriorLevelLen, 0, 0,                    0,   0, Offset F_EE_CDerivedStatsGetWarriorLevel, Offset szCDerivedStatsGetWarriorLevel>
PATTERN   <0, 0, Offset P_CDerivedStatsReload, P_CDerivedStatsReloadLen, 0,                0,                     -21,   0, Offset F_EE_CDerivedStatsReload, Offset szCDerivedStatsReload>
; CGameSprite
PATTERN   <0, 0, Offset P_CGameSpriteGetActiveProficiency, P_CGameSpriteGetActiveProficiencyLen,0,0,                0,   0, Offset F_EE_CGameSpriteGetActiveProficiency, Offset szCGameSpriteGetActiveProficiency>
PATTERN   <0, 0, Offset P_CGameSpriteGetActiveStats, P_CGameSpriteGetActiveStatsLen, 0,    0,                       0,   0, Offset F_EE_CGameSpriteGetActiveStats, Offset szCGameSpriteGetActiveStats>
PATTERN   <0, 0, Offset P_CGameSpriteAddKnownSpell, P_CGameSpriteAddKnownSpellLen, 0,      0,                     -21,   0, Offset F_EE_CGameSpriteAddKnownSpell, Offset szCGameSpriteAddKnownSpell>
PATTERN   <0, 0, Offset P_CGameSpriteAddKnownSpellMage, P_CGameSpriteAddKnownSpellMageLen, 0, 0,                    0,   0, Offset F_EE_CGameSpriteAddKnownSpellMage, Offset szCGameSpriteAddKnownSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteAddKnownSpellPriest, P_CGameSpriteAddKnownSpellPriestLen, 0, 0,                0,   0, Offset F_EE_CGameSpriteAddKnownSpellPriest, Offset szCGameSpriteAddKnownSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteAddNewSA, P_CGameSpriteAddNewSALen, Offset V_CGameSpriteAddNewSA, V_CGameSpriteAddNewSALen, -92, 25, Offset F_EE_CGameSpriteAddNewSA, Offset szCGameSpriteAddNewSA>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpell, P_CGameSpriteMemorizeSpellLen, 0,      0,                     -20,   0, Offset F_EE_CGameSpriteMemorizeSpell, Offset szCGameSpriteMemorizeSpell>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpellMage, P_CGameSpriteMemorizeSpellMageLen, 0, 0,                  -68,   0, Offset F_EE_CGameSpriteMemorizeSpellMage, Offset szCGameSpriteMemorizeSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpellPriest, P_CGameSpriteMemorizeSpellPriestLen, 0, 0,              -68,   0, Offset F_EE_CGameSpriteMemorizeSpellPriest, Offset szCGameSpriteMemorizeSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteMemorizeSpellInnate, P_CGameSpriteMemorizeSpellInnateLen, 0, 0,              -32,   0, Offset F_EE_CGameSpriteMemorizeSpellInnate, Offset szCGameSpriteMemorizeSpellInnate>
PATTERN   <0, 0, Offset P_CGameSpriteReadySpell, P_CGameSpriteReadySpellLen, 0,            0,                     -51,   0, Offset F_EE_CGameSpriteReadySpell,Offset szCGameSpriteReadySpell>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpell, P_CGameSpriteRemoveKnownSpellLen, 0,0,                     -28,   0, Offset F_EE_CGameSpriteRemoveKnownSpell, Offset szCGameSpriteRemoveKnownSpell>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpellMage, P_CGameSpriteRemoveKnownSpellMageLen, 0,0,               0,   0, Offset F_EE_CGameSpriteRemoveKnownSpellMage, Offset szCGameSpriteRemoveKnownSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpellPriest, P_CGameSpriteRemoveKnownSpellPriestLen, 0,0,           0,   0, Offset F_EE_CGameSpriteRemoveKnownSpellPriest, Offset szCGameSpriteRemoveKnownSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteRemoveKnownSpellInnate, P_CGameSpriteRemoveKnownSpellInnateLen,0,0,            0,   0, Offset F_EE_CGameSpriteRemoveKnownSpellInnate, Offset szCGameSpriteRemoveKnownSpellInnate>
PATTERN   <0, 0, Offset P_CGameSpriteUnmemorizeSpellMage, P_CGameSpriteUnmemorizeSpellMageLen,0,0,                -11,   0, Offset F_EE_CGameSpriteUnmemorizeSpellMage, Offset szCGameSpriteUnmemorizeSpellMage>
PATTERN   <0, 0, Offset P_CGameSpriteUnmemorizeSpellPriest, P_CGameSpriteUnmemorizeSpellPriestLen,0,0,            -11,   0, Offset F_EE_CGameSpriteUnmemorizeSpellPriest, Offset szCGameSpriteUnmemorizeSpellPriest>
PATTERN   <0, 0, Offset P_CGameSpriteUnmemorizeSpellInnate, P_CGameSpriteUnmemorizeSpellInnateLen,0,0,            -11,   0, Offset F_EE_CGameSpriteUnmemorizeSpellInnate, Offset szCGameSpriteUnmemorizeSpellInnate>
PATTERN   <0, 0, Offset P_CGameSpriteShatter,P_CGameSpriteShatterLen, 0,                   0,                     -38,   0, Offset F_EE_CGameSpriteShatter,  Offset szCGameSpriteShatter>  
PATTERN   <0, 0, Offset P_CGameSpriteRemoveNewSA, P_CGameSpriteRemoveNewSALen, Offset V_CGameSpriteRemoveNewSA, V_CGameSpriteRemoveNewSALen, -89, 25, Offset F_EE_CGameSpriteRemoveNewSA, Offset szCGameSpriteRemoveNewSA>
PATTERN   <0, 0, Offset P_CGameSpriteRenderHealthBar, P_CGameSpriteRenderHealthBarLen, 0,  0,                    -155,   0, Offset F_EE_CGameSpriteRenderHealthBar, Offset szCGameSpriteRenderHealthBar>
PATTERN   <0, 0, Offset P_CGameSpriteSetColor, P_CGameSpriteSetColorLen,0,                 0,                      -7,   0, Offset F_EE_CGameSpriteSetColor, Offset szCGameSpriteSetColor>
PATTERN   <0, 0, Offset P_CGameSpriteGetKit,P_CGameSpriteGetKitLen, 0,                     0,                     -14,   0, Offset F_EE_CGameSpriteGetKit,   Offset szCGameSpriteGetKit>
PATTERN   <0, 0, Offset P_CGameSpriteGetName, P_CGameSpriteGetNameLen, 0,                  0,                     -13,   0, Offset F_EE_CGameSpriteGetName,  Offset szCGameSpriteGetName>
PATTERN   <0, 0, Offset P_CGameSpriteGetQuickButtons, P_CGameSpriteGetQuickButtonsLen, 0,  0,                    -138,   0, Offset F_EE_CGameSpriteGetQuickButtons, Offset szCGameSpriteGetQuickButtons>
PATTERN   <0, 0, Offset P_CGameSpriteCGameSprite, P_CGameSpriteCGameSpriteLen,0,           0,                     -25,   0, Offset F_EE_CGameSpriteCGameSprite, Offset szCGameSpriteCGameSprite>
PATTERN   <0, 0, Offset P_CGameSpriteSetCTT,P_CGameSpriteSetCTTLen,0,                      0,                     -95,   0, Offset F_EE_CGameSpriteSetCTT,   Offset szCGameSpriteSetCTT>
; CInfinity
PATTERN   <0, 0, Offset P_CInfinityDrawLine,P_CInfinityDrawLineLen, 0,                     0,                    -209,   0, Offset F_EE_CInfinityDrawLine,   Offset szCInfinityDrawLine>
PATTERN   <0, 0, Offset P_CInfinityDrawRectangle, P_CInfinityDrawRectangleLen, 0,          0,                    -137,   0, Offset F_EE_CInfinityDrawRectangle, Offset szCInfinityDrawRectangle>
PATTERN   <0, 0, Offset P_CInfinityRenderAOE, P_CInfinityRenderAOELen, 0,                  0,                     -41,   0, Offset F_EE_CInfinityRenderAOE,  Offset szCInfinityRenderAOE>
; CInfGame
PATTERN   <0, 0, Offset P_CInfGameAddCTA,   P_CInfGameAddCTALen, Offset V_CInfGameAddCTA, V_CInfGameAddCTALen,        0,  36, Offset F_EE_CInfGameAddCTA,      Offset szCInfGameAddCTA>
PATTERN   <0, 0, Offset P_CInfGameAddCTF,   P_CInfGameAddCTFLen, Offset V_CInfGameAddCTF, V_CInfGameAddCTFLen,        0,  36, Offset F_EE_CInfGameAddCTF,      Offset szCInfGameAddCTF>
PATTERN   <0, 0, Offset P_CInfGameGetCharacterId, P_CInfGameGetCharacterIdLen, 0,          0,                       0,   0, Offset F_EE_CInfGameGetCharacterId, Offset szCInfGameGetCharacterId>
; CObList
PATTERN   <0, 0, Offset P_CObListRemoveAll, P_CObListRemoveAllLen, 0,                      0,                       0,   0, Offset F_EE_CObListRemoveAll,    Offset szCObListRemoveAll>
PATTERN   <0, 0, Offset P_CObListRemoveHead, P_CObListRemoveHeadLen,0,                     0,                       0,   0, Offset F_EE_CObListRemoveHead,   Offset szCObListRemoveHead>
; CResRef
PATTERN   <0, 0, Offset P_CResRefGetResRefStr, P_CResRefGetResRefStrLen, 0,                0,                     -21,   0, Offset F_EE_CResRefGetResRefStr, Offset szCResRefGetResRefStr>
PATTERN   <0, 0, Offset P_CResRefIsValid,   P_CResRefIsValidLen,   0,                      0,                       0,   0, Offset F_EE_CResRefIsValid,      Offset szCResRefIsValid>
PATTERN   <0, 0, Offset P_CResRefOpEqu,     P_CResRefOpEquLen,     0,                      0,                       0,   0, Offset F_EE_CResRefOpEqu,        Offset szCResRefOpEqu>
PATTERN   <0, 0, Offset P_CResRefOpNotEqu,  P_CResRefOpNotEquLen,  0,                      0,                       0,   0, Offset F_EE_CResRefOpNotEqu,     Offset szCResRefOpNotEqu>
PATTERN   <0, 0, Offset P_CResRefCResRef,   P_CResRefCResRefLen,   0,                      0,                       0,   0, Offset F_EE_CResRefCResRef,      Offset szCResRefCResRef>
; CString
PATTERN   <0, 0, Offset P_CStringOpPlus,    P_CStringOpPlusLen,    0,                      0,                     -39,   0, Offset F_EE_CStringOpPlus,       Offset szCStringOpPlus>
PATTERN   <0, 0, Offset P_CStringCString,   P_CStringCStringLen,   0,                      0,                       0,   0, Offset F_EE_CStringCString,      Offset szCStringCString>
PATTERN   <0, 0, Offset P_CStringFindIndex, P_CStringFindIndexLen, 0,                      0,                       0,   0, Offset F_EE_CStringFindIndex,    Offset szCStringFindIndex>
; CInfButtonArray
PATTERN   <0, 0, Offset P_CInfButtonArraySetState, P_CInfButtonArraySetStateLen,0,         0,                    -127,   0, Offset F_EE_CInfButtonArraySetState, Offset szCInfButtonArraySetState>
PATTERN   <0, 0, Offset P_CInfButtonArrayUpdateButtons, P_CInfButtonArrayUpdateButtonsLen,0,0,                    -51,   0, Offset F_EE_CInfButtonArrayUpdateButtons, Offset szCInfButtonArrayUpdateButtons>
PATTERN   <0, 0, Offset P_CInfButtonArraySTT, P_CInfButtonArraySTTLen, 0,                  0,                       0,   0, Offset F_EE_CInfButtonArraySTT,  Offset szCInfButtonArraySTT>
; Misc
PATTERN   <0, 0, Offset P_CGameObjectArrayGetDeny, P_CGameObjectArrayGetDenyLen, 0,        0,                      -9,   0, Offset F_EE_CGameObjectArrayGetDeny,  Offset szCGameObjectArrayGetDeny>
PATTERN   <0, 0, Offset P_CGameEffectFireSpell, P_CGameEffectFireSpellLen, 0,              0,                     -31,   0, Offset F_EE_CGameEffectFireSpell,Offset szCGameEffectFireSpell>
PATTERN   <0, 0, Offset P_CGameAIBaseFireSpellPoint, P_CGameAIBaseFireSpellPointLen, 0,    0,                     -16,   0, Offset F_EE_CGameAIBaseFireSpellPoint, Offset szCGameAIBaseFireSpellPoint>
PATTERN   <0, 0, Offset P_CListRemoveAt,    P_CListRemoveAtLen,    0,                      0,                       0,   0, Offset F_EE_CListRemoveAt,       Offset szCListRemoveAt>
PATTERN   <0, 0, Offset P_CRuleTablesMapCSTS, P_CRuleTablesMapCSTSLen, 0,                  0,                       0,   0, Offset F_EE_CRuleTablesMapCSTS,  Offset szCRuleTablesMapCSTS>
PATTERN   <0, 0, Offset P_dimmGetResObject, P_dimmGetResObjectLen, 0,                      0,                       0,   0, Offset F_EE_dimmGetResObject,    Offset szdimmGetResObject>
PATTERN   <0, 0, Offset P_operator_new,     P_operator_newLen,     0,                      0,                    -123,   0, Offset F_EE_operator_new,        Offset szoperator_new>
PATTERN   <0, 0, Offset P_CAIScriptCAIScript, P_CAIScriptCAIScriptLen, 0,                  0,                     -37,   0, Offset F_EE_CAIScriptCAIScript,  Offset szCAIScriptCAIScript>
; CGameEffect
PATTERN   <0, 0, Offset P_CGameEffectCGameEffect, P_CGameEffectCGameEffectLen, 0,          0,                     -17,   0, Offset F_EE_CGameEffectCGameEffect, Offset szCGameEffectCGameEffect>
PATTERN   <0, 0, Offset P_CGameEffectCopyFromBase, P_CGameEffectCopyFromBaseLen, 0,        0,                     -17,   0, Offset F_EE_CGameEffectCopyFromBase, Offset szCGameEffectCopyFromBase>
PATTERN   <0, 0, Offset P_CGameEffectGetItemEffect, P_CGameEffectGetItemEffectLen, 0,      0,                     -11,   0, Offset F_EE_CGameEffectGetItemEffect, Offset szCGameEffectGetItemEffect>
; Others
PATTERN   <0, 0, Offset P__ftol2_sse,       P__ftol2_sseLen,       0,                      0,                      -7,   0, Offset F__ftol2_sse,             Offset sz_ftol2_sse>
PATTERN   <0, 0, Offset P_p_malloc,         P_p_mallocLen,         0,                      0,                       0,   0, Offset F_p_malloc,               Offset szp_malloc>
PATTERN   <0, 0, Offset P__mbscmp,          P__mbscmpLen,          0,                      0,                       0,   0, Offset F__mbscmp,                Offset sz_mbscmp>
 ; Globals
PATTERN   <0, 1, Offset P_g_pChitin,        P_g_pChitinLen,        0,                      0,                      11,   0, Offset pp_pChitin,               Offset sz_pp_pChitin>
PATTERN   <0, 1, Offset P_g_pBaldurChitin,  P_g_pBaldurChitinLen,  0,                      0,                      34,   0, Offset pp_pBaldurChitin,         Offset sz_pp_pBaldurChitin>
PATTERN   <0, 1, Offset P_g_backgroundMenu, P_g_backgroundMenuLen, 0,                      0,                     -23,   0, Offset pp_backgroundMenu,        Offset sz_pp_backgroundMenu>
PATTERN   <0, 1, Offset P_g_overlayMenu,    P_g_overlayMenuLen,    0,                      0,                      -4,   0, Offset pp_overlayMenu,           Offset sz_pp_overlayMenu>
PATTERN   <0, 1, Offset P_CChitin_timer_ups,P_CChitin_timer_upsLen,0,                      0,                      14,   0, Offset pp_timer_ups,             Offset sz_pp_timer_ups>
PATTERN   <0, 1, Offset P_aB_1,             P_aB_1Len,             0,                      0,                      14,   0, Offset pp_aB_1,                  Offset sz_pp_aB_1>
PATTERN   <0, 1, Offset P_CGameSprite_vftable, P_CGameSprite_vftableLen, 0,                0,                      17,   0, Offset pp_CGameSprite_vftable,   Offset sz_pp_CGameSprite_vftable>
PATTERN   <0, 1, Offset P_CAIObjectTypeANYONE, P_CAIObjectTypeANYONELen, 0,                0,                      12,   0, Offset pp_CAIObjectTypeANYONE,   Offset sz_pp_CAIObjectTypeANYONE>
PATTERN   <0, 1, Offset P_VersionString_Push, P_VersionString_PushLen, Offset V_VersionString_Push, V_VersionString_PushLen, 31, 41, Offset pp_VersionString_Push, Offset sz_pp_VersionString_Push>
ENDIF
PatternsSize            EQU $-Patterns ; Entire Patterns array/table structure size
TotalPatterns           DD (PatternsSize / SIZEOF PATTERN) ; calc total patterns based on size of patterns array / size of PATTERN entry

VerifiedPatterns        DD 0 ; Total verified patterns by EEexVerifyPatterns
NotVerifiedPatterns     DD 0 ; Total patterns not verified by EEexVerifyPatterns
FoundPatterns           DD 0 ; Total searched and found patterns by EEexSearchPatterns
NotFoundPatterns        DD 0 ; Total patterns not found by EEexSearchPatterns
SkippedPatterns         DD 0 ; For game specific patterns - oossible future use




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
; NOTE: Not currently using - might be required in future - needs testing
; and adjustment to change bit 0 to be compare, and bit 1 to ignore I think.
; 
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






















