param(
    [string]$VersionTag = "v0.4.1-matzke.13",
    [string]$HostIP = "10.0.2.2",
    [string]$HostPort = "8018"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Log($message) {
    $line = "$(Get-Date -Format o) $message"
    Write-Host $line
    Add-Content -Path C:\build\provision.log -Value $line
}

New-Item -ItemType Directory -Force C:\build, C:\tools, C:\src | Out-Null
Log "Provisioning started"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$flutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.41.7-stable.zip"
$flutterZip = "C:\build\flutter.zip"
if (!(Test-Path C:\tools\flutter\bin\flutter.bat)) {
    Log "Downloading Flutter 3.41.7"
    Invoke-WebRequest $flutterUrl -OutFile $flutterZip
    Log "Extracting Flutter"
    Expand-Archive $flutterZip -DestinationPath C:\tools -Force
}

$env:Path = "C:\tools\flutter\bin;C:\Users\Administrator\.cargo\bin;$env:Path"
[Environment]::SetEnvironmentVariable("Path", "C:\tools\flutter\bin;C:\Users\Administrator\.cargo\bin;" + [Environment]::GetEnvironmentVariable("Path", "Machine"), "Machine")

if (!(Test-Path C:\BuildTools\Common7\Tools\VsDevCmd.bat)) {
    $vsExe = "C:\build\vs_BuildTools.exe"
    Log "Downloading Visual Studio Build Tools"
    Invoke-WebRequest "https://aka.ms/vs/17/release/vs_BuildTools.exe" -OutFile $vsExe
    Log "Installing Visual Studio Build Tools"
    $vsArgs = @(
        "--quiet", "--wait", "--norestart", "--nocache",
        "--installPath", "C:\BuildTools",
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "--add", "Microsoft.VisualStudio.Component.VC.CMake.Project",
        "--add", "Microsoft.VisualStudio.Component.Windows11SDK.26100"
    )
    $p = Start-Process -FilePath $vsExe -ArgumentList $vsArgs -PassThru -Wait
    Log "Visual Studio Build Tools exit code $($p.ExitCode)"
    if (($p.ExitCode -ne 0) -and ($p.ExitCode -ne 3010)) {
        throw "Visual Studio Build Tools install failed with $($p.ExitCode)"
    }
}

if (!(Test-Path C:\Users\Administrator\.cargo\bin\rustc.exe)) {
    $rustExe = "C:\build\rustup-init.exe"
    Log "Downloading rustup"
    Invoke-WebRequest "https://win.rustup.rs/x86_64" -OutFile $rustExe
    Log "Installing Rust MSVC toolchain"
    $p = Start-Process -FilePath $rustExe -ArgumentList @("-y", "--default-host", "x86_64-pc-windows-msvc", "--profile", "minimal") -PassThru -Wait
    Log "rustup exit code $($p.ExitCode)"
    if ($p.ExitCode -ne 0) {
        throw "rustup failed with $($p.ExitCode)"
    }
}

if (!(Test-Path C:\tools\nsis\makensis.exe)) {
    $nsisExe = "C:\build\nsis-installer.exe"
    Log "Downloading NSIS"
    Invoke-WebRequest "https://downloads.sourceforge.net/nsis/nsis-3.10-setup.exe" -OutFile $nsisExe
    Log "Installing NSIS"
    $p = Start-Process -FilePath $nsisExe -ArgumentList @("/S", "/D=C:\tools\nsis") -PassThru -Wait
    Log "NSIS install exit code $($p.ExitCode)"
    if ($p.ExitCode -ne 0) {
        throw "NSIS install failed with $($p.ExitCode)"
    }
}
$env:Path = "C:\tools\nsis;$env:Path"
[Environment]::SetEnvironmentVariable("Path", "C:\tools\nsis;" + [Environment]::GetEnvironmentVariable("Path", "Machine"), "Machine")

if (!(Test-Path C:\src\commet\pubspec.yaml)) {
    Log "Downloading Commet source archive from host"
    Invoke-WebRequest "http://${HostIP}:${HostPort}/commet-source.zip" -OutFile "C:\build\commet-source.zip"
    Log "Extracting Commet source"
    Expand-Archive "C:\build\commet-source.zip" -DestinationPath C:\src -Force
}

Set-Location C:\src\commet
Log "Flutter version"
flutter --version | Tee-Object -FilePath C:\build\flutter-version.log

Log "Regenerating Windows plugin files"
Remove-Item windows\flutter\generated_plugin_registrant.cc, windows\flutter\generated_plugins.cmake -Force -ErrorAction SilentlyContinue
flutter pub get

Log "Building Windows release"
powershell -ExecutionPolicy Bypass -File scripts\build_matzke_windows.ps1 -VersionTag $VersionTag -GitHash "vm-build" -BuildDetail "matzke"

Log "Building NSIS installer"
$nsisScript = "C:\src\commet\scripts\commet_matzke_windows_installer.nsi"
$p = Start-Process -FilePath "C:\tools\nsis\makensis.exe" -ArgumentList @("/V2", $nsisScript) -PassThru -Wait -NoNewWindow
Log "makensis exit code $($p.ExitCode)"
if ($p.ExitCode -ne 0) {
    throw "makensis failed with exit code $($p.ExitCode)"
}

$zipPath    = "C:\src\commet\build\windows\x64\runner\commet-matzke-windows-x64.zip"
$exePath    = "C:\build\commet-matzke-windows-x64-installer.exe"
$installerSrc = "C:\src\commet\build\windows\x64\matzke-package\commet-matzke-windows-x64-installer.exe"

# Copy installer to a predictable path for upload
if (Test-Path $installerSrc) {
    Copy-Item $installerSrc $exePath -Force
} else {
    # Fallback: find any installer.exe produced by NSIS
    $found = Get-ChildItem "C:\src\commet\build\windows\x64" -Recurse -Filter "*installer*.exe" | Select-Object -First 1
    if ($found) { Copy-Item $found.FullName $exePath -Force }
}

Log "Uploading ZIP to host"
$zipBytes = [System.IO.File]::ReadAllBytes($zipPath)
Invoke-WebRequest -Uri "http://${HostIP}:${HostPort}/upload/zip" -Method POST -Body $zipBytes -ContentType "application/octet-stream" | Out-Null

Log "Uploading installer to host"
$exeBytes = [System.IO.File]::ReadAllBytes($exePath)
Invoke-WebRequest -Uri "http://${HostIP}:${HostPort}/upload/installer" -Method POST -Body $exeBytes -ContentType "application/octet-stream" | Out-Null

Log "Build complete — artifacts uploaded to host"
Get-Item $zipPath, $exePath | Format-List FullName,Length,LastWriteTime | Out-File C:\build\artifact.txt
