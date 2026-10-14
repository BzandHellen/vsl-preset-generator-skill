<#
  controller-map.ps1  —  read the MIDI controller map (Dim.Ctrl / automation) of a preset.

  Where it lives: the preset JSON has  data.custom.paramControl.mappings  =  { <destination>: { source, curve, rangeFrom, rangeTo, bipolar } }.
  Dimensions are keyed by nodeXFadeN (0-based): nodeXFade0..7  ==  Dim.Ctrl A..H  (switchControl 257..264).

  Sources can be: cc0..ccN | velocity | previousVelocity | pitchBend | speed | duration | aftertouch | aftertouchAlt | none.

  Usage:
    powershell -File controller-map.ps1 -Preset "…\STR Synchron Vln1 a14.vsynpreset"
    powershell -File controller-map.ps1 -Preset <…> -Json
#>
param(
  [Parameter(Mandatory)][string]$Preset,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"

$text = Get-PresetText -File $Preset
if ($text -notmatch '"paramControl"') {
  Write-Host "no paramControl block (root slots don't carry one; only full presets do)"
  return
}
$slice = Get-ObjectSlice -Text $text -Key 'paramControl'
$pc = $slice.text | ConvertFrom-Json

function DestLabel([string]$d) {
  if ($d -match '^nodeXFade(\d+)$') {
    $i = [int]$Matches[1]
    $letter = if ($i -ge 0 -and $i -lt 8) { [string][char](65 + $i) } else { '?' }
    return "{0}  (Dim.Ctrl {1}, switchControl {2})" -f $d, $letter, (257 + $i)
  }
  return $d
}

$rows = New-Object System.Collections.Generic.List[object]
if ($pc.mappings) {
  foreach ($p in $pc.mappings.PSObject.Properties) {
    $v = $p.Value
    $rows.Add([pscustomobject]@{
      destination = $p.Name
      label       = (DestLabel $p.Name)
      source      = "$($v.source)"
      curve       = "$($v.curve)"
      rangeFrom   = "$($v.rangeFrom)"
      rangeTo     = "$($v.rangeTo)"
      bipolar     = "$($v.bipolar)"
    })
  }
}
if ($Json) { @{ preset=$Preset; mappings=$rows } | ConvertTo-Json -Depth 5; return }
foreach ($r in $rows) {
  "{0,-14} -> {1,-12}  curve={2} range={3}..{4} bipolar={5}" -f $r.label, $r.source, $r.curve, $r.rangeFrom, $r.rangeTo, $r.bipolar
}
