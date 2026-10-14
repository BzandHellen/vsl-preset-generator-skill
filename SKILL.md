---
name: VSL Synchron Player 换 Patch / 预设克隆
description: >-
  处理 Vienna Synchron Player 的 root slot / preset：解析 .vsynpreset（zstd）与 .syvolume，
  提取真实 patch 名称目录（CSV 数据库），把某个声部的预设克隆/换 patch 到其它声部（含音域与
  低音缺 LyV 等差异），并生成可直接导入的 .vsynpreset。当用户提到 VSL、Synchron Player、
  root slot、vsynpatch、vsynpreset、syvolume、换 patch、克隆预设、Strings Pro/Elite/Brass/
  Woodwinds 等时使用。
---

# VSL Synchron Player —— 换 Patch / 预设克隆

本机环境：库在 `D:\VSL Library`，玩家数据在 `C:\ProgramData\VSL\Vienna Synchron Player`，
用户预设在 `C:\Users\Administrator\Documents\VSL\Vienna Synchron Player\Presets`。

**本 skill 目录 = 这份文件所在目录**。它存放在本地 skill 仓库
`C:\Agent Program Files\Skills\vsl-synchron-player`，并**软链（junction）**到 harness 目录
`C:\Users\Administrator\.config\opencode\skills\vsl-synchron-player` 供 OpenCode 使用。
相对路径都相对它：`scripts/`（脚本）、`data/`（数据库）、`references/`（文档）、`examples/`（示例）、`plugin/`（工具插件）。

### 已注册的工具（OpenChamber / Code Mode 可直接调用）
`plugin/index.ts` 把下面的 shell 脚本注册成 OpenCode 工具（`vsl` 命名空间，codemode 可用）：

| 工具 | 作用 |
|---|---|
| `vsl_db_build` | 提取/刷新 patch+preset 数据库（增量刷新几秒） |
| `vsl_db_query` | 查数据库找精确名字（collection/product/instrument/patch regex） |
| `vsl_read_preset` | 解压 `.vsynpreset` 返回 JSON（summary/full） |
| `vsl_unpack_volume` | 从 `.syvolume` 刨出 patch/preset 树 |
| `vsl_generate_presets` | 用 map.json 批量克隆/换 patch |
| `vsl_build_preset` | 用 patch 清单 JSON 拼预设 |
| `vsl_verify_patches` | 校验 preset 里每条 patchEntry 是否存在 |
| `vsl_export_preset` | 把 `.vsynpreset` 解成 JSON（单个/多个/整目录） |
| `vsl_outline_preset` | 打印完整维度树（folder/patch、switchControl+槽位、parallel、xfade→CC、range、velXFadeMode…） |
| `vsl_compare_presets` | 多份预设逐节点对比（缩写归一成 `@`），查跨声部不一致 |
| `vsl_edit_preset` | 改字段写新文件：`setField` / `setPatch` / `setXfades`（8 值一档）/ `removeSlot` / `setController` / **成套修复** `mapSection` `fillSlots` `fixCrossSection` `syncFromPresets` `syncAllSections`（`report:true` 只报告不写） |
| `vsl_controller_map` | 读控制器映射：Dim.Ctrl A–H（`nodeXFade0..7`）与自动化 destination → source |
| `vsl_scan_presets` | 扫一个目录出总报告：槽数、各维度 Dim.Ctrl 来源、异常（空槽 / 缺音域 / 重复 patch / 跨声部指错） |
| `vsl_scan_volume_frames` | 诊断：扫 `.syvolume` 里所有压缩帧并尝试解码（用于判断"本体是否可得"） |

> **写入安全（硬约束）**：所有写盘脚本（generate / build_preset / export / edit）**只允许写到路径中含
> `Generated`/`generated` 的目录**，且**默认不覆盖已存在文件**（要覆盖须显式 `-Force`）。
> 需要写到别处必须显式 `-AllowOutsideGenerated`（或设 `VSL_ALLOW_OUTSIDE_GENERATED=1`）。
> 目的：**永不覆盖你手写的预设**。

插件注册方式（**推荐：自动发现 + junction**）：
`~/.config/opencode/plugins/vsl-synchron-player` → junction 到 `C:\Agent Program Files\Skills\vsl-synchron-player\plugin`。
`plugins/` 目录下的插件会被 OpenCode 自动加载，与 skill 的 junction 做法一致。

> ⚠️ 踩坑记录：用 `opencode.jsonc` 的 `"plugins"` 条目引用 `./skills/vsl-synchron-player/plugin` **能加载**，
> 但重启后可能仍挂着**旧的编译缓存**（新加的工具不出现）；改用 `~/.config/opencode/plugins/` 自动发现后就正常了。
> 另外 `plugins` 条目本身要求指向**目录**（直接写 `.ts` 会被 `configured plugin path must be a directory` 拒绝）。
> 改了插件代码后：`opencode service restart`。

**用户习惯**见 `references/user-habits.md`（例如：**CC58 切技法，每 8 个值一档**）——生成预设默认遵循。
（该文件为**个人配置，已 gitignore，不随仓库发布**；新环境需自建。）

---

## 1. 核心事实（记住这几条就够用）

- **root slot**：在播放器维度区空白处右键 `Copy root slot` 得到的 JSON，顶层是 `folderNodeData`，
  整个维度树（folder 节点 + patch 叶子）。粘回空白/已启用的树即可覆盖。
- **patch 指向**：patch 叶子的 `patchEntry` 字段是
  `vol://<内容卷ID>:public/patches/<产品文件夹>/<乐器文件夹>/<技法文件夹>/<patch文件>.vsynpatch`
  ——换声部就是**替换其中 3 段**：内容卷 ID、乐器文件夹、patch 文件名里的缩写。
- **`.vsynpreset`** = **一个 zstd 帧**包着预设 JSON（无额外头）。7-Zip **能解压**（不能压缩）。
  预设树在 JSON 里的 `data.custom.sampler.rootNode`。
- **控制器映射**：完整预设的 `data.custom.paramControl.mappings` 存 destination → source；
  维度槽位 key 是 `nodeXFade0..7` = **Dim.Ctrl A..H（共 8 个）**，对应 `switchControl = 257 + i`。
  source 可为 `ccN` / `velocity` / `previousVelocity` / `pitchBend` / `speed` / `duration` / `aftertouch(Alt)` / `none`。
  （root slot 不含此块。）
- **切换语义（实测）**：`parallel=false`（默认）= **单极硬切换**（按下的那一刻决定档位，按住期间拉控制器不变），
  切换点 = 该槽 `fadeOutStart..fadeOutEnd` 的**中点**；`parallel=true` = **渐变/叠加**，**按住时实时渐变**，
  渐变区间 = `nodeXFades` 的重叠区本身（面板显示即精确值）。
  → 硬切"每 8 值一档"：中点落在 8/16/24…（`setXfades … "steps":8`），分档 `0–7 / 8–15 / …`，末档到 127。
- **`.syvolume`** = `VINv` 魔数 + **明文 JSON 头**（含 `id`/`description`/`volumeRefs`）
  + 一个 **zstd 帧**（内容是该乐器卷的**完整 patch 树 + 工厂预设名清单**）。
- **工厂预设本体拿不到**（实测结论）：卷里那个 zstd 帧只是一个**清单**（名字 → 编号；
  预设与 patch 共用同一编号空间，例如预设 `0..5`、patch 从 `6` 起）。本体在卷的数据区按编号存放，
  但**不是任何标准压缩帧**——整个卷只有 1 个 zstd 帧，原始字节里也搜不到 `patchEntry` / `nodeXFades` /
  `vsynpreset` 字样；VE Pro 工程文件（`.vesp64`/`.vecs`）里同样不是明文。
  → **只能**在播放器里打开工厂预设，右键 `Copy root slot`（或另存 `.vsynpreset`）来导出。
  诊断脚本：`scripts/scan-volume-frames.ps1`（多压缩格式扫描）。
- patch 树 JSON 形状：
  `{ patches: { <Collection>: { <Product>: { <乐器文件夹>: { <技法>: { <patch文件>: index } } } } },
     instruments: { at.co.vsl.synchronplayer: { presets: {...} } } }`

> 详细字段字典、语法、坑，见 `references/`（用户整理的中文长文档）。
> 重要：**乐器文件夹前面的编号必须一起换**（1st=01/2nd=02/Vla=03/Vc=04/DB=05），只换
> `1st Violins-14` 会得到不存在的 `01 SY 2nd Violins-10 Pro`。

## 2. 数据库（已生成，可直接查）

`data/vsl-patches.csv` —— 全部已装库的真实 patch（约 **25,700** 条）。
列：`Volume, ContentId, Description, Collection, Product, Instrument, Articulation, PatchFile, Index, Path`
（`Path` 是 patch 文件所在的目录，`Path + '/' + PatchFile` 即 `patchEntry` 里 `patches/` 之后的部分。）

其他：`data/vsl-presets.csv`（约 2,500 个工厂预设名）、`data/vsl-patches-by-collection.csv`
（分类计数）、`data/vsl-content-ids.txt`（734 个内容卷 ID）、`data/cache/`（每卷缓存）。

**刷新数据库（重要：内容可能随 VSL 更新而过时）**

```powershell
# 全量重建 ~95 s / 197 卷；之后增量刷新只要几秒（按 大小+mtime 跳过未变卷）
powershell -ExecutionPolicy Bypass -File scripts/build-vsl-patch-db.ps1 -LibraryRoot "D:\VSL Library"
# 改了库/想强制重扫：
... -Force
```
想"即时/避免过时"：把上面命令在需要前跑一次即可 —— **刷新约 5 s**，完全够用。

**查 names**（例：某声部有哪些 LyV、某技法的完整 patch 名）：

```powershell
$db = Import-Csv data/vsl-patches.csv
$db | Where-Object { $_.Collection -eq '02 Synchron Strings Pro' -and $_.Instrument -match 'basses' } |
      Select-Object Product,Instrument,Articulation,PatchFile | Format-Table -AutoSize
```

## 3. 标准工作流

1. **（可选）刷新 DB** —— `scripts/build-vsl-patch-db.ps1`。
2. **确认目标声部的真实字符串**：查 `data/vsl-patches.csv`，或从目标 factory 预设 `Copy root slot` 读
   `patchEntry`；或 `scripts/build-vsl-patch-db.ps1` 解出的树。**不要凭别的库推断**。
3. **准备模板**：用户复制出来的 root slot（JSON），或一个现成 `.vsynpreset`。
4. **写 map JSON**（见 `examples/strings-pro-map.json`）：每条含 `name`、按顺序的
   `replacements`（`[from,to]`）、可选 `rangeSource`（从哪个预设抄音域）、可选
   `ranges`（逐 patch 覆盖音域）、`currentPreset`。
5. **生成**：`scripts/generate-section-presets.ps1 -Template <本地模板> -MapFile <map> -OutDir <目录>`。
6. **校验**：`scripts/verify-patch-paths.ps1 -Preset <生成物> -Database data/vsl-patches.csv`
   —— 要求 `NOT FOUND: 0`。
7. 把结果放进 `…\Documents\VSL\Vienna Synchron Player\Presets\` 即被播放器识别。

## 4. 脚本速查

```powershell
# 提取/更新 patch+preset 数据库
scripts\build-vsl-patch-db.ps1 [-LibraryRoot "D:\VSL Library"] [-OutDir <默认 data>] [-Force]

# 由模板批量克隆到各声部（输出 .vsynpreset 或 .json root slot）
scripts\generate-section-presets.ps1 -Template <x.vsynpreset|.json> -MapFile <map.json> -OutDir <dir>

# 校验生成物里的每条 patchEntry 是否真实存在于库
scripts\verify-patch-paths.ps1 -Preset <x.vsynpreset> -Database data\vsl-patches.csv
```

`-Template`、`-rangeSource` 都可以直接给 `.vsynpreset`（脚本内部用 7-Zip 自动解压）。

## 5. 坑清单（务必逐条核对）

- 乐器文件夹**编号一起换**（01→02/03/04/05）。这是最常见的翻车点。
- **大提**两个文件夹用词不同：Pro 是 `04 SY Violoncellos-8 Pro`，全力度是 `04 SY Cellos-8`。
  替换时**先换带 ` Pro` 的那条**。
- **各声部不完全对称**：低音在 Synchron Strings I 层**没有 `…_LyV`（抒情/多颤）**，
  所以 `13F DB-6_Legato-LyV` 等不存在；可改指 Pro 的 `31 DB-6 Legato molto Vib` 或删槽。
  另外低音 `XFade Resource` 只有 2 条（其它声部 22）。
- **音域 `rangeFrom/rangeTo` 各声部不同**，必须按目标声部改写（`rangeSource`/`ranges`），
  否则用官方做法删掉这些行让播放器回填。
- 播放器内：**先 `Enable all slots` 再复制**；粘到**空白/已启用**的树；必要时**粘两次**修正音域。
- **写入安全**：写盘脚本只写 `Generated/generated` 目录、默认不覆盖已存在文件（见上）。**永不覆盖手写预设。**
- root slot / 预设**不含 mixer preset**（本库 mixer 与声部无关，但别库要留意）；需要时另加载 Mixer Preset。
- 指向不存在的 patch 会报错——可在播放器里"删除含缺失 patch 的槽"清理。
- **手工写 `.vsynpreset` 用的是 zstd raw block（合法但不压缩，约 117 KB/个）**；播放器用标准
  zstd 解码器理论可读。若播放器拒收，改输出 root slot 文本（`"output":"json"`）再右键粘贴。

## 6. Synchron Strings Pro 对照表（实测，经卷内 patch 树核对）

| 声部 | 内容卷 ID | Pro 文件夹 | 全力度文件夹 | 缩写 |
|---|---|---|---|---|
| 1st Violins-14 | `at.co.vsl.sy.stringspro.violins1` | `01 SY 1st Violins-14 Pro` | `01 SY 1st Violins-14` | `VI-14` |
| 2nd Violins-10 | `...stringspro.violins2` | `02 SY 2nd Violins-10 Pro` | `02 SY 2nd Violins-10` | `VI-10` |
| Violas-8 | `...stringspro.violas` | `03 SY Violas-8 Pro` | `03 SY Violas-8` | `VA-8` |
| Cellos-8 | `...stringspro.cellos` | `04 SY Violoncellos-8 Pro` | `04 SY Cellos-8` | `VC-8` |
| Double basses-6 | `...stringspro.basses` | `05 SY Double basses-6 Pro` | `05 SY Double basses-6` | `DB-6` |

三步替换（大提四步）：`violins1→目标ID`；`01 SY 1st Violins-14[ Pro]→目标文件夹`；`VI-14→目标缩写`。

## 7. 参考与示例

- `references/user-habits.md` —— **个人习惯（不入库）**：CC58 每 8 值一档切技法、家族前缀命名（STR/BRS/WW/PERC/ETH）等，生成时默认遵循
- `references/VSL-root-slot-换patch-完全指南.md` —— 完整方法/语法/字段字典/坑（中文长文档）
- `examples/strings-pro-map.json` —— 上面 5 声部的 map 配置示例（含低音 LyV→molto Vib 处理）
- 其它库的乐器代码不统一（Elite `vi1/vi2/va/vc/db`、Dimension `vi/va/vc/db`、Brass `tp1/ho1/…`），
  一律先查 `data/vsl-patches.csv` 的 `ContentId`/`Instrument` 列。

## 8. 工具覆盖度（能做到 / 仍需人工）

**已覆盖**（14 个 `vsl_*` 工具）

| 环节 | 怎么做 |
|---|---|
| 建/刷新数据库 | `vsl_db_build`（全量 ~95s，增量几秒） |
| 查名字 | `vsl_db_query`（按库/声部/技法/正则） |
| 读预设 | `vsl_read_preset`、`vsl_export_preset`（导出 JSON）、`vsl_outline_preset`（完整树 + 控制器映射）、`vsl_controller_map` |
| 对比 | `vsl_compare_presets`（节点 + 控制器映射） |
| 体检 | `vsl_scan_presets`（目录总表 + 异常：空槽 / 缺音域 / 重复 patch / 跨声部指错） |
| 生成 | `vsl_generate_presets`（按 map 克隆到各声部）、`vsl_build_preset`（按 patch 清单拼，支持 per-slot 参数） |
| 修改 | `vsl_edit_preset`：`setField`（含点路径）/ `setPatch` / `setXfades`（`steps` \| 四元组）/ `removeSlot` / `setController` / `mapSection` / `fillSlots` / `fixCrossSection` / `syncFromPresets` / `syncAllSections`；`report:true` 只预览 |
| 校验 | `vsl_verify_patches`（每条 patchEntry 是否存在） |
| 卷诊断 | `vsl_unpack_volume`（patch 树 / 预设名清单）、`vsl_scan_volume_frames`（所有压缩帧） |
| 写盘安全 | 只写 `Generated`；默认不覆盖 |

**仍需人工 / 做不到（已知边界）**

- 工厂预设**本体**导出 → 私有编码，**只能**在播放器里 `Copy root slot` / 另存（见 §1）
- **覆盖 / 删除**手写预设 → 设计上禁止
- 播放器 GUI 操作：加载 / 保存预设、勾 `parallel`、`Enable all slots`、粘 root slot、设 Dim.Ctrl 来源
- mixer 部分：可用 `setField` 改字段，但没有"加载 / 切换 Mixer Preset"的 op
- 从零新建**空**预设：目前只能基于某个 shell 预设（`build_preset` 需要 shell）
- 跨库一次性批量（多库 × 多预设）
