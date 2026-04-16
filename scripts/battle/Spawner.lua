-- ============================================================================
-- battle/Spawner.lua - 敌人生成器 (关卡制)
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local GameMode         = require("GameMode")
local EnemyAnim        = require("battle.EnemyAnim")

local Spawner = {}

local spawnTimer_ = 0
local spawnQueue_ = {}   -- 当前波次待生成的怪物队列
local spawnIdx_   = 0    -- 当前队列中已生成的数量
local totalInWave_ = 0   -- 当前波次总怪物数
local stageTotalMonsters_ = 0  -- 当前关卡所有波次累计怪物总数

function Spawner.Reset()
    spawnTimer_ = 0.5
    spawnQueue_ = {}
    spawnIdx_   = 0
    totalInWave_ = 0
end

--- 重置并预计算当前关卡所有波次的怪物总数
function Spawner.ResetStageTotal()
    stageTotalMonsters_ = 0

    -- 特殊模式无法预计算，依赖 BuildQueue 累加
    local mode = GameMode.GetActive()
    if mode and mode.BuildSpawnQueue then return end

    local gs = GameState.stage
    local stageCfg, chapterCfg = StageConfig.GetStage(gs.chapter, gs.stage)
    if not stageCfg or not stageCfg.waves then return end

    local tagLevels = chapterCfg and chapterCfg.tagLevels or nil

    -- 检测是否为 Boss 关卡
    local hasBoss = false
    for _, wave in ipairs(stageCfg.waves) do
        if wave.monsters then
            for _, m in ipairs(wave.monsters) do
                local t = StageConfig.ResolveMonster(m.id, gs.chapter, tagLevels)
                if t and t.isBoss then hasBoss = true; break end
            end
        end
        if hasBoss then break end
    end

    if hasBoss then
        -- Boss 关卡：小怪上限 MAX_BOSS_MOBS + Boss 数量
        local MAX_BOSS_MOBS = 10
        local bossCount = 0
        local mobTotal  = 0
        for _, wave in ipairs(stageCfg.waves) do
            if wave.monsters then
                for _, entry in ipairs(wave.monsters) do
                    local t = StageConfig.ResolveMonster(entry.id, gs.chapter, tagLevels)
                    if t then
                        if t.isBoss then
                            bossCount = bossCount + entry.count
                        else
                            mobTotal = mobTotal + entry.count
                        end
                    end
                end
            end
        end
        stageTotalMonsters_ = math.min(mobTotal, MAX_BOSS_MOBS) + bossCount
    else
        -- 非 Boss 关卡：所有波次累加
        for _, wave in ipairs(stageCfg.waves) do
            if wave.monsters then
                for _, entry in ipairs(wave.monsters) do
                    stageTotalMonsters_ = stageTotalMonsters_ + entry.count
                end
            end
        end
    end
end

--- 构建当前波次的生成队列
function Spawner.BuildQueue()
    spawnQueue_ = {}
    spawnIdx_   = 0

    -- ── 特殊模式: 通过 GameMode 适配器构建队列 ──
    local mode = GameMode.GetActive()
    if mode and mode.BuildSpawnQueue then
        local queue = mode:BuildSpawnQueue()
        if queue then
            for _, entry in ipairs(queue) do
                table.insert(spawnQueue_, entry)
            end
        end
        totalInWave_ = #spawnQueue_
        stageTotalMonsters_ = stageTotalMonsters_ + totalInWave_
        return
    end

    local gs = GameState.stage
    local stageCfg, chapterCfg = StageConfig.GetStage(gs.chapter, gs.stage)
    if not stageCfg then return end

    -- 获取章节 tagLevels（家族编排章节使用）
    local tagLevels = chapterCfg and chapterCfg.tagLevels or nil

    --- 统一怪物解析：支持 MONSTERS 表 / 家族组合ID / Boss 原型
    local function resolveTemplate(mId)
        return StageConfig.ResolveMonster(mId, gs.chapter, tagLevels)
    end

    -- Boss 关卡：合并所有波次，小怪在前 Boss 在后，一次性出完
    local hasBoss = false
    if stageCfg.waves then
        for _, wave in ipairs(stageCfg.waves) do
            if wave.monsters then
                for _, m in ipairs(wave.monsters) do
                    local t = resolveTemplate(m.id)
                    if t and t.isBoss then hasBoss = true break end
                end
            end
            if hasBoss then break end
        end
    end

    if hasBoss then
        -- Boss 关卡：合并所有波次，小怪先出，Boss 最后
        local bossEntries = {}
        local mobEntries = {}
        for _, wave in ipairs(stageCfg.waves) do
            if wave.monsters then
                for _, entry in ipairs(wave.monsters) do
                    local template = resolveTemplate(entry.id)
                    if template then
                        if template.isBoss then
                            table.insert(bossEntries, { templateId = entry.id, template = template, count = entry.count })
                        else
                            table.insert(mobEntries, { templateId = entry.id, template = template, count = entry.count })
                        end
                    end
                end
            end
        end
        -- 小怪先入队（Boss关小怪上限10只）
        local MAX_BOSS_MOBS = 10
        local mobCount = 0
        for _, mob in ipairs(mobEntries) do
            for _ = 1, mob.count do
                if mobCount >= MAX_BOSS_MOBS then break end
                table.insert(spawnQueue_, { templateId = mob.templateId, template = mob.template })
                mobCount = mobCount + 1
            end
            if mobCount >= MAX_BOSS_MOBS then break end
        end
        -- Boss 最后入队
        for _, boss in ipairs(bossEntries) do
            for _ = 1, boss.count do
                table.insert(spawnQueue_, { templateId = boss.templateId, template = boss.template })
            end
        end
        -- 标记为单波制，跳过后续波次切换
        gs.waveIdx = #stageCfg.waves
    else
        -- 非 Boss 关卡：按原逻辑单波次生成
        local waveIdx = gs.waveIdx
        local waveCfg = stageCfg.waves[waveIdx]
        if not waveCfg then return end

        for _, entry in ipairs(waveCfg.monsters) do
            local template = resolveTemplate(entry.id)
            if template then
                for _ = 1, entry.count do
                    table.insert(spawnQueue_, {
                        templateId = entry.id,
                        template = template,
                    })
                end
            end
        end
    end

    totalInWave_ = #spawnQueue_
    -- 特殊模式路径：ResetStageTotal 跳过了预计算，需要在此累加
    -- 正常关卡路径：ResetStageTotal 已预计算完整总数，不再重复累加
end

function Spawner.IsWaveSpawnDone()
    return spawnIdx_ >= totalInWave_
end

function Spawner.GetTotalInWave()
    return totalInWave_
end

--- 获取当前关卡所有波次累计怪物总数
function Spawner.GetStageTotalMonsters()
    return stageTotalMonsters_
end

function Spawner.Update(dt, enemies, areaW, areaH)
    if spawnIdx_ >= totalInWave_ then return end

    -- 同屏存活上限检查：存活数 >= MAX_ALIVE_ENEMIES 时暂停生成
    local alive = 0
    for _, e in ipairs(enemies) do
        if not e.dead then alive = alive + 1 end
    end
    if alive >= Config.MAX_ALIVE_ENEMIES then return end

    spawnTimer_ = spawnTimer_ - dt
    if spawnTimer_ <= 0 then
        spawnTimer_ = 0.8  -- 每只怪生成间隔
        spawnIdx_ = spawnIdx_ + 1
        if spawnIdx_ <= totalInWave_ then
            Spawner.SpawnFromQueue(enemies, spawnIdx_, areaW, areaH)
        end
    end
end

function Spawner.SpawnFromQueue(enemies, idx, areaW, areaH)
    local entry = spawnQueue_[idx]
    if not entry then return end

    local template = entry.template

    -- 试炼模式: 使用队列中附带的 scaleMul 和 resistOverride
    local scaleMul
    local expScaleMul
    local resistOverride
    if entry.scaleMul then
        scaleMul = entry.scaleMul
        expScaleMul = entry.expScaleMul or scaleMul
        resistOverride = entry.resistOverride
    else
        local gs = GameState.stage
        scaleMul = StageConfig.GetScaleMul(gs.chapter, gs.stage)
        expScaleMul = scaleMul
    end

    local isBoss = template.isBoss or false

    -- 解析掉落模板 → 具体金币/掉率参数
    local dropTpl = Config.DROP_TEMPLATES[template.dropTemplate or "common"] or Config.DROP_TEMPLATES.common
    template.dropGoldMin    = dropTpl.goldDrop[1]
    template.dropGoldMax    = dropTpl.goldDrop[2]
    template.dropGoldChance = dropTpl.goldChance
    template.dropEquipChance = dropTpl.equipChance

    local hp  = math.floor(template.hp * scaleMul)
    local atk = math.floor(template.atk * scaleMul)

    -- 边缘随机位置
    local margin = 30
    local maxX = math.max(margin, math.floor(areaW - margin))
    local maxY = math.max(margin, math.floor(areaH - margin))
    local side = math.random(1, 4)
    local x, y
    if side == 1 then
        x = math.random(margin, maxX); y = margin
    elseif side == 2 then
        x = math.random(margin, maxX); y = areaH - margin
    elseif side == 3 then
        x = margin; y = math.random(margin, maxY)
    else
        x = areaW - margin; y = math.random(margin, maxY)
    end

    table.insert(enemies, {
        x = x, y = y,
        hp = hp, maxHp = hp,
        atk = atk,
        speed   = template.speed,
        radius  = template.radius or (isBoss and 28 or 16),
        expDrop = math.floor(template.expDrop * expScaleMul),
        goldMin = template.dropGoldMin or 2,
        goldMax = template.dropGoldMax or 7,
        goldChance  = template.dropGoldChance or 0.30,
        equipChance = template.dropEquipChance or 0.12,
        color   = { template.color[1], template.color[2], template.color[3] },
        image   = template.image,
        isBoss  = isBoss,
        dead    = false,
        def     = math.floor((template.def or 0) * scaleMul),
        atkTimer = 0,
        atkCd    = template.atkInterval or (isBoss and 1.5 or 2.0),
        atkRange = template.atkRange or 35,
        name    = template.name,
        knockbackVx = 0,
        knockbackVy = 0,
        -- 击退抗性 (weight: 1.0=普通, 2~3=精英, 3~5=Boss)
        weight  = template.weight or (isBoss and 3.0 or 1.0),
        -- 元素 & debuff 属性
        element     = template.element or "physical",
        antiHeal    = template.antiHeal or false,
        slowOnHit   = template.slowOnHit or 0,
        slowDuration = template.slowDuration or 0,
        -- 敌人身上被附着的元素 (玩家攻击触发)
        attachedElement = nil,
        attachedElementTimer = 0,
        -- 反应debuff
        defReduceRate = 0,   -- 防御降低比率
        defReduceTimer = 0,  -- 防御降低剩余时间
        elemWeakenRate = 0,  -- 元素抗性削弱比率
        elemWeakenTimer = 0, -- 元素抗性削弱剩余时间
        reactionDot = nil,   -- 反应DoT {dmgPerTick, tickRate, tickCD, timer}
        -- 世界Boss标记
        isWorldBoss  = entry.isWorldBoss or template.isWorldBoss or false,
        -- 特殊能力 (从模板透传)
        templateId   = entry.templateId,
        familyId     = template.familyId,
        behaviorId   = template.behaviorId,
        familyType   = template.familyType,
        eliteRank    = template.eliteRank,
        eliteAffixes = template.eliteAffixes,
        -- v3.1: 怪物等级 (用于 DEF K 缩放, 深渊/尖塔由 entry 携带)
        level        = entry.monsterLevel or template.level,
        defPierce    = template.defPierce or 0,
        packBonus    = template.packBonus or 0,
        packThreshold = template.packThreshold or 0,
        isRanged     = template.isRanged or false,
        deathExplode = template.deathExplode,
        hpRegenPct   = template.hpRegen or 0,
        hpRegenInterval = template.hpRegenInterval or 0,
        hpRegenTimer = 0,
        -- Boss 技能
        barrage      = template.barrage,
        barrageTimer = template.barrage and template.barrage.interval or 0,
        iceArmor     = template.iceArmor,
        iceArmorActive = false,
        iceArmorTimer = 0,
        iceArmorCdTimer = 0,
        dragonBreath = template.dragonBreath,
        breathTimer  = template.dragonBreath and template.dragonBreath.interval or 0,
        frozenField  = template.frozenField,
        frozenFieldActive = false,
        frozenFieldTimer = 0,
        frozenFieldCdTimer = 0,
        iceRegen     = template.iceRegen,
        -- 狂暴 (通用 Boss)
        enraged      = false,
        -- 第四章新机制
        resist       = resistOverride or template.resist,  -- 试炼模式覆盖 / 原模板抗性
        lifesteal    = template.lifesteal or 0,   -- 敌人吸血比率
        healAura     = template.healAura,         -- 治疗光环 { pct, interval, radius }
        healAuraTimer = 0,
        summon       = template.summon,           -- 召唤 { interval, monsterId, count }
        summonTimer  = template.summon and template.summon.interval or 0,
        firstStrikeMul = template.firstStrikeMul, -- 首击倍率
        firstStrikeDone = false,
        -- 点燃DoT (套装触发)
        igniteDot    = nil,                       -- { dmgPerTick, tickRate, tickCD, timer }
        -- 第五章新机制
        splitOnDeath = template.splitOnDeath,      -- 死亡分裂 { childId, count }
        corrosion    = template.corrosion,          -- 腐蚀 { defReducePct, stackMax, duration }
        inkBlind     = template.inkBlind,            -- 墨汁致盲 { atkReducePct, duration }
        -- 第六章新机制
        chargeUp     = template.chargeUp,           -- 充能 { stackMax, dmgMul, resetOnTrigger, isAOE?, aoeRadius? }
        chargeUpStacks = 0,                         -- 当前充能层数
        chainLightning = template.chainLightning,   -- 链弹 { bounces, dmgMul, element, range }
        sandStorm    = template.sandStorm,           -- 沙暴 { critReducePct, duration }
        -- 第七章新机制
        venomStack   = template.venomStack,          -- 毒蛊叠加 { dmgPctPerStack, stackMax, duration }
        sporeCloud   = template.sporeCloud,          -- 孢子云 { atkSpeedReducePct, duration }
        -- 第15章新机制
        burnStack    = template.burnStack,           -- 灼烧叠层 { dmgPct, atkSpdReduce, maxStacks, duration }
        scorchOnHit  = template.scorchOnHit,         -- 焚灼命中 { dmgAmpPct, maxStacks, duration }
        burnAura     = template.burnAura,            -- 灼热光环 { radius, interval }
        burnAuraTimer = template.burnAura and template.burnAura.interval or 0,
        damageReflect = template.damageReflect,      -- 受击反弹 { element, pct }
        -- 第16章新机制
        drenchStack  = template.drenchStack,         -- 浸蚀叠层 { perStack, maxStacks, duration }
        -- 模板系统 Boss (第13章+)
        phases       = template.phases,              -- 阶段技能配置 (BossSkillTemplates)
    })

    -- ── 家族/精英 后处理 ──
    local newEnemy = enemies[#enemies]
    -- 设置 familyType (如果模板未预设)
    if not newEnemy.familyType and newEnemy.familyId then
        local FamilyConfig = require("FamilyConfig")
        newEnemy.familyType = FamilyConfig.GetFamilyType(newEnemy.familyId, newEnemy.behaviorId)
    end
    -- 精英掷骰
    local EliteSystem = require("battle.EliteSystem")
    local chapter = GameState.stage and GameState.stage.chapter or 1
    EliteSystem.RollElite(newEnemy, chapter)
    -- 家族生成钩子
    local FamilyMechanics = require("battle.FamilyMechanics")
    FamilyMechanics.OnEnemySpawned({ enemies = enemies }, newEnemy)
    -- 初始化代码动画
    EnemyAnim.InitAnim(newEnemy)
end

return Spawner
