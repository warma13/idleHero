-- ============================================================================
-- ui/StageSelect.lua - 关卡选择面板（全屏覆盖，按章节显示，左右切换）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local StageConfig = require("StageConfig")

local StageSelect = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local viewChapter_ = 1  -- 当前查看的章节
local onJumpCallback_ = nil  -- 跳转回调

function StageSelect.SetOverlayRoot(root)
    overlayRoot_ = root
end

--- 设置跳转回调（由 main.lua 注入）
function StageSelect.SetJumpCallback(fn)
    onJumpCallback_ = fn
end

function StageSelect.IsOpen()
    return overlay_ ~= nil
end

function StageSelect.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

function StageSelect.Open()
    if overlay_ then StageSelect.Close() end
    viewChapter_ = GameState.stage.chapter
    StageSelect.Build()
end

function StageSelect.Toggle()
    if overlay_ then
        StageSelect.Close()
    else
        StageSelect.Open()
    end
end

function StageSelect.Build()
    if overlay_ then overlay_:Destroy() end

    local totalChapters = StageConfig.GetChapterCount()
    local ch = StageConfig.CHAPTERS[viewChapter_]
    if not ch then return end

    local gs = GameState.stage
    local curChapter = gs.chapter
    local curStage = gs.stage
    -- 用历史最高记录判断"已通关"，避免跳回旧关后丢失通关状态
    local maxCh = GameState.records and GameState.records.maxChapter or curChapter
    local maxSt = GameState.records and GameState.records.maxStage or curStage

    -- 关卡按钮列表 (两列网格)
    local stageButtons = {}
    local stageCount = StageConfig.GetStageCount(viewChapter_)
    for i = 1, stageCount do
        local stageCfg = StageConfig.GetStage(viewChapter_, i)
        local isCurrent = (viewChapter_ == curChapter and i == curStage)
        -- 已解锁: 在历史最高记录范围内
        local isUnlocked = (viewChapter_ < maxCh) or (viewChapter_ == maxCh and i <= maxSt)
        local isCleared = isUnlocked and not isCurrent
        local isLocked = not isUnlocked and not isCurrent
        local isBoss = stageCfg.isBoss or false

        local bgColor
        if isCurrent then
            bgColor = { 40, 100, 180, 220 }
        elseif isCleared then
            bgColor = { 35, 70, 35, 200 }
        elseif isLocked then
            bgColor = { 35, 35, 45, 150 }
        else
            bgColor = { 45, 50, 65, 200 }
        end

        local stageIdx = i
        local stageLabel = viewChapter_ .. "-" .. i
        local stageName = stageCfg.name or ""
        table.insert(stageButtons, UI.Panel {
            width = "48%", height = 60,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            gap = 1,
            backgroundColor = bgColor,
            borderRadius = 8,
            borderWidth = isCurrent and 2 or (isBoss and 1 or 0),
            borderColor = isCurrent and { 100, 180, 255, 255 } or { 200, 160, 60, 180 },
            onClick = (not isLocked) and function()
                if onJumpCallback_ then
                    onJumpCallback_(viewChapter_, stageIdx)
                end
                StageSelect.Close()
            end or nil,
            children = {
                -- 关卡编号
                UI.Label {
                    text = stageLabel,
                    fontSize = 14, fontColor = isBoss and { 255, 180, 60, isLocked and 100 or 240 } or { 255, 255, 255, isLocked and 100 or 230 },
                    textAlign = "center",
                },
                -- 关卡名称
                UI.Label {
                    text = stageName,
                    fontSize = 9,
                    fontColor = isBoss and { 255, 200, 100, isLocked and 80 or 200 } or { 200, 200, 210, isLocked and 80 or 170 },
                    textAlign = "center",
                },
                -- 状态标记
                UI.Label {
                    text = isCurrent and "当前" or (isCleared and "已通关" or (isLocked and "未解锁" or "")),
                    fontSize = 9,
                    fontColor = isCurrent and { 100, 200, 255, 230 } or (isCleared and { 100, 200, 100, 200 } or { 150, 150, 160, 150 }),
                    textAlign = "center",
                },
            },
        })
    end

    -- 章节切换：可查看当前章节前后各一章
    local minView = math.max(1, curChapter - 1)
    local maxView = math.min(totalChapters, curChapter + 1)
    local canPrev = viewChapter_ > minView
    local canNext = viewChapter_ < maxView

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        zIndex = 500,
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() StageSelect.Close() end,
        children = {
            -- 主面板
            UI.Panel {
                width = "88%", height = "75%",
                flexDirection = "column",
                borderRadius = 10,
                overflow = "hidden",
                onClick = function() end,  -- 阻止冒泡
                children = {
                    -- 背景图层 + 内容叠加
                    UI.Panel {
                        width = "100%", height = "100%",
                        flexDirection = "column",
                        backgroundImage = "Textures/stage_map_bg_ch" .. ((viewChapter_ - 1) % 17 + 1) .. ".png",
                        backgroundFit = "cover",
                        children = {
                            -- 半透明遮罩让文字可读
                            UI.Panel {
                                width = "100%", height = "100%",
                                flexDirection = "column",
                                backgroundColor = { 10, 12, 20, 180 },
                                children = {
                                    -- 标题栏（左右箭头切换章节）
                                    UI.Panel {
                                        width = "100%", height = 44,
                                        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                                        paddingHorizontal = 8,
                                        backgroundColor = { 20, 24, 38, 220 },
                                        borderBottomWidth = 1, borderBottomColor = { 80, 70, 50, 150 },
                                        children = {
                                            -- 左箭头
                                            UI.Panel {
                                                width = 36, height = 36,
                                                alignItems = "center", justifyContent = "center",
                                                borderRadius = 18,
                                                backgroundColor = canPrev and { 60, 60, 80, 200 } or { 40, 40, 50, 100 },
                                                onClick = canPrev and function()
                                                    viewChapter_ = viewChapter_ - 1
                                                    StageSelect.Build()
                                                end or nil,
                                                children = {
                                                    UI.Label {
                                                        text = "<",
                                                        fontSize = 18,
                                                        fontColor = canPrev and { 255, 255, 255, 230 } or { 100, 100, 110, 100 },
                                                    },
                                                },
                                            },
                                            -- 章节标题
                                            UI.Label {
                                                text = "第" .. viewChapter_ .. "章 " .. ch.name,
                                                fontSize = 15, fontColor = { 255, 220, 150, 240 },
                                                textAlign = "center",
                                                flexShrink = 1,
                                            },
                                            -- 右箭头
                                            UI.Panel {
                                                width = 36, height = 36,
                                                alignItems = "center", justifyContent = "center",
                                                borderRadius = 18,
                                                backgroundColor = canNext and { 60, 60, 80, 200 } or { 40, 40, 50, 100 },
                                                onClick = canNext and function()
                                                    viewChapter_ = viewChapter_ + 1
                                                    StageSelect.Build()
                                                end or nil,
                                                children = {
                                                    UI.Label {
                                                        text = ">",
                                                        fontSize = 18,
                                                        fontColor = canNext and { 255, 255, 255, 230 } or { 100, 100, 110, 100 },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                    -- 个人最佳 + 章节描述
                                    UI.Panel {
                                        width = "100%",
                                        paddingHorizontal = 12, paddingVertical = 4,
                                        flexDirection = "row", alignItems = "center",
                                        justifyContent = "space-between",
                                        children = {
                                            UI.Label {
                                                text = ch.desc or "",
                                                fontSize = 10, fontColor = { 180, 180, 200, 180 },
                                            },
                                            UI.Panel {
                                                flexDirection = "row", alignItems = "center", gap = 8,
                                                children = {
                                                    UI.Label {
                                                        text = "最高IP:" .. (GameState.records and GameState.records.maxPower or 0),
                                                        fontSize = 9, fontColor = { 255, 200, 100, 200 },
                                                    },
                                                    UI.Label {
                                                        text = "最高关卡:" .. (GameState.records and (GameState.records.maxChapter .. "-" .. GameState.records.maxStage) or "1-1"),
                                                        fontSize = 9, fontColor = { 100, 200, 255, 200 },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                    -- 关卡列表（可滚动，两列网格）+ 章节故事
                                    UI.ScrollView {
                                        width = "100%", flexGrow = 1,
                                        paddingHorizontal = 6, paddingVertical = 6,
                                        children = {
                                            -- 关卡网格
                                            UI.Panel {
                                                width = "100%",
                                                flexDirection = "row",
                                                flexWrap = "wrap",
                                                justifyContent = "space-between",
                                                gap = 6,
                                                children = stageButtons,
                                            },
                                            -- 章节背景故事卡片
                                            ch.lore and UI.Panel {
                                                width = "100%",
                                                marginTop = 12,
                                                paddingHorizontal = 10, paddingVertical = 10,
                                                backgroundColor = { 15, 10, 25, 180 },
                                                borderRadius = 8,
                                                borderWidth = 1,
                                                borderColor = { 80, 60, 120, 120 },
                                                flexDirection = "column",
                                                gap = 6,
                                                children = {
                                                    -- 标题
                                                    UI.Panel {
                                                        width = "100%",
                                                        flexDirection = "row", alignItems = "center", gap = 6,
                                                        paddingBottom = 4,
                                                        borderBottomWidth = 1,
                                                        borderBottomColor = { 80, 60, 120, 80 },
                                                        children = {
                                                            UI.Label {
                                                                text = "章节故事",
                                                                fontSize = 16,
                                                                fontColor = { 200, 170, 255, 230 },
                                                            },
                                                        },
                                                    },
                                                    -- 故事正文
                                                    UI.Label {
                                                        text = ch.lore,
                                                        fontSize = 15,
                                                        fontColor = { 190, 185, 210, 200 },
                                                        textAlign = "left",
                                                    },
                                                },
                                            } or nil,
                                        },
                                    },
                                    -- 底部关闭按钮
                                    UI.Panel {
                                        width = "100%", height = 40,
                                        alignItems = "center", justifyContent = "center",
                                        backgroundColor = { 20, 24, 38, 220 },
                                        borderTopWidth = 1, borderTopColor = { 80, 70, 50, 150 },
                                        children = {
                                            UI.Panel {
                                                width = 80, height = 28,
                                                alignItems = "center", justifyContent = "center",
                                                backgroundColor = { 80, 50, 50, 200 },
                                                borderRadius = 14,
                                                onClick = function() StageSelect.Close() end,
                                                children = {
                                                    UI.Label { text = "关闭", fontSize = 12, fontColor = { 255, 255, 255, 230 } },
                                                },
                                            },
                                        },
                                    },
                                },
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

return StageSelect
