-- ============================================================================
-- WorldBoss.lua - 全服世界Boss系统
--
-- 设计:
--   1. 确定性赛季: 每24小时一轮,所有客户端根据UTC时间同步计算
--   2. 每赛季3次挑战,每次60秒,累计伤害排行
--   3. 参与奖: 当前最高章节Boss掉落×3
--   4. 排名奖: 前3名散光棱镜+碎裂宝石, 4-50名碎裂宝石
-- ============================================================================

local Config         = require("Config")
local GameState      = require("GameState")
local StageConfig    = require("StageConfig")
local SaveSystem     = require("SaveSystem")
local DamageTracker  = require("DamageTracker")
local FloatTip       = require("ui.FloatTip")

---@diagnostic disable-next-line: undefined-global
local lobby = lobby  -- 引擎内置全局

local WorldBoss = {}

-- ============================================================================
-- 配置常量
-- ============================================================================

local SEASON_DURATION   = 86400   -- 赛季时长: 24小时(秒)
local EPOCH             = 1735689600  -- 基准: 2025-01-01 00:00:00 UTC
local MAX_ATTEMPTS      = 3       -- 每赛季挑战次数
local FIGHT_DURATION    = 60      -- 每次战斗时长(秒)
local BOSS_HP_BASE      = 1e100  -- Boss基础血量 (浮点数,确保不可击杀)

-- Boss 轮换表 (按赛季编号取模)
local BOSS_ROSTER = {
    {
        name    = "深渊领主·莫格拉斯",
        element = "fire",
        color   = { 255, 100, 30 },
        atkMul  = 0.3,  -- 攻击力系数(相对玩家血量)
        image   = "Textures/mobs/boss_fire_world.png",
        -- 具体技能配置
        barrage = { interval = 6.0, count = 12, dmgMul = 0.5, element = "fire" },
    },
    {
        name    = "冰霜巨龙·霜息",
        element = "ice",
        color   = { 80, 160, 255 },
        atkMul  = 0.3,
        image   = "Textures/mobs/boss_ice_world.png",
        barrage      = { interval = 7.0, count = 10, dmgMul = 0.5, element = "ice" },
        dragonBreath = { interval = 10.0, dmgMul = 1.5, element = "ice" },
        iceArmor     = { hpThreshold = 0.5, dmgReduce = 0.5, duration = 3.0, cd = 15.0 },
    },
    {
        name    = "剧毒女皇·薇诺莎",
        element = "poison",
        color   = { 120, 220, 60 },
        atkMul  = 0.3,
        image   = "Textures/mobs/boss_poison_world.png",
        barrage  = { interval = 6.0, count = 14, dmgMul = 0.4, element = "poison" },
    },
    {
        name    = "奥术魔导·星辰之主",
        element = "arcane",
        color   = { 180, 100, 255 },
        atkMul  = 0.3,
        image   = "Textures/mobs/boss_arcane_world.png",
        barrage = { interval = 5.0, count = 16, dmgMul = 0.5, element = "arcane" },
    },
}

-- 排名奖励配置
local RANK_REWARDS = {
    { maxRank = 1,   prisms = 2, chippedGems = 5, materials = { riftEcho = 3, eternal = 2 }, label = "第1名" },
    { maxRank = 2,   prisms = 1, chippedGems = 4, materials = { riftEcho = 2, eternal = 1 }, label = "第2名" },
    { maxRank = 3,   prisms = 1, chippedGems = 3, materials = { riftEcho = 1, eternal = 1 }, label = "第3名" },
    { maxRank = 50,  prisms = 0, chippedGems = 1, materials = { riftEcho = 1 },              label = "第4-50名" },
}

-- ============================================================================
-- 公开状态
-- ============================================================================

WorldBoss.active       = false   -- 是否在世界Boss战斗中
WorldBoss.fightTimer   = 0       -- 当前战斗剩余时间
WorldBoss.fightDamage  = 0       -- 本次战斗累计伤害
WorldBoss.fightEnded   = false   -- 本次战斗已结束

-- ============================================================================
-- 赛季计算 (确定性,无需服务端)
-- ============================================================================

--- 获取当前赛季编号
function WorldBoss.GetSeason()
    return math.floor((os.time() - EPOCH) / SEASON_DURATION)
end

--- 获取赛季专属排序键名 (每赛季独立排行榜)
---@param season number|nil 赛季号,默认当前赛季
local function SeasonSortKey(season)
    return "wb_s" .. (season or WorldBoss.GetSeason())
end

--- 获取赛季剩余秒数
function WorldBoss.GetSeasonRemaining()
    local elapsed = (os.time() - EPOCH) % SEASON_DURATION
    return SEASON_DURATION - elapsed
end

--- 格式化倒计时
function WorldBoss.FormatTime(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

--- 获取当前赛季Boss配置
function WorldBoss.GetCurrentBoss()
    local season = WorldBoss.GetSeason()
    local idx = (season % #BOSS_ROSTER) + 1
    return BOSS_ROSTER[idx]
end

-- ============================================================================
-- 存档字段 (存在 GameState.worldBoss 中)
-- ============================================================================

--- 确保存档字段初始化
function WorldBoss.EnsureState()
    if not GameState.worldBoss then
        GameState.worldBoss = {
            season      = 0,
            attempts    = 0,
            totalDamage = 0,
            lastReward  = -1,
            cachedRank  = nil,   -- 上次查询到的排名(供赛季结算用)
        }
    end
    -- 赛季切换检测
    local currentSeason = WorldBoss.GetSeason()
    if GameState.worldBoss.season ~= currentSeason then
        local prevSeason = GameState.worldBoss.season
        -- 先尝试领取上赛季排名奖励(赛季切换时自动发放)
        if prevSeason > 0 and GameState.worldBoss.lastReward < prevSeason then
            WorldBoss._TryClaimPrevSeasonReward(prevSeason)
        end

        GameState.worldBoss.season      = currentSeason
        GameState.worldBoss.attempts    = 0
        GameState.worldBoss.totalDamage = 0
        GameState.worldBoss.cachedRank  = nil
        print("[WorldBoss] Season reset to " .. currentSeason)
    end
end

--- 内部: 显示赛季奖励领取通知
local function showRewardToast(rank, reward)
    local ok, Toast = pcall(require, "ui.Toast")
    if ok and Toast then
        local parts = {}
        if reward.prisms > 0 then table.insert(parts, reward.prisms .. "散光棱镜") end
        if reward.chippedGems > 0 then table.insert(parts, reward.chippedGems .. "碎裂宝石") end
        if reward.materials then
            local MatMap = Config.MATERIAL_MAP
            for matId, amt in pairs(reward.materials) do
                local def = MatMap and MatMap[matId]
                local name = def and def.name or matId
                table.insert(parts, amt .. name)
            end
        end
        local desc = table.concat(parts, " + ")
        Toast.Show("赛季排名#" .. rank .. " 奖励已领取: " .. desc,
            { 255, 220, 100, 255 }, { 60, 40, 15, 230 })
    end
end

--- 内部: 尝试领取上赛季排名奖励
function WorldBoss._TryClaimPrevSeasonReward(prevSeason)
    local cached = GameState.worldBoss.cachedRank
    if cached and cached > 0 then
        -- 有缓存排名,直接领取
        local ok, result = WorldBoss.ClaimSeasonReward(cached)
        if ok then
            showRewardToast(cached, result)
            print("[WorldBoss] Auto-claimed season reward from cached rank #" .. cached)
        end
    else
        -- 无缓存排名,异步查询后领取
        pcall(function()
            local myId = lobby:GetMyUserId()
            local prevSeasonKey = SeasonSortKey(prevSeason)
            clientCloud:GetUserRank(myId, prevSeasonKey, {
                ok = function(rank, _)
                    if rank and rank > 0 then
                        local ok, result = WorldBoss.ClaimSeasonReward(rank)
                        if ok then
                            showRewardToast(rank, result)
                            SaveSystem.SaveNow()
                            print("[WorldBoss] Auto-claimed season reward from queried rank #" .. rank)
                        end
                    else
                        print("[WorldBoss] No rank found for prev season, no reward")
                    end
                end,
                error = function()
                    print("[WorldBoss] Failed to query prev season rank, reward skipped")
                end,
            })
        end)
    end
end

--- 获取剩余挑战次数
function WorldBoss.GetAttemptsLeft()
    WorldBoss.EnsureState()
    return math.max(0, MAX_ATTEMPTS - GameState.worldBoss.attempts)
end

--- 获取本赛季累计伤害
function WorldBoss.GetTotalDamage()
    WorldBoss.EnsureState()
    return GameState.worldBoss.totalDamage
end

-- ============================================================================
-- 战斗入口/退出
-- ============================================================================

--- 进入世界Boss战斗
function WorldBoss.EnterFight()
    WorldBoss.EnsureState()

    if GameState.worldBoss.attempts >= MAX_ATTEMPTS then
        -- 免费次数用完，尝试消耗挑战券
        local ticketCount = GameState.GetBagItemCount("wb_ticket")
        if ticketCount > 0 then
            GameState.DiscardBagItem("wb_ticket", 1)
            print("[WorldBoss] Used wb_ticket, remaining: " .. (ticketCount - 1))
        else
            print("[WorldBoss] No attempts left and no tickets")
            return false
        end
    end

    -- 保存当前关卡状态
    WorldBoss._savedStage = {
        chapter = GameState.stage.chapter,
        stage   = GameState.stage.stage,
        waveIdx = GameState.stage.waveIdx,
    }

    WorldBoss.active      = true
    WorldBoss.fightTimer  = FIGHT_DURATION
    WorldBoss.fightDamage = 0
    WorldBoss.fightEnded  = false

    GameState.worldBoss.attempts = GameState.worldBoss.attempts + 1

    -- 开启 DamageTracker 会话
    DamageTracker.StartSession()

    print("[WorldBoss] Fight started! Attempt " .. GameState.worldBoss.attempts .. "/" .. MAX_ATTEMPTS)
    return true
end

--- 结束当前战斗
function WorldBoss.EndFight()
    if not WorldBoss.active then return end

    WorldBoss.active     = false
    WorldBoss.fightEnded = true

    -- 从 DamageTracker 获取本次会话伤害 (独立于 Boss hp 状态)
    local sessionDmg = DamageTracker.EndSession()
    WorldBoss.fightDamage = sessionDmg

    -- 累计伤害
    GameState.worldBoss.totalDamage = GameState.worldBoss.totalDamage + sessionDmg

    -- 上传伤害到排行榜
    WorldBoss.UploadDamage()

    -- 发放参与奖 (当前最高章节Boss掉落×3)
    WorldBoss.GrantParticipationReward()

    SaveSystem.SaveNow()

    print("[WorldBoss] Fight ended! Damage=" .. sessionDmg
        .. " Total=" .. GameState.worldBoss.totalDamage)
end

--- 退出世界Boss模式,恢复关卡
function WorldBoss.ExitToMain()
    WorldBoss.active     = false
    WorldBoss.fightEnded = false

    -- 恢复关卡
    if WorldBoss._savedStage then
        GameState.stage.chapter = WorldBoss._savedStage.chapter
        GameState.stage.stage   = WorldBoss._savedStage.stage
        GameState.stage.waveIdx = WorldBoss._savedStage.waveIdx
        WorldBoss._savedStage   = nil
    end
end

-- ============================================================================
-- 伤害记录 (供 CombatCore 调用)
-- ============================================================================

--- 记录伤害 (每次对Boss造成伤害时调用)
function WorldBoss.RecordDamage(amount)
    if WorldBoss.active then
        WorldBoss.fightDamage = WorldBoss.fightDamage + amount
    end
end

-- ============================================================================
-- 参与奖: 当前最高章节Boss掉落×3
-- ============================================================================

function WorldBoss.GrantParticipationReward()
    local chapter = GameState.records.maxChapter or 1

    -- 找到该章节Boss关卡 (最后一关)
    local stageCount = StageConfig.GetStageCount(chapter)
    local bossStageCfg = nil
    if stageCount > 0 then
        bossStageCfg = StageConfig.GetStage(chapter, stageCount)
    end

    local lootItems = {}  -- 记录掉落物
    local totalGold = 0
    local totalCrystal = 0

    for _ = 1, 3 do
        -- 金币
        if bossStageCfg and bossStageCfg.reward and bossStageCfg.reward.gold then
            GameState.AddGold(bossStageCfg.reward.gold)
            totalGold = totalGold + bossStageCfg.reward.gold
        end

        -- 装备 (Boss掉落品质)
        local equip = GameState.GenerateEquip(chapter * 10, true)
        local _, decompInfo = GameState.AddToInventory(equip)
        if decompInfo then FloatTip.Decompose(decompInfo) end
        table.insert(lootItems, {
            type      = "equip",
            name      = equip.name,
            slotName  = equip.slotName,
            qualityName = equip.qualityName,
            color     = equip.qualityColor,
        })

        -- 魂晶
        local crystalAmount = Config.SOUL_CRYSTAL.dropPerBoss or 1
        GameState.materials.soulCrystal = (GameState.materials.soulCrystal or 0) + crystalAmount
        totalCrystal = totalCrystal + crystalAmount
    end

    -- 参与奖材料: 裂隙残响
    local riftDrop = 1
    GameState.AddMaterial("riftEcho", riftDrop)

    -- 存储本次掉落详情 (供结算界面读取)
    WorldBoss.lastLoot = {
        gold      = totalGold,
        crystal   = totalCrystal,
        equips    = lootItems,
        materials = { riftEcho = riftDrop },
    }
end

-- ============================================================================
-- 云端排行榜
-- ============================================================================

--- int32 上限
local INT32_MAX = 2147483647

-- ============================================================================
-- 科学计数法存储: mantissa × 10^exponent
-- 排序键编码: exponent × 10,000,000 + mantissa 前7位
-- 可表示范围: 0 ~ 9,999,999 × 10^214 (远超 float64 精确范围)
-- ============================================================================

--- 将浮点数拆分为 mantissa + exponent (科学计数法)
--- mantissa: 最多 9 位有效数字 (int32 安全)
--- exponent: 10 的幂次
local function SplitDamage(totalDmg)
    if totalDmg <= 0 then return 0, 0 end
    local exp = math.floor(math.log(totalDmg, 10))
    -- mantissa 保留 9 位有效数字
    local digits = 9
    local shift = exp - (digits - 1)
    local man
    if shift >= 0 then
        man = math.floor(totalDmg / (10 ^ shift) + 0.5)
    else
        man = math.floor(totalDmg * (10 ^ (-shift)) + 0.5)
    end
    -- 进位修正: 四舍五入可能让 man 变成 10^digits
    if man >= 10 ^ digits then
        man = math.floor(man / 10 + 0.5)
        shift = shift + 1
    end
    local finalExp = math.max(0, shift)
    return man, finalExp
end

--- 从 mantissa + exponent 还原为 float64
--- 防护: exp 超过 308 时 10^exp 溢出为 inf
local function MergeDamage(man, exp)
    if (man or 0) <= 0 then return 0 end
    local e = math.min(exp or 0, 300)  -- float64 最大 ~1.8e308, 留余量
    return (man or 0) * (10 ^ e)
end

--- 编码排序键: exponent × 1e7 + mantissa 前 7 位
--- exponent 上限 214, 精度 7 位有效数字
local function EncodeSortKey(man, exp)
    -- mantissa 可能最多 9 位, 截取前 7 位
    local man7 = man
    if man7 >= 10000000 then
        man7 = math.floor(man7 / 100)  -- 9位 → 7位
    elseif man7 >= 1000000 then
        man7 = math.floor(man7 / 10)   -- 8位 → 7位 (不太可能)
    end
    local key = exp * 10000000 + man7
    if key > INT32_MAX then key = INT32_MAX end
    return key
end

--- 上传伤害到排行榜 (科学计数法存储)
function WorldBoss.UploadDamage()
    pcall(function()
        local totalDmg = GameState.worldBoss.totalDamage
        local season   = GameState.worldBoss.season
        local man, exp = SplitDamage(totalDmg)
        local sortKey  = EncodeSortKey(man, exp)

        local seasonKey = SeasonSortKey(season)
        local prevSeasonKey = SeasonSortKey(season - 1)
        clientCloud:BatchSet()
            :SetInt(seasonKey, sortKey)
            :SetInt("wb_dmg_hi_v2", man)
            :SetInt("wb_dmg_lo_v2", exp)
            :SetInt("wb_season_v2", season)
            :Delete(prevSeasonKey)
            :Save("世界Boss伤害", {
                ok = function()
                    print("[WorldBoss] Damage uploaded: " .. totalDmg
                        .. " (man=" .. man .. " exp=" .. exp .. " key=" .. sortKey .. ")")
                end,
                error = function(code, reason)
                    print("[WorldBoss] Upload failed: " .. tostring(reason))
                end,
            })
    end)
end

--- 读取排行榜
--- @param callback fun(rankList: table[], myRank: number|nil, myDamage: number|nil)
function WorldBoss.FetchLeaderboard(callback)
    pcall(function()
        local seasonKey = SeasonSortKey()
        clientCloud:GetRankList(seasonKey, 0, 50, {
            ok = function(rankList)
                -- 从 mantissa + exponent 还原真实伤害值
                for _, r in ipairs(rankList) do
                    if r.iscore then
                        local man = r.iscore["wb_dmg_hi_v2"] or 0
                        local exp = r.iscore["wb_dmg_lo_v2"] or 0
                        r._realDamage = MergeDamage(man, exp)
                    else
                        r._realDamage = 0
                    end
                end

                -- 收集所有 userId，批量查询昵称
                local userIds = {}
                for _, r in ipairs(rankList) do
                    if r.userId then
                        table.insert(userIds, r.userId)
                    end
                end

                -- 过滤封禁用户
                local bannedSet = {}
                for _, bid in ipairs(Config.BANNED_USER_IDS or {}) do bannedSet[bid] = true end
                local cleanList = {}
                for _, r in ipairs(rankList) do
                    if not bannedSet[r.userId] then
                        table.insert(cleanList, r)
                    end
                end
                rankList = cleanList

                local function fetchMyRank(list)
                    pcall(function()
                        local myId = lobby:GetMyUserId()
                        clientCloud:GetUserRank(myId, seasonKey, {
                            ok = function(rank, score)
                                -- 缓存排名供赛季结算用
                                if rank and rank > 0 and GameState.worldBoss then
                                    GameState.worldBoss.cachedRank = rank
                                end
                                local myRealDmg
                                if GameState.worldBoss and GameState.worldBoss.totalDamage and GameState.worldBoss.totalDamage > 0 then
                                    myRealDmg = GameState.worldBoss.totalDamage
                                elseif score and score > 0 then
                                    -- 从排序键近似反解: key = exp × 1e7 + man7
                                    local e = math.min(math.floor(score / 10000000), 300)
                                    local m = score % 10000000
                                    myRealDmg = m * (10 ^ e)
                                else
                                    myRealDmg = 0
                                end
                                callback(list, rank, myRealDmg)
                            end,
                            error = function()
                                callback(list, nil, nil)
                            end,
                        })
                    end)
                end

                -- 批量获取昵称
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
        }, "wb_dmg_hi_v2", "wb_dmg_lo_v2")
    end)
end

--- 根据排名获取奖励配置 (排名>50无奖励)
function WorldBoss.GetRewardForRank(rank)
    if not rank or rank < 1 then return nil end
    for _, r in ipairs(RANK_REWARDS) do
        if rank <= r.maxRank then return r end
    end
    return nil
end

--- 领取赛季排名奖
function WorldBoss.ClaimSeasonReward(rank)
    -- 注意: 不要调用 EnsureState()，此函数由 EnsureState→_TryClaimPrevSeasonReward 调用，会导致无限递归
    if not GameState.worldBoss then return false, "no_state" end
    local prevSeason = WorldBoss.GetSeason() - 1
    if GameState.worldBoss.lastReward >= prevSeason then
        return false, "already_claimed"
    end

    local reward = WorldBoss.GetRewardForRank(rank)
    if not reward then return false, "no_reward" end

    -- 发放散光棱镜
    if reward.prisms > 0 then
        GameState.AddBagItem("prism", reward.prisms)
    end

    -- 发放随机碎裂宝石 (品质1=碎裂, 从7种宝石中随机)
    local gemTypes = Config.GEM_TYPES
    for _ = 1, reward.chippedGems do
        local gem = gemTypes[math.random(1, #gemTypes)]
        GameState.AddGem(gem.id, 1, 1)
    end

    -- 发放排名材料奖励
    if reward.materials then
        GameState.AddMaterials(reward.materials)
    end

    GameState.worldBoss.lastReward = prevSeason
    SaveSystem.SaveNow()

    print("[WorldBoss] Season reward claimed: rank=" .. tostring(rank)
        .. " prisms=" .. reward.prisms .. " chippedGems=" .. reward.chippedGems
        .. " materials=" .. (reward.materials and "yes" or "none"))
    return true, reward
end

-- ============================================================================
-- 战斗模式 Boss 配置生成
-- ============================================================================

--- 生成世界Boss怪物模板 (供 Spawner 使用)
function WorldBoss.GenerateBossTemplate()
    local bossCfg = WorldBoss.GetCurrentBoss()
    local playerPower = GameState.records.maxPower or 1000

    return {
        id          = "world_boss",
        name        = bossCfg.name,
        hp          = BOSS_HP_BASE,
        atk         = math.floor(GameState.GetMaxHP() * bossCfg.atkMul),
        speed       = 25,
        def         = 0,
        atkInterval = 2.0,
        element     = bossCfg.element,
        expDrop     = 0,
        goldDrop    = { 0, 0 },
        image       = bossCfg.image,
        radius      = 40,
        color       = bossCfg.color,
        isBoss      = true,
        isWorldBoss = true,
        antiHeal    = true,
        -- Boss 技能配置 (从 BOSS_ROSTER 透传)
        barrage      = bossCfg.barrage,
        dragonBreath = bossCfg.dragonBreath,
        iceArmor     = bossCfg.iceArmor,
        frozenField  = bossCfg.frozenField,
        iceRegen     = bossCfg.iceRegen,
    }
end

-- ============================================================================
-- 常量导出
-- ============================================================================

WorldBoss.MAX_ATTEMPTS   = MAX_ATTEMPTS
WorldBoss.FIGHT_DURATION = FIGHT_DURATION
WorldBoss.RANK_REWARDS   = RANK_REWARDS

-- ============================================================================
-- GameMode 适配器
-- ============================================================================

do
    local GameMode  = require("GameMode")
    local adapter   = {}

    -- ── 生命周期 ──
    adapter.background = "world_boss_bg_20260310050648.png"

    function adapter:OnEnter()
        return WorldBoss.EnterFight()  -- false = 次数用完
    end

    function adapter:OnExit()
        WorldBoss.ExitToMain()
    end

    -- ── 战斗 ──

    function adapter:BuildSpawnQueue()
        local template = WorldBoss.GenerateBossTemplate()
        return {
            {
                templateId  = "world_boss",
                template    = template,
                scaleMul    = 1.0,
                isWorldBoss = true,
            },
        }
    end

    function adapter:GetBattleConfig()
        return {
            isBossWave            = true,
            bossTimerMax          = FIGHT_DURATION,
            startTimerImmediately = false,
        }
    end

    function adapter:OnEnemyKilled(bs, enemy)
        local Particles = require("battle.Particles")
        Particles.SpawnExplosion(bs.particles, enemy.x, enemy.y, enemy.color)
        self:_SpawnLootParticles(bs, enemy.x, enemy.y)
        return true
    end

    function adapter:OnDeath(bs)
        local totalDmg = 0
        local bossX, bossY = bs.areaW / 2, bs.areaH / 2
        for _, e in ipairs(bs.enemies) do
            if e.isBoss and e.maxHp then
                totalDmg = totalDmg + math.max(0, e.maxHp - e.hp)
                bossX, bossY = e.x, e.y
            end
        end
        WorldBoss.fightDamage = totalDmg
        WorldBoss.EndFight()
        self:_SpawnLootParticles(bs, bossX, bossY)
        bs.worldBossEndDelay = 1.5
        print("[WorldBoss] Fight ended via death! Damage=" .. totalDmg)
        return true
    end

    function adapter:OnTimeout(bs)
        WorldBoss.EndFight()
        bs.worldBossEnded = true
        print("[BattleSystem] WorldBoss fight ended! Damage=" .. WorldBoss.fightDamage)
        return true
    end

    function adapter:CheckWaveComplete(_bs)
        return true  -- 世界Boss不检测波次完成
    end

    function adapter:SkipNormalExpDrop()
        return true
    end

    function adapter:IsTimerMode()
        return true
    end

    function adapter:GetDisplayName()
        local boss = WorldBoss.GetCurrentBoss()
        return boss and boss.name or "世界Boss"
    end

    --- 内部: 生成装备掉落粒子
    function adapter:_SpawnLootParticles(bs, bossX, bossY)
        local Particles = require("battle.Particles")
        local loot = WorldBoss.lastLoot
        if not loot or not loot.equips then return end
        for i, eq in ipairs(loot.equips) do
            local c = eq.color or { 200, 200, 200 }
            local name = eq.qualityName or ""
            local slotName = eq.slotName or "?"
            local offsetX = (i - 1) * 25 - (#loot.equips - 1) * 12
            Particles.SpawnEquipDrop(bs.particles,
                bossX + offsetX + math.random(-5, 5),
                bossY + math.random(-10, 0),
                name, slotName, c)
        end
        if loot.gold > 0 then
            Particles.SpawnReactionText(bs.particles,
                bossX, bossY - 30,
                "金币 +" .. loot.gold,
                { 255, 215, 0 })
        end
        if loot.crystal > 0 then
            Particles.SpawnReactionText(bs.particles,
                bossX, bossY - 50,
                "魂晶 +" .. loot.crystal,
                { 180, 100, 255 })
        end
    end

    GameMode.Register("worldBoss", adapter)
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "worldBoss",
    keys  = { "worldBoss" },
    group = "misc",
    serialize = function(GS)
        return {
            worldBoss = GS.worldBoss or nil,
        }
    end,
    deserialize = function(GS, data)
        if data.worldBoss and type(data.worldBoss) == "table" then
            GS.worldBoss = data.worldBoss
        end
    end,
})

return WorldBoss
