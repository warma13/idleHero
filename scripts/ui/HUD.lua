-- ============================================================================
-- ui/HUD.lua - 顶部状态栏 (HP条 + DPS + 金币 + 关卡)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local DamageTracker = require("DamageTracker")
local Utils = require("Utils")

local HUD = {}

function HUD.Create()
    return UI.Panel {
        id = "hud",
        width = "100%", height = 44,
        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
        backgroundColor = { 25, 30, 42, 240 },
        borderBottomWidth = 1, borderBottomColor = { 50, 60, 80, 100 },
        children = {
            -- 左侧: 等级 + DPS + IP
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                paddingLeft = 12, gap = 8,
                children = {
                    UI.Label { id = "hud_level", text = "Lv.1", fontSize = 14, fontColor = { 255, 255, 255, 255 } },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 2,
                        children = {
                            UI.Label { text = "DPS", fontSize = 9, fontColor = { 255, 130, 80, 200 } },
                            UI.Label { id = "hud_dps", text = "0", fontSize = 12, fontColor = { 255, 180, 130, 230 } },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 2,
                        children = {
                            UI.Label { text = "IP", fontSize = 9, fontColor = { 160, 130, 60, 200 } },
                            UI.Label { id = "hud_power", text = "0", fontSize = 12, fontColor = { 255, 215, 0, 230 } },
                        }
                    },
                },
            },
            -- 右侧: 用户ID + 魂晶
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                paddingRight = 12, gap = 10,
                children = {
                    -- 用户ID
                    UI.Label {
                        id = "hud_uid",
                        text = "",
                        fontSize = 9, fontColor = { 140, 140, 160, 160 },
                    },
                    -- 魂晶
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            UI.Panel { width = 14, height = 14, backgroundImage = "Textures/icon_soul_crystal.png", backgroundFit = "contain" },
                            UI.Label { id = "hud_crystal", text = "0", fontSize = 12, fontColor = { 180, 120, 255, 230 } },
                        },
                    },
                },
            },
        }
    }
end

---@param root Widget
function HUD.Refresh(root)
    if not root then return end
    local p = GameState.player

    local function set(id, text)
        local w = root:FindById(id)
        if w then w:SetText(tostring(text)) end
    end

    set("hud_level", "Lv." .. p.level)

    -- 实时 DPS: 战斗中显示滑动窗口 DPS, 非战斗显示理论 DPS
    local realtimeDPS = DamageTracker.GetRealtimeDPS()
    if realtimeDPS > 0 then
        set("hud_dps", Utils.FormatNumber(realtimeDPS))
    else
        set("hud_dps", Utils.FormatNumber(GameState.GetDPS()))
    end

    set("hud_power", Utils.FormatNumber(GameState.GetPower()))
    set("hud_crystal", Utils.FormatNumber(GameState.GetSoulCrystal()))

    -- 用户ID (只设置一次)
    local uidWidget = root:FindById("hud_uid")
    if uidWidget and not uidWidget._uidSet then
        pcall(function()
            ---@diagnostic disable-next-line: undefined-global
            local uid = lobby:GetMyUserId()
            if uid and uid ~= 0 then
                uidWidget:SetText("ID:" .. tostring(uid))
                uidWidget._uidSet = true
            end
        end)
    end
end

return HUD
