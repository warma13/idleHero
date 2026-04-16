-- ============================================================================
-- ui/RewardPanel.lua - 统一奖励入口面板（Tab切换: 奖励 / 日常）
-- 每个 Tab 保留各自原始面板的独立样式
-- ============================================================================

local UI = require("urhox-libs/UI")
local VersionReward = require("VersionReward")
local DailyRewards  = require("DailyRewards")
local OfflineChest  = require("ui.OfflineChest")

local RewardPanel = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
---@type Widget
local contentArea_ = nil

local activeTab_ = "reward"  -- "reward" | "daily" | "offline"

-- ============================================================================
-- 公开接口
-- ============================================================================

function RewardPanel.SetOverlayRoot(root)
    overlayRoot_ = root
end

function RewardPanel.IsOpen()
    return overlay_ ~= nil
end

function RewardPanel.Close()
    VersionReward.SetEmbeddedRefresh(nil)
    DailyRewards.SetEmbeddedRefresh(nil)
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
        contentArea_ = nil
    end
end

function RewardPanel.Open(tab)
    if overlay_ then RewardPanel.Close() end
    activeTab_ = tab or "reward"
    RewardPanel.Build()
end

function RewardPanel.Toggle()
    if overlay_ then
        RewardPanel.Close()
    else
        RewardPanel.Open()
    end
end

--- 检查是否有任一红点
function RewardPanel.HasRedDot()
    return VersionReward.HasUnclaimedReward()
        or DailyRewards.HasRedDot()
end

-- ============================================================================
-- 构建
-- ============================================================================

local function SwitchTab(tab)
    if tab == activeTab_ and contentArea_ then return end
    activeTab_ = tab
    RewardPanel.Build()
end

function RewardPanel.Build()
    if overlay_ then overlay_:Destroy(); overlay_ = nil end

    local closeFn = function() RewardPanel.Close() end

    -- 刷新函数
    local refreshFn = function() RewardPanel.Build() end
    VersionReward.SetEmbeddedRefresh(refreshFn)
    DailyRewards.SetEmbeddedRefresh(refreshFn)

    -- Tab 按钮样式
    local function tabBtn(label, tabId, hasRedDot)
        local isActive = (tabId == activeTab_)
        return UI.Panel {
            paddingHorizontal = 16, paddingVertical = 6,
            flexShrink = 0,
            backgroundColor = isActive and { 100, 70, 180, 220 } or { 40, 35, 60, 160 },
            borderRadius = 6,
            borderWidth = isActive and 1.5 or 0,
            borderColor = isActive and { 160, 120, 255, 200 } or { 0, 0, 0, 0 },
            onClick = function() SwitchTab(tabId) end,
            children = {
                UI.Label {
                    text = label,
                    fontSize = 13,
                    color = isActive and { 255, 240, 255, 255 } or { 160, 150, 180, 200 },
                },
                hasRedDot and UI.Panel {
                    width = 6, height = 6,
                    backgroundColor = { 255, 60, 60, 255 },
                    borderRadius = 3,
                    position = "absolute", top = 0, right = 0,
                } or nil,
            },
        }
    end

    -- Tab 栏 (独立浮在顶部)
    local tabBar = UI.Panel {
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        gap = 8, paddingVertical = 8, paddingHorizontal = 12,
        children = {
            tabBtn("奖励", "reward", VersionReward.HasUnclaimedReward()),
            tabBtn("日常", "daily", DailyRewards.HasRedDot()),
            -- 关闭按钮
            UI.Panel {
                width = 28, height = 28, borderRadius = 14,
                backgroundColor = { 60, 50, 80, 180 },
                justifyContent = "center", alignItems = "center",
                marginLeft = 4,
                onClick = closeFn,
                children = {
                    UI.Label { text = "×", fontSize = 16, color = { 200, 190, 220, 230 } },
                },
            },
        },
    }

    -- 内容区 (各面板自带卡片样式，overflow hidden 确保卡片不溢出)
    contentArea_ = UI.Panel {
        width = "100%", flexGrow = 1, flexShrink = 1,
        alignItems = "center",
        overflow = "hidden",
    }

    -- 填充内容 (每个 BuildContent 自带完整原始样式)
    if activeTab_ == "reward" then
        VersionReward.BuildContent(contentArea_)
    elseif activeTab_ == "daily" then
        DailyRewards.BuildContent(contentArea_, refreshFn)
    end

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = closeFn,
        children = {
            -- 不再包一层统一卡片，让内容区自己决定样式
            UI.Panel {
                width = "88%", maxWidth = 340,
                maxHeight = "92%",
                alignItems = "center",
                overflow = "hidden",
                onClick = function() end,  -- 阻止冒泡到遮罩
                children = {
                    tabBar,
                    contentArea_,
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end
end

return RewardPanel
