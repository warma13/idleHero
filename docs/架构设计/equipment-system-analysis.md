# 装备掉落、获取与自动分解系统分析

## 1. 系统架构总览

```
击杀敌人                         关卡通关
  │                                │
  ▼                                ▼
StageManager.OnEnemyKilled()     StageManager.NextWave()
  │                                │
  ├─ 判断掉落概率                   ├─ 保底装备(guaranteeEquipQuality)
  ├─ GenerateEquip(wave, isBoss)   ├─ GenerateEquip(wave) + 重试循环
  ▼                                ▼
Loot.Spawn()                     AddToInventory(equip, true) ← 跳过自动分解
  │
  ├─ 散落物理 (0.5~1s)
  ├─ 磁吸拾取 (2s延迟后全屏吸)
  ▼
Loot.Collect()
  │
  ▼
AddToInventory(item)
  │
  ├─ autoDecomposeLevel 检查
  │   ├─ 符合 → 直接分解为金币+强化石
  │   └─ 不符合 → 加入背包
  └─ 背包满 → return false (物品丢弃)
```

**涉及文件**:
| 文件 | 职责 |
|------|------|
| `Config.lua` | 品质权重、词条数值、套装定义、Tier公式 |
| `state/Equipment.lua` | 装备生成、背包管理、分解、升级 |
| `battle/StageManager.lua` | 击杀掉落、关卡保底、波次管理 |
| `battle/Loot.lua` | 掉落物生成、散落物理、磁吸拾取、地面上限 |
| `state/StatCalc.lua` | 属性计算、装备战力评估 |

---

## 2. 装备生成流水线 (GenerateEquip)

### 2.1 品质抽取

**基础权重**:

| 品质 | 权重 | 基础概率 | qualityMul | 副词条数 | 可升级 | 可套装 |
|------|------|----------|------------|----------|--------|--------|
| 白色 | 50 | 50.0% | 1.0x | 0 | 不可 | 否 |
| 绿色 | 30 | 30.0% | 1.5x | 1 | Lv.5 | 否 |
| 蓝色 | 15 | 15.0% | 2.0x | 2 | Lv.10 | 是 |
| 紫色 | 4 | 4.0% | 3.0x | 3 | Lv.15 | 是 |
| 橙色 | 1 | 1.0% | 5.0x | 4 | Lv.20 | 是 |

**幸运值修正** (luck 影响权重):
```lua
-- 白/绿: 权重 × max(0.3, 1 - luck)    → luck越高, 白绿越少
-- 蓝:    权重 × (1 + luck × 1)         → luck越高, 蓝越多
-- 紫:    权重 × (1 + luck × 2)         → luck越高, 紫越多
-- 橙:    权重 × (1 + luck × 3)         → luck越高, 橙越多
```

**小怪降权乘数** (`mobMul`):
```
白色: ×1.0    (不变)
绿色: ×1.0    (不变)
蓝色: ×0.054  (极大降低)
紫色: ×0.02   (极大降低)
橙色: ×0.008  (极大降低)
```

**实际概率计算 (luck=0, Boss)**:

| 品质 | 权重 | 概率 |
|------|------|------|
| 白色 | 50 | 50.0% |
| 绿色 | 30 | 30.0% |
| 蓝色 | 15 | 15.0% |
| 紫色 | 4 | 4.0% |
| 橙色 | 1 | 1.0% |

**实际概率计算 (luck=0, 小怪)**:

| 品质 | 权重 | 概率 |
|------|------|------|
| 白色 | 50 | 61.05% |
| 绿色 | 30 | 36.63% |
| 蓝色 | 15×0.054=0.81 | 0.99% |
| 紫色 | 4×0.02=0.08 | 0.098% |
| 橙色 | 1×0.008=0.008 | 0.0098% |

**实际概率计算 (luck=0.5, Boss)**:

| 品质 | 权重 | 概率 |
|------|------|------|
| 白色 | 50×0.5=25 | 30.49% |
| 绿色 | 30×0.5=15 | 18.29% |
| 蓝色 | 15×1.5=22.5 | 27.44% |
| 紫色 | 4×2.0=8 | 9.76% |
| 橙色 | 1×2.5=2.5 | 3.05% |

### 2.2 章节Tier系数

```lua
tierMul = 3^(chapter - 1)
```

| 章节 | tierMul | 含义 |
|------|---------|------|
| 1 | 1 | 基准 |
| 2 | 3 | 词条×3 |
| 3 | 9 | 词条×9 |
| 4 | 27 | 词条×27 |
| 5 | 81 | 词条×81 |

**所有词条值(主/副)都乘以 tierMul**，形成跨章节换装驱动。

### 2.3 主词条生成

```
mainValue = stat.base × stat.mainMul × quality.qualityMul × tierMul
```

示例: 武器主词条 `atk`, 紫色品质, 第2章:
```
mainValue = 0.3 × 20 × 3.0 × 3.0 = 54.0
```

### 2.4 副词条生成

```
subValue = stat.base × random(0.8, 1.0) × tierMul
```

- 使用 Fisher-Yates 洗牌从 `slotCfg.subPool` 随机不重复抽取
- 副词条 **可以** 与主词条同key (代码中标注: "同件可与主词条重复")
- 副词条数量由品质决定: 0/1/2/3/4

### 2.5 套装分配

- 蓝色及以上 (`canHaveSet = true`) 有 **50%** 概率获得套装标签
- 套装来源: 当前章节及之前章节解锁的所有套装
- 每章解锁2个套装, 共5章10套

### 2.6 武器元素

仅武器槽(`hasElement = true`)生成元素属性:

| 品质 | 物理 | 火 | 冰 | 毒 | 水 | 奥 |
|------|------|------|------|------|------|------|
| 白色 | 50% | 10% | 10% | 10% | 10% | 10% |
| 绿色 | 30% | 14% | 14% | 14% | 14% | 14% |
| 蓝色 | 15% | 17% | 17% | 17% | 17% | 17% |
| 紫色 | 5% | 19% | 19% | 19% | 19% | 19% |
| 橙色 | 0% | 20% | 20% | 20% | 20% | 20% |

---

## 3. 掉落触发机制

### 3.1 击杀掉落 (OnEnemyKilled)

| 掉落类型 | Boss | 小怪 |
|----------|------|------|
| 经验值 | 100% | 100% |
| 金币 | 100% | 30% |
| 装备 | 100% | 15% + luck×50% |
| 魂晶 | 每次1个 | 不掉 |

**金币量**: `baseGold × (1 + luck)`, 范围 `[goldMin, goldMax]`

**装备掉落概率**: 小怪在 luck=0.5 时为 40%, luck=1.0 时为 65%

### 3.2 关卡通关保底 (NextWave)

部分关卡配置 `reward.guaranteeEquipQuality`, 通关时保底一件指定品质装备:
1. 先正常 `GenerateEquip()` 生成一件装备
2. 如果品质低于保底值, 最多重试 20 次
3. 20次后仍不达标 → **强制覆盖** 品质(见下方问题分析)
4. 通关装备调用 `AddToInventory(equip, true)` **跳过自动分解**

---

## 4. 掉落物管理 (Loot)

### 4.1 散落物理

- 初始散射速度: 100~200 像素/秒, 随机方向
- 摩擦衰减: `exp(-2.0 × dt)`, 约0.5秒停止
- 散落阶段不触发磁吸

### 4.2 磁吸拾取

- 进入 `pickupRadius` 范围 → 立即吸引
- 存在超过 `ABSORB_DELAY`(2秒) → 全屏吸引
- 吸引速度: `300 + (200 - dist) × 3`, 距离越近越快
- 到达距离 < 12 像素时收集

### 4.3 地面装备上限

- `MAX_GROUND_EQUIPS = 100`
- 背包满时触发上限检查
- 超出时按品质升序 + 掉落时间升序移除(低品质旧装备优先删除)

---

## 5. 自动分解系统

### 5.1 机制

```lua
-- AddToInventory() 中:
if adl > 0 and item.qualityIdx <= adl and not item.locked then
    → 直接分解为金币 + 强化石, 不进背包
end
```

- `autoDecomposeLevel`: 0=关闭, 1=白, 2=绿, 3=蓝, 4=紫, 5=全部
- 锁定装备(`locked = true`)不会被自动分解
- 关卡保底装备传 `skipAutoDecomp = true`, 不受自动分解影响

### 5.2 自动分解收益

```lua
gold   = max(1, floor(ItemPower(item) × 3 + qualityIdx × 15))
stones = DECOMPOSE_STONES[qualityIdx]  -- {0, 1, 2, 4, 8}
```

| 品质 | 强化石 | 金币(约) |
|------|--------|----------|
| 白色 | 0 | 15~20 |
| 绿色 | 1 | 45~70 |
| 蓝色 | 2 | 80~120 |
| 紫色 | 4 | 150~250 |
| 橙色 | 8 | 300~500+ |

### 5.3 手动分解

- `DecomposeItem(invIndex)`: 分解单件, 已升级装备额外返还 `upgradeStonesSpent × 0.8`
- `DecomposeByFilter(maxQuality, keepSets)`: 批量分解指定品质及以下, 可选保留套装
- `DecomposeAllWhite()`: 分解全部白色(已被 DecomposeByFilter 覆盖)

---

## 6. 装备升级系统

### 6.1 升级规则

| 品质 | 最大等级 | 副词条提升次数(每5级一次) |
|------|---------|--------------------------|
| 白色 | 0 (不可升级) | 0 |
| 绿色 | 5 | 1次 |
| 蓝色 | 10 | 2次 |
| 紫色 | 15 | 3次 |
| 橙色 | 20 | 4次 |

### 6.2 升级效果

- **主词条**: `mainValue = baseMainValue × (1 + level × 0.05)`
  - 橙色满级: 主词条翻倍 (1 + 20 × 0.05 = 2.0)
- **副词条**: 每5级随机一条副词条 `+= baseValue × 0.5`
- **消耗**: `UpgradeCost(level, chapter) = max(2, floor(2 + lv×1.2 + lv²×0.06)) × chapter`

### 6.3 分解返还

已升级装备分解时返还:
```
额外强化石 = floor(upgradeStonesSpent × 0.8)
```

---

## 7. 错误与问题分析

### 7.1 [严重] 关卡保底装备覆盖缺少 tierMul

**位置**: `StageManager.lua` → `NextWave()` → 保底装备强制覆盖逻辑

**问题描述**: 当重试20次后仍未达到保底品质时, 强制覆盖品质后重新计算主词条:

```lua
equip.mainValue = mainDef.base * mainDef.mainMul * q.qualityMul
-- 缺少 × tierMul !
```

而正常的 `GenerateEquip()` 中:
```lua
local mainValue = mainStatDef.base * mainStatDef.mainMul * quality.qualityMul * tierMul
```

**影响**: 在第2章及以后, 保底装备的主词条数值会缺失 tierMul 乘数, 导致保底装备(本应为奖励)反而比正常掉落弱得多。例如第3章保底紫装主词条只有正常值的 1/9。

**修复**: 覆盖主词条时乘以 tierMul:
```lua
equip.mainValue = mainDef.base * mainDef.mainMul * q.qualityMul * tierMul
```

**严重度**: 🔴 高 — 直接影响玩家体验, 保底奖励弱于普通掉落

---

### 7.2 [严重] 保底装备覆盖后副词条也缺少 tierMul

**位置**: `StageManager.lua` → 保底品质覆盖 → 填充副词条

```lua
local subVal = subDef.base * (0.8 + math.random() * 0.2)
-- 缺少 × tierMul !
```

正常 `GenerateEquip()`:
```lua
local subVal = subDef.base * (0.8 + math.random() * 0.2) * tierMul
```

**影响**: 与 7.1 相同, 保底装备的新增副词条也缺失 tierMul。

**严重度**: 🔴 高

---

### 7.3 [中等] 保底覆盖的 isBoss 参数缺失

**位置**: `StageManager.lua` → `NextWave()`:

```lua
local equip = GameState.GenerateEquip(gs.chapter * 10 + gs.stage)
-- 未传递 isBoss 参数, 默认 nil → 视为小怪
```

**影响**: 关卡保底装备使用小怪的品质降权(`mobMul`), 大幅降低蓝紫橙概率, 导致几乎必然触发20次重试上限, 然后走强制覆盖路径(而强制覆盖路径有 7.1/7.2 的 tierMul 缺失问题)。

**修复**: 保底装备应使用 Boss 权重:
```lua
local equip = GameState.GenerateEquip(gs.chapter * 10 + gs.stage, true)
```

**严重度**: 🟡 中 — 不直接影响结果(因为有强制覆盖), 但浪费了20次重试的CPU开销, 且与强制覆盖bug联动放大了问题。

---

### 7.4 [中等] 地面装备清理排序索引稳定性问题

**位置**: `Loot.lua` → `EnforceGroundEquipCap()`:

```lua
table.sort(equipIndices, function(a, b)
    local qa = loots[a].value and loots[a].value.qualityIdx or 0
    local qb = loots[b].value and loots[b].value.qualityIdx or 0
    if qa ~= qb then return qa < qb end
    return a < b
end)
```

排序后按 `removeSet` 集合倒序删除:
```lua
for i = #loots, 1, -1 do
    if removeSet[i] then
        table.remove(loots, i)
    end
end
```

**问题**: `table.sort` 中使用的索引 `a`, `b` 是 `equipIndices` 数组中存储的原始 loots 索引。排序本身逻辑正确。但 `table.remove` 是 O(n) 操作, 循环中对所有 loots 倒序检查效率偏低(每次remove都移动后续元素)。当 MAX_GROUND_EQUIPS=100 且超出量较大时, 性能不是最优。

**严重度**: 🟢 低 — 功能正确, 仅性能微优化

---

### 7.5 [中等] elemDmg 主词条的 mainMul 过低

**位置**: `Config.lua`:

```lua
elemDmg = { name = "全元素增伤", base = 0.0005, mainMul = 4, ... }
-- 其他主词条 mainMul = 20
```

**问题分析**: `elemDmg` 的 `mainMul` 只有 4, 其他主词条都是 20。

主词条数值 = `base × mainMul × qualityMul × tierMul`

| 词条 | base | mainMul | 白色主值 | 橙色主值 |
|------|------|---------|---------|---------|
| atk | 0.3 | 20 | 6.0 | 30.0 |
| elemDmg | 0.0005 | 4 | 0.002 (0.2%) | 0.01 (1.0%) |
| fireDmg | 0.0025 | 20 | 0.05 (5%) | 0.25 (25%) |

而 `elemDmg` 在生成时会被 `resolveElemDmg()` 转换为随机具体元素:

```lua
local function resolveElemDmg(statKey)
    if statKey == "elemDmg" then
        local pool = Config.ELEM_DMG_STATS  -- {"fireDmg","iceDmg",...}
        return pool[math.random(1, #pool)]
    end
    return statKey
end
```

所以当主词条池抽到 `elemDmg` 时, 实际用的是具体元素的 stat(如 `fireDmg`), 而 `fireDmg` 的 `mainMul = 20` 和 `base = 0.0025`。

**结论**: `elemDmg` 的 `mainMul = 4` 只影响作为**副词条**时的 `equipSum("elemDmg")` 和 `GetElemDmg()` 中的全元素增伤分支。它被设计为全元素通用增伤, 数值偏低是**有意为之**(否则全元素增伤 + 特定元素增伤叠加太强)。

**严重度**: 🟢 低 — 设计合理, 但建议在代码注释中明确说明

---

### 7.6 [低] 副词条可能与主词条重复

**位置**: `Equipment.lua` → `GenerateEquip()`:

代码注释写道: "同件可与主词条重复"。

```lua
-- 副词条从 subPool 抽取, 而 resolveElemDmg 可能产生与主词条相同的 key
```

**影响**: 当主词条和副词条都是同一属性(如 `fireDmg`)时, 两者数值都会叠加到 `equipSum()`, 功能上不会出错。但从游戏设计角度, 玩家可能觉得困惑("为什么同一属性出现两次?")。

**严重度**: 🟢 低 — 这是有意设计, 在很多 RPG 中是常见做法

---

### 7.7 [中等] 背包满时装备拾取静默丢弃

**位置**: `Equipment.lua` → `AddToInventory()`:

```lua
if #GameState.inventory >= GameState.GetInventorySize() then
    return false
end
```

`Loot.Collect()` 调用 `AddToInventory()` 后没有检查返回值:

```lua
-- Loot.Collect:
elseif loot.type == "equip" then
    GameState.AddToInventory(loot.value)
    SaveSystem.MarkDirty()
```

**问题**: 虽然 `Loot.Update()` 中已有磁吸阶段的背包满检查(`canAttract = false`), 但存在时序边界:
1. 磁吸开始时背包未满 → `canAttract = true`
2. 磁吸飞行过程中其他装备先进包 → 背包满了
3. 到达玩家时 `Collect()` 调用 `AddToInventory()` → return false
4. 装备从 loots 表中移除, 但没有进入背包 → **装备丢失**

而且即使未丢失, 也没有任何 UI 提示告知玩家"背包已满"。

**修复建议**: `Loot.Collect()` 中检查返回值, 若失败则不从 loots 中移除, 或弹出提示。

**严重度**: 🟡 中 — 特定时序下装备丢失, 且无提示

---

### 7.8 [低] 自动分解不返回魂晶

**位置**: `Equipment.lua` → `AddToInventory()` 自动分解分支:

```lua
local gold = math.max(1, math.floor(GameState.ItemPower(item) * 3 + item.qualityIdx * 15))
local stones = Config.DECOMPOSE_STONES[item.qualityIdx] or 1
GameState.AddGold(gold)
GameState.AddStone(stones)
```

而手动 `DecomposeItem()` 也只返回金币和强化石。两者逻辑一致。

但如果未来加入"分解返还魂晶"的机制, 需要同步更新两处。当前不是 bug。

**严重度**: 🟢 低 — 当前一致, 仅为维护提醒

---

## 8. 优化建议

### 8.1 [P0] 修复保底装备 tierMul 缺失

**优先级**: 立即修复

将 `StageManager.lua` 的保底覆盖逻辑补充 tierMul:

```lua
-- 在保底覆盖分支开头获取 tierMul
local tierMul = Config.GetChapterTier(GameState.stage.chapter)

-- 修复主词条
equip.mainValue = mainDef.base * mainDef.mainMul * q.qualityMul * tierMul

-- 修复副词条
local subVal = subDef.base * (0.8 + math.random() * 0.2) * tierMul
```

同时传递 `isBoss = true` 给保底生成:
```lua
local equip = GameState.GenerateEquip(gs.chapter * 10 + gs.stage, true)
```

---

### 8.2 [P1] 装备拾取失败处理

在 `Loot.Collect()` 中:
```lua
elseif loot.type == "equip" then
    local ok = GameState.AddToInventory(loot.value)
    if ok then
        SaveSystem.MarkDirty()
    else
        -- 背包满, 不收集, 返回 false 让 Update 保留掉落物
        return false
    end
```

在 `Loot.Update()` 中:
```lua
if dist < 12 then
    local ok = Loot.Collect(loot)
    if ok ~= false then
        table.remove(loots, i)
    else
        loot.attracted = false  -- 取消吸引, 落回地面
    end
end
```

---

### 8.3 [P1] 保底装备重构: 提取为独立函数

当前保底覆盖逻辑嵌在 `NextWave()` 中, 约60行, 可读性差。建议提取为:

```lua
--- 生成保底品质装备
--- @param minQuality number 最低品质索引
--- @param chapter number 当前章节
--- @return table equip
local function GenerateGuaranteedEquip(minQuality, chapter)
    local equip = GameState.GenerateEquip(chapter * 10, true)
    local attempts = 0
    while equip.qualityIdx < minQuality and attempts < 20 do
        equip = GameState.GenerateEquip(chapter * 10, true)
        attempts = attempts + 1
    end
    if equip.qualityIdx < minQuality then
        -- 强制提升品质并重新计算所有数值
        OverrideEquipQuality(equip, minQuality, chapter)
    end
    return equip
end
```

---

### 8.4 [P2] 自动分解收益显示

自动分解是静默进行的, 玩家不知道获得了什么。建议:
1. 累积一个批次的自动分解结果 (金币、强化石、件数)
2. 在战斗结算或定期弹出汇总 Toast: "自动分解 12 件装备, 获得 450 金币 + 15 强化石"

---

### 8.5 [P2] 掉落概率曲线平衡

**当前小怪装备掉落概率过低**:
- luck=0 时: 蓝色 0.99%, 紫色 0.098%, 橙色 0.0098%
- 考虑掉落触发率(15%), 实际每次击杀小怪获得蓝装概率: 0.15%
- 获得紫装: 0.015%, 获得橙装: 0.0015%

这意味着平均需要击杀 **67,000 只小怪** 才能从小怪掉落获得一件橙色装备。

**建议**: 
- 如果设计意图是"橙装只从Boss获得", 则mobMul合理
- 如果希望小怪也有微小概率掉橙装, 当前概率过低, 可调整 `mobMul[5]` 从 0.008 到 0.05

---

### 8.6 [P2] 套装掉落概率优化

当前所有可用套装等概率被选中。随着章节推进, 套装池越来越大:
- 第1章: 2个套装, 各50%
- 第3章: 6个套装, 各16.7%
- 第5章: 10个套装, 各10%

**问题**: 玩家在第5章想凑第5章的新套装(沧溟之怒/潮汐壁垒), 但实际获得概率只有 10% × 50%(套装触发) = 5%。

**建议**: 增加当前章节套装的权重偏向, 如:
- 当前章节套装: 权重 3
- 之前章节套装: 权重 1

---

### 8.7 [P3] 升级石经济平衡检查

| 章节 | 橙装满级(Lv.20)总消耗 | 分解返还 |
|------|----------------------|----------|
| 1 | ~166 强化石 | ~133 (80%) |
| 3 | ~498 强化石 | ~398 |
| 5 | ~830 强化石 | ~664 |

而白装分解给 0 石, 绿色给 1, 蓝色给 2。高章节的升级成本可能过高, 需要关注强化石的产出/消耗平衡。

---

## 9. 系统数据流总结

```
┌──────────────────────────────────────────────────────────┐
│                     Config.lua (配置层)                    │
│  品质权重 → mobMul → 幸运修正 → tierMul → 套装 → 元素     │
└─────────────────────────┬────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│              Equipment.GenerateEquip() (生成层)           │
│  品质roll → 槽位 → 主词条 → 副词条 → 套装 → 武器元素      │
└─────────────────────────┬────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              ▼                       ▼
┌─────────────────────┐   ┌─────────────────────┐
│ StageManager (触发层) │   │ Loot.lua (物理层)    │
│ 击杀概率/保底品质      │   │ 散落/磁吸/地面上限    │
└──────────┬──────────┘   └──────────┬──────────┘
           │                         │
           └────────────┬────────────┘
                        ▼
┌──────────────────────────────────────────────────────────┐
│              AddToInventory() (入包层)                     │
│  autoDecompose check → 背包容量 check → 入包/分解          │
└──────────────────────────────────────────────────────────┘
```

---

## 10. 总结

| 类别 | 数量 | 说明 |
|------|------|------|
| 🔴 严重Bug | 2 | 保底装备 tierMul 缺失(主词条+副词条) |
| 🟡 中等问题 | 3 | isBoss参数缺失、拾取丢弃、地面清理性能 |
| 🟢 低级问题 | 3 | 词条重复、分解一致性、elemDmg mainMul |
| 优化建议 | 7 | P0×1, P1×2, P2×3, P3×1 |

**最紧急修复**: 保底装备 tierMul 缺失 (7.1 + 7.2 + 7.3), 这直接导致关卡奖励装备在第2章以后严重弱于正常掉落。
