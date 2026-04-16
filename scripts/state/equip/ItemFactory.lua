-- ============================================================================
-- state/equip/ItemFactory.lua — 物品生成: GenerateEquip, CreateEquip
-- ============================================================================
-- 同时将共享 helper 注入 ctx 供 Forge/Upgrade 使用:
--   ctx.calcItemPower, ctx.rollNewAffixes, ctx.rollWeaponElement,
--   ctx.buildItemName, ctx.addSocketsIfOrange
-- ============================================================================

local M = {}

---@param GS table GameState
---@param ctx table { Config, AffixHelper }
function M.Install(GS, ctx)
    local Config      = ctx.Config
    local AffixHelper = ctx.AffixHelper

    -- ====================================================================
    -- 内部工具
    -- ====================================================================

    local function shuffle(arr)
        for i = #arr, 2, -1 do
            local j = math.random(1, i)
            arr[i], arr[j] = arr[j], arr[i]
        end
    end

    local function shuffleSelect(pool, n)
        local copy = {}
        for i, v in ipairs(pool) do copy[i] = v end
        shuffle(copy)
        local result = {}
        for i = 1, math.min(n, #copy) do result[i] = copy[i] end
        return result
    end

    -- ====================================================================
    -- 孔位生成 (仅橙装)
    -- ====================================================================

    local function rollInitialSockets()
        local weights = Config.SOCKET_WEIGHTS
        local roll = math.random()
        local acc = 0
        for i, w in ipairs(weights) do
            acc = acc + w
            if roll <= acc then return i - 1 end
        end
        return 0
    end

    local function addSocketsIfOrange(item)
        if item.qualityIdx == 5 then
            item.sockets = rollInitialSockets()
            item.gems = {}
        end
    end

    -- ====================================================================
    -- IP 驱动词缀 Roll
    -- ====================================================================

    local function calcItemPower(chapter, qualityIdx)
        local baseIP = Config.CalcBaseIP(chapter)
        local qMul = Config.IP_QUALITY_MUL[qualityIdx] or 0.5
        return math.floor(baseIP * qMul)
        -- (v4.0: 升级不再改变 IP, 移除 upgradeLv * IP_PER_UPGRADE)
    end

    local function rollNewAffixes(slotId, qualityIdx, itemPower)
        local pool = Config.AFFIX_SLOT_POOLS[slotId]
        if not pool then return {} end
        local affixCount = Config.AFFIX_COUNT_BY_QUALITY[qualityIdx] or 1
        local selected = shuffleSelect(pool, affixCount)
        local minRoll, maxRoll = Config.GetIPBracket(itemPower)
        local isOrange = (qualityIdx == 5)
        local affixes = {}
        for _, affId in ipairs(selected) do
            local def = Config.AFFIX_POOL_MAP[affId]
            if def then
                local roll = minRoll + math.random() * (maxRoll - minRoll)
                local value = Config.CalcAffixValue(def, itemPower, roll)
                local isGreater = false
                if isOrange and math.random() < Config.AFFIX_GREATER_CHANCE then
                    value = value * 1.5
                    isGreater = true
                end
                table.insert(affixes, {
                    id = affId, value = value,
                    greater = isGreater or nil,
                })
            end
        end
        return affixes
    end

    -- ====================================================================
    -- 套装 & 名称
    -- ====================================================================

    -- (v4.0: rollWeaponElement 已移除, 武器不再有元素)

    local function buildItemName(slotCfg, setId)
        local nameParts = { slotCfg.name }
        if setId then
            local setCfg = Config.EQUIP_SET_MAP[setId]
            if setCfg then table.insert(nameParts, 1, setCfg.name) end
        end
        return table.concat(nameParts)
    end

    local function rollSetId(chapter, quality)
        if not quality.canHaveSet then return nil end
        if math.random() >= Config.SET_DROP_CHANCE then return nil end
        local batchStart, batchEnd = Config.GetDropBatch(chapter)
        local available = {}
        for _, s in ipairs(Config.EQUIP_SETS) do
            if not s.retired and Config.IsSetInBatch(s, batchStart, batchEnd) then
                table.insert(available, s.id)
            end
        end
        if #available == 0 then return nil end
        return available[math.random(1, #available)]
    end

    -- ====================================================================
    -- 共享 helper 注入 ctx (Forge/Upgrade 需要)
    -- ====================================================================

    ctx.calcItemPower      = calcItemPower
    ctx.rollNewAffixes     = rollNewAffixes
    ctx.buildItemName      = buildItemName
    ctx.addSocketsIfOrange = addSocketsIfOrange

    -- ====================================================================
    -- GameState 方法
    -- ====================================================================

    --- 生成随机装备
    function GS.GenerateEquip(waveLevel, isBoss, overrideChapter)
        local luck = GS.GetLuck()
        local luckyStarVal = AffixHelper.GetAffixValue("lucky_star")
        local totalWeight = 0
        local weights = {}
        local mobMul = { 1, 1, 0.054, 0.02, 0.008 }
        for i, q in ipairs(Config.EQUIP_QUALITY) do
            local w = q.dropWeight
            if i <= 2 then
                w = w * math.max(0.3, 1 - luck)
            else
                w = w * (1 + luck * (i - 2))
                if luckyStarVal > 0 then
                    w = w * (1 + luckyStarVal)
                end
            end
            if not isBoss and mobMul[i] then
                w = w * mobMul[i]
            end
            weights[i] = w
            totalWeight = totalWeight + w
        end
        local roll = math.random() * totalWeight
        local qualityIdx = 1
        local acc = 0
        for i, w in ipairs(weights) do
            acc = acc + w
            if roll <= acc then qualityIdx = i; break end
        end

        local slotIdx = math.random(1, #Config.EQUIP_SLOTS)
        local slotCfg = Config.EQUIP_SLOTS[slotIdx]
        local quality = Config.EQUIP_QUALITY[qualityIdx]
        local chapter = overrideChapter or (GS.stage and GS.stage.chapter or 1)
        local itemPower = calcItemPower(chapter, qualityIdx, 0)
        local setId = nil  -- v12: 套装不再从普通掉落产出，改为套装秘境掉落
        local affixes = rollNewAffixes(slotCfg.id, qualityIdx, itemPower)

        local item = {
            slot = slotCfg.id, slotName = slotCfg.name,
            qualityIdx = qualityIdx, qualityName = quality.name, qualityColor = quality.color,
            itemPower = itemPower, affixes = affixes,
            setId = setId, upgradeLv = 0,
        }
        -- 主属性 (固有, 不占词缀格)
        local msDef = Config.GetMainStatDef(slotCfg.id)
        if msDef then
            item.mainStatId    = msDef.id
            item.mainStatBase  = msDef.slotBase
            item.mainStatValue = Config.CalcMainStatValue(msDef.slotBase, itemPower)
        end
        item.name = buildItemName(slotCfg, setId)
        addSocketsIfOrange(item)
        return item
    end

    --- 指定参数直接构造装备
    function GS.CreateEquip(qualityIdx, chapter, slotId, forceSetId)
        local quality = Config.EQUIP_QUALITY[qualityIdx]
        if not quality then quality = Config.EQUIP_QUALITY[1]; qualityIdx = 1 end

        local slotCfg
        if slotId then
            for _, sc in ipairs(Config.EQUIP_SLOTS) do
                if sc.id == slotId then slotCfg = sc; break end
            end
        end
        if not slotCfg then
            slotCfg = Config.EQUIP_SLOTS[math.random(1, #Config.EQUIP_SLOTS)]
        end

        local itemPower = calcItemPower(chapter, qualityIdx, 0)
        local setId = forceSetId or nil  -- v12: 仅通过 forceSetId 指定套装
        local affixes = rollNewAffixes(slotCfg.id, qualityIdx, itemPower)

        local item = {
            slot = slotCfg.id, slotName = slotCfg.name,
            qualityIdx = qualityIdx, qualityName = quality.name, qualityColor = quality.color,
            itemPower = itemPower, affixes = affixes,
            setId = setId, upgradeLv = 0,
        }
        -- 主属性 (固有, 不占词缀格)
        local msDef = Config.GetMainStatDef(slotCfg.id)
        if msDef then
            item.mainStatId    = msDef.id
            item.mainStatBase  = msDef.slotBase
            item.mainStatValue = Config.CalcMainStatValue(msDef.slotBase, itemPower)
        end
        item.name = buildItemName(slotCfg, setId)
        addSocketsIfOrange(item)
        return item
    end
end

return M
