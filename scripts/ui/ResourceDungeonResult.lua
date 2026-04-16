-- ============================================================================
-- ui/ResourceDungeonResult.lua - 折光矿脉结算界面 (全屏覆盖)
-- ============================================================================

local UI             = require("urhox-libs/UI")
local Config         = require("Config")
local ResourceDungeon = require("ResourceDungeon")
local SaveSystem     = require("SaveSystem")

local ResourceDungeonResult = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onCloseCallback_ = nil
local autoContinue_ = false
local autoTimer_ = nil       -- 倒计时剩余秒数 (nil=未激活)
local autoCountdown_ = 5.0   -- 倒计时总秒数
local reenterBtn_ = nil      -- "再次挑战"按钮引用

function ResourceDungeonResult.SetOverlayRoot(root)
    overlayRoot_ = root
end

function ResourceDungeonResult.SetCloseCallback(fn)
    onCloseCallback_ = fn
end

function ResourceDungeonResult.IsOpen()
    return overlay_ ~= nil
end

function ResourceDungeonResult.Close()
    autoTimer_ = nil
    reenterBtn_ = nil
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

--- 每帧更新倒计时（由 main.lua 调用）
---@param dt number
function ResourceDungeonResult.Update(dt)
    if autoTimer_ and overlay_ then
        autoTimer_ = autoTimer_ - dt
        if reenterBtn_ then
            local sec = math.max(0, math.ceil(autoTimer_))
            reenterBtn_:SetText("自动继续 " .. sec .. "s")
        end
        if autoTimer_ <= 0 then
            autoTimer_ = nil
            ResourceDungeonResult.Close()
            ResourceDungeon.ExitToMain()
            if ResourceDungeon.EnterFight() then
                local BattleSystem = require("BattleSystem")
                BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
                print("[ResourceDungeonResult] Auto continue triggered")
            end
        end
    end
end

function ResourceDungeonResult.IsAutoContinue()
    return autoContinue_
end

function ResourceDungeonResult.SetAutoContinue(val)
    autoContinue_ = val
end

--- 构建宝石奖励展示区域
---@param result table fightResult from ResourceDungeon
local function BuildGemSection(result)
    local children = {}

    -- 宝石列表
    if result.gems and #result.gems > 0 then
        table.insert(children, UI.Label {
            text = "获得宝石",
            fontSize = 11, color = { 180, 220, 255, 230 },
            textAlign = "center", width = "100%", marginBottom = 4,
        })

        -- 按品质分组计数
        local qualityCounts = {}  -- { [qualityIdx] = { count, qualityName, colors } }
        for _, gem in ipairs(result.gems) do
            local qi = gem.qualityIdx
            if not qualityCounts[qi] then
                local qDef = Config.GEM_QUALITIES[qi]
                qualityCounts[qi] = {
                    count = 0,
                    qualityName = gem.qualityName,
                    color = qDef and qDef.color or { 200, 200, 200 },
                }
            end
            qualityCounts[qi].count = qualityCounts[qi].count + 1
        end

        -- 按品质排列
        local qualityOrder = { 3, 2, 1 }  -- 完美 > 普通 > 碎裂
        local gemRow = {}
        for _, qi in ipairs(qualityOrder) do
            local info = qualityCounts[qi]
            if info then
                local c = info.color
                table.insert(gemRow, UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 3,
                    children = {
                        UI.Panel {
                            width = 16, height = 16, borderRadius = 3,
                            backgroundColor = { c[1], c[2], c[3], 80 },
                            borderWidth = 1,
                            borderColor = { c[1], c[2], c[3], 200 },
                            justifyContent = "center", alignItems = "center",
                            children = {
                                UI.Label { text = string.sub(info.qualityName, 1, 3), fontSize = 7, color = { c[1], c[2], c[3], 255 } },
                            },
                        },
                        UI.Label {
                            text = info.qualityName .. " x" .. info.count,
                            fontSize = 11, color = { c[1], c[2], c[3], 255 },
                        },
                    },
                })
            end
        end
        if #gemRow > 0 then
            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 10,
                flexWrap = "wrap",
                marginBottom = 6,
                children = gemRow,
            })
        end
    else
        table.insert(children, UI.Label {
            text = "未获得宝石",
            fontSize = 11, color = { 120, 120, 140, 200 },
            textAlign = "center", width = "100%", marginBottom = 4,
        })
    end

    -- 棱镜
    if result.prismCount > 0 then
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 4,
            marginTop = 4,
            children = {
                UI.Panel {
                    width = 16, height = 16, borderRadius = 3,
                    backgroundColor = { 200, 160, 255, 80 },
                    borderWidth = 1,
                    borderColor = { 200, 160, 255, 200 },
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label { text = "P", fontSize = 8, color = { 200, 160, 255, 255 } },
                    },
                },
                UI.Label {
                    text = "散光棱镜 x" .. result.prismCount,
                    fontSize = 12, color = { 200, 160, 255, 255 },
                },
            },
        })
    end

    return UI.Panel {
        width = "100%", paddingAll = 8,
        backgroundColor = { 15, 25, 45, 180 },
        borderRadius = 6, marginBottom = 10,
        children = children,
    }
end

--- 显示结算界面
---@param result table fightResult from ResourceDungeon
function ResourceDungeonResult.Show(result)
    if overlay_ then ResourceDungeonResult.Close() end
    if not result then return end

    local attemptsLeft = ResourceDungeon.GetAttemptsLeft()
    local isBonusRun   = result.isBonusRun or false
    local accentColor  = isBonusRun and { 200, 180, 100 } or { 100, 180, 255 }

    -- 连续挑战开关
    local toggleLabel = UI.Label {
        text = autoContinue_ and "ON" or "OFF",
        fontSize = 10,
        color = autoContinue_ and { 100, 220, 100, 255 } or { 160, 160, 180, 200 },
    }
    local toggleTrack = UI.Panel {
        id = "rd_toggle_track",
        width = 28, height = 16, borderRadius = 8,
        backgroundColor = autoContinue_ and { 60, 160, 80, 220 } or { 60, 65, 80, 200 },
        borderWidth = 1,
        borderColor = autoContinue_ and { 80, 200, 100, 180 } or { 80, 85, 100, 150 },
        justifyContent = "center",
        alignItems = autoContinue_ and "flex-end" or "flex-start",
        paddingHorizontal = 2,
        children = {
            UI.Panel {
                width = 12, height = 12, borderRadius = 6,
                backgroundColor = { 220, 220, 230, 255 },
            },
        },
    }
    local autoToggle = UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "center", alignItems = "center", gap = 8,
        marginBottom = 6,
        onClick = function()
            autoContinue_ = not autoContinue_
            toggleLabel:SetText(autoContinue_ and "ON" or "OFF")
            toggleLabel:SetFontColor(autoContinue_ and { 100, 220, 100, 255 } or { 160, 160, 180, 200 })
            toggleTrack:SetStyle({
                backgroundColor = autoContinue_ and { 60, 160, 80, 220 } or { 60, 65, 80, 200 },
                borderColor = autoContinue_ and { 80, 200, 100, 180 } or { 80, 85, 100, 150 },
                alignItems = autoContinue_ and "flex-end" or "flex-start",
            })
        end,
        children = {
            toggleTrack,
            UI.Label { text = "连续挑战", fontSize = 11, color = { 180, 190, 210, 220 } },
            toggleLabel,
        },
    }

    -- 按钮列表
    local buttons = {}
    -- 始终可再次进入
    local reenterText = isBonusRun and "继续探索" or "再次挑战"
    local reenterButton = UI.Button {
        text = reenterText, variant = "primary",
        width = 110, height = 34,
        onClick = function()
            autoTimer_ = nil
            ResourceDungeonResult.Close()
            ResourceDungeon.ExitToMain()
            if ResourceDungeon.EnterFight() then
                local BattleSystem = require("BattleSystem")
                BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
                print("[ResourceDungeonResult] Re-entering fight")
            end
        end,
    }
    reenterBtn_ = reenterButton
    table.insert(buttons, reenterButton)
    table.insert(buttons, UI.Button {
        text = "返回", variant = "secondary",
        width = 100, height = 34,
        onClick = function()
            autoContinue_ = false
            autoTimer_ = nil
            ResourceDungeonResult.Close()
            ResourceDungeon.ExitToMain()
            SaveSystem.SaveNow()
            if onCloseCallback_ then
                onCloseCallback_()
            end
        end,
    })

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 260, maxHeight = "85%", paddingAll = 16,
                backgroundColor = { 15, 20, 40, 245 },
                borderRadius = 12,
                borderWidth = 1.5,
                borderColor = { accentColor[1], accentColor[2], accentColor[3], 180 },
                children = {
                    -- 可滚动内容区
                    UI.Panel {
                        width = "100%", flexShrink = 1, overflow = "scroll",
                        children = {
                            -- 标题
                            UI.Label {
                                text = isBonusRun and "额外探索结束" or "矿脉探索结束",
                                fontSize = 20,
                                color = { accentColor[1], accentColor[2], accentColor[3], 255 },
                                textAlign = "center", width = "100%", marginBottom = 4,
                            },
                            UI.Label {
                                text = isBonusRun and "折光矿脉 · 概率掉落" or "折光矿脉",
                                fontSize = 12,
                                color = { 180, 180, 200, 180 },
                                textAlign = "center", width = "100%", marginBottom = 10,
                            },
                            -- 击杀数
                            UI.Panel {
                                width = "100%", paddingAll = 10,
                                backgroundColor = { 25, 35, 55, 200 },
                                borderRadius = 6, marginBottom = 8,
                                justifyContent = "center", alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "击杀数",
                                        fontSize = 11,
                                        color = { 160, 170, 200, 200 },
                                        textAlign = "center",
                                    },
                                    UI.Label {
                                        text = tostring(result.killCount),
                                        fontSize = 24,
                                        color = { 255, 220, 100, 255 },
                                        textAlign = "center", marginTop = 2,
                                    },
                                    result.eliteKilled and UI.Label {
                                        text = "精英已击杀",
                                        fontSize = 10,
                                        color = { 255, 180, 50, 230 },
                                        textAlign = "center", marginTop = 2,
                                    } or nil,
                                },
                            },
                            -- 剩余次数 (仅前3次显示)
                            isBonusRun and nil or UI.Panel {
                                width = "100%",
                                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                                marginBottom = 8,
                                children = {
                                    UI.Label { text = "剩余挑战次数", fontSize = 11, color = { 150, 150, 170, 200 } },
                                    UI.Label {
                                        text = tostring(attemptsLeft) .. "/" .. tostring(ResourceDungeon.GetMaxAttempts()),
                                        fontSize = 13,
                                        color = attemptsLeft > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
                                    },
                                },
                            },
                            -- 奖励区域
                            BuildGemSection(result),
                        },
                    },
                    -- 连续挑战开关
                    autoToggle,
                    -- 按钮区域
                    UI.Panel {
                        width = "100%", flexShrink = 0,
                        flexDirection = "row", justifyContent = "center", gap = 12,
                        children = buttons,
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end

    -- 连续挑战: 启动倒计时
    if autoContinue_ then
        autoTimer_ = autoCountdown_
    else
        autoTimer_ = nil
    end
end

return ResourceDungeonResult
