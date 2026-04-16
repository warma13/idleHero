-- ============================================================================
-- ui/SetDungeonPanel.lua - 套装秘境入口面板
-- 供 ChallengePanel 嵌入使用 (BuildContent 模式)
-- ============================================================================

local UI          = require("urhox-libs/UI")
local Config      = require("Config")
local GameState   = require("GameState")
local SetDungeon  = require("SetDungeon")

local SetDungeonPanel = {}

local onStartCallback_ = nil

-- 主题色 (紫色调)
local TC = { 180, 100, 255 }

function SetDungeonPanel.SetStartCallback(fn)
    onStartCallback_ = fn
end

--- 构建内容到指定容器
---@param container Widget
---@param closeCallback function|nil
function SetDungeonPanel.BuildContent(container, closeCallback)
    local closeFn = closeCallback or function() end

    -- 检查解锁
    if not SetDungeon.IsUnlocked() then
        local unlockCh = Config.SET_DUNGEON.UNLOCK_CHAPTER
        container:AddChild(UI.Panel {
            width = 260, paddingAll = 18, alignItems = "center",
            children = {
                UI.Label {
                    text = "套装秘境",
                    fontSize = 18, color = { TC[1], TC[2], TC[3], 255 },
                    textAlign = "center", width = "100%", marginBottom = 12,
                },
                UI.Label {
                    text = "通关第" .. unlockCh .. "章后解锁",
                    fontSize = 13, color = { 160, 160, 180, 200 },
                    textAlign = "center", width = "100%", marginBottom = 16,
                },
                UI.Button {
                    text = "返回", variant = "secondary",
                    width = 100, height = 34,
                    onClick = function() closeFn() end,
                },
            },
        })
        return
    end

    SetDungeon.EnsureState()
    local attemptsLeft = SetDungeon.GetAttemptsLeft()
    local maxAttempts  = SetDungeon.GetMaxAttempts()
    local totalRuns    = GameState.setDungeon and GameState.setDungeon.totalRuns or 0
    local maxChapter   = GameState.records and GameState.records.maxChapter or 1
    local canEnter     = SetDungeon.CanEnter()
    local hardUnlocked = SetDungeon.IsHardUnlocked()
    local availableSets = SetDungeon.GetAvailableSets()

    -- 选择状态
    local selectedSetIdx = 1
    local selectedHard   = false

    -- 套装选择按钮构建
    local setButtons = {}
    local selectedIndicator = nil

    local function buildSetSelector()
        local children = {}
        for i, entry in ipairs(availableSets) do
            local setCfg = entry.setCfg
            local c = setCfg.color or { 200, 200, 200 }
            local isSelected = (i == selectedSetIdx)
            children[#children + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row", alignItems = "center",
                paddingVertical = 6, paddingHorizontal = 10,
                backgroundColor = isSelected and { c[1], c[2], c[3], 40 } or { 30, 30, 45, 120 },
                borderRadius = 6,
                borderWidth = isSelected and 1.5 or 0.5,
                borderColor = isSelected and { c[1], c[2], c[3], 200 } or { 60, 60, 80, 100 },
                marginBottom = 4,
                onClick = function()
                    selectedSetIdx = i
                    -- 重建面板
                    container:RemoveAllChildren()
                    SetDungeonPanel.BuildContent(container, closeCallback)
                end,
                children = {
                    -- 颜色指示器
                    UI.Panel {
                        width = 10, height = 10, borderRadius = 5,
                        backgroundColor = { c[1], c[2], c[3], isSelected and 255 or 120 },
                        marginRight = 8,
                    },
                    -- 套装名称
                    UI.Label {
                        text = setCfg.name,
                        fontSize = 12,
                        color = isSelected and { 255, 255, 255, 255 } or { 180, 180, 200, 200 },
                        flexGrow = 1,
                    },
                    -- 章节标识
                    UI.Label {
                        text = setCfg.chapterRange
                            and ("Ch" .. setCfg.chapterRange[1] .. "-" .. setCfg.chapterRange[2])
                            or ("Ch" .. setCfg.chapter),
                        fontSize = 9,
                        color = { 140, 140, 160, 160 },
                    },
                },
            }
        end
        return children
    end

    -- 构建套装效果预览
    local selectedSet = availableSets[selectedSetIdx]
    local previewChildren = {}
    if selectedSet then
        local bonuses = selectedSet.setCfg.bonuses
        for _, threshold in ipairs({ 2, 4, 6 }) do
            local b = bonuses[threshold]
            if b then
                previewChildren[#previewChildren + 1] = UI.Label {
                    text = "(" .. threshold .. ") " .. b.desc,
                    fontSize = 9, color = { 180, 180, 200, 180 },
                    width = "100%", marginBottom = 2,
                }
            end
        end
    end

    local content = UI.Panel {
        width = 280, paddingAll = 14,
        alignItems = "center",
        children = {
            -- 标题
            UI.Label {
                text = "套装秘境",
                fontSize = 18, color = { TC[1], TC[2], TC[3], 255 },
                textAlign = "center", width = "100%", marginBottom = 4,
            },
            UI.Label {
                text = "定向刷取套装装备",
                fontSize = 11, color = { 160, 170, 200, 200 },
                textAlign = "center", width = "100%", marginBottom = 10,
            },

            -- 状态栏
            UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 25, 35, 55, 200 },
                borderRadius = 6, marginBottom = 8,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 3,
                        children = {
                            UI.Label { text = "剩余次数", fontSize = 11, color = { 160, 170, 200, 200 } },
                            UI.Label {
                                text = attemptsLeft .. "/" .. maxAttempts,
                                fontSize = 13,
                                color = canEnter and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label { text = "累计挑战", fontSize = 10, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = tostring(totalRuns) .. " 次",
                                fontSize = 10, color = { 180, 180, 200, 200 },
                            },
                        },
                    },
                },
            },

            -- 套装选择区
            UI.Label {
                text = "选择目标套装",
                fontSize = 12, color = { TC[1], TC[2], TC[3], 220 },
                width = "100%", marginBottom = 4,
            },
            UI.Panel {
                width = "100%", maxHeight = 160,
                overflow = "scroll",
                marginBottom = 8,
                children = buildSetSelector(),
            },

            -- 套装效果预览
            #previewChildren > 0 and UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 20, 20, 35, 160 },
                borderRadius = 4, marginBottom = 8,
                children = previewChildren,
            } or nil,

            -- 难度选择
            hardUnlocked and UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", alignItems = "center", gap = 10,
                marginBottom = 10,
                children = {
                    UI.Panel {
                        paddingHorizontal = 14, paddingVertical = 5,
                        backgroundColor = (not selectedHard) and { 60, 120, 60, 200 } or { 40, 40, 55, 160 },
                        borderRadius = 5,
                        borderWidth = (not selectedHard) and 1 or 0,
                        borderColor = { 100, 200, 100, 180 },
                        onClick = function()
                            selectedHard = false
                            container:RemoveAllChildren()
                            SetDungeonPanel.BuildContent(container, closeCallback)
                        end,
                        children = {
                            UI.Label { text = "普通", fontSize = 11, color = { 200, 255, 200, 255 } },
                        },
                    },
                    UI.Panel {
                        paddingHorizontal = 14, paddingVertical = 5,
                        backgroundColor = selectedHard and { 120, 50, 50, 200 } or { 40, 40, 55, 160 },
                        borderRadius = 5,
                        borderWidth = selectedHard and 1 or 0,
                        borderColor = { 255, 100, 100, 180 },
                        onClick = function()
                            selectedHard = true
                            container:RemoveAllChildren()
                            SetDungeonPanel.BuildContent(container, closeCallback)
                        end,
                        children = {
                            UI.Label { text = "困难", fontSize = 11, color = { 255, 180, 180, 255 } },
                        },
                    },
                },
            } or nil,

            -- 按钮组
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 12,
                children = {
                    UI.Button {
                        text = canEnter and "进入秘境" or "次数已用完",
                        variant = canEnter and "primary" or "secondary",
                        width = 110, height = 34,
                        disabled = not canEnter,
                        onClick = function()
                            if not canEnter then return end
                            local entry = availableSets[selectedSetIdx]
                            if not entry then return end
                            -- 先调用 EnterFight，再通知外部切换模式
                            if SetDungeon.EnterFight(entry.setId, selectedHard) then
                                closeFn()
                                if onStartCallback_ then onStartCallback_() end
                            end
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

return SetDungeonPanel
