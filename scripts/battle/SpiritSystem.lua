-- ============================================================================
-- battle/SpiritSystem.lua - 元素精灵 AI (v4.0 独立行为分支)
-- ============================================================================

local Config            = require("Config")
local GameState         = require("GameState")
local Particles         = require("battle.Particles")
local CombatUtils       = require("battle.CombatUtils")
local DamageFormula     = require("battle.DamageFormula")

local SpiritSystem = {}

-- ============================================================================
-- 内部工具: 查找最近存活敌人
-- ============================================================================

---@param bs table
---@param fx number 查找起点x
---@param fy number 查找起点y
---@param maxRange number 最大距离 (0=无限)
---@param excludeSet table|nil 已命中的敌人集合(用于穿透排除)
---@return table|nil enemy, number dist
local function FindNearestEnemy(bs, fx, fy, maxRange, excludeSet)
    local bestE, bestD = nil, math.huge
    for _, e in ipairs(bs.enemies) do
        if not e.dead and (not excludeSet or not excludeSet[e]) then
            local dx, dy = e.x - fx, e.y - fy
            local dist = math.sqrt(dx * dx + dy * dy)
            if (maxRange <= 0 or dist <= maxRange) and dist < bestD then
                bestE = e
                bestD = dist
            end
        end
    end
    return bestE, bestD
end

-- ============================================================================
-- 内部工具: 对目标造成伤害 (共用管线)
-- ============================================================================

---@param sp table 精灵数据
---@param target table 敌人
---@param bs table BattleSystem
---@param showProjectile boolean 是否生成视觉弹道
local function DealSpiritDamage(sp, target, bs, showProjectile)
    local isLightningSpear = sp.source == "lightning_spear"
    local lsEnhanced = isLightningSpear and GameState.GetSkillLevel("lightning_spear_enhanced") > 0
    local forceCritVal = lsEnhanced and nil or false

    local ctx = DamageFormula.BuildContext({
        target     = target,
        bs         = bs,
        multiplier = sp.dmgScale,
        damageTag  = "skill",
        element    = sp.element,
        forceCrit  = forceCritVal,
    })
    local finalDmg = DamageFormula.Calculate(ctx)
    local isCrit = ctx.isCrit

    require("battle.EnemySystem").ApplyDamage(target, finalDmg, bs)
    GameState.LifeStealHeal(finalDmg, Config.LIFESTEAL.efficiency.summon)
    Particles.SpawnDmgText(bs.particles, target.x, target.y - (target.radius or 16) - 5,
        finalDmg, isCrit, false, { 80, 180, 255 })

    if showProjectile then
        CombatUtils.SpawnProjectile(bs, sp.x, sp.y, target.x, target.y, isCrit)
    end

    -- lightning_spear enhanced: 暴击叠加+5%暴击率(最多25%)
    if lsEnhanced and isCrit then
        GameState._lsEnhancedCritStacks = math.min(
            (GameState._lsEnhancedCritStacks or 0) + 0.05, 0.25)
    end

    -- lightning_spear destructive: 暴击生成爆裂电花
    if isLightningSpear and isCrit
       and GameState.GetSkillLevel("lightning_spear_destructive") > 0 then
        GameState._cracklingEnergyCount = (GameState._cracklingEnergyCount or 0) + 1
    end
end

-- ============================================================================
-- 闪电矛 AI: 高速追踪 → 命中穿透 → 寻找下一目标
-- ============================================================================

local SPEAR_SPEED       = 350   -- 飞行速度 px/s
local SPEAR_HIT_RADIUS  = 18    -- 命中判定半径
local SPEAR_RETARGET_CD = 0.15  -- 穿透后重新锁定的冷却

local function UpdateLightningSpear(sp, dt, bs)
    -- 初始化追踪状态
    if not sp._initialized then
        sp._initialized = true
        sp._target = nil
        sp._hitSet = {}       -- 已穿透过的敌人(每次锁定周期内不重复)
        sp._retargetCD = 0
        sp._moveAngle = sp.orbitAngle or 0  -- 初始飞行朝向
        sp._hitCount = 0
    end

    -- 重新锁定冷却
    sp._retargetCD = math.max(0, sp._retargetCD - dt)

    -- 寻找/更新目标
    if (not sp._target or sp._target.dead) and sp._retargetCD <= 0 then
        -- 穿透过5个目标后清空已命中集合，允许循环攻击
        if sp._hitCount >= 5 then
            sp._hitSet = {}
            sp._hitCount = 0
        end
        sp._target = FindNearestEnemy(bs, sp.x, sp.y, sp.atkRange, sp._hitSet)
    end

    if sp._target and not sp._target.dead then
        -- 向目标飞行
        local dx = sp._target.x - sp.x
        local dy = sp._target.y - sp.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > 1 then
            sp._moveAngle = math.atan2(dy, dx)
            local step = SPEAR_SPEED * dt
            if step >= dist then step = dist end
            sp.x = sp.x + (dx / dist) * step
            sp.y = sp.y + (dy / dist) * step
        end

        -- 命中检测
        local hitDx = sp._target.x - sp.x
        local hitDy = sp._target.y - sp.y
        local hitDist = math.sqrt(hitDx * hitDx + hitDy * hitDy)
        if hitDist <= SPEAR_HIT_RADIUS then
            -- 造成伤害
            DealSpiritDamage(sp, sp._target, bs, false)
            CombatUtils.PlaySfx("lightningSpear", 0.35)
            -- 标记已穿透
            sp._hitSet[sp._target] = true
            sp._hitCount = sp._hitCount + 1
            sp._target = nil
            sp._retargetCD = SPEAR_RETARGET_CD
        end
    else
        -- 没有目标时缓慢回到玩家附近
        local p = bs.playerBattle
        local dx = p.x - sp.x
        local dy = (p.y - 20) - sp.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 30 then
            local returnSpeed = SPEAR_SPEED * 0.4
            sp._moveAngle = math.atan2(dy, dx)
            sp.x = sp.x + (dx / dist) * returnSpeed * dt
            sp.y = sp.y + (dy / dist) * returnSpeed * dt
        end
    end

    -- 将 moveAngle 同步到 orbitAngle 供渲染层使用
    sp.orbitAngle = sp._moveAngle
end

-- ============================================================================
-- 九头蛇 AI: 独立移动寻敌 → 到达射程后发射火球弹体
-- ============================================================================

local HYDRA_MOVE_SPEED  = 80    -- 移动速度 px/s
local HYDRA_STOP_RANGE  = 100   -- 停下来射击的距离
local HYDRA_WANDER_RAD  = 120   -- 无目标时在玩家周围游荡半径
local HYDRA_FB_SPEED    = 300   -- 火球飞行速度

local function UpdateHydra(sp, dt, bs)
    -- 初始化状态
    if not sp._initialized then
        sp._initialized = true
        sp._target = nil
        sp._wanderAngle = sp.orbitAngle or 0
        sp._faceDirX = 1
    end

    -- 寻找最近敌人
    local enemy = FindNearestEnemy(bs, sp.x, sp.y, sp.atkRange, nil)
    sp._target = enemy

    if enemy then
        local dx = enemy.x - sp.x
        local dy = enemy.y - sp.y
        local dist = math.sqrt(dx * dx + dy * dy)

        -- 更新朝向
        sp._faceDirX = dx >= 0 and 1 or -1

        -- 如果距离 > 停止射程，则向敌人移动
        if dist > HYDRA_STOP_RANGE then
            local step = HYDRA_MOVE_SPEED * dt
            sp.x = sp.x + (dx / dist) * step
            sp.y = sp.y + (dy / dist) * step
        end

        -- 攻击逻辑: 在射程内时发射火球弹体
        sp.atkCD = sp.atkCD - dt
        if sp.atkCD <= 0 and dist <= sp.atkRange then
            sp.atkCD = sp.atkInterval

            -- 造成伤害(即时结算) + 生成火球视觉弹体
            DealSpiritDamage(sp, enemy, bs, false)
            CombatUtils.PlaySfx("fireBolt", 0.3)

            -- 生成九头蛇专属火球弹体 (有独立图片, 标记 source)
            table.insert(bs.projectiles, {
                x = sp.x, y = sp.y,
                targetX = enemy.x, targetY = enemy.y,
                speed = HYDRA_FB_SPEED,
                isCrit = false,
                life = 1.5,
                trail = {},
                trailTimer = 0,
                source = "hydra_fireball",
            })
        end
    else
        -- 无目标: 在玩家附近游荡
        local p = bs.playerBattle
        sp._wanderAngle = sp._wanderAngle + dt * 0.8
        local wx = p.x + math.cos(sp._wanderAngle) * HYDRA_WANDER_RAD
        local wy = p.y + math.sin(sp._wanderAngle) * HYDRA_WANDER_RAD * 0.5
        local dx = wx - sp.x
        local dy = wy - sp.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 3 then
            sp._faceDirX = dx >= 0 and 1 or -1
            local step = math.min(HYDRA_MOVE_SPEED * dt, dist)
            sp.x = sp.x + (dx / dist) * step
            sp.y = sp.y + (dy / dist) * step
        end
    end

    -- 同步朝向给渲染层
    sp.orbitAngle = sp._wanderAngle
end

-- ============================================================================
-- 通用精灵 AI: 绕玩家公转 + 范围攻击 (默认行为)
-- ============================================================================

local function UpdateGenericSpirit(sp, dt, bs)
    local p = bs.playerBattle
    sp.orbitAngle = sp.orbitAngle + dt * 2.5
    local orbitR = 40
    sp.x = p.x + math.cos(sp.orbitAngle) * orbitR
    sp.y = p.y + math.sin(sp.orbitAngle) * orbitR

    sp.atkCD = sp.atkCD - dt
    if sp.atkCD <= 0 then
        sp.atkCD = sp.atkInterval
        local enemy = FindNearestEnemy(bs, sp.x, sp.y, sp.atkRange, nil)
        if enemy then
            DealSpiritDamage(sp, enemy, bs, true)
        end
    end
end

-- ============================================================================
-- 元素精灵 AI 主入口
-- ============================================================================

function SpiritSystem.UpdateElementSpirits(dt, bs)
    for i = #GameState.spirits, 1, -1 do
        local sp = GameState.spirits[i]
        sp.timer = sp.timer - dt
        if sp.timer <= 0 then
            table.remove(GameState.spirits, i)
        else
            if sp.source == "lightning_spear" then
                UpdateLightningSpear(sp, dt, bs)
            elseif sp.source == "hydra" then
                UpdateHydra(sp, dt, bs)
            else
                UpdateGenericSpirit(sp, dt, bs)
            end
        end
    end
end

return SpiritSystem
