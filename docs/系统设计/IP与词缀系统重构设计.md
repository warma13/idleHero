# P2 装备全词缀化 + Item Power 重构设计

> **核心思想**: 废除 mainStat / subStats / tierMul，所有属性统一为**词缀 (Affix)**，IP 是唯一数值驱动。  
> **对标**: 暗黑 4 S12 — IP 决定词缀 roll 范围，无独立 tier 缩放  
> **前置**: P0 怪物家族 ✅, P1 属性系统 ✅  
> **后续**: P3 技能系统

---

## 1. 现状与改造目标

### 1.1 现状 (要被废除的结构)

```lua
{
    slot, qualityIdx, tier, tierMul,     -- ← tier/tierMul 废除
    mainStat = "atk",                    -- ← 废除
    mainValue = 150.0,                   -- ← 废除
    subStats = { ... },                  -- ← 废除
    affixes = { { id = "combo_strike", enhanced = true } },
    setId, element, sockets, gems, upgradeLv, baseMainValue,
}
```

**痛点**:
- tierMul 是隐藏的数值放大器，玩家看不懂，设计上也不透明
- 主副词条 + tierMul 三层结构过于复杂
- 8 个 proc 词缀池太小
- ch16 的 tierMul ≈ 60，但 ch16 远不是毕业

### 1.2 改造目标

```lua
-- 新结构: IP 驱动一切
{
    slot, qualityIdx,
    itemPower = 480,              -- ★ 唯一数值驱动 (取代 tier + tierMul + qualityMul)
    affixes = {                   -- ★ 唯一属性载体 (取代 mainStat + subStats + affixes)
        { id = "atk",           value = 150.0, greater = false },
        { id = "crit",          value = 0.015, greater = false },
        { id = "combo_strike",  value = 0.22,  greater = true  },  -- ★ 大词缀
    },
    setId, element, sockets, gems, upgradeLv,
}
```

**废除字段一览**:

| 旧字段 | 处理 |
|--------|------|
| `tier` | **删除** — IP 已包含章节进度信息 |
| `tierMul` | **删除** — IP 取代其缩放功能 |
| `mainStat` / `mainValue` / `baseMainValue` | **删除** — 对应属性变为词缀 |
| `subStats[]` | **删除** — 对应属性变为词缀 |
| `affixes[].enhanced` | 改为 `affixes[].greater` (bool) |

---

## 2. Item Power 系统 (核心变更)

### 2.1 设计理念

D4 的 IP 是装备强度的**唯一标尺**:
- 高 IP = 高数值词缀 (通过 roll 范围)
- 无独立 tier 缩放层 — IP 本身就编码了章节进度
- 品质影响词缀数量和 IP 系数，而非独立的 qualityMul 倍率

### 2.2 IP 公式

```lua
-- baseIP: 章节决定的基础 IP
-- 对数增长, ch1=100, ch16≈568, ch50≈787, ch100=925
Config.CalcBaseIP = function(chapter)
    if chapter <= 1 then return 100 end
    return math.floor(100 + 825 * math.log(chapter) / math.log(100))
end

-- 最终 IP = baseIP × 品质系数 + 升级加成
Config.IP_QUALITY_MUL = { 0.50, 0.65, 0.80, 0.90, 1.00 }  -- 白/绿/蓝/紫/橙
Config.IP_PER_UPGRADE = 5

-- itemPower = floor(baseIP × qualityMul) + upgradeLv × 5
```

**IP 参考表**:

| 章节 | baseIP | 白(×0.5) | 绿(×0.65) | 蓝(×0.8) | 紫(×0.9) | 橙(×1.0) | 橙+20 |
|------|--------|---------|----------|---------|---------|---------|-------|
| 1 | 100 | 50 | 65 | 80 | 90 | 100 | 200 |
| 5 | 413 | 206 | 268 | 330 | 371 | 413 | 513 |
| 10 | 513 | 256 | 333 | 410 | 461 | 513 | 613 |
| 16 | 568 | 284 | 369 | 454 | 511 | 568 | 668 |
| 25 | 618 | 309 | 401 | 494 | 556 | 618 | 718 |
| 50 | 700 | 350 | 455 | 560 | 630 | 700 | 800 |
| 100 | 925 | 462 | 601 | 740 | 832 | 925 | 1025 |

**关键**: ch16 橙装 IP=568，还有巨大提升空间 (925 才是 ch100 毕业级)。

### 2.3 IP 驱动词缀数值

每条词缀定义一个 `base` 值 (IP=100 时的参考值) 和一个 `ipScale` 系数:

```lua
-- 词缀值 = base × ipFactor × roll
-- ipFactor = 1 + (IP/100 - 1) × ipScale

-- ipScale 决定 IP 对这条词缀的影响程度:
--   ipScale = 1.0 → 绝对值属性 (atk/hp/def), IP 线性放大
--   ipScale = 0.15 → 百分比属性 (crit/critDmg), IP 缓慢提升
--   ipScale = 0.05 → proc 属性 (combo_strike), 几乎不随 IP 变化
```

**示例** (atk, base=40, ipScale=1.0):
- IP=100: ipFactor=1.0, roll×40 → 可得 12~40
- IP=500: ipFactor=5.0, roll×200 → 可得 60~200
- IP=925: ipFactor=9.25, roll×370 → 可得 111~370

**示例** (crit, base=0.04, ipScale=0.15):
- IP=100: ipFactor=1.0, roll×0.04 → 0.012~0.04 (1.2%~4%)
- IP=500: ipFactor=1.6, roll×0.064 → 0.019~0.064 (1.9%~6.4%)
- IP=925: ipFactor=2.24, roll×0.089 → 0.027~0.089 (2.7%~8.9%)

### 2.4 Roll 范围 (IP 区间)

```lua
Config.IP_BRACKETS = {
    { maxIP = 150,  minRoll = 0.30, maxRoll = 0.50 },
    { maxIP = 300,  minRoll = 0.40, maxRoll = 0.65 },
    { maxIP = 500,  minRoll = 0.50, maxRoll = 0.80 },
    { maxIP = 700,  minRoll = 0.60, maxRoll = 0.90 },
    { maxIP = 9999, minRoll = 0.70, maxRoll = 1.00 },
}
```

### 2.5 完整词缀值计算

```lua
local function calcAffixValue(affixDef, ip, roll)
    local ipFactor = 1 + (ip / 100 - 1) * affixDef.ipScale
    return affixDef.base * ipFactor * roll
end
```

**注意**: 不再有 qualityMul 直接乘词缀值。品质的影响完全通过:
1. IP 计算 (qualityMul 影响 IP → 影响 ipFactor 和 roll 范围)
2. 词缀数量 (品质越高词缀越多)

这与 D4 一致: 同章节的橙色 IP > 蓝色 IP，所以橙色词缀值自然更高。

---

## 3. 词缀系统设计

### 3.1 统一词缀池

将现有 25 个 `EQUIP_STATS` + 8 个 `AFFIX_DEFS` 合并为 `AFFIX_POOL`。

每条词缀定义:
```lua
{
    id = "atk",
    name = "攻击力",
    category = "attack",        -- attack / defense / utility
    base = 40.0,                -- IP=100 时的参考值
    ipScale = 1.0,              -- IP 敏感度 (0~1)
    isPercent = false,
    desc = "攻击力 +%s",
    slots = { "weapon", "gloves", "ring", "necklace" },
}
```

#### 攻击类 (Attack, 13 条)

| ID | 名称 | base | ipScale | isPercent | 可出现槽位 |
|----|------|------|---------|-----------|-----------|
| `atk` | 攻击力 | 40.0 | 1.0 | ❌ | 武器/手套/戒指/项链 |
| `spd` | 攻速 | 0.03 | 0.10 | ❌ | 手套/靴子/戒指 |
| `crit` | 暴击率 | 0.04 | 0.15 | ✅ | 手套/护符/项链 |
| `critDmg` | 暴击伤害 | 0.08 | 0.15 | ✅ | 护符/戒指/武器 |
| `skillDmg` | 技能伤害 | 0.06 | 0.12 | ✅ | 武器/手套/项链 |
| `reactionDmg` | 反应增伤 | 0.05 | 0.12 | ✅ | 武器/戒指/项链 |
| `fireDmg` | 火焰增伤 | 0.05 | 0.12 | ✅ | 武器/手套/护符 |
| `iceDmg` | 冰霜增伤 | 0.05 | 0.12 | ✅ | 武器/手套/护符 |
| `poisonDmg` | 毒素增伤 | 0.05 | 0.12 | ✅ | 武器/手套/护符 |
| `arcaneDmg` | 奥术增伤 | 0.05 | 0.12 | ✅ | 武器/手套/护符 |
| `waterDmg` | 流水增伤 | 0.05 | 0.12 | ✅ | 武器/手套/护符 |
| `combo_strike` | 连击 | 0.20 | 0.05 | ✅ | 武器/手套 |
| `elite_hunter` | 精英猎手 | 0.25 | 0.08 | ✅ | 武器/戒指 |

#### 防御类 (Defense, 13 条)

| ID | 名称 | base | ipScale | isPercent | 可出现槽位 |
|----|------|------|---------|-----------|-----------|
| `hp` | 生命值 | 640.0 | 1.0 | ❌ | 护符/靴子/项链/戒指 |
| `def` | 防御力 | 26.0 | 1.0 | ❌ | 靴子/护符/戒指 |
| `hpPct` | 生命百分比 | 0.06 | 0.12 | ✅ | 护符/靴子/项链 |
| `hpRegen` | 生命回复 | 13.4 | 1.0 | ❌ | 靴子/项链/护符 |
| `lifeSteal` | 生命偷取 | 0.016 | 0.10 | ✅ | 武器/戒指 |
| `shldPct` | 护盾比例 | 0.02 | 0.10 | ✅ | 护符/靴子 |
| `fireRes` | 火焰抗性 | 0.16 | 0.08 | ✅ | 护符/靴子/项链 |
| `iceRes` | 冰霜抗性 | 0.16 | 0.08 | ✅ | 护符/靴子/项链 |
| `poisonRes` | 毒素抗性 | 0.16 | 0.08 | ✅ | 手套/护符/项链 |
| `arcaneRes` | 奥术抗性 | 0.16 | 0.08 | ✅ | 手套/护符/项链 |
| `waterRes` | 流水抗性 | 0.16 | 0.08 | ✅ | 靴子/护符/项链 |
| `last_stand` | 绝境 | 0.30 | 0.05 | ✅ | 护符/靴子 |
| `kill_heal` | 击杀回复 | 0.02 | 0.05 | ✅ | 武器/戒指 |

#### 功能类 (Utility, 6 条)

| ID | 名称 | base | ipScale | isPercent | 可出现槽位 |
|----|------|------|---------|-----------|-----------|
| `luck` | 幸运 | 0.02 | 0.10 | ✅ | 戒指/项链 |
| `skillCdReduce` | 冷却缩减 | 0.04 | 0.10 | ✅ | 项链/护符 |
| `crit_surge` | 暴击强化 | 0.35 | 0.05 | ✅ | 手套/护符 |
| `greed` | 贪婪 | 0.30 | 0.05 | ✅ | 戒指/项链 |
| `scholar` | 博学 | 0.20 | 0.05 | ✅ | 项链 |
| `lucky_star` | 幸运星 | 0.15 | 0.05 | ✅ | 项链/戒指 |

**总计: 32 条词缀** (13 攻击 + 13 防御 + 6 功能)

> **base 值的校准**: base 值 = 旧系统中 `EQUIP_STATS.base × mainMul(20) × qualityMul(1.0)` 在 ch1 (tierMul=1) 时的数值。
> 例如 atk: 旧 `base=2.0, mainMul=20` → 新 `base=40.0`。
> 这样 IP=100 (ch1 橙装) 的词缀值与旧系统 ch1 橙装主词条一致。

### 3.2 词缀数量规则

| 品质 | 词缀数量 | Greater 概率 | 最大升级 |
|------|---------|-------------|---------|
| 白色 | 1 | 0% | 0 |
| 绿色 | 2 | 0% | 5 |
| 蓝色 | 3 | 0% | 10 |
| 紫色 | 4 | 0% | 15 |
| 橙色 | 5 | 15% per affix | 20 |

### 3.3 槽位词缀池

```lua
-- 自动构建
Config.AFFIX_SLOT_POOLS = {}
for _, aff in ipairs(Config.AFFIX_POOL) do
    for _, slotId in ipairs(aff.slots) do
        Config.AFFIX_SLOT_POOLS[slotId] = Config.AFFIX_SLOT_POOLS[slotId] or {}
        table.insert(Config.AFFIX_SLOT_POOLS[slotId], aff.id)
    end
end
```

### 3.4 Greater Affix (大词缀) ★

- **仅橙色品质**可产出
- 每条词缀 **15%** 概率成为 Greater
- Greater 词缀数值 = 正常值 **× 1.5**
- UI 显示 **★** 标记 + 金色文字
- 附魔时 Greater 状态保留

---

## 4. 装备生成流程

```lua
function GS.GenerateEquip(chapter, slotIdx, qualityIdx)
    local slotCfg = Config.EQUIP_SLOTS[slotIdx]

    -- 1. 计算 IP (唯一数值驱动, 无 tierMul)
    local baseIP = Config.CalcBaseIP(chapter)
    local ipQMul = Config.IP_QUALITY_MUL[qualityIdx]
    local itemPower = math.floor(baseIP * ipQMul)

    -- 2. 查 IP 区间 → roll 范围
    local minRoll, maxRoll = getIPBracket(itemPower)

    -- 3. 确定词缀数量 (按品质)
    local affixCount = Config.AFFIX_COUNT_BY_QUALITY[qualityIdx]

    -- 4. 从槽位池无重复选取 N 条
    local pool = Config.AFFIX_SLOT_POOLS[slotCfg.id]
    local selected = shuffleSelect(pool, affixCount)

    -- 5. Roll 每条词缀 (IP 驱动值)
    local affixes = {}
    for _, affId in ipairs(selected) do
        local def = Config.AFFIX_MAP[affId]
        local roll = minRoll + math.random() * (maxRoll - minRoll)
        local value = calcAffixValue(def, itemPower, roll)
        local isGreater = false
        if qualityIdx == 5 and math.random() < Config.AFFIX_GREATER_CHANCE then
            value = value * 1.5
            isGreater = true
        end
        table.insert(affixes, { id = affId, value = value, greater = isGreater })
    end

    -- 6. 组装 (无 tier/tierMul/mainStat/subStats)
    return {
        slot = slotCfg.id,
        qualityIdx = qualityIdx,
        itemPower = itemPower,
        affixes = affixes,
        -- setId, element, sockets, gems 等逻辑保持不变
        upgradeLv = 0,
    }
end
```

---

## 5. 升级系统

### 5.1 常规升级 (强化)

升级提升**所有词缀**的数值 + IP:

```lua
function GS.UpgradeEquip(item)
    item.upgradeLv = (item.upgradeLv or 0) + 1
    item.itemPower = item.itemPower + Config.IP_PER_UPGRADE  -- +5 IP

    local growth = Config.UPGRADE_AFFIX_GROWTH  -- 每级 +3%
    for _, aff in ipairs(item.affixes) do
        if not aff.baseValue then aff.baseValue = aff.value end
        aff.value = aff.baseValue * (1 + item.upgradeLv * growth)
    end
end
```

- 橙色满级 (+20): 所有词缀 ×1.60, IP +100

### 5.2 IP 注入 (取代旧 Tier 升级)

当玩家到达更高章节后，可以对旧装备执行 **IP 注入**，将 IP 提升到当前章节水平:

```lua
function GS.InfuseEquip(item, newChapter)
    local newBaseIP = Config.CalcBaseIP(newChapter)
    local newIP = math.floor(newBaseIP * Config.IP_QUALITY_MUL[item.qualityIdx]
                           + (item.upgradeLv or 0) * Config.IP_PER_UPGRADE)
    local oldIP = item.itemPower
    if newIP <= oldIP then return false end  -- 已经是更高 IP

    -- 重算所有词缀值 (基于新 IP 的 ipFactor)
    for _, aff in ipairs(item.affixes) do
        local def = Config.AFFIX_MAP[aff.id]
        if def then
            local oldFactor = 1 + (oldIP / 100 - 1) * def.ipScale
            local newFactor = 1 + (newIP / 100 - 1) * def.ipScale
            if oldFactor > 0 then
                local ratio = newFactor / oldFactor
                aff.value = aff.value * ratio
                if aff.baseValue then aff.baseValue = aff.baseValue * ratio end
            end
        end
    end

    item.itemPower = newIP
    return true
end
```

**效果**: 绝对值属性 (atk/hp/def, ipScale=1.0) 大幅提升，百分比属性 (crit/critDmg, ipScale=0.15) 小幅提升，proc 属性 (combo_strike, ipScale=0.05) 几乎不变。
这与旧 TierUpgrade 的效果一致（绝对值缩放，百分比不缩放），但通过 IP 统一实现。

---

## 6. 附魔系统 (洗词缀)

### 6.1 规则

- **紫色/橙色**装备可附魔
- 选择 1 条词缀重 roll
- 从该槽位池随机选取新词缀 (排除其他已有词缀)
- 新词缀按当前 IP 重新 roll
- Greater 状态保留
- 消耗**魂晶** (随 IP 递增)

### 6.2 费用

```lua
Config.ENCHANT_COST = {
    baseCost = 50,
    ipMul = 0.5,        -- 每点 IP +0.5 魂晶
    qualityMul = { [4] = 1, [5] = 2 },
}
-- 费用 = floor((baseCost + IP × ipMul) × qualityMul)
-- IP=568 橙色 = (50 + 284) × 2 = 668 魂晶
```

---

## 7. 属性收集 (StatCalc)

### 7.1 equipSum 重写

```lua
local function equipSum(statKey)
    local total = 0
    for _, slotCfg in ipairs(Config.EQUIP_SLOTS) do
        local item = GameState.equipment[slotCfg.id]
        if item and item.affixes then
            for _, aff in ipairs(item.affixes) do
                if aff.id == statKey then
                    total = total + (aff.value or 0)
                end
            end
        end
    end
    return total
end
```

所有 `Get*` 函数调用 `equipSum(key)` 不变。

### 7.2 Proc 词缀

AffixHelper.GetAffixValue 从 affixes[] 读 value (接口不变)。

### 7.3 ItemScore (原 ItemPower 排序公式)

```lua
function GS.ItemScore(item)
    local score = 0
    if item.affixes then
        for _, aff in ipairs(item.affixes) do
            local def = Config.AFFIX_MAP[aff.id]
            if def then
                local importance = StatDefs.GetImportance(aff.id) or 1.0
                local normalized = aff.value / (def.base * (1 + (item.itemPower/100 - 1) * def.ipScale))
                score = score + normalized * importance
            end
        end
    end
    if item.setId then score = score + 15 end
    if item.gems then
        for _, gem in pairs(item.gems) do if gem then score = score + 5 end end
    end
    return score
end
```

---

## 8. 存档迁移 v7 → v8

### 8.1 迁移逻辑

```lua
MIGRATIONS[7] = function(data)
    local function migrateItem(item)
        if not item then return end
        local newAffixes = {}

        -- 1. mainStat → 第一条词缀 (保留原始数值)
        if item.mainStat then
            table.insert(newAffixes, {
                id = item.mainStat,
                value = item.mainValue or 0,
                greater = false,
            })
        end

        -- 2. subStats → 后续词缀
        if item.subStats then
            for _, sub in ipairs(item.subStats) do
                table.insert(newAffixes, {
                    id = sub.key,
                    value = sub.value or 0,
                    greater = false,
                })
            end
        end

        -- 3. 旧 proc 词缀 → 合并
        if item.affixes then
            for _, aff in ipairs(item.affixes) do
                local def = LEGACY_AFFIX_MAP[aff.id]
                local base = def and def.baseValue or 0.2
                local isGreater = aff.enhanced or false
                table.insert(newAffixes, {
                    id = aff.id,
                    value = isGreater and (base * 1.5) or base,
                    greater = isGreater,
                })
            end
        end

        -- 4. 计算 IP (从旧 tier 推导 chapter，再算 baseIP)
        local chapter = tierToChapter(item.tier or 1)  -- 反查章节
        local baseIP = Config.CalcBaseIP(chapter)
        local qi = item.qualityIdx or 1
        local ipQMul = Config.IP_QUALITY_MUL[qi] or 0.5
        item.itemPower = math.floor(baseIP * ipQMul + (item.upgradeLv or 0) * 5)

        -- 5. 写入新结构, 删除旧字段
        item.affixes = newAffixes
        item.mainStat = nil
        item.mainValue = nil
        item.baseMainValue = nil
        item.subStats = nil
        item.tier = nil
        item.tierMul = nil
    end

    if data.equipment then
        for _, item in pairs(data.equipment) do migrateItem(item) end
    end
    if data.inventory then
        for _, item in ipairs(data.inventory) do migrateItem(item) end
    end
    data.version = 8
    return data
end
```

### 8.2 tierToChapter 反查

旧系统 `tier = GetChapterTier(chapter)` 是对数函数，反查:

```lua
-- tier = 1 + 99 × ln(ch) / ln(100)
-- → ch = 100 ^ ((tier - 1) / 99)
local function tierToChapter(tier)
    if tier <= 1 then return 1 end
    return math.max(1, math.floor(100 ^ ((tier - 1) / 99) + 0.5))
end
```

### 8.3 迁移效果

玩家装备完全保留原始数值 (mainValue/subStats 的 value 原封不动变成词缀 value)。
IP 从旧 tier 推导，确保 InfuseEquip 在迁移后不会"降级"。

---

## 9. 存档压缩适配

```lua
-- 压缩: 废除 ms/mv/ss/t/tm, 新增 af/ip
c.ip = item.itemPower
c.af = {}
for i, aff in ipairs(item.affixes) do
    local ca = { i = aff.id, v = aff.value }
    if aff.greater then ca.g = 1 end
    if aff.baseValue then ca.bv = aff.baseValue end
    c.af[i] = ca
end

-- 解压
item.itemPower = c.ip or 100
if c.af then
    item.affixes = {}
    for i, ca in ipairs(c.af) do
        item.affixes[i] = {
            id = ca.i, value = ca.v,
            greater = ca.g == 1,
            baseValue = ca.bv,
        }
    end
end
```

---

## 10. 与旧系统的对应关系

### 10.1 旧 tierMul → 新 ipFactor

| 旧概念 | 新概念 | 关系 |
|--------|--------|------|
| `tierMul = GetChapterTier(ch)` | `ipFactor = 1 + (IP/100 - 1) × ipScale` | ipScale=1.0 时，ipFactor ≈ tierMul (同章节) |
| `item.tierMul` | `item.itemPower` | IP 编码了 tier + quality + upgrade 信息 |
| `TierUpgradeEquip` | `InfuseEquip` | 功能等价，但通过 IP 驱动 |
| `EQUIP_STATS.base × mainMul × tierMul` | `AFFIX_POOL.base × ipFactor × roll` | base 已包含旧 mainMul |

### 10.2 其他系统对 tierMul 的引用

**不受 P2 影响**的 tierMul 引用:
- `Config.GetChapterTier(chapter)` — **保留**，怪物缩放、属性点缩放等仍用
- `Config.GetAttrScale(chapter)` — **保留**，属性加点系统仍用
- `StatDefs.GetTierMul(statKey, chapter, tierMul)` — **保留**，属性加点系统仍用

**P2 废除的** tierMul 引用:
- `item.tierMul` — 装备上的 tierMul 字段删除
- `Equipment.lua` 中所有 `tierMul` 参数 — 改用 IP
- `SlotSaveSystem.lua` 中 tierMul 压缩/解压 — 删除
- `InventoryCompare.lua` 中 TierUpgrade 预览的 tierMul 对比 — 改用 IP

---

## 11. UI 变更

### 11.1 InventoryCompare.lua

- 废除: 黄色主词条行 + 灰色副词条行
- 新增: 统一词缀行，按 category 着色 (attack 红/defense 蓝/utility 绿)
- Greater 词缀: ★ + 金色
- IP 注入预览: 对比每条词缀的 ipScale 变化

### 11.2 InventoryPage.lua

- 装备卡片显示 **IP 值**
- 附魔按钮入口

---

## 12. 文件变更清单

### 核心修改

| 文件 | 变更 |
|------|------|
| `Config.lua` | 新增 `AFFIX_POOL` (32条); `CalcBaseIP`; `IP_BRACKETS`/`IP_QUALITY_MUL`; `AFFIX_COUNT_BY_QUALITY`; `AFFIX_SLOT_POOLS`; `UPGRADE_AFFIX_GROWTH`; `ENCHANT_COST`; 废除 mainPool/subPool/`UPGRADE_MAIN_GROWTH`/`UPGRADE_SUB_BOOST_RATIO` |
| `state/Equipment.lua` | 全面重写: 废除 mainStat/subStats/tierMul, 统一 affixes; IP 驱动 roll; InfuseEquip 取代 TierUpgrade; enchantAffix |
| `state/StatCalc.lua` | equipSum 从 affixes[] 收集; ItemPower→ItemScore; 废除 mainStat/subStats 遍历 |
| `SlotSaveSystem.lua` | 废除 ms/mv/ss/t/tm 字段; 新增 af/ip; v7→v8 迁移 |
| `ui/InventoryCompare.lua` | 统一词缀显示; Greater ★; IP 注入预览; 附魔入口 |

### 中等修改

| 文件 | 变更 |
|------|------|
| `state/AffixHelper.lua` | GetAffixValue 从 affixes[] 读 value |
| `ui/InventoryPage.lua` | IP 显示; 附魔按钮 |
| `state/StatDefs.lua` | GetImportance 扩展 proc 词缀权重 |

### 低修改 (接口不变)

| 文件 | 说明 |
|------|------|
| `battle/CombatCore.lua` | combo_strike/crit_surge 读 AffixHelper (不变) |
| `battle/DamageFormula.lua` | elite_hunter 读 AffixHelper (不变) |
| `battle/DropManager.lua` | greed/scholar 读 AffixHelper (不变) |
| `ui/ShopPage.lua` | ForgeEquip 参数适配 |
| `VersionReward.lua` | CreateEquip 参数适配 |

---

## 13. 实现顺序

### Phase 1: Config 数据层
1. 新增 `AFFIX_POOL` + `CalcBaseIP` + `IP_BRACKETS` + `IP_QUALITY_MUL`
2. 新增 `AFFIX_COUNT_BY_QUALITY` + `AFFIX_SLOT_POOLS` + `UPGRADE_AFFIX_GROWTH`
3. 保留 `EQUIP_STATS` 供 FormatStatValue 显示用

### Phase 2: Equipment.lua
4. 重写 GenerateEquip / CreateEquip / ForgeEquip (IP 驱动, 无 tierMul)
5. 重写 UpgradeEquip (均匀增长)
6. 新增 InfuseEquip (取代 TierUpgrade)
7. 适配 DecomposeItem

### Phase 3: StatCalc + AffixHelper
8. equipSum 从 affixes[] 收集
9. ItemPower → ItemScore
10. AffixHelper 改读 aff.value

### Phase 4: 存档迁移
11. 压缩/解压适配
12. v7→v8 迁移

### Phase 5: UI
13. InventoryCompare 统一词缀显示 + IP 注入预览
14. InventoryPage IP 显示 + 附魔
15. HUD / CharacterPage 适配

### Phase 6: 清理 + 构建
16. 全局搜索残留 mainStat/mainValue/subStats/tierMul
17. LSP + 构建验证

---

## 14. 验收标准

- [ ] 装备无 mainStat / subStats / tier / tierMul 字段
- [ ] IP 是唯一数值驱动 (CalcBaseIP × qualityMul + upgLv × 5)
- [ ] 词缀值 = base × ipFactor × roll, ipFactor 由 ipScale 控制
- [ ] 白1/绿2/蓝3/紫4/橙5 词缀
- [ ] Greater ★ 橙色 15%
- [ ] 升级: 所有词缀 +3%/级, IP +5/级
- [ ] IP 注入: 旧装备 IP 提升到新章节水平
- [ ] 附魔: 紫/橙洗 1 条
- [ ] 存档 v7→v8 迁移正确
- [ ] StatCalc/AffixHelper 从 affixes 收集
- [ ] ch16 ≈ IP 568 (远未毕业), ch100 ≈ IP 925
- [ ] 构建通过, 0 LSP 错误

---

*版本: v3.0 (全词缀化 + IP 取代 tierMul)*  
*日期: 2026-03-25*
