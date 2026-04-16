-- ============================================================================
-- ui/WorldBossResult.lua - 世界Boss战斗结算界面 (全屏覆盖)
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local WorldBoss = require("WorldBoss")
local SaveSystem = require("SaveSystem")
local Config = require("Config")

local Utils = require("Utils")

local WorldBossResult = {}

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local onCloseCallback_ = nil

function WorldBossResult.SetOverlayRoot(root)
    overlayRoot_ = root
end

function WorldBossResult.SetCloseCallback(fn)
    onCloseCallback_ = fn
end

function WorldBossResult.IsOpen()
    return overlay_ ~= nil
end

function WorldBossResult.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
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

--- 显示结算界面
function WorldBossResult.Show()
    if overlay_ then WorldBossResult.Close() end

    local bossCfg = WorldBoss.GetCurrentBoss()
    local damage = WorldBoss.fightDamage or 0
    local totalDamage = WorldBoss.GetTotalDamage()
    local attemptsLeft = WorldBoss.GetAttemptsLeft()
    local bc = bossCfg.color

    -- 按钮列表 (始终包含返回按钮)
    local buttons = {}
    if attemptsLeft > 0 then
        table.insert(buttons, UI.Button {
            text = "再次挑战", variant = "primary",
            width = 100, height = 34,
            onClick = function()
                WorldBossResult.Close()
                if WorldBoss.EnterFight() then
                    local BattleSystem = require("BattleSystem")
                    BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
                    print("[WorldBossResult] Re-entering fight")
                end
            end,
        })
    end
    table.insert(buttons, UI.Button {
        text = "返回", variant = "secondary",
        width = 100, height = 34,
        onClick = function()
            WorldBossResult.Close()
            WorldBoss.ExitToMain()
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
                backgroundColor = { 20, 15, 35, 245 },
                borderRadius = 12,
                borderWidth = 1.5,
                borderColor = { bc[1], bc[2], bc[3], 180 },
                children = {
                    -- 可滚动内容区
                    UI.Panel {
                        width = "100%", flexShrink = 1, overflow = "scroll",
                        children = {
                            -- 标题
                            UI.Label {
                                text = "战斗结束",
                                fontSize = 20,
                                color = { bc[1], bc[2], bc[3], 255 },
                                textAlign = "center", width = "100%", marginBottom = 4,
                            },
                            -- Boss名称
                            UI.Label {
                                text = bossCfg.name,
                                fontSize = 12,
                                color = { 180, 180, 200, 180 },
                                textAlign = "center", width = "100%", marginBottom = 10,
                            },
                            -- 本次伤害
                            UI.Panel {
                                width = "100%", paddingAll = 10,
                                backgroundColor = { 40, 25, 55, 200 },
                                borderRadius = 6, marginBottom = 8,
                                justifyContent = "center", alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "本次伤害",
                                        fontSize = 11,
                                        color = { 160, 150, 190, 200 },
                                        textAlign = "center",
                                    },
                                    UI.Label {
                                        text = FormatDamage(damage),
                                        fontSize = 24,
                                        color = { 255, 200, 100, 255 },
                                        textAlign = "center", marginTop = 2,
                                    },
                                },
                            },
                            -- 赛季累计
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                                marginBottom = 6,
                                children = {
                                    UI.Label { text = "赛季累计伤害", fontSize = 11, color = { 150, 150, 170, 200 } },
                                    UI.Label { text = FormatDamage(totalDamage), fontSize = 13, color = { 220, 200, 150, 255 } },
                                },
                            },
                            -- 剩余次数
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                                marginBottom = 6,
                                children = {
                                    UI.Label { text = "剩余挑战次数", fontSize = 11, color = { 150, 150, 170, 200 } },
                                    UI.Label {
                                        text = tostring(attemptsLeft) .. "/" .. tostring(WorldBoss.MAX_ATTEMPTS),
                                        fontSize = 13,
                                        color = attemptsLeft > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
                                    },
                                },
                            },
                            -- 参与奖掉落物
                            WorldBossResult.BuildLootSection(),
                        },
                    },
                    -- 按钮区域 (固定底部, 不被内容挤出)
                    UI.Panel {
                        width = "100%", flexShrink = 0, marginTop = 10,
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

--- 构建掉落物展示区域
function WorldBossResult.BuildLootSection()
    local loot = WorldBoss.lastLoot
    if not loot then
        return UI.Panel { height = 0 }
    end

    local children = {}

    -- 标题
    table.insert(children, UI.Label {
        text = "参与奖励",
        fontSize = 11, color = { 150, 220, 100, 230 },
        textAlign = "center", width = "100%", marginBottom = 4,
    })

    -- 金币 + 魂晶行
    local resourceRow = {}
    if loot.gold > 0 then
        table.insert(resourceRow, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            children = {
                UI.Panel {
                    width = 14, height = 14, borderRadius = 7,
                    backgroundColor = { 255, 215, 0, 255 },
                    justifyContent = "center", alignItems = "center",
                    children = { UI.Label { text = "$", fontSize = 8, color = { 80, 50, 0, 255 } } },
                },
                UI.Label { text = Utils.FormatNumber(loot.gold), fontSize = 11, color = { 255, 220, 100, 255 } },
            },
        })
    end
    if loot.crystal > 0 then
        local cc = Config.SOUL_CRYSTAL.color
        table.insert(resourceRow, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            children = {
                UI.Panel {
                    width = 14, height = 14, borderRadius = 3,
                    backgroundColor = { cc[1], cc[2], cc[3], 255 },
                    justifyContent = "center", alignItems = "center",
                    children = { UI.Label { text = "魂", fontSize = 7, color = { 255, 255, 255, 255 } } },
                },
                UI.Label { text = tostring(loot.crystal), fontSize = 11, color = { cc[1], cc[2], cc[3], 255 } },
            },
        })
    end
    if #resourceRow > 0 then
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 12,
            marginBottom = 6,
            children = resourceRow,
        })
    end

    -- 装备图标行
    if loot.equips and #loot.equips > 0 then
        local equipIcons = {}
        for _, eq in ipairs(loot.equips) do
            local c = eq.color or { 200, 200, 200 }
            -- 取槽位首字作为图标文字
            local iconText = eq.slotName and string.sub(eq.slotName, 1, 3) or "?"
            table.insert(equipIcons, UI.Panel {
                width = 36, height = 44,
                justifyContent = "center", alignItems = "center",
                backgroundColor = { c[1], c[2], c[3], 40 },
                borderRadius = 4,
                borderWidth = 1.5,
                borderColor = { c[1], c[2], c[3], 200 },
                children = {
                    UI.Label {
                        text = iconText,
                        fontSize = 11, color = { c[1], c[2], c[3], 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = eq.qualityName or "",
                        fontSize = 8, color = { c[1], c[2], c[3], 180 },
                        textAlign = "center", marginTop = 1,
                    },
                },
            })
        end
        table.insert(children, UI.Panel {
            width = "100%",
            flexDirection = "row", justifyContent = "center", alignItems = "center", gap = 6,
            children = equipIcons,
        })
    end

    return UI.Panel {
        width = "100%", paddingAll = 8,
        backgroundColor = { 25, 35, 20, 180 },
        borderRadius = 6, marginBottom = 10,
        children = children,
    }
end

return WorldBossResult
