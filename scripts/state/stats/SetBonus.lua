-- ============================================================================
-- state/stats/SetBonus.lua — 套装系统: 件数统计, stats/statsMul 查询
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config }
function M.Install(GS, ctx)
    local Config = ctx.Config

    -- 运行时状态初始化
    GS.setBuff   = {}   -- { [buffId] = { timer = N, ... } }
    GS.setBuffCD = {}   -- { [buffId] = remainingCD }

    --- 统计当前装备的套装件数
    ---@return table<string, number>
    GS.GetEquippedSetCounts = function()
        local counts = {}
        for _, item in pairs(GS.equipment) do
            if item and item.setId then
                counts[item.setId] = (counts[item.setId] or 0) + 1
            end
        end
        return counts
    end

    --- 获取所有激活的套装被动属性加成 (stats)
    ---@return table<string, number>
    GS.GetSetBonusStats = function()
        local result = {}
        local counts = GS.GetEquippedSetCounts()
        for setId, count in pairs(counts) do
            local setCfg = Config.EQUIP_SET_MAP[setId]
            if setCfg then
                for threshold, bonus in pairs(setCfg.bonuses) do
                    if count >= threshold and bonus.stats then
                        for stat, val in pairs(bonus.stats) do
                            result[stat] = (result[stat] or 0) + val
                        end
                    end
                end
            end
        end
        return result
    end

    --- 获取套装乘算加成 (statsMul)
    ---@return table<string, number>
    GS.GetSetBonusStatsMul = function()
        local result = {}
        local counts = GS.GetEquippedSetCounts()
        for setId, count in pairs(counts) do
            local setCfg = Config.EQUIP_SET_MAP[setId]
            if setCfg then
                for threshold, bonus in pairs(setCfg.bonuses) do
                    if count >= threshold and bonus.statsMul then
                        for stat, val in pairs(bonus.statsMul) do
                            result[stat] = (result[stat] or 0) + val
                        end
                    end
                end
            end
        end
        return result
    end
end

return M
