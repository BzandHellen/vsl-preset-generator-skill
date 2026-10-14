<#
  compare-presets.ps1  —  compare two or more presets / root slots node by node.

  Walks every tree by position (index path) and reports differences, so you can spot
  "cross-section" mistakes (e.g. a slot in section A pointing at section B's patch).

  Normalization (on by default): instrument abbreviations are replaced with "@" in
  patch names and patch file names, and the vol://…:public/patches/… prefix is dropped,
  so only the *articulation* part is compared. Add/override tokens with -Tokens.

  Usage:
    powershell -File compare-presets.ps1 -Preset "…\Vln1.vsynpreset","…\Vln2.vsynpreset"
    powershell -File compare-presets.ps1 -Preset <…> -Json -Tokens "VI-14","VI-10"
#>
param(
  [Parameter(Mandatory)][string[]]$Preset,
  [switch]$Json,
  [switch]$NoNormalize,
  [string[]]$Tokens = @(
    'VI-14','VI-12','VI-10','VI-8','VA-8','VA-6','VC-8','VC-6','DB-6','DB-5',
    '1st Violins-14','2nd Violins-10','Violas-8','Cellos-8','Violoncellos-8','Double basses-6',
    'violins1','violins2','violas','cellos','basses'
  )
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"
# -File passes a comma list as ONE string, so split it back
if ($Preset.Count -eq 1 -and $Preset[0] -match ',') { $Preset = $Preset[0] -split '\s*,\s*' }
if ($Tokens.Count -eq 1 -and $Tokens[0] -match ',') { $Tokens = $Tokens[0] -split '\s*,\s*' }
if ($Preset.Count -lt 2) { throw "need at least 2 presets (got $($Preset.Count))" }

function Normalize([string]$s) {
  if (-not $s) { return '' }
  $x = $s
  if ($NoNormalize) { return $x }
  foreach ($tk in $Tokens) { $x = $x.Replace($tk, '@') }
  $x = [regex]::Replace($x, '^vol://[^:]*:public/patches/', '')
  return $x
}
function Flat($root) {
  $list = New-Object System.Collections.Generic.List[object]
  function W($node, [string]$idx, [string]$titlePath) {
    $tp = $titlePath.Trim('/')
    $isFolder = ($node.PSObject.Properties.Name -contains 'nodes')
    if ($isFolder) {
      $list.Add([pscustomobject]@{ idx=$idx; kind='folder'; title=$node.title; subTitle=$node.subTitle;
        switchControl=$node.switchControl; parallel=[string]$node.parallel; children=@($node.nodes).Count; key="F|$tp|$($node.title)" })
      for ($i=0; $i -lt @($node.nodes).Count; $i++) { W $node.nodes[$i] "$idx.$i" "$titlePath/$($node.title)" }
    } else {
      $fn = if ($node.patchEntry) { Normalize (Split-Path -Leaf $node.patchEntry) } else { '' }
      $list.Add([pscustomobject]@{ idx=$idx; kind='patch'; title=$node.title; subTitle='';
        switchControl=$null; parallel=''; children=0; key="P|$tp|$($node.title)";
        patchName=(Normalize $node.patchName); file=$fn; range="$($node.rangeFrom)-$($node.rangeTo)"; velXFadeMode=$node.velXFadeMode })
    }
  }
  W $root '' ''
  return $list
}

$trees = @()
foreach ($p in $Preset) { $trees += ,(Flat (Get-RootNode -Text (Get-PresetText -File $p))) }

$names = $Preset | ForEach-Object { Split-Path -Leaf $_ }
$diffs = New-Object System.Collections.Generic.List[object]
$maxN = ($trees | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
for ($i=0; $i -lt $maxN; $i++) {
  $nodes = $trees | ForEach-Object { if ($i -lt $_.Count) { $_[$i] } else { $null } }
  $ref = $nodes[0]
  for ($k=1; $k -lt $nodes.Count; $k++) {
    $c = $nodes[$k]
    if (-not $ref -or -not $c) { $diffs.Add([pscustomobject]@{ idx=$i; preset=$names[$k]; field='(structure)'; ref=''; got='missing' }); continue }
    foreach ($fld in 'kind','title','switchControl','parallel','children','patchName','file','range','velXFadeMode') {
      $a = "$($ref.$fld)"; $b = "$($c.$fld)"
      if ($a -ne $b) { $diffs.Add([pscustomobject]@{ idx=$i; path=$ref.key; field=$fld; ref=$a; got=$b; preset=$names[$k] }) }
    }
  }
}
# --- controller mappings (paramControl.mappings = Dim.Ctrl A-H / automation) ---
$maps = @()
foreach ($p in $Preset) {
  $t = Get-PresetText -File $p
  if ($t -match '"paramControl"') { $maps += ,(((Get-ObjectSlice -Text $t -Key 'paramControl').text | ConvertFrom-Json).mappings) } else { $maps += ,$null }
}
$ctrlDiffs = New-Object System.Collections.Generic.List[object]
$dests = @(); foreach ($m in $maps) { if ($m) { $dests += $m.PSObject.Properties.Name } }
foreach ($d in ($dests | Select-Object -Unique)) {
  $vals = foreach ($m in $maps) { if ($m -and ($m.PSObject.Properties.Name -contains $d)) { "$($m.$d.source)" } else { '(none)' } }
  if (@($vals | Select-Object -Unique).Count -gt 1) { $ctrlDiffs.Add([pscustomobject]@{ destination=$d; perPreset=@($vals) }) }
}

if ($Json) { @{ presets=$names; diffCount=$diffs.Count; diffs=$diffs; controllerDiffCount=$ctrlDiffs.Count; controllerDiffs=$ctrlDiffs } | ConvertTo-Json -Depth 5; return }
"presets: $($names -join '  |  ')"
"nodes per preset: " + (($trees | ForEach-Object { $_.Count }) -join ', ')
if ($ctrlDiffs.Count -gt 0) {
  "CONTROLLER MAP DIFFERENCES: $($ctrlDiffs.Count)"
  foreach ($c in $ctrlDiffs) { "  {0}: {1}" -f $c.destination, ($c.perPreset -join ' | ') }
} else { "controller map: identical" }
if ($diffs.Count -eq 0) { "NO TREE DIFFERENCES"; return }
"TREE DIFFERENCES: $($diffs.Count)"
$diffs | ForEach-Object { "  [{0}] vs {1}  {2}: {3}  ->  {4}" -f $_.path,$_.preset,$_.field,$_.ref,$_.got }
