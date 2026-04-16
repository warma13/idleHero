-- ============================================================================
-- ui/OfflineChest.lua - 离线挂机奖励面板
-- 全屏覆盖层: 显示离线时长、奖励预览、一键收取
-- v1.13: 可关闭面板(X按钮)、离线入口按钮、背包空间检查、多次离线奖励合并
-- ============================================================================

local UI             = require("urhox-libs/UI")
local GameState      = require("GameState")
local SlotSaveSystem = require("SlotSaveSystem")
local Config         = require("Config")
local Utils          = require("Utils")
local Toast          = require("ui.Toast")

local OfflineChest = {}

---@type Widget
local overlayRoot_ = nil
---@type Widget
local overlay_     = nil
local visible_     = false

-- 奖励数据（关闭面板后保留，直到成功领取）
local rewardData_  = nil  -- { gold, exp, equips, orangeEquips, decomposedMats, soulCrystal }
local offlineSec_  = 0

-- ============================================================================
-- 公共接口
-- ============================================================================

function OfflineChest.SetOverlayRoot(root)
    overlayRoot_ = root
end

--- 是否有未领取的离线奖励（离线奖励已禁用）
function OfflineChest.HasPendingReward()
    return false
end

--- 合并新奖励到已有的未领取奖励中
local function MergeReward(existing, new)
    existing.gold             = (existing.gold or 0) + (new.gold or 0)
    existing.exp              = (existing.exp or 0) + (new.exp or 0)
    -- 合并分解材料
    existing.decomposedMats = existing.decomposedMats or {}
    if new.decomposedMats then
        for matId, amt in pairs(new.decomposedMats) do
            existing.decomposedMats[matId] = (existing.decomposedMats[matId] or 0) + amt
        end
    end
    existing.soulCrystal      = (existing.soulCrystal or 0) + (new.soulCrystal or 0)

    -- 合并橙装列表，上限10件，溢出分解
    local MAX_ORANGE = 10
    if new.orangeEquips then
        existing.orangeEquips = existing.orangeEquips or {}
        for _, item in ipairs(new.orangeEquips) do
            if #existing.orangeEquips < MAX_ORANGE then
                table.insert(existing.orangeEquips, item)
            else
                local mats = Config.DECOMPOSE_MATERIALS[item.qualityIdx]
                if mats then
                    existing.decomposedMats = existing.decomposedMats or {}
                    for matId, amt in pairs(mats) do
                        existing.decomposedMats[matId] = (existing.decomposedMats[matId] or 0) + amt
                    end
                end
                -- 金币产出
                local dGold = Config.DECOMPOSE_GOLD[item.qualityIdx] or 0
                if dGold > 0 then
                    existing.gold = (existing.gold or 0) + dGold
                end
            end
        end
    end

    -- 合并普通装备（兜底，当前算法不产生）
    if new.equips then
        existing.equips = existing.equips or {}
        for _, item in ipairs(new.equips) do
            table.insert(existing.equips, item)
        end
    end
end

--- 检查并显示离线奖励（离线奖励已禁用，直接跳过）
function OfflineChest.Check()
    SlotSaveSystem.offlineSeconds = 0
    return
end

--- 格式化离线时长
local function FormatDuration(sec)
    local hours = math.floor(sec / 3600)
    local mins  = math.floor((sec % 3600) / 60)
    if hours > 0 then
        return hours .. "小时" .. mins .. "分钟"
    elseif mins > 0 then
        return mins .. "分钟"
    else
        return "不到1分钟"
    end
end

--- 构建奖励行 (带图标)
local function RewardRow(iconPath, label, value, color)
    return UI.Panel {
        flexDirection = "row", alignItems = "center", width = "100%",
        paddingVertical = 4, paddingHorizontal = 8,
        children = {
            UI.Panel { width = 18, height = 18, backgroundImage = iconPath, backgroundFit = "contain", marginRight = 4 },
            UI.Label { text = label, fontSize = 12, fontColor = { 200, 205, 215, 220 }, flexGrow = 1 },
            UI.Label { text = value, fontSize = 13, fontColor = color },
        },
    }
end

--- 计算橙装入背包需要的空间（排除会被自动分解的）
local function CountOrangeNeedSlots()
    if not rewardData_ or not rewardData_.orangeEquips then return 0 end

    -- 读取自动分解配置
    local activeLevel, activeMode = 0, 0
    for k = #GameState.autoDecompConfig, 1, -1 do
        if GameState.autoDecompConfig[k] > 0 then
            activeLevel = k
            activeMode = GameState.autoDecompConfig[k]
            break
        end
    end

    local need = 0
    for _, item in ipairs(rewardData_.orangeEquips) do
        -- 模拟 AddToInventory 的自动分解判断
        local willDecomp = false
        if activeLevel > 0 and item.qualityIdx and item.qualityIdx <= activeLevel
            and not item.locked and (activeMode == 1 or not (item.setId and item.qualityIdx == activeLevel)) then
            willDecomp = true
        end
        if not willDecomp then
            need = need + 1
        end
    end
    return need
end

--- 显示离线奖励面板
function OfflineChest.Show()
    if visible_ or not overlayRoot_ then return end
    if not rewardData_ then return end
    visible_ = true

    local timeStr = FormatDuration(offlineSec_)

    -- 构建奖励行列表
    local rewardRows = {}

    -- 图标路径
    local ICON_GOLD    = "icon_gold_20260307034449.png"
    local ICON_EXP     = "icon_exp_20260312174245.png"
    local ICON_EQUIP   = "equip_weapon_20260306085701.png"
    local ICON_STONE   = "icon_stone_20260307170829.png"
    local ICON_CRYSTAL = "icon_soul_crystal_20260307170758.png"

    if rewardData_.gold and rewardData_.gold > 0 then
        table.insert(rewardRows, RewardRow(ICON_GOLD, "金币", "+" .. Utils.FormatNumber(rewardData_.gold), { 255, 230, 100, 255 }))
    end
    if rewardData_.exp and rewardData_.exp > 0 then
        table.insert(rewardRows, RewardRow(ICON_EXP, "经验", "+" .. Utils.FormatNumber(rewardData_.exp), { 130, 220, 255, 255 }))
    end

    local equipCount = rewardData_.equips and #rewardData_.equips or 0
    if equipCount > 0 then
        table.insert(rewardRows, RewardRow(ICON_EQUIP, "装备", "+" .. equipCount .. "件", { 200, 160, 255, 255 }))
    end

    local orangeCount = rewardData_.orangeEquips and #rewardData_.orangeEquips or 0
    if orangeCount > 0 then
        table.insert(rewardRows, RewardRow(ICON_EQUIP, "橙色装备", "+" .. orangeCount .. "件", { 255, 165, 0, 255 }))
    end

    -- 分解材料行
    if rewardData_.decomposedMats then
        local MatMap = Config.MATERIAL_MAP
        for matId, amt in pairs(rewardData_.decomposedMats) do
            if amt > 0 then
                local def = MatMap and MatMap[matId]
                local name = def and def.name or matId
                local clr = def and def.color or { 160, 180, 200, 255 }
                table.insert(rewardRows, RewardRow(ICON_STONE, name .. "(分解)", "+" .. Utils.FormatNumber(amt), { clr[1], clr[2], clr[3], 255 }))
            end
        end
    end

    local crystal = rewardData_.soulCrystal or 0
    if crystal > 0 then
        table.insert(rewardRows, RewardRow(ICON_CRYSTAL, "魂晶", "+" .. Utils.FormatNumber(crystal), { 160, 80, 255, 255 }))
    end

    -- 全屏半透明覆盖 + 居中卡片
    overlay_ = UI.Panel {
        id = "offlineRewardOverlay",
        position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 120 },
        justifyContent = "center", alignItems = "center",
        onClick = function() OfflineChest.Dismiss() end,
        children = {
            -- 卡片
            UI.Panel {
                width = 260,
                onClick = function() end,  -- 阻止冒泡
                backgroundColor = { 30, 35, 50, 245 },
                borderRadius = 12, borderWidth = 1, borderColor = { 80, 90, 120, 160 },
                shadowColor = { 0, 0, 0, 180 }, shadowRadius = 24, shadowOffsetY = 4,
                flexDirection = "column", alignItems = "center",
                paddingVertical = 16, paddingHorizontal = 16,
                children = {
                    -- 关闭按钮 (右上角 X)
                    UI.Button {
                        text = "✕",
                        position = "absolute",
                        top = 4, right = 4,
                        width = 28, height = 28,
                        fontSize = 14,
                        fontColor = { 180, 180, 180, 200 },
                        backgroundColor = { 0, 0, 0, 0 },
                        borderRadius = 14,
                        onClick = function()
                            OfflineChest.Dismiss()
                        end,
                    },
                    -- 标题
                    UI.Label {
                        text = "离线收益",
                        fontSize = 18, fontColor = { 255, 215, 0, 255 },
                        marginBottom = 4,
                    },
                    -- 离线时长
                    UI.Label {
                        text = "你离开了 " .. timeStr,
                        fontSize = 11, fontColor = { 160, 165, 180, 180 },
                        marginBottom = 12,
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 90, 120, 80 },
                        marginBottom = 8,
                    },
                    -- 奖励列表
                    UI.Panel {
                        width = "100%", flexDirection = "column", gap = 2,
                        marginBottom = 12,
                        children = rewardRows,
                    },
                    -- 收取按钮
                    UI.Button {
                        text = "收取奖励",
                        width = "100%", height = 36,
                        fontSize = 14,
                        backgroundColor = { 60, 140, 70, 255 },
                        fontColor = { 255, 255, 255, 255 },
                        borderRadius = 8,
                        onClick = function()
                            OfflineChest.Collect()
                        end,
                    },
                },
            },
        },
    }

    overlayRoot_:AddChild(overlay_)
end

--- 关闭面板但保留奖励数据（玩家稍后可从入口按钮重新打开）
function OfflineChest.Dismiss()
    if overlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
    visible_ = false
    -- 不清除 rewardData_，保留待领取
end

--- 收取奖励并关闭
function OfflineChest.Collect()
    if not rewardData_ then
        OfflineChest.Close()
        return
    end

    -- 检查背包空间是否足够放下橙装
    local needSlots = CountOrangeNeedSlots()
    if needSlots > 0 then
        local freeSlots = GameState.GetInventorySize() - #GameState.inventory
        if freeSlots < needSlots then
            Toast.Warn("背包空间不足，请先清理背包 (需要" .. needSlots .. "格，剩余" .. freeSlots .. "格)")
            return  -- 阻止领取，面板不关闭
        end
    end

    -- 发放金币
    if rewardData_.gold and rewardData_.gold > 0 then
        GameState.AddGold(rewardData_.gold)
    end

    -- 发放经验
    if rewardData_.exp and rewardData_.exp > 0 then
        GameState.AddExp(rewardData_.exp)
    end

    -- 发放普通装备到背包
    if rewardData_.equips then
        local FloatTip = require("ui.FloatTip")
        for _, item in ipairs(rewardData_.equips) do
            local _, decompInfo = GameState.AddToInventory(item)
            if decompInfo then
                FloatTip.Decompose(decompInfo)
            end
        end
    end

    -- 发放分解获得的材料
    if rewardData_.decomposedMats then
        GameState.AddMaterials(rewardData_.decomposedMats)
    end

    -- 橙色装备直接入背包
    if rewardData_.orangeEquips then
        for _, item in ipairs(rewardData_.orangeEquips) do
            local _, decompInfo = GameState.AddToInventory(item)
            if decompInfo then
                local FloatTip = require("ui.FloatTip")
                FloatTip.Decompose(decompInfo)
            end
        end
    end

    -- 魂晶直接入账
    if rewardData_.soulCrystal and rewardData_.soulCrystal > 0 then
        GameState.AddSoulCrystal(rewardData_.soulCrystal)
    end

    -- 立即保存
    SlotSaveSystem.SaveNow()

    OfflineChest.Close()
end

--- 关闭面板并清除奖励数据（领取成功后调用）
function OfflineChest.Close()
    if overlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
    visible_ = false
    rewardData_ = nil
end

--- 保留空 Update 供 main.lua 调用 (无需每帧逻辑)
function OfflineChest.Update(dt)
end

function OfflineChest.IsVisible()
    return visible_
end

--- 将离线奖励内容构建到指定容器中（用于 RewardPanel 嵌入）
--- 保留原始卡片样式（背景、圆角、边框、阴影、标题）
function OfflineChest.BuildContent(container)
    if not container then return end

    -- 卡片内容子元素
    local cardChildren = {}

    if not rewardData_ then
        table.insert(cardChildren, UI.Label {
            text = "离线收益",
            fontSize = 18, fontColor = { 255, 215, 0, 255 },
            marginBottom = 4,
        })
        table.insert(cardChildren, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 80, 90, 120, 80 },
            marginBottom = 8,
        })
        table.insert(cardChildren, UI.Panel {
            width = "100%", alignItems = "center", justifyContent = "center",
            paddingVertical = 30,
            children = {
                UI.Label { text = "暂无离线奖励", fontSize = 13, fontColor = { 160, 165, 180, 180 } },
            },
        })
    else
        local timeStr = FormatDuration(offlineSec_)

        -- 构建奖励行列表
        local rewardRows = {}
        local ICON_GOLD    = "icon_gold_20260307034449.png"
        local ICON_EXP     = "icon_exp_20260312174245.png"
        local ICON_EQUIP   = "equip_weapon_20260306085701.png"
        local ICON_STONE   = "icon_stone_20260307170829.png"
        local ICON_CRYSTAL = "icon_soul_crystal_20260307170758.png"

        if rewardData_.gold and rewardData_.gold > 0 then
            table.insert(rewardRows, RewardRow(ICON_GOLD, "金币", "+" .. Utils.FormatNumber(rewardData_.gold), { 255, 230, 100, 255 }))
        end
        if rewardData_.exp and rewardData_.exp > 0 then
            table.insert(rewardRows, RewardRow(ICON_EXP, "经验", "+" .. Utils.FormatNumber(rewardData_.exp), { 130, 220, 255, 255 }))
        end
        local orangeCount = rewardData_.orangeEquips and #rewardData_.orangeEquips or 0
        if orangeCount > 0 then
            table.insert(rewardRows, RewardRow(ICON_EQUIP, "橙色装备", "+" .. orangeCount .. "件", { 255, 165, 0, 255 }))
        end
        -- 分解材料行
        if rewardData_.decomposedMats then
            local MatMap = Config.MATERIAL_MAP
            for matId, amt in pairs(rewardData_.decomposedMats) do
                if amt > 0 then
                    local def = MatMap and MatMap[matId]
                    local name = def and def.name or matId
                    local clr = def and def.color or { 160, 180, 200, 255 }
                    table.insert(rewardRows, RewardRow(ICON_STONE, name .. "(分解)", "+" .. Utils.FormatNumber(amt), { clr[1], clr[2], clr[3], 255 }))
                end
            end
        end
        local crystal = rewardData_.soulCrystal or 0
        if crystal > 0 then
            table.insert(rewardRows, RewardRow(ICON_CRYSTAL, "魂晶", "+" .. Utils.FormatNumber(crystal), { 160, 80, 255, 255 }))
        end

        -- 标题
        table.insert(cardChildren, UI.Label {
            text = "离线收益",
            fontSize = 18, fontColor = { 255, 215, 0, 255 },
            marginBottom = 4,
        })
        -- 离线时长
        table.insert(cardChildren, UI.Label {
            text = "你离开了 " .. timeStr,
            fontSize = 11, fontColor = { 160, 165, 180, 180 },
            marginBottom = 12,
        })
        -- 分隔线
        table.insert(cardChildren, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 80, 90, 120, 80 },
            marginBottom = 8,
        })
        -- 奖励列表
        table.insert(cardChildren, UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            marginBottom = 12,
            children = rewardRows,
        })
        -- 收取按钮
        table.insert(cardChildren, UI.Button {
            text = "收取奖励",
            width = "100%", height = 36,
            fontSize = 14,
            backgroundColor = { 60, 140, 70, 255 },
            fontColor = { 255, 255, 255, 255 },
            borderRadius = 8,
            onClick = function()
                OfflineChest.Collect()
                if OfflineChest._embeddedRefreshFn then
                    OfflineChest._embeddedRefreshFn()
                end
            end,
        })
    end

    -- 原始卡片样式（flexShrink=1 配合 RewardPanel 的 overflow hidden 限高）
    container:AddChild(UI.Panel {
        width = 260,
        flexShrink = 1,
        onClick = function() end,
        backgroundColor = { 30, 35, 50, 245 },
        borderRadius = 12, borderWidth = 1, borderColor = { 80, 90, 120, 160 },
        shadowColor = { 0, 0, 0, 180 }, shadowRadius = 24, shadowOffsetY = 4,
        flexDirection = "column", alignItems = "center",
        paddingVertical = 16, paddingHorizontal = 16,
        overflow = "scroll",
        children = cardChildren,
    })
end

--- 设置嵌入模式的刷新回调
function OfflineChest.SetEmbeddedRefresh(fn)
    OfflineChest._embeddedRefreshFn = fn
end

return OfflineChest
