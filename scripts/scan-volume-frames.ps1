<#
  scan-volume-frames.ps1  —  find every compressed frame in a VSL *.syvolume and try to decode it.

  Looks for several magic signatures (zstd, zstd-skippable, gzip, xz, lz4 frame, bzip2, 7z) at every
  offset, carves a slice at each and lets 7-Zip try to decode it, then reports the decoded size and
  whether the text looks like a preset body ("folderNodeData" / "rootNode" / "custom") or a patch tree
  ("patches" / "vsynpatch").

  Usage:
    powershell -File scan-volume-frames.ps1 -Volume "D:\...\SY-Strings-Pro_1stviolins_Patches.syvolume"
    powershell -File scan-volume-frames.ps1 -Volume <…> -MaxCandidates 50 -Json
#>
param(
  [Parameter(Mandatory)][string]$Volume,
  [int]$MaxCandidates = 60,
  [double]$CarveMB = 16,
  [switch]$Json
)
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\vsl-common.ps1"
$enc = [Text.Encoding]::GetEncoding(28591)
$v = Get-Item -LiteralPath $Volume

$MAGICS = @(
  @{ name='zstd';            bytes=@(0x28,0xB5,0x2F,0xFD) },
  @{ name='zstd-skippable';  bytes=@(0x50,0x2A,0x4D,0x18) },
  @{ name='gzip';            bytes=@(0x1F,0x8B) },
  @{ name='xz';              bytes=@(0xFD,0x37,0x7A,0x58,0x5A,0x00) },
  @{ name='lz4-frame';       bytes=@(0x04,0x22,0x4D,0x18) },
  @{ name='bzip2';           bytes=@(0x42,0x5A,0x68) },
  @{ name='7z';              bytes=@(0x37,0x7A,0xBC,0xAF,0x27,0x1C) }
)

$cap = [Math]::Min($v.Length, [int64]64MB)
$fs = [IO.File]::OpenRead($v.FullName)
try { $buf = New-Object byte[] ([int]$cap); [void]$fs.Read($buf,0,[int]$cap) } finally { $fs.Close() }

$hits = New-Object System.Collections.Generic.List[object]
foreach ($m in $MAGICS) {
  $mb = [byte[]]$m.bytes; $i = 0
  while ($true) {
    $j = [Array]::IndexOf($buf, $mb[0], $i)
    if ($j -lt 0 -or $j -ge $cap - $mb.Length) { break }
    $ok = $true
    for ($k=1; $k -lt $mb.Length; $k++) { if ($buf[$j+$k] -ne $mb[$k]) { $ok = $false; break } }
    if ($ok) { $hits.Add([pscustomobject]@{ offset=$j; magic=$m.name }); $i = $j + 1 } else { $i = $j + 1 }
  }
}
$hits = @($hits | Sort-Object offset)
Write-Host ("found {0} candidate frame(s) in {1}" -f $hits.Count, $v.Name)

$rows = New-Object System.Collections.Generic.List[object]
$work = Join-Path $env:TEMP ("vslscan_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
$n = 0
foreach ($h in $hits) {
  if ($n -ge $MaxCandidates) { break }
  $n++
  $off = $h.offset
  $len = [Math]::Min([int64]($CarveMB*1MB), $cap - $off)
  $d = Join-Path $work ("c$n"); New-Item -ItemType Directory -Force $d | Out-Null
  $slice = New-Object byte[] $len
  [Array]::Copy($buf, $off, $slice, 0, $len)
  [IO.File]::WriteAllBytes((Join-Path $d 'f.bin'), $slice)
  & $VslSevenZip x -y ("-o$d\out") (Join-Path $d 'f.bin') 2>$null | Out-Null
  $dec = Get-ChildItem "$d\out" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  $size = 0; $sample = ''; $kind = ''
  if ($dec) {
    $size = $dec.Length
    $t = $enc.GetString([IO.File]::ReadAllBytes($dec.FullName))
    if ($t -match '"folderNodeData"|"rootNode"|"currentPreset"') { $kind = 'PRESET-BODY?' }
    elseif ($t -match '"patches"|"vsynpatch"') { $kind = 'patch-tree' }
    elseif ($t -match '^\s*\{') { $kind = 'json?' }
    else { $kind = 'binary/other' }
    $sample = ($t.Substring(0,[Math]::Min(120,$t.Length)) -replace '[^\x20-\x7E]','.')
  }
  Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
  $rows.Add([pscustomobject]@{ offset=$off; magic=$h.magic; decoded=$size; kind=$kind; sample=$sample })
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

if ($Json) { @{ volume=$v.Name; candidates=$hits.Count; rows=$rows } | ConvertTo-Json -Depth 4; return }
"offset       magic            decoded      kind              sample"
foreach ($r in $rows) {
  "{0,-12} {1,-16} {2,10}   {3,-16}  {4}" -f $r.offset, $r.magic, $r.decoded, $r.kind, $r.sample
}
