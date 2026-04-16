-- ============================================================================
-- state/ShieldManager.lua - 通用护盾管理器
-- 支持多来源护盾独立追踪，统一吸收伤害
-- ============================================================================

local ShieldManager = {}

--- 护盾条目表 { [sourceId] = { value = N, maxValue = N } }
---@type table<string, { value: number, maxValue: number }>
local shields = {}

--- 护盾上限获取回调（外部注入，避免循环依赖）
---@type fun(): number | nil
local maxGetter = nil

--- 注册护盾上限获取函数（护盾总量不超过此值）
---@param fn fun(): number
function ShieldManager.SetMaxGetter(fn)
    maxGetter = fn
end

--- 添加/刷新护盾（自动裁剪到上限）
---@param sourceId string 来源标识（如 "ice_armor", "flame_shield"）
---@param value number 护盾值
function ShieldManager.Add(sourceId, value)
    -- 裁剪到上限
    if maxGetter then
        local cap = maxGetter()
        local total = ShieldManager.GetTotal()
        local room = math.max(0, cap - total)
        value = math.min(value, room)
    end
    if value <= 0 then return end

    local existing = shields[sourceId]
    if existing then
        existing.value = existing.value + value
        existing.maxValue = existing.maxValue + value
    else
        shields[sourceId] = { value = value, maxValue = value }
    end
end

--- 移除指定来源的护盾
---@param sourceId string
function ShieldManager.Remove(sourceId)
    shields[sourceId] = nil
end

--- 获取护盾总量
---@return number
function ShieldManager.GetTotal()
    local total = 0
    for _, s in pairs(shields) do
        total = total + s.value
    end
    return total
end

--- 吸收伤害，按比例从各来源扣减
---@param dmg number 待吸收伤害
---@return number absorbed 实际吸收量
---@return number remaining 剩余未吸收伤害
function ShieldManager.Absorb(dmg)
    local total = ShieldManager.GetTotal()
    if total <= 0 then return 0, dmg end

    local absorbed = math.min(dmg, total)
    local ratio = absorbed / total

    -- 按比例从每个来源扣减
    local toRemove = {}
    for id, s in pairs(shields) do
        local deduct = s.value * ratio
        s.value = s.value - deduct
        if s.value < 0.5 then
            toRemove[#toRemove + 1] = id
        end
    end

    -- 清理耗尽的护盾
    for _, id in ipairs(toRemove) do
        shields[id] = nil
    end

    return absorbed, dmg - absorbed
end

--- 检查指定来源是否有护盾
---@param sourceId string
---@return boolean
function ShieldManager.Has(sourceId)
    local s = shields[sourceId]
    return s ~= nil and s.value > 0
end

--- 获取指定来源剩余护盾值
---@param sourceId string
---@return number
function ShieldManager.Get(sourceId)
    local s = shields[sourceId]
    return s and s.value or 0
end

--- 重置所有护盾（战斗重置时调用）
function ShieldManager.Reset()
    shields = {}
end

return ShieldManager
