-- ============================================================================
-- ui/BagPage.lua - 通用道具背包页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local SaveSystem = require("SaveSystem")
local Colors = require("ui.Colors")
local Utils = require("Utils")
local Toast = require("ui.Toast")

local BagPage = {}

---@type Widget
local page_ = nil
---@type Widget
local confirmOverlay_ = nil
local lastBagKey_ = "__INIT__"

-- 预创建的固定格子引用 (静态容器，增量更新内容)
local slots_ = {}   -- slots_[1..BAG_GRID_SIZE] = { widget, iconW, nameW, countW }

-- 丢弃确认: "本日不再提醒" 标记 (按日期记录)
local discardNoRemindDate_ = nil

--- 生成背包快照key用于脏检测
local function BagKey()
    local parts = {}
    for _, itemCfg in ipairs(Config.ITEMS) do
        local c = GameState.bag[itemCfg.id] or 0
        if c > 0 then
            table.insert(parts, itemCfg.id .. ":" .. c)
        end
    end
    return table.concat(parts, ",")
end

local BAG_GRID_SIZE = 20

local EMPTY_BG    = { 28, 32, 44, 120 }
local EMPTY_BORDER = { 40, 45, 58, 80 }
local EMPTY_NAME_COLOR = { 100, 105, 120, 180 }
local EMPTY_LABEL = "-"

--- 创建一个固定格子 (骨架)，内部子元素通过引用更新
local function CreateSlotSkeleton(index)
    local iconW = UI.Panel {
        id = "bag_icon_" .. index,
        width = 40, height = 40,
        backgroundFit = "contain",
        opacity = 0.3,
    }
    local nameW = UI.Label {
        id = "bag_name_" .. index,
        text = EMPTY_LABEL,
        fontSize = 7,
        fontColor = EMPTY_NAME_COLOR,
    }
    local countW = UI.Label {
        id = "bag_count_" .. index,
        text = "",
        fontSize = 8,
        fontColor = { 220, 220, 220, 220 },
    }
    local slotW = UI.Panel {
        id = "bag_slot_" .. index,
        width = 64, height = 78,
        alignItems = "center", justifyContent = "center", gap = 2,
        backgroundColor = EMPTY_BG,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = EMPTY_BORDER,
        children = { iconW, nameW, countW },
    }
    slots_[index] = { widget = slotW, iconW = iconW, nameW = nameW, countW = countW, itemId = nil }
    return slotW
end

--- 更新单个格子的内容 (增量更新，不销毁重建)
local function UpdateSlot(index, itemCfg)
    local s = slots_[index]
    if not s then return end

    if itemCfg then
        local count = GameState.GetBagItemCount(itemCfg.id)
        local hasItem = count > 0
        local c = itemCfg.color

        s.widget:SetStyle({
            backgroundColor = hasItem and { 40, 44, 60, 200 } or { 30, 34, 48, 150 },
            borderColor = hasItem and { c[1], c[2], c[3], 120 } or { 50, 55, 70, 100 },
        })
        s.widget.props.onClick = hasItem and function()
            BagPage.ShowUseConfirm(itemCfg)
        end or nil
        s.iconW:SetStyle({ backgroundImage = itemCfg.icon, opacity = hasItem and 1.0 or 0.3 })
        s.nameW:SetText(itemCfg.name)
        s.nameW:SetStyle({ fontColor = hasItem and { c[1], c[2], c[3], 255 } or EMPTY_NAME_COLOR })
        s.countW:SetText(hasItem and ("x" .. count) or "")
        s.itemId = itemCfg.id
    else
        -- 空格子
        s.widget:SetStyle({ backgroundColor = EMPTY_BG, borderColor = EMPTY_BORDER })
        s.widget.props.onClick = nil
        s.iconW:SetStyle({ backgroundImage = "", opacity = 0.3 })
        s.nameW:SetText(EMPTY_LABEL)
        s.nameW:SetStyle({ fontColor = { 50, 55, 70, 60 } })
        s.countW:SetText("")
        s.itemId = nil
    end
end

--- 显示使用确认弹窗
function BagPage.ShowUseConfirm(itemCfg)
    if not page_ then return end
    BagPage.CloseConfirm()

    local count = GameState.GetBagItemCount(itemCfg.id)

    -- 构建内容子元素（避免 nil 空洞导致 ipairs 中断）
    local contentChildren = {
        UI.Panel {
            width = 48, height = 48,
            backgroundImage = itemCfg.icon,
            backgroundFit = "contain",
        },
        UI.Label {
            text = itemCfg.name .. " x" .. count,
            fontSize = 14,
            fontColor = { itemCfg.color[1], itemCfg.color[2], itemCfg.color[3], 255 },
        },
        UI.Label {
            text = itemCfg.desc,
            fontSize = 10,
            fontColor = { 180, 185, 200, 220 },
            textAlign = "center",
        },
    }

    -- 魔法石类道具: 提示去装备页使用
    if itemCfg.isMagicStone then
        table.insert(contentChildren, UI.Label {
            text = "请在「装备」页点击已装备的装备，选择「提升Tier」使用",
            fontSize = 9,
            fontColor = { 255, 220, 130, 200 },
            textAlign = "center",
            marginTop = 2,
        })
    end

    -- 按钮行
    local btnChildren = {
        UI.Button {
            text = "丢弃", height = 30, fontSize = 11,
            backgroundColor = { 120, 50, 50, 200 },
            onClick = function()
                BagPage.DoDiscard(itemCfg)
            end,
        },
        UI.Button {
            text = "取消", height = 30, fontSize = 11,
            backgroundColor = { 60, 65, 80, 200 },
            onClick = function() BagPage.CloseConfirm() end,
        },
    }
    -- 非魔法石道具才显示"使用"按钮
    if not itemCfg.isMagicStone then
        table.insert(btnChildren, UI.Button {
            text = "使用", height = 30, fontSize = 11, variant = "primary",
            onClick = function()
                local ok, msg = GameState.UseBagItem(itemCfg.id)
                BagPage.CloseConfirm()
                lastBagKey_ = "__FORCE__"
                BagPage.Refresh()
                SaveSystem.SaveNow()
                if msg then
                    if ok then Toast.Success(msg) else Toast.Warn(msg) end
                end
            end,
        })
    end

    table.insert(contentChildren, UI.Panel {
        flexDirection = "row", gap = 10, marginTop = 6,
        children = btnChildren,
    })

    confirmOverlay_ = UI.Panel {
        position = "absolute", width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() BagPage.CloseConfirm() end,
        children = {
            UI.Panel {
                width = 260,
                backgroundColor = { 35, 40, 55, 245 },
                borderRadius = 10, padding = 16, gap = 10,
                alignItems = "center",
                borderWidth = 1,
                borderColor = { itemCfg.color[1], itemCfg.color[2], itemCfg.color[3], 100 },
                onClick = function() end, -- 阻止冒泡
                children = contentChildren,
            },
        },
    }
    page_:AddChild(confirmOverlay_)
end

function BagPage.CloseConfirm()
    if confirmOverlay_ then
        confirmOverlay_:Remove()
        confirmOverlay_ = nil
    end
end

--- 执行丢弃 (带二次确认)
function BagPage.DoDiscard(itemCfg)
    local today = os.date("%Y-%m-%d")
    if discardNoRemindDate_ == today then
        -- 本日已勾选不再提醒，直接丢弃
        BagPage.ExecuteDiscard(itemCfg)
        return
    end
    -- 弹出二次确认
    BagPage.CloseConfirm()
    local noRemindChecked = false
    confirmOverlay_ = UI.Panel {
        position = "absolute", width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        onClick = function() BagPage.CloseConfirm() end,
        children = {
            UI.Panel {
                width = 240,
                backgroundColor = { 45, 40, 55, 250 },
                borderRadius = 10, padding = 16, gap = 10,
                alignItems = "center",
                borderWidth = 1, borderColor = { 200, 80, 80, 120 },
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "确认丢弃",
                        fontSize = 14, fontColor = { 255, 100, 100, 255 },
                    },
                    UI.Label {
                        text = "确定要丢弃 " .. itemCfg.name .. " x1 吗？\n丢弃后无法恢复！",
                        fontSize = 10, fontColor = { 200, 200, 210, 220 },
                        textAlign = "center",
                    },
                    UI.Checkbox {
                        label = "本日不再提醒", checked = false,
                        size = 14, fontSize = 10,
                        fontColor = { 160, 165, 180, 200 },
                        onChange = function(self, v) noRemindChecked = v end,
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 4,
                        children = {
                            UI.Button {
                                text = "取消", height = 30, fontSize = 11,
                                backgroundColor = { 60, 65, 80, 200 },
                                onClick = function() BagPage.CloseConfirm() end,
                            },
                            UI.Button {
                                text = "确认丢弃", height = 30, fontSize = 11,
                                backgroundColor = { 160, 50, 50, 220 },
                                onClick = function()
                                    if noRemindChecked then
                                        discardNoRemindDate_ = os.date("%Y-%m-%d")
                                    end
                                    BagPage.ExecuteDiscard(itemCfg)
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
    page_:AddChild(confirmOverlay_)
end

--- 实际执行丢弃
function BagPage.ExecuteDiscard(itemCfg)
    local ok, msg = GameState.DiscardBagItem(itemCfg.id, 1)
    BagPage.CloseConfirm()
    lastBagKey_ = "__FORCE__"
    BagPage.Refresh()
    SaveSystem.SaveNow()
    if msg then
        if ok then Toast.Success(msg) else Toast.Warn(msg) end
    end
end

function BagPage.Create()
    -- 预创建固定格子骨架
    slots_ = {}
    local slotWidgets = {}
    for i = 1, BAG_GRID_SIZE do
        table.insert(slotWidgets, CreateSlotSkeleton(i))
    end

    page_ = UI.ScrollView {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        padding = 10,
        children = {
            UI.Panel {
                width = "100%",
                backgroundColor = Colors.cardBg,
                borderRadius = 8, padding = 10, gap = 8,
                children = {
                    UI.Label { text = "背包", fontSize = 13, fontColor = Colors.text, marginBottom = 4 },
                    UI.Panel {
                        id = "bag_grid",
                        flexDirection = "row", flexWrap = "wrap", gap = 6, width = "100%",
                        children = slotWidgets,
                    },
                },
            },
        },
    }

    -- lastBagKey_ 保持 "__INIT__"，确保首次 switchTab 触发内容填充
    return page_
end

function BagPage.Refresh()
    if not page_ then return end

    local curKey = BagKey()
    if curKey == lastBagKey_ then return end
    lastBagKey_ = curKey

    -- 增量更新：遍历格子，按需更新内容，不销毁重建
    local slotIdx = 1
    for _, itemCfg in ipairs(Config.ITEMS) do
        local count = GameState.GetBagItemCount(itemCfg.id)
        if count > 0 then
            UpdateSlot(slotIdx, itemCfg)
            slotIdx = slotIdx + 1
        end
    end
    -- 剩余格子置空
    for i = slotIdx, BAG_GRID_SIZE do
        UpdateSlot(i, nil)
    end
end

function BagPage.InvalidateCache()
    lastBagKey_ = "__FORCE__"
end

return BagPage
