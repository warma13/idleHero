-- ============================================================================
-- AbyssMode.lua - 深渊模式 (动态等级体系)
--
-- 职责: 无限层推进、DynamicLevel 驱动怪物生成、Boss限时、死亡重试
-- 依赖: AbyssConfig, DynamicLevel, MonsterFamilies, GameState, GameMode
-- 设计文档: docs/数值/怪物家族系统设计.md §十一
-- ============================================================================

local GameState       = require("GameState")
local AbyssConfig     = require("AbyssConfig")
local DynamicLevel    = require("DynamicLevel")
local MonsterFamilies = require("MonsterFamilies")
local SaveSystem      = require("SaveSystem")

local AbyssMode = {}

-- ============================================================================
-- 内部: 获取当前世界层级 (GameState 尚未集成时 fallback 为 1)
-- ============================================================================

local function getWorldTierId()
    if GameState.spireTrial and GameState.spireTrial.worldTier then
        return GameState.spireTrial.worldTier
    end
    return 1
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 当前是否在深渊模式中
function AbyssMode.IsActive()
    return GameState.abyss.active
end

--- 获取当前层数
function AbyssMode.GetFloor()
    return GameState.abyss.floor
end

--- 获取历史最高层
function AbyssMode.GetMaxFloor()
    return GameState.abyss.maxFloor
end

-- ============================================================================
-- 进入 / 退出
-- ============================================================================

--- 进入深渊模式（从上次退出的层数继续）
function AbyssMode.Enter()
    local ab = GameState.abyss
    ab.savedStage = {
        chapter = GameState.stage.chapter,
        stage   = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }
    ab.active   = true
    -- 继续上次退出的层数，首次进入为 1
    if ab.floor < 1 then ab.floor = 1 end
    ab.killCount = 0
    print("[AbyssMode] Entered abyss, floor " .. ab.floor)
end

--- 退出深渊模式, 恢复章节进度
function AbyssMode.Exit()
    local ab = GameState.abyss
    if ab.savedStage then
        GameState.stage.chapter = ab.savedStage.chapter
        GameState.stage.stage   = ab.savedStage.stage
        GameState.stage.waveIdx = ab.savedStage.waveIdx
    end
    ab.active    = false
    ab.killCount = 0
    SaveSystem.MarkDirty()
    print("[AbyssMode] Exited abyss, restored stage " .. GameState.stage.chapter .. "-" .. GameState.stage.stage)
end

-- ============================================================================
-- 推层
-- ============================================================================

--- 推进到下一层
function AbyssMode.AdvanceFloor()
    local ab = GameState.abyss
    ab.floor = ab.floor + 1
    ab.killCount = 0
    if ab.floor > ab.maxFloor then
        ab.maxFloor = ab.floor
    end
    SaveSystem.MarkDirty()
    print("[AbyssMode] Advanced to floor " .. ab.floor)
end

-- ============================================================================
-- 怪物生成队列 (动态等级体系)
-- ============================================================================

--- 内部: 从 MonsterFamilies 解析怪物并计算深渊属性
---@param monsterDef table  { familyId, behaviorId, monsterId, [raceTier], [name] }
---@param monsterLevel number
---@param layer number 深渊层数
---@param roleName string  "normal"|"dungeon_boss"
---@param isBoss boolean
---@return table entry Spawner 兼容条目
function AbyssMode._makeEntry(monsterDef, monsterLevel, layer, roleName, isBoss)
    -- 通过家族系统解析怪物模板 (获取贴图/抗性/标签/种族基准)
    local chapter  = GameState.stage.chapter or 1
    local template = MonsterFamilies.Resolve(
        monsterDef.familyId,
        monsterDef.behaviorId,
        chapter,
        nil,           -- tagLevels: 深渊不使用章节标签等级
        monsterDef.monsterId
    )

    -- 种族基准值 (已由 MonsterFamilies.Resolve 注入 raceBaseHP/ATK/DEF)
    local raceHP  = template.raceBaseHP  or template.hp  or 110
    local raceATK = template.raceBaseATK or template.atk or 13
    local raceDEF = template.raceBaseDEF or template.def or 15

    -- Boss 的 raceTier 可以被主题定义覆盖
    if isBoss and monsterDef.raceTier then
        local overrideTier = MonsterFamilies.RACE_TIERS[monsterDef.raceTier]
        if overrideTier then
            raceHP  = overrideTier.hp
            raceATK = overrideTier.atk
            raceDEF = overrideTier.def
        end
    end

    -- 通过 AbyssConfig 统一计算最终属性
    template.hp     = AbyssConfig.CalcHP(raceHP, monsterLevel, layer, roleName)
    template.atk    = AbyssConfig.CalcATK(raceATK, monsterLevel, layer, roleName)
    template.def    = raceDEF   -- DEF 为固定值，不随等级成长
    template.isBoss = isBoss
    template.level  = monsterLevel

    -- Boss 名称覆盖
    if isBoss and monsterDef.name then
        template.name = monsterDef.name
    end

    -- 深渊怪物经验/金币 (基于等级)
    local baseExp   = template.expDrop or 10
    template.expDrop = math.floor(baseExp * DynamicLevel.GrowthHP(monsterLevel) * 0.3)
    template.dropTemplate = isBoss and "boss" or "common"

    return {
        templateId = monsterDef.monsterId or (monsterDef.familyId .. "_" .. monsterDef.behaviorId),
        template   = template,
        monsterLevel = monsterLevel,
    }
end

--- 构建当前层的生成队列 (Spawner 兼容格式)
---@return table[] queue
function AbyssMode.BuildQueue()
    local floor        = GameState.abyss.floor
    local playerLevel  = GameState.player.level or 1
    local worldTierId  = getWorldTierId()
    local monsterLevel = AbyssConfig.CalcLevel(playerLevel, floor, worldTierId)
    local isBoss       = AbyssConfig.IsBossFloor(floor)
    local theme        = AbyssConfig.GetTheme(floor)
    local queue        = {}

    if isBoss then
        -- Boss 层: 先出几只小怪，再出 Boss
        local mobCount = 5
        for _ = 1, mobCount do
            local mDef  = AbyssConfig.PickMonster(theme)
            local entry = AbyssMode._makeEntry(mDef, monsterLevel, floor, AbyssConfig.MOB_ROLE, false)
            table.insert(queue, entry)
        end
        -- Boss
        local entry = AbyssMode._makeEntry(theme.boss, monsterLevel, floor, AbyssConfig.BOSS_ROLE, true)
        entry.template.isBoss = true
        table.insert(queue, entry)
    else
        -- 普通层: KILL_TARGET 只怪
        for _ = 1, AbyssConfig.KILL_TARGET do
            local mDef  = AbyssConfig.PickMonster(theme)
            local entry = AbyssMode._makeEntry(mDef, monsterLevel, floor, AbyssConfig.MOB_ROLE, false)
            table.insert(queue, entry)
        end
    end

    return queue
end

-- ============================================================================
-- GameMode 适配器 (尾部注册)
-- ============================================================================

do
    local GameMode  = require("GameMode")
    local Particles = require("battle.Particles")

    local adapter = {}

    -- ── 生命周期 ──
    adapter.background = "image/battle_bg_abyss_20260324034310.png"

    function adapter:OnEnter()
        AbyssMode.Enter()
        return true
    end

    function adapter:OnExit()
        AbyssMode.Exit()
    end

    --- 波次公告渲染
    function adapter:DrawWaveInfo(nvg, l, bs, alpha)
        local floor = AbyssMode.GetFloor()
        if bs.isBossWave then
            nvgFontSize(nvg, 22)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(180, 60, 255, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32, "深渊 BOSS!")
            nvgFontSize(nvg, 14)
            nvgFillColor(nvg, nvgRGBA(200, 150, 255, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32 + 24, "第 " .. floor .. " 层")
        else
            nvgFontSize(nvg, 16)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(180, 140, 255, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32, "深渊 · 第 " .. floor .. " 层")
        end
    end

    -- ── 战斗 ──

    function adapter:BuildSpawnQueue()
        return AbyssMode.BuildQueue()
    end

    function adapter:GetBattleConfig()
        local floor   = AbyssMode.GetFloor()
        local isBoss  = AbyssConfig.IsBossFloor(floor)
        return {
            isBossWave            = isBoss,
            bossTimerMax          = isBoss and AbyssConfig.BOSS_TIMER or 0,
            startTimerImmediately = false,
        }
    end

    function adapter:SkipNormalExpDrop()
        return false   -- 深渊保留正常掉落
    end

    function adapter:OnEnemyKilled(bs, enemy)
        local ab = GameState.abyss
        ab.killCount = ab.killCount + 1

        -- Boss 击杀 → 通关
        if enemy.isBoss then
            -- 清残余
            for _, e in ipairs(bs.enemies) do
                if not e.dead and e ~= enemy then e.dead = true end
            end
            bs._waveComplete = true
            bs._restTimer    = 1.5

            -- 深渊Boss掉落: 深渊之心 + 怨魂碎片
            local heartDrop = 1 + math.floor(ab.floor / 10)   -- 每10层+1
            local wraithDrop = 2 + math.floor(ab.floor / 5)   -- 每5层+2
            GameState.AddMaterials({ abyssHeart = heartDrop, wraith = wraithDrop })
            print("[AbyssMode] Boss drop: abyssHeart=" .. heartDrop .. " wraith=" .. wraithDrop)

            Particles.SpawnReactionText(bs.particles,
                bs.playerBattle.x, bs.playerBattle.y - 40,
                "深渊 " .. ab.floor .. " 层通过!", { 180, 120, 255 })
            return true
        end

        -- 普通层: 击杀够了 → 通关
        if not AbyssConfig.IsBossFloor(ab.floor) and ab.killCount >= AbyssConfig.KILL_TARGET then
            bs._waveComplete = true
            bs._restTimer    = 1.0

            -- 普通层掉落: 怨魂碎片
            local wraithDrop = 1 + math.floor(ab.floor / 10)
            GameState.AddMaterial("wraith", wraithDrop)
            print("[AbyssMode] Floor clear drop: wraith=" .. wraithDrop)

            Particles.SpawnReactionText(bs.particles,
                bs.playerBattle.x, bs.playerBattle.y - 40,
                "深渊 " .. ab.floor .. " 层通过!", { 180, 120, 255 })
            return true
        end

        return false  -- 未通关，走默认掉落逻辑
    end

    function adapter:CheckWaveComplete(bs)
        return false
    end

    function adapter:OnNextWave(bs)
        local Spawner = require("battle.Spawner")

        AbyssMode.AdvanceFloor()
        local floor   = AbyssMode.GetFloor()
        local isBoss  = AbyssConfig.IsBossFloor(floor)

        bs.enemies      = {}
        bs.waveAnnounce = 1.5
        bs.isBossWave   = isBoss
        bs.bossTimer    = 0
        bs.bossTimeout  = false
        bs.bossStarted  = false
        if isBoss then
            bs.bossTimerMax = AbyssConfig.BOSS_TIMER
        end

        GameState.abyss.killCount = 0
        GameState.ResetHP()
        Spawner.Reset()
        Spawner.BuildQueue()
        return true
    end

    function adapter:OnDeath(bs)
        -- 深渊死亡: 原地重试当前层
        local Spawner = require("battle.Spawner")

        GameState.abyss.killCount = 0
        bs.isPlayerDead    = false
        bs.playerDeadTimer = 0
        bs.enemies      = {}
        bs.particles    = {}
        bs.bossTimeout  = false
        bs.bossTimer    = 0
        bs.bossStarted  = false
        bs.waveAnnounce = 2.0

        GameState.ResetHP()
        Spawner.Reset()
        Spawner.BuildQueue()

        Particles.SpawnReactionText(bs.particles,
            bs.playerBattle.x, bs.playerBattle.y - 40,
            "重试 第 " .. AbyssMode.GetFloor() .. " 层", { 255, 200, 100 })
        return true
    end

    function adapter:OnTimeout(bs)
        -- Boss 超时: 和死亡一样，原地重试
        return self:OnDeath(bs)
    end

    function adapter:IsTimerMode()
        return false
    end

    function adapter:GetDisplayName()
        local floor = AbyssMode.GetFloor()
        local ab    = GameState.abyss
        if AbyssConfig.IsBossFloor(floor) then
            return "深渊 第 " .. floor .. " 层 (Boss)"
        else
            return "深渊 第 " .. floor .. " 层  " .. ab.killCount .. "/" .. AbyssConfig.KILL_TARGET
        end
    end

    GameMode.Register("abyss", adapter)
end

-- ============================================================================
-- 存档域注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "abyss",
    keys  = { "abyss" },
    group = "misc",
    serialize = function(GS)
        return {
            abyss = {
                floor    = GS.abyss.floor,
                maxFloor = GS.abyss.maxFloor,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.abyss then
            GS.abyss.floor    = data.abyss.floor or 1
            GS.abyss.maxFloor = data.abyss.maxFloor or 0
        end
    end,
})

return AbyssMode
