--- 怪物家族配置 (静态数据表)
--- 精英/冠军层级、20 精英词缀、家族-词缀共鸣、章节编排
--- 设计文档: docs/数值/怪物家族系统设计.md §4

local M = {}

---------------------------------------------------------------------------
-- 一、现有 familyId → 10 设计家族类型 映射
-- familyType 决定 FamilyMechanics 中的战斗机制
---------------------------------------------------------------------------

---@alias FamilyType "swarm"|"undead"|"fiends"|"venomkin"|"beasts"|"drowned"|"fungal"|"constructs"|"cult"|"voidborn"

---@type table<string, FamilyType>
M.FAMILY_TYPE_FROM_ID = {
    undead           = "undead",     -- 复活
    beast            = "beasts",     -- 群猎嚎叫
    elemental_fire   = "fiends",     -- 首领光环
    elemental_ice    = "constructs", -- 碎裂重组
    elemental_poison = "venomkin",   -- 毒蚀
    arcane           = "voidborn",   -- 相位闪移
    divine           = "cult",       -- 献祭
    aquatic          = "drowned",    -- 潮池
}

--- 个别怪物覆盖 familyType (behaviorId 级别)
--- key = familyId .. "_" .. behaviorId
---@type table<string, FamilyType>
M.FAMILY_TYPE_OVERRIDES = {
    -- 虫潮特征: swarm/exploder 行为模板中的分裂型成员
    elemental_poison_swarm    = "swarm",   -- 瘟疫甲虫 → 虫潮
    elemental_poison_exploder = "fungal",  -- 孢子潜伏者 → 菌落
    elemental_fire_debuffer   = "fungal",  -- 毒焰蘑菇 → 菌落
    beast_debuffer            = "venomkin",-- 毒蛙 → 蛛蝎
}

--- 获取怪物的 familyType
---@param familyId string
---@param behaviorId string|nil
---@return FamilyType
function M.GetFamilyType(familyId, behaviorId)
    if behaviorId then
        local key = familyId .. "_" .. behaviorId
        local override = M.FAMILY_TYPE_OVERRIDES[key]
        if override then return override end
    end
    return M.FAMILY_TYPE_FROM_ID[familyId] or "beasts"
end

---------------------------------------------------------------------------
-- 二、精英/冠军层级 (§4.2, 针对挂机平衡调优)
---------------------------------------------------------------------------

---@class EliteTierDef
---@field hpMul number       HP 倍率
---@field atkMul number      ATK 倍率
---@field defAdd number      DEF 加成
---@field sizeMul number     体型缩放
---@field critRate number    暴击率
---@field critMul number     暴击倍率
---@field affixMin number    最少词缀数
---@field affixMax number    最多词缀数
---@field nameColor number[] 名字颜色 {r,g,b}
---@field label string       显示标签

---@type table<string, EliteTierDef>
M.ELITE_TIERS = {
    elite = {
        hpMul = 2.5, atkMul = 1.6, defAdd = 100,
        sizeMul = 1.3, critRate = 0.07, critMul = 1.5,
        affixMin = 1, affixMax = 3,
        nameColor = { 100, 150, 255 }, label = "精英",
    },
    champion = {
        hpMul = 5.0, atkMul = 2.2, defAdd = 200,
        sizeMul = 1.6, critRate = 0.12, critMul = 2.0,
        affixMin = 2, affixMax = 4,
        nameColor = { 255, 200, 50 }, label = "冠军",
    },
}

---------------------------------------------------------------------------
-- 三、精英出现概率 (按章节)
---------------------------------------------------------------------------

--- 返回精英/冠军出现概率
---@param chapter number
---@return number eliteChance, number championChance
function M.GetEliteChance(chapter)
    if chapter < 4 then return 0, 0 end          -- ch1-3 无精英
    if chapter < 8 then return 0.08, 0 end        -- ch4-7 仅精英 8%
    if chapter < 12 then return 0.10, 0.02 end    -- ch8-11 精英10% 冠军2%
    return 0.12, 0.04                              -- ch12+ 精英12% 冠军4%
end

---------------------------------------------------------------------------
-- 四、20 精英词缀定义 (§4.3)
-- 每个词缀声明式定义, 运行时逻辑在 EliteSystem.lua
---------------------------------------------------------------------------

---@class AffixDef
---@field id string           词缀ID
---@field name string         显示名
---@field category string     "offense"|"defense"|"control"|"special"
---@field icon string|nil     图标 (预留)
---@field color number[]      标识色 {r,g,b}
---@field desc string         简短描述

---@type table<string, AffixDef>
M.AFFIXES = {
    -- ── 进攻 (5) ──
    berserker = {
        id = "berserker", name = "狂暴", category = "offense",
        color = { 255, 80, 80 },
        desc = "ATK+40%, 攻速+30%",
    },
    explosive = {
        id = "explosive", name = "爆裂", category = "offense",
        color = { 255, 140, 40 },
        desc = "攻击20%概率范围爆炸; 死亡爆炸",
    },
    armor_pierce = {
        id = "armor_pierce", name = "穿甲", category = "offense",
        color = { 200, 180, 100 },
        desc = "无视30%防御",
    },
    lifesteal = {
        id = "lifesteal", name = "吸血", category = "offense",
        color = { 180, 40, 60 },
        desc = "伤害10%转回血",
    },
    execute = {
        id = "execute", name = "猎杀", category = "offense",
        color = { 200, 50, 50 },
        desc = "对低血量(<30%)目标伤害+60%",
    },

    -- ── 防御 (5) ──
    iron_wall = {
        id = "iron_wall", name = "铁壁", category = "defense",
        color = { 140, 140, 160 },
        desc = "DEF+50%, 免疫击退和控制",
    },
    regen = {
        id = "regen", name = "再生", category = "defense",
        color = { 80, 200, 80 },
        desc = "每秒回2% HP",
    },
    thorns = {
        id = "thorns", name = "荆棘", category = "defense",
        color = { 160, 120, 80 },
        desc = "反弹15%受到的伤害",
    },
    shield = {
        id = "shield", name = "护盾", category = "defense",
        color = { 100, 180, 255 },
        desc = "每10秒生成20% HP护盾",
    },
    undying = {
        id = "undying", name = "不死", category = "defense",
        color = { 200, 200, 255 },
        desc = "首次致命伤回30% HP",
    },

    -- ── 控制 (5) ──
    frozen = {
        id = "frozen", name = "冰封", category = "control",
        color = { 140, 220, 255 },
        desc = "攻击叠寒冷,满层冻结+受伤+25%",
    },
    burning = {
        id = "burning", name = "燃烧", category = "control",
        color = { 255, 120, 40 },
        desc = "脚下留火焰区, DOT",
    },
    entangle = {
        id = "entangle", name = "缠绕", category = "control",
        color = { 80, 160, 40 },
        desc = "25%概率定身2秒",
    },
    blind = {
        id = "blind", name = "致盲", category = "control",
        color = { 100, 80, 120 },
        desc = "降低暴击率30%",
    },
    slow = {
        id = "slow", name = "减速", category = "control",
        color = { 80, 140, 200 },
        desc = "降低移速40%",
    },

    -- ── 特殊 (5) ──
    leader = {
        id = "leader", name = "领袖", category = "special",
        color = { 255, 220, 100 },
        desc = "光环: 附近同伴ATK+25%",
    },
    summoner = {
        id = "summoner", name = "召唤", category = "special",
        color = { 180, 100, 220 },
        desc = "定期召唤2只小怪",
    },
    teleport = {
        id = "teleport", name = "传送", category = "special",
        color = { 160, 80, 255 },
        desc = "瞬移到玩家身边",
    },
    chain_lightning = {
        id = "chain_lightning", name = "闪电链", category = "special",
        color = { 120, 200, 255 },
        desc = "闪电弹射3目标",
    },
    frenzy = {
        id = "frenzy", name = "狂热", category = "special",
        color = { 255, 60, 60 },
        desc = "生命越低攻速越快",
    },
}

--- 按类别索引
M.AFFIX_BY_CATEGORY = {}
for id, def in pairs(M.AFFIXES) do
    local cat = def.category
    if not M.AFFIX_BY_CATEGORY[cat] then M.AFFIX_BY_CATEGORY[cat] = {} end
    M.AFFIX_BY_CATEGORY[cat][#M.AFFIX_BY_CATEGORY[cat] + 1] = id
end

--- 全部词缀ID列表 (用于随机掷骰)
M.ALL_AFFIX_IDS = {}
for id in pairs(M.AFFIXES) do
    M.ALL_AFFIX_IDS[#M.ALL_AFFIX_IDS + 1] = id
end
table.sort(M.ALL_AFFIX_IDS) -- 确保稳定顺序

---------------------------------------------------------------------------
-- 五、家族-词缀共鸣 (§4.4)
-- 词缀恰好与家族机制匹配时效果 +50%
---------------------------------------------------------------------------

---@type table<FamilyType, string> familyType → affixId
M.FAMILY_RESONANCE = {
    swarm      = "explosive",    -- 爆裂×1.5范围, 分裂体也带爆裂
    undead     = "undying",      -- 回复50% HP
    fiends     = "leader",       -- 光环范围和效果×1.5
    venomkin   = "entangle",     -- 缠绕期间叠2层蚀毒
    beasts     = "berserker",    -- 群猎状态下攻速额外+20%
    drowned    = "slow",         -- 减速60%
    fungal     = "burning",      -- 改为毒伤DOT, 孢子云中伤害翻倍
    constructs = "shield",       -- 护盾30% HP
    cult       = "leader",       -- 额外提供献祭加速
    voidborn   = "teleport",     -- 闪现间隔减半
}

--- 检查词缀是否与家族共鸣
---@param familyType FamilyType
---@param affixId string
---@return boolean isResonant, number bonusMul
function M.IsResonant(familyType, affixId)
    local resonantAffix = M.FAMILY_RESONANCE[familyType]
    if resonantAffix == affixId then
        return true, 1.5
    end
    return false, 1.0
end

---------------------------------------------------------------------------
-- 六、章节→家族编排 (§6)
---------------------------------------------------------------------------

---@class ChapterFamilyDef
---@field areaFloor number       区域等级下限
---@field main FamilyType[]      主家族
---@field sub FamilyType[]|nil   辅助家族
---@field boss FamilyType[]      Boss 家族

---@type table<number, ChapterFamilyDef>
M.CHAPTER_FAMILIES = {
    [1]  = { areaFloor = 1,  main = {"fiends","beasts"},             sub = {"cult"},                  boss = {"cult","constructs"} },
    [2]  = { areaFloor = 5,  main = {"fiends","constructs"},         sub = {"drowned"},               boss = {"cult","beasts"} },
    [3]  = { areaFloor = 8,  main = {"fungal","beasts"},             sub = {"fiends"},                boss = {"fiends","constructs"} },
    [4]  = { areaFloor = 12, main = {"undead"},                      sub = {"venomkin","constructs"}, boss = {"undead"} },
    [5]  = { areaFloor = 16, main = {"drowned"},                     sub = nil,                       boss = {"drowned"} },
    [6]  = { areaFloor = 20, main = {"beasts","swarm"},              sub = {"cult"},                  boss = {"beasts","constructs"} },
    [7]  = { areaFloor = 24, main = {"venomkin","fungal"},           sub = {"beasts"},                boss = {"venomkin","fungal"} },
    [8]  = { areaFloor = 28, main = {"voidborn"},                    sub = {"constructs"},            boss = {"voidborn"} },
    [9]  = { areaFloor = 32, main = {"cult","fiends"},               sub = {"constructs"},            boss = {"cult"} },
    [10] = { areaFloor = 36, main = {"undead","voidborn"},           sub = {"cult"},                  boss = {"undead","voidborn"} },
    [11] = { areaFloor = 40, main = {"fiends","cult"},               sub = {"constructs"},            boss = {"cult","constructs"} },
    [12] = { areaFloor = 43, main = {"voidborn","swarm"},            sub = {"constructs"},            boss = {"voidborn"} },
    [13] = { areaFloor = 45, main = {"venomkin","fungal"},           sub = {"constructs","cult"},     boss = {"constructs","beasts","fungal"} },
    [14] = { areaFloor = 47, main = {"venomkin","swarm"},            sub = {"fungal"},                boss = {"venomkin","fungal","venomkin"} },
    [15] = { areaFloor = 48, main = {"fiends","fungal"},             sub = {"cult"},                  boss = {"fiends","constructs","fiends"} },
    [16] = { areaFloor = 49, main = {"drowned","venomkin"},          sub = {"voidborn"},              boss = {"drowned"} },
    [17] = { areaFloor = 50, main = {"swarm","fungal"},              sub = {"fiends"},                boss = {"swarm","constructs"} },
}

---------------------------------------------------------------------------
-- 七、家族机制参数 (供 FamilyMechanics 读取)
---------------------------------------------------------------------------

---@type table<FamilyType, table>
M.MECHANIC_PARAMS = {
    swarm = {
        splitChance    = 0.60,   -- 死亡分裂概率
        splitHpRatio   = 0.40,   -- 分裂体 HP 比例
        splitAtkRatio  = 0.40,   -- 分裂体 ATK 比例
        maxSplitGen    = 1,      -- 最多再裂 1 次
    },
    undead = {
        reviveDelay    = 2.0,    -- 死后多久可被复活 (秒)
        reviveHpRatio  = 0.50,   -- 复活 HP 比例
        maxRevives     = 2,      -- 单体最多被复活次数
        reviveCooldown = 5.0,    -- 侍祭复活冷却
    },
    fiends = {
        leaderAtkBuff  = 0.30,   -- 首领光环 ATK+
        leaderSpdBuff  = 0.20,   -- 首领光环移速+
        panicDuration  = 2.0,    -- 恐慌停顿时间
        fleeDuration   = 3.0,    -- 四散逃跑时间
        postPanicAtkDebuff = 0.50, -- 恐慌后 ATK 降低比例
    },
    venomkin = {
        venomPerHit    = 1,      -- 每次攻击叠毒层数
        venomMax       = 10,     -- 最大毒层
        venomDmgPct    = 0.05,   -- 每层: 受伤增幅
        venomDotPct    = 0.02,   -- 每层: 每秒毒伤 (占怪ATK%)
        burstDmgMul    = 3.0,    -- 毒爆伤害倍率 (基于叠满层毒伤)
    },
    beasts = {
        packThreshold  = 3,      -- 群猎最低数量
        packAtkBuff    = 0.40,   -- 群猎 ATK+
        packSpdBuff    = 0.25,   -- 群猎移速+
        cowardDuration = 3.0,    -- 怯懦逃跑时间
    },
    drowned = {
        poolDuration   = 8.0,    -- 水池持续时间
        poolRadius     = 35,     -- 水池半径
        poolSlowPct    = 0.40,   -- 玩家减速
        poolDotPct     = 0.03,   -- 每秒水压伤害 (占怪ATK%)
        poolAllySpd    = 0.30,   -- 海民在水池中移速+
        poolAllyDef    = 0.20,   -- 海民在水池中DEF+
    },
    fungal = {
        sporeRadius    = 40,     -- 孢子云半径
        sporeDotPct    = 0.02,   -- 每秒毒伤
        sporeAtkSpdDebuff = 0.20,-- 玩家攻速降低
        sporeCdDebuff  = 0.30,   -- 玩家技能CD增加
        burstRadius    = 60,     -- 死亡孢子爆发半径
        burstDuration  = 3.0,    -- 爆发持续时间
    },
    constructs = {
        fragmentCount  = 2,      -- 碎片数量
        fragmentHpRatio = 0.30,  -- 碎片 HP 比例
        fragmentAtkRatio = 0.30, -- 碎片 ATK 比例
        reassembleDelay = 10.0,  -- 碎片尝试重组延迟
        reassembleCast  = 3.0,   -- 重组施法时间
        reassembleHpRatio = 0.50,-- 重组后 HP 比例
    },
    cult = {
        sacrificeHpPct  = 0.15,  -- 献祭: 受献者 HP+
        sacrificeAtkPct = 0.10,  -- 献祭: 受献者 ATK+
        sacrificeDuration = 5.0, -- 献祭增益持续
        fanaticThreshold = 3,    -- 触发狂信的献祭次数
        fanaticMul       = 2.0,  -- 狂信全属性倍率
    },
    voidborn = {
        blinkChance    = 0.20,   -- 受击闪移概率
        blinkDist      = { 60, 100 }, -- 闪移距离范围
        blinkInvisTime = 0.5,    -- 消失时间
        weaverStealth  = 2.0,    -- 编织者赋予的隐身时间
        aoeDmgReduction = 0.30,  -- AOE 伤害减免
    },
}

---------------------------------------------------------------------------
-- 八、Boss → 家族分配 (§3.2, 34 Boss)
---------------------------------------------------------------------------

---@class BossFamilyDef
---@field familyTypes FamilyType[]  所属家族 (双家族Boss有2个)
---@field chapter number            所在章节

---@type table<string, BossFamilyDef>
M.BOSS_FAMILIES = {
    -- ch1
    boss_corrupted_patrol = { familyTypes = {"cult"},       chapter = 1 },
    boss_wasteland_colossus = { familyTypes = {"constructs"}, chapter = 1 },
    -- ch2
    boss_ice_witch       = { familyTypes = {"cult"},         chapter = 2 },
    boss_ice_dragon      = { familyTypes = {"beasts"},       chapter = 2 },
    -- ch3
    boss_lava_lord       = { familyTypes = {"fiends"},       chapter = 3 },
    boss_inferno_king    = { familyTypes = {"constructs"},   chapter = 3 },
    -- ch4
    boss_bone_lord       = { familyTypes = {"undead"},       chapter = 4 },
    boss_tomb_king       = { familyTypes = {"undead"},       chapter = 4 },
    -- ch5
    boss_siren           = { familyTypes = {"drowned"},      chapter = 5 },
    boss_leviathan       = { familyTypes = {"drowned"},      chapter = 5 },
    -- ch6
    boss_sandstorm_lord  = { familyTypes = {"beasts"},       chapter = 6 },
    boss_thunder_titan   = { familyTypes = {"constructs"},   chapter = 6 },
    -- ch7
    boss_venom_queen     = { familyTypes = {"venomkin"},     chapter = 7 },
    boss_rotwood_mother  = { familyTypes = {"fungal"},       chapter = 7 },
    -- ch8
    boss_void_prince     = { familyTypes = {"voidborn"},     chapter = 8 },
    boss_rift_lord        = { familyTypes = {"voidborn"},     chapter = 8 },
    -- ch9
    boss_holy_judge      = { familyTypes = {"cult"},         chapter = 9 },
    boss_celestial_emperor = { familyTypes = {"cult"},       chapter = 9 },
    -- ch10
    boss_abyss_general   = { familyTypes = {"undead"},                   chapter = 10 },
    boss_void_lord       = { familyTypes = {"undead","voidborn"},         chapter = 10 },
    -- ch11
    boss_inferno_general = { familyTypes = {"cult"},                     chapter = 11 },
    boss_world_flame     = { familyTypes = {"constructs"},               chapter = 11 },
    -- ch12
    boss_time_rift       = { familyTypes = {"voidborn"},                 chapter = 12 },
    boss_chronos         = { familyTypes = {"voidborn"},                 chapter = 12 },
    -- ch13
    boss_frost_lord      = { familyTypes = {"constructs"},               chapter = 13 },
    boss_ice_sovereign   = { familyTypes = {"beasts","fungal"},           chapter = 13 },
    -- ch14
    boss_venom_mother    = { familyTypes = {"venomkin"},                  chapter = 14 },
    boss_plague_sovereign = { familyTypes = {"fungal","venomkin"},        chapter = 14 },
    -- ch15
    boss_flame_lord      = { familyTypes = {"fiends"},                   chapter = 15 },
    boss_inferno_sovereign = { familyTypes = {"constructs","fiends"},    chapter = 15 },
    -- ch16
    boss_tide_commander  = { familyTypes = {"drowned"},                  chapter = 16 },
    boss_abyssal_leviathan = { familyTypes = {"drowned"},                chapter = 16 },
    -- ch17
    boss_flame_warden    = { familyTypes = {"swarm"},                    chapter = 17 },
    boss_ash_colossus    = { familyTypes = {"constructs"},               chapter = 17 },
}

--- 查询 Boss 的家族类型
---@param bossId string  Boss templateId
---@return FamilyType[]|nil
function M.GetBossFamilyTypes(bossId)
    local def = M.BOSS_FAMILIES[bossId]
    return def and def.familyTypes or nil
end

return M
