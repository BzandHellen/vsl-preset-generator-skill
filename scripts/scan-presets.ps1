<#
  scan-presets.ps1  —  scan a folder (or list) of presets and report a summary + anomalies.

  Per preset: folder/dimension count, patch-slot count, the controller map (Dim.Ctrl sources),
  and anomaly hints:
    empty-slot    a slot with no patchEntry
    no-range      a patch slot without rangeFrom/rangeTo
    dup-patch     the same patchEntry used more than once
    token         a patch whose instrument abbreviation differs from the preset's majority
                  (only a hint — Tutti presets mix sections by design)

  Usage:
    powershell -File scan-presets.ps1 -Path "C:\...\Presets\Strings"
    powershell -File scan-presets.ps1 -Path <dir> -Json
#>
param(
  [Parameter(Mandatory)][string[]]$Path,
  [switch]$NoRecurse,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"
if ($Path.Count -eq 1 -and $Path[0] -match ',') { $Path = $Path[0] -split '\s*,\s*' }

$files = New-Object System.Collections.Generic.List[object]
foreach ($p in $Path) {
  if (Test-Path -LiteralPath $p -PathType Container) {
    Get-ChildItem -LiteralPath $p -File -Recurse:(-not $NoRecurse) -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -in '.vsynpreset','.json' } | ForEach-Object { $files.Add($_) }
  } else {
    Get-Item -LiteralPath $p -ErrorAction SilentlyContinue | ForEach-Object { $files.Add($_) }
  }
}
if ($files.Count -eq 0) { throw "no presets matched" }

$results = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
  $name = $f.BaseName; $folders = 0; $slots = 0; $dims = @(); $patches = @(); $cm = @(); $errors = @()
  try {
    $text = Get-PresetText -File $f.FullName
    $root = Get-RootNode -Text $text
    if ($text -match '"paramControl"') {
      $pc = (Get-ObjectSlice -Text $text -Key 'paramControl').text | ConvertFrom-Json
      if ($pc.mappings) { foreach ($q in $pc.mappings.PSObject.Properties) {
        $lbl = $q.Name; if ($q.Name -match '^nodeXFade(\d+)$') { $lbl = "Dim.Ctrl " + [char](65+[int]$Matches[1]) }
        $cm += [pscustomobject]@{ dest=$q.Name; label=$lbl; source="$($q.Value.source)" } } }
    }
    $dl = New-Object System.Collections.Generic.List[object]
    $pl = New-Object System.Collections.Generic.List[object]
    function Walk($n, [string]$path) {
      if ($n.PSObject.Properties.Name -contains 'nodes') {
        $dl.Add([pscustomobject]@{ title=$n.title; switchControl=$n.switchControl; children=@($n.nodes).Count; parallel=$n.parallel })
        foreach ($c in $n.nodes) { Walk $c "$path/$($n.title)" }
      } else {
        $pl.Add([pscustomobject]@{ title=$n.title; path=$path; patchName="$($n.patchName)"; entry="$($n.patchEntry)"; rangeFrom=$n.rangeFrom })
      }
    }
    Walk $root ''
    $dims = $dl; $patches = $pl
    $folders = $dims.Count; $slots = $patches.Count
  } catch { $errors += $_.Exception.Message }

  # dimension summary "D=cc58" style
  $dimSummary = @()
  foreach ($d in $dims) {
    if ($d.switchControl -and $d.switchControl -ne 0) {
      $i = [int]$d.switchControl - 257
      $slot = if ($i -ge 0 -and $i -lt 8) { [string][char](65+$i) } else { '?' }
      $src = ($cm | Where-Object { $_.dest -eq "nodeXFade$i" } | Select-Object -First 1).source
      $dimSummary += ("{0}={1}" -f $slot, $(if ($src) { $src } else { '?' }))
    }
  }

  # anomalies
  $an = New-Object System.Collections.Generic.List[string]
  $empties = @($patches | Where-Object { $_.title -ne '' -and $_.title -ne 'Extended' -and (-not $_.entry -or $_.entry -eq '') })
  if ($empties.Count) { $an.Add("empty-slot x$($empties.Count): " + (($empties | ForEach-Object { $_.title }) -join ', ')) }
  $noRange = @($patches | Where-Object { $_.entry -and $null -eq $_.rangeFrom })
  if ($noRange.Count) { $an.Add("no-range x$($noRange.Count): " + (($noRange | ForEach-Object { $_.title }) -join ', ')) }
  $dups = $patches | Where-Object { $_.entry } | Group-Object entry | Where-Object { $_.Count -gt 1 }
  if ($dups) { $an.Add("dup-patch x$($dups.Count): " + (($dups | ForEach-Object { ($_.Name -split '/')[-1] }) -join ', ')) }
  $tokens = @{}
  foreach ($p in $patches) {
    if ($p.patchName -match '(?i)\b([A-Za-z]{2,4}-?\d{1,2})\b') { $tk = $Matches[1]; if ($tokens.ContainsKey($tk)) { $tokens[$tk]++ } else { $tokens[$tk] = 1 } }
  }
  $tokStr = ($tokens.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ', '
  if ($tokens.Count -gt 1) {
    $maj = ($tokens.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
    $odd = @($patches | Where-Object { $_.patchName -match '(?i)\b([A-Za-z]{2,4}-?\d{1,2})\b' -and $Matches[1] -ne $maj })
    if ($odd.Count) { $an.Add("token(minority!= $maj) x$($odd.Count): " + (($odd | Select-Object -First 8 | ForEach-Object { $_.title }) -join ', ') + $(if ($odd.Count -gt 8) {' …'} else {''})) }
  }

  $results.Add([pscustomobject]@{
    name=$name; file=$f.Name; folders=$folders; patchSlots=$slots
    dims=($dimSummary -join ' '); tokens=$tokStr
    controllerMap=($cm | ForEach-Object { "$($_.label)=$($_.source)" }) -join ' '
    anomalies=$an; errors=$errors
  })
}

if ($Json) { @{ count=$results.Count; presets=$results } | ConvertTo-Json -Depth 6; return }
foreach ($r in $results) {
  "{0}" -f $r.name
  "  folders={0} patchSlots={1}  dims: {2}" -f $r.folders, $r.patchSlots, $r.dims
  if ($r.tokens) { "  tokens: {0}" -f $r.tokens }
  if ($r.errors.Count) { "  ERROR: {0}" -f ($r.errors -join '; ') }
  if ($r.anomalies.Count) { foreach ($a in $r.anomalies) { "  ! {0}" -f $a } } else { "  ok" }
}
"`nscanned {0} preset(s)" -f $results.Count
