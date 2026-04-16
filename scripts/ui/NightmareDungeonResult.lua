-- ============================================================================
-- ui/NightmareDungeonResult.lua - 噩梦地牢结算界面 (全屏覆盖)
-- ============================================================================

local UI               = require("urhox-libs/UI")
local Config           = require("Config")
local NightmareDungeon = require("NightmareDungeon")
local SaveSystem       = require("SaveSystem")

local NightmareDungeonResult = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onCloseCallback_ = nil

-- 主题色 (暗紫)
local TC = { 180, 60, 220 }

-- 品质颜色
local QUALITY_COLORS = {
    [3] = { 80, 140, 255 },   -- 蓝
    [4] = { 160, 80, 220 },   -- 紫
    [5] = { 255, 160, 40 },   -- 橙
}

function NightmareDungeonResult.SetOverlayRoot(root)
    overlayRoot_ = root
end

function NightmareDungeonResult.SetCloseCallback(fn)
    onCloseCallback_ = fn
end

function NightmareDungeonResult.IsOpen()
    return overlay_ ~= nil
end

function NightmareDungeonResult.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

--- 获取词缀名
---@param affixId string
---@return string
local function getAffixName(affixId)
    local ND = Config.NIGHTMARE_DUNGEON
    for _, def in ipairs(ND.POSITIVE_AFFIXES) do
        if def.id == affixId then return def.name end
    end
    for _, def in ipairs(ND.NEGATIVE_AFFIXES) do
        if def.id == affixId then return def.name end
    end
    return affixId
end

--- 构建装备展示区
---@param equips table
---@return Widget
local function BuildEquipSection(equips)
    local rows = {}
    for i, equip in ipairs(equips) do
        local qColor = QUALITY_COLORS[equip.qualityIdx] or { 180, 180, 180 }
        local qualityNames = { [3] = "蓝", [4] = "紫", [5] = "橙" }
        local qName = qualityNames[equip.qualityIdx] or "?"
        table.insert(rows, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 2,
            children = {
                UI.Label {
                    text = (equip.name or "装备"),
                    fontSize = 11, color = { qColor[1], qColor[2], qColor[3], 240 },
                },
                UI.Label {
                    text = "[" .. qName .. "]",
                    fontSize = 10, color = { qColor[1], qColor[2], qColor[3], 200 },
                },
            },
        })
    end
    return UI.Panel {
        width = "100%", paddingAll = 6,
        backgroundColor = { 20, 15, 40, 160 },
        borderRadius = 4, marginBottom = 6,
        children = {
            UI.Label {
                text = "装备掉落 (" .. #equips .. "件)",
                fontSize = 12, color = { 200, 180, 255, 230 },
                marginBottom = 4,
            },
            table.unpack(rows),
        },
    }
end

--- 构建材料展示
---@param materials table
---@return Widget
local function BuildMaterialSection(materials)
    local rows = {}
    local matNames = {
        iron = "锈蚀铁块", crystal = "暗纹晶体", wraith = "怨魂碎片",
        eternal = "永夜之魂", abyssHeart = "深渊之心", riftEcho = "裂隙残响",
    }
    for _, mat in ipairs(materials) do
        table.insert(rows, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 2,
            children = {
                UI.Label {
                    text = matNames[mat.matId] or mat.matId,
                    fontSize = 11, color = { 160, 180, 200, 220 },
                },
                UI.Label {
                    text = "x" .. mat.count,
                    fontSize = 11, color = { 180, 200, 255, 255 },
                },
            },
        })
    end
    if #rows == 0 then return UI.Panel { width = 0, height = 0 } end
    return UI.Panel {
        width = "100%", paddingAll = 6,
        backgroundColor = { 15, 20, 40, 160 },
        borderRadius = 4, marginBottom = 6,
        children = {
            UI.Label {
                text = "材料掉落",
                fontSize = 12, color = { 140, 180, 220, 220 },
                marginBottom = 4,
            },
            table.unpack(rows),
        },
    }
end

--- 显示结算界面
---@param result table fightResult from NightmareDungeon
function NightmareDungeonResult.Show(result)
    if overlay_ then NightmareDungeonResult.Close() end
    if not result then return end

    local tier = result.tier or 0
    local completed = result.completed

    -- 标题
    local titleText = completed and "地牢通关" or "挑战失败"
    local accentColor = completed and { TC[1], TC[2], TC[3] } or { 200, 80, 80 }

    -- 按钮
    local buttons = {}

    -- 通关后如有钥石可再次挑战
    if completed then
        local canReenter, _ = NightmareDungeon.CanEnter()
        if canReenter then
            table.insert(buttons, UI.Button {
                text = "再次挑战", variant = "primary",
                width = 110, height = 34,
                onClick = function()
                    NightmareDungeonResult.Close()
                    NightmareDungeon.ExitToMain()
                    -- 选第一把钥石进入
                    if NightmareDungeon.EnterFight(1) then
                        local BattleSystem = require("BattleSystem")
                        local GameMode = require("GameMode")
                        GameMode.SwitchTo("nightmareDungeon")
                        print("[NightmareDungeonResult] Re-entering fight")
                    end
                end,
            })
        end
    end

    table.insert(buttons, UI.Button {
        text = "返回", variant = "secondary",
        width = 100, height = 34,
        onClick = function()
            NightmareDungeonResult.Close()
            NightmareDungeon.ExitToMain()
            SaveSystem.SaveNow()
            if onCloseCallback_ then onCloseCallback_() end
        end,
    })

    -- 滚动内容
    local scrollChildren = {
        -- 标题
        UI.Label {
            text = titleText,
            fontSize = 20,
            color = { accentColor[1], accentColor[2], accentColor[3], 255 },
            textAlign = "center", width = "100%", marginBottom = 4,
        },
        UI.Label {
            text = "噩梦地牢 Lv." .. tier,
            fontSize = 13, color = { 200, 160, 255, 200 },
            textAlign = "center", width = "100%", marginBottom = 10,
        },
        -- 击杀 + 用时
        UI.Panel {
            width = "100%", paddingAll = 10,
            backgroundColor = { 25, 20, 50, 200 },
            borderRadius = 6, marginBottom = 8,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    marginBottom = 4,
                    children = {
                        UI.Label { text = "击杀数", fontSize = 12, color = { 160, 170, 200, 200 } },
                        UI.Label {
                            text = tostring(result.totalKills),
                            fontSize = 16, color = { 255, 220, 100, 255 },
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    marginBottom = 4,
                    children = {
                        UI.Label { text = "用时", fontSize = 11, color = { 140, 140, 160, 180 } },
                        UI.Label {
                            text = string.format("%.1f", result.elapsedTime or 0) .. "s",
                            fontSize = 11, color = { 180, 200, 255, 200 },
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label { text = "到达阶段", fontSize = 11, color = { 140, 140, 160, 180 } },
                        UI.Label {
                            text = (result.phase or 1) .. "/" .. #Config.NIGHTMARE_DUNGEON.PHASES,
                            fontSize = 11, color = { 180, 180, 200, 200 },
                        },
                    },
                },
            },
        },
    }

    if completed then
        -- 装备
        if result.equips and #result.equips > 0 then
            table.insert(scrollChildren, BuildEquipSection(result.equips))
        end

        -- 材料
        if result.materials and #result.materials > 0 then
            table.insert(scrollChildren, BuildMaterialSection(result.materials))
        end

        -- 金币/经验
        if (result.gold or 0) > 0 or (result.exp or 0) > 0 then
            local rewardRows = {}
            if result.gold > 0 then
                table.insert(rewardRows, UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    marginBottom = 2,
                    children = {
                        UI.Label { text = "金币", fontSize = 11, color = { 255, 220, 100, 200 } },
                        UI.Label { text = "+" .. result.gold, fontSize = 11, color = { 255, 220, 100, 255 } },
                    },
                })
            end
            if result.exp > 0 then
                table.insert(rewardRows, UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    marginBottom = 2,
                    children = {
                        UI.Label { text = "经验", fontSize = 11, color = { 100, 220, 180, 200 } },
                        UI.Label { text = "+" .. result.exp, fontSize = 11, color = { 100, 220, 180, 255 } },
                    },
                })
            end
            table.insert(scrollChildren, UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 15, 20, 40, 160 },
                borderRadius = 4, marginBottom = 6,
                children = rewardRows,
            })
        end

        -- 下一枚钥石
        if result.nextSigil then
            local ns = result.nextSigil
            local affixTexts = {}
            for _, id in ipairs(ns.positives or {}) do
                table.insert(affixTexts, "+" .. getAffixName(id))
            end
            for _, id in ipairs(ns.negatives or {}) do
                table.insert(affixTexts, "-" .. getAffixName(id))
            end
            local affixStr = #affixTexts > 0 and table.concat(affixTexts, " ") or "无词缀"

            table.insert(scrollChildren, UI.Panel {
                width = "100%", paddingAll = 8,
                backgroundColor = { TC[1], TC[2], TC[3], 30 },
                borderRadius = 6, borderWidth = 1,
                borderColor = { TC[1], TC[2], TC[3], 120 },
                marginBottom = 6,
                children = {
                    UI.Label {
                        text = "获得钥石: Lv." .. ns.tier,
                        fontSize = 13, color = { TC[1], TC[2], TC[3], 255 },
                        marginBottom = 2,
                    },
                    UI.Label {
                        text = affixStr,
                        fontSize = 10, color = { 180, 160, 220, 200 },
                    },
                },
            })
        end
    else
        -- 失败提示
        table.insert(scrollChildren, UI.Panel {
            width = "100%", paddingAll = 8,
            backgroundColor = { 60, 20, 20, 120 },
            borderRadius = 4, marginBottom = 6,
            children = {
                UI.Label {
                    text = "钥石已退回，可再次尝试",
                    fontSize = 12, color = { 220, 160, 160, 230 },
                    textAlign = "center", width = "100%",
                },
            },
        })
    end

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 270, maxHeight = "85%", paddingAll = 16,
                backgroundColor = { 12, 10, 25, 245 },
                borderRadius = 12, borderWidth = 1.5,
                borderColor = { accentColor[1], accentColor[2], accentColor[3], 180 },
                children = {
                    -- 可滚动内容区
                    UI.Panel {
                        width = "100%", flexShrink = 1, overflow = "scroll",
                        children = scrollChildren,
                    },
                    -- 按钮区
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

return NightmareDungeonResult
