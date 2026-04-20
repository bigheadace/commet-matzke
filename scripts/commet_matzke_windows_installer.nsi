Unicode true
SetCompressor /SOLID lzma
ManifestDPIAware true

!include "x64.nsh"
!include "LogicLib.nsh"

!define APP_NAME "Commet Chat"
!define APP_PUBLISHER "MatzkeHQ"
!define APP_EXE "commet-matzke.exe"
!define APP_VERSION "0.4.1-matzke.12"
!define APP_SRC_DIR "/home/ace/apps/Commet-src/commet/build/windows/x64/matzke-package"
!define APP_OUT_FILE "/home/ace/apps/Synapse/data/commet/web/downloads/commet-matzke-windows-x64-v12-r4-installer.exe"
!define APP_REG_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MatzkeHQ Commet Chat"

Name "${APP_NAME}"
OutFile "${APP_OUT_FILE}"
InstallDir "$PROGRAMFILES64\MatzkeHQ\Commet Chat"
InstallDirRegKey HKLM "Software\MatzkeHQ\Commet Chat" "InstallDir"
RequestExecutionLevel admin

VIProductVersion "0.4.1.12"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "${APP_PUBLISHER}"

Page directory
Page instfiles

UninstPage uninstConfirm
UninstPage instfiles

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "This installer requires 64-bit Windows."
    Abort
  ${EndIf}
FunctionEnd

Section "Install"
  SetShellVarContext all
  SetRegView 64
  SetOutPath "$INSTDIR"
  File /r "${APP_SRC_DIR}/*"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKLM "Software\MatzkeHQ\Commet Chat" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${APP_REG_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${APP_REG_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${APP_REG_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${APP_REG_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${APP_REG_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "${APP_REG_KEY}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegDWORD HKLM "${APP_REG_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${APP_REG_KEY}" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\MatzkeHQ"
  CreateShortcut "$SMPROGRAMS\MatzkeHQ\Commet Chat.lnk" "$INSTDIR\${APP_EXE}"
  CreateShortcut "$DESKTOP\Commet Chat.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

Section "Uninstall"
  SetShellVarContext all
  SetRegView 64
  Delete "$DESKTOP\Commet Chat.lnk"
  Delete "$SMPROGRAMS\MatzkeHQ\Commet Chat.lnk"
  RMDir "$SMPROGRAMS\MatzkeHQ"

  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\flutter_windows.dll"
  Delete "$INSTDIR\lib*.dll"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${APP_REG_KEY}"
  DeleteRegKey HKLM "Software\MatzkeHQ\Commet Chat"
SectionEnd
