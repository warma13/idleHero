-- ============================================================================
-- ui/InventoryPage.lua - 背包装备页 (六属性装备系统)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local SaveSystem = require("SaveSystem")
local Colors = require("ui.Colors")
local Utils = require("Utils")
local FloatTip = require("ui.FloatTip")

local InventoryPage = {}

---@type Widget
local page_ = nil
---@type Widget
local expandOverlay_ = nil         -- 扩容确认浮层
---@type Widget
local gemExpandOverlay_ = nil      -- 宝石背包扩容确认浮层
---@type Widget
local decompOrangeOverlay_ = nil   -- 分解橙色确认浮层
---@type Widget
local gemDetailOverlay_ = nil      -- 宝石详情浮窗
---@type Widget
local gemDiscardConfirm_ = nil     -- 宝石丢弃确认弹窗
---@type Widget
local matDetailOverlay_ = nil      -- 材料详情浮窗
local matDetailId_ = nil           -- 当前展示的材料 ID（用于 toggle）
---@type Widget
local matDiscardConfirm_ = nil     -- 材料丢弃确认弹窗
local skipGemDiscardConfirm_ = false  -- 本次登录不再提示

local decompPanelVisible_ = false
local decompToggleTime_ = 0
local currentTab_ = "bag"  -- "bag" | "mat" | "gem"

-- 数据快照，用于检测是否需要重建格子
local lastInvCount_ = -1
local lastStoneCount_ = -1
local lastMatKey_ = ""
local lastDecompVis_ = false
local lastAutoDecomp_ = 0
local lastAutoKeepSets_ = true
local lastEquipKey_ = ""

-- 跨模块共享状态 (与 InventoryCompare 子模块共享)
local shared_ = {
    overlayRoot = nil,
    compareOverlay = nil,
    compareSlotId = nil,
    compareInvIdx = nil,
    compareSource = nil,
    gridDirty = false,
}

-- 子模块注入 (对比/详情浮层)
require("ui.InventoryCompare").Install(InventoryPage, shared_)

--- 生成装备栏指纹（slot+品质+强化级），变化时才重建
local function EquipKey()
    local parts = {}
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        local item = GameState.equipment[slot.id]
        if item then
            parts[#parts + 1] = slot.id
            parts[#parts + 1] = tostring(item.qualityIdx or 0)
            parts[#parts + 1] = tostring(item.upgradeLv or 0)
            parts[#parts + 1] = item.setId or ""
            parts[#parts + 1] = item.name or ""
        end
    end
    return table.concat(parts, "|")
end

-- ============================================================================
-- 外部注入浮层容器
-- ============================================================================

--- 由 main.lua 调用，传入 uiRoot 用于挂载浮层
function InventoryPage.SetOverlayRoot(root)
    shared_.overlayRoot = root
end

-- ============================================================================
-- 辅助构建
-- ============================================================================

local function CreateEquipSlotWidget(slotCfg, item)
    local bgColor = item
        and { item.qualityColor[1], item.qualityColor[2], item.qualityColor[3], 40 }
        or  { 40, 48, 60, 200 }
    local borderColor = item
        and { item.qualityColor[1], item.qualityColor[2], item.qualityColor[3], 120 }
        or  { 60, 70, 85, 150 }

    local iconPath = Config.GetEquipSlotIcon(slotCfg.id, item and item.setId)
    if item and item.setId then
        print("[InventoryPage] equip slot=" .. slotCfg.id .. " setId=" .. tostring(item.setId) .. " iconPath=" .. tostring(iconPath))
    end
    local iconProps = {
        width = 28, height = 28,
        backgroundImage = iconPath,
        backgroundFit = "contain",
        pointerEvents = "none",
    }
    if not item then
        iconProps.opacity = 0.3
    end
    local children = { UI.Panel(iconProps) }
    if item then
        local displayName = item.name or slotCfg.name
        if #displayName > 12 then displayName = string.sub(displayName, 1, 12) .. ".." end
        local upgLv = item.upgradeLv or 0
        if upgLv > 0 then displayName = displayName .. " +" .. upgLv end
        table.insert(children, UI.Label { text = displayName, fontSize = 7, fontColor = { item.qualityColor[1], item.qualityColor[2], item.qualityColor[3], 230 }, textAlign = "center", height = 10, pointerEvents = "none" })
        -- 锁定图标（右上角）
        if item.locked then
            table.insert(children, UI.Panel {
                position = "absolute", right = 0, top = 0,
                width = 18, height = 18,
                backgroundImage = "Textures/icon_lock.png",
                backgroundFit = "contain",
                pointerEvents = "none",
            })
        end
    end

    return UI.Panel {
        width = 60, height = 66,
        backgroundImage = "Textures/equip_slot_border.png",
        backgroundFit = "fill",
        alignItems = "center", justifyContent = "center", gap = 2,
        onClick = item and function()
            InventoryPage.ShowCompare(slotCfg.id, nil, "equipped")
        end or nil,
        children = children,
    }
end

local function CreateInvItemWidget(item, index)
    local c = item.qualityColor
    local iconPath = Config.GetEquipSlotIcon(item.slot, item.setId)
    if item.setId then
        print("[InventoryPage] bag slot=" .. tostring(item.slot) .. " setId=" .. tostring(item.setId) .. " iconPath=" .. tostring(iconPath))
    end
    local setIconPath = item.setId and Config.SET_ICON_PATHS[item.setId]

    local invName = item.name or item.slotName
    local invUpgLv = item.upgradeLv or 0
    if invUpgLv > 0 then invName = invName .. " +" .. invUpgLv end
    local children = {
        UI.Panel {
            width = 28, height = 28,
            backgroundImage = iconPath,
            backgroundFit = "contain",
            pointerEvents = "none",
        },
        UI.Label { text = invName, fontSize = 7, fontColor = { c[1], c[2], c[3], 230 }, pointerEvents = "none" },
    }
    if setIconPath then
        table.insert(children, UI.Panel {
            width = 14, height = 14,
            backgroundImage = setIconPath,
            backgroundFit = "contain",
            pointerEvents = "none",
        })
    end

    -- 锁定图标（右上角）
    if item.locked then
        table.insert(children, UI.Panel {
            position = "absolute", right = 0, top = 0,
            width = 16, height = 16,
            backgroundImage = "Textures/icon_lock.png",
            backgroundFit = "contain",
            pointerEvents = "none",
        })
    end

    return UI.Panel {
        width = 56, height = 60,
        backgroundColor = { c[1], c[2], c[3], 30 },
        borderColor = item.locked and { 255, 200, 60, 180 } or { c[1], c[2], c[3], 100 },
        borderWidth = item.locked and 2 or 1, borderRadius = 4,
        alignItems = "center", justifyContent = "center", gap = 1,
        onClick = function()
            InventoryPage.ShowCompare(item.slot, index, "inventory")
        end,
        children = children,
    }
end

-- ============================================================================
-- 创建 & 刷新
-- ============================================================================

function InventoryPage.Create()
    page_ = UI.ScrollView {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        padding = 10,
        children = {
            -- 装备栏
            UI.Panel {
                width = "100%",
                backgroundColor = Colors.cardBg,
                borderRadius = 8, padding = 10, gap = 6, marginBottom = 8,
                children = {
                    UI.Label { text = "装备栏", fontSize = 13, fontColor = Colors.text, marginBottom = 4 },
                    UI.Panel { id = "equip_grid", flexDirection = "row", flexWrap = "wrap", gap = 6, width = "100%" },
                }
            },
            -- 背包 / 宝石 Tab 切换卡片
            UI.Panel {
                width = "100%",
                backgroundColor = Colors.cardBg,
                borderRadius = 8, padding = 10, gap = 6,
                children = {
                    -- Tab 行
                    UI.Panel {
                        id = "bag_gem_tabs",
                        flexDirection = "row", width = "100%", gap = 0,
                    },
                    -- 工具行（背包Tab: 强化石+按钮 / 宝石Tab: 棱镜）
                    UI.Panel { id = "toolbar_row", width = "100%" },
                    -- 分解面板
                    UI.Panel { id = "decomp_panel", width = "100%", marginBottom = 4 },
                    -- 装备格子
                    UI.Panel { id = "inv_grid", flexDirection = "row", flexWrap = "wrap", gap = 4, width = "100%" },
                    -- 材料格子
                    UI.Panel { id = "mat_grid", flexDirection = "row", flexWrap = "wrap", gap = 4, width = "100%" },
                    -- 宝石格子
                    UI.Panel { id = "gem_grid", flexDirection = "row", flexWrap = "wrap", gap = 4, width = "100%" },
                },
            },
        }
    }
    -- 不在此处调用 Refresh()：page_ 尚未挂载到 UI 树，
    -- 此时重建格子会更新快照，导致 switchTab 后的 Refresh() 误判为"无变化"。
    -- 标记 gridDirty，让首次 switchTab 触发完整重建。
    shared_.gridDirty = true
    return page_
end

local lastTab_ = ""

--- 构建 Tab 行
local function RebuildTabs()
    local tabsPanel = page_:FindById("bag_gem_tabs")
    if not tabsPanel then return end
    tabsPanel:ClearChildren()

    local bagText = "背包 " .. #GameState.inventory .. "/" .. GameState.GetInventorySize()
    local gemText = "宝石 " .. GameState.GetGemBagUsedSlots() .. "/" .. GameState.GetGemBagSize()

    -- 统计材料占用格子数（含溢出堆叠）
    local matUsed = 0
    for _, def in ipairs(Config.MATERIAL_DEFS) do
        local amt = GameState.GetMaterial(def.id) or 0
        if amt > 0 then
            matUsed = matUsed + math.ceil(amt / 999)
        end
    end
    local matText = "材料 " .. matUsed .. "/40"

    local tabs = {
        { key = "bag", text = bagText },
        { key = "mat", text = matText },
        { key = "gem", text = gemText },
    }
    for _, tab in ipairs(tabs) do
        local active = currentTab_ == tab.key
        tabsPanel:AddChild(UI.Panel {
            flexGrow = 1, height = 30,
            backgroundColor = active and { 60, 70, 100, 200 } or { 30, 35, 50, 150 },
            borderColor = active and { 100, 120, 200, 220 } or { 50, 60, 75, 100 },
            borderWidth = active and 1 or 0,
            borderRadius = 4,
            alignItems = "center", justifyContent = "center",
            onClick = function()
                if currentTab_ ~= tab.key then
                    currentTab_ = tab.key
                    decompPanelVisible_ = false
                    shared_.gridDirty = true
                    InventoryPage.CloseMatDetail()
                    InventoryPage.Refresh()
                end
            end,
            children = {
                UI.Label { text = tab.text, fontSize = 12, fontColor = active and { 220, 230, 255, 255 } or { 140, 150, 170, 180 }, pointerEvents = "none" },
            },
        })
    end
end

--- 构建工具行（背包Tab: 强化石+按钮 / 宝石Tab: 棱镜）
local function RebuildToolbar()
    local toolbar = page_:FindById("toolbar_row")
    if not toolbar then return end
    toolbar:ClearChildren()

    if currentTab_ == "bag" then
        toolbar:AddChild(UI.Panel {
            flexDirection = "row", gap = 6, width = "100%",
            flexWrap = "wrap", alignItems = "center",
            children = {

                UI.Button {
                    text = "套装", height = 26, fontSize = 11,
                    backgroundColor = { 80, 60, 120, 200 },
                    onClick = Utils.Debounce(function()
                        GameState.SortInventoryBySet()
                        InventoryPage.CloseCompare()
                        shared_.gridDirty = true
                        InventoryPage.Refresh()
                        SaveSystem.MarkDirty()
                    end, 0.3),
                },
                UI.Button {
                    text = "整理", height = 26, fontSize = 11,
                    backgroundColor = { 60, 100, 120, 200 },
                    onClick = Utils.Debounce(function()
                        GameState.SortInventory()
                        InventoryPage.CloseCompare()
                        shared_.gridDirty = true
                        InventoryPage.Refresh()
                        SaveSystem.MarkDirty()
                    end, 0.3),
                },
                UI.Button {
                    text = "一键穿戴", height = 26, fontSize = 11, variant = "primary",
                    onClick = Utils.Debounce(function()
                        local changed = GameState.AutoEquipBest()
                        InventoryPage.CloseCompare()
                        shared_.gridDirty = true
                        InventoryPage.Refresh()
                        if changed then
                            SaveSystem.MarkDirty()
                            require("ui.TabBar").MarkAllDirty()
                        end
                    end, 0.3),
                },
                UI.Button {
                    id = "btn_decomp_toggle",
                    text = "分解装备", height = 26, fontSize = 11,
                    backgroundColor = { 120, 60, 60, 200 },
                    onClick = function()
                        local now = time:GetElapsedTime()
                        if now - decompToggleTime_ < 0.3 then return end
                        decompToggleTime_ = now
                        InventoryPage.CloseCompare()
                        decompPanelVisible_ = not decompPanelVisible_
                        InventoryPage.Refresh()
                    end,
                },
            },
        })
    elseif currentTab_ == "mat" then
        -- 材料Tab: 各材料图标+数量概览
        local matChildren = {}
        for _, def in ipairs(Config.MATERIAL_DEFS) do
            local amt = GameState.GetMaterial(def.id) or 0
            local c = def.color
            table.insert(matChildren, UI.Panel {
                width = 14, height = 14,
                backgroundImage = Config.MATERIAL_ICON_PATHS[def.id],
                backgroundFit = "contain",
            })
            table.insert(matChildren, UI.Label {
                text = Utils.FormatNumber(amt),
                fontSize = 9,
                fontColor = { c[1], c[2], c[3], amt > 0 and 220 or 100 },
                marginRight = 6,
            })
        end
        toolbar:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 2, width = "100%", flexWrap = "wrap",
            children = matChildren,
        })
    else
        -- 宝石Tab: 散光棱镜 (图标+数量)
        local prismCount = GameState.GetBagItemCount("prism")
        if prismCount > 0 then
            toolbar:AddChild(UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, width = "100%",
                children = {
                    UI.Panel { width = 14, height = 14, backgroundImage = "Textures/Items/item_prism.png", backgroundFit = "contain" },
                    UI.Label { text = "×" .. prismCount, fontSize = 10, fontColor = { 180, 200, 240, 180 } },
                },
            })
        end
    end
end

function InventoryPage.Refresh()
    if not page_ then return end

    -- 对比/详情浮层打开时只刷新 Tab 文本，实际数据变化才标脏（避免布局抖动）
    if shared_.compareOverlay then
        local curInvCheck = #GameState.inventory
        local curEquipCheck = EquipKey()
        if curInvCheck ~= lastInvCount_ or curEquipCheck ~= lastEquipKey_ then
            shared_.gridDirty = true
        end
        RebuildTabs()
        -- Tab 切换或 gridDirty 时需要完整重建格子
        if currentTab_ ~= lastTab_ then
            shared_.gridDirty = true
        elseif not shared_.gridDirty then
            return
        end
    end

    -- 检测数据是否有变化，决定是否需要重建格子
    local curInvCount = #GameState.inventory
    local curStoneCount = GameState.GetMaterial("iron")
    local curEquipKey = EquipKey()
    local curDecompVis = decompPanelVisible_
    local curAutoDecomp = table.concat(GameState.autoDecompConfig, ",")

    -- 材料数据快照（各材料数量拼接）
    local matSnap = {}
    for _, def in ipairs(Config.MATERIAL_DEFS) do
        table.insert(matSnap, def.id .. ":" .. (GameState.GetMaterial(def.id) or 0))
    end
    local curMatKey = table.concat(matSnap, ",")

    -- 检测格子是否为空（首次挂载到 UI 树时需要强制构建）
    local equipGrid = page_:FindById("equip_grid")
    local invGrid = page_:FindById("inv_grid")
    local matGrid = page_:FindById("mat_grid")
    local gemGrid = page_:FindById("gem_grid")
    local gridsEmpty = (equipGrid and #equipGrid.children == 0)

    local needRebuild = shared_.gridDirty
        or gridsEmpty
        or curInvCount ~= lastInvCount_
        or curEquipKey ~= lastEquipKey_
        or curDecompVis ~= lastDecompVis_
        or curAutoDecomp ~= lastAutoDecomp_
        or curMatKey ~= lastMatKey_
        or currentTab_ ~= lastTab_

    -- Tab 行始终更新
    RebuildTabs()

    -- 数据没变化，跳过格子重建，保持控件对象稳定
    if not needRebuild then return end

    -- 更新快照
    shared_.gridDirty = false
    lastInvCount_ = curInvCount
    lastStoneCount_ = curStoneCount
    lastMatKey_ = curMatKey
    lastDecompVis_ = curDecompVis
    lastAutoDecomp_ = curAutoDecomp
    lastTab_ = currentTab_

    -- 工具行
    RebuildToolbar()

    -- 装备栏：首次（格子为空）或已装备物品变化时重建
    local equipChanged = curEquipKey ~= lastEquipKey_ or (equipGrid and #equipGrid.children == 0)
    lastEquipKey_ = curEquipKey
    if equipChanged then
        if equipGrid then
            equipGrid:ClearChildren()
            for _, slotCfg in ipairs(Config.EQUIP_SLOTS) do
                equipGrid:AddChild(CreateEquipSlotWidget(slotCfg, GameState.equipment[slotCfg.id]))
            end
        end
    end

    -- 非活跃 Tab 的格子清空（无子元素自然不占空间）
    if invGrid and currentTab_ ~= "bag" then invGrid:ClearChildren() end
    if matGrid and currentTab_ ~= "mat" then matGrid:ClearChildren() end
    if gemGrid and currentTab_ ~= "gem" then gemGrid:ClearChildren() end

    -- 分解筛选面板（仅背包Tab）
    local decompPanel = page_:FindById("decomp_panel")
    if decompPanel then
        decompPanel:ClearChildren()
        if decompPanelVisible_ and currentTab_ == "bag" then
            local qualityNames = {}
            for _, q in ipairs(Config.EQUIP_QUALITY) do
                table.insert(qualityNames, q)
            end

            local rows = {}
            -- 品质筛选按钮 + 自动分解勾选框
            local filterItems = {}
            for qi = 1, #qualityNames do
                table.insert(filterItems, { qIdx = qi, label = qualityNames[qi].name .. "及以下", color = qualityNames[qi].color })
            end

            for _, fi in ipairs(filterItems) do
                local qIdx = fi.qIdx
                local cfgMode = GameState.autoDecompConfig[qIdx] or 0
                local isAutoIncSets = (cfgMode == 1)
                local isAutoKeepSets = (cfgMode == 2)
                local canHaveSet = qualityNames[qIdx].canHaveSet
                table.insert(rows, UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4, width = "100%",
                    children = {
                        UI.Button {
                            text = "分解" .. fi.label,
                            height = 24, fontSize = 9, flexGrow = 1,
                            backgroundColor = { fi.color[1], fi.color[2], fi.color[3], 100 },
                            borderColor = { fi.color[1], fi.color[2], fi.color[3], 180 },
                            borderWidth = 1, borderRadius = 4,
                            onClick = Utils.Debounce(function()
                                if qIdx == #Config.EQUIP_QUALITY then
                                    InventoryPage.ShowDecompOrangeConfirm()
                                    return
                                end
                                local gold, cnt, mats = GameState.DecomposeByFilter(qIdx, false)
                                local matParts = {}
                                if mats then for matId, amt in pairs(mats) do local d = Config.MATERIAL_MAP[matId]; table.insert(matParts, amt .. (d and d.name or matId)) end end
                                print("[UI] 分解: " .. cnt .. "件, " .. gold .. "金, " .. table.concat(matParts, "+"))
                                if cnt > 0 then
                                    FloatTip.Decompose("批量分解 " .. cnt .. " 件 → " .. table.concat(matParts, " + "))
                                    SaveSystem.MarkDirty()
                                end
                                decompPanelVisible_ = false
                                InventoryPage.Refresh()
                            end, 0.5),
                        },
                        UI.Checkbox {
                            checked = isAutoIncSets,
                            label = "自动",
                            size = 14, fontSize = 8,
                            onChange = function(self, checked)
                                if checked and qIdx == #Config.EQUIP_QUALITY then
                                    self:SetChecked(false)
                                    InventoryPage.ShowAutoDecompOrangeConfirm(false)
                                    return
                                end
                                -- 互斥：先清空所有，再设置当前
                                for k = 1, #GameState.autoDecompConfig do
                                    GameState.autoDecompConfig[k] = 0
                                end
                                if checked then GameState.autoDecompConfig[qIdx] = 1 end
                                SaveSystem.MarkDirty()
                                InventoryPage.Refresh()
                            end,
                        },
                        canHaveSet and UI.Checkbox {
                            checked = isAutoKeepSets,
                            label = "留" .. string.sub(fi.label, 1, 3) .. "套",
                            size = 14, fontSize = 8,
                            onChange = function(self, checked)
                                if checked and qIdx == #Config.EQUIP_QUALITY then
                                    self:SetChecked(false)
                                    InventoryPage.ShowAutoDecompOrangeConfirm(true)
                                    return
                                end
                                -- 互斥：先清空所有，再设置当前
                                for k = 1, #GameState.autoDecompConfig do
                                    GameState.autoDecompConfig[k] = 0
                                end
                                if checked then GameState.autoDecompConfig[qIdx] = 2 end
                                SaveSystem.MarkDirty()
                                InventoryPage.Refresh()
                            end,
                        } or nil,
                    },
                })
            end

            decompPanel:AddChild(UI.Panel {
                width = "100%",
                backgroundColor = { 50, 30, 30, 180 },
                borderColor = { 120, 60, 60, 150 },
                borderWidth = 1, borderRadius = 6,
                padding = 8, gap = 6,
                children = {
                    UI.Label { text = "选择分解条件 (勾选\"自动\"可自动分解新掉落)", fontSize = 9, fontColor = { 255, 200, 200, 200 }, marginBottom = 2 },
                    UI.Panel { gap = 4, width = "100%", children = rows },
                },
            })
        end
    end

    -- 背包格子（仅背包Tab时重建）
    if invGrid and currentTab_ == "bag" then
        invGrid:ClearChildren()
        local maxSlots = GameState.GetInventorySize()
        for i, item in ipairs(GameState.inventory) do
            invGrid:AddChild(CreateInvItemWidget(item, i))
        end
        for _ = #GameState.inventory + 1, maxSlots do
            invGrid:AddChild(UI.Panel {
                width = 56, height = 60,
                backgroundColor = { 35, 42, 55, 150 },
                borderColor = { 50, 60, 75, 100 },
                borderWidth = 1, borderRadius = 4,
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Label { text = "-", fontSize = 14, fontColor = { 50, 60, 75, 50 } },
                },
            })
        end
        -- 扩容格子 ("+")
        local expandCost = GameState.GetExpandCost()
        local canExpand = GameState.GetSoulCrystal() >= expandCost
        invGrid:AddChild(UI.Panel {
            width = 56, height = 60,
            backgroundColor = canExpand and { 60, 40, 100, 180 } or { 30, 30, 40, 120 },
            borderColor = canExpand and { 160, 80, 255, 180 } or { 60, 50, 80, 100 },
            borderWidth = 1, borderRadius = 4,
            borderStyle = "dashed",
            alignItems = "center", justifyContent = "center", gap = 1,
            onClick = function()
                InventoryPage.ShowExpandConfirm()
            end,
            children = {
                UI.Label { text = "+", fontSize = 22, fontColor = canExpand and { 160, 80, 255, 230 } or { 80, 70, 100, 150 }, pointerEvents = "none" },
                UI.Label { text = expandCost .. " 魂晶", fontSize = 7, fontColor = canExpand and { 160, 80, 255, 180 } or { 80, 70, 100, 120 }, pointerEvents = "none" },
            },
        })
    end

    -- 宝石背包格子（仅宝石Tab时重建，固定槽位 + 空占位 + 扩容按钮）
    if gemGrid and currentTab_ == "gem" then
        gemGrid:ClearChildren()

        -- 收集所有宝石并排序
        local gemList = {}
        for key, count in pairs(GameState.gemBag or {}) do
            if count and count > 0 then
                local parts = {}
                for s in string.gmatch(key, "[^:]+") do table.insert(parts, s) end
                local gemTypeId = parts[1]
                local qualityIdx = tonumber(parts[2])
                if gemTypeId and qualityIdx then
                    local gemType = Config.GEM_TYPE_MAP[gemTypeId]
                    local gemQual = Config.GEM_QUALITIES[qualityIdx]
                    if gemType and gemQual then
                        table.insert(gemList, {
                            key = key,
                            typeId = gemTypeId,
                            quality = qualityIdx,
                            count = count,
                            typeDef = gemType,
                            qualDef = gemQual,
                        })
                    end
                end
            end
        end
        -- 按品质降序，同品质按类型排序
        table.sort(gemList, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            return a.typeId < b.typeId
        end)

        local gemBagSize = GameState.GetGemBagSize()

        -- 已占用的宝石格子
        for _, g in ipairs(gemList) do
            local gc = g.typeDef.color
            local qc = g.qualDef.color
            local gemName = g.qualDef.name .. g.typeDef.name
            local canSynth = g.quality < #Config.GEM_QUALITIES and g.count >= Config.GEM_SYNTH_COST
            local typeId = g.typeId
            local quality = g.quality

            gemGrid:AddChild(UI.Panel {
                width = 56, height = 60,
                backgroundColor = { gc[1], gc[2], gc[3], 25 },
                borderColor = { qc[1], qc[2], qc[3], 120 },
                borderWidth = 1, borderRadius = 4,
                alignItems = "center", justifyContent = "center", gap = 1,
                onClick = Utils.Debounce(function()
                    InventoryPage.ShowGemDetail(typeId, quality, g.count)
                end, 0.2),
                children = {
                    UI.Panel {
                        width = 32, height = 32,
                        backgroundImage = Config.GetGemIcon(typeId, quality),
                        backgroundFit = "contain",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "×" .. g.count, fontSize = 8,
                        fontColor = { 200, 210, 220, 200 },
                        pointerEvents = "none",
                    },
                },
            })
        end

        -- 空占位格子
        for _ = #gemList + 1, gemBagSize do
            gemGrid:AddChild(UI.Panel {
                width = 56, height = 60,
                backgroundColor = { 35, 42, 55, 150 },
                borderColor = { 50, 60, 75, 100 },
                borderWidth = 1, borderRadius = 4,
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Label { text = "-", fontSize = 14, fontColor = { 50, 60, 75, 50 } },
                },
            })
        end

        -- 宝石背包扩容格子 ("+")
        local gemExpandCost = GameState.GetGemBagExpandCost()
        local canGemExpand = GameState.GetSoulCrystal() >= gemExpandCost and gemBagSize < Config.GEM_BAG_MAX_SIZE
        gemGrid:AddChild(UI.Panel {
            width = 56, height = 60,
            backgroundColor = canGemExpand and { 60, 40, 100, 180 } or { 30, 30, 40, 120 },
            borderColor = canGemExpand and { 160, 80, 255, 180 } or { 60, 50, 80, 100 },
            borderWidth = 1, borderRadius = 4,
            borderStyle = "dashed",
            alignItems = "center", justifyContent = "center", gap = 1,
            onClick = function()
                InventoryPage.ShowGemBagExpandConfirm()
            end,
            children = {
                UI.Label { text = "+", fontSize = 22, fontColor = canGemExpand and { 160, 80, 255, 230 } or { 80, 70, 100, 150 }, pointerEvents = "none" },
                UI.Label { text = gemExpandCost .. " 魂晶", fontSize = 7, fontColor = canGemExpand and { 160, 80, 255, 180 } or { 80, 70, 100, 120 }, pointerEvents = "none" },
            },
        })
    end

    -- 材料网格（仅材料Tab时重建，固定40格，支持堆叠溢出）
    if matGrid and currentTab_ == "mat" then
        matGrid:ClearChildren()
        local MAT_BAG_SIZE = 40
        local MAT_STACK_MAX = 999

        -- 收集有数量的材料，超过999的拆分为多个格子
        local matList = {}
        for _, def in ipairs(Config.MATERIAL_DEFS) do
            local amt = GameState.GetMaterial(def.id) or 0
            local remaining = amt
            while remaining > 0 do
                local stackAmt = math.min(remaining, MAT_STACK_MAX)
                table.insert(matList, { def = def, amount = stackAmt, total = amt })
                remaining = remaining - stackAmt
            end
        end

        -- 已有材料格子（点击弹出详情）
        for _, m in ipairs(matList) do
            local c = m.def.color
            local matId = m.def.id
            matGrid:AddChild(UI.Panel {
                width = 56, height = 60,
                backgroundColor = { c[1], c[2], c[3], 25 },
                borderColor = { c[1], c[2], c[3], 120 },
                borderWidth = 1, borderRadius = 4,
                alignItems = "center", justifyContent = "center", gap = 1,
                onClick = function()
                    InventoryPage.ShowMatDetail(matId)
                end,
                children = {
                    UI.Panel {
                        width = 32, height = 32,
                        backgroundImage = Config.MATERIAL_ICON_PATHS[m.def.id],
                        backgroundFit = "contain",
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = m.def.name, fontSize = 7,
                        fontColor = { c[1], c[2], c[3], 200 },
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = "×" .. m.amount, fontSize = 8,
                        fontColor = { 200, 210, 220, 200 },
                        pointerEvents = "none",
                    },
                },
            })
        end

        -- 空占位格子（点击关闭详情）
        for _ = #matList + 1, MAT_BAG_SIZE do
            matGrid:AddChild(UI.Panel {
                width = 56, height = 60,
                backgroundColor = { 35, 42, 55, 150 },
                borderColor = { 50, 60, 75, 100 },
                borderWidth = 1, borderRadius = 4,
                alignItems = "center", justifyContent = "center",
                onClick = function() InventoryPage.CloseMatDetail() end,
                children = {
                    UI.Label { text = "-", fontSize = 14, fontColor = { 50, 60, 75, 50 } },
                },
            })
        end
    end
end

-- ============================================================================
-- 背包扩容确认浮层
-- ============================================================================

function InventoryPage.CloseExpandConfirm()
    if expandOverlay_ then
        expandOverlay_:Destroy()
        expandOverlay_ = nil
    end
end

function InventoryPage.ShowExpandConfirm()
    InventoryPage.CloseCompare()
    InventoryPage.CloseExpandConfirm()

    local cost = GameState.GetExpandCost()
    local cur = GameState.GetSoulCrystal()
    local curSize = GameState.GetInventorySize()
    local maxSize = Config.INVENTORY_MAX_SIZE
    local atMax = curSize >= maxSize
    local canExpand = (not atMax) and (cur >= cost)
    local addSlots = Config.INVENTORY_EXPAND_SLOTS

    expandOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = "50%",
        zIndex = 200,
        paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 100, 60, 180, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 12, gap = 8,
                alignItems = "center",
                children = {
                    -- 标题栏
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label { text = "背包扩容", fontSize = 14, fontColor = { 160, 80, 255, 240 }, fontWeight = "bold" },
                            UI.Panel {
                                width = 24, height = 24,
                                backgroundColor = { 160, 50, 50, 200 },
                                borderRadius = 12,
                                alignItems = "center", justifyContent = "center",
                                onClick = function() InventoryPage.CloseExpandConfirm() end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                                },
                            },
                        },
                    },
                    -- 信息
                    UI.Label { text = "当前容量: " .. curSize .. "/" .. maxSize .. " 格", fontSize = 11, fontColor = { 180, 190, 210, 220 } },
                    atMax
                        and UI.Label { text = "已达上限", fontSize = 11, fontColor = { 255, 100, 100, 220 } }
                        or  UI.Label { text = "扩容后: " .. (curSize + addSlots) .. " 格 (+" .. addSlots .. ")", fontSize = 11, fontColor = { 80, 255, 80, 220 } },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4, marginTop = 4,
                        children = {
                            UI.Label { text = "消耗: " .. cost .. " 魂晶", fontSize = 12, fontColor = { 160, 80, 255, 230 } },
                            UI.Label { text = "(拥有 " .. cur .. ")", fontSize = 10, fontColor = canExpand and { 140, 200, 140, 200 } or { 255, 100, 100, 200 } },
                        },
                    },
                    -- 按钮
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 6,
                        children = {
                            UI.Button {
                                text = atMax and "已达上限" or (canExpand and "确认扩容" or "魂晶不足"),
                                height = 32, fontSize = 13,
                                width = 120,
                                backgroundColor = canExpand and { 100, 50, 200, 230 } or { 60, 60, 70, 200 },
                                onClick = Utils.Debounce(function()
                                    if not canExpand then return end
                                    local ok, _ = GameState.ExpandInventory()
                                    if ok then
                                        InventoryPage.CloseExpandConfirm()
                                        shared_.gridDirty = true
                                        InventoryPage.Refresh()
                                    end
                                end, 0.5),
                            },
                            UI.Button {
                                text = "取消", height = 32, fontSize = 13,
                                width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function()
                                    InventoryPage.CloseExpandConfirm()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(expandOverlay_)
    end
end


-- ============================================================================
-- 宝石背包扩容确认浮层
-- ============================================================================

function InventoryPage.CloseGemBagExpandConfirm()
    if gemExpandOverlay_ then
        gemExpandOverlay_:Destroy()
        gemExpandOverlay_ = nil
    end
end

function InventoryPage.ShowGemBagExpandConfirm()
    InventoryPage.CloseCompare()
    InventoryPage.CloseGemBagExpandConfirm()

    local cost = GameState.GetGemBagExpandCost()
    local cur = GameState.GetSoulCrystal()
    local curSize = GameState.GetGemBagSize()
    local maxSize = Config.GEM_BAG_MAX_SIZE
    local atMax = curSize >= maxSize
    local canExpand = (not atMax) and (cur >= cost)
    local addSlots = Config.GEM_BAG_EXPAND_SLOTS

    gemExpandOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = "50%",
        zIndex = 200,
        paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 100, 60, 180, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 12, gap = 8,
                alignItems = "center",
                children = {
                    -- 标题栏
                    UI.Panel {
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        width = "100%",
                        children = {
                            UI.Label { text = "宝石背包扩容", fontSize = 14, fontColor = { 160, 80, 255, 240 }, fontWeight = "bold" },
                            UI.Panel {
                                width = 24, height = 24,
                                backgroundColor = { 160, 50, 50, 200 },
                                borderRadius = 12,
                                alignItems = "center", justifyContent = "center",
                                onClick = function() InventoryPage.CloseGemBagExpandConfirm() end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                                },
                            },
                        },
                    },
                    -- 信息
                    UI.Label { text = "当前容量: " .. curSize .. "/" .. maxSize .. " 格", fontSize = 11, fontColor = { 180, 190, 210, 220 } },
                    atMax
                        and UI.Label { text = "已达上限", fontSize = 11, fontColor = { 255, 100, 100, 220 } }
                        or  UI.Label { text = "扩容后: " .. (curSize + addSlots) .. " 格 (+" .. addSlots .. ")", fontSize = 11, fontColor = { 80, 255, 80, 220 } },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4, marginTop = 4,
                        children = {
                            UI.Label { text = "消耗: " .. cost .. " 魂晶", fontSize = 12, fontColor = { 160, 80, 255, 230 } },
                            UI.Label { text = "(拥有 " .. cur .. ")", fontSize = 10, fontColor = canExpand and { 140, 200, 140, 200 } or { 255, 100, 100, 200 } },
                        },
                    },
                    -- 按钮
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 6,
                        children = {
                            UI.Button {
                                text = atMax and "已达上限" or (canExpand and "确认扩容" or "魂晶不足"),
                                height = 32, fontSize = 13,
                                width = 120,
                                backgroundColor = canExpand and { 100, 50, 200, 230 } or { 60, 60, 70, 200 },
                                onClick = Utils.Debounce(function()
                                    if not canExpand then return end
                                    local ok, _ = GameState.ExpandGemBag()
                                    if ok then
                                        SaveSystem.MarkDirty()
                                        InventoryPage.CloseGemBagExpandConfirm()
                                        shared_.gridDirty = true
                                        InventoryPage.Refresh()
                                    end
                                end, 0.5),
                            },
                            UI.Button {
                                text = "取消", height = 32, fontSize = 13,
                                width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function()
                                    InventoryPage.CloseGemBagExpandConfirm()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(gemExpandOverlay_)
    end
end

-- ============================================================================
-- 材料丢弃确认弹窗
-- ============================================================================

function InventoryPage.CloseMatDiscardConfirm()
    if matDiscardConfirm_ then
        matDiscardConfirm_:Destroy()
        matDiscardConfirm_ = nil
    end
end

--- 显示材料丢弃确认弹窗
---@param matId string
function InventoryPage.ShowMatDiscardConfirm(matId)
    InventoryPage.CloseMatDiscardConfirm()

    local def = Config.MATERIAL_MAP[matId]
    if not def then return end
    local totalAmt = GameState.GetMaterial(matId) or 0
    if totalAmt <= 0 then return end

    local discardAmt = totalAmt  -- 默认丢弃全部
    local c = def.color

    local function closeOverlay()
        InventoryPage.CloseMatDiscardConfirm()
    end

    -- 数量选择行（-100, -10, 数量, +10, +100）
    local amtLabelRef = nil

    local function clampAmt(v)
        return math.max(1, math.min(totalAmt, v))
    end

    local function mkAdjBtn(label, delta)
        return UI.Button {
            text = label, width = 40, height = 26, fontSize = 11,
            backgroundColor = { 55, 60, 80, 220 },
            onClick = function()
                discardAmt = clampAmt(discardAmt + delta)
                if amtLabelRef then amtLabelRef:SetText(tostring(discardAmt)) end
            end,
        }
    end

    matDiscardConfirm_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%",
        zIndex = 500,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() closeOverlay() end,
        children = {
            UI.Panel {
                width = 270,
                backgroundColor = { 28, 32, 48, 250 },
                borderColor = { 180, 60, 60, 200 },
                borderWidth = 1, borderRadius = 10,
                padding = 18, gap = 10,
                alignItems = "center",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "丢弃材料",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 220, 225, 240, 255 },
                    },
                    UI.Label {
                        text = "确认丢弃 " .. def.name .. " ？\n丢弃后无法恢复",
                        fontSize = 12,
                        fontColor = { 200, 180, 170, 220 },
                        textAlign = "center",
                    },
                    -- 数量选择
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            mkAdjBtn("-100", -100),
                            mkAdjBtn("-10", -10),
                            UI.Panel {
                                width = 60, height = 26,
                                backgroundColor = { 20, 24, 36, 220 },
                                borderColor = { c[1], c[2], c[3], 120 },
                                borderWidth = 1, borderRadius = 4,
                                alignItems = "center", justifyContent = "center",
                                children = {
                                    UI.Label {
                                        id = "__matDiscardAmt",
                                        text = tostring(discardAmt),
                                        fontSize = 12, fontWeight = "bold",
                                        fontColor = { 255, 220, 100, 255 },
                                    },
                                },
                            },
                            mkAdjBtn("+10", 10),
                            mkAdjBtn("+100", 100),
                        },
                    },
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row", gap = 16, justifyContent = "center",
                        children = {
                            UI.Button {
                                text = "取消", width = 85, height = 32, fontSize = 12,
                                backgroundColor = { 60, 65, 80, 200 },
                                onClick = function() closeOverlay() end,
                            },
                            UI.Button {
                                text = "确认丢弃", variant = "primary", width = 100, height = 32, fontSize = 12,
                                backgroundColor = { 160, 50, 50, 230 },
                                onClick = function()
                                    local cur = GameState.GetMaterial(matId) or 0
                                    local amt = math.min(discardAmt, cur)
                                    if amt > 0 then
                                        GameState.AddMaterial(matId, -amt)
                                        FloatTip.Show("已丢弃 " .. def.name .. " ×" .. amt, { 255, 140, 100, 255 })
                                    end
                                    closeOverlay()
                                    InventoryPage.CloseMatDetail()
                                    shared_.gridDirty = true
                                    InventoryPage.Refresh()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    -- 记住数量 label 引用
    amtLabelRef = matDiscardConfirm_:FindById("__matDiscardAmt")

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(matDiscardConfirm_)
    end
end

-- ============================================================================
-- 材料详情浮窗
-- ============================================================================

function InventoryPage.CloseMatDetail()
    if matDetailOverlay_ then
        matDetailOverlay_:Destroy()
        matDetailOverlay_ = nil
    end
    matDetailId_ = nil
end

--- 显示材料详情浮窗（复用装备详情视觉风格）
---@param matId string
function InventoryPage.ShowMatDetail(matId)
    -- toggle：再次点击同一材料 → 关闭
    if matDetailId_ == matId then
        InventoryPage.CloseMatDetail()
        return
    end

    InventoryPage.CloseMatDetail()

    local def = Config.MATERIAL_MAP[matId]
    if not def then return end

    local c = def.color
    local totalAmt = GameState.GetMaterial(matId) or 0

    -- 稀有度
    local rarityNames = {
        common = "普通", uncommon = "精良", rare = "稀有",
        legendary = "传说", mythic = "神话",
    }
    local rarityColors = {
        common    = { 180, 180, 180 },
        uncommon  = { 80, 200, 80 },
        rare      = { 80, 140, 255 },
        legendary = { 255, 165, 0 },
        mythic    = { 255, 80, 120 },
    }
    local rarityName = rarityNames[def.rarity] or def.rarity
    local rc = rarityColors[def.rarity] or { 200, 200, 200 }

    local headerBg = { math.floor(c[1] * 0.25 + 20), math.floor(c[2] * 0.25 + 20), math.floor(c[3] * 0.25 + 20), 250 }

    -- 内容区子元素
    local contentChildren = {}

    -- 图标 + 名称 + 持有数 + 稀有度
    table.insert(contentChildren, UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 8,
        width = "100%", paddingLeft = 8, paddingRight = 8, paddingTop = 6,
        children = {
            UI.Panel {
                width = 36, height = 36,
                backgroundColor = { c[1], c[2], c[3], 30 },
                borderColor = { c[1], c[2], c[3], 80 },
                borderWidth = 1, borderRadius = 6,
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Panel {
                        width = 28, height = 28,
                        backgroundImage = Config.MATERIAL_ICON_PATHS[matId],
                        backgroundFit = "contain",
                        pointerEvents = "none",
                    },
                },
            },
            UI.Panel {
                flexGrow = 1, gap = 2,
                children = {
                    UI.Label {
                        text = def.name,
                        fontSize = 13, fontWeight = "bold",
                        fontColor = { c[1], c[2], c[3], 255 },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Label {
                                text = "持有 " .. totalAmt,
                                fontSize = 10,
                                fontColor = { 255, 215, 0, 230 },
                            },
                            UI.Label {
                                text = rarityName,
                                fontSize = 9,
                                fontColor = { rc[1], rc[2], rc[3], 200 },
                            },
                        },
                    },
                },
            },
        },
    })

    -- 分割线
    table.insert(contentChildren, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 60, 70, 90, 120 },
        marginTop = 4, marginBottom = 2,
    })

    -- 属性行：堆叠上限 / 占用格数
    local slotsUsed = math.ceil(totalAmt / 999)
    local statRows = {
        { label = "堆叠上限", value = "999 / 格" },
        { label = "占用格数", value = slotsUsed .. " 格" },
    }
    for _, row in ipairs(statRows) do
        table.insert(contentChildren, UI.Panel {
            flexDirection = "row", alignItems = "center",
            justifyContent = "space-between", width = "100%",
            paddingLeft = 10, paddingRight = 10,
            children = {
                UI.Label { text = row.label, fontSize = 9, fontColor = { 140, 150, 170, 180 } },
                UI.Label { text = row.value, fontSize = 9, fontColor = { 190, 195, 200, 220 } },
            },
        })
    end

    -- 分割线
    table.insert(contentChildren, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 60, 70, 90, 120 },
        marginTop = 4, marginBottom = 2,
    })

    -- 描述
    table.insert(contentChildren, UI.Label {
        text = "「" .. (def.desc or "") .. "」",
        fontSize = 9,
        fontColor = { 160, 155, 140, 170 },
        textAlign = "center",
        paddingLeft = 8, paddingRight = 8,
        paddingBottom = 4,
    })

    -- 丢弃按钮
    if totalAmt > 0 then
        table.insert(contentChildren, UI.Panel {
            width = "100%", alignItems = "center", paddingBottom = 8,
            children = {
                UI.Button {
                    text = "丢弃", width = 80, height = 28, fontSize = 11,
                    backgroundColor = { 120, 45, 45, 200 },
                    onClick = function()
                        InventoryPage.ShowMatDiscardConfirm(matId)
                    end,
                },
            },
        })
    end

    -- 组装面板（复用装备详情的布局结构）
    local panelChildren = {
        -- 标题栏（带颜色背景 + 关闭按钮）
        UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            width = "100%",
            backgroundColor = headerBg,
            paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
            children = {
                UI.Label { text = "材料详情", fontSize = 12, fontColor = { 200, 210, 230, 245 } },
                UI.Panel {
                    width = 24, height = 24,
                    backgroundColor = { 160, 50, 50, 200 },
                    borderRadius = 12,
                    alignItems = "center", justifyContent = "center",
                    onClick = function() InventoryPage.CloseMatDetail() end,
                    children = {
                        UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                    },
                },
            },
        },
        -- 内容区
        UI.Panel {
            width = "100%", gap = 4,
            children = contentChildren,
        },
    }

    matDetailOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = "50%",
        zIndex = 200,
        paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 60, 70, 95, 200 },
                borderWidth = 1, borderRadius = 8,
                gap = 4,
                overflow = "hidden",
                children = panelChildren,
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(matDetailOverlay_)
    end
    matDetailId_ = matId
end

-- ============================================================================
-- 宝石详情浮窗
-- ============================================================================

function InventoryPage.CloseGemDetail()
    if gemDetailOverlay_ then
        gemDetailOverlay_:Destroy()
        gemDetailOverlay_ = nil
    end
end

function InventoryPage.CloseGemDiscardConfirm()
    if gemDiscardConfirm_ then
        gemDiscardConfirm_:Destroy()
        gemDiscardConfirm_ = nil
    end
end

function InventoryPage.ShowGemDiscardConfirm(gemName, onConfirm)
    InventoryPage.CloseGemDiscardConfirm()

    local checked = false

    local function closeOverlay()
        InventoryPage.CloseGemDiscardConfirm()
    end

    gemDiscardConfirm_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%",
        zIndex = 500,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() closeOverlay() end,
        children = {
            UI.Panel {
                width = 250,
                backgroundColor = { 28, 32, 48, 250 },
                borderColor = { 180, 60, 60, 200 },
                borderWidth = 1, borderRadius = 10,
                padding = 18, gap = 12,
                alignItems = "center",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "丢弃宝石",
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { 220, 225, 240, 255 },
                    },
                    UI.Label {
                        text = "确认丢弃 " .. gemName .. " ？\n丢弃后无法恢复",
                        fontSize = 12,
                        fontColor = { 200, 180, 170, 220 },
                        textAlign = "center",
                    },
                    -- 勾选框
                    UI.Checkbox {
                        checked = false,
                        label = "本次登录不再提示",
                        size = 16, fontSize = 11,
                        onChange = function(self, val)
                            checked = val
                        end,
                    },
                    -- 按钮行
                    UI.Panel {
                        flexDirection = "row", gap = 16, justifyContent = "center",
                        children = {
                            UI.Button {
                                text = "取消", width = 85, height = 32, fontSize = 12,
                                backgroundColor = { 60, 65, 80, 200 },
                                onClick = function() closeOverlay() end,
                            },
                            UI.Button {
                                text = "确认丢弃", variant = "primary", width = 100, height = 32, fontSize = 12,
                                backgroundColor = { 160, 50, 50, 230 },
                                onClick = function()
                                    if checked then
                                        skipGemDiscardConfirm_ = true
                                    end
                                    closeOverlay()
                                    onConfirm()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(gemDiscardConfirm_)
    end
end

--- 显示宝石详情浮窗（信息 + 合成 + 丢弃）
---@param gemTypeId string
---@param qualityIdx number
---@param count number
function InventoryPage.ShowGemDetail(gemTypeId, qualityIdx, count)
    InventoryPage.CloseGemDetail()

    local gemType = Config.GEM_TYPE_MAP[gemTypeId]
    local gemQual = Config.GEM_QUALITIES[qualityIdx]
    if not gemType or not gemQual then return end

    local gemName = gemQual.name .. gemType.name
    local qc = gemQual.color
    local gc = gemType.color
    local canSynth = qualityIdx < #Config.GEM_QUALITIES and count >= Config.GEM_SYNTH_COST
    local nextQual = Config.GEM_QUALITIES[qualityIdx + 1]

    -- 当前章节对应的缩放因子，用于宝石属性预览
    local chapter = GameState.chapter or 1
    local tierMul = Config.GetChapterTier(chapter)

    -- 三类装备属性预览
    local categories = { "weapon", "armor", "jewelry" }
    local catNames = { weapon = "武器", armor = "防具", jewelry = "饰品" }
    local effectRows = {}
    for _, cat in ipairs(categories) do
        local statKey, statVal = Config.CalcGemStat(gemTypeId, qualityIdx, cat, tierMul)
        if statKey and statVal and statVal > 0 then
            local displayName
            local displayVal
            if statKey == "allRes" then
                displayName = "全抗"
                displayVal = GameState.FormatStatValue("fireRes", statVal)
            else
                local sd = Config.EQUIP_STATS[statKey]
                displayName = sd and sd.name or statKey
                displayVal = GameState.FormatStatValue(statKey, statVal)
            end
            table.insert(effectRows, {
                catName = catNames[cat],
                statName = displayName,
                statVal = displayVal,
            })
        end
    end

    -- 构建浮窗子元素
    local children = {}

    -- 标题行：宝石图标 + 名称 + 品质
    table.insert(children, UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 8,
        children = {
            UI.Panel {
                width = 40, height = 40,
                backgroundImage = Config.GetGemIcon(gemTypeId, qualityIdx),
                backgroundFit = "contain",
                pointerEvents = "none",
            },
            UI.Panel {
                gap = 2,
                children = {
                    UI.Label {
                        text = gemName,
                        fontSize = 15, fontWeight = "bold",
                        fontColor = { qc[1], qc[2], qc[3], 255 },
                    },
                    UI.Label {
                        text = "持有: " .. count .. " 颗",
                        fontSize = 11,
                        fontColor = { 180, 190, 210, 200 },
                    },
                },
            },
        },
    })

    -- 分割线
    table.insert(children, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 90, 120, 80 },
        marginTop = 2, marginBottom = 2,
    })

    -- 属性效果列表
    table.insert(children, UI.Label {
        text = "镶嵌效果（基础值）",
        fontSize = 11, fontWeight = "bold",
        fontColor = { 140, 160, 200, 220 },
    })

    for _, row in ipairs(effectRows) do
        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center",
            justifyContent = "space-between",
            width = "100%", paddingLeft = 4, paddingRight = 4,
            children = {
                UI.Label {
                    text = row.catName,
                    fontSize = 10,
                    fontColor = { 130, 140, 160, 180 },
                },
                UI.Label {
                    text = row.statName .. " " .. row.statVal,
                    fontSize = 11,
                    fontColor = { 100, 220, 160, 230 },
                },
            },
        })
    end

    -- 宝石描述文本
    local desc = gemType.descs and gemType.descs[qualityIdx]
    if desc then
        table.insert(children, UI.Label {
            text = "「" .. desc .. "」",
            fontSize = 9,
            fontColor = { 160, 155, 140, 160 },
            textAlign = "center",
            marginTop = 4,
        })
    end

    -- 分割线
    table.insert(children, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 90, 120, 80 },
        marginTop = 4, marginBottom = 2,
    })

    -- 合成提示
    if qualityIdx < #Config.GEM_QUALITIES then
        local synthText
        if canSynth then
            synthText = Config.GEM_SYNTH_COST .. " 颗 → 1 颗 " .. (nextQual and nextQual.name or "") .. gemType.name
        else
            synthText = "需要 " .. Config.GEM_SYNTH_COST .. " 颗（还差 " .. (Config.GEM_SYNTH_COST - count) .. " 颗）"
        end
        table.insert(children, UI.Label {
            text = synthText,
            fontSize = 10,
            fontColor = canSynth and { 100, 230, 100, 200 } or { 160, 160, 170, 160 },
            textAlign = "center",
        })
    else
        table.insert(children, UI.Label {
            text = "最高品质",
            fontSize = 10,
            fontColor = { 255, 200, 80, 200 },
            textAlign = "center",
        })
    end

    -- 按钮行
    local typeId = gemTypeId
    local quality = qualityIdx
    table.insert(children, UI.Panel {
        flexDirection = "row", gap = 10, justifyContent = "center",
        marginTop = 4,
        children = {
            -- 丢弃按钮
            UI.Button {
                text = "丢弃", width = 80, height = 32, fontSize = 12,
                backgroundColor = { 120, 50, 50, 220 },
                onClick = Utils.Debounce(function()
                    local function doDiscard()
                        local ok = GameState.RemoveGem(typeId, quality, 1)
                        if ok then
                            require("ui.Toast").Success("已丢弃 1 颗 " .. gemName)
                        else
                            require("ui.Toast").Warn("丢弃失败")
                        end
                        InventoryPage.CloseGemDetail()
                        shared_.gridDirty = true
                        InventoryPage.Refresh()
                    end
                    if skipGemDiscardConfirm_ then
                        doDiscard()
                    else
                        InventoryPage.ShowGemDiscardConfirm(gemName, doDiscard)
                    end
                end, 0.3),
            },
            -- 合成按钮
            UI.Button {
                text = "合成",
                width = 80, height = 32, fontSize = 12,
                backgroundColor = canSynth and { 50, 130, 80, 230 } or { 60, 65, 75, 180 },
                fontColor = canSynth and { 255, 255, 255, 255 } or { 120, 120, 130, 150 },
                onClick = canSynth and Utils.Debounce(function()
                    local ok, msg = GameState.SynthesizeGem(typeId, quality)
                    if ok then
                        require("ui.Toast").Success(msg)
                    else
                        require("ui.Toast").Warn(msg)
                    end
                    InventoryPage.CloseGemDetail()
                    shared_.gridDirty = true
                    InventoryPage.Refresh()
                end, 0.3) or nil,
            },
        },
    })

    -- 浮窗面板（定位在宝石格子区域上方）
    gemDetailOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%",
        zIndex = 250,
        backgroundColor = { 0, 0, 0, 100 },
        justifyContent = "center", alignItems = "center",
        onClick = function()
            InventoryPage.CloseGemDetail()
        end,
        children = {
            UI.Panel {
                width = 240,
                backgroundColor = { 22, 26, 40, 248 },
                borderColor = { qc[1], qc[2], qc[3], 160 },
                borderWidth = 1, borderRadius = 8,
                padding = 14, gap = 6,
                onClick = function() end,  -- 阻止冒泡
                children = children,
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(gemDetailOverlay_)
    end
end

-- ============================================================================
-- 分解橙色及以下确认浮层
-- ============================================================================

function InventoryPage.CloseDecompOrangeConfirm()
    if decompOrangeOverlay_ then
        decompOrangeOverlay_:Destroy()
        decompOrangeOverlay_ = nil
    end
end

function InventoryPage.ShowDecompOrangeConfirm()
    InventoryPage.CloseDecompOrangeConfirm()

    local maxQ = #Config.EQUIP_QUALITY
    local count = 0
    for _, item in ipairs(GameState.inventory) do
        if item.qualityIdx <= maxQ and not item.locked then
            count = count + 1
        end
    end

    decompOrangeOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = "50%",
        zIndex = 200,
        paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 255, 165, 0, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 12, gap = 8,
                alignItems = "center",
                children = {
                    UI.Label { text = "确认分解橙色及以下", fontSize = 14, fontColor = { 255, 165, 0, 240 }, fontWeight = "bold" },
                    UI.Label { text = "将分解背包中 " .. count .. " 件橙色及以下装备", fontSize = 11, fontColor = { 200, 205, 215, 220 } },
                    UI.Label { text = "此操作不可撤销!", fontSize = 10, fontColor = { 255, 180, 80, 200 } },
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 6,
                        children = {
                            UI.Button {
                                text = count > 0 and "确认分解" or "无可分解",
                                height = 32, fontSize = 13, width = 120,
                                backgroundColor = count > 0 and { 200, 120, 0, 230 } or { 60, 60, 70, 200 },
                                onClick = Utils.Debounce(function()
                                    if count <= 0 then return end
                                    local gold, cnt, mats = GameState.DecomposeByFilter(maxQ, false)
                                    local matParts = {}
                                    if mats then for matId, amt in pairs(mats) do local d = Config.MATERIAL_MAP[matId]; table.insert(matParts, amt .. (d and d.name or matId)) end end
                                    print("[UI] 分解橙色及以下: " .. cnt .. "件, " .. gold .. "金, " .. table.concat(matParts, "+"))
                                    if cnt > 0 then
                                        FloatTip.Decompose("批量分解 " .. cnt .. " 件 → " .. table.concat(matParts, " + "))
                                        SaveSystem.MarkDirty()
                                    end
                                    InventoryPage.CloseDecompOrangeConfirm()
                                    decompPanelVisible_ = false
                                    shared_.gridDirty = true
                                    InventoryPage.Refresh()
                                end, 0.5),
                            },
                            UI.Button {
                                text = "取消", height = 32, fontSize = 13, width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function()
                                    InventoryPage.CloseDecompOrangeConfirm()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(decompOrangeOverlay_)
    end
end

function InventoryPage.ShowAutoDecompOrangeConfirm(keepSets)
    InventoryPage.CloseDecompOrangeConfirm()

    local maxQ = #Config.EQUIP_QUALITY
    local descText = keepSets
        and "开启后，新掉落的橙色及以下装备将自动分解（保留橙色套装）"
        or  "开启后，新掉落的橙色及以下装备将自动分解（含套装）"

    decompOrangeOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, bottom = "50%",
        zIndex = 200,
        paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 255, 165, 0, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 12, gap = 8,
                alignItems = "center",
                children = {
                    UI.Label { text = "确认自动分解橙色及以下", fontSize = 14, fontColor = { 255, 165, 0, 240 }, fontWeight = "bold" },
                    UI.Label { text = descText, fontSize = 11, fontColor = { 200, 205, 215, 220 } },
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 6,
                        children = {
                            UI.Button {
                                text = "确认开启",
                                height = 32, fontSize = 13, width = 120,
                                backgroundColor = { 200, 120, 0, 230 },
                                onClick = Utils.Debounce(function()
                                    -- 互斥：先清空所有，再设置当前
                                    for k = 1, #GameState.autoDecompConfig do
                                        GameState.autoDecompConfig[k] = 0
                                    end
                                    GameState.autoDecompConfig[maxQ] = keepSets and 2 or 1
                                    SaveSystem.MarkDirty()
                                    InventoryPage.CloseDecompOrangeConfirm()
                                    InventoryPage.Refresh()
                                end, 0.5),
                            },
                            UI.Button {
                                text = "取消", height = 32, fontSize = 13, width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function()
                                    InventoryPage.CloseDecompOrangeConfirm()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if shared_.overlayRoot then
        shared_.overlayRoot:AddChild(decompOrangeOverlay_)
    end
end

function InventoryPage.InvalidateCache()
    shared_.gridDirty = true
    lastInvCount_ = -1
    lastEquipKey_ = ""
end

return InventoryPage
