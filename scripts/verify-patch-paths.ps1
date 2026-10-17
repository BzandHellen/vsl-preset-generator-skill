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
  [string]$Database,
  [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe"
)
$ErrorActionPreference='Stop'
if (-not $Database) { $Database = Join-Path (Split-Path $PSScriptRoot -Parent) 'data\vsl-patches.csv' }
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
$map = @{}
foreach ($r in $rows) { $map[($r.Path + '/' + $r.PatchFile)] = $r.ContentId }

# 同时校验 (1) patch 路径存在  (2) contentId 与该 patch 所属卷一致  ← 以前漏了 (2)
$ms = [regex]::Matches($txt,'vol://([^:"]*):public/patches/([^"]*\.vsynpatch)')
$miss = @(); $badCid = @()
foreach ($m in $ms) {
  $cid = $m.Groups[1].Value; $rel = $m.Groups[2].Value
  if (-not $map.ContainsKey($rel)) { $miss += $rel }
  elseif ($map[$rel] -ne $cid) { $badCid += ("{0}   (cid={1}, 应为 {2})" -f $rel, $cid, $map[$rel]) }
}
Write-Host ("patchEntry: {0}   NOT FOUND: {1}   BAD-CID: {2}" -f $ms.Count, @($miss).Count, @($badCid).Count)
@($miss) | Select-Object -Unique | ForEach-Object { Write-Host ("  MISSING -> " + $_) }
@($badCid) | Select-Object -Unique | ForEach-Object { Write-Host ("  BAD-CID -> " + $_) }
