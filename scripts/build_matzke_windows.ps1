param(
    [string]$VersionTag = "v0.4.1-matzke.7",
    [string]$GitHash = "unknown",
    [string]$BuildDetail = "matzke"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

dart run scripts/build_release.dart `
    --version_tag $VersionTag `
    --platform windows `
    --git_hash $GitHash `
    --build_detail $BuildDetail `
    --enable_google_services false

if ($LASTEXITCODE -ne 0) {
    throw "Windows Flutter build failed with exit code $LASTEXITCODE"
}

$ReleaseDir = Join-Path $RepoRoot "build\windows\x64\runner\Release"
$ZipPath = Join-Path $RepoRoot "build\windows\x64\runner\commet-matzke-windows-x64.zip"

if (-not (Test-Path $ReleaseDir)) {
    throw "Windows release directory was not created: $ReleaseDir"
}

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath
}

Compress-Archive -Path (Join-Path $ReleaseDir "*") -DestinationPath $ZipPath
Write-Host "Windows package written to $ZipPath"
