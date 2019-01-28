# ![](/EEex.png) EEexLoader

**NOTE:** This project is work in progress. Currently only BG2EE v2.5.16.6 is supported as per the notes located at [github.com/Bubb13/EEex](https://github.com/Bubb13/EEex)

Please visit [github.com/Bubb13/EEex](https://github.com/Bubb13/EEex) for the details about the [EEex](https://github.com/Bubb13/EEex) project, which was created by [Bubb](https://github.com/Bubb13).

# Summary

> EEex is an executable extender for Beamdog's Enhanced Edition of the Infinity Engine.

EEexLoader is a proof of concept project designed to help the [EEex](https://github.com/Bubb13/EEex) project. Currently the EE game executable is hardcode patched via the weidu installer. EEexLoader instead loads the game executable and injects a dynamic link library to achieve the same result as the hardcoded patching does. In theory it should also handle newer builds and in the future possibly other EE games. Currently EEexLoader works with BG2EE v2.5.16.6.

This project consists of two RadASM assembly projects:
- **EEex** - Creates the executable loader: `EEex.exe`
- **EEexDll** - Creates the injection dynamic link library: `EEex.dll`

# Technical Details

The loader `EEex.exe` will inject the `EEex.dll` into the EE game. 

The `EEex.dll` searches the EE game for known _Lua_ functions by matching byte patterns. It  also looks for a specific address to patch a redirection to a `EEexLuaInit` function located within itself.

The `EEexLuaInit`function, when called by the EE game engine, registers the _Lua_ `EEexInit` function with the _Lua_ state and sets it to globally visible.

The Lua `EEexInit` function in turn registers and sets global visibility to the _Lua_ `EEexWriteByte` and `EEexExposeToLua` functions. These _Lua_ functions are then available for usage in script files.

# Build Instructions

The projects can be compiled with the [RadASM IDE](http://www.softpedia.com/get/Programming/File-Editors/RadASM.shtml) or manually with just the [Masm32 SDK](http://www.masm32.com/download.htm).

**Requirements:**
- [RadASM IDE](http://www.softpedia.com/get/Programming/File-Editors/RadASM.shtml)
- [Masm32 SDK](http://www.masm32.com/download.htm)

**Building with RadASM IDE**

- Open up the RadASM project file (`*.rap`)
- Select the menu option: 
	- Make -> Compile RC
	- Make -> Assemble
	- Make -> Link
	- or Make -> Build to do all steps at once

**Manual Build Instructions For EEex (`EEex.exe`)**

- Open a command prompt
- Navigate to the appropriate projects folder
- Enter the following commands, one at a time:
```
\MASM32\BIN\RC.EXE /v EEex.rc
```
```
\MASM32\BIN\ML.EXE /c /coff /Cp /nologo /I"MASM32\INCLUDE" /LIBPATH:"\MASM32\LIB" EEex.asm
```
```
\MASM32\BIN\LINK.EXE /SUBSYSTEM:WINDOWS /RELEASE /VERSION:4.0 /LIBPATH:"\MASM32\LIB" /OUT:"EEex.exe" EEex.obj EEex.res
```

**Manual Build Instructions For EEexDLL (`EEex.dll`)**

- Open a command prompt
- Navigate to the appropriate projects folder
- Enter the following commands, one at a time:
```
\MASM32\BIN\RC.EXE /v EEex.rc
```
```
\MASM32\BIN\ML.EXE /c /coff /Cp /nologo /I"MASM32\INCLUDE" /LIBPATH:"\MASM32\LIB" EEex.asm
```
```
\MASM32\BIN\LINK.EXE /SUBSYSTEM:WINDOWS /RELEASE /DLL /VERSION:4.0 /LIBPATH:"\MASM32\LIB" /OUT:"EEex.dll" EEex.obj EEex.res
```

# Download

The latest downloadable release is available [here](https://github.com/mrfearless/libraries/blob/master/release/EEexLoader.zip?raw=true)