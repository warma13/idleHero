-- ============================================================================
-- ui/ChallengePanel.lua - 统一挑战入口面板（Tab切换: 无尽试炼 / 世界Boss）
-- ============================================================================

local UI = require("urhox-libs/UI")
local EndlessTrialPanel = require("ui.EndlessTrialPanel")
local WorldBossPanel = require("ui.WorldBossPanel")
local ResourceDungeonPanel = require("ui.ResourceDungeonPanel")
local SetDungeonPanel = require("ui.SetDungeonPanel")


local ChallengePanel = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
---@type Widget
local contentArea_ = nil

local activeTab_ = "trial"  -- "trial" | "boss" | "mine" | "set"

-- ============================================================================
-- 公开接口
-- ============================================================================

function ChallengePanel.SetOverlayRoot(root)
    overlayRoot_ = root
    EndlessTrialPanel.SetOverlayRoot(root)
    WorldBossPanel.SetOverlayRoot(root)
end

function ChallengePanel.SetTrialStartCallback(fn)
    EndlessTrialPanel.SetStartCallback(fn)
end

function ChallengePanel.SetBossStartCallback(fn)
    WorldBossPanel.SetStartCallback(fn)
    WorldBossPanel.SetDataReadyCallback(function()
        if overlay_ and activeTab_ == "boss" then
            ChallengePanel.Build()
        end
    end)
end

function ChallengePanel.SetMineStartCallback(fn)
    ResourceDungeonPanel.SetStartCallback(fn)
end

function ChallengePanel.SetSetDungeonStartCallback(fn)
    SetDungeonPanel.SetStartCallback(fn)
end



function ChallengePanel.IsOpen()
    return overlay_ ~= nil
end

function ChallengePanel.Close()
    WorldBossPanel.CloseConfirm()
    WorldBossPanel.ResetLeaderboard()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
        contentArea_ = nil
    end
end

function ChallengePanel.Open(tab)
    if overlay_ then ChallengePanel.Close() end
    activeTab_ = tab or "trial"
    ChallengePanel.Build()
end

function ChallengePanel.Toggle()
    if overlay_ then
        ChallengePanel.Close()
    else
        ChallengePanel.Open()
    end
end

--- 刷新世界Boss倒计时（由 main.lua 周期调用）
function ChallengePanel.RefreshTimer()
    WorldBossPanel.RefreshTimer()
end

-- ============================================================================
-- 构建
-- ============================================================================

local function SwitchTab(tab)
    if tab == activeTab_ and contentArea_ then return end
    activeTab_ = tab
    ChallengePanel.Build()
end

function ChallengePanel.Build()
    if overlay_ then overlay_:Destroy(); overlay_ = nil end

    local closeFn = function() ChallengePanel.Close() end

    -- Tab 按钮样式
    local function tabBtn(label, tabId)
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
            },
        }
    end

    -- Tab 栏
    local tabBar = UI.Panel {
        width = "100%",
        flexDirection = "row", justifyContent = "center", alignItems = "center",
        gap = 8, paddingVertical = 8, paddingHorizontal = 8,
        backgroundColor = { 15, 10, 25, 200 },
        borderBottomWidth = 1,
        borderColor = { 80, 60, 120, 100 },
        children = {
            UI.Panel { flexGrow = 1 },  -- 左侧占位
            tabBtn("无尽试炼", "trial"),
            tabBtn("世界Boss", "boss"),
            tabBtn("折光矿脉", "mine"),

            -- tabBtn("套装秘境", "set"),  -- 暂时隐藏，后续完善
            UI.Panel { flexGrow = 1 },  -- 右侧弹性占位
            -- 关闭按钮
            UI.Panel {
                width = 28, height = 28, borderRadius = 14,
                backgroundColor = { 60, 50, 80, 180 },
                justifyContent = "center", alignItems = "center",
                onClick = function() ChallengePanel.Close() end,
                children = {
                    UI.Label { text = "×", fontSize = 16, color = { 200, 190, 220, 230 } },
                },
            },
        },
    }

    -- 内容区
    contentArea_ = UI.Panel {
        width = "100%", flexGrow = 1,
        justifyContent = "center", alignItems = "center",
    }

    -- 填充内容
    if activeTab_ == "trial" then
        EndlessTrialPanel.BuildContent(contentArea_, closeFn)
    elseif activeTab_ == "boss" then
        WorldBossPanel.BuildContent(contentArea_, closeFn)
    elseif activeTab_ == "mine" then
        ResourceDungeonPanel.BuildContent(contentArea_, closeFn)
    elseif activeTab_ == "set" then
        SetDungeonPanel.BuildContent(contentArea_, closeFn)

    end

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() ChallengePanel.Close() end,
        children = {
            UI.Panel {
                maxHeight = "96%",
                backgroundColor = { 18, 14, 32, 250 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = { 100, 70, 160, 150 },
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

return ChallengePanel
