-- ============================================================================
-- battle/StageManager.lua - 击杀奖励 + 波次管理 + 死亡重试
-- ============================================================================

local Config          = require("Config")
local GameState       = require("GameState")
local StageConfig     = require("StageConfig")
local Spawner         = require("battle.Spawner")
local Loot            = require("battle.Loot")
local Particles       = require("battle.Particles")
local CombatUtils     = require("battle.CombatUtils")
local SaveSystem      = require("SaveSystem")
local GameMode        = require("GameMode")
local Utils           = require("Utils")
local DailyRewards    = require("DailyRewards")
local DropManager     = require("battle.DropManager")
local FloatTip        = require("ui.FloatTip")

local StageManager = {}

-- ============================================================================
-- 保底装备生成
-- ============================================================================

--- 生成保底品质装备: 直接使用 CreateEquip 构造
--- @param minQuality number 最低品质索引
--- @param chapter number 当前章节
--- @return table equip
function StageManager.GenerateGuaranteedEquip(minQuality, chapter)
    return GameState.CreateEquip(minQuality, chapter)
end

-- ============================================================================
-- 击杀 & 掉落
-- ============================================================================

--- @param bs table BattleSystem 引用
--- @param enemy table 被击杀的敌人
function StageManager.OnEnemyKilled(bs, enemy)
    -- ── 特殊模式: 通过 GameMode 适配器处理击杀 ──
    local mode = GameMode.GetActive()
    if mode and mode.OnEnemyKilled then
        local handled = mode:OnEnemyKilled(bs, enemy)
        if handled then return end
    end

    GameState.wave.killCount  = GameState.wave.killCount + 1
    GameState.wave.totalKills = GameState.wave.totalKills + 1
    DailyRewards.TrackProgress("kills", 1)

    -- 击杀触发护盾
    GameState.OnKillShield()

    -- 掉落处理 → 委托给 DropManager (数据驱动)
    DropManager.ProcessDrops(bs, enemy, mode)

    Particles.SpawnExplosion(bs.particles, enemy.x, enemy.y, enemy.color)
    CombatUtils.PlaySfx("enemyDie", 0.3)

    -- Boss 击杀即通关：清除残余小怪，直接标记关卡完成
    if enemy.isBoss then
        for _, e in ipairs(bs.enemies) do
            if not e.dead and e ~= enemy and not e._isFragment then
                e.dead = true
            end
        end
        bs._waveComplete = true
        bs._restTimer = 1.5
        Particles.SpawnReactionText(bs.particles,
            bs.playerBattle.x, bs.playerBattle.y - 40,
            "Boss已击杀! 关卡通关!", { 255, 220, 60 })
    end
end

-- ============================================================================
-- 关卡波次管理
-- ============================================================================

--- @param bs table BattleSystem 引用
function StageManager.CheckWaveComplete(bs)
    -- ── 特殊模式: 计时器控制的模式跳过波次完成检测 ──
    local mode = GameMode.GetActive()
    if mode then
        if mode.IsTimerMode and mode:IsTimerMode() then return end
    end

    if not Spawner.IsWaveSpawnDone() then return end
    for _, e in ipairs(bs.enemies) do
        if not e.dead then return end
    end

    -- ── 特殊模式: 波次清空后的自定义处理 ──
    if mode and mode.CheckWaveComplete then
        local handled = mode:CheckWaveComplete(bs)
        if handled then return end
    end

    local gs = GameState.stage
    local stageCfg = StageConfig.GetStage(gs.chapter, gs.stage)
    if not stageCfg then return end

    -- 当前关卡还有下一波？
    if gs.waveIdx < #stageCfg.waves then
        gs.waveIdx = gs.waveIdx + 1
        bs.enemies = {}
        -- 不清空 pendingMeteors，让未落地的陨石/冰霜继续播放完毕
        Spawner.Reset()
        Spawner.BuildQueue()
        bs.waveAnnounce = 1.5
        print("[BattleSystem] Stage " .. gs.chapter .. "-" .. gs.stage .. " wave " .. gs.waveIdx)
        return
    end

    -- 当前关卡所有波次已清完 → 关卡通关
    bs._waveComplete = true
    bs._restTimer = 1.5
    DailyRewards.TrackProgress("stages", 1)
end

--- @param bs table BattleSystem 引用
function StageManager.NextWave(bs)
    -- ── 特殊模式: 通过 GameMode 适配器处理下一波 ──
    local mode = GameMode.GetActive()
    if mode and mode.OnNextWave then
        local handled = mode:OnNextWave(bs)
        if handled then return end
    end

    local gs = GameState.stage

    -- 发放关卡奖励
    local stageCfg = StageConfig.GetStage(gs.chapter, gs.stage)
    if stageCfg and stageCfg.reward then
        -- 金币统一从怪物掉落获取，通关不再发金币
        if stageCfg.reward.guaranteeEquipQuality then
            local equip = StageManager.GenerateGuaranteedEquip(
                stageCfg.reward.guaranteeEquipQuality, gs.chapter)
            local _, decompInfo = GameState.AddToInventory(equip)
            if decompInfo then FloatTip.Decompose(decompInfo) end
        end
        print("[BattleSystem] Stage " .. gs.chapter .. "-" .. gs.stage .. " cleared!")
        -- 通关时即时存档
        SaveSystem.SaveNow()
    end

    -- 推进到下一关（动态判断：当前关卡低于最高记录则为回刷，不推进）
    local maxCh = GameState.records and GameState.records.maxChapter or 1
    local maxSt = GameState.records and GameState.records.maxStage or 1
    local alreadyCleared = (gs.chapter < maxCh) or (gs.chapter == maxCh and gs.stage < maxSt)
    if alreadyCleared then
        -- 回刷已通关关卡：不推进，保持当前关卡重复刷
        print("[BattleSystem] Replay mode (cleared): staying at " .. gs.chapter .. "-" .. gs.stage
            .. " (max=" .. maxCh .. "-" .. maxSt .. ")")
    else
        local totalStages = StageConfig.GetStageCount(gs.chapter)
        if gs.stage < totalStages then
            gs.stage = gs.stage + 1
        else
            local totalChapters = StageConfig.GetChapterCount()
            if gs.chapter < totalChapters then
                gs.chapter = gs.chapter + 1
                gs.stage = 1
            else
                -- 已是最后一章最后一关，锁定在此关无限循环
                print("[BattleSystem] Final stage reached, staying at " .. gs.chapter .. "-" .. gs.stage)
            end
        end
    end

    gs.waveIdx = 1
    gs.cleared = false
    GameState.wave.killCount = 0
    bs.currentWave = bs.currentWave + 1
    GameState.wave.current = bs.currentWave

    -- 新关卡: 重置套装状态
    -- 第13章: 熔岩征服者+极寒之心重置
    GameState._lavaLordTimer = 0
    GameState._permafrostFatalUsed = false
    GameState._permafrostInvulTimer = 0
    GameState._iceAvatarTimer = 0

    bs.enemies = {}
    -- 不清空 pendingMeteors，让未落地的特效继续播放
    bs.waveAnnounce = 2.0

    Spawner.Reset()
    Spawner.ResetStageTotal()
    Spawner.BuildQueue()

    -- 更新 BOSS 标记
    local newStageCfg = StageConfig.GetStage(gs.chapter, gs.stage)
    bs.isBossWave = newStageCfg and newStageCfg.isBoss or false
    if bs.isBossWave then
        DailyRewards.TrackProgress("bossAttempts", 1)
    end

    bs.bossTimer = 0
    bs.bossTimeout = false
    bs.bossStarted = false

    print("[BattleSystem] Now at " .. gs.chapter .. "-" .. gs.stage .. (bs.isBossWave and " (BOSS)" or ""))
    DailyRewards.FlushProgress()
end

-- ============================================================================
-- 死亡重试: 重试当前关卡
-- ============================================================================

--- @param bs table BattleSystem 引用
function StageManager.RetryStage(bs)
    -- ── 特殊模式: 通过 GameMode 适配器处理死亡 ──
    local mode = GameMode.GetActive()
    if mode and mode.OnDeath then
        local handled = mode:OnDeath(bs)
        if handled then return end
    end

    print("[BattleSystem] Retrying stage " .. GameState.stage.chapter .. "-" .. GameState.stage.stage)

    bs.enemies      = {}
    -- bs.loots 不清空，保留未拾取的掉落物（磁吸机制会自动收取）
    bs.particles    = {}
    bs.skillEffects = {}
    bs.bossSkillEffects = {}
    bs.projectiles  = {}
    bs.bullets      = {}
    bs.pendingSalvos = {}
    bs.fireZones    = {}
    bs.pendingMeteors = {}
    bs.delayedActions = {}
    -- Boss 模板技能残留清理
    bs.bossProjectiles = {}
    bs.bossZones       = {}
    bs.phaseTransition = nil
    if bs.threats then
        local ok, ThreatSystem = pcall(require, "battle.ThreatSystem")
        if ok then ThreatSystem.Clear(bs) end
    end
    GameState._bossDecayMoveSpeed = 0
    GameState._bossDecayAtkSpeed  = 0
    GameState._bossDecayAtk       = 0
    GameState._bossDecayDef       = 0
    bs.waveAnnounce = 2.0
    bs.screenShake  = 0
    bs.isPlayerDead = false
    bs.playerDeadTimer = 0
    bs.playerHitFlash = 0
    bs.bossTimeout = false

    local stageCfg = StageConfig.GetStage(GameState.stage.chapter, GameState.stage.stage)
    bs.isBossWave = stageCfg and stageCfg.isBoss or false
    if bs.isBossWave then
        DailyRewards.TrackProgress("bossAttempts", 1)
    end
    bs.bossTimer = 0
    bs.bossStarted = false

    bs._waveComplete = false
    bs._restTimer    = 0

    GameState.stage.waveIdx = 1
    GameState.stage.cleared = false
    GameState.wave.killCount = 0

    GameState.ResetHP()

    -- 重置套装状态
    -- 第13章: 熔岩征服者+极寒之心重置
    GameState._lavaLordTimer = 0
    GameState._permafrostFatalUsed = false
    GameState._permafrostInvulTimer = 0
    GameState._iceAvatarTimer = 0

    Spawner.Reset()
    Spawner.ResetStageTotal()
    Spawner.BuildQueue()

    -- 引导系统: 波次切换时强制重置
    local ok_ch, ChannelSystem = pcall(require, "battle.ChannelSystem")
    if ok_ch then ChannelSystem.Reset() end

    if bs.playerBattle then
        bs.playerBattle.x = bs.areaW / 2
        bs.playerBattle.y = bs.areaH / 2
        bs.playerBattle.atkTimer = 0
        bs.playerBattle.atkFlash = 0
        for k, _ in pairs(bs.playerBattle.skillTimers) do
            bs.playerBattle.skillTimers[k] = 0
        end
    end
    DailyRewards.FlushProgress()
end

return StageManager
