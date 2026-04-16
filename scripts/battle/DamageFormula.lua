-- ============================================================================
-- battle/DamageFormula.lua - 六桶伤害管线 (v3.0 D4模型)
-- ============================================================================
-- 最终伤害 = 桶0基础 × 桶1主属性 × 桶2A伤 × 桶3暴击 × 桶4易伤
--            × 桶5X伤(独立连乘) + 桶6压制(3%触发)
--            × 防御区 × 抗性区
--
-- 设计原则:
--   - 同桶加算, 跨桶乘算 (D4六桶规则)
--   - A伤堆叠边际递减 → 鼓励多桶均衡
--   - X伤各源独立乘算 → 高端Build核心追求
--   - 压制伤害 = 额外固定值 (基于当前HP+盾值)
--   - 移除元素反应系统, 保留防御区+抗性区
-- ============================================================================

local Config         = require("Config")
local GameState      = require("GameState")
local AffixHelper    = require("state.AffixHelper")
local DefenseFormula = require("DefenseFormula")

local DamageFormula = {}

-- ============================================================================
-- 内部: 获取当前世界层级 ID (供抗性穿透使用)
-- ============================================================================

local function getWorldTierId()
    if GameState.spireTrial and GameState.spireTrial.worldTier then
        return GameState.spireTrial.worldTier
    end
    return 1
end

-- ============================================================================
-- 内部: 按攻击元素取元素增伤
-- ============================================================================

local ELEM_TO_STAT = {
    fire = "fireDmg", ice = "iceDmg", lightning = "lightningDmg",
}

--- 根据实际攻击元素计算元素增伤
--- (技能用技能自身元素, 普攻用武器元素)
local function getElemDmgBonus(element)
    local specificKey = ELEM_TO_STAT[element]
    local specific = specificKey and GameState._equipSum(specificKey) or 0
    local allElem = GameState._equipSum("elemDmg")
    local setStats = GameState.GetSetBonusStats()
    return specific + allElem + (setStats.elemDmg or 0)
end

-- ============================================================================
-- 桶0: 基础伤害 (绝对值)
-- = 武器伤害 × 技能系数 × 技能等级倍率
-- 或 baseDmg (弹体预计算)
-- ============================================================================

local function CalcBase(ctx)
    if ctx.baseDmg then
        return ctx.baseDmg
    end
    return ctx.totalAtk * ctx.multiplier
end

-- ============================================================================
-- 桶1: 主属性乘数 (1 + M × 0.001)
-- 术士主属性 = INT (智力)
-- ============================================================================

local function CalcMainStat(ctx)
    return 1 + ctx.mainStatPoints * 0.001
end

-- ============================================================================
-- 桶2: A伤 (加法类伤害, 区内加算 → 1 + ΣAi)
-- 包含: 元素增伤、药水、印记、套装增伤、词缀增伤、技能专属增伤
-- 注意: 装备易伤加成也归入此桶 (D4 1.2后规则)
-- ============================================================================

local function CalcAdditive(ctx)
    local bonus = 0

    -- 元素增伤 (非物理)
    if ctx.element ~= "physical" then
        bonus = bonus + ctx.elemDmgBonus
    end

    -- 攻击药水
    bonus = bonus + ctx.atkPotionBonus

    -- 套装被动增伤 (atkDmg/normalAtkDmg 等)
    bonus = bonus + (ctx.setPassiveBonus or 0)

    -- 迅捷猎手4件: 同目标叠层增伤
    bonus = bonus + (ctx.swiftHunterBonus or 0)

    -- 龙息之怒4件: 普攻/技能交替增伤
    if ctx.damageTag == "normal" then
        bonus = bonus + (ctx.dragonFuryAtkBonus or 0)
    elseif ctx.damageTag == "skill" then
        bonus = bonus + (ctx.dragonFurySkillBonus or 0)
        -- 符文编织4件: 下次技能增伤 (一次性消耗)
        bonus = bonus + (ctx.runeNextSkillBonus or 0)
        -- 符文编织6件: 共鸣期间技能增伤
        bonus = bonus + (ctx.runeResonanceSkillDmg or 0)
    end

    -- 龙息之怒6件: 龙威全伤害加成
    bonus = bonus + (ctx.dragonMightBonus or 0)

    -- 词缀: 精英猎手 (对Boss/精英增伤)
    bonus = bonus + (ctx.affixEliteHunterBonus or 0)

    -- 装备易伤加成 → 归入A伤桶 (D4 1.2后规则)
    bonus = bonus + (ctx.vulnerableEquipBonus or 0)

    -- 技能/天赋专属加成 (调用者通过 extraBonuses 传入)
    if ctx.extraBonuses then
        for _, v in pairs(ctx.extraBonuses) do
            bonus = bonus + v
        end
    end

    return 1 + bonus
end

-- ============================================================================
-- 桶3: 暴击乘数
-- 暴击时 = 1 + 暴击伤害加成; 非暴击 = 1.0
-- (critDmg 已包含基础50%+装备加成, 如 1.8 = 基础50%+额外30%)
-- ============================================================================

local function CalcCrit(ctx)
    if ctx.isCrit then
        -- critDmg 是总暴伤倍率 (如 1.8), 暴击时伤害 × critDmg
        return ctx.critDmg
    end
    return 1.0
end

-- ============================================================================
-- 桶4: 易伤独立乘数
-- 目标处于易伤状态时 × (1 + VD), VD默认0.20 (20%)
-- 装备的"易伤伤害+X%"已归入A伤桶, 不在此处
-- ============================================================================

--- 易伤公式: 1.2 × (1 + Σa伤%) × Π(1 + x伤i%)
--- a伤: 加法倍率, 多个来源求和后一次性乘
--- x伤: 乘法倍率, 每个来源独立相乘
local function CalcVulnerable(ctx)
    if ctx.target.isVulnerable then
        local base = 1.2
        -- a伤: 加法汇总
        local vulnAdd = ctx.target.vulnAdd or 0
        -- x伤: 独立连乘
        local vulnXMul = 1.0
        local vulnXSources = ctx.target.vulnXSources
        if vulnXSources then
            for _, xi in ipairs(vulnXSources) do
                if xi > 0 then
                    vulnXMul = vulnXMul * (1 + xi)
                end
            end
        end
        return base * (1 + vulnAdd) * vulnXMul
    end
    return 1.0
end

-- ============================================================================
-- 桶5: X伤 (独立乘数, 每个来源独立乘算)
-- Π(1 + Xi) — 最强桶, 不与A伤混合
-- ============================================================================

local function CalcXDamage(ctx)
    local mul = 1.0

    -- 技能伤害 (独立乘区, 非技能不生效)
    if ctx.damageTag == "skill" then
        local skillDmgBonus = GameState.GetSkillDmg()
        if skillDmgBonus > 0 then
            mul = mul * (1 + skillDmgBonus)
        end
    end

    -- 超杀 (P1 WIL 通用效果, 目标低血量时)
    if ctx.overkillBonus > 0 then
        local target = ctx.target
        if target.hp and target.maxHP and target.maxHP > 0 then
            local hpRatio = target.hp / target.maxHP
            local StatDefs = require("state.StatDefs")
            if hpRatio < StatDefs.OVERKILL_HP_THRESHOLD then
                mul = mul * (1 + ctx.overkillBonus)
            end
        end
    end

    -- 技能增强提供的X伤 (增强节点可能给出独立乘数)
    if ctx.xDamageSources then
        for _, xi in ipairs(ctx.xDamageSources) do
            if xi > 0 then
                mul = mul * (1 + xi)
            end
        end
    end

    -- 神秘寒冰甲: 对冻结敌人伤害+15%[x]
    if GameState.iceArmorActive and GameState._hasIceArmorMystical then
        local target = ctx.target
        if target and target.isFrozen then
            mul = mul * 1.15
        end
    end

    -- 雪崩: 冰霜技能伤害+60%[x], 对易伤+25%[x]
    if ctx.element == "ice" and ctx._avalancheEffect then
        mul = mul * (1 + ctx._avalancheEffect.dmgX)
        if ctx.target.isVulnerable and ctx._avalancheEffect.vulnX then
            mul = mul * (1 + ctx._avalancheEffect.vulnX)
        end
    end

    -- 关键被动: 燃爆 — 对燃烧敌人+15%[x]
    if GameState.GetSkillLevel("kp_combustion") > 0 then
        local target = ctx.target
        if target.burnTimer and target.burnTimer > 0 then
            mul = mul * 1.15
        end
    end

    -- 关键被动: 伊苏祝福 — 攻速每超过基础1%, 伤害+0.5%[x]
    if ctx._esuBlessingBonus and ctx._esuBlessingBonus > 0 then
        mul = mul * (1 + ctx._esuBlessingBonus)
    end

    -- 关键被动: 元素归一 — 交替元素+12%[x]
    if ctx._alignElementsBonus then
        mul = mul * (1 + ctx._alignElementsBonus)
    end

    -- 关键被动: 过载 — 有爆裂电花时+25%[x] 并消耗1个
    if (GameState._cracklingEnergyCount or 0) > 0
       and GameState.GetSkillLevel("kp_overcharge") > 0 then
        mul = mul * 1.25
        GameState._cracklingEnergyCount = GameState._cracklingEnergyCount - 1
    end

    -- 至尊陨石: 火焰伤害+20%[x] (8秒)
    if ctx.element == "fire" and (GameState._meteorSupremeTimer or 0) > 0 then
        mul = mul * 1.20
    end

    return mul
end

-- ============================================================================
-- 桶6: 压制伤害 (3%触发概率, 加法额外伤害)
-- 压制额外 = (当前HP + 盾值) × (1 + 压制加成%)
-- 注: 压制伤害也受暴击影响
-- ============================================================================

local OVERPOWER_CHANCE = 0.03

local function CalcOverpower(ctx)
    if not ctx.isOverpower then
        return 0
    end
    local currentHP = GameState.playerHP or 0
    local ShieldManager = require("state.ShieldManager")
    local shieldHP = ShieldManager.GetTotal()
    local overpowerBase = currentHP + shieldHP
    -- 压制伤害加成 (装备词缀, 未来可从 equipSum 获取)
    local overpowerBonus = ctx.overpowerDmgBonus or 0
    return overpowerBase * (1 + overpowerBonus)
end

-- ============================================================================
-- 防御区: 敌人DEF (保留, 非D4桶, 但挂机游戏需要)
-- = 1 - effectiveDef / (effectiveDef + K)
-- ============================================================================

local function CalcDef(ctx)
    local enemyDef = ctx.target.def or 0
    if ctx.target.defReduceRate and ctx.target.defReduceTimer and ctx.target.defReduceTimer > 0 then
        enemyDef = enemyDef * (1 - ctx.target.defReduceRate)
    end
    -- v3.1: K 随怪物等级缩放 (替代旧 scaleMul)
    local monsterLevel = ctx.target.level or GameState.player.level or 1
    local K = DefenseFormula.CalcEnemyDefK(monsterLevel)
    return DefenseFormula.DefMul(enemyDef, K)
end

-- ============================================================================
-- 抗性区: 敌人元素抗性 (保留)
-- ============================================================================

local function CalcResistance(ctx)
    if not ctx.target.resist or not ctx.element then
        return 1.0
    end
    local resistVal = ctx.target.resist[ctx.element] or 0
    -- 元素削弱debuff
    if ctx.target.elemWeakenRate and ctx.target.elemWeakenTimer and ctx.target.elemWeakenTimer > 0 then
        resistVal = resistVal - ctx.target.elemWeakenRate
    end
    -- 玩家全抗降低敌人等效抗性 (INT通用效果)
    local allRes = GameState.GetAllResist()
    if allRes > 0 then
        resistVal = resistVal - allRes * 0.5  -- 全抗50%转化为穿透
    end
    -- v3.1: 世界层级抗性穿透 (T1=0%, T2=5%, T3=10%, T4=15%)
    resistVal = DefenseFormula.CalcEffectiveResist(resistVal, ctx.worldTierId or 1)
    return DefenseFormula.ResistMul(resistVal)
end

-- ============================================================================
-- 主计算
-- ============================================================================

--- 计算六桶管线伤害
--- @param ctx table 由 BuildContext 构建的上下文
--- @return number 最终伤害 (整数, ≥1)
function DamageFormula.Calculate(ctx)
    -- 桶0: 基础伤害 (绝对值)
    local base = CalcBase(ctx)

    -- 桶1: 主属性
    local mainStatMul = CalcMainStat(ctx)

    -- 桶2: A伤
    local additiveMul = CalcAdditive(ctx)

    -- 桶3: 暴击
    local critMul = CalcCrit(ctx)

    -- 桶4: 易伤
    local vulnerableMul = CalcVulnerable(ctx)

    -- 桶5: X伤 (独立连乘)
    local xDamageMul = CalcXDamage(ctx)

    -- 管线乘算
    local dmg = base * mainStatMul * additiveMul * critMul * vulnerableMul * xDamageMul

    -- 防御区 & 抗性区 (游戏特有, 非D4桶)
    dmg = dmg * CalcDef(ctx) * CalcResistance(ctx)

    -- 桶6: 压制 (加法额外伤害)
    local opDmg = CalcOverpower(ctx)
    if opDmg > 0 then
        -- 压制伤害也受暴击影响
        if ctx.isCrit then
            opDmg = opDmg * ctx.critDmg
        end
        dmg = dmg + opDmg
    end

    return math.max(1, math.floor(dmg))
end

-- ============================================================================
-- 上下文构建器
-- ============================================================================

--- 构建伤害计算上下文
--- @param opts table 选项:
---   target         : table   目标敌人 (必须)
---   bs             : table   BattleSystem 引用 (必须)
---   multiplier     : number  技能倍率 (默认 1.0)
---   baseDmg        : number  基础伤害覆盖 (可选)
---   damageTag      : string  "normal" | "skill" (默认 "normal")
---   element        : string  "weapon" → 自动取武器元素; 或具体元素 (默认 "weapon")
---   extraCritRate  : number  额外暴击率 (默认 0)
---   forceCrit      : bool    true=必暴 false=不暴 nil=正常roll (可选)
---   forceOverpower : bool    true=必触发压制 (可选)
---   extraBonuses   : table   { [key]=value } A伤桶技能专属增伤 (可选)
---   xDamageSources : table   { value1, value2, ... } X伤桶独立来源 (可选)
--- @return table ctx
function DamageFormula.BuildContext(opts)
    local BuffManager = require("battle.BuffManager")
    local target = opts.target
    local bs = opts.bs

    local ctx = {}
    ctx.target = target
    ctx.bs = bs
    ctx.multiplier = opts.multiplier or 1.0
    ctx.baseDmg = opts.baseDmg
    ctx.damageTag = opts.damageTag or "normal"

    -- v3.1: 世界层级ID (用于抗性穿透计算)
    ctx.worldTierId = getWorldTierId()

    -- 解析元素: "weapon" → 武器元素; 具体字符串 → 直接使用
    if not opts.element or opts.element == "weapon" then
        ctx.element = GameState.GetWeaponElement()
    else
        ctx.element = opts.element
    end

    -- ATK
    ctx.totalAtk = GameState.GetTotalAtk()

    -- ==================== 桶1: 主属性 ====================
    -- 术士主属性 = INT
    local allocPts = GameState.player.allocatedPoints or {}
    ctx.mainStatPoints = allocPts.INT or 0

    -- ==================== 桶3: 暴击 ====================
    local critRate = GameState.GetCritRate() + (opts.extraCritRate or 0)
    -- 暗影猎手6件: 爆发后暴击率加成
    local shadowCritBonus = BuffManager.GetShadowHunterCritBonus()
    critRate = critRate + shadowCritBonus
    -- 精英致盲光环: 降低玩家暴击率
    local EliteSystem = require("battle.EliteSystem")
    if ctx.bs then
        critRate = critRate - EliteSystem.GetBlindReduction(ctx.bs)
    end
    critRate = math.min(1.0, math.max(0, critRate))

    if opts.forceCrit ~= nil then
        ctx.isCrit = opts.forceCrit
    else
        ctx.isCrit = math.random() < critRate
    end
    ctx.critDmg = GameState.GetCritDmg()

    -- ==================== 桶6: 压制 ====================
    if opts.forceOverpower then
        ctx.isOverpower = true
    else
        ctx.isOverpower = math.random() < OVERPOWER_CHANCE
    end
    ctx.overpowerDmgBonus = GameState._equipSum("overpowerDmg") or 0

    -- ==================== 桶2: A伤相关 ====================

    -- 元素增伤 (按攻击元素计算)
    ctx.elemDmgBonus = getElemDmgBonus(ctx.element)

    -- 攻击药水
    ctx.atkPotionBonus = GameState.GetAtkPotionMul() - 1.0

    -- 套装被动增伤 (stats 字段)
    local setStats = GameState.GetSetBonusStats()
    if ctx.damageTag == "normal" then
        ctx.setPassiveBonus = (setStats.atkDmg or 0) + (setStats.normalAtkDmg or 0)
    else
        ctx.setPassiveBonus = 0
    end

    -- 装备易伤加成 → 归入A伤桶
    ctx.vulnerableEquipBonus = GameState._equipSum("vulnerableDmg") or 0

    -- 套装buff增伤
    ctx.swiftHunterBonus = BuffManager.GetSwiftHunterBonus(target)
    ctx.dragonFuryAtkBonus = BuffManager.GetDragonFuryAtkBonus()
    ctx.dragonFurySkillBonus = BuffManager.GetDragonFurySkillBonus()
    ctx.dragonMightBonus = BuffManager.GetDragonMightBonus()

    if ctx.damageTag == "skill" then
        ctx.runeNextSkillBonus = BuffManager.ConsumeRuneNextSkillBonus()
        ctx.runeResonanceSkillDmg = BuffManager.GetRuneResonanceSkillDmgBonus()
    else
        ctx.runeNextSkillBonus = 0
        ctx.runeResonanceSkillDmg = 0
    end

    -- 词缀: 精英猎手
    ctx.affixEliteHunterBonus = 0
    if target.isBoss or target.isElite then
        local ehVal = AffixHelper.GetAffixValue("elite_hunter")
        if ehVal > 0 then
            ctx.affixEliteHunterBonus = ehVal
        end
    end

    -- 技能专属A伤加成
    ctx.extraBonuses = opts.extraBonuses or {}

    -- ==================== 桶5: X伤来源 ====================
    ctx.xDamageSources = opts.xDamageSources or {}
    ctx.overkillBonus = GameState.GetOverkillDmg()

    -- 雪崩: 冰霜技能X伤加成 (预查询, 避免重复GetSkillLevel)
    if ctx.element == "ice" and GameState.GetSkillLevel("kp_avalanche") > 0 then
        local SkillTreeCfg = require("SkillTreeConfig")
        local kpCfg = SkillTreeCfg.SKILL_MAP["kp_avalanche"]
        if kpCfg then
            ctx._avalancheEffect = kpCfg.effect()
        end
    end

    -- 关键被动: 伊苏祝福 — 攻速每超过基础1%, 伤害+0.5%[x]
    ctx._esuBlessingBonus = 0
    if GameState.GetSkillLevel("kp_esu_blessing") > 0 then
        local effectiveSpd = GameState.GetAtkSpeed()
        local baseSpd = GameState.player.atkSpeed or 1.0
        if effectiveSpd > baseSpd then
            local excessPct = (effectiveSpd / baseSpd - 1) * 100
            ctx._esuBlessingBonus = excessPct * 0.005
        end
    end

    -- 关键被动: 元素归一 — 交替不同元素+12%[x]
    if GameState.GetSkillLevel("kp_align_elements") > 0
       and ctx.damageTag == "skill" and ctx.element then
        local lastElem = GameState._lastSkillElement
        if lastElem and lastElem ~= ctx.element then
            ctx._alignElementsBonus = 0.12
        end
    end

    return ctx
end

-- ============================================================================
-- 导出桶函数 (便于外部自定义或调试)
-- ============================================================================

DamageFormula.Buckets = {
    Base       = CalcBase,
    MainStat   = CalcMainStat,
    Additive   = CalcAdditive,
    Crit       = CalcCrit,
    Vulnerable = CalcVulnerable,
    XDamage    = CalcXDamage,
    Overpower  = CalcOverpower,
    Def        = CalcDef,
    Resistance = CalcResistance,
}

-- 向后兼容: 旧代码可能引用 DamageFormula.Zones
DamageFormula.Zones = DamageFormula.Buckets

return DamageFormula
