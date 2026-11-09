$ErrorActionPreference = 'Stop'

$releasePath = Join-Path $PSScriptRoot 'Release'
$exeName = 'barqaab_google_drive_backup.exe'
$sourceExe = Join-Path $releasePath $exeName
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
    throw "Release files were not found beside this script. Extract the complete installer ZIP first."
}

$installPath = Join-Path $env:LOCALAPPDATA 'Programs\BARQAAB Drive Backup'
New-Item -ItemType Directory -Path $installPath -Force | Out-Null
Copy-Item -Path (Join-Path $releasePath '*') -Destination $installPath -Recurse -Force

$installedExe = Join-Path $installPath $exeName
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\BARQAAB Drive Backup.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($startMenu)
$shortcut.TargetPath = $installedExe
$shortcut.WorkingDirectory = $installPath
$shortcut.IconLocation = "$installedExe,0"
$shortcut.Save()

$answer = Read-Host 'Create a desktop shortcut too? (Y/N)'
if ($answer -match '^(y|yes)$') {
    $desktopLink = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BARQAAB Drive Backup.lnk'
    $desktopShortcut = $shell.CreateShortcut($desktopLink)
    $desktopShortcut.TargetPath = $installedExe
    $desktopShortcut.WorkingDirectory = $installPath
    $desktopShortcut.IconLocation = "$installedExe,0"
    $desktopShortcut.Save()
}

Write-Host "Installed to: $installPath"
Write-Host 'Launch BARQAAB Drive Backup from the Start menu.'
