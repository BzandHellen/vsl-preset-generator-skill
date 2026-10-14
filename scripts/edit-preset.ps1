<#
  edit-preset.ps1  —  edit fields of a preset / root slot and write a NEW file.

  Edits are a JSON array of ops, each with a "path" = list of node titles from the root
  ([] = the root node itself):

    { "op":"setField",  "path":["NV-Vib Leg"], "field":"switchControl", "value":257 }
    { "op":"setField",  "path":["Breathing Leg","Soft At-Rs"], "field":"velXFadeMode", "value":1 }
    { "op":"setPatch",  "path":["Harmonics","Harmonics"],
                        "patchEntry":"vol://…/11 VI-14 Harmonics long.vsynpatch",
                        "patchName":"11 VI-14 Harmonics long" }
    { "op":"setXfades", "path":[""], "steps":8 }                    // 每 8 值一档（末档到 127）
    { "op":"setXfades", "path":["Trills"], "explicit":[[0,15],[16,31],[32,127]] }   // CC 区间
    { "op":"removeSlot","path":["Pizzicato"], "slot":"Pizzicato" }

  Safety: output must be under a "Generated"/"generated" folder (else -AllowOutsideGenerated),
  and an existing file is never overwritten unless -Force.

  Usage:
    powershell -File edit-preset.ps1 -Preset "…\x.vsynpreset" -Edits ".\edits.json" `
      -OutDir "C:\...\Vienna Synchron Player\Presets\Generated"
#>
param(
  [Parameter(Mandatory)][string]$Preset,
  [Parameter(Mandatory)][string]$Edits,
  [Parameter(Mandatory)][string]$OutDir,
  [string]$Name,
  [switch]$Force,
  [switch]$AllowOutsideGenerated
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"

$text = Get-PresetText -File $Preset
$slice = Get-TreeSlice -Text $text
$root = $slice.text | ConvertFrom-Json
$ops = if (Test-Path -LiteralPath $Edits) { Get-Content -LiteralPath $Edits -Raw | ConvertFrom-Json } else { $Edits | ConvertFrom-Json }
$ops = @($ops)

function Get-Path([string[]]$titles) {
  $cur = $root
  foreach ($w in @($titles)) {
    if ($w -eq '') { continue }
    $ok = $false
    foreach ($c in @($cur.nodes)) { if ($c.title -eq $w) { $cur = $c; $ok = $true; break } }
    if (-not $ok) { throw "node not found: '$w' (in path $($titles -join '/'))" }
  }
  return $cur
}

# ---- tree ops ----------------------------------------------------------------
foreach ($op in @($ops | Where-Object { $_.op -ne 'setController' })) {
  switch ($op.op) {
    'setField' {
      $n = Get-Path $op.path
      if ($n.PSObject.Properties.Name -contains $op.field) { $n.$($op.field) = $op.value }
      else { $n | Add-Member -NotePropertyName $op.field -NotePropertyValue $op.value }
    }
    'setPatch' {
      $n = Get-Path $op.path
      $n.patchEntry = $op.patchEntry
      if ($op.patchName) { $n.patchName = $op.patchName }
    }
    'setXfades' {
      $n = Get-Path $op.path
      $kids = @($n.nodes).Count
      $arr = @()
      if ($op.explicit) {
        foreach ($pair in $op.explicit) {
          $arr += [pscustomobject]@{ fadeInStart=([double]$pair[0]/127); fadeInEnd=([double]$pair[0]/127); fadeOutStart=([double]$pair[1]/127); fadeOutEnd=([double]$pair[1]/127) }
        }
      } else {
        $steps = if ($op.steps) { [int]$op.steps } else { 8 }
        for ($i=0; $i -lt $kids; $i++) {
          $lo = $steps * $i
          $hi = if ($i -eq $kids-1) { 127 } else { ($steps * ($i+1)) - 1 }
          $arr += [pscustomobject]@{ fadeInStart=($lo/127.0); fadeInEnd=($lo/127.0); fadeOutStart=($hi/127.0); fadeOutEnd=($hi/127.0) }
        }
      }
      $n.nodeXFades = $arr
    }
    'removeSlot' {
      $n = Get-Path $op.path
      $kids = @($n.nodes)
      $idx = -1
      for ($i=0; $i -lt $kids.Count; $i++) { if ($kids[$i].title -eq $op.slot) { $idx = $i; break } }
      if ($idx -lt 0) { throw "slot not found: $($op.slot)" }
      $n.nodes = @($kids | Where-Object { $_.title -ne $op.slot })
      if ($n.nodeXFades) { $xf = @($n.nodeXFades); $n.nodeXFades = @($xf[0..($idx-1)] + $xf[($idx+1)..($xf.Count-1)]) }
    }
    default { throw "unknown op: $($op.op)" }
  }
}

$newText = Set-TreeSlice -Text $text -Slice $slice -NewObjectText ($root | ConvertTo-Json -Depth 100 -Compress)

# ---- controller ops: setController (paramControl.mappings) --------------------
$ctrlOps = @($ops | Where-Object { $_.op -eq 'setController' })
if ($ctrlOps.Count -gt 0) {
  if ($newText -notmatch '"paramControl"') { throw "this target has no paramControl block (root slots don't carry one)" }
  $pcSlice = Get-ObjectSlice -Text $newText -Key 'paramControl'
  $pc = $pcSlice.text | ConvertFrom-Json
  if (-not $pc.mappings) { $pc | Add-Member -NotePropertyName mappings -NotePropertyValue ([pscustomobject]@{}) }
  foreach ($op in $ctrlOps) {
    $dest = $op.destination
    if (-not $dest -and $op.dimCtrl) {
      $i = 'ABCDEFGH'.IndexOf(([string]$op.dimCtrl).ToUpper())
      if ($i -lt 0) { throw "bad dimCtrl '$($op.dimCtrl)' (use A..H)" }
      $dest = "nodeXFade$i"
    }
    if (-not $dest) { throw "setController needs 'destination' or 'dimCtrl'" }
    if ($pc.mappings.PSObject.Properties.Name -contains $dest) { $entry = $pc.mappings.$dest }
    else { $entry = New-Object psobject; $pc.mappings | Add-Member -NotePropertyName $dest -NotePropertyValue $entry }
    function Set-Prop($obj,[string]$name,$value) {
      if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
    }
    if ($op.source) { Set-Prop $entry 'source' $op.source }
    if ($null -ne $op.bipolar) { Set-Prop $entry 'bipolar' $op.bipolar }
    if ($null -ne $op.curve) { Set-Prop $entry 'curve' $op.curve }
    if ($op.range) { Set-Prop $entry 'rangeFrom' ([int]$op.range[0]); Set-Prop $entry 'rangeTo' ([int]$op.range[1]) }
  }
  $newText = Set-TreeSlice -Text $newText -Slice $pcSlice -NewObjectText ($pc | ConvertTo-Json -Depth 100 -Compress)
}

$out = Assert-GeneratedDir -OutDir $OutDir -AllowOutsideGenerated:$AllowOutsideGenerated
New-Item -ItemType Directory -Force $out | Out-Null
if (-not $Name) { $Name = (Split-Path -LeafBase $Preset) + " (edited)" }
$target = Join-Path $out ($Name + ".vsynpreset")
Assert-NoOverwrite -Path $target -Force:$Force
Write-ZstdRaw -Data ([Text.Encoding]::UTF8.GetBytes($newText)) -Path $target
Write-Host ("wrote {0}  ({1} bytes, {2} ops)" -f (Split-Path $target -Leaf), (Get-Item $target).Length, @($ops).Count)
