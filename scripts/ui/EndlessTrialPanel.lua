-- ============================================================================
-- ui/EndlessTrialPanel.lua - 无尽试炼入口面板 (全屏覆盖)
-- 双栏布局: 左侧试炼信息 + 右侧排行榜
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local EndlessTrial = require("EndlessTrial")
local StageConfig = require("StageConfig")
local MonsterTemplates = require("MonsterTemplates")

local EndlessTrialPanel = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onStartCallback_ = nil  -- 开始试炼回调

-- 排行榜异步数据
local leaderboardData_ = nil
local leaderboardLoading_ = false
---@type Widget
local leaderboardContainer_ = nil  -- 排行榜区域容器，用于局部刷新

-- 前置声明
local BuildLeaderboard

-- 主题色
local TC = { 140, 100, 220 }

function EndlessTrialPanel.SetOverlayRoot(root)
    overlayRoot_ = root
end

function EndlessTrialPanel.SetStartCallback(fn)
    onStartCallback_ = fn
end

function EndlessTrialPanel.IsOpen()
    return overlay_ ~= nil
end

function EndlessTrialPanel.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
        leaderboardContainer_ = nil
    end
end

function EndlessTrialPanel.Open()
    if overlay_ then EndlessTrialPanel.Close() end
    -- 异步加载排行榜
    leaderboardData_ = nil
    leaderboardLoading_ = true
    EndlessTrial.FetchLeaderboard(function(rankList, myRank, myFloor)
        leaderboardData_ = { ranks = rankList or {}, myRank = myRank, myFloor = myFloor }
        leaderboardLoading_ = false
        -- 局部刷新排行榜区域，避免整个面板重建导致闪烁
        if overlay_ and leaderboardContainer_ then
            leaderboardContainer_:ClearChildren()
            leaderboardContainer_:AddChild(BuildLeaderboard())
        end
    end)
    EndlessTrialPanel.Build()
end

function EndlessTrialPanel.Toggle()
    if overlay_ then
        EndlessTrialPanel.Close()
    else
        EndlessTrialPanel.Open()
    end
end

-- ============================================================================
-- 排行榜面板构建
-- ============================================================================

BuildLeaderboard = function()
    local children = {
        UI.Label {
            text = "最高层排行榜",
            fontSize = 13, color = { TC[1], TC[2], TC[3], 255 },
            textAlign = "center", width = "100%", marginBottom = 8,
        },
    }

    if leaderboardLoading_ then
        table.insert(children, UI.Label {
            text = "加载中...",
            fontSize = 11, color = { 160, 160, 180, 180 },
            textAlign = "center", width = "100%",
        })
    elseif leaderboardData_ then
        local ranks = leaderboardData_.ranks
        if #ranks == 0 then
            table.insert(children, UI.Label {
                text = "暂无数据",
                fontSize = 11, color = { 140, 140, 160, 160 },
                textAlign = "center", width = "100%",
            })
        else
            local showCount = math.min(#ranks, 10)
            for i = 1, showCount do
                local r = ranks[i]
                local rankLabel = "#" .. i
                local nameText = r.nickname or r.name or ("玩家" .. i)
                local floorText = "F" .. (r._floor or 0)
                -- 前3名高亮
                local nameColor = { 180, 180, 200, 220 }
                local rankColor = { 160, 160, 180, 200 }
                if i == 1 then
                    rankColor = { 255, 215, 0, 255 }
                    nameColor = { 255, 230, 150, 255 }
                elseif i == 2 then
                    rankColor = { 200, 210, 220, 255 }
                    nameColor = { 200, 210, 230, 255 }
                elseif i == 3 then
                    rankColor = { 200, 150, 80, 255 }
                    nameColor = { 220, 180, 120, 255 }
                end

                table.insert(children, UI.Panel {
                    width = "100%",
                    flexDirection = "row", alignItems = "center",
                    paddingVertical = 2,
                    children = {
                        UI.Label { text = rankLabel, fontSize = 10, color = rankColor, width = 24 },
                        UI.Label { text = nameText, fontSize = 10, color = nameColor, flexGrow = 1, flexShrink = 1 },
                        UI.Label { text = floorText, fontSize = 10, color = { 255, 200, 100, 220 } },
                    },
                })
            end
        end

        -- 我的排名
        if leaderboardData_.myRank then
            table.insert(children, UI.Panel {
                width = "100%", marginTop = 6, paddingTop = 6,
                borderTopWidth = 1, borderColor = { 80, 70, 100, 120 },
                flexDirection = "row", alignItems = "center",
                children = {
                    UI.Label { text = "#" .. leaderboardData_.myRank, fontSize = 10, color = { 100, 200, 255, 255 }, width = 24 },
                    UI.Label { text = "我", fontSize = 10, color = { 100, 200, 255, 255 }, flexGrow = 1 },
                    UI.Label { text = "F" .. (leaderboardData_.myFloor or 0), fontSize = 10, color = { 255, 200, 100, 255 } },
                },
            })
        end
    end

    return UI.Panel {
        width = "100%", paddingAll = 10,
        backgroundColor = { 15, 12, 25, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { TC[1], TC[2], TC[3], 60 },
        flexShrink = 1, overflow = "scroll",
        children = children,
    }
end

-- ============================================================================
-- 面板构建
-- ============================================================================

--- 构建内容到指定容器（供 ChallengePanel 调用）
--- @param container Widget 内容容器
--- @param closeCallback function|nil 关闭面板回调
function EndlessTrialPanel.BuildContent(container, closeCallback)
    local closeFn = closeCallback or function() EndlessTrialPanel.Close() end
    EndlessTrialPanel.FetchData()

    local maxFloor = GameState.endlessTrial.maxFloor or 0
    local clearedFloor = EndlessTrial.GetClearedFloor()

    local startFloor = math.max(1, clearedFloor + 1)

    local elemNames = { fire = "火", ice = "冰", poison = "毒", arcane = "奥", water = "水", physical = "物理" }
    local elemColors = {
        fire = {255,100,50}, ice = {100,200,255}, poison = {100,220,80},
        arcane = {180,100,255}, water = {60,140,255}, physical = {200,200,200}
    }

    local function getWeakElem(floor)
        local resistId = EndlessTrial.GetFloorResistId(floor)
        local resistBase = MonsterTemplates.Resists[resistId]
        if not resistBase then return "无", "physical" end
        local minVal = math.huge
        local weakKey = nil
        for elem, val in pairs(resistBase) do
            if val < minVal then minVal = val; weakKey = elem end
        end
        if not weakKey or minVal >= 10 then return "无", "physical" end
        return elemNames[weakKey] or weakKey, weakKey
    end

    local function buildFloorRow(floor, label, isCurrent)
        local isBoss = EndlessTrial.IsBossFloor(floor)
        local weakName, weakKey = getWeakElem(floor)
        local scaleMul = EndlessTrial.GetScaleMul(floor)
        local ec = elemColors[weakKey] or {255,255,255}
        local alpha = isCurrent and 255 or 140
        local labelColor = isCurrent and {255, 220, 100, 255} or {140, 140, 160, 200}
        local nameColor = isCurrent and {240, 240, 255, 255} or {160, 160, 180, alpha}
        local weakColor = {ec[1], ec[2], ec[3], alpha}
        local bossTag = isBoss and " [BOSS]" or ""
        local scaleStr = string.format("%.0fx", scaleMul)
        local typeDesc = ""
        if isBoss then
            typeDesc = "Boss"
        else
            local behaviors = EndlessTrial.GetFloorBehaviors(floor)
            local behNames = {}
            local behNameMap = {
                swarm="群攻", bruiser="强袭", glass="脆皮",
                debuffer="减益", tank="坦克", caster="法师", exploder="爆炸"
            }
            for _, bid in ipairs(behaviors) do
                table.insert(behNames, behNameMap[bid] or bid)
            end
            typeDesc = table.concat(behNames, "+")
        end
        return UI.Panel {
            width = "100%", paddingAll = 5,
            backgroundColor = isCurrent and {60, 40, 100, 180} or {0, 0, 0, 0},
            borderRadius = isCurrent and 6 or 0, marginBottom = 2,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4, marginBottom = 2,
                    children = {
                        UI.Label { text = label, fontSize = 9, color = labelColor },
                        UI.Label { text = "F" .. floor .. bossTag, fontSize = isCurrent and 14 or 11,
                            color = isBoss and {255, 80, 80, alpha} or nameColor },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = typeDesc, fontSize = 10, color = nameColor },
                        UI.Label { text = "弱点:" .. weakName, fontSize = 10, color = weakColor },
                        UI.Label { text = scaleStr, fontSize = 9, color = {180, 160, 200, alpha} },
                    },
                },
            },
        }
    end

    local floorRows = {}
    if startFloor > 1 then
        table.insert(floorRows, buildFloorRow(startFloor - 1, "已通关", false))
    end
    table.insert(floorRows, buildFloorRow(startFloor, "当前", true))
    table.insert(floorRows, buildFloorRow(startFloor + 1, "下一层", false))

    local floorPreviewChildren = {
        UI.Label { text = "层次预览", fontSize = 10, color = { 160, 140, 200, 180 },
            textAlign = "center", width = "100%", marginBottom = 4 },
    }
    for _, row in ipairs(floorRows) do
        table.insert(floorPreviewChildren, row)
    end

    local leftColumn = UI.Panel {
        width = 220, paddingAll = 18,
        children = {
            UI.Label { text = "无尽试炼", fontSize = 18, color = { 220, 180, 255, 255 },
                textAlign = "center", width = "100%", marginBottom = 8 },
            UI.Label { text = "挑战无尽层数的怪物，每层更强！\n每10层出现BOSS，限时击败。\n死亡结束试炼，不影响主线进度。",
                fontSize = 11, color = { 180, 170, 200, 200 }, textAlign = "center", width = "100%", marginBottom = 10 },
            UI.Panel { width = "100%", paddingAll = 8, backgroundColor = { 40, 30, 60, 200 },
                borderRadius = 6, marginBottom = 10, justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label { text = "最高到达: F" .. maxFloor, fontSize = 16,
                        color = maxFloor > 0 and { 255, 220, 100, 255 } or { 120, 120, 140, 200 }, textAlign = "center" },
                    UI.Label { text = "已通关: F" .. clearedFloor, fontSize = 12,
                        color = clearedFloor > 0 and { 100, 220, 180, 220 } or { 120, 120, 140, 160 }, textAlign = "center", marginTop = 3 },
                },
            },
            UI.Panel { width = "100%", paddingAll = 6, backgroundColor = { 30, 25, 50, 180 },
                borderRadius = 4, marginBottom = 12, children = floorPreviewChildren },
            UI.Panel { width = "100%", flexDirection = "row", justifyContent = "center", gap = 12,
                children = {
                    UI.Button { text = "开始试炼", variant = "primary", width = 100, height = 34,
                        onClick = function()
                            closeFn()
                            if onStartCallback_ then onStartCallback_() end
                        end },
                    UI.Button { text = "返回", variant = "secondary", width = 70, height = 34,
                        onClick = function() closeFn() end },
                },
            },
        },
    }

    leaderboardContainer_ = UI.Panel { width = "100%", children = { BuildLeaderboard() } }
    local rightColumn = UI.Panel { width = 180, paddingAll = 18, children = { leaderboardContainer_ } }

    local content = UI.Panel {
        maxHeight = "90%", flexDirection = "row",
        backgroundColor = { 20, 15, 40, 245 }, borderRadius = 12,
        borderWidth = 1.5, borderColor = { TC[1], TC[2], TC[3], 180 },
        overflow = "hidden", paddingAll = 6,
        onClick = function() end,
        children = { leftColumn,
            UI.Panel { width = 1, backgroundColor = { TC[1], TC[2], TC[3], 60 }, alignSelf = "stretch" },
            rightColumn },
    }
    container:AddChild(content)
end

--- 异步加载排行榜数据
function EndlessTrialPanel.FetchData()
    leaderboardData_ = nil
    leaderboardLoading_ = true
    EndlessTrial.FetchLeaderboard(function(rankList, myRank, myFloor)
        leaderboardData_ = { ranks = rankList or {}, myRank = myRank, myFloor = myFloor }
        leaderboardLoading_ = false
        if leaderboardContainer_ then
            leaderboardContainer_:ClearChildren()
            leaderboardContainer_:AddChild(BuildLeaderboard())
        end
    end)
end

function EndlessTrialPanel.Build()
    if overlay_ then overlay_:Destroy() end

    local maxFloor = GameState.endlessTrial.maxFloor or 0
    local clearedFloor = EndlessTrial.GetClearedFloor()

    -- 下次进入的起始层
    local startFloor = math.max(1, clearedFloor + 1)

    local elemNames = { fire = "火", ice = "冰", poison = "毒", arcane = "奥", water = "水", physical = "物理" }
    local elemColors = {
        fire = {255,100,50}, ice = {100,200,255}, poison = {100,220,80},
        arcane = {180,100,255}, water = {60,140,255}, physical = {200,200,200}
    }

    --- 获取某层的弱点元素名和key
    local function getWeakElem(floor)
        local resistId = EndlessTrial.GetFloorResistId(floor)
        local resistBase = MonsterTemplates.Resists[resistId]
        if not resistBase then return "无", "physical" end
        local minVal = math.huge
        local weakKey = nil
        for elem, val in pairs(resistBase) do
            if val < minVal then minVal = val; weakKey = elem end
        end
        if not weakKey or minVal >= 10 then return "无", "physical" end
        return elemNames[weakKey] or weakKey, weakKey
    end

    --- 构建单层信息行
    local function buildFloorRow(floor, label, isCurrent)
        local isBoss = EndlessTrial.IsBossFloor(floor)
        local weakName, weakKey = getWeakElem(floor)
        local scaleMul = EndlessTrial.GetScaleMul(floor)
        local ec = elemColors[weakKey] or {255,255,255}

        local alpha = isCurrent and 255 or 140
        local labelColor = isCurrent and {255, 220, 100, 255} or {140, 140, 160, 200}
        local nameColor = isCurrent and {240, 240, 255, 255} or {160, 160, 180, alpha}
        local weakColor = {ec[1], ec[2], ec[3], alpha}

        local bossTag = isBoss and " [BOSS]" or ""
        local scaleStr = string.format("%.0fx", scaleMul)

        -- 行为模板描述
        local typeDesc = ""
        if isBoss then
            typeDesc = "Boss"
        else
            local behaviors = EndlessTrial.GetFloorBehaviors(floor)
            local behNames = {}
            local behNameMap = {
                swarm="群攻", bruiser="强袭", glass="脆皮",
                debuffer="减益", tank="坦克", caster="法师", exploder="爆炸"
            }
            for _, bid in ipairs(behaviors) do
                table.insert(behNames, behNameMap[bid] or bid)
            end
            typeDesc = table.concat(behNames, "+")
        end

        return UI.Panel {
            width = "100%", paddingAll = 5,
            backgroundColor = isCurrent and {60, 40, 100, 180} or {0, 0, 0, 0},
            borderRadius = isCurrent and 6 or 0,
            marginBottom = 2,
            children = {
                -- 第一行: 标签 + 层号
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    marginBottom = 2,
                    children = {
                        UI.Label { text = label, fontSize = 9, color = labelColor },
                        UI.Label {
                            text = "F" .. floor .. bossTag,
                            fontSize = isCurrent and 14 or 11,
                            color = isBoss and {255, 80, 80, alpha} or nameColor,
                        },
                    },
                },
                -- 第二行: 类型 + 弱点 + 倍率
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = typeDesc, fontSize = 10, color = nameColor },
                        UI.Label { text = "弱点:" .. weakName, fontSize = 10, color = weakColor },
                        UI.Label { text = scaleStr, fontSize = 9, color = {180, 160, 200, alpha} },
                    },
                },
            },
        }
    end

    local floorRows = {}
    -- 上一层 (仅 startFloor > 1 时显示)
    if startFloor > 1 then
        table.insert(floorRows, buildFloorRow(startFloor - 1, "已通关", false))
    end
    -- 当前层
    table.insert(floorRows, buildFloorRow(startFloor, "当前", true))
    -- 下一层
    table.insert(floorRows, buildFloorRow(startFloor + 1, "下一层", false))

    -- 层次预览子节点 (避免 table.unpack 陷阱)
    local floorPreviewChildren = {
        UI.Label {
            text = "层次预览",
            fontSize = 10, color = { 160, 140, 200, 180 },
            textAlign = "center", width = "100%", marginBottom = 4,
        },
    }
    for _, row in ipairs(floorRows) do
        table.insert(floorPreviewChildren, row)
    end

    -- ── 左栏: 试炼信息 ──
    local leftColumn = UI.Panel {
        width = 220, paddingAll = 18,
        children = {
            -- 标题
            UI.Label {
                text = "无尽试炼",
                fontSize = 18, color = { 220, 180, 255, 255 },
                textAlign = "center", width = "100%", marginBottom = 8,
            },
            -- 说明
            UI.Label {
                text = "挑战无尽层数的怪物，每层更强！\n每10层出现BOSS，限时击败。\n死亡结束试炼，不影响主线进度。",
                fontSize = 11, color = { 180, 170, 200, 200 },
                textAlign = "center", width = "100%", marginBottom = 10,
            },
            -- 最高纪录 + 已通关
            UI.Panel {
                width = "100%", paddingAll = 8,
                backgroundColor = { 40, 30, 60, 200 },
                borderRadius = 6, marginBottom = 10,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = "最高到达: F" .. maxFloor,
                        fontSize = 16,
                        color = maxFloor > 0 and { 255, 220, 100, 255 } or { 120, 120, 140, 200 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "已通关: F" .. clearedFloor,
                        fontSize = 12,
                        color = clearedFloor > 0 and { 100, 220, 180, 220 } or { 120, 120, 140, 160 },
                        textAlign = "center", marginTop = 3,
                    },
                },
            },
            -- 层次信息预览
            UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 30, 25, 50, 180 },
                borderRadius = 4, marginBottom = 12,
                children = floorPreviewChildren,
            },
            -- 按钮组
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 12,
                children = {
                    UI.Button {
                        text = "开始试炼", variant = "primary",
                        width = 100, height = 34,
                        onClick = function()
                            EndlessTrialPanel.Close()
                            if onStartCallback_ then
                                onStartCallback_()
                            end
                        end,
                    },
                    UI.Button {
                        text = "返回", variant = "secondary",
                        width = 70, height = 34,
                        onClick = function()
                            EndlessTrialPanel.Close()
                        end,
                    },
                },
            },
        },
    }

    -- ── 右栏: 排行榜 ──
    leaderboardContainer_ = UI.Panel {
        width = "100%",
        children = { BuildLeaderboard() },
    }
    local rightColumn = UI.Panel {
        width = 180, paddingAll = 18,
        children = { leaderboardContainer_ },
    }

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        onClick = function() EndlessTrialPanel.Close() end,
        children = {
            UI.Panel {
                maxHeight = "90%",
                flexDirection = "row",
                backgroundColor = { 20, 15, 40, 245 },
                borderRadius = 12,
                borderWidth = 1.5,
                borderColor = { TC[1], TC[2], TC[3], 180 },
                overflow = "hidden",
                paddingAll = 6,
                onClick = function() end,  -- 阻止冒泡
                children = {
                    leftColumn,
                    -- 分隔线
                    UI.Panel {
                        width = 1,
                        backgroundColor = { TC[1], TC[2], TC[3], 60 },
                        alignSelf = "stretch",
                    },
                    rightColumn,
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end
end

return EndlessTrialPanel
