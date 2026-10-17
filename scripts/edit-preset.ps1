<#
  edit-preset.ps1  —  edit a preset / root slot and write a NEW file.

  Edits are a JSON array of ops, each with "path" = list of node titles from the root
  ([] = the root node). Ops:

    { "op":"setField",   "path":["NV-Vib Leg"], "field":"switchControl", "value":257 }
    { "op":"setPatch",   "path":["Harmonics","Harmonics"], "patchEntry":"vol://…", "patchName":"…" }
    { "op":"setXfades",  "path":[""], "steps":8 }                          // 每 8 值一档（末档到 127）
    { "op":"setXfades",  "path":["Trills"], "explicit":[[0,15],[16,31],[32,127]] }   // CC 区间
    { "op":"removeSlot", "path":["Pizzicato"], "slot":"Pizzicato" }
    { "op":"setController","dimCtrl":"C","source":"cc74","range":[0,100] } // 控制器映射 (paramControl)

  Section-aware fix ops (need a section map; built-in "stringspro" or inline "sections"):

    { "op":"mapSection",     "path":["Sustain","Soft Release","Vln1"], "to":"Vla" }
    { "op":"fillSlots",      "path":["Sustain","Soft Release"], "from":"Vln1",
                             "to":["Vln2","Vla","Vc","DB"], "overwrite":false }
    { "op":"fixCrossSection","path":["Sustain","Soft Release"] }   // 把"指错声部"的槽改回本声部

  -Report prints the planned changes and writes nothing.

  Safety: output must be under a "Generated"/"generated" folder (else -AllowOutsideGenerated),
  and an existing file is never overwritten unless -Force.

  Usage:
    powershell -File edit-preset.ps1 -Preset "…\x.vsynpreset" -Edits ".\edits.json" `
      -OutDir "…\Presets\Generated" [-Report] [-Name "x (fixed)"]
#>
param(
  [Parameter(Mandatory)][string]$Preset,
  [Parameter(Mandatory)][string]$Edits,
  [Parameter(Mandatory)][string]$OutDir,
  [string]$Name,
  [switch]$Force,
  [switch]$Report,
  [switch]$AllowOutsideGenerated
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\vsl-common.ps1"

# ---- built-in section maps ---------------------------------------------------
$MAPS = @{
  stringspro = @(
    @{ name='Vln1'; id='violins1'; folder='01 SY 1st Violins-14';  pro='01 SY 1st Violins-14 Pro'; abbr='VI-14' },
    @{ name='Vln2'; id='violins2'; folder='02 SY 2nd Violins-10';  pro='02 SY 2nd Violins-10 Pro'; abbr='VI-10' },
    @{ name='Vla';  id='violas';   folder='03 SY Violas-8';        pro='03 SY Violas-8 Pro';       abbr='VA-8'  },
    @{ name='Vc';   id='cellos';   folder='04 SY Cellos-8';        pro='04 SY Violoncellos-8 Pro'; abbr='VC-8'  },
    @{ name='DB';   id='basses';   folder='05 SY Double basses-6'; pro='05 SY Double basses-6 Pro';abbr='DB-6'  }
  )
}
function Get-Map($op) {
  if ($op.sections) { return @($op.sections) }
  $mn = if ($op.map) { [string]$op.map } else { 'stringspro' }
  if ($MAPS.ContainsKey($mn)) { return $MAPS[$mn] }
  throw "unknown section map '$mn'"
}
function Convert-Section([string]$entry,[string]$patchName,[string]$fromName,[string]$toName,$map) {
  $f = $map | Where-Object { $_.name -eq $fromName } | Select-Object -First 1
  $t = $map | Where-Object { $_.name -eq $toName }   | Select-Object -First 1
  if (-not $f -or -not $t) { throw "section map: unknown '$fromName' -> '$toName'" }
  $e = $entry
  if ($f.pro) { $e = $e.Replace([string]$f.pro, [string]$t.pro) }   # "... Pro" first
  $e = $e.Replace([string]$f.folder, [string]$t.folder).Replace([string]$f.id, [string]$t.id).Replace([string]$f.abbr, [string]$t.abbr)
  $p = if ($patchName) { $patchName.Replace([string]$f.abbr, [string]$t.abbr) } else { $patchName }
  return @{ entry=$e; patchName=$p }
}
function Section-OfPatch([string]$entry,$map) {
  foreach ($s in $map) { if ($entry -match [regex]::Escape([string]$s.id)) { return $s } }
  return $null
}

$text = Get-PresetText -File $Preset
$slice = Get-TreeSlice -Text $text
$root = $slice.text | ConvertFrom-Json
$ops = if (Test-Path -LiteralPath $Edits) { Get-Content -LiteralPath $Edits -Raw | ConvertFrom-Json } else { $Edits | ConvertFrom-Json }
$ops = @($ops)
$CHANGES = New-Object System.Collections.Generic.List[string]

function Navigate($node,[string[]]$titles) {
  $cur = $node
  foreach ($w in @($titles)) {
    if ($w -eq '') { continue }
    $ok = $false
    foreach ($c in @($cur.nodes)) { if ($c.title -eq $w) { $cur = $c; $ok = $true; break } }
    if (-not $ok) { return $null }
  }
  return $cur
}
function Get-Path([string[]]$titles) {
  $n = Navigate $root $titles
  if (-not $n) { throw "node not found: '$($titles -join '/')'" }
  return $n
}
function Set-Prop($obj,[string]$name,$value) {
  if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value } else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Replace-Child($folder,[string]$title,$newNode) {
  $arr = @($folder.nodes)
  for ($i=0; $i -lt $arr.Count; $i++) { if ($arr[$i].title -eq $title) { $arr[$i] = $newNode } }
  $folder.nodes = $arr
}
function Sync-Children($folder,[string[]]$pathTitles,$presets,$overwrite) {
  foreach ($child in @($folder.nodes)) {
    $srcPath = $presets.$($child.title)
    if (-not $srcPath) { continue }
    if ($child.patchEntry -and -not $overwrite) { $CHANGES.Add("sync: skip $($child.title) (has patch)"); continue }
    $srcRoot = Get-RootNode -Text (Get-PresetText -File $srcPath)
    $sn = Navigate $srcRoot $pathTitles
    if (-not $sn -or -not $sn.patchEntry) { $CHANGES.Add("sync: $($child.title): path '$($pathTitles -join '/')' not found in $([IO.Path]::GetFileName($srcPath))"); continue }
    $CHANGES.Add("sync: $($pathTitles -join '/') / $($child.title): $($child.patchName)  ->  $($sn.patchName)")
    $clone = $sn | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $clone.title = $child.title
    Replace-Child $folder $child.title $clone
  }
}

# ---- tree ops ---------------------------------------------------------------
foreach ($op in @($ops | Where-Object { $_.op -ne 'setController' })) {
  switch ($op.op) {
    'setField' {
      $n = Get-Path $op.path
      $field = [string]$op.field
      if ($field -match '\.') {
        $parts = $field -split '\.'
        $obj = $n
        for ($k=0; $k -lt $parts.Count-1; $k++) { $obj = $obj.$($parts[$k]) }
        Set-Prop $obj $parts[-1] $op.value
      } else {
        Set-Prop $n $field $op.value
      }
      $CHANGES.Add("setField $($op.path -join '/') . $field = $($op.value)")
    }
    'setPatch' {
      $n = Get-Path $op.path
      $CHANGES.Add("setPatch $($op.path -join '/'): -> $($op.patchName)")
      $n.patchEntry = $op.patchEntry
      if ($op.patchName) { $n.patchName = $op.patchName }
    }
    'setXfades' {
      $n = Get-Path $op.path
      $kids = @($n.nodes).Count
      $arr = @()
      if ($op.explicit) {
        foreach ($pair in $op.explicit) {
          $q = @($pair)
          if ($q.Count -ge 4) {
            $arr += [pscustomobject]@{ fadeInStart=([double]$q[0]/127); fadeInEnd=([double]$q[1]/127); fadeOutStart=([double]$q[2]/127); fadeOutEnd=([double]$q[3]/127) }
          } else {
            $arr += [pscustomobject]@{ fadeInStart=([double]$q[0]/127); fadeInEnd=([double]$q[0]/127); fadeOutStart=([double]$q[1]/127); fadeOutEnd=([double]$q[1]/127) }
          }
        }
      } else {
        # switch mode: put the boundary (= midpoint of the shared fade interval) on multiples of N
        #   slot i: in = interval(b_i), out = interval(b_i+1);  interval(b) = [b-1, b+1]  (b = 0/127 -> zero width)
        #   bounds = steps*i - 1  (每 N 个值一档：边界 = N-1, 2N-1, ... 例 steps:8 -> 7/15/23/31，末档才是满 8 个)
        $steps = if ($op.steps) { [int]$op.steps } else { 8 }
        $bounds = @()
        for ($i=0; $i -le $kids; $i++) { $bounds += $(if ($i -eq 0) {0} elseif ($i -ge $kids) {127} else {($steps * $i) - 1}) }
        for ($i=0; $i -lt $kids; $i++) {
          $bi = $bounds[$i]; $bn = $bounds[$i+1]
          if ($bi -le 0) { $a0=0; $a1=0 } elseif ($bi -ge 127) { $a0=127; $a1=127 } else { $a0=[Math]::Max(0,$bi-1); $a1=[Math]::Min(127,$bi+1) }
          if ($bn -le 0) { $c0=0; $c1=0 } elseif ($bn -ge 127) { $c0=127; $c1=127 } else { $c0=[Math]::Max(0,$bn-1); $c1=[Math]::Min(127,$bn+1) }
          $arr += [pscustomobject]@{ fadeInStart=($a0/127.0); fadeInEnd=($a1/127.0); fadeOutStart=($c0/127.0); fadeOutEnd=($c1/127.0) }
        }
      }
      $n.nodeXFades = $arr
      $mids = @()
      for ($t=0; $t -lt ($arr.Count-1); $t++) { $mids += [int][math]::Round((([double]$arr[$t].fadeOutStart + [double]$arr[$t].fadeOutEnd)/2)*127) }
      $bands = @(); $lo = 0
      for ($t=0; $t -lt $mids.Count; $t++) { $bands += "$lo-$($mids[$t]-1)"; $lo = $mids[$t] }
      $bands += "$lo-127"
      $CHANGES.Add("setXfades $($op.path -join '/'): $kids slot(s) -> bands " + ($bands -join ', '))
    }
    'removeSlot' {
      $n = Get-Path $op.path
      $kids = @($n.nodes); $idx = -1
      for ($i=0; $i -lt $kids.Count; $i++) { if ($kids[$i].title -eq $op.slot) { $idx = $i; break } }
      if ($idx -lt 0) { throw "slot not found: $($op.slot)" }
      $n.nodes = @($kids | Where-Object { $_.title -ne $op.slot })
      if ($n.nodeXFades) { $xf = @($n.nodeXFades); $n.nodeXFades = @($xf[0..($idx-1)] + $xf[($idx+1)..($xf.Count-1)]) }
      $CHANGES.Add("removeSlot $($op.path -join '/'): $($op.slot)")
    }
    'mapSection' {
      $map = Get-Map $op
      $n = Get-Path $op.path
      $from = $op.from
      if (-not $from) { $s = Section-OfPatch $n.patchEntry $map; if (-not $s) { throw "cannot detect source section for 'mapSection'" }; $from = $s.name }
      $conv = Convert-Section $n.patchEntry $n.patchName $from $op.to $map
      $CHANGES.Add("mapSection $($op.path -join '/'): $($n.patchName) -> $($conv.patchName)")
      $n.patchEntry = $conv.entry; $n.patchName = $conv.patchName
    }
    'fillSlots' {
      $map = Get-Map $op
      $folder = Get-Path $op.path
      $tmpl = @($folder.nodes) | Where-Object { $_.title -eq $op.from } | Select-Object -First 1
      if (-not $tmpl) { throw "fillSlots: template child '$($op.from)' not found in $($op.path -join '/')" }
      if (-not $tmpl.patchEntry) { throw "fillSlots: template child '$($op.from)' has no patch" }
      foreach ($tname in @($op.to)) {
        $tgt = @($folder.nodes) | Where-Object { $_.title -eq $tname } | Select-Object -First 1
        if (-not $tgt) { $CHANGES.Add("fillSlots: skip '$tname' (no such child)"); continue }
        if ($tgt.patchEntry -and -not $op.overwrite) { $CHANGES.Add("fillSlots: skip '$tname' (already has a patch)"); continue }
        $conv = Convert-Section $tmpl.patchEntry $tmpl.patchName $op.from $tname $map
        $clone = $tmpl | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $clone.title = $tgt.title
        $clone.patchEntry = $conv.entry
        $clone.patchName = $conv.patchName
        Replace-Child $folder $tname $clone
        $CHANGES.Add("fillSlots: $tname <- $($conv.patchName)")
      }
    }
    'syncFromPresets' {
      # align the section children of a folder with each section's own preset at the same node path
      $folder = Get-Path $op.path
      Sync-Children $folder $op.path $op.presets $op.overwrite
    }
    'syncAllSections' {
      # walk the whole tree; every folder whose children include >=2 known sections gets synced
      $sections = @($op.presets.PSObject.Properties.Name)
      $walk = $null
      $walk = {
        param($node,[string[]]$tp)
        if ($node.PSObject.Properties.Name -notcontains 'nodes') { return }
        $titles = @($node.nodes | ForEach-Object { $_.title })
        $hit = @($sections | Where-Object { $titles -contains $_ })
        if ($hit.Count -ge 2) { Sync-Children $node $tp $op.presets $op.overwrite }
        foreach ($c in @($node.nodes)) { & $walk $c ($tp + $c.title) }
      }
      & $walk $root @()
    }
    'fixCrossSection' {
      $map = Get-Map $op
      $folder = Get-Path $op.path
      foreach ($child in @($folder.nodes)) {
        $sec = $map | Where-Object { $_.name -eq $child.title } | Select-Object -First 1
        if (-not $sec -or -not $child.patchEntry) { continue }
        $cur = Section-OfPatch $child.patchEntry $map
        if (-not $cur) { $CHANGES.Add("fixCrossSection: '$($child.title)' not in map — skipped"); continue }
        if ($cur.name -eq $sec.name) { continue }
        $conv = Convert-Section $child.patchEntry $child.patchName $cur.name $sec.name $map
        $CHANGES.Add("fixCrossSection: $($child.title): $($child.patchName)  ->  $($conv.patchName)")
        $child.patchEntry = $conv.entry; $child.patchName = $conv.patchName
      }
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
    if ($op.source) { Set-Prop $entry 'source' $op.source }
    if ($null -ne $op.bipolar) { Set-Prop $entry 'bipolar' $op.bipolar }
    if ($null -ne $op.curve) { Set-Prop $entry 'curve' $op.curve }
    if ($op.range) { Set-Prop $entry 'rangeFrom' ([int]$op.range[0]); Set-Prop $entry 'rangeTo' ([int]$op.range[1]) }
    $CHANGES.Add("setController ${dest}: source=$($op.source)")
  }
  $newText = Set-TreeSlice -Text $newText -Slice $pcSlice -NewObjectText ($pc | ConvertTo-Json -Depth 100 -Compress)
}

if ($CHANGES.Count) { $CHANGES | ForEach-Object { "  - $_" } } else { "  (no changes)" }
if ($Report) { "REPORT ONLY — nothing written."; return }

$out = Assert-GeneratedDir -OutDir $OutDir -AllowOutsideGenerated:$AllowOutsideGenerated
New-Item -ItemType Directory -Force $out | Out-Null
if (-not $Name) { $Name = (Split-Path -LeafBase $Preset) + " (edited)" }
$target = Join-Path $out ($Name + ".vsynpreset")
Assert-NoOverwrite -Path $target -Force:$Force
Write-ZstdRaw -Data ([Text.Encoding]::UTF8.GetBytes($newText)) -Path $target
Write-Host ("wrote {0}  ({1} bytes, {2} ops)" -f (Split-Path $target -Leaf), (Get-Item $target).Length, $ops.Count)
