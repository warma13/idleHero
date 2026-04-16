-- ============================================================================
-- ui/TrialResultOverlay.lua - 无尽试炼结算界面 (全屏覆盖)
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local EndlessTrial = require("EndlessTrial")
local SaveSystem = require("SaveSystem")
local Utils = require("Utils")

local TrialResultOverlay = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onCloseCallback_ = nil

function TrialResultOverlay.SetOverlayRoot(root)
    overlayRoot_ = root
end

function TrialResultOverlay.SetCloseCallback(fn)
    onCloseCallback_ = fn
end

function TrialResultOverlay.IsOpen()
    return overlay_ ~= nil
end

function TrialResultOverlay.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

--- 显示结算界面
function TrialResultOverlay.Show()
    if overlay_ then TrialResultOverlay.Close() end

    local et = GameState.endlessTrial
    local result = et.result
    if not result then return end

    local isNewRecord = result.reachedFloor >= result.maxFloor
    local clearedFloor = result.clearedFloor or 0
    local totalExp = result.totalExp or 0

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 240, paddingAll = 16,
                backgroundColor = { 25, 15, 45, 245 },
                borderRadius = 12,
                borderWidth = 1.5,
                borderColor = isNewRecord and { 255, 200, 80, 200 } or { 140, 100, 220, 180 },
                children = {
                    -- 标题
                    UI.Label {
                        text = "试炼结束",
                        fontSize = 20,
                        color = { 255, 200, 150, 255 },
                        textAlign = "center", width = "100%", marginBottom = 6,
                    },
                    -- 新纪录提示
                    isNewRecord and UI.Label {
                        text = "新纪录!",
                        fontSize = 14,
                        color = { 255, 220, 80, 255 },
                        textAlign = "center", width = "100%", marginBottom = 8,
                    } or UI.Panel { height = 0 },
                    -- 到达层数
                    UI.Panel {
                        width = "100%", paddingAll = 10,
                        backgroundColor = { 40, 30, 60, 200 },
                        borderRadius = 6, marginBottom = 6,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label {
                                text = "到达: F" .. result.reachedFloor,
                                fontSize = 22,
                                color = { 220, 180, 255, 255 },
                                textAlign = "center",
                            },
                            UI.Label {
                                text = "已通关: F" .. clearedFloor .. "  |  最高: F" .. result.maxFloor,
                                fontSize = 11,
                                color = { 160, 140, 200, 200 },
                                textAlign = "center", marginTop = 4,
                            },
                        },
                    },
                    -- 获得经验
                    UI.Panel {
                        width = "100%", paddingAll = 8,
                        backgroundColor = { 30, 45, 35, 200 },
                        borderRadius = 6, marginBottom = 10,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label {
                                text = "获得经验",
                                fontSize = 10,
                                color = { 120, 200, 160, 180 },
                                textAlign = "center",
                            },
                            UI.Label {
                                text = "+" .. Utils.FormatNumber(totalExp) .. " EXP",
                                fontSize = 16,
                                color = totalExp > 0 and { 100, 255, 200, 255 } or { 120, 120, 140, 180 },
                                textAlign = "center", marginTop = 2,
                            },
                        },
                    },
                    -- 返回按钮
                    UI.Panel {
                        width = "100%", justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Button {
                                text = "返回主线", variant = "primary",
                                width = 140, height = 36,
                                onClick = function()
                                    TrialResultOverlay.Close()
                                    -- 退出试炼, 恢复主线
                                    GameState.ExitTrial()
                                    SaveSystem.SaveNow()
                                    if onCloseCallback_ then
                                        onCloseCallback_()
                                    end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end
end

return TrialResultOverlay
