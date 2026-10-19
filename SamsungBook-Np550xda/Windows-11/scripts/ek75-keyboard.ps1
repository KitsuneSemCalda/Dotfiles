#!/usr/bin/env powershell
# Windows PowerShell 5.1: add the ANSI EK75 layout without removing ABNT2.
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
Import-Module International
$tip = '0409:00020409' # English (US), United States-International
$languages = Get-WinUserLanguageList
$english = $languages | Where-Object { $_.LanguageTag -eq 'en-US' } | Select-Object -First 1

if (-not $Apply) {
    Write-Output ('US-International present: ' + [bool]($english -and $english.InputMethodTips.Contains($tip)))
    Write-Output 'Run with -Apply to add the EK75 layout; switch with Win+Space.'
    return
}

$changed = $false
if (-not $english) {
    $newLanguage = New-WinUserLanguageList 'en-US'
    $english = $newLanguage[0]
    $english.InputMethodTips.Clear()
    $languages.Add($english)
    $changed = $true
}
if (-not $english.InputMethodTips.Contains($tip)) {
    $english.InputMethodTips.Add($tip)
    $changed = $true
}
if ($changed) {
    Set-WinUserLanguageList -LanguageList $languages -Force
    Write-Output 'Added United States-International for the EK75. Existing layouts were preserved.'
} else {
    Write-Output 'United States-International is already available.'
}
