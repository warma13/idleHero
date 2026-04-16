-- ============================================================================
-- state/equip/Forge.lua — 锻造系统 (装备商店)
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, calcItemPower, rollNewAffixes, rollWeaponElement, buildItemName, addSocketsIfOrange }
function M.Install(GS, ctx)
    local Config             = ctx.Config
    local calcItemPower      = ctx.calcItemPower
    local rollNewAffixes     = ctx.rollNewAffixes
    local rollWeaponElement  = ctx.rollWeaponElement
    local buildItemName      = ctx.buildItemName
    local addSocketsIfOrange = ctx.addSocketsIfOrange

    function GS.ForgeEquip(segmentId, lockSlotId)
        local today = os.date("%Y-%m-%d")
        if GS.forge.lastDate ~= today then
            GS.forge.usedFree = 0
            GS.forge.usedPaid = 0
            GS.forge.lastDate = today
        end

        local isFree = GS.forge.usedFree < Config.FORGE_FREE_PER_DAY
        local totalUsed = GS.forge.usedFree + GS.forge.usedPaid

        if totalUsed >= Config.FORGE_TOTAL_PER_DAY then
            return nil, "今日锻造次数已用完"
        end

        if isFree and lockSlotId then
            return nil, "免费锻造不能锁定部位"
        end

        local maxCh = GS.records and GS.records.maxChapter or 1
        local maxSt = GS.records and GS.records.maxStage or 1
        local scaleMul, bossChapter = Config.GetForgeSegmentScaleMul(segmentId, maxCh, maxSt)
        if not scaleMul then
            return nil, "未解锁该分段（需通关Boss）"
        end

        local lockSlot = lockSlotId ~= nil
        local goldCost = isFree and 0 or Config.GetForgeGoldCost(scaleMul, lockSlot)
        local matCost = isFree and {} or Config.GetForgeMaterialCost(lockSlot)

        if not isFree then
            if GS.player.gold < goldCost then
                return nil, "金币不足 (" .. math.floor(GS.player.gold) .. "/" .. goldCost .. ")"
            end
            local ok, reason = GS.HasMaterials(matCost)
            if not ok then
                return nil, reason
            end
        end

        if not isFree then
            GS.player.gold = GS.player.gold - goldCost
            GS.SpendMaterials(matCost)
        end

        local qualityIdx = Config.FORGE_QUALITY_IDX
        local quality = Config.EQUIP_QUALITY[qualityIdx]

        local slotCfg
        if lockSlotId then
            for _, sc in ipairs(Config.EQUIP_SLOTS) do
                if sc.id == lockSlotId then slotCfg = sc; break end
            end
        end
        if not slotCfg then
            slotCfg = Config.EQUIP_SLOTS[math.random(1, #Config.EQUIP_SLOTS)]
        end

        local itemPower = calcItemPower(bossChapter, qualityIdx, 0)

        -- v12: 锻造不再产出套装，套装改为套装秘境掉落
        local setId = nil

        local element = rollWeaponElement(slotCfg, qualityIdx)
        local affixes = rollNewAffixes(slotCfg.id, qualityIdx, itemPower)

        local item = {
            slot = slotCfg.id, slotName = slotCfg.name,
            qualityIdx = qualityIdx, qualityName = quality.name, qualityColor = quality.color,
            itemPower = itemPower, affixes = affixes,
            setId = setId, element = element, forged = true, upgradeLv = 0,
        }
        item.name = buildItemName(slotCfg, setId, element)
        addSocketsIfOrange(item)

        if isFree then
            GS.forge.usedFree = GS.forge.usedFree + 1
        else
            GS.forge.usedPaid = GS.forge.usedPaid + 1
        end

        local SaveSys = require("SaveSystem")
        SaveSys.MarkDirty()

        local costStr = "免费"
        if not isFree then
            local parts = { goldCost .. "金" }
            for matId, amt in pairs(matCost) do
                local def = Config.MATERIAL_MAP[matId]
                parts[#parts + 1] = amt .. (def and def.name or matId)
            end
            costStr = "消耗 " .. table.concat(parts, " ")
        end
        print("[Forge] " .. item.name .. " (IP " .. itemPower .. ", " .. costStr .. ")")
        return item, nil
    end

    function GS.GetForgeInfo()
        local today = os.date("%Y-%m-%d")
        if GS.forge.lastDate ~= today then
            GS.forge.usedFree = 0
            GS.forge.usedPaid = 0
            GS.forge.lastDate = today
        end
        local isFree = GS.forge.usedFree < Config.FORGE_FREE_PER_DAY
        local totalUsed = GS.forge.usedFree + GS.forge.usedPaid
        return {
            isFree = isFree,
            remaining = Config.FORGE_TOTAL_PER_DAY - totalUsed,
            usedFree = GS.forge.usedFree,
            usedPaid = GS.forge.usedPaid,
        }
    end
end

return M
