-- ============================================================================
-- ui/ManaForestResult.lua - 魔力之森结算界面 (全屏覆盖)
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Config     = require("Config")
local ManaForest = require("ManaForest")
local SaveSystem = require("SaveSystem")

local ManaForestResult = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onCloseCallback_ = nil

local lastDifficulty_ = "normal"

-- 主题色
local TC = { 60, 200, 140 }

function ManaForestResult.SetOverlayRoot(root)
    overlayRoot_ = root
end

function ManaForestResult.SetCloseCallback(fn)
    onCloseCallback_ = fn
end

function ManaForestResult.IsOpen()
    return overlay_ ~= nil
end

function ManaForestResult.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

--- 构建奖励展示区域
---@param result table fightResult from ManaForest
local function BuildRewardSection(result)
    local children = {}

    -- 精华统计
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        marginBottom = 4,
        children = {
            UI.Label { text = "收集精华", fontSize = 12, color = { 160, 170, 200, 200 } },
            UI.Label {
                text = tostring(result.essence),
                fontSize = 14, color = { 100, 220, 255, 255 },
            },
        },
    })

    -- 增益等级
    local tierNames = { "I", "II", "III", "IV" }
    local tierColors = {
        { 120, 200, 255 }, { 80, 160, 255 }, { 140, 100, 255 }, { 200, 80, 255 },
    }
    local tierColor = result.buffTier > 0 and tierColors[result.buffTier] or { 150, 150, 150 }
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Label { text = "最高增益", fontSize = 11, color = { 140, 140, 160, 180 } },
            UI.Label {
                text = result.buffTier > 0 and ("Lv." .. tierNames[result.buffTier]) or "无",
                fontSize = 12, color = { tierColor[1], tierColor[2], tierColor[3], 255 },
            },
        },
    })

    -- 分隔线
    table.insert(children, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 60, 70, 90, 120 },
        marginBottom = 8,
    })

    -- 魔力药水
    if result.potions > 0 then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label { text = "魔力药水", fontSize = 12, color = { 180, 140, 255, 230 } },
                UI.Label {
                    text = "x" .. result.potions,
                    fontSize = 13, color = { 180, 140, 255, 255 },
                },
            },
        })
    end

    -- 森之露
    if result.forestDew > 0 then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label { text = "森之露", fontSize = 12, color = { TC[1], TC[2], TC[3], 230 } },
                UI.Label {
                    text = "x" .. result.forestDew,
                    fontSize = 13, color = { TC[1], TC[2], TC[3], 255 },
                },
            },
        })
    end

    -- 金币
    if result.gold > 0 then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label { text = "金币", fontSize = 11, color = { 255, 220, 100, 200 } },
                UI.Label {
                    text = "+" .. result.gold,
                    fontSize = 11, color = { 255, 220, 100, 255 },
                },
            },
        })
    end

    -- 经验
    if result.exp > 0 then
        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label { text = "经验", fontSize = 11, color = { 100, 220, 180, 200 } },
                UI.Label {
                    text = "+" .. result.exp,
                    fontSize = 11, color = { 100, 220, 180, 255 },
                },
            },
        })
    end

    -- 首通奖励
    if result.firstClear then
        table.insert(children, UI.Panel {
            width = "100%", marginTop = 6, paddingAll = 6,
            backgroundColor = { 255, 200, 60, 30 },
            borderRadius = 4, borderWidth = 1,
            borderColor = { 255, 200, 60, 120 },
            children = {
                UI.Label {
                    text = "首通奖励: 药水x" .. Config.MANA_FOREST.FIRST_CLEAR_POTIONS
                        .. " + 森之露x" .. Config.MANA_FOREST.FIRST_CLEAR_DEW,
                    fontSize = 11, color = { 255, 220, 100, 255 },
                    textAlign = "center", width = "100%",
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
---@param result table fightResult from ManaForest
function ManaForestResult.Show(result)
    if overlay_ then ManaForestResult.Close() end
    if not result then return end

    lastDifficulty_ = result.difficulty or "normal"
    local attemptsLeft = ManaForest.GetAttemptsLeft()
    local canReenter, _ = ManaForest.CanEnter()
    local isHard = result.difficulty == "hard"
    local accentColor = isHard and { 200, 100, 80 } or { TC[1], TC[2], TC[3] }

    -- 标题文本
    local titleText
    if result.noKill then
        titleText = "挑战失败"
    elseif result.completed then
        titleText = "挑战完成"
    else
        titleText = "英勇牺牲"
    end

    -- 按钮列表
    local buttons = {}
    if canReenter then
        local reenterButton = UI.Button {
            text = "再次挑战", variant = "primary",
            width = 110, height = 34,
            onClick = function()
                ManaForestResult.Close()
                ManaForest.ExitToMain()
                if ManaForest.EnterFight(lastDifficulty_) then
                    local BattleSystem = require("BattleSystem")
                    BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
                    print("[ManaForestResult] Re-entering fight")
                end
            end,
        }
        table.insert(buttons, reenterButton)
    end
    table.insert(buttons, UI.Button {
        text = "返回", variant = "secondary",
        width = 100, height = 34,
        onClick = function()
            ManaForestResult.Close()
            ManaForest.ExitToMain()
            SaveSystem.SaveNow()
            if onCloseCallback_ then onCloseCallback_() end
        end,
    })

    -- 构建 scrollable 子元素列表
    local scrollChildren = {
        -- 标题
        UI.Label {
            text = titleText,
            fontSize = 20,
            color = { accentColor[1], accentColor[2], accentColor[3], 255 },
            textAlign = "center", width = "100%", marginBottom = 4,
        },
        UI.Label {
            text = "魔力之森" .. (isHard and " · 困难" or ""),
            fontSize = 12, color = { 180, 180, 200, 180 },
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
                    text = "击杀数", fontSize = 11, color = { 160, 170, 200, 200 },
                    textAlign = "center",
                },
                UI.Label {
                    text = tostring(result.killCount),
                    fontSize = 24, color = { 255, 220, 100, 255 },
                    textAlign = "center", marginTop = 2,
                },
            },
        },
    }

    -- 新纪录
    if result.newRecord then
        table.insert(scrollChildren, UI.Panel {
            width = "100%", marginBottom = 8, alignItems = "center",
            children = {
                UI.Label {
                    text = "新纪录！精华 " .. result.essence,
                    fontSize = 14, color = { 255, 200, 60, 255 },
                    textAlign = "center",
                },
            },
        })
    end

    -- 剩余次数
    table.insert(scrollChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Label { text = "剩余次数", fontSize = 11, color = { 150, 150, 170, 200 } },
            UI.Label {
                text = tostring(attemptsLeft) .. "/" .. tostring(ManaForest.GetMaxAttempts()),
                fontSize = 13,
                color = attemptsLeft > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
            },
        },
    })

    -- 奖励区域
    if not result.noKill then
        table.insert(scrollChildren, BuildRewardSection(result))
    end

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 260, maxHeight = "85%", paddingAll = 16,
                backgroundColor = { 15, 20, 40, 245 },
                borderRadius = 12, borderWidth = 1.5,
                borderColor = { accentColor[1], accentColor[2], accentColor[3], 180 },
                children = {
                    -- 可滚动内容区
                    UI.Panel {
                        width = "100%", flexShrink = 1, overflow = "scroll",
                        children = scrollChildren,
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

return ManaForestResult
