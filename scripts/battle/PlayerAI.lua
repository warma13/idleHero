-- ============================================================================
-- battle/PlayerAI.lua - 玩家自动战斗 AI & 技能释放
-- ============================================================================

local Config = require("Config")
local GameState = require("GameState")
local FamilyMechanics = require("battle.FamilyMechanics")

local PlayerAI = {}

-- ============================================================================
-- 闪避系统参数 (智能弹体/区域躲避)
-- ============================================================================

local DodgeConfig = {
    -- 反应延迟: 模拟人类感知延迟
    REACTION_DELAY      = 0.15,   -- 150ms 基础反应时间
    REACTION_VARIANCE   = 0.10,   -- ±100ms 随机波动
    MISS_CHANCE         = 0.08,   -- 8% 概率完全忽略某个威胁

    -- 弹体闪避
    PROJ_LOOKAHEAD      = 1.2,    -- 预测 1.2 秒内的弹体
    PROJ_DANGER_DIST    = 30,     -- CPA < 30px 时触发 (玩家12 + 弹体8 + 余量10)
    PROJ_WEIGHT         = 0.8,    -- 弹体闪避向量混合权重
    PROJ_URGENCY_SCALE  = 3.0,    -- 紧急度放大系数

    -- 扇形弹幕间隙
    BARRAGE_MIN_COUNT   = 4,      -- ≥4 颗弹体视为扇形弹幕
    BARRAGE_AGE_WINDOW  = 0.3,    -- 同一波弹幕的 age 窗口 (秒)
    BARRAGE_GAP_MIN     = 0.22,   -- 最小安全间隙角度 (~12.6°)
    BARRAGE_RETREAT_W   = 1.2,    -- 无间隙时后撤权重

    -- 爆炸闪避
    EXPL_HP_THRESHOLD   = 0.15,   -- 敌人 HP<15% 时预判死亡爆炸
    EXPL_FLEE_MARGIN    = 15,     -- 额外逃离余量 (像素)
    EXPL_WEIGHT         = 0.5,    -- 爆炸闪避权重

    -- 攻击态闪避
    ATTACK_DODGE_MUL    = 0.6,    -- 攻击态闪避速度 = 60% 移速

    -- 噪音 / 不完美性
    DODGE_NOISE         = 0.15,   -- 闪避方向噪音 ±8.5°
    NOISE_INTERVAL      = 0.4,    -- 噪音重新随机间隔 (秒)
}

-- ============================================================================
-- 辅助
-- ============================================================================

function PlayerAI.FindNearestEnemy(px, py, enemies)
    local nearestIdx, nearestDist = nil, math.huge
    for i, e in ipairs(enemies) do
        if not e.dead and not FamilyMechanics.IsUntargetable(e) then
            local dx, dy = e.x - px, e.y - py
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < nearestDist then
                nearestDist = dist
                nearestIdx  = i
            end
        end
    end
    return nearestIdx, nearestDist
end

-- ============================================================================
-- 普攻 AI  (风筝走位: 保持攻击范围边缘, 边打边退)
-- ============================================================================

--- 计算所有活着敌人的威胁排斥力 (用于远离密集敌群)
---@param px number
---@param py number
---@param enemies table
---@param dangerRadius number 排斥生效半径
---@return number, number 归一化排斥方向 (rx, ry), 无威胁时返回 0,0
local function CalcRepulsion(px, py, enemies, dangerRadius)
    local rx, ry = 0, 0
    for _, e in ipairs(enemies) do
        if not e.dead then
            local dx, dy = px - e.x, py - e.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < dangerRadius and dist > 1 then
                -- 距离越近排斥越强 (反比权重)
                local weight = (dangerRadius - dist) / dangerRadius
                weight = weight * weight  -- 平方衰减, 近处更强
                rx = rx + (dx / dist) * weight
                ry = ry + (dy / dist) * weight
            end
        end
    end
    local len = math.sqrt(rx * rx + ry * ry)
    if len > 0.01 then
        return rx / len, ry / len
    end
    return 0, 0
end

-- ============================================================================
-- 弹体轨迹预测 (CPA — Closest Point of Approach)
-- ============================================================================

--- 计算单颗弹体的闪避向量
---@param px number 玩家 X
---@param py number 玩家 Y
---@param proj table 弹体 {x, y, vx, vy, radius, ...}
---@return number, number 加权闪避方向 (未归一化), number 紧急度
local function CalcSingleProjDodge(px, py, proj)
    local dpx, dpy = px - proj.x, py - proj.y
    local speedSq = proj.vx * proj.vx + proj.vy * proj.vy
    if speedSq < 1 then return 0, 0, 0 end

    -- 最近接近时刻
    local t_cpa = (dpx * proj.vx + dpy * proj.vy) / speedSq
    if t_cpa < 0 then return 0, 0, 0 end                          -- 弹体远离
    if t_cpa > DodgeConfig.PROJ_LOOKAHEAD then return 0, 0, 0 end  -- 太远

    -- 最近接近点
    local cpx = proj.x + proj.vx * t_cpa
    local cpy = proj.y + proj.vy * t_cpa
    local closeDx, closeDy = px - cpx, py - cpy
    local closeDist = math.sqrt(closeDx * closeDx + closeDy * closeDy)

    local dangerDist = DodgeConfig.PROJ_DANGER_DIST
    if closeDist >= dangerDist then return 0, 0, 0 end  -- 安全

    -- 闪避方向: 垂直于弹体速度, 推向远离轨迹的一侧
    local perpX, perpY = -proj.vy, proj.vx
    local dot = perpX * closeDx + perpY * closeDy
    if dot < 0 then perpX, perpY = -perpX, -perpY end

    local perpLen = math.sqrt(perpX * perpX + perpY * perpY)
    if perpLen < 0.01 then return 0, 0, 0 end
    perpX, perpY = perpX / perpLen, perpY / perpLen

    -- 紧急度: 越近越紧急, 越快到达越紧急
    local distUrgency = (dangerDist - closeDist) / dangerDist
    local timeUrgency = math.min(DodgeConfig.PROJ_URGENCY_SCALE, 1.0 / math.max(t_cpa, 0.1))
    local urgency = distUrgency * timeUrgency

    return perpX * urgency, perpY * urgency, urgency
end

-- ============================================================================
-- 弹幕闪避 (分组 + 间隙查找 + 反应延迟)
-- ============================================================================

--- 计算弹体闪避向量 (含扇形弹幕间隙查找)
---@param px number 玩家 X
---@param py number 玩家 Y
---@param bs table BattleSystem
---@param p table playerBattle
---@param dt number 帧时间
---@return number, number 归一化闪避方向
local function CalcProjectileDodge(px, py, bs, p, dt)
    if not bs or not bs.bossProjectiles or #bs.bossProjectiles == 0 then
        return 0, 0
    end

    -- 初始化反应状态
    if not p._projReaction then
        p._projReaction = {}
        p._projMissed = {}
        p._dodgeNoise = 0
        p._dodgeNoiseTimer = 0
    end

    -- 更新噪音
    p._dodgeNoiseTimer = p._dodgeNoiseTimer - dt
    if p._dodgeNoiseTimer <= 0 then
        p._dodgeNoise = (math.random() - 0.5) * 2 * DodgeConfig.DODGE_NOISE
        p._dodgeNoiseTimer = DodgeConfig.NOISE_INTERVAL
    end

    local seenIds = {}
    local barrages = {}   -- [sourceKey] = { projs = {}, srcX, srcY }

    for _, proj in ipairs(bs.bossProjectiles) do
        local id = proj.threatId or tostring(proj)
        seenIds[id] = true

        -- 反应延迟
        if not p._projReaction[id] and not p._projMissed[id] then
            if math.random() < DodgeConfig.MISS_CHANCE then
                p._projMissed[id] = true
            else
                p._projReaction[id] = DodgeConfig.REACTION_DELAY
                    + (math.random() - 0.5) * 2 * DodgeConfig.REACTION_VARIANCE
            end
        end
        if p._projMissed[id] then goto proj_continue end
        if p._projReaction[id] then
            if p._projReaction[id] > 0 then
                p._projReaction[id] = p._projReaction[id] - dt
                goto proj_continue
            end
        end

        -- 按来源 + age 窗口分组
        do
            local srcKey = tostring(proj.sourceEnemy or "?") .. "_" .. math.floor((proj.age or 0) / DodgeConfig.BARRAGE_AGE_WINDOW)
            if not barrages[srcKey] then
                local se = proj.sourceEnemy
                barrages[srcKey] = {
                    projs = {},
                    srcX = se and se.x or proj.x,
                    srcY = se and se.y or proj.y,
                }
            end
            table.insert(barrages[srcKey].projs, proj)
        end

        ::proj_continue::
    end

    -- 清理过期条目
    for id in pairs(p._projReaction) do
        if not seenIds[id] then p._projReaction[id] = nil end
    end
    for id in pairs(p._projMissed) do
        if not seenIds[id] then p._projMissed[id] = nil end
    end

    local ax, ay = 0, 0
    local maxUrgency = 0
    local bestDx, bestDy = 0, 0

    for _, group in pairs(barrages) do
        if #group.projs >= DodgeConfig.BARRAGE_MIN_COUNT then
            -- ═══ 扇形弹幕: 找角度间隙 ═══
            local srcX, srcY = group.srcX, group.srcY
            local angles = {}
            for _, proj in ipairs(group.projs) do
                table.insert(angles, math.atan(proj.y - srcY, proj.x - srcX))
            end
            table.sort(angles)

            -- 找最大间隙
            local bestGap, bestMid = 0, nil
            for i = 1, #angles do
                local nextI = (i % #angles) + 1
                local gap = angles[nextI] - angles[i]
                if nextI == 1 then gap = gap + 2 * math.pi end
                if gap > bestGap then
                    bestGap = gap
                    bestMid = angles[i] + gap * 0.5
                end
            end

            if bestGap > DodgeConfig.BARRAGE_GAP_MIN and bestMid then
                -- 穿过间隙中点
                local tgtX = srcX + math.cos(bestMid) * 100
                local tgtY = srcY + math.sin(bestMid) * 100
                local gdx, gdy = tgtX - px, tgtY - py
                local glen = math.sqrt(gdx * gdx + gdy * gdy)
                if glen > 1 then
                    local distToSrc = math.sqrt((px - srcX) * (px - srcX) + (py - srcY) * (py - srcY))
                    local urg = math.max(0, 1 - distToSrc / 300)
                    ax = ax + (gdx / glen) * urg * 1.5
                    ay = ay + (gdy / glen) * urg * 1.5
                end
            else
                -- 无安全间隙: 后撤
                local rdx, rdy = px - srcX, py - srcY
                local rlen = math.sqrt(rdx * rdx + rdy * rdy)
                if rlen > 1 then
                    ax = ax + (rdx / rlen) * DodgeConfig.BARRAGE_RETREAT_W
                    ay = ay + (rdy / rlen) * DodgeConfig.BARRAGE_RETREAT_W
                end
            end
        else
            -- ═══ 少量弹体: 逐个 CPA 闪避 ═══
            for _, proj in ipairs(group.projs) do
                local pdx, pdy, purg = CalcSingleProjDodge(px, py, proj)
                ax = ax + pdx
                ay = ay + pdy
                if purg > maxUrgency then
                    maxUrgency = purg
                    bestDx, bestDy = pdx, pdy
                end
            end
        end
    end

    -- 方向冲突回退: 多向量相互抵消但有高紧急威胁时, 用最紧急的
    local len = math.sqrt(ax * ax + ay * ay)
    if len < 0.1 and maxUrgency > 0.5 then
        ax, ay = bestDx, bestDy
        len = math.sqrt(ax * ax + ay * ay)
    end

    -- 噪音注入
    if len > 0.01 then
        local cos_n = math.cos(p._dodgeNoise)
        local sin_n = math.sin(p._dodgeNoise)
        local nx = ax * cos_n - ay * sin_n
        local ny = ax * sin_n + ay * cos_n
        ax, ay = nx, ny
        len = math.sqrt(ax * ax + ay * ay)
    end

    if len > 0.01 then
        return ax / len, ay / len
    end
    return 0, 0
end

-- ============================================================================
-- 死亡爆炸预判
-- ============================================================================

--- 预判即将死亡的敌人的爆炸, 提前逃离
---@param px number 玩家 X
---@param py number 玩家 Y
---@param enemies table 敌人列表
---@return number, number 归一化逃离方向
local function CalcExplosionDodge(px, py, enemies)
    local fx, fy = 0, 0
    for _, e in ipairs(enemies) do
        if not e.dead and e.deathExplode then
            local hpPct = (e.maxHp and e.maxHp > 0) and (e.hp / e.maxHp) or 1
            if hpPct <= DodgeConfig.EXPL_HP_THRESHOLD then
                local radius = e.deathExplode.radius or 40
                local edx, edy = px - e.x, py - e.y
                local dist = math.sqrt(edx * edx + edy * edy)
                local fleeR = radius + DodgeConfig.EXPL_FLEE_MARGIN

                if dist < fleeR and dist > 1 then
                    local urgency = (fleeR - dist) / fleeR
                    urgency = urgency * urgency
                    urgency = urgency * (1 + (DodgeConfig.EXPL_HP_THRESHOLD - hpPct) * 10)
                    fx = fx + (edx / dist) * urgency
                    fy = fy + (edy / dist) * urgency
                end
            end
        end
    end
    local len = math.sqrt(fx * fx + fy * fy)
    if len > 0.01 then return fx / len, fy / len end
    return 0, 0
end

-- ============================================================================
-- 威胁感知 (增强版: 支持 sector/ring/rect 形状)
-- ============================================================================

--- 从威胁表计算躲避向量
---@param px number
---@param py number
---@param bs table BattleSystem
---@return number, number 归一化躲避方向
local function CalcThreatAvoidance(px, py, bs)
    if not bs or not bs.threats then return 0, 0 end
    local ThreatSystem = require("battle.ThreatSystem")
    local threats = ThreatSystem.GetThreats(bs)
    if not threats or #threats == 0 then return 0, 0 end

    local ax, ay = 0, 0
    for _, t in ipairs(threats) do
        if t.type == "dangerZone" then
            if t.shape == "sector" and t.shapeData then
                -- ═══ 扇形 (吐息攻击): 向最近边缘外侧逃离 ═══
                local sd = t.shapeData
                local range = sd.range or t.radius or 50
                if ThreatSystem.PointInSector(px, py, t.x, t.y, sd.dirAngle, sd.halfAngle, range) then
                    local pAngle = math.atan(py - t.y, px - t.x)
                    local diff = pAngle - sd.dirAngle
                    diff = (diff + math.pi) % (2 * math.pi) - math.pi

                    -- 向更近的扇形边缘外侧逃 (切线 70% + 径向 30%)
                    local escAngle
                    if diff >= 0 then
                        escAngle = sd.dirAngle + sd.halfAngle + math.pi * 0.4
                    else
                        escAngle = sd.dirAngle - sd.halfAngle - math.pi * 0.4
                    end
                    local angX = math.cos(escAngle)
                    local angY = math.sin(escAngle)

                    local rdx, rdy = px - t.x, py - t.y
                    local rdist = math.sqrt(rdx * rdx + rdy * rdy)
                    local radX = rdist > 1 and (rdx / rdist) or 0
                    local radY = rdist > 1 and (rdy / rdist) or 0

                    ax = ax + (angX * 0.7 + radX * 0.3) * 1.5
                    ay = ay + (angY * 0.7 + radY * 0.3) * 1.5
                end

            elseif t.shape == "ring" and t.shapeData then
                -- ═══ 脉冲环: 判断内外决定逃跑方向 ═══
                local sd = t.shapeData
                local ringSpeed = sd.speed or 80
                local ringWidth = sd.width or 20
                local currentR = (t.age or 0) * ringSpeed
                local outerR = currentR
                local innerR = math.max(0, currentR - ringWidth)

                local rdx, rdy = px - t.x, py - t.y
                local dist = math.sqrt(rdx * rdx + rdy * rdy)

                if dist >= innerR - 20 and dist <= outerR + 20 and dist > 1 then
                    if currentR > dist * 1.6 then
                        -- 环已越过: 向内移动 (已在安全区)
                        ax = ax + (-rdx / dist) * 0.5
                        ay = ay + (-rdy / dist) * 0.5
                    else
                        -- 环接近: 向外跑
                        ax = ax + (rdx / dist) * 1.2
                        ay = ay + (rdy / dist) * 1.2
                    end
                end

            elseif t.shape == "rect" and t.shapeData then
                -- ═══ 矩形 (屏障): 沿最短轴逃出 ═══
                local sd = t.shapeData
                local rx = sd.rx or (t.x - (sd.rw or 40) / 2)
                local ry = sd.ry or (t.y - (sd.rh or 40) / 2)
                local rw = sd.rw or 40
                local rh = sd.rh or 40
                if ThreatSystem.PointInRect(px, py, rx, ry, rw, rh) then
                    local cx, cy = rx + rw / 2, ry + rh / 2
                    local rdx, rdy = px - cx, py - cy
                    local escX, escY = 0, 0
                    if math.abs(rdx) / rw < math.abs(rdy) / rh then
                        escX = rdx > 0 and 1 or -1
                    else
                        escY = rdy > 0 and 1 or -1
                    end
                    ax = ax + escX * 1.5
                    ay = ay + escY * 1.5
                end

            else
                -- ═══ 圆形 (默认): 径向排斥 ═══
                local dx, dy = px - t.x, py - t.y
                local dist = math.sqrt(dx * dx + dy * dy)
                local r = t.radius or 50
                if dist < r and dist > 1 then
                    local urgency = (r - dist) / r
                    urgency = urgency * urgency
                    ax = ax + (dx / dist) * urgency * 2.0
                    ay = ay + (dy / dist) * urgency * 2.0
                end
            end

        elseif t.type == "pull" then
            -- 漩涡拉力: AI 尝试远离中心
            local dx, dy = px - t.x, py - t.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local r = t.radius or 60
            if dist < r and dist > 1 then
                local urgency = (r - dist) / r
                ax = ax + (dx / dist) * urgency * 1.5
                ay = ay + (dy / dist) * urgency * 1.5
            end
        end
    end

    local len = math.sqrt(ax * ax + ay * ay)
    if len > 0.01 then
        return ax / len, ay / len
    end
    return 0, 0
end

--- 评估威胁目标: 如果存在优先攻击目标(可摧毁物), 返回其索引
---@param px number
---@param py number
---@param enemies table
---@param bs table
---@return integer|nil 优先目标在 enemies 中的索引
local function EvaluateThreatTargets(px, py, enemies, bs)
    if not bs or not bs.threats then return nil end
    local ThreatSystem = require("battle.ThreatSystem")
    local threats = ThreatSystem.GetThreats(bs)
    if not threats then return nil end

    -- 查找 priorityTarget 类型威胁
    for _, t in ipairs(threats) do
        if t.type == "priorityTarget" then
            -- 找到对应的 enemies 条目
            for i, e in ipairs(enemies) do
                if not e.dead and e.isBossDestroyable then
                    local dx, dy = e.x - t.x, e.y - t.y
                    if math.abs(dx) < 5 and math.abs(dy) < 5 then
                        return i
                    end
                end
            end
        end
    end
    return nil
end

---@param dt number
---@param p table  playerBattle
---@param enemies table
---@param areaW number
---@param areaH number
---@param onAttack fun(targetIdx: integer)
---@param bs table|nil BattleSystem 引用 (模板系统威胁感知)
function PlayerAI.Update(dt, p, enemies, areaW, areaH, onAttack, bs)
    -- 攻击闪光衰减
    if p.atkFlash > 0 then p.atkFlash = p.atkFlash - dt * 4 end
    p.atkTimer = math.max(0, p.atkTimer - dt)

    local nearestIdx, nearestDist = PlayerAI.FindNearestEnemy(p.x, p.y, enemies)
    if not nearestIdx then
        p.state = "idle"
        p.targetIdx = nil
        return
    end

    -- 锁定冷却: 切换目标后一段时间内不再切换, 防止频繁转向
    local LOCK_COOLDOWN = 0.1  -- 锁定冷却时间（秒）
    p.targetLockTimer = (p.targetLockTimer or 0) - dt

    -- 威胁系统: 检查是否有优先攻击目标 (可摧毁物)
    local priorityIdx = EvaluateThreatTargets(p.x, p.y, enemies, bs)

    -- 迟滞阈值 + 冷却: 当前目标仍存活时, 冷却期内不切换
    if priorityIdx then
        -- 优先攻击可摧毁物 (覆盖常规目标选择)
        p.targetIdx = priorityIdx
        p.targetLockTimer = LOCK_COOLDOWN
    elseif p.targetIdx and enemies[p.targetIdx] and not enemies[p.targetIdx].dead then
        if p.targetLockTimer <= 0 then
            local cur = enemies[p.targetIdx]
            local cdx, cdy = cur.x - p.x, cur.y - p.y
            local curDist = math.sqrt(cdx * cdx + cdy * cdy)
            if nearestDist < curDist * 0.75 then
                p.targetIdx = nearestIdx
                p.targetLockTimer = LOCK_COOLDOWN
            end
        end
        -- 冷却中或距离不够: 保持当前目标
    else
        p.targetIdx = nearestIdx
        p.targetLockTimer = LOCK_COOLDOWN
    end

    local target = enemies[p.targetIdx]
    local dx, dy = target.x - p.x, target.y - p.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if math.abs(dx) > 1 then p.faceDirX = dx > 0 and 1 or -1 end

    local atkRange = GameState.GetRange()
    -- 理想站位距离: 攻击范围的 85%, 留一定余量确保命中
    local idealDist = atkRange * 0.85
    -- 敌人攻击范围 (用最近敌人的, 默认 35)
    local enemyRange = target.atkRange or 35
    -- 危险距离: 敌人攻击范围 + 缓冲区
    local dangerDist = enemyRange + 10

    -- ================================================================
    -- 移动决策
    -- ================================================================
    -- 引导期间降低移速
    local ok_cs, CS = pcall(require, "battle.ChannelSystem")
    local channelSpeedMul = (ok_cs and CS.IsChanneling()) and CS.GetMoveSpeedMul() or 1.0
    local effectiveMoveSpeed = Config.PLAYER.moveSpeed * channelSpeedMul
    -- 闪光火焰护盾: 移动速度+25%
    if GameState._flameShieldSpeedTimer and GameState._flameShieldSpeedTimer > 0 then
        effectiveMoveSpeed = effectiveMoveSpeed * 1.25
    end
    -- 闪光冰霜新星: 移动速度+20% (4秒)
    if GameState._frostNovaSpeedTimer and GameState._frostNovaSpeedTimer > 0 then
        effectiveMoveSpeed = effectiveMoveSpeed * 1.20
    end
    -- 强化冰封球: 移动速度+30% (3秒)
    if GameState._frozenOrbSpeedTimer and GameState._frozenOrbSpeedTimer > 0 then
        effectiveMoveSpeed = effectiveMoveSpeed * 1.30
    end

    local moveX, moveY = 0, 0

    -- 迟滞: 攻击态需超出范围 15% 才切移动, 防止边界反复切换导致卡顿
    local effAtkRange = (p.state == "attacking") and (atkRange * 1.15) or atkRange

    if dist > effAtkRange then
        -- 太远: 直接接近目标
        p.state = "moving"
        moveX, moveY = dx / dist, dy / dist
    elseif dist < dangerDist and atkRange > dangerDist then
        -- 太近 (在敌人攻击范围内且我方射程有优势): 后撤到理想距离
        p.state = "moving"
        -- 后撤方向 = 远离目标
        local backX, backY = -dx / dist, -dy / dist
        -- 混合横向分量实现弧线后撤, 不是直线退
        local sideX, sideY = -backY, backX  -- 垂直方向
        -- 选择远离边界的侧向
        local centerX, centerY = areaW * 0.5, areaH * 0.5
        local toCenterX, toCenterY = centerX - p.x, centerY - p.y
        local sideDot = sideX * toCenterX + sideY * toCenterY
        if sideDot < 0 then sideX, sideY = -sideX, -sideY end
        -- 后撤 70% + 侧移 30%
        moveX = backX * 0.7 + sideX * 0.3
        moveY = backY * 0.7 + sideY * 0.3
    elseif dist < idealDist * 0.7 then
        -- 距离明显小于理想距离: 轻微后撤
        p.state = "moving"
        moveX, moveY = -dx / dist, -dy / dist
    else
        -- 在理想范围内: 攻击 + 平滑风筝
        p.state = "attacking"
        local repX, repY = CalcRepulsion(p.x, p.y, enemies, dangerDist)
        local threatX, threatY = CalcThreatAvoidance(p.x, p.y, bs)
        local driftX = repX + threatX * 0.5
        local driftY = repY + threatY * 0.5
        local driftSpeed = effectiveMoveSpeed * 0.3
        -- 平滑风筝: 敌人接近时持续微退, 不等到 dangerDist 才跑
        if dist < idealDist and dist > 1 then
            local gap = math.max(1, idealDist - dangerDist)
            local kiteT = math.min(1, (idealDist - dist) / gap)
            driftX = driftX + (-dx / dist) * kiteT
            driftY = driftY + (-dy / dist) * kiteT
            driftSpeed = effectiveMoveSpeed * (0.3 + kiteT * 0.3)
        end
        local driftLen = math.sqrt(driftX * driftX + driftY * driftY)
        if driftLen > 0.01 then
            driftX, driftY = driftX / driftLen, driftY / driftLen
            p.x = p.x + driftX * driftSpeed * dt
            p.y = p.y + driftY * driftSpeed * dt
        end
    end

    -- 执行移动
    if moveX ~= 0 or moveY ~= 0 then
        local len = math.sqrt(moveX * moveX + moveY * moveY)
        moveX, moveY = moveX / len, moveY / len
        -- 叠加群体排斥力 (避免扎堆)
        local repX, repY = CalcRepulsion(p.x, p.y, enemies, dangerDist)
        moveX = moveX + repX * 0.3
        moveY = moveY + repY * 0.3
        -- 叠加威胁躲避 (Boss 技能区域)
        local threatX, threatY = CalcThreatAvoidance(p.x, p.y, bs)
        moveX = moveX + threatX * 0.6
        moveY = moveY + threatY * 0.6
        -- 重新归一化
        len = math.sqrt(moveX * moveX + moveY * moveY)
        if len > 0.01 then
            moveX, moveY = moveX / len, moveY / len
        end
        p.x = p.x + moveX * effectiveMoveSpeed * dt
        p.y = p.y + moveY * effectiveMoveSpeed * dt
    end

    -- ════ 闪避叠加层 (独立于基础移动, 不会抵消导致卡顿) ════
    local projDX, projDY = CalcProjectileDodge(p.x, p.y, bs, p, dt)
    local explDX, explDY = CalcExplosionDodge(p.x, p.y, enemies)
    local dodgeX = projDX * DodgeConfig.PROJ_WEIGHT + explDX * DodgeConfig.EXPL_WEIGHT
    local dodgeY = projDY * DodgeConfig.PROJ_WEIGHT + explDY * DodgeConfig.EXPL_WEIGHT
    local dodgeLen = math.sqrt(dodgeX * dodgeX + dodgeY * dodgeY)
    if dodgeLen > 0.01 then
        dodgeX, dodgeY = dodgeX / dodgeLen, dodgeY / dodgeLen
        local dodgeMul = (p.state == "attacking") and DodgeConfig.ATTACK_DODGE_MUL or 0.5
        local dodgeSpeed = effectiveMoveSpeed * dodgeMul
        p.x = p.x + dodgeX * dodgeSpeed * dt
        p.y = p.y + dodgeY * dodgeSpeed * dt
    end

    -- 边界限制
    p.x = math.max(20, math.min(areaW - 20, p.x))
    p.y = math.max(20, math.min(areaH - 20, p.y))

    -- 引导系统: 引导中跳过普攻, 但攻速计时器继续流转(引导结束后可立即攻击)
    local ok_ch, ChannelSystem = pcall(require, "battle.ChannelSystem")
    local isChanneling = ok_ch and ChannelSystem.IsChanneling()

    -- 攻击判定: 只要在攻击范围内就可以攻击 (包括边移动边攻击)
    if not isChanneling and dist <= atkRange and p.atkTimer <= 0 then
        onAttack(nearestIdx)
        p.atkTimer = 1.0 / GameState.GetAtkSpeed()
        p.atkFlash = 1.0
    end
end

-- ============================================================================
-- 技能自动释放
-- ============================================================================

---@param dt number
---@param p table  playerBattle
---@param enemies table
---@param onCastSkill fun(skillCfg: table, lv: integer)
function PlayerAI.UpdateSkills(dt, p, enemies, onCastSkill)
    local cdMul = GameState.GetSkillCdMul()

    -- 符文编织6件: 共鸣期间CD流速翻倍 (dt加速)
    local cdFlowMul = 1.0
    local ok_bm, BuffManager = pcall(require, "battle.BuffManager")
    if ok_bm and BuffManager.GetRuneResonanceCdMul then
        cdFlowMul = BuffManager.GetRuneResonanceCdMul()
    end
    local effectiveDt = dt * cdFlowMul

    -- CD 始终倒计时 (包括空闲期), 但施法仅在非空闲时
    local isIdle = (p.state == "idle")

    -- v3.0: 使用已装备的主动技能列表 (SkillTreeConfig 驱动)
    local equippedList = GameState.GetEquippedSkillList()
    for _, entry in ipairs(equippedList) do
        local skillCfg = entry.cfg
        local lv = entry.level
        -- 核心技能走攻速槽位 (CombatCore.PlayerAttack), 不走CD通道
        if skillCfg.coreSkill then
            -- skip: 由攻速计时器驱动
        else
        local cd = skillCfg.cooldown or 0
        if cd > 0 then
            local timer = p.skillTimers[entry.id] or 0
            timer = timer - effectiveDt
            if timer <= 0 then
                if not isIdle then
                    onCastSkill(skillCfg, lv)
                end
                -- 无论是否施法, CD 重置 (空闲时技能转好后等待下一波立刻施放)
                if timer <= 0 then
                    local finalCd = cd * cdMul
                    -- 至尊雷霆风暴: 闪电技能CD-20%
                    if (GameState._thunderStormSupremeTimer or 0) > 0
                       and skillCfg.element == "lightning" then
                        finalCd = finalCd * 0.80
                    end
                    timer = isIdle and 0 or finalCd
                end
            end
            p.skillTimers[entry.id] = timer
        end
        end -- else (non-coreSkill)
    end
end

return PlayerAI
