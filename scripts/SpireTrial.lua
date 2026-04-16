-- ============================================================================
-- SpireTrial.lua - 尖塔试炼模块 (世界层级解锁)
--
-- 职责: 固定难度的限时副本, 通关后解锁下一世界层级
-- 依赖: WorldTierConfig, DynamicLevel, MonsterFamilies, GameState, GameMode
-- 设计文档: docs/数值/怪物家族系统设计.md §十
-- ============================================================================

local WorldTierConfig = require("WorldTierConfig")
local DynamicLevel    = require("DynamicLevel")
local GameState       = require("GameState")
local SaveSystem      = require("SaveSystem")

local M = {}

-- ============================================================================
-- 常数
-- ============================================================================

M.TIME_LIMIT         = 180    -- 限时 3 分钟 (秒)
M.PHASE_COUNT        = 3      -- 3 个阶段
M.WAVES_PER_PHASE    = { 6, 6, 3 }  -- 各阶段波数 (总计 15 波)
M.BOSS_TIMER         = 60     -- Boss 阶段内限时 (秒)

-- 每阶段精英/冠军配置
M.PHASE_CONFIG = {
    -- 阶段 1: 清扫层 (波 1-6)
    {
        mobCount     = 8,           -- 每波小怪数量
        eliteCount   = 1,           -- 精英数 (从第 3 波开始)
        eliteFromWave = 3,          -- 精英最早出现的波次
        championCount = 0,
        roleMob      = "normal",
        roleElite    = "elite",
    },
    -- 阶段 2: 精英层 (波 7-12)
    {
        mobCount     = 6,
        eliteCount   = 2,
        eliteFromWave = 1,
        championCount = 1,          -- 冠军 (从第 3 波开始)
        championFromWave = 3,
        roleMob      = "normal",
        roleElite    = "elite",
        roleChampion = "champion",
    },
    -- 阶段 3: 守卫 Boss (波 13-15)
    {
        mobCount     = 4,           -- Boss 阶段的增援小怪
        eliteCount   = 0,
        championCount = 0,
        roleMob      = "normal",
        isBossPhase  = true,
    },
}

-- 守卫 Boss 定义
M.GUARDIANS = {
    [1] = {
        name     = "石卫·震岳",
        familyId = "elemental_fire",   -- 构造体系
        raceTier = "D",                -- 超重型
        element  = "physical",
    },
    [2] = {
        name     = "影卫·虚蚀",
        familyId = "arcane",           -- 虚空体系
        raceTier = "D",
        element  = "arcane",
    },
    [3] = {
        name     = "焰卫·灰烬",
        familyId = "elemental_fire",   -- 恶鬼(火)+教团(火)
        raceTier = "D",
        element  = "fire",
    },
}

-- ============================================================================
-- 运行时状态 (不持久化, 每次进入重置)
-- ============================================================================

local state_ = {
    active      = false,
    spireId     = 0,        -- 当前试炼编号 (1-3)
    phase       = 1,        -- 当前阶段 (1-3)
    wave        = 1,        -- 当前阶段内波次
    totalWave   = 1,        -- 总波次 (1-15)
    timeRemain  = 0,        -- 剩余时间 (秒)
    killCount   = 0,        -- 当前波击杀数
    targetCount = 0,        -- 当前波目标数
    bossSpawned = false,    -- Boss 是否已出场
}

-- ============================================================================
-- 查询接口
-- ============================================================================

function M.IsActive()       return state_.active end
function M.GetSpireId()     return state_.spireId end
function M.GetPhase()       return state_.phase end
function M.GetWave()        return state_.wave end
function M.GetTotalWave()   return state_.totalWave end
function M.GetTimeRemain()  return state_.timeRemain end

--- 获取试炼的完成状态 (从 GameState 读取)
---@param spireId number 1-3
---@return boolean completed
function M.IsCompleted(spireId)
    local gs = GameState.spireTrial
    return gs and gs.completed and gs.completed[spireId] or false
end

--- 检查能否进入指定试炼
---@param spireId number
---@return boolean canEnter
---@return string|nil reason
function M.CanEnter(spireId)
    if M.IsCompleted(spireId) then
        return false, "试炼已通关"
    end
    local currentWT = (GameState.spireTrial and GameState.spireTrial.worldTier) or 1
    return WorldTierConfig.CanEnterSpire(spireId, GameState.level, GameState.stage.chapter, currentWT)
end

-- ============================================================================
-- 进入 / 退出
-- ============================================================================

--- 进入尖塔试炼
---@param spireId number 试炼编号 (1-3)
---@return boolean success
function M.Enter(spireId)
    local canEnter, reason = M.CanEnter(spireId)
    if not canEnter then
        print("[SpireTrial] Cannot enter spire " .. spireId .. ": " .. (reason or ""))
        return false
    end

    state_.active      = true
    state_.spireId     = spireId
    state_.phase       = 1
    state_.wave        = 1
    state_.totalWave   = 1
    state_.timeRemain  = M.TIME_LIMIT
    state_.killCount   = 0
    state_.targetCount = 0
    state_.bossSpawned = false

    print("[SpireTrial] Entered Spire " .. spireId)
    return true
end

--- 退出尖塔试炼
function M.Exit()
    state_.active = false
    state_.spireId = 0
    print("[SpireTrial] Exited")
end

-- ============================================================================
-- 通关处理
-- ============================================================================

--- 试炼通关: 解锁下一世界层级
function M.Complete()
    local def = WorldTierConfig.GetSpireUnlock(state_.spireId)
    if not def then return end

    -- 确保 GameState.spireTrial 存在
    if not GameState.spireTrial then
        GameState.spireTrial = { worldTier = 1, completed = {} }
    end

    -- 标记试炼通关
    GameState.spireTrial.completed[state_.spireId] = true

    -- 解锁世界层级
    if def.unlocksWT > (GameState.spireTrial.worldTier or 1) then
        GameState.spireTrial.worldTier = def.unlocksWT
        print("[SpireTrial] World Tier unlocked: " .. def.unlocksWT .. " (" .. WorldTierConfig.Get(def.unlocksWT).name .. ")")
    end

    -- 试炼通关掉落: 裂隙残响 (按试炼编号递增)
    local riftDrop = state_.spireId * 2  -- spire1=2, spire2=4, spire3=6
    local eternalDrop = state_.spireId   -- spire1=1, spire2=2, spire3=3
    GameState.AddMaterials({ riftEcho = riftDrop, eternal = eternalDrop })
    print("[SpireTrial] Completion reward: riftEcho=" .. riftDrop .. " eternal=" .. eternalDrop)

    SaveSystem.MarkDirty()
    state_.active = false
    print("[SpireTrial] Spire " .. state_.spireId .. " completed!")
end

-- ============================================================================
-- 怪物生成
-- ============================================================================

--- 构建当前波次的生成队列
---@return table[] queue  Spawner 兼容队列
function M.BuildQueue()
    local spireDef   = WorldTierConfig.GetSpireUnlock(state_.spireId)
    if not spireDef then return {} end

    local phaseCfg   = M.PHASE_CONFIG[state_.phase]
    local monsterLv  = spireDef.monsterLevel
    local bossLv     = spireDef.bossLevel
    local wtMulId    = spireDef.usesWTMul
    local tierHPMul  = WorldTierConfig.GetHPMul(wtMulId)
    local tierATKMul = WorldTierConfig.GetATKMul(wtMulId)

    local queue = {}

    if phaseCfg.isBossPhase then
        -- 阶段 3: Boss + 增援小怪
        -- 先出小怪增援
        for i = 1, phaseCfg.mobCount do
            local entry = M._makeMobEntry(monsterLv, tierHPMul, tierATKMul, "normal")
            if entry then
                table.insert(queue, entry)
            end
        end
        -- Boss (仅最后一波)
        if state_.wave >= M.WAVES_PER_PHASE[3] and not state_.bossSpawned then
            local entry = M._makeBossEntry(bossLv, tierHPMul, tierATKMul)
            if entry then
                table.insert(queue, entry)
                state_.bossSpawned = true
            end
        end
    else
        -- 阶段 1-2: 普通怪 + 精英 + 冠军
        for i = 1, phaseCfg.mobCount do
            local entry = M._makeMobEntry(monsterLv, tierHPMul, tierATKMul, phaseCfg.roleMob)
            if entry then
                table.insert(queue, entry)
            end
        end

        -- 精英
        if phaseCfg.eliteCount > 0 and state_.wave >= (phaseCfg.eliteFromWave or 1) then
            for i = 1, phaseCfg.eliteCount do
                local entry = M._makeMobEntry(monsterLv, tierHPMul, tierATKMul, phaseCfg.roleElite or "elite")
                if entry then
                    entry.template.isElite = true
                    table.insert(queue, entry)
                end
            end
        end

        -- 冠军
        if (phaseCfg.championCount or 0) > 0 and state_.wave >= (phaseCfg.championFromWave or 1) then
            for i = 1, phaseCfg.championCount do
                local entry = M._makeMobEntry(monsterLv, tierHPMul, tierATKMul, phaseCfg.roleChampion or "champion")
                if entry then
                    entry.template.isChampion = true
                    table.insert(queue, entry)
                end
            end
        end
    end

    state_.targetCount = #queue
    state_.killCount   = 0
    return queue
end

--- 内部: 构造普通怪条目
---@param level number
---@param tierHPMul number
---@param tierATKMul number
---@param role string  DynamicLevel.ROLE_MULS key
---@return table|nil entry
function M._makeMobEntry(level, tierHPMul, tierATKMul, role)
    local roleDef = DynamicLevel.ROLE_MULS[role] or DynamicLevel.ROLE_MULS.normal
    -- 使用 B 档 (标准近战) 作为默认种族基准
    local raceHP  = 110
    local raceATK = 13
    local raceDEF = 15

    local hp  = DynamicLevel.CalcHP(raceHP, level, tierHPMul, roleDef.hpMul)
    local atk = DynamicLevel.CalcATK(raceATK, level, tierATKMul, roleDef.atkMul)

    return {
        templateId = "spire_mob",
        template = {
            name        = "尖塔守卫",
            hp          = hp,
            atk         = atk,
            def         = raceDEF,
            speed       = 35,
            atkInterval = 1.0,
            element     = "physical",
            expDrop     = 0,     -- 尖塔不给经验
            dropTemplate = "none",
            radius      = 16,
            monsterLevel = level,
        },
        scaleMul = 1,  -- 兼容字段, 不再使用
    }
end

--- 内部: 构造守卫 Boss 条目
---@param level number
---@param tierHPMul number
---@param tierATKMul number
---@return table|nil entry
function M._makeBossEntry(level, tierHPMul, tierATKMul)
    local guardian = M.GUARDIANS[state_.spireId]
    if not guardian then return nil end

    local roleDef = DynamicLevel.ROLE_MULS.dungeon_boss
    -- Boss 使用 C 档 (重型近战) 基准
    local raceHP  = 240
    local raceATK = 18
    local raceDEF = 35

    local hp  = DynamicLevel.CalcHP(raceHP, level, tierHPMul, roleDef.hpMul)
    local atk = DynamicLevel.CalcATK(raceATK, level, tierATKMul, roleDef.atkMul)

    return {
        templateId = "spire_boss_" .. state_.spireId,
        template = {
            name        = guardian.name,
            hp          = hp,
            atk         = atk,
            def         = raceDEF,
            speed       = 20,
            atkInterval = 1.8,
            element     = guardian.element,
            expDrop     = 0,
            dropTemplate = "boss",
            radius      = 22,
            isBoss      = true,
            monsterLevel = level,
        },
        scaleMul = 1,
    }
end

-- ============================================================================
-- 波次推进
-- ============================================================================

--- 推进到下一波
---@return boolean finished true = 试炼结束 (通关或全部波次完成)
function M.AdvanceWave()
    state_.wave = state_.wave + 1
    state_.totalWave = state_.totalWave + 1

    -- 检查当前阶段是否结束
    local maxWave = M.WAVES_PER_PHASE[state_.phase] or 5
    if state_.wave > maxWave then
        -- 进入下一阶段
        state_.phase = state_.phase + 1
        state_.wave  = 1
        if state_.phase > M.PHASE_COUNT then
            -- 所有阶段完毕 → 通关
            return true
        end
    end

    return false
end

--- 更新剩余时间
---@param dt number 帧间隔 (秒)
---@return boolean timedOut true = 超时
function M.UpdateTimer(dt)
    if not state_.active then return false end
    state_.timeRemain = state_.timeRemain - dt
    if state_.timeRemain <= 0 then
        state_.timeRemain = 0
        return true
    end
    return false
end

-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode  = require("GameMode")
    local Particles = require("battle.Particles")

    local adapter = {}

    adapter.background = "image/battle_bg_spire.png"

    -- ── 生命周期 ──

    function adapter:OnEnter()
        -- spireId 由外部设置 (通过 M.pendingSpireId)
        local spireId = M.pendingSpireId or 1
        M.pendingSpireId = nil
        return M.Enter(spireId)
    end

    function adapter:OnExit()
        M.Exit()
    end

    -- ── 战斗 ──

    function adapter:BuildSpawnQueue()
        return M.BuildQueue()
    end

    function adapter:GetBattleConfig()
        local phaseCfg = M.PHASE_CONFIG[state_.phase]
        local isBoss   = phaseCfg and phaseCfg.isBossPhase and state_.bossSpawned
        return {
            isBossWave            = isBoss or false,
            bossTimerMax          = isBoss and M.BOSS_TIMER or 0,
            startTimerImmediately = false,
        }
    end

    function adapter:SkipNormalExpDrop()
        return true  -- 尖塔不给正常经验掉落
    end

    function adapter:IsTimerMode()
        return true  -- 整体限时模式
    end

    function adapter:OnEnemyKilled(bs, enemy)
        state_.killCount = state_.killCount + 1

        -- Boss 击杀 → 试炼通关
        if enemy.isBoss then
            for _, e in ipairs(bs.enemies) do
                if not e.dead and e ~= enemy then e.dead = true end
            end
            M.Complete()
            bs._waveComplete = true
            bs._restTimer    = 2.0
            Particles.SpawnReactionText(bs.particles,
                bs.playerBattle.x, bs.playerBattle.y - 40,
                "尖塔试炼通关!", { 255, 220, 80 })
            return true
        end

        -- 当前波击杀完毕
        if state_.killCount >= state_.targetCount then
            local finished = M.AdvanceWave()
            if finished then
                -- 所有波次完毕但无 Boss → 异常, 视为通关
                M.Complete()
                bs._waveComplete = true
                bs._restTimer    = 2.0
                return true
            end
            bs._waveComplete = true
            bs._restTimer    = 1.0
            return true
        end

        return false
    end

    function adapter:CheckWaveComplete(bs)
        return false
    end

    function adapter:OnNextWave(bs)
        local Spawner = require("battle.Spawner")

        local phaseCfg = M.PHASE_CONFIG[state_.phase]

        bs.enemies      = {}
        bs.waveAnnounce = 1.5
        bs.isBossWave   = phaseCfg and phaseCfg.isBossPhase or false
        bs.bossTimer    = 0
        bs.bossTimeout  = false
        bs.bossStarted  = false

        GameState.ResetHP()
        Spawner.Reset()
        Spawner.BuildQueue()
        return true
    end

    function adapter:OnDeath(bs)
        -- 死亡 = 试炼失败, 退出
        M.Exit()
        return false  -- 走默认死亡逻辑 (回到章节)
    end

    function adapter:OnTimeout(bs)
        -- 超时 = 试炼失败
        M.Exit()
        Particles.SpawnReactionText(bs.particles,
            bs.playerBattle.x, bs.playerBattle.y - 40,
            "时间耗尽, 试炼失败!", { 255, 80, 80 })
        return false
    end

    function adapter:GetDisplayName()
        local spireDef = WorldTierConfig.GetSpireUnlock(state_.spireId)
        local wtName   = spireDef and WorldTierConfig.Get(spireDef.unlocksWT).name or "?"
        local timeStr  = string.format("%d:%02d", math.floor(state_.timeRemain / 60), math.floor(state_.timeRemain % 60))
        return "尖塔试炼 " .. state_.spireId .. " [" .. timeStr .. "] 阶段 " .. state_.phase .. " 波 " .. state_.wave
    end

    function adapter:DrawWaveInfo(nvg, l, bs, alpha)
        local spireDef = WorldTierConfig.GetSpireUnlock(state_.spireId)
        local wtName   = spireDef and WorldTierConfig.Get(spireDef.unlocksWT).name or "?"

        -- 标题
        nvgFontSize(nvg, 20)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 220, 80, alpha))
        nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.28, "尖塔试炼 · 解锁 " .. wtName)

        -- 倒计时
        local timeStr = string.format("%d:%02d", math.floor(state_.timeRemain / 60), math.floor(state_.timeRemain % 60))
        nvgFontSize(nvg, 16)
        local timeColor = state_.timeRemain < 30 and nvgRGBA(255, 80, 80, alpha) or nvgRGBA(255, 255, 200, alpha)
        nvgFillColor(nvg, timeColor)
        nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.28 + 24, timeStr)

        -- 阶段/波次
        nvgFontSize(nvg, 13)
        nvgFillColor(nvg, nvgRGBA(200, 200, 200, alpha))
        local phaseNames = { "清扫层", "精英层", "守卫 Boss" }
        local phaseStr = (phaseNames[state_.phase] or "") .. " · 第 " .. state_.wave .. " 波"
        nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.28 + 42, phaseStr)
    end

    GameMode.Register("spireTrial", adapter)
end

-- ============================================================================
-- 存档域注册 (spireTrial 完成状态 + 世界层级)
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "spireTrial",
    keys  = { "spireTrial" },
    group = "misc",
    serialize = function(GS)
        local st = GS.spireTrial or { worldTier = 1, completed = {} }
        -- 将 completed table 序列化为数组 (JSON 友好)
        local comp = {}
        for i = 1, 3 do
            comp[i] = st.completed[i] or false
        end
        return {
            spireTrial = {
                worldTier = st.worldTier or 1,
                completed = comp,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.spireTrial then
            GS.spireTrial = GS.spireTrial or { worldTier = 1, completed = {} }
            GS.spireTrial.worldTier = data.spireTrial.worldTier or 1
            if data.spireTrial.completed then
                for i = 1, 3 do
                    GS.spireTrial.completed[i] = data.spireTrial.completed[i] or false
                end
            end
        end
    end,
})

-- ============================================================================
-- GameState 安装: 初始化 spireTrial 字段
-- ============================================================================

--- 安装到 GameState (由 GameState.Init 调用)
function M.Install(GS)
    if not GS.spireTrial then
        GS.spireTrial = {
            worldTier = 1,           -- 当前最高解锁的世界层级
            completed = {},          -- { [1]=bool, [2]=bool, [3]=bool }
        }
    end
end

return M
