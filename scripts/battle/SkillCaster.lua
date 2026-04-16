-- ============================================================================
-- battle/SkillCaster.lua - 技能释放入口 (v4.0 模块化拆分)
-- 3元素: 火焰(Fire) / 冰霜(Ice) / 闪电(Lightning)
-- 具体施放函数按元素拆分到 battle/skills/ 子模块
-- ============================================================================

local Config          = require("Config")
local GameState       = require("GameState")
local SkillTreeConfig = require("SkillTreeConfig")
local Particles       = require("battle.Particles")
local CombatUtils     = require("battle.CombatUtils")
local DamageFormula   = require("battle.DamageFormula")

local SkillCaster = {}

-- ============================================================================
-- 技能释放主入口
-- ============================================================================

local function DispatchCast(bs, skillCfg, lv, p)
    local id = skillCfg.id
    local fn = SkillCaster["_Cast_" .. id]
    if fn then
        fn(bs, skillCfg, lv, p)
    else
        -- fallback: 通用全屏AoE
        SkillCaster._CastGenericAoe(bs, skillCfg, lv, p)
    end
end

function SkillCaster.CastSkill(bs, skillCfg, lv)
    -- 法力消耗检查: 有 manaCost 的技能必须有足够法力
    local manaCost = skillCfg.manaCost or 0
    if manaCost > 0 then
        -- 雪崩: 冰霜技能法力消耗 -30%
        if skillCfg.element == "ice" and GameState.GetSkillLevel("kp_avalanche") > 0 then
            manaCost = math.floor(manaCost * 0.70)
        end
        if not GameState.SpendMana(manaCost) then
            return false  -- 法力不足, 跳过施放
        end
    end

    -- 日常任务: 使用技能
    local ok, DR = pcall(require, "DailyRewards")
    if ok and DR and DR.TrackProgress then DR.TrackProgress("skills", 1) end

    local p = bs.playerBattle
    DispatchCast(bs, skillCfg, lv, p)

    -- 元素归一: 记录本次技能元素 (施放后记录, 供下次 BuildContext 比较)
    if skillCfg.element then
        GameState._lastSkillElement = skillCfg.element
    end

    return true
end

--- 通用全屏AoE (fallback)
function SkillCaster._CastGenericAoe(bs, skillCfg, lv, p)
    local H = require("battle.skills.Helpers")
    local element = skillCfg.element or "fire"
    local dmgScale = type(skillCfg.effect) == "function" and skillCfg.effect(lv) / 100 or 1.0

    for _, e in ipairs(bs.enemies) do
        if not e.dead then
            H.HitEnemySkill(bs, e, dmgScale, element, {}, bs.areaW * 0.5, e.y, CombatUtils.KNOCKBACK_SKILL)
        end
    end

    CombatUtils.TriggerShake(bs, CombatUtils.SHAKE_STORM)
    table.insert(bs.skillEffects, {
        type = "generic_aoe",
        life = 0.8, maxLife = 0.8,
        areaW = bs.areaW, areaH = bs.areaH,
        element = element,
    })
end

-- ============================================================================
-- 注册各元素技能施放函数
-- ============================================================================
require("battle.skills.FireSkills").Register(SkillCaster)
require("battle.skills.IceSkills").Register(SkillCaster)
require("battle.skills.LightningSkills").Register(SkillCaster)

-- ============================================================================
-- 向后兼容: 旧技能ID映射到新函数
-- ============================================================================
SkillCaster._Cast_frost_rain     = SkillCaster._Cast_frozen_orb
SkillCaster._Cast_ice_barrage    = SkillCaster._Cast_ice_shards
SkillCaster._Cast_absolute_zero  = SkillCaster._Cast_deep_freeze
SkillCaster._Cast_fire_bolt_old  = SkillCaster._Cast_fire_bolt

return SkillCaster
