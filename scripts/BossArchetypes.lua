--- Boss 原型系统
--- 7 个原型 (4 中Boss + 3 终Boss) × 元素注入 = 168 种组合
--- 设计文档: docs/系统设计/怪物家族重构设计.md §8

local MonsterTemplates = require("MonsterTemplates")
local MonsterFamilies  = require("MonsterFamilies")

local M = {}

---------------------------------------------------------------------------
-- 一、元素风味表
-- 同一原型在不同元素下产生完全不同的战斗体验
---------------------------------------------------------------------------

---@class ElementFlavor
---@field onHit table|string   命中效果
---@field decay string         衰减目标属性
---@field shieldReaction string 护盾反应类型
---@field weakElement string   弱点元素

local ELEMENT_FLAVOR = {
    ice    = { onHit = { slow = 0.10, slowDuration = 1.5 },    decay = "moveSpeed",  shieldReaction = "melt",      weakElement = "fire" },
    poison = { onHit = "ApplyVenomStackDebuff",                 decay = "def",        shieldReaction = "purify",    weakElement = "fire" },
    fire   = { onHit = "ApplyBlazeDebuff",                      decay = "atkSpeed",   shieldReaction = "quench",    weakElement = "water" },
    arcane = { onHit = { silence = 1.5 },                       decay = "crit",       shieldReaction = "dispel",    weakElement = "holy" },
    water  = { onHit = { corrode = 0.03 },                      decay = "healReduce", shieldReaction = "evaporate", weakElement = "fire" },
    holy   = { onHit = { blind = 2.0 },                         decay = "dmgReduce",  shieldReaction = "judgment",  weakElement = "arcane" },
}

---------------------------------------------------------------------------
-- 二、Boss 命名
---------------------------------------------------------------------------

local ARCHETYPE_TITLES = {
    striker_2p   = { "领主", "统帅" },
    charger_2p   = { "猛将", "冲锋者" },
    summoner_2p  = { "母巢", "召唤者" },
    fortress_2p  = { "守卫", "堡垒" },
    sovereign_3p = { "至尊", "君王" },
    overlord_3p  = { "霸主", "毁灭者" },
    herald_3p    = { "先驱", "裁决者" },
}

local ELEMENT_PREFIXES = {
    ice = "冰渊", fire = "焚天", poison = "腐蚀",
    arcane = "虚空", water = "深渊", holy = "天穹",
    physical = "蛮荒",
}

--- 自动生成 Boss 名称
---@param archetypeId string
---@param element string
---@param isFinal boolean
---@return string
local function generateBossName(archetypeId, element, isFinal)
    local prefix = ELEMENT_PREFIXES[element] or "混沌"
    local titles = ARCHETYPE_TITLES[archetypeId]
    local suffix = titles and titles[isFinal and 2 or 1] or "首领"
    return prefix .. suffix
end

---------------------------------------------------------------------------
-- 三、原型定义
-- category: "mid" = 中Boss, "final" = 终Boss
-- hp/atk: 相对 BossBase 的倍率
-- phases: 阶段模板（技能槽引用 BossSkillTemplates）
---------------------------------------------------------------------------

---@class BossArchetype
---@field category "mid"|"final"
---@field hp number       HP 倍率（相对 BossBase）
---@field atk number      ATK 倍率
---@field def number      基础 DEF
---@field radius number   碰撞半径
---@field atkInterval number  攻击间隔
---@field phases table[]  阶段模板

---@type table<string, BossArchetype>
local ARCHETYPES = {

    -- ━━━━━━━━━━ 中Boss 原型 (2阶段) ━━━━━━━━━━

    -- A: 弹幕突袭型
    -- P1: 远程弹幕 + 地面陷阱 + 召唤小怪
    -- P2: 360°弹幕 + 领域 + 防御 + 可摧毁物
    striker_2p = {
        category = "mid",
        hp = 1.7, atk = 0.85, def = 35, radius = 44, atkInterval = 1.8,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage",  defaults = { count = 18, spread = 140, dmgMul = 0.75, speed = 200, interval = 5.5 } },
                    { template = "ATK_spikes",   defaults = { count = 4, radius = 32, delay = 1.0, dmgMul = 1.1, lingerTime = 5.0, interval = 7.0 } },
                    { template = "SUM_minion",   defaults = { count = 5, interval = 8.0 } },
                },
                transition = { hpThreshold = 0.55, duration = 1.0 },
            },
            {
                hpThreshold = 0.55,
                skills = {
                    { template = "ATK_barrage",  defaults = { count = 16, spread = 360, dmgMul = 0.75, speed = 170, interval = 6.0 } },
                    { template = "CTL_field",    defaults = { radius = 120, dmgMul = 0.30, tickRate = 0.5, duration = 8.0, cd = 13.0 } },
                    { template = "DEF_armor",    defaults = { hpThreshold = 0.40, dmgReduce = 0.60, duration = 5.0, cd = 12.0 } },
                    { template = "DEF_crystal",  defaults = { count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 11.0, spawnRadius = 85 } },
                },
            },
        },
    },

    -- B: 吐息冲锋型
    -- P1: 锥形吐息 + 脉冲 + 召唤侍卫
    -- P2: 广角吐息 + 护甲 + 领域
    charger_2p = {
        category = "mid",
        hp = 1.5, atk = 0.90, def = 30, radius = 40, atkInterval = 1.6,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath",   defaults = { angle = 60, range = 150, dmgMul = 0.50, tickRate = 0.3, duration = 1.5, interval = 7.0 } },
                    { template = "ATK_pulse",    defaults = { speed = 80, width = 20, maxRadius = 180, dmgMul = 0.8, interval = 10.0 } },
                    { template = "SUM_guard",    defaults = { count = 2, hpPct = 0.01, atkMul = 0.35, interval = 14.0 } },
                },
                transition = { hpThreshold = 0.50, duration = 1.0 },
            },
            {
                hpThreshold = 0.50,
                skills = {
                    { template = "ATK_breath",   defaults = { angle = 100, range = 160, dmgMul = 0.65, tickRate = 0.3, duration = 2.0, interval = 7.0 } },
                    { template = "DEF_armor",    defaults = { hpThreshold = 0.40, dmgReduce = 0.55, duration = 5.0, cd = 13.0 } },
                    { template = "CTL_field",    defaults = { radius = 110, dmgMul = 0.25, tickRate = 0.5, duration = 7.0, cd = 14.0 } },
                },
            },
        },
    },

    -- C: 召唤统领型
    -- P1: 大量召唤 + 弹幕掩护
    -- P2: 精英侍卫 + 屏障 + 衰减
    summoner_2p = {
        category = "mid",
        hp = 2.0, atk = 0.70, def = 40, radius = 42, atkInterval = 2.0,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "SUM_minion",   defaults = { count = 6, interval = 7.0 } },
                    { template = "ATK_barrage",  defaults = { count = 12, spread = 120, dmgMul = 0.60, speed = 180, interval = 8.0 } },
                    { template = "DEF_crystal",  defaults = { count = 2, hpPct = 0.015, healPct = 0.012, spawnInterval = 12.0, spawnRadius = 80 } },
                },
                transition = { hpThreshold = 0.50, duration = 1.0 },
            },
            {
                hpThreshold = 0.50,
                skills = {
                    { template = "SUM_guard",    defaults = { count = 3, hpPct = 0.012, atkMul = 0.40, interval = 10.0 } },
                    { template = "CTL_barrier",  defaults = { count = 2, duration = 6.0, contactDmgMul = 0.30, interval = 13.0 } },
                    { template = "CTL_decay",    defaults = { stat = "moveSpeed", reducePerSec = 0.02, maxReduce = 0.30 } },
                },
            },
        },
    },

    -- D: 堡垒型 (旧版 Ch1-12 终Boss 的升级版)
    -- P1: 吐息 + 领域
    -- P2: 护甲 + 回血 + 召唤
    fortress_2p = {
        category = "mid",
        hp = 1.8, atk = 0.75, def = 45, radius = 44, atkInterval = 2.0,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath",   defaults = { angle = 70, range = 140, dmgMul = 0.45, tickRate = 0.3, duration = 1.5, interval = 8.0 } },
                    { template = "CTL_field",    defaults = { radius = 100, dmgMul = 0.20, tickRate = 0.5, duration = 6.0, cd = 15.0 } },
                    { template = "SUM_minion",   defaults = { count = 4, interval = 10.0 } },
                },
                transition = { hpThreshold = 0.50, duration = 1.0 },
            },
            {
                hpThreshold = 0.50,
                skills = {
                    { template = "DEF_armor",    defaults = { hpThreshold = 0.40, dmgReduce = 0.60, duration = 6.0, cd = 14.0 } },
                    { template = "DEF_regen",    defaults = { hpThreshold = 0.40, regenPct = 0.02 } },
                    { template = "SUM_guard",    defaults = { count = 2, hpPct = 0.01, atkMul = 0.35, interval = 12.0 } },
                    { template = "ATK_barrage",  defaults = { count = 14, spread = 360, dmgMul = 0.50, speed = 160, interval = 7.0 } },
                },
            },
        },
    },

    -- ━━━━━━━━━━ 终Boss 原型 (3阶段) ━━━━━━━━━━

    -- E: 君主型
    -- P1: 吐息试探 + 召唤侍卫
    -- P2: 控制地狱 + 反应护盾
    -- P3: 终焉绞杀
    sovereign_3p = {
        category = "final",
        hp = 3.0, atk = 0.90, def = 50, radius = 50, atkInterval = 2.2,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath",   defaults = { angle = 70, range = 160, dmgMul = 0.50, tickRate = 0.3, duration = 1.8, interval = 7.0 } },
                    { template = "ATK_spikes",   defaults = { count = 3, radius = 35, delay = 1.2, dmgMul = 1.1, lingerTime = 5.0, interval = 9.0 } },
                    { template = "SUM_guard",    defaults = { count = 2, hpPct = 0.012, atkMul = 0.35, tauntWeight = 0.55, interval = 14.0 } },
                },
                transition = { hpThreshold = 0.60, duration = 1.5 },
            },
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_breath",   defaults = { angle = 100, range = 160, dmgMul = 0.60, tickRate = 0.3, duration = 1.8, interval = 7.0 } },
                    { template = "CTL_decay",    defaults = { reducePerSec = 0.015, maxReduce = 0.40, bonusOnHit = 0.04 } },
                    { template = "CTL_barrier",  defaults = { count = 2, duration = 7.0, contactDmgMul = 0.35, interval = 13.0 } },
                    { template = "CTL_field",    defaults = { radius = 130, dmgMul = 0.30, tickRate = 0.5, duration = 9.0, cd = 15.0 } },
                    { template = "DEF_shield",   defaults = { hpPct = 0.035, bossDmgReduce = 0.80, duration = 10.0, cd = 18.0, hpThreshold = 0.50, baseResist = 0.50 } },
                },
                transition = { hpThreshold = 0.30, duration = 2.0 },
            },
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_armor",    defaults = { hpThreshold = 0.30, dmgReduce = 0.70, duration = 7.0, cd = 14.0 } },
                    { template = "DEF_regen",    defaults = { hpThreshold = 0.30, regenPct = 0.025 } },
                    { template = "CTL_vortex",   defaults = { radius = 110, pullSpeed = 35, coreDmgMul = 0.55, coreRadius = 35, duration = 4.5, interval = 11.0 } },
                    { template = "ATK_detonate", defaults = { count = 3, hpPct = 0.01, timer = 9.0, dmgMul = 2.2, bossHealPct = 0.08 } },
                },
            },
        },
    },

    -- F: 霸主型 (弹幕重心)
    -- P1: 弹幕 + 脉冲 + 召唤
    -- P2: 360°弹幕 + 屏障 + 可摧毁物
    -- P3: 爆破 + 漩涡
    overlord_3p = {
        category = "final",
        hp = 2.8, atk = 0.95, def = 45, radius = 48, atkInterval = 2.0,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage",  defaults = { count = 20, spread = 150, dmgMul = 0.70, speed = 200, interval = 5.5 } },
                    { template = "ATK_pulse",    defaults = { speed = 80, width = 20, maxRadius = 200, dmgMul = 0.8, interval = 10.0 } },
                    { template = "SUM_minion",   defaults = { count = 5, interval = 9.0 } },
                },
                transition = { hpThreshold = 0.60, duration = 1.5 },
            },
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_barrage",  defaults = { count = 24, spread = 360, dmgMul = 0.70, speed = 170, interval = 6.0 } },
                    { template = "CTL_field",    defaults = { radius = 130, dmgMul = 0.30, tickRate = 0.5, duration = 9.0, cd = 14.0 } },
                    { template = "CTL_barrier",  defaults = { count = 2, duration = 7.0, contactDmgMul = 0.35, interval = 13.0 } },
                    { template = "DEF_crystal",  defaults = { count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 12.0, spawnRadius = 90 } },
                },
                transition = { hpThreshold = 0.30, duration = 2.0 },
            },
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "ATK_detonate", defaults = { count = 4, hpPct = 0.012, timer = 8.0, dmgMul = 2.5, bossHealPct = 0.10 } },
                    { template = "CTL_vortex",   defaults = { radius = 120, pullSpeed = 40, coreDmgMul = 0.60, coreRadius = 35, duration = 5.0, interval = 10.0 } },
                    { template = "DEF_armor",    defaults = { hpThreshold = 0.30, dmgReduce = 0.65, duration = 6.0, cd = 13.0 } },
                    { template = "SUM_guard",    defaults = { count = 2, hpPct = 0.015, atkMul = 0.45, interval = 12.0 } },
                },
            },
        },
    },

    -- G: 先驱型 (防御重心)
    -- P1: 防御 + 侍卫 + 脉冲
    -- P2: 控场 + 衰减 + 吐息
    -- P3: 反应护盾 + 回血 + 爆破
    herald_3p = {
        category = "final",
        hp = 3.5, atk = 0.80, def = 60, radius = 50, atkInterval = 2.2,
        phases = {
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "DEF_armor",    defaults = { hpThreshold = 0.80, dmgReduce = 0.50, duration = 6.0, cd = 14.0 } },
                    { template = "SUM_guard",    defaults = { count = 3, hpPct = 0.015, atkMul = 0.40, interval = 12.0 } },
                    { template = "ATK_pulse",    defaults = { speed = 70, width = 20, maxRadius = 180, dmgMul = 0.7, interval = 9.0 } },
                },
                transition = { hpThreshold = 0.60, duration = 1.5 },
            },
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "CTL_field",    defaults = { radius = 140, dmgMul = 0.30, tickRate = 0.5, duration = 10.0, cd = 15.0 } },
                    { template = "CTL_decay",    defaults = { reducePerSec = 0.018, maxReduce = 0.35, bonusOnHit = 0.04 } },
                    { template = "ATK_breath",   defaults = { angle = 90, range = 160, dmgMul = 0.55, tickRate = 0.3, duration = 2.0, interval = 7.0 } },
                    { template = "DEF_crystal",  defaults = { count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 12.0, spawnRadius = 85 } },
                },
                transition = { hpThreshold = 0.30, duration = 2.0 },
            },
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_shield",   defaults = { hpPct = 0.04, bossDmgReduce = 0.80, duration = 10.0, cd = 20.0, hpThreshold = 0.50, baseResist = 0.50 } },
                    { template = "DEF_regen",    defaults = { hpThreshold = 0.30, regenPct = 0.030 } },
                    { template = "ATK_detonate", defaults = { count = 3, hpPct = 0.01, timer = 9.0, dmgMul = 2.0, bossHealPct = 0.08 } },
                    { template = "CTL_vortex",   defaults = { radius = 100, pullSpeed = 30, coreDmgMul = 0.55, coreRadius = 30, duration = 4.0, interval = 12.0 } },
                },
            },
        },
    },
}

---------------------------------------------------------------------------
-- 四、Deep Copy 工具
---------------------------------------------------------------------------

---@param t table
---@return table
local function deepCopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deepCopy(v)
    end
    return copy
end

---------------------------------------------------------------------------
-- 五、元素注入
-- 遍历所有技能槽，根据元素类型注入 onHit/decay/shield_reaction
---------------------------------------------------------------------------

---@param phases table  deep-copied phases
---@param element string  元素类型
local function injectElementFlavor(phases, element)
    local flavor = ELEMENT_FLAVOR[element]
    if not flavor then return end

    for _, phase in ipairs(phases) do
        for _, skill in ipairs(phase.skills) do
            -- 确保 params 存在（从 defaults 复制而来）
            local p = skill.params

            -- 攻击技能注入 onHit
            if skill.template == "ATK_barrage" or skill.template == "ATK_breath" then
                p.onHit = p.onHit or flavor.onHit
            end

            -- 衰减技能注入目标属性
            if skill.template == "CTL_decay" then
                p.stat = p.stat or flavor.decay
            end

            -- 护盾技能注入反应类型
            if skill.template == "DEF_shield" then
                p.shield_reaction = p.shield_reaction or {
                    weakReaction = flavor.shieldReaction,
                    weakElement = flavor.weakElement,
                    weakMultiplier = 2.5,
                }
            end

            -- 领域技能注入效果
            if skill.template == "CTL_field" then
                p.effect = p.effect or flavor.onHit
            end

            -- 漩涡技能注入核心效果
            if skill.template == "CTL_vortex" then
                p.coreEffect = p.coreEffect or flavor.onHit
            end
        end
    end
end

---------------------------------------------------------------------------
-- 六、原型解析
---------------------------------------------------------------------------

--- 获取原型定义（只读）
---@param archetypeId string
---@return BossArchetype|nil
function M.GetArchetype(archetypeId)
    return ARCHETYPES[archetypeId]
end

--- 将 Boss 配置三元组解析为 Spawner 兼容的 Boss 定义
--- 输入: { archetype, element, family, nameOverride? }
--- 输出: 含 phases 的完整 Boss 定义（可直接放入 spawnQueue）
---@param bossConfig table  { archetype = string, element = string, family = string, nameOverride? = string }
---@param chapter number    章节号（决定数值缩放）
---@return table bossDef    Spawner 兼容的 Boss 定义
function M.Resolve(bossConfig, chapter)
    local archetypeId = bossConfig.archetype
    local element     = bossConfig.element
    local familyId    = bossConfig.family

    local archetype = ARCHETYPES[archetypeId]
    if not archetype then
        error("BossArchetypes.Resolve: unknown archetype '" .. tostring(archetypeId) .. "'")
    end

    local family = MonsterFamilies.Get(familyId)
    local isFinal = archetype.category == "final"

    -- 基准数值（从 MonsterTemplates.BossBase 获取）
    local base = isFinal and MonsterTemplates.BossBase.final or MonsterTemplates.BossBase.mid

    -- 1) Deep-copy phases，将 defaults 展开为 params
    local phases = deepCopy(archetype.phases)
    for _, phase in ipairs(phases) do
        for _, skill in ipairs(phase.skills) do
            skill.params = skill.params or {}
            if skill.defaults then
                for k, v in pairs(skill.defaults) do
                    if skill.params[k] == nil then
                        skill.params[k] = v
                    end
                end
                skill.defaults = nil  -- 清理，Spawner 不需要 defaults
            end
        end
    end

    -- 2) 注入元素风味
    injectElementFlavor(phases, element)

    -- 3) 计算抗性（使用家族的抗性模板 + 章节系数）
    local resistId = family and family.resistProfile or "balanced"
    local resist = MonsterTemplates.CalcResist(resistId, chapter)

    -- 4) 外观
    local colorBase = family and family.colorBase or { 128, 128, 128 }
    local name = bossConfig.nameOverride or generateBossName(archetypeId, element, isFinal)

    -- 贴图：优先 bossConfig.image，否则用家族 caster 的贴图作占位
    local image = bossConfig.image or ""
    if image == "" and family then
        local casterMember = family.members.caster
        if casterMember then
            image = casterMember.image
        end
    end

    -- 5) 组装 Boss 定义
    local def = {
        -- 基础属性（原始基准 × 原型倍率，Spawner 运行时再 × scaleMul）
        hp          = math.floor(base.hp * archetype.hp),
        atk         = math.floor(base.atk * archetype.atk),
        def         = archetype.def,
        speed       = base.speed,
        atkInterval = archetype.atkInterval,
        radius      = archetype.radius,
        element     = element,
        resist      = resist,

        -- Boss 标记
        isBoss      = true,
        expDrop     = isFinal and 120 or 60,
        dropTemplate = isFinal and "boss_final" or "boss_mid",

        -- 外观
        name        = name,
        image       = image,
        color       = { colorBase[1], colorBase[2], colorBase[3] },

        -- 阶段技能（BossSkillTemplates 系统）
        phases      = phases,
    }

    return def
end

--- 生成 Boss 注册ID（用于 MONSTERS 表的 key）
--- 格式: "boss_{archetypeId}_{element}"
---@param bossConfig table  { archetype, element, family }
---@return string
function M.MakeBossId(bossConfig)
    return "boss_" .. bossConfig.archetype .. "_" .. bossConfig.element
end

return M
