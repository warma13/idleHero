-- ============================================================================
-- ui/ShopPage.lua - 商店页 (药水 + 装备锻造 双Tab)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local SaveSystem = require("SaveSystem")
local ManualSave = require("ManualSave")
local Colors = require("ui.Colors")
local Toast = require("ui.Toast")
local Utils = require("Utils")

local ShopPage = {}

---@type Widget
local page_ = nil
local currentTab_ = "potion"  -- "potion" | "equip"

-- 锻造状态
local selectedSegment_ = 1
local lockedSlotId_ = nil  -- nil=随机
local needRebuild_ = true  -- 标记是否需要完整重建
local lastTab_ = "potion"  -- 上次渲染的tab

-- 抽卡动画状态
local gachaOverlay_ = nil
local gachaItem_ = nil
local gachaPhase_ = 0       -- 0=无 1=翻转中 2=展示
local gachaTimer_ = 0

-- 锻造确认框状态 (会话级，不持久化)
local forgeConfirmOverlay_ = nil
local dontAskForge_ = false      -- 本次登录不再提示
local pendingForgeAction_ = nil   -- 暂存锻造回调

-- ============================================================================
-- 辅助 (药水)
-- ============================================================================

local function getPotionCost(typeId, sizeIdx)
    local baseCost = Config.POTION_BASE_COST[typeId] or 0
    local sizeCfg = Config.POTION_SIZES[sizeIdx]
    if not sizeCfg then return 0 end
    return math.floor(baseCost * sizeCfg.costMul)
end

local function getIconPath(typeId, sizeId)
    local key = typeId .. "_" .. sizeId
    return Config.POTION_ICONS[key]
end

-- ============================================================================
-- Tab 栏
-- ============================================================================

local function createTabBar()
    local function tabBtn(label, tabId)
        local isActive = currentTab_ == tabId
        return UI.Button {
            id = "shop_tab_" .. tabId,
            flexGrow = 1, flexBasis = 0, height = 32,
            borderRadius = 6,
            backgroundColor = isActive and { 60, 110, 230, 255 } or { 40, 44, 58, 180 },
            alignItems = "center", justifyContent = "center",
            onClick = function()
                if currentTab_ ~= tabId then
                    currentTab_ = tabId
                    ShopPage.MarkDirty()
                end
            end,
            children = {
                UI.Label {
                    id = "shop_tab_label_" .. tabId,
                    text = label,
                    fontSize = 13,
                    fontColor = isActive and { 255, 255, 255, 255 } or { 160, 165, 180, 230 },
                },
            },
        }
    end
    return UI.Panel {
        id = "shop_tabbar",
        width = "100%", flexDirection = "row", gap = 6,
        paddingLeft = 10, paddingRight = 10, paddingBottom = 6,
        children = {
            tabBtn("药水", "potion"),
            tabBtn("装备锻造", "equip"),
        },
    }
end

-- ============================================================================
-- 资源栏
-- ============================================================================

local function createResourceBar()
    return UI.Panel {
        id = "shop_resource_bar",
        width = "100%",
        flexDirection = "row", justifyContent = "flex-end", alignItems = "center", gap = 10,
        paddingLeft = 10, paddingRight = 10, paddingTop = 4, paddingBottom = 2,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    UI.Panel { width = 12, height = 12, backgroundImage = Config.GOLD_ICON, backgroundFit = "contain" },
                    UI.Label { id = "shop_gold", text = Utils.FormatNumber(GameState.player.gold), fontSize = 11, fontColor = { 255, 215, 0, 230 } },
                },
            },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    UI.Panel { width = 12, height = 12, backgroundImage = "Textures/icon_stone.png", backgroundFit = "contain" },
                    UI.Label { id = "shop_stone", text = Utils.FormatNumber(GameState.GetMaterial("iron")), fontSize = 11, fontColor = { 160, 200, 255, 230 } },
                },
            },
        },
    }
end

-- ============================================================================
-- 药水Tab
-- ============================================================================

local function createPotionTab()
    local children = {}

    for _, pt in ipairs(Config.POTION_TYPES) do
        -- 类型标题
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center", gap = 4,
            marginTop = 4, marginBottom = 2,
            children = {
                UI.Label { text = pt.name, fontSize = 12, fontColor = { pt.color[1], pt.color[2], pt.color[3], 255 } },
                UI.Label { text = pt.statDesc or "", fontSize = 9, fontColor = Colors.textDim },
            },
        })

        -- 三瓶一行
        local cardChildren = {}
        for sizeIdx, sizeCfg in ipairs(Config.POTION_SIZES) do
            local cost = getPotionCost(pt.id, sizeIdx)
            local iconPath = getIconPath(pt.id, sizeCfg.id)
            local canAfford = GameState.player.gold >= cost

            local baseValue = Config.POTION_VALUES[pt.id] or 0
            local hpMul = Config.HP_POTION_MUL and Config.HP_POTION_MUL[sizeCfg.id]
            local tierValue = baseValue * ((pt.id == "hp" and hpMul) and hpMul or sizeCfg.valueMul)
            local tierTimer = GameState.GetPotionTierTimer(pt.id, tierValue)
            local tierTimeStr = tierTimer > 0 and GameState.FormatSeconds(tierTimer) or nil

            local durMin = math.floor(sizeCfg.duration / 60)
            local effectBrief = "+" .. math.floor(tierValue * 100) .. "%"

            -- 动态元素 ID: potion_timer_{typeId}_{sizeIdx}, potion_btn_{typeId}_{sizeIdx}, potion_cost_{typeId}_{sizeIdx}
            local timerId = "potion_timer_" .. pt.id .. "_" .. sizeIdx
            local btnId = "potion_btn_" .. pt.id .. "_" .. sizeIdx
            local costId = "potion_cost_" .. pt.id .. "_" .. sizeIdx

            table.insert(cardChildren, UI.Panel {
                flexGrow = 1, flexBasis = 0,
                backgroundColor = Colors.cardBg,
                borderRadius = 6, padding = 6, gap = 3,
                alignItems = "center",
                children = {
                    iconPath and UI.Panel {
                        width = 36, height = 36,
                        backgroundImage = iconPath, backgroundFit = "contain",
                    } or UI.Panel {
                        width = 36, height = 36,
                        backgroundColor = { pt.color[1], pt.color[2], pt.color[3], 100 },
                        borderRadius = 6, alignItems = "center", justifyContent = "center",
                        children = { UI.Label { text = sizeCfg.name, fontSize = 14, fontColor = Colors.text } },
                    },
                    UI.Label { text = sizeCfg.name .. "瓶", fontSize = 11, fontColor = Colors.text },
                    UI.Label { text = effectBrief .. " " .. durMin .. "分", fontSize = 9, fontColor = Colors.textDim },
                    -- 计时器（有ID，动态更新）
                    UI.Label {
                        id = timerId,
                        text = tierTimeStr or "",
                        fontSize = 8,
                        fontColor = { 255, 200, 80, 230 },
                        height = tierTimeStr and nil or 10,
                    },
                    -- 购买按钮（有ID，动态更新颜色）
                    UI.Button {
                        id = btnId,
                        width = "100%", height = 24, borderRadius = 4,
                        backgroundColor = canAfford and { 50, 100, 220, 255 } or { 60, 65, 80, 180 },
                        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 2,
                        onClick = Utils.Debounce((function(tid, sidx, ptName, sizeName)
                            return function()
                                local cst = getPotionCost(tid, sidx)
                                if GameState.player.gold < cst then
                                    Toast.Warn("金币不足")
                                    return
                                end
                                local ok, err = GameState.BuyPotion(tid, sidx)
                                if ok then
                                    SaveSystem.MarkDirty()
                                    PlaySFX("audio/sfx/sfx_potion_drink.ogg", 0.6)
                                    Toast.Success(sizeName .. "瓶" .. ptName .. " 已激活")
                                    ShopPage.MarkDirty()
                                elseif err then
                                    Toast.Warn(err)
                                end
                            end
                        end)(pt.id, sizeIdx, pt.name, sizeCfg.name), 0.5),
                        children = {
                            UI.Label { id = costId, text = tostring(cost), fontSize = 9, fontColor = canAfford and { 255, 255, 255, 255 } or { 140, 140, 140, 200 } },
                            UI.Panel { width = 10, height = 10, backgroundImage = Config.GOLD_ICON, backgroundFit = "contain" },
                        },
                    },
                },
            })
        end

        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6,
            children = cardChildren,
        })
    end

    return UI.Panel { width = "100%", gap = 6, children = children }
end

-- ============================================================================
-- 装备锻造Tab
-- ============================================================================

local function createSegmentSelector()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local maxSt = GameState.records and GameState.records.maxStage or 1

    -- 构建下拉选项
    local options = {}
    local selectedValue = nil
    for _, seg in ipairs(Config.FORGE_SEGMENTS) do
        local scaleMul, bossCh = Config.GetForgeSegmentScaleMul(seg.id, maxCh, maxSt)
        local unlocked = scaleMul ~= nil
        if unlocked then
            local label = seg.name .. "  T" .. bossCh .. " Ch" .. seg.chapterRange[1] .. "-" .. seg.chapterRange[2]
            table.insert(options, { value = tostring(seg.id), label = label })
            if selectedSegment_ == seg.id then
                selectedValue = tostring(seg.id)
            end
        end
    end

    -- 若当前选中段未解锁，自动选第一个已解锁的
    if not selectedValue and #options > 0 then
        selectedValue = options[1].value
        selectedSegment_ = tonumber(selectedValue)
    end

    return UI.Dropdown {
        width = "100%",
        placeholder = "选择分段...",
        options = options,
        value = selectedValue,
        onChange = function(_, value)
            selectedSegment_ = tonumber(value) or 1
            ShopPage.MarkDirty()
        end,
    }
end

local function createSlotSelector()
    local slotChildren = {}

    -- "随机"按钮
    local randomSelected = lockedSlotId_ == nil
    table.insert(slotChildren, UI.Button {
        height = 32, borderRadius = 4,
        paddingLeft = 10, paddingRight = 10,
        backgroundColor = randomSelected and { 60, 180, 120, 220 } or { 50, 55, 70, 160 },
        alignItems = "center", justifyContent = "center",
        onClick = function()
            lockedSlotId_ = nil
            ShopPage.MarkDirty()
        end,
        children = {
            UI.Label { text = "随机", fontSize = 10, fontColor = randomSelected and { 255, 255, 255, 255 } or { 160, 165, 180, 200 } },
        },
    })

    for _, slotCfg in ipairs(Config.EQUIP_SLOTS) do
        local isLocked = lockedSlotId_ == slotCfg.id
        local btnChildren = {
            UI.Label {
                text = slotCfg.name,
                fontSize = 10,
                fontColor = isLocked and { 255, 255, 255, 255 } or { 160, 165, 180, 200 },
            },
        }
        if isLocked then
            table.insert(btnChildren, UI.Label { text = "锁定", fontSize = 7, fontColor = { 255, 230, 150, 220 } })
        end
        table.insert(slotChildren, UI.Button {
            height = 32, borderRadius = 4,
            paddingLeft = 10, paddingRight = 10,
            backgroundColor = isLocked and { 220, 160, 50, 220 } or { 50, 55, 70, 160 },
            alignItems = "center", justifyContent = "center",
            onClick = function()
                lockedSlotId_ = slotCfg.id
                ShopPage.MarkDirty()
            end,
            children = btnChildren,
        })
    end

    return UI.Panel {
        width = "100%", gap = 4, marginBottom = 8,
        children = {
            UI.Label { text = "部位选择", fontSize = 11, fontColor = Colors.textDim, marginBottom = 2 },
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 4, flexWrap = "wrap",
                children = slotChildren,
            },
        },
    }
end

-- ============================================================================
-- 锻造执行 & 确认框
-- ============================================================================

--- 实际执行锻造逻辑
local function executeForge()
    local item, err = GameState.ForgeEquip(selectedSegment_, lockedSlotId_)
    if item then
        -- 先入袋再保存，防止刷新丢装备
        local added = GameState.AddToInventory(item)
        -- 锻造成功后立即强制存档，防止 SL
        SaveSystem.SaveNow()       -- 覆盖自动存档（本地+云）
        ManualSave.Save()          -- 覆盖手动存档（云端）
        PlaySFX("audio/sfx/sfx_purchase.ogg", 0.7)
        if added then
            ShopPage.ShowGacha(item)
        else
            Toast.Warn("背包已满，装备已丢弃")
        end
    elseif err then
        Toast.Warn(err)
    end
    ShopPage.MarkDirty()
end

--- 显示锻造确认框
local function showForgeConfirm()
    if not forgeConfirmOverlay_ then return end

    local dontAskChecked = false

    forgeConfirmOverlay_:ClearChildren()
    forgeConfirmOverlay_:AddChild(UI.Panel {
        width = "100%",
        paddingLeft = 20, paddingRight = 20,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = { 25, 30, 45, 250 },
                borderColor = { 80, 90, 120, 180 },
                borderWidth = 1, borderRadius = 10,
                padding = 16, gap = 12,
                alignItems = "center",
                children = {
                    UI.Label { text = "确认锻造", fontSize = 15, fontColor = { 255, 220, 100, 255 } },
                    UI.Label { text = "锻造将消耗资源，确定继续吗？", fontSize = 12, fontColor = { 200, 205, 220, 220 } },
                    UI.Label { text = "会覆盖云端备份，不可恢复", fontSize = 11, fontColor = { 255, 100, 80, 230 } },
                    -- 勾选框行
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        marginTop = 4,
                        onClick = function()
                            dontAskChecked = not dontAskChecked
                            local box = forgeConfirmOverlay_:FindById("forge_confirm_checkbox")
                            if box then
                                box:SetStyle({
                                    backgroundColor = dontAskChecked
                                        and { 60, 110, 230, 255 }
                                        or { 50, 55, 70, 200 },
                                })
                            end
                            local mark = forgeConfirmOverlay_:FindById("forge_confirm_checkmark")
                            if mark then
                                mark:SetText(dontAskChecked and "✓" or "")
                            end
                        end,
                        children = {
                            UI.Panel {
                                id = "forge_confirm_checkbox",
                                width = 18, height = 18,
                                backgroundColor = { 50, 55, 70, 200 },
                                borderColor = { 100, 110, 140, 180 },
                                borderWidth = 1, borderRadius = 4,
                                alignItems = "center", justifyContent = "center",
                                children = {
                                    UI.Label { id = "forge_confirm_checkmark", text = "", fontSize = 13, fontColor = { 255, 255, 255, 255 } },
                                },
                            },
                            UI.Label { text = "本次登录不再提示", fontSize = 11, fontColor = { 160, 165, 180, 200 } },
                        },
                    },
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row", gap = 10, width = "100%", marginTop = 4,
                        children = {
                            UI.Button {
                                text = "确定锻造", height = 34, fontSize = 13,
                                flexGrow = 1, flexBasis = 0,
                                backgroundColor = { 220, 160, 40, 255 },
                                onClick = function()
                                    if dontAskChecked then
                                        dontAskForge_ = true
                                    end
                                    forgeConfirmOverlay_:SetVisible(false)
                                    executeForge()
                                end,
                            },
                            UI.Button {
                                text = "取消", height = 34, fontSize = 13,
                                flexGrow = 1, flexBasis = 0,
                                backgroundColor = { 60, 65, 80, 200 },
                                onClick = function()
                                    forgeConfirmOverlay_:SetVisible(false)
                                end,
                            },
                        },
                    },
                },
            },
        },
    })
    forgeConfirmOverlay_:SetVisible(true)
end

--- 锻造按钮点击入口：检查是否需要确认
local function onForgeClick()
    if dontAskForge_ then
        executeForge()
    else
        showForgeConfirm()
    end
end

local function createForgeButton()
    local forgeInfo = GameState.GetForgeInfo()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local maxSt = GameState.records and GameState.records.maxStage or 1
    local scaleMul = Config.GetForgeSegmentScaleMul(selectedSegment_, maxCh, maxSt)

    -- 消耗计算
    local lockSlot = lockedSlotId_ ~= nil
    local goldCost = 0
    local costLabel = "免费"

    local matCost = nil
    if not forgeInfo.isFree then
        if scaleMul then
            goldCost = Config.GetForgeGoldCost(scaleMul, lockSlot)
            matCost = Config.GetForgeMaterialCost(lockSlot)
        end
        -- 构建材料消耗描述
        local matParts = {}
        if matCost then
            for matId, amt in pairs(matCost) do
                local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                local name = def and def.name or matId
                table.insert(matParts, amt .. name)
            end
        end
        costLabel = table.concat(matParts, "+") .. " + " .. goldCost .. "金"
    end

    local canForge = forgeInfo.remaining > 0 and scaleMul ~= nil
    if not forgeInfo.isFree and scaleMul then
        if GameState.player.gold < goldCost or not GameState.HasMaterials(matCost) then
            canForge = false
        end
    end
    -- 免费不能锁定
    if forgeInfo.isFree and lockedSlotId_ then
        canForge = false
    end

    -- 剩余次数显示
    local remainText = "剩余 " .. forgeInfo.remaining .. "/" .. Config.FORGE_TOTAL_PER_DAY
    if forgeInfo.isFree then
        remainText = remainText .. " (本次免费)"
    end

    -- 免费锁定警告
    local warnLabel = nil
    if forgeInfo.isFree and lockedSlotId_ then
        warnLabel = UI.Label {
            text = "免费锻造不能锁定部位",
            fontSize = 9, fontColor = { 255, 120, 80, 230 },
            marginBottom = 4,
        }
    end

    -- 构建 children（避免 nil 空洞导致后续元素丢失）
    local forgeChildren = {
        -- 消耗显示
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label { id = "forge_cost", text = "消耗: " .. costLabel, fontSize = 11, fontColor = Colors.text },
                UI.Label { id = "forge_remain", text = remainText, fontSize = 10, fontColor = { 180, 185, 200, 200 } },
            },
        },
    }

    if warnLabel then
        table.insert(forgeChildren, warnLabel)
    end

    -- 锻造按钮
    table.insert(forgeChildren, UI.Button {
        width = "100%", height = 40, borderRadius = 8,
        variant = "primary",
        disabled = not canForge,
        backgroundColor = canForge
            and { 220, 160, 40, 255 }
            or { 60, 65, 80, 180 },
        disabledBackgroundColor = { 60, 65, 80, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = Utils.Debounce(onForgeClick, 0.8),
        children = {
            UI.Label {
                text = forgeInfo.isFree and "免费锻造" or "锻造",
                fontSize = 15,
                fontColor = canForge and { 60, 30, 0, 255 } or { 140, 140, 140, 200 },
            },
        },
    })

    -- 说明
    table.insert(forgeChildren, UI.Label {
        text = "固定橙色品质 · 通用套装 · 部位"
            .. (lockedSlotId_ and "锁定(双倍消耗)" or "随机"),
        fontSize = 9, fontColor = Colors.textDim,
    })

    return UI.Panel {
        width = "100%", alignItems = "center", gap = 6, marginTop = 4,
        children = forgeChildren,
    }
end

local function createEquipTab()
    return UI.Panel {
        width = "100%", gap = 4, paddingBottom = 60,
        children = {
            UI.Label { text = "装备锻造", fontSize = 14, fontColor = Colors.text, marginBottom = 4 },
            -- 分段选择
            UI.Label { text = "选择分段", fontSize = 11, fontColor = Colors.textDim, marginBottom = 2 },
            createSegmentSelector(),
            -- 部位选择
            createSlotSelector(),
            -- 锻造按钮区
            createForgeButton(),
        },
    }
end

-- ============================================================================
-- 抽卡动画 (Gacha Overlay)
-- ============================================================================

function ShopPage.ShowGacha(item)
    gachaItem_ = item
    gachaPhase_ = 1
    gachaTimer_ = 0
    ShopPage.RenderGachaOverlay()
end

function ShopPage.RenderGachaOverlay()
    if not gachaItem_ and gachaOverlay_ then
        gachaOverlay_:SetVisible(false)
        return
    end
    if not gachaItem_ then return end

    local item = gachaItem_
    local c = item.qualityColor or { 255, 165, 0 }
    local headerBg = { math.floor(c[1] * 0.25 + 20), math.floor(c[2] * 0.25 + 20), math.floor(c[3] * 0.25 + 20), 250 }

    -- === 构建装备详情卡（复用 InventoryCompare.BuildDetailCard 的样式） ===
    local children = {}

    -- 装备图标 + 名称横排
    local iconPath = Config.GetEquipSlotIcon(item.slot, item.setId)
    local nameText = item.name or ""
    local nameRow = {}
    if iconPath and iconPath ~= "" then
        table.insert(nameRow, UI.Panel {
            width = 36, height = 36,
            backgroundColor = { c[1], c[2], c[3], 30 },
            borderColor = { c[1], c[2], c[3], 80 },
            borderWidth = 1, borderRadius = 6,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Panel {
                    width = 28, height = 28,
                    backgroundImage = iconPath,
                    backgroundFit = "contain",
                    pointerEvents = "none",
                },
            },
        })
    end
    table.insert(nameRow, UI.Label { text = nameText, fontSize = 13, fontColor = { c[1], c[2], c[3], 255 }, fontWeight = "bold" })
    table.insert(children, UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6,
        children = nameRow,
    })

    -- IP + 品质
    local ip = item.itemPower or 0
    table.insert(children, UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 8, marginTop = 2,
        children = {
            UI.Label { text = "IP " .. ip, fontSize = 10, fontColor = { 255, 215, 0, 230 } },
            UI.Label { text = item.qualityName or "", fontSize = 9, fontColor = { c[1], c[2], c[3], 180 } },
            UI.Label { text = item.slotName or "", fontSize = 9, fontColor = { 180, 185, 200, 200 } },
        },
    })

    -- (v4.0: 武器元素显示已移除)

    -- 分隔线
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 70, 90, 120 }, marginTop = 4, marginBottom = 2 })

    -- 词缀列表
    if item.affixes and #item.affixes > 0 then
        for _, aff in ipairs(item.affixes) do
            local def = Config.AFFIX_POOL_MAP[aff.id] or Config.EQUIP_STATS[aff.id]
            if def then
                local valStr = GameState.FormatStatValue(aff.id, aff.value)
                local greaterMark = aff.greater and " *" or ""
                local fc = aff.greater and { 255, 180, 60, 240 } or { 190, 195, 200, 210 }
                table.insert(children, UI.Label { text = def.name .. " " .. valStr .. greaterMark, fontSize = 9, fontColor = fc })
            end
        end
    end

    -- 套装效果
    if item.setId then
        local setCfg = Config.EQUIP_SET_MAP[item.setId]
        if setCfg then
            local sc = setCfg.color
            table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 70, 90, 120 }, marginTop = 4, marginBottom = 2 })
            table.insert(children, UI.Label { text = setCfg.name, fontSize = 9, fontColor = { sc[1], sc[2], sc[3], 230 }, fontWeight = "bold" })
            local setCounts = GameState.GetEquippedSetCounts and GameState.GetEquippedSetCounts() or {}
            local curCount = setCounts[item.setId] or 0
            local thresholds = {}
            for k, _ in pairs(setCfg.bonuses) do table.insert(thresholds, k) end
            table.sort(thresholds)
            for _, threshold in ipairs(thresholds) do
                local bonus = setCfg.bonuses[threshold]
                local activated = curCount >= threshold
                local fc = activated
                    and { sc[1], sc[2], sc[3], 255 }
                    or  { 100, 105, 115, 140 }
                table.insert(children, UI.Label {
                    text = "(" .. threshold .. "件) " .. bonus.desc,
                    fontSize = 8, fontColor = fc,
                })
            end
        end
    end

    -- 详情卡面板
    local detailCard = UI.Panel {
        width = "100%",
        padding = 10, gap = 2,
        children = children,
    }

    -- 操作按钮行
    local actionRow = UI.Panel {
        flexDirection = "row", gap = 8, width = "100%",
        paddingLeft = 8, paddingRight = 8, paddingBottom = 8,
        children = {
            UI.Button {
                text = "确认（已在背包）",
                height = 32, fontSize = 13,
                flexGrow = 1, flexBasis = 0,
                backgroundColor = { 50, 140, 70, 240 },
                onClick = function()
                    if gachaItem_ then
                        Toast.Success("已放入背包")
                        gachaItem_ = nil
                        gachaPhase_ = 0
                        if gachaOverlay_ then gachaOverlay_:SetVisible(false) end
                        ShopPage.MarkDirty()
                    end
                end,
            },
            UI.Button {
                text = "直接分解",
                height = 32, fontSize = 12,
                flexGrow = 1, flexBasis = 0,
                backgroundColor = { 140, 50, 50, 220 },
                onClick = function()
                    if gachaItem_ then
                        -- 从背包中找到并移除该装备
                        for i, inv in ipairs(GameState.inventory) do
                            if inv == gachaItem_ then
                                table.remove(GameState.inventory, i)
                                break
                            end
                        end
                        local mats = Config.DECOMPOSE_MATERIALS[gachaItem_.qualityIdx]
                        if mats then GameState.AddMaterials(mats) end
                        -- 金币产出
                        local dGold = Config.DECOMPOSE_GOLD[gachaItem_.qualityIdx] or 0
                        if dGold > 0 then GameState.AddGold(dGold) end
                        -- 构建分解结果描述
                        local matParts = {}
                        if dGold > 0 then table.insert(matParts, dGold .. "金币") end
                        if mats then
                            for matId, amt in pairs(mats) do
                                local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                                table.insert(matParts, amt .. (def and def.name or matId))
                            end
                        end
                        Toast.Success("已分解，获得 " .. table.concat(matParts, " + "))
                        gachaItem_ = nil
                        gachaPhase_ = 0
                        if gachaOverlay_ then gachaOverlay_:SetVisible(false) end
                        SaveSystem.SaveNow()
                        ShopPage.MarkDirty()
                    end
                end,
            },
        },
    }

    -- 组装整个面板（与装备详情面板一致的结构）
    local panelChildren = {
        -- 标题栏
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            width = "100%",
            backgroundColor = headerBg,
            paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
            children = {
                UI.Label { text = "锻造结果", fontSize = 12, fontColor = { 200, 210, 230, 245 } },
                UI.Panel {
                    width = 24, height = 24,
                    backgroundColor = { 160, 50, 50, 200 },
                    borderRadius = 12,
                    alignItems = "center", justifyContent = "center",
                    onClick = function()
                        if gachaItem_ then
                            gachaItem_ = nil
                            gachaPhase_ = 0
                        end
                        if gachaOverlay_ then gachaOverlay_:SetVisible(false) end
                        ShopPage.MarkDirty()
                    end,
                    children = {
                        UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                    },
                },
            },
        },
        -- 装备详情卡
        detailCard,
        -- 操作按钮
        actionRow,
    }

    -- 覆盖层
    if gachaOverlay_ then
        gachaOverlay_:ClearChildren()
        -- 居中容器
        gachaOverlay_:AddChild(UI.Panel {
            width = "100%",
            paddingLeft = 8, paddingRight = 8,
            children = {
                UI.Panel {
                    width = "100%",
                    backgroundColor = { 18, 22, 34, 245 },
                    borderColor = { c[1], c[2], c[3], 200 },
                    borderWidth = 1, borderRadius = 8,
                    gap = 4,
                    overflow = "hidden",
                    children = panelChildren,
                },
            },
        })
        gachaOverlay_:SetVisible(true)
    end
end

-- ============================================================================
-- 创建 & 刷新
-- ============================================================================

function ShopPage.Create()
    -- 抽卡覆盖层（固定在最外层）
    gachaOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 200 },
        alignItems = "center", justifyContent = "center",
        visible = false,
        onPointerDown = function() end,  -- 阻止穿透
        onPointerUp = function() end,
    }

    -- 锻造确认覆盖层
    forgeConfirmOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        visible = false,
        onPointerDown = function() end,
        onPointerUp = function() end,
    }

    page_ = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0,
        children = {
            -- 固定顶部：资源栏
            createResourceBar(),
            -- 固定顶部：Tab 栏
            createTabBar(),
            -- 可滚动内容区
            UI.ScrollView {
                id = "shop_scroll",
                width = "100%", flexGrow = 1, flexBasis = 0,
                padding = 10,
                onPointerDown = function() end,
                onPointerUp = function() end,
                children = {
                    UI.Panel { id = "shop_scroll_content", width = "100%", gap = 4 },
                },
            },
            gachaOverlay_,
            forgeConfirmOverlay_,
        },
    }

    -- 每次 Create 都必须完整重建内容
    needRebuild_ = true
    ShopPage.Refresh()
    return page_
end

--- 标记需要完整重建（切Tab、锻造操作等主动行为调用此方法）
function ShopPage.MarkDirty()
    needRebuild_ = true
    ShopPage.Refresh()
end

-- ============================================================================
-- 分层刷新：动态更新函数（不重建结构，只更新文本/颜色）
-- ============================================================================

--- 第1层：共享资源文本（金币、强化石）
local function updateResourceText()
    local goldLabel = page_:FindById("shop_gold")
    if goldLabel then goldLabel:SetText(Utils.FormatNumber(GameState.player.gold)) end
    local stoneLabel = page_:FindById("shop_stone")
    if stoneLabel then stoneLabel:SetText(Utils.FormatNumber(GameState.GetMaterial("iron"))) end
end

--- 第2层-药水：更新计时器 + 按钮状态
local function updatePotionDynamic()
    local gold = GameState.player.gold
    for _, pt in ipairs(Config.POTION_TYPES) do
        for sizeIdx, sizeCfg in ipairs(Config.POTION_SIZES) do
            local suffix = pt.id .. "_" .. sizeIdx

            -- 计时器
            local timerLabel = page_:FindById("potion_timer_" .. suffix)
            if timerLabel then
                local baseValue = Config.POTION_VALUES[pt.id] or 0
                local hpMul = Config.HP_POTION_MUL and Config.HP_POTION_MUL[sizeCfg.id]
                local tierValue = baseValue * ((pt.id == "hp" and hpMul) and hpMul or sizeCfg.valueMul)
                local tierTimer = GameState.GetPotionTierTimer(pt.id, tierValue)
                if tierTimer > 0 then
                    timerLabel:SetText(GameState.FormatSeconds(tierTimer))
                    timerLabel:SetHeight(nil)
                else
                    timerLabel:SetText("")
                    timerLabel:SetHeight(10)
                end
            end

            -- 按钮颜色
            local cost = getPotionCost(pt.id, sizeIdx)
            local canAfford = gold >= cost
            local btn = page_:FindById("potion_btn_" .. suffix)
            if btn then
                btn:SetStyle({ backgroundColor = canAfford and { 50, 100, 220, 255 } or { 60, 65, 80, 180 } })
            end
            -- 按钮内文字颜色
            local costLabel = page_:FindById("potion_cost_" .. suffix)
            if costLabel then
                costLabel:SetFontColor(canAfford and { 255, 255, 255, 255 } or { 140, 140, 140, 200 })
            end
        end
    end
end

--- 第2层-装备：更新消耗和剩余次数文本
local function updateForgeDynamic()
    local forgeInfo = GameState.GetForgeInfo()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local maxSt = GameState.records and GameState.records.maxStage or 1
    local scaleMul = Config.GetForgeSegmentScaleMul(selectedSegment_, maxCh, maxSt)

    local lockSlot = lockedSlotId_ ~= nil
    local costLabel = "免费"
    if not forgeInfo.isFree then
        if scaleMul then
            local goldCost = Config.GetForgeGoldCost(scaleMul, lockSlot)
            local matCost = Config.GetForgeMaterialCost(lockSlot)
            local matParts = {}
            if matCost then
                for matId, amt in pairs(matCost) do
                    local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                    table.insert(matParts, amt .. (def and def.name or matId))
                end
            end
            costLabel = table.concat(matParts, "+") .. " + " .. goldCost .. "金"
        end
    end

    local remainText = "剩余 " .. forgeInfo.remaining .. "/" .. Config.FORGE_TOTAL_PER_DAY
    if forgeInfo.isFree then
        remainText = remainText .. " (本次免费)"
    end

    local costEl = page_:FindById("forge_cost")
    if costEl then costEl:SetText("消耗: " .. costLabel) end
    local remainEl = page_:FindById("forge_remain")
    if remainEl then remainEl:SetText(remainText) end
end

-- ============================================================================
-- Refresh 入口：分层刷新
-- ============================================================================

--- 更新 Tab 栏高亮状态（通过 ID 动态更新，不重建）
local function updateTabHighlight()
    for _, tabId in ipairs({ "potion", "equip" }) do
        local isActive = currentTab_ == tabId
        local btn = page_:FindById("shop_tab_" .. tabId)
        if btn then
            btn:SetStyle({ backgroundColor = isActive and { 60, 110, 230, 255 } or { 40, 44, 58, 180 } })
        end
        local lbl = page_:FindById("shop_tab_label_" .. tabId)
        if lbl then
            lbl:SetFontColor(isActive and { 255, 255, 255, 255 } or { 160, 165, 180, 230 })
        end
    end
end

function ShopPage.Refresh()
    if not page_ then return end

    -- Tab 切换时需要重建内容 + 更新 tab 高亮
    if currentTab_ ~= lastTab_ then
        needRebuild_ = true
        lastTab_ = currentTab_
        updateTabHighlight()
    end

    -- 第3层：结构重建（仅重建 scroll 内部内容）
    if needRebuild_ then
        needRebuild_ = false

        local content = page_:FindById("shop_scroll_content")
        if not content then return end
        content:ClearChildren()

        if currentTab_ == "potion" then
            content:AddChild(createPotionTab())
        else
            content:AddChild(createEquipTab())
        end
    end

    -- 第1层：共享资源文本（每次都执行）
    updateResourceText()

    -- 第2层：当前 tab 的动态更新（每次都执行）
    if currentTab_ == "potion" then
        updatePotionDynamic()
    else
        updateForgeDynamic()
    end
end

function ShopPage.InvalidateCache()
    needRebuild_ = true
end

return ShopPage
