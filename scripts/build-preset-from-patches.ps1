<#
  build-preset-from-patches.ps1

  Build a Synchron Player preset from an explicit list of patches, reusing an existing preset as the
  "shell" (schema + mixer). Handy when you don't have a template preset for that instrument yet
  (e.g. build a Horn preset out of Legato / Long / Marcato / Rips patches).

  Spec JSON:
    {
      "name":          "Horn 1 - Legato Long Marcato Rips",
      "currentPreset": "Generated/Horn 1 - Legato Long Marcato Rips",
      "rootTitle":     "",                       // optional
      "switchControl": 260,                      // optional (default: keep shell's)
      "patches": [
        { "title":"Legato",  "patchEntry":"vol://at.co.vsl.sy.brass.ho1:public/patches/21 Synchron Brass/11 Horn 1/02 Legato/01 HO1 Legato.vsynpatch",
                             "patchName":"01 HO1 Legato", "range": [34, 82] },
        ...
      ]
    }
  "range" is optional; when omitted the rangeFrom/rangeTo fields are removed so the player refills them.

  Usage:
    powershell -ExecutionPolicy Bypass -File build-preset-from-patches.ps1 `
      -Shell "C:\...\STR Synchron Vln1 a14.vsynpreset" -Spec ".\horn.json" -OutDir "C:\...\Presets\Generated"
#>
param(
  [Parameter(Mandatory)][string]$Shell,
  [Parameter(Mandatory)][string]$SpecFile,
  [string]$OutDir   = ".",
  [string]$SevenZip = "C:\Program Files\7-Zip\7z.exe",
  [switch]$Force,
  [switch]$AllowOutsideGenerated
)
$ErrorActionPreference='Stop'
. "$PSScriptRoot\vsl-common.ps1"
$OutDir = Assert-GeneratedDir -OutDir $OutDir -AllowOutsideGenerated:$AllowOutsideGenerated
New-Item -ItemType Directory -Force $OutDir | Out-Null

function Read-PresetText([string]$file){
  if ($file -match '\.vsynpreset$') {
    $d=Join-Path $env:TEMP ("vslshell_"+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $d|Out-Null
    Copy-Item $file (Join-Path $d 'f.zst') -Force
    & $SevenZip x -y ("-o$d\out") (Join-Path $d 'f.zst') 2>$null | Out-Null
    $dec=Get-ChildItem "$d\out" -File | Select-Object -First 1
    $t=[IO.File]::ReadAllText($dec.FullName); Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; return $t
  }
  return [IO.File]::ReadAllText($file)
}
function Write-ZstdRaw([byte[]]$data,[string]$path){
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
# find "rootNode":{ ... } with brace matching (string-aware)
function Get-ObjectSlice([string]$text,[string]$key){
  $i = $text.IndexOf('"' + $key + '":')
  if ($i -lt 0) { throw "key '$key' not found" }
  $s = $text.IndexOf('{', $i); $d=0; $inStr=$false; $esc=$false
  for ($j=$s; $j -lt $text.Length; $j++) {
    $c=$text[$j]
    if ($inStr) { if ($esc) { $esc=$false } elseif ($c -eq '\') { $esc=$true } elseif ($c -eq '"') { $inStr=$false } }
    else { if ($c -eq '"') { $inStr=$true } elseif ($c -eq '{') { $d++ } elseif ($c -eq '}') { $d--; if ($d -eq 0) { return @{ start=$s; end=$j; text=$text.Substring($s,$j-$s+1) } } } }
  }
  throw "unbalanced braces for '$key'"
}
function Find-PatchNode($node){
  if ($node.PSObject.Properties.Name -contains 'patchEntry') { return $node }
  if ($node.PSObject.Properties.Name -contains 'nodes') { foreach ($c in $node.nodes) { $r = Find-PatchNode $c; if ($r) { return $r } } }
  return $null
}

$shellText = Read-PresetText $Shell
$slice = Get-ObjectSlice $shellText 'rootNode'
$rn = $slice.text | ConvertFrom-Json
$patchTmpl = Find-PatchNode $rn
if (-not $patchTmpl) { throw "no patch node found inside shell rootNode" }
# a nodeXFades array with the right length (fall back to any)
$xf = $null
foreach ($n in $rn.nodes) { if ($n.nodeXFades -and $n.nodeXFades.Count -ge 1) { $xf = $n.nodeXFades; break } }

$spec = Get-Content $SpecFile -Raw | ConvertFrom-Json
if (-not $spec -or -not $spec.patches) { throw "spec '$SpecFile' has no 'patches' array" }
$children = New-Object System.Collections.Generic.List[object]
foreach ($p in $spec.patches) {
  $c = $patchTmpl | ConvertTo-Json -Depth 100 | ConvertFrom-Json   # deep clone
  $c.patchEntry = $p.patchEntry
  $c.patchName  = $p.patchName
  $c.title      = $p.title
  $c.isCustomTitle = $true
  $c.enabled    = $true
  $c.PSObject.Properties.Remove('rangeFrom')
  $c.PSObject.Properties.Remove('rangeTo')
  if ($p.range) {
    $c | Add-Member -NotePropertyName rangeFrom -NotePropertyValue ([int]$p.range[0])
    $c | Add-Member -NotePropertyName rangeTo   -NotePropertyValue ([int]$p.range[1])
  }
  $children.Add($c)
}
$rn.nodes = $children.ToArray()
if ($spec.rootTitle -ne $null) { $rn.title = $spec.rootTitle }
if ($spec.switchControl) { $rn.switchControl = [int]$spec.switchControl }
$nf = @()
for ($k=0; $k -lt $children.Count; $k++) {
  if ($xf -and $k -lt $xf.Count) { $nf += $xf[$k] }
  else { $nf += [pscustomobject]@{ fadeInStart=0.0; fadeInEnd=0.0; fadeOutEnd=1.0; fadeOutStart=1.0 } }
}
$rn.nodeXFades = $nf

$newRn = ($rn | ConvertTo-Json -Depth 100 -Compress)
$outText = $shellText.Substring(0,$slice.start) + $newRn + $shellText.Substring($slice.end+1)
if ($spec.currentPreset) { $outText = [regex]::Replace($outText,'"currentPreset"\s*:\s*"[^"]*"',('"currentPreset":"'+$spec.currentPreset+'"')) }
$out = Join-Path $OutDir ("$($spec.name).vsynpreset")
Assert-NoOverwrite -Path $out -Force:$Force
Write-ZstdRaw ([Text.Encoding]::UTF8.GetBytes($outText)) $out
Write-Host ("wrote {0}  ({1} patches)" -f (Split-Path $out -Leaf), $children.Count)
