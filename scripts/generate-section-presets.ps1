<#
  generate-section-presets.ps1

  Clone a VSL Synchron Player preset (or root slot) to other instruments by text replacement,
  then write importable .vsynpreset files (or plain .json root slots).

  Template may be either:
    - a .vsynpreset  (zstd; auto-decompressed with 7-Zip), or
    - a .json        (the decompressed preset, or a copied root slot)

  Map file is a JSON array; each entry:
    {
      "name":         "STR Synchron Vln2 a10",
      "output":       "preset",                       // optional: preset (default) | json
      "replacements": [ ["violins1","violins2"],
                        ["01 SY 1st Violins-14","02 SY 2nd Violins-10"],
                        ["VI-14","VI-10"] ],           // applied IN ORDER (put "... Pro" first for cellos)
      "rangeSource":  "C:\\path\\STR Synchron Vln2 a10.json",  // optional: preset whose rangeFrom/To to copy (by patchName)
      "currentPreset":"Strings/STR Synchron Vln2 a10"          // optional
    }

  Usage:
    powershell -ExecutionPolicy Bypass -File generate-section-presets.ps1 `
      -Template "C:\...\STR Synchron Vln1 a14.vsynpreset" -MapFile ".\map.json" -OutDir "C:\...\generated"
#>
param(
  [Parameter(Mandatory)][string]$Template,
  [Parameter(Mandatory)][string]$MapFile,
  [string]$OutDir   = ".",
  [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe",
  [switch]$Force,
  [switch]$AllowOutsideGenerated
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"
$OutDir = Assert-GeneratedDir -OutDir $OutDir -AllowOutsideGenerated:$AllowOutsideGenerated
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Write-ZstdRaw([byte[]]$data,[string]$path){   # valid zstd frame, raw (uncompressed) blocks
  $ms=New-Object IO.MemoryStream; $bw=New-Object IO.BinaryWriter($ms)
  foreach($b in 0x28,0xB5,0x2F,0xFD){ $bw.Write([byte]$b) }
  $bw.Write([byte]0xA0); $bw.Write([uint32]$data.Length)
  $max=131072; $off=0
  while($off -lt $data.Length){
    $sz=[Math]::Min($max,$data.Length-$off); $last= if(($off+$sz) -ge $data.Length){1}else{0}
    $bh=[uint32]((([uint32]$sz) -shl 3) -bor [uint32]$last)
    $bw.Write([byte]($bh -band 0xFF)); $bw.Write([byte](($bh -shr 8) -band 0xFF)); $bw.Write([byte](($bh -shr 16) -band 0xFF))
    $bw.Write($data,$off,$sz); $off+=$sz
  }
  $bw.Flush(); [IO.File]::WriteAllBytes($path,$ms.ToArray())
}
function Read-PresetText([string]$file){
  if ($file -match '\.vsynpreset$') {
    $d=Join-Path $env:TEMP ("vsltpl_"+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $d|Out-Null
    Copy-Item $file (Join-Path $d 'f.zst') -Force
    & $SevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
    $dec=Get-ChildItem "$d\out" -File | Select-Object -First 1
    $txt=[IO.File]::ReadAllText($dec.FullName)
    Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    return $txt
  }
  return [IO.File]::ReadAllText($file)
}
function Get-RangeMap([string]$file){
  $t=Read-PresetText $file; $m=@{}
  foreach($x in [regex]::Matches($t,'"patchName"\s*:\s*"([^"]*)"[\s\S]*?"rangeFrom"\s*:\s*(-?\d+)\s*,\s*"rangeTo"\s*:\s*(-?\d+)')){
    $m[$x.Groups[1].Value]=@([int]$x.Groups[2].Value,[int]$x.Groups[3].Value)
  }
  return $m
}

$base = Read-PresetText $Template
$map  = Get-Content $MapFile -Raw | ConvertFrom-Json

foreach ($e in $map) {
  $t = $base
  foreach ($r in $e.replacements) { $t = $t.Replace([string]$r[0], [string]$r[1]) }
  if ($e.rangeSource) {
    $rm = Get-RangeMap $e.rangeSource
    foreach ($k in $rm.Keys) {
      $pat='("patchName"\s*:\s*"'+[regex]::Escape($k)+'"[\s\S]*?"rangeFrom"\s*:\s*)(-?\d+)(\s*,\s*"rangeTo"\s*:\s*)(-?\d+)'
      $t=[regex]::Replace($t,$pat,('${1}'+$rm[$k][0]+'${3}'+$rm[$k][1]))
    }
  }
  if ($e.ranges) {                             # explicit per-patch overrides: { "<patchName>": [from,to] }
    foreach ($k in $e.ranges.PSObject.Properties.Name) {
      $v=$e.ranges.$k
      $pat='("patchName"\s*:\s*"'+[regex]::Escape($k)+'"[\s\S]*?"rangeFrom"\s*:\s*)-?\d+(\s*,\s*"rangeTo"\s*:\s*)-?\d+'
      $t=[regex]::Replace($t,$pat,('${1}'+$v[0]+'${2}'+$v[1]))
    }
  }
  if ($e.currentPreset) {
    $t=[regex]::Replace($t,'"currentPreset"\s*:\s*"[^"]*"',('"currentPreset":"'+$e.currentPreset+'"'))
  }
  $fmt = if ($e.output) { $e.output } else { 'preset' }
  if ($fmt -eq 'json') {
    $out = Join-Path $OutDir ("$($e.name).json")
    Assert-NoOverwrite -Path $out -Force:$Force
    [IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
  } else {
    $out = Join-Path $OutDir ("$($e.name).vsynpreset")
    Assert-NoOverwrite -Path $out -Force:$Force
    Write-ZstdRaw ([Text.Encoding]::UTF8.GetBytes($t)) $out
  }
  Write-Host ("wrote {0}" -f (Split-Path $out -Leaf))
}
