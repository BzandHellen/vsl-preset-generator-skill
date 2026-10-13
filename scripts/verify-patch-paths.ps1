<#
  verify-patch-paths.ps1

  Verify that every patchEntry in a preset (or root slot) really exists in the library,
  using the extracted database (vsl-patches.csv).

  Usage:
    powershell -ExecutionPolicy Bypass -File verify-patch-paths.ps1 `
      -Preset "C:\...\STR Synchron DB a6 (generated).vsynpreset" -Database "C:\...\data\vsl-patches.csv"
#>
param(
  [Parameter(Mandatory)][string]$Preset,
  [Parameter(Mandatory)][string]$Database,
  [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe"
)
$ErrorActionPreference='Stop'
function Read-PresetText([string]$file){
  if ($file -match '\.vsynpreset$') {
    $d=Join-Path $env:TEMP ("vslvfy_"+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $d|Out-Null
    Copy-Item $file (Join-Path $d 'f.zst') -Force
    & $SevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
    $dec=Get-ChildItem "$d\out" -File | Select-Object -First 1
    $txt=[IO.File]::ReadAllText($dec.FullName); Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; return $txt
  }
  return [IO.File]::ReadAllText($file)
}
$txt = Read-PresetText $Preset
$rows = Import-Csv $Database
$set = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($r in $rows) { [void]$set.Add(($r.Path + '/' + $r.PatchFile)) }

$pe = [regex]::Matches($txt,'vol://[^:]*:public/patches/([^"]*\.vsynpatch)') | ForEach-Object { $_.Groups[1].Value }
$miss = $pe | Where-Object { -not $set.Contains($_) } | Select-Object -Unique
Write-Host ("patchEntry: {0}   NOT FOUND: {1}" -f $pe.Count, @($miss).Count)
$miss | ForEach-Object { Write-Host ("  MISSING -> " + $_) }
