# AP-3 — a reproducible, project-level way to run the Functions test suite
# under the exact Node major version `package.json`'s own "engines": {"node":
# "20"} pins, regardless of what Node version happens to be the machine's
# current global default. Firebase's own emulator tooling degrades silently
# rather than refusing to start on a mismatch ("Using node@24 from host."),
# which produced real, confusing full-suite failures this project's own
# closure history documents (docs/visual_evidence/ap3/README.md) — this
# script exists so nobody has to rediscover that the hard way again.
#
# Usage (from functions/):
#   .\scripts\run-with-node20.ps1              # runs `npm test`
#   .\scripts\run-with-node20.ps1 npm run build # runs an arbitrary command
#
# If the machine's own `node` is already v20.x, this is a no-op passthrough —
# no download, no PATH change beyond what's already there. Otherwise it
# downloads the official Node 20 LTS Windows x64 build from nodejs.org into
# functions/.tools/ (gitignored — a downloaded runtime binary, never source;
# safe to delete any time, re-downloaded on next run) and prepends it to PATH
# for the duration of the invoked command only.

$ErrorActionPreference = 'Stop'

$NodeVersionPin = '20.19.5'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FunctionsDir = Split-Path -Parent $ScriptDir
$ToolsDir = Join-Path $FunctionsDir '.tools'
$Node20Dir = Join-Path $ToolsDir "node-v$NodeVersionPin-win-x64"
$Node20Exe = Join-Path $Node20Dir 'node.exe'

function Get-NodeMajorVersion {
    param([string]$NodePath = 'node')
    try {
        $v = & $NodePath --version 2>$null
        if ($v -match '^v(\d+)\.') { return [int]$Matches[1] }
    } catch {}
    return $null
}

$systemMajor = Get-NodeMajorVersion
if ($systemMajor -eq 20) {
    Write-Host "System Node is already v20.x — using it directly, no download needed."
} else {
    if (-not (Test-Path $Node20Exe)) {
        Write-Host "System Node is v$systemMajor (or unavailable); pinned Node v$NodeVersionPin not yet cached — downloading..."
        New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
        $zipPath = Join-Path $ToolsDir "node-v$NodeVersionPin-win-x64.zip"
        $url = "https://nodejs.org/dist/v$NodeVersionPin/node-v$NodeVersionPin-win-x64.zip"
        Invoke-WebRequest -Uri $url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $ToolsDir -Force
        Remove-Item $zipPath
    }
    if (-not (Test-Path $Node20Exe)) {
        throw "Node v$NodeVersionPin download/extract did not produce $Node20Exe — aborting."
    }
    Write-Host "Using pinned Node v$NodeVersionPin from $Node20Dir"
    $env:PATH = "$Node20Dir;$env:PATH"
}

Write-Host "node --version: $(node --version)"

if ($args.Count -eq 0) {
    Push-Location $FunctionsDir
    try { npm test } finally { Pop-Location }
} else {
    Push-Location $FunctionsDir
    try { & $args[0] $args[1..($args.Count - 1)] } finally { Pop-Location }
}
