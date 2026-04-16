-- ============================================================================
-- state/DebuffApplier.lua - 数据驱动的 Debuff 施加器
-- 替换 BuffRuntime 中 10 个重复的 Apply*Debuff 函数
-- 保留相同的外部函数签名 (GameState.ApplyXxxDebuff), 内部统一走此模块
--
-- 三种模式:
--   override   — 新值 > 旧值时覆盖 (slow/antiHeal/inkBlind/sandStorm/sporeCloud)
--   stack_inc  — 设值 + stacks++ (corrosion/venomStack/scorch)
--   stack_add  — stacks += N, 每层固定值经韧性衰减 (drench/tidalCorrosion)
-- ============================================================================

local DebuffApplier = {}

---@class DebuffConfig
---@field ccImmune boolean          是否受 CC 免疫阻挡
---@field mode "override"|"stack_inc"|"stack_add"
---@field valueField string|nil     效果值字段 (override/stack_inc)
---@field timerField string         计时器字段
---@field stackField string|nil     叠层计数字段 (stack_*)
---@field maxStackField string|nil  最大层数字段 (stack_*)
---@field extraFields table|nil     额外字段映射 { paramKey -> gsField }, 值 × (1-resist)
---@field thresholdParam string|nil stack_add 时用于阈值判断的 param key
---@field minThreshold number|nil   最小有效值 (默认 0.01)

---@type table<string, DebuffConfig>
local registry = {}

--- 注册一种 debuff 配置
function DebuffApplier.Register(id, cfg)
    registry[id] = cfg
end

--- 统一施加 debuff (经韧性衰减)
--- @param id string          debuff 类型 ID
--- @param GameState table    游戏状态
--- @param params table       { value, duration, [maxStacks], [stacksToAdd], ... }
--- @return boolean           是否成功施加
function DebuffApplier.Apply(id, GameState, params)
    if GameState.playerDead then return false end

    local cfg = registry[id]
    if not cfg then
        print("[DebuffApplier] unknown debuff: " .. tostring(id))
        return false
    end

    -- CC 免疫检查
    if cfg.ccImmune and GameState.ccImmune then return false end

    -- 韧性衰减
    local Config = require("Config")
    local resist = GameState.GetDebuffResist()
    local durFactor = Config.TENACITY.durFactor
    local actualDur = params.duration * (1 - resist * durFactor)
    local threshold = cfg.minThreshold or 0.01

    -- ----------------------------------------------------------------
    -- 阈值检查 (在设置任何字段之前)
    -- ----------------------------------------------------------------
    if cfg.mode == "override" or cfg.mode == "stack_inc" then
        local actualValue = params.value * (1 - resist)
        if actualValue < threshold then return false end
    end
    if cfg.thresholdParam then
        local raw = params[cfg.thresholdParam]
        if raw and raw * (1 - resist) < threshold then return false end
    end

    -- ----------------------------------------------------------------
    -- 按模式设置字段
    -- ----------------------------------------------------------------
    if cfg.mode == "override" then
        local actualValue = params.value * (1 - resist)
        local curValue = GameState[cfg.valueField] or 0
        local curTimer = GameState[cfg.timerField] or 0
        if actualValue > curValue or curTimer <= 0 then
            GameState[cfg.valueField] = actualValue
            GameState[cfg.timerField] = actualDur
        end

    elseif cfg.mode == "stack_inc" then
        local actualValue = params.value * (1 - resist)
        GameState[cfg.valueField] = actualValue
        GameState[cfg.timerField] = actualDur
        if cfg.maxStackField then
            GameState[cfg.maxStackField] = params.maxStacks
        end
        if cfg.stackField then
            local max = params.maxStacks or 999
            if GameState[cfg.stackField] < max then
                GameState[cfg.stackField] = GameState[cfg.stackField] + 1
            end
        end

    elseif cfg.mode == "stack_add" then
        GameState[cfg.timerField] = actualDur
        if cfg.maxStackField then
            GameState[cfg.maxStackField] = params.maxStacks
        end
        if cfg.stackField then
            local max = params.maxStacks or 999
            local add = params.stacksToAdd or 1
            GameState[cfg.stackField] = math.min(GameState[cfg.stackField] + add, max)
        end
    end

    -- 额外字段: 值 × (1-resist)
    if cfg.extraFields then
        for paramKey, gsField in pairs(cfg.extraFields) do
            local raw = params[paramKey]
            if raw ~= nil then
                GameState[gsField] = raw * (1 - resist)
            end
        end
    end

    return true
end

return DebuffApplier
