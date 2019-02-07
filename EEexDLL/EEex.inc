;------------------------------------------------------------------------------
; EEex.DLL - Injected dll for EEex.exe loader by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------
include windows.inc

include user32.inc
include kernel32.inc
include psapi.inc
include version.inc

includelib user32.lib
includelib kernel32.lib
includelib psapi.lib
includelib version.lib

IFDEF EEEX_LUALIB
include lua52.inc
includelib lua523.lib ; nil value for lua_setglobal
includelib msvcrt12.lib
ENDIF

;------------------------------------------------------------------------------
; EEex.dll Prototypes
;------------------------------------------------------------------------------
EEexInitDll             PROTO                       ;
EEexInitGlobals         PROTO                       ;
EEexVerifyPatterns      PROTO                       ;
EEexSearchPatterns      PROTO                       ;
EEexFallbackAddresses   PROTO                       ;
EEexApplyCallPatch      PROTO :DWORD                ; dwAddressToPatch
EEexGameGlobals         PROTO                       ;

EEexLogInformation      PROTO :DWORD                ; dwType
EEexLogPatterns         PROTO :DWORD                ; bFoundPattern
EEexEEFileInformation   PROTO                       ;
EEexEEGameInformation   PROTO                       ;
EEexWriteAddressesToIni PROTO                       ;

EEexDwordToAscii        PROTO :DWORD, :DWORD        ; dwValue, lpszAsciiString
EEexAsciiHexToDword     PROTO :DWORD                ; lpszAsciiHexString
EEexDwordToAsciiHex     PROTO :DWORD, :DWORD, :DWORD; dwValue, lpszAsciiHexString, bUppercase


;------------------------------------------------------------------------------
; EEex.dll Structures
;------------------------------------------------------------------------------
IFNDEF MODULEINFO
MODULEINFO              STRUCT
    lpBaseOfDll         LPVOID ?
    SizeOfImage         DWORD ?
    EntryPoint          LPVOID ?
MODULEINFO              ENDS  
ENDIF

IFNDEF LANGANDCODEPAGE
LANGANDCODEPAGE         STRUCT
   wLanguage            DW ?
   wCodepage            DW ?
LANGANDCODEPAGE         ENDS
ENDIF


.CONST
; EEexLogInformation dwType:
INFO_ALL                EQU 0
INFO_GAME               EQU 1
INFO_DEBUG              EQU 2
INFO_VERIFIED           EQU 3
INFO_SEARCHED           EQU 4
INFO_FALLBACK           EQU 5

; Beamdog EE Game Type:
GAME_UNKNOWN            EQU 0h
GAME_BGEE               EQU 1h
GAME_BG2EE              EQU 2h
GAME_BGSOD              EQU 4h
GAME_IWDEE              EQU 8h
GAME_PSTEE              EQU 10h


.DATA
;------------------------------------------------------------------------------
; EEex.dll Initialized Data
;------------------------------------------------------------------------------
AppName                 DB "EEex.dll",0
szBeamdog_BGEE          DB "BALDUR.EXE",0
szBeamdog_BG2EE         DB "BALDUR.EXE",0
szBeamdog_BGSOD         DB "SIEGEOFDRAGONSPEAR.EXE",0
szBeamdog_IWDEE         DB "ICEWIND.EXE",0
szBeamdog_IWD2EE        DB "ICEWIND.EXE",0
szBeamdog_PSTEE         DB "TORMENT.EXE",0
szBeamdog_BG2EE_Name    DB "Baldur's Gate II: Enhanced Edition",0
gEEGameType             DD 0 ; Beamdog EE Game Type

;---------------------------
; Version Info
;---------------------------
szVerRoot               DB "\\",0
szLang                  DB "\VarFileInfo\Translation",0
szProductVersion        DB "\StringFileInfo\%04x%04x\ProductVersion",0
szProductName           DB "\StringFileInfo\%04x%04x\ProductName",0
szFileVersion           DB "%d.%d.%d.%d",0

;---------------------------
; Error Log Messages
;---------------------------
szErrorGetModuleInfo    DB "GetModuleInformation Failed",0
szErrorImageDosSig      DB "IMAGE_DOS_SIGNATURE Failed",0
szErrorImageNtSig       DB "IMAGE_NT_SIGNATURE Failed",0
szErrorSearchFunctions  DB "Cannot find or verify EE game lua functions and/or global variables.",13,10
                        DB "Possible unsupported version or a new build.",13,10
                        DB "The game will continue to launch, but EEex will not be enabled.",0

;---------------------------
; Pattern message strings
;---------------------------
szVerified              DB " patterns verified,",0
szNotVerified           DB " patterns not verified",0
szFound                 DB " patterns found,",0
szNotFound              DB " patterns not found",0
szSkipped               DB " patterns skipped",0
szToSearchFor           DB " patterns left to search for",0
szPatternsOutOf         DB " out of ",0
szPatterns              DB " patterns",0
szPattern               DB "Pattern",0


;---------------------------
; Functions/globals names:
;---------------------------
szPatchLocation                 DB "PatchLocation",0
; Lua Functions
szLua_createtable               DB "_lua_createtable",0
szLua_createtablex              DB "_lua_createtablex",0
szLua_getglobal                 DB "_lua_getglobal",0
szLua_gettop                    DB "_lua_gettop",0
szLua_pcallk                    DB "_lua_pcallk",0
szLua_pushcclosure              DB "_lua_pushcclosure",0
szLua_pushlightuserdata         DB "_lua_pushlightuserdata",0
szLua_pushlstring               DB "_lua_pushlstring",0
szLua_pushnumber                DB "_lua_pushnumber",0
szLua_pushstring                DB "_lua_pushstring",0
szLua_rawgeti                   DB "_lua_rawgeti",0
szLua_rawlen                    DB "_lua_rawlen",0
szLua_setfield                  DB "_lua_setfield",0
szLua_setglobal                 DB "_lua_setglobal",0
szLua_settable                  DB "_lua_settable",0
szLua_settop                    DB "_lua_settop",0
szLua_toboolean                 DB "_lua_toboolean",0
szLua_tolstring                 DB "_lua_tolstring",0
szLua_tonumberx                 DB "_lua_tonumberx",0
szLua_touserdata                DB "_lua_touserdata",0
szLua_type                      DB "_lua_type",0
szLua_typename                  DB "_lua_typename",0
szLuaL_loadstring               DB "_luaL_loadstring",0
; Other functions
sz_ftol2_sse                    DB "__ftol2_sse",0
szGetProcAddress                DB "__imp__GetProcAddress",0
szLoadLibrary                   DB "__imp__LoadLibraryA",0
szSDL_Free                      DB "_SDL_free",0
szSDL_FreeExport                DB "SDL_free",0
sz_mbscmp                       DB "__mbscmp",0
szp_malloc                      DB "_p_malloc",0
; EE game functions
; CAIObjectType
szCAIObjectTypeDecode           DB "CAIObjectType::Decode",0
szCAIObjectTypeRead             DB "CAIObjectType::Read",0
szCAIObjectTypeSet              DB "CAIObjectType::Set",0
szCAIObjectTypeSSC              DB "CAIObjectType::SetSpecialCase",0 ; CAIObjectType::SetSpecialCase
szCAIObjectTypeOpEqu2           DB "CAIObjectType::operator==",0 ; CAIObjectType::operator==
szCAIObjectTypeOpEqu            DB "CAIObjectType::operator=",0 ; CAIObjectType::operator=
; CDerivedStats
szCDerivedStatsGetAtOffset      DB "CDerivedStats::GetAtOffset",0
szCDerivedStatsGetLevel         DB "CDerivedStats::GetLevel",0
szCDerivedStatsSetLevel         DB "CDerivedStats::SetLevel",0
szCDerivedStatsGetSpellState    DB "CDerivedStats::GetSpellState",0
szCDerivedStatsSetSpellState    DB "CDerivedStats::SetSpellState",0
szCDerivedStatsGetWarriorLevel  DB "CDerivedStats::GetWarriorLevel",0
szCDerivedStatsReload           DB "CDerivedStats::Reload",0
; CGameSprite
szCGameSpriteCGameSprite        DB "CGameSprite::~CGameSprite",0 ; CGameSprite::~CGameSprite
szCGameSpriteAddKnownSpell      DB "CGameSprite::AddKnownSpell",0
szCGameSpriteAddKnownSpellMage  DB "CGameSprite::AddKnownSpellMage",0
szCGameSpriteAddKnownSpellPriest DB "CGameSprite::AddKnownSpellPriest",0
szCGameSpriteAddNewSA           DB "CGameSprite::AddNewSpecialAbilities",0
szCGameSpriteGetActiveStats     DB "CGameSprite::GetActiveStats",0
szCGameSpriteGetActiveProficiency DB "CGameSprite::GetActiveProficiency",0
szCGameSpriteGetKit             DB "CGameSprite::GetKit",0
szCGameSpriteGetName            DB "CGameSprite::GetName",0
szCGameSpriteGetQuickButtons    DB "CGameSprite::GetQuickButtons",0
szCGameSpriteMemorizeSpell      DB "CGameSprite::MemorizeSpell",0
szCGameSpriteMemorizeSpellMage  DB "CGameSprite::MemorizeSpellMage",0
szCGameSpriteMemorizeSpellPriest DB "CGameSprite::MemorizeSpellPriest",0
szCGameSpriteMemorizeSpellInnate DB "CGameSprite::MemorizeSpellInnate",0
szCGameSpriteReadySpell         DB "CGameSprite::ReadySpell",0
szCGameSpriteRemoveKnownSpell   DB "CGameSprite::RemoveKnownSpell",0
szCGameSpriteRemoveKnownSpellMage DB "CGameSprite::RemoveKnownSpellMage",0
szCGameSpriteRemoveKnownSpellPriest DB "CGameSprite::RemoveKnownSpellPriest",0
szCGameSpriteRemoveKnownSpellInnate DB "CGameSprite::RemoveKnownSpellInnate",0
szCGameSpriteRemoveNewSA        DB "CGameSprite::RemoveNewSpecialAbilities",0
szCGameSpriteRenderHealthBar    DB "CGameSprite::RenderHealthBar",0
szCGameSpriteSetCTT             DB "CGameSprite::SetCharacterToolTip",0 ; CGameSprite::SetCharacterToolTip
szCGameSpriteSetColor           DB "CGameSprite::SetColor",0
szCGameSpriteShatter            DB "CGameSprite::Shatter",0
szCGameSpriteUnmemorizeSpellMage DB "CGameSprite::UnmemorizeSpellMage",0
szCGameSpriteUnmemorizeSpellPriest DB "CGameSprite::UnmemorizeSpellPriest",0
szCGameSpriteUnmemorizeSpellInnate DB "CGameSprite::UnmemorizeSpellInnate",0
; CInfinity
szCInfinityDrawLine             DB "CInfinity::DrawLine",0
szCInfinityDrawRectangle        DB "CInfinity::DrawRectangle",0
szCInfinityRenderAOE            DB "CInfinity::RenderAOE",0
; CInfGame
szCInfGameAddCTA                DB "CInfGame::AddCharacterToAllies",0
szCInfGameAddCTF                DB "CInfGame::AddCharacterToFamiliars",0
szCInfGameGetCharacterId        DB "CInfGame::GetCharacterId",0
; CObList
szCObListRemoveAll              DB "CObList::RemoveAll",0
szCObListRemoveHead             DB "CObList::RemoveHead",0
; CResRef
szCResRefGetResRefStr           DB "CResRef::GetResRefStr",0
szCResRefIsValid                DB "CResRef::IsValid",0
szCResRefCResRef                DB "CResRef::~CResRef",0 ; ~CResRef
szCResRefOpEqu                  DB "CResRef::operator=",0 ; operator= 
szCResRefOpNotEqu               DB "CResRef::operator!=",0 ; operator!=
; CString
szCStringOpPlus                 DB "(CString)_operator+",0 ; operator+
szCStringCString                DB "CString::~CString",0 ; ~CString
szCStringFindIndex              DB "CStringList::FindIndex",0 ; CList::FindIndex
; CInfButtonArray
szCInfButtonArraySetState       DB "CInfButtonArray::SetState",0
szCInfButtonArrayUpdateButtons  DB "CInfButtonArray::UpdateButtons",0
szCInfButtonArraySTT            DB "CInfButtonArray::SetTooltip",0
; CGameEffect
szCGameEffectCGameEffect        DB "CGameEffect::CGameEffect",0
szCGameEffectCopyFromBase       DB "CGameEffect::CopyFromBase",0
szCGameEffectGetItemEffect      DB "CGameEffect::GetItemEffect",0
; Misc
szCGameObjectArrayGetDeny       DB "CGameObjectArray::GetDeny",0 ; CGameObjectArray::GetShare
szCGameEffectFireSpell          DB "CGameEffect::FireSpell",0
szCGameAIBaseFireSpellPoint     DB "CGameAIBase::FireSpellPoint",0
szdimmGetResObject              DB "dimmGetResObject",0
szCAIActionDecode               DB "CAIAction::Decode",0
szCListRemoveAt                 DB "CPtrList::RemoveAt",0
szCRuleTablesMapCSTS            DB "CRuleTables::MapCharacterSpecializationToSchool",0
szoperator_new                  DB "operator_new",0
szCAIScriptCAIScript            DB "CAIScript::CAIScript",0
; EE game global variables 
sz_pp_lua                       DB "pp_lua",0
sz_p_lua                        DB "_g_lua",0 ; same as _g_lua in EEex_lab.lua
sz_g_lua                        DB "g_lua",0
sz_pp_pChitin                   DB "pp_pChitin",0
sz_p_pChitin                    DB "p_pChitin",0
sz_g_pChitin                    DB "g_pChitin",0
sz_pp_pBaldurChitin             DB "pp_pBaldurChitin",0
sz_p_pBaldurChitin              DB "p_pBaldurChitin",0
sz_g_pBaldurChitin              DB "g_pBaldurChitin",0
sz_pp_backgroundMenu            DB "pp_backgroundMenu",0
sz_p_backgroundMenu             DB "p_backgroundMenu",0
sz_g_backgroundMenu             DB "g_backgroundMenu",0
sz_pp_overlayMenu               DB "pp_overlayMenu",0
sz_p_overlayMenu                DB "p_overlayMenu",0
sz_g_overlayMenu                DB "g_overlayMenu",0
sz_pp_timer_ups                 DB "pp_timer_ups",0
sz_p_timer_ups                  DB "p_timer_ups",0
sz_timer_ups                    DB "timer_ups",0 ; CChitin::TIMER_UPDATES_PER_SECOND
sz_pp_aB_1                      DB "pp_aB_1",0
sz_p_aB_1                       DB "p_aB_1",0
sz_aB_1                         DB "aB_1",0
sz_pp_CGameSprite_vftable       DB "pp_CGameSprite_vftable",0
sz_p_CGameSprite_vftable        DB "p_CGameSprite_vftable",0
sz_CGameSprite_vftable          DB "CGameSprite::`vftable'",0
sz_pp_CAIObjectTypeANYONE       DB "pp_CAIObjectType::ANYONE",0
sz_p_CAIObjectTypeANYONE        DB "p_CAIObjectType::ANYONE",0
sz_CAIObjectTypeANYONE          DB "CAIObjectType::ANYONE",0
sz_pp_VersionString_Push        DB "pp_VersionString_Push",0
sz_p_VersionString_Push         DB "p_VersionString_Push",0
sz_VersionString_Push           DB "CChitin::GetVersionString()_versionStringPush",0


;---------------------------
; Module and section info
;---------------------------
hEEGameModule           DD 0
hEEGameProcess          DD 0
EEGameBaseAddress       DD 0
EEGameImageSize         DD 0
EEGameNoSections        DD 0
EEGameSectionTEXTSize   DD 0
EEGameSectionTEXTPtr    DD 0
EEGameSectionRDATASize  DD 0
EEGameSectionRDATAPtr   DD 0
EEGameSectionDATASize   DD 0
EEGameSectionDATAPtr    DD 0
EEGameAddressEP         DD 0
EEGameAddressStart      DD 0
EEGameAddressFinish     DD 0
modinfo                 MODULEINFO <>

;---------------------------
; Filenames 
;---------------------------
EEexExeFile             DB MAX_PATH DUP (0)
EEexIniFile             DB MAX_PATH DUP (0)
EEexLogFile             DB MAX_PATH DUP (0)

;---------------------------
; Version buffers 
;---------------------------
EEGameProductVersion    DB 64 DUP (0)
EEGameProductName       DB 128 DUP (0)
EEGameExeName           DB 64 DUP (0)

;---------------------------
; Pattern message buffers 
;---------------------------
szVerifiedNo            DB 16 DUP (0)
szNotVerifiedNo         DB 16 DUP (0)
szFoundNo               DB 16 DUP (0)
szNotFoundNo            DB 16 DUP (0)
szSkippedNo             DB 16 DUP (0)
szTotalPatternNo        DB 16 DUP (0)
szPatternMessageBuffer  DB 128 DUP (0)


.DATA?
;------------------------------------------------------------------------------
; EEex.dll Uninitialized Data
;------------------------------------------------------------------------------
hInstance               DD ?
hWnd                    DD ?
szFileVersionBuffer     DB 32 DUP (?)
szProductVersionBuffer  DB MAX_PATH DUP (?)
szProductNameBuffer     DB MAX_PATH DUP (?)










