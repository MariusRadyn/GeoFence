# Downloads nuget.exe into this folder for Windows flutter_tts builds.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$nuget = Join-Path $dir 'nuget.exe'

if (Test-Path $nuget) {
    Write-Host "nuget.exe already exists: $nuget"
    exit 0
}

Write-Host 'Downloading nuget.exe...'
Invoke-WebRequest `
    -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' `
    -OutFile $nuget

Write-Host "Saved: $nuget"
Write-Host 'Rebuild with: flutter run -d windows'
