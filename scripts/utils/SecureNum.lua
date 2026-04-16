-- ============================================================================
-- SecureNum.lua - 内存数值混淆 (反作弊)
--
-- 原理: 在原表中直接存储 XOR 编码后的值，通过 metatable 拦截读写透明编解码。
--       内存搜索器搜索"已知值"时无法命中，因为内存中存的是编码后的值。
--
-- 使用:
--   local SecureNum = require("utils.SecureNum")
--   SecureNum.protect(myTable, {"gold", "level", "exp"})
--   -- 之后正常读写 myTable.gold 即可，编解码完全透明
--
-- 限制:
--   - 被保护的字段不能通过 pairs()/next() 正确读取（返回编码值）
--   - 因此只保护不被 pairs() 遍历的表/字段
--   - 仅支持 integer 值（Lua 5.4 的 ~ 运算符要求整数操作数）
--     浮点值会先 ×10000 取整再 XOR，读取时还原
-- ============================================================================

local SecureNum = {}

--- 生成随机 XOR key（每次调用不同，每次 session 不同）
local function newKey()
    return math.random(0x10000, 0x7FFFFFFE)
end

local FLOAT_SCALE = 10000  -- 浮点→整数精度倍率

--- 保护一个表的指定字段
--- @param tbl table 要保护的表
--- @param fields string[] 要保护的字段名列表
--- @param floatFields? string[] 其中的浮点字段（需要特殊处理）
function SecureNum.protect(tbl, fields, floatFields)
    local key = newKey()
    local protectedSet = {}
    local floatSet = {}

    for _, f in ipairs(fields) do
        protectedSet[f] = true
    end
    if floatFields then
        for _, f in ipairs(floatFields) do
            floatSet[f] = true
        end
    end

    -- 将现有值编码
    for _, f in ipairs(fields) do
        local v = rawget(tbl, f)
        if v ~= nil and type(v) == "number" then
            if floatSet[f] then
                rawset(tbl, f, math.floor(v * FLOAT_SCALE) ~ key)
            else
                rawset(tbl, f, math.floor(v) ~ key)
            end
        end
    end

    local mt = {
        __index = function(_, k)
            local raw = rawget(tbl, k)
            if protectedSet[k] and raw ~= nil and type(raw) == "number" then
                if floatSet[k] then
                    return (raw ~ key) / FLOAT_SCALE
                else
                    return raw ~ key
                end
            end
            return raw
        end,

        __newindex = function(_, k, v)
            if protectedSet[k] and type(v) == "number" then
                if floatSet[k] then
                    rawset(tbl, k, math.floor(v * FLOAT_SCALE) ~ key)
                else
                    rawset(tbl, k, math.floor(v) ~ key)
                end
            else
                rawset(tbl, k, v)
            end
        end,
    }

    -- 创建代理表，把原表藏起来
    local proxy = setmetatable({}, mt)
    return proxy, tbl  -- 返回代理和原始表（原始表用于 rawget 需要时）
end

--- 保护多个子表，返回一个总代理
--- 用法: SecureNum.protectGameState(GameState, config)
--- config 格式: { {path="player", fields={...}, floatFields={...}}, ... }
function SecureNum.protectFields(parentTbl, configs)
    for _, cfg in ipairs(configs) do
        local subTbl = parentTbl[cfg.path]
        if subTbl and type(subTbl) == "table" then
            local proxy = SecureNum.protect(subTbl, cfg.fields, cfg.floatFields)
            parentTbl[cfg.path] = proxy
        end
    end
end

return SecureNum
