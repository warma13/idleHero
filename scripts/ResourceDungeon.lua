-- ============================================================================
-- ResourceDungeon.lua - 折光矿脉 (资源关)
--
-- 设计:
--   1. 单入口, 60秒限时, 每日3次
--   2. 按玩家最高通关章节(maxChapter)缩放怪物强度和奖励
--   3. 击杀获取宝石(碎裂/普通/完美), 击杀精英怪概率获得散光棱镜
--   4. 怪物强度 = 章节C末关 scaleMul × 0.9
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local MonsterTemplates = require("MonsterTemplates")
local SaveSystem       = require("SaveSystem")
local RDConfig         = require("ResourceDungeonConfig")

local ResourceDungeon = {}

-- ============================================================================
-- 配置常量 (从 ResourceDungeonConfig 读取)
-- ============================================================================

local MAX_DAILY_ATTEMPTS = RDConfig.MAX_DAILY_ATTEMPTS
local FIGHT_DURATION     = RDConfig.FIGHT_DURATION
local MONSTER_SCALE      = RDConfig.MONSTER_SCALE
local ELITE_HP_MUL       = RDConfig.ELITE_HP_MUL

ResourceDungeon.FIGHT_DURATION = FIGHT_DURATION

-- ============================================================================
-- 运行时状态 (不存档)
-- ============================================================================

ResourceDungeon.active       = false
ResourceDungeon.killCount    = 0
ResourceDungeon.eliteKilled  = false
ResourceDungeon.fightResult  = nil   -- 结算数据
ResourceDungeon._combatDrops = {}    -- 第4次+运行时掉落记录

-- 进入前保存的关卡状态
ResourceDungeon._savedStage  = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 随机选取宝石类型ID
---@return string typeId
local function randomGemType()
    local types = Config.GEM_TYPES
    local idx = math.random(1, #types)
    return types[idx].id
end

local function getTodayStr()
    return os.date("%Y-%m-%d", os.time())
end

-- ============================================================================
-- 存档状态管理
-- ============================================================================

--- 确保存档字段初始化 + 每日重置
function ResourceDungeon.EnsureState()
    if not GameState.resourceDungeon then
        GameState.resourceDungeon = {
            attemptsToday = 0,
            lastDate      = "",
            totalRuns     = 0,
        }
    end
    local today = getTodayStr()
    if GameState.resourceDungeon.lastDate ~= today then
        GameState.resourceDungeon.attemptsToday = 0
        GameState.resourceDungeon.lastDate = today
        print("[ResourceDungeon] Daily reset")
    end
end

--- 是否可以进入 (始终可进入, 前3次有批量奖励, 第4次起概率掉落)
---@return boolean
function ResourceDungeon.CanEnter()
    ResourceDungeon.EnsureState()
    return true
end

--- 是否为额外探索 (第4次及以后, 仅概率掉落)
---@return boolean
function ResourceDungeon.IsBonusRun()
    ResourceDungeon.EnsureState()
    return GameState.resourceDungeon.attemptsToday >= MAX_DAILY_ATTEMPTS
end

--- 是否已击杀所有怪物
---@return boolean
function ResourceDungeon.IsAllKilled()
    return ResourceDungeon.killCount >= #RDConfig.SPAWN_SEQUENCE
end

--- 获取剩余次数
---@return number
function ResourceDungeon.GetAttemptsLeft()
    ResourceDungeon.EnsureState()
    return math.max(0, MAX_DAILY_ATTEMPTS - GameState.resourceDungeon.attemptsToday)
end

-- ============================================================================
-- 战斗入口/退出
-- ============================================================================

--- 进入折光矿脉
---@return boolean success
function ResourceDungeon.EnterFight()
    ResourceDungeon.EnsureState()

    -- 保存当前关卡状态
    ResourceDungeon._savedStage = {
        chapter = GameState.stage.chapter,
        stage   = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }

    ResourceDungeon.active       = true
    ResourceDungeon.killCount    = 0
    ResourceDungeon.eliteKilled  = false
    ResourceDungeon.fightResult  = nil
    ResourceDungeon._combatDrops = {}

    GameState.resourceDungeon.attemptsToday = GameState.resourceDungeon.attemptsToday + 1
    GameState.resourceDungeon.totalRuns     = GameState.resourceDungeon.totalRuns + 1

    local isBonusRun = GameState.resourceDungeon.attemptsToday > MAX_DAILY_ATTEMPTS
    print("[ResourceDungeon] Fight started! Attempt "
        .. GameState.resourceDungeon.attemptsToday
        .. (isBonusRun and " (bonus run)" or ("/" .. MAX_DAILY_ATTEMPTS)))
    return true
end

--- 击杀回调
---@param isElite boolean
function ResourceDungeon.OnKill(isElite)
    if not ResourceDungeon.active then return end
    ResourceDungeon.killCount = ResourceDungeon.killCount + 1
    if isElite then
        ResourceDungeon.eliteKilled = true
    end

    -- 第4次+: 每次击杀概率掉落碎裂宝石 (概率随章节√缩放)
    if ResourceDungeon.IsBonusRun() then
        local ch = GameState.records.maxChapter or 1
        local chScale = math.sqrt(ch)
        local dropChance = (isElite and 0.10 or 0.01) * chScale
        if math.random() < dropChance then
            local gem = { typeId = randomGemType(), qualityIdx = 1, qualityName = "碎裂" }
            GameState.AddGem(gem.typeId, gem.qualityIdx, 1)
            table.insert(ResourceDungeon._combatDrops, gem)
            print("[ResourceDungeon] Bonus drop! " .. gem.typeId .. " (碎裂)")
        end
    end
end

--- 结束战斗, 计算并发放奖励
function ResourceDungeon.EndFight()
    if not ResourceDungeon.active then return end

    ResourceDungeon.active = false

    local C = GameState.records.maxChapter or 1
    local K = ResourceDungeon.killCount
    local isBonusRun = ResourceDungeon.IsBonusRun()

    if isBonusRun then
        -- 第4次+: 奖励已在 OnKill 中实时发放, 只构造结算数据
        ResourceDungeon.fightResult = {
            killCount    = K,
            eliteKilled  = ResourceDungeon.eliteKilled,
            gems         = ResourceDungeon._combatDrops,
            prismCount   = 0,
            maxChapter   = C,
            isBonusRun   = true,
        }
        print("[ResourceDungeon] Bonus fight ended! Kills=" .. K
            .. " Drops=" .. #ResourceDungeon._combatDrops)
    else
        -- 前3次: 批量计算奖励
        local rewards = ResourceDungeon.CalcRewards(C, K, ResourceDungeon.eliteKilled)

        -- 发放宝石
        for _, gem in ipairs(rewards.gems) do
            GameState.AddGem(gem.typeId, gem.qualityIdx, 1)
        end

        -- 发放棱镜
        if rewards.prismCount > 0 then
            GameState.AddBagItem("prism", rewards.prismCount)
        end

        -- 构造结算数据
        ResourceDungeon.fightResult = {
            killCount    = K,
            eliteKilled  = ResourceDungeon.eliteKilled,
            gems         = rewards.gems,
            prismCount   = rewards.prismCount,
            maxChapter   = C,
            isBonusRun   = false,
        }
        print("[ResourceDungeon] Fight ended! Kills=" .. K
            .. " Gems=" .. #rewards.gems
            .. " Prisms=" .. rewards.prismCount)
    end

    SaveSystem.SaveNow()
end

--- 退出矿脉模式, 恢复关卡
function ResourceDungeon.ExitToMain()
    ResourceDungeon.active      = false
    ResourceDungeon.fightResult = nil

    -- 恢复关卡状态
    if ResourceDungeon._savedStage then
        GameState.stage.chapter = ResourceDungeon._savedStage.chapter
        GameState.stage.stage   = ResourceDungeon._savedStage.stage
        GameState.stage.waveIdx = ResourceDungeon._savedStage.waveIdx
        ResourceDungeon._savedStage = nil
    end
end

-- ============================================================================
-- 奖励计算 (纯函数)
-- ============================================================================

--- 计算矿脉奖励
---@param C number 最高通关章节
---@param K number 击杀数
---@param eliteKilled boolean 是否击杀了精英
---@return table { gems = { {typeId, qualityIdx, qualityName} ... }, prismCount = number }
function ResourceDungeon.CalcRewards(C, K, eliteKilled)
    local gems = {}

    -- 碎裂宝石 (qualityIdx = 1)
    local chippedCount = math.floor(C / 3) + 1 + math.min(3, math.floor(K / 20))
    for _ = 1, chippedCount do
        table.insert(gems, { typeId = randomGemType(), qualityIdx = 1, qualityName = "碎裂" })
    end

    -- 普通宝石 (qualityIdx = 2)
    local normalCount = math.max(0, math.floor((C - 3) / 4))
    for _ = 1, normalCount do
        table.insert(gems, { typeId = randomGemType(), qualityIdx = 2, qualityName = "普通" })
    end

    -- 完美宝石 (qualityIdx = 3, 概率掉落)
    local flawlessChance = math.max(0, (C - 8) * 4) / 100
    if math.random() < flawlessChance then
        table.insert(gems, { typeId = randomGemType(), qualityIdx = 3, qualityName = "完美" })
    end

    -- 散光棱镜 (需击杀精英)
    local prismCount = 0
    if eliteKilled then
        local prismChance = math.min(40, 5 + C * 2.5) / 100
        if math.random() < prismChance then
            prismCount = 1
        end
    end

    return { gems = gems, prismCount = prismCount }
end

-- ============================================================================
-- 怪物生成队列
-- ============================================================================

--- 构建矿脉怪物生成队列
---@return table queue Spawner 兼容的队列
function ResourceDungeon.BuildMineQueue()
    local C = GameState.records.maxChapter or 1
    local scaleMul = StageConfig.CalcScaleMul(C, 10) * MONSTER_SCALE

    -- 章节主题(用于抗性计算)
    local chapter = ((C - 1) % 12) + 1
    local theme = MonsterTemplates.ChapterThemes[chapter]
    local themeResistId = RDConfig.GetThemeResistId(theme and theme.element or "fire")

    local queue = {}
    local seq = RDConfig.SPAWN_SEQUENCE

    for i = 1, #seq do
        local key = seq[i]

        if key == "ELITE" then
            -- 精英怪
            local elite = RDConfig.ELITE
            local resistId = elite.resistRule == "theme" and themeResistId or elite.resistRule
            local template = MonsterTemplates.Assemble(elite.behaviorId, resistId, chapter, {
                name  = elite.name,
                image = elite.image,
                tags  = elite.tags(C),
            })
            template.hp = template.hp * ELITE_HP_MUL
            template.isElite = true
            template.color = elite.color

            table.insert(queue, {
                templateId  = "elite_mine",
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        else
            -- 普通怪
            local def = RDConfig.MONSTERS[key]
            local resistId = def.resistRule == "theme" and themeResistId or def.resistRule
            local template = MonsterTemplates.Assemble(def.behaviorId, resistId, chapter, {
                name  = def.name,
                image = def.image,
                tags  = def.tags(C),
            })

            table.insert(queue, {
                templateId  = def.behaviorId .. "_mine_" .. i,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        end
    end

    return queue
end

--- 获取最大每日次数(供UI显示)
---@return number
function ResourceDungeon.GetMaxAttempts()
    return MAX_DAILY_ATTEMPTS
end


-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode  = require("GameMode")
    local adapter   = {}

    -- ── 生命周期 ──
    adapter.background = "Textures/battle_bg_mine.png"

    function adapter:OnEnter()
        return ResourceDungeon.EnterFight()  -- always true
    end

    function adapter:OnExit()
        ResourceDungeon.ExitToMain()
    end

    -- ── 战斗 ──

    function adapter:BuildSpawnQueue()
        return ResourceDungeon.BuildMineQueue()
    end

    function adapter:GetBattleConfig()
        return {
            isBossWave            = true,
            bossTimerMax          = FIGHT_DURATION,
            startTimerImmediately = true,
        }
    end

    function adapter:OnEnemyKilled(bs, enemy)
        local Particles   = require("battle.Particles")
        local CombatUtils = require("battle.CombatUtils")
        ResourceDungeon.OnKill(enemy.isElite)
        Particles.SpawnExplosion(bs.particles, enemy.x, enemy.y, enemy.color)
        CombatUtils.PlaySfx("enemyDie", 0.3)
        if ResourceDungeon.IsAllKilled() and not bs.resourceDungeonEnded then
            ResourceDungeon.EndFight()
            bs.resourceDungeonEnded = true
            print("[ResourceDungeon] All enemies killed, fight ended early.")
        end
        return true
    end

    function adapter:OnDeath(bs)
        ResourceDungeon.EndFight()
        bs.resourceDungeonEnded = true
        print("[ResourceDungeon] Player died, fight ended. Kills="
            .. ResourceDungeon.fightResult.killCount)
        return true
    end

    function adapter:OnTimeout(bs)
        ResourceDungeon.EndFight()
        bs.resourceDungeonEnded = true
        print("[BattleSystem] ResourceDungeon time up! Kills="
            .. (ResourceDungeon.fightResult and ResourceDungeon.fightResult.killCount or 0))
        return true
    end

    function adapter:CheckWaveComplete(_bs)
        return true  -- 矿脉不检测波次完成 (由计时器控制)
    end

    function adapter:SkipNormalExpDrop()
        return true
    end

    function adapter:IsTimerMode()
        return true
    end

    function adapter:GetDisplayName()
        return "折光矿脉"
    end

    GameMode.Register("resourceDungeon", adapter)
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "resourceDungeon",
    keys  = { "resourceDungeon" },
    group = "misc",
    serialize = function(GS)
        return {
            resourceDungeon = {
                attemptsToday = GS.resourceDungeon.attemptsToday,
                lastDate      = GS.resourceDungeon.lastDate,
                totalRuns     = GS.resourceDungeon.totalRuns,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.resourceDungeon and type(data.resourceDungeon) == "table" then
            GS.resourceDungeon.attemptsToday = data.resourceDungeon.attemptsToday or 0
            GS.resourceDungeon.lastDate      = data.resourceDungeon.lastDate or ""
            GS.resourceDungeon.totalRuns     = data.resourceDungeon.totalRuns or 0
        end
    end,
})

return ResourceDungeon
