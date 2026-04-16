-- ============================================================================
-- state/BuffRegistry.lua - 数据驱动的 Buff 注册表
-- 替换 BuffRuntime 中重复的 if-block 倒计时模式
-- 用法:
--   BuffRegistry.Register({ id="slow", timerField="playerSlowTimer",
--       resetFields = { playerSlowRate = 0, playerSlowTimer = 0 } })
--   BuffRegistry.Update(dt, GameState, bs)   -- 每帧调用
--   BuffRegistry.ResetAll(GameState)          -- 重置战斗时调用
-- ============================================================================

local BuffRegistry = {}

---@type table<string, {id:string, timerField:string, resetFields:table<string,any>, onExpire?:fun(GS:table,bs:table)}>
local buffs = {}

--- 注册一个简单倒计时 buff
---@param cfg {id:string, timerField:string, resetFields:table<string,any>, onExpire?:fun(GS:table,bs:table)}
function BuffRegistry.Register(cfg)
    buffs[cfg.id] = cfg
end

--- 统一倒计时，每帧调用一次
---@param dt number
---@param GameState table
---@param bs table|nil
function BuffRegistry.Update(dt, GameState, bs)
    for _, b in pairs(buffs) do
        local t = GameState[b.timerField]
        if t and t > 0 then
            t = t - dt
            if t <= 0 then
                -- 归零：重置所有关联字段
                for field, val in pairs(b.resetFields) do
                    GameState[field] = val
                end
                if b.onExpire then
                    b.onExpire(GameState, bs)
                end
            else
                GameState[b.timerField] = t
            end
        end
    end
end

--- 批量重置所有已注册 buff 的状态字段
---@param GameState table
function BuffRegistry.ResetAll(GameState)
    for _, b in pairs(buffs) do
        for field, val in pairs(b.resetFields) do
            GameState[field] = val
        end
    end
end

return BuffRegistry
