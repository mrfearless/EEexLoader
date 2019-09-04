;------------------------------------------------------------------------------
; EEex.exe - Loader for EEex to inject EEex.dll by github.com/mrfearless
;
; EEex by Bubb: github.com/Bubb13/EEex 
; https://forums.beamdog.com/discussion/71798/mod-eeex-v0-2-1-alpha/p1
;------------------------------------------------------------------------------
include windows.inc

include user32.inc
include kernel32.inc
include version.inc

includelib user32.lib
includelib kernel32.lib
includelib version.lib


;------------------------------------------------------------------------------
; EEex Prototypes
;------------------------------------------------------------------------------
ProcessCmdLine          PROTO
WinMain                 PROTO :DWORD, :DWORD, :DWORD, :DWORD
EnumWindowsProc         PROTO :DWORD, :DWORD
CheckFileVersion        PROTO :DWORD, :DWORD
InjectDLL               PROTO :DWORD, :DWORD

DisplayErrorMessage     PROTO :DWORD, :DWORD
LogMessage              PROTO :DWORD


IFNDEF LANGANDCODEPAGE
LANGANDCODEPAGE         STRUCT
   wLanguage            DW ?
   wCodepage            DW ?
LANGANDCODEPAGE         ENDS
ENDIF

.CONST
EEEX_ALIGN              TEXTEQU <ALIGN 16>

.DATA
;------------------------------------------------------------------------------
; EEex Initialized Data
;------------------------------------------------------------------------------
AppName                 DB "EEex loader",0
szAppName               DB "[EEex loader]",0
szAppVersion            DB " v1.0.0.16",0
szEEexLoaderByfearless  DB "EEex loader by fearless: github.com/mrfearless/EEexLoader",0
szEEexByBubb            DB "EEex by Bubb: github.com/Bubb13/EEex",0
szCRLF                  DB 13,10,0
szInfoEntry             DB "[*] ",0
szStatusEntry           DB "[-] ",0
szErrorEntry            DB "[!] ",0

; Beamdog EE game executables:
szBeamdog_BGEE          DB "Baldur.exe",0
szBeamdog_BG2EE         DB "Baldur.exe",0
szBeamdog_BGSOD         DB "SiegeOfDragonspear.exe",0
szBeamdog_IWDEE         DB "Icewind.exe",0
szBeamdog_IWD2EE        DB "Icewind.exe",0
szBeamdog_PSTEE         DB "Torment.exe",0

szBeamdog_ExeVersion    DB "0.1.0.0",0

szOverride              DB "\override\",0
szUImenu                DB "UI.menu",0
szTRIGGERids            DB "TRIGGER.ids",0
szOBJECTids             DB "OBJECT.ids",0
szACTIONids             DB "ACTION.ids",0
szM__EEexlua            DB "M__EEex.lua",0
szEEexDB                DB "\EEex.db",0

szEEexDLL               DB "EEex.dll",0
szKernel32Dll           DB "kernel32.dll",0
szLoadLibraryProc       DB "LoadLibraryA",0

szVerRoot               DB "\\",0
szLang                  DB "\VarFileInfo\Translation",0
szProductVersion        DB "\StringFileInfo\%04x%04x\ProductVersion",0
szFileVersion           DB "%d.%d.%d.%d",0
szFormatErrorMessage    DB 'Error: ', '%s', 0

;------------------------------------------------------------------------------
; Error Strings
;------------------------------------------------------------------------------

; EE Game Locate And Execute Error Messages:
szErrorEEGameRunning    DB "A Beamdog Enhanced Edition game is already running, please close it before launching EEex.",0
szErrorEEGameExecute    DB "CreateProcess failed to execute Beamdog Enhanced Edition game executable. ",0
szErrorEEGameEXE        DB "Failed to locate a Beamdog Enhanced Edition game executable.",0
szErrorEEexDLLFind      DB "Failed to locate EEex.dll. Make sure it is located in the game folder along with EEex.exe",0   
szErrorEEOverrideFiles  DB "One of more override files appear to be missing: UI.menu, TRIGGER.ids, OBJECT.ids and ACTION.ids",0
szErrorM__EEexMissing   DB "M__EEex.lua is missing in the override folder - cannot continue.",0
szErrorEEexDBMissing    DB "EEex.db is missing - cannot continue.",0

; EE Game Version Check Error Messages:
szErrorBeamdog_BGEE     DB "Your version of Baldur's Gate is incompatible with EEex.",0
szErrorBeamdog_BG2EE    DB "Your version of Baldur's Gate II: Throne of Bhaal is incompatible with EEex.",0
szErrorBeamdog_BGSOD    DB "Your version of Siege of Dragonspear is incompatible with EEex.",0
szErrorBeamdog_IWDEE    DB "Your version of Icewind Dale is incompatible with EEex.",0
szErrorBeamdog_IWD2EE   DB "Your version of Icewind Dale II is incompatible with EEex.",0
szErrorBeamdog_PSTEE    DB "Your version of Planescape Torment is incompatible with EEex.",0
 
; CheckFileVersion Error Messages:
szErrorGetVersionInfo   DB "CheckFileVersion: GetFileVersionInfo failed.",0
szErrorVerQueryValue    DB "CheckFileVersion: VerQueryValue failed.",0
szErrorGetVersionSize   DB "CheckFileVersion: GetFileVersionInfoSizeA failed.",0
szErrorHeap             DB "CheckFileVersion: GetProcessHeap failed.",0
szErrorHeapAlloc        DB "CheckFileVersion: HeapAlloc failed.",0

; InjectDLL Error Messages:
szErrorVirtualAllocEx   DB "InjectDLL: VirtualAllocEx failed. ",0
szErrorWriteProcessMem  DB "InjectDLL: WriteProcessMemory failed. ",0
szErrorGetModuleHandle  DB "InjectDLL: GetModuleHandle failed. ",0
szErrorGetProcAddress   DB "InjectDLL: GetProcAddress failed. ",0
szErrorRemoteThread     DB "InjectDLL: CreateRemoteThread failed. ", 0
szErrorWaitSingleObj    DB "InjectDLL: WaitForSingleObject failed. ",0
szErrorWaitSingleInv    DB "InjectDLL: WaitForSingleObject returned invalid value. ",0
szErrorExitCodeThread   DB "InjectDLL: GetExitCodeThread failed. ",0
szErrorThreadActive     DB "InjectDLL: hRemoteThread still active. ",0

szStatusLaunchingEEGame DB "Launching EE game executable: ",0
szStatusInjectingDLL    DB "Injecting EEex.dll into EE game executable.",0
szStatusRedirectCon     DB "Redirecting console output of EE game executable: ",0

szCurrentFolder         DB MAX_PATH DUP (0)
szEEGameEXE             DB MAX_PATH DUP (0)
szEEGameOverrideFolder  DB MAX_PATH DUP (0)

szFileUImenu            DB MAX_PATH DUP (0)
szFileTRIGGERids        DB MAX_PATH DUP (0)
szFileOBJECTids         DB MAX_PATH DUP (0)
szFileACTIONids         DB MAX_PATH DUP (0)
szFileM__EEexlua        DB MAX_PATH DUP (0)
szFileEEexDB            DB MAX_PATH DUP (0)




.DATA?
;------------------------------------------------------------------------------
; EEex Uninitialized Data
;------------------------------------------------------------------------------
szFileVersionBuffer     DB 64 DUP (?)
szClassName             DB MAX_PATH DUP (?)
szWindowTitle           DB MAX_PATH DUP (?)
szErrorMessage          DB 512 DUP (?)
hInstance               DD ?
CommandLine             DD ?
hWnd                    DD ?
startinfo               STARTUPINFO <>
pi                      PROCESS_INFORMATION <>
wfd                     WIN32_FIND_DATA <>
ExitCode                DD ?
hConOutput              DD ?

