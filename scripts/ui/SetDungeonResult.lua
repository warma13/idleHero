-- ============================================================================
-- ui/SetDungeonResult.lua - 套装秘境结算界面 (全屏覆盖)
-- ============================================================================

local UI          = require("urhox-libs/UI")
local Config      = require("Config")
local SetDungeon  = require("SetDungeon")
local SaveSystem  = require("SaveSystem")

local SetDungeonResult = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onCloseCallback_ = nil

function SetDungeonResult.SetOverlayRoot(root)
    overlayRoot_ = root
end

function SetDungeonResult.SetCloseCallback(fn)
    onCloseCallback_ = fn
end

function SetDungeonResult.IsOpen()
    return overlay_ ~= nil
end

function SetDungeonResult.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

--- 构建装备奖励展示区域
---@param reward table|nil 装备数据
local function BuildRewardSection(reward)
    if not reward then
        return UI.Panel {
            width = "100%", paddingAll = 10,
            backgroundColor = { 25, 15, 15, 180 },
            borderRadius = 6, marginBottom = 10,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "未获得奖励",
                    fontSize = 12, color = { 180, 100, 100, 200 },
                    textAlign = "center",
                },
            },
        }
    end

    -- 品质颜色
    local qDef = Config.QUALITIES[reward.qualityIdx]
    local qColor = qDef and qDef.color or { 200, 200, 200 }

    -- 套装信息
    local setCfg = reward.setId and Config.EQUIP_SET_MAP[reward.setId]
    local setColor = setCfg and setCfg.color or { 180, 180, 200 }

    local children = {
        UI.Label {
            text = "获得装备",
            fontSize = 11, color = { 180, 220, 255, 230 },
            textAlign = "center", width = "100%", marginBottom = 6,
        },
        -- 装备名称
        UI.Panel {
            width = "100%",
            justifyContent = "center", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label {
                    text = reward.name or "未知装备",
                    fontSize = 15,
                    color = { qColor[1], qColor[2], qColor[3], 255 },
                    textAlign = "center",
                },
            },
        },
        -- 品质 + 部位
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "center", alignItems = "center", gap = 8,
            marginBottom = 4,
            children = {
                UI.Label {
                    text = reward.qualityName or "",
                    fontSize = 10, color = { qColor[1], qColor[2], qColor[3], 200 },
                },
                UI.Panel { width = 1, height = 10, backgroundColor = { 80, 80, 100, 120 } },
                UI.Label {
                    text = reward.slotName or reward.slotId or "",
                    fontSize = 10, color = { 180, 180, 200, 200 },
                },
            },
        },
        -- 套装标识
        setCfg and UI.Panel {
            width = "100%",
            justifyContent = "center", alignItems = "center",
            marginTop = 2, marginBottom = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    paddingHorizontal = 8, paddingVertical = 2,
                    backgroundColor = { setColor[1], setColor[2], setColor[3], 30 },
                    borderRadius = 4,
                    borderWidth = 1,
                    borderColor = { setColor[1], setColor[2], setColor[3], 120 },
                    children = {
                        UI.Panel {
                            width = 6, height = 6, borderRadius = 3,
                            backgroundColor = { setColor[1], setColor[2], setColor[3], 200 },
                        },
                        UI.Label {
                            text = setCfg.name,
                            fontSize = 10,
                            color = { setColor[1], setColor[2], setColor[3], 230 },
                        },
                    },
                },
            },
        } or nil,
        -- IP
        reward.itemPower and UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "center", alignItems = "center", gap = 4,
            marginTop = 4,
            children = {
                UI.Label { text = "装备战力", fontSize = 10, color = { 140, 140, 160, 180 } },
                UI.Label {
                    text = tostring(math.floor(reward.itemPower)),
                    fontSize = 13, color = { 255, 220, 100, 255 },
                },
            },
        } or nil,
    }

    return UI.Panel {
        width = "100%", paddingAll = 10,
        backgroundColor = { 15, 25, 45, 180 },
        borderRadius = 6, marginBottom = 10,
        children = children,
    }
end

--- 显示结算界面
---@param result table fightResult from SetDungeon
function SetDungeonResult.Show(result)
    if overlay_ then SetDungeonResult.Close() end
    if not result then return end

    local won = result.won
    local attemptsLeft = SetDungeon.GetAttemptsLeft()
    local maxAttempts  = SetDungeon.GetMaxAttempts()
    local canReenter   = SetDungeon.CanEnter()

    -- 套装信息
    local setCfg = result.targetSet and Config.EQUIP_SET_MAP[result.targetSet]
    local setName = setCfg and setCfg.name or "未知套装"

    local accentColor = won and { 180, 100, 255 } or { 200, 80, 80 }

    -- 按钮列表
    local buttons = {}

    -- 再次挑战 (有次数时)
    if canReenter then
        table.insert(buttons, UI.Button {
            text = "再次挑战",
            variant = "primary",
            width = 110, height = 34,
            onClick = function()
                SetDungeonResult.Close()
                SetDungeon.ExitToMain()
                if SetDungeon.EnterFight(result.targetSet, result.hardMode) then
                    local BattleSystem = require("BattleSystem")
                    BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
                    print("[SetDungeonResult] Re-entering fight")
                end
            end,
        })
    end

    table.insert(buttons, UI.Button {
        text = "返回",
        variant = "secondary",
        width = 100, height = 34,
        onClick = function()
            SetDungeonResult.Close()
            SetDungeon.ExitToMain()
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
                                text = won and "秘境通关" or "挑战失败",
                                fontSize = 20,
                                color = { accentColor[1], accentColor[2], accentColor[3], 255 },
                                textAlign = "center", width = "100%", marginBottom = 4,
                            },
                            UI.Label {
                                text = setName .. (result.hardMode and " · 困难" or " · 普通"),
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
                                        color = won and { 255, 220, 100, 255 } or { 200, 120, 120, 255 },
                                        textAlign = "center", marginTop = 2,
                                    },
                                },
                            },
                            -- 失败提示
                            (not won) and UI.Label {
                                text = "失败不扣除挑战次数，可重新挑战",
                                fontSize = 10, color = { 120, 200, 120, 200 },
                                textAlign = "center", width = "100%", marginBottom = 8,
                            } or nil,
                            -- 剩余次数
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                                marginBottom = 8,
                                children = {
                                    UI.Label { text = "剩余挑战次数", fontSize = 11, color = { 150, 150, 170, 200 } },
                                    UI.Label {
                                        text = tostring(attemptsLeft) .. "/" .. tostring(maxAttempts),
                                        fontSize = 13,
                                        color = attemptsLeft > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
                                    },
                                },
                            },
                            -- 奖励区域
                            BuildRewardSection(result.reward),
                        },
                    },
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
end

return SetDungeonResult
