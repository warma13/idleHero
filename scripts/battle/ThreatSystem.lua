-- ============================================================================
-- battle/ThreatSystem.lua - 威胁表管理 + 空间碰撞工具
-- Boss 模板技能创建威胁对象, PlayerAI 读取后自主决策
-- ============================================================================

local ThreatSystem = {}

-- ============================================================================
-- 威胁表管理
-- ============================================================================

--- 初始化威胁表 (BattleSystem.Init 调用)
function ThreatSystem.Init(bs)
    bs.threats = {}
end

--- 清空威胁表 (波次结束/Boss死亡时调用)
function ThreatSystem.Clear(bs)
    bs.threats = {}
end

--- 注册威胁对象
--- @param bs table BattleSystem
--- @param threat table { type, x, y, radius, damage, duration, priority, sourceId, shape?, shapeData? }
--- type: "dangerZone" | "priorityTarget" | "taunt" | "pull" | "expandingRing"
function ThreatSystem.Register(bs, threat)
    threat.age = 0
    table.insert(bs.threats, threat)
end

--- 每帧更新: 衰减 duration, 清除过期威胁
function ThreatSystem.Update(dt, bs)
    for i = #bs.threats, 1, -1 do
        local t = bs.threats[i]
        t.age = t.age + dt
        if t.duration then
            t.duration = t.duration - dt
            if t.duration <= 0 then
                table.remove(bs.threats, i)
            end
        end
    end
end

--- 获取当前所有活跃威胁
--- @return table threats
function ThreatSystem.GetThreats(bs)
    return bs.threats or {}
end

--- 移除指定 sourceId 的所有威胁 (Boss 死亡/技能结束时调用)
function ThreatSystem.RemoveBySource(bs, sourceId)
    for i = #bs.threats, 1, -1 do
        if bs.threats[i].sourceId == sourceId then
            table.remove(bs.threats, i)
        end
    end
end

-- ============================================================================
-- 空间碰撞工具
-- ============================================================================

--- 圆-圆碰撞
--- @return boolean
function ThreatSystem.CircleCircle(x1, y1, r1, x2, y2, r2)
    local dx, dy = x2 - x1, y2 - y1
    local distSq = dx * dx + dy * dy
    local rSum = r1 + r2
    return distSq <= rSum * rSum
end

--- 点在扇形内 (Boss位置为圆心, 朝向angle, 半角halfAngle)
--- @param px number 点X
--- @param py number 点Y
--- @param cx number 扇形圆心X
--- @param cy number 扇形圆心Y
--- @param dirAngle number 扇形朝向角度(弧度)
--- @param halfAngle number 扇形半角(弧度)
--- @param range number 扇形半径
--- @return boolean
function ThreatSystem.PointInSector(px, py, cx, cy, dirAngle, halfAngle, range)
    local dx, dy = px - cx, py - cy
    local distSq = dx * dx + dy * dy
    if distSq > range * range then return false end
    local pointAngle = math.atan(dy, dx)
    local diff = pointAngle - dirAngle
    -- 归一化到 [-pi, pi]
    diff = (diff + math.pi) % (2 * math.pi) - math.pi
    return math.abs(diff) <= halfAngle
end

--- 点在环形内 (环心cx,cy, 内半径ri, 外半径ro)
--- @return boolean
function ThreatSystem.PointInRing(px, py, cx, cy, innerR, outerR)
    local dx, dy = px - cx, py - cy
    local distSq = dx * dx + dy * dy
    return distSq >= innerR * innerR and distSq <= outerR * outerR
end

--- 点在矩形内 (AABB: x,y 为左上角, w,h 为宽高)
--- @return boolean
function ThreatSystem.PointInRect(px, py, rx, ry, rw, rh)
    return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

--- 两点距离的平方 (避免 sqrt 开销)
function ThreatSystem.DistSq(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return dx * dx + dy * dy
end

--- 两点距离
function ThreatSystem.Dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

return ThreatSystem
