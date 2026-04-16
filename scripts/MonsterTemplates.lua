--- 怪物模板系统
--- 三层正交架构: 行为模板 × 抗性模板 × 章节主题/数值缩放
--- 设计文档: docs/数值/怪物模板系统.md

local M = {}

---------------------------------------------------------------------------
-- 一、行为模板 (7 种)
-- 基准值固定，不随章节变化。所有数值增长交给 scaleMul。
-- speed / atkInterval 不缩放。
---------------------------------------------------------------------------

---@alias BehaviorId "swarm"|"tank"|"glass"|"bruiser"|"debuffer"|"caster"|"exploder"

---@class BehaviorTemplate
---@field hp number       基准 HP（scaleMul 缩放）
---@field atk number      基准 ATK（scaleMul^atkExp 缩放）
---@field def number      基准 DEF（scaleMul 缩放）
---@field speed number    移动速度（不缩放）
---@field atkInterval number 攻击间隔秒（不缩放）
---@field expDrop number  基础经验值
---@field dropTemplate string 掉落模板 ID
---@field radius number   碰撞半径（像素）
---@field defaultTags table<string, boolean|number> 默认能力标签槽（始终携带）
---@field optionalTags table<string, number> 可选标签槽（key = 标签名, value = 引入章节）

---@type table<BehaviorId, BehaviorTemplate>
M.Behaviors = {
    swarm = {
        hp = 35, atk = 3, def = 0, speed = 55, atkInterval = 1.2,
        expDrop = 8, dropTemplate = "common", radius = 14,
        defaultTags = {},
        optionalTags = { packBonus = 2 },
    },
    tank = {
        hp = 160, atk = 9, def = 14, speed = 15, atkInterval = 1.8,
        expDrop = 20, dropTemplate = "elite", radius = 20,
        defaultTags = { antiHeal = true },
        optionalTags = { hpRegen = 2, sporeCloud = 7 },
    },
    glass = {
        hp = 20, atk = 14, def = 0, speed = 75, atkInterval = 0.8,
        expDrop = 12, dropTemplate = "common", radius = 13,
        defaultTags = {},
        optionalTags = { defPierce = 2, firstStrikeMul = 4 },
    },
    bruiser = {
        hp = 70, atk = 8, def = 3, speed = 40, atkInterval = 1.0,
        expDrop = 15, dropTemplate = "elite", radius = 16,
        defaultTags = {},
        optionalTags = { slowOnHit = 1, lifesteal = 4, venomStack = 7 },
    },
    debuffer = {
        hp = 60, atk = 5, def = 1, speed = 25, atkInterval = 1.0,
        expDrop = 12, dropTemplate = "common", radius = 15,
        defaultTags = { slowOnHit = true },
        optionalTags = { antiHeal = 1 },
    },
    caster = {
        hp = 70, atk = 15, def = 4, speed = 30, atkInterval = 1.0,
        expDrop = 18, dropTemplate = "elite", radius = 16,
        defaultTags = { isRanged = true },
        optionalTags = { healAura = 4, lifesteal = 4 },
    },
    exploder = {
        hp = 40, atk = 8, def = 2, speed = 40, atkInterval = 1.0,
        expDrop = 10, dropTemplate = "common", radius = 14,
        defaultTags = { deathExplode = true },
        optionalTags = { packBonus = 8 },
    },
}

---------------------------------------------------------------------------
-- 二、抗性模板 (~12 种)
-- 基准值 × 章节抗性系数 = 最终抗性值
-- 值域: 负值=弱点（受伤加深）, 正值=抗性（受伤减少）
---------------------------------------------------------------------------

---@alias ResistId "balanced"|"fire_res"|"ice_res"|"poison_res"|"water_res"|"arcane_res"|"holy_res"|"phys_armor"|"magic_vuln"|"all_low"|"all_high"|"mixed_a"

---@class ResistTemplate
---@field fire number
---@field ice number
---@field poison number
---@field water number
---@field arcane number
---@field physical number

---@type table<ResistId, ResistTemplate>
M.Resists = {
    balanced    = { fire = 10,  ice = 10,  poison = 10,  water = 10,  arcane = 10,  physical = 10 },
    fire_res    = { fire = 50,  ice = 5,   poison = 10,  water = 0,   arcane = 5,   physical = 15 },
    ice_res     = { fire = 0,   ice = 50,  poison = 5,   water = 10,  arcane = 5,   physical = 15 },
    poison_res  = { fire = 5,   ice = 5,   poison = 50,  water = 0,   arcane = 10,  physical = 15 },
    water_res   = { fire = 0,   ice = 10,  poison = 0,   water = 50,  arcane = 5,   physical = 15 },
    arcane_res  = { fire = 5,   ice = 5,   poison = 10,  water = 5,   arcane = 50,  physical = 10 },
    holy_res    = { fire = 5,   ice = 5,   poison = -10, water = 5,   arcane = 10,  physical = 10 },
    phys_armor  = { fire = -5,  ice = -5,  poison = 0,   water = -5,  arcane = -10, physical = 40 },
    magic_vuln  = { fire = -10, ice = -10, poison = 0,   water = -10, arcane = -15, physical = 30 },
    all_low     = { fire = -5,  ice = -5,  poison = -5,  water = -5,  arcane = -5,  physical = -5 },
    all_high    = { fire = 25,  ice = 25,  poison = 25,  water = 25,  arcane = 25,  physical = 25 },
    mixed_a     = { fire = 30,  ice = -10, poison = 20,  water = -10, arcane = 15,  physical = 10 },
}

---------------------------------------------------------------------------
-- 三、能力标签等级参数表
-- 每个标签有 1~5 级，等级决定具体数值。
-- 结构: TagParams[标签名][等级] = { 参数表 }
---------------------------------------------------------------------------

---@type table<string, table<number, table>>
M.TagParams = {
    -- A. 减益类 --------------------------------------------------------

    slowOnHit = {
        [1] = { slowAmount = 0.20, slowDuration = 1.5 },
        [2] = { slowAmount = 0.30, slowDuration = 2.0 },
        [3] = { slowAmount = 0.35, slowDuration = 2.5 },
        [4] = { slowAmount = 0.40, slowDuration = 2.5 },
        [5] = { slowAmount = 0.50, slowDuration = 3.0 },
    },

    sporeCloud = {
        [1] = { atkSpeedReducePct = 0.15, duration = 4.0 },
        [2] = { atkSpeedReducePct = 0.20, duration = 5.0 },
        [3] = { atkSpeedReducePct = 0.25, duration = 5.0 },
        [4] = { atkSpeedReducePct = 0.30, duration = 5.0 },
        [5] = { atkSpeedReducePct = 0.35, duration = 5.0 },
    },

    venomStack = {
        [1] = { dmgPctPerStack = 0.015, stackMax = 6, duration = 5.0 },
        [2] = { dmgPctPerStack = 0.020, stackMax = 8, duration = 6.0 },
        [3] = { dmgPctPerStack = 0.025, stackMax = 6, duration = 5.0 },
        [4] = { dmgPctPerStack = 0.030, stackMax = 5, duration = 5.0 },
        [5] = { dmgPctPerStack = 0.040, stackMax = 6, duration = 5.0 },
    },

    corrosion = {
        [1] = { defReducePct = 0.08, stackMax = 5, duration = 8.0 },
    },

    inkBlind = {
        [1] = { atkReducePct = 0.25, duration = 4.0 },
    },

    sandStorm = {
        [1] = { critReducePct = 0.20, duration = 5.0 },
    },

    -- B. 攻击增强类 ----------------------------------------------------

    defPierce = {
        [1] = { pierce = 0.25 },
        [2] = { pierce = 0.30 },
        [3] = { pierce = 0.35 },
        [4] = { pierce = 0.425 },
        [5] = { pierce = 0.50 },
    },

    firstStrikeMul = {
        [1] = { mul = 2.0 },
        [2] = { mul = 2.2 },
        [3] = { mul = 2.5 },
        [4] = { mul = 2.8 },
    },

    packBonus = {
        [1] = { bonus = 0.25, threshold = 5 },
        [2] = { bonus = 0.30, threshold = 4 },
        [3] = { bonus = 0.35, threshold = 3 },
        [4] = { bonus = 0.40, threshold = 4 },
        [5] = { bonus = 0.45, threshold = 4 },
    },

    chargeUp = {
        [1] = { stackMax = 5, dmgMul = 2.5, aoe = false },
        [2] = { stackMax = 8, dmgMul = 2.0, aoe = true, aoeRadius = 60 },
    },

    chainLightning = {
        [1] = { bounces = 2, dmgMul = 0.50, range = 80 },
    },

    -- C. 防御/续航类 ---------------------------------------------------

    lifesteal = {
        [1] = { pct = 0.12 },
        [2] = { pct = 0.15 },
        [3] = { pct = 0.18 },
        [4] = { pct = 0.20 },
    },

    hpRegen = {
        [1] = { regenPct = 0.02, interval = 6.0 },
        [2] = { regenPct = 0.025, interval = 5.0 },
        [3] = { regenPct = 0.03, interval = 5.0 },
    },

    healAura = {
        [1] = { pct = 0.04, interval = 7.0, radius = 90 },
        [2] = { pct = 0.05, interval = 7.0, radius = 100 },
        [3] = { pct = 0.06, interval = 7.0, radius = 100 },
        [4] = { pct = 0.07, interval = 7.0, radius = 120 },
        [5] = { pct = 0.08, interval = 7.0, radius = 120 },
    },

    -- D. 死亡触发类 ---------------------------------------------------

    deathExplode = {
        [1] = { dmgMul = 0.6, radius = 35 },
        [2] = { dmgMul = 0.8, radius = 42 },
        [3] = { dmgMul = 1.0, radius = 50 },
        [4] = { dmgMul = 1.2, radius = 55 },
        [5] = { dmgMul = 1.5, radius = 58 },
    },

    splitOnDeath = {
        [1] = { count = 2, childHpRatio = 0.4, childAtkRatio = 0.4 },
    },
}

---------------------------------------------------------------------------
-- 四、章节主题配置
-- 每章的元素主题、抗性系数、色调等。
---------------------------------------------------------------------------

---@class ChapterTheme
---@field name string         章节名称
---@field element string      主题元素
---@field auxElements string[] 辅助元素
---@field resistCoeff number  抗性系数（基准值 × 此系数 = 最终抗性百分比 / 100）
---@field colorBase number[]  色调基础 {r, g, b}

---@type table<number, ChapterTheme>
M.ChapterThemes = {
    [1]  = { name = "灰烬荒原", element = "fire",   auxElements = { "poison", "water", "arcane" }, resistCoeff = 0.3,  colorBase = { 140, 120, 100 } },
    [2]  = { name = "冰封深渊", element = "ice",    auxElements = { "water", "physical" },         resistCoeff = 0.3,  colorBase = { 150, 180, 220 } },
    [3]  = { name = "熔岩炼狱", element = "fire",   auxElements = { "poison" },                    resistCoeff = 0.5,  colorBase = { 200, 100, 60 } },
    [4]  = { name = "幽暗墓域", element = "arcane", auxElements = { "poison", "physical" },        resistCoeff = 0.5,  colorBase = { 100, 80, 140 } },
    [5]  = { name = "深海渊域", element = "water",  auxElements = { "poison" },                    resistCoeff = 0.7,  colorBase = { 60, 120, 180 } },
    [6]  = { name = "雷鸣荒漠", element = "arcane", auxElements = { "fire", "physical" },          resistCoeff = 0.7,  colorBase = { 200, 180, 120 } },
    [7]  = { name = "瘴毒密林", element = "poison", auxElements = { "physical" },                  resistCoeff = 0.85, colorBase = { 80, 160, 80 } },
    [8]  = { name = "虚空裂隙", element = "arcane", auxElements = { "physical" },                  resistCoeff = 0.85, colorBase = { 100, 60, 160 } },
    [9]  = { name = "天穹圣域", element = "holy",   auxElements = { "physical" },                  resistCoeff = 1.0,  colorBase = { 220, 200, 140 } },
    [10] = { name = "永夜深渊", element = "arcane", auxElements = { "fire" },                      resistCoeff = 1.0,  colorBase = { 60, 40, 100 } },
    [11] = { name = "焚天炼狱", element = "fire",   auxElements = { "physical" },                  resistCoeff = 1.1,  colorBase = { 220, 80, 40 } },
    [12] = { name = "时渊回廊", element = "arcane", auxElements = { "physical" },                  resistCoeff = 1.1,  colorBase = { 140, 100, 180 } },
    [13] = { name = "寒渊冰域", element = "ice",    auxElements = { "water", "physical" },         resistCoeff = 1.2,  colorBase = { 100, 200, 230 } },
    [14] = { name = "腐蚀魔域", element = "poison", auxElements = { "physical", "water" },         resistCoeff = 1.2,  colorBase = { 80, 180, 60 } },
}

---------------------------------------------------------------------------
-- 五、Boss 基准值
-- Boss 不走小怪 scaleMul，但定义比例锚点便于新章快速配值。
---------------------------------------------------------------------------

M.BossBase = {
    mid  = { hp = 600,  atk = 10, def = 8,  speed = 22, atkInterval = 1.5 },
    final = { hp = 1200, atk = 14, def = 12, speed = 14, atkInterval = 2.0 },
}

--- 中 Boss hpBase / swarm hpBase ≈ 17x
--- 终 Boss hpBase / swarm hpBase ≈ 34x
--- 终 Boss / 中 Boss ≈ 2x

---------------------------------------------------------------------------
-- 六、缩放参数
---------------------------------------------------------------------------

M.Scaling = {
    atkExp = 0.75,  -- ATK 缩放指数（< 1.0 使 ATK 增速慢于 HP）
}

---------------------------------------------------------------------------
-- 七、组装函数
-- 将行为模板 + 抗性模板 + 能力标签 + 章节主题 组装为 Spawner 兼容的怪物定义。
---------------------------------------------------------------------------

--- 计算最终抗性值
---@param resistId ResistId
---@param chapter number
---@return table resist {fire=, ice=, poison=, water=, arcane=, physical=}
function M.CalcResist(resistId, chapter)
    local base = M.Resists[resistId]
    if not base then
        return nil
    end
    local theme = M.ChapterThemes[chapter]
    local coeff = theme and theme.resistCoeff or 1.0
    return {
        fire     = base.fire * coeff / 100,
        ice      = base.ice * coeff / 100,
        poison   = base.poison * coeff / 100,
        water    = base.water * coeff / 100,
        arcane   = base.arcane * coeff / 100,
        physical = base.physical * coeff / 100,
    }
end

--- 将能力标签展开为 Spawner 兼容的扁平字段
---@param tags table<string, number> { tagName = level, ... }
---@param chapter number
---@param element string 章节元素（deathExplode 的 element）
---@return table fields 扁平字段表
function M.ExpandTags(tags, chapter, element)
    local out = {}
    for tagName, level in pairs(tags) do
        local defs = M.TagParams[tagName]
        if not defs then
            -- 布尔标签（antiHeal, isRanged）
            out[tagName] = true
        else
            local params = defs[level] or defs[1]
            if tagName == "slowOnHit" then
                out.slowOnHit = params.slowAmount
                out.slowDuration = params.slowDuration
            elseif tagName == "defPierce" then
                out.defPierce = params.pierce
            elseif tagName == "firstStrikeMul" then
                out.firstStrikeMul = params.mul
            elseif tagName == "packBonus" then
                out.packBonus = params.bonus
                out.packThreshold = params.threshold
            elseif tagName == "deathExplode" then
                out.deathExplode = {
                    element = element,
                    dmgMul = params.dmgMul,
                    radius = params.radius,
                }
            elseif tagName == "splitOnDeath" then
                out.splitOnDeath = {
                    count = params.count,
                    childHpRatio = params.childHpRatio,
                    childAtkRatio = params.childAtkRatio,
                }
            elseif tagName == "hpRegen" then
                out.hpRegen = params.regenPct
                out.hpRegenInterval = params.interval
            elseif tagName == "healAura" then
                out.healAura = {
                    pct = params.pct,
                    interval = params.interval,
                    radius = params.radius,
                }
            elseif tagName == "lifesteal" then
                out.lifesteal = params.pct
            elseif tagName == "corrosion" then
                out.corrosion = {
                    defReducePct = params.defReducePct,
                    stackMax = params.stackMax,
                    duration = params.duration,
                }
            elseif tagName == "inkBlind" then
                out.inkBlind = {
                    atkReducePct = params.atkReducePct,
                    duration = params.duration,
                }
            elseif tagName == "sandStorm" then
                out.sandStorm = {
                    critReducePct = params.critReducePct,
                    duration = params.duration,
                }
            elseif tagName == "chargeUp" then
                out.chargeUp = {
                    stackMax = params.stackMax,
                    dmgMul = params.dmgMul,
                    resetOnTrigger = true,
                }
                if params.aoe then
                    out.chargeUp.aoe = true
                    out.chargeUp.aoeRadius = params.aoeRadius
                end
            elseif tagName == "chainLightning" then
                out.chainLightning = {
                    bounces = params.bounces,
                    dmgMul = params.dmgMul,
                    element = element,
                    range = params.range,
                }
            elseif tagName == "venomStack" then
                out.venomStack = {
                    dmgPctPerStack = params.dmgPctPerStack,
                    stackMax = params.stackMax,
                    duration = params.duration,
                }
            elseif tagName == "sporeCloud" then
                out.sporeCloud = {
                    atkSpeedReducePct = params.atkSpeedReducePct,
                    duration = params.duration,
                }
            end
        end
    end
    return out
end

--- 组装一个怪物定义（与 Spawner 兼容）
---@param behaviorId BehaviorId
---@param resistId ResistId
---@param chapter number
---@param opts table|nil 额外覆盖 { name, image, color, tags = {tagName=level}, expDrop, dropTemplate }
---@return table monsterDef Spawner 兼容的怪物定义表
function M.Assemble(behaviorId, resistId, chapter, opts)
    opts = opts or {}
    local beh = M.Behaviors[behaviorId]
    local theme = M.ChapterThemes[chapter]
    local element = theme and theme.element or "physical"

    -- 基础属性（原始基准值，由 Spawner 在运行时 × scaleMul）
    local def = {
        hp          = beh.hp,
        atk         = beh.atk,
        def         = beh.def,
        speed       = beh.speed,
        atkInterval = beh.atkInterval,
        element     = element,
        expDrop     = opts.expDrop or beh.expDrop,
        dropTemplate = opts.dropTemplate or beh.dropTemplate,
        radius      = beh.radius,
        -- 外观（需调用方提供）
        name        = opts.name or (theme and theme.name or "") .. behaviorId,
        image       = opts.image or "",
        color       = opts.color or (theme and theme.colorBase or { 128, 128, 128 }),
    }

    -- 抗性
    def.resist = M.CalcResist(resistId, chapter)

    -- 能力标签: 合并默认标签 + 调用方指定标签
    local mergedTags = {}
    for k, v in pairs(beh.defaultTags) do
        if type(v) == "boolean" then
            mergedTags[k] = v  -- 布尔标签直接存
        else
            mergedTags[k] = v  -- 数值标签（等级），后面覆盖
        end
    end
    if opts.tags then
        for k, v in pairs(opts.tags) do
            mergedTags[k] = v
        end
    end

    -- 展开标签为扁平字段
    local tagFields = M.ExpandTags(mergedTags, chapter, element)
    for k, v in pairs(tagFields) do
        def[k] = v
    end

    return def
end

return M
