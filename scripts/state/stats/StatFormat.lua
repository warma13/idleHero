-- ============================================================================
-- state/stats/StatFormat.lua — 属性格式化: FormatStatValue, FormatItemStat, FormatSeconds, FormatBigNumber
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config }
function M.Install(GS, ctx)
    local Config = ctx.Config

    --- 智能格式化数值
    local function smartFmt(v, maxDec)
        local rounded = math.floor(v * 10^maxDec + 0.5) / 10^maxDec
        if math.abs(rounded - math.floor(rounded + 0.5)) < 0.001 then
            return string.format("%d", math.floor(rounded + 0.5))
        elseif maxDec >= 2 and math.abs(rounded * 10 - math.floor(rounded * 10 + 0.5)) < 0.01 then
            return string.format("%.1f", rounded)
        else
            return string.format("%." .. maxDec .. "f", rounded)
        end
    end

    --- 格式化单个属性值
    GS.FormatStatValue = function(statKey, value)
        local def = Config.EQUIP_STATS[statKey]
        if not def then return "+" .. smartFmt(value, 2) end
        if def.isPercent then
            return "+" .. smartFmt(value * 100, 1) .. "%"
        elseif def.fmtSub then
            return string.format("+" .. def.fmtSub, value)
        else
            return "+" .. smartFmt(value, 2)
        end
    end

    --- 格式化装备简短显示
    GS.FormatItemStat = function(item)
        if not item then return "" end
        if item.itemPower then
            return "IP " .. item.itemPower
        end
        return ""
    end

    --- 格式化秒数
    GS.FormatSeconds = function(secs)
        if secs <= 0 then return "" end
        secs = math.floor(secs)
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        local s = secs % 60
        if h > 0 then
            return string.format("%d:%02d:%02d", h, m, s)
        else
            return string.format("%d:%02d", m, s)
        end
    end

    --- 大数字缩写
    GS.FormatBigNumber = function(n)
        local FmtUtils = require("Utils")
        return FmtUtils.FormatNumber(n)
    end
end

return M
