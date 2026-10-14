<#
  unpack-volume.ps1  —  extract the patch/preset tree embedded in a VSL *.syvolume.

  Usage:
    powershell -File unpack-volume.ps1 -Volume "D:\VSL Library\...\SY-Strings-Pro_1stviolins_Patches.syvolume"
    powershell -File unpack-volume.ps1 -Volume <...> -Mode patches -Limit 50
#>
param(
  [Parameter(Mandatory)][string]$Volume,
  [ValidateSet('patches','presets','raw')][string]$Mode = 'patches',
  [int]$Limit = 0,
  [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe"
)
$ErrorActionPreference='Stop'
$enc=[Text.Encoding]::GetEncoding(28591)
$v=Get-Item $Volume
function Get-FrameOffset([byte[]]$buf){ $i=0;$cap=$buf.Length
  while($true){ $j=[Array]::IndexOf($buf,[byte]0x28,$i); if($j -lt 0 -or $j -ge $cap-4){return -1}
    if($buf[$j+1]-eq 0xB5 -and $buf[$j+2]-eq 0x2F -and $buf[$j+3]-eq 0xFD){return $j}; $i=$j+1 } }
$cap=[Math]::Min($v.Length,[int64]12MB)
$fs=[IO.File]::OpenRead($v.FullName); try{ $buf=New-Object byte[] ([int]$cap); [void]$fs.Read($buf,0,[int]$cap) } finally { $fs.Close() }
$off=Get-FrameOffset $buf
if($off -lt 0){ Write-Error "no zstd frame in $($v.Name)"; exit 1 }
$n=[Math]::Min([int64]2MB,$cap-$off)
$d=Join-Path $env:TEMP ("vslunpack_"+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $d|Out-Null
# adaptive carve: the frame size is unknown, so try growing slices until 7z yields output
$dec=$null
foreach($mb in 0.25,1,4,12){
  $n=[Math]::Min([int64]($mb*1MB), $cap-$off)
  Remove-Item "$d\out" -Recurse -Force -ErrorAction SilentlyContinue
  [IO.File]::WriteAllBytes((Join-Path $d 'f.zst'), $buf[$off..($off+$n-1)])
  & $SevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
  $dec=Get-ChildItem "$d\out" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if($dec -and $dec.Length -gt 0){ break }
}
if(-not $dec){ Write-Error "could not extract frame from $($v.Name)"; exit 1 }
$txt=$enc.GetString([IO.File]::ReadAllBytes($dec.FullName)); Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
if($Mode -eq 'raw'){ [Console]::Out.Write($txt); exit 0 }
$j=$txt|ConvertFrom-Json
$list=New-Object System.Collections.Generic.List[string]
function Walk($obj,[string]$pfx,$sink){ foreach($p in $obj.PSObject.Properties){
  if($p.Value -is [int] -or $p.Value -is [long]){ $sink.Add("$pfx/$($p.Name)") } else { Walk $p.Value "$pfx/$($p.Name)" $sink } } }
if($Mode -eq 'patches' -and $j.patches){ Walk $j.patches '' $list }
if($Mode -eq 'presets'){ $pre=$j.instruments.'at.co.vsl.synchronplayer'.presets; if($pre){ Walk $pre '' $list } }
$list = $list | ForEach-Object { $_.TrimStart('/') }
$total=@($list).Count
if($Limit -gt 0){ $list = $list | Select-Object -First $Limit }
@{ volume=$v.Name; mode=$Mode; total=$total; returned=@($list).Count; paths=@($list) } | ConvertTo-Json -Depth 3
