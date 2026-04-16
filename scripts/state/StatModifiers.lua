-- ============================================================================
-- state/StatModifiers.lua - 属性修饰器注册系统
-- ============================================================================
-- 注册式修饰器，替代 StatCalc Get* 函数中的硬编码 if-timer 检查。
-- 新增 buff/debuff 只需 SM.Register({...})，无需改 StatCalc。
--
-- 修饰器类型:
--   pctPool   : 加算百分比池, 求和后 ×(1 + sum)
--   pctMul    : 独立乘算, 逐个 ×(1 + val)
--   pctReduce : 独立减算, 逐个 ×(1 - val)
--   flatAdd   : 平坦加值, 求和加到 base
--   flatSub   : 平坦减值, 求和从 base 减
--
-- Apply 公式:
--   result = (base + flatAdd - flatSub) × (1 + Σ pctPool) × Π(1 + pctMul_i) × Π(1 - pctReduce_j)
-- ============================================================================

local StatModifiers = {}

---@class StatModifier
---@field id string           唯一标识
---@field stat string         目标属性 ("atk"|"atkSpeed"|"crit" 等)
---@field type string         修饰器类型
---@field valueFn fun(): number  返回当前修饰值
---@field conditionFn? fun(): boolean  可选条件, nil 视为始终生效

-- 按属性分组: { [stat] = { mod1, mod2, ... } }
local byStat = {}

-- id → mod 快查 (用于 Remove)
local byId = {}

--- 注册修饰器
---@param mod StatModifier
function StatModifiers.Register(mod)
    assert(mod.id, "StatModifiers.Register: missing id")
    assert(mod.stat, "StatModifiers.Register: missing stat")
    assert(mod.type, "StatModifiers.Register: missing type")
    assert(mod.valueFn, "StatModifiers.Register: missing valueFn")

    -- 如果 id 已存在, 先移除旧的
    if byId[mod.id] then
        StatModifiers.Remove(mod.id)
    end

    if not byStat[mod.stat] then
        byStat[mod.stat] = {}
    end
    table.insert(byStat[mod.stat], mod)
    byId[mod.id] = mod
end

--- 移除修饰器
---@param id string
function StatModifiers.Remove(id)
    local mod = byId[id]
    if not mod then return end
    byId[id] = nil

    local list = byStat[mod.stat]
    if list then
        for i = #list, 1, -1 do
            if list[i].id == id then
                table.remove(list, i)
                break
            end
        end
    end
end

--- 收集某属性所有活跃修饰器的汇总值
---@param stat string
---@return { pctPool: number, pctMuls: number[], pctReduces: number[], flatAdd: number, flatSub: number }
function StatModifiers.Collect(stat)
    local result = { pctPool = 0, pctMuls = {}, pctReduces = {}, flatAdd = 0, flatSub = 0 }
    local list = byStat[stat]
    if not list then return result end

    for _, mod in ipairs(list) do
        -- 检查条件
        if not mod.conditionFn or mod.conditionFn() then
            local val = mod.valueFn()
            if val and val ~= 0 then
                local t = mod.type
                if t == "pctPool" then
                    result.pctPool = result.pctPool + val
                elseif t == "pctMul" then
                    result.pctMuls[#result.pctMuls + 1] = val
                elseif t == "pctReduce" then
                    result.pctReduces[#result.pctReduces + 1] = val
                elseif t == "flatAdd" then
                    result.flatAdd = result.flatAdd + val
                elseif t == "flatSub" then
                    result.flatSub = result.flatSub + val
                end
            end
        end
    end

    return result
end

--- 应用修饰器到基础值
---@param stat string
---@param base number
---@return number
function StatModifiers.Apply(stat, base)
    local c = StatModifiers.Collect(stat)

    -- flatAdd / flatSub
    local result = base + c.flatAdd - c.flatSub

    -- pctPool: 加算汇总, 一次乘
    result = result * (1 + c.pctPool)

    -- pctMul: 独立乘算
    for _, val in ipairs(c.pctMuls) do
        result = result * (1 + val)
    end

    -- pctReduce: 独立减算
    for _, val in ipairs(c.pctReduces) do
        result = result * (1 - val)
    end

    return result
end

--- 清空所有修饰器 (测试用)
function StatModifiers.Clear()
    byStat = {}
    byId = {}
end

return StatModifiers
