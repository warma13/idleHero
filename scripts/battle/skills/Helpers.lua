-- ============================================================================
-- battle/skills/Helpers.lua - 技能施放公共工具函数
-- ============================================================================

local Config      = require("Config")
local GameState   = require("GameState")
local Particles   = require("battle.Particles")
local CombatUtils = require("battle.CombatUtils")
local DamageFormula = require("battle.DamageFormula")

local H = {}

--- 检查增强节点是否已学
function H.HasEnhance(enhId)
    return GameState.GetSkillLevel(enhId) > 0
end

--- 找最密集的敌人聚集点
function H.FindBestAoeCenter(enemies, radius, fx, fy)
    local bestX, bestY, bestCount = fx, fy, 0
    for _, e in ipairs(enemies) do
        if not e.dead then
            local cnt = 0
            for _, e2 in ipairs(enemies) do
                if not e2.dead then
                    local dx, dy = e2.x - e.x, e2.y - e.y
                    if math.sqrt(dx * dx + dy * dy) <= radius then cnt = cnt + 1 end
                end
            end
            if cnt > bestCount then bestX, bestY, bestCount = e.x, e.y, cnt end
        end
    end
    return bestX, bestY
end

--- 找范围内最近敌人
function H.FindNearestEnemy(enemies, px, py, range)
    local best, bestDist = nil, math.huge
    for _, e in ipairs(enemies) do
        if not e.dead then
            local dx, dy = e.x - px, e.y - py
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= range and dist < bestDist then
                best, bestDist = e, dist
            end
        end
    end
    return best
end

--- 收集存活敌人
function H.GetAliveEnemies(enemies)
    local alive = {}
    for _, e in ipairs(enemies) do
        if not e.dead then alive[#alive + 1] = e end
    end
    return alive
end

--- 收集指定范围内的存活敌人
function H.GetAliveEnemiesInRange(enemies, px, py, range)
    local alive = {}
    local r2 = range * range
    for _, e in ipairs(enemies) do
        if not e.dead then
            local dx, dy = e.x - px, e.y - py
            if dx * dx + dy * dy <= r2 then
                alive[#alive + 1] = e
            end
        end
    end
    return alive
end

--- 统一的 "命中单个敌人" 管线 (技能用)
--- @return number finalDmg
function H.HitEnemySkill(bs, e, multiplier, element, extraBonuses, px, py, kbMul, xSources)
    local ctx = DamageFormula.BuildContext({
        target = e, bs = bs,
        multiplier = multiplier,
        damageTag = "skill", element = element,
        extraBonuses = extraBonuses,
        xDamageSources = xSources,
    })
    local dmg = DamageFormula.Calculate(ctx)
    local isCrit = ctx.isCrit

    local EnemySystem = require("battle.EnemySystem")
    dmg = EnemySystem.ApplyDamageReduction(e, dmg)
    EnemySystem.ApplyDamage(e, dmg, bs)
    GameState.LifeStealHeal(dmg, Config.LIFESTEAL.efficiency.skill)

    if kbMul and kbMul > 0 then
        CombatUtils.ApplyKnockback(e, px or bs.areaW * 0.5, py or e.y, kbMul)
    end

    -- 关键被动: 过载 — 技能暴击生成1个爆裂电花
    if isCrit and GameState.GetSkillLevel("kp_overcharge") > 0 then
        GameState._cracklingEnergyCount = (GameState._cracklingEnergyCount or 0) + 1
    end

    local color = Config.ELEMENTS.colors[element] or { 255, 255, 255 }
    Particles.SpawnDmgText(bs.particles, e.x, e.y - (e.radius or 16) - 10, dmg, isCrit, true, color)
    return dmg, isCrit
end

--- 施加冻伤 (chill): 减速
function H.ApplyChill(e, slowPct, duration)
    e.slowTimer = math.max(e.slowTimer or 0, duration)
    e.slowFactor = math.min(e.slowFactor or 1.0, 1.0 - slowPct)
end

--- 施加冻结 (freeze): 近乎完全停止
function H.ApplyFreeze(e, duration)
    if e.isBoss then return end -- Boss 免疫冻结
    e.slowTimer = math.max(e.slowTimer or 0, duration)
    e.slowFactor = 0.05  -- 几乎完全冻结
    e.isFrozen = true
    e.frozenTimer = duration
end

--- 施加冻伤累积 (frostbite): 减速25%, 累积到100%时冻结3秒
function H.ApplyFrostbite(e, pct)
    e.frostbite = (e.frostbite or 0) + pct
    -- 冻伤减速效果 (对Boss也生效)
    H.ApplyChill(e, 0.25, 2.0)
    -- 冻伤达到100%: 冻结3秒并重置
    if e.frostbite >= 100 then
        e.frostbite = 0
        H.ApplyFreeze(e, 3.0) -- Boss免疫冻结但减速仍生效
    end
end

--- 施加燃烧 (burn)
function H.ApplyBurn(e, dmgPct, duration, maxStacks)
    e.burnTimer = math.max(e.burnTimer or 0, duration)
    e.burnDmgPct = math.max(e.burnDmgPct or 0, dmgPct)
    if maxStacks and maxStacks > 1 then
        e.burnStacks = math.min((e.burnStacks or 0) + 1, maxStacks)
    end
end

--- 施加易伤 (vulnerable)
--- @param e table 敌人
--- @param duration number 持续时间
--- @param opts table|nil { addPct=number, xPct=number }
function H.ApplyVulnerable(e, duration, opts)
    e.isVulnerable = true
    e.vulnerableTimer = math.max(e.vulnerableTimer or 0, duration)
    if opts then
        if opts.addPct then
            e.vulnAdd = (e.vulnAdd or 0) + opts.addPct
        end
        if opts.xPct then
            if not e.vulnXSources then e.vulnXSources = {} end
            e.vulnXSources[#e.vulnXSources + 1] = opts.xPct
        end
    end
end

--- 施加眩晕 (stun)
function H.ApplyStun(e, duration)
    e.stunTimer = math.max(e.stunTimer or 0, duration)
end

return H
