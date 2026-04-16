-- ============================================================================
-- battle/CombatCore.lua - 命中处理 + 普攻 (v3.0 D4模型)
-- 普攻走已装备的基础技能 (T1), 无元素反应系统
-- ============================================================================

local Config            = require("Config")
local GameState         = require("GameState")
local SkillTreeConfig   = require("SkillTreeConfig")
local Particles         = require("battle.Particles")
local CombatUtils       = require("battle.CombatUtils")
local DamageFormula     = require("battle.DamageFormula")
local AffixHelper       = require("state.AffixHelper")

local CombatCore = {}

-- ============================================================================
-- 单次命中逻辑 (普攻共用)
-- ============================================================================

--- @param bs table BattleSystem 引用
--- @param target table 目标敌人
--- @param fromX number 攻击来源X
--- @param fromY number 攻击来源Y
--- @param dmgMul number 伤害倍率
--- @param isSplit boolean 是否分裂弹(用于击退减弱)
--- @param extraCritRate? number 额外暴击率加成
local function HitEnemy(bs, target, fromX, fromY, dmgMul, isSplit, extraCritRate)
    if target.dead then return end

    -- 模板 Boss 无敌 (阶段转换中)
    if target._invincible then return end

    -- 模板系统可摧毁物: 委托给 BossSkillTemplates 处理
    if target.isBossDestroyable then
        local ok, BossSkillTemplates = pcall(require, "battle.BossSkillTemplates")
        if ok and BossSkillTemplates.DamageDestroyable then
            local ctx = DamageFormula.BuildContext({
                target       = target,
                bs           = bs,
                multiplier   = dmgMul,
                damageTag    = "normal",
                element      = "weapon",
                extraCritRate = extraCritRate,
            })
            local dmg = DamageFormula.Calculate(ctx)
            local isCrit = ctx.isCrit
            local weaponElem = ctx.element
            -- 弹道
            CombatUtils.SpawnProjectile(bs, fromX, fromY, target.x, target.y, isCrit)
            -- 飘字
            local weaponColor = Config.ELEMENTS.colors[weaponElem] or { 255, 255, 255 }
            Particles.SpawnDmgText(bs.particles, target.x, target.y - (target.radius or 16) - 10, dmg, isCrit, false, weaponColor)
            -- 委托伤害处理
            BossSkillTemplates.DamageDestroyable(bs, target, dmg, { element = weaponElem, isCrit = isCrit })
        end
        return
    end

    -- ==================== 六桶管线计算 ====================
    local ctx = DamageFormula.BuildContext({
        target       = target,
        bs           = bs,
        multiplier   = dmgMul,
        damageTag    = "normal",
        element      = "weapon",
        extraCritRate = extraCritRate,
    })
    local dmg = DamageFormula.Calculate(ctx)
    local isCrit = ctx.isCrit
    local weaponElem = ctx.element

    -- 冰甲减伤
    local EnemySystem = require("battle.EnemySystem")
    dmg = EnemySystem.ApplyDamageReduction(target, dmg)

    -- 词缀: 暴击强化 (暴击时额外造成N%ATK的固定伤害)
    local critSurgeDmg = 0
    if isCrit then
        local csVal = AffixHelper.GetAffixValue("crit_surge")
        if csVal > 0 then
            critSurgeDmg = math.floor(GameState.GetTotalAtk() * csVal)
            dmg = dmg + critSurgeDmg
        end
    end

    local killed = EnemySystem.ApplyDamage(target, dmg, bs)

    -- 充能叠层 (chargeUp): 受伤后积累充能
    EnemySystem.OnEnemyTakeDamageChargeUp(target)

    -- 吸血触发 (普攻)
    GameState.LifeStealHeal(dmg, Config.LIFESTEAL.efficiency.normal)

    -- 弹道
    CombatUtils.SpawnProjectile(bs, fromX, fromY, target.x, target.y, isCrit)

    -- 击退 & 飘字
    local kbMul = isCrit and CombatUtils.KNOCKBACK_CRIT or (isSplit and 0.6 or 1.0)
    CombatUtils.ApplyKnockback(target, fromX, fromY, kbMul)
    local weaponColor = Config.ELEMENTS.colors[weaponElem] or { 255, 255, 255 }
    Particles.SpawnDmgText(bs.particles, target.x, target.y - (target.radius or 16) - 10, dmg, isCrit, false, weaponColor)

    -- ===== 新套装: 普攻命中 hook =====
    local BuffManager = require("battle.BuffManager")
    -- 迅捷猎手2件: 普攻命中回血
    BuffManager.TrySwiftHunterOnHit(bs, target)
    -- 迅捷猎手4件: 同目标叠层
    BuffManager.OnSwiftHunterHit(bs, target)
    -- 裂变之力2件: 普攻命中获取能量
    BuffManager.OnFissionForceHit(bs, target)
    -- 暗影猎手2件: 暴击命中叠暗影
    if isCrit then
        BuffManager.OnShadowHunterCrit(bs, target)
        -- 暗影猎手6件: 爆发后暴击回血
        BuffManager.OnShadowHunterCritHeal()
    end
    -- 龙息之怒4件: 普攻命中计数 (交替循环)
    BuffManager.OnDragonFuryNormalHit(bs, target)
    -- 熔岩征服者2件: 攻击命中点燃
    BuffManager.OnLavaConquerorHit(bs, target)
    -- 熔岩征服者6件: 熔岩领主暴击火焰冲击
    if isCrit then
        BuffManager.OnLavaLordCritHit(bs, target)
    end
    -- 熔岩征服者6件: 熔岩领主溅射
    if not target.dead then
        BuffManager.OnLavaLordSplash(bs, target, dmg)
    end

    -- 词缀: 击杀回复 (击杀敌人回复N%最大生命)
    if killed then
        local khVal = AffixHelper.GetAffixValue("kill_heal")
        if khVal > 0 then
            GameState.HealPlayer(math.floor(GameState.GetMaxHP() * khVal))
        end
    end
end

-- ============================================================================
-- 玩家普攻 — 使用已装备的基础技能 (T1)
-- 如果未装备基础技能, 退回默认普攻
-- ============================================================================

--- 查找已装备的核心技能 (coreSkill=true, 与基础技能共享攻速槽位)
--- @return table|nil skillCfg, number level
local function FindEquippedCoreSkill()
    local equippedList = GameState.GetEquippedSkillList()
    for _, entry in ipairs(equippedList) do
        if entry.cfg.coreSkill and entry.level > 0 then
            return entry.cfg, entry.level
        end
    end
    return nil, 0
end

--- @param bs table BattleSystem 引用
--- @param targetIdx number 目标索引
function CombatCore.PlayerAttack(bs, targetIdx)
    local target = bs.enemies[targetIdx]
    if not target or target.dead then return end

    -- 引导中: 跳过所有攻击 (引导占用攻击槽位)
    local ChannelSystem = require("battle.ChannelSystem")
    if ChannelSystem.IsChanneling() then return end

    local p = bs.playerBattle
    local SkillCaster = require("battle.SkillCaster")

    -- 基础/核心技能槽 (基础技能无法力消耗, 核心技能消耗法力)
    local basicSkillId = GameState.GetEquippedBasicSkill()
    if basicSkillId then
        local cfg = SkillTreeConfig.SKILL_MAP[basicSkillId]
        local lv = GameState.GetSkillLevel(basicSkillId)
        if cfg and lv > 0 then
            local manaCost = cfg.manaCost or 0
            if manaCost > 0 then
                -- 核心技能 (tier 2): 需要法力, 法力不足时退回普攻
                if GameState.HasMana(manaCost) then
                    local success = SkillCaster.CastSkill(bs, cfg, lv)
                    if success ~= false then
                        local BuffManager = require("battle.BuffManager")
                        BuffManager.OnRuneWeaverSkillCast(bs)
                        BuffManager.OnDragonFurySkillHit(bs)
                        BuffManager.OnRuneResonanceSkillHit()
                        return
                    end
                end
                -- 法力不足: 继续到下面的普攻
            else
                -- 基础技能 (tier 1): 无法力消耗
                SkillCaster.CastSkill(bs, cfg, lv)

                -- 词缀: 连击 (概率连续攻击2次)
                if not target.dead then
                    local comboVal = AffixHelper.GetAffixValue("combo_strike")
                    if comboVal > 0 and math.random() < comboVal then
                        SkillCaster.CastSkill(bs, cfg, lv)
                    end
                end
                return
            end
        end
    end

    -- 退回默认普攻 (未装备基础技能时)
    local baseDmgMul = 1.0
    HitEnemy(bs, target, p.x, p.y, baseDmgMul, false)
    CombatUtils.PlaySfx(math.random() < GameState.GetCritRate() and "crit" or "attack", 0.4)
    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_NORMAL)

    -- 词缀: 连击 (概率连续攻击2次)
    if not target.dead then
        local comboVal = AffixHelper.GetAffixValue("combo_strike")
        if comboVal > 0 and math.random() < comboVal then
            HitEnemy(bs, target, p.x, p.y, baseDmgMul, false)
        end
    end
end

return CombatCore
