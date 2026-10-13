# vsl-preset-generator-skill

An [OpenCode](https://opencode.ai) **skill** for working with Vienna Synchron Player presets:
read/decode `.vsynpreset` (zstd) and `.syvolume`, extract the real patch inventory, and
generate / clone instrument presets (e.g. build every string section from one template, or
assemble a custom articulation set such as *Legato + Long + Marcato + Rips* for a horn).

一个用于 **Vienna Synchron Player** 预设（root slot / `.vsynpreset`）的 OpenCode skill：
解析格式、提取真实 patch 名称库、把一个声部的预设克隆/换 patch 到其它声部，或按需求拼装预设。

> 说明：仓库中**不包含**从本机已授权库提取的数据库（`data/`）——它是可再生成的、且与本机环境相关。
> 用脚本一条命令即可重建（见下）。

## What it does

- **Decode** a `.vsynpreset` — it is just one **zstd frame** wrapping preset JSON (7-Zip can
  *decompress* zstd, not compress, so the tooling can also *write* presets with hand-built
  zstd raw-block frames).
- **Unpack** a `*_Patches*.syvolume` — it embeds a zstd frame whose payload is the instrument's
  complete patch tree (`patches → collection → product → instrument folder → articulation → patch file`).
- **Build a patch database (CSV)** from every installed library.
- **Clone / convert** a preset to other instruments by replacing the *content id / instrument
  folder / patch abbreviation* (plus fixing play ranges).
- **Build a preset from an explicit patch list**, reusing an existing preset as the shell.
- **Verify** that every `patchEntry` in a preset really exists in the library.

## Layout

```text
SKILL.md                       # the skill itself (methods, syntax, pitfalls, workflows)
scripts/
  build-vsl-patch-db.ps1       # extract / refresh the patch + factory-preset database (cached)
  generate-section-presets.ps1 # clone a template to other instruments (map JSON)
  build-preset-from-patches.ps1# assemble a preset from a patch list (spec JSON)
  verify-patch-paths.ps1       # check every patchEntry against the database
  query-patches.ps1            # query the database
  read-preset.ps1              # decompress a .vsynpreset (summary / full JSON)
  unpack-volume.ps1            # extract the patch/preset tree from a .syvolume
plugin/index.ts                # registers the scripts as OpenCode tools (namespace `vsl`)
examples/                      # map / spec JSON examples
references/                    # in-depth guide + user habits/preferences
data/                          # (not committed) generated database — rebuild with the script
```

## Requirements

- Windows + PowerShell (5.1 is fine)
- [7-Zip](https://www.7-zip.org/) at `C:\Program Files\7-Zip\7z.exe`
- VSL Synchron Player libraries installed locally (for the database / patches)

## Usage (scripts)

```powershell
# 1) build / refresh the database (full ~95s; incremental refresh a few seconds)
powershell -ExecutionPolicy Bypass -File scripts/build-vsl-patch-db.ps1 -LibraryRoot "D:\VSL Library"

# 2) find exact names
powershell -ExecutionPolicy Bypass -File scripts/query-patches.ps1 -Product "Horn 1" -Patch "Rip|Legato"

# 3) clone a template to several instruments (see examples/strings-pro-map.json)
powershell -ExecutionPolicy Bypass -File scripts/generate-section-presets.ps1 `
  -Template "…\STR Synchron Vln1 a14.vsynpreset" -MapFile examples/strings-pro-map.json -OutDir "…\Presets\Generated"

# 4) build a preset from a patch list (see examples/horn1.json)
powershell -ExecutionPolicy Bypass -File scripts/build-preset-from-patches.ps1 `
  -Shell "…\some.vsynpreset" -SpecFile examples/horn1.json -OutDir "…\Presets\Generated"

# 5) verify
powershell -ExecutionPolicy Bypass -File scripts/verify-patch-paths.ps1 `
  -Preset "…\Generated\Horn 1 - Legato Long Marcato Rips.vsynpreset" -Database data/vsl-patches.csv
```

## Usage (OpenCode tools)

`plugin/index.ts` registers a `vsl` namespace so an agent (and OpenChamber / Code Mode) can call
the scripts directly. Register the plugin directory in `opencode.json(c)`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["./skills/vsl-synchron-player/plugin"]
}
```

> The configured plugin path must be a **directory** (pointing directly at a `.ts` file is rejected).

Tools: `vsl_db_build` · `vsl_db_query` · `vsl_read_preset` · `vsl_unpack_volume`
· `vsl_generate_presets` · `vsl_build_preset` · `vsl_verify_patches`

## Notes

- `.vsynpreset` = a **zstd** frame around the preset JSON. Since no zstd *compressor* is assumed,
  generated presets use a valid zstd frame with **raw (uncompressed) blocks** — any zstd decoder
  reads them; if the player ever rejected one, emit a root-slot JSON and paste it instead.
- Patch names / folder names differ between libraries, and a section is not always a perfect mirror
  of another (e.g. Synchron Strings Pro double basses have no `…_LyV` "lyrical vibrato" patches).
  Always confirm against the extracted database.
- This repository contains only tooling and documentation, not sample/library content.

## License

Tooling and docs: use as you like. VSL and Vienna Symphonic Library are trademarks of their owner;
no library content is distributed here.
