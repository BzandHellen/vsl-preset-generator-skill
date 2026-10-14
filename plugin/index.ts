/**
 * VSL Synchron Player tools — bundled with the `vsl-synchron-player` skill.
 *
 * Registers shell-backed tools so the agent (and OpenChamber / Code Mode) can call the
 * skill's PowerShell scripts directly instead of shelling out by hand.
 *
 * Load it from a global or project opencode config:
 *   { "plugins": ["./skills/vsl-synchron-player/plugin/index.ts"] }
 */
import { Plugin } from "@opencode/plugin"
import { execFile } from "node:child_process"
import { existsSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { fileURLToPath } from "node:url"

// Locate this skill's own directory: prefer the plugin's own location (works directly or via the
// junction in the harness skills dir), otherwise fall back to the known paths.
const SKILL = (() => {
  const cands: string[] = []
  try { cands.push(fileURLToPath(new URL("..", import.meta.url)).replace(/[\\/]+$/, "")) } catch {}
  cands.push("C:\\Agent Program Files\\Skills\\vsl-synchron-player")
  cands.push("C:\\Users\\Administrator\\.config\\opencode\\skills\\vsl-synchron-player")
  for (const c of cands) if (existsSync(c + "\\scripts\\build-vsl-patch-db.ps1")) return c
  return cands[0]
})()
const SCRIPTS = SKILL + "\\scripts\\"
const DATA = SKILL + "\\data"
const DB = DATA + "\\vsl-patches.csv"

const text = (s: unknown) => ({ content: String(s ?? "") })

function ps(scriptFile: string, args: string[], timeoutMs = 900_000, cap = 60_000): Promise<string> {
  return new Promise((resolve) => {
    execFile(
      "powershell.exe",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", SCRIPTS + scriptFile, ...args],
      { maxBuffer: 256 * 1024 * 1024, timeout: timeoutMs, windowsHide: true },
      (err, stdout, stderr) => {
        let out = String(stdout ?? "")
        const errs = String(stderr ?? "")
        let tail = ""
        if (err) tail += `\n[exit] ${err.message}`
        if (errs.trim()) tail += `\n[stderr]\n${errs.trim()}`
        if (out.length > cap) out = `…[${out.length - cap} chars trimmed]…\n` + out.slice(-cap)
        resolve(out + tail)
      },
    )
  })
}
const arg = (k: string, v: unknown) => [`-${k}`, String(v)]

const SKILL_DIR = { type: "string" as const, description: "Absolute path (defaults to the skill's own data/generated folders)" }

export default Plugin.define({
  id: "vsl-synchron-player.tools",
  async setup(ctx) {
    await ctx.tool.transform((editor) => {
      editor.namespace({ name: "vsl", description: "Vienna Synchron Player patch database and preset tools" })

      editor.add({
        name: "db_build",
        description:
          "Extract / refresh the VSL patch + factory-preset database from every installed *_Patches*.syvolume. " +
          "Full rebuild ~95s; incremental refresh a few seconds (unchanged volumes are skipped by size+mtime cache).",
        input: {
          type: "object",
          properties: {
            libraryRoot: { type: "string", description: "Library root, e.g. D:\\VSL Library" },
            force: { type: "boolean", description: "Ignore cache and re-extract everything" },
          },
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { libraryRoot?: string; force?: boolean }
          const args: string[] = []
          if (i.libraryRoot) args.push(...arg("LibraryRoot", i.libraryRoot))
          if (i.force) args.push("-Force")
          return text(await ps("build-vsl-patch-db.ps1", args))
        },
      })

      editor.add({
        name: "db_query",
        description:
          "Query the extracted patch database (data/vsl-patches.csv). Filters are substring matches except `patch` (regex). " +
          "Use it to find the exact content id / instrument folder / patch file name before writing a map or spec.",
        input: {
          type: "object",
          properties: {
            collection: { type: "string", description: "e.g. '02 Synchron Strings Pro', '21 Synchron Brass'" },
            product: { type: "string", description: "e.g. '11 Horn 1'" },
            instrument: { type: "string", description: "e.g. '02 Legato'" },
            articulation: { type: "string" },
            patch: { type: "string", description: "regex against the patch file name, e.g. 'Rip|Legato'" },
            contentId: { type: "string", description: "e.g. 'stringspro.basses'" },
            limit: { type: "number", description: "default 100" },
          },
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as Record<string, string | number | undefined>
          const args: string[] = [...arg("Database", DB)]
          for (const k of ["collection", "product", "instrument", "articulation", "patch", "contentId"]) {
            const v = i[k]
            if (v !== undefined && v !== "") args.push(...arg(k[0].toUpperCase() + k.slice(1), v))
          }
          if (i.limit) args.push(...arg("Limit", i.limit))
          return text(await ps("query-patches.ps1", args, 120_000))
        },
      })

      editor.add({
        name: "read_preset",
        description:
          "Decompress a .vsynpreset (zstd) and return it. mode=summary (default) lists slots (title/patchName/range); " +
          "mode=full returns the whole preset JSON.",
        input: {
          type: "object",
          properties: {
            path: { type: "string", description: "Absolute path to a .vsynpreset or .json" },
            mode: { type: "string", enum: ["summary", "full"] },
          },
          required: ["path"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { path: string; mode?: string }
          return text(await ps("read-preset.ps1", [...arg("Preset", i.path), ...arg("Mode", i.mode ?? "summary")]))
        },
      })

      editor.add({
        name: "unpack_volume",
        description:
          "Extract the patch tree (or factory-preset tree) embedded in a VSL *.syvolume. " +
          "Use it to confirm the real instrument-folder / patch names for any library.",
        input: {
          type: "object",
          properties: {
            volume: { type: "string", description: "Absolute path to a *.syvolume" },
            mode: { type: "string", enum: ["patches", "presets", "raw"] },
            limit: { type: "number", description: "0 = all" },
          },
          required: ["volume"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { volume: string; mode?: string; limit?: number }
          const args = [...arg("Volume", i.volume), ...arg("Mode", i.mode ?? "patches")]
          if (i.limit) args.push(...arg("Limit", i.limit))
          return text(await ps("unpack-volume.ps1", args, 180_000))
        },
      })

      editor.add({
        name: "generate_presets",
        description:
          "Clone a preset/root-slot to other instruments via text replacement (map JSON) and write importable .vsynpreset files.",
        input: {
          type: "object",
          properties: {
            template: { type: "string", description: "Template .vsynpreset or .json" },
            mapFile: { type: "string", description: "Map JSON (see examples/strings-pro-map.json)" },
            outDir: { type: "string" },
          },
          required: ["template", "mapFile", "outDir"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { template: string; mapFile: string; outDir: string }
          return text(await ps("generate-section-presets.ps1", [...arg("Template", i.template), ...arg("MapFile", i.mapFile), ...arg("OutDir", i.outDir)]))
        },
      })

      editor.add({
        name: "build_preset",
        description:
          "Build a preset from an explicit patch list (spec JSON) reusing an existing preset as the shell " +
          "(see examples/horn1.json). Good for arbitrary technique combinations.",
        input: {
          type: "object",
          properties: {
            shell: { type: "string", description: "Existing .vsynpreset used for schema + mixer" },
            specFile: { type: "string", description: "Spec JSON with name/currentPreset/patches[]" },
            outDir: { type: "string" },
          },
          required: ["shell", "specFile", "outDir"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { shell: string; specFile: string; outDir: string }
          return text(await ps("build-preset-from-patches.ps1", [...arg("Shell", i.shell), ...arg("SpecFile", i.specFile), ...arg("OutDir", i.outDir)]))
        },
      })

      editor.add({
        name: "verify_patches",
        description: "Check that every patchEntry in a preset exists in the library, using the extracted database.",
        input: {
          type: "object",
          properties: {
            preset: { type: "string" },
            database: { type: "string", description: "defaults to the skill database" },
          },
          required: ["preset"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { preset: string; database?: string }
          return text(await ps("verify-patch-paths.ps1", [...arg("Preset", i.preset), ...arg("Database", i.database ?? DB)], 180_000))
        },
      })

      editor.add({
        name: "export_preset",
        description:
          "Decompress .vsynpreset(s) to plain .json for analysis. Accepts a file, several files, or a folder. " +
          "Writes into a Generated/generated folder only (safety).",
        input: {
          type: "object",
          properties: {
            preset: { type: "array", items: { type: "string" }, description: "files and/or folders" },
            outDir: { type: "string", description: "must be under a Generated/generated folder" },
            pretty: { type: "boolean" },
            force: { type: "boolean", description: "allow overwriting existing output files" },
            allowOutsideGenerated: { type: "boolean" },
          },
          required: ["preset", "outDir"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { preset: string[]; outDir: string; pretty?: boolean; force?: boolean; allowOutsideGenerated?: boolean }
          const args = [...arg("Preset", i.preset.join(",")), ...arg("OutDir", i.outDir)]
          if (i.pretty) args.push("-Pretty")
          if (i.force) args.push("-Force")
          if (i.allowOutsideGenerated) args.push("-AllowOutsideGenerated")
          return text(await ps("export-preset.ps1", args, 180_000))
        },
      })

      editor.add({
        name: "outline_preset",
        description:
          "Print a preset's full dimension tree: folder/patch nodes, switchControl (+Dim.Ctrl A–H slot), parallel, " +
          "child counts, nodeXFades as CC ranges, per-slot patchName / range / velXFadeMode / legatoMode, " +
          "and the controller map (paramControl.mappings).",
        input: {
          type: "object",
          properties: {
            preset: { type: "string" },
            json: { type: "boolean" },
            includeEntry: { type: "boolean" },
          },
          required: ["preset"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { preset: string; json?: boolean; includeEntry?: boolean }
          const args = [...arg("Preset", i.preset)]
          if (i.json) args.push("-Json")
          if (i.includeEntry) args.push("-IncludeEntry")
          return text(await ps("outline-preset.ps1", args, 180_000, 200_000))
        },
      })

      editor.add({
        name: "compare_presets",
        description:
          "Compare presets node by node (position-based) and report differences. Instrument abbreviations are " +
          "normalized to '@' by default, so cross-section mistakes stand out.",
        input: {
          type: "object",
          properties: {
            preset: { type: "array", items: { type: "string" }, description: "2 or more presets" },
            json: { type: "boolean" },
            noNormalize: { type: "boolean" },
            tokens: { type: "array", items: { type: "string" }, description: "extra/replacement normalize tokens" },
          },
          required: ["preset"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { preset: string[]; json?: boolean; noNormalize?: boolean; tokens?: string[] }
          const args = [...arg("Preset", i.preset.join(","))]
          if (i.json) args.push("-Json")
          if (i.noNormalize) args.push("-NoNormalize")
          if (i.tokens) args.push(...arg("Tokens", i.tokens.join(",")))
          return text(await ps("compare-presets.ps1", args, 180_000, 200_000))
        },
      })

      editor.add({
        name: "edit_preset",
        description:
          "Edit a preset and write a NEW file. Ops: setField / setPatch / setXfades (e.g. 8-value stepping) / " +
          "removeSlot / setController (midi map: {dimCtrl:'A'..'H' or destination:'nodeXFade0', source:'cc21'|'velocity'|…, range:[0,100]}). " +
          "Output must be under a Generated/generated folder; existing files are never overwritten unless force=true.",
        input: {
          type: "object",
          properties: {
            preset: { type: "string", description: "source preset (read-only)" },
            edits: { type: "string", description: "JSON string or path to a JSON file with ops" },
            outDir: { type: "string", description: "must be under a Generated/generated folder" },
            name: { type: "string", description: "output base name (no extension)" },
            force: { type: "boolean" },
            allowOutsideGenerated: { type: "boolean" },
          },
          required: ["preset", "edits", "outDir"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { preset: string; edits: string; outDir: string; name?: string; force?: boolean; allowOutsideGenerated?: boolean }
          // pass complex JSON via a temp file (safer quoting than an inline argument)
          let editsArg = i.edits
          if (/^\s*[\[{]/.test(editsArg)) {
            const p = join(tmpdir(), `vsl-edits-${Date.now()}-${Math.random().toString(36).slice(2)}.json`)
            writeFileSync(p, editsArg, "utf8")
            editsArg = p
          }
          const args = [...arg("Preset", i.preset), ...arg("Edits", editsArg), ...arg("OutDir", i.outDir)]
          if (i.name) args.push(...arg("Name", i.name))
          if (i.force) args.push("-Force")
          if (i.allowOutsideGenerated) args.push("-AllowOutsideGenerated")
          return text(await ps("edit-preset.ps1", args, 180_000))
        },
      })

      editor.add({
        name: "controller_map",
        description:
          "Read a preset's MIDI controller map (paramControl.mappings): Dim.Ctrl A–H (nodeXFade0..7) and automation " +
          "destinations → source. Sources: ccN | velocity | previousVelocity | pitchBend | speed | duration | " +
          "aftertouch | aftertouchAlt | none.",
        input: {
          type: "object",
          properties: { preset: { type: "string" }, json: { type: "boolean" } },
          required: ["preset"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { preset: string; json?: boolean }
          const args = [...arg("Preset", i.preset)]
          if (i.json) args.push("-Json")
          return text(await ps("controller-map.ps1", args, 120_000))
        },
      })
      editor.add({
        name: "scan_presets",
        description:
          "Scan a folder (or list) of presets and report a summary + anomaly hints: folder/patch-slot counts, Dim.Ctrl " +
          "sources per dimension, instrument tokens, empty slots, missing ranges, duplicated patches, minority-token " +
          "slots (cross-section mistakes).",
        input: {
          type: "object",
          properties: {
            path: { type: "array", items: { type: "string" }, description: "folders and/or files" },
            noRecurse: { type: "boolean" },
            json: { type: "boolean" },
          },
          required: ["path"],
          additionalProperties: false,
        },
        options: { namespace: "vsl", codemode: true },
        execute: async (input) => {
          const i = input as { path: string[]; noRecurse?: boolean; json?: boolean }
          const args = [...arg("Path", i.path.join(","))]
          if (i.noRecurse) args.push("-NoRecurse")
          if (i.json) args.push("-Json")
          return text(await ps("scan-presets.ps1", args, 300_000, 200_000))
        },
      })
    })
  },
})
