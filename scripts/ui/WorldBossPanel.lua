-- ============================================================================
-- ui/WorldBossPanel.lua - 世界Boss入口面板 (全屏覆盖)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")
local WorldBoss = require("WorldBoss")
local GameState = require("GameState")

local Utils = require("Utils")

local WorldBossPanel = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onStartCallback_ = nil

-- 排行榜异步数据
local leaderboardData_ = nil
local leaderboardLoading_ = false
local onDataReady_ = nil  -- 外部重建回调 (ChallengePanel 嵌入模式)

-- 倒计时 Label 引用
---@type Label
local timerLabel_ = nil

-- 消耗券确认弹窗
---@type Widget
local confirmOverlay_ = nil

-- ============================================================================
-- Boss图片 NanoVG Widget
-- ============================================================================

---@class BossIconWidget : Widget
local BossIconWidget = Widget:Extend("BossIconWidget")

function BossIconWidget:Init(props)
    Widget.Init(self, props)
    self._imgHandle = nil
end

function BossIconWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    if not self._imgHandle and self.props.imageSrc then
        self._imgHandle = nvgCreateImage(nvg, self.props.imageSrc, 0)
    end

    local bc = self.props.borderColor or { 200, 200, 200 }
    local radius = math.min(l.w, l.h) / 2

    -- 背景圆
    nvgBeginPath(nvg)
    nvgCircle(nvg, l.x + l.w / 2, l.y + l.h / 2, radius)
    nvgFillColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], 40))
    nvgFill(nvg)

    -- Boss图片
    if self._imgHandle and self._imgHandle > 0 then
        local imgPaint = nvgImagePattern(nvg, l.x, l.y, l.w, l.h, 0, self._imgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgCircle(nvg, l.x + l.w / 2, l.y + l.h / 2, radius - 1)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    else
        -- fallback: 文字
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 14)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
        nvgText(nvg, l.x + l.w / 2, l.y + l.h / 2, "BOSS")
    end

    -- 边框
    nvgBeginPath(nvg)
    nvgCircle(nvg, l.x + l.w / 2, l.y + l.h / 2, radius)
    nvgStrokeColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], 180))
    nvgStrokeWidth(nvg, 1.5)
    nvgStroke(nvg)
end

-- ============================================================================
-- 公开接口
-- ============================================================================

function WorldBossPanel.SetOverlayRoot(root)
    overlayRoot_ = root
end

function WorldBossPanel.SetStartCallback(fn)
    onStartCallback_ = fn
end

function WorldBossPanel.IsOpen()
    return overlay_ ~= nil
end

function WorldBossPanel.CloseConfirm()
    if confirmOverlay_ then
        confirmOverlay_:Destroy()
        confirmOverlay_ = nil
    end
end

function WorldBossPanel.Close()
    WorldBossPanel.CloseConfirm()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
    timerLabel_ = nil
    leaderboardData_ = nil
    leaderboardLoading_ = false
end

--- 重置排行榜缓存 (ChallengePanel 关闭时调用)
function WorldBossPanel.ResetLeaderboard()
    leaderboardData_ = nil
    leaderboardLoading_ = false
end

--- 消耗券确认弹窗
local function ShowTicketConfirm(ticketCount)
    WorldBossPanel.CloseConfirm()
    if not overlay_ then return end

    confirmOverlay_ = UI.Panel {
        position = "absolute", width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() WorldBossPanel.CloseConfirm() end,
        children = {
            UI.Panel {
                width = 240,
                backgroundColor = { 35, 30, 50, 245 },
                borderRadius = 10, paddingAll = 16, gap = 10,
                alignItems = "center",
                borderWidth = 1,
                borderColor = { 255, 200, 80, 120 },
                onClick = function() end, -- 阻止冒泡
                children = {
                    UI.Panel {
                        width = 36, height = 36,
                        backgroundImage = "item_wb_ticket_20260310175942.png",
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        text = "消耗挑战券",
                        fontSize = 14,
                        color = { 255, 220, 100, 255 },
                    },
                    UI.Label {
                        text = "免费次数已用完，是否消耗1张挑战券？\n(剩余 " .. ticketCount .. " 张)",
                        fontSize = 11,
                        color = { 180, 180, 200, 220 },
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 4,
                        children = {
                            UI.Button {
                                text = "确认挑战", height = 30, fontSize = 11,
                                width = 90, variant = "primary",
                                onClick = function()
                                    WorldBossPanel.CloseConfirm()
                                    WorldBossPanel.Close()
                                    if onStartCallback_ then
                                        onStartCallback_()
                                    end
                                end,
                            },
                            UI.Button {
                                text = "取消", height = 30, fontSize = 11,
                                width = 80,
                                backgroundColor = { 60, 65, 80, 200 },
                                onClick = function() WorldBossPanel.CloseConfirm() end,
                            },
                        },
                    },
                },
            },
        },
    }
    overlay_:AddChild(confirmOverlay_)
end

--- 外部定时调用：刷新倒计时（由 main.lua 的 UI 刷新周期驱动）
function WorldBossPanel.RefreshTimer()
    if not overlay_ or not timerLabel_ then return end
    local remaining = WorldBoss.GetSeasonRemaining()
    timerLabel_:SetText("赛季剩余: " .. WorldBoss.FormatTime(remaining))
end

function WorldBossPanel.Open()
    if overlay_ then WorldBossPanel.Close() end
    -- 异步加载排行榜
    leaderboardData_ = nil
    leaderboardLoading_ = true
    WorldBoss.FetchLeaderboard(function(rankList, myRank, myDamage)
        leaderboardData_ = { ranks = rankList or {}, myRank = myRank, myDamage = myDamage }
        leaderboardLoading_ = false
        if overlay_ then
            WorldBossPanel.Build()
        end
    end)
    WorldBossPanel.Build()
end

function WorldBossPanel.Toggle()
    if overlay_ then
        WorldBossPanel.Close()
    else
        WorldBossPanel.Open()
    end
end

--- 格式化大数字 (统一调用 Utils.FormatNumber)
--- 防护: 如果伤害值为 inf/NaN，显示为 "0" 而非 "∞"
local function FormatDamage(n)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
        return "0"
    end
    return Utils.FormatNumber(n)
end

-- ============================================================================
-- 构建排行榜面板
-- ============================================================================

local function BuildLeaderboard(bc)
    local children = {
        UI.Label {
            text = "伤害排行榜",
            fontSize = 13, color = { bc[1], bc[2], bc[3], 255 },
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
            -- 前10名
            local showCount = math.min(#ranks, 10)
            for i = 1, showCount do
                local r = ranks[i]
                local rankLabel = "#" .. i
                local nameText = r.nickname or r.name or ("玩家" .. i)
                local dmgText = FormatDamage(r._realDamage or 0)
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
                        UI.Label { text = dmgText, fontSize = 10, color = { 255, 200, 100, 220 } },
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
                    UI.Label { text = FormatDamage(leaderboardData_.myDamage or 0), fontSize = 10, color = { 255, 200, 100, 255 } },
                },
            })
        end
    end

    return UI.Panel {
        width = "100%", paddingAll = 10,
        backgroundColor = { 15, 12, 25, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { bc[1], bc[2], bc[3], 60 },
        flexShrink = 1, overflow = "scroll",
        children = children,
    }
end

-- ============================================================================
-- 构建面板
-- ============================================================================

--- 构建内容到指定容器（供 ChallengePanel 调用）
--- @param container Widget 内容容器
--- @param closeCallback function|nil 关闭面板回调
function WorldBossPanel.BuildContent(container, closeCallback)
    local closeFn = closeCallback or function() WorldBossPanel.Close() end
    if not leaderboardData_ and not leaderboardLoading_ then
        WorldBossPanel.FetchData()
    end
    WorldBoss.EnsureState()

    local bossCfg = WorldBoss.GetCurrentBoss()
    local bc = bossCfg.color
    local attemptsLeft = WorldBoss.GetAttemptsLeft()
    local ticketCount = GameState.GetBagItemCount("wb_ticket")
    local canFight = attemptsLeft > 0 or ticketCount > 0
    local totalDamage = WorldBoss.GetTotalDamage()
    local remaining = WorldBoss.GetSeasonRemaining()
    local elemNames = { fire = "火焰", ice = "冰霜", poison = "剧毒", arcane = "奥术" }

    local rewardRows = {}
    for _, r in ipairs(WorldBoss.RANK_REWARDS) do
        local parts = {}
        if r.prisms and r.prisms > 0 then table.insert(parts, r.prisms .. "散光棱镜") end
        if r.chippedGems and r.chippedGems > 0 then table.insert(parts, r.chippedGems .. "碎裂宝石") end
        table.insert(rewardRows, UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", paddingVertical = 2,
            children = {
                UI.Label { text = r.label, fontSize = 10, color = { 180, 170, 200, 200 } },
                UI.Label { text = table.concat(parts, " + "), fontSize = 10, color = { 255, 220, 100, 220 } },
            },
        })
    end
    local rewardChildren = {
        UI.Label { text = "赛季排名奖励", fontSize = 10, color = { 180, 160, 220, 200 },
            textAlign = "center", width = "100%", marginBottom = 4 },
    }
    for _, row in ipairs(rewardRows) do table.insert(rewardChildren, row) end

    timerLabel_ = UI.Label {
        text = "赛季剩余: " .. WorldBoss.FormatTime(remaining),
        fontSize = 10, color = { 180, 180, 200, 180 }, textAlign = "center", width = "100%", marginBottom = 10,
    }

    -- 消耗券确认（嵌入 container 父级）
    local function showTicketConfirmInContainer(tCount)
        if confirmOverlay_ then confirmOverlay_:Destroy(); confirmOverlay_ = nil end
        confirmOverlay_ = UI.Panel {
            position = "absolute", width = "100%", height = "100%",
            backgroundColor = { 0, 0, 0, 160 }, justifyContent = "center", alignItems = "center",
            onClick = function() if confirmOverlay_ then confirmOverlay_:Destroy(); confirmOverlay_ = nil end end,
            children = {
                UI.Panel {
                    width = 240, backgroundColor = { 35, 30, 50, 245 }, borderRadius = 10, paddingAll = 16, gap = 10,
                    alignItems = "center", borderWidth = 1, borderColor = { 255, 200, 80, 120 },
                    onClick = function() end,
                    children = {
                        UI.Panel { width = 36, height = 36, backgroundImage = "item_wb_ticket_20260310175942.png", backgroundFit = "contain" },
                        UI.Label { text = "消耗挑战券", fontSize = 14, color = { 255, 220, 100, 255 } },
                        UI.Label { text = "免费次数已用完，是否消耗1张挑战券？\n(剩余 " .. tCount .. " 张)",
                            fontSize = 11, color = { 180, 180, 200, 220 }, textAlign = "center" },
                        UI.Panel { flexDirection = "row", gap = 12, marginTop = 4, children = {
                            UI.Button { text = "确认挑战", height = 30, fontSize = 11, width = 90, variant = "primary",
                                onClick = function()
                                    if confirmOverlay_ then confirmOverlay_:Destroy(); confirmOverlay_ = nil end
                                    closeFn()
                                    if onStartCallback_ then onStartCallback_() end
                                end },
                            UI.Button { text = "取消", height = 30, fontSize = 11, width = 80,
                                backgroundColor = { 60, 65, 80, 200 },
                                onClick = function() if confirmOverlay_ then confirmOverlay_:Destroy(); confirmOverlay_ = nil end end },
                        }},
                    },
                },
            },
        }
        container:GetParent():AddChild(confirmOverlay_)
    end

    local leftColumn = UI.Panel {
        width = 220, paddingAll = 18,
        children = {
            UI.Label { text = "世界Boss", fontSize = 18, color = { bc[1], bc[2], bc[3], 255 },
                textAlign = "center", width = "100%", marginBottom = 4 },
            timerLabel_,
            UI.Panel {
                width = "100%", paddingAll = 10, backgroundColor = { bc[1], bc[2], bc[3], 30 },
                borderRadius = 8, marginBottom = 10, borderWidth = 1, borderColor = { bc[1], bc[2], bc[3], 80 },
                justifyContent = "center", alignItems = "center",
                children = {
                    BossIconWidget { width = 56, height = 56, imageSrc = bossCfg.image, borderColor = bc, marginBottom = 6 },
                    UI.Label { text = bossCfg.name, fontSize = 13, color = { bc[1], bc[2], bc[3], 255 }, textAlign = "center" },
                    UI.Label { text = (elemNames[bossCfg.element] or bossCfg.element) .. "属性",
                        fontSize = 10, color = { 160, 150, 190, 200 }, textAlign = "center", marginTop = 2 },
                },
            },
            UI.Panel { width = "100%", marginBottom = 8, children = {
                UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginBottom = 4, children = {
                    UI.Label { text = "累计伤害", fontSize = 11, color = { 150, 150, 170, 200 } },
                    UI.Label { text = FormatDamage(totalDamage), fontSize = 13, color = { 255, 200, 100, 255 } },
                }},
                UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", children = {
                    UI.Label { text = "剩余挑战", fontSize = 11, color = { 150, 150, 170, 200 } },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, children = {
                        UI.Label { text = attemptsLeft .. "/" .. WorldBoss.MAX_ATTEMPTS, fontSize = 13,
                            color = attemptsLeft > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 } },
                        ticketCount > 0 and UI.Panel { flexDirection = "row", alignItems = "center", gap = 1, children = {
                            UI.Label { text = "(", fontSize = 11, color = { 255, 200, 80, 230 } },
                            UI.Panel { width = 24, height = 24, backgroundImage = "item_wb_ticket_20260310175942.png", backgroundFit = "contain" },
                            UI.Label { text = "×" .. ticketCount .. ")", fontSize = 11, color = { 255, 200, 80, 230 } },
                        }} or nil,
                    }},
                }},
            }},
            UI.Panel { width = "100%", paddingAll = 6, backgroundColor = { 30, 25, 45, 180 },
                borderRadius = 4, marginBottom = 8, children = rewardChildren },
            UI.Label { text = "每赛季3次·每次60秒·累计伤害排名", fontSize = 9,
                color = { 140, 140, 160, 160 }, textAlign = "center", width = "100%", marginBottom = 10 },
            UI.Panel { width = "100%", flexDirection = "row", justifyContent = "center", gap = 12, children = {
                canFight and UI.Button { text = "开始挑战", variant = "primary", width = 100, height = 34,
                    onClick = function()
                        if attemptsLeft <= 0 and ticketCount > 0 then
                            showTicketConfirmInContainer(ticketCount)
                        else
                            closeFn()
                            if onStartCallback_ then onStartCallback_() end
                        end
                    end }
                or UI.Label { text = "次数已用完", fontSize = 12, color = { 200, 80, 80, 200 }, textAlign = "center" },
                UI.Button { text = "返回", variant = "secondary", width = 70, height = 34,
                    onClick = function() closeFn() end },
            }},
        },
    }

    local rightColumn = UI.Panel { width = 180, paddingAll = 18, children = { BuildLeaderboard(bc) } }

    local content = UI.Panel {
        flexDirection = "row",
        backgroundColor = { 20, 12, 30, 245 }, borderRadius = 12,
        borderWidth = 1.5, borderColor = { bc[1], bc[2], bc[3], 180 },
        overflow = "hidden", paddingAll = 6,
        onClick = function() end,
        children = { leftColumn,
            UI.Panel { width = 1, backgroundColor = { bc[1], bc[2], bc[3], 60 }, alignSelf = "stretch" },
            rightColumn },
    }
    container:AddChild(content)
end

--- 设置数据就绪回调 (ChallengePanel 嵌入模式用)
function WorldBossPanel.SetDataReadyCallback(fn)
    onDataReady_ = fn
end

--- 异步加载排行榜数据
function WorldBossPanel.FetchData()
    leaderboardData_ = nil
    leaderboardLoading_ = true
    WorldBoss.FetchLeaderboard(function(rankList, myRank, myDamage)
        leaderboardData_ = { ranks = rankList or {}, myRank = myRank, myDamage = myDamage }
        leaderboardLoading_ = false
        if overlay_ then
            WorldBossPanel.Build()
        elseif onDataReady_ then
            onDataReady_()
        end
    end)
end

function WorldBossPanel.Build()
    if overlay_ then overlay_:Destroy() end

    WorldBoss.EnsureState()

    local bossCfg = WorldBoss.GetCurrentBoss()
    local bc = bossCfg.color
    local attemptsLeft = WorldBoss.GetAttemptsLeft()
    local ticketCount = GameState.GetBagItemCount("wb_ticket")
    local canFight = attemptsLeft > 0 or ticketCount > 0
    local totalDamage = WorldBoss.GetTotalDamage()
    local remaining = WorldBoss.GetSeasonRemaining()

    -- 元素名称映射
    local elemNames = { fire = "火焰", ice = "冰霜", poison = "剧毒", arcane = "奥术" }

    -- 排名奖励展示
    local rewardRows = {}
    for _, r in ipairs(WorldBoss.RANK_REWARDS) do
        local parts = {}
        if r.prisms and r.prisms > 0 then
            table.insert(parts, r.prisms .. "散光棱镜")
        end
        if r.chippedGems and r.chippedGems > 0 then
            table.insert(parts, r.chippedGems .. "碎裂宝石")
        end
        local rewardText = table.concat(parts, " + ")
        table.insert(rewardRows, UI.Panel {
            width = "100%",
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            paddingVertical = 2,
            children = {
                UI.Label { text = r.label, fontSize = 10, color = { 180, 170, 200, 200 } },
                UI.Label { text = rewardText, fontSize = 10, color = { 255, 220, 100, 220 } },
            },
        })
    end

    -- 排名奖励的 children（手动构造避免 table.unpack 位置陷阱）
    local rewardChildren = {
        UI.Label {
            text = "赛季排名奖励",
            fontSize = 10, color = { 180, 160, 220, 200 },
            textAlign = "center", width = "100%", marginBottom = 4,
        },
    }
    for _, row in ipairs(rewardRows) do
        table.insert(rewardChildren, row)
    end

    -- ── 左栏: Boss信息 ──
    timerLabel_ = UI.Label {
        text = "赛季剩余: " .. WorldBoss.FormatTime(remaining),
        fontSize = 10, color = { 180, 180, 200, 180 },
        textAlign = "center", width = "100%", marginBottom = 10,
    }
    local leftColumn = UI.Panel {
        width = 220, paddingAll = 18,
        children = {
            -- 标题
            UI.Label {
                text = "世界Boss",
                fontSize = 18, color = { bc[1], bc[2], bc[3], 255 },
                textAlign = "center", width = "100%", marginBottom = 4,
            },
            -- 赛季倒计时 (保存引用以实时刷新)
            timerLabel_,
            -- Boss信息卡 (带Boss图片)
            UI.Panel {
                width = "100%", paddingAll = 10,
                backgroundColor = { bc[1], bc[2], bc[3], 30 },
                borderRadius = 8, marginBottom = 10,
                borderWidth = 1,
                borderColor = { bc[1], bc[2], bc[3], 80 },
                justifyContent = "center", alignItems = "center",
                children = {
                    -- Boss图片 (NanoVG渲染)
                    BossIconWidget {
                        width = 56, height = 56,
                        imageSrc = bossCfg.image,
                        borderColor = bc,
                        marginBottom = 6,
                    },
                    UI.Label {
                        text = bossCfg.name,
                        fontSize = 13, color = { bc[1], bc[2], bc[3], 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = (elemNames[bossCfg.element] or bossCfg.element) .. "属性",
                        fontSize = 10, color = { 160, 150, 190, 200 },
                        textAlign = "center", marginTop = 2,
                    },
                },
            },
            -- 状态栏
            UI.Panel {
                width = "100%", marginBottom = 8,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        marginBottom = 4,
                        children = {
                            UI.Label { text = "累计伤害", fontSize = 11, color = { 150, 150, 170, 200 } },
                            UI.Label { text = FormatDamage(totalDamage), fontSize = 13, color = { 255, 200, 100, 255 } },
                        },
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label { text = "剩余挑战", fontSize = 11, color = { 150, 150, 170, 200 } },
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    UI.Label {
                                        text = attemptsLeft .. "/" .. WorldBoss.MAX_ATTEMPTS,
                                        fontSize = 13,
                                        color = attemptsLeft > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
                                    },
                                    ticketCount > 0 and UI.Panel {
                                        flexDirection = "row", alignItems = "center", gap = 1,
                                        children = {
                                            UI.Label {
                                                text = "(",
                                                fontSize = 11,
                                                color = { 255, 200, 80, 230 },
                                            },
                                            UI.Panel {
                                                width = 24, height = 24,
                                                backgroundImage = "item_wb_ticket_20260310175942.png",
                                                backgroundFit = "contain",
                                            },
                                            UI.Label {
                                                text = "×" .. ticketCount .. ")",
                                                fontSize = 11,
                                                color = { 255, 200, 80, 230 },
                                            },
                                        },
                                    } or nil,
                                },
                            },
                        },
                    },
                },
            },
            -- 排名奖励
            UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 30, 25, 45, 180 },
                borderRadius = 4, marginBottom = 8,
                children = rewardChildren,
            },
            -- 规则说明
            UI.Label {
                text = "每赛季3次·每次60秒·累计伤害排名",
                fontSize = 9, color = { 140, 140, 160, 160 },
                textAlign = "center", width = "100%", marginBottom = 10,
            },
            -- 按钮组
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 12,
                children = {
                    canFight and UI.Button {
                        text = "开始挑战", variant = "primary",
                        width = 100, height = 34,
                        onClick = function()
                            if attemptsLeft <= 0 and ticketCount > 0 then
                                ShowTicketConfirm(ticketCount)
                            else
                                WorldBossPanel.Close()
                                if onStartCallback_ then
                                    onStartCallback_()
                                end
                            end
                        end,
                    } or UI.Label {
                        text = "次数已用完",
                        fontSize = 12, color = { 200, 80, 80, 200 },
                        textAlign = "center",
                    },
                    UI.Button {
                        text = "返回", variant = "secondary",
                        width = 70, height = 34,
                        onClick = function()
                            WorldBossPanel.Close()
                        end,
                    },
                },
            },
        },
    }

    -- ── 右栏: 排行榜 ──
    local rightColumn = UI.Panel {
        width = 180, paddingAll = 18,
        children = {
            BuildLeaderboard(bc),
        },
    }

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        onClick = function() WorldBossPanel.Close() end,
        children = {
            UI.Panel {
                maxHeight = "90%",
                flexDirection = "row",
                backgroundColor = { 20, 12, 30, 245 },
                borderRadius = 12,
                borderWidth = 1.5,
                borderColor = { bc[1], bc[2], bc[3], 180 },
                overflow = "hidden",
                paddingAll = 6,
                onClick = function() end,  -- 阻止冒泡
                children = {
                    leftColumn,
                    -- 分隔线
                    UI.Panel {
                        width = 1,
                        backgroundColor = { bc[1], bc[2], bc[3], 60 },
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

return WorldBossPanel
