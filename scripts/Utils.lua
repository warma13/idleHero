-- ============================================================================
-- Utils.lua - 通用工具函数
-- ============================================================================

local Utils = {}

--- 创建防抖包装器
--- 在 cooldown 秒内重复调用会被忽略
--- @param fn function 原始回调
--- @param cd? number 冷却秒数 (默认 0.3)
--- @return function 包装后的回调
function Utils.Debounce(fn, cd)
    cd = cd or 0.3
    local lastTime = 0
    return function(...)
        local now = time:GetElapsedTime()
        if now - lastTime < cd then return end
        lastTime = now
        return fn(...)
    end
end

-- ========================================================================
-- 大数格式化 (统一全游戏数字显示)
-- ========================================================================

--- 格式化大数字为可读文本
--- 规则: <1万原样, >=1万用万, >=1亿用亿, >=1万亿用万亿, >=1e16用科学计数法
--- @param n number
--- @return string
function Utils.FormatNumber(n)
    if n ~= n then return "0" end       -- NaN
    if n == math.huge then return "∞" end
    local abs = math.abs(n)
    local sign = n < 0 and "-" or ""
    if abs < 10000 then
        return sign .. tostring(math.floor(abs))
    elseif abs < 100000000 then          -- 1万 ~ 1亿
        return sign .. string.format("%.2f万", abs / 10000)
    elseif abs < 1000000000000 then      -- 1亿 ~ 1万亿
        return sign .. string.format("%.2f亿", abs / 100000000)
    elseif abs < 10000000000000000 then  -- 1万亿 ~ 1e16
        return sign .. string.format("%.2f万亿", abs / 1000000000000)
    else
        -- 科学计数法
        local exp = math.floor(math.log(abs, 10))
        local man = abs / (10 ^ exp)
        return sign .. string.format("%.2f×10^%d", man, exp)
    end
end

--- 格式化大数字 - 整数版 (无小数, 适合不需要精度的场景)
--- @param n number
--- @return string
function Utils.FormatNumberInt(n)
    if n ~= n then return "0" end
    local abs = math.abs(n)
    local sign = n < 0 and "-" or ""
    if abs < 10000 then
        return sign .. tostring(math.floor(abs))
    elseif abs < 100000000 then
        return sign .. string.format("%.1f万", abs / 10000)
    elseif abs < 1000000000000 then
        return sign .. string.format("%.1f亿", abs / 100000000)
    elseif abs < 10000000000000000 then
        return sign .. string.format("%.1f万亿", abs / 1000000000000)
    else
        local exp = math.floor(math.log(abs, 10))
        local man = abs / (10 ^ exp)
        return sign .. string.format("%.1f×10^%d", man, exp)
    end
end

return Utils
