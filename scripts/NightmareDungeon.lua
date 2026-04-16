-- ============================================================================
-- NightmareDungeon.lua - 噩梦地牢 (终局装备刷取副本)
--
-- 设计:
--   1. 消耗钥石进入, 层级1-100递进
--   2. 三阶段制: 扫荡 → 精英层 → 守护者Boss
--   3. 词缀系统: 随机正面(玩家增益) + 负面(怪物增强/玩家惩罚)
--   4. 高roll装备出口, 层级越高掉落品质越好
--   5. 通关后100%获得下一级钥石, 形成自循环
-- ============================================================================

local Config           = require("Config")
local GameState        = require("GameState")
local StageConfig      = require("StageConfig")
local MonsterFamilies  = require("MonsterFamilies")
local SaveSystem       = require("SaveSystem")

local NightmareDungeon = {}

-- ============================================================================
-- 配置引用
-- ============================================================================

local ND = Config.NIGHTMARE_DUNGEON

-- ============================================================================
-- 噩梦主题定义 (按钥石元素 → 怪物家族映射)
-- 格式与 AbyssConfig.THEMES 一致, 通过 MonsterFamilies.Resolve 加载
-- ============================================================================

local NIGHTMARE_THEMES = {
    -- ── 火元素钥石 → 火元素族 + 野兽族 ──
    fire = {
        name = "烈焰深渊",
        mobs = {
            { familyId = "elemental_fire", behaviorId = "swarm",   monsterId = "lava_lizard"   },
            { familyId = "elemental_fire", behaviorId = "glass",   monsterId = "volcano_moth"  },
            { familyId = "beast",          behaviorId = "bruiser",  monsterId = "lava_hound"    },
        },
        elites = {
            { familyId = "elemental_fire", behaviorId = "tank",     monsterId = "rock_scorpion" },
            { familyId = "elemental_fire", behaviorId = "bruiser",  monsterId = "lava_hound"    },
        },
        champions = {
            { familyId = "elemental_fire", behaviorId = "caster",   monsterId = "pyro_mage"     },
        },
        boss = {
            familyId   = "elemental_fire",
            behaviorId = "tank",
            monsterId  = "inferno_titan",
            name       = "噩梦守护者·焚渊",
            raceTier   = "D",
        },
    },

    -- ── 冰元素钥石 → 冰元素族 ──
    ice = {
        name = "永冻冰窟",
        mobs = {
            { familyId = "elemental_ice", behaviorId = "swarm",   monsterId = "frost_imp"      },
            { familyId = "elemental_ice", behaviorId = "glass",   monsterId = "ice_wraith"     },
            { familyId = "elemental_ice", behaviorId = "bruiser",  monsterId = "snow_wolf"      },
        },
        elites = {
            { familyId = "elemental_ice", behaviorId = "tank",     monsterId = "frost_golem"    },
            { familyId = "elemental_ice", behaviorId = "caster",   monsterId = "cryo_mage"      },
        },
        champions = {
            { familyId = "elemental_ice", behaviorId = "bruiser",  monsterId = "frost_behemoth" },
        },
        boss = {
            familyId   = "elemental_ice",
            behaviorId = "tank",
            monsterId  = "glacier_titan",
            name       = "噩梦守护者·寒渊",
            raceTier   = "D",
        },
    },

    -- ── 毒元素钥石 → 毒元素族 + 野兽族 ──
    poison = {
        name = "腐蚀深渊",
        mobs = {
            { familyId = "elemental_poison", behaviorId = "swarm",    monsterId = "plague_beetle"   },
            { familyId = "elemental_poison", behaviorId = "glass",    monsterId = "jungle_panther"  },
            { familyId = "beast",            behaviorId = "debuffer",  monsterId = "swamp_frog"      },
        },
        elites = {
            { familyId = "elemental_poison", behaviorId = "debuffer",  monsterId = "vine_strangler" },
            { familyId = "elemental_poison", behaviorId = "bruiser",   monsterId = "thorn_viper"    },
        },
        champions = {
            { familyId = "elemental_poison", behaviorId = "caster",    monsterId = "swamp_shaman"   },
        },
        boss = {
            familyId   = "elemental_poison",
            behaviorId = "tank",
            monsterId  = "ironbark_treant",
            name       = "噩梦守护者·蚀渊",
            raceTier   = "D",
        },
    },

    -- ── 奥术钥石 → 奥术族 + 不死族 ──
    arcane = {
        name = "虚空裂隙",
        mobs = {
            { familyId = "arcane", behaviorId = "swarm",   monsterId = "entropy_mote"     },
            { familyId = "undead", behaviorId = "glass",   monsterId = "shadow_assassin"  },
            { familyId = "arcane", behaviorId = "glass",   monsterId = "sand_phantom"     },
        },
        elites = {
            { familyId = "undead", behaviorId = "bruiser",  monsterId = "cursed_knight"    },
            { familyId = "arcane", behaviorId = "bruiser",  monsterId = "rift_ripper"      },
        },
        champions = {
            { familyId = "arcane", behaviorId = "caster",   monsterId = "phase_weaver"     },
        },
        boss = {
            familyId   = "arcane",
            behaviorId = "tank",
            monsterId  = "void_colossus",
            name       = "噩梦守护者·虚渊",
            raceTier   = "D",
        },
    },
}

-- ============================================================================
-- 运行时状态 (不存档)
-- ============================================================================

NightmareDungeon.active      = false
NightmareDungeon.fightResult = nil

-- 当前钥石信息
local currentSigil = nil  -- { tier, affixes = {positives, negatives}, element }

-- 战斗临时状态
local fight = {
    phase        = 1,       -- 当前阶段 (1-3)
    killCount    = 0,       -- 当前阶段击杀数
    totalKills   = 0,       -- 总击杀数
    phaseTargets = {},      -- { [1]=N, [2]=N, [3]=N } 每阶段需击杀数
    spawnCount   = 0,       -- 已生成数
    totalMonsters = 0,      -- 总怪物数
    elapsedTime  = 0,       -- 已用时间
    timeLimit    = 0,       -- 总限时
    monsterMods  = {},      -- 怪物词缀修饰
    playerMods   = {},      -- 玩家词缀修饰
}

-- 进入前保存的关卡状态
NightmareDungeon._savedStage = nil

-- ============================================================================
-- 钥石管理 (简化版: 使用 GameState.bag 存储钥石数量, 额外属性存在内存列表)
-- ============================================================================

-- 钥石列表 (内存维护, 存档保存)
-- GameState.nightmareDungeon.sigils = { {tier=5, positives={"empowered"}, negatives={"armored"}, element="fire"}, ... }

--- 获取词缀数量规则
---@param tier number
---@return number positive, number negative
local function getAffixCounts(tier)
    for _, bracket in ipairs(ND.AFFIX_BRACKETS) do
        if tier <= bracket.maxTier then
            return bracket.positive, bracket.negative
        end
    end
    local last = ND.AFFIX_BRACKETS[#ND.AFFIX_BRACKETS]
    return last.positive, last.negative
end

--- 随机抽取不重复词缀
---@param pool table 词缀定义列表
---@param count number 抽取数量
---@return table affixIds
local function randomAffixes(pool, count)
    if count <= 0 then return {} end
    local indices = {}
    for i = 1, #pool do indices[i] = i end
    -- Fisher-Yates shuffle
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end
    local result = {}
    for i = 1, math.min(count, #indices) do
        table.insert(result, pool[indices[i]].id)
    end
    return result
end

--- 生成一枚钥石
---@param tier number 层级
---@return table sigil
function NightmareDungeon.GenerateSigil(tier)
    tier = math.max(1, math.min(ND.MAX_TIER, tier))
    local posCount, negCount = getAffixCounts(tier)
    local positives = randomAffixes(ND.POSITIVE_AFFIXES, posCount)
    local negatives = randomAffixes(ND.NEGATIVE_AFFIXES, negCount)
    local elements = { "fire", "ice", "poison", "arcane" }
    local element = elements[math.random(1, #elements)]
    return {
        tier = tier,
        positives = positives,
        negatives = negatives,
        element = element,
    }
end

--- 添加钥石到背包
---@param sigil table
function NightmareDungeon.AddSigil(sigil)
    NightmareDungeon.EnsureState()
    table.insert(GameState.nightmareDungeon.sigils, sigil)
    SaveSystem.MarkDirty()
end

--- 移除钥石
---@param index number 在 sigils 列表中的索引
function NightmareDungeon.RemoveSigil(index)
    NightmareDungeon.EnsureState()
    table.remove(GameState.nightmareDungeon.sigils, index)
    SaveSystem.MarkDirty()
end

--- 获取所有钥石
---@return table sigils
function NightmareDungeon.GetSigils()
    NightmareDungeon.EnsureState()
    return GameState.nightmareDungeon.sigils
end

--- 获取钥石数量
---@return number
function NightmareDungeon.GetSigilCount()
    NightmareDungeon.EnsureState()
    return #GameState.nightmareDungeon.sigils
end

-- ============================================================================
-- 存档状态管理
-- ============================================================================

function NightmareDungeon.EnsureState()
    if not GameState.nightmareDungeon then
        GameState.nightmareDungeon = {
            totalRuns      = 0,
            maxTierCleared = 0,
            sigils         = {},   -- 钥石列表
            adSigilDate    = "",   -- 广告获取钥石日期
            adSigilCount   = 0,    -- 当日已看广告次数
        }
    end
    if not GameState.nightmareDungeon.sigils then
        GameState.nightmareDungeon.sigils = {}
    end
end

-- ============================================================================
-- 看广告获取钥石
-- ============================================================================

local function getTodayStr()
    return os.date("%Y-%m-%d", os.time())
end

--- 获取今日已看广告次数
---@return number
function NightmareDungeon.GetAdSigilCount()
    NightmareDungeon.EnsureState()
    local nd = GameState.nightmareDungeon
    if nd.adSigilDate ~= getTodayStr() then return 0 end
    return nd.adSigilCount or 0
end

--- 获取今日剩余广告次数
---@return number
function NightmareDungeon.GetAdSigilRemaining()
    return math.max(0, ND.AD_SIGIL_DAILY_MAX - NightmareDungeon.GetAdSigilCount())
end

--- 看广告获取钥石 (生成层级基于已通关最高层)
---@param callback function|nil 成功回调
function NightmareDungeon.WatchAdForSigil(callback)
    if NightmareDungeon.GetAdSigilRemaining() <= 0 then
        local Toast = require("ui.FloatTip")
        if Toast and Toast.Warn then Toast.Warn("今日广告次数已用完") end
        return
    end

    local ok, err = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        sdk:ShowRewardVideoAd(function(result)
            if result.success then
                NightmareDungeon.EnsureState()
                local nd = GameState.nightmareDungeon
                local today = getTodayStr()
                if nd.adSigilDate ~= today then
                    nd.adSigilDate = today
                    nd.adSigilCount = 0
                end
                nd.adSigilCount = (nd.adSigilCount or 0) + 1

                -- 钥石层级: 基于已通关最高层 +1~3, 首次为 Lv.1
                local maxCleared = nd.maxTierCleared or 0
                local tier = maxCleared <= 0 and 1
                    or math.min(ND.MAX_TIER, maxCleared + math.random(ND.SIGIL_TIER_UP_MIN, ND.SIGIL_TIER_UP_MAX))
                local sigil = NightmareDungeon.GenerateSigil(tier)
                NightmareDungeon.AddSigil(sigil)
                SaveSystem.SaveNow()
                print("[NightmareDungeon] Ad sigil granted: Lv." .. tier .. " (" .. nd.adSigilCount .. "/" .. ND.AD_SIGIL_DAILY_MAX .. ")")
                if callback then callback(sigil) end
            else
                if result.msg == "embed manual close" then
                    print("[NightmareDungeon] Ad closed early")
                else
                    print("[NightmareDungeon] Ad failed: " .. tostring(result.msg))
                end
            end
        end)
    end)

    if not ok then
        print("[NightmareDungeon] Ad SDK error: " .. tostring(err))
        -- SDK 不可用时直接发放 (开发/测试环境)
        NightmareDungeon.EnsureState()
        local nd = GameState.nightmareDungeon
        local today = getTodayStr()
        if nd.adSigilDate ~= today then
            nd.adSigilDate = today
            nd.adSigilCount = 0
        end
        nd.adSigilCount = (nd.adSigilCount or 0) + 1
        local maxCleared = nd.maxTierCleared or 0
        local tier = maxCleared <= 0 and 1
            or math.min(ND.MAX_TIER, maxCleared + math.random(ND.SIGIL_TIER_UP_MIN, ND.SIGIL_TIER_UP_MAX))
        local sigil = NightmareDungeon.GenerateSigil(tier)
        NightmareDungeon.AddSigil(sigil)
        SaveSystem.SaveNow()
        print("[NightmareDungeon] [DEV] Ad sigil granted (no SDK): Lv." .. tier)
        if callback then callback(sigil) end
    end
end

--- 是否已解锁
---@return boolean unlocked
---@return string|nil reason
function NightmareDungeon.IsUnlocked()
    return true, nil
end

--- 是否可进入
---@return boolean canEnter
---@return string|nil reason
function NightmareDungeon.CanEnter()
    local unlocked, reason = NightmareDungeon.IsUnlocked()
    if not unlocked then return false, reason end

    if NightmareDungeon.GetSigilCount() <= 0 then
        return false, "没有噩梦钥石"
    end
    return true, nil
end

-- ============================================================================
-- 词缀查找工具
-- ============================================================================

--- 通过ID获取词缀定义
---@param affixId string
---@return table|nil def
local function getAffixDef(affixId)
    for _, def in ipairs(ND.POSITIVE_AFFIXES) do
        if def.id == affixId then return def end
    end
    for _, def in ipairs(ND.NEGATIVE_AFFIXES) do
        if def.id == affixId then return def end
    end
    return nil
end

--- 获取掉落分档
---@param tier number
---@return table bracket
local function getLootTier(tier)
    for _, lt in ipairs(ND.LOOT_TIERS) do
        if tier <= lt.maxTier then return lt end
    end
    return ND.LOOT_TIERS[#ND.LOOT_TIERS]
end

--- 获取Boss品质权重
---@param tier number
---@return table weights {blue, purple, orange}
local function getBossQualityWeights(tier)
    for _, qt in ipairs(ND.BOSS_QUALITY_TIERS) do
        if tier <= qt.maxTier then return qt.weights end
    end
    return ND.BOSS_QUALITY_TIERS[#ND.BOSS_QUALITY_TIERS].weights
end

--- 计算层级缩放倍率 (渐近线模型)
---@param tier number
---@return number tierMul
local function calcTierMul(tier)
    return 1.0 + ND.TIER_SCALE_MAX * tier / (tier + ND.TIER_SCALE_K)
end

--- 计算时间限制
---@param tier number
---@return number seconds
local function calcTimeLimit(tier)
    local t = ND.TIME_BASE + ND.TIME_PER_TIER * tier
    return math.min(t, ND.TIME_MAX or 1200)
end

-- ============================================================================
-- 战斗入口/退出
-- ============================================================================

--- 进入噩梦地牢
---@param sigilIndex number 钥石在列表中的索引
---@return boolean success
function NightmareDungeon.EnterFight(sigilIndex)
    NightmareDungeon.EnsureState()

    local sigils = GameState.nightmareDungeon.sigils
    if not sigils[sigilIndex] then
        print("[NightmareDungeon] Invalid sigil index: " .. tostring(sigilIndex))
        return false
    end

    -- 保存并消耗钥石
    currentSigil = sigils[sigilIndex]
    table.remove(sigils, sigilIndex)

    -- 保存当前关卡状态
    NightmareDungeon._savedStage = {
        chapter = GameState.stage.chapter,
        stage   = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }

    -- 解析词缀效果
    fight.monsterMods = {}
    fight.playerMods  = {}
    local allAffixes = {}
    for _, id in ipairs(currentSigil.positives or {}) do
        table.insert(allAffixes, id)
        local def = getAffixDef(id)
        if def and def.stats then
            for k, v in pairs(def.stats) do
                fight.playerMods[k] = (fight.playerMods[k] or 0) + v
            end
        end
    end
    for _, id in ipairs(currentSigil.negatives or {}) do
        table.insert(allAffixes, id)
        local def = getAffixDef(id)
        if def then
            if def.target == "monster" then
                for k, v in pairs(def.stats or {}) do
                    fight.monsterMods[k] = (fight.monsterMods[k] or 0) + v
                end
            else
                for k, v in pairs(def.stats or {}) do
                    fight.playerMods[k] = (fight.playerMods[k] or 0) + v
                end
            end
        end
    end

    -- 计算阶段目标击杀数
    local tier = currentSigil.tier
    local countMul = 1.0 + (fight.monsterMods.countMul or 0)
    fight.phaseTargets = {}
    fight.totalMonsters = 0
    for i, phase in ipairs(ND.PHASES) do
        local mobs = math.floor((phase.mobBase + tier * (phase.mobPerTier or 0)) * countMul)
        local elites = math.floor((phase.eliteBase or 0) + tier * (phase.elitePerTier or 0))
        local champs = math.floor((phase.champBase or 0) + tier * (phase.champPerTier or 0))
        local boss = phase.bossCount or 0
        local total = mobs + elites + champs + boss
        fight.phaseTargets[i] = {
            total = total,
            mobs = mobs,
            elites = elites,
            champs = champs,
            boss = boss,
        }
        fight.totalMonsters = fight.totalMonsters + total
    end

    -- 初始化战斗状态
    fight.phase      = 1
    fight.killCount  = 0
    fight.totalKills = 0
    fight.spawnCount = 0
    fight.elapsedTime = 0
    fight.timeLimit  = calcTimeLimit(tier)

    NightmareDungeon.active      = true
    NightmareDungeon.fightResult = nil

    -- 更新统计
    GameState.nightmareDungeon.totalRuns = (GameState.nightmareDungeon.totalRuns or 0) + 1

    print("[NightmareDungeon] Fight started! Tier=" .. tier
        .. " Affixes: +" .. table.concat(currentSigil.positives or {}, ",")
        .. " -" .. table.concat(currentSigil.negatives or {}, ",")
        .. " TimeLimit=" .. fight.timeLimit .. "s"
        .. " TotalMonsters=" .. fight.totalMonsters)
    return true
end

--- 击杀回调
---@param enemy table
function NightmareDungeon.OnEnemyKilled(enemy)
    if not NightmareDungeon.active then return end

    fight.killCount  = fight.killCount + 1
    fight.totalKills = fight.totalKills + 1
end

--- 检查当前阶段是否完成, 若完成则推进到下一阶段
---@return boolean dungeonComplete 是否通关
function NightmareDungeon.CheckPhaseComplete()
    if not NightmareDungeon.active then return false end

    local target = fight.phaseTargets[fight.phase]
    if not target then return true end

    if fight.killCount >= target.total then
        if fight.phase >= #ND.PHASES then
            -- 全部阶段完成 → 通关
            return true
        else
            -- 推进到下一阶段
            fight.phase = fight.phase + 1
            fight.killCount = 0
            fight.spawnCount = 0
            print("[NightmareDungeon] Phase " .. fight.phase .. " started!")
        end
    end
    return false
end

--- 获取当前阶段信息
---@return table info
function NightmareDungeon.GetPhaseInfo()
    local phaseDef = ND.PHASES[fight.phase]
    local target = fight.phaseTargets[fight.phase]
    return {
        phase       = fight.phase,
        phaseCount  = #ND.PHASES,
        phaseName   = phaseDef and phaseDef.name or "未知",
        killCount   = fight.killCount,
        killTarget  = target and target.total or 0,
        totalKills  = fight.totalKills,
        totalMonsters = fight.totalMonsters,
        elapsedTime = fight.elapsedTime,
        timeLimit   = fight.timeLimit,
        tier        = currentSigil and currentSigil.tier or 0,
    }
end

--- 获取当前钥石
---@return table|nil sigil
function NightmareDungeon.GetCurrentSigil()
    return currentSigil
end

--- 获取玩家词缀修饰
---@return table mods
function NightmareDungeon.GetPlayerMods()
    return fight.playerMods
end

-- ============================================================================
-- 奖励计算
-- ============================================================================

--- 根据品质权重随机选择品质
---@param weights table {blue, purple, orange}
---@return number qualityIdx 3=蓝 4=紫 5=橙
local function rollQuality(weights)
    local r = math.random()
    if r < weights[1] then return 3 end           -- 蓝
    if r < weights[1] + weights[2] then return 4 end  -- 紫
    return 5                                          -- 橙
end

--- 结束战斗, 计算并发放奖励
---@param completed boolean 是否通关 (true=通关, false=死亡/超时)
function NightmareDungeon.EndFight(completed)
    if not NightmareDungeon.active then return end

    NightmareDungeon.active = false
    local tier = currentSigil and currentSigil.tier or 1

    -- 失败: 钥石已消耗不退回, 不给奖励
    if not completed then
        print("[NightmareDungeon] Failed, sigil consumed (not returned).")

        NightmareDungeon.fightResult = {
            completed     = false,
            tier          = tier,
            totalKills    = fight.totalKills,
            elapsedTime   = fight.elapsedTime,
            phase         = fight.phase,
            equips        = {},
            materials     = {},
            gold          = 0,
            exp           = 0,
            nextSigil     = nil,
        }
        SaveSystem.SaveNow()
        return
    end

    -- ── 通关奖励 ──

    local lootTier = getLootTier(tier)
    local maxCh = GameState.records.maxChapter or 1

    -- 装备生成
    local equipCount = math.random(lootTier.equipMin, lootTier.equipMax)
    local bossWeights = getBossQualityWeights(tier)
    local equips = {}
    local FloatTip = require("ui.FloatTip")

    -- Boss阶段必掉橙装
    local orangeCount = tier >= ND.BOSS_DOUBLE_ORANGE_TIER and 2 or 1
    for i = 1, orangeCount do
        local equip = GameState.CreateEquip(5, maxCh)  -- 5=橙色
        if equip then
            local _, decompInfo = GameState.AddToInventory(equip)
            if decompInfo then FloatTip.Decompose(decompInfo) end
            table.insert(equips, equip)
        end
    end

    -- 剩余装备
    for i = 1, math.max(0, equipCount - orangeCount) do
        local q = rollQuality(bossWeights)
        q = math.max(q, lootTier.minQuality)
        local equip = GameState.CreateEquip(q, maxCh)
        if equip then
            local _, decompInfo = GameState.AddToInventory(equip)
            if decompInfo then FloatTip.Decompose(decompInfo) end
            table.insert(equips, equip)
        end
    end

    -- 材料掉落
    local materials = {}
    for _, md in ipairs(ND.MATERIAL_DROPS) do
        if tier >= md.minTier then
            local count = math.floor(md.base + md.perTier * tier)
            -- Boss-only 特殊处理
            if md.bossOnly then
                if md.chance then
                    if math.random() > md.chance then count = 0 end
                end
                -- 深渊之心 Lv90+ ×2
                if md.matId == "abyssHeart" and tier >= ND.ABYSS_HEART_DOUBLE_TIER then
                    count = count * 2
                end
            end
            if count > 0 then
                GameState.materials[md.matId] = (GameState.materials[md.matId] or 0) + count
                table.insert(materials, { matId = md.matId, count = count })
            end
        end
    end

    -- 经验/金币
    local exp  = math.floor(ND.EXP_BASE * (1 + tier * ND.EXP_TIER_MUL))
    local scaleMul = StageConfig.CalcScaleMul(maxCh, 10) * calcTierMul(tier)
    local gold = math.floor(ND.GOLD_BASE * math.sqrt(scaleMul) * (1 + tier * ND.GOLD_TIER_MUL))
    GameState.AddGold(gold)
    GameState.AddExp(exp)

    -- 生成下一级钥石
    local nextTier = math.min(ND.MAX_TIER, tier + math.random(ND.SIGIL_TIER_UP_MIN, ND.SIGIL_TIER_UP_MAX))
    local nextSigil = NightmareDungeon.GenerateSigil(nextTier)
    NightmareDungeon.AddSigil(nextSigil)

    -- 更新记录
    if tier > (GameState.nightmareDungeon.maxTierCleared or 0) then
        GameState.nightmareDungeon.maxTierCleared = tier
    end

    -- 日常任务追踪
    local ok, DailyRewards = pcall(require, "DailyRewards")
    if ok and DailyRewards and DailyRewards.Track then
        DailyRewards.Track("nightmareDungeonRuns", 1)
    end

    -- 构造结算数据
    NightmareDungeon.fightResult = {
        completed     = true,
        tier          = tier,
        totalKills    = fight.totalKills,
        elapsedTime   = fight.elapsedTime,
        phase         = fight.phase,
        equips        = equips,
        materials     = materials,
        gold          = gold,
        exp           = exp,
        nextSigil     = nextSigil,
        affixes       = {
            positives = currentSigil and currentSigil.positives or {},
            negatives = currentSigil and currentSigil.negatives or {},
        },
    }

    print("[NightmareDungeon] Fight completed! Tier=" .. tier
        .. " Kills=" .. fight.totalKills
        .. " Time=" .. string.format("%.1f", fight.elapsedTime) .. "s"
        .. " Equips=" .. #equips
        .. " NextSigil=Lv." .. nextTier
        .. " Gold=" .. gold .. " Exp=" .. exp)

    SaveSystem.SaveNow()
end

--- 退出噩梦地牢, 恢复关卡
function NightmareDungeon.ExitToMain()
    NightmareDungeon.active      = false
    NightmareDungeon.fightResult = nil
    currentSigil = nil

    -- 清空战斗状态
    fight.phase      = 1
    fight.killCount  = 0
    fight.totalKills = 0
    fight.spawnCount = 0
    fight.monsterMods = {}
    fight.playerMods  = {}

    -- 恢复关卡状态
    if NightmareDungeon._savedStage then
        GameState.stage.chapter = NightmareDungeon._savedStage.chapter
        GameState.stage.stage   = NightmareDungeon._savedStage.stage
        GameState.stage.waveIdx = NightmareDungeon._savedStage.waveIdx
        NightmareDungeon._savedStage = nil
    end
end

-- ============================================================================
-- 怪物生成队列
-- ============================================================================

--- 从家族系统解析怪物模板并应用噩梦词缀缩放
---@param monsterDef table { familyId, behaviorId, monsterId, [raceTier], [name] }
---@param scaleMul number 基础缩放倍率
---@param role string "mob"|"elite"|"champion"|"boss"
---@return table template, string templateId
local function resolveMonster(monsterDef, scaleMul, role)
    local chapter = GameState.stage.chapter or 1
    local template = MonsterFamilies.Resolve(
        monsterDef.familyId,
        monsterDef.behaviorId,
        chapter,
        nil,
        monsterDef.monsterId
    )

    -- 基准值: 直接使用 MonsterFamilies.Resolve 返回的模板值
    -- (与主线一致，Spawner 通过 scaleMul 统一缩放)
    local baseHP  = template.hp  or 110
    local baseATK = template.atk or 13
    local baseDEF = template.def or 15

    -- Boss raceTier 覆盖
    if role == "boss" and monsterDef.raceTier then
        local overrideTier = MonsterFamilies.RACE_TIERS[monsterDef.raceTier]
        if overrideTier then
            baseHP  = overrideTier.hp
            baseATK = overrideTier.atk
            baseDEF = overrideTier.def
        end
    end

    -- 词缀缩放
    local monsterDefMul = 1.0 + (fight.monsterMods.defMul or 0)
    local monsterAtkMul = 1.0 + (fight.monsterMods.atkMul or 0)

    -- 噩梦主题颜色
    local colorMap = {
        mob      = { 120, 60, 160 },   -- 紫色小怪
        elite    = { 180, 60, 60 },    -- 红色精英
        champion = { 220, 160, 40 },   -- 金色冠军
        boss     = { 200, 40, 200 },   -- 紫红Boss
    }

    -- 按角色类型设置属性倍率 (与主线对齐: 使用模板基础值 × role 倍率)
    if role == "boss" then
        template.hp      = baseHP * 8
        template.atk     = baseATK * 2.5
        template.def     = baseDEF * monsterDefMul * 1.5
        template.isElite = true
        template.isBoss  = true
        template.radius  = 24
        if monsterDef.name then template.name = monsterDef.name end
    elseif role == "champion" then
        template.hp      = baseHP * 4
        template.atk     = baseATK * monsterAtkMul * 1.5
        template.def     = baseDEF * monsterDefMul * 1.3
        template.isElite = true
        template.radius  = 20
    elseif role == "elite" then
        template.hp      = baseHP * 2.5
        template.atk     = baseATK * monsterAtkMul
        template.def     = baseDEF * monsterDefMul
        template.isElite = true
    else  -- mob
        template.hp  = baseHP
        template.atk = baseATK
        template.def = baseDEF
    end

    -- 添加噩梦标签
    template.tags = template.tags or {}
    template.tags.nightmare = true
    if role == "elite" then template.tags.elite = true end
    if role == "champion" then template.tags.champion = true end
    if role == "boss" then template.tags.boss = true end

    template.color = colorMap[role] or colorMap.mob

    -- 禁用家族机制 (避免构装体碎片/重组等副作用)
    template.familyType = nil
    template.familyId   = nil

    local templateId = monsterDef.monsterId
                    or (monsterDef.familyId .. "_" .. monsterDef.behaviorId)
    return template, templateId
end

--- 从列表中随机选一个怪物定义
---@param list table 怪物定义列表
---@return table monsterDef
local function pickRandom(list)
    return list[math.random(1, #list)]
end

--- 构建当前阶段的怪物生成队列 (使用 MonsterFamilies 家族系统)
---@return table queue Spawner 兼容的队列
function NightmareDungeon.BuildSpawnQueue()
    local tier = currentSigil and currentSigil.tier or 1
    -- 怪物使用模板基础值，仅由层级缩放 (不再乘主线 CalcScaleMul)
    local tierMul = calcTierMul(tier)
    local scaleMul = tierMul

    local element = currentSigil and currentSigil.element or "fire"
    local theme = NIGHTMARE_THEMES[element] or NIGHTMARE_THEMES.fire

    local target = fight.phaseTargets[fight.phase]
    if not target then return {} end

    local queue = {}
    local phaseDef = ND.PHASES[fight.phase]

    -- Boss 阶段
    if phaseDef.bossCount and phaseDef.bossCount > 0 then
        -- 先生成小怪侍从
        for i = 1, target.mobs do
            local mDef = pickRandom(theme.mobs)
            local template, tplId = resolveMonster(mDef, scaleMul, "mob")
            table.insert(queue, {
                templateId  = "nd_mob_p3_" .. i,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        end
        -- Boss
        local bossTemplate, bossTplId = resolveMonster(theme.boss, scaleMul, "boss")
        table.insert(queue, {
            templateId  = "nd_boss_" .. bossTplId,
            template    = bossTemplate,
            scaleMul    = scaleMul,
            expScaleMul = 0,
        })
    else
        -- 普通/精英阶段
        local idx = 0

        -- 普通怪 (从 mobs 池随机)
        for i = 1, target.mobs do
            idx = idx + 1
            local mDef = pickRandom(theme.mobs)
            local template, tplId = resolveMonster(mDef, scaleMul, "mob")
            table.insert(queue, {
                templateId  = "nd_mob_" .. fight.phase .. "_" .. idx,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        end

        -- 精英 (从 elites 池随机)
        for i = 1, target.elites do
            idx = idx + 1
            local mDef = pickRandom(theme.elites)
            local template, tplId = resolveMonster(mDef, scaleMul, "elite")
            table.insert(queue, {
                templateId  = "nd_elite_" .. fight.phase .. "_" .. idx,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        end

        -- 冠军怪 (从 champions 池随机)
        for i = 1, (target.champs or 0) do
            idx = idx + 1
            local mDef = pickRandom(theme.champions)
            local template, tplId = resolveMonster(mDef, scaleMul, "champion")
            table.insert(queue, {
                templateId  = "nd_champ_" .. fight.phase .. "_" .. idx,
                template    = template,
                scaleMul    = scaleMul,
                expScaleMul = 0,
            })
        end
    end

    return queue
end

-- ============================================================================
-- HUD 绘制
-- ============================================================================

--- 绘制噩梦地牢专属 HUD
---@param nvg userdata NanoVG 上下文
---@param l table 布局信息
---@param bs table BattleSystem 引用
---@param alpha number 透明度
function NightmareDungeon.DrawHUD(nvg, l, bs, alpha)
    if not NightmareDungeon.active then return end

    local info = NightmareDungeon.GetPhaseInfo()
    local cx = l.x + l.w / 2
    local y = l.y + 6

    -- 标题
    nvgFontSize(nvg, 16)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(180, 60, 220, math.floor(255 * alpha)))
    nvgText(nvg, cx, y, "噩梦地牢 Lv." .. info.tier)

    -- 阶段进度
    y = y + 20
    nvgFontSize(nvg, 13)
    local phaseColor = fight.phase == 3 and { 220, 60, 60 } or { 180, 180, 220 }
    nvgFillColor(nvg, nvgRGBA(phaseColor[1], phaseColor[2], phaseColor[3], math.floor(220 * alpha)))
    nvgText(nvg, cx, y, info.phaseName .. " (" .. info.phase .. "/" .. info.phaseCount .. ") - " .. info.killCount .. "/" .. info.killTarget)

    -- 词缀图标
    y = y + 18
    nvgFontSize(nvg, 11)
    local affixTexts = {}
    if currentSigil then
        for _, id in ipairs(currentSigil.positives or {}) do
            local def = getAffixDef(id)
            if def then table.insert(affixTexts, { "+" .. def.name, { 80, 220, 80 } }) end
        end
        for _, id in ipairs(currentSigil.negatives or {}) do
            local def = getAffixDef(id)
            if def then table.insert(affixTexts, { "-" .. def.name, { 220, 80, 80 } }) end
        end
    end

    local affixX = cx - (#affixTexts - 1) * 40
    for i, at in ipairs(affixTexts) do
        nvgFillColor(nvg, nvgRGBA(at[2][1], at[2][2], at[2][3], math.floor(200 * alpha)))
        nvgText(nvg, affixX + (i - 1) * 80, y, at[1])
    end
end

-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode = require("GameMode")
    local adapter  = {}

    function adapter:OnEnter()
        return NightmareDungeon.active
    end

    function adapter:OnExit()
        NightmareDungeon.ExitToMain()
    end

    function adapter:BuildSpawnQueue()
        return NightmareDungeon.BuildSpawnQueue()
    end

    function adapter:GetBattleConfig()
        return {
            isBossWave            = (fight.phase == 3),
            bossTimerMax          = fight.timeLimit,
            startTimerImmediately = true,
            maxAliveOverride      = ND.MAX_ON_FIELD,
        }
    end

    function adapter:OnEnemyKilled(bs, enemy)
        local Particles   = require("battle.Particles")
        local CombatUtils = require("battle.CombatUtils")

        NightmareDungeon.OnEnemyKilled(enemy)

        -- 视觉效果
        local color = enemy.isElite and { 200, 60, 200 } or { 140, 60, 180 }
        Particles.SpawnExplosion(bs.particles, enemy.x, enemy.y, color)
        CombatUtils.PlaySfx("enemyDie", 0.3)

        -- 检查阶段完成
        local dungeonComplete = NightmareDungeon.CheckPhaseComplete()

        if dungeonComplete and not bs.nightmareDungeonEnded then
            NightmareDungeon.EndFight(true)
            bs.nightmareDungeonEnded = true
            print("[NightmareDungeon] Dungeon cleared!")
        elseif fight.killCount == 0 and fight.phase > 1 then
            -- 阶段刚切换, 直接重建队列
            -- (IsTimerMode=true 导致 StageManager.CheckWaveComplete 跳过,
            --  不能依赖 _nightmarePhaseTransition 标志)
            local Spawner = require("battle.Spawner")
            Spawner.Reset()
            Spawner.BuildQueue()
            print("[NightmareDungeon] Phase " .. fight.phase .. " queue rebuilt, " .. Spawner.GetTotalInWave() .. " enemies")
        end

        return true  -- 跳过正常掉落
    end

    function adapter:OnDeath(bs)
        NightmareDungeon.EndFight(false)
        bs.nightmareDungeonEnded = true
        print("[NightmareDungeon] Player died at phase " .. fight.phase)
        return true
    end

    function adapter:OnTimeout(bs)
        NightmareDungeon.EndFight(false)
        bs.nightmareDungeonEnded = true
        print("[NightmareDungeon] Time up at phase " .. fight.phase)
        return true
    end

    function adapter:CheckWaveComplete(bs)
        -- 阶段过渡: 击杀完当前阶段全部怪 → 自动推进
        if bs._nightmarePhaseTransition then
            bs._nightmarePhaseTransition = nil
            -- 重建队列
            local Spawner = require("battle.Spawner")
            Spawner.Reset()
            Spawner.BuildQueue()
            return false  -- 继续战斗
        end

        local target = fight.phaseTargets[fight.phase]
        if target and fight.killCount >= target.total then
            local dungeonComplete = NightmareDungeon.CheckPhaseComplete()
            if dungeonComplete and not bs.nightmareDungeonEnded then
                NightmareDungeon.EndFight(true)
                bs.nightmareDungeonEnded = true
                return true
            end
        end
        return false
    end

    function adapter:SkipNormalExpDrop()
        return true
    end

    function adapter:IsTimerMode()
        return true
    end

    function adapter:GetDisplayName()
        local tier = currentSigil and currentSigil.tier or 0
        return "噩梦地牢 Lv." .. tier .. "  " .. fight.totalKills .. "/" .. fight.totalMonsters
    end

    function adapter:DrawWaveInfo(nvg, l, bs, alpha)
        -- 强制常驻: 每帧钳制 waveAnnounce, 确保下帧仍被 BattleView 调用
        bs.waveAnnounce = 2
        NightmareDungeon.DrawHUD(nvg, l, bs, 1.0)
    end

    function adapter:OnUpdate(dt, bs)
        if not NightmareDungeon.active then return end
        fight.elapsedTime = fight.elapsedTime + dt
        bs.waveAnnounce = 2

        -- 将玩家词缀效果存入 bs 供战斗系统读取
        bs._nightmareDungeonMods = fight.playerMods
    end

    GameMode.Register("nightmareDungeon", adapter)
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "nightmareDungeon",
    keys  = { "nightmareDungeon" },
    group = "misc",
    serialize = function(GS)
        return {
            nightmareDungeon = {
                totalRuns      = GS.nightmareDungeon.totalRuns,
                maxTierCleared = GS.nightmareDungeon.maxTierCleared,
                sigils         = GS.nightmareDungeon.sigils,
                adSigilDate    = GS.nightmareDungeon.adSigilDate or "",
                adSigilCount   = GS.nightmareDungeon.adSigilCount or 0,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.nightmareDungeon and type(data.nightmareDungeon) == "table" then
            GS.nightmareDungeon.totalRuns      = data.nightmareDungeon.totalRuns or 0
            GS.nightmareDungeon.maxTierCleared  = data.nightmareDungeon.maxTierCleared or 0
            GS.nightmareDungeon.sigils          = data.nightmareDungeon.sigils or {}
            GS.nightmareDungeon.adSigilDate     = data.nightmareDungeon.adSigilDate or ""
            GS.nightmareDungeon.adSigilCount    = data.nightmareDungeon.adSigilCount or 0
        end
    end,
})

return NightmareDungeon
