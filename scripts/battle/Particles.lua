-- ============================================================================
-- battle/Particles.lua - 粒子 & 技能特效
-- ============================================================================

local Particles = {}

-- ============================================================================
-- 粒子数量上限（超过时淘汰剩余生命最短的粒子）
-- ============================================================================

local MAX_PARTICLES = 200

--- 带上限的粒子添加（超限时淘汰 life 最小的粒子）
local function AddParticle(particles, p)
    if #particles < MAX_PARTICLES then
        table.insert(particles, p)
        return
    end
    -- 找剩余生命最短的粒子替换掉
    local minIdx, minLife = 1, particles[1].life
    for i = 2, #particles do
        if particles[i].life < minLife then
            minIdx = i
            minLife = particles[i].life
        end
    end
    -- 新粒子比最旧的更有价值才替换
    if p.life > minLife then
        particles[minIdx] = p
    end
end

-- ============================================================================
-- 伤害飘字
-- ============================================================================

local DMG_MERGE_DIST = 30   -- 合并距离阈值(像素)
local DMG_MERGE_TIME = 0.5  -- 飘字剩余生命 > 此值时可合并

-- fxLevel 限频计时器
local lastCritTextTime_ = 0

function Particles.SpawnDmgText(particles, x, y, dmg, isCrit, isSkill, overrideColor)
    -- 特效等级过滤
    local Settings = require("ui.Settings")
    local fxLv = Settings.GetFxLevel()
    if fxLv == 2 then
        -- 减弱: 只显示暴击飘字，且限频 0.2s
        if not isCrit then return end
        local now = time:GetElapsedTime()
        if now - lastCritTextTime_ < 0.2 then return end
        lastCritTextTime_ = now
    elseif fxLv == 3 then
        -- 非常弱: 只显示暴击且限频 0.8s
        if not isCrit then return end
        local now = time:GetElapsedTime()
        if now - lastCritTextTime_ < 0.8 then return end
        lastCritTextTime_ = now
    end
    local color = overrideColor or { 255, 255, 255 }
    if not overrideColor then
        if isSkill then
            color = { 100, 180, 255 }
        end
    end
    -- 暴击时提亮颜色
    if isCrit then
        color = {
            math.min(255, color[1] + 80),
            math.min(255, color[2] + 80),
            math.min(255, color[3] + 40),
        }
    end

    -- 合并: 找附近且足够新的同类飘字，累加数值
    for _, p in ipairs(particles) do
        if p.ptype == "dmgText" and p.life > DMG_MERGE_TIME then
            local dx = (p.mergeX or p.x) - x
            local dy = (p.mergeY or p.y) - y
            if dx * dx + dy * dy < DMG_MERGE_DIST * DMG_MERGE_DIST then
                p.dmgSum = (p.dmgSum or 0) + dmg
                p.text = tostring(p.dmgSum)
                -- 暴击优先级: 有暴击就升级显示
                if isCrit and not p.isCrit then
                    p.isCrit = true
                    p.fontSize = 16
                    p.color = color
                end
                p.life = p.maxLife  -- 重置生命，让合并数字停留更久
                return
            end
        end
    end

    AddParticle(particles, {
        ptype = "dmgText",
        x  = x + math.random(-8, 8),
        y  = y,
        vx = math.random(-15, 15),
        vy = -50 - math.random(0, 30),
        life = 0.8, maxLife = 0.8,
        text = tostring(dmg),
        dmgSum = dmg,
        mergeX = x, mergeY = y,  -- 合并用原始坐标
        color = color,
        isCrit = isCrit,
        fontSize = isCrit and 16 or 12,
    })
end

-- ============================================================================
-- 闪避飘字 (P1 DEX 通用效果)
-- ============================================================================

function Particles.SpawnDodgeText(particles, x, y)
    AddParticle(particles, {
        ptype = "reactionText",  -- 复用反应跳字的渲染逻辑 (缩放动画)
        x  = x + math.random(-4, 4),
        y  = y,
        vx = 0,
        vy = -40,
        life = 1.0, maxLife = 1.0,
        text = "闪避",
        color = { 140, 220, 255 },  -- 淡蓝色
        fontSize = 14,
    })
end

-- ============================================================================
-- 元素反应跳字 (带缩放动画)
-- ============================================================================

function Particles.SpawnReactionText(particles, x, y, name, color)
    AddParticle(particles, {
        ptype = "reactionText",
        x  = x + math.random(-4, 4),
        y  = y,
        vx = 0,
        vy = -35,
        life = 1.2, maxLife = 1.2,
        text = name,
        color = color or { 255, 255, 100 },
        fontSize = 14,
    })
end

-- ============================================================================
-- 击杀爆炸碎片
-- ============================================================================

function Particles.SpawnExplosion(particles, x, y, color)
    for _ = 1, 8 do
        local angle = math.random() * math.pi * 2
        local speed = 60 + math.random() * 80
        AddParticle(particles, {
            ptype = "debris",
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 30,
            life = 0.5, maxLife = 0.5,
            size  = 2 + math.random() * 3,
            color = { color[1], color[2], color[3] },
        })
    end
end

-- ============================================================================
-- 陨石爆炸粒子 (爆炸火球 + 烟雾 + 火星碎片)
-- ============================================================================

function Particles.SpawnMeteorExplosion(particles, x, y, radius)
    -- 爆炸火球 (中心大火球 + 周围小火球)
    AddParticle(particles, {
        ptype = "meteorExplosion",
        x = x, y = y, vx = 0, vy = 0,
        life = 0.6, maxLife = 0.6,
        size = radius * 1.2,
        subtype = "fireball",
    })
    for i = 1, 4 do
        local angle = (i / 4) * math.pi * 2 + math.random() * 0.5
        local dist = radius * 0.4
        AddParticle(particles, {
            ptype = "meteorExplosion",
            x = x + math.cos(angle) * dist,
            y = y + math.sin(angle) * dist,
            vx = math.cos(angle) * 20,
            vy = math.sin(angle) * 20,
            life = 0.45, maxLife = 0.45,
            size = radius * 0.6,
            subtype = "fireball",
        })
    end

    -- 烟雾 (向上飘散)
    for i = 1, 5 do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius * 0.5
        AddParticle(particles, {
            ptype = "meteorExplosion",
            x = x + math.cos(angle) * dist,
            y = y + math.sin(angle) * dist,
            vx = math.random(-15, 15),
            vy = -20 - math.random(0, 30),
            life = 0.9 + math.random() * 0.3,
            maxLife = 1.2,
            size = radius * (0.5 + math.random() * 0.4),
            subtype = "smoke",
        })
    end

    -- 火星碎片 (四散飞溅)
    for i = 1, 10 do
        local angle = math.random() * math.pi * 2
        local speed = 80 + math.random() * 120
        AddParticle(particles, {
            ptype = "meteorExplosion",
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 40,
            life = 0.4 + math.random() * 0.3,
            maxLife = 0.7,
            size = 10 + math.random() * 8,
            subtype = "ember",
        })
    end
end

-- ============================================================================
-- 冰霜爆炸粒子 (冰晶碎片 + 霜雾 + 雪花飘散)
-- ============================================================================

function Particles.SpawnFrostExplosion(particles, x, y, radius)
    -- 冰晶碎片 (中心爆裂 + 四周飞溅)
    AddParticle(particles, {
        ptype = "frostExplosion",
        x = x, y = y, vx = 0, vy = 0,
        life = 0.5, maxLife = 0.5,
        size = radius * 1.0,
        subtype = "iceShard",
    })
    for i = 1, 5 do
        local angle = (i / 5) * math.pi * 2 + math.random() * 0.6
        local dist = radius * 0.3
        local speed = 60 + math.random() * 40
        AddParticle(particles, {
            ptype = "frostExplosion",
            x = x + math.cos(angle) * dist,
            y = y + math.sin(angle) * dist,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.4 + math.random() * 0.2,
            maxLife = 0.6,
            size = radius * 0.4 + math.random() * radius * 0.2,
            subtype = "iceShard",
        })
    end

    -- 霜雾 (缓慢扩散)
    for i = 1, 4 do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius * 0.4
        AddParticle(particles, {
            ptype = "frostExplosion",
            x = x + math.cos(angle) * dist,
            y = y + math.sin(angle) * dist,
            vx = math.random(-10, 10),
            vy = -10 - math.random(0, 15),
            life = 1.0 + math.random() * 0.4,
            maxLife = 1.4,
            size = radius * (0.6 + math.random() * 0.4),
            subtype = "frostMist",
        })
    end

    -- 雪花 (四散飘落)
    for i = 1, 8 do
        local angle = math.random() * math.pi * 2
        local speed = 40 + math.random() * 80
        AddParticle(particles, {
            ptype = "frostExplosion",
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed - 20,
            life = 0.5 + math.random() * 0.4,
            maxLife = 0.9,
            size = 8 + math.random() * 6,
            subtype = "snowflake",
        })
    end
end

-- ============================================================================
-- 更新
-- ============================================================================

function Particles.Update(dt, particles)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        -- 重力支持 (装备掉落等)
        if p.gravity then
            p.vy = (p.vy or 0) + p.gravity * dt
        end
        p.x = p.x + (p.vx or 0) * dt
        p.y = p.y + (p.vy or 0) * dt
        if p.life <= 0 then table.remove(particles, i) end
    end
end

-- ============================================================================
-- 升级特效 (金色光点上飘 + 光环扩散)
-- ============================================================================

function Particles.SpawnLevelUp(particles, x, y)
    -- 金色光点上飘 (12颗)
    for i = 1, 12 do
        local angle = (i / 12) * math.pi * 2 + math.random() * 0.3
        local dist = 8 + math.random() * 16
        AddParticle(particles, {
            ptype = "levelUpSparkle",
            x = x + math.cos(angle) * dist,
            y = y + math.sin(angle) * dist * 0.5,
            vx = math.cos(angle) * (10 + math.random() * 15),
            vy = -40 - math.random() * 40,
            life = 0.8 + math.random() * 0.5,
            maxLife = 1.3,
            size = 2 + math.random() * 3,
        })
    end
    -- 光环扩散
    AddParticle(particles, {
        ptype = "levelUpRing",
        x = x, y = y,
        vx = 0, vy = 0,
        life = 0.7, maxLife = 0.7,
        size = 0,
    })
    -- "LEVEL UP" 跳字
    AddParticle(particles, {
        ptype = "levelUpText",
        x = x, y = y - 10,
        vx = 0, vy = -25,
        life = 1.4, maxLife = 1.4,
        text = "LEVEL UP!",
        color = { 255, 230, 80 },
        fontSize = 14,
    })
end

-- ============================================================================
-- 装备掉落粒子 (世界Boss击杀后掉落展示)
-- ============================================================================

function Particles.SpawnEquipDrop(particles, x, y, name, slotName, color)
    AddParticle(particles, {
        ptype    = "equipDrop",
        x        = x,
        y        = y,
        vx       = math.random(-25, 25),
        vy       = -70 - math.random(0, 40),
        gravity  = 120,
        life     = 2.5,
        maxLife  = 2.5,
        text     = name,
        slotName = slotName,
        color    = color or { 200, 200, 200 },
        fontSize = 10,
    })
end

-- 同屏特效数量上限（超出时移除最老的）
local MAX_SKILL_EFFECTS = 24

function Particles.UpdateSkillEffects(dt, effects)
    -- 过期清理
    for i = #effects, 1, -1 do
        local eff = effects[i]
        eff.life = eff.life - dt
        if eff.life <= 0 then table.remove(effects, i) end
    end
    -- 超出上限时移除最老的（数组头部 = 最先插入 = 最老）
    while #effects > MAX_SKILL_EFFECTS do
        table.remove(effects, 1)
    end
end

return Particles
