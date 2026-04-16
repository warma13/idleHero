-- ============================================================================
-- ui/ManaForestPanel.lua - 魔力之森入口面板 (独立弹窗)
-- ============================================================================

local UI              = require("urhox-libs/UI")
local Config          = require("Config")
local GameState       = require("GameState")
local ManaForest      = require("ManaForest")

local ManaForestPanel = {}

local onStartCallback_ = nil
local selectedDifficulty_ = "normal"

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil

-- 主题色 (蓝绿色调)
local TC = { 60, 200, 140 }

function ManaForestPanel.SetStartCallback(fn)
    onStartCallback_ = fn
end

function ManaForestPanel.SetOverlayRoot(root)
    overlayRoot_ = root
end

function ManaForestPanel.IsOpen()
    return overlay_ ~= nil
end

function ManaForestPanel.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

function ManaForestPanel.Toggle()
    if overlay_ then
        ManaForestPanel.Close()
    else
        ManaForestPanel.Show()
    end
end

function ManaForestPanel.Show()
    if overlay_ then ManaForestPanel.Close() end
    if not overlayRoot_ then return end

    local contentArea = UI.Panel {
        width = "100%", flexGrow = 1,
        justifyContent = "center", alignItems = "center",
    }
    local closeFn = function() ManaForestPanel.Close() end
    ManaForestPanel.BuildContent(contentArea, closeFn)

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() ManaForestPanel.Close() end,
        children = { contentArea },
    }
    overlayRoot_:AddChild(overlay_)
end

--- 构建内容到指定容器
---@param container Widget 内容容器
---@param closeCallback function|nil 关闭面板回调
function ManaForestPanel.BuildContent(container, closeCallback)
    local closeFn = closeCallback or function() end

    ManaForest.EnsureState()
    local attemptsLeft = ManaForest.GetAttemptsLeft()
    local maxAttempts  = ManaForest.GetMaxAttempts()
    local totalRuns    = GameState.manaForest and GameState.manaForest.totalRuns or 0
    local bestEssence  = GameState.manaForest and GameState.manaForest.bestEssence or 0
    local maxChapter   = GameState.records.maxChapter or 1
    local hardUnlocked = ManaForest.IsHardUnlocked()
    local canEnter, reason = ManaForest.CanEnter()

    -- 难度选择状态
    selectedDifficulty_ = hardUnlocked and selectedDifficulty_ or "normal"

    local MF = Config.MANA_FOREST
    local monsterScale = selectedDifficulty_ == "hard" and MF.HARD_MONSTER_SCALE or MF.MONSTER_SCALE

    -- 难度选择按钮
    local diffButtons = {}
    local normalBtnRef, hardBtnRef

    local function updateDiffButtons()
        if normalBtnRef then
            normalBtnRef:SetStyle({
                backgroundColor = selectedDifficulty_ == "normal"
                    and { TC[1], TC[2], TC[3], 180 }
                    or { 40, 50, 70, 180 },
            })
        end
        if hardBtnRef then
            hardBtnRef:SetStyle({
                backgroundColor = selectedDifficulty_ == "hard"
                    and { 200, 100, 80, 180 }
                    or { 40, 50, 70, 180 },
            })
        end
    end

    normalBtnRef = UI.Panel {
        width = 70, height = 28, borderRadius = 6,
        backgroundColor = selectedDifficulty_ == "normal"
            and { TC[1], TC[2], TC[3], 180 }
            or { 40, 50, 70, 180 },
        justifyContent = "center", alignItems = "center",
        onClick = function()
            selectedDifficulty_ = "normal"
            updateDiffButtons()
        end,
        children = {
            UI.Label { text = "普通", fontSize = 12, color = { 255, 255, 255, 240 } },
        },
    }
    table.insert(diffButtons, normalBtnRef)

    if hardUnlocked then
        hardBtnRef = UI.Panel {
            width = 70, height = 28, borderRadius = 6,
            backgroundColor = selectedDifficulty_ == "hard"
                and { 200, 100, 80, 180 }
                or { 40, 50, 70, 180 },
            justifyContent = "center", alignItems = "center",
            onClick = function()
                selectedDifficulty_ = "hard"
                updateDiffButtons()
            end,
            children = {
                UI.Label { text = "困难", fontSize = 12, color = { 255, 255, 255, 240 } },
            },
        }
        table.insert(diffButtons, hardBtnRef)
    end

    -- 构建内容
    local content = UI.Panel {
        width = 280, paddingAll = 18,
        backgroundColor = { 18, 22, 34, 245 },
        borderRadius = 12, borderWidth = 1.5,
        borderColor = { TC[1], TC[2], TC[3], 180 },
        alignItems = "center",
        onClick = function() end,  -- 阻止冒泡关闭
        children = {
            -- 标题
            UI.Label {
                text = "魔力之森",
                fontSize = 18, color = { TC[1], TC[2], TC[3], 255 },
                textAlign = "center", width = "100%", marginBottom = 4,
            },
            -- 说明
            UI.Label {
                text = "击杀异变生物，收集魔力精华\n精华越多增益越强，获取更多奖励",
                fontSize = 11, color = { 160, 170, 200, 200 },
                textAlign = "center", width = "100%", marginBottom = 12,
            },
            -- 难度选择
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 10,
                marginBottom = 12,
                children = diffButtons,
            },
            -- 状态面板
            UI.Panel {
                width = "100%", paddingAll = 8,
                backgroundColor = { 25, 35, 55, 200 },
                borderRadius = 6, marginBottom = 12,
                children = {
                    -- 剩余次数
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Label { text = "今日剩余", fontSize = 12, color = { 160, 170, 200, 200 } },
                            UI.Label {
                                text = attemptsLeft .. "/" .. maxAttempts,
                                fontSize = 14,
                                color = attemptsLeft > 0
                                    and { 100, 220, 100, 255 }
                                    or { 200, 80, 80, 255 },
                            },
                        },
                    },
                    -- 最高精华
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Label { text = "最高精华", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = bestEssence > 0 and tostring(bestEssence) or "--",
                                fontSize = 11, color = { 180, 200, 255, 200 },
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
                            UI.Label { text = "怪物缩放", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = "第" .. maxChapter .. "章 x" .. string.format("%.2f", monsterScale),
                                fontSize = 11, color = { 180, 180, 200, 200 },
                            },
                        },
                    },
                },
            },
            -- 奖励预览
            UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 20, 30, 50, 160 },
                borderRadius = 4, marginBottom = 12,
                children = {
                    UI.Label {
                        text = "奖励预览: 魔力药水 + 森之露 + 金币经验",
                        fontSize = 10, color = { 140, 180, 160, 200 },
                        textAlign = "center", width = "100%",
                    },
                },
            },
            -- 按钮组
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 12,
                children = {
                    (function()
                        -- 次数用完但可看广告 → 广告按钮
                        if attemptsLeft <= 0 and ManaForest.CanAddBonusAttempt() then
                            return UI.Button {
                                text = "▶ 看广告 +1次", variant = "primary",
                                width = 130, height = 34,
                                onClick = function()
                                    local ok2, sdk = pcall(require, "urhox-libs.Platform.PlatformSDK")
                                    if ok2 and sdk and sdk.ShowRewardVideoAd then
                                        sdk:ShowRewardVideoAd(function(rewarded)
                                            if rewarded then
                                                ManaForest.AddBonusAttempt()
                                                container:RemoveAllChildren()
                                                ManaForestPanel.BuildContent(container, closeCallback)
                                            end
                                        end)
                                    end
                                end,
                            }
                        else
                            return UI.Button {
                                text = canEnter and "进入森林" or (reason or "无法进入"),
                                variant = canEnter and "primary" or "secondary",
                                width = 110, height = 34,
                                disabled = not canEnter,
                                onClick = function()
                                    if not canEnter then return end
                                    closeFn()
                                    ManaForest.EnterFight(selectedDifficulty_)
                                    if onStartCallback_ then onStartCallback_() end
                                end,
                            }
                        end
                    end)(),
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

return ManaForestPanel
