-- ============================================================================
-- state/AffixHelper.lua - 词缀运行时工具模块 (P2: 统一词缀系统)
-- ============================================================================
-- 提供装备词缀的运行时查询:
--   GetAffixValue(affixId)  → 所有已装备物品中该词缀的合计生效值
--   HasAffix(affixId)       → 是否拥有该词缀
--   GetAllAffixes()         → 所有已装备词缀列表 { {id, value, greater}, ... }
-- ============================================================================

local AffixHelper = {}

-- 惰性引用，避免循环依赖 (GameState ← Combat ← AffixHelper ← GameState)
local Config, GameState

local function ensureDeps()
    if not Config then
        Config    = require("Config")
        GameState = require("GameState")
    end
end

--- 获取指定词缀在所有已装备物品上的合计生效值
--- P2: 直接读 aff.value (IP 驱动, 值已内含)
---@param affixId string
---@return number 合计值 (0 = 未拥有)
function AffixHelper.GetAffixValue(affixId)
    ensureDeps()
    local total = 0
    for _, item in pairs(GameState.equipment) do
        if item and item.affixes then
            for _, aff in ipairs(item.affixes) do
                if aff.id == affixId then
                    total = total + (aff.value or 0)
                end
            end
        end
    end
    return total
end

--- 是否拥有指定词缀 (至少一件装备带有)
---@param affixId string
---@return boolean
function AffixHelper.HasAffix(affixId)
    ensureDeps()
    for _, item in pairs(GameState.equipment) do
        if item and item.affixes then
            for _, aff in ipairs(item.affixes) do
                if aff.id == affixId then return true end
            end
        end
    end
    return false
end

--- 获取所有已装备词缀 (去重合并)
--- P2: 使用 greater 字段 (取代旧 enhanced)
--- @return table[] { {id, value, greater}, ... }
function AffixHelper.GetAllAffixes()
    ensureDeps()
    local map = {}   -- id → { value, greater }
    local order = {} -- 保持顺序
    for _, item in pairs(GameState.equipment) do
        if item and item.affixes then
            for _, aff in ipairs(item.affixes) do
                if not map[aff.id] then
                    map[aff.id] = { value = 0, greater = false }
                    order[#order + 1] = aff.id
                end
                map[aff.id].value = map[aff.id].value + (aff.value or 0)
                if aff.greater then map[aff.id].greater = true end
            end
        end
    end
    local result = {}
    for _, id in ipairs(order) do
        result[#result + 1] = {
            id      = id,
            value   = map[id].value,
            greater = map[id].greater,
        }
    end
    return result
end

--- 格式化词缀描述文本
--- P2: 使用 AFFIX_POOL_MAP, 兼容旧 AFFIX_MAP
---@param affixId string
---@param value number 生效值
---@return string
function AffixHelper.FormatDesc(affixId, value)
    ensureDeps()
    local def = Config.AFFIX_POOL_MAP[affixId] or Config.AFFIX_MAP[affixId]
    if not def then return "" end
    if def.isPercent then
        return string.format(def.desc, math.floor(value * 100 + 0.5))
    else
        -- 绝对值属性: 显示整数或1位小数
        local rounded = math.floor(value * 10 + 0.5) / 10
        if math.abs(rounded - math.floor(rounded + 0.5)) < 0.01 then
            return string.format(def.desc, string.format("%d", math.floor(rounded + 0.5)))
        else
            return string.format(def.desc, string.format("%.1f", rounded))
        end
    end
end

return AffixHelper
