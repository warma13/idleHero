-- ============================================================================
-- EventBus.lua - 轻量级事件总线
-- 用于模块间解耦通信, 替代直接 require 反向依赖
-- ============================================================================

local EventBus = {}

---@type table<string, function[]>
local listeners_ = {}

--- 注册事件监听
---@param event string 事件名
---@param callback function 回调函数
function EventBus.On(event, callback)
    if not listeners_[event] then
        listeners_[event] = {}
    end
    table.insert(listeners_[event], callback)
end

--- 移除事件监听
---@param event string
---@param callback function
function EventBus.Off(event, callback)
    local list = listeners_[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
        end
    end
end

--- 触发事件
---@param event string
---@param ... any 事件参数
function EventBus.Emit(event, ...)
    local list = listeners_[event]
    if not list then return end
    for i = 1, #list do
        list[i](...)
    end
end

--- 清除所有监听 (用于测试或重置)
function EventBus.Clear()
    listeners_ = {}
end

return EventBus
