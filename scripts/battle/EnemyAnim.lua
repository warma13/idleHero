-- ============================================================================
-- EnemyAnim.lua - 怪物代码动画系统
-- 职责: 为静态贴图怪物提供 7 种代码驱动动画
-- 设计: 零侵入(仅添加 e.anim 子表), 零内存分配(复用模块级结果表)
-- ============================================================================

local EnemyAnim = {}

-- ======================== 调节常量 ========================
local PI2            = 6.2831853            -- 2π
local BREATHE_FREQ   = 1.2                 -- Hz 呼吸频率
local BREATHE_AMP    = 2.5                 -- px 普通怪浮动幅度
local BREATHE_AMP_BOSS = 1.8              -- px Boss浮动幅度(更沉稳)
local FLASH_DURATION = 0.12                -- s  受击闪白持续
local RECOIL_DURATION = 0.18               -- s  受击后仰持续
local RECOIL_DIST    = 5.0                 -- px 后仰最大位移
local WINDUP_DURATION = 0.30               -- s  攻击前摇持续
local SPAWN_DURATION = 0.25                -- s  出生弹跳持续
local DEATH_DURATION = 0.35                -- s  死亡缩小淡出持续
local BOSS_PULSE_FREQ = 0.8               -- Hz Boss脉冲频率
local BOSS_PULSE_AMP = 0.04               -- ±缩放量

-- 模块级复用结果表(零分配)
local _result = { offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1, alpha = 1, flashWhite = 0 }

-- ======================== 公开 API ========================

--- 初始化怪物动画状态 (生成时调用一次)
---@param e table 怪物实体
function EnemyAnim.InitAnim(e)
    e.anim = {
        breathePhase = math.random() * PI2,    -- 随机初相位,避免全体同步
        flashTimer   = 0,
        recoilTimer  = 0,
        recoilDirX   = 0,
        recoilDirY   = 0,
        windupTimer  = 0,
        spawnTimer   = SPAWN_DURATION,          -- 出生弹跳
        deathTimer   = 0,
        pulsePhase   = math.random() * PI2,     -- Boss脉冲初相位
    }
    e._dyingAnim = false
end

--- 每帧更新所有怪物的动画计时器
---@param dt number 帧间隔
---@param bs table BattleSystem
function EnemyAnim.Update(dt, bs)
    local enemies = bs.enemies
    if not enemies then return end

    for i = 1, #enemies do
        local e = enemies[i]
        local a = e.anim
        if not a then goto continue end

        -- 呼吸浮动 (活着时持续)
        if not e.dead then
            a.breathePhase = a.breathePhase + dt * BREATHE_FREQ * PI2
            if a.breathePhase > PI2 then a.breathePhase = a.breathePhase - PI2 end

            -- Boss 脉冲
            if e.isBoss then
                a.pulsePhase = a.pulsePhase + dt * BOSS_PULSE_FREQ * PI2
                if a.pulsePhase > PI2 then a.pulsePhase = a.pulsePhase - PI2 end
            end
        end

        -- 倒计时器 tick
        if a.flashTimer > 0 then
            a.flashTimer = a.flashTimer - dt
            if a.flashTimer < 0 then a.flashTimer = 0 end
        end
        if a.recoilTimer > 0 then
            a.recoilTimer = a.recoilTimer - dt
            if a.recoilTimer < 0 then a.recoilTimer = 0 end
        end
        if a.windupTimer > 0 then
            a.windupTimer = a.windupTimer - dt
            if a.windupTimer < 0 then a.windupTimer = 0 end
        end
        if a.spawnTimer > 0 then
            a.spawnTimer = a.spawnTimer - dt
            if a.spawnTimer < 0 then a.spawnTimer = 0 end
        end
        if a.deathTimer > 0 then
            a.deathTimer = a.deathTimer - dt
            if a.deathTimer <= 0 then
                a.deathTimer = 0
                e._dyingAnim = false      -- 死亡动画完毕,允许清理
            end
        end

        ::continue::
    end
end

--- 受击触发 (闪白 + 后仰)
---@param e table 怪物实体
---@param bs table BattleSystem
function EnemyAnim.OnHit(e, bs)
    local a = e.anim
    if not a then return end

    a.flashTimer = FLASH_DURATION
    a.recoilTimer = RECOIL_DURATION

    -- 后仰方向: 远离玩家
    local p = bs.playerBattle
    if p then
        local dx, dy = e.x - p.x, e.y - p.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 0.01 then
            a.recoilDirX = dx / dist
            a.recoilDirY = dy / dist
        else
            a.recoilDirX, a.recoilDirY = 0, -1
        end
    else
        a.recoilDirX, a.recoilDirY = 0, -1
    end
end

--- 攻击触发 (前摇挤压弹出)
---@param e table 怪物实体
function EnemyAnim.OnAttack(e)
    local a = e.anim
    if not a then return end
    a.windupTimer = WINDUP_DURATION
end

--- 死亡触发 (缩小淡出)
---@param e table 怪物实体
function EnemyAnim.OnDeath(e)
    local a = e.anim
    if not a then return end
    a.deathTimer = DEATH_DURATION
    e._dyingAnim = true
end

--- 检查死亡动画是否播放中
---@param e table 怪物实体
---@return boolean
function EnemyAnim.IsDying(e)
    return e._dyingAnim == true
end

--- 获取绘制变换 (每帧每怪调用, 零分配)
--- 返回 {offsetX, offsetY, scaleX, scaleY, alpha, flashWhite}
---@param e table 怪物实体
---@return table transform
function EnemyAnim.GetDrawTransform(e)
    local a = e.anim
    if not a then
        _result.offsetX = 0; _result.offsetY = 0
        _result.scaleX = 1; _result.scaleY = 1
        _result.alpha = 1; _result.flashWhite = 0
        return _result
    end

    local ox, oy = 0, 0
    local sx, sy = 1.0, 1.0
    local alpha = 1.0
    local flash = 0

    -- 1) 出生弹跳 (优先级最高, 覆盖基础缩放)
    if a.spawnTimer > 0 then
        local t = 1.0 - (a.spawnTimer / SPAWN_DURATION)   -- 0→1
        local ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)  -- cubic ease-out
        local s = ease * (1.0 + 0.2 * math.sin(t * 3.14159))  -- overshoot hump
        sx, sy = s, s
        -- 出生期间跳过其他缩放
        goto apply_offset
    end

    -- 2) 死亡缩小淡出
    if a.deathTimer > 0 then
        local t = 1.0 - (a.deathTimer / DEATH_DURATION)   -- 0→1
        local ease = t * t                                  -- quadratic ease-in
        sx = sx * (1.0 - ease * 0.8)     -- 1.0 → 0.2
        sy = sy * (1.0 - ease * 0.8)
        alpha = alpha * (1.0 - ease)      -- 1.0 → 0.0
    end

    -- 3) 攻击前摇 (squash & stretch)
    if a.windupTimer > 0 then
        local t = 1.0 - (a.windupTimer / WINDUP_DURATION)  -- 0→1
        local wsx, wsy = 1.0, 1.0
        if t < 0.4 then
            -- 蓄力: 横向挤压, 纵向压扁
            local p = t / 0.4
            wsx = 1.0 + p * 0.12         -- 1.00→1.12
            wsy = 1.0 - p * 0.10         -- 1.00→0.90
        elseif t < 0.7 then
            -- 弹出: 反向拉伸
            local p = (t - 0.4) / 0.3
            wsx = 1.12 - p * 0.22        -- 1.12→0.90
            wsy = 0.90 + p * 0.20        -- 0.90→1.10
        else
            -- 回正
            local p = (t - 0.7) / 0.3
            wsx = 0.90 + p * 0.10        -- 0.90→1.00
            wsy = 1.10 - p * 0.10        -- 1.10→1.00
        end
        sx = sx * wsx
        sy = sy * wsy
    end

    -- 4) Boss 脉冲
    if e.isBoss and not e.dead then
        local pd = math.sin(a.pulsePhase) * BOSS_PULSE_AMP
        sx = sx + pd
        sy = sy + pd
    end

    ::apply_offset::

    -- 5) 呼吸浮动 (活着时)
    if not e.dead then
        local amp = e.isBoss and BREATHE_AMP_BOSS or BREATHE_AMP
        oy = oy + math.sin(a.breathePhase) * amp
    end

    -- 6) 受击后仰
    if a.recoilTimer > 0 then
        local t = 1.0 - (a.recoilTimer / RECOIL_DURATION)  -- 0→1
        -- (1-t)*sin(t*π): 快速弹出, 平滑回正
        local mag = (1.0 - t) * math.sin(t * 3.14159) * RECOIL_DIST
        ox = ox + a.recoilDirX * mag
        oy = oy + a.recoilDirY * mag
    end

    -- 7) 闪白 (独立通道)
    if a.flashTimer > 0 then
        flash = a.flashTimer / FLASH_DURATION
    end

    _result.offsetX = ox; _result.offsetY = oy
    _result.scaleX = sx; _result.scaleY = sy
    _result.alpha = alpha; _result.flashWhite = flash
    return _result
end

return EnemyAnim
