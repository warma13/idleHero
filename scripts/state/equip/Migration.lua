-- ============================================================================
-- state/equip/Migration.lua — 运行时迁移: 旧格式装备 → 统一词缀 + IP
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config }
function M.Install(GS, ctx)
    local Config = ctx.Config

    --- 就地迁移单个装备 (旧 mainStat/subStats → 统一 affixes[] + itemPower)
    local function runtimeMigrateItem(item)
        if not item or type(item) ~= "table" then return false end
        if item.itemPower and item.affixes and #item.affixes > 0 then return false end

        local newAffixes = {}

        if item.mainStat then
            table.insert(newAffixes, {
                id = item.mainStat, value = item.mainValue or 0, greater = false,
            })
        end

        if item.subStats then
            for _, sub in ipairs(item.subStats) do
                table.insert(newAffixes, {
                    id = sub.key, value = sub.value or 0, greater = false,
                })
            end
        end

        if item.affixes then
            for _, aff in ipairs(item.affixes) do
                local def = Config.AFFIX_MAP and Config.AFFIX_MAP[aff.id]
                local base = def and def.baseValue or 0.2
                local isGreater = aff.enhanced or false
                table.insert(newAffixes, {
                    id = aff.id,
                    value = isGreater and (base * 1.5) or base,
                    greater = isGreater,
                })
            end
        end

        local tier = item.tier or 1
        local chapter = 1
        if tier > 1 then
            chapter = math.max(1, math.floor(100 ^ ((tier - 1) / 99) + 0.5))
        end
        local baseIP = Config.CalcBaseIP(chapter)
        local qi = item.qualityIdx or 1
        local ipQMul = Config.IP_QUALITY_MUL[qi] or 0.5
        -- v4.0: IP_PER_UPGRADE 已移除; 旧迁移路径仍需回退旧值 5
        local OLD_IP_PER_UPGRADE = 5
        item.itemPower = math.floor(baseIP * ipQMul + (item.upgradeLv or 0) * OLD_IP_PER_UPGRADE)

        item.affixes = newAffixes
        item.mainStat = nil
        item.mainValue = nil
        item.baseMainValue = nil
        item.subStats = nil
        item.tier = nil
        item.tierMul = nil
        return true
    end

    --- 为缺少主属性的装备补上主属性 (存档兼容)
    local function ensureMainStat(item)
        if not item or type(item) ~= "table" then return false end
        if item.mainStatId then return false end  -- 已有主属性
        if not item.slot then return false end
        local msDef = Config.GetMainStatDef(item.slot)
        if not msDef then return false end
        item.mainStatId    = msDef.id
        item.mainStatBase  = msDef.slotBase
        item.mainStatValue = Config.CalcMainStatValueFull(msDef.slotBase, item.itemPower or 100, item.upgradeLv)
        return true
    end

    -- 启动时迁移
    local migratedCount = 0
    local mainStatCount = 0
    if GS.equipment then
        for _, item in pairs(GS.equipment) do
            if runtimeMigrateItem(item) then migratedCount = migratedCount + 1 end
            if ensureMainStat(item) then mainStatCount = mainStatCount + 1 end
        end
    end
    if GS.inventory then
        for _, item in ipairs(GS.inventory) do
            if runtimeMigrateItem(item) then migratedCount = migratedCount + 1 end
            if ensureMainStat(item) then mainStatCount = mainStatCount + 1 end
        end
    end
    if migratedCount > 0 then
        print(string.format("[Equipment] Runtime migrated %d items to unified affix system", migratedCount))
    end
    if mainStatCount > 0 then
        print(string.format("[Equipment] Added mainStat to %d items (save compat)", mainStatCount))
    end
end

return M
