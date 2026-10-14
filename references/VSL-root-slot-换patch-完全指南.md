# VSL Synchron Player —— Root Slot / 换 Patch 完全指南

> 适用于：Vienna Synchron Player（以及 Synchron Piano Player，格式同源）。
> 本文实例库：**Synchron Strings Pro**（本机 `D:\VSL Library\Synchron Series\VSL - Synchron Strings Pro`）。
> 结论基于：官方手册 + VSL 论坛 + vi-control + **对本机已装库/预设的实测**。
>
> 配套文件（同目录）：
> - `vsl-content-ids.txt` —— 本机扫描出的**全部**内容卷 ID（734 条，含各话筒卷）
> - `vsl-instrument-ids.csv` / `vsl-instrument-ids.txt` —— 过滤掉话筒后缀后的**乐器级 ID**（150 条）

---

## 0. TL;DR

1. 你贴的那种 JSON 是 Synchron Player 的 **root slot（根槽 = 整个维度树/矩阵）**，右键空白处 `Copy root slot` 得到，粘回空白/已启用的树即可覆盖。
2. 换 patch 本质就是改 **`patchEntry`** 里那串 `vol://…` 地址中的 3 段：**内容卷 ID（乐器）/ 乐器文件夹 / patch 缩写**（官方说法：abbreviation / ID / folder）。
3. 还有一段要处理：**`rangeFrom` / `rangeTo`**（各声部音域不同）。
4. 不用猜——**最可靠的做法是从目标声部的 factory 预设里再 `Copy root slot` 一份，直接对照那 3 段字符串**。或者在文本编辑器里全文替换（本文给出本库精确值）。
5. root slot **不包含 mixer preset**，混音要另外加载。

---

## 1. 这是什么文件

Synchron Player 的预设里，"维度树"是一棵递归 JSON：

- 每个节点要么是 **folder（文件夹 = 一个维度列，如 "02 Legatos"）**，要么是 **patch slot（叶子 = 一个具体技法，如 "04 VI-14 Legato AT+RS soft"）**。
- `Copy root slot` 复制出来的文本，顶层是 `folderNodeData`，即整棵树。
- 真正的 `.vsynpreset` 文件还包含 mixer / FX / vibrato / MIDI 等区块；**root slot 复制时只带走维度树，不带 mixer**。

本实例（你贴的文件）的树：

```
根 Root（subTitle="Articulation"，switchControl=260，title=""）
├─ Breathing Leg      Soft At-Rs / Soft Release / Regular / Marcato
├─ Perfomance Leg     Portamento / Slur / Legato
├─ NV-Vib Leg         No Vibrato / Vibrato / Lyrical Vib        (parallel)
├─ Sustain            Soft At-Rs / Soft Release / Regular / Sfz
├─ Tremolo            Sustain / Tremolo                          (parallel)
├─ Trills             Trills HT / Trills WT
├─ Short              Spiccato / Staccatissimo / Staccato / Detache
├─ Pizzicato          Pizzicato / Bartok Pizz / Col Legno
├─ Harmonics          Harmonics
└─ Extended           （空槽，patchEntry=null，占位）
```
共 26 个 patch 槽 + 1 个空槽。

---

## 2. `patchEntry` 语法

```
vol://at.co.vsl.sy.stringspro.violins1:public/patches/02 Synchron Strings Pro/01 SY 1st Violins-14 Pro/02 Legatos/04 VI-14 Legato AT+RS soft.vsynpatch
└─┬─┘ └──────────── 内容卷 ID（= 乐器） ─────────┘└─范围─┘ └──产品文件夹─┘ └────乐器文件夹──────┘ └─技法─┘ └──────── patch 文件名 ────────┘
```

| 段 | 例子 | 换声部时 |
|---|---|---|
| 协议头 | `vol://` | 不变 |
| **内容卷 ID** | `at.co.vsl.sy.stringspro.violins1` | **要改** |
| 命名空间 | `:public` | 不变 |
| 产品文件夹 | `02 Synchron Strings Pro` | 不变 |
| **乐器文件夹** | `01 SY 1st Violins-14 Pro` | **要改**（注意 Pro 录音带 ` Pro` 后缀，另有不带后缀的 `…-14` 用于 FULL VELOCITIES 技法） |
| 技法文件夹 | `02 Legatos` | 不变 |
| patch 文件名 | `04 VI-14 Legato AT+RS soft.vsynpatch` | 含**缩写**，**要改** |

内容卷 ID 的通用形状：`at.co.vsl.sy.<产品代码>.<乐器代码>`
- 产品代码例：`stringspro` `syels`(Elite Strings) `brass` `syww`(Woodwinds) `perc1/2/3` `chmbstr`(Chamber) `dimstrI/II/III` `solostr1` `studiobrass` `bbostrings` `harp`…
- **乐器代码各库不统一**（详见 §9）：Strings Pro 用 `violins1/violins2/violas/cellos/basses`；Elite 用 `vi1/vi2/va/vc/db`；Dimension 用 `vi/va/vc/db`。**不要假设**。

---

## 3. root slot 的 JSON 结构（字段字典）

### 3.1 结构 / 树

| 字段 | 含义 |
|---|---|
| `nodes` | 子节点数组（folder 有、patch slot 没有） |
| `parallel` | 该列子槽是**叠加**（true，如 NV-Vib Leg / Tremolo）还是**互斥**（false） |
| `subTitle` | `"Articulation"`（顶层）/ `"Sub Technique"`（子层） |
| `switchControl` | 该维度列绑定的**维度控制器槽位**：`257/258/259/260 = Dim.Ctrl A/B/C/D`，`0`=无。**槽位→控制器类型是播放器里的全局设置**（可以是 CC、力度等），JSON 里**不存 CC 号**。Strings Pro 顶层 = `260`(D)，子列 = `257`(A)/`258`(B)/`259`(C)/`0` |
| `switchControlSeqChordThresh` / `…SeqResetThresh` | 序进/和弦方式切换时的判定阈值（本库 0.2 / 2.0） |
| `whiteNoteSwitch` | 是否只用白键当 keyswitch |
| `useCurrentNodeForRelease` | 释放音是否取当前槽样本 |
| `targetBpm` | 时间拉伸目标速；**负值（-120）表示该层不参与拉伸/同步** |

> ⚠️ 常见误解：`switchControl` **不是 MIDI CC 号**，也没有 `256+CC` 的编码。
> `257..260` 只是 A/B/C/D 四个控制器槽位；某个槽位到底绑 CC 几（或力度）由播放器全局设置决定，
> 所以同一个预设换台机器/换设置，实际切换控制器就可能不同。

### 3.2 交叉淡化 / 选中

| 字段 | 含义 |
|---|---|
| `nodeXFades` | 数组，**长度 = 子槽数**；每项 `{fadeInStart,fadeInEnd,fadeOutStart,fadeOutEnd}`（0–1）。第 i 项的 fadeIn 区间 = 第 i-1 项的 fadeOut 区间（交叉淡化区） |
| `currentNodeIndex` | 当前选中位置：`n+0.5` = 第 n 槽正中；带小数 = 停在淡化区中间 |

### 3.3 通用参数 `parameters`（folder 与 patch 都有，子级继承父级）

`gain, balance, attack, decay, sustain, release, hold, delay, shutdown, startOffset, startOffsetAttack, gainLow, gainLowXFade, gainCurve, gainCurveXFade, releaseVoiceLimit, transposeOctave/Semitone/Cents, vibratoMode, velXFadeMode, nodeXFadeMode`

### 3.4 patch 槽专有

| 字段 | 含义 |
|---|---|
| `patchEntry` | patch 的 `vol://` 地址（null=空槽）——**换 patch 改这里** |
| `patchName` | patch 显示名（含缩写） |
| `enabled` | 是否启用 |
| `outputMatrix` | 该 patch 路由到的混音通道（本库 `[0..8]`=9 通道） |
| `legatoMode` | 连奏模式 |
| `lastHumanizePreset` | 最后使用的 Humanize 预设（`In tune random v6`/`v1`…） |
| `performances` | **12 组** `[time,value]` 折线 = 每次"重复音/演奏变体"的人性化曲线 |
| `performanceDelays` | 12 个延迟值 = 每次重复的起始延迟 |
| `rangeFrom` / `rangeTo` | 可演奏音域（MIDI 音高号；**各声部不同，克隆时要处理**） |
| `sourceBpm` / `targetBpm` | 拉伸原速/目标速（120） |
| `stretchEnabled/stretchMode/stretchSyncMode` | 实时时间拉伸 |
| `startOffsetMode`, `velXFadeGroup`, `timeBeforeReleaseSampleTrigger` | 其它播放细节 |
| `title` / `isCustomTitle` | 槽名（多为自定义） |

### 3.5 UI/元数据

`color`(ARGB)、`icon`、`editId`

---

## 4. 通用克隆工作流

### 4.1 官方流程（Custom Preset Creation）

1. 在 Synchron Player 里把预设调到你要的结构。
2. 右键空白处 → `Copy root slot`。
3. 粘到文本编辑器 → 全文替换 **缩写 / ID / 文件夹** 三段。
4. 删掉所有含 `rangeFrom` / `rangeTo` 的行：
   - Notepad++：`Ctrl+H` → 勾"正则表达式" → 查找 `\n.*range[^\n]*` → 替换留空 → Replace All。
5. 把文本粘到**目标乐器的空白/已启用维度树**里。
6. 需要的话改 keyswitch。

### 4.2 社区实测补充（重要坑）

- **先 `Enable all slots` 再复制**（VSL 官方 andi：不 enable 就删 range 会导致音域被撑大的已知 bug）。
- 粘到**已启用或空白**的树里；社区实测常需 **粘两次**（先 paste → Enable all slots → 再 paste），range 才刷新正确。
- 替换后指向不存在的 patch 会**报错**，可在 player 里 **一键删除所有含缺失 patch 的槽**。
- **更省事的做法**：先在 **Tutti 预设**上搭结构，然后只靠文本替换生成各声部（省得每个声部都要重搭）。
- **mixer preset 不在文本里**：要单独 load，或开两个 player 实例（一个装工厂预设，一个粘自定义树）。
- Humanize 曲线会跟着走（有人把 SS1 patch 的 v1 改成 SSPro 的 v6）。

---

## 5. 如何拿到「任意库」的准确名字

> 核心原则：**不要猜，直接从目标里读**。以下 4 种方法，可靠性递减。

### 方法 A（最权威）：从目标 factory 预设 `Copy root slot`

打开目标乐器（比如 Synchron Elite Strings – Viola）的 factory 预设 → 右键 → `Copy root slot` → 粘到编辑器 → 读它 `patchEntry` 里的 3 段。**这是唯一 100% 不会错的方法。**

### 方法 B：解压你自己的 `.vsynpreset` 读 `patchEntry`

`.vsynpreset` 是 **Zstandard（zstd）** 压缩（文件头魔数 `28 B5 2F FD`）。用 7-Zip（≥21.07）即可解压：

```powershell
# 把 .vsynpreset 复制成 .zst，再解压，得到 JSON 文本
& "C:\Program Files\7-Zip\7z.exe" x -y -o"$out" "$preset.zst"
# 然后 regex 提取 patchEntry / patchName / rangeFrom / rangeTo
```

本指南里的 Strings Pro 对照表就是这么读出来的。

### 方法 C：读 `.syvolume` 头部的 JSON，拿内容卷 ID

全部 `.syvolume` 文件开头有一段明文 JSON（`VINv` 魔数之后）：

```json
{
  "compatibilityVolumeIds": ["at.co.vsl.sy.strings1.1stviolins"],
  "contentVersion": 2,
  "creationDate": "...",
  "description": "Synchron Strings Pro - 1st Violins",
  "flags": 0,
  "id": "at.co.vsl.sy.stringspro.violins1",
  "license": { "id": "...", "name": "Synchron Strings Pro Standard" },
  "title": "SYNCHRON Collections",
  "volumeRefs": [ "at.co.vsl.sy.stringspro.violins1.Room-Mix", ... ]
}
```
`id` 就是内容卷 ID。批量扫描脚本见 §7。

### 方法 D：官方文档给的对照表（以 Synchron Strings I 为例）

官方 Custom Preset Creation 页给出：

| 声部 | 缩写 | ID | 文件夹 |
|---|---|---|---|
| 1st Violins | VI-14 | 1st violins | 01 SY 1st Violins-14 |
| 2nd Violins | VI-10 | 2nd violins | 02 SY 2nd Violins-10 |
| Violas | VA-8 | violas | 03 SY Violas-8 |
| Cellos | VC-8 | cellos | 04 SY Cellos-8 |
| Double Basses | DB-6 | basses | 05 SY Double basses-6 |

⚠️ 不同库/不同版本的字符串不同（Strings I 的 ID 写成 `1st violins`，而实际卷 ID 是 `at.co.vsl.sy.strings1.1stviolins`；Strings Pro 则是 `…stringspro.violins1`）。**以方法 A/B/C/E 实测为准。**

### 方法 E（可枚举"任意已装库"的**全部 patch 名**）：从 `.syvolume` 里"刨"出 patch 树

`.syvolume` 内部有一段 **zstd 帧**，解出来就是该乐器卷的完整 patch 目录
（`patches → 产品 → 乐器文件夹 → 技法 → patch 文件名`）。
7-Zip **不能压缩** zstd，但**能解压**。步骤：

1. 在 `*_Patches.syvolume` 里找唯一一个 zstd 魔数 `28 B5 2F FD` 的偏移（本机 Strings Pro 各卷约在 2.9 MB 处）。
2. 从该偏移截到文件尾，另存为 `.zst`。
3. `7z x` 解开 → 得到含完整 patch 树的 JSON。

这是**最权威的"有哪些 patch、文件夹叫什么"来源**，可用于任意已安装的库（脚本见 §7）。

### 方法 F：把 JSON 重新编码成**可直接导入**的 `.vsynpreset`

`.vsynpreset` = **一个 zstd 帧**，内容就是预设 JSON（没有额外文件头）。
本机没有 zstd 压缩器，但可以用 **raw block**（不压缩块）手工构造一个**合法 zstd 帧**——任何 zstd 解码器都能读，只是体积≈JSON 原始大小（约 117 KB / 个）。脚本见 §7，本文档已用它生成了 4 个可直接导入的 preset（见 `generated/`）。

---

## 6. Synchron Strings Pro —— 精确对照表（本机实测，经卷内 patch 树核对）

| 声部 | 内容卷 ID | Pro 文件夹 | FULL VELOCITIES 文件夹 | 缩写 |
|---|---|---|---|---|
| 1st Violins-14 | `at.co.vsl.sy.stringspro.violins1` | `01 SY 1st Violins-14 Pro` | `01 SY 1st Violins-14` | `VI-14` |
| 2nd Violins-10 | `at.co.vsl.sy.stringspro.violins2` | `02 SY 2nd Violins-10 Pro` | `02 SY 2nd Violins-10` | `VI-10` |
| Violas-8 | `at.co.vsl.sy.stringspro.violas` | `03 SY Violas-8 Pro` | `03 SY Violas-8` | `VA-8` |
| Cellos-8 | `at.co.vsl.sy.stringspro.cellos` | `04 SY Violoncellos-8 Pro` | `04 SY Cellos-8` | `VC-8` |
| Double basses-6 | `at.co.vsl.sy.stringspro.basses` | `05 SY Double basses-6 Pro` | `05 SY Double basses-6` | `DB-6` |

> ⚠️ **最容易犯的错**：乐器文件夹**前面的编号必须一起换**（1st=01、2nd=02、Vla=03、Vc=04、DB=05）。
> 只把 `1st Violins-14`→`2nd Violins-10` 而保留 `01 `，会得到**不存在的** `01 SY 2nd Violins-10 Pro`。
> （本机 `Documents\VSL\...\Presets\Strings` 里那几个 `STR Synchron Vln2/Vla/Vc/DB` 预设**正是这个 bug**——开头全是 `01 SY …`，需要修，或被 `generated/` 里正确的版本替换。）

以 **小提1** 为模板，每声部三步（大提四步）：

- **→ 小提2**：`violins1`→`violins2`；`01 SY 1st Violins-14`→`02 SY 2nd Violins-10`；`VI-14`→`VI-10`
- **→ 中提**：`violins1`→`violas`；`01 SY 1st Violins-14`→`03 SY Violas-8`；`VI-14`→`VA-8`
- **→ 大提**：`violins1`→`cellos`；**先** `01 SY 1st Violins-14 Pro`→`04 SY Violoncellos-8 Pro`，**再** `01 SY 1st Violins-14`→`04 SY Cellos-8`；`VI-14`→`VC-8`
  ⚠️ 大提是唯一两个文件夹用词不同的：Pro 用 **Violoncellos**，FULL VELOCITIES 用 **Cellos**。顺序反了/漏了会指向不存在的 patch。
- **→ 低音**：`violins1`→`basses`；`01 SY 1st Violins-14`→`05 SY Double basses-6`；`VI-14`→`DB-6`

### 6.1 音域（`rangeFrom`/`rangeTo`）——各声部不同

实测（MIDI 音高号，C4=60）：

| 声部 | 基本音域 | Long 类 | FULL VEL 连奏 | Trill_1 / Trill_2 | Harmonics |
|---|---|---|---|---|---|
| 1st Violins | 55–98 | 55–100 | 55–103 | 102 / 101 | 67–95 |
| 2nd Violins | 55–98 | 55–100 | 55–100 | 99 / 98 | 67–95 |
| Violas | 48–88 | 48–89 | 48–88 | 88 / 87 | 60–89 |
| Cellos | 36–81 | 36–81 | 36–81 | 80 / 79 | 48–83 |
| Double basses | 23–60 | 23–62 | 23–62 | 61 / 60 | 35–65 |

两条路：**(a)** 官方做法——删掉所有 `rangeFrom/rangeTo` 行，让 player 自动回填（先 Enable all slots、必要时粘两次）；**(b)** 按上表把各声部的正确值写进去（更稳，推荐）。

### 6.2 缺失 patch（克隆后需删槽）

- **低音缺少 `13F …_Legato-LyV`（"Lyrical Vib" 连奏）**：克隆到低音后，"NV-Vib Leg / Lyrical Vib" 槽会报错 → 删除该槽即可（低音一共有 25 个 patch，其它声部 26 个）。

### 6.3 keyswitch

Strings Pro 五个声部的 factory 预设里 `switchControl` 序列**完全一致**（`259,259,257,259,257,258,258,258,0,260`），所以**同库内跨声部克隆不需要改 keyswitch**。官方那句"violin/viola ↔ cello/bass 要改 keyswitch"主要针对跨库/音域差异大的情况；若你的 DAW 表情映射用音高 keyswitch，仍建议核对。

---

### 6.4 已生成的可导入 preset（`generated/`）

用方法 F 生成了 4 个可直接导入的 `.vsynpreset`：

- `STR Synchron Vln2 a10 (generated).vsynpreset`
- `STR Synchron Vla a8 (generated).vsynpreset`
- `STR Synchron Vc a8 (generated).vsynpreset`
- `STR Synchron DB a6 (generated).vsynpreset`

内容 = 你的 Vln1 预设（26 个技法槽）＋各声部正确的 ID/文件夹/缩写＋各声部正确音域。
**已逐条核对**：四个声部的 26 条 `patchEntry` **全部命中**卷内真实 patch 树（26/26）。

> 低音有一处特别处理：模板里 "NV-Vib Leg → Lyrical Vib" 用的是 SS1 的 `13F …_Legato-LyV`，
> 而 **低音在 Synchron Strings I 里没有 LyV（抒情/多颤）**，该 patch 不存在；
> 已改指向 Pro 层的 `…/05 SY Double basses-6 Pro/02 Legatos/31 DB-6 Legato molto Vib.vsynpatch`（音域 23–60）。
> 详见 §9.3。

- 放入 `…\Documents\VSL\Vienna Synchron Player\Presets\` 即可加载（建议改名，避免与现有 `STR Synchron …` 冲突）。
- 复用 Vln1 的 mixer 区块（本库 mixer 不含声部专属 volume id，故跨声部可用）；若要各声部自带混音，加载后在 MIX 页加载对应 Mixer Preset。
- 手工构造的是 zstd **raw block**（合法但不压缩）。播放器用标准 zstd 解码器，理论可读；若播放器拒收，改用 root slot 文本粘贴（内容等价）。

> 修复建议：你现有的 `STR Synchron Vln2/Vla/Vc/DB` 预设开头是 `01 SY …`（错误），
> 可删掉换成 `generated/` 里正确的版本，或按 §6 把 `01 SY 1st Violins-14`→`0N SY …` 重新替换一遍。

---

## 7. 全库内容卷 ID（本机 150 个乐器级）

完整清单见同目录：
- `vsl-content-ids.txt`（734 条，含各话筒卷）
- `vsl-instrument-ids.txt`（150 条，乐器级）

附录见文末。

### 批量扫描脚本（PowerShell，可直接复用到任何机器）

```powershell
$enc = [Text.Encoding]::GetEncoding(28591)   # 注意：PS 5.1 没有 [Text.Encoding]::Latin1
$roots = @("D:\VSL Library","C:\ProgramData\VSL\Vienna Synchron Player\Volumes")
$rows = foreach($f in (Get-ChildItem $roots -Recurse -File -Include *.syvolume -ErrorAction SilentlyContinue)){
  $fs=[IO.File]::OpenRead($f.FullName)
  $len=[Math]::Min(16384,$fs.Length); $buf=New-Object byte[] $len; [void]$fs.Read($buf,0,[int]$len); $fs.Close()
  $txt=$enc.GetString($buf)
  $id=[regex]::Match($txt,'"id"\s*:\s*"([^"]*)"').Groups[1].Value
  $desc=[regex]::Match($txt,'"description"\s*:\s*"([^"]*)"').Groups[1].Value
  if($id -match '^at\.co\.vsl'){ [pscustomobject]@{Id=$id;Desc=$desc} }
}
$rows | Sort-Object Id -Unique
```

### 解压预设脚本（读某个 `.vsynpreset` 的 patchEntry）

```powershell
$src = "C:\Users\<你>\Documents\VSL\Vienna Synchron Player\Presets"
$tmp = "$env:TEMP\vsl"; New-Item -ItemType Directory -Force $tmp | Out-Null
foreach($p in (Get-ChildItem $src -Recurse -Filter *.vsynpreset)){
  $d = Join-Path $tmp $p.BaseName; New-Item -ItemType Directory -Force $d | Out-Null
  Copy-Item $p.FullName (Join-Path $d "f.zst") -Force
  & "C:\Program Files\7-Zip\7z.exe" x -y "-o$d" (Join-Path $d "f.zst") | Out-Null
  $t = [IO.File]::ReadAllText((Join-Path $d "f"))    # 解出来是 JSON
  "### $($p.Name)"
  [regex]::Matches($t,'"patchEntry"\s*:\s*"([^"]*)"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
}
```

### 从 `.syvolume` 刨出完整 patch 树（方法 E）

```powershell
function Get-VolumePatchTree([string]$volumeFile,[string]$workDir){
  $b=[IO.File]::ReadAllBytes($volumeFile)
  $off=-1
  for($i=0;$i -lt $b.Length-4;$i++){ if($b[$i]-eq 0x28 -and $b[$i+1]-eq 0xB5 -and $b[$i+2]-eq 0x2F -and $b[$i+3]-eq 0xFD){ $off=$i; break } }
  New-Item -ItemType Directory -Force $workDir | Out-Null
  [IO.File]::WriteAllBytes("$workDir\f.zst", $b[$off..($b.Length-1)])
  & "C:\Program Files\7-Zip\7z.exe" x -y "-o$workDir\out" "$workDir\f.zst" | Out-Null
  $dec = Get-ChildItem "$workDir\out" -File | Select-Object -First 1
  return ([Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($dec.FullName)) | ConvertFrom-Json)
}
# 用法：$j = Get-VolumePatchTree "D:\...\SY-Strings-Pro_2ndviolins_Patches.syvolume" "$env:TEMP\v2"
# patch 树在 $j.patches.'02 Synchron Strings Pro' 下（递归：对象=文件夹，整数=patch 索引）
```

### 手工 zstd 编码（方法 F：把 JSON 写成可导入的 `.vsynpreset`）

```powershell
function Write-ZstdRaw([byte[]]$data,[string]$path){   # 合法 zstd 帧，raw block（不压缩）
  $ms=New-Object IO.MemoryStream; $bw=New-Object IO.BinaryWriter($ms)
  foreach($b in 0x28,0xB5,0x2F,0xFD){ $bw.Write([byte]$b) }   # magic
  $bw.Write([byte]0xA0)                                        # FCS=4B | Single_Segment=1
  $bw.Write([uint32]$data.Length)                              # Frame_Content_Size
  $max=131072; $off=0
  while($off -lt $data.Length){
    $sz=[Math]::Min($max,$data.Length-$off); $last= if(($off+$sz) -ge $data.Length){1}else{0}
    $bh=[uint32]((([uint32]$sz) -shl 3) -bor [uint32]$last)     # Block_Header: size<<3 | last
    $bw.Write([byte]($bh -band 0xFF)); $bw.Write([byte](($bh -shr 8) -band 0xFF)); $bw.Write([byte](($bh -shr 16) -band 0xFF))
    $bw.Write($data,$off,$sz); $off+=$sz
  }
  $bw.Flush(); [IO.File]::WriteAllBytes($path,$ms.ToArray())
}
# Write-ZstdRaw ([Text.Encoding]::UTF8.GetBytes($jsonText)) "out.vsynpreset"
# 验证：7z x out.vsynpreset(.zst) 应还原出字节完全相同的 JSON
```

### 生成各声部 preset / root slot（模板替换）脚本骨架

```powershell
$base = [IO.File]::ReadAllText("STR Synchron Vln1 a14.json")   # 解压后的 Vln1 预设 JSON（或你复制的 root slot）
$sections = @(
  @{ n='Vln2'; id='violins2'; old='01 SY 1st Violins-14'; new='02 SY 2nd Violins-10'; abbr='VI-14'; abbrTo='VI-10' },
  @{ n='Vla';  id='violas';   old='01 SY 1st Violins-14'; new='03 SY Violas-8';       abbr='VI-14'; abbrTo='VA-8'  },
  @{ n='Vc';   id='cellos';   old='01 SY 1st Violins-14'; new='04 SY Cellos-8';       abbr='VI-14'; abbrTo='VC-8';
     proOld='01 SY 1st Violins-14 Pro'; proNew='04 SY Violoncellos-8 Pro' },        # 大提：先换带 " Pro" 的
  @{ n='DB';   id='basses';   old='01 SY 1st Violins-14'; new='05 SY Double basses-6';abbr='VI-14'; abbrTo='DB-6'  }
)
foreach($s in $sections){
  $t = $base
  if($s.proOld){ $t = $t.Replace($s.proOld,$s.proNew) }                 # 大提先行
  $t = $t.Replace('violins1',$s.id).Replace($s.old,$s.new).Replace($s.abbr,$s.abbrTo)
  # rangeFrom/rangeTo 用目标声部的值覆盖（按 patchName 匹配），或先删掉让 player 回填
  Write-ZstdRaw ([Text.Encoding]::UTF8.GetBytes($t)) "$($s.n).vsynpreset"
}
```

> 结果放入 `…\Documents\VSL\Vienna Synchron Player\Presets\` 即可在播放器里出现。
> root slot 版本则改成输出 JSON、再在播放器里右键 `Paste root slot`（并先 `Enable all slots`）。

---

## 8. 坑清单（Checklist）

- [ ] 先 `Enable all slots`，再复制/粘贴；必要时 **粘两次**。
- [ ] 只粘到**空白或已启用**的维度树。
- [ ] 大提：**先替换带 ` Pro` 的文件夹**（Violoncellos），再替换不带 Pro 的（Cellos）。
- [ ] `rangeFrom/rangeTo`：按声部改写，或删除让 player 回填。
- [ ] 低音缺 `13F…LyV`（Lyrical Vib）→ 删对应槽。
- [ ] **mixer preset 不在 root slot 里**，要另外加载。
- [ ] 缺 patch 会报错——用"删除含缺失 patch 的槽"清理。
- [ ] 备份原预设（`…\Documents\VSL\Vienna Synchron Player\Presets\`）。
- [ ] 不要跨产品盲目替换 ID后缀（各库乐器代码不统一，见 §9）。
- [ ] `.vsynpreset` 是 zstd；直接文本打开是乱码，要 7-Zip 解压。

---

## 9. 各库 / 技法命名差异观察

### 9.1 内容卷 ID 的乐器代码（本机实测）

| 库 | 产品代码 | 乐器代码 |
|---|---|---|
| Synchron Strings Pro | `stringspro` | `violins1` `violins2` `violas` `cellos` `basses` |
| Synchron Elite Strings | `syels` | `vi1` `vi2` `va` `vc` `db` |
| Synchron Chamber Strings (sordino) | `chmbstrmu` | `vi` `va` `vc` `db` |
| SYNCHRON-ized Dimension Strings I/II/III | `dimstrI/II/III` | `vi` `va` `vc` `db` |
| SYNCHRON-ized Solo Strings | `solostr1` | `vi1` `vi2` `va` `vc1` `vc2` `db` |
| Synchron Brass | `brass` | `tp1` `tp2` `tp4` `tp6` `ho1` `ho2` `ho6` `ho12` `ttb` `tb4` `tb9` `btb` `tu` `cim` `lb` |
| Synchron Woodwinds | `syww` | `pfl` `fl1` `fl2` `ob1` `ob2` `eh` `cl1` `cl2` `bcl` `ba1` `ba2` `cba` `afl` `ens` `tutti` `fxhigh` `fxlow` |
| Synchron Percussion I/II/III | `perc1/2/3` | `timpani` `drums` `cymbals` `gongs` `mallets` `bells` `percussion` `bonus` |
| Studio Brass | `studiobrass` | `Trumpet-Bb` `Trumpet-C` … `TrbTen` `TrbBass` |
| Special Brass | `specialbrass` | `Horns8` `cim` |
| BBO | `bbostrings` `bbobrass` `bboww` `bbochoirs` `bboperc` `bbotutti` | 无（整库一个卷） |
| Harp / Harps | `harp` / `hps` | `harp1` `harp2` |
| Pianos | `pianos` | `f308ess` `f212` `yamahaess` `steinway` `boesvc` `boesupr`（多为 `*.pianocore`） |

### 9.2 技法文件夹 / 缩写

- **技法是每个乐器各自的一套文件夹**，Strings Pro 为：
  `01 Shorts` / `02 Legatos` / `03 Long` / `04 Dynamics` / `05 Ponticello - Harmonics` / `06 Phrases` / `A - FULL VELOCITIES`。
- 文件夹名里含**序号前缀**（`01 `, `02 `…），所以整段替换比只改单词更安全。
- **缩写**一般是 `<乐器代码>-<人数>`（`VI-14`、`VA-8`、`VC-8`、`DB-6`），并出现在 **patch 文件名**和 **`patchName`** 两处，所以替换缩写会同时改到这两处（好事）。
- **FULL VELOCITIES** 里的 patch（`11F/12F/13F/21F …`）来自 Synchron Strings I（"Optimized" 内容），其 Humanize 可能是 v1 而非 v6。
- 其它库的技法命名/缩写**务必用 §5 方法 A/B/E 实测**，不要从别库推断。

### 9.3 各声部内容并不完全对称：低音没有 LyV（抒情/多颤）

从卷内 patch 树对比可见：Vln1/Vln2/Vla/Vc 各 **160** 个 patch，而 **DB 只有 120 个**。差的 40 个正好是"抒情颤音（LyV）"相关：

| 位置 | 其它声部 | Double basses |
|---|---|---|
| `A - FULL VELOCITIES` | 17 | **12** |
| `B - SOFT / C - MED / D - LOUD VELOCITIES` | 18/18/17 | **13/13/12** |
| `XFade Resource` | 22 | **2** |
| `01 Shorts`/`02 Legatos`/`03 Long`/`04 Dynamics`/`05 Ponticello - Harmonics`/`06 Phrases` | 12/20/13/5/7/11 | 12/20/13/5/7/11（**相同**） |

原因：那些 `*F`（FULL VELOCITIES）patch 是从 **Synchron Strings I** 导进来的，而 **SS1 没有为低音录制 LyV（lyrical/molto-vibrato）采样**，于是低音卷里**所有 `…_LyV` 都不存在**：

`04F …_Long-LyV`、`10F …_Lo-soft-LyV`、`13F …_Legato-LyV`、`16F …_Leg-Soft-LyV`、`23F …_Leg-slur-LyV`

连带 `XFade Resource`（用于 noV↔LyV 颤音交叉淡化）在低音里也只剩 Short-Layer 两条。

注意：**低音在 Pro 层是有"多颤"的**——`05 SY Double basses-6 Pro/02 Legatos/31 DB-6 Legato molto Vib.vsynpatch`（以及 `03 Long/11 DB-6 Long molto Vibrato`）。所以低音的替代做法是：
- 删掉该槽（与 VSL 自己的低音预设一致），**或**
- 把它改指向 Pro 的 `31 DB-6 Legato molto Vib.vsynpatch`（`generated/` 里的低音版本就是这么做的，音域 23–60）。

同理，任何"从别的声部克隆"的操作，遇到低音/其它不对称声部时，务必用 **§5 方法 E** 先列出该声部的真实 patch 清单再替换。

---

## 10. 参考链接

- 官方手册 · Custom Preset Creation：`https://www.vsl.info/en/manuals/synchron-player/custom-preset-creation`
  （Wayback 可读：`http://web.archive.org/web/2024id_/https://www.vsl.info/en/manuals/synchron-player/custom-preset-creation`）
- 官方手册 · Edit Tab：`https://www.vsl.co.at/manuals/synchron-player/edit-tab`
- Synchron Player 版本历史：`https://www.vsl.co.at/manuals/changelog/synchron-player`
- 论坛 · Editing presets with a text editor：`https://forum.vsl.co.at/topic/57448`
- 论坛 · Custom presets ranges?：`https://forum.vsl.co.at/topic/61660`
- 论坛 · Custom Preset creation – Mixer presets：`https://forum.vsl.co.at/topic/56963`
- 论坛 · how to replicate Matrices：`https://forum.vsl.co.at/topic/54879`
- vi-control · Sync-ized Dimension Strings 管理技法：`https://vi-control.net/community/threads/106948`
- vi-control · SS1 + SSPro 合并预设：`https://vi-control.net/community/threads/101008`
- 官方视频（预设定制）：`https://www.youtube.com/watch?v=cEBTh2iula0`

---

## 附录：本机全部乐器级内容卷 ID（150）

### 

- `at.co.vsl.synchronplayer` — Vienna Synchron Player Core

### appstr

- `at.co.vsl.sy.appstr` — SYNCHRON-ized Appassionata Strings

### bbobrass

- `at.co.vsl.sy.bbobrass` — BBO Brass
- `at.co.vsl.sy.bbobrass.Ho-Close` — BBO Brass Ho-Close
- `at.co.vsl.sy.bbobrass.Ho-Mid` — BBO Brass Combo Horns Mid
- `at.co.vsl.sy.bbobrass.VA-Close` — BBO Brass VA-Close
- `at.co.vsl.sy.bbobrass.VC-Close` — BBO Brass Violoncellos Close
- `at.co.vsl.sy.bbobrass.WW-Mid` — BBO Brass Combo WW-Mid

### bbochoirs

- `at.co.vsl.sy.bbochoirs` — BBO Choirs

### bboperc

- `at.co.vsl.sy.bboperc` — BBO Percussion

### bbostrings

- `at.co.vsl.sy.bbostrings` — BBO Strings

### bbotutti

- `at.co.vsl.sy.bbotutti` — BBO Tutti

### bboww

- `at.co.vsl.sy.bboww` — BBO Woodwinds

### brass

- `at.co.vsl.sy.brass.btb` — Synchron Brass - Bass trombone
- `at.co.vsl.sy.brass.cim` — Synchron Brass - Cimbasso
- `at.co.vsl.sy.brass.ho1` — Synchron Brass - Horn 1
- `at.co.vsl.sy.brass.ho12` — Synchron Brass - Horns-12
- `at.co.vsl.sy.brass.ho2` — Synchron Brass - Horn 2
- `at.co.vsl.sy.brass.ho6` — Synchron Brass - Horns-6
- `at.co.vsl.sy.brass.lb` — Synchron Brass - Low brass
- `at.co.vsl.sy.brass.tb4` — Synchron Brass - Tenor trombones-4
- `at.co.vsl.sy.brass.tb9` — Synchron Brass - Trombones-9
- `at.co.vsl.sy.brass.tp1` — Synchron Brass - Trumpet 1
- `at.co.vsl.sy.brass.tp2` — Synchron Brass - Trumpet 2
- `at.co.vsl.sy.brass.tp4` — Synchron Brass - Trumpets-4
- `at.co.vsl.sy.brass.tp6` — Synchron Brass - Trumpets-6
- `at.co.vsl.sy.brass.ttb` — Synchron Brass - Tenor trombone
- `at.co.vsl.sy.brass.tu` — Synchron Brass - Tuba

### chmbstr

- `at.co.vsl.sy.chmbstr` — SYNCHRON-ized Chamber Strings

### chmbstrmu

- `at.co.vsl.sy.chmbstrmu.db` — SYNCHRON-ized Chamber Double basses sordino
- `at.co.vsl.sy.chmbstrmu.va` — SYNCHRON-ized Chamber Violas sordino
- `at.co.vsl.sy.chmbstrmu.vc` — SYNCHRON-ized Chamber Violoncellos sordino
- `at.co.vsl.sy.chmbstrmu.vi` — SYNCHRON-ized Chamber Strings - sordino

### dimbrI

- `at.co.vsl.sy.dimbrI` — SYNCHRON-ized Dimension Brass I

### dimbrII

- `at.co.vsl.sy.dimbrII` — SYNCHRON-ized Dimension Brass II

### dimstrbonus

- `at.co.vsl.sy.dimstrbonus.db` — SYNCHRON-ized Dimension Strings Bonus - Double basses
- `at.co.vsl.sy.dimstrbonus.va` — SYNCHRON-ized Dimension Strings Bonus - Violas
- `at.co.vsl.sy.dimstrbonus.vc` — SYNCHRON-ized Dimension Strings Bonus - Violoncellos
- `at.co.vsl.sy.dimstrbonus.vi` — SYNCHRON-ized Dimension Strings Bonus - Violins

### dimstrI

- `at.co.vsl.sy.dimstrI.db` — SYNCHRON-ized Dimension Strings I - Double basses
- `at.co.vsl.sy.dimstrI.va` — SYNCHRON-ized Dimension Strings I - Violas
- `at.co.vsl.sy.dimstrI.vc` — SYNCHRON-ized Dimension Strings I - Cellos
- `at.co.vsl.sy.dimstrI.vi` — SYNCHRON-ized Dimension Strings I - Violins

### dimstrII

- `at.co.vsl.sy.dimstrII.db` — SYNCHRON-ized Dimension Strings II - Double basses
- `at.co.vsl.sy.dimstrII.va` — SYNCHRON-ized Dimension Strings II - Violas
- `at.co.vsl.sy.dimstrII.vc` — SYNCHRON-ized Dimension Strings II - Cellos
- `at.co.vsl.sy.dimstrII.vi` — SYNCHRON-ized Dimension Strings II - Violins

### dimstrIII

- `at.co.vsl.sy.dimstrIII.db` — SYNCHRON-ized Dimension Strings III - Double basses
- `at.co.vsl.sy.dimstrIII.va` — SYNCHRON-ized Dimension Strings III - Violas
- `at.co.vsl.sy.dimstrIII.vc` — SYNCHRON-ized Dimension Strings III - Cellos
- `at.co.vsl.sy.dimstrIII.vi` — SYNCHRON-ized Dimension Strings III - Violins

### harp

- `at.co.vsl.sy.harp` — Synchron Harp

### hps

- `at.co.vsl.sy.hps.harp1` — Synchron Harps - Harp 1
- `at.co.vsl.sy.hps.harp2` — Synchron Harps - Harp 2

### orchstr

- `at.co.vsl.sy.orchstr` — SYNCHRON-ized Orchestral Strings

### perc1

- `at.co.vsl.sy.perc1.bells` — Synchron Percussion I - Bells
- `at.co.vsl.sy.perc1.bonus` — Synchron Percussion I - Bonus
- `at.co.vsl.sy.perc1.cymbals` — Synchron Percussion I - Cymbals
- `at.co.vsl.sy.perc1.drums` — Synchron Percussion I - Bonus
- `at.co.vsl.sy.perc1.mallets` — Synchron Percussion I - 04 SY Mallets
- `at.co.vsl.sy.perc1.percussion` — Synchron Percussion I - 06 SY Percussion
- `at.co.vsl.sy.perc1.timpani` — Synchron Percussion I - Timpani

### perc2

- `at.co.vsl.sy.perc2.bells` — Synchron Percussion II - 05 SY Bells
- `at.co.vsl.sy.perc2.drums` — Synchron Percussion II - 02 SY Drums
- `at.co.vsl.sy.perc2.gongs` — Synchron Percussion II - 03 SY Cymbals - Gongs
- `at.co.vsl.sy.perc2.mallets` — Synchron Percussion II - 04 SY Mallets
- `at.co.vsl.sy.perc2.percussion` — Synchron Percussion II - 06 SY Orchestral Percussion
- `at.co.vsl.sy.perc2.timpani` — Synchron Percussion II - 01 SY Timpani

### perc3

- `at.co.vsl.sy.perc3.bells` — Synchron Percussion III - 05 SY Bells
- `at.co.vsl.sy.perc3.cymbals` — Synchron Percussion III - 03 SY Cymbals
- `at.co.vsl.sy.perc3.drums` — Synchron Percussion III - 02 SY Drums
- `at.co.vsl.sy.perc3.mallets` — Synchron Percussion III - 04 SY Mallets
- `at.co.vsl.sy.perc3.percussion` — Synchron Percussion III - 06 SY Orchestral Percussion
- `at.co.vsl.sy.perc3.timpani` — Synchron Percussion III - 01 SY Timpani

### pianos

- `at.co.vsl.sy.pianos.bechupr.pianocore` — This Bechstein upright piano was built in Berlin in the early 20th century. Always at home with families in the Stuttgart area, it is now owned by pianist and film composer Mick Baumeister, who is also the creator of the Hornberg breath controller. The piano's distinctive vintage character with a lot of resonating wood was captured at Synchron Stage Vienna's Stage B.
- `at.co.vsl.sy.pianos.bluethner.pianocore` — This BlÃ¼thner grand piano made in Leipzig in 1895 is a particularly glorious example of the legendary German piano manufacturer's âgolden toneâ. The beautifully refurbished instrument is equipped with BlÃ¼thner's patented Aliquot system that uses additional resonating strings in the treble register, resulting in a lyrical, warm and rich sound with lots of overtones.
- `at.co.vsl.sy.pianos.boes.pianocore` — This BÃ¶sendorfer Concert Grand 290 Imperial was captured at Stage A of Vienna Synchron Stage. Its extraordinary, orchestral sound is rich in expression and resonance, thanks to the enormous resonance board and the nine additional sub-bass notes, extending the instrumentâs key range downward to the low Câ for a total range of eight octaves.
- `at.co.vsl.sy.pianos.boesupr.pianocore` — The BÃ¶sendorfer Upright is a âmodern classicâ with a clear and uninhibited sound that lets you focus on your music. It comes with all the features that will make you pick an upright piano over a grand piano for your music, and our presets show the versatility of this powerful piano in its many facets. Recorded with utmost precision, the BÃ¶sendorfer Upright represents this specific category of pianos in the best way.
- `at.co.vsl.sy.pianos.boesvc.pianocore` — BÃ¶sendorfer's new and acclaimed \
- `at.co.vsl.sy.pianos.bosimpess.pianocore` — This BÃ¶sendorfer Concert Grand 290 Imperial was recorded on Stage A of Vienna Synchron Stage. Its nine additional sub-bass notes extend the instrumentâs range to a full eight octaves, down to the low Câ. The Essentials version captures all the expression and rich resonance of the original in a streamlined, efficient package.
- `at.co.vsl.sy.pianos.d274ess.pianocore` — The Steinway D-274, Hamburg Model, is a majestic instrument that meets the highest demands of musical expression and never ceases to amaze with its exhilarating performance. The extraordinary ability to seamlessly blend between all registers earned it the reputation as the choice of the worldâs greatest pianists, and the legendary recordings are amongst the most beautiful in music history.
- `at.co.vsl.sy.pianos.f212.pianocore` — Fazioliâs classic mid-size piano, the F212, was captured in the smaller, dryer Stage B of Synchron Stage Vienna. In the more intimate setting every nuance of its rich sound shines, from the powerful bass to the warm mid-range to the crisp upper registers. An extremely expressive piano, with rounded tones across the entire range.
- `at.co.vsl.sy.pianos.f308.pianocore` — With a length of 308 cm, the Fazioli F308 is the world's largest piano, owing its powerful sound and extraordinary harmonic clarity to the increased string length in the bass and middle range. It is equipped with a fourth pedal invented by Fazioli which lowers the keyboard and raises the hammers for a decrease in volume without changing the timbre.
- `at.co.vsl.sy.pianos.f308ess.pianocore` — As one of the largest pianos in the world, the Fazioli F308 is the crown jewel of Fazioliâs renowned concert grand series, esteemed for its warm, colorful, and sparkling sound. This Essentials version offers all the nuance and expressivity in a streamlined, efficient package.
- `at.co.vsl.sy.pianos.steinway.pianocore` — The Steinway D-274, Hamburg Model, is a majestic instrument that meets the highest demands of musical expression and never ceases to amaze with its exhilarating performance. The extraordinary ability to seamlessly blend between all registers earned it the reputation as the choice of the worldâs greatest pianists, and the legendary recordings are amongst the most beautiful in music history.
- `at.co.vsl.sy.pianos.steinwaylight.pianocore` — The Steinway D-274, Hamburg Model, is a majestic instrument that meets the highest demands of musical expression and never ceases to amaze with its exhilarating performance. The extraordinary ability to seamlessly blend between all registers earned it the reputation as the choice of the worldâs greatest pianists, and the legendary recordings are amongst the most beautiful in music history.
- `at.co.vsl.sy.pianos.studioconcertd.pianocore` — This early Steinway & Sons model D, serial no. 62523, is the only surviving concert grand of its kind. With nearly all original parts intact, including its hammerheads, it was carefully restored with just three replacements â strings, tuning pins, and bearing felts â to retain its authentic 1887 sound. Its duplex scale and varying string lengths for each note imbue the instrument with a truly singular voice.
- `at.co.vsl.sy.pianos.studioimperial.pianocore` — This BÃ¶sendorfer Concert Grand 290 Imperial was captured in the controlled acoustics of Vienna Symphonic Libraryâs Silent Stage. The elaborate positioning of microphones allowed for the sound to naturally evolve and spread while minimizing room characteristics. As a result, this piano is very flexible and can be placed easily in any virtual environment.
- `at.co.vsl.sy.pianos.yamaha.pianocore` — The Yamaha CFX concert grand offers a wide palette of expressive tonal colors, eliciting dramatic intensity and the most subtle nuances. Its distinctive sound can be characterized as precise, bright, clear, powerful and assertive, lending itself to any genre of classical, romantic and contemporary piano music and from solo pieces to chamber and concert works.
- `at.co.vsl.sy.pianos.yamahaess.pianocore` — Hand-crafted and full-sized at 275 cm (9'), the Yamaha CFX stands at the pinnacle of the Japanese manufacturerâs tradition of craftsmanship â bold, bright, and exceptionally expressive. Captured in the warm, natural acoustics of Vienna Synchron Stage, this Essentials edition delivers dramatic intensity and delicate nuance alike in a sleek, efficient form.

### powerdr

- `at.co.vsl.sy.powerdr.sonor` — Synchron Power Drums - Sonor
- `at.co.vsl.sy.powerdr.tamastar` — Synchron Power Drums - Tama Star
- `at.co.vsl.sy.powerdr.tamasuper` — Synchron Power Drums - Tama Superstar

### solostr1

- `at.co.vsl.sy.solostr1.db` — SYNCHRON-ized Solo Strings - Double bass
- `at.co.vsl.sy.solostr1.va` — SYNCHRON-ized Solo Strings - Viola
- `at.co.vsl.sy.solostr1.vc1` — SYNCHRON-ized Solo Strings - Violoncello 1
- `at.co.vsl.sy.solostr1.vc2` — SYNCHRON-ized Solo Strings - Violoncello 2
- `at.co.vsl.sy.solostr1.vi1` — SYNCHRON-ized Solo Strings - Violin 1
- `at.co.vsl.sy.solostr1.vi2` — SYNCHRON-ized Solo Strings - Violin 2

### solostrmu

- `at.co.vsl.sy.solostrmu.db` — SYNCHRON-ized Solo Strings muted - Double bass
- `at.co.vsl.sy.solostrmu.va` — SYNCHRON-ized Solo Strings muted - Viola
- `at.co.vsl.sy.solostrmu.vc` — SYNCHRON-ized Solo Strings muted - Violoncello
- `at.co.vsl.sy.solostrmu.vi` — SYNCHRON-ized Solo Strings muted - Violin

### specialbrass

- `at.co.vsl.sy.specialbrass.cim` — Cimbasso - Patches
- `at.co.vsl.sy.specialbrass.Horns8` — Horns a8 - Patches

### stringspro

- `at.co.vsl.sy.stringspro.basses` — Synchron Strings Pro - Double basses
- `at.co.vsl.sy.stringspro.cellos` — Synchron Strings Pro - Violoncellos
- `at.co.vsl.sy.stringspro.violas` — Synchron Strings Pro - Violas
- `at.co.vsl.sy.stringspro.violins1` — Synchron Strings Pro - 1st Violins
- `at.co.vsl.sy.stringspro.violins2` — Synchron Strings Pro - 2nd Violins

### studiobrass

- `at.co.vsl.sy.studiobrass.Horns4` — Horns a4 - Patches
- `at.co.vsl.sy.studiobrass.HornTri` — Triple horn - Patches
- `at.co.vsl.sy.studiobrass.HornVien` — Viennese horn - Patches
- `at.co.vsl.sy.studiobrass.tpc` — Trumpet in C - Patches
- `at.co.vsl.sy.studiobrass.TrbBass` — Bass trombone - Patches
- `at.co.vsl.sy.studiobrass.Trbs3` — Trombones a3 - Patches
- `at.co.vsl.sy.studiobrass.TrbTen` — Tenor trombone - Patches
- `at.co.vsl.sy.studiobrass.Trp3` — Trumpets a3 - Patches
- `at.co.vsl.sy.studiobrass.TrpB` — Trumpet in Bb - Patches
- `at.co.vsl.sy.studiobrass.tuba` — Tuba - Patches

### syels

- `at.co.vsl.sy.syels.db` — Synchron Elite Strings - Double basses
- `at.co.vsl.sy.syels.va` — Synchron Elite Strings - Violas
- `at.co.vsl.sy.syels.vc` — Synchron Elite Strings - Violoncellos
- `at.co.vsl.sy.syels.vi1` — Synchron Elite Strings - 1st Violins
- `at.co.vsl.sy.syels.vi2` — Synchron Elite Strings - 2nd Violins

### sysolostr

- `at.co.vsl.sy.sysolostr.va` — Synchron Solo Viola
- `at.co.vsl.sy.sysolostr.vc` — Synchron Solo Strings - Violoncello
- `at.co.vsl.sy.sysolostr.vi` — Synchron Solo Strings - Violin - Patches
- `at.co.vsl.sy.sysolostr.vi2` — Synchron Solo Strings - Violin 2 

### syww

- `at.co.vsl.sy.syww.afl` — Synchron Woodwinds - Alto flute
- `at.co.vsl.sy.syww.ba1` — Synchron Woodwinds - Bassoon 1
- `at.co.vsl.sy.syww.ba2` — Synchron Woodwinds - Bassoon 2
- `at.co.vsl.sy.syww.bcl` — Synchron Woodwinds - Bass clarinet
- `at.co.vsl.sy.syww.cba` — Synchron Woodwinds - Contrabassoon
- `at.co.vsl.sy.syww.cl1` — Synchron Woodwinds - Clarinet 1
- `at.co.vsl.sy.syww.cl2` — Synchron Woodwinds - Clarinet 2
- `at.co.vsl.sy.syww.eh` — Synchron Woodwinds - English horn
- `at.co.vsl.sy.syww.ens` — Synchron Woodwinds - Ensembles
- `at.co.vsl.sy.syww.fl1` — Synchron Woodwinds - Flute 1
- `at.co.vsl.sy.syww.fl2` — Synchron Woodwinds - Flute 2
- `at.co.vsl.sy.syww.fxhigh` — Synchron Woodwinds - Effects High
- `at.co.vsl.sy.syww.fxlow` — Synchron Woodwinds - Effects Low
- `at.co.vsl.sy.syww.ob1` — Synchron Woodwinds - Oboe 1
- `at.co.vsl.sy.syww.ob2` — Synchron Woodwinds - Oboe 2
- `at.co.vsl.sy.syww.pfl` — Synchron Woodwinds - Piccolo Flute
- `at.co.vsl.sy.syww.tutti` — Synchron Woodwinds - Tutti

### vbc

- `at.co.vsl.sy.vbc` — Vienna Boys Choir

### vchoir

- `at.co.vsl.sy.vchoir` — SYNCHRON-ized Vienna Choir

### worldw

- `at.co.vsl.sy.worldw.dud` — Synchron World Winds - Duduks

### ww

- `at.co.vsl.sy.ww` — SYNCHRON-ized Woodwinds


