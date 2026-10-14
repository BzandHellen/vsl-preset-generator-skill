<#
  read-preset.ps1  —  decompress a .vsynpreset (or read a .json) and print it.

  Usage:
    powershell -File read-preset.ps1 -Preset "C:\...\x.vsynpreset"                 # full JSON
    powershell -File read-preset.ps1 -Preset "C:\...\x.vsynpreset" -Mode summary   # slots only
#>
param(
  [Parameter(Mandatory)][string]$Preset,
  [ValidateSet('full','summary')][string]$Mode = 'summary',
  [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe"
)
$ErrorActionPreference='Stop'
function Get-Text([string]$file){
  if ($file -match '\.vsynpreset$') {
    $d=Join-Path $env:TEMP ("vslread_"+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $d|Out-Null
    Copy-Item $file (Join-Path $d 'f.zst') -Force
    & $SevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
    $dec=Get-ChildItem "$d\out" -File | Select-Object -First 1
    $t=[IO.File]::ReadAllText($dec.FullName); Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; return $t
  }
  return [IO.File]::ReadAllText($file)
}
$t = Get-Text $Preset
if ($Mode -eq 'full') {
  [Console]::Out.Write($t)
  exit 0
}
$slots = @()
foreach ($m in [regex]::Matches($t,'"title"\s*:\s*"([^"]*)"\s*,\s*"velXFadeGroup"')) {
  # patch slots end with "title":"X","velXFadeGroup"
}
# robust: walk patchName -> title/range
foreach ($m in [regex]::Matches($t,'"patchName"\s*:\s*"([^"]*)"[\s\S]*?"title"\s*:\s*"([^"]*)"')) {
  $seg = $m.Value
  $rf = [regex]::Match($seg,'"rangeFrom"\s*:\s*(-?\d+)').Groups[1].Value
  $rt = [regex]::Match($seg,'"rangeTo"\s*:\s*(-?\d+)').Groups[1].Value
  $slots += [pscustomobject]@{ title=$m.Groups[2].Value; patchName=$m.Groups[1].Value; rangeFrom=$rf; rangeTo=$rt }
}
@{ currentPreset=([regex]::Match($t,'"currentPreset"\s*:\s*"([^"]*)"').Groups[1].Value); slotCount=@($slots).Count; slots=$slots } | ConvertTo-Json -Depth 4
