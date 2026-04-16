-- ============================================================================
-- ResourceDungeonConfig.lua - 折光矿脉 怪物配置
--
-- 纯数据表，定义矿脉怪物的阵容、抗性、能力标签、贴图路径。
-- 由 ResourceDungeon.BuildMineQueue() 读取。
-- ============================================================================

local RDConfig = {}

-- ============================================================================
-- 常量
-- ============================================================================

RDConfig.MAX_DAILY_ATTEMPTS = 3        -- 每日挑战次数
RDConfig.FIGHT_DURATION     = 60       -- 战斗时长(秒)
RDConfig.MONSTER_SCALE      = 0.9      -- 怪物强度系数(相对章节末关)
RDConfig.ELITE_HP_MUL       = 3.0      -- 精英HP倍率

-- ============================================================================
-- 怪物定义 (7种普通 + 1精英)
--
-- behaviorId: 行为模板ID (对应 MonsterTemplates.Behaviors)
-- name:       矿脉主题名称
-- image:      专属贴图路径
-- resistRule: 抗性规则 ("theme"=跟随章节主题元素, 或固定抗性模板ID)
-- tags:       能力标签 (函数, 接收maxChapter返回tags表)
-- ============================================================================

RDConfig.MONSTERS = {
    swarm = {
        behaviorId = "swarm",
        name       = "碎晶虫",
        image      = "Textures/mobs/mine/mine_crystal_bug.png",
        resistRule = "theme",
        tags = function(C)
            if C >= 2 then return { packBonus = 1 } end
            return {}
        end,
    },
    glass = {
        behaviorId = "glass",
        name       = "折光蝠",
        image      = "Textures/mobs/mine/mine_refract_bat.png",
        resistRule = "all_low",
        tags = function(C)
            if C >= 2 then return { defPierce = 1 } end
            return {}
        end,
    },
    bruiser = {
        behaviorId = "bruiser",
        name       = "矿脉卫兵",
        image      = "Textures/mobs/mine/mine_guard.png",
        resistRule = "balanced",
        tags = function(_C)
            return { slowOnHit = 1 }
        end,
    },
    debuffer = {
        behaviorId = "debuffer",
        name       = "辉石蛞蝓",
        image      = "Textures/mobs/mine/mine_slug.png",
        resistRule = "theme",
        tags = function(_C)
            return {}  -- slowOnHit 是 debuffer 的默认标签
        end,
    },
    caster = {
        behaviorId = "caster",
        name       = "晶能术士",
        image      = "Textures/mobs/mine/mine_crystal_mage.png",
        resistRule = "theme",
        tags = function(C)
            if C >= 4 then return { healAura = 1 } end
            return {}
        end,
    },
    tank = {
        behaviorId = "tank",
        name       = "岩晶巨兽",
        image      = "Textures/mobs/mine/mine_rock_beast.png",
        resistRule = "phys_armor",
        tags = function(C)
            if C >= 2 then return { hpRegen = 1 } end
            return {}
        end,
    },
    exploder = {
        behaviorId = "exploder",
        name       = "爆晶虫",
        image      = "Textures/mobs/mine/mine_burst_bug.png",
        resistRule = "all_low",
        tags = function(_C)
            return {}  -- deathExplode 是 exploder 的默认标签
        end,
    },
}

-- 精英定义
RDConfig.ELITE = {
    behaviorId = "caster",
    name       = "折光领主",
    image      = "Textures/mobs/mine/mine_refract_lord.png",
    resistRule = "theme",
    color      = { 255, 180, 50 },
    tags = function(_C)
        return { healAura = 2, lifesteal = 1 }
    end,
}

-- ============================================================================
-- 出场序列
--
-- 字符串key对应 MONSTERS 表, "ELITE" 为精英位置
-- 三梯队设计:
--   先锋 (#1~#10):  swarm + glass, 快节奏清扫
--   主力 (#11~#20): bruiser + debuffer + caster + exploder, 策略深度
--   精锐 (#21~#31): 全类型混合, 高压收尾
-- ============================================================================

RDConfig.SPAWN_SEQUENCE = {
    -- 先锋 (1-10)
    "swarm", "swarm", "glass", "swarm", "glass",
    "swarm", "glass", "swarm", "glass", "swarm",
    -- 主力前半 (11-15)
    "bruiser", "debuffer", "caster", "bruiser", "debuffer",
    -- 精英 (16)
    "ELITE",
    -- 主力后半 (17-20)
    "exploder", "bruiser", "debuffer", "caster",
    -- 精锐 (21-31)
    "swarm", "bruiser", "glass", "tank", "swarm",
    "bruiser", "exploder", "glass", "swarm", "bruiser", "glass",
}

-- ============================================================================
-- 辅助: 章节主题元素 → 抗性模板ID映射
-- ============================================================================

local ELEMENT_TO_RESIST = {
    fire    = "fire_res",
    ice     = "ice_res",
    poison  = "poison_res",
    water   = "water_res",
    arcane  = "arcane_res",
    holy    = "holy_res",
}

--- 根据章节主题获取抗性模板ID
---@param element string 章节主题元素
---@return string resistId
function RDConfig.GetThemeResistId(element)
    return ELEMENT_TO_RESIST[element] or "balanced"
end

return RDConfig
