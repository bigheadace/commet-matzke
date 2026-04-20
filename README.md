# Commet Chat — MatzkeHQ Build

Custom packaging and build scripts for a self-hosted [Commet Chat](https://github.com/commetchat/commet) deployment on MatzkeHQ.

This build defaults to the MatzkeHQ Matrix homeserver and is distributed as a Windows installer and Android APK from chat.matzkehq.com/downloads.

## Upstream

Built on top of [Commet Chat](https://github.com/commetchat/commet) (Apache 2.0 license).

## Contents

- `scripts/build_matzke_windows.ps1` — PowerShell build script for Windows (run inside MSVC environment)
- `scripts/commet_matzke_windows_installer.nsi` — NSIS installer script producing a signed installer

## Building

### Windows

Requires Flutter SDK and MSVC build tools.

```powershell
.\scripts\build_matzke_windows.ps1 -VersionTag "v0.4.1-matzke.13"
```

Then compile the NSIS installer:

```
makensis scripts\commet_matzke_windows_installer.nsi
```

## License

Build scripts: MIT  
Commet Chat source: Apache 2.0 (see upstream)
