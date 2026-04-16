-- ============================================================================
-- BattleSystem.lua - 挂机自动战斗 薄编排器
-- (术士: D4六桶伤害模型, 3元素技能树)
-- ============================================================================

local Config          = require("Config")
local GameState       = require("GameState")
local SkillTreeConfig = require("SkillTreeConfig")
local StageConfig     = require("StageConfig")
local Spawner         = require("battle.Spawner")
local PlayerAI        = require("battle.PlayerAI")
local Loot            = require("battle.Loot")
local Particles       = require("battle.Particles")

local GameMode        = require("GameMode")

-- 子模块
local DamageTracker   = require("DamageTracker")
local CombatUtils     = require("battle.CombatUtils")
local BulletSystem    = require("battle.BulletSystem")
local BuffManager     = require("battle.BuffManager")
local EnemySystem     = require("battle.EnemySystem")
local MeteorSystem    = require("battle.MeteorSystem")
local SpiritSystem    = require("battle.SpiritSystem")
local CombatCore      = require("battle.CombatCore")
local SkillCaster     = require("battle.SkillCaster")
local StageManager    = require("battle.StageManager")
local ThreatSystem        = require("battle.ThreatSystem")
local BossSkillTemplates  = require("battle.BossSkillTemplates")
local EliteSystem         = require("battle.EliteSystem")
local FamilyMechanics     = require("battle.FamilyMechanics")
local EnemyAnim           = require("battle.EnemyAnim")

local BattleSystem = {}

-- ============================================================================
-- 公开状态 (供 BattleView 读取)
-- ============================================================================

BattleSystem.enemies      = {}
BattleSystem.loots        = {}
BattleSystem.particles    = {}
BattleSystem.skillEffects = {}
BattleSystem.bossSkillEffects = {}
BattleSystem.projectiles  = {}
BattleSystem.bullets      = {}
BattleSystem.pendingSalvos = {}
BattleSystem.fireZones    = {}
BattleSystem.playerBattle = nil
BattleSystem.time         = 0
BattleSystem.pickupRadius = Config.PLAYER.pickupRadius

BattleSystem.currentWave   = 1
BattleSystem.isBossWave    = false
BattleSystem.waveAnnounce  = 0
BattleSystem.screenShake   = 0

BattleSystem.pendingMeteors = {}

BattleSystem.playerDeadTimer = 0
BattleSystem.isPlayerDead    = false

BattleSystem.bossTimer    = 0
BattleSystem.bossTimerMax = 60
BattleSystem.bossTimeout  = false
BattleSystem.bossStarted  = false

BattleSystem.stageCleared    = false
BattleSystem.stageClearTimer = 0
BattleSystem.delayedActions  = {}
BattleSystem.trialEnded      = false
BattleSystem.worldBossEnded  = false

-- Boss 模板系统状态
BattleSystem.bossProjectiles = {}
BattleSystem.bossZones       = {}
BattleSystem.threats         = {}
BattleSystem.phaseTransition = nil

-- 内部状态 (暴露给子模块通过 bs._ 前缀)
BattleSystem._waveComplete = false
BattleSystem._restTimer    = 0
BattleSystem.areaW = 0
BattleSystem.areaH = 0

-- ============================================================================
-- 子模块回调桥接 (子模块通过 bs.OnEnemyKilled 调用)
-- ============================================================================

function BattleSystem.OnEnemyKilled(enemy)
    -- 模板 Boss 死亡清理
    if enemy.phases then
        BossSkillTemplates.OnBossDied(BattleSystem, enemy)
    end
    -- 精英死亡词缀 (爆裂等)
    EliteSystem.OnEliteDeath(BattleSystem, enemy)
    -- 家族机制死亡钩子 (分裂/复活/碎裂/献祭/孢子/潮池)
    FamilyMechanics.OnEnemyDeath(BattleSystem, enemy)
    -- 原有死亡处理 (splitOnDeath/sporeCloud/deathExplode)
    EnemySystem.OnEnemyDeath(BattleSystem, enemy)
    StageManager.OnEnemyKilled(BattleSystem, enemy)
end

-- ============================================================================
-- 初始化
-- ============================================================================

function BattleSystem.Init(areaWidth, areaHeight)
    BattleSystem.areaW, BattleSystem.areaH = areaWidth, areaHeight

    BattleSystem.enemies      = {}
    BattleSystem.loots        = {}
    BattleSystem.particles    = {}
    BattleSystem.skillEffects = {}
    BattleSystem.bossSkillEffects = {}
    BattleSystem.projectiles  = {}
    BattleSystem.bullets      = {}
    BattleSystem.pendingSalvos = {}
    BattleSystem.fireZones    = {}
    BattleSystem.pendingMeteors = {}
    BattleSystem.poisonPools    = {}
    BattleSystem.pendingBarrageWaves = {}
    BattleSystem.frostShards  = {}
    BattleSystem.delayedActions = {}
    -- Boss 模板系统
    BattleSystem.bossProjectiles = {}
    BattleSystem.bossZones       = {}
    BattleSystem.phaseTransition = nil
    ThreatSystem.Init(BattleSystem)
    FamilyMechanics.Init()
    -- Decay 状态重置
    GameState._bossDecayMoveSpeed = 0
    GameState._bossDecayAtkSpeed = 0
    GameState._bossDecayAtk = 0
    GameState._bossDecayDef = 0
    BattleSystem.time         = 0
    BattleSystem.currentWave  = GameState.wave.current
    BattleSystem.isBossWave   = false
    BattleSystem.waveAnnounce = 2.0
    BattleSystem.screenShake  = 0
    BattleSystem.stageCleared = false
    BattleSystem.stageClearTimer = 0
    BattleSystem.playerDeadTimer = 0
    BattleSystem.isPlayerDead = false
    BattleSystem.trialEnded = false
    BattleSystem.worldBossEnded = false
    BattleSystem.resourceDungeonEnded = false
    BattleSystem.setDungeonEnded = false
    BattleSystem.manaForestEnded = false
    BattleSystem.nightmareDungeonEnded = false

    BattleSystem._waveComplete = false
    BattleSystem._restTimer    = 0

    GameState.ResetHP()
    GameState.ResetMana()
    GameState._sparkCritStacks = 0
    GameState._arcaneStrikeAtkSpdTimer = 0
    GameState._arcaneStrikeCastCount = 0

    Spawner.Reset()
    GameState.stage.waveIdx = 1
    GameState.stage.cleared = false
    Spawner.BuildQueue()

    -- ── 通过 GameMode 适配器获取战斗配置 ──
    local mode = GameMode.GetActive()
    if mode and mode.GetBattleConfig then
        local cfg = mode:GetBattleConfig()
        BattleSystem.isBossWave = cfg.isBossWave or false
        if cfg.bossTimerMax then
            BattleSystem.bossTimerMax = cfg.bossTimerMax
        end
        BattleSystem._startTimerImmediately = cfg.startTimerImmediately or false
    else
        local stageCfg = StageConfig.GetStage(GameState.stage.chapter, GameState.stage.stage)
        if stageCfg then
            BattleSystem.isBossWave = stageCfg.isBoss or false
        end
        BattleSystem._startTimerImmediately = false
    end

    BattleSystem.bossTimer = 0
    BattleSystem.bossTimeout = false
    BattleSystem.bossStarted = false

    -- 套装状态重置
    GameState._swiftHunterTarget = nil
    GameState._swiftHunterStacks = 0
    GameState._swiftHunterStormTimer = 0
    GameState._swiftHunterAtkSpdMul = 0
    GameState._swiftHunterExtraSplit = 0
    GameState._fissionEnergy = 0
    GameState._fissionAtkSpdTimer = 0
    GameState._fissionAtkSpdBonus = 0
    GameState._shadowStacks = 0
    GameState._shadowPostBurstTimer = 0
    GameState._shadowPostBurstCritBonus = 0
    GameState._shadowPostBurstCritHealPct = 0
    GameState._ironBastionDmgReduceTimer = 0
    GameState._ironBastionDmgReducePct = 0
    GameState._dragonPhase = nil
    GameState._dragonHitCount = 0
    GameState._dragonSkillBonus = 0
    GameState._dragonAtkBonus = 0
    GameState._dragonAtkBonusHits = 0
    GameState._dragonCycleCount = 0
    GameState._dragonMightTimer = 0
    GameState._dragonMightBonus = 0
    GameState._runeStacks = 0
    GameState._runeNextSkillBonus = 0
    GameState._runeResonanceTimer = 0
    GameState._runeResonanceSkillDmg = 0
    GameState._runeResonanceHealPct = 0
    GameState._runeResonanceCdMul = 0
    -- 第13章: 熔岩征服者状态重置
    GameState._lavaLordTimer = 0
    GameState._lavaLordFireDmgBonus = 0
    GameState._lavaLordSplashPct = 0
    GameState._lavaLordCritFireDmgMul = 0
    GameState._lavaLordCritFireRadius = 0
    -- 第13章: 极寒之心状态重置
    GameState._permafrostFatalUsed = false
    GameState._permafrostInvulTimer = 0
    GameState._iceAvatarTimer = 0
    GameState._iceAvatarDmgReduce = 0
    GameState._iceAvatarRegenPct = 0
    GameState._iceAvatarReflectChance = 0
    GameState._iceAvatarReflectDmgMul = 0
    GameState._iceAvatarSlowImmune = false

    if not CombatUtils.IsAudioReady() then CombatUtils.InitAudio() end

    BattleSystem.playerBattle = {
        x = BattleSystem.areaW / 2, y = BattleSystem.areaH / 2,
        state = "idle", targetIdx = nil,
        atkTimer = 0, atkFlash = 0,
        faceDirX = 1, skillTimers = {},
    }

    -- v3.0: 初始化所有主动技能的CD计时器 (含已装备和未装备的)
    for _, s in ipairs(SkillTreeConfig.SKILLS) do
        if s.nodeType == "active" and (s.cooldown or 0) > 0 then
            BattleSystem.playerBattle.skillTimers[s.id] = 0
        end
    end

    print("[BattleSystem] Initialized (Mage), area=" .. BattleSystem.areaW .. "x" .. BattleSystem.areaH)
end

function BattleSystem.SetAreaSize(w, h)
    BattleSystem.areaW, BattleSystem.areaH = w, h
end

-- ============================================================================
-- 公开接口 (供 PlayerAI 回调)
-- ============================================================================

function BattleSystem.PlayerAttack(idx)
    CombatCore.PlayerAttack(BattleSystem, idx)
end

function BattleSystem.CastSkill(skillCfg, lv)
    local success = SkillCaster.CastSkill(BattleSystem, skillCfg, lv)
    if success == false then return end  -- 法力不足, 跳过后续效果
    -- 符文编织2件: 技能释放叠符文
    BuffManager.OnRuneWeaverSkillCast(BattleSystem)
    -- 龙息之怒4件: 技能命中回调 (交替循环)
    BuffManager.OnDragonFurySkillHit(BattleSystem)
    -- 符文编织6件: 共鸣期间技能命中回血
    BuffManager.OnRuneResonanceSkillHit()
end

-- ============================================================================
-- 主循环
-- ============================================================================

function BattleSystem.Update(dt)
    local bs = BattleSystem
    bs._frameCount = (bs._frameCount or 0) + 1

    -- 驱动 DamageTracker 滑动窗口
    DamageTracker.Update(dt)

    -- 试炼/世界Boss/矿脉已结束, 等待结算面板处理
    if bs.trialEnded then return end
    if bs.worldBossEnded then return end
    if bs.resourceDungeonEnded then return end
    if bs.setDungeonEnded then return end
    if bs.manaForestEnded then return end
    if bs.nightmareDungeonEnded then return end

    bs.time = bs.time + dt
    bs.pickupRadius = GameState.player.pickupRadius

    if bs.waveAnnounce > 0 then
        bs.waveAnnounce = bs.waveAnnounce - dt
    end

    -- 震屏衰减
    if bs.screenShake > 0.1 then
        bs.screenShake = bs.screenShake * math.exp(-CombatUtils.SHAKE_DECAY * dt)
    else
        bs.screenShake = 0
    end

    -- BOSS 限时倒计时: 当 Boss 敌人出现在场上时才开始计时
    if bs.isBossWave and not bs.bossTimeout then
        local mode = GameMode.GetActive()
        if not bs.bossStarted then
            -- 立即启动计时器模式 (如折光矿脉)
            if bs._startTimerImmediately then
                bs.bossStarted = true
                bs.bossTimer = bs.bossTimerMax
                print("[BattleSystem] Timer started immediately: " .. bs.bossTimerMax .. "s")
            else
                -- 检测是否有 Boss 敌人已经生成
                for _, e in ipairs(bs.enemies) do
                    if not e.dead and e.isBoss then
                        bs.bossStarted = true
                        bs.bossTimer = bs.bossTimerMax
                        print("[BattleSystem] BOSS appeared! Timer started: " .. bs.bossTimerMax .. "s")
                        break
                    end
                end
                -- 特殊模式生成超时保护: 5秒内Boss未出现则强制启动计时
                if not bs.bossStarted and mode and mode.IsTimerMode and mode:IsTimerMode() then
                    bs._bossSpawnWait = (bs._bossSpawnWait or 0) + dt
                    if bs._bossSpawnWait > 5.0 then
                        print("[BattleSystem] WARNING: Boss spawn timeout, force starting timer")
                        bs.bossStarted = true
                        bs.bossTimer = bs.bossTimerMax
                    end
                end
            end
        end
        if bs.bossStarted and bs.bossTimer > 0 then
            bs.bossTimer = bs.bossTimer - dt
            if bs.bossTimer <= 0 then
                bs.bossTimer = 0
                bs.bossTimeout = true
                -- 特殊模式: 通过适配器处理超时
                if mode and mode.OnTimeout then
                    local handled = mode:OnTimeout(bs)
                    if handled then return end
                end
                -- 默认: 章节Boss超时 = 死亡
                bs.isPlayerDead = true
                bs.playerDeadTimer = 2.5
                CombatUtils.TriggerShake(bs, 10)
                print("[BattleSystem] BOSS timeout! Stage failed.")
                return
            end
        end
    end

    -- 玩家死亡处理
    if bs.isPlayerDead then
        bs.playerDeadTimer = bs.playerDeadTimer - dt
        Particles.Update(dt, bs.particles)
        Particles.UpdateSkillEffects(dt, bs.skillEffects)
        Particles.UpdateSkillEffects(dt, bs.bossSkillEffects)
        if bs.playerDeadTimer <= 0 then
            StageManager.RetryStage(bs)
        end
        return
    end

    -- 波次间休息
    if bs._waveComplete then
        bs._restTimer = bs._restTimer - dt
        if bs._restTimer <= 0 then
            StageManager.NextWave(bs)
            bs._waveComplete = false
        end
        -- 继续更新陨石/冰霜等延迟特效，避免因敌人全灭而中断动画
        MeteorSystem.UpdatePendingMeteors(dt, bs)
        MeteorSystem.UpdateFireZones(dt, bs)
        MeteorSystem.UpdateFrostShards(dt, bs)
        MeteorSystem.UpdatePoisonPools(dt, bs)
        MeteorSystem.UpdatePendingBarrageWaves(dt, bs)
        Loot.Update(dt, bs.loots, bs.playerBattle, bs.pickupRadius)
        Particles.Update(dt, bs.particles)
        Particles.UpdateSkillEffects(dt, bs.skillEffects)
        Particles.UpdateSkillEffects(dt, bs.bossSkillEffects)
        return
    end

    -- 生存系统 tick
    GameState.UpdateLifeStealTimer(dt)
    GameState.TickHPRegen(dt)
    GameState.TickManaRegen(dt)

    -- 自动喝魔力之源: MP 低于 30% 时自动使用
    if GameState.manaPotion and GameState.manaPotion.autoUse then
        local maxMana = GameState.GetMaxMana()
        if maxMana > 0 and GameState.playerMana / maxMana < 0.30 then
            local free = GameState.IsManaPotionFreeRegen()
            GameState.UseManaPotionOnce(free)
        end
    end

    GameState.UpdateDebuffs(dt, bs)

    -- 受击闪烁衰减
    if bs.playerHitFlash and bs.playerHitFlash > 0 then
        bs.playerHitFlash = bs.playerHitFlash - dt
    end

    Spawner.Update(dt, bs.enemies, bs.areaW, bs.areaH)

    -- 引导系统更新 (在 PlayerAI 之前, 以便引导段伤害先结算)
    local ChannelSystem = require("battle.ChannelSystem")
    ChannelSystem.Update(dt)

    PlayerAI.Update(dt, bs.playerBattle, bs.enemies, bs.areaW, bs.areaH, function(idx)
        BattleSystem.PlayerAttack(idx)
    end, bs)
    PlayerAI.UpdateSkills(dt, bs.playerBattle, bs.enemies, function(cfg, lv)
        BattleSystem.CastSkill(cfg, lv)
    end)

    -- 子系统更新
    BuffManager.UpdateSwiftHunter(dt)
    BuffManager.UpdateFissionForce(dt)
    BuffManager.UpdateShadowHunter(dt)
    BuffManager.UpdateIronBastion(dt)
    BuffManager.UpdateDragonFury(dt)
    BuffManager.UpdateRuneWeaver(dt)
    BuffManager.UpdateLavaConqueror(dt, bs)
    BuffManager.UpdatePermafrostHeart(dt)
    SpiritSystem.UpdateElementSpirits(dt, bs)
    EnemySystem.UpdateEnemyDebuffs(dt, bs)

    -- 微光寒冰甲: 花费法力减少 ice_armor CD
    if GameState._iceArmorCdrPending and GameState._iceArmorCdrPending > 0 then
        local cdr = GameState._iceArmorCdrPending
        GameState._iceArmorCdrPending = 0
        if bs.playerBattle.skillTimers["ice_armor"] then
            bs.playerBattle.skillTimers["ice_armor"] = math.max(0,
                bs.playerBattle.skillTimers["ice_armor"] - cdr)
        end
    end

    -- 神秘寒冰甲: 周期性对近距离敌人施加冻伤
    if GameState._iceArmorFrostbitePending then
        GameState._iceArmorFrostbitePending = false
        local px, py = bs.playerBattle.x, bs.playerBattle.y
        local range = 100  -- 近距离范围
        for _, e in ipairs(bs.enemies) do
            if not e.dead then
                local dx, dy = e.x - px, e.y - py
                if dx * dx + dy * dy <= range * range then
                    local Helpers = require("battle.skills.Helpers")
                    Helpers.ApplyFrostbite(e, 20)
                end
            end
        end
    end

    MeteorSystem.UpdatePendingMeteors(dt, bs)
    CombatUtils.UpdateProjectiles(dt, bs)
    BulletSystem.UpdatePendingSalvos(dt, bs)
    BulletSystem.UpdateBullets(dt, bs, bs.areaW, bs.areaH)
    MeteorSystem.UpdateFireZones(dt, bs)
    MeteorSystem.UpdateFrostShards(dt, bs)
    MeteorSystem.UpdatePoisonPools(dt, bs)
    MeteorSystem.UpdatePendingBarrageWaves(dt, bs)
    EnemySystem.UpdateEnemyAI(dt, bs)
    EnemySystem.UpdateEnemyAbilities(dt, bs)

    -- ── 新 Boss 模板系统 ──
    ThreatSystem.Update(dt, bs)
    BossSkillTemplates.Update(dt, bs)
    BossSkillTemplates.UpdateProjectiles(dt, bs)
    BossSkillTemplates.UpdateZones(dt, bs)
    BossSkillTemplates.UpdateDestroyables(dt, bs)
    BossSkillTemplates.UpdateVortexPull(dt, bs)

    -- 家族机制 & 精英词缀 逐帧更新
    FamilyMechanics.Update(bs, dt)
    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.eliteRank then
            EliteSystem.UpdateAffixes(bs, e, dt)
        end
    end
    -- 怪物代码动画更新
    EnemyAnim.Update(dt, bs)

    -- 延迟动作 (Boss 技能延迟伤害) - 带安全防护
    for i = #bs.delayedActions, 1, -1 do
        local a = bs.delayedActions[i]
        if not a or not a.timer then
            table.remove(bs.delayedActions, i)
        else
            a.timer = a.timer - dt
            if a.timer <= 0 then
                table.remove(bs.delayedActions, i)
                if a.callback then
                    local ok, err = pcall(a.callback)
                    if not ok then
                        print("[BattleSystem] delayedAction callback error: " .. tostring(err))
                    end
                end
            end
        end
    end

    Loot.Update(dt, bs.loots, bs.playerBattle, bs.pickupRadius)
    Particles.Update(dt, bs.particles)
    Particles.UpdateSkillEffects(dt, bs.skillEffects)
    Particles.UpdateSkillEffects(dt, bs.bossSkillEffects)
    BattleSystem.CleanupDead()
    StageManager.CheckWaveComplete(bs)

    -- 检查玩家死亡
    if GameState.playerDead and not bs.isPlayerDead then
        bs.isPlayerDead = true
        bs.playerDeadTimer = 2.5
        CombatUtils.TriggerShake(bs, 10)
        print("[BattleSystem] Player died!")
    end
end

-- ============================================================================
-- 清理
-- ============================================================================

function BattleSystem.CleanupDead()
    for i = #BattleSystem.enemies, 1, -1 do
        local e = BattleSystem.enemies[i]
        -- _pendingRevive: 亡灵待复活/构装碎裂原体, 保留在列表中
        -- _dyingAnim: 死亡动画播放中, 延迟移除
        if e.dead and not e._pendingRevive and not e._dyingAnim then
            table.remove(BattleSystem.enemies, i)
        end
    end
end

-- ============================================================================
-- 兼容旧接口 (BattleView 可能直接调用)
-- ============================================================================

function BattleSystem.RetryStage()
    StageManager.RetryStage(BattleSystem)
end

return BattleSystem
