-- ============================================================================
-- ui/ResourceDungeonPanel.lua - 折光矿脉入口面板
-- 供 ChallengePanel 嵌入使用 (BuildContent 模式)
-- ============================================================================

local UI                    = require("urhox-libs/UI")
local GameState             = require("GameState")
local ResourceDungeon       = require("ResourceDungeon")
local ResourceDungeonResult = require("ui.ResourceDungeonResult")

local ResourceDungeonPanel = {}

local onStartCallback_ = nil

-- 主题色 (蓝色调)
local TC = { 80, 160, 255 }

function ResourceDungeonPanel.SetStartCallback(fn)
    onStartCallback_ = fn
end

--- 构建内容到指定容器（供 ChallengePanel 调用）
--- @param container Widget 内容容器
--- @param closeCallback function|nil 关闭面板回调
function ResourceDungeonPanel.BuildContent(container, closeCallback)
    local closeFn = closeCallback or function() end

    ResourceDungeon.EnsureState()
    local attemptsLeft = ResourceDungeon.GetAttemptsLeft()
    local maxAttempts  = ResourceDungeon.GetMaxAttempts()
    local totalRuns    = GameState.resourceDungeon and GameState.resourceDungeon.totalRuns or 0
    local maxChapter   = GameState.records.maxChapter or 1
    local isBonusRun   = ResourceDungeon.IsBonusRun()
    local canStart     = true  -- 始终可进入

    -- 直接往 container 里放内容，不加额外外壳
    local content = UI.Panel {
        width = 260, paddingAll = 18,
        alignItems = "center",
        children = {
            -- 标题
            UI.Label {
                text = "折光矿脉",
                fontSize = 18, color = { TC[1], TC[2], TC[3], 255 },
                textAlign = "center", width = "100%", marginBottom = 8,
            },
            -- 说明
            UI.Label {
                text = "限时60秒击杀矿脉守卫\n获取宝石与散光棱镜\n前" .. maxAttempts .. "次丰厚奖励，之后概率掉落",
                fontSize = 11, color = { 160, 170, 200, 200 },
                textAlign = "center", width = "100%", marginBottom = 14,
            },
            -- 状态面板
            UI.Panel {
                width = "100%", paddingAll = 8,
                backgroundColor = { 25, 35, 55, 200 },
                borderRadius = 6, marginBottom = 16,
                children = {
                    -- 剩余次数 / 额外探索提示
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Label {
                                text = isBonusRun and "额外探索" or "丰厚奖励",
                                fontSize = 12, color = { 160, 170, 200, 200 },
                            },
                            UI.Label {
                                text = isBonusRun and "概率掉落" or (attemptsLeft .. "/" .. maxAttempts),
                                fontSize = 14,
                                color = isBonusRun and { 200, 180, 100, 255 } or { 100, 220, 100, 255 },
                            },
                        },
                    },
                    -- 累计挑战
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Label { text = "累计探索", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = tostring(totalRuns) .. " 次",
                                fontSize = 11, color = { 180, 180, 200, 200 },
                            },
                        },
                    },
                    -- 怪物强度
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label { text = "怪物基准", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = "第" .. maxChapter .. "章 x0.9",
                                fontSize = 11, color = { 180, 180, 200, 200 },
                            },
                        },
                    },
                },
            },
            -- 连续挑战开关
            (function()
                local isOn = ResourceDungeonResult.IsAutoContinue()
                local toggleLabel = UI.Label {
                    text = isOn and "ON" or "OFF", fontSize = 10,
                    color = isOn and { 100, 220, 100, 255 } or { 160, 160, 180, 200 },
                }
                local toggleTrack = UI.Panel {
                    width = 28, height = 16, borderRadius = 8,
                    backgroundColor = isOn and { 60, 160, 80, 220 } or { 60, 65, 80, 200 },
                    borderWidth = 1,
                    borderColor = isOn and { 80, 200, 100, 180 } or { 80, 85, 100, 150 },
                    justifyContent = "center",
                    alignItems = isOn and "flex-end" or "flex-start",
                    paddingHorizontal = 2,
                    children = {
                        UI.Panel { width = 12, height = 12, borderRadius = 6, backgroundColor = { 220, 220, 230, 255 } },
                    },
                }
                return UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "center", alignItems = "center", gap = 8,
                    marginBottom = 8,
                    onClick = function()
                        local newVal = not ResourceDungeonResult.IsAutoContinue()
                        ResourceDungeonResult.SetAutoContinue(newVal)
                        toggleLabel:SetText(newVal and "ON" or "OFF")
                        toggleLabel:SetFontColor(newVal and { 100, 220, 100, 255 } or { 160, 160, 180, 200 })
                        toggleTrack:SetStyle({
                            backgroundColor = newVal and { 60, 160, 80, 220 } or { 60, 65, 80, 200 },
                            borderColor = newVal and { 80, 200, 100, 180 } or { 80, 85, 100, 150 },
                            alignItems = newVal and "flex-end" or "flex-start",
                        })
                    end,
                    children = { toggleTrack, UI.Label { text = "连续挑战", fontSize = 11, color = { 180, 190, 210, 220 } }, toggleLabel },
                }
            end)(),
            -- 按钮组
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 12,
                children = {
                    UI.Button {
                        text = isBonusRun and "额外探索" or "进入矿脉",
                        variant = "primary",
                        width = 110, height = 34,
                        onClick = function()
                            closeFn()
                            if onStartCallback_ then onStartCallback_() end
                        end,
                    },
                    UI.Button {
                        text = "返回", variant = "secondary",
                        width = 70, height = 34,
                        onClick = function() closeFn() end,
                    },
                },
            },
        },
    }
    container:AddChild(content)
end

return ResourceDungeonPanel
