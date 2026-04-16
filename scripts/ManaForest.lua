-- ============================================================================
-- ManaForest.lua - 魔力之森 (限时挑战副本)
--
-- 设计:
--   1. 90秒限时, 每日3次 + 广告额外2次
--   2. 持续涌入模式: 场上保持怪物上限, 击杀后立即补充
--   3. 击杀掉落魔力精华 → 4阶增益循环
--   4. 每30秒触发魔力涌潮事件(水晶拾取)
--   5. 精华 → 魔力药水 + 森之露(魔力之源升级独占材料)
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local MonsterTemplates = require("MonsterTemplates")
local SaveSystem       = require("SaveSystem")

local ManaForest = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

local MF = Config.MANA_FOREST

ManaForest.FIGHT_DURATION = MF.FIGHT_DURATION

-- 元素→抗性ID映射 (与 ResourceDungeonConfig 一致)
local ELEMENT_TO_RESIST = {
    fire     = "fire_res",
    ice      = "ice_res",
    poison   = "poison_res",
    water    = "water_res",
    arcane   = "arcane_res",
    physical = "physical_res",
}

local function getThemeResistId(element)
    return ELEMENT_TO_RESIST[element] or "balanced"
end

-- ============================================================================
-- 运行时状态 (不存档)
-- ============================================================================

ManaForest.active      = false
ManaForest.fightResult = nil

-- 战斗临时状态
local fight = {
    essence       = 0,
    difficulty    = "normal",
    spawnCount    = 0,
    killCount     = 0,
    surgeTimer    = 0,
    surgeCount    = 0,
    buffTier      = 0,
    crystalsOnField = {},
    totalMonsters = 0,
    elitePositions = {},  -- 精英出场位序
    maxOnField    = 0,
}

-- 进入前保存的关卡状态
ManaForest._savedStage = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

local function getTodayStr()
    return os.date("%Y-%m-%d", os.time())
end

--- 计算精英出场位序
---@param total number 总怪物数
---@param eliteCount number 精英数量
---@return table positions 精英出场位序列表
local function calcElitePositions(total, eliteCount)
    local positions = {}
    if eliteCount <= 0 then return positions end
    local interval = math.floor(total / eliteCount)
    for i = 1, eliteCount do
        positions[interval * i] = true
    end
    return positions
end

--- 获取当前增益阶级
---@param essence number 当前精华数
---@return number tier 0-4
function ManaForest.GetBuffTier(essence)
    local thresholds = MF.BUFF_THRESHOLDS
    local tier = 0
    for i = 1, #thresholds do
        if essence >= thresholds[i] then
            tier = i
        else
            break
        end
    end
    return tier
end

--- 获取当前增益效果
---@param tier number 增益阶级
---@return table|nil buff {atkSpd, dmg, crit}
function ManaForest.GetBuffEffect(tier)
    if tier <= 0 then return nil end
    return MF.BUFF_TIERS[tier]
end

--- 获取到下一阶级需要的精华数
---@param essence number 当前精华数
---@return number|nil nextThreshold 下一阶级门槛, nil表示已满级
function ManaForest.GetNextThreshold(essence)
    local thresholds = MF.BUFF_THRESHOLDS
    for i = 1, #thresholds do
        if essence < thresholds[i] then
            return thresholds[i]
        end
    end
    return nil
end

-- ============================================================================
-- 存档状态管理
-- ============================================================================

--- 确保存档字段初始化 + 每日重置
function ManaForest.EnsureState()
    if not GameState.manaForest then
        GameState.manaForest = {
            attemptsToday   = 0,
            bonusAttempts   = 0,
            lastDate        = "",
            totalRuns       = 0,
            bestEssence     = 0,
            totalEssence    = 0,
            firstClearToday = false,
        }
    end
    local today = getTodayStr()
    if GameState.manaForest.lastDate ~= today then
        GameState.manaForest.attemptsToday   = 0
        GameState.manaForest.bonusAttempts   = 0
        GameState.manaForest.firstClearToday = false
        GameState.manaForest.lastDate        = today
        print("[ManaForest] Daily reset")
    end
end

--- 是否可以进入
---@return boolean canEnter
---@return string|nil reason 不可进入的原因
function ManaForest.CanEnter()
    ManaForest.EnsureState()
    local maxCh = GameState.records.maxChapter or 1
    if maxCh < Config.MANA_FOREST.UNLOCK_CHAPTER then
        return false, "通关第" .. Config.MANA_FOREST.UNLOCK_CHAPTER .. "章解锁"
    end
    local left = ManaForest.GetAttemptsLeft()
    if left <= 0 then
        return false, "今日次数已用完"
    end
    return true, nil
end

--- 是否已解锁困难模式
---@return boolean
function ManaForest.IsHardUnlocked()
    return true
end

--- 获取剩余次数
---@return number
function ManaForest.GetAttemptsLeft()
    ManaForest.EnsureState()
    local mf = GameState.manaForest
    local total = MF.MAX_DAILY_ATTEMPTS + mf.bonusAttempts
    return math.max(0, total - mf.attemptsToday)
end

--- 获取最大每日次数(含广告)
---@return number
function ManaForest.GetMaxAttempts()
    ManaForest.EnsureState()
    return MF.MAX_DAILY_ATTEMPTS + GameState.manaForest.bonusAttempts
end

--- 是否还能看广告加次数
---@return boolean
function ManaForest.CanAddBonusAttempt()
    ManaForest.EnsureState()
    return GameState.manaForest.bonusAttempts < MF.MAX_BONUS_ATTEMPTS
end

--- 广告增加次数
function ManaForest.AddBonusAttempt()
    ManaForest.EnsureState()
    if GameState.manaForest.bonusAttempts < MF.MAX_BONUS_ATTEMPTS then
        GameState.manaForest.bonusAttempts = GameState.manaForest.bonusAttempts + 1
        print("[ManaForest] Bonus attempt added, total bonus: " .. GameState.manaForest.bonusAttempts)
    end
end

--- 所有怪物是否已生成完毕
---@return boolean
function ManaForest.AllSpawned()
    return fight.spawnCount >= fight.totalMonsters
end

--- 所有怪物是否已击杀
---@return boolean
function ManaForest.AllKilled()
    return fight.killCount >= fight.totalMonsters
end

-- ============================================================================
-- 战斗入口/退出
-- ============================================================================

--- 进入魔力之森
---@param difficulty string "normal"|"hard"
---@return boolean success
function ManaForest.EnterFight(difficulty)
    ManaForest.EnsureState()

    difficulty = difficulty or "normal"
    if difficulty == "hard" and not ManaForest.IsHardUnlocked() then
        difficulty = "normal"
    end

    -- 保存当前关卡状态
    ManaForest._savedStage = {
        chapter = GameState.stage.chapter,
        stage   = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }

    -- 初始化战斗状态
    local isHard = (difficulty == "hard")
    local totalMonsters = isHard and MF.HARD_MONSTER_COUNT or MF.MONSTER_COUNT
    local eliteCount    = isHard and MF.HARD_ELITE_COUNT or MF.ELITE_COUNT

    fight.essence         = 0
    fight.difficulty      = difficulty
    fight.spawnCount      = 0
    fight.killCount       = 0
    fight.surgeTimer      = MF.SURGE_INTERVAL
    fight.surgeCount      = 0
    fight.buffTier        = 0
    fight.crystalsOnField = {}
    fight.totalMonsters   = totalMonsters
    fight.elitePositions  = calcElitePositions(totalMonsters, eliteCount)
    fight.maxOnField      = isHard and MF.HARD_MAX_ON_FIELD or MF.MAX_ON_FIELD

    ManaForest.active      = true
    ManaForest.fightResult = nil

    -- 消耗次数
    GameState.manaForest.attemptsToday = GameState.manaForest.attemptsToday + 1
    GameState.manaForest.totalRuns     = GameState.manaForest.totalRuns + 1

    print("[ManaForest] Fight started! Difficulty=" .. difficulty
        .. " Attempt=" .. GameState.manaForest.attemptsToday
        .. "/" .. ManaForest.GetMaxAttempts()
        .. " Monsters=" .. totalMonsters
        .. " Elites=" .. eliteCount)
    return true
end

--- 击杀回调 (由 GameMode adapter 调用)
---@param enemy table 被击杀的敌人
function ManaForest.OnEnemyKilled(enemy)
    if not ManaForest.active then return end

    fight.killCount = fight.killCount + 1

    -- 精华掉落
    local essenceGain = enemy.isElite
        and MF.ESSENCE_PER_ELITE
        or  MF.ESSENCE_PER_NORMAL
    fight.essence = fight.essence + essenceGain

    -- 更新增益阶级
    local newTier = ManaForest.GetBuffTier(fight.essence)
    if newTier > fight.buffTier then
        fight.buffTier = newTier
        print("[ManaForest] Buff tier up! Tier=" .. newTier .. " Essence=" .. fight.essence)
    end
end

--- 收集水晶
---@param crystalIdx number 水晶索引
function ManaForest.CollectCrystal(crystalIdx)
    if not ManaForest.active then return end
    local crystal = fight.crystalsOnField[crystalIdx]
    if not crystal or crystal.collected then return end

    crystal.collected = true
    fight.essence = fight.essence + MF.CRYSTAL_ESSENCE

    local newTier = ManaForest.GetBuffTier(fight.essence)
    if newTier > fight.buffTier then
        fight.buffTier = newTier
        print("[ManaForest] Buff tier up (crystal)! Tier=" .. newTier .. " Essence=" .. fight.essence)
    end
    print("[ManaForest] Crystal collected! Essence=" .. fight.essence)
end

--- 更新涌潮计时器 (由 adapter:OnUpdate 调用)
---@param dt number 帧间隔
---@param areaW number 战场宽度
---@param areaH number 战场高度
function ManaForest.UpdateSurge(dt, areaW, areaH)
    if not ManaForest.active then return end

    -- 更新水晶生命周期
    for i = #fight.crystalsOnField, 1, -1 do
        local c = fight.crystalsOnField[i]
        if not c.collected then
            c.timer = c.timer - dt
            if c.timer <= 0 then
                c.expired = true
                print("[ManaForest] Crystal expired at (" .. math.floor(c.x) .. "," .. math.floor(c.y) .. ")")
            end
        end
    end

    -- 涌潮倒计时
    fight.surgeTimer = fight.surgeTimer - dt
    if fight.surgeTimer <= 0 then
        fight.surgeTimer = MF.SURGE_INTERVAL
        fight.surgeCount = fight.surgeCount + 1

        -- 在场地中央区域随机生成水晶
        local margin = 60
        local cx, cy = areaW / 2, areaH / 2
        local spread = math.min(areaW, areaH) * 0.3

        for i = 1, MF.SURGE_CRYSTAL_COUNT do
            local angle = (i - 1) * (2 * math.pi / MF.SURGE_CRYSTAL_COUNT) + math.random() * 0.5
            local dist = spread * (0.5 + math.random() * 0.5)
            table.insert(fight.crystalsOnField, {
                x = cx + math.cos(angle) * dist,
                y = cy + math.sin(angle) * dist,
                timer = MF.SURGE_CRYSTAL_LIFE,
                collected = false,
                expired = false,
            })
        end

        print("[ManaForest] Mana Surge #" .. fight.surgeCount .. "! Crystals spawned.")
    end
end

--- 获取场上活跃水晶列表 (供渲染使用)
---@return table crystals
function ManaForest.GetActiveCrystals()
    local active = {}
    for i, c in ipairs(fight.crystalsOnField) do
        if not c.collected and not c.expired then
            table.insert(active, { idx = i, x = c.x, y = c.y, timer = c.timer })
        end
    end
    return active
end

--- 获取当前战斗状态 (供 HUD 显示)
---@return table state
function ManaForest.GetFightState()
    return {
        essence      = fight.essence,
        buffTier     = fight.buffTier,
        difficulty   = fight.difficulty,
        killCount    = fight.killCount,
        totalMonsters = fight.totalMonsters,
        surgeTimer   = fight.surgeTimer,
        surgeCount   = fight.surgeCount,
    }
end

--- 获取当前增益 (供战斗系统应用)
---@return table|nil buff
function ManaForest.GetCurrentBuff()
    return ManaForest.GetBuffEffect(fight.buffTier)
end

--- 结束战斗, 计算并发放奖励
---@param completed boolean 是否正常完成 (true=超时/全灭, false=死亡)
function ManaForest.EndFight(completed)
    if not ManaForest.active then return end

    ManaForest.active = false

    local essence = fight.essence
    local isHard = (fight.difficulty == "hard")

    -- 0击杀不消耗次数
    if fight.killCount == 0 then
        GameState.manaForest.attemptsToday = math.max(0, GameState.manaForest.attemptsToday - 1)
        GameState.manaForest.totalRuns     = math.max(0, GameState.manaForest.totalRuns - 1)
        ManaForest.fightResult = {
            essence      = 0,
            killCount    = 0,
            buffTier     = 0,
            difficulty   = fight.difficulty,
            potions      = 0,
            forestDew    = 0,
            gold         = 0,
            exp          = 0,
            firstClear   = false,
            newRecord    = false,
            completed    = false,
            noKill       = true,
        }
        print("[ManaForest] No kills, attempt refunded.")
        SaveSystem.SaveNow()
        return
    end

    -- 死亡惩罚: 精华效率降低
    if not completed then
        essence = math.floor(essence * MF.DEATH_EFFICIENCY)
    end

    -- 精华→奖励转化
    local potionRatio = isHard and MF.POTION_RATIO_HARD or MF.POTION_RATIO_NORMAL
    local dewRatio    = isHard and MF.DEW_RATIO_HARD or MF.DEW_RATIO_NORMAL

    local potions   = math.floor(essence / potionRatio)
    local forestDew = math.floor(essence / dewRatio)

    -- 额外固定奖励
    local C = GameState.records.maxChapter or 1
    local scaleMul = StageConfig.CalcScaleMul(C, 10) * (isHard and MF.HARD_MONSTER_SCALE or MF.MONSTER_SCALE)
    local goldScale = Config.GetGoldScale(scaleMul)

    local goldBase = isHard and MF.GOLD_BASE_HARD or MF.GOLD_BASE_NORMAL
    local expBase  = isHard and MF.EXP_BASE_HARD or MF.EXP_BASE_NORMAL
    local gold = math.floor(goldBase * goldScale)
    local exp  = math.floor(expBase * scaleMul)

    -- 首通奖励
    local firstClear = false
    if not GameState.manaForest.firstClearToday then
        GameState.manaForest.firstClearToday = true
        firstClear = true
        potions   = potions + MF.FIRST_CLEAR_POTIONS
        forestDew = forestDew + MF.FIRST_CLEAR_DEW
    end

    -- 发放奖励
    GameState.manaPotion.count = (GameState.manaPotion.count or 0) + potions
    GameState.materials.forestDew = (GameState.materials.forestDew or 0) + forestDew
    GameState.AddGold(gold)
    GameState.AddExp(exp)

    -- 更新记录
    local newRecord = false
    if fight.essence > (GameState.manaForest.bestEssence or 0) then
        GameState.manaForest.bestEssence = fight.essence
        newRecord = true
    end
    GameState.manaForest.totalEssence = (GameState.manaForest.totalEssence or 0) + fight.essence

    -- 日常任务追踪
    local ok, DailyRewards = pcall(require, "DailyRewards")
    if ok and DailyRewards and DailyRewards.Track then
        DailyRewards.Track("manaForestRuns", 1)
    end

    -- 构造结算数据
    ManaForest.fightResult = {
        essence      = fight.essence,
        effectiveEssence = essence,
        killCount    = fight.killCount,
        buffTier     = fight.buffTier,
        difficulty   = fight.difficulty,
        potions      = potions,
        forestDew    = forestDew,
        gold         = gold,
        exp          = exp,
        firstClear   = firstClear,
        newRecord    = newRecord,
        completed    = completed,
        noKill       = false,
    }

    print("[ManaForest] Fight ended! Completed=" .. tostring(completed)
        .. " Essence=" .. fight.essence
        .. " Potions=" .. potions
        .. " ForestDew=" .. forestDew
        .. " Gold=" .. gold
        .. " Exp=" .. exp
        .. (firstClear and " (First Clear!)" or "")
        .. (newRecord and " (New Record!)" or ""))

    SaveSystem.SaveNow()
end

--- 退出魔力之森, 恢复关卡
function ManaForest.ExitToMain()
    ManaForest.active      = false
    ManaForest.fightResult = nil

    -- 清空战斗状态
    fight.essence = 0
    fight.killCount = 0
    fight.spawnCount = 0
    fight.crystalsOnField = {}

    -- 恢复关卡状态
    if ManaForest._savedStage then
        GameState.stage.chapter = ManaForest._savedStage.chapter
        GameState.stage.stage   = ManaForest._savedStage.stage
        GameState.stage.waveIdx = ManaForest._savedStage.waveIdx
        ManaForest._savedStage = nil
    end
end

-- ============================================================================
-- 怪物生成队列
-- ============================================================================

--- 构建魔力之森怪物生成队列 (持续涌入模式)
---@return table queue Spawner 兼容的队列
function ManaForest.BuildSpawnQueue()
    local C = GameState.records.maxChapter or 1
    local isHard = (fight.difficulty == "hard")
    local monsterScale = isHard and MF.HARD_MONSTER_SCALE or MF.MONSTER_SCALE
    local scaleMul = StageConfig.CalcScaleMul(C, 10) * monsterScale
    local eliteHpMul = isHard and MF.HARD_ELITE_HP_MUL or MF.ELITE_HP_MUL

    -- 章节主题
    local chapter = ((C - 1) % 12) + 1
    local theme = MonsterTemplates.ChapterThemes[chapter]
    local themeResistId = getThemeResistId(theme and theme.element or "fire")

    local queue = {}

    -- 森林主题怪物配色
    local forestColors = {
        swarm   = { 60, 160, 80 },    -- 绿色小怪
        tank    = { 40, 120, 100 },   -- 深绿重型
        bruiser = { 80, 140, 180 },   -- 蓝绿精英
    }

    for i = 1, fight.totalMonsters do
        local isElite = fight.elitePositions[i] or false

        if isElite then
            -- 精英怪: bruiser/tank 交替
            local behaviorId = (fight.surgeCount % 2 == 0) and "bruiser" or "tank"
            local template = MonsterTemplates.Assemble(behaviorId, themeResistId, chapter, {
                name  = "异变守卫",
                image = "image/enemy_forest_elite_20260414154129.png",
                tags  = { "forest", "elite" },
            })
            template.hp = template.hp * eliteHpMul
            template.isElite = true
            template.color = forestColors.bruiser

            table.insert(queue, {
                templateId  = "forest_elite_" .. i,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        else
            -- 普通怪: swarm 类型
            local template = MonsterTemplates.Assemble("swarm", themeResistId, chapter, {
                name  = "魔化林兽",
                image = "image/enemy_forest_normal_20260414154110.png",
                tags  = { "forest" },
            })
            template.color = forestColors.swarm

            table.insert(queue, {
                templateId  = "forest_mob_" .. i,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        end
    end

    return queue
end

-- ============================================================================
-- HUD 绘制 (在战斗中显示精华/增益信息)
-- ============================================================================

--- 绘制魔力之森专属 HUD
---@param nvg userdata NanoVG 上下文
---@param l table 布局信息
---@param bs table BattleSystem 引用
---@param alpha number 透明度
function ManaForest.DrawHUD(nvg, l, bs, alpha)
    if not ManaForest.active then return end

    local state = ManaForest.GetFightState()
    local tier = state.buffTier
    local essence = state.essence
    local nextThreshold = ManaForest.GetNextThreshold(essence)

    -- 颜色方案
    local tierColors = {
        [0] = { 180, 180, 180 },       -- 灰色 (无增益)
        [1] = { 120, 200, 255 },       -- 淡蓝
        [2] = { 80, 160, 255 },        -- 蓝色
        [3] = { 140, 100, 255 },       -- 蓝紫
        [4] = { 200, 80, 255 },        -- 紫色
    }
    local color = tierColors[tier] or tierColors[0]

    local cx = l.x + l.w / 2
    local y = l.y + 8

    -- 精华计数
    nvgFontSize(nvg, 18)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], math.floor(255 * alpha)))
    local tierText = tier > 0 and ("  Lv." .. tier) or ""
    nvgText(nvg, cx, y, "🔮 " .. essence .. " 精华" .. tierText)

    -- 进度条 (到下一阶级)
    if nextThreshold then
        local barW = 160
        local barH = 6
        local barX = cx - barW / 2
        local barY = y + 24

        -- 当前阶级的起始门槛
        local prevThreshold = 0
        for i = 1, #MF.BUFF_THRESHOLDS do
            if MF.BUFF_THRESHOLDS[i] <= essence then
                prevThreshold = MF.BUFF_THRESHOLDS[i]
            end
        end

        local progress = (essence - prevThreshold) / (nextThreshold - prevThreshold)
        progress = math.max(0, math.min(1, progress))

        -- 背景
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, barX, barY, barW, barH, 3)
        nvgFillColor(nvg, nvgRGBA(40, 40, 40, math.floor(180 * alpha)))
        nvgFill(nvg)

        -- 进度
        if progress > 0 then
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW * progress, barH, 3)
            nvgFillColor(nvg, nvgRGBA(color[1], color[2], color[3], math.floor(220 * alpha)))
            nvgFill(nvg)
        end

        -- 下一阶段文字
        nvgFontSize(nvg, 12)
        nvgFillColor(nvg, nvgRGBA(200, 200, 200, math.floor(180 * alpha)))
        nvgText(nvg, cx, barY + barH + 4, essence .. "/" .. nextThreshold)
    end

    -- 涌潮预警 (3秒内)
    if state.surgeTimer <= 3 and state.surgeTimer > 0 then
        nvgFontSize(nvg, 22)
        nvgFillColor(nvg, nvgRGBA(100, 220, 255, math.floor(255 * alpha * (0.5 + 0.5 * math.sin(time:GetElapsedTime() * 6)))))
        nvgText(nvg, cx, y + 50, "⚡ 魔力涌潮即将到来！")
    end
end

-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode = require("GameMode")
    local adapter  = {}

    adapter.background = "image/battle_bg_forest_20260414153431.png"

    function adapter:OnEnter()
        -- difficulty 由 ManaForest.EnterFight 预先设置
        return ManaForest.active
    end

    function adapter:OnExit()
        ManaForest.ExitToMain()
    end

    function adapter:BuildSpawnQueue()
        return ManaForest.BuildSpawnQueue()
    end

    function adapter:GetBattleConfig()
        return {
            isBossWave            = false,
            bossTimerMax          = MF.FIGHT_DURATION,
            startTimerImmediately = true,
            maxAliveOverride      = fight.maxOnField,
        }
    end

    function adapter:OnEnemyKilled(bs, enemy)
        local Particles   = require("battle.Particles")
        local CombatUtils = require("battle.CombatUtils")

        ManaForest.OnEnemyKilled(enemy)

        -- 精华球视觉效果 (蓝绿色)
        Particles.SpawnExplosion(bs.particles, enemy.x, enemy.y,
            enemy.isElite and { 80, 200, 255 } or { 60, 200, 120 })
        CombatUtils.PlaySfx("enemyDie", 0.3)

        -- 全部击杀 → 结束
        if ManaForest.AllKilled() and not bs.manaForestEnded then
            ManaForest.EndFight(true)
            bs.manaForestEnded = true
            print("[ManaForest] All enemies killed, fight ended early.")
        end

        return true  -- 跳过正常掉落 (精华替代)
    end

    function adapter:OnDeath(bs)
        ManaForest.EndFight(false)
        bs.manaForestEnded = true
        print("[ManaForest] Player died. Essence=" .. fight.essence)
        return true
    end

    function adapter:OnTimeout(bs)
        ManaForest.EndFight(true)
        bs.manaForestEnded = true
        print("[ManaForest] Time up! Essence=" .. fight.essence)
        return true
    end

    function adapter:CheckWaveComplete(bs)
        -- 持续涌入: 不通过波次完成判定
        -- 仅通过超时/全灭/死亡结束
        if ManaForest.AllSpawned() and ManaForest.AllKilled() then
            if not bs.manaForestEnded then
                ManaForest.EndFight(true)
                bs.manaForestEnded = true
            end
            return true
        end
        return false
    end

    function adapter:SkipNormalExpDrop()
        return true  -- 精华替代经验掉落
    end

    function adapter:IsTimerMode()
        return true
    end

    function adapter:GetDisplayName()
        local diff = fight.difficulty == "hard" and " (困难)" or ""
        return "魔力之森" .. diff
    end

    function adapter:DrawWaveInfo(nvg, l, bs, alpha)
        ManaForest.DrawHUD(nvg, l, bs, alpha)
    end

    --- 每帧更新 (涌潮事件、水晶生命周期)
    function adapter:OnUpdate(dt, bs)
        if not ManaForest.active then return end
        ManaForest.UpdateSurge(dt, bs.areaW or 400, bs.areaH or 600)

        -- 应用精华增益到玩家
        local buff = ManaForest.GetCurrentBuff()
        if buff then
            -- 通过 bs 的临时 buff 系统应用
            bs._manaForestBuff = buff
        else
            bs._manaForestBuff = nil
        end
    end

    GameMode.Register("manaForest", adapter)
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "manaForest",
    keys  = { "manaForest" },
    group = "misc",
    serialize = function(GS)
        return {
            manaForest = {
                attemptsToday   = GS.manaForest.attemptsToday,
                bonusAttempts   = GS.manaForest.bonusAttempts,
                lastDate        = GS.manaForest.lastDate,
                totalRuns       = GS.manaForest.totalRuns,
                bestEssence     = GS.manaForest.bestEssence,
                totalEssence    = GS.manaForest.totalEssence,
                firstClearToday = GS.manaForest.firstClearToday,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.manaForest and type(data.manaForest) == "table" then
            GS.manaForest.attemptsToday   = data.manaForest.attemptsToday or 0
            GS.manaForest.bonusAttempts   = data.manaForest.bonusAttempts or 0
            GS.manaForest.lastDate        = data.manaForest.lastDate or ""
            GS.manaForest.totalRuns       = data.manaForest.totalRuns or 0
            GS.manaForest.bestEssence     = data.manaForest.bestEssence or 0
            GS.manaForest.totalEssence    = data.manaForest.totalEssence or 0
            GS.manaForest.firstClearToday = data.manaForest.firstClearToday or false
        end
    end,
})

return ManaForest
