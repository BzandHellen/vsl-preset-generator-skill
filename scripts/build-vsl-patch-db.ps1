<#
  build-vsl-patch-db.ps1  (skill copy)

  Build/extend a patch + factory-preset database for installed VSL Synchron Player libraries.

  Each "<something>_Patches.syvolume" embeds ONE zstd frame (magic 28 B5 2F FD) whose payload is JSON:
      { "instruments": { "at.co.vsl.synchronplayer": { "presets": {...} } },
        "patches":     { "<collection>": { "<product>": { "<instrument>": { "<articulation>": { "<patch>.vsynpatch": index } } } } } }

  7-Zip can DECOMPRESS zstd. Locate the magic, carve a slice, unpack with 7z, walk the tree.

  Caching: each volume is cached under <OutDir>\cache\<hash>.json keyed by path+size+mtime, so re-runs only
  re-extract volumes that changed (a full machine rebuild is ~90 s; a refresh is a few seconds).

  Usage:
    powershell -ExecutionPolicy Bypass -File build-vsl-patch-db.ps1
    ... -LibraryRoot "D:\VSL Library" -OutDir "<...>\data" -Force
#>
param(
  [string]$LibraryRoot = "D:\VSL Library",
  [string]$OutDir      = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data'),
  [string]$SevenZip    = "C:\Program Files\7-Zip\7z.exe",
  [int]$ScanCapMB      = 12,
  [int]$CarveMB        = 2,
  [switch]$Force
)
$ErrorActionPreference = 'Continue'
$enc = [Text.Encoding]::GetEncoding(28591)
$cacheDir = Join-Path $OutDir 'cache'
New-Item -ItemType Directory -Force $OutDir   | Out-Null
New-Item -ItemType Directory -Force $cacheDir | Out-Null

function Get-ZstdFrameOffset([byte[]]$buf) {
  $cap=$buf.Length; $i=0
  while ($true) {
    $j=[Array]::IndexOf($buf,[byte]0x28,$i)
    if ($j -lt 0 -or $j -ge $cap-4) { return -1 }
    if ($buf[$j+1]-eq 0xB5 -and $buf[$j+2]-eq 0x2F -and $buf[$j+3]-eq 0xFD) { return $j }
    $i=$j+1
  }
}
function Walk-Tree($obj,[string]$pfx,$sink) {
  foreach ($p in $obj.PSObject.Properties) {
    if ($p.Value -is [int] -or $p.Value -is [long]) {
      $segs = $pfx.Split('/')
      $sink.Add([pscustomobject]@{
        Collection   = if ($segs.Count -gt 0) { $segs[0] } else { '' }
        Product      = if ($segs.Count -gt 1) { $segs[1] } else { '' }
        Instrument   = if ($segs.Count -gt 2) { $segs[2] } else { '' }
        Articulation = if ($segs.Count -gt 3) { $segs[3] } else { '' }
        Path         = $pfx
        File         = $p.Name
        Index        = [int]$p.Value
      })
    } else { Walk-Tree $p.Value "$pfx/$($p.Name)" $sink }
  }
}

$volumes = Get-ChildItem $LibraryRoot -Recurse -File -Filter *.syvolume -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -match 'Patches' } | Sort-Object FullName
Write-Host "found $($volumes.Count) '*Patches*' volumes under $LibraryRoot"

$swAll=[Diagnostics.Stopwatch]::StartNew()
$extracted=0; $cached=0; $skipped=0
$work = Join-Path $env:TEMP ("vslpatchdb_" + [Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $work | Out-Null

foreach ($v in $volumes) {
  $key = ($v.FullName.ToLower() -replace '[^a-z0-9]','_')
  if ($key.Length -gt 120) { $key = $key.Substring($key.Length-120) }
  $cache = Join-Path $cacheDir ($key + '.json')
  $stamp = "$($v.Length)|$($v.LastWriteTimeUtc.Ticks)"
  if (-not $Force -and (Test-Path $cache)) {
    try { $c = Get-Content $cache -Raw | ConvertFrom-Json; if ($c.stamp -eq $stamp) { $cached++; continue } } catch {}
  }
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $cid=''; $desc=''
  $fs=[IO.File]::OpenRead($v.FullName)
  try { $hb=New-Object byte[] ([Math]::Min(16384,$fs.Length)); [void]$fs.Read($hb,0,$hb.Length) } finally { $fs.Close() }
  $ht=$enc.GetString($hb)
  $cid  = [regex]::Match($ht,'"id"\s*:\s*"([^"]*)"').Groups[1].Value
  $desc = [regex]::Match($ht,'"description"\s*:\s*"([^"]*)"').Groups[1].Value

  $cap=[Math]::Min($v.Length,[int64]$ScanCapMB*1MB)
  $fs=[IO.File]::OpenRead($v.FullName)
  try { $buf=New-Object byte[] ([int]$cap); [void]$fs.Read($buf,0,[int]$cap) } finally { $fs.Close() }
  $off=Get-ZstdFrameOffset $buf
  $patches=New-Object System.Collections.Generic.List[object]
  $presets=New-Object System.Collections.Generic.List[object]
  if ($off -lt 0) {
    [pscustomobject]@{ stamp=$stamp; file=$v.Name; cid=$cid; desc=$desc; patches=@(); presets=@() } |
      ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $cache
    Write-Host ("  {0,-52} no zstd frame" -f $v.Name); $skipped++; continue
  }
  $n=[Math]::Min([int64]$CarveMB*1MB, $cap-$off)
  $d=Join-Path $work ([Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $d|Out-Null
  [IO.File]::WriteAllBytes((Join-Path $d 'f.zst'), $buf[$off..($off+$n-1)])
  & $SevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
  $dec=Get-ChildItem "$d\out" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($dec) {
    try {
      $j = ($enc.GetString([IO.File]::ReadAllBytes($dec.FullName)) | ConvertFrom-Json)
      if ($j.patches) { foreach ($col in $j.patches.PSObject.Properties) { Walk-Tree $col.Value $col.Name $patches } }
      $pre = $j.instruments.'at.co.vsl.synchronplayer'.presets
      if ($pre) { foreach ($col in $pre.PSObject.Properties) { Walk-Tree $col.Value $col.Name $presets } }
    } catch { Write-Host ("  {0,-52} parse failed: {1}" -f $v.Name,$_.Exception.Message) }
  }
  Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
  [pscustomobject]@{ stamp=$stamp; file=$v.Name; cid=$cid; desc=$desc; patches=$patches; presets=$presets } |
    ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $cache
  $sw.Stop()
  Write-Host ("  {0,-52} ok p+{1,-4} pre+{2,-4} {3,5} ms" -f $v.Name,$patches.Count,$presets.Count,$sw.ElapsedMilliseconds)
  $extracted++
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

# ---- aggregate ----
$allP=New-Object System.Collections.Generic.List[object]
$allPre=New-Object System.Collections.Generic.List[object]
$seen=New-Object 'System.Collections.Generic.HashSet[string]'
Get-ChildItem $cacheDir -Filter *.json | ForEach-Object {
  $c = Get-Content $_.FullName -Raw | ConvertFrom-Json
  foreach ($r in $c.patches) {
    $k = "$($c.file)|$($r.Collection)|$($r.Product)|$($r.Instrument)|$($r.Articulation)|$($r.File)"
    if ($seen.Add($k)) { $allP.Add([pscustomobject]@{ Volume=$c.file; ContentId=$c.cid; Description=$c.desc; Collection=$r.Collection; Product=$r.Product; Instrument=$r.Instrument; Articulation=$r.Articulation; PatchFile=$r.File; Index=$r.Index; Path=$r.Path }) }
  }
  foreach ($r in $c.presets) {
    $allPre.Add([pscustomobject]@{ Volume=$c.file; ContentId=$c.cid; Collection=$r.Collection; Product=$r.Product; Path=$r.Path; PresetFile=$r.File; Index=$r.Index })
  }
}
$allP  | Sort-Object Collection,Product,Instrument,Articulation,PatchFile | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutDir 'vsl-patches.csv')
$allPre| Sort-Object Collection,Product,PresetFile                              | Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutDir 'vsl-presets.csv')
$allP  | Group-Object Collection | Sort-Object Name |
  Select-Object @{n='Collection';e={$_.Name}},@{n='Patches';e={$_.Count}} |
  Export-Csv -NoTypeInformation -Encoding UTF8 (Join-Path $OutDir 'vsl-patches-by-collection.csv')
$swAll.Stop()
Write-Host ""
Write-Host ("DONE: {0} patches, {1} factory presets | extracted {2}, cached {3}, skipped {4} | {5:N1}s" -f $allP.Count,$allPre.Count,$extracted,$cached,$skipped,$swAll.Elapsed.TotalSeconds)
