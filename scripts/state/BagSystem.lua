-- ============================================================================
-- state/BagSystem.lua - 通用道具背包 (Install 模式注入 GameState)
-- ============================================================================

local Config = require("Config")

local M = {}

function M.Install(GS)

    --- 添加道具到背包
    --- @param itemId string 道具ID
    --- @param count number 数量（默认1）
    --- @return number added 实际添加的数量
    function GS.AddBagItem(itemId, count)
        count = count or 1
        local cfg = Config.ITEM_MAP[itemId]
        if not cfg then return 0 end
        local cur = GS.bag[itemId] or 0
        local maxAdd = cfg.maxStack - cur
        local added = math.min(count, math.max(0, maxAdd))
        if added > 0 then
            GS.bag[itemId] = cur + added
        end
        return added
    end

    --- 获取道具数量
    --- @param itemId string
    --- @return number
    function GS.GetBagItemCount(itemId)
        return GS.bag[itemId] or 0
    end

    --- 丢弃道具
    --- @param itemId string
    --- @param count number 丢弃数量（默认1）
    --- @return boolean success, string|nil message
    function GS.DiscardBagItem(itemId, count)
        count = count or 1
        local cfg = Config.ITEM_MAP[itemId]
        if not cfg then return false, "未知道具" end
        local cur = GS.bag[itemId] or 0
        if cur <= 0 then return false, "数量不足" end
        local removed = math.min(count, cur)
        GS.bag[itemId] = cur - removed
        if GS.bag[itemId] <= 0 then GS.bag[itemId] = nil end
        return true, "已丢弃 " .. cfg.name .. " x" .. removed
    end

    --- 使用道具
    --- @param itemId string
    --- @return boolean success, string|nil message
    function GS.UseBagItem(itemId)
        local cfg = Config.ITEM_MAP[itemId]
        if not cfg then return false, "未知道具" end
        local cur = GS.bag[itemId] or 0
        if cur <= 0 then return false, "数量不足" end

        if itemId == "attr_reset" then
            local allocated = GS.GetTotalAllocatedPoints()
            if allocated <= 0 then return false, "没有已分配的属性点" end
            local p = GS.player
            for stat, pts in pairs(p.allocatedPoints) do
                p.freePoints = p.freePoints + pts
                p.allocatedPoints[stat] = 0
            end
            GS.ResetHP()
            GS.bag[itemId] = cur - 1
            return true, "已重置所有属性点，回收 " .. allocated .. " 点"
        elseif itemId == "skill_reset" then
            local spent = GS.GetSpentSkillPts()
            if spent <= 0 then return false, "没有已分配的技能点" end
            for _, skill in pairs(GS.skills) do
                skill.level = 0
            end
            GS.bag[itemId] = cur - 1
            return true, "已重置所有技能点，回收 " .. spent .. " 点"
        elseif cfg.expValue and cfg.expValue > 0 then
            GS.AddExp(cfg.expValue)
            GS.bag[itemId] = cur - 1
            local expStr = cfg.expValue >= 1000000000000 and string.format("%.0f万亿", cfg.expValue / 1000000000000)
                        or cfg.expValue >= 100000000 and string.format("%.0f亿", cfg.expValue / 100000000)
                        or cfg.expValue >= 10000 and string.format("%.0f万", cfg.expValue / 10000)
                        or tostring(cfg.expValue)
            return true, "获得 " .. expStr .. " 经验"
        end

        return false, "该道具暂不可用"
    end
end

return M
