-- ============================================================================
-- SetDungeon.lua - 套装秘境
--
-- 设计:
--   1. 通关第5章解锁, 每日3次, 120秒限时
--   2. 定向选择目标套装, 通关掉落该套装随机部位1件
--   3. 普通/困难两档难度, 困难需通关第9章
--   4. 失败不扣次数, 可重试
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local MonsterTemplates = require("MonsterTemplates")
local SaveSystem       = require("SaveSystem")
local SDConfig         = require("SetDungeonConfig")

local SetDungeon = {}

-- ============================================================================
-- 配置快捷引用
-- ============================================================================

local SD = Config.SET_DUNGEON

SetDungeon.FIGHT_DURATION = SD.FIGHT_DURATION

-- ============================================================================
-- 运行时状态 (不存档)
-- ============================================================================

SetDungeon.active       = false
SetDungeon.killCount    = 0
SetDungeon.totalSpawns  = 0
SetDungeon.fightResult  = nil
SetDungeon.targetSetId  = nil   -- 当前选择的目标套装ID
SetDungeon.isHardMode   = false -- 是否困难模式
SetDungeon.fightWon     = false -- 是否通关 (全灭 or 超时前清完)

-- 进入前保存的关卡状态
SetDungeon._savedStage  = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

local function getTodayStr()
    return os.date("%Y-%m-%d", os.time())
end

-- ============================================================================
-- 存档状态管理
-- ============================================================================

function SetDungeon.EnsureState()
    if not GameState.setDungeon then
        GameState.setDungeon = {
            attemptsToday = 0,
            lastDate      = "",
            totalRuns     = 0,
        }
    end
    local today = getTodayStr()
    if GameState.setDungeon.lastDate ~= today then
        GameState.setDungeon.attemptsToday = 0
        GameState.setDungeon.lastDate = today
        print("[SetDungeon] Daily reset")
    end
end

--- 是否已解锁套装秘境
---@return boolean
function SetDungeon.IsUnlocked()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    return maxCh >= SD.UNLOCK_CHAPTER
end

--- 是否可以进入 (有次数)
---@return boolean
function SetDungeon.CanEnter()
    SetDungeon.EnsureState()
    return GameState.setDungeon.attemptsToday < SD.MAX_DAILY_ATTEMPTS
end

--- 获取剩余次数
---@return number
function SetDungeon.GetAttemptsLeft()
    SetDungeon.EnsureState()
    return math.max(0, SD.MAX_DAILY_ATTEMPTS - GameState.setDungeon.attemptsToday)
end

--- 是否解锁困难模式
---@return boolean
function SetDungeon.IsHardUnlocked()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    return maxCh >= SD.HARD_UNLOCK_CHAPTER
end

--- 获取当前可选套装列表
---@return table[] { setId, setCfg }
function SetDungeon.GetAvailableSets()
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local result = {}
    for _, batch in ipairs(SD.UNLOCK_BATCHES) do
        if maxCh >= batch.minChapter then
            for _, setId in ipairs(batch.setIds) do
                local setCfg = Config.EQUIP_SET_MAP[setId]
                if setCfg and not setCfg.retired then
                    result[#result + 1] = { setId = setId, setCfg = setCfg }
                end
            end
        end
    end
    return result
end

-- ============================================================================
-- 战斗入口/退出
-- ============================================================================

--- 进入套装秘境
---@param targetSetId string 目标套装ID
---@param hardMode boolean 是否困难模式
---@return boolean success
function SetDungeon.EnterFight(targetSetId, hardMode)
    SetDungeon.EnsureState()

    if not SetDungeon.CanEnter() then
        print("[SetDungeon] No attempts left!")
        return false
    end

    -- 验证套装ID合法
    local setCfg = Config.EQUIP_SET_MAP[targetSetId]
    if not setCfg then
        print("[SetDungeon] Invalid set ID: " .. tostring(targetSetId))
        return false
    end

    -- 保存当前关卡状态
    SetDungeon._savedStage = {
        chapter = GameState.stage.chapter,
        stage   = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }

    SetDungeon.active       = true
    SetDungeon.killCount    = 0
    SetDungeon.fightResult  = nil
    SetDungeon.targetSetId  = targetSetId
    SetDungeon.isHardMode   = hardMode or false
    SetDungeon.fightWon     = false

    -- 计算出场总数
    SetDungeon.totalSpawns = SD.SPAWN_COUNT + SD.ELITE_COUNT

    -- 扣次数 (失败会退还)
    GameState.setDungeon.attemptsToday = GameState.setDungeon.attemptsToday + 1
    GameState.setDungeon.totalRuns     = GameState.setDungeon.totalRuns + 1

    print("[SetDungeon] Fight started! Target=" .. targetSetId
        .. " Hard=" .. tostring(SetDungeon.isHardMode)
        .. " Attempt=" .. GameState.setDungeon.attemptsToday
        .. "/" .. SD.MAX_DAILY_ATTEMPTS)
    return true
end

--- 击杀回调
---@param isElite boolean
function SetDungeon.OnKill(isElite)
    if not SetDungeon.active then return end
    SetDungeon.killCount = SetDungeon.killCount + 1
    if isElite then
        print("[SetDungeon] Elite killed!")
    end
end

--- 是否全部击杀
---@return boolean
function SetDungeon.IsAllKilled()
    return SetDungeon.killCount >= SetDungeon.totalSpawns
end

--- 结束战斗 (通关或超时)
---@param won boolean 是否通关
function SetDungeon.EndFight(won)
    if not SetDungeon.active then return end

    SetDungeon.active   = false
    SetDungeon.fightWon = won

    if won then
        -- 通关: 生成套装装备奖励
        local reward = SetDungeon.GenerateReward()

        -- 材料掉落: 普通→永夜之魂, 困难→额外裂隙残响
        local matDrop = {}
        if SetDungeon.isHardMode then
            matDrop.eternal  = 2
            matDrop.riftEcho = 1
        else
            matDrop.eternal = 1
        end
        GameState.AddMaterials(matDrop)

        SetDungeon.fightResult = {
            won       = true,
            killCount = SetDungeon.killCount,
            targetSet = SetDungeon.targetSetId,
            hardMode  = SetDungeon.isHardMode,
            reward    = reward,
            materials = matDrop,
        }
        local matDesc = ""
        for k, v in pairs(matDrop) do matDesc = matDesc .. k .. "=" .. v .. " " end
        print("[SetDungeon] Victory! Reward: " .. reward.name
            .. " (" .. reward.qualityName .. ") Materials: " .. matDesc)
    else
        -- 失败: 退还次数
        GameState.setDungeon.attemptsToday = math.max(0,
            GameState.setDungeon.attemptsToday - 1)
        SetDungeon.fightResult = {
            won       = false,
            killCount = SetDungeon.killCount,
            targetSet = SetDungeon.targetSetId,
            hardMode  = SetDungeon.isHardMode,
            reward    = nil,
        }
        print("[SetDungeon] Defeated. Attempt refunded. Kills=" .. SetDungeon.killCount)
    end

    SaveSystem.SaveNow()
end

--- 退出秘境, 恢复关卡
function SetDungeon.ExitToMain()
    SetDungeon.active      = false
    SetDungeon.fightResult = nil
    SetDungeon.targetSetId = nil

    if SetDungeon._savedStage then
        GameState.stage.chapter = SetDungeon._savedStage.chapter
        GameState.stage.stage   = SetDungeon._savedStage.stage
        GameState.stage.waveIdx = SetDungeon._savedStage.waveIdx
        SetDungeon._savedStage = nil
    end
end

-- ============================================================================
-- 奖励生成
-- ============================================================================

--- 生成套装装备奖励
---@return table item 装备数据
function SetDungeon.GenerateReward()
    local maxCh = GameState.records and GameState.records.maxChapter or 1

    -- 品质roll
    local weights = SetDungeon.isHardMode
        and SD.QUALITY_WEIGHTS_HARD
        or  SD.QUALITY_WEIGHTS_NORMAL
    local roll = math.random()
    local acc = 0
    local qualityIdx = 3  -- 默认蓝品 (index 3)
    for i, w in ipairs(weights) do
        acc = acc + w
        if roll <= acc then
            qualityIdx = i + 2  -- weights[1]=蓝(3), [2]=紫(4), [3]=橙(5)
            break
        end
    end

    -- 随机部位
    local slotIdx = math.random(1, #Config.EQUIP_SLOTS)
    local slotId = Config.EQUIP_SLOTS[slotIdx].id

    -- 使用 CreateEquip + forceSetId 生成
    local item = GameState.CreateEquip(qualityIdx, maxCh, slotId, SetDungeon.targetSetId)

    -- 加入背包
    local _, decompInfo = GameState.AddToInventory(item)
    if decompInfo then
        local FloatTip = require("ui.FloatTip")
        FloatTip.Decompose(decompInfo)
    end

    return item
end

-- ============================================================================
-- 怪物生成队列
-- ============================================================================

--- 构建套装秘境怪物队列
---@return table queue Spawner 兼容队列
function SetDungeon.BuildQueue()
    local C = GameState.records and GameState.records.maxChapter or 1
    local scaleFactor = SetDungeon.isHardMode and SD.HARD_MONSTER_SCALE or SD.MONSTER_SCALE
    local scaleMul = StageConfig.CalcScaleMul(C, 10) * scaleFactor

    -- 章节主题
    local chapter = ((C - 1) % 12) + 1
    local theme = MonsterTemplates.ChapterThemes[chapter]
    local themeResistId = SDConfig.GetThemeResistId(theme and theme.element or "fire")

    local seq = SDConfig.BuildSpawnSequence(SD.SPAWN_COUNT, SD.ELITE_COUNT)
    local queue = {}

    for i = 1, #seq do
        local key = seq[i]

        if key == "ELITE" then
            local elite = SDConfig.ELITE
            local resistId = elite.resistRule == "theme" and themeResistId or elite.resistRule
            local template = MonsterTemplates.Assemble(elite.behaviorId, resistId, chapter, {
                name  = elite.name,
                image = elite.image,
                tags  = elite.tags(C),
            })
            template.hp = template.hp * SD.ELITE_HP_MUL
            template.isElite = true
            template.color = elite.color

            queue[#queue + 1] = {
                templateId  = "elite_setdungeon_" .. i,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            }
        else
            local def = SDConfig.MONSTERS[key]
            if def then
                local resistId = def.resistRule == "theme" and themeResistId or def.resistRule
                local template = MonsterTemplates.Assemble(def.behaviorId, resistId, chapter, {
                    name  = def.name,
                    image = def.image,
                    tags  = def.tags(C),
                })

                queue[#queue + 1] = {
                    templateId  = def.behaviorId .. "_setdungeon_" .. i,
                    template    = template,
                    scaleMul    = scaleMul,
                    expScaleMul = 0,
                }
            end
        end
    end

    return queue
end

--- 获取最大每日次数
---@return number
function SetDungeon.GetMaxAttempts()
    return SD.MAX_DAILY_ATTEMPTS
end

-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode = require("GameMode")
    local adapter  = {}

    adapter.background = "Textures/battle_bg_mine.png"

    function adapter:OnEnter()
        return SetDungeon.active  -- EnterFight 已在面板中调用
    end

    function adapter:OnExit()
        SetDungeon.ExitToMain()
    end

    function adapter:BuildSpawnQueue()
        return SetDungeon.BuildQueue()
    end

    function adapter:GetBattleConfig()
        return {
            isBossWave            = true,
            bossTimerMax          = SetDungeon.FIGHT_DURATION,
            startTimerImmediately = true,
        }
    end

    function adapter:OnEnemyKilled(bs, enemy)
        local Particles   = require("battle.Particles")
        local CombatUtils = require("battle.CombatUtils")
        SetDungeon.OnKill(enemy.isElite)
        Particles.SpawnExplosion(bs.particles, enemy.x, enemy.y, enemy.color)
        CombatUtils.PlaySfx("enemyDie", 0.3)
        if SetDungeon.IsAllKilled() and not bs.setDungeonEnded then
            SetDungeon.EndFight(true)
            bs.setDungeonEnded = true
            print("[SetDungeon] All enemies killed, victory!")
        end
        return true
    end

    function adapter:OnDeath(bs)
        if not bs.setDungeonEnded then
            SetDungeon.EndFight(false)
            bs.setDungeonEnded = true
        end
        return true
    end

    function adapter:OnTimeout(bs)
        if not bs.setDungeonEnded then
            -- 超时视为失败
            SetDungeon.EndFight(false)
            bs.setDungeonEnded = true
        end
        return true
    end

    function adapter:CheckWaveComplete(_bs)
        return true  -- 不检测波次完成 (计时器控制)
    end

    function adapter:SkipNormalExpDrop()
        return true
    end

    function adapter:IsTimerMode()
        return true
    end

    function adapter:GetDisplayName()
        return "套装秘境"
    end

    GameMode.Register("setDungeon", adapter)
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "setDungeon",
    keys  = { "setDungeon" },
    group = "misc",
    serialize = function(GS)
        return {
            setDungeon = {
                attemptsToday = GS.setDungeon.attemptsToday,
                lastDate      = GS.setDungeon.lastDate,
                totalRuns     = GS.setDungeon.totalRuns,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.setDungeon and type(data.setDungeon) == "table" then
            GS.setDungeon.attemptsToday = data.setDungeon.attemptsToday or 0
            GS.setDungeon.lastDate      = data.setDungeon.lastDate or ""
            GS.setDungeon.totalRuns     = data.setDungeon.totalRuns or 0
        end
    end,
})

return SetDungeon
