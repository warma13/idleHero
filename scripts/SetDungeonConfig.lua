-- ============================================================================
-- SetDungeonConfig.lua - 套装秘境 怪物配置
--
-- 纯数据表，定义套装秘境的怪物阵容。
-- 由 SetDungeon.BuildQueue() 读取。
-- ============================================================================

local SDConfig = {}

-- ============================================================================
-- 怪物定义 (复用 ResourceDungeon 的怪物类型)
-- ============================================================================

SDConfig.MONSTERS = {
    swarm = {
        behaviorId = "swarm",
        name       = "秘境幻蝶",
        image      = "Textures/mobs/mine/mine_crystal_bug.png",
        resistRule = "theme",
        tags = function(C)
            if C >= 5 then return { packBonus = 1 } end
            return {}
        end,
    },
    bruiser = {
        behaviorId = "bruiser",
        name       = "秘境守卫",
        image      = "Textures/mobs/mine/mine_guard.png",
        resistRule = "balanced",
        tags = function(_C)
            return { slowOnHit = 1 }
        end,
    },
    caster = {
        behaviorId = "caster",
        name       = "秘境织法者",
        image      = "Textures/mobs/mine/mine_crystal_mage.png",
        resistRule = "theme",
        tags = function(C)
            if C >= 7 then return { healAura = 1 } end
            return {}
        end,
    },
    tank = {
        behaviorId = "tank",
        name       = "秘境巨像",
        image      = "Textures/mobs/mine/mine_rock_beast.png",
        resistRule = "phys_armor",
        tags = function(C)
            if C >= 5 then return { hpRegen = 1 } end
            return {}
        end,
    },
    glass = {
        behaviorId = "glass",
        name       = "秘境刺客",
        image      = "Textures/mobs/mine/mine_refract_bat.png",
        resistRule = "all_low",
        tags = function(C)
            if C >= 5 then return { defPierce = 1 } end
            return {}
        end,
    },
}

-- 精英定义
SDConfig.ELITE = {
    behaviorId = "caster",
    name       = "套装守护者",
    image      = "Textures/mobs/mine/mine_refract_lord.png",
    resistRule = "theme",
    color      = { 200, 100, 255 },
    tags = function(_C)
        return { healAura = 2, lifesteal = 1 }
    end,
}

-- ============================================================================
-- 出场序列构建
-- ============================================================================

--- 构建出场序列
---@param normalCount number 普通怪数量
---@param eliteCount number 精英数量
---@return string[]
function SDConfig.BuildSpawnSequence(normalCount, eliteCount)
    local monsterKeys = { "swarm", "bruiser", "caster", "tank", "glass" }
    local seq = {}

    -- 普通怪循环分配
    for i = 1, normalCount do
        local key = monsterKeys[((i - 1) % #monsterKeys) + 1]
        seq[#seq + 1] = key
    end

    -- 精英穿插在队列中（均匀分布）
    local totalWithElite = normalCount + eliteCount
    local interval = math.floor(totalWithElite / (eliteCount + 1))
    for e = 1, eliteCount do
        local pos = math.min(e * interval, #seq + 1)
        table.insert(seq, pos, "ELITE")
    end

    return seq
end

-- ============================================================================
-- 辅助
-- ============================================================================

local ELEMENT_TO_RESIST = {
    fire    = "fire_res",
    ice     = "ice_res",
    poison  = "poison_res",
    water   = "water_res",
    arcane  = "arcane_res",
    holy    = "holy_res",
}

---@param element string
---@return string
function SDConfig.GetThemeResistId(element)
    return ELEMENT_TO_RESIST[element] or "balanced"
end

return SDConfig
