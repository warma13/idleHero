-- ============================================================================
-- EndlessTrial.lua - 无尽试炼核心模块 (v2: MonsterTemplates 集成)
-- 职责: 动态怪物组装、数值缩放(锚定玩家章节)、抗性模板轮换、
--       逐层一次性经验发放、层推进、死亡结算
-- 设计文档: docs/数值/无尽试炼设计.md
-- ============================================================================

local GameState       = require("GameState")
local StageConfig     = require("StageConfig")
local MonsterTemplates = require("MonsterTemplates")
local SlotSaveSystem  = require("SlotSaveSystem")

---@diagnostic disable-next-line: undefined-global
local lobby = lobby  -- 引擎内置全局

--- 获取带槽位后缀的试炼排行榜 key
local function TrialSlotKey()
    local slot = SlotSaveSystem.GetActiveSlot()
    if slot <= 0 then slot = 1 end
    return "max_trial_floor_v3_s" .. slot
end

local EndlessTrial = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

local FLOOR_GROWTH_RATE   = 0.06   -- 每层 scaleMul 增长率
local BOSS_FLOOR_MUL      = 2.0    -- Boss 层额外倍率
local TRIAL_EXP_MUL       = 3.0    -- 试炼经验额外乘数
local NORMAL_COUNT_BASE   = 8      -- 基础怪物数量
local NORMAL_COUNT_INCR   = 2      -- 每 5 层增加数量
local NORMAL_COUNT_MAX    = 40     -- 怪物数量上限
local RESIST_ROTATION_PERIOD = 5   -- 抗性轮换周期(每 N 层切换)
local BOSS_TIMER_BASE     = 60     -- Boss 限时基础(秒)
local BOSS_TIMER_MIN      = 30     -- Boss 限时下限(秒)

-- 抗性轮换序列: 12 种 MonsterTemplates.Resists 模板按固定顺序循环
local RESIST_SEQUENCE = {
    "balanced", "fire_res", "ice_res", "poison_res", "water_res", "arcane_res",
    "holy_res", "phys_armor", "magic_vuln", "all_low", "all_high", "mixed_a",
}

-- 行为模板轮换序列
local BEHAVIOR_SEQUENCE = {
    "swarm", "bruiser", "glass", "debuffer", "tank", "caster", "exploder",
}

-- resistCoeff 按层数分段 (替代 ChapterThemes.resistCoeff)
local RESIST_COEFF_TIERS = {
    { maxFloor = 10,  coeff = 0.3 },
    { maxFloor = 30,  coeff = 0.5 },
    { maxFloor = 60,  coeff = 0.7 },
    { maxFloor = 80,  coeff = 0.85 },
}
local RESIST_COEFF_DEFAULT = 1.0

-- ============================================================================
-- 章节怪物贴图池 (试炼用, 按玩家章节分配外观)
-- ============================================================================

local CHAPTER_MOB_SPRITES = {
    [1]  = { "Textures/mobs/ash_rat.png", "Textures/mobs/rot_worm.png", "Textures/mobs/void_bat.png", "Textures/mobs/bandit.png", "Textures/mobs/spore_shroom.png", "Textures/mobs/swamp_frog.png", "Textures/mobs/water_spirit.png", "Textures/mobs/tide_crab.png" },
    [2]  = { "Textures/mobs/frost_imp.png", "Textures/mobs/ice_wraith.png", "Textures/mobs/glacier_beetle.png", "Textures/mobs/snow_wolf.png", "Textures/mobs/cryo_mage.png", "Textures/mobs/frozen_revenant.png", "Textures/mobs/abyssal_jellyfish.png", "Textures/mobs/permafrost_golem.png" },
    [3]  = { "Textures/mobs/lava_lizard.png", "Textures/mobs/volcano_moth.png", "Textures/mobs/toxiflame_shroom.png", "Textures/mobs/rock_scorpion.png", "Textures/mobs/molten_sprite.png", "Textures/mobs/miasma_weaver.png", "Textures/mobs/lava_hound.png", "Textures/mobs/obsidian_guard.png" },
    [4]  = { "Textures/mobs/grave_rat.png", "Textures/mobs/skeleton_warrior.png", "Textures/mobs/wraith.png", "Textures/mobs/corpse_spider.png", "Textures/mobs/necro_acolyte.png", "Textures/mobs/bone_golem.png", "Textures/mobs/shadow_assassin.png", "Textures/mobs/cursed_knight.png" },
    [5]  = { "Textures/mobs/abyss_angler.png", "Textures/mobs/storm_seahorse.png", "Textures/mobs/venom_jelly.png", "Textures/mobs/coral_guardian.png", "Textures/mobs/sea_anemone.png", "Textures/mobs/abyssal_crab.png", "Textures/mobs/ink_octopus.png", "Textures/mobs/tide_merfolk.png" },
    [6]  = { "Textures/mobs/sand_scarab.png", "Textures/mobs/sand_wraith.png", "Textures/mobs/dune_worm.png", "Textures/mobs/desert_golem.png", "Textures/mobs/lightning_lizard.png", "Textures/mobs/storm_hawk.png", "Textures/mobs/thunder_scorpion.png", "Textures/mobs/thunder_shaman.png" },
    [7]  = { "Textures/mobs/plague_beetle.png", "Textures/mobs/thorn_viper.png", "Textures/mobs/spore_lurker.png", "Textures/mobs/vine_strangler.png", "Textures/mobs/mire_shaman.png", "Textures/mobs/ironbark_treant.png", "Textures/mobs/jungle_panther.png", "Textures/mobs/toxic_wasp.png" },
    [8]  = { "Textures/mobs/void_wisp.png", "Textures/mobs/rift_stalker.png", "Textures/mobs/null_sentinel.png", "Textures/mobs/phase_weaver.png", "Textures/mobs/spatial_ripper.png", "Textures/mobs/entropy_mote.png", "Textures/mobs/void_bat.png", "Textures/mobs/void_colossus.png" },
    [9]  = { "Textures/mobs/radiant_sprite.png", "Textures/mobs/sanctum_wisp.png", "Textures/mobs/halo_lancer.png", "Textures/mobs/golden_guardian.png", "Textures/mobs/zealot_knight.png", "Textures/mobs/celestial_mender.png", "Textures/mobs/star_oracle.png", "Textures/mobs/divine_colossus.png" },
    [10] = { "Textures/mobs/mob_doom_wisp_20260310091652.png", "Textures/mobs/mob_void_lancer_20260310091651.png", "Textures/mobs/mob_dark_sentinel_20260310091701.png", "Textures/mobs/mob_corrupt_mage_20260310091712.png", "Textures/mobs/mob_shadow_oracle_20260310091708.png", "Textures/mobs/mob_abyss_shade_20260310091659.png", "Textures/mobs/mob_night_reaper_20260310091728.png", "Textures/mobs/mob_abyssal_titan_20260310091724.png" },
    [11] = { "Textures/mobs/mob_pyre_imp_20260310091844.png", "Textures/mobs/mob_cinder_wraith_20260310091839.png", "Textures/mobs/mob_molten_golem_20260310091840.png", "Textures/mobs/mob_hellfire_caster_20260310091830.png", "Textures/mobs/mob_scorch_knight_20260310091857.png", "Textures/mobs/mob_flame_hierophant_20260310091853.png", "Textures/mobs/mob_inferno_blade_20260310091854.png", "Textures/mobs/mob_purgatory_giant_20260310091828.png" },
    [12] = { "Textures/mobs/mob_chrono_mite_20260311050719.png", "Textures/mobs/mob_chrono_mage_20260311050720.png", "Textures/mobs/mob_rift_phantom_20260311050716.png", "Textures/mobs/mob_stasis_spider_20260311050557.png", "Textures/mobs/mob_epoch_colossus_20260311050558.png", "Textures/mobs/mob_rewind_assassin_20260311050743.png", "Textures/mobs/mob_eternal_sentinel_20260311050745.png", "Textures/mobs/mob_aeon_hierophant_20260311050620.png" },
}

-- 回退到章节1的贴图池
local function getChapterSprites(chapter)
    return CHAPTER_MOB_SPRITES[chapter] or CHAPTER_MOB_SPRITES[1]
end

-- ============================================================================
-- Boss 池 (沿用手工设计的 Boss，不走 MonsterTemplates)
-- ============================================================================

EndlessTrial.BOSS_MONSTERS = {
    "boss_corrupt_guard", "boss_golem",
    "boss_ice_witch", "boss_frost_dragon",
    "boss_lava_lord", "boss_inferno_king",
    "boss_bone_lord", "boss_tomb_king",
    "boss_siren", "boss_leviathan",
    "boss_sandstorm_lord", "boss_thunder_titan",
    "boss_venom_queen", "boss_rotwood_mother",
}

-- ============================================================================
-- 数值缩放
-- ============================================================================

-- 试炼基础倍率: 等同于 ch1-s1 的难度, 所有人起点相同
local TRIAL_BASE_SCALE = StageConfig.CalcScaleMul(1, 1)

--- 获取指定层的数值倍率 (纯 floor 函数, 与玩家章节无关)
---@param floor number 层数 (1-based)
---@return number scaleMul
function EndlessTrial.GetScaleMul(floor)
    local floorMul = (1 + FLOOR_GROWTH_RATE) ^ (floor - 1)
    local scaleMul = TRIAL_BASE_SCALE * floorMul
    -- Boss 层额外倍率
    if floor % 10 == 0 then
        scaleMul = scaleMul * BOSS_FLOOR_MUL
    end
    return scaleMul
end

--- 获取指定层的 Boss 限时 (秒)
---@param floor number
---@return number
function EndlessTrial.GetBossTimerMax(floor)
    return math.max(BOSS_TIMER_MIN, BOSS_TIMER_BASE - floor)
end

-- ============================================================================
-- 怪物数量
-- ============================================================================

--- 普通层怪物数量
---@param floor number
---@return number
function EndlessTrial.GetNormalCount(floor)
    local base = NORMAL_COUNT_BASE + math.floor(floor / 5) * NORMAL_COUNT_INCR
    return math.min(base, NORMAL_COUNT_MAX)
end

-- ============================================================================
-- 抗性轮换
-- ============================================================================

--- 获取指定层的 resistId (按 RESIST_SEQUENCE 轮换)
---@param floor number
---@return string resistId
function EndlessTrial.GetFloorResistId(floor)
    local groupIdx = (math.floor((floor - 1) / RESIST_ROTATION_PERIOD) % #RESIST_SEQUENCE) + 1
    return RESIST_SEQUENCE[groupIdx]
end

--- 获取指定层的 resistCoeff (按层数分段)
---@param floor number
---@return number
function EndlessTrial.GetFloorResistCoeff(floor)
    for _, tier in ipairs(RESIST_COEFF_TIERS) do
        if floor <= tier.maxFloor then
            return tier.coeff
        end
    end
    return RESIST_COEFF_DEFAULT
end

--- 使用自定义 resistCoeff 计算抗性 (替代 MonsterTemplates.CalcResist 的章节查表)
---@param resistId string
---@param coeff number
---@return table resist {fire=, ice=, poison=, water=, arcane=, physical=}
local function CalcResistWithCoeff(resistId, coeff)
    local base = MonsterTemplates.Resists[resistId]
    if not base then
        return { fire = 0, ice = 0, poison = 0, water = 0, arcane = 0, physical = 0 }
    end
    return {
        fire     = base.fire * coeff / 100,
        ice      = base.ice * coeff / 100,
        poison   = base.poison * coeff / 100,
        water    = base.water * coeff / 100,
        arcane   = base.arcane * coeff / 100,
        physical = base.physical * coeff / 100,
    }
end

-- ============================================================================
-- 行为模板选取
-- ============================================================================

--- 获取指定层的行为模板列表 (混搭策略)
---@param floor number
---@return string[] behaviorIds
function EndlessTrial.GetFloorBehaviors(floor)
    local seqLen = #BEHAVIOR_SEQUENCE
    -- 主行为: 按层数循环
    local mainIdx = ((floor - 1) % seqLen) + 1
    local main = BEHAVIOR_SEQUENCE[mainIdx]

    if floor <= 10 then
        -- 教学期: 单一行为
        return { main }
    elseif floor <= 30 then
        -- 组合期: 2 种行为混搭
        local subIdx = (mainIdx % seqLen) + 1
        return { main, BEHAVIOR_SEQUENCE[subIdx] }
    elseif floor <= 60 then
        -- 挑战期: 2-3 种行为
        local subIdx1 = (mainIdx % seqLen) + 1
        local subIdx2 = ((mainIdx + 1) % seqLen) + 1
        if floor % 3 == 0 then
            return { main, BEHAVIOR_SEQUENCE[subIdx1], BEHAVIOR_SEQUENCE[subIdx2] }
        else
            return { main, BEHAVIOR_SEQUENCE[subIdx1] }
        end
    else
        -- 极限期: 3 种行为
        local subIdx1 = (mainIdx % seqLen) + 1
        local subIdx2 = ((mainIdx + 1) % seqLen) + 1
        return { main, BEHAVIOR_SEQUENCE[subIdx1], BEHAVIOR_SEQUENCE[subIdx2] }
    end
end

-- ============================================================================
-- 能力标签叠加
-- ============================================================================

--- 获取指定层的标签配置 {tagName = level}
---@param floor number
---@return table tags
function EndlessTrial.GetFloorTags(floor)
    local tags = {}

    -- 确定标签数量和等级范围
    local tagCount, minLv, maxLv
    if floor <= 10 then
        -- 0-1 个, Lv.1
        if floor >= 6 then tagCount = 1 else tagCount = 0 end
        minLv, maxLv = 1, 1
    elseif floor <= 20 then
        tagCount = 1
        minLv, maxLv = 1, 2
    elseif floor <= 40 then
        tagCount = (floor % 2 == 0) and 2 or 1
        minLv, maxLv = 2, 3
    elseif floor <= 60 then
        tagCount = 2
        minLv, maxLv = 3, 4
    elseif floor <= 80 then
        tagCount = (floor % 3 == 0) and 3 or 2
        minLv, maxLv = 4, 5
    else
        tagCount = 3
        minLv, maxLv = 4, 5
    end

    if tagCount == 0 then return tags end

    -- 可选标签池 (从所有行为模板收集)
    local allTags = {
        "slowOnHit", "hpRegen", "defPierce", "packBonus",
        "lifesteal", "venomStack", "healAura", "sporeCloud",
        "firstStrikeMul", "corrosion",
    }

    -- 使用 floor 作为种子确保同层同标签 (可重试一致)
    local seed = floor * 31
    for i = 1, tagCount do
        local idx = ((seed + i * 7) % #allTags) + 1
        local tagName = allTags[idx]
        -- 标签等级在 [minLv, maxLv] 之间
        local lv = minLv + ((seed + i * 13) % (maxLv - minLv + 1))
        -- 检查 TagParams 是否有该等级
        local defs = MonsterTemplates.TagParams[tagName]
        if defs then
            if not defs[lv] then lv = minLv end
            tags[tagName] = lv
        end
    end

    return tags
end

-- ============================================================================
-- 经验计算
-- ============================================================================

--- 计算某层通关一次性经验
---@param floor number
---@return number exp
function EndlessTrial.CalcFloorExp(floor)
    local isBossFloor = (floor % 10 == 0)
    local scaleMul = EndlessTrial.GetScaleMul(floor)

    if isBossFloor then
        -- Boss 经验 = 等价普通怪总经验
        local normalCount = EndlessTrial.GetNormalCount(floor)
        local avgExpDrop = 12  -- 加权平均基准 (7 种行为模板)
        return math.floor(normalCount * avgExpDrop * scaleMul * TRIAL_EXP_MUL)
    else
        -- 普通层: normalCount × avgExpDrop × scaleMul × trialExpMul
        local normalCount = EndlessTrial.GetNormalCount(floor)
        -- 计算该层实际使用行为模板的平均 expDrop
        local behaviors = EndlessTrial.GetFloorBehaviors(floor)
        local totalExp = 0
        for _, bid in ipairs(behaviors) do
            local beh = MonsterTemplates.Behaviors[bid]
            totalExp = totalExp + (beh and beh.expDrop or 12)
        end
        local avgExpDrop = totalExp / #behaviors
        return math.floor(normalCount * avgExpDrop * scaleMul * TRIAL_EXP_MUL)
    end
end

--- 发放某层经验 (仅未领取过的层才返回经验值)
---@param floor number
---@return number exp 实际发放的经验 (已领取层返回 0)
function EndlessTrial.AwardFloorExp(floor)
    local et = GameState.endlessTrial
    if floor <= (et.clearedFloor or 0) then
        return 0  -- 已领取过
    end
    return EndlessTrial.CalcFloorExp(floor)
end

-- ============================================================================
-- 生成队列构建
-- ============================================================================

--- 判断是否为 Boss 层
---@param floor number
---@return boolean
function EndlessTrial.IsBossFloor(floor)
    return floor % 10 == 0
end

--- 构建试炼层的怪物生成队列
---@param floor number
---@return table queue Spawner 兼容的队列 { { templateId, template, scaleMul, expScaleMul }, ... }
---@return boolean isBossFloor
function EndlessTrial.BuildTrialQueue(floor)
    local isBossFloor = EndlessTrial.IsBossFloor(floor)
    local scaleMul = EndlessTrial.GetScaleMul(floor)

    if isBossFloor then
        -- Boss 层: 沿用 BOSS_MONSTERS 循环 + StageConfig.MONSTERS 查模板
        local bossIdx = ((floor / 10 - 1) % #EndlessTrial.BOSS_MONSTERS) + 1
        local bossId = EndlessTrial.BOSS_MONSTERS[bossIdx]
        local template = StageConfig.ResolveMonster(bossId)
        if not template then
            print("[EndlessTrial] ERROR: unknown boss id=" .. tostring(bossId))
            return {}, true
        end
        return {
            {
                templateId = bossId,
                template = template,
                scaleMul = scaleMul,
                expScaleMul = 0,  -- 试炼不走逐怪经验
            },
        }, true
    end

    -- 普通层: MonsterTemplates 动态组装
    local behaviors = EndlessTrial.GetFloorBehaviors(floor)
    local resistId = EndlessTrial.GetFloorResistId(floor)
    local resistCoeff = EndlessTrial.GetFloorResistCoeff(floor)
    local tags = EndlessTrial.GetFloorTags(floor)
    -- 章节主题由 floor 推导: 每10层换一个章节, 12章循环
    local chapter = ((math.ceil(floor / 10) - 1) % 12) + 1
    local count = EndlessTrial.GetNormalCount(floor)

    -- 预计算抗性 (同层共享)
    local resist = CalcResistWithCoeff(resistId, resistCoeff)

    -- 贴图池: 按玩家章节选取
    local sprites = getChapterSprites(chapter)

    local queue = {}
    for i = 1, count do
        local behIdx = ((i - 1) % #behaviors) + 1
        local behaviorId = behaviors[behIdx]

        -- 确定性分配贴图: 用 floor + i 索引轮换
        local spriteIdx = ((floor * 7 + i - 1) % #sprites) + 1
        local mobImage = sprites[spriteIdx]

        local template = MonsterTemplates.Assemble(behaviorId, resistId, chapter, {
            tags = tags,
            image = mobImage,
        })
        -- 覆盖抗性: 使用试炼自己的 resistCoeff (而非章节查表)
        template.resist = resist

        table.insert(queue, {
            templateId = behaviorId .. "_trial_f" .. floor,
            template = template,
            scaleMul = scaleMul,
            expScaleMul = 0,  -- 试炼不走逐怪经验
        })
    end

    return queue, false
end

-- ============================================================================
-- 层推进 & 结算
-- ============================================================================

--- 当前试炼层通关, 推进到下一层
function EndlessTrial.AdvanceFloor()
    local et = GameState.endlessTrial
    -- 标记当前层已通关(更新已领取经验的最高层)
    local clearedFloor = et.floor
    if clearedFloor > (et.clearedFloor or 0) then
        et.clearedFloor = clearedFloor
    end
    -- 推进到下一层
    et.floor = et.floor + 1
    if et.floor > et.maxFloor then
        et.maxFloor = et.floor
    end
    print("[EndlessTrial] Cleared F" .. clearedFloor .. ", advanced to F" .. et.floor
        .. " (maxFloor=" .. et.maxFloor .. ", clearedFloor=" .. et.clearedFloor .. ")")
end

--- 试炼死亡, 生成结算数据
function EndlessTrial.OnTrialDeath()
    local et = GameState.endlessTrial
    local reachedFloor = et.floor
    if reachedFloor > et.maxFloor then
        et.maxFloor = reachedFloor
    end
    et.result = {
        reachedFloor = reachedFloor,
        maxFloor     = et.maxFloor,
        clearedFloor = et.clearedFloor or 0,
        totalGold    = et.totalGold,
        totalExp     = et.totalExp,
    }
    print("[EndlessTrial] Death at F" .. reachedFloor .. ", maxFloor=" .. et.maxFloor
        .. ", clearedFloor=" .. (et.clearedFloor or 0) .. ", totalExp=" .. et.totalExp)
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 检查是否在试炼中
---@return boolean
function EndlessTrial.IsActive()
    return GameState.endlessTrial.active
end

--- 获取当前试炼层
---@return number
function EndlessTrial.GetFloor()
    return GameState.endlessTrial.floor
end

--- 获取历史最高层
---@return number
function EndlessTrial.GetMaxFloor()
    return GameState.endlessTrial.maxFloor
end

--- 获取已通关层
---@return number
function EndlessTrial.GetClearedFloor()
    return GameState.endlessTrial.clearedFloor or 0
end

-- ============================================================================
-- 排行榜 (键名升版 v2→v3, 新版数据从零开始)
-- ============================================================================

--- 获取试炼排行榜
---@param callback fun(rankList: table[], myRank: number|nil, myFloor: number|nil)
function EndlessTrial.FetchLeaderboard(callback)
    local trialKey = TrialSlotKey()
    pcall(function()
        clientCloud:GetRankList(trialKey, 0, 50, {
            ok = function(rankList)
                -- 提取层数
                for _, r in ipairs(rankList) do
                    if r.iscore then
                        r._floor = r.iscore[trialKey] or 0
                    else
                        r._floor = 0
                    end
                end

                -- 批量查询昵称
                local userIds = {}
                for _, r in ipairs(rankList) do
                    if r.userId then
                        table.insert(userIds, r.userId)
                    end
                end

                local function fetchMyRank(list)
                    pcall(function()
                        local myId = lobby:GetMyUserId()
                        clientCloud:GetUserRank(myId, trialKey, {
                            ok = function(rank, score)
                                local myFloor = GameState.endlessTrial.maxFloor or 0
                                if (score or 0) > myFloor then
                                    myFloor = score
                                end
                                callback(list, rank, myFloor)
                            end,
                            error = function()
                                callback(list, nil, nil)
                            end,
                        })
                    end)
                end

                if #userIds > 0 then
                    local nicknameOk, _ = pcall(function()
                        GetUserNickname({
                            userIds = userIds,
                            onSuccess = function(nicknames)
                                local map = {}
                                for _, info in ipairs(nicknames) do
                                    if info.userId and info.nickname and info.nickname ~= "" then
                                        map[info.userId] = info.nickname
                                    end
                                end
                                for _, r in ipairs(rankList) do
                                    if r.userId and map[r.userId] then
                                        r.nickname = map[r.userId]
                                    end
                                end
                                fetchMyRank(rankList)
                            end,
                            onError = function()
                                fetchMyRank(rankList)
                            end,
                        })
                    end)
                    if not nicknameOk then
                        fetchMyRank(rankList)
                    end
                else
                    fetchMyRank(rankList)
                end
            end,
            error = function()
                callback({}, nil, nil)
            end,
        }, trialKey)
    end)
end


-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode  = require("GameMode")
    local adapter   = {}

    -- ── 生命周期 ──
    adapter.background = "trial_battle_bg_20260309124737.png"

    function adapter:OnEnter()
        GameState.EnterTrial()
        return true
    end

    function adapter:OnExit()
        GameState.endlessTrial.active = false
    end

    --- 波次公告渲染
    function adapter:DrawWaveInfo(nvg, l, bs, alpha)
        local floor = EndlessTrial.GetFloor()
        if bs.isBossWave then
            nvgFontSize(nvg, 22)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 60, 60, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32, "试炼 BOSS!")
            nvgFontSize(nvg, 14)
            nvgFillColor(nvg, nvgRGBA(255, 180, 80, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32 + 24, "第 " .. floor .. " 层")
        else
            nvgFontSize(nvg, 16)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(200, 180, 255, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32, "无尽试炼 · 第 " .. floor .. " 层")
        end
    end

    -- ── 战斗 ──

    function adapter:BuildSpawnQueue()
        local floor = EndlessTrial.GetFloor()
        local queue, _ = EndlessTrial.BuildTrialQueue(floor)
        return queue
    end

    function adapter:GetBattleConfig()
        local floor = EndlessTrial.GetFloor()
        local isBossFloor = EndlessTrial.IsBossFloor(floor)
        return {
            isBossWave           = isBossFloor,
            bossTimerMax         = isBossFloor and EndlessTrial.GetBossTimerMax(floor) or 0,
            startTimerImmediately = false,
        }
    end

    function adapter:SkipNormalExpDrop()
        return true
    end

    function adapter:CheckWaveComplete(bs)
        local Particles = require("battle.Particles")
        local Utils     = require("Utils")
        local floor = EndlessTrial.GetFloor()
        local exp   = EndlessTrial.AwardFloorExp(floor)
        if exp > 0 then
            GameState.AddExp(exp)
            GameState.endlessTrial.totalExp = GameState.endlessTrial.totalExp + exp
            Particles.SpawnReactionText(bs.particles,
                bs.playerBattle.x, bs.playerBattle.y - 40,
                "F" .. floor .. " +" .. Utils.FormatNumber(exp) .. " EXP",
                { 100, 255, 200 })
        end
        bs._waveComplete = true
        bs._restTimer = 1.0
        return true
    end

    function adapter:OnNextWave(bs)
        local Spawner = require("battle.Spawner")
        EndlessTrial.AdvanceFloor()
        local floor       = EndlessTrial.GetFloor()
        local isBossFloor = EndlessTrial.IsBossFloor(floor)

        bs.enemies      = {}
        bs.waveAnnounce = 1.5
        bs.isBossWave   = isBossFloor
        bs.bossTimer    = 0
        bs.bossTimeout  = false
        bs.bossStarted  = false
        if isBossFloor then
            bs.bossTimerMax = EndlessTrial.GetBossTimerMax(floor)
        end

        -- 重置致命保护等状态
        GameState._lavaLordTimer          = 0
        GameState._permafrostFatalUsed    = false
        GameState._permafrostInvulTimer   = 0
        GameState._iceAvatarTimer         = 0

        GameState.ResetHP()
        Spawner.Reset()
        Spawner.BuildQueue()
        print("[EndlessTrial] Floor " .. floor .. (isBossFloor and " (BOSS)" or ""))
        return true
    end

    function adapter:OnDeath(bs)
        EndlessTrial.OnTrialDeath()
        bs.trialEnded = true
        print("[EndlessTrial] Trial ended, waiting for result overlay")
        return true
    end

    function adapter:IsTimerMode()
        return false
    end

    function adapter:GetDisplayName()
        return "无尽试炼 F" .. EndlessTrial.GetFloor()
    end

    GameMode.Register("endlessTrial", adapter)
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "endlessTrial",
    keys  = { "endlessTrial" },
    group = "misc",
    serialize = function(GS)
        return {
            endlessTrial = {
                maxFloor     = GS.endlessTrial.maxFloor,
                clearedFloor = GS.endlessTrial.clearedFloor,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.endlessTrial then
            -- v2→v3 迁移: 新版试炼系统全面重置所有玩家进度
            -- 旧版 maxFloor 在新难度曲线下无意义，强制归零
            if data.endlessTrial.clearedFloor then
                -- 新版存档: 保留数据
                GS.endlessTrial.maxFloor     = data.endlessTrial.maxFloor or 0
                GS.endlessTrial.clearedFloor = data.endlessTrial.clearedFloor or 0
            else
                -- 旧版存档: 重置试炼进度
                GS.endlessTrial.maxFloor     = 0
                GS.endlessTrial.clearedFloor = 0
            end
        end
    end,
})

return EndlessTrial
