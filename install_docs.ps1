\
param(
    [string]$ProjectPath = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
$SourceDocs = Join-Path $PSScriptRoot "docs"
$TargetDocs = Join-Path $ProjectPath "docs"

if (-not (Test-Path (Join-Path $ProjectPath "pubspec.yaml"))) {
    throw "Hedef klasörde pubspec.yaml bulunamadı. Scripti Flutter proje kökünde çalıştırın."
}

New-Item -ItemType Directory -Force -Path $TargetDocs | Out-Null

Get-ChildItem -Path $SourceDocs -Filter *.md | ForEach-Object {
    $target = Join-Path $TargetDocs $_.Name
    Copy-Item $_.FullName $target -Force
    Write-Host "[OK] docs\$($_.Name)"
}

Write-Host ""
Write-Host "Abaküs Gemini bağlam belgeleri projeye eklendi."
Write-Host "Hedef: $TargetDocs"
