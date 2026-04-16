-- ============================================================================
-- ui/StatusBars.lua - HP条 + MP条 + 经验条（位于战斗区和背包区之间）
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local Config = require("Config")

local StatusBars = {}

---@type Widget
local panel_ = nil

-- 参考基准：图2窄屏下不溢出时的比例
-- 窄屏约 390px 宽，paddingHorizontal=10 → 比例 ~2.5%
local PADDING_RATIO = 0.025  -- 左右内边距占屏幕宽度的比例

function StatusBars.Create()
    -- 根据屏幕宽度计算等比 padding
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local hPad = math.max(6, math.floor(screenW * PADDING_RATIO))

    panel_ = UI.Panel {
        id = "statusBars",
        width = "100%", height = 52,
        flexDirection = "column",
        justifyContent = "center",
        gap = 2,
        paddingHorizontal = hPad,
        paddingVertical = 3,
        backgroundColor = { 14, 18, 28, 250 },
        borderTopWidth = 1, borderTopColor = { 60, 50, 30, 120 },
        borderBottomWidth = 1, borderBottomColor = { 60, 50, 30, 120 },
        children = {
            -- HP 条行
            UI.Panel {
                width = "100%", height = 14,
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Label { text = "HP", fontSize = 9, fontColor = { 220, 80, 80, 230 }, width = 20 },
                    -- 条框（分层：填充在下，边框图在上）
                    UI.Panel {
                        flexGrow = 1, height = 14,
                        children = {
                            -- 底层：填充区域容器（left/right 用百分比匹配边框端盖比例 30/288≈10.4%）
                            UI.Panel {
                                position = "absolute",
                                left = "10.4%", top = 2, bottom = 2, right = "10.4%",
                                zIndex = 1,
                                overflow = "hidden",
                                borderRadius = 2,
                                children = {
                                    UI.Panel {
                                        id = "hp_fill",
                                        width = "100%", height = "100%",
                                        backgroundColor = { 180, 40, 40, 220 },
                                    },
                                    -- 护盾条：叠加在 HP 条上方，蓝色半透明
                                    UI.Panel {
                                        id = "shield_fill",
                                        position = "absolute",
                                        right = 0, top = 0, bottom = 0,
                                        width = "0%",
                                        backgroundColor = { 60, 160, 255, 180 },
                                    },
                                },
                            },
                            -- 上层：边框图片
                            UI.Panel {
                                position = "absolute",
                                left = 0, top = 0, right = 0, bottom = 0,
                                zIndex = 2,
                                backgroundImage = "Textures/hp_bar_frame.png",
                                backgroundFit = "cover",
                                pointerEvents = "none",
                            },
                        },
                    },
                    UI.Label { id = "hp_text", text = "", fontSize = 8, fontColor = { 200, 180, 180, 200 }, flexShrink = 0, textAlign = "right" },
                },
            },
            -- MP 条行 (法力)
            UI.Panel {
                width = "100%", height = 14,
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Label { text = "MP", fontSize = 9, fontColor = { 80, 160, 220, 230 }, width = 20 },
                    UI.Panel {
                        flexGrow = 1, height = 14,
                        children = {
                            UI.Panel {
                                position = "absolute",
                                left = "10.4%", top = 2, bottom = 2, right = "10.4%",
                                zIndex = 1,
                                overflow = "hidden",
                                borderRadius = 2,
                                children = {
                                    UI.Panel {
                                        id = "mp_fill",
                                        width = "100%", height = "100%",
                                        backgroundColor = { 40, 120, 200, 220 },
                                    },
                                },
                            },
                            UI.Panel {
                                position = "absolute",
                                left = 0, top = 0, right = 0, bottom = 0,
                                zIndex = 2,
                                backgroundImage = "Textures/hp_bar_frame.png",
                                backgroundFit = "cover",
                                pointerEvents = "none",
                            },
                        },
                    },
                    UI.Label { id = "mp_text", text = "", fontSize = 8, fontColor = { 160, 190, 220, 200 }, flexShrink = 0, textAlign = "right" },
                },
            },
            -- EXP 条行
            UI.Panel {
                width = "100%", height = 14,
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Label { text = "EXP", fontSize = 9, fontColor = { 120, 140, 220, 230 }, width = 20 },
                    UI.Panel {
                        flexGrow = 1, height = 14,
                        children = {
                            -- 底层：填充区域容器（left/right 用百分比匹配边框端盖比例 30/288≈10.4%）
                            UI.Panel {
                                position = "absolute",
                                left = "10.4%", top = 2, bottom = 2, right = "10.4%",
                                zIndex = 1,
                                overflow = "hidden",
                                borderRadius = 2,
                                children = {
                                    UI.Panel {
                                        id = "exp_fill",
                                        width = "100%", height = "100%",
                                        backgroundColor = { 80, 100, 200, 220 },
                                    },
                                },
                            },
                            -- 上层：边框图片
                            UI.Panel {
                                position = "absolute",
                                left = 0, top = 0, right = 0, bottom = 0,
                                zIndex = 2,
                                backgroundImage = "Textures/exp_bar_frame.png",
                                backgroundFit = "cover",
                                pointerEvents = "none",
                            },
                        },
                    },
                    UI.Label { id = "exp_text", text = "", fontSize = 8, fontColor = { 180, 190, 220, 200 }, flexShrink = 0, textAlign = "right" },
                },
            },
        },
    }
    return panel_
end

---@param root Widget
function StatusBars.Refresh(root)
    if not root then return end
    local p = GameState.player

    -- HP
    local maxHP = GameState.GetMaxHP()
    local curHP = GameState.playerHP
    local hpPct = maxHP > 0 and (curHP / maxHP) or 0
    local hpFill = root:FindById("hp_fill")
    if hpFill then
        local pctStr = math.floor(hpPct * 100) .. "%"
        hpFill:SetStyle({ width = pctStr })
    end
    local hpText = root:FindById("hp_text")
    if hpText then hpText:SetText(math.floor(curHP) .. "/" .. maxHP) end

    -- Shield
    local ShieldManager = require("state.ShieldManager")
    local shieldTotal = ShieldManager.GetTotal()
    local shieldFill = root:FindById("shield_fill")
    if shieldFill then
        if shieldTotal > 0 and maxHP > 0 then
            local shieldPct = math.min(1.0, shieldTotal / maxHP)
            shieldFill:SetStyle({ width = math.floor(shieldPct * 100) .. "%" })
        else
            shieldFill:SetStyle({ width = "0%" })
        end
    end

    -- MP
    local maxMana = GameState.GetMaxMana()
    local curMana = GameState.playerMana
    local mpPct = maxMana > 0 and (curMana / maxMana) or 0
    local mpFill = root:FindById("mp_fill")
    if mpFill then
        local pctStr = math.floor(mpPct * 100) .. "%"
        mpFill:SetStyle({ width = pctStr })
    end
    local mpText = root:FindById("mp_text")
    if mpText then mpText:SetText(math.floor(curMana) .. "/" .. math.floor(maxMana)) end

    -- EXP
    local needExp = Config.LevelExp(p.level)
    local expPct = needExp > 0 and (p.exp / needExp) or 0
    local expFill = root:FindById("exp_fill")
    if expFill then
        local pctStr = math.floor(expPct * 100) .. "%"
        expFill:SetStyle({ width = pctStr })
    end
    local expText = root:FindById("exp_text")
    if expText then expText:SetText(GameState.FormatBigNumber(p.exp) .. "/" .. GameState.FormatBigNumber(needExp)) end
end

return StatusBars
