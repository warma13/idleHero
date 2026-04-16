-- ============================================================================
-- battle/CombatUtils.lua - 音效、常量、击退、震屏、视觉弹道
-- ============================================================================

local CombatUtils = {}

-- ============================================================================
-- 常量
-- ============================================================================

CombatUtils.KNOCKBACK_SPEED  = 0    -- 全局击退基础速度 (默认关闭，仅特定技能使用)
CombatUtils.KNOCKBACK_CRIT   = 1.6
CombatUtils.KNOCKBACK_SKILL  = 1.3
CombatUtils.KNOCKBACK_DECAY  = 8.0
CombatUtils.SHAKE_NORMAL     = 3.0
CombatUtils.SHAKE_CRIT       = 6.0
CombatUtils.SHAKE_SKILL      = 5.0
CombatUtils.SHAKE_STORM      = 8.0
CombatUtils.SHAKE_BLAST      = 6.0
CombatUtils.SHAKE_DECAY      = 12.0

-- ============================================================================
-- 音效系统
-- ============================================================================

local audioScene_     = nil
local sfxCache_       = {}

local SFX = {
    attack       = "audio/sfx/sfx_attack.ogg",
    crit         = "audio/sfx/sfx_crit.ogg",
    elemBlast    = "audio/sfx/sfx_detonate.ogg",
    stormWarn    = "audio/sfx/sfx_meteor_warn.ogg",
    stormImpact  = "audio/sfx/sfx_meteor_impact.ogg",
    frostWarn    = "audio/sfx/sfx_frost_warn.ogg",
    frostImpact  = "audio/sfx/sfx_frost_impact.ogg",
    enemyDie     = "audio/sfx/sfx_enemy_die.ogg",
    fireBolt     = "audio/sfx/sfx_fire_bolt.ogg",
    frostBolt    = "audio/sfx/sfx_frost_bolt.ogg",
    spark        = "audio/sfx/sfx_spark.ogg",
    arcaneStrike = "audio/sfx/sfx_arcane_strike.ogg",
    -- 新增技能专属音效
    incinerate     = "audio/sfx/sfx_incinerate.ogg",
    firewall       = "audio/sfx/sfx_firewall.ogg",
    hydra          = "audio/sfx/sfx_hydra.ogg",
    fireballCast   = "audio/sfx/sfx_fireball_cast.ogg",
    frostNova      = "audio/sfx/sfx_frost_nova.ogg",
    iceArmor       = "audio/sfx/sfx_ice_armor.ogg",
    frozenOrb      = "audio/sfx/sfx_frozen_orb.ogg",
    chargedBolts   = "audio/sfx/sfx_charged_bolts.ogg",
    chainLightning = "audio/sfx/sfx_chain_lightning.ogg",
    lightningSpear = "audio/sfx/sfx_lightning_spear.ogg",
    teleport       = "audio/sfx/sfx_teleport.ogg",
    thunderStorm   = "audio/sfx/sfx_thunder_storm.ogg",
    energyPulse    = "audio/sfx/sfx_energy_pulse.ogg",
}

function CombatUtils.InitAudio()
    audioScene_ = Scene()
    for key, path in pairs(SFX) do
        sfxCache_[key] = cache:GetResource("Sound", path)
    end
end

function CombatUtils.PlaySfx(key, gain)
    local sound = sfxCache_[key]
    if not sound or not audioScene_ then return end
    local node = audioScene_:CreateChild("Sfx")
    local src  = node:CreateComponent("SoundSource")
    src.gain = gain or 0.5
    src:Play(sound)
    src.autoRemoveMode = REMOVE_NODE
end

function CombatUtils.IsAudioReady()
    return audioScene_ ~= nil
end

-- ============================================================================
-- 击退
-- ============================================================================

function CombatUtils.ApplyKnockback(enemy, fromX, fromY, multiplier)
    local dx = enemy.x - fromX
    local dy = enemy.y - fromY
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dx, dy, dist = 1, 0, 1 end
    local nx, ny = dx / dist, dy / dist
    local w = enemy.weight or 1.0
    local spd = CombatUtils.KNOCKBACK_SPEED * multiplier / w
    enemy.knockbackVx = nx * spd
    enemy.knockbackVy = ny * spd
end

-- ============================================================================
-- 震屏
-- ============================================================================

--- 触发震屏 (取最大值)
--- @param bs table BattleSystem 引用
--- @param intensity number 震屏强度
function CombatUtils.TriggerShake(bs, intensity)
    bs.screenShake = math.max(bs.screenShake, intensity)
end

-- ============================================================================
-- 视觉弹道 (紫焰弹，纯视觉，伤害已即时结算)
-- ============================================================================

local TRAIL_MAX = 6

function CombatUtils.SpawnProjectile(bs, fromX, fromY, toX, toY, isCrit)
    table.insert(bs.projectiles, {
        x = fromX, y = fromY,
        targetX = toX, targetY = toY,
        speed = 700,
        isCrit = isCrit,
        life = 1.0,
        trail = {},
        trailTimer = 0,
    })
end

function CombatUtils.UpdateProjectiles(dt, bs)
    for i = #bs.projectiles, 1, -1 do
        local proj = bs.projectiles[i]
        local dx = proj.targetX - proj.x
        local dy = proj.targetY - proj.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 8 or proj.life <= 0 then
            table.remove(bs.projectiles, i)
        else
            proj.trailTimer = proj.trailTimer + dt
            if proj.trailTimer >= 0.02 then
                proj.trailTimer = 0
                table.insert(proj.trail, {
                    x = proj.x, y = proj.y,
                    alpha = 1.0,
                    scale = 0.6 + math.random() * 0.4,
                    offsetX = (math.random() - 0.5) * 4,
                    offsetY = (math.random() - 0.5) * 4,
                })
                if #proj.trail > TRAIL_MAX then
                    table.remove(proj.trail, 1)
                end
            end
            for _, t in ipairs(proj.trail) do
                t.alpha = t.alpha - dt * 4
                t.scale = t.scale * (1 - dt * 3)
            end
            local nx, ny = dx / dist, dy / dist
            proj.x = proj.x + nx * proj.speed * dt
            proj.y = proj.y + ny * proj.speed * dt
            proj.life = proj.life - dt
        end
    end
end

-- ============================================================================
-- 共享增伤管线 (v2: 技能与普攻共享套装/药水/元素抗性等乘算层)
-- ============================================================================

--- 将技能基础伤害经过套装/药水/条件增伤等共享乘算层
--- @param dmg number 技能经过ATK*scale*crit*elemDmg*mark*DEF后的基础伤害
--- @param target table 目标敌人
--- @param bs table BattleSystem 引用
--- @return number 增伤后的伤害
function CombatUtils.ApplySharedDmgBonus(dmg, target, bs)
    local GameState = require("GameState")
    local Config    = require("Config")

    -- 攻击药水
    dmg = math.floor(dmg * GameState.GetAtkPotionMul())

    -- 元素抗性
    local weaponElem = GameState.GetWeaponElement()
    if target.resist and weaponElem then
        local resistVal = target.resist[weaponElem] or 0
        if target.elemWeakenRate and target.elemWeakenTimer and target.elemWeakenTimer > 0 then
            resistVal = resistVal - target.elemWeakenRate
        end
        if resistVal ~= 0 then
            dmg = math.max(1, math.floor(dmg * (1 - resistVal)))
        end
    end

    return math.max(1, dmg)
end

function CombatUtils.RecordBossDmg(dmg)
    if dmg <= 0 then return end
    -- 统一记录到 DamageTracker (独立于 Boss 状态)
    local okDT, DamageTracker = pcall(require, "DamageTracker")
    if okDT and DamageTracker then
        DamageTracker.Record(dmg)
    end
    -- 保留旧调用兼容
    local ok, WorldBoss = pcall(require, "WorldBoss")
    if ok and WorldBoss and WorldBoss.RecordDamage then
        WorldBoss.RecordDamage(dmg)
    end
end

return CombatUtils
