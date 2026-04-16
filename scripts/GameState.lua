-- ============================================================================
-- GameState.lua - 挂机自动战斗游戏 中央数据管理
-- (术士: 元素流派, 元素附着+反应输出导向)
-- ============================================================================

local Config = require("Config")
local SkillTreeConfig = require("SkillTreeConfig")
local StageConfig = require("StageConfig")
local SecureNum = require("utils.SecureNum")
local StatDefs = require("state.StatDefs")

local GameState = {}

-- ============================================================================
-- 初始化
-- ============================================================================

function GameState.Init()
    -- 玩家数据 (术士)
    GameState.player = {
        class = Config.PLAYER.class,
        className = Config.PLAYER.className,
        level = 1,
        exp = 0,
        gold = 0,
        baseAtk = Config.PLAYER.baseAtk,
        atkSpeed = Config.PLAYER.atkSpeed,
        critRate = 0.05,
        critDmg = Config.PLAYER.baseCritDmg,
        pickupRadius = Config.PLAYER.pickupRadius,
        freePoints = 0,
        allocatedPoints = StatDefs.MakeAllocatedPoints(),
    }

    -- 玩家运行时生存状态
    GameState.playerHP = 0       -- 当前HP (Init后由 ResetHP 设置)
    GameState.playerDead = false -- 是否死亡
    GameState.playerMana = 0     -- 当前法力 (Init后由 ResetMana 设置)
    GameState.lifeStealAccum = 0 -- 本秒吸血累计
    GameState.lifeStealTimer = 0 -- 吸血每秒重置计时器
    GameState.attachedElementGrade = 0 -- 附着元素强弱等级 (2=强, 1=弱, 0=无)
    -- buff/debuff 状态由 BuffRuntime 统一管理
    GameState.InitBuffState()

    -- 装备栏
    GameState.equipment = {}
    for _, slot in ipairs(Config.EQUIP_SLOTS) do
        GameState.equipment[slot.id] = nil
    end

    -- 材料 (v5.0: D4多材料体系)
    GameState.materials = {
        iron = 0,           -- 锈蚀铁块 (白/绿装分解)
        crystal = 0,        -- 暗纹晶体 (蓝装分解)
        wraith = 0,         -- 怨魂碎片 (紫装分解)
        eternal = 0,        -- 永夜之魂 (橙装分解)
        abyssHeart = 0,     -- 深渊之心 (深渊Boss)
        riftEcho = 0,       -- 裂隙残响 (秘境/世界Boss)
        soulCrystal = 0,    -- 魂晶 (背包扩容等)
        forestDew = 0,      -- 森之露 (魔力之森独占, 升级魔力之源)
    }

    -- 背包扩容次数
    GameState.expandCount = 0

    -- 背包
    GameState.inventory = {}

    -- 自动分解配置 (逐品质独立控制)
    -- 每个品质: 0=关闭, 1=含套装(全分解), 2=留套装(只分解非套装)
    -- [1]白 [2]绿 [3]蓝 [4]紫 [5]橙
    GameState.autoDecompConfig = { 0, 0, 0, 0, 0 }

    -- 装备锻造 (每日重置)
    GameState.forge = {
        usedFree = 0,       -- 今日已用免费次数
        usedPaid = 0,       -- 今日已用付费次数
        lastDate = "",      -- 上次使用日期 (YYYY-MM-DD)
    }

    -- 通用道具背包 { [itemId] = count }
    GameState.bag = {}

    -- 宝石背包 { ["gemTypeId:qualityIdx"] = count }
    GameState.gemBag = {}
    GameState.gemBagExpandCount = 0

    -- 已兑换码记录
    GameState.redeemedCodes = {}

    -- 已领取版本奖励记录
    GameState.claimedVersionRewards = {}

    -- 称号系统 (已解锁的称号ID列表)
    GameState.unlockedTitles = {}
    GameState.equippedTitle = nil

    -- 日常奖励数据
    GameState.dailyRewards = {
        daily     = { currentDay = 0, lastClaimDate = "" },
        -- 日常任务系统
        quests = {
            date = "",              -- 当日日期，换日自动重置
            progress = {},          -- { kills=0, stages=0, bossKills=0, enhance=0, skills=0, goldSpent=0, trialFloors=0 }
            claimed = {},           -- { [questIndex]=true } 已领取的任务
            milestones = {},        -- { ["20"]=true, ["50"]=true } 已领取的里程碑
            activityPoints = 0,     -- 当日活跃点数
        },
    }

    -- 技能 (从 SkillTreeConfig 初始化)
    GameState.skills = {}
    for _, skillCfg in ipairs(SkillTreeConfig.SKILLS) do
        GameState.skills[skillCfg.id] = {
            id = skillCfg.id,
            level = 0,
        }
    end

    -- 波次
    GameState.wave = {
        current = 1,
        killCount = 0,
        totalKills = 0,
    }

    -- 章节/关卡进度
    GameState.stage = {
        chapter = 1,       -- 当前章节
        stage = 1,         -- 当前关卡
        waveIdx = 1,       -- 当前关卡内的波次索引
        cleared = false,   -- 当前关卡是否通关
    }

    -- 商店 (兼容旧代码结构)
    GameState.shop = { items = {}, refreshCount = 0 }

    -- 个人最佳记录
    GameState.records = {
        maxPower = 0,
        maxChapter = 1,
        maxStage = 1,
    }

    -- 无尽试炼
    GameState.endlessTrial = {
        active = false,      -- 当前是否在试炼中
        floor = 0,           -- 当前层数
        maxFloor = 0,        -- 历史最高层数
        clearedFloor = 0,    -- 已领取经验的最高层（通关即更新）

        savedStage = nil,    -- 进入试炼前保存的关卡进度
        totalGold = 0,       -- 本次试炼累计金币
        totalExp = 0,        -- 本次试炼累计经验
        result = nil,        -- 结算结果 { floor, gold, exp, isNewRecord }
    }

    -- 折光矿脉
    GameState.resourceDungeon = {
        attemptsToday = 0,   -- 今日已用次数
        lastDate      = "",  -- 上次重置日期
        totalRuns     = 0,   -- 累计挑战次数
    }

    -- 套装秘境
    GameState.setDungeon = {
        attemptsToday = 0,   -- 今日已用次数
        lastDate      = "",  -- 上次重置日期
        totalRuns     = 0,   -- 累计挑战次数
    }

    -- 深渊模式
    GameState.abyss = {
        active    = false,   -- 当前是否在深渊中
        floor     = 1,       -- 当前层数
        maxFloor  = 0,       -- 历史最高层数
        killCount = 0,       -- 当前层已击杀数
        savedStage = nil,    -- 进入前保存的章节进度
    }

    -- 魔力之森
    GameState.manaForest = {
        attemptsToday   = 0,     -- 今日已用次数
        bonusAttempts   = 0,     -- 广告额外次数（已用）
        lastDate        = "",    -- 上次重置日期
        totalRuns       = 0,     -- 历史总通关次数
        bestEssence     = 0,     -- 单次最高精华记录
        totalEssence    = 0,     -- 历史总精华收集
        firstClearToday = false, -- 今日是否已首通
    }

    -- 噩梦地牢
    GameState.nightmareDungeon = {
        totalRuns      = 0,      -- 累计挑战次数
        maxTierCleared = 0,      -- 最高通关层级
        sigils         = {},     -- 钥石列表 { {tier, positives, negatives, element}, ... }
    }

    -- 魔力之源 (蓝药水)
    GameState.manaPotion = {
        count = 0,              -- 当前瓶数
        level = 0,              -- 升级次数 (0~10)
        autoUse = false,        -- 是否自动喝药
        freeRegenEnd = 0,       -- 无消耗回复到期时间戳 (os.time)
        adWatchCount = 0,       -- 今日已看广告次数
        adWatchDate = "",       -- 上次看广告日期
    }

    -- 初始化HP和法力
    GameState.ResetHP()
    GameState.ResetMana()

    -- 首次更新记录
    GameState.UpdateRecords()

    -- 内存混淆：保护关键数值（必须在所有初始化完成后执行）
    GameState.player = SecureNum.protect(GameState.player,
        { "level", "exp", "gold", "freePoints", "baseAtk", "atkSpeed", "critRate", "critDmg", "pickupRadius" },
        { "atkSpeed", "critRate", "critDmg", "pickupRadius" }  -- 浮点字段
    )
    GameState.records = SecureNum.protect(GameState.records,
        { "maxPower", "maxChapter", "maxStage" }
    )
    GameState.materials = SecureNum.protect(GameState.materials,
        { "iron", "crystal", "wraith", "eternal", "abyssHeart", "riftEcho", "soulCrystal", "forestDew" }
    )
    GameState.endlessTrial = SecureNum.protect(GameState.endlessTrial,
        { "floor", "maxFloor", "clearedFloor", "totalGold", "totalExp" }
    )
    GameState.abyss = SecureNum.protect(GameState.abyss,
        { "floor", "maxFloor", "killCount" }
    )

    print("[GameState] Initialized")
end

-- ============================================================================
-- 子模块注入 (Install 模式: 方法注入到 GameState 表, 外部调用不变)
-- ============================================================================

require("state.StatCalc").Install(GameState)
require("state.BuffRuntime").Install(GameState)
require("state.Combat").Install(GameState)
require("state.Equipment").Install(GameState)
require("state.AttrPoints").Install(GameState)
require("state.SkillPoints").Install(GameState)
require("state.BagSystem").Install(GameState)
require("state.GemSystem").Install(GameState)

-- ============================================================================
-- 离线挂机奖励计算
-- ============================================================================

--- 查找玩家已通关范围内最高的Boss关配置
--- @return table|nil stageCfg, number|nil chapter
local function FindHighestClearedBossStage()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local maxSt = GameState.records and GameState.records.maxStage or 1
    -- 从最高章节往回找最近的已通关 Boss 关
    for ch = maxCh, 1, -1 do
        local stageCount = StageConfig.GetStageCount(ch)
        local endStage = (ch == maxCh) and (maxSt - 1) or stageCount  -- maxStage 是当前关(未必通关), 往前一关才是已通关
        for st = endStage, 1, -1 do
            local cfg = StageConfig.GetStage(ch, st)
            if cfg and cfg.isBoss then
                return cfg, ch
            end
        end
    end
    return nil, nil
end

--- 计算离线挂机奖励
--- @param offlineSeconds number 离线秒数 (已经被 SaveSystem 夹紧到 300~28800)
--- @return table { gold=N, exp=N, equips={item,...}, orangeEquips={item,...}, decomposedMats={[matId]=N,...}, soulCrystal=N }
function GameState.CalculateOfflineReward(offlineSeconds)
    local minutes = offlineSeconds / 60

    -- ── 使用最高通关关卡计算 scaleMul ──
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local maxSt = GameState.records and GameState.records.maxStage or 1
    local scaleMul = StageConfig.GetScaleMul(maxCh, maxSt)

    local OFFLINE_RATE = 0.50  -- 离线收益 = 在线的50%

    -- ── 金币 (与在线掉落对齐: 掉落模板 common 均值 × 缩放 × 模拟击杀速率) ──
    -- 每分钟约击杀30只怪, 30%掉率 → 9次掉落, 均值4.5金 → 40.5金/分钟(基础)
    local goldScale = Config.GetGoldScale(scaleMul)
    local goldPerMin = 40 * goldScale * OFFLINE_RATE
    local gold = math.floor(goldPerMin * minutes)

    -- ── 经验 ──
    local expPerMin = 16000 * scaleMul * OFFLINE_RATE
    local expOld = (maxCh * 5 + maxSt * 2) * 0.5
    local exp = math.floor(math.max(expPerMin, expOld) * minutes)

    -- ── 离线Boss爆装 (只保留橙装, 非橙直接分解) ──
    -- 按最高已通关Boss关算, 幸运值使用登录时的值(离线期间属性不变)
    local orangeEquips = {}
    local decomposedMats = {}
    local soulCrystal = 0

    local bossCfg, bossCh = FindHighestClearedBossStage()
    if bossCfg then
        -- 在线: 每2分钟通一关, Boss关100%掉装备 → 每关1件Boss装
        -- 离线效率50%: 每2分钟 / 0.50 = 每4分钟1次Boss爆装机会
        local bossDropInterval = 2 / OFFLINE_RATE  -- =4分钟一次
        local bossDropCount = math.floor(minutes / bossDropInterval)
        bossDropCount = math.min(bossDropCount, 128)  -- 8h=480min/4=120次, 留余量

        local MAX_ORANGE = 10  -- 橙装最多10件

        for i = 1, bossDropCount do
            local item = GameState.GenerateEquip(GameState.player.level, true, bossCh)
            if item.qualityIdx >= 5 and #orangeEquips < MAX_ORANGE then
                -- 橙装且未达上限 → 保留
                table.insert(orangeEquips, item)
            else
                -- 非橙装, 或橙装已达上限 → 分解为材料+金币
                local mats = Config.DECOMPOSE_MATERIALS[item.qualityIdx]
                if mats then
                    for matId, amt in pairs(mats) do
                        decomposedMats[matId] = (decomposedMats[matId] or 0) + amt
                    end
                end
                local dGold = Config.DECOMPOSE_GOLD[item.qualityIdx] or 0
                if dGold > 0 then
                    gold = gold + dGold
                end
            end
        end

        -- ── 魂晶 (含章节缩放, 与在线逻辑对齐: StageManager.lua:80) ──
        local crystalPerBoss = (Config.SOUL_CRYSTAL.dropPerBoss or 1)
                             + math.floor((bossCh - 1) / 4)
        soulCrystal = bossDropCount * crystalPerBoss
    end

    return {
        gold             = gold,
        exp              = exp,
        equips           = {},  -- 不再生成小怪装备
        orangeEquips     = orangeEquips,
        decomposedMats   = decomposedMats,
        soulCrystal      = soulCrystal,
    }
end

-- ============================================================================
-- 经验与升级
-- ============================================================================

--- 增加经验 (含药水buff+称号加成), 返回是否升级
function GameState.AddExp(amount)
    local p = GameState.player
    local expBonus = GameState.GetPotionBuff("exp")
    -- 称号经验加成
    local ok, TitleSystem = pcall(require, "TitleSystem")
    if ok and TitleSystem and TitleSystem.GetBonus then
        expBonus = expBonus + TitleSystem.GetBonus("exp")
    end
    if expBonus > 0 then
        amount = math.floor(amount * (1 + expBonus))
    end
    p.exp = p.exp + amount
    local leveledUp = false
    while p.exp >= Config.LevelExp(p.level) do
        p.exp = p.exp - Config.LevelExp(p.level)
        p.level = p.level + 1
        p.freePoints = p.freePoints + Config.POINTS_PER_LEVEL
        leveledUp = true
        print("[GameState] Level Up! Lv." .. p.level)
    end
    return leveledUp
end

--- 增加金币
function GameState.AddGold(amount)
    GameState.player.gold = GameState.player.gold + amount
end

--- 消耗金币
function GameState.SpendGold(amount)
    if GameState.player.gold >= amount then
        GameState.player.gold = GameState.player.gold - amount
        -- 日常任务: 花费金币
        local ok, DR = pcall(require, "DailyRewards")
        if ok and DR and DR.TrackProgress then DR.TrackProgress("goldSpent", amount) end
        return true
    end
    return false
end

--- 元素精灵列表
GameState.spirits = {}

-- ============================================================================
-- 魔力之源 (蓝药水)
-- ============================================================================

--- 基础恢复比例 30%，每级 +3%，最高 10 级 = 60%
function GameState.GetManaPotionPct()
    local lv = GameState.manaPotion.level or 0
    return 0.30 + lv * 0.03
end

--- 是否处于无消耗回复状态
function GameState.IsManaPotionFreeRegen()
    return (GameState.manaPotion.freeRegenEnd or 0) > os.time()
end

--- 获取无消耗剩余秒数
function GameState.GetFreeRegenRemain()
    local remain = (GameState.manaPotion.freeRegenEnd or 0) - os.time()
    return remain > 0 and remain or 0
end

local MANA_POTION_CD = 10  -- 喝药冷却时间(秒)

--- 喝药是否在冷却中
function GameState.IsManaPotionOnCD()
    return (GameState.manaPotion.cdEnd or 0) > time:GetElapsedTime()
end

--- 获取喝药剩余冷却秒数
function GameState.GetManaPotionCDRemain()
    local remain = (GameState.manaPotion.cdEnd or 0) - time:GetElapsedTime()
    return remain > 0 and remain or 0
end

--- 使用一瓶魔力之源 (free=true 时不消耗瓶数)
--- @param free boolean|nil 是否免费
--- @return boolean 是否成功使用
function GameState.UseManaPotionOnce(free)
    if GameState.IsManaPotionOnCD() then return false end
    local maxMana = GameState.GetMaxMana()
    if GameState.playerMana >= maxMana then return false end
    if not free then
        if (GameState.manaPotion.count or 0) <= 0 then return false end
        GameState.manaPotion.count = GameState.manaPotion.count - 1
    end
    local heal = maxMana * GameState.GetManaPotionPct()
    GameState.playerMana = math.min(maxMana, GameState.playerMana + heal)
    GameState.manaPotion.cdEnd = time:GetElapsedTime() + MANA_POTION_CD
    local FloatTip = require("ui.FloatTip")
    FloatTip.Show("魔力之源 +" .. math.floor(heal) .. " MP", { 100, 180, 255, 255 })
    return true
end

local MANA_POTION_AD_DAILY_MAX = 24

--- 今日剩余广告次数
function GameState.GetManaPotionAdRemain()
    local today = os.date("%Y-%m-%d", os.time())
    if (GameState.manaPotion.adWatchDate or "") ~= today then
        return MANA_POTION_AD_DAILY_MAX
    end
    return math.max(0, MANA_POTION_AD_DAILY_MAX - (GameState.manaPotion.adWatchCount or 0))
end

--- 获取魔力之源升级所需森之露数量 (nil = 已满级)
---@return number|nil
function GameState.GetManaPotionUpgradeCost()
    local lv = GameState.manaPotion.level or 0
    local costs = Config.MANA_POTION_UPGRADE_COSTS
    if lv >= #costs then return nil end  -- 已满级
    return costs[lv + 1]
end

--- 使用森之露升级魔力之源
---@return boolean success
---@return string|nil errMsg
function GameState.UpgradeManaPotionWithDew()
    local cost = GameState.GetManaPotionUpgradeCost()
    if not cost then return false, "已达最高等级" end
    local have = GameState.materials.forestDew or 0
    if have < cost then return false, "森之露不足" end
    GameState.materials.forestDew = have - cost
    GameState.manaPotion.level = (GameState.manaPotion.level or 0) + 1
    return true, nil
end

--- 记录一次广告观看，增加 1 小时免费回复
function GameState.RecordManaPotionAd()
    local today = os.date("%Y-%m-%d", os.time())
    if (GameState.manaPotion.adWatchDate or "") ~= today then
        GameState.manaPotion.adWatchCount = 0
        GameState.manaPotion.adWatchDate = today
    end
    GameState.manaPotion.adWatchCount = (GameState.manaPotion.adWatchCount or 0) + 1
    -- 叠加 1 小时
    local now = os.time()
    local curEnd = GameState.manaPotion.freeRegenEnd or 0
    if curEnd < now then curEnd = now end
    GameState.manaPotion.freeRegenEnd = curEnd + 3600
end

-- ============================================================================
-- 个人最佳记录更新
-- ============================================================================

function GameState.UpdateRecords()
    if not GameState.records then return end
    local power = GameState.GetPower()
    if power > GameState.records.maxPower then
        GameState.records.maxPower = power
    end
    local ch = GameState.stage.chapter
    local st = GameState.stage.stage
    if ch > GameState.records.maxChapter
        or (ch == GameState.records.maxChapter and st > GameState.records.maxStage) then
        GameState.records.maxChapter = ch
        GameState.records.maxStage = st
    end
end

-- ============================================================================
-- 存档校验: 加载后检测点数是否超额, 超额则重置
-- ============================================================================

--- 校验结果 (供 UI 层读取并弹 Toast)
GameState.pointsValidationMsg = nil
--- 存档迁移结果消息 (供 UI 层读取并弹 Toast)
GameState.migrationMsg = nil

--- 校验属性点和技能点是否合法, 超额则全部重置
--- @return boolean 是否进行了修正
function GameState.ValidatePoints()
    local p = GameState.player
    local msgs = {}

    -- ── 属性点校验 ──
    local earnedAttr = (p.level - 1) * Config.POINTS_PER_LEVEL
    local allocatedAttr = 0
    for _, pts in pairs(p.allocatedPoints) do
        allocatedAttr = allocatedAttr + pts
    end
    local totalAttr = allocatedAttr + p.freePoints

    if totalAttr > earnedAttr then
        print("[GameState] Attribute points exceed: used=" .. allocatedAttr
            .. " free=" .. p.freePoints .. " earned=" .. earnedAttr)
        for stat, _ in pairs(p.allocatedPoints) do
            p.allocatedPoints[stat] = 0
        end
        p.freePoints = earnedAttr
        GameState.ResetHP()
        table.insert(msgs, "属性点")
    elseif totalAttr < earnedAttr then
        local missing = earnedAttr - totalAttr
        print("[GameState] Attribute points missing: have=" .. totalAttr
            .. " earned=" .. earnedAttr .. " recovering=" .. missing)
        p.freePoints = p.freePoints + missing
        table.insert(msgs, "属性点(已补回" .. missing .. "点)")
    end

    -- ── 技能点校验 ──
    local earnedSkill = GameState.GetTotalSkillPts()
    local spentSkill = GameState.GetSpentSkillPts()

    if spentSkill > earnedSkill then
        print("[GameState] Skill points exceed: spent=" .. spentSkill .. " earned=" .. earnedSkill)
        for _, skill in pairs(GameState.skills) do
            skill.level = 0
        end
        table.insert(msgs, "技能点")
    end

    if #msgs > 0 then
        local detail = table.concat(msgs, "和")
        GameState.pointsValidationMsg = "检测到" .. detail .. "数据异常，已自动重置，请重新分配"
        print("[GameState] Points validation corrected: " .. detail)
        return true
    end

    GameState.pointsValidationMsg = nil
    return false
end

-- ============================================================================
-- 无尽试炼
-- ============================================================================

--- 进入无尽试炼模式
function GameState.EnterTrial()
    local et = GameState.endlessTrial
    et.savedStage = {
        chapter = GameState.stage.chapter,
        stage = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }
    et.active = true
    -- 日常任务: 挑战试炼
    local ok, DR = pcall(require, "DailyRewards")
    if ok and DR and DR.TrackProgress then DR.TrackProgress("trialAttempts", 1) end
    -- 从已通关层的下一层开始（而非 maxFloor，因为 maxFloor 可能是死亡到达但未通关的层）
    et.floor = math.max(1, (et.clearedFloor or 0) + 1)
    et.totalGold = 0
    et.totalExp = 0
    et.result = nil
    print("[GameState] Entered Endless Trial at floor " .. et.floor)
end

--- 退出无尽试炼模式, 恢复关卡进度
function GameState.ExitTrial()
    local et = GameState.endlessTrial
    if et.savedStage then
        GameState.stage.chapter = et.savedStage.chapter
        GameState.stage.stage = et.savedStage.stage
        GameState.stage.waveIdx = et.savedStage.waveIdx
    end
    et.active = false
    et.savedStage = nil
    print("[GameState] Exited Endless Trial, restored stage")
end

return GameState
