# ![](/EEex.png) EEexLoader

Please visit [github.com/Bubb13/EEex](https://github.com/Bubb13/EEex) for the details about the [EEex](https://github.com/Bubb13/EEex) project, which was created by [Bubb](https://github.com/Bubb13).

# Summary

> EEex is an executable extender for Beamdog's Enhanced Edition of the Infinity Engine.

EEexLoader was designed to help the [EEex](https://github.com/Bubb13/EEex) project. In the past the EE game executable was hardcode patched via the weidu installer. EEexLoader instead loads the EE game executable and injects a dynamic link library to achieve the same result as the hardcoded patching did. 

In addition, the EEexLoader searches for EE game functions and EE game global variables that can be used by [EEex](https://github.com/Bubb13/EEex) directly instead of using hardcoded memory addresses specific to a particular game. A pattern database of entries for specific functions and global variables is used for this search process. In theory it should also handle newer builds of EE games.

Currently EEexLoader works with:

- BGEE: 2.5.17.0
- BG2EE: 2.5.16.6
- BGSOD: 2.5.17.0
- IWDEE: 2.5.17.0

Note: _PSTEE has some differences that will require some additional work to support. Some functions and features may not be possible with EEex for PSTEE, due to those differences._

This project consists of two RadASM assembly projects:
- **EEex** - Creates the executable loader: `EEex.exe`
- **EEexDll** - Creates the injection dynamic link library: `EEex.dll`

# Technical Information

For details on the EEex loader's operation or the pattern database vist the wiki [here](https://github.com/mrfearless/EEexLoader/wiki)

# Build Instructions

See the [Build-Instructions](https://github.com/mrfearless/EEexLoader/wiki/Build-Instructions) wiki entry for details of building the projects.

# Download

The latest downloadable release is available [here](https://github.com/mrfearless/EEexLoader/blob/master/Release/EEexLoader.zip?raw=true)
