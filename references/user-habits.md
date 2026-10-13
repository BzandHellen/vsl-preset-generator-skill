# 用户习惯 / 偏好（VSL & 通用）

> 这个文件记录用户的工作习惯，生成预设、写脚本、给建议时**默认遵循**。新习惯直接往下追加。

## VSL Synchron Player

### 维度 / 技法切换（控制器分配）
- **技法（articulation）切换：CC58**，**每 8 个值一档**。
  - N 个技法时第 i 档（i 从 0）：`i < N-1` → `[8i, 8i+7]`；最后一档 → `[8(N-1), 127]`。
  - 例：3 技法 = `0–7` / `8–15` / `16–127`；4 技法 = `0–7` / `8–15` / `16–23` / `24–127`；2 技法 = `0–7` / `8–127`。
- **揉弦（vibrato）与震音（tremolo）切换：CC21**。
- **颤音（Trill）WT/HT + 短音系列（分弓 détaché、stac、spic、pizz 等）切换：CC4**。
- 落地到预设 JSON：对应维度节点的 `switchControl` 字段。
  编码疑似 **`256 + CC 号`**：
  - `CC4 → 260`、`CC21 → 277`、`CC58 → 314`
  - **旁证**：Strings Pro factory 预设顶层的 Articulation 维度就是 `switchControl = 260`（=CC4），与上面的推断吻合。
  - 仍建议在播放器 CONTROL 页核对一次再作为脚本默认值。

### 短音：力度触发采样层
- 短音（stac / spic / détaché / pizz 等）用**力度触发采样层切换**，即 `velXFadeMode = 1`（按力度分层切换），
  而不是连续交叉淡化。
- 旁证：用户自己的 Strings Pro 预设里，Short / Pizzicato 系列的槽就是 `velXFadeMode: 1`，其余长音/连奏为 `0`。

### 麦克风（混音）
- **只启用 Close 和 Main 两个麦位**（其余麦位关闭）。
- **只有 Close 麦需要摆位**（position / power pan 等）；Main 保持默认、不做摆位。

### 预设命名规则
- 沿用用户自己的一套命名：`<前缀> <声部简称> a<人数>`
  - `STR Synchron Vln1 a14`、`STR Synchron Vln2 a10`、`STR Synchron Vla a8`、
    `STR Synchron Vc a8`、`STR Synchron DB a6`
  - 合奏 / 全奏：`STR Synchron Tutti`
- 声部简称固定用：`Vln1` / `Vln2` / `Vla` / `Vc` / `DB`（对应 1st Violins / 2nd Violins / Violas / Cellos / Double basses）。
- 前缀按库/系列取（Strings 用 `STR`）；文件名与预设内部 `currentPreset` 路径保持一致，放在
  `…\Vienna Synchron Player\Presets\<分类>\` 下。

---

## 生成预设时默认套用（checklist）
1. 技法维度 `switchControl` = CC58（314），每 8 值一档。
2. 揉弦/震音维度 = CC21（277）；颤音+短音维度 = CC4（260）。
3. 短音槽 `velXFadeMode = 1`；长音/连奏 `= 0`。
4. 命名遵循 `<前缀> <声部简称> a<人数>`，`currentPreset` 与文件名一致。
5. （播放器内）只开 Close + Main 麦，仅 Close 摆位。
