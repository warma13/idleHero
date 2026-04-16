-- ============================================================================
-- ui/AdExchange.lua - 看广告兑换奖励面板
-- ============================================================================

local UI         = require("urhox-libs/UI")
local GameState  = require("GameState")
local SaveSystem = require("SaveSystem")
local Config     = require("Config")
local Colors     = require("ui.Colors")
local Toast      = require("ui.Toast")
local Utils      = require("Utils")

local AdExchange = {}

-- ============================================================================
-- 常量
-- ============================================================================

local ICON = "icon_gold_20260307034449.png"

--- 每日广告次数上限
local DAILY_AD_LIMIT = 10

--- 兑换奖励配置
local REWARDS = {
    { id = "gold",        name = "金币",   amount = 1500,  icon = "icon_gold_20260307034449.png",           color = { 255, 215, 0 } },
    { id = "soulCrystal", name = "魂晶",   amount = 10,    icon = "icon_soul_crystal_20260307170758.png",   color = { 180, 120, 255 } },
    { id = "stone",       name = "强化石", amount = 20,    icon = "icon_stone_20260307170829.png",           color = { 120, 200, 255 } },
}

-- ============================================================================
-- 状态
-- ============================================================================

---@type Widget
local overlayRoot_ = nil
---@type Widget
local overlay_     = nil

function AdExchange.GetIcon()
    return ICON
end

-- ============================================================================
-- 每日次数管理
-- ============================================================================

local function GetTodayStr()
    return os.date("%Y-%m-%d", os.time())
end

--- 获取今日已观看次数
local function GetTodayCount()
    local ad = GameState.adExchange or {}
    local today = GetTodayStr()
    if ad.date ~= today then
        return 0
    end
    return ad.count or 0
end

--- 记录一次观看
local function RecordWatch()
    if not GameState.adExchange then
        GameState.adExchange = {}
    end
    local today = GetTodayStr()
    if GameState.adExchange.date ~= today then
        GameState.adExchange.date = today
        GameState.adExchange.count = 0
    end
    GameState.adExchange.count = (GameState.adExchange.count or 0) + 1
end

--- 获取剩余次数
local function GetRemaining()
    return math.max(0, DAILY_AD_LIMIT - GetTodayCount())
end

-- ============================================================================
-- 发放奖励
-- ============================================================================

local function GiveReward(rewardCfg)
    if rewardCfg.id == "gold" then
        GameState.AddGold(rewardCfg.amount)
    elseif rewardCfg.id == "soulCrystal" then
        GameState.AddSoulCrystal(rewardCfg.amount)
    elseif rewardCfg.id == "stone" or rewardCfg.id == "iron" then
        GameState.AddMaterial("iron", rewardCfg.amount)
    elseif rewardCfg.id == "crystal" then
        GameState.AddMaterial("crystal", rewardCfg.amount)
    end
end

-- ============================================================================
-- 观看广告
-- ============================================================================

local watching_ = false

local function WatchAd(rewardCfg)
    if watching_ then return end

    local remaining = GetRemaining()
    if remaining <= 0 then
        Toast.Warn("今日广告次数已用完")
        return
    end

    watching_ = true

    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        sdk:ShowRewardVideoAd(function(result)
            watching_ = false
            if result.success then
                RecordWatch()
                GiveReward(rewardCfg)
                SaveSystem.Save()
                Toast.Success("获得 " .. rewardCfg.name .. " ×" .. rewardCfg.amount)
                -- 刷新面板
                if overlay_ then
                    AdExchange.Close()
                    AdExchange.Show()
                end
            else
                if result.msg == "embed manual close" then
                    Toast.Warn("需完整观看广告才能获得奖励")
                else
                    Toast.Warn("广告播放失败")
                end
            end
        end)
    end)

    if not ok then
        watching_ = false
        Toast.Warn("广告功能暂不可用")
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function AdExchange.SetOverlayRoot(root)
    overlayRoot_ = root
end

function AdExchange.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

function AdExchange.IsOpen()
    return overlay_ ~= nil
end

function AdExchange.Toggle()
    if overlay_ then
        AdExchange.Close()
    else
        AdExchange.Show()
    end
end

function AdExchange.Show()
    if overlay_ then AdExchange.Close() end
    if not overlayRoot_ then return end

    local remaining = GetRemaining()

    -- 奖励卡片列表
    local cards = {}
    for _, rw in ipairs(REWARDS) do
        local c = rw.color
        table.insert(cards, UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            backgroundColor = { 32, 38, 52, 220 },
            borderRadius = 10,
            borderWidth = 1, borderColor = { c[1], c[2], c[3], 80 },
            paddingHorizontal = 14, paddingVertical = 10,
            marginBottom = 8,
            children = {
                -- 图标
                UI.Panel {
                    width = 36, height = 36,
                    backgroundImage = rw.icon,
                    backgroundFit = "contain",
                    marginRight = 12,
                },
                -- 名称+数量
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        UI.Label { text = rw.name, fontSize = 15, color = { c[1], c[2], c[3], 255 } },
                        UI.Label { text = "×" .. rw.amount, fontSize = 12, color = Colors.textDim },
                    },
                },
                -- 观看按钮
                UI.Button {
                    text = remaining > 0 and "📺 观看" or "已用完",
                    fontSize = 13,
                    variant = remaining > 0 and "primary" or "outline",
                    disabled = remaining <= 0,
                    paddingHorizontal = 16, paddingVertical = 6,
                    onClick = function()
                        if remaining > 0 then
                            WatchAd(rw)
                        end
                    end,
                },
            },
        })
    end

    overlay_ = UI.Panel {
        position = "absolute", left = 0, top = 0, right = 0, bottom = 0,
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        onClick = function() AdExchange.Close() end,
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = Colors.bg,
                borderRadius = 14,
                borderWidth = 1, borderColor = Colors.cardBorder,
                paddingHorizontal = 16, paddingVertical = 16,
                onClick = function() end,  -- 阻止穿透关闭
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                        marginBottom = 12,
                        children = {
                            UI.Label { text = "广告兑换", fontSize = 18, color = Colors.text },
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    UI.Label {
                                        text = "剩余 " .. remaining .. "/" .. DAILY_AD_LIMIT,
                                        fontSize = 12,
                                        color = remaining > 0 and { 100, 220, 120, 220 } or { 255, 100, 80, 220 },
                                    },
                                },
                            },
                        },
                    },
                    -- 说明
                    UI.Label {
                        text = "观看广告即可免费兑换奖励，每日重置",
                        fontSize = 11, color = Colors.textDim,
                        marginBottom = 12,
                    },
                    -- 奖励列表
                    table.unpack(cards),
                },
            },
        },
    }

    overlayRoot_:AddChild(overlay_)
end

-- ============================================================================
-- 存档域注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "adExchange",
    keys  = { "adExchange" },
    group = "misc",
    serialize = function(GS)
        return {
            adExchange = GS.adExchange or nil,
        }
    end,
    deserialize = function(GS, data)
        if data.adExchange and type(data.adExchange) == "table" then
            GS.adExchange = data.adExchange
        end
    end,
})

return AdExchange
