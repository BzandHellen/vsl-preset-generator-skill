<#
  vsl-common.ps1  —  shared helpers for the VSL Synchron Player skill scripts.

  Dot-source it:  . "$PSScriptRoot\vsl-common.ps1"
#>

$VslSevenZip = if ($env:VSL_SEVENZIP) { $env:VSL_SEVENZIP } else { "C:\Program Files\7-Zip\7z.exe" }

# --- read a .vsynpreset (zstd) or a plain .json -------------------------------
function Get-PresetText {
  param([Parameter(Mandatory)][string]$File)
  if ($File -match '\.vsynpreset$') {
    $d = Join-Path $env:TEMP ("vsl_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $d | Out-Null
    Copy-Item $File (Join-Path $d 'f.zst') -Force
    & $VslSevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
    $dec = Get-ChildItem "$d\out" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dec) { throw "cannot decompress: $File" }
    $t = [IO.File]::ReadAllText($dec.FullName)
    Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
    return $t
  }
  return [IO.File]::ReadAllText($File)
}

# --- write a valid zstd frame (raw blocks; 7-Zip can only decompress zstd) -----
function Write-ZstdRaw {
  param([Parameter(Mandatory)][byte[]]$Data,[Parameter(Mandatory)][string]$Path)
  $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
  foreach ($b in 0x28,0xB5,0x2F,0xFD) { $bw.Write([byte]$b) }
  $bw.Write([byte]0xA0); $bw.Write([uint32]$Data.Length)
  $max = 131072; $off = 0
  while ($off -lt $Data.Length) {
    $sz = [Math]::Min($max, $Data.Length - $off); $last = if (($off+$sz) -ge $Data.Length) {1} else {0}
    $bh = [uint32]((([uint32]$sz) -shl 3) -bor [uint32]$last)
    $bw.Write([byte]($bh -band 0xFF)); $bw.Write([byte](($bh -shr 8) -band 0xFF)); $bw.Write([byte](($bh -shr 16) -band 0xFF))
    $bw.Write($Data,$off,$sz); $off += $sz
  }
  $bw.Flush(); [IO.File]::WriteAllBytes($Path, $ms.ToArray())
}

# --- slice the "{...}" that follows a top-level key (string-aware) ------------
function Get-ObjectSlice {
  param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string]$Key)
  $i = $Text.IndexOf('"' + $Key + '":')
  if ($i -lt 0) { throw "key '$Key' not found" }
  $s = $Text.IndexOf('{', $i); $d = 0; $inStr = $false; $esc = $false
  for ($j = $s; $j -lt $Text.Length; $j++) {
    $c = $Text[$j]
    if ($inStr) { if ($esc) { $esc = $false } elseif ($c -eq '\') { $esc = $true } elseif ($c -eq '"') { $inStr = $false } }
    else { if ($c -eq '"') { $inStr = $true } elseif ($c -eq '{') { $d++ } elseif ($c -eq '}') { $d--; if ($d -eq 0) { return @{ start=$s; end=$j; text=$Text.Substring($s,$j-$s+1) } } } }
  }
  throw "unbalanced braces for '$Key'"
}

# --- locate the dimension tree (preset: data.custom.sampler.rootNode ; root slot: folderNodeData)
function Get-TreeSlice {
  param([Parameter(Mandatory)][string]$Text)
  if ($Text -match '"folderNodeData"\s*:\s*\{') { return Get-ObjectSlice $Text 'folderNodeData' }
  return Get-ObjectSlice $Text 'rootNode'
}
function Set-TreeSlice {
  param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)]$Slice,[Parameter(Mandatory)][string]$NewObjectText)
  return $Text.Substring(0,$Slice.start) + $NewObjectText + $Text.Substring($Slice.end+1)
}

# --- node helpers -------------------------------------------------------------
function Get-RootNode {
  param([Parameter(Mandatory)][string]$Text)
  return ((Get-TreeSlice $Text).text | ConvertFrom-Json)
}
function Find-Node {
  param($Node,[Parameter(Mandatory)][string[]]$TitlePath)
  # TitlePath = folder titles from the root (root itself = ""), last element is the target
  $cur = $Node
  foreach ($want in $TitlePath) {
    if ($cur.PSObject.Properties.Name -notcontains 'nodes') { return $null }
    $next = $null
    foreach ($c in $cur.nodes) { if ($c.title -eq $want) { $next = $c; break } }
    if (-not $next) { return $null }
    $cur = $next
  }
  return $cur
}
function Get-CC { param($v) [int][math]::Round([double]$v * 127) }

# --- guard: never write outside a Generated/generated folder ------------------
function Assert-GeneratedDir {
  param([Parameter(Mandatory)][string]$OutDir,[switch]$AllowOutsideGenerated)
  $full = [IO.Path]::GetFullPath($OutDir)
  $parts = $full -split '[\\/]'
  $inGenerated = @($parts | Where-Object { $_ -ieq 'generated' }).Count -gt 0
  if ($inGenerated) { return $full }
  if ($AllowOutsideGenerated -or $env:VSL_ALLOW_OUTSIDE_GENERATED -eq '1') { return $full }
  throw ("拒绝写入 Generated 目录之外的路径（保护你手写的预设）：$full" + "`n" +
         "如确实要写这里，请显式加 -AllowOutsideGenerated，或设环境变量 VSL_ALLOW_OUTSIDE_GENERATED=1。")
}
function Assert-NoOverwrite {
  param([Parameter(Mandatory)][string]$Path,[switch]$Force)
  if ((Test-Path -LiteralPath $Path) -and (-not $Force) -and ($env:VSL_ALLOW_OVERWRITE -ne '1')) {
    throw "目标已存在，默认不覆盖：$Path  （要覆盖请加 -Force）"
  }
}
