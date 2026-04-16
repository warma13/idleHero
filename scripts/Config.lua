-- ============================================================================
-- Config.lua - 挂机自动战斗游戏 数值配置
-- ============================================================================

local Config = {}

Config.Title = "挂机英雄 · 法师"
Config.SKILL_PT_INTERVAL = 1   -- 每级获得1技能点

-- ============================================================================
-- 章节数值缩放体系
-- ============================================================================

-- GetChapterTier, GetAttrScale → ConfigCalc.lua

-- 玩家基础属性 (术士: 中程法师, 核心 CDM/LCK)
Config.PLAYER = {
    class = "mage",
    className = "术士",
    baseAtk = 18,        -- 略低于通用
    atkSpeed = 1.0,      -- 中等攻速
    moveSpeed = 110,     -- 略慢
    pickupRadius = 80,
    baseRange = 95,      -- 中程攻击距离
    baseCritDmg = 1.8,   -- 术士暴击伤害更高
    -- 生存属性
    baseHP = 500,        -- 基础生命值
    hpPerLevel = 12,     -- 每级+12HP
    baseDEF = 5,         -- 基础防御力
    defPerLevel = 0.3,   -- 每级+0.3DEF
    defK = 200,          -- 玩家受伤DEF减免常数: 减免率=DEF/(DEF+K)
}

-- (v3.0: 元素增幅/反应系统已移除, 改用D4六桶伤害公式)

-- 每级属性点
Config.POINTS_PER_LEVEL = 3

-- 暴击率溢出转暴伤比率 (1%溢出 → 2%暴伤, 独立于核心属性)
Config.CRIT_OVERFLOW_RATIO = 2

-- 吸血配置
Config.LIFESTEAL = {
    maxPctPerSec = 0.08,  -- 每秒吸血上限 = 最大HP × 8%
    -- 吸血效率分级
    efficiency = {
        normal   = 1.0,   -- 普攻(含分裂弹)
        skill    = 0.6,   -- 技能伤害(元素冲击/风暴/天崩)
        summon   = 0.3,   -- 召唤物伤害(精灵/图腾)
        fireZone = 0.2,   -- 持续区域(图腾/毁灭领域)
    },
}

-- 护盾触发配置
Config.SHIELD = {
    onKillBase = 8,         -- 击杀获得护盾基础值
    onKillPerLevel = 0.3,   -- 每等级额外护盾
}

-- 减疗 debuff 配置 (特定怪物攻击附带)
Config.ANTI_HEAL = {
    duration = 4.0,    -- 减疗持续时间(秒)
    rate = 0.35,       -- 减疗比率 (35%减疗)
}

-- ============================================================================
-- 法力(Mana)系统 — D4 资源机制
-- ============================================================================
-- 法力上限 = MANA_BASE + level × MANA_PER_LEVEL
-- 每秒回复 = MANA_REGEN_BASE × (1 + manaRegenSpeed%)^2
--            × (1 + resourceGen%) × (1 + willpowerResourceGen%)
-- 意志资源生成: 每点意志 = +0.1% 意志资源生成
-- ============================================================================
Config.MANA = {
    base           = 50,     -- 初始法力值
    perLevel       = 0.505,  -- 每级增加法力上限
    regenBase      = 10,     -- 每秒基础回复
    willRegenPer   = 0.001,  -- 每点意志 +0.1% 意志资源生成
}

-- 韧性系统配置 — 通用减益抗性
-- P1 重构: 减益抗性不再来自加点，改为纯装备/称号
-- 持续时间衰减 = 原始持续 × (1 - resist × durFactor)
Config.TENACITY = {
    maxResist = 0.80,      -- 最大减益抗性80%
    durFactor = 0.5,       -- 持续时间衰减系数 (抗性×0.5 用于缩短持续时间)
}

-- 攻速双池模型
-- 公式: 总攻速 = (1 + 第一类 + 第二类) × 武器攻速
-- 第一类: 面板加成 (装备/套装/被动技能等), 上限 100%
-- 第二类: 触发加成 (技能buff/药水/debuff等), 上限 100%
Config.ATK_SPEED_CAP1 = 1.0   -- 第一类(面板)上限 100%
Config.ATK_SPEED_CAP2 = 1.0   -- 第二类(触发)上限 100%

-- 技能冷却递减 (渐近线模型, 和攻速结构一致)
-- 公式: cdMul = 1 - maxCDR × totalCDR / (totalCDR + K)
-- totalCDR = 天赋 + 装备 + 套装 + 精通 (加算后统一进递减)
Config.CDR_DR = {
    maxCDR = 0.75,  -- 渐近线: 最多减75%CD (永远达不到)
    K      = 0.50,  -- 半值常数: 投入0.50时获得 maxCDR/2 ≈ 37.5% 实际CDR
}

-- 攻击范围边际递减 (渐近线模型)
-- 公式: 实际范围 = baseRange + maxBonus × rawBonus / (rawBonus + K)
-- 其中 rawBonus = 点数 × perPoint + 装备词缀range
Config.RANGE_DR = {
    maxBonus = 150,  -- 理论最大范围增量 (实际范围永远 < baseRange + 150)
    K        = 40,   -- 半值常数 (投入rawBonus=40时获得75的增量)
}

-- ResistMul → ConfigCalc.lua

-- 元素属性配置 (v3.0: 3元素, 无反应)
Config.ELEMENTS = {
    -- 元素类型: fire, ice, lightning, physical
    types = { "fire", "ice", "lightning", "physical" },
    names = {
        fire = "火焰", ice = "冰霜", lightning = "闪电", physical = "物理",
    },
    colors = {
        fire      = { 255, 100, 30 },
        ice       = { 100, 180, 255 },
        lightning = { 255, 220, 80 },
        physical  = { 200, 200, 200 },
    },
    -- 玩家基础元素抗性 (0 = 无抗性, 0.3 = 30%减免)
    baseResist = {
        fire = 0.10,  -- 术士天生10%火抗
        ice = 0, lightning = 0, physical = 0,
    },
}

-- (v4.0: 武器元素系统已移除, 默认 fire)

-- 敌人DEF减免常数 (玩家攻击敌人时)
Config.ENEMY_DEF_K = 100

-- DefMul, OldLevelExp, LevelExp → ConfigCalc.lua

-- 经验版本号 (用于存档迁移)
Config.EXP_VERSION = 3

-- ============================================================================
-- 掉落模板 (v1, 2026-03-15)
-- 怪物通过 dropTemplate 字段引用, 不再手写 goldDrop
-- 金币缩放: scaleMul^0.3 (比花费的 sqrt 慢, 越后期越紧)
-- 校准锚点: ch1 前4关(~34次掉落) × 均值4.5 ≈ 153金 ≈ 1瓶小药水(150金)
-- ============================================================================
Config.DROP_TEMPLATES = {
    -- 普通小怪: 低金币, 高数量补偿
    common    = { goldDrop = { 2, 7 },  goldChance = 0.30, equipChance = 0.12 },
    -- 精英怪: 中等金币, 中等概率
    elite     = { goldDrop = { 5, 12 }, goldChance = 0.50, equipChance = 0.20 },
    -- 小Boss(每章第5关): 中高金币, 必掉金, 半数掉装备
    miniboss  = { goldDrop = { 8, 18 }, goldChance = 1.00, equipChance = 0.50 },
    -- 大Boss(每章第10关): 高金币, 必掉金, 必掉装备
    boss      = { goldDrop = { 20, 40 }, goldChance = 1.00, equipChance = 1.00 },
    -- 召唤物/分裂体: 极低或无掉落
    summon    = { goldDrop = { 0, 1 },  goldChance = 0.10, equipChance = 0.00 },
}

-- GetGoldScale → ConfigCalc.lua

-- BOSS 倍率
Config.BOSS = {
    hpMul = 5,
    atkMul = 2,
    expMul = 10,
    goldMul = 5,
    guaranteeDrop = true,  -- 必掉装备
}

-- 波次配置
Config.WAVE = {
    enemiesPerWave = 5,
    spawnInterval = 1.5,   -- 每只怪生成间隔(秒)
    bossEvery = 10,        -- 每10波出BOSS
    restTime = 1.5,        -- 波次间休息时间
    scalingPerWave = 0.08, -- 每波属性增长比例
}

-- 装备品质配置
-- qualityMul 用于主词条缩放; 副词条数量 = subCount
Config.EQUIP_QUALITY = {
    { name = "白色", color = { 200, 200, 200 }, qualityMul = 1.0, subCount = 0, dropWeight = 50, maxUpgrade = 0 },
    { name = "绿色", color = { 100, 220, 100 }, qualityMul = 1.5, subCount = 1, dropWeight = 30, maxUpgrade = 4 },
    { name = "蓝色", color = { 80, 140, 255 },  qualityMul = 2.0, subCount = 2, dropWeight = 15, canHaveSet = true, maxUpgrade = 4 },
    { name = "紫色", color = { 180, 80, 220 },  qualityMul = 3.0, subCount = 3, dropWeight = 4,  canHaveSet = true, maxUpgrade = 4 },
    { name = "橙色", color = { 255, 165, 0 },   qualityMul = 5.0, subCount = 4, dropWeight = 1,  canHaveSet = true, maxUpgrade = 4 },
}

-- ============================================================================
-- 装备升级系统 (v5.0: D4风格 4次固定消耗制)
-- ============================================================================

-- 升级每次主属性增长率: 每次 +10%, 4次满级 = +40%
Config.UPGRADE_MAIN_GROWTH = 0.10

-- 词缀增长: 每次升级所有词缀统一 +5%, 4次满级 = +20%
Config.UPGRADE_AFFIX_GROWTH = 0.05

-- (旧版兼容, 存档迁移用)
Config.UPGRADE_AFFIX_MILESTONE_INTERVAL = 5
Config.UPGRADE_AFFIX_MILESTONE_BONUS   = 0.02

-- 升级固定消耗表 (按品质索引 2-5, 每品质 4 次)
-- 每次消耗: { gold = N, mats = { [matId] = amount, ... } }
Config.UPGRADE_COSTS = {
    -- [2] 绿色
    [2] = {
        { gold = 50,   mats = { iron = 5 } },
        { gold = 150,  mats = { iron = 10 } },
        { gold = 400,  mats = { iron = 20 } },
        { gold = 800,  mats = { iron = 35 } },
    },
    -- [3] 蓝色
    [3] = {
        { gold = 200,  mats = { iron = 8,  crystal = 2 } },
        { gold = 500,  mats = { iron = 15, crystal = 4 } },
        { gold = 1200, mats = { iron = 25, crystal = 8 } },
        { gold = 2500, mats = { iron = 40, crystal = 15 } },
    },
    -- [4] 紫色
    [4] = {
        { gold = 500,  mats = { iron = 10, crystal = 5,  wraith = 2 } },
        { gold = 1500, mats = { iron = 20, crystal = 10, wraith = 4 } },
        { gold = 4000, mats = { iron = 35, crystal = 18, wraith = 8 } },
        { gold = 8000, mats = { iron = 55, crystal = 30, wraith = 15 } },
    },
    -- [5] 橙色
    [5] = {
        { gold = 1000,  mats = { iron = 12, crystal = 8,  wraith = 4,  eternal = 1 } },
        { gold = 3000,  mats = { iron = 25, crystal = 15, wraith = 8,  eternal = 2 } },
        { gold = 8000,  mats = { iron = 40, crystal = 25, wraith = 15, eternal = 4 } },
        { gold = 15000, mats = { iron = 65, crystal = 40, wraith = 25, eternal = 8 } },
    },
}

-- 终局强化 (橙色满4级后可选第5次, 消耗深渊之心)
Config.UPGRADE_ENDGAME = {
    gold = 25000,
    mats = { abyssHeart = 3 },
    mainGrowth = 0.10,    -- 额外 +10% 主属性
    affixGrowth = 0.05,   -- 额外 +5% 全词缀
}

-- UpgradeCost → ConfigCalc.lua

-- ============================================================================
-- D4 风格材料系统
-- ============================================================================

-- 6 种材料定义
Config.MATERIAL_DEFS = {
    { id = "iron",       name = "锈蚀铁块", color = { 180, 160, 140 }, rarity = "common",    desc = "分解白/绿装获得，低级升级材料" },
    { id = "crystal",    name = "暗纹晶体", color = { 100, 140, 220 }, rarity = "uncommon",  desc = "分解蓝装获得，中级升级材料" },
    { id = "wraith",     name = "怨魂碎片", color = { 180, 80, 220 },  rarity = "rare",      desc = "分解紫装获得，高级升级材料" },
    { id = "eternal",    name = "永夜之魂", color = { 255, 165, 0 },   rarity = "legendary", desc = "分解橙装获得，顶级升级材料" },
    { id = "abyssHeart", name = "深渊之心", color = { 200, 50, 80 },   rarity = "mythic",    desc = "深渊模式Boss掉落" },
    { id = "riftEcho",   name = "裂隙残响", color = { 80, 220, 200 },  rarity = "mythic",    desc = "套装秘境/世界Boss掉落" },
    { id = "forestDew",  name = "森之露",   color = { 60, 200, 120 },  rarity = "rare",      desc = "魔力之森中凝结的纯净魔力，可用于强化魔力之源" },
}

-- 材料快查表 { [id] = materialDef }
Config.MATERIAL_MAP = {}
for _, mat in ipairs(Config.MATERIAL_DEFS) do
    Config.MATERIAL_MAP[mat.id] = mat
end

-- 所有材料 ID 列表 (用于遍历)
Config.MATERIAL_IDS = { "iron", "crystal", "wraith", "eternal", "abyssHeart", "riftEcho", "forestDew" }

-- 材料图标路径 (生成后填入)
Config.MATERIAL_ICON_PATHS = {
    iron       = "image/mat_iron_20260412164347.png",
    crystal    = "image/mat_crystal_20260412165207.png",
    wraith     = "image/mat_wraith_20260412165203.png",
    eternal    = "image/mat_eternal_20260412174302.png",
    abyssHeart = "image/mat_abyssHeart_20260412165755.png",
    riftEcho   = "image/mat_riftEcho_20260412172604.png",
    forestDew  = "image/mat_forestDew_20260414151650.png",
}

-- 分解装备获得的材料 (按品质索引 1-5)
-- qualityIdx: 1=白, 2=绿, 3=蓝, 4=紫, 5=橙
Config.DECOMPOSE_MATERIALS = {
    [1] = { iron = 2 },                       -- 白色: 2铁块
    [2] = { iron = 5 },                       -- 绿色: 5铁块
    [3] = { iron = 5, crystal = 3 },          -- 蓝色: 5铁块 + 3晶体
    [4] = { crystal = 3, wraith = 4 },        -- 紫色: 3晶体 + 4碎片
    [5] = { wraith = 3, eternal = 3 },        -- 橙色: 3碎片 + 3永夜
}

-- 分解金币产出 (按品质索引 1-5)
Config.DECOMPOSE_GOLD = {
    [1] = 5,     -- 白色
    [2] = 15,    -- 绿色
    [3] = 50,    -- 蓝色
    [4] = 150,   -- 紫色
    [5] = 500,   -- 橙色
}

-- 旧版兼容: DECOMPOSE_STONES (某些旧代码可能引用)
Config.DECOMPOSE_STONES = { 0, 1, 2, 4, 8 }

-- 升级材料分段: 不同升级等级消耗不同材料
-- 每段指定: 起始等级(含), 结束等级(不含), 材料ID
Config.UPGRADE_MATERIAL_TIERS = {
    { minLv = 0,  maxLv = 10, matId = "iron" },       -- Lv0-9:  锈蚀铁块
    { minLv = 10, maxLv = 20, matId = "crystal" },    -- Lv10-19: 暗纹晶体
    { minLv = 20, maxLv = 35, matId = "wraith" },     -- Lv20-34: 怨魂碎片
    { minLv = 35, maxLv = 999, matId = "eternal" },   -- Lv35+:   永夜之魂
}

-- 深渊之心额外消耗: 升级等级 >= 此值时每次额外消耗 1 深渊之心
Config.UPGRADE_ABYSS_HEART_LEVEL = 45

-- 分解已升级装备时, 返还已投入材料的比例 (v5.0: 80%→50%)
Config.UPGRADE_REFUND_RATIO = 0.5

-- 12 项装备属性定义
-- base = 副词条基础值; mainMul = 主词条倍率(相对base); isPercent = 显示为百分比
-- isAtkStat = 攻击系词条(主词条权重1, 非攻击系权重2, 即攻击系出现概率减半)
Config.EQUIP_STATS = {
    atk         = { name = "攻击力",   base = 2.0,    mainMul = 20, isPercent = false, canBeMain = true, isAtkStat = true },
    spd         = { name = "攻速",     base = 0.0015, mainMul = 20, isPercent = false, canBeMain = true, isAtkStat = true, fmtSub = "%.4f" },
    crit        = { name = "暴击率",   base = 0.002,  mainMul = 20, isPercent = true,  canBeMain = true, isAtkStat = true },
    critDmg     = { name = "暴击伤害", base = 0.004,  mainMul = 20, isPercent = true,  canBeMain = true, isAtkStat = true },
    elemDmg     = { name = "全元素增伤", base = 0.0005, mainMul = 4,  isPercent = true,  canBeMain = true },
    fireDmg     = { name = "火焰增伤", base = 0.0025, mainMul = 20, isPercent = true,  canBeMain = true, isAtkStat = true, element = "fire" },
    iceDmg      = { name = "冰霜增伤", base = 0.0025, mainMul = 20, isPercent = true,  canBeMain = true, isAtkStat = true, element = "ice" },
    lightningDmg = { name = "闪电增伤", base = 0.0025, mainMul = 20, isPercent = true,  canBeMain = true, isAtkStat = true, element = "lightning" },
    hp          = { name = "生命值",   base = 32.0,   mainMul = 20, isPercent = false, canBeMain = true },
    def         = { name = "防御力",   base = 1.3,    mainMul = 20, isPercent = false, canBeMain = true },
    luck        = { name = "幸运",     base = 0.001,  mainMul = 20, isPercent = true,  canBeMain = true },
    hpRegen     = { name = "生命回复", base = 0.67,   mainMul = 20, isPercent = false, canBeMain = false },
    lifeSteal   = { name = "生命偷取", base = 0.0008, mainMul = 20, isPercent = true,  canBeMain = false },
    shldPct     = { name = "护盾比例", base = 0.001,  mainMul = 20, isPercent = true,  canBeMain = false },
    -- 百分比生命 & 技能冷却缩减 (v1.8新增)
    hpPct       = { name = "生命百分比", base = 0.003, mainMul = 20, isPercent = true,  canBeMain = true },
    skillCdReduce = { name = "技能冷却缩减", base = 0.002, mainMul = 20, isPercent = true, canBeMain = true },
    -- 技能伤害 (v3新增, X伤害桶独立乘区)
    skillDmg    = { name = "技能伤害", base = 0.003, mainMul = 20, isPercent = true, canBeMain = true },
    -- 易伤伤害 (v3新增, 装备来源走A伤桶)
    vulnerableDmg = { name = "易伤伤害", base = 0.002, mainMul = 20, isPercent = true, canBeMain = true },
    -- 超杀伤害 (v3新增, X伤害桶独立乘区)
    overkillDmg = { name = "超杀伤害", base = 0.002, mainMul = 20, isPercent = true, canBeMain = false },
    -- 压制伤害 (v3新增, 桶6压制乘区)
    overpowerDmg = { name = "压制伤害", base = 0.002, mainMul = 20, isPercent = true, canBeMain = false },
    -- 元素抗性 (仅副词条)
    fireRes     = { name = "火焰抗性", base = 0.008,  mainMul = 20, isPercent = true,  canBeMain = false },
    iceRes      = { name = "冰霜抗性", base = 0.008,  mainMul = 20, isPercent = true,  canBeMain = false },
    lightningRes = { name = "闪电抗性", base = 0.008,  mainMul = 20, isPercent = true,  canBeMain = false },
}

-- ============================================================================
-- 装备词缀系统
-- ============================================================================

-- 词缀品质规则: 紫色0~1条(30%出1条), 橙色1~2条(30%出2条)
Config.AFFIX_QUALITY_RULES = {
    -- [qualityIdx] = { min, max, extraChance }
    -- extraChance = 从 min 升到 min+1 的概率
    [4] = { min = 0, max = 1, extraChance = 0.30 },  -- 紫色: 70%无词缀, 30%出1条
    [5] = { min = 1, max = 2, extraChance = 0.30 },  -- 橙色: 70%出1条, 30%出2条
}

-- 强化词缀概率 (仅橙色可出, 值 ×1.5)
Config.AFFIX_ENHANCED_CHANCE = 0.15

-- 词缀定义表
-- category: "attack" | "defense" | "utility"
-- baseValue: 普通档数值, enhanced = baseValue × 1.5
-- desc: %d 会被替换为实际百分比值
Config.AFFIX_DEFS = {
    {
        id = "combo_strike",
        name = "连击",
        category = "attack",
        baseValue = 0.20,       -- 20% 概率连续攻击2次
        desc = "普攻有%d%%概率连续攻击2次",
    },
    {
        id = "elite_hunter",
        name = "精英猎手",
        category = "attack",
        baseValue = 0.25,       -- 对Boss/精英 +25% 伤害
        desc = "对Boss/精英怪伤害+%d%%",
    },
    {
        id = "crit_surge",
        name = "暴击强化",
        category = "attack",
        baseValue = 0.35,       -- 暴击时额外造成35%ATK固定伤害
        desc = "暴击时额外造成%d%%攻击力的固定伤害",
    },
    {
        id = "last_stand",
        name = "绝境",
        category = "defense",
        baseValue = 0.30,       -- 生命<20%时减伤+30%
        desc = "生命低于20%%时减伤+%d%%",
    },
    {
        id = "kill_heal",
        name = "击杀回复",
        category = "defense",
        baseValue = 0.02,       -- 击杀回复2%最大生命
        desc = "击杀敌人回复%d%%最大生命",
    },
    {
        id = "greed",
        name = "贪婪",
        category = "utility",
        baseValue = 0.30,       -- 金币掉落+30%
        desc = "金币掉落+%d%%",
    },
    {
        id = "scholar",
        name = "博学",
        category = "utility",
        baseValue = 0.20,       -- 经验获取+20%
        desc = "经验获取+%d%%",
    },
    {
        id = "lucky_star",
        name = "幸运星",
        category = "utility",
        baseValue = 0.15,       -- 装备掉落品质提升概率+15%
        desc = "装备掉落品质提升概率+%d%%",
    },
}

-- 词缀快查表 { [id] = affixDef }
Config.AFFIX_MAP = {}
for _, affix in ipairs(Config.AFFIX_DEFS) do
    Config.AFFIX_MAP[affix.id] = affix
end

-- 词缀分类颜色 (旧三类, 兼容)
Config.AFFIX_CATEGORY_COLORS = {
    attack  = { 255, 120, 80 },   -- 橙红
    defense = { 80, 200, 120 },   -- 绿色
    utility = { 255, 215, 80 },   -- 金色
}

-- 六桶颜色 (词缀详情显示)
Config.AFFIX_BUCKET_COLORS = {
    base      = { 255, 160, 80 },   -- 暖橙 — 桶0 基础
    additive  = { 255, 120, 100 },  -- 橙红 — 桶2 A伤
    crit      = { 255, 220, 60 },   -- 金黄 — 桶3 暴击
    xDamage   = { 200, 100, 255 },  -- 紫色 — 桶5 X伤 (最强桶)
    overpower = { 80, 200, 255 },   -- 天蓝 — 桶6 压制
    speed     = { 120, 220, 160 },  -- 青绿 — 攻速
    proc      = { 255, 180, 220 },  -- 粉红 — 触发
}

-- 六桶短标签 (UI 中词缀名后显示)
Config.AFFIX_BUCKET_LABELS = {
    base      = "[基础]",
    additive  = "[A伤]",
    crit      = "[暴击]",
    xDamage   = "[X伤]",
    overpower = "[压制]",
    speed     = "[攻速]",
    proc      = "[触发]",
}

-- 强化词缀标记颜色 (金星)
Config.AFFIX_ENHANCED_COLOR = { 255, 200, 50 }

-- ============================================================================
-- P2: Item Power 与统一词缀系统 (D4 风格)
-- ============================================================================

-- IP 品质系数: 白/绿/蓝/紫/橙
Config.IP_QUALITY_MUL = { 0.50, 0.65, 0.80, 0.90, 1.00 }

-- (v4.0: IP_PER_UPGRADE 已移除, 升级不再改变 IP)

-- IP 区间 → roll 范围
-- 主线掉落品质 (6档, 封顶0.60; 副本/进阶/附魔/世界Boss 提供0.60→1.00)
Config.IP_BRACKETS = {
    { maxIP = 150,  minRoll = 0.15, maxRoll = 0.30 },  -- 新手期
    { maxIP = 300,  minRoll = 0.20, maxRoll = 0.38 },  -- 开始关注词缀
    { maxIP = 450,  minRoll = 0.25, maxRoll = 0.45 },  -- 学会比较装备
    { maxIP = 600,  minRoll = 0.28, maxRoll = 0.50 },  -- 追求特定词缀
    { maxIP = 800,  minRoll = 0.30, maxRoll = 0.55 },  -- 主线中后期
    { maxIP = 9999, minRoll = 0.33, maxRoll = 0.60 },  -- 主线天花板
}

-- 根据 IP 查询 roll 范围
function Config.GetIPBracket(ip)
    for _, b in ipairs(Config.IP_BRACKETS) do
        if ip <= b.maxIP then
            return b.minRoll, b.maxRoll
        end
    end
    local last = Config.IP_BRACKETS[#Config.IP_BRACKETS]
    return last.minRoll, last.maxRoll
end

-- 品质 → 词缀数量: 白1/绿2/蓝3/紫4/橙5
Config.AFFIX_COUNT_BY_QUALITY = { 1, 2, 3, 4, 5 }

-- Greater (大词缀) 概率 (仅橙色)
Config.AFFIX_GREATER_CHANCE = 0.15

-- (v4.0: UPGRADE_AFFIX_GROWTH 已移除, 改用里程碑机制)

-- 附魔费用
Config.ENCHANT_COST = {
    baseCost    = 50,
    ipMul       = 0.5,     -- 每点 IP +0.5 魂晶
    qualityMul  = { [4] = 1, [5] = 2 },
}

-- 统一词缀池: 合并旧 EQUIP_STATS + AFFIX_DEFS
-- base = IP=100 时参考值, ipScale = IP 敏感度
-- bucket: 六桶伤害管线分类 (同桶加算, 跨桶乘算)
--   "base"      = 桶0 基础伤害 (ATK)
--   "additive"  = 桶2 A伤 (元素增伤/易伤/精英猎手, 区内加算)
--   "crit"      = 桶3 暴击 (暴击率/暴击伤害)
--   "xDamage"   = 桶5 X伤 (独立乘算, 最强桶)
--   "overpower" = 桶6 压制 (基于当前HP+盾值)
--   "speed"     = 攻速 (独立乘区, 非D4桶)
--   "proc"      = 触发 (概率触发效果)
--   nil         = 非伤害类 (防御/功能)
Config.AFFIX_POOL = {
    -- ═══ 攻击类 (Attack, 13 条) ═══
    { id = "atk",           name = "攻击力",     category = "attack",  bucket = "base",     base = 40.0,   ipScale = 1.0,  isPercent = false,
      desc = "攻击力 +%s",           slots = { "weapon", "gloves", "ring", "necklace" } },
    { id = "spd",           name = "攻速",       category = "attack",  bucket = "speed",    base = 0.03,   ipScale = 0, isPercent = false,
      desc = "攻速 +%s",             slots = { "gloves", "boots", "ring" } },
    { id = "crit",          name = "暴击率",     category = "attack",  bucket = "crit",     base = 0.04,   ipScale = 0, isPercent = true,
      desc = "暴击率 +%s%%",         slots = { "gloves", "amulet", "necklace" } },
    { id = "critDmg",       name = "暴击伤害",   category = "attack",  bucket = "crit",     base = 0.08,   ipScale = 0.7, isPercent = true,
      desc = "暴击伤害 +%s%%",       slots = { "amulet", "ring", "weapon" } },
    { id = "skillDmg",      name = "技能伤害",   category = "attack",  bucket = "xDamage",  base = 0.06,   ipScale = 0.3, isPercent = true,
      desc = "技能伤害 +%s%%",       slots = { "weapon", "gloves", "necklace" } },
    { id = "vulnerableDmg", name = "易伤伤害",   category = "attack",  bucket = "additive", base = 0.04,   ipScale = 0.4, isPercent = true,
      desc = "易伤伤害 +%s%%",       slots = { "weapon", "ring", "necklace" } },
    { id = "fireDmg",       name = "火焰增伤",   category = "attack",  bucket = "additive", base = 0.05,   ipScale = 0.5, isPercent = true,
      desc = "火焰增伤 +%s%%",       slots = { "weapon", "gloves", "amulet" } },
    { id = "iceDmg",        name = "冰霜增伤",   category = "attack",  bucket = "additive", base = 0.05,   ipScale = 0.5, isPercent = true,
      desc = "冰霜增伤 +%s%%",       slots = { "weapon", "gloves", "amulet" } },
    { id = "lightningDmg",  name = "闪电增伤",   category = "attack",  bucket = "additive", base = 0.05,   ipScale = 0.5, isPercent = true,
      desc = "闪电增伤 +%s%%",       slots = { "weapon", "gloves", "amulet" } },
    { id = "combo_strike",  name = "连击",       category = "attack",  bucket = "proc",     base = 0.20,   ipScale = 0, isPercent = true,
      desc = "普攻有%s%%概率连续攻击2次", slots = { "weapon", "gloves" } },
    { id = "elite_hunter",  name = "精英猎手",   category = "attack",  bucket = "additive", base = 0.25,   ipScale = 0.3, isPercent = true,
      desc = "对Boss/精英怪伤害+%s%%",   slots = { "weapon", "ring" } },
    { id = "overpowerDmg",  name = "压制伤害",   category = "attack",  bucket = "overpower", base = 0.05,  ipScale = 0, isPercent = true,
      desc = "压制伤害 +%s%%",       slots = { "weapon", "gloves", "ring" } },
    { id = "range",         name = "攻击范围",   category = "attack",  bucket = "range",    base = 8.0,   ipScale = 0.5, isPercent = false,
      desc = "攻击范围 +%s",         slots = { "weapon", "gloves", "ring" } },

    -- ═══ 防御类 (Defense, 11 条) ═══
    { id = "hp",            name = "生命值",     category = "defense", base = 640.0,  ipScale = 1.0,  isPercent = false,
      desc = "生命值 +%s",           slots = { "amulet", "boots", "necklace", "ring" } },
    { id = "def",           name = "防御力",     category = "defense", base = 26.0,   ipScale = 1.0,  isPercent = false,
      desc = "防御力 +%s",           slots = { "boots", "amulet", "ring" } },
    { id = "hpPct",         name = "生命百分比", category = "defense", base = 0.06,   ipScale = 0, isPercent = true,
      desc = "生命值 +%s%%",         slots = { "amulet", "boots", "necklace" } },
    { id = "hpRegen",       name = "生命回复",   category = "defense", base = 13.4,   ipScale = 1.0,  isPercent = false,
      desc = "生命回复 +%s/秒",      slots = { "boots", "necklace", "amulet" } },
    { id = "lifeSteal",     name = "生命偷取",   category = "defense", base = 0.016,  ipScale = 0, isPercent = true,
      desc = "生命偷取 +%s%%",       slots = { "weapon", "ring" } },
    { id = "shldPct",       name = "护盾比例",   category = "defense", base = 0.02,   ipScale = 0, isPercent = true,
      desc = "护盾比例 +%s%%",       slots = { "amulet", "boots" } },
    { id = "fireRes",       name = "火焰抗性",   category = "defense", base = 0.16,   ipScale = 0, isPercent = true,
      desc = "火焰抗性 +%s%%",       slots = { "amulet", "boots", "necklace" } },
    { id = "iceRes",        name = "冰霜抗性",   category = "defense", base = 0.16,   ipScale = 0, isPercent = true,
      desc = "冰霜抗性 +%s%%",       slots = { "amulet", "boots", "necklace" } },
    { id = "lightningRes",  name = "闪电抗性",   category = "defense", base = 0.16,   ipScale = 0, isPercent = true,
      desc = "闪电抗性 +%s%%",       slots = { "gloves", "amulet", "necklace" } },
    { id = "last_stand",    name = "绝境",       category = "defense", base = 0.30,   ipScale = 0, isPercent = true,
      desc = "生命低于20%%时减伤+%s%%",   slots = { "amulet", "boots" } },
    { id = "kill_heal",     name = "击杀回复",   category = "defense", base = 0.02,   ipScale = 0, isPercent = true,
      desc = "击杀敌人回复%s%%最大生命",  slots = { "weapon", "ring" } },

    -- ═══ 功能类 (Utility, 6 条) ═══
    { id = "luck",          name = "幸运",       category = "utility", base = 0.02,   ipScale = 0, isPercent = true,
      desc = "幸运 +%s%%",           slots = { "ring", "necklace" } },
    { id = "skillCdReduce", name = "冷却缩减",   category = "utility", base = 0.04,   ipScale = 0, isPercent = true,
      desc = "技能冷却缩减 +%s%%",   slots = { "necklace", "amulet" } },
    { id = "crit_surge",    name = "暴击强化",   category = "attack",  bucket = "proc",     base = 0.35,   ipScale = 0, isPercent = true,
      desc = "暴击时额外造成%s%%攻击力的固定伤害", slots = { "gloves", "amulet" } },
    { id = "greed",         name = "贪婪",       category = "utility", base = 0.30,   ipScale = 0, isPercent = true,
      desc = "金币掉落+%s%%",        slots = { "ring", "necklace" } },
    { id = "scholar",       name = "博学",       category = "utility", base = 0.20,   ipScale = 0, isPercent = true,
      desc = "经验获取+%s%%",        slots = { "necklace" } },
    { id = "lucky_star",    name = "幸运星",     category = "utility", base = 0.15,   ipScale = 0, isPercent = true,
      desc = "装备掉落品质提升概率+%s%%", slots = { "necklace", "ring" } },
}

-- 统一词缀快查表 { [id] = affixDef }  (新系统用, 不覆盖旧 AFFIX_MAP)
Config.AFFIX_POOL_MAP = {}
for _, aff in ipairs(Config.AFFIX_POOL) do
    Config.AFFIX_POOL_MAP[aff.id] = aff
end

-- 槽位词缀池 { [slotId] = { "atk", "crit", ... } }  (自动构建)
Config.AFFIX_SLOT_POOLS = {}
for _, aff in ipairs(Config.AFFIX_POOL) do
    for _, slotId in ipairs(aff.slots) do
        Config.AFFIX_SLOT_POOLS[slotId] = Config.AFFIX_SLOT_POOLS[slotId] or {}
        table.insert(Config.AFFIX_SLOT_POOLS[slotId], aff.id)
    end
end

-- 词缀值计算
---@param affixDef table AFFIX_POOL 中的词缀定义
---@param ip number 装备的 Item Power
---@param roll number roll 系数 (0~1)
---@return number value
function Config.CalcAffixValue(affixDef, ip, roll)
    local ipFactor = 1 + (ip / 100 - 1) * affixDef.ipScale
    return affixDef.base * ipFactor * roll
end

-- ============================================================================
-- 旧装备槽位 (Phase 2 重写前保留 mainPool/subPool 兼容)
-- ============================================================================

-- 装备槽位 (六槽位)
-- mainPool: 主词条候选(3选1)   subPool: 副词条候选(6选N)
Config.EQUIP_SLOTS = {
    { id = "weapon",   name = "武器", icon = "W",
      mainPool = { "atk", "vulnerableDmg", "fireDmg", "iceDmg", "lightningDmg" },
      subPool  = { "spd", "crit", "critDmg", "hp", "lifeSteal", "luck", "skillDmg", "fireRes", "iceRes", "lightningRes", "fireDmg", "iceDmg", "lightningDmg" } },
    { id = "gloves",   name = "手套", icon = "G",
      mainPool = { "spd", "crit", "skillDmg" },
      subPool  = { "atk", "critDmg", "vulnerableDmg", "def", "hpRegen", "luck", "skillDmg", "hpPct", "lightningRes", "fireDmg", "iceDmg", "lightningDmg" } },
    { id = "amulet",   name = "护符", icon = "A",
      mainPool = { "crit", "hpPct", "critDmg", "fireDmg", "iceDmg", "lightningDmg" },
      subPool  = { "atk", "spd", "critDmg", "def", "shldPct", "luck", "fireRes", "iceRes", "lightningRes", "fireDmg", "iceDmg", "lightningDmg" } },
    { id = "ring",     name = "戒指", icon = "R",
      mainPool = { "critDmg", "vulnerableDmg", "atk" },
      subPool  = { "spd", "crit", "hp", "hpRegen", "shldPct", "hpPct", "skillDmg", "lightningRes", "fireDmg", "iceDmg", "lightningDmg" } },
    { id = "boots",    name = "靴子", icon = "B",
      mainPool = { "def", "hpPct", "spd" },
      subPool  = { "atk", "crit", "critDmg", "hpRegen", "lifeSteal", "fireRes", "iceRes", "lightningRes", "fireDmg", "iceDmg", "lightningDmg" } },
    { id = "necklace", name = "项链", icon = "N",
      mainPool = { "luck", "skillDmg", "vulnerableDmg" },
      subPool  = { "atk", "spd", "crit", "hp", "def", "shldPct", "hpPct", "fireRes", "iceRes", "lightningRes", "fireDmg", "iceDmg", "lightningDmg" } },
}

-- (v4.0: WEAPON_ELEMENT_WEIGHTS 已移除)

-- 元素增伤词条列表 (装备生成时随机选择一种)
Config.ELEM_DMG_STATS = { "fireDmg", "iceDmg", "lightningDmg" }
-- 非物理元素数量 (用于全元素增伤换算)
Config.ELEM_COUNT = 3

-- 套装图标路径
Config.SET_ICON_PATHS = {
    -- Cross-chapter sets (Batch1)
    swift_hunter     = "swift_hunter_weapon.png",
    fission_force    = "fission_force_weapon.png",
    shadow_hunter    = "shadow_hunter_weapon.png",
    iron_bastion     = "iron_bastion_weapon.png",
    dragon_fury      = "dragon_fury_weapon.png",
    rune_weaver      = "rune_weaver_weapon.png",
    -- Ch13 sets
    lava_conqueror   = "lava_conqueror_weapon.png",
    permafrost_heart = "permafrost_heart_weapon.png",
}

-- 装备槽位图标路径
-- 属性图标路径
Config.STAT_ICON_PATHS = {
    -- 4 核心属性 (P1 重构)
    STR     = "stat_vit_20260306131842.png",   -- 力量 (复用体力图标, TODO: 替换)
    DEX     = "stat_spd_20260306131739.png",   -- 敏捷 (复用攻速图标, TODO: 替换)
    INT     = "stat_crit_20260306131741.png",  -- 智力 (复用暴击图标, TODO: 替换)
    WIL     = "stat_ten_20260306131838.png",   -- 意志 (复用韧性图标, TODO: 替换)
    -- 装备/面板属性图标 (保留)
    atk     = "stat_atk_20260306131755.png",
    spd     = "stat_spd_20260306131739.png",
    crit    = "stat_crit_20260306131741.png",
    critDmg = "stat_critdmg_20260306131740.png",
    range   = "stat_range_20260306131843.png",
    luck    = "stat_luck_20260306131906.png",
    hp      = "stat_vit_20260306131842.png",
    def     = "stat_vit_20260306131842.png",
}

-- 区块图标路径
Config.SECTION_ICON_PATHS = {
    level    = "sec_level_20260306132007.png",
    survival = "sec_survival_20260306132004.png",
    resist   = "sec_resist_20260306132002.png",
    element  = "sec_element_20260306132000.png",
    setbonus = "sec_setbonus_20260306132006.png",
}

Config.EQUIP_ICON_PATHS = {
    weapon   = "equip_weapon_20260306085701.png",
    gloves   = "equip_gloves_20260306085716.png",
    amulet   = "equip_amulet_20260306085720.png",
    ring     = "equip_ring_20260306085657.png",
    boots    = "equip_boots_20260306085715.png",
    necklace = "equip_necklace_20260306085658.png",
}

-- 套装专属部位图标 (setId → slotId → filename)
-- 优先查此表, 不存在则 fallback 到 EQUIP_ICON_PATHS 通用图标
Config.EQUIP_SET_SLOT_ICONS = {
    -- Cross-chapter sets (Batch1)
    swift_hunter = {
        weapon   = "swift_hunter_weapon.png",
        gloves   = "swift_hunter_gloves.png",
        amulet   = "swift_hunter_amulet.png",
        ring     = "swift_hunter_ring.png",
        boots    = "swift_hunter_boots.png",
        necklace = "swift_hunter_necklace.png",
    },
    fission_force = {
        weapon   = "fission_force_weapon.png",
        gloves   = "fission_force_gloves.png",
        amulet   = "fission_force_amulet.png",
        ring     = "fission_force_ring.png",
        boots    = "fission_force_boots.png",
        necklace = "fission_force_necklace.png",
    },
    shadow_hunter = {
        weapon   = "shadow_hunter_weapon.png",
        gloves   = "shadow_hunter_gloves.png",
        amulet   = "shadow_hunter_amulet.png",
        ring     = "shadow_hunter_ring.png",
        boots    = "shadow_hunter_boots.png",
        necklace = "shadow_hunter_necklace.png",
    },
    iron_bastion = {
        weapon   = "iron_bastion_weapon.png",
        gloves   = "iron_bastion_gloves.png",
        amulet   = "iron_bastion_amulet.png",
        ring     = "iron_bastion_ring.png",
        boots    = "iron_bastion_boots.png",
        necklace = "iron_bastion_necklace.png",
    },
    dragon_fury = {
        weapon   = "dragon_fury_weapon.png",
        gloves   = "dragon_fury_gloves.png",
        amulet   = "dragon_fury_amulet.png",
        ring     = "dragon_fury_ring.png",
        boots    = "dragon_fury_boots.png",
        necklace = "dragon_fury_necklace.png",
    },
    rune_weaver = {
        weapon   = "rune_weaver_weapon.png",
        gloves   = "rune_weaver_gloves.png",
        amulet   = "rune_weaver_amulet.png",
        ring     = "rune_weaver_ring.png",
        boots    = "rune_weaver_boots.png",
        necklace = "rune_weaver_necklace.png",
    },
    -- Ch13 sets
    lava_conqueror = {
        weapon   = "lava_conqueror_weapon.png",
        gloves   = "lava_conqueror_gloves.png",
        amulet   = "lava_conqueror_amulet.png",
        ring     = "lava_conqueror_ring.png",
        boots    = "lava_conqueror_boots.png",
        necklace = "lava_conqueror_necklace.png",
    },
    permafrost_heart = {
        weapon   = "permafrost_heart_weapon.png",
        gloves   = "permafrost_heart_gloves.png",
        amulet   = "permafrost_heart_amulet.png",
        ring     = "permafrost_heart_ring.png",
        boots    = "permafrost_heart_boots.png",
        necklace = "permafrost_heart_necklace.png",
    },
}

-- Buff 图标路径 (buff id → filename)
Config.BUFF_ICON_PATHS = {
    -- (Deleted single-chapter set buff icons removed; retained sets use inline buff definitions)
}

-- GetEquipSlotIcon → ConfigCalc.lua

-- ============================================================================
-- 套装定义 (仅保留跨章节套装 + Ch13套装)
-- ============================================================================
Config.EQUIP_SETS = {
    -- ==================== 第十三章套装 ====================
    {
        id = "lava_conqueror",
        name = "熔岩征服者",
        chapter = 13,
        color = { 255, 100, 30 },
        bonuses = {
            [2] = { desc = "火伤+30%,攻速+12%。攻击25%几率点燃(4%ATK/秒,5秒,叠3层)",
                stats = { fireDmg = 0.30 },
                statsMul = { atkSpeed = 0.12 },
                buff = { id = "lava_conqueror_2", trigger = "onHit",
                    burnChance = 0.25, burnDmgPct = 0.04, burnDur = 5.0, burnMaxStacks = 3 },
            },
            [4] = { desc = "点燃满3层→熔岩爆发450%ATK火伤+清层+扩散1层(半径80,CD5秒)",
                buff = { id = "lava_conqueror_4", trigger = "onBurnFullStacks",
                    burstDmgMul = 4.5, burstElement = "fire",
                    spreadBurn = true, spreadRadius = 80, spreadStacks = 1, cd = 5.0 },
            },
            [6] = { desc = "熔岩爆发后6秒「熔岩领主」:火伤+40%+25%溅射+暴击火焰冲击100%ATK(CD28秒)",
                buff = { id = "lava_conqueror_6", trigger = "postBurst",
                    fireDmgBonus = 0.40, splashPct = 0.25,
                    critFireDmgMul = 1.0, critFireRadius = 60,
                    duration = 6.0, cd = 28.0 },
            },
        },
    },
    {
        id = "permafrost_heart",
        name = "极寒之心",
        chapter = 13,
        color = { 100, 200, 240 },
        bonuses = {
            [2] = { desc = "冰抗+40%,雷抗+25%,HP+20%。受冰/雷伤回复2%HP",
                resist = { ice = 0.40, lightning = 0.25 },
                statsMul = { hp = 0.20 },
                buff = { id = "permafrost_heart_2", trigger = "onIceLightningDmg", healPct = 0.02 },
            },
            [4] = { desc = "受致命伤→极寒护盾(6秒无敌+回55%HP+冻结3秒+清减速),每关1次",
                buff = { id = "permafrost_heart_4", trigger = "onTakeDmg",
                    fatalProtect = true, fatalInvulDur = 6.0,
                    fatalHealPct = 0.55, freezeDur = 3.0, freezeRadius = 100,
                    clearSlow = true, perStage = true },
            },
            [6] = { desc = "极寒护盾后12秒「寒冰化身」:减伤40%+回5%HP/秒+30%反弹冰伤150%ATK+免减速(CD32秒)",
                buff = { id = "permafrost_heart_6", trigger = "postFatal",
                    dmgReduce = 0.40, regenPctPerSec = 0.05,
                    reflectChance = 0.30, reflectDmgMul = 1.5, reflectElement = "ice",
                    slowImmune = true, duration = 12.0, cd = 32.0 },
            },
        },
    },
    -- ╔════════════════════════════════════════════════════════════╗
    -- ║  跨章节套装 (每4章2套, 共6套)                             ║
    -- ╚════════════════════════════════════════════════════════════╝

    -- ── ch1-4 清怪期: 攻速清怪 + AOE清怪 ──
    {
        id = "swift_hunter",
        name = "迅捷猎手",
        chapter = 1, chapterRange = { 1, 4 },
        color = { 255, 200, 50 },
        bonuses = {
            [2] = { desc = "攻速+12%, 普攻命中回复0.5%HP",
                statsMul = { atkSpeed = 0.12 },
                buff = { id = "swift_hunter_2", trigger = "onHit", healPct = 0.005 },
            },
            [4] = { desc = "连续命中同一目标每次伤害+3%(最多10层=+30%,换目标清零)",
                buff = { id = "swift_hunter_4", trigger = "onHitSameTarget",
                    stackDmgPct = 0.03, maxStacks = 10, resetOnSwitch = true },
            },
            [6] = { desc = "叠满10层触发连击风暴: 3秒攻速翻倍+分裂弹+3(CD20秒)",
                buff = { id = "swift_hunter_6", trigger = "fullStacks",
                    atkSpeedMul = 2.0, extraSplit = 3, duration = 3.0, cd = 20.0 },
            },
        },
    },
    {
        id = "fission_force",
        name = "裂变之力",
        chapter = 1, chapterRange = { 1, 4 },
        color = { 80, 200, 255 },
        bonuses = {
            [2] = { desc = "普攻伤害+10%, 每命中敌人获得1点裂变能量(上限50)",
                stats = { normalAtkDmg = 0.10 },
                buff = { id = "fission_force_2", trigger = "onHit",
                    energyPerHit = 1, maxEnergy = 50 },
            },
            [4] = { desc = "能量满50自动释放裂变脉冲: 150%ATK AOE+清空能量+2秒减速30%",
                buff = { id = "fission_force_4", trigger = "energyFull",
                    pulseDmgMul = 1.5, pulseRadius = 60,
                    slowRate = 0.30, slowDur = 2.0 },
            },
            [6] = { desc = "裂变脉冲伤害改为250%ATK+命中每敌回1%HP+脉冲后5秒攻速+20%(CD10秒)",
                buff = { id = "fission_force_6", trigger = "energyFull",
                    pulseDmgMul = 2.5, healPerEnemyPct = 0.01,
                    postPulseAtkSpeed = 0.20, postPulseDur = 5.0, cd = 10.0 },
            },
        },
    },

    -- ── ch5-8 打Boss期: 暴击爆发 + 坦克反击 ──
    {
        id = "shadow_hunter",
        name = "暗影猎手",
        chapter = 5, chapterRange = { 5, 8 },
        color = { 80, 50, 120 },
        bonuses = {
            [2] = { desc = "暴击伤害+25%, 暴击命中获得1层暗影(上限30)",
                statsMul = { critDmg = 0.25 },
                buff = { id = "shadow_hunter_2", trigger = "onCrit",
                    shadowPerCrit = 1, maxShadow = 30 },
            },
            [4] = { desc = "暗影满30层自动释放'暗影爆发': 200%ATK AOE+吸血30%+清空暗影",
                buff = { id = "shadow_hunter_4", trigger = "shadowFull",
                    burstDmgMul = 2.0, burstRadius = 70,
                    lifestealPct = 0.30 },
            },
            [6] = { desc = "暗影爆发后10秒内暴击率+20%+每次暴击回复0.3%HP(CD15秒)",
                buff = { id = "shadow_hunter_6", trigger = "postBurst",
                    critBonus = 0.20, critHealPct = 0.003, duration = 10.0, cd = 15.0 },
            },
        },
    },
    {
        id = "iron_bastion",
        name = "铁壁要塞",
        chapter = 5, chapterRange = { 5, 8 },
        color = { 140, 160, 180 },
        bonuses = {
            [2] = { desc = "受击时获得等于伤害5%的护盾(最多叠加至30%maxHP), DEF+10%",
                statsMul = { def = 0.10 },
                buff = { id = "iron_bastion_2", trigger = "onTakeDmg",
                    shieldPct = 0.05, maxShieldPct = 0.30 },
            },
            [4] = { desc = "护盾超过20%maxHP时, 溢出部分每1%转化为+2%攻击力(最多+20%ATK)",
                buff = { id = "iron_bastion_4", trigger = "passive",
                    shieldThreshold = 0.20, overflowToAtk = 0.02, maxAtkBonus = 0.20 },
            },
            [6] = { desc = "护盾被击碎时爆炸: 造成已消耗护盾量200%的伤害+3秒50%减伤(CD10秒)",
                buff = { id = "iron_bastion_6", trigger = "onShieldBreak",
                    shieldBurstMul = 2.0, burstRadius = 60,
                    dmgReduceDur = 3.0, dmgReducePct = 0.50, cd = 10.0 },
            },
        },
    },

    -- ── ch9-12 技能期: 普攻技能交替 + 纯技能连锁 ──
    {
        id = "dragon_fury",
        name = "龙息之怒",
        chapter = 9, chapterRange = { 9, 12 },
        color = { 255, 80, 30 },
        bonuses = {
            [2] = { desc = "普攻和技能伤害共享增伤池: 任一伤害+15%",
                stats = { atkDmg = 0.15, skillDmg = 0.15 },
            },
            [4] = { desc = "普攻命中3次后下次技能+50%; 技能命中后3次普攻+30%(交替循环)",
                buff = { id = "dragon_fury_4", trigger = "alternating",
                    atkHitsForSkill = 3, skillBonusToSkill = 0.50,
                    skillBonusToAtk = 0.30, atkBonusHits = 3 },
            },
            [6] = { desc = "交替3轮触发'龙息': 400%ATK全屏火伤+获得8秒'龙威'buff全伤害+20%(CD18秒)",
                buff = { id = "dragon_fury_6", trigger = "cycleComplete",
                    cyclesRequired = 3, breathDmgMul = 4.0,
                    breathElement = "fire", allDmgBonus = 0.20,
                    allDmgDur = 8.0, cd = 18.0 },
            },
        },
    },
    {
        id = "rune_weaver",
        name = "符文编织",
        chapter = 9, chapterRange = { 9, 12 },
        color = { 100, 150, 255 },
        bonuses = {
            [2] = { desc = "技能CD缩减+15%, 每次释放技能获得1层'符文'(上限5)",
                statsMul = { skillCdReduce = 0.15 },
                buff = { id = "rune_weaver_2", trigger = "onSkillCast",
                    runePerCast = 1, maxRunes = 5 },
            },
            [4] = { desc = "符文满5层自动消耗: 随机一个技能CD-5秒+下次技能伤害+160%",
                buff = { id = "rune_weaver_4", trigger = "runesFull",
                    cdReduceRandom = 5.0, nextSkillDmgBonus = 1.60 },
            },
            [6] = { desc = "符文消耗后6秒'符文共鸣': 技能伤害+50%+技能命中回复1%HP+技能CD流速翻倍(CD18秒)",
                buff = { id = "rune_weaver_6", trigger = "postRuneConsume",
                    skillDmgBonus = 0.50, skillHealPct = 0.01,
                    cdFlowMul = 2.0, duration = 6.0, cd = 18.0 },
            },
        },
    },
}

-- 套装ID快速查找
Config.EQUIP_SET_MAP = {}
for _, s in ipairs(Config.EQUIP_SETS) do
    Config.EQUIP_SET_MAP[s.id] = s
end

-- 当前章节可掉落的套装 (蓝品及以上, 50%概率带套装标签)
-- v12: 普通掉落/锻造不再产出套装，以下常量仅供参考
Config.SET_DROP_CHANCE = 0.5

-- ============================================================================
-- 套装秘境配置
-- ============================================================================

Config.SET_DUNGEON = {
    UNLOCK_CHAPTER    = 5,      -- 解锁章节 (通关第5章)
    MAX_DAILY_ATTEMPTS = 3,     -- 每日次数
    FIGHT_DURATION     = 120,   -- 战斗时长 (秒)
    MONSTER_SCALE      = 0.85,  -- 普通难度怪物缩放 (相对maxChapter末关)
    HARD_MONSTER_SCALE = 1.20,  -- 困难难度怪物缩放
    HARD_UNLOCK_CHAPTER = 9,    -- 困难难度解锁章节
    ELITE_HP_MUL       = 3.0,   -- 精英怪HP倍率
    SPAWN_COUNT        = 25,    -- 普通怪数量
    ELITE_COUNT        = 3,     -- 精英怪数量

    -- 品质掉落概率 [蓝, 紫, 橙] (qualityIdx = 3, 4, 5)
    QUALITY_WEIGHTS_NORMAL = { 0.60, 0.35, 0.05 },
    QUALITY_WEIGHTS_HARD   = { 0.30, 0.50, 0.20 },

    -- 套装解锁批次 { minChapter, setIds }
    UNLOCK_BATCHES = {
        { minChapter = 5,  setIds = { "swift_hunter", "fission_force" } },
        { minChapter = 9,  setIds = { "shadow_hunter", "iron_bastion" } },
        { minChapter = 13, setIds = { "dragon_fury", "rune_weaver" } },
        { minChapter = 13, setIds = { "lava_conqueror", "permafrost_heart" } },
    },
}

-- (v3.0: 旧 Config.SKILLS 已移除, 技能定义统一走 SkillTreeConfig.lua)
-- 向后兼容: 部分UI/存档代码可能引用 Config.SKILLS, 置空表
Config.SKILLS = {}

-- ============================================================================
-- 装备锻造配置
-- ============================================================================

-- 分段定义: 每4章一段, 对应通用套装池
Config.FORGE_SEGMENTS = {
    { id = 1, name = "荒原·炎狱",   chapterRange = { 1, 4 },  color = { 200, 120, 50 } },
    { id = 2, name = "深海·雷霆",   chapterRange = { 5, 8 },  color = { 60, 140, 220 } },
    { id = 3, name = "圣域·深渊",   chapterRange = { 9, 12 }, color = { 180, 80, 220 } },
}

-- 掉落批次: 每4章一批, 决定该章节可掉落哪些套装
-- 与 FORGE_SEGMENTS 一致, 超出范围的章节独立成批
Config.DROP_BATCHES = {
    { 1, 4 },
    { 5, 8 },
    { 9, 12 },
    { 13, 16 },
}

-- GetDropBatch, IsSetInBatch → ConfigCalc.lua

-- 锻造材料消耗 (替代旧版单一强化石)
Config.FORGE_MATERIAL_COST = {
    iron = 30, crystal = 15, wraith = 5,
}
Config.FORGE_MATERIAL_COST_LOCK = {
    iron = 60, crystal = 30, wraith = 10,
}
-- 旧版兼容字段 (部分UI可能引用)
Config.FORGE_STONE_COST       = 160
Config.FORGE_STONE_COST_LOCK  = 320
Config.FORGE_GOLD_BASE        = 30    -- 金币 = FORGE_GOLD_BASE × sqrt(bossScaleMul)
Config.FORGE_GOLD_BASE_LOCK   = 60    -- 锁定部位时双倍

-- 每日锻造次数
Config.FORGE_FREE_PER_DAY  = 1    -- 每日免费次数
Config.FORGE_PAID_PER_DAY  = 10   -- 每日付费次数
Config.FORGE_TOTAL_PER_DAY = 11   -- 总次数

-- 锻造品质 (固定橙色)
Config.FORGE_QUALITY_IDX = 5

-- GetForgeSegmentScaleMul, GetForgeGoldCost, GetForgeStoneCost → ConfigCalc.lua

-- ============================================================================
-- 药水商店配置
-- ============================================================================

-- 药水类型定义
Config.POTION_TYPES = {
    { id = "exp",  name = "经验药水", color = { 80, 140, 255 },  statDesc = "经验获取" },
    { id = "hp",   name = "生命药水", color = { 255, 80, 80 },   statDesc = "生命上限" },
    { id = "atk",  name = "攻击药水", color = { 255, 160, 40 },  statDesc = "伤害增幅" },
    { id = "luck", name = "幸运药水", color = { 255, 215, 0 },   statDesc = "幸运值" },
}

-- 药水尺寸定义 (越大效果越好持续越久)
Config.POTION_SIZES = {
    { id = "s", name = "小", duration = 1800, costMul = 1.0,  valueMul = 1.0 },  -- 30分钟
    { id = "m", name = "中", duration = 3600, costMul = 2.5,  valueMul = 1.4 },  -- 60分钟 (atk: 5%*1.4=7%)
    { id = "l", name = "大", duration = 7200, costMul = 5.0,  valueMul = 2.0 },  -- 120分钟 (atk: 5%*2.0=10%)
}

-- 药水效果值 (基础值, 实际 = base * sizeMul)
Config.POTION_VALUES = {
    exp  = 0.30,   -- +30% 经验获取
    hp   = 0.10,   -- +10% 生命上限 (小10%/中20%/大30%, 独立倍率见 HP_POTION_MUL)
    atk  = 0.05,   -- +5% 伤害增幅 (比例增伤)
    luck = 0.10,   -- +10% 幸运
}

-- 生命药水独立倍率 (不使用通用 sizeMul，精确控制为 10%/20%/30%)
Config.HP_POTION_MUL = { s = 1.0, m = 2.0, l = 3.0 }

-- 药水基础价格 (小瓶价格)
Config.POTION_BASE_COST = {
    exp  = 150,
    hp   = 150,
    atk  = 200,
    luck = 250,
}

-- 药水图标路径
Config.POTION_ICONS = {
    exp_s  = "potion_exp_s_20260307034458.png",
    exp_m  = "potion_exp_m_20260307034503.png",
    exp_l  = "potion_exp_l_20260307034454.png",
    hp_s   = "potion_hp_s_20260307034506.png",
    hp_m   = "potion_hp_m_20260307034451.png",
    hp_l   = "potion_hp_l_20260307034505.png",
    atk_s  = "potion_atk_s_20260307034509.png",
    atk_m  = "potion_atk_m_20260307034458.png",
    atk_l  = "potion_atk_l_20260307034459.png",
    luck_s = "potion_luck_s_20260307034605.png",
    luck_m = "potion_luck_m_20260307034556.png",
    luck_l = "potion_luck_l_20260307034555.png",
}

-- 金币图标
Config.GOLD_ICON = "icon_gold_20260307034449.png"
-- 排行榜图标
Config.LEADERBOARD_ICON = "icon_leaderboard_20260307034600.png"

-- 技能图标路径 (v3.0: 新技能树图标)
Config.SKILL_ICON_PATHS = {
    -- 通用 / 基础
    default                = "skill_elem_blast_20260307021441.png",             -- 默认技能图标

    -- 火焰系
    fire_bolt              = "image/skill_fireball_20260410082151.png",          -- 火焰弹
    fireball               = "skill_fire_react_burn_20260309035341.png",        -- 火球术
    incinerate             = "image/skill_incinerate_20260410114515.png",       -- 焚烧
    firewall               = "image/skill_firewall_20260410165325.png",         -- 火墙
    fire_storm             = "skill_fire_storm_20260309035628.png",             -- 烈焰风暴
    meteor                 = "skill_arcane_meteor_20260309035727.png",          -- 陨石坠落
    hydra                  = "image/skill_hydra_20260410114526.png",            -- 九头蛇
    fire_affinity          = "skill_fire_reaction_boost_20260309035339.png",    -- 火焰亲和
    burn_mastery           = "skill_fire_burn_spread_20260309035335.png",       -- 燃烧精通
    flame_shield           = "skill_fire_reaction_boost_20260309035339.png",    -- 烈焰护盾
    fire_mastery           = "skill_fire_storm_empower_20260309035626.png",     -- 火焰精通
    kp_combustion          = "image/skill_kp_combustion_20260410115522.png",    -- 燃爆

    -- 冰霜系
    frost_bolt             = "image/skill_frost_bolt_20260410082331.png",       -- 冰霜弹
    ice_shards             = "image/skill_ice_shard_20260410082141.png",        -- 冰碎片
    frost_nova             = "image/skill_frost_nova_20260410114602.png",       -- 冰霜新星
    frozen_orb             = "image/skill_frost_orb_20260410082117.png",        -- 冰封球
    kp_avalanche           = "image/skill_avalanche_20260410082125.png",        -- 雪崩
    kp_shatter             = "image/skill_shatter_20260410082121.png",          -- 碎冰
    frost_rain             = "skill_frost_rain_20260307021555.png",             -- 冰霜领域
    ice_barrage            = "skill_ice_barrage_20260309035625.png",            -- 冰晶弹幕
    blizzard               = "skill_ice_barrage_shatter_20260309035629.png",    -- 暴风雪
    ice_affinity           = "skill_ice_reaction_boost_20260309035337.png",     -- 冰霜亲和
    deep_freeze            = "skill_ice_barrage_freeze_20260309035633.png",     -- 深度冻结
    ice_armor              = "image/skill_ice_armor_20260410114501.png",        -- 冰甲
    ice_mastery            = "skill_frost_power_20260307021552.png",            -- 冰霜精通

    -- 闪电系
    spark                  = "image/skill_electric_spark_20260410082111.png",    -- 电花
    arcane_strike          = "image/skill_arc_strike_20260410093623.png",       -- 电弧打击
    charged_bolts          = "image/skill_charged_bolts_20260410114654.png",    -- 充能弹
    chain_lightning        = "skill_arcane_dual_catalyst_20260309035439.png",   -- 闪电链
    lightning_spear        = "image/skill_lightning_spear_20260410114648.png",  -- 闪电矛
    teleport               = "image/skill_teleport_20260410114759.png",         -- 传送
    thunderstorm           = "skill_fire_storm_afterburn_20260309035632.png",   -- 雷暴
    thunder_storm          = "image/skill_thunder_storm_20260410114648.png",    -- 雷暴(别名)
    ball_lightning          = "skill_doom_cascade_20260309035730.png",           -- 球状闪电
    energy_pulse           = "image/skill_energy_pulse_20260410114648.png",     -- 能量脉冲
    lightning_affinity     = "skill_arcane_reaction_boost_20260309035437.png",  -- 闪电亲和
    charged_strikes        = "skill_poison_stack_bonus_20260309035336.png",     -- 蓄电打击
    static_field           = "skill_water_deep_slow_20260309035435.png",       -- 静电力场
    lightning_mastery      = "skill_arcane_reaction_boost_20260309035437.png",  -- 闪电精通
    kp_overcharge          = "image/skill_kp_overcharge_20260410115522.png",    -- 过载

    -- 关键被动
    kp_esu_blessing        = "image/skill_kp_esu_blessing_20260410115531.png",  -- 伊苏祝福
    kp_align_elements      = "image/skill_kp_align_elements_20260410115614.png", -- 元素归一
    kp_vyr_mastery         = "image/skill_kp_vyr_mastery_20260410115626.png",   -- 维尔精通
}

-- 重置属性/技能点消耗 (魂晶 = 已分配点数 × 单价)
Config.RESET_ATTR_UNIT_COST = 2   -- 每点属性消耗2魂晶
Config.RESET_SKILL_UNIT_COST = 3  -- 每退还1技能点消耗3魂晶 (降级/重置共用)

-- 背包容量
Config.INVENTORY_SIZE = 20          -- 初始背包容量
Config.INVENTORY_EXPAND_SLOTS = 4   -- 每次扩容增加的格子数
Config.INVENTORY_MAX_SIZE = 100     -- 背包容量上限

-- 魂晶 (背包扩容材料)
Config.SOUL_CRYSTAL = {
    name = "魂晶",
    color = { 160, 80, 255 },       -- 紫色
    dropPerBoss = 1,                 -- 每次击杀Boss掉落数量
}
-- 扩容消耗公式: 第N次扩容消耗 = baseCost + (N-1) * costIncrement
Config.EXPAND_BASE_COST = 100       -- 第一次扩容消耗100魂晶
Config.EXPAND_COST_INCREMENT = 50   -- 每次递增50 (第二次150, 第三次200...)

-- ============================================================================
-- 通用道具定义
-- ============================================================================
Config.ITEMS = {
    {
        id = "attr_reset",
        name = "属性洗点券",
        desc = "使用后重置所有属性点分配，免费回收全部已分配点数",
        icon = "Textures/Items/item_attr_reset.png",
        maxStack = 999,
        color = { 255, 200, 80 },  -- 金色
    },
    {
        id = "skill_reset",
        name = "技能重置券",
        desc = "使用后重置所有技能点分配，免费回收全部已分配点数",
        icon = "Textures/Items/item_skill_reset.png",
        maxStack = 999,
        color = { 180, 100, 255 },  -- 紫色
    },
    {
        id = "exp_potion_10m",
        name = "速升药水·初",
        desc = "使用后立即获得 1000万 经验值",
        icon = "item_exp_potion_10m_20260309142542.png",
        maxStack = 999,
        color = { 100, 220, 100 },  -- 绿色
        expValue = 10000000,
    },
    {
        id = "exp_potion_100m",
        name = "速升药水·中",
        desc = "使用后立即获得 1亿 经验值",
        icon = "item_exp_potion_100m_20260309142547.png",
        maxStack = 999,
        color = { 80, 140, 255 },  -- 蓝色
        expValue = 100000000,
    },
    {
        id = "exp_potion_1b",
        name = "速升药水·极",
        desc = "使用后立即获得 10亿 经验值",
        icon = "item_exp_potion_1b_20260309142538.png",
        maxStack = 999,
        color = { 180, 80, 220 },  -- 紫色
        expValue = 1000000000,
    },
    {
        id = "exp_potion_250",
        name = "速升药水·250",
        desc = "使用后立即获得 30万亿 经验值，可直升250级",
        icon = "item_exp_potion_250_20260310012228.png",
        maxStack = 999,
        color = { 255, 100, 50 },  -- 橙红色
        expValue = 30000000000000,
    },
    {
        id = "wb_ticket",
        name = "世界Boss挑战券",
        desc = "使用后增加1次世界Boss挑战次数",
        icon = "item_wb_ticket_20260310175942.png",
        maxStack = 999,
        color = { 255, 80, 80 },  -- 红色
    },
    -- 魔法石 (统一定义，tier 掉落时动态附加)
    {
        id = "magic_stone",
        name = "魔法石",
        desc = "将装备Tier提升至指定章节等级",
        icon = "magic_stone_20260311035426.png",
        maxStack = 999,
        color = { 100, 220, 100 },
        isMagicStone = true,
    },
    -- 顶级魔法石 (使用时以 maxChapter 为目标Tier，特殊来源)
    {
        id = "magic_stone_top",
        name = "顶级魔法石",
        desc = "将装备Tier提升至当前最高章节等级",
        icon = "magic_stone_top_20260311035701.png",
        maxStack = 999,
        color = { 255, 215, 0 },  -- 金色
        isMagicStone = true,
        isTopMagicStone = true,
    },
    -- 散光棱镜 (宝石打孔材料)
    {
        id = "prism",
        name = "散光棱镜",
        desc = "用于为橙色装备打孔，每次增加1个宝石孔位",
        icon = "Textures/Items/item_prism.png",
        maxStack = 999,
        color = { 200, 220, 255 },  -- 浅蓝白色
    },
    -- 噩梦钥石 (噩梦地牢入场券)
    {
        id = "nightmare_sigil",
        name = "噩梦钥石",
        desc = "开启噩梦地牢的钥匙，层级越高挑战越强",
        icon = "Textures/Items/item_prism.png",  -- 复用棱镜图标
        maxStack = 99,
        color = { 180, 60, 220 },  -- 紫色
    },
}

-- 魔法石掉率 (Boss独立判定, 不受幸运影响)
Config.MAGIC_STONE_DROP = {
    s10 = 100,   -- 大Boss: 百分之一 (math.random(1, 100) == 1)
    s5  = 143,   -- 小Boss: 千分之七 ≈ 1/143 (s10 的 0.7 倍)
}

Config.ITEM_MAP = {}
for _, item in ipairs(Config.ITEMS) do
    Config.ITEM_MAP[item.id] = item
end

-- 程序化生成 magic_stone:1 ~ magic_stone:12 的 ITEM_MAP 条目
-- 背包 key 为 "magic_stone:N"，共享基础定义的 icon/color，各自 targetTier 不同
do
    local base = Config.ITEM_MAP["magic_stone"]
    if base then
        for ch = 1, 12 do
            Config.ITEM_MAP["magic_stone:" .. ch] = {
                id          = "magic_stone:" .. ch,
                name        = "T" .. ch .. "魔法石",
                desc        = base.desc,
                icon        = base.icon,
                maxStack    = base.maxStack,
                color       = base.color,
                isMagicStone = true,
                targetTier  = ch,
            }
        end
    end
end

-- ============================================================================
-- 宝石镶嵌系统
-- ============================================================================

-- 装备槽位 → 类型分类 (决定宝石提供哪种属性)
Config.EQUIP_CATEGORIES = {
    weapon   = "weapon",
    gloves   = "armor",
    boots    = "armor",
    amulet   = "jewelry",
    ring     = "jewelry",
    necklace = "jewelry",
}

-- 7 种宝石类型
-- effects: 按装备类型提供不同属性的 statKey
Config.GEM_TYPES = {
    {
        id = "ruby", name = "红宝石", color = { 255, 60, 60 },
        effects = { weapon = "atk", armor = "hp", jewelry = "fireRes" },
        descs = {
            "粗糙的红色晶石，内部隐约闪烁着微弱火光",
            "打磨过的红宝石，稳定的火焰在其中燃烧",
            "精心切割的红宝石，炽热的火焰翻涌不息",
            "王室珍藏的红宝石，蕴含着毁灭性的烈焰之力",
            "传说中的至高红宝石，仿佛封印了一座火山的怒焰",
        },
    },
    {
        id = "sapphire", name = "蓝宝石", color = { 60, 120, 255 },
        effects = { weapon = "crit", armor = "def", jewelry = "iceRes" },
        descs = {
            "暗淡的蓝色碎晶，触碰时略感冰凉",
            "清澈的蓝宝石，寒意从内部缓缓散发",
            "深邃的蓝宝石，凝聚着极北冰原的寒霜",
            "散发冷冽光芒的蓝宝石，万物在其前皆会凝结",
            "远古冰川孕育的至高蓝宝石，拥有冻结时间的力量",
        },
    },
    {
        id = "emerald", name = "绿宝石", color = { 60, 200, 60 },
        effects = { weapon = "critDmg", armor = "luck", jewelry = "lightningRes" },
        descs = {
            "黯淡的绿色碎片，散发着微弱的自然气息",
            "翠绿的宝石，其中似有生命力在流转",
            "剔透的绿宝石，蕴含森林深处的古老力量",
            "浓郁翠意的绿宝石，令佩戴者心想事成",
            "世界树根系孕育的至高绿宝石，命运在它面前低头",
        },
    },
    {
        id = "topaz", name = "黄宝石", color = { 255, 220, 50 },
        effects = { weapon = "skillDmg", armor = "spd", jewelry = "fireRes" },
        descs = {
            "浑浊的黄色碎石，偶尔闪过一丝电弧",
            "温润的黄宝石，内部雷光时隐时现",
            "璀璨的黄宝石，蕴藏着奥术与雷霆之能",
            "雷暴中结晶的黄宝石，触碰者的思维会变得迅捷无比",
            "诸神赐福的至高黄宝石，承载着万千法术的回响",
        },
    },
    {
        id = "amethyst", name = "紫水晶", color = { 180, 80, 220 },
        effects = { weapon = "vulnerableDmg", armor = "shldPct", jewelry = "iceRes" },
        descs = {
            "粗糙的紫色晶簇，隐约散发出神秘微光",
            "打磨后的紫水晶，元素能量在表面隐隐浮现",
            "瑰丽的紫水晶，能激发元素之间的共鸣反应",
            "深紫色的皇家水晶，元素在它周围疯狂交织",
            "虚空深渊中凝结的至高紫水晶，万元素在其中归一",
        },
    },
    {
        id = "diamond", name = "钻石", color = { 220, 240, 255 },
        effects = { weapon = "elemDmg", armor = "hpPct", jewelry = "allRes" },
        -- 声明式 override: 替代 CalcGemStat 中的 if-else 特判
        overrides = {
            weapon  = { base = "DIAMOND_ELEMDMG_BASE" },            -- 使用独立 base 值
            jewelry = { baseStat = "fireRes", discount = "DIAMOND_ALLRES_DISCOUNT" },  -- allRes 折扣
        },
        descs = {
            "灰暗的碎钻，折射出微弱的七彩光芒",
            "小巧的钻石，纯净的光芒在其中流转",
            "切割精良的钻石，折射出令人目眩的虹光",
            "罕见的大颗钻石，蕴含着对所有元素的亲和力",
            "天外陨石孕育的至高钻石，传说它能抵御一切力量",
        },
    },
    {
        id = "moonstone", name = "月光石", color = { 200, 220, 255 },
        effects = { weapon = "lifeSteal", armor = "hpRegen", jewelry = "def" },
        descs = {
            "黯淡的乳白碎石，夜晚会微微泛光",
            "柔和的月光石，散发着治愈的银色光辉",
            "皎洁的月光石，据说能吸收月光转化为生命力",
            "被月华浸润千年的月光石，伤口在它面前会自行愈合",
            "传说中月神遗落的至高月光石，拥有起死回生之力",
        },
    },
}

-- 宝石类型快查表 { [id] = gemDef }
Config.GEM_TYPE_MAP = {}
for _, gem in ipairs(Config.GEM_TYPES) do
    Config.GEM_TYPE_MAP[gem.id] = gem
end

-- 5 个品质等级
Config.GEM_QUALITIES = {
    { id = 1, name = "碎裂", gemMul = 0.15, color = { 200, 200, 200 } },
    { id = 2, name = "普通", gemMul = 0.25, color = { 100, 220, 100 } },
    { id = 3, name = "完美", gemMul = 0.40, color = { 80, 140, 255 } },
    { id = 4, name = "皇家", gemMul = 0.60, color = { 180, 80, 220 } },
    { id = 5, name = "宏伟", gemMul = 0.75, color = { 255, 165, 0 } },
}

-- GetGemIcon → ConfigCalc.lua

-- 合成: 3 颗低品质 → 1 颗高品质
Config.GEM_SYNTH_COST = 3

-- 宝石背包容量
Config.GEM_BAG_SIZE = 40              -- 初始宝石背包容量（格数）
Config.GEM_BAG_EXPAND_SLOTS = 4      -- 每次扩容增加的格子数
Config.GEM_BAG_MAX_SIZE = 100        -- 宝石背包容量上限

-- 钻石首饰全抗折扣系数 (防止 3 抗叠加过强)
Config.DIAMOND_ALLRES_DISCOUNT = 0.6
-- 钻石首饰全抗影响的抗性列表
Config.DIAMOND_ALLRES_STATS = { "fireRes", "iceRes", "lightningRes" }

-- 钻石武器使用的 elemDmg base 值 (独立于 EQUIP_STATS.elemDmg.base)
Config.DIAMOND_ELEMDMG_BASE = 0.0025

-- 装备孔位上限
Config.MAX_SOCKETS = 3

-- 同屏最大存活敌人数量 (队列中还有怪时，死一补一)
Config.MAX_ALIVE_ENEMIES = 5

-- 橙装生成时初始孔数概率权重 (索引 = 孔数+1: [1]=0孔, [2]=1孔, [3]=2孔, [4]=3孔)
Config.SOCKET_WEIGHTS = { 0.50, 0.39, 0.10, 0.01 }

-- 打孔消耗散光棱镜数量 (索引 = 第N次打孔: [1]=第1孔, [2]=第2孔, [3]=第3孔)
Config.PUNCH_COSTS = { 1, 2, 4 }

-- CalcGemStat → ConfigCalc.lua

-- ============================================================================
-- 装备主属性系统 (固有属性, 不占词缀格)
-- ============================================================================
-- 每件装备根据槽位获得 1 条固定主属性
-- 公式: mainStatValue = slotBase × (IP / 100)
-- ring 槽随机 atk 或 hp (各 50%)
Config.MAIN_STAT = {
    weapon   = { id = "atk",     slotBase = 50  },
    gloves   = { id = "atk",     slotBase = 20  },
    boots    = { id = "def",     slotBase = 30  },
    amulet   = { id = "hp",      slotBase = 800 },
    ring     = {
        { id = "atk", slotBase = 15  },
        { id = "hp",  slotBase = 400 },
    },
    necklace = { id = "hpRegen", slotBase = 16  },
}

--- 获取指定槽位的主属性定义 (ring 随机选一个)
---@param slotId string
---@return table {id=string, slotBase=number}
function Config.GetMainStatDef(slotId)
    local def = Config.MAIN_STAT[slotId]
    if not def then return nil end
    -- ring 是数组 → 随机选
    if def[1] then
        return def[math.random(1, #def)]
    end
    return def
end

--- 计算主属性数值 (基础, 不含升级加成)
---@param slotBase number
---@param itemPower number
---@return number
function Config.CalcMainStatValue(slotBase, itemPower)
    return slotBase * (itemPower / 100)
end

--- 计算主属性数值 (含升级加成)
--- v5.0 公式: slotBase × (IP/100) × (1 + upgradeLv × UPGRADE_MAIN_GROWTH)
---@param slotBase number
---@param itemPower number
---@param upgradeLv number
---@return number
function Config.CalcMainStatValueFull(slotBase, itemPower, upgradeLv)
    local base = slotBase * (itemPower / 100)
    local upgradeMul = 1.0 + (upgradeLv or 0) * Config.UPGRADE_MAIN_GROWTH
    return base * upgradeMul
end

--- 计算词缀升级倍率 (v5.0: 每次升级全词缀 +5%)
--- @param upgradeLv number 升级次数 (0-4, 终局强化后5)
--- @return number 倍率 (1.0 表示无加成)
function Config.CalcAffixUpgradeMul(upgradeLv)
    if not upgradeLv or upgradeLv <= 0 then return 1.0 end
    return 1.0 + upgradeLv * Config.UPGRADE_AFFIX_GROWTH
end

--- (旧版兼容) 计算单条词缀的里程碑倍率
--- @param milestoneCount number 该词缀被选中的里程碑次数
--- @return number 倍率 (1.0 表示无加成)
function Config.CalcAffixMilestoneMul(milestoneCount)
    if not milestoneCount or milestoneCount <= 0 then return 1.0 end
    return 1.0 + milestoneCount * Config.UPGRADE_AFFIX_MILESTONE_BONUS
end

-- 测试账号列表（排行榜中不予统计）
Config.TEST_USER_IDS = {
}

-- 封禁用户列表（禁止登录 + 排行榜不计入）
Config.BANNED_USER_IDS = {
}

-- ============================================================================
-- 噩梦地牢配置
-- ============================================================================

Config.NIGHTMARE_DUNGEON = {
    UNLOCK_CHAPTER     = 7,       -- 解锁章节 (通关第7章)
    AD_SIGIL_DAILY_MAX = 10,      -- 每日看广告获取钥石次数上限
    TIME_BASE          = 600,     -- 基础限时 10 分钟（秒）
    TIME_PER_TIER      = 3,       -- 每层额外 3 秒
    TIME_MAX           = 1200,    -- 时限上限 20 分钟
    MAX_TIER           = 100,     -- 最高层级

    -- 怪物缩放
    TIER_SCALE_MAX     = 2.0,     -- tierMul 渐近线上限
    TIER_SCALE_K       = 50,      -- 半值常数

    -- 阶段配置 (三阶段制: 扫荡 → 精英层 → 守护者)
    -- Lv.1  → ~150 只 (扫荡80 + 精英层50 + 守护者20)  ≈ 8-10 分钟
    -- Lv.50 → ~300 只 (扫荡160 + 精英层100 + 守护者40) ≈ 15-18 分钟
    -- Lv.100→ ~400 只 (扫荡210 + 精英层140 + 守护者55) ≈ 18-20 分钟
    PHASES = {
        { name = "扫荡",   mobBase = 60, mobPerTier = 1.5,  eliteBase = 6,  elitePerTier = 0.15 },
        { name = "精英层", mobBase = 30, mobPerTier = 0.8,  eliteBase = 10, elitePerTier = 0.3, champBase = 3, champPerTier = 0.1 },
        { name = "守护者", mobBase = 12, mobPerTier = 0.3,  eliteBase = 2,  elitePerTier = 0.06, bossCount = 1 },
    },
    MAX_ON_FIELD = 12,  -- 场上同时存在上限

    -- 掉落配置 (按层级分档)
    LOOT_TIERS = {
        { maxTier = 10,  minRoll = 0.40, maxRoll = 0.65, minQuality = 3, equipMin = 2, equipMax = 3 },
        { maxTier = 25,  minRoll = 0.45, maxRoll = 0.72, minQuality = 3, equipMin = 3, equipMax = 4 },
        { maxTier = 50,  minRoll = 0.50, maxRoll = 0.80, minQuality = 4, equipMin = 3, equipMax = 5 },
        { maxTier = 75,  minRoll = 0.55, maxRoll = 0.88, minQuality = 4, equipMin = 4, equipMax = 5 },
        { maxTier = 100, minRoll = 0.60, maxRoll = 1.00, minQuality = 4, equipMin = 4, equipMax = 6 },
    },

    -- Boss 品质权重 { 蓝, 紫, 橙 }
    BOSS_QUALITY_TIERS = {
        { maxTier = 10,  weights = { 0.50, 0.40, 0.10 } },
        { maxTier = 25,  weights = { 0.30, 0.50, 0.20 } },
        { maxTier = 50,  weights = { 0.15, 0.50, 0.35 } },
        { maxTier = 75,  weights = { 0.05, 0.45, 0.50 } },
        { maxTier = 100, weights = { 0.00, 0.35, 0.65 } },
    },

    -- 材料掉落
    MATERIAL_DROPS = {
        { matId = "iron",       minTier = 1,  base = 10, perTier = 0.5 },
        { matId = "crystal",    minTier = 10, base = 5,  perTier = 0.25 },
        { matId = "wraith",     minTier = 25, base = 2,  perTier = 0.125 },
        { matId = "eternal",    minTier = 50, base = 1,  perTier = 0.05 },
        { matId = "abyssHeart", minTier = 75, base = 1,  perTier = 0, bossOnly = true },
        { matId = "riftEcho",   minTier = 50, base = 1,  perTier = 0, bossOnly = true, chance = 0.30 },
    },

    -- 经验/金币
    EXP_BASE           = 5000,
    EXP_TIER_MUL       = 0.15,
    GOLD_BASE          = 500,
    GOLD_TIER_MUL      = 0.08,

    -- 钥石递进
    SIGIL_TIER_UP_MIN  = 1,
    SIGIL_TIER_UP_MAX  = 3,

    -- Lv50+ Boss 必掉 2 件橙装
    BOSS_DOUBLE_ORANGE_TIER = 50,
    -- Lv90+ 深渊之心 ×2
    ABYSS_HEART_DOUBLE_TIER = 90,

    -- 正面词缀
    POSITIVE_AFFIXES = {
        { id = "empowered",      name = "力量涌动", desc = "攻击力 +20%",              stats = { atkMul = 0.20 } },
        { id = "swiftness",      name = "疾风之力", desc = "攻速 +25%",                stats = { atkSpdMul = 0.25 } },
        { id = "fortified",      name = "铁壁",     desc = "防御力 +30%",              stats = { defMul = 0.30 } },
        { id = "vampiric",       name = "吸血本能", desc = "生命偷取 +3%",             stats = { lifeSteal = 0.03 } },
        { id = "critical_mass",  name = "暴击聚能", desc = "暴击率 +15%，暴击伤害 +20%", stats = { critRate = 0.15, critDmg = 0.20 } },
        { id = "elemental_fury", name = "元素狂怒", desc = "全元素增伤 +15%",           stats = { elemDmgMul = 0.15 } },
    },

    -- 负面词缀
    NEGATIVE_AFFIXES = {
        { id = "armored",     name = "铁甲",     desc = "怪物防御力 +50%",              target = "monster", stats = { defMul = 0.50 } },
        { id = "frenzied",    name = "狂暴",     desc = "怪物攻速 +40%，攻击力 +15%",    target = "monster", stats = { atkSpdMul = 0.40, atkMul = 0.15 } },
        { id = "shadowborn",  name = "暗影降生", desc = "怪物数量 +30%",                 target = "monster", stats = { countMul = 0.30 } },
        { id = "frostborn",   name = "寒霜",     desc = "玩家移速 -20%，攻速 -10%",      stats = { spdMul = -0.20, atkSpdMul = -0.10 } },
        { id = "corrosive",   name = "腐蚀",     desc = "玩家防御力 -25%，生命回复 -30%", stats = { defMul = -0.25, regenMul = -0.30 } },
        { id = "afflicted",   name = "诅咒",     desc = "玩家受到的元素伤害 +25%",        stats = { elemVuln = 0.25 } },
        { id = "suppression", name = "压制",     desc = "暴击率上限降至 30%",             stats = { critCap = 0.30 } },
        { id = "desolate",    name = "荒芜",     desc = "生命偷取效率 -50%",              stats = { lifeStealMul = -0.50 } },
    },

    -- 层级→词缀数 { maxTier, positive, negative }
    AFFIX_BRACKETS = {
        { maxTier = 10,  positive = 1, negative = 0 },
        { maxTier = 25,  positive = 1, negative = 1 },
        { maxTier = 50,  positive = 2, negative = 1 },
        { maxTier = 75,  positive = 2, negative = 2 },
        { maxTier = 100, positive = 2, negative = 3 },
    },
}

-- ============================================================================
-- 魔力之森配置
-- ============================================================================

Config.MANA_FOREST = {
    UNLOCK_CHAPTER      = 4,     -- 解锁章节 (通关第4章)
    HARD_UNLOCK_CHAPTER = 8,     -- 困难模式解锁章节
    MAX_DAILY_ATTEMPTS  = 1,     -- 每日免费次数
    MAX_BONUS_ATTEMPTS  = 5,     -- 广告额外次数上限
    FIGHT_DURATION      = 90,    -- 战斗时长 (秒)
    MONSTER_SCALE       = 0.80,  -- 普通模式怪物缩放
    HARD_MONSTER_SCALE  = 1.30,  -- 困难模式怪物缩放
    ELITE_HP_MUL        = 2.5,   -- 精英HP倍率（普通）
    HARD_ELITE_HP_MUL   = 3.5,   -- 精英HP倍率（困难）

    -- 怪物数量
    MONSTER_COUNT        = 30,   -- 普通模式总怪物数
    HARD_MONSTER_COUNT   = 40,   -- 困难模式总怪物数
    ELITE_COUNT          = 3,    -- 普通精英数
    HARD_ELITE_COUNT     = 5,    -- 困难精英数
    MAX_ON_FIELD         = 8,    -- 场上同时存在上限（普通）
    HARD_MAX_ON_FIELD    = 10,   -- 场上同时存在上限（困难）
    SPAWN_INTERVAL       = 0.8,  -- 生成间隔

    -- 精华系统
    ESSENCE_PER_NORMAL  = 1,     -- 普通怪精华
    ESSENCE_PER_ELITE   = 5,     -- 精英怪精华
    CRYSTAL_ESSENCE     = 3,     -- 水晶精华

    -- 增益阶梯门槛
    BUFF_THRESHOLDS = { 5, 15, 25, 35 },
    BUFF_TIERS = {
        { atkSpd = 0.15 },                                     -- Tier 1
        { atkSpd = 0.15, dmg = 0.10 },                         -- Tier 2
        { atkSpd = 0.30, dmg = 0.20 },                         -- Tier 3
        { atkSpd = 0.30, dmg = 0.20, crit = 0.10 },            -- Tier 4
    },

    -- 涌潮事件
    SURGE_INTERVAL      = 30,    -- 每30秒一次涌潮
    SURGE_CRYSTAL_COUNT = 3,     -- 每次生成3个水晶
    SURGE_CRYSTAL_LIFE  = 8,     -- 水晶存在8秒

    -- 精华→奖励转化
    POTION_RATIO_NORMAL = 8,     -- 普通: floor(精华/8) 瓶药水
    POTION_RATIO_HARD   = 6,     -- 困难: floor(精华/6) 瓶药水
    DEW_RATIO_NORMAL    = 7,     -- 普通: floor(精华/7) 森之露
    DEW_RATIO_HARD      = 5,     -- 困难: floor(精华/5) 森之露

    -- 额外固定奖励
    GOLD_BASE_NORMAL = 200,
    GOLD_BASE_HARD   = 400,
    EXP_BASE_NORMAL  = 2000,
    EXP_BASE_HARD    = 4000,

    -- 首通额外奖励
    FIRST_CLEAR_POTIONS = 5,
    FIRST_CLEAR_DEW     = 3,

    -- 死亡惩罚
    DEATH_EFFICIENCY = 0.60,     -- 死亡时精华效率60%
}

-- 魔力之源升级成本 (森之露消耗)
-- 索引 = 目标等级 (从Lv0升到Lv1需要20, 从Lv1升到Lv2需要35, ...)
Config.MANA_POTION_UPGRADE_COSTS = {
    20, 35, 55, 80, 110, 145, 185, 230, 280, 340,
}

-- ConfigCalc 注入计算函数到 Config 表 (消除循环依赖)
require("ConfigCalc").Install(Config)

return Config
