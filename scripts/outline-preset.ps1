<#
  outline-preset.ps1  —  print the full dimension tree of a preset / root slot.

  Shows, per node: kind (folder/patch), title, and for folders: subTitle, switchControl
  (with its A–D slot letter), parallel, child count and the nodeXFades ranges converted
  to CC values; for patch slots: patchName, play range, velXFadeMode, legatoMode, enabled
  (and patchEntry with -IncludeEntry).

  Usage:
    powershell -File outline-preset.ps1 -Preset "C:\...\STR Synchron Vln1 a14.vsynpreset"
    powershell -File outline-preset.ps1 -Preset <...> -Json
#>
param(
  [Parameter(Mandatory)][string]$Preset,
  [switch]$Json,
  [switch]$IncludeEntry,
  [int]$MaxDepth = 20
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"

$text = Get-PresetText -File $Preset
$root = Get-RootNode -Text $text

$rows = New-Object System.Collections.Generic.List[object]
function SlotLetter($sc) { switch ([int]$sc) { 257 {'A'} 258 {'B'} 259 {'C'} 260 {'D'} default {''} } }
function Walk($node, [string]$path, [int]$depth) {
  if ($depth -gt $MaxDepth) { return }
  $isFolder = ($node.PSObject.Properties.Name -contains 'nodes')
  $p = if ($path) { "$path/$($node.title)" } else { $node.title }
  if ($isFolder) {
    $xf = @()
    if ($node.nodeXFades) { for ($i=0; $i -lt $node.nodeXFades.Count; $i++) {
      $e = $node.nodeXFades[$i]
      $xf += ("{0}-{1}" -f (Get-CC $e.fadeInStart), (Get-CC $e.fadeOutEnd)) } }
    $rows.Add([pscustomobject]@{
      kind='folder'; depth=$depth; path=$p; title=$node.title; subTitle=$node.subTitle
      switchControl=$node.switchControl; slot=(SlotLetter $node.switchControl)
      parallel=$node.parallel; children=@($node.nodes).Count; xfade_cc=($xf -join ',')
      patchName=''; range=''; velXFadeMode=$null; legatoMode=$null; enabled=$null; patchEntry=$null
    })
    foreach ($c in $node.nodes) { Walk $c $p ($depth+1) }
  } else {
    $r = if ($null -ne $node.rangeFrom) { "$($node.rangeFrom)-$($node.rangeTo)" } else { '' }
    $rows.Add([pscustomobject]@{
      kind='patch'; depth=$depth; path=$p; title=$node.title; subTitle=''
      switchControl=$null; slot=''; parallel=$null; children=0; xfade_cc=''
      patchName=$node.patchName; range=$r; velXFadeMode=$node.velXFadeMode
      legatoMode=$node.legatoMode; enabled=$node.enabled; patchEntry=$node.patchEntry
    })
  }
}
Walk $root '' 0

# controller map (Dim.Ctrl / automation), if this is a full preset
$cm = New-Object System.Collections.Generic.List[object]
if ($text -match '"paramControl"') {
  $pc = (Get-ObjectSlice -Text $text -Key 'paramControl').text | ConvertFrom-Json
  if ($pc.mappings) {
    foreach ($p in $pc.mappings.PSObject.Properties) {
      $lbl = $p.Name
      if ($p.Name -match '^nodeXFade(\d+)$') { $i=[int]$Matches[1]; $lbl = "{0} (Dim.Ctrl {1})" -f $p.Name, [char](65+$i) }
      $cm.Add([pscustomobject]@{ destination=$p.Name; label=$lbl; source="$($p.Value.source)" })
    }
  }
}

if ($Json) {
  if (-not $IncludeEntry) { $rows | ForEach-Object { $_.patchEntry = $null } }
  @{ preset=$Preset; nodes=$rows; controllerMap=$cm } | ConvertTo-Json -Depth 5
  return
}
foreach ($r in $rows) {
  $ind = '  ' * $r.depth
  if ($r.kind -eq 'folder') {
    $sl = if ($r.slot) { "($($r.slot))" } else { '' }
    "{0}[folder] {1}  sub='{2}' switchControl={3}{4} parallel={5} children={6}" -f $ind,$r.title,$r.subTitle,$r.switchControl,$sl,$r.parallel,$r.children
    if ($r.xfade_cc) { "{0}         xfade(CC): {1}" -f $ind,$r.xfade_cc }
  } else {
    $ex = "patch='$($r.patchName)' range=$($r.range) velXFadeMode=$($r.velXFadeMode) legato=$($r.legatoMode) enabled=$($r.enabled)"
    if ($IncludeEntry) { $ex += " entry='$($r.patchEntry)'" }
    "{0}- {1}  {2}" -f $ind,$r.title,$ex
  }
}
if ($cm.Count -gt 0) {
  ""
  "controller map (paramControl.mappings):"
  foreach ($c in $cm) { "  {0,-22} -> {1}" -f $c.label, $c.source }
}
