-- ============================================================================
-- state/equip/Inventory.lua — 背包操作: 穿戴, 排序, 锁定, 分解
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config }
function M.Install(GS, ctx)
    local Config = ctx.Config

    -- 内部工具: 合并材料表 dst += src
    local function mergeMats(dst, src)
        for k, v in pairs(src) do
            dst[k] = (dst[k] or 0) + v
        end
    end

    --- 添加装备到背包，支持自动分解
    --- @return boolean success
    --- @return string|nil autoDecompInfo  自动分解时返回描述文本，否则 nil
    function GS.AddToInventory(item)
        -- 自动分解
        local activeLevel, activeMode = 0, 0
        for k = #GS.autoDecompConfig, 1, -1 do
            if GS.autoDecompConfig[k] > 0 then
                activeLevel = k
                activeMode = GS.autoDecompConfig[k]
                break
            end
        end
        if activeLevel > 0 and item.qualityIdx and item.qualityIdx <= activeLevel
            and not item.locked and (activeMode == 1 or not (item.setId and item.qualityIdx == activeLevel)) then
            -- 金币产出 (按品质)
            local gold = Config.DECOMPOSE_GOLD[item.qualityIdx] or 0
            if gold > 0 then GS.AddGold(gold) end
            local mats = Config.DECOMPOSE_MATERIALS[item.qualityIdx] or { iron = 1 }
            GS.AddMaterials(mats)
            -- 构建分解描述
            local parts = {}
            if gold > 0 then parts[#parts + 1] = gold .. "金币" end
            for matId, amt in pairs(mats) do
                local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                parts[#parts + 1] = amt .. (def and def.name or matId)
            end
            local info = "自动分解 " .. (item.name or "装备") .. " → " .. table.concat(parts, " + ")
            return true, info
        end
        if #GS.inventory >= GS.GetInventorySize() then
            return false, nil
        end
        table.insert(GS.inventory, item)
        return true, nil
    end

    function GS.EquipItem(invIndex)
        local item = GS.inventory[invIndex]
        if not item then return false end
        local old = GS.equipment[item.slot]
        GS.equipment[item.slot] = item
        table.remove(GS.inventory, invIndex)
        if old then
            table.insert(GS.inventory, old)
        end
        return true
    end

    function GS.SortInventoryBySet()
        local slotOrder = {}
        for i, slot in ipairs(Config.EQUIP_SLOTS) do
            slotOrder[slot.id] = i
        end
        table.sort(GS.inventory, function(a, b)
            local sA = a.setId or ""
            local sB = b.setId or ""
            if sA ~= sB then return sA < sB end
            local sa = slotOrder[a.slot] or 99
            local sb = slotOrder[b.slot] or 99
            if sa ~= sb then return sa < sb end
            if a.qualityIdx ~= b.qualityIdx then return a.qualityIdx > b.qualityIdx end
            return (a.itemPower or 0) > (b.itemPower or 0)
        end)
    end

    function GS.SortInventory()
        local slotOrder = {}
        for i, slot in ipairs(Config.EQUIP_SLOTS) do
            slotOrder[slot.id] = i
        end
        table.sort(GS.inventory, function(a, b)
            local sa = slotOrder[a.slot] or 99
            local sb = slotOrder[b.slot] or 99
            if sa ~= sb then return sa < sb end
            if a.qualityIdx ~= b.qualityIdx then return a.qualityIdx > b.qualityIdx end
            local ipA = a.itemPower or 0
            local ipB = b.itemPower or 0
            if ipA ~= ipB then return ipA > ipB end
            local sA = a.setId or ""
            local sB = b.setId or ""
            return sA < sB
        end)
    end

    function GS.AutoEquipBest()
        local changed = false
        for _, slotCfg in ipairs(Config.EQUIP_SLOTS) do
            local bestIdx = nil
            local cur = GS.equipment[slotCfg.id]
            local bestIP = cur and (cur.itemPower or 0) or 0
            for i, item in ipairs(GS.inventory) do
                if item.slot == slotCfg.id then
                    local ip = item.itemPower or 0
                    if ip > bestIP then
                        bestIP = ip
                        bestIdx = i
                    end
                end
            end
            if bestIdx then
                GS.EquipItem(bestIdx)
                changed = true
            end
        end
        return changed
    end

    function GS.ToggleLock(invIndex)
        local item = GS.inventory[invIndex]
        if not item then return end
        item.locked = not item.locked
    end

    function GS.ToggleEquipLock(slotId)
        local item = GS.equipment[slotId]
        if not item then return end
        item.locked = not item.locked
    end

    --- 分解单件装备，返回 gold, matsTable, gemsReturned
    --- matsTable: { [matId] = amount, ... }
    --- gemsReturned: { {type=.., quality=..}, ... } 或 nil
    function GS.DecomposeItem(invIndex)
        local item = GS.inventory[invIndex]
        if not item then return 0, {}, nil end
        if item.locked then return 0, {}, nil end

        -- 金币产出: 基础(按品质) + 退还升级金币(50%)
        local gold = Config.DECOMPOSE_GOLD[item.qualityIdx] or 0
        local spentGold = item.upgradeGoldSpent or 0
        if spentGold > 0 then
            gold = gold + math.floor(spentGold * Config.UPGRADE_REFUND_RATIO)
        end

        -- 基础材料产出
        local baseMats = Config.DECOMPOSE_MATERIALS[item.qualityIdx] or {}
        local mats = {}
        mergeMats(mats, baseMats)

        -- 退还已投入的升级材料 (50%)
        local spent = item.upgradeMatSpent
        if spent then
            for matId, amount in pairs(spent) do
                if amount > 0 then
                    mats[matId] = (mats[matId] or 0) + math.floor(amount * Config.UPGRADE_REFUND_RATIO)
                end
            end
        end

        -- 宝石返还: 100% 原样返还镶嵌的宝石
        local gemsReturned = nil
        if item.gems then
            gemsReturned = {}
            for idx, gem in pairs(item.gems) do
                if gem then
                    table.insert(gemsReturned, { type = gem.type, quality = gem.quality })
                    -- 放回宝石背包
                    if GS.gemBag then
                        table.insert(GS.gemBag, { type = gem.type, quality = gem.quality })
                    end
                end
            end
            if #gemsReturned == 0 then gemsReturned = nil end
        end

        table.remove(GS.inventory, invIndex)
        if gold > 0 then GS.AddGold(gold) end
        GS.AddMaterials(mats)
        return gold, mats, gemsReturned
    end

    function GS.DecomposeAllWhite()
        local totalGold = 0
        local totalMats = {}
        for i = #GS.inventory, 1, -1 do
            if GS.inventory[i].qualityIdx == 1 then
                local g, m = GS.DecomposeItem(i)
                totalGold = totalGold + g
                mergeMats(totalMats, m)
            end
        end
        return totalGold, totalMats
    end

    function GS.DecomposeByFilter(maxQuality, keepSets)
        local totalGold = 0
        local totalMats = {}
        local count = 0
        for i = #GS.inventory, 1, -1 do
            local item = GS.inventory[i]
            if item.qualityIdx <= maxQuality then
                if not item.locked and not (keepSets and item.setId) then
                    local g, m = GS.DecomposeItem(i)
                    totalGold = totalGold + g
                    mergeMats(totalMats, m)
                    count = count + 1
                end
            end
        end
        return totalGold, count, totalMats
    end
end

return M
