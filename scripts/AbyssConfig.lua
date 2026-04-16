-- ============================================================================
-- AbyssConfig.lua - 深渊模式数值配置 (动态等级体系)
--
-- 职责: 深渊常量、主题轮换、Boss 配置、家族映射
-- 依赖: DynamicLevel (等级/成长公式), MonsterFamilies (种族查询)
-- 设计文档: docs/数值/怪物家族系统设计.md §十一
-- ============================================================================

local DynamicLevel    = require("DynamicLevel")
local MonsterFamilies = require("MonsterFamilies")

local AbyssConfig = {}

-- ============================================================================
-- 常量
-- ============================================================================

AbyssConfig.BOSS_INTERVAL     = 5      -- 每5层出Boss
AbyssConfig.BOSS_TIMER        = 30     -- Boss限时(秒)
AbyssConfig.KILL_TARGET       = 10     -- 每层需击杀怪物数

--- Boss 使用 dungeon_boss 角色倍率 (×75 HP, ×2.5 ATK)
AbyssConfig.BOSS_ROLE         = "dungeon_boss"

--- 普通怪使用 normal 角色倍率 (×1 HP, ×1 ATK)
AbyssConfig.MOB_ROLE          = "normal"

-- ============================================================================
-- 主题轮换 (5 主题 × 50 层循环)
--
-- 怪物列表改为 familyId 引用，通过 MonsterFamilies 解析
-- monsters: 每个条目 { familyId, behaviorId, monsterId(种族查询) }
-- boss: { familyId, behaviorId, monsterId, name }
-- ============================================================================

AbyssConfig.THEMES = {
    -- ── 灰烬荒原: 恶鬼 + 教团 ──
    {
        name     = "灰烬荒原",
        monsters = {
            { familyId = "elemental_fire", behaviorId = "swarm",    monsterId = "ash_rat"     },
            { familyId = "elemental_fire", behaviorId = "glass",    monsterId = "void_bat"    },
            { familyId = "beast",          behaviorId = "bruiser",  monsterId = "bandit"      },
            { familyId = "elemental_poison", behaviorId = "swarm",  monsterId = "rot_worm"    },
            { familyId = "elemental_poison", behaviorId = "debuffer", monsterId = "spore_shroom" },
        },
        boss = {
            familyId   = "divine",
            behaviorId = "bruiser",
            monsterId  = "boss_corrupt_guard",
            name       = "腐化巡逻兵",
            raceTier   = "D",
        },
    },
    -- ── 冰封深渊: 恶鬼(冰) + 构造体(冰) ──
    {
        name     = "冰封深渊",
        monsters = {
            { familyId = "elemental_ice", behaviorId = "swarm",    monsterId = "frost_imp"       },
            { familyId = "elemental_ice", behaviorId = "glass",    monsterId = "ice_wraith"      },
            { familyId = "elemental_ice", behaviorId = "bruiser",  monsterId = "snow_wolf"       },
            { familyId = "elemental_ice", behaviorId = "tank",     monsterId = "glacier_beetle"  },
            { familyId = "elemental_ice", behaviorId = "caster",   monsterId = "cryo_mage"       },
        },
        boss = {
            familyId   = "elemental_ice",
            behaviorId = "tank",
            monsterId  = "boss_frost_dragon",
            name       = "深渊冰龙·寒渊",
            raceTier   = "D",
        },
    },
    -- ── 熔岩裂谷: 菌落(火) + 野兽(火) ──
    {
        name     = "熔岩裂谷",
        monsters = {
            { familyId = "elemental_fire", behaviorId = "bruiser",  monsterId = "lava_lizard"    },
            { familyId = "elemental_fire", behaviorId = "glass",    monsterId = "volcano_moth"   },
            { familyId = "elemental_fire", behaviorId = "tank",     monsterId = "rock_scorpion"  },
            { familyId = "elemental_fire", behaviorId = "debuffer", monsterId = "molten_sprite"  },
        },
        boss = {
            familyId   = "elemental_fire",
            behaviorId = "tank",
            monsterId  = "boss_inferno_king",
            name       = "炼狱之王·焚渊",
            raceTier   = "D",
        },
    },
    -- ── 亡灵墓穴: 亡灵 + 蛛蝎 ──
    {
        name     = "亡灵墓穴",
        monsters = {
            { familyId = "undead", behaviorId = "swarm",    monsterId = "grave_rat"         },
            { familyId = "undead", behaviorId = "bruiser",  monsterId = "skeleton_warrior"  },
            { familyId = "undead", behaviorId = "glass",    monsterId = "wraith"            },
            { familyId = "undead", behaviorId = "debuffer", monsterId = "corpse_spider"     },
        },
        boss = {
            familyId   = "undead",
            behaviorId = "tank",
            monsterId  = "boss_tomb_king",
            name       = "墓域君王·永夜",
            raceTier   = "D",
        },
    },
    -- ── 深海遗迹: 海民 ──
    {
        name     = "深海遗迹",
        monsters = {
            { familyId = "aquatic", behaviorId = "swarm",    monsterId = "abyss_angler"    },
            { familyId = "aquatic", behaviorId = "glass",    monsterId = "storm_seahorse"  },
            { familyId = "aquatic", behaviorId = "debuffer", monsterId = "venom_jelly"     },
            { familyId = "aquatic", behaviorId = "tank",     monsterId = "coral_guardian"  },
        },
        boss = {
            familyId   = "aquatic",
            behaviorId = "tank",
            monsterId  = "boss_leviathan",
            name       = "海渊之主·利维坦",
            raceTier   = "D",
        },
    },
}

AbyssConfig.THEME_CYCLE = 50    -- 每50层切换主题

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 当前层是否为Boss层
---@param floor number
---@return boolean
function AbyssConfig.IsBossFloor(floor)
    return floor % AbyssConfig.BOSS_INTERVAL == 0
end

--- 获取指定层的主题
---@param floor number
---@return table theme { name, monsters, boss }
function AbyssConfig.GetTheme(floor)
    local themeIdx = (math.floor((floor - 1) / AbyssConfig.THEME_CYCLE) % #AbyssConfig.THEMES) + 1
    return AbyssConfig.THEMES[themeIdx]
end

--- 从主题中随机选一个普通怪定义
---@param theme table
---@return table { familyId, behaviorId, monsterId }
function AbyssConfig.PickMonster(theme)
    local list = theme.monsters
    return list[math.random(1, #list)]
end

-- ============================================================================
-- 怪物属性计算 (委托 DynamicLevel)
-- ============================================================================

--- 计算深渊怪物最终 HP
---@param raceBaseHP number 种族基准 HP
---@param monsterLevel number 怪物等级
---@param layer number 深渊层数
---@param roleName string 角色名 ("normal"|"dungeon_boss"|...)
---@return number hp
function AbyssConfig.CalcHP(raceBaseHP, monsterLevel, layer, roleName)
    local abyssMul = DynamicLevel.AbyssHPMul(layer)
    local role     = DynamicLevel.GetRoleMul(roleName)
    return DynamicLevel.CalcHP(raceBaseHP, monsterLevel, abyssMul, role.hpMul)
end

--- 计算深渊怪物最终 ATK
---@param raceBaseATK number 种族基准 ATK
---@param monsterLevel number 怪物等级
---@param layer number 深渊层数
---@param roleName string 角色名
---@return number atk
function AbyssConfig.CalcATK(raceBaseATK, monsterLevel, layer, roleName)
    local abyssMul = DynamicLevel.AbyssATKMul(layer)
    local role     = DynamicLevel.GetRoleMul(roleName)
    return DynamicLevel.CalcATK(raceBaseATK, monsterLevel, abyssMul, role.atkMul)
end

--- 计算深渊怪物等级
---@param playerLevel number
---@param layer number 深渊层数
---@param worldTierId number 当前世界层级 (1-4)
---@return number monsterLevel
function AbyssConfig.CalcLevel(playerLevel, layer, worldTierId)
    return DynamicLevel.CalcAbyssLevel(playerLevel, layer, worldTierId)
end

return AbyssConfig
