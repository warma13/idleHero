-- ============================================================================
-- DailyRewards.lua - 日常任务奖励系统
-- ============================================================================

local GameState  = require("GameState")
local SaveSystem = require("SaveSystem")
local Config     = require("Config")
local UI         = require("urhox-libs/UI")
local Colors     = require("ui.Colors")
local Toast      = require("ui.Toast")
local Utils      = require("Utils")

local DailyRewards = {}

-- ============================================================================
-- 图标
-- ============================================================================

local ICON = "icon_daily_rewards_20260310143202.png"

function DailyRewards.GetIcon()
    return ICON
end

-- ============================================================================
-- 奖励配置（后续可自由修改此处）
-- 支持字段: gold / soulCrystal / materials / bagItems / equips
-- ============================================================================

DailyRewards.CONFIG = {
    -- 日常签到: 7天循环，第7天大奖后重置
    daily = {
        [1] = { gold = 1000 },
        [2] = { gold = 1500 },
        [3] = { soulCrystal = 50 },
        [4] = { gold = 2000 },
        [5] = { materials = { iron = 20, crystal = 10 } },
        [6] = { soulCrystal = 100 },
        [7] = { soulCrystal = 200, materials = { iron = 30, crystal = 15, wraith = 5 } },
    },
}

-- ============================================================================
-- 日期工具
-- ============================================================================

local function getTodayStr()
    return os.date("%Y-%m-%d", os.time())
end

-- ============================================================================
-- 奖励图标
-- ============================================================================

local REWARD_ICONS = {
    gold        = "icon_gold_20260307034449.png",
    soulCrystal = "icon_soul_crystal_20260307170758.png",
    iron        = "icon_stone_20260307170829.png",  -- 暂用旧图标
    crystal     = "icon_stone_20260307170829.png",
    wraith      = "icon_stone_20260307170829.png",
    eternal     = "icon_stone_20260307170829.png",
    abyssHeart  = "icon_stone_20260307170829.png",
    riftEcho    = "icon_stone_20260307170829.png",
}

-- ============================================================================
-- 日常任务配置
-- ============================================================================

---@class QuestDef
---@field name string
---@field desc string
---@field trackKey string
---@field target number
---@field points number
---@field stars number
---@field rewards table

DailyRewards.QUESTS = {
    { name = "初露锋芒",   desc = "通关3个关卡",       trackKey = "stages",      target = 3,    points = 10, stars = 1, rewards = { gold = 250 } },
    { name = "杀戮机器",   desc = "击败80个怪物",       trackKey = "kills",       target = 80,   points = 10, stars = 1, rewards = { gold = 350 } },
    { name = "以战养战",   desc = "强化装备3次",        trackKey = "enhance",     target = 3,    points = 15, stars = 1, rewards = { materials = { iron = 8, crystal = 4 } } },
    { name = "挥金如土",   desc = "花费5000金币",       trackKey = "goldSpent",   target = 5000, points = 10, stars = 1, rewards = { soulCrystal = 4 } },
    { name = "魔力涌动",   desc = "使用技能10次",       trackKey = "skills",      target = 10,   points = 15, stars = 2, rewards = { soulCrystal = 5 } },
    { name = "挑战强者",   desc = "挑战Boss 3次",       trackKey = "bossAttempts",  target = 3,    points = 20, stars = 2, rewards = { gold = 600, soulCrystal = 6 } },
    { name = "试炼之路",   desc = "挑战试炼 3次",       trackKey = "trialAttempts", target = 3,    points = 25, stars = 3, rewards = { gold = 900, materials = { crystal = 6 } } },
    { name = "森林探秘",   desc = "挑战魔力之森2次",    trackKey = "manaForestRuns", target = 2,   points = 15, stars = 2, rewards = { gold = 400 } },
}

DailyRewards.MILESTONES = {
    { threshold = 20,  rewards = { soulCrystal = 30 } },
    { threshold = 50,  rewards = { materials = { iron = 40, crystal = 20 } } },
    { threshold = 80,  rewards = { materials = { crystal = 30, wraith = 10 } } },
    { threshold = 105, rewards = { soulCrystal = 100, equip = { quality = 4 } } },
}

-- ============================================================================
-- 通用奖励发放（复用 VersionReward 的模式）
-- ============================================================================

local function grantRewards(rewards)
    if not rewards then return end
    if rewards.gold and rewards.gold > 0 then
        GameState.AddGold(rewards.gold)
    end
    if rewards.soulCrystal and rewards.soulCrystal > 0 then
        GameState.AddSoulCrystal(rewards.soulCrystal)
    end
    if rewards.materials then
        GameState.AddMaterials(rewards.materials)
    end
    if rewards.bagItems then
        for _, bi in ipairs(rewards.bagItems) do
            GameState.AddBagItem(bi.id, bi.count or 1)
        end
    end
    if rewards.equips then
        for _, eq in ipairs(rewards.equips) do
            local item = GameState.CreateEquip(eq.minQuality or 1, eq.chapter, eq.slot)
            GameState.AddToInventory(item)
        end
    end
    -- 单装备奖励 (里程碑格式: equip = { quality = 4 })
    if rewards.equip then
        local ch = GameState.stage and GameState.stage.chapter or 1
        local item = GameState.CreateEquip(rewards.equip.quality or 4, ch)
        item.locked = true  -- 标记锁定，防止被自动分解
        GameState.AddToInventory(item)
    end
end

-- ============================================================================
-- 日常任务进度管理
-- ============================================================================

--- 确保 quests 结构存在并检查日期重置
local function ensureQuestsState()
    local dr = GameState.dailyRewards
    if not dr.quests then
        dr.quests = { date = "", progress = {}, claimed = {}, milestones = {}, activityPoints = 0 }
    end
    local today = getTodayStr()
    if dr.quests.date ~= today then
        dr.quests.date = today
        dr.quests.progress = {}
        dr.quests.claimed = {}
        dr.quests.milestones = {}
        dr.quests.activityPoints = 0
    end
    return dr.quests
end

--- 节流存档：高频 trackKey（如 kills）不会每次都写盘
local TRACK_SAVE_INTERVAL = 5       -- 至少间隔 5 秒才写盘一次
local lastTrackSaveTime_  = 0       -- 上次存档的 time:GetElapsedTime()
local trackDirty_         = false   -- 有未存档的进度变更

--- 外部调用：追踪任务进度
--- @param trackKey string  "kills"|"stages"|"bossAttempts"|"enhance"|"skills"|"goldSpent"|"trialAttempts"
--- @param amount number    增量（默认 1）
function DailyRewards.TrackProgress(trackKey, amount)
    local qs = ensureQuestsState()
    qs.progress[trackKey] = (qs.progress[trackKey] or 0) + (amount or 1)
    local now = time:GetElapsedTime()
    if now - lastTrackSaveTime_ >= TRACK_SAVE_INTERVAL then
        lastTrackSaveTime_ = now
        trackDirty_ = false
        SaveSystem.Save()
    else
        trackDirty_ = true
    end
end

--- 刷盘：在关键时机（如切后台、退出战斗）调用，确保脏数据落盘
function DailyRewards.FlushProgress()
    if trackDirty_ then
        trackDirty_ = false
        lastTrackSaveTime_ = time:GetElapsedTime()
        SaveSystem.Save()
    end
end

--- 获取任务当前进度
local function getQuestProgress(questIdx)
    local qs = ensureQuestsState()
    local quest = DailyRewards.QUESTS[questIdx]
    if not quest then return 0, 0, false, false end
    local cur = qs.progress[quest.trackKey] or 0
    local done = cur >= quest.target
    local claimed = qs.claimed[tostring(questIdx)] == true
    return cur, quest.target, done, claimed
end

--- 领取单个任务奖励
function DailyRewards.ClaimQuest(questIdx)
    local qs = ensureQuestsState()
    local quest = DailyRewards.QUESTS[questIdx]
    if not quest then return false, "无效任务" end
    local cur = qs.progress[quest.trackKey] or 0
    if cur < quest.target then return false, "任务未完成" end
    if qs.claimed[tostring(questIdx)] then return false, "已领取" end

    grantRewards(quest.rewards)
    qs.claimed[tostring(questIdx)] = true
    qs.activityPoints = qs.activityPoints + quest.points

    SaveSystem.Save()
    return true, "+" .. quest.points .. " 活跃点"
end

--- 领取里程碑奖励
function DailyRewards.ClaimMilestone(threshold)
    local qs = ensureQuestsState()
    local threshKey = tostring(threshold)
    if qs.milestones[threshKey] then return false, "已领取" end
    if qs.activityPoints < threshold then return false, "活跃点不足" end

    for _, ms in ipairs(DailyRewards.MILESTONES) do
        if ms.threshold == threshold then
            -- 背包空间检查（含装备奖励时）
            if ms.rewards.equip then
                local cap = GameState.GetInventorySize()
                local used = #GameState.inventory
                if used >= cap then
                    return false, "背包空间不足"
                end
            end
            grantRewards(ms.rewards)
            qs.milestones[threshKey] = true
            SaveSystem.Save()
            return true, "里程碑奖励已领取！"
        end
    end
    return false, "未找到里程碑"
end

--- 一键领取所有已完成任务
function DailyRewards.ClaimAllQuests()
    local qs = ensureQuestsState()
    local count = 0
    for i, quest in ipairs(DailyRewards.QUESTS) do
        local cur = qs.progress[quest.trackKey] or 0
        if cur >= quest.target and not qs.claimed[tostring(i)] then
            grantRewards(quest.rewards)
            qs.claimed[tostring(i)] = true
            qs.activityPoints = qs.activityPoints + quest.points
            count = count + 1
        end
    end
    if count > 0 then
        SaveSystem.Save()
        return true, count .. " 个任务奖励已领取"
    end
    return false, "没有可领取的任务"
end

--- 是否有可领取的任务或里程碑
function DailyRewards.HasClaimableQuests()
    local qs = ensureQuestsState()
    for i, quest in ipairs(DailyRewards.QUESTS) do
        local cur = qs.progress[quest.trackKey] or 0
        if cur >= quest.target and not qs.claimed[tostring(i)] then return true end
    end
    for _, ms in ipairs(DailyRewards.MILESTONES) do
        if qs.activityPoints >= ms.threshold and not qs.milestones[tostring(ms.threshold)] then
            return true
        end
    end
    return false
end



--- 生成奖励描述文本
--- @param rewards table
--- @return string
local function describeRewards(rewards)
    if not rewards then return "" end
    local parts = {}
    if rewards.gold and rewards.gold > 0 then
        table.insert(parts, "金币×" .. rewards.gold)
    end
    if rewards.soulCrystal and rewards.soulCrystal > 0 then
        table.insert(parts, "魂晶×" .. rewards.soulCrystal)
    end
    if rewards.materials then
        for matId, amount in pairs(rewards.materials) do
            local def = Config.MATERIAL_MAP[matId]
            local name = def and def.name or matId
            table.insert(parts, name .. "×" .. amount)
        end
    end
    if rewards.bagItems then
        for _, bi in ipairs(rewards.bagItems) do
            local cfg = Config.ITEM_MAP[bi.id]
            local name = cfg and cfg.name or bi.id
            table.insert(parts, name .. "×" .. (bi.count or 1))
        end
    end
    if rewards.equips then
        local QUALITY_NAMES = { "白色", "绿色", "蓝色", "紫色", "橙色" }
        for _, eq in ipairs(rewards.equips) do
            local qName = QUALITY_NAMES[eq.minQuality or 1] or "白色"
            table.insert(parts, qName .. "装备×1")
        end
    end
    if rewards.equip then
        local QUALITY_NAMES = { "白色", "绿色", "蓝色", "紫色", "橙色" }
        local qName = QUALITY_NAMES[rewards.equip.quality or 4] or "橙色"
        table.insert(parts, qName .. "装备×1")
    end
    return table.concat(parts, "  ")
end

-- ============================================================================
-- 日常签到逻辑
-- ============================================================================

function DailyRewards.CanClaimDaily()
    local dr = GameState.dailyRewards
    return dr.daily.lastClaimDate ~= getTodayStr()
end

function DailyRewards.ClaimDaily()
    local dr = GameState.dailyRewards
    local today = getTodayStr()
    if dr.daily.lastClaimDate == today then
        return false, "今日已签到"
    end

    local nextDay = dr.daily.currentDay + 1
    if nextDay > 7 then nextDay = 1 end

    local rewards = DailyRewards.CONFIG.daily[nextDay]
    if not rewards then return false, "配置错误" end

    -- 装备背包预检
    if rewards.equips and #rewards.equips > 0 then
        local cap = GameState.GetInventorySize()
        local used = #GameState.inventory
        if (cap - used) < #rewards.equips then
            return false, "背包空间不足"
        end
    end

    grantRewards(rewards)

    dr.daily.currentDay = nextDay
    dr.daily.lastClaimDate = today

    SaveSystem.Save()
    return true, "签到成功！" .. describeRewards(rewards)
end



-- ============================================================================
-- 红点判断
-- ============================================================================

function DailyRewards.HasRedDot()
    return DailyRewards.HasClaimableQuests()
end

-- ============================================================================
-- UI 弹窗
-- ============================================================================

---@type Widget
local overlay_     = nil
---@type Widget
local overlayRoot_ = nil

function DailyRewards.SetOverlayRoot(root)
    overlayRoot_ = root
end

function DailyRewards.Hide()
    if overlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
end

-- ---- 奖励颜色 ----
local REWARD_COLORS = {
    gold        = { 255, 215, 0, 255 },
    soulCrystal = { 180, 100, 255, 255 },
    iron        = { 180, 160, 140, 255 },
    crystal     = { 100, 140, 220, 255 },
    wraith      = { 180, 80, 220, 255 },
    eternal     = { 255, 165, 0, 255 },
    abyssHeart  = { 200, 50, 80, 255 },
    riftEcho    = { 80, 220, 200, 255 },
    default     = { 200, 210, 220, 255 },
}

--- 构建奖励图标行
local function BuildRewardIcons(rewards, iconSize)
    iconSize = iconSize or 14
    local children = {}
    local order = { "gold", "soulCrystal" }
    for _, key in ipairs(order) do
        local val = rewards[key]
        if val and val > 0 then
            table.insert(children, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                children = {
                    UI.Panel { width = iconSize, height = iconSize,
                        backgroundImage = REWARD_ICONS[key], backgroundFit = "contain" },
                    UI.Label { text = tostring(val), fontSize = 10,
                        fontColor = REWARD_COLORS[key] or REWARD_COLORS.default },
                },
            })
        end
    end
    -- 材料奖励
    if rewards.materials then
        for matId, amount in pairs(rewards.materials) do
            table.insert(children, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                children = {
                    UI.Panel { width = iconSize, height = iconSize,
                        backgroundImage = REWARD_ICONS[matId] or REWARD_ICONS.iron, backgroundFit = "contain" },
                    UI.Label { text = tostring(amount), fontSize = 10,
                        fontColor = REWARD_COLORS[matId] or REWARD_COLORS.default },
                },
            })
        end
    end
    return children
end

--- 构建日常任务 Tab 内容
local function BuildDailyTab()
    local qs = ensureQuestsState()
    local totalPts = qs.activityPoints
    local maxPts = DailyRewards.MILESTONES[#DailyRewards.MILESTONES].threshold

    -- ====== 上半部分：活跃点数 + 里程碑奖励 ======
    local milestoneChildren = {}
    for _, ms in ipairs(DailyRewards.MILESTONES) do
        local reached = totalPts >= ms.threshold
        local msKey = tostring(ms.threshold)
        local claimed = qs.milestones[msKey] == true
        local canClaim = reached and not claimed

        -- 宝箱图标
        local boxColor = claimed and { 60, 75, 60, 200 }
            or canClaim and { 70, 55, 20, 240 }
            or { 40, 42, 55, 200 }
        local boxBorder = canClaim and { 255, 200, 60, 200 } or { 60, 70, 90, 100 }

        -- 生成奖励简短描述
        local rewardLines = {}
        local REWARD_NAMES = { gold = "金", soulCrystal = "魂晶" }
        for key, val in pairs(ms.rewards) do
            if key == "materials" then
                for matId, amt in pairs(val) do
                    local def = Config.MATERIAL_MAP[matId]
                    table.insert(rewardLines, (def and def.name or matId) .. "×" .. amt)
                end
            elseif key == "equip" then
                table.insert(rewardLines, "橙装×1")
            else
                table.insert(rewardLines, val .. (REWARD_NAMES[key] or key))
            end
        end

        table.insert(milestoneChildren, UI.Panel {
            flex = 1, alignItems = "center", gap = 2,
            children = {
                -- 宝箱按钮
                UI.Panel {
                    width = 44, minHeight = 36,
                    backgroundColor = boxColor,
                    borderRadius = 6,
                    borderWidth = canClaim and 1 or 0,
                    borderColor = boxBorder,
                    alignItems = "center", justifyContent = "center",
                    paddingVertical = 2, paddingHorizontal = 2,
                    onClick = canClaim and Utils.Debounce(function()
                        local ok, msg = DailyRewards.ClaimMilestone(ms.threshold)
                        Toast.Show(msg)
                        if DailyRewards._embeddedRefreshFn then
                            DailyRewards._embeddedRefreshFn()
                        else
                            DailyRewards.Hide()
                            DailyRewards.Show()
                        end
                    end, 0.5) or nil,
                    children = (function()
                        local labels = {}
                        for _, line in ipairs(rewardLines) do
                            table.insert(labels, UI.Label {
                                text = line, fontSize = 8, textAlign = "center",
                                fontColor = claimed and { 80, 130, 80 } or (canClaim and { 255, 220, 80 } or { 140, 150, 170 }),
                            })
                        end
                        return labels
                    end)(),
                },
                -- 点数标签
                UI.Label {
                    text = ms.threshold .. "pt",
                    fontSize = 9,
                    fontColor = reached and { 255, 220, 100 } or { 120, 130, 150 },
                },
            },
        })
    end

    -- 进度条
    local progressPct = math.min(totalPts / maxPts * 100, 100)
    local pointsHeader = UI.Panel {
        width = "100%", gap = 6,
        children = {
            -- 活跃点数标题
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label { text = "活跃点数", fontSize = 11, fontColor = Colors.textDim },
                    UI.Label { text = totalPts .. " / " .. maxPts, fontSize = 12,
                        fontColor = { 255, 220, 100 } },
                },
            },
            -- 进度条
            UI.Panel {
                width = "100%", height = 6,
                backgroundColor = { 40, 42, 55, 200 },
                borderRadius = 3,
                children = {
                    UI.Panel {
                        width = progressPct .. "%", height = "100%",
                        backgroundColor = { 255, 180, 40, 230 },
                        borderRadius = 3,
                    },
                },
            },
            -- 里程碑宝箱行
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 4,
                children = milestoneChildren,
            },
        },
    }

    -- ====== 下半部分：任务列表 ======
    local questItems = {}
    for i, quest in ipairs(DailyRewards.QUESTS) do
        local cur, target, done, claimed = getQuestProgress(i)
        local canClaim = done and not claimed
        local displayCur = math.min(cur, target)

        -- 星级
        local starStr = string.rep("*", quest.stars)

        -- 背景色
        local bgColor = claimed and { 35, 50, 35, 180 }
            or canClaim and { 55, 48, 20, 220 }
            or { 35, 38, 50, 180 }
        local borderColor = canClaim and { 255, 200, 60, 150 } or { 60, 70, 90, 80 }

        -- 奖励图标
        local rewardIcons = BuildRewardIcons(quest.rewards)

        -- 右侧状态
        local statusWidget
        if claimed then
            statusWidget = UI.Label { text = displayCur .. "/" .. target, fontSize = 10, fontColor = { 80, 130, 80 }, width = 50, textAlign = "center" }
        elseif canClaim then
            statusWidget = UI.Panel {
                width = 40, height = 22,
                backgroundColor = { 200, 160, 30, 255 },
                borderRadius = 4,
                alignItems = "center", justifyContent = "center",
                onClick = Utils.Debounce(function()
                    local ok, msg = DailyRewards.ClaimQuest(i)
                    Toast.Show(msg)
                    if DailyRewards._embeddedRefreshFn then
                        DailyRewards._embeddedRefreshFn()
                    else
                        DailyRewards.Hide()
                        DailyRewards.Show()
                    end
                end, 0.5),
                children = {
                    UI.Label { text = "领取", fontSize = 10, fontColor = { 30, 20, 0 } },
                },
            }
        else
            statusWidget = UI.Label {
                text = displayCur .. "/" .. target,
                fontSize = 10, fontColor = { 120, 130, 150 },
                width = 50, textAlign = "center",
            }
        end

        table.insert(questItems, UI.Panel {
            width = "100%",
            flexDirection = "row", alignItems = "center",
            paddingHorizontal = 8, paddingVertical = 6, gap = 6,
            backgroundColor = bgColor,
            borderRadius = 6,
            borderWidth = canClaim and 1 or 0,
            borderColor = borderColor,
            children = {
                -- 星级 + 任务名
                UI.Panel {
                    flex = 1, gap = 1, flexShrink = 1,
                    children = {
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 4,
                            children = {
                                UI.Label { text = starStr, fontSize = 10,
                                    fontColor = { 255, 200, 60 } },
                                UI.Label { text = quest.name, fontSize = 12,
                                    fontColor = claimed and { 100, 130, 100 } or { 220, 225, 235 } },
                            },
                        },
                        -- 任务描述
                        UI.Label { text = quest.desc, fontSize = 9,
                            fontColor = { 140, 145, 160 } },
                        -- 奖励图标行
                        UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 6,
                            children = rewardIcons,
                        },
                    },
                },
                -- 活跃点
                UI.Label {
                    text = "+" .. quest.points,
                    fontSize = 10,
                    fontColor = claimed and { 80, 120, 80 } or { 180, 200, 255 },
                    width = 32,
                    textAlign = "center",
                },
                -- 状态
                statusWidget,
            },
        })
    end

    -- 一键领取按钮
    local hasClaimable = false
    for i, quest in ipairs(DailyRewards.QUESTS) do
        local _, _, done, claimed = getQuestProgress(i)
        if done and not claimed then hasClaimable = true; break end
    end

    local claimAllBtn
    if hasClaimable then
        claimAllBtn = UI.Button {
            text = "一键领取",
            width = "100%", height = 32, fontSize = 12,
            variant = "primary",
            onClick = Utils.Debounce(function()
                local ok, msg = DailyRewards.ClaimAllQuests()
                Toast.Show(msg)
                if DailyRewards._embeddedRefreshFn then
                    DailyRewards._embeddedRefreshFn()
                else
                    DailyRewards.Hide()
                    DailyRewards.Show()
                end
            end, 0.5),
        }
    end

    return UI.Panel {
        width = "100%", gap = 8,
        children = {
            pointsHeader,
            -- 分割
            UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 90, 120, 60 } },
            -- 任务标题
            UI.Label { text = "日常任务", fontSize = 11, fontColor = Colors.textDim },
            -- 任务列表
            UI.Panel { width = "100%", gap = 4, children = questItems },
            -- 一键领取
            claimAllBtn,
        },
    }
end



function DailyRewards.Show()
    if overlay_ then DailyRewards.Hide() end

    overlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() DailyRewards.Hide() end,
        children = {
            UI.Panel {
                width = "82%", maxWidth = 320,
                maxHeight = "88%",
                backgroundColor = { 28, 32, 48, 250 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                padding = 12,
                gap = 10,
                overflow = "scroll",
                onClick = function() end,  -- 阻止穿透
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%", alignItems = "center",
                        children = {
                            UI.Label { text = "每日福利", fontSize = 16, fontColor = { 255, 220, 100, 255 } },
                        },
                    },
                    -- 分割线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 90, 120, 80 } },
                    -- 日常任务内容
                    BuildDailyTab(),
                    -- 关闭
                    UI.Button {
                        text = "关闭", width = "100%", height = 30, fontSize = 12,
                        onClick = function() DailyRewards.Hide() end,
                    },
                },
            },
        },
    }

    overlayRoot_:AddChild(overlay_)
end

function DailyRewards.Toggle()
    if overlay_ then DailyRewards.Hide() else DailyRewards.Show() end
end

--- 将日常奖励内容构建到指定容器中（用于 RewardPanel 嵌入）
--- 保留原始卡片样式（背景、圆角、边框、标题、分割线）
--- @param container Widget 目标容器
--- @param refreshFn function|nil 刷新整个 RewardPanel 的回调
function DailyRewards.BuildContent(container, refreshFn)
    if not container then return end

    -- 原始卡片样式（flexShrink=1 配合 RewardPanel 的 overflow hidden 限高）
    container:AddChild(UI.Panel {
        width = "100%", maxWidth = 320,
        flexShrink = 1,
        backgroundColor = { 28, 32, 48, 250 },
        borderRadius = 12,
        borderWidth = 1, borderColor = { 100, 120, 180, 120 },
        padding = 12,
        gap = 10,
        overflow = "scroll",
        onClick = function() end,
        children = {
            -- 标题
            UI.Panel {
                width = "100%", alignItems = "center",
                children = {
                    UI.Label { text = "每日福利", fontSize = 16, fontColor = { 255, 220, 100, 255 } },
                },
            },
            -- 分割线
            UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 90, 120, 80 } },
            -- 日常任务内容
            BuildDailyTab(),
        },
    })
end

--- 刷新嵌入模式的回调（RewardPanel 调用）
function DailyRewards.SetEmbeddedRefresh(fn)
    DailyRewards._embeddedRefreshFn = fn
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "dailyRewards",
    keys  = { "dailyRewards" },
    group = "misc",
    serialize = function(GS)
        return {
            dailyRewards = GS.dailyRewards or nil,
        }
    end,
    deserialize = function(GS, data)
        if data.dailyRewards and type(data.dailyRewards) == "table" then
            local dr = data.dailyRewards
            if dr.daily and type(dr.daily) == "table" then
                GS.dailyRewards.daily.currentDay   = dr.daily.currentDay or 0
                GS.dailyRewards.daily.lastClaimDate = dr.daily.lastClaimDate or ""
            end
            if dr.quests and type(dr.quests) == "table" then
                GS.dailyRewards.quests.date           = dr.quests.date or ""
                GS.dailyRewards.quests.progress       = dr.quests.progress or {}
                GS.dailyRewards.quests.claimed         = dr.quests.claimed or {}
                GS.dailyRewards.quests.milestones      = dr.quests.milestones or {}
                GS.dailyRewards.quests.activityPoints  = dr.quests.activityPoints or 0
            end
        end
    end,
})

return DailyRewards
