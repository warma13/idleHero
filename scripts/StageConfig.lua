-- ============================================================================
-- StageConfig.lua - 章节关卡配置 (第一章: 灰烬荒原)
-- 数值基准: 1级玩家 DPS≈18, 大量低血怪割草体验
-- ============================================================================

local StageConfig = {}

--- 延迟获取 GameState (避免循环依赖, Boss回调运行时才调用)
---@return table GameState
local function GS()
    return require("GameState")
end

--- 延迟获取 MonsterFamilies / BossArchetypes (避免循环依赖)
---@return table MonsterFamilies
local function MF()
    return require("MonsterFamilies")
end
---@return table BossArchetypes
local function BA()
    return require("BossArchetypes")
end

-- ============================================================================
-- 怪物模板
-- 血量说明 (1级玩家 DPS≈18):
--   ash_rat   35HP → ~2s击杀, 群体填充怪(蜂群)
--   void_bat  20HP → ~1s击杀, 高速脆皮(大量涌入)
--   spore_shroom 60HP → ~3s, 静止型减速怪
--   swamp_frog   50HP → ~3s, 中速中血
--   rot_worm  80HP → ~4s, 慢速肉盾
--   bandit    70HP → ~4s, 中速高攻精英
--   water_spirit 30HP → ~2s, 水元素填充
--   tide_crab 100HP → ~6s, 水系肉盾
--   中BOSS  800HP → ~45s, 需要技能配合
--   终BOSS 2500HP → ~2min, 后期玩家更强实际更快
-- ============================================================================

StageConfig.MONSTERS = {
    ash_rat = {
        name = "灰烬鼠", hp = 35, atk = 3, speed = 55, def = 0,
        atkInterval = 1.2, element = "fire",
        expDrop = 8, dropTemplate = "common",
        image = "Textures/mobs/ash_rat.png", radius = 14,
        color = { 140, 120, 100 },
    },
    rot_worm = {
        name = "腐土蠕虫", hp = 80, atk = 5, speed = 20, def = 1,
        atkInterval = 1.5, element = "poison", antiHeal = true,
        expDrop = 15, dropTemplate = "common",
        image = "Textures/mobs/rot_worm.png", radius = 16,
        color = { 120, 80, 160 },
    },
    void_bat = {
        name = "虚隙蝠", hp = 20, atk = 4, speed = 70, def = 0,
        atkInterval = 0.8, element = "arcane",
        expDrop = 6, dropTemplate = "common",
        image = "Textures/mobs/void_bat.png", radius = 12,
        color = { 80, 50, 120 },
    },
    bandit = {
        name = "荒原劫匪", hp = 70, atk = 8, speed = 40, def = 2,
        atkInterval = 1.0, element = "physical",
        expDrop = 18, dropTemplate = "common",
        image = "Textures/mobs/bandit.png", radius = 16,
        color = { 180, 140, 100 },
    },
    spore_shroom = {
        name = "孢子菇", hp = 60, atk = 5, speed = 25, def = 1,
        atkInterval = 1.0, element = "poison", antiHeal = true,
        slowOnHit = 0.3, slowDuration = 2.0,
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/spore_shroom.png", radius = 14,
        color = { 100, 180, 80 },
    },
    swamp_frog = {
        name = "沼泽蛙", hp = 50, atk = 6, speed = 45, def = 1,
        atkInterval = 1.0, element = "ice",
        slowOnHit = 0.2, slowDuration = 1.5,
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/swamp_frog.png", radius = 15,
        color = { 60, 140, 80 },
    },
    -- 水元素怪物
    water_spirit = {
        name = "水灵", hp = 30, atk = 4, speed = 50, def = 1,
        atkInterval = 1.0, element = "water",
        expDrop = 8, dropTemplate = "common",
        image = "Textures/mobs/water_spirit.png", radius = 13,
        color = { 40, 100, 220 },
    },
    tide_crab = {
        name = "潮汐蟹", hp = 100, atk = 7, speed = 30, def = 3,
        atkInterval = 1.3, element = "water",
        slowOnHit = 0.25, slowDuration = 2.0,
        expDrop = 18, dropTemplate = "common",
        image = "Textures/mobs/tide_crab.png", radius = 17,
        color = { 30, 80, 180 },
    },
    -- ==================== 第二章: 冰封深渊 ====================
    frost_imp = {
        name = "霜魔小鬼", hp = 45, atk = 10, speed = 55, def = 1,
        atkInterval = 1.2, element = "ice",
        slowOnHit = 0.25, slowDuration = 1.5,
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/frost_imp.png", radius = 14,
        color = { 150, 200, 255 },
    },
    ice_wraith = {
        name = "寒魂幽灵", hp = 25, atk = 14, speed = 75, def = 0,
        atkInterval = 0.8, element = "ice",
        defPierce = 0.30, -- 无视30%DEF
        expDrop = 10, dropTemplate = "common",
        image = "Textures/mobs/ice_wraith.png", radius = 13,
        color = { 180, 220, 255 },
    },
    glacier_beetle = {
        name = "冰川甲虫", hp = 120, atk = 6, speed = 20, def = 8,
        atkInterval = 1.5, element = "ice", antiHeal = true,
        expDrop = 20, dropTemplate = "common",
        image = "Textures/mobs/glacier_beetle.png", radius = 17,
        color = { 100, 160, 200 },
    },
    snow_wolf = {
        name = "雪原狼", hp = 55, atk = 12, speed = 65, def = 2,
        atkInterval = 1.0, element = "physical",
        packBonus = 0.30, packThreshold = 3, -- >=3只同屏ATK+30%
        expDrop = 14, dropTemplate = "common",
        image = "Textures/mobs/snow_wolf.png", radius = 15,
        color = { 220, 230, 245 },
    },
    cryo_mage = {
        name = "冰霜术士", hp = 70, atk = 15, speed = 30, def = 3,
        atkInterval = 1.0, element = "ice",
        slowOnHit = 0.4, slowDuration = 2.5,
        isRanged = true,
        expDrop = 18, dropTemplate = "common",
        image = "Textures/mobs/cryo_mage.png", radius = 15,
        color = { 80, 130, 220 },
    },
    frozen_revenant = {
        name = "冰封亡灵", hp = 90, atk = 11, speed = 35, def = 4,
        atkInterval = 1.2, element = "ice", antiHeal = true,
        deathExplode = { element = "ice", dmgMul = 0.8, radius = 40 },
        expDrop = 16, dropTemplate = "common",
        image = "Textures/mobs/frozen_revenant.png", radius = 16,
        color = { 120, 150, 200 },
    },
    abyssal_jellyfish = {
        name = "深渊水母", hp = 40, atk = 8, speed = 40, def = 1,
        atkInterval = 1.0, element = "water",
        expDrop = 10, dropTemplate = "common",
        image = "Textures/mobs/abyssal_jellyfish.png", radius = 14,
        color = { 60, 80, 200 },
    },
    permafrost_golem = {
        name = "永冻傀儡", hp = 160, atk = 9, speed = 15, def = 11,
        atkInterval = 1.8, element = "ice", antiHeal = true,
        hpRegen = 0.03, -- 每5s回复3%HP
        hpRegenInterval = 5.0,
        expDrop = 25, dropTemplate = "common",
        image = "Textures/mobs/permafrost_golem.png", radius = 18,
        color = { 140, 180, 210 },
    },
    -- 第二章 BOSS
    boss_ice_witch = {
        name = "冰晶女巫", hp = 2240, atk = 20, speed = 25, def = 12,
        atkInterval = 1.5, element = "ice", antiHeal = true,
        slowOnHit = 0.5, slowDuration = 3.0,
        -- 冰棱弹幕: 每8s向周围发射冰棱
        barrage = { interval = 8.0, count = 6, dmgMul = 0.5, element = "ice" },
        -- 冰甲: HP<50%时受伤减半3s, CD15s
        iceArmor = { hpThreshold = 0.5, dmgReduce = 0.5, duration = 3.0, cd = 15.0 },
        expDrop = 600, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_ice_witch.png", radius = 28,
        color = { 100, 160, 240 }, isBoss = true,
    },
    boss_frost_dragon = {
        name = "深渊冰龙·寒渊", hp = 5120, atk = 28, speed = 18, def = 18,
        atkInterval = 2.0, element = "ice", antiHeal = true,
        slowOnHit = 0.4, slowDuration = 2.5,
        -- 龙息: 每10s锥形冰息
        dragonBreath = { interval = 10.0, dmgMul = 2.0, element = "ice" },
        -- 冰封领域: HP<60%时减速区域
        frozenField = { hpThreshold = 0.6, slowRate = 0.6, duration = 8.0, cd = 20.0 },
        -- 冰晶再生: HP<30%时每秒回复0.5%HP
        iceRegen = { hpThreshold = 0.3, regenPct = 0.005 },
        expDrop = 1500, dropTemplate = "boss",
        image = "Textures/mobs/boss_frost_dragon.png", radius = 35,
        color = { 80, 140, 230 }, isBoss = true,
    },
    -- 第一章 BOSS
    boss_corrupt_guard = {
        name = "腐化巡逻兵", hp = 640, atk = 12, speed = 30, def = 8,
        atkInterval = 1.5, element = "physical", antiHeal = true,
        expDrop = 300, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_corrupt_guard.png", radius = 28,
        color = { 160, 100, 60 }, isBoss = true,
    },
    boss_golem = {
        name = "荒原巨像", hp = 1600, atk = 18, speed = 20, def = 15,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.4, slowDuration = 3.0,
        expDrop = 800, dropTemplate = "boss",
        image = "Textures/mobs/boss_golem.png", radius = 32,
        color = { 130, 100, 160 }, isBoss = true,
    },
    -- ==================== 第三章: 熔岩炼狱 ====================
    lava_lizard = {
        name = "熔岩蜥蜴", hp = 60, atk = 16, speed = 55, def = 3,
        atkInterval = 1.2, element = "fire",
        expDrop = 18, dropTemplate = "common",
        image = "Textures/mobs/lava_lizard.png", radius = 14,
        color = { 220, 100, 40 },
    },
    volcano_moth = {
        name = "火山飞蛾", hp = 30, atk = 20, speed = 80, def = 0,
        atkInterval = 0.8, element = "fire",
        defPierce = 0.25,
        expDrop = 14, dropTemplate = "common",
        image = "Textures/mobs/volcano_moth.png", radius = 12,
        color = { 255, 150, 50 },
    },
    toxiflame_shroom = {
        name = "毒焰蘑菇", hp = 80, atk = 12, speed = 0, def = 4,
        atkInterval = 1.0, element = "poison", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.0,
        expDrop = 16, dropTemplate = "common",
        image = "Textures/mobs/toxiflame_shroom.png", radius = 14,
        color = { 140, 200, 60 },
    },
    rock_scorpion = {
        name = "岩甲巨蝎", hp = 180, atk = 14, speed = 20, def = 12,
        atkInterval = 1.5, element = "physical",
        hpRegen = 0.02, hpRegenInterval = 6.0,
        expDrop = 28, dropTemplate = "common",
        image = "Textures/mobs/rock_scorpion.png", radius = 18,
        color = { 120, 100, 80 },
    },
    molten_sprite = {
        name = "熔核精灵", hp = 45, atk = 22, speed = 60, def = 1,
        atkInterval = 1.0, element = "fire",
        deathExplode = { element = "fire", dmgMul = 1.0, radius = 50 },
        expDrop = 16, dropTemplate = "common",
        image = "Textures/mobs/molten_sprite.png", radius = 13,
        color = { 255, 200, 50 },
    },
    miasma_weaver = {
        name = "瘴气编织者", hp = 90, atk = 18, speed = 35, def = 4,
        atkInterval = 1.0, element = "poison",
        isRanged = true,
        slowOnHit = 0.30, slowDuration = 2.0,
        expDrop = 22, dropTemplate = "common",
        image = "Textures/mobs/miasma_weaver.png", radius = 15,
        color = { 130, 80, 180 },
    },
    lava_hound = {
        name = "熔岩猎犬", hp = 70, atk = 20, speed = 70, def = 4,
        atkInterval = 1.0, element = "fire",
        packBonus = 0.35, packThreshold = 3,
        expDrop = 20, dropTemplate = "common",
        image = "Textures/mobs/lava_hound.png", radius = 15,
        color = { 200, 80, 30 },
    },
    obsidian_guard = {
        name = "黑曜石守卫", hp = 220, atk = 10, speed = 15, def = 16,
        atkInterval = 1.8, element = "physical", antiHeal = true,
        deathExplode = { element = "fire", dmgMul = 0.6, radius = 35 },
        expDrop = 30, dropTemplate = "common",
        image = "Textures/mobs/obsidian_guard.png", radius = 19,
        color = { 50, 40, 50 },
    },
    -- 第三章 BOSS
    boss_lava_lord = {
        name = "熔岩领主·烬牙", hp = 7680, atk = 35, speed = 25, def = 20,
        atkInterval = 1.5, element = "fire", antiHeal = true,
        slowOnHit = 0.3, slowDuration = 2.0,
        barrage = { interval = 7.0, count = 8, dmgMul = 0.6, element = "fire" },
        iceArmor = { hpThreshold = 0.5, dmgReduce = 0.6, duration = 4.0, cd = 12.0 },
        expDrop = 2000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_lava_lord.png", radius = 30,
        color = { 255, 120, 30 }, isBoss = true,
    },
    boss_inferno_king = {
        name = "炼狱之王·焚渊", hp = 14080, atk = 45, speed = 20, def = 25,
        atkInterval = 2.0, element = "fire", antiHeal = true,
        slowOnHit = 0.4, slowDuration = 2.5,
        dragonBreath = { interval = 9.0, dmgMul = 2.5, element = "fire" },
        frozenField = { hpThreshold = 0.6, slowRate = 0.5, duration = 6.0, cd = 18.0 },
        iceRegen = { hpThreshold = 0.3, regenPct = 0.008 },
        expDrop = 4000, dropTemplate = "boss",
        image = "Textures/mobs/boss_inferno_king.png", radius = 36,
        color = { 200, 50, 20 }, isBoss = true,
    },
    -- ==================== 第四章: 幽暗墓域 ====================
    grave_rat = {
        name = "墓穴鼠", hp = 40, atk = 22, speed = 70, def = 0,
        atkInterval = 1.2, element = "physical",
        packBonus = 0.40, packThreshold = 4,
        expDrop = 10, dropTemplate = "common",
        image = "Textures/mobs/grave_rat.png", radius = 13,
        color = { 100, 80, 70 },
        resist = { poison = 0.40 },
    },
    skeleton_warrior = {
        name = "骸骨武士", hp = 130, atk = 20, speed = 40, def = 14,
        atkInterval = 1.3, element = "physical",
        expDrop = 22, dropTemplate = "common",
        image = "Textures/mobs/skeleton_warrior.png", radius = 16,
        color = { 200, 190, 170 },
        resist = { fire = -0.25, ice = 0.10, poison = 0.50, physical = 0.20 },
    },
    wraith = {
        name = "怨灵", hp = 35, atk = 28, speed = 55, def = 0,
        atkInterval = 0.9, element = "arcane",
        defPierce = 0.45,
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/wraith.png", radius = 14,
        color = { 120, 80, 180 },
        resist = { ice = 0.20, poison = 0.50, arcane = 0.30, physical = 0.50 },
    },
    corpse_spider = {
        name = "尸蛛", hp = 90, atk = 18, speed = 50, def = 4,
        atkInterval = 1.0, element = "poison", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.0,
        expDrop = 16, dropTemplate = "common",
        image = "Textures/mobs/corpse_spider.png", radius = 15,
        color = { 80, 100, 60 },
        resist = { fire = -0.20, poison = 0.50, water = 0.10 },
    },
    necro_acolyte = {
        name = "亡灵侍祭", hp = 75, atk = 24, speed = 45, def = 3,
        atkInterval = 1.0, element = "arcane",
        isRanged = true,
        healAura = { pct = 0.05, interval = 8.0, radius = 100 },
        expDrop = 20, dropTemplate = "common",
        image = "Textures/mobs/necro_acolyte.png", radius = 15,
        color = { 100, 60, 140 },
        resist = { poison = 0.40, arcane = 0.20 },
    },
    bone_golem = {
        name = "骨傀儡", hp = 280, atk = 15, speed = 30, def = 19,
        atkInterval = 1.8, element = "physical",
        deathExplode = { element = "arcane", dmgMul = 1.0, radius = 50 },
        expDrop = 30, dropTemplate = "common",
        image = "Textures/mobs/bone_golem.png", radius = 18,
        color = { 180, 170, 150 },
        resist = { fire = -0.30, poison = 0.50, water = 0.10, physical = 0.30 },
    },
    shadow_assassin = {
        name = "暗影刺客", hp = 50, atk = 35, speed = 65, def = 1,
        atkInterval = 0.8, element = "arcane",
        firstStrikeMul = 2.0,
        expDrop = 18, dropTemplate = "common",
        image = "Textures/mobs/shadow_assassin.png", radius = 14,
        color = { 60, 40, 80 },
        resist = { fire = 0.10, ice = 0.10, poison = 0.40, arcane = 0.30, physical = 0.40 },
    },
    cursed_knight = {
        name = "诅咒骑士", hp = 160, atk = 25, speed = 45, def = 9,
        atkInterval = 1.0, element = "arcane",
        lifesteal = 0.15,
        expDrop = 24, dropTemplate = "common",
        image = "Textures/mobs/cursed_knight.png", radius = 16,
        color = { 140, 50, 60 },
        resist = { ice = 0.10, poison = 0.50, arcane = 0.15, physical = 0.15 },
    },
    -- 第四章 BOSS
    boss_bone_lord = {
        name = "骨冠领主·厄亡", hp = 22400, atk = 55, speed = 25, def = 15,
        atkInterval = 1.5, element = "arcane", antiHeal = true,
        barrage = { interval = 12.0, count = 8, dmgMul = 0.6, element = "arcane" },
        iceArmor = { hpThreshold = 0.5, dmgReduce = 0.55, duration = 4.0, cd = 14.0 },
        summon = { interval = 12.0, monsterId = "skeleton_warrior", count = 2 },
        expDrop = 5000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_bone_lord.png", radius = 32,
        color = { 160, 130, 80 }, isBoss = true,
        resist = { fire = -0.20, ice = 0.15, poison = 0.50, arcane = 0.20, physical = 0.25 },
    },
    boss_tomb_king = {
        name = "墓域君王·永夜", hp = 41600, atk = 70, speed = 20, def = 20,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.5,
        barrage = { interval = 8.0, count = 10, dmgMul = 0.5, element = "arcane" },
        frozenField = { hpThreshold = 0.6, slowRate = 0.5, duration = 8.0, cd = 18.0 },
        iceRegen = { hpThreshold = 0.25, regenPct = 0.02 },
        expDrop = 8000, dropTemplate = "boss",
        image = "Textures/mobs/boss_tomb_king.png", radius = 36,
        color = { 80, 50, 120 }, isBoss = true,
        resist = { fire = 0.10, ice = 0.10, poison = 0.50, arcane = 0.30, physical = 0.20 },
    },
    -- ==================== 第五章: 深海渊域 ====================
    abyss_angler = {
        name = "深海灯笼鱼", hp = 50, atk = 30, speed = 65, def = 0,
        atkInterval = 1.2, element = "water",
        packBonus = 0.35, packThreshold = 3,
        expDrop = 14, dropTemplate = "common",
        image = "Textures/mobs/abyss_angler.png", radius = 14,
        color = { 20, 60, 160 },
        resist = { ice = -0.20, water = 0.50 },
    },
    storm_seahorse = {
        name = "风暴海马", hp = 45, atk = 35, speed = 75, def = 1,
        atkInterval = 0.9, element = "water",
        defPierce = 0.30,
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/storm_seahorse.png", radius = 13,
        color = { 80, 50, 180 },
        resist = { ice = -0.25, water = 0.50 },
    },
    venom_jelly = {
        name = "毒刺水母", hp = 55, atk = 25, speed = 40, def = 0,
        atkInterval = 1.0, element = "poison", antiHeal = true,
        slowOnHit = 0.30, slowDuration = 2.0,
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/venom_jelly.png", radius = 14,
        color = { 140, 60, 200 },
        resist = { poison = 0.50, water = 0.30, physical = 0.20 },
    },
    coral_guardian = {
        name = "珊瑚甲卫", hp = 200, atk = 18, speed = 20, def = 17,
        atkInterval = 1.5, element = "water",
        splitOnDeath = { childId = "coral_shard", count = 2 },
        expDrop = 28, dropTemplate = "common",
        image = "Textures/mobs/coral_guardian.png", radius = 18,
        color = { 200, 80, 60 },
        resist = { fire = -0.20, poison = 0.10, water = 0.50, physical = 0.30 },
    },
    -- 珊瑚甲卫分裂产物 (不再分裂)
    coral_shard = {
        name = "珊瑚碎片", hp = 60, atk = 12, speed = 35, def = 6,
        atkInterval = 1.2, element = "water",
        expDrop = 6, dropTemplate = "summon",
        image = "Textures/mobs/coral_guardian.png", radius = 11,
        color = { 200, 100, 80 },
        resist = { fire = -0.20, water = 0.50 },
    },
    sea_anemone = {
        name = "海葵祭司", hp = 85, atk = 28, speed = 35, def = 3,
        atkInterval = 1.0, element = "water",
        isRanged = true,
        healAura = { pct = 0.06, interval = 8.0, radius = 100 },
        expDrop = 22, dropTemplate = "common",
        image = "Textures/mobs/sea_anemone.png", radius = 15,
        color = { 40, 140, 120 },
        resist = { fire = -0.25, poison = 0.40, water = 0.50, arcane = 0.10 },
    },
    abyssal_crab = {
        name = "深渊巨蟹", hp = 300, atk = 20, speed = 15, def = 22,
        atkInterval = 1.8, element = "water",
        corrosion = { defReducePct = 0.08, stackMax = 5, duration = 8.0 },
        expDrop = 35, dropTemplate = "common",
        image = "Textures/mobs/abyssal_crab.png", radius = 19,
        color = { 20, 40, 100 },
        resist = { fire = -0.15, ice = 0.10, poison = 0.10, water = 0.50, physical = 0.40 },
    },
    ink_octopus = {
        name = "墨渊章鱼", hp = 100, atk = 32, speed = 50, def = 4,
        atkInterval = 1.0, element = "water",
        inkBlind = { atkReducePct = 0.25, duration = 4.0 },
        expDrop = 20, dropTemplate = "common",
        image = "Textures/mobs/ink_octopus.png", radius = 15,
        color = { 60, 20, 80 },
        resist = { ice = -0.20, poison = 0.30, water = 0.50 },
    },
    tide_merfolk = {
        name = "潮汐鲛人", hp = 180, atk = 30, speed = 50, def = 11,
        atkInterval = 1.0, element = "water",
        lifesteal = 0.20,
        expDrop = 26, dropTemplate = "common",
        image = "Textures/mobs/tide_merfolk.png", radius = 16,
        color = { 40, 120, 100 },
        resist = { poison = 0.15, water = 0.40, arcane = -0.20, physical = 0.10 },
    },
    -- 第五章 BOSS
    boss_siren = {
        name = "深渊女妖·塞壬", hp = 64000, atk = 85, speed = 25, def = 20,
        atkInterval = 1.5, element = "water", antiHeal = true,
        slowOnHit = 0.40, slowDuration = 2.5,
        barrage = { interval = 8.0, count = 10, dmgMul = 0.6, element = "water" },
        iceArmor = { hpThreshold = 0.5, dmgReduce = 0.50, duration = 4.0, cd = 12.0 },
        summon = { interval = 12.0, monsterId = "venom_jelly", count = 2 },
        expDrop = 10000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_siren.png", radius = 32,
        color = { 60, 100, 200 }, isBoss = true,
        resist = { ice = -0.15, poison = 0.40, water = 0.50, physical = 0.20 },
    },
    boss_leviathan = {
        name = "海渊之主·利维坦", hp = 128000, atk = 110, speed = 18, def = 30,
        atkInterval = 2.0, element = "water", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.5,
        dragonBreath = { interval = 9.0, dmgMul = 2.5, element = "water" },
        frozenField = { hpThreshold = 0.6, slowRate = 0.50, duration = 8.0, cd = 18.0 },
        iceRegen = { hpThreshold = 0.25, regenPct = 0.025 },
        expDrop = 15000, dropTemplate = "boss",
        image = "Textures/mobs/boss_leviathan.png", radius = 38,
        color = { 10, 30, 80 }, isBoss = true,
        resist = { fire = -0.10, poison = 0.30, water = 0.50, arcane = 0.15, physical = 0.30 },
    },
    -- ==================== 第六章: 雷鸣荒漠 ====================
    sand_scarab = {
        name = "沙漠甲虫", hp = 55, atk = 28, speed = 70, def = 1,
        atkInterval = 1.0, element = "physical",
        packBonus = 0.30, packThreshold = 4,
        expDrop = 18, dropTemplate = "common",
        image = "Textures/mobs/sand_scarab.png", radius = 13,
        color = { 200, 170, 80 },
        resist = { ice = -0.20, poison = 0.10, water = -0.25, physical = 0.30 },
    },
    thunder_scorpion = {
        name = "雷蝎", hp = 80, atk = 38, speed = 55, def = 3,
        atkInterval = 0.9, element = "arcane",
        chargeUp = { stackMax = 5, dmgMul = 2.5, resetOnTrigger = true },
        expDrop = 24, dropTemplate = "common",
        image = "Textures/mobs/thunder_scorpion.png", radius = 15,
        color = { 180, 130, 255 },
        resist = { fire = 0.10, ice = -0.15, poison = 0.30, water = -0.20, arcane = 0.40 },
    },
    dune_worm = {
        name = "沙丘蠕虫", hp = 250, atk = 22, speed = 18, def = 20,
        atkInterval = 1.8, element = "physical",
        firstStrikeMul = 2.0,
        expDrop = 32, dropTemplate = "common",
        image = "Textures/mobs/dune_worm.png", radius = 18,
        color = { 160, 140, 90 },
        resist = { fire = -0.15, poison = 0.20, water = -0.20, physical = 0.40 },
    },
    storm_hawk = {
        name = "风暴鹰", hp = 60, atk = 40, speed = 80, def = 0,
        atkInterval = 0.8, element = "arcane",
        defPierce = 0.30,
        expDrop = 20, dropTemplate = "common",
        image = "Textures/mobs/storm_hawk.png", radius = 14,
        color = { 140, 100, 220 },
        resist = { ice = -0.25, water = 0.10, arcane = 0.50 },
    },
    lightning_lizard = {
        name = "雷脊蜥", hp = 120, atk = 35, speed = 50, def = 8,
        atkInterval = 1.0, element = "fire",
        chainLightning = { bounces = 2, dmgMul = 0.50, element = "arcane", range = 80 },
        expDrop = 26, dropTemplate = "common",
        image = "Textures/mobs/lightning_lizard.png", radius = 16,
        color = { 220, 160, 50 },
        resist = { fire = 0.30, ice = -0.20, water = -0.15, arcane = 0.20, physical = 0.10 },
    },
    sand_wraith = {
        name = "荒漠蛛后", hp = 100, atk = 32, speed = 40, def = 4,
        atkInterval = 1.0, element = "poison",
        isRanged = true,
        sandStorm = { critReducePct = 0.20, duration = 5.0 },
        expDrop = 22, dropTemplate = "common",
        image = "Textures/mobs/sand_wraith.png", radius = 15,
        color = { 180, 160, 100 },
        resist = { fire = -0.20, poison = 0.50, physical = 0.10 },
    },
    desert_golem = {
        name = "沙漠傀儡", hp = 350, atk = 25, speed = 12, def = 25,
        atkInterval = 2.0, element = "physical",
        chargeUp = { stackMax = 8, dmgMul = 2.0, resetOnTrigger = true, isAOE = true, aoeRadius = 60 },
        hpRegen = 0.02, hpRegenInterval = 6.0,
        expDrop = 40, dropTemplate = "common",
        image = "Textures/mobs/desert_golem.png", radius = 19,
        color = { 170, 150, 100 },
        resist = { ice = 0.10, water = -0.25, arcane = -0.15, physical = 0.50 },
    },
    thunder_shaman = {
        name = "雷能巫师", hp = 200, atk = 35, speed = 45, def = 12,
        atkInterval = 1.2, element = "arcane",
        isRanged = true,
        lifesteal = 0.15,
        healAura = { pct = 0.05, interval = 8.0, radius = 100 },
        expDrop = 34, dropTemplate = "common",
        image = "Textures/mobs/thunder_shaman.png", radius = 16,
        color = { 200, 180, 255 },
        resist = { ice = -0.15, poison = 0.20, water = -0.20, arcane = 0.30 },
    },
    -- 第六章 BOSS
    boss_sandstorm_lord = {
        name = "沙暴君主·拉赫", hp = 192000, atk = 130, speed = 22, def = 24,
        atkInterval = 1.5, element = "arcane", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.0,
        barrage = { interval = 7.0, count = 12, dmgMul = 0.5, element = "arcane" },
        frozenField = { hpThreshold = 0.6, slowRate = 0.40, duration = 6.0, cd = 16.0 },
        iceArmor = { hpThreshold = 0.4, dmgReduce = 0.45, duration = 5.0, cd = 14.0 },
        summon = { interval = 10.0, monsterId = "thunder_scorpion", count = 3 },
        expDrop = 15000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_sandstorm_lord.png", radius = 36,
        color = { 200, 170, 60 }, isBoss = true,
        resist = { fire = 0.20, ice = -0.20, poison = 0.10, water = -0.15, arcane = 0.50, physical = 0.25 },
    },
    boss_thunder_titan = {
        name = "雷霆泰坦·奥西曼", hp = 224000, atk = 150, speed = 16, def = 35,
        atkInterval = 2.0, element = "fire", antiHeal = true,
        slowOnHit = 0.30, slowDuration = 2.5,
        dragonBreath = { interval = 8.0, dmgMul = 3.0, element = "fire" },
        frozenField = { hpThreshold = 0.55, slowRate = 0.55, duration = 8.0, cd = 18.0 },
        iceArmor = { hpThreshold = 0.35, dmgReduce = 0.55, duration = 5.0, cd = 15.0 },
        iceRegen = { hpThreshold = 0.20, regenPct = 0.020 },
        expDrop = 22000, dropTemplate = "boss",
        image = "Textures/mobs/boss_thunder_titan.png", radius = 40,
        color = { 255, 200, 50 }, isBoss = true,
        resist = { fire = 0.40, ice = 0.10, poison = -0.15, water = -0.20, arcane = 0.30, physical = 0.20 },
    },

    -- ==================== 第七章: 瘴毒密林 ====================
    plague_beetle = {
        name = "瘟疫甲虫", hp = 55, atk = 28, def = 1, speed = 70,
        atkInterval = 1.0, element = "poison",
        packBonus = 0.30, packThreshold = 4,
        expDrop = 450, dropTemplate = "common",
        image = "Textures/mobs/plague_beetle.png", radius = 13,
        color = {80, 140, 50},
        resist = { fire = -0.15, ice = 0, poison = 0.30, water = 0, arcane = 0, physical = 0.10 },
    },
    thorn_viper = {
        name = "荆棘蝮蛇", hp = 70, atk = 42, def = 2, speed = 65,
        atkInterval = 0.8, element = "poison",
        venomStack = { dmgPctPerStack = 0.02, stackMax = 8, duration = 6.0 },
        expDrop = 650, dropTemplate = "common",
        image = "Textures/mobs/thorn_viper.png", radius = 15,
        color = {120, 180, 40},
        resist = { fire = -0.30, ice = 0, poison = 0.40, water = -0.15, arcane = 0, physical = 0 },
    },
    jungle_panther = {
        name = "丛林黑豹", hp = 65, atk = 45, def = 2, speed = 80,
        atkInterval = 0.7, element = "physical",
        defPierce = 0.35, firstStrikeMul = 2.0,
        expDrop = 600, dropTemplate = "common",
        image = "Textures/mobs/jungle_panther.png", radius = 15,
        color = {60, 60, 60},
        resist = { fire = -0.15, ice = 0, poison = 0.10, water = 0, arcane = 0, physical = 0.30 },
    },
    vine_strangler = {
        name = "绞杀藤蔓", hp = 150, atk = 30, def = 14, speed = 25,
        atkInterval = 1.5, element = "physical",
        slowOnHit = 0.40, slowDuration = 2.5, antiHeal = true,
        expDrop = 700, dropTemplate = "common",
        image = "Textures/mobs/vine_strangler.png", radius = 17,
        color = {80, 120, 50},
        resist = { fire = -0.20, ice = 0.10, poison = 0.20, water = 0, arcane = 0, physical = 0.40 },
    },
    spore_lurker = {
        name = "孢子潜伏者", hp = 120, atk = 28, def = 9, speed = 35,
        atkInterval = 1.2, element = "poison",
        sporeCloud = { atkSpeedReducePct = 0.15, duration = 4.0 },
        deathExplode = { element = "poison", dmgMul = 0.8, radius = 45 },
        expDrop = 650, dropTemplate = "common",
        image = "Textures/mobs/spore_lurker.png", radius = 14,
        color = {160, 130, 80},
        resist = { fire = -0.20, ice = -0.15, poison = 0.50, water = 0, arcane = 0, physical = 0.10 },
    },
    toxic_wasp = {
        name = "毒雾黄蜂", hp = 50, atk = 30, def = 1, speed = 75,
        atkInterval = 0.9, element = "poison",
        venomStack = { dmgPctPerStack = 0.015, stackMax = 6, duration = 5.0 },
        packBonus = 0.25, packThreshold = 5,
        expDrop = 500, dropTemplate = "common",
        image = "Textures/mobs/toxic_wasp.png", radius = 12,
        color = {180, 200, 30},
        resist = { fire = -0.25, ice = 0, poison = 0.35, water = -0.10, arcane = 0, physical = 0 },
    },
    ironbark_treant = {
        name = "铁木树人", hp = 500, atk = 20, def = 36, speed = 10,
        atkInterval = 2.2, element = "physical",
        sporeCloud = { atkSpeedReducePct = 0.20, duration = 5.0 },
        hpRegen = 0.02, hpRegenInterval = 6.0,
        expDrop = 1100, dropTemplate = "common",
        image = "Textures/mobs/ironbark_treant.png", radius = 20,
        color = {100, 80, 50},
        resist = { fire = -0.30, ice = 0, poison = 0.20, water = -0.15, arcane = -0.10, physical = 0.50 },
    },
    mire_shaman = {
        name = "沼地巫师", hp = 180, atk = 38, def = 11, speed = 40,
        atkInterval = 1.2, element = "poison",
        isRanged = true, lifesteal = 0.18,
        healAura = { pct = 0.05, interval = 8.0, radius = 100 },
        expDrop = 950, dropTemplate = "common",
        image = "Textures/mobs/mire_shaman.png", radius = 16,
        color = {60, 160, 80},
        resist = { fire = -0.15, ice = 0, poison = 0.40, water = 0, arcane = 0.20, physical = 0 },
    },
    -- 第七章 BOSS
    boss_venom_queen = {
        name = "毒液女王·阿拉克涅", hp = 320000, atk = 200, speed = 22, def = 28,
        atkInterval = 1.5, element = "poison", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.0,
        barrage = { interval = 7.0, count = 14, dmgMul = 0.5, element = "poison" },
        iceArmor = { hpThreshold = 0.4, dmgReduce = 0.50, duration = 5.0, cd = 14.0 },
        summon = { interval = 10.0, monsterId = "thorn_viper", count = 3 },
        expDrop = 20000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_venom_queen.png", radius = 36,
        color = { 100, 200, 50 }, isBoss = true,
        resist = { fire = -0.20, ice = 0.10, poison = 0.50, water = -0.15, arcane = 0, physical = 0.20 },
    },
    boss_rotwood_mother = {
        name = "朽木之母·耶梦加得", hp = 640000, atk = 270, speed = 14, def = 42,
        atkInterval = 2.0, element = "physical", antiHeal = true,
        slowOnHit = 0.30, slowDuration = 2.5,
        dragonBreath = { interval = 8.0, dmgMul = 3.0, element = "physical" },
        frozenField = { hpThreshold = 0.55, slowRate = 0.50, duration = 7.0, cd = 18.0 },
        iceArmor = { hpThreshold = 0.35, dmgReduce = 0.55, duration = 5.0, cd = 15.0 },
        iceRegen = { hpThreshold = 0.20, regenPct = 0.022 },
        expDrop = 28000, dropTemplate = "boss",
        image = "Textures/mobs/boss_rotwood_mother.png", radius = 40,
        color = { 80, 60, 40 }, isBoss = true,
        resist = { fire = -0.15, ice = -0.10, poison = 0.30, water = 0, arcane = 0.10, physical = 0.40 },
    },
    -- ==================== 第八章: 虚空裂隙 ====================
    void_wisp = {
        name = "虚空游光", hp = 45, atk = 35, def = 1, speed = 75,
        atkInterval = 0.9, element = "arcane",
        packBonus = 0.35, packThreshold = 4,
        expDrop = 600, dropTemplate = "common",
        image = "Textures/mobs/void_wisp.png", radius = 12,
        color = {160, 80, 220},
        resist = { fire = 0, ice = 0, poison = -0.20, water = -0.15, arcane = 0.40, physical = -0.10 },
    },
    rift_stalker = {
        name = "裂隙潜行者", hp = 75, atk = 52, def = 3, speed = 70,
        atkInterval = 0.7, element = "arcane",
        defPierce = 0.40, firstStrikeMul = 2.2,
        expDrop = 800, dropTemplate = "common",
        image = "Textures/mobs/rift_stalker.png", radius = 15,
        color = {120, 50, 180},
        resist = { fire = -0.15, ice = 0, poison = -0.20, water = 0, arcane = 0.35, physical = 0.10 },
    },
    null_sentinel = {
        name = "虚无哨兵", hp = 200, atk = 35, def = 17, speed = 30,
        atkInterval = 1.4, element = "arcane",
        slowOnHit = 0.35, slowDuration = 2.0,
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 900, dropTemplate = "common",
        image = "Textures/mobs/null_sentinel.png", radius = 18,
        color = {100, 60, 160},
        resist = { fire = -0.15, ice = 0.10, poison = 0, water = -0.10, arcane = 0.45, physical = 0.30 },
    },
    phase_weaver = {
        name = "相位编织者", hp = 130, atk = 45, def = 8, speed = 45,
        atkInterval = 1.1, element = "arcane",
        isRanged = true, lifesteal = 0.15,
        healAura = { pct = 0.04, interval = 7.0, radius = 90 },
        expDrop = 850, dropTemplate = "common",
        image = "Textures/mobs/phase_weaver.png", radius = 15,
        color = {180, 100, 220},
        resist = { fire = 0, ice = -0.15, poison = 0, water = 0, arcane = 0.30, physical = -0.10 },
    },
    entropy_mote = {
        name = "熵灭微粒", hp = 60, atk = 38, def = 1, speed = 80,
        atkInterval = 0.8, element = "arcane",
        deathExplode = { element = "arcane", dmgMul = 1.0, radius = 50 },
        packBonus = 0.30, packThreshold = 5,
        expDrop = 650, dropTemplate = "common",
        image = "Textures/mobs/entropy_mote.png", radius = 11,
        color = {200, 120, 255},
        resist = { fire = -0.20, ice = -0.15, poison = 0, water = 0, arcane = 0.50, physical = -0.15 },
    },
    spatial_ripper = {
        name = "空间撕裂者", hp = 100, atk = 48, def = 4, speed = 55,
        atkInterval = 0.9, element = "arcane",
        venomStack = { dmgPctPerStack = 0.025, stackMax = 6, duration = 5.0 },
        expDrop = 750, dropTemplate = "common",
        image = "Textures/mobs/spatial_ripper.png", radius = 14,
        color = {140, 60, 200},
        resist = { fire = 0, ice = 0, poison = -0.15, water = -0.20, arcane = 0.35, physical = 0.10 },
    },
    void_colossus = {
        name = "虚空巨像", hp = 600, atk = 25, def = 40, speed = 10,
        atkInterval = 2.4, element = "arcane",
        sporeCloud = { atkSpeedReducePct = 0.25, duration = 5.0 },
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 1400, dropTemplate = "common",
        image = "Textures/mobs/void_colossus.png", radius = 22,
        color = {80, 40, 130},
        resist = { fire = -0.20, ice = -0.10, poison = 0.10, water = 0, arcane = 0.50, physical = 0.40 },
    },
    star_oracle = {
        name = "星辰神谕者", hp = 220, atk = 50, def = 12, speed = 40,
        atkInterval = 1.3, element = "arcane",
        isRanged = true, antiHeal = true,
        healAura = { pct = 0.06, interval = 7.0, radius = 110 },
        expDrop = 1200, dropTemplate = "common",
        image = "Textures/mobs/star_oracle.png", radius = 16,
        color = {220, 180, 255},
        resist = { fire = -0.10, ice = 0, poison = -0.15, water = 0, arcane = 0.40, physical = 0.10 },
    },
    -- 第八章 BOSS
    boss_void_prince = {
        name = "虚空亲王·艾瑟隆", hp = 384000, atk = 260, speed = 22, def = 35,
        atkInterval = 1.4, element = "arcane", antiHeal = true,
        slowOnHit = 0.30, slowDuration = 2.0,
        barrage = { interval = 6.0, count = 16, dmgMul = 0.5, element = "arcane" },
        iceArmor = { hpThreshold = 0.45, dmgReduce = 0.50, duration = 5.0, cd = 13.0 },
        summon = { interval = 10.0, monsterId = "rift_stalker", count = 3 },
        expDrop = 28000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_void_prince.png", radius = 38,
        color = { 160, 80, 220 }, isBoss = true,
        resist = { fire = -0.15, ice = 0, poison = -0.20, water = 0.10, arcane = 0.50, physical = 0.15 },
    },
    boss_rift_sovereign = {
        name = "裂隙君主·奥伯龙", hp = 832000, atk = 340, speed = 14, def = 50,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.5,
        dragonBreath = { interval = 7.0, dmgMul = 3.5, element = "arcane" },
        frozenField = { hpThreshold = 0.55, slowRate = 0.55, duration = 7.0, cd = 16.0 },
        iceArmor = { hpThreshold = 0.35, dmgReduce = 0.60, duration = 5.0, cd = 14.0 },
        iceRegen = { hpThreshold = 0.20, regenPct = 0.025 },
        expDrop = 36000, dropTemplate = "boss",
        image = "Textures/mobs/boss_rift_sovereign.png", radius = 42,
        color = { 100, 40, 180 }, isBoss = true,
        resist = { fire = -0.10, ice = -0.15, poison = 0.10, water = 0, arcane = 0.40, physical = 0.30 },
    },
    -- ==================== 第九章: 天穹圣域 ====================
    radiant_sprite = {
        name = "辉光精灵", hp = 55, atk = 40, def = 2, speed = 72,
        atkInterval = 0.85, element = "holy",
        packBonus = 0.35, packThreshold = 4,
        expDrop = 750, dropTemplate = "common",
        image = "Textures/mobs/radiant_sprite.png", radius = 12,
        color = {255, 220, 140},
        resist = { fire = 0.10, ice = 0, poison = -0.25, water = 0, arcane = -0.15, physical = -0.10, holy = 0.45 },
    },
    zealot_knight = {
        name = "狂信骑士", hp = 90, atk = 58, def = 4, speed = 65,
        atkInterval = 0.75, element = "holy",
        defPierce = 0.35, firstStrikeMul = 2.0,
        expDrop = 950, dropTemplate = "common",
        image = "Textures/mobs/zealot_knight.png", radius = 16,
        color = {240, 200, 100},
        resist = { fire = 0, ice = -0.15, poison = -0.20, water = 0, arcane = 0, physical = 0.20, holy = 0.40 },
    },
    golden_guardian = {
        name = "金甲守卫", hp = 250, atk = 38, def = 22, speed = 25,
        atkInterval = 1.5, element = "holy",
        slowOnHit = 0.30, slowDuration = 2.0,
        hpRegen = 0.02, hpRegenInterval = 5.0,
        expDrop = 1100, dropTemplate = "common",
        image = "Textures/mobs/golden_guardian.png", radius = 19,
        color = {220, 190, 80},
        resist = { fire = -0.10, ice = 0.10, poison = -0.15, water = 0, arcane = 0, physical = 0.35, holy = 0.50 },
    },
    celestial_mender = {
        name = "天穹治愈师", hp = 160, atk = 48, def = 9, speed = 42,
        atkInterval = 1.1, element = "holy",
        isRanged = true, lifesteal = 0.12,
        healAura = { pct = 0.05, interval = 6.0, radius = 100 },
        expDrop = 1000, dropTemplate = "common",
        image = "Textures/mobs/celestial_mender.png", radius = 15,
        color = {255, 240, 180},
        resist = { fire = 0, ice = -0.10, poison = -0.15, water = 0.10, arcane = 0, physical = -0.10, holy = 0.35 },
    },
    sanctum_wisp = {
        name = "圣光游魂", hp = 70, atk = 42, def = 1, speed = 78,
        atkInterval = 0.8, element = "holy",
        deathExplode = { element = "holy", dmgMul = 1.1, radius = 55 },
        packBonus = 0.30, packThreshold = 5,
        expDrop = 800, dropTemplate = "common",
        image = "Textures/mobs/sanctum_wisp.png", radius = 11,
        color = {255, 250, 200},
        resist = { fire = -0.15, ice = -0.15, poison = -0.20, water = 0, arcane = -0.10, physical = -0.15, holy = 0.55 },
    },
    halo_lancer = {
        name = "光环枪兵", hp = 120, atk = 52, def = 6, speed = 52,
        atkInterval = 0.9, element = "holy",
        venomStack = { dmgPctPerStack = 0.03, stackMax = 5, duration = 5.0 },
        expDrop = 900, dropTemplate = "common",
        image = "Textures/mobs/halo_lancer.png", radius = 15,
        color = {250, 210, 120},
        resist = { fire = 0, ice = 0, poison = -0.20, water = -0.10, arcane = 0, physical = 0.15, holy = 0.40 },
    },
    divine_colossus = {
        name = "圣域巨灵", hp = 700, atk = 30, def = 44, speed = 8,
        atkInterval = 2.5, element = "holy",
        sporeCloud = { atkSpeedReducePct = 0.30, duration = 5.0 },
        hpRegen = 0.02, hpRegenInterval = 5.0,
        expDrop = 1700, dropTemplate = "common",
        image = "Textures/mobs/divine_colossus.png", radius = 23,
        color = {200, 170, 60},
        resist = { fire = -0.15, ice = -0.10, poison = -0.10, water = 0, arcane = 0.10, physical = 0.45, holy = 0.55 },
    },
    seraph_invoker = {
        name = "炽天使祈唤者", hp = 260, atk = 55, def = 14, speed = 38,
        atkInterval = 1.3, element = "holy",
        isRanged = true, antiHeal = true,
        healAura = { pct = 0.07, interval = 7.0, radius = 120 },
        expDrop = 1500, dropTemplate = "common",
        image = "Textures/mobs/seraph_invoker.png", radius = 17,
        color = {255, 230, 160},
        resist = { fire = -0.10, ice = 0, poison = -0.15, water = 0, arcane = 0, physical = 0.10, holy = 0.45 },
    },
    -- 第九章 BOSS
    boss_archon = {
        name = "圣裁者·米迦勒", hp = 480000, atk = 300, speed = 20, def = 40,
        atkInterval = 1.3, element = "holy", antiHeal = true,
        slowOnHit = 0.30, slowDuration = 2.0,
        barrage = { interval = 5.5, count = 18, dmgMul = 0.55, element = "holy" },
        iceArmor = { hpThreshold = 0.45, dmgReduce = 0.55, duration = 5.0, cd = 12.0 },
        summon = { interval = 9.0, monsterId = "zealot_knight", count = 4 },
        expDrop = 35000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_archon.png", radius = 40,
        color = { 255, 220, 100 }, isBoss = true,
        resist = { fire = -0.10, ice = 0, poison = -0.25, water = 0, arcane = -0.10, physical = 0.20, holy = 0.50 },
    },
    boss_celestial_emperor = {
        name = "天穹帝皇·乌列尔", hp = 1024000, atk = 400, speed = 12, def = 58,
        atkInterval = 2.0, element = "holy", antiHeal = true,
        slowOnHit = 0.40, slowDuration = 2.5,
        dragonBreath = { interval = 6.5, dmgMul = 3.8, element = "holy" },
        frozenField = { hpThreshold = 0.55, slowRate = 0.60, duration = 7.0, cd = 15.0 },
        iceArmor = { hpThreshold = 0.35, dmgReduce = 0.65, duration = 5.0, cd = 13.0 },
        iceRegen = { hpThreshold = 0.20, regenPct = 0.03 },
        expDrop = 45000, dropTemplate = "boss",
        image = "Textures/mobs/boss_celestial_emperor.png", radius = 45,
        color = { 255, 200, 60 }, isBoss = true,
        resist = { fire = -0.10, ice = -0.10, poison = -0.15, water = 0, arcane = 0.10, physical = 0.30, holy = 0.45 },
    },

    -- ==================== 第十章: 永夜深渊 ====================
    abyss_shade = {
        name = "深渊暗影", hp = 65, atk = 45, speed = 72, def = 2,
        atkInterval = 1.0, element = "arcane",
        packBonus = 0.35, packThreshold = 4,
        expDrop = 900, dropTemplate = "common",
        image = "Textures/mobs/mob_abyss_shade_20260310091659.png", radius = 14,
        color = { 100, 50, 160 },
        resist = { fire = -0.20, ice = 0, poison = 0, water = 0, arcane = 0.40, physical = -0.10 },
    },
    night_reaper = {
        name = "永夜收割者", hp = 100, atk = 62, speed = 68, def = 5,
        atkInterval = 0.9, element = "arcane",
        defPierce = 0.40, firstStrikeMul = 2.2,
        expDrop = 1100, dropTemplate = "common",
        image = "Textures/mobs/mob_night_reaper_20260310091728.png", radius = 15,
        color = { 130, 40, 180 },
        resist = { fire = -0.15, ice = 0, poison = -0.20, water = 0, arcane = 0.35, physical = 0 },
    },
    dark_sentinel = {
        name = "暗之哨卫", hp = 300, atk = 42, speed = 25, def = 24,
        atkInterval = 1.5, element = "physical",
        slowOnHit = 0.35, slowDuration = 2.0,
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 1400, dropTemplate = "common",
        image = "Textures/mobs/mob_dark_sentinel_20260310091701.png", radius = 18,
        color = { 80, 70, 100 },
        resist = { fire = 0, ice = 0.10, poison = 0, water = -0.20, arcane = 0.30, physical = 0.20 },
    },
    corrupt_mage = {
        name = "腐化法师", hp = 180, atk = 55, speed = 42, def = 11,
        atkInterval = 1.2, element = "arcane",
        isRanged = true, lifesteal = 0.15,
        healAura = { pct = 0.04, interval = 7.0, radius = 90 },
        expDrop = 1200, dropTemplate = "common",
        image = "Textures/mobs/mob_corrupt_mage_20260310091712.png", radius = 15,
        color = { 120, 60, 180 },
        resist = { fire = -0.25, ice = 0, poison = 0, water = 0, arcane = 0.45, physical = -0.10 },
    },
    doom_wisp = {
        name = "末日游魂", hp = 80, atk = 48, speed = 78, def = 1,
        atkInterval = 0.9, element = "fire",
        deathExplode = { element = "fire", dmgMul = 1.2, radius = 55 },
        packBonus = 0.30, packThreshold = 5,
        expDrop = 1000, dropTemplate = "common",
        image = "Textures/mobs/mob_doom_wisp_20260310091652.png", radius = 13,
        color = { 200, 80, 40 },
        resist = { fire = 0.30, ice = -0.25, poison = 0, water = -0.15, arcane = 0, physical = 0 },
    },
    void_lancer = {
        name = "虚空枪兵", hp = 140, atk = 58, speed = 52, def = 7,
        atkInterval = 1.1, element = "arcane",
        venomStack = { dmgPctPerStack = 0.025, stackMax = 6, duration = 5.0 },
        expDrop = 1100, dropTemplate = "common",
        image = "Textures/mobs/mob_void_lancer_20260310091651.png", radius = 16,
        color = { 110, 50, 170 },
        resist = { fire = -0.15, ice = 0, poison = -0.15, water = 0, arcane = 0.30, physical = 0 },
    },
    abyssal_titan = {
        name = "深渊巨人", hp = 800, atk = 35, speed = 8, def = 48,
        atkInterval = 2.0, element = "physical",
        sporeCloud = { atkSpeedReducePct = 0.25, duration = 5.0 },
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 2000, dropTemplate = "common",
        image = "Textures/mobs/mob_abyssal_titan_20260310091724.png", radius = 22,
        color = { 60, 40, 80 },
        resist = { fire = 0, ice = 0, poison = -0.25, water = 0, arcane = 0.20, physical = 0.30 },
    },
    shadow_oracle = {
        name = "暗影神谕", hp = 280, atk = 60, speed = 38, def = 16,
        atkInterval = 1.3, element = "arcane",
        isRanged = true, antiHeal = true,
        healAura = { pct = 0.06, interval = 7.0, radius = 110 },
        expDrop = 1500, dropTemplate = "common",
        image = "Textures/mobs/mob_shadow_oracle_20260310091708.png", radius = 16,
        color = { 140, 60, 200 },
        resist = { fire = -0.20, ice = 0, poison = 0, water = -0.15, arcane = 0.40, physical = 0 },
    },
    boss_abyss_general = {
        name = "深渊魔将·暗噬者", hp = 576000, atk = 340, speed = 20, def = 45,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.0,
        barrage = { interval = 8.0, count = 10, dmgMul = 0.7, element = "arcane" },
        iceArmor = { hpThreshold = 0.50, dmgReduce = 0.55, duration = 5.0, cd = 14.0 },
        summon = { interval = 12.0, monsterId = "abyss_shade", count = 3 },
        expDrop = 55000, dropTemplate = "miniboss",
        image = "Textures/mobs/mob_boss_abyss_general_20260310091649.png", radius = 40,
        color = { 120, 50, 200 }, isBoss = true,
        resist = { fire = -0.25, ice = 0, poison = -0.15, water = 0, arcane = 0.50, physical = 0.10 },
    },
    boss_abyss_lord = {
        name = "深渊君王·虚无之主", hp = 1280000, atk = 450, speed = 12, def = 65,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.40, slowDuration = 2.5,
        dragonBreath = { interval = 10.0, dmgMul = 1.2, element = "arcane" },
        frozenField = { hpThreshold = 0.60, slowRate = 0.50, duration = 8.0, cd = 16.0 },
        iceArmor = { hpThreshold = 0.40, dmgReduce = 0.60, duration = 5.0, cd = 13.0 },
        iceRegen = { hpThreshold = 0.20, regenPct = 0.025 },
        expDrop = 70000, dropTemplate = "boss",
        image = "Textures/mobs/mob_boss_abyss_lord_20260310091656.png", radius = 45,
        color = { 140, 40, 220 }, isBoss = true,
        resist = { fire = -0.20, ice = 0.10, poison = -0.20, water = 0, arcane = 0.50, physical = 0.15 },
    },

    -- ==================== 第十一章: 焚天炼狱 ====================
    pyre_imp = {
        name = "焚炎小鬼", hp = 75, atk = 50, speed = 70, def = 3,
        atkInterval = 1.0, element = "fire",
        packBonus = 0.40, packThreshold = 4,
        expDrop = 1100, dropTemplate = "common",
        image = "Textures/mobs/mob_pyre_imp_20260310091844.png", radius = 14,
        color = { 255, 120, 30 },
        resist = { fire = 0.40, ice = -0.25, poison = 0, water = -0.15, arcane = 0, physical = -0.10 },
    },
    inferno_blade = {
        name = "炼狱刀客", hp = 110, atk = 68, speed = 66, def = 6,
        atkInterval = 0.9, element = "fire",
        defPierce = 0.45, firstStrikeMul = 2.5,
        expDrop = 1300, dropTemplate = "common",
        image = "Textures/mobs/mob_inferno_blade_20260310091854.png", radius = 15,
        color = { 220, 100, 20 },
        resist = { fire = 0.35, ice = -0.20, poison = 0, water = -0.15, arcane = 0, physical = 0 },
    },
    molten_golem = {
        name = "熔金傀儡", hp = 350, atk = 48, speed = 22, def = 28,
        atkInterval = 1.5, element = "physical",
        slowOnHit = 0.40, slowDuration = 2.0,
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 1600, dropTemplate = "common",
        image = "Textures/mobs/mob_molten_golem_20260310091840.png", radius = 19,
        color = { 200, 160, 40 },
        resist = { fire = 0.30, ice = -0.15, poison = 0, water = -0.25, arcane = 0, physical = 0.25 },
    },
    hellfire_caster = {
        name = "狱火法师", hp = 200, atk = 62, speed = 40, def = 12,
        atkInterval = 1.2, element = "fire",
        isRanged = true, lifesteal = 0.18,
        healAura = { pct = 0.05, interval = 6.0, radius = 100 },
        expDrop = 1400, dropTemplate = "common",
        image = "Textures/mobs/mob_hellfire_caster_20260310091830.png", radius = 15,
        color = { 255, 80, 30 },
        resist = { fire = 0.45, ice = -0.25, poison = -0.10, water = 0, arcane = 0, physical = -0.10 },
    },
    cinder_wraith = {
        name = "余烬亡魂", hp = 90, atk = 55, speed = 76, def = 1,
        atkInterval = 0.9, element = "fire",
        deathExplode = { element = "fire", dmgMul = 1.3, radius = 55 },
        packBonus = 0.30, packThreshold = 5,
        expDrop = 1200, dropTemplate = "common",
        image = "Textures/mobs/mob_cinder_wraith_20260310091839.png", radius = 13,
        color = { 180, 100, 40 },
        resist = { fire = 0.30, ice = -0.30, poison = 0, water = -0.15, arcane = 0, physical = 0 },
    },
    scorch_knight = {
        name = "灼焰骑士", hp = 160, atk = 65, speed = 50, def = 8,
        atkInterval = 1.1, element = "fire",
        venomStack = { dmgPctPerStack = 0.03, stackMax = 5, duration = 5.0 },
        expDrop = 1300, dropTemplate = "common",
        image = "Textures/mobs/mob_scorch_knight_20260310091857.png", radius = 16,
        color = { 240, 110, 20 },
        resist = { fire = 0.30, ice = -0.15, poison = -0.15, water = 0, arcane = 0, physical = 0 },
    },
    purgatory_giant = {
        name = "炼狱巨兽", hp = 900, atk = 40, speed = 6, def = 56,
        atkInterval = 2.0, element = "physical",
        sporeCloud = { atkSpeedReducePct = 0.30, duration = 5.0 },
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 2400, dropTemplate = "common",
        image = "Textures/mobs/mob_purgatory_giant_20260310091828.png", radius = 22,
        color = { 180, 130, 30 },
        resist = { fire = 0.20, ice = 0, poison = -0.25, water = -0.15, arcane = 0, physical = 0.30 },
    },
    flame_hierophant = {
        name = "烈焰祭司", hp = 320, atk = 68, speed = 36, def = 17,
        atkInterval = 1.3, element = "fire",
        isRanged = true, antiHeal = true,
        healAura = { pct = 0.07, interval = 7.0, radius = 120 },
        expDrop = 1800, dropTemplate = "common",
        image = "Textures/mobs/mob_flame_hierophant_20260310091853.png", radius = 16,
        color = { 255, 140, 40 },
        resist = { fire = 0.40, ice = -0.20, poison = 0, water = -0.20, arcane = 0, physical = 0 },
    },
    boss_inferno_general = {
        name = "炼狱将军·焚骨者", hp = 704000, atk = 400, speed = 18, def = 52,
        atkInterval = 2.0, element = "fire", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.0,
        barrage = { interval = 7.0, count = 12, dmgMul = 0.75, element = "fire" },
        iceArmor = { hpThreshold = 0.50, dmgReduce = 0.60, duration = 5.0, cd = 13.0 },
        summon = { interval = 10.0, monsterId = "pyre_imp", count = 3 },
        expDrop = 65000, dropTemplate = "miniboss",
        image = "Textures/mobs/mob_boss_inferno_general_20260310091831.png", radius = 42,
        color = { 255, 100, 20 }, isBoss = true,
        resist = { fire = 0.50, ice = -0.25, poison = 0.10, water = -0.20, arcane = 0, physical = 0.10 },
    },
    boss_pyre_sovereign = {
        name = "焚天帝主·灭世之焰", hp = 1600000, atk = 520, speed = 10, def = 75,
        atkInterval = 2.0, element = "fire", antiHeal = true,
        slowOnHit = 0.45, slowDuration = 2.5,
        dragonBreath = { interval = 9.0, dmgMul = 1.3, element = "fire" },
        frozenField = { hpThreshold = 0.55, slowRate = 0.55, duration = 8.0, cd = 15.0 },
        iceArmor = { hpThreshold = 0.35, dmgReduce = 0.65, duration = 6.0, cd = 12.0 },
        iceRegen = { hpThreshold = 0.18, regenPct = 0.03 },
        expDrop = 85000, dropTemplate = "boss",
        image = "Textures/mobs/mob_boss_pyre_sovereign_20260310091909.png", radius = 48,
        color = { 255, 160, 30 }, isBoss = true,
        resist = { fire = 0.50, ice = -0.20, poison = 0.10, water = -0.15, arcane = 0, physical = 0.20 },
    },

    -- ==================== 第十二章: 时渊回廊 ====================
    -- 蜂群
    chrono_mite = {
        name = "时隙蜉蝣", hp = 95, atk = 62, speed = 72, def = 4,
        atkInterval = 1.0, element = "arcane",
        packBonus = 0.45, packThreshold = 4,
        expDrop = 1100, dropTemplate = "common",
        image = "Textures/mobs/mob_chrono_mite_20260311050719.png", radius = 10,
        color = { 140, 80, 200 },
        resist = { fire = -0.25, ice = 0, poison = 0, water = 0, arcane = 0.40, physical = -0.15 },
    },
    -- 高速刺客
    rewind_assassin = {
        name = "回溯刺客", hp = 130, atk = 82, speed = 70, def = 8,
        atkInterval = 0.9, element = "arcane",
        defPierce = 0.50, firstStrikeMul = 2.8,
        expDrop = 1400, dropTemplate = "common",
        image = "Textures/mobs/mob_rewind_assassin_20260311050743.png", radius = 14,
        color = { 120, 60, 180 },
        resist = { fire = -0.20, ice = 0, poison = 0, water = -0.10, arcane = 0.35, physical = -0.20 },
    },
    -- 肉盾
    eternal_sentinel = {
        name = "永恒哨卫", hp = 450, atk = 55, speed = 20, def = 33,
        atkInterval = 1.5, element = "physical",
        slowOnHit = 0.40, slowDuration = 2.0,
        hpRegen = 0.03, hpRegenInterval = 5.0,
        expDrop = 1600, dropTemplate = "common",
        image = "Textures/mobs/mob_eternal_sentinel_20260311050745.png", radius = 18,
        color = { 80, 100, 180 },
        resist = { fire = -0.15, ice = 0, poison = -0.20, water = 0, arcane = 0.30, physical = 0.30 },
    },
    -- 远程精英
    chrono_mage = {
        name = "时序术士", hp = 250, atk = 75, speed = 38, def = 14,
        atkInterval = 1.2, element = "arcane",
        isRanged = true, lifesteal = 0.20,
        expDrop = 1500, dropTemplate = "common",
        image = "Textures/mobs/mob_chrono_mage_20260311050720.png", radius = 15,
        color = { 160, 80, 220 },
        resist = { fire = -0.20, ice = 0.10, poison = -0.15, water = 0, arcane = 0.45, physical = -0.10 },
    },
    -- 自爆脆皮
    rift_phantom = {
        name = "时裂游魂", hp = 110, atk = 65, speed = 78, def = 2,
        atkInterval = 0.9, element = "arcane",
        deathExplode = { element = "arcane", dmgMul = 1.5, radius = 58 },
        packBonus = 0.35, packThreshold = 5,
        expDrop = 1200, dropTemplate = "common",
        image = "Textures/mobs/mob_rift_phantom_20260311050716.png", radius = 12,
        color = { 150, 90, 210 },
        resist = { fire = -0.25, ice = 0, poison = 0, water = 0, arcane = 0.35, physical = 0 },
    },
    -- 控制精英
    stasis_spider = {
        name = "迟滞蛛母", hp = 190, atk = 72, speed = 45, def = 11,
        atkInterval = 1.1, element = "arcane",
        venomStack = { dmgPctPerStack = 0.04, stackMax = 6, duration = 5.0 },
        slowOnHit = 0.35, slowDuration = 2.5,
        expDrop = 1300, dropTemplate = "common",
        image = "Textures/mobs/mob_stasis_spider_20260311050557.png", radius = 16,
        color = { 130, 70, 190 },
        resist = { fire = -0.20, ice = 0, poison = -0.15, water = 0, arcane = 0.35, physical = 0 },
    },
    -- 超级肉盾
    epoch_colossus = {
        name = "时渊巨像", hp = 1100, atk = 48, speed = 6, def = 68,
        atkInterval = 2.0, element = "physical",
        sporeCloud = { atkSpeedReducePct = 0.35, duration = 5.0 },
        hpRegen = 0.03, hpRegenInterval = 5.0,
        expDrop = 2800, dropTemplate = "common",
        image = "Textures/mobs/mob_epoch_colossus_20260311050558.png", radius = 24,
        color = { 100, 80, 160 },
        resist = { fire = -0.15, ice = 0, poison = -0.25, water = 0, arcane = 0.25, physical = 0.35 },
    },
    -- 远程祭司
    aeon_hierophant = {
        name = "永劫祭司", hp = 400, atk = 80, speed = 34, def = 20,
        atkInterval = 1.3, element = "arcane",
        isRanged = true, antiHeal = true,
        healAura = { pct = 0.08, interval = 7.0, radius = 120 },
        expDrop = 2000, dropTemplate = "common",
        image = "Textures/mobs/mob_aeon_hierophant_20260311050620.png", radius = 16,
        color = { 180, 100, 240 },
        resist = { fire = -0.20, ice = 0, poison = 0, water = -0.15, arcane = 0.45, physical = 0 },
    },
    -- 中章Boss
    boss_rift_lord = {
        name = "时空裂主·弗拉克图斯", hp = 896000, atk = 480, speed = 18, def = 62,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.40, slowDuration = 2.0,
        barrage = { interval = 7.0, count = 14, dmgMul = 0.80, element = "arcane" },
        iceArmor = { hpThreshold = 0.50, dmgReduce = 0.62, duration = 5.0, cd = 13.0 },
        summon = { interval = 10.0, monsterId = "chrono_mite", count = 4 },
        expDrop = 75000, dropTemplate = "miniboss",
        image = "Textures/mobs/mob_boss_rift_lord_20260311050623.png", radius = 44,
        color = { 160, 90, 220 }, isBoss = true,
        resist = { fire = -0.25, ice = 0.10, poison = 0.10, water = -0.15, arcane = 0.50, physical = -0.15 },
    },
    -- 章末Boss
    boss_chrono_sovereign = {
        name = "永恒钟主·克洛诺斯", hp = 2048000, atk = 620, speed = 10, def = 90,
        atkInterval = 2.0, element = "arcane", antiHeal = true,
        slowOnHit = 0.50, slowDuration = 2.5,
        dragonBreath = { interval = 9.0, dmgMul = 1.5, element = "arcane" },
        frozenField = { hpThreshold = 0.55, slowRate = 0.58, duration = 8.0, cd = 15.0 },
        chronoDecay = { hpThreshold = 0.55, atkSpdReducePerSec = 0.05, maxReduce = 0.50 },
        iceArmor = { hpThreshold = 0.35, dmgReduce = 0.68, duration = 6.0, cd = 12.0 },
        iceRegen = { hpThreshold = 0.18, regenPct = 0.035 },
        expDrop = 100000, dropTemplate = "boss",
        image = "Textures/mobs/mob_boss_chrono_sovereign_20260311050617.png", radius = 50,
        color = { 180, 110, 240 }, isBoss = true,
        resist = { fire = -0.20, ice = 0.10, poison = 0.10, water = -0.10, arcane = 0.55, physical = -0.10 },
    },

    -- ==================== 第十三章: 寒渊冰域 ====================
    -- 蜂群: 霜蚀虫群
    frost_mite = {
        name = "霜蚀虫群", hp = 115, atk = 75, speed = 74, def = 4,
        atkInterval = 1.0, element = "ice",
        slowOnHit = 0.15, slowDuration = 1.5,
        packBonus = 0.50, packThreshold = 4,
        expDrop = 10, dropTemplate = "common",
        image = "Textures/mobs/frost_mite.png", radius = 14,
        color = { 100, 200, 230 },
        resist = { fire = -0.30, ice = 0.40, poison = -0.10, water = 0.25, arcane = 0, physical = -0.15 },
    },
    -- 高速刺客: 冰棘猎手
    ice_stalker = {
        name = "冰棘猎手", hp = 155, atk = 98, speed = 72, def = 9,
        atkInterval = 1.2, element = "ice",
        defPierce = 0.55, firstStrikeMul = 3.0,
        expDrop = 14, dropTemplate = "common",
        image = "Textures/mobs/ice_stalker.png", radius = 13,
        color = { 120, 210, 240 },
        resist = { fire = -0.25, ice = 0.35, poison = -0.15, water = 0.20, arcane = 0, physical = -0.10 },
    },
    -- 肉盾: 永冻巨兽
    permafrost_beast = {
        name = "永冻巨兽", hp = 540, atk = 66, speed = 18, def = 40,
        atkInterval = 2.0, element = "physical", antiHeal = true,
        iceArmor = { hpThreshold = 0.60, dmgReduce = 0.25, duration = 5.0, cd = 10.0 },
        hpRegen = 0.03, hpRegenInterval = 5.0,
        expDrop = 22, dropTemplate = "elite",
        image = "Textures/mobs/permafrost_beast.png", radius = 20,
        color = { 140, 190, 210 },
        resist = { fire = -0.20, ice = 0.30, poison = -0.20, water = 0.15, arcane = 0, physical = 0.30 },
    },
    -- 远程精英: 冰川术士
    glacier_caster = {
        name = "冰川术士", hp = 300, atk = 90, speed = 36, def = 17,
        atkInterval = 1.5, element = "water", isRanged = true,
        lifesteal = 0.22,
        slowOnHit = 0.25, slowDuration = 2.0,
        expDrop = 20, dropTemplate = "elite",
        image = "Textures/mobs/glacier_caster.png", radius = 16,
        color = { 80, 170, 240 },
        resist = { fire = -0.25, ice = 0.35, poison = 0, water = 0.40, arcane = -0.15, physical = 0 },
    },
    -- 自爆脆皮: 冰晶爆破者
    cryo_wraith = {
        name = "冰晶爆破者", hp = 135, atk = 78, speed = 76, def = 3,
        atkInterval = 1.0, element = "ice",
        deathExplode = { element = "ice", dmgMul = 1.6, radius = 55 },
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/cryo_wraith.png", radius = 14,
        color = { 130, 220, 255 },
        resist = { fire = -0.30, ice = 0.35, poison = 0, water = 0.20, arcane = -0.10, physical = 0 },
    },
    -- 控制精英: 霜织蛛
    rime_weaver = {
        name = "霜织蛛", hp = 230, atk = 86, speed = 43, def = 13,
        atkInterval = 1.4, element = "water",
        slowOnHit = 0.40, slowDuration = 3.0,
        venomStack = { dmgPctPerStack = 0.025, stackMax = 6, duration = 5.0 },
        expDrop = 16, dropTemplate = "elite",
        image = "Textures/mobs/rime_weaver.png", radius = 15,
        color = { 90, 180, 220 },
        resist = { fire = -0.25, ice = 0.30, poison = -0.20, water = 0.30, arcane = 0, physical = 0 },
    },
    -- 超级肉盾: 冰渊泰坦
    glacial_titan = {
        name = "冰渊泰坦", hp = 1320, atk = 58, speed = 5, def = 80,
        atkInterval = 2.2, element = "physical", antiHeal = true,
        iceArmor = { hpThreshold = 0.50, dmgReduce = 0.30, duration = 6.0, cd = 12.0 },
        hpRegen = 0.03, hpRegenInterval = 4.0,
        expDrop = 28, dropTemplate = "elite",
        image = "Textures/mobs/glacial_titan.png", radius = 24,
        color = { 100, 180, 200 },
        resist = { fire = -0.20, ice = 0.25, poison = -0.25, water = 0.15, arcane = 0, physical = 0.35 },
    },
    -- 远程精英: 冰潮祭司
    frostfall_priest = {
        name = "冰潮祭司", hp = 480, atk = 96, speed = 32, def = 24,
        atkInterval = 1.6, element = "water", isRanged = true, antiHeal = true,
        healAura = { pct = 0.06, interval = 7.0, radius = 110 },
        expDrop = 24, dropTemplate = "elite",
        image = "Textures/mobs/frostfall_priest.png", radius = 16,
        color = { 70, 160, 230 },
        resist = { fire = -0.25, ice = 0.35, poison = 0, water = 0.45, arcane = -0.15, physical = 0 },
    },
    -- 中Boss: 霜暴领主·格拉西恩 (新模板系统, 2阶段)
    boss_frost_lord = {
        name = "霜暴领主·格拉西恩", hp = 1088000, atk = 576, speed = 16, def = 74,
        atkInterval = 2.0, element = "ice", isBoss = true,
        expDrop = 85000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_frost_lord.png", radius = 44,
        color = { 80, 190, 255 },
        resist = { fire = -0.30, ice = 0.50, poison = -0.20, water = 0.35, arcane = 0.10, physical = -0.10 },
        -- 新模板系统: phases 阶段技能配置
        phases = {
            -- 阶段一 (100%→55%): 弹幕风暴
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage",  params = { count = 16, spread = 120, dmgMul = 0.85, speed = 200, interval = 6.0, onHit = { slow = 0.10, slowDuration = 1.5 } } },
                    { template = "ATK_spikes",   params = { count = 3, radius = 35, delay = 1.2, dmgMul = 1.2, lingerTime = 4.0, interval = 8.0, lingerEffect = { slow = 0.30 } } },
                    { template = "SUM_minion",   params = { monsterId = "frost_mite", count = 5, interval = 9.0 } },
                },
                transition = { hpThreshold = 0.55, duration = 1.0, text = "霜暴领域！" },
            },
            -- 阶段二 (55%→0%): 冰原领域
            {
                hpThreshold = 0.55,
                skills = {
                    { template = "ATK_barrage",  params = { count = 20, spread = 90, dmgMul = 0.85, speed = 220, interval = 6.0, onHit = { slow = 0.10, slowDuration = 1.5 } } },
                    { template = "CTL_field",    params = { radius = 120, dmgMul = 0.30, tickRate = 0.5, duration = 8.0, cd = 14.0, effect = { slow = 0.40 } } },
                    { template = "DEF_armor",    params = { hpThreshold = 0.45, dmgReduce = 0.65, duration = 5.0, cd = 13.0 } },
                    { template = "DEF_crystal",  params = { count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 12.0, spawnRadius = 80, onDestroy = { dmgMul = 0.5, radius = 40, element = "ice" } } },
                },
            },
        },
    },
    -- 章末Boss: 冰渊至尊·尼弗海姆 (新模板系统, 3阶段)
    boss_ice_sovereign = {
        name = "冰渊至尊·尼弗海姆", hp = 2496000, atk = 745, speed = 9, def = 108,
        atkInterval = 2.2, element = "ice", isBoss = true,
        expDrop = 120000, dropTemplate = "boss",
        image = "Textures/mobs/boss_ice_sovereign.png", radius = 50,
        color = { 60, 170, 240 },
        resist = { fire = -0.25, ice = 0.60, poison = -0.15, water = 0.40, arcane = -0.10, physical = 0.10 },
        -- 新模板系统: phases 阶段技能配置
        phases = {
            -- 阶段一 (100%→60%): 寒潮试探
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath",   params = { angle = 60, range = 150, dmgMul = 0.50, tickRate = 0.3, duration = 1.5, interval = 8.0, onHit = { frostbite = 0.05 } } },
                    { template = "ATK_pulse",    params = { speed = 80, width = 20, maxRadius = 200, dmgMul = 0.8, hitEffect = "stun", hitDuration = 0.5, interval = 10.0 } },
                    { template = "SUM_guard",    params = { count = 2, hpPct = 0.01, atkMul = 0.4, tauntWeight = 0.6, interval = 15.0, aura = { slow = 0.20, radius = 40 } } },
                },
                transition = { hpThreshold = 0.60, duration = 1.5, text = "绝对零度！" },
            },
            -- 阶段二 (60%→30%): 空间压缩
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_breath",   params = { angle = 90, range = 150, dmgMul = 0.65, tickRate = 0.3, duration = 1.5, interval = 8.0, onHit = { frostbite = 0.05 } } },
                    { template = "CTL_field",    params = { radius = 140, dmgMul = 0.35, tickRate = 0.5, duration = 10.0, cd = 16.0, effect = { slow = 0.55 } } },
                    { template = "CTL_barrier",  params = { count = 2, duration = 6.0, contactDmgMul = 0.3, interval = 14.0, onContact = { freeze = 1.0 } } },
                    { template = "CTL_decay",    params = { stat = "moveSpeed", reducePerSec = 0.02, maxReduce = 0.30, bonusOnHit = 0.05 } },
                    { template = "DEF_shield",   params = {
                        hpPct = 0.03, bossDmgReduce = 0.80, duration = 10.0, cd = 18.0, hpThreshold = 0.50, baseResist = 0.50,
                        shield_reaction = {
                            weakReaction = "melt", weakElement = "fire", weakMultiplier = 3.0,
                            wrongHitEffects = {
                                ice     = { shieldHeal = 0.05, bossHeal = 0.02 },
                                water   = { reflect = 0.30 },
                                physical = { atkSpeedReduce = 0.15, duration = 3.0 },
                                arcane  = { dmgFactor = 0.7 },
                                poison  = { dmgFactor = 0.5, dotOnSelf = 0.01 },
                            },
                            timeoutPenalty = { type = "bossHeal", healPct = 0.15 },
                        },
                    } },
                },
                transition = { hpThreshold = 0.30, duration = 2.0, text = "万物终将冰封！" },
            },
            -- 阶段三 (30%→0%): 永冻绞杀
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_armor",    params = { hpThreshold = 0.30, dmgReduce = 0.72, duration = 7.0, cd = 14.0 } },
                    { template = "DEF_regen",    params = { hpThreshold = 0.30, regenPct = 0.03 } },
                    { template = "CTL_vortex",   params = { radius = 100, pullSpeed = 30, coreDmgMul = 0.6, coreRadius = 30, duration = 4.0, interval = 12.0, coreEffect = { freeze = 1.0 } } },
                    { template = "ATK_detonate", params = { count = 4, hpPct = 0.008, timer = 8.0, dmgMul = 2.0, bossHealPct = 0.10, interval = 0, onExplode = { freeze = 2.0 } } },
                },
            },
        },
    },

    -- ==================== 第十四章: 腐蚀魔域 ====================
    -- 蜂群: 瘟蚀虫群
    plague_mite = {
        name = "瘟蚀虫群", hp = 138, atk = 90, speed = 76, def = 5,
        atkInterval = 1.0, element = "poison",
        packBonus = 0.55, packThreshold = 4,
        deathExplode = { element = "poison", dmgMul = 0.4, radius = 25 },
        expDrop = 12, dropTemplate = "common",
        image = "Textures/mobs/plague_mite.png", radius = 14,
        color = { 80, 180, 60 },
        resist = { fire = -0.30, ice = -0.20, poison = 0.40, water = 0.25, arcane = 0, physical = -0.10 },
    },
    -- 高速刺客: 毒刺猎手
    venom_stalker = {
        name = "毒刺猎手", hp = 186, atk = 118, speed = 74, def = 11,
        atkInterval = 1.2, element = "poison",
        defPierce = 0.60, firstStrikeMul = 3.0,
        corrosion = { defReducePct = 0.03, stackMax = 3, duration = 6.0 },
        expDrop = 16, dropTemplate = "common",
        image = "Textures/mobs/venom_stalker.png", radius = 13,
        color = { 100, 200, 70 },
        resist = { fire = -0.25, ice = -0.15, poison = 0.35, water = 0.20, arcane = 0, physical = -0.10 },
    },
    -- 肉盾: 腐朽巨兽
    rot_beast = {
        name = "腐朽巨兽", hp = 650, atk = 79, speed = 18, def = 46,
        atkInterval = 2.0, element = "physical", antiHeal = true,
        hpRegen = 0.03, hpRegenInterval = 5.0,
        expDrop = 26, dropTemplate = "elite",
        image = "Textures/mobs/rot_beast.png", radius = 20,
        color = { 100, 160, 60 },
        resist = { fire = -0.20, ice = -0.15, poison = 0.30, water = 0.15, arcane = 0, physical = 0.30 },
    },
    -- 远程精英: 枯萎术士
    blight_caster = {
        name = "枯萎术士", hp = 360, atk = 108, speed = 36, def = 20,
        atkInterval = 1.5, element = "poison", isRanged = true,
        lifesteal = 0.24,
        venomStack = { dmgPctPerStack = 0.012, stackMax = 5, duration = 6.0 },
        expDrop = 22, dropTemplate = "elite",
        image = "Textures/mobs/blight_caster.png", radius = 16,
        color = { 90, 170, 50 },
        resist = { fire = -0.25, ice = -0.10, poison = 0.40, water = 0.30, arcane = -0.15, physical = 0 },
    },
    -- 自爆脆皮: 孢子爆破者
    spore_wraith = {
        name = "孢子爆破者", hp = 162, atk = 94, speed = 78, def = 4,
        atkInterval = 1.0, element = "poison",
        deathExplode = { element = "poison", dmgMul = 1.8, radius = 55 },
        expDrop = 14, dropTemplate = "common",
        image = "Textures/mobs/spore_wraith.png", radius = 14,
        color = { 110, 200, 80 },
        resist = { fire = -0.30, ice = -0.15, poison = 0.35, water = 0.20, arcane = -0.10, physical = 0 },
    },
    -- 控制精英: 瘴毒蛛母
    miasma_weaver = {
        name = "瘴毒蛛母", hp = 276, atk = 103, speed = 43, def = 16,
        atkInterval = 1.4, element = "poison",
        venomStack = { dmgPctPerStack = 0.015, stackMax = 6, duration = 6.0 },
        corrosion = { defReducePct = 0.03, stackMax = 4, duration = 6.0 },
        expDrop = 18, dropTemplate = "elite",
        image = "Textures/mobs/miasma_weaver.png", radius = 15,
        color = { 120, 160, 80 },
        resist = { fire = -0.25, ice = -0.15, poison = 0.30, water = 0.25, arcane = 0, physical = 0 },
    },
    -- 超级肉盾: 瘟疫泰坦
    plague_titan = {
        name = "瘟疫泰坦", hp = 1580, atk = 70, speed = 5, def = 94,
        atkInterval = 2.2, element = "physical", antiHeal = true,
        hpRegen = 0.03, hpRegenInterval = 4.0,
        expDrop = 32, dropTemplate = "elite",
        image = "Textures/mobs/plague_titan.png", radius = 24,
        color = { 80, 150, 50 },
        resist = { fire = -0.20, ice = -0.15, poison = 0.25, water = 0.15, arcane = 0, physical = 0.35 },
    },
    -- 远程祭司: 毒雾祭司
    toxin_priest = {
        name = "毒雾祭司", hp = 576, atk = 115, speed = 32, def = 28,
        atkInterval = 1.6, element = "poison", isRanged = true, antiHeal = true,
        healAura = { pct = 0.05, interval = 7.0, radius = 110 },
        expDrop = 28, dropTemplate = "elite",
        image = "Textures/mobs/toxin_priest.png", radius = 16,
        color = { 70, 180, 60 },
        resist = { fire = -0.25, ice = -0.10, poison = 0.40, water = 0.35, arcane = -0.15, physical = 0 },
    },
    -- 中Boss: 剧毒母巢·维诺莎 (新模板系统, 2阶段)
    boss_venom_mother = {
        name = "剧毒母巢·维诺莎", hp = 1312000, atk = 690, speed = 18, def = 89,
        atkInterval = 1.8, element = "poison", isBoss = true,
        expDrop = 102000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_venom_mother.png", radius = 44,
        color = { 80, 200, 60 },
        resist = { fire = -0.30, ice = -0.20, poison = 0.50, water = 0.30, arcane = 0.10, physical = -0.10 },
        phases = {
            -- 阶段一 (100%→55%): 毒潮侵袭
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 18, spread = 140, dmgMul = 0.70, speed = 190, interval = 5.5,
                        onHit = function(bs, source)
                            GS().ApplyVenomStackDebuff(0.015, 8, 6.0)
                        end,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 4, radius = 30, delay = 1.0, dmgMul = 1.0, lingerTime = 5.0, interval = 7.0,
                        lingerEffect = { slow = 0.20 },
                        lingerOnTick = function(bs, source)
                            GS().ApplyVenomStackDebuff(0.015, 8, 6.0)
                        end,
                    }},
                    { template = "SUM_minion", params = { monsterId = "plague_mite", count = 6, interval = 8.0 } },
                },
                transition = { hpThreshold = 0.55, duration = 1.0, text = "毒巢觉醒！" },
            },
            -- 阶段二 (55%→0%): 毒巢领域
            {
                hpThreshold = 0.55,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 14, spread = 360, dmgMul = 0.70, speed = 160, interval = 6.0,
                        onHit = function(bs, source)
                            GS().ApplyVenomStackDebuff(0.015, 8, 6.0)
                        end,
                    }},
                    { template = "CTL_field", params = {
                        radius = 110, dmgMul = 0.25, tickRate = 0.5, duration = 7.0, cd = 13.0,
                        effect = function(bs, source)
                            GS().ApplyVenomStackDebuff(0.015, 8, 6.0)
                            GS().ApplyAntiHeal(0.50, 1.0)
                        end,
                    }},
                    { template = "DEF_armor", params = { hpThreshold = 0.40, dmgReduce = 0.60, duration = 5.0, cd = 12.0 } },
                    { template = "DEF_crystal", params = {
                        count = 2, hpPct = 0.018, healPct = 0.012, spawnInterval = 11.0, spawnRadius = 90,
                        onDestroy = function(bs, source)
                            -- 摧毁毒腺图腾: 清除玩家3层蚀毒
                            local gs = GS()
                            gs.venomStackCount = math.max(0, gs.venomStackCount - 3)
                            if gs.venomStackCount == 0 then
                                gs.venomStackTimer = 0
                                gs.venomStackDmgPct = 0
                                gs.venomStackMaxStacks = 0
                                gs.venomStackTickCD = 0
                            end
                        end,
                    }},
                },
            },
        },
    },
    -- 章末Boss: 腐蚀主宰·涅克洛斯 (新模板系统, 3阶段)
    boss_plague_sovereign = {
        name = "腐蚀主宰·涅克洛斯", hp = 3008000, atk = 895, speed = 10, def = 130,
        atkInterval = 2.2, element = "poison", isBoss = true,
        expDrop = 144000, dropTemplate = "boss",
        image = "Textures/mobs/boss_plague_sovereign.png", radius = 50,
        color = { 60, 180, 40 },
        resist = { fire = -0.25, ice = -0.15, poison = 0.60, water = 0.35, arcane = -0.10, physical = 0.10 },
        phases = {
            -- 阶段一 (100%→60%): 腐蚀试探
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 70, range = 160, dmgMul = 0.45, tickRate = 0.3, duration = 1.8, interval = 7.0,
                        onHit = function(bs, source)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                        end,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 3, radius = 35, delay = 1.2, dmgMul = 1.1, lingerTime = 5.0, interval = 9.0,
                        lingerEffect = function(bs, source)
                            GS().ApplyAntiHeal(0.40, 1.0)
                        end,
                    }},
                    { template = "SUM_guard", params = { count = 2, hpPct = 0.012, atkMul = 0.35, tauntWeight = 0.55, interval = 14.0 } },
                },
                transition = { hpThreshold = 0.60, duration = 1.5, text = "万物腐朽！" },
            },
            -- 阶段二 (60%→30%): 腐朽侵蚀
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 100, range = 160, dmgMul = 0.55, tickRate = 0.3, duration = 1.8, interval = 7.0,
                        onHit = function(bs, source)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                        end,
                    }},
                    { template = "CTL_decay", params = { stat = "def", reducePerSec = 0.015, maxReduce = 0.40, bonusOnHit = 0.04 } },
                    { template = "CTL_barrier", params = {
                        count = 2, duration = 7.0, contactDmgMul = 0.35, interval = 13.0,
                        onContact = function(bs, source)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                        end,
                    }},
                    { template = "CTL_field", params = {
                        radius = 130, dmgMul = 0.30, tickRate = 0.5, duration = 9.0, cd = 15.0,
                        effect = function(bs, source)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                            GS().ApplyAntiHeal(0.60, 1.0)
                        end,
                    }},
                    { template = "DEF_shield", params = {
                        hpPct = 0.035, bossDmgReduce = 0.80, duration = 10.0, cd = 20.0, hpThreshold = 0.50, baseResist = 0.50,
                        shield_reaction = {
                            weakReaction = "purify", weakElement = "fire", weakMultiplier = 2.5,
                            wrongHitEffects = {
                                poison   = { shieldHeal = 0.08, bossHeal = 0.02 },
                                water    = { spreadPoison = true, aoeRadius = 60 },
                                ice      = { dmgFactor = 0.6, slowSelf = 0.20 },
                                physical = { corrosion = 0.05, maxStack = 5 },
                                arcane   = { dmgFactor = 0.65 },
                            },
                            timeoutPenalty = { type = "bossBuff", atkBonus = 0.30, duration = 8.0 },
                        },
                    }},
                },
                transition = { hpThreshold = 0.30, duration = 2.0, text = "一切终将腐朽！" },
            },
            -- 阶段三 (30%→0%): 腐朽终焉
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_armor", params = { hpThreshold = 0.30, dmgReduce = 0.70, duration = 7.0, cd = 15.0 } },
                    { template = "DEF_regen", params = { hpThreshold = 0.30, regenPct = 0.025 } },
                    { template = "CTL_vortex", params = {
                        radius = 110, pullSpeed = 35, coreDmgMul = 0.55, coreRadius = 35, duration = 4.5, interval = 11.0,
                        coreEffect = function(bs, source)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                            GS().ApplyCorrosionDebuff(0.04, 10, 8.0)
                            GS().ApplyAntiHeal(0.80, 1.0)
                        end,
                    }},
                    { template = "ATK_detonate", params = {
                        count = 3, hpPct = 0.01, timer = 9.0, dmgMul = 2.2, bossHealPct = 0.08, interval = 0,
                        onExplode = function(bs, source)
                            GS().ApplyAntiHeal(1.0, 5.0)
                            -- 全场毒伤5s由antiHeal覆盖，DoT通过venomStack实现
                            GS().ApplyVenomStackDebuff(0.005, 1, 5.0) -- 0.5% maxHP/秒持续5s
                        end,
                    }},
                },
            },
        },
    },

    -- ==================== 第十五章: 天火之泉 ====================
    -- 蜂群: 烈焰小鬼
    flame_imp = {
        name = "烈焰小鬼", hp = 166, atk = 108, speed = 76, def = 6,
        atkInterval = 1.0, element = "fire",
        packBonus = 0.50, packThreshold = 4,
        deathExplode = { element = "fire", dmgMul = 0.4, radius = 20 },
        expDrop = 14, dropTemplate = "common",
        image = "Textures/mobs/flame_imp.png", radius = 14,
        color = { 240, 80, 30 },
        resist = { water = -0.30, ice = -0.20, fire = 0.40, poison = 0.25, arcane = 0, physical = -0.10 },
    },
    -- 高速刺客: 灼刃猎手
    ember_stalker = {
        name = "灼刃猎手", hp = 223, atk = 142, speed = 74, def = 13,
        atkInterval = 1.2, element = "fire",
        defPierce = 0.55, firstStrikeMul = 3.0,
        burnStack = { dmgPct = 0.018, atkSpdReduce = 0.03, maxStacks = 8, duration = 5.0 },
        expDrop = 19, dropTemplate = "common",
        image = "Textures/mobs/ember_stalker.png", radius = 13,
        color = { 255, 120, 40 },
        resist = { water = -0.25, ice = -0.15, fire = 0.35, poison = 0.20, arcane = 0, physical = -0.10 },
    },
    -- 肉盾: 熔岩巨兽
    magma_beast = {
        name = "熔岩巨兽", hp = 780, atk = 95, speed = 18, def = 62,
        atkInterval = 2.0, element = "fire",
        damageReflect = { element = "fire", pct = 0.15 },
        expDrop = 31, dropTemplate = "elite",
        image = "Textures/mobs/magma_beast.png", radius = 20,
        color = { 200, 60, 20 },
        resist = { water = -0.20, ice = -0.15, fire = 0.30, poison = 0.15, arcane = 0, physical = 0.30 },
    },
    -- 远程精英: 焚炎术士
    inferno_caster = {
        name = "焚炎术士", hp = 432, atk = 130, speed = 36, def = 24,
        atkInterval = 1.5, element = "fire", isRanged = true,
        lifesteal = 0.22,
        burnStack = { dmgPct = 0.018, atkSpdReduce = 0.03, maxStacks = 8, duration = 5.0 },
        expDrop = 26, dropTemplate = "elite",
        image = "Textures/mobs/inferno_caster.png", radius = 16,
        color = { 255, 100, 30 },
        resist = { water = -0.25, ice = -0.10, fire = 0.40, poison = 0.30, arcane = -0.15, physical = 0 },
    },
    -- 自爆脆皮: 余烬爆破者
    cinder_wraith = {
        name = "余烬爆破者", hp = 194, atk = 113, speed = 78, def = 5,
        atkInterval = 1.0, element = "fire",
        deathExplode = { element = "fire", dmgMul = 2.0, radius = 55 },
        burnStack = { dmgPct = 0.018, atkSpdReduce = 0.03, maxStacks = 8, duration = 5.0 },
        expDrop = 17, dropTemplate = "common",
        image = "Textures/mobs/cinder_wraith.png", radius = 14,
        color = { 255, 140, 50 },
        resist = { water = -0.30, ice = -0.15, fire = 0.35, poison = 0.20, arcane = -0.10, physical = 0 },
    },
    -- 控制精英: 狱火编织者
    hellfire_weaver = {
        name = "狱火编织者", hp = 331, atk = 124, speed = 43, def = 19,
        atkInterval = 1.4, element = "fire",
        burnStack = { dmgPct = 0.018, atkSpdReduce = 0.03, maxStacks = 8, duration = 5.0 },
        scorchOnHit = { dmgAmpPct = 0.03, maxStacks = 10, duration = 8.0 },
        expDrop = 22, dropTemplate = "elite",
        image = "Textures/mobs/hellfire_weaver.png", radius = 15,
        color = { 220, 70, 40 },
        resist = { water = -0.25, ice = -0.15, fire = 0.30, poison = 0.25, arcane = 0, physical = 0 },
    },
    -- 超级肉盾: 焰狱泰坦
    flame_titan = {
        name = "焰狱泰坦", hp = 1680, atk = 84, speed = 5, def = 125,
        atkInterval = 2.2, element = "fire",
        burnAura = { radius = 50, interval = 1.0 },
        expDrop = 38, dropTemplate = "elite",
        image = "Textures/mobs/flame_titan.png", radius = 24,
        color = { 180, 50, 20 },
        resist = { water = -0.20, ice = -0.15, fire = 0.25, poison = 0.15, arcane = 0, physical = 0.35 },
    },
    -- 远程祭司: 焚祭司
    pyre_priest = {
        name = "焚祭司", hp = 691, atk = 138, speed = 32, def = 34,
        atkInterval = 1.6, element = "fire", isRanged = true,
        healAura = { pct = 0.06, interval = 7.0, radius = 110 },
        scorchOnHit = { dmgAmpPct = 0.03, maxStacks = 10, duration = 8.0 },
        expDrop = 34, dropTemplate = "elite",
        image = "Textures/mobs/pyre_priest.png", radius = 16,
        color = { 200, 90, 30 },
        resist = { water = -0.25, ice = -0.10, fire = 0.40, poison = 0.35, arcane = -0.15, physical = 0 },
    },
    -- 中Boss: 灼翼领主·伊格尼斯 (新模板系统, 2阶段)
    boss_flame_lord = {
        name = "灼翼领主·伊格尼斯", hp = 1574400, atk = 828, speed = 20, def = 107,
        atkInterval = 1.6, element = "fire", isBoss = true,
        expDrop = 122000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_flame_lord.png", radius = 44,
        color = { 240, 80, 30 },
        resist = { water = -0.30, ice = -0.20, fire = 0.50, poison = 0.30, arcane = 0.10, physical = -0.10 },
        phases = {
            -- 阶段一 (100%→55%): 烈焰洗礼
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 20, spread = 150, dmgMul = 0.75, speed = 200, interval = 5.0,
                        onHit = function(bs, source)
                            GS().ApplyBlazeDebuff(0.018, 0.03, 8, 5.0, source.atk)
                        end,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 5, radius = 32, delay = 1.0, dmgMul = 1.1, lingerTime = 6.0, interval = 7.0,
                        lingerOnTick = function(bs, source)
                            GS().ApplyBlazeDebuff(0.018, 0.03, 8, 5.0, source.atk)
                        end,
                    }},
                    { template = "SUM_minion", params = { monsterId = "flame_imp", count = 5, interval = 8.0 } },
                },
                transition = { hpThreshold = 0.55, duration = 1.0, text = "烈焰燃尽一切！" },
            },
            -- 阶段二 (55%→0%): 焰翼领域
            {
                hpThreshold = 0.55,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 16, spread = 360, dmgMul = 0.75, speed = 170, interval = 6.0,
                        onHit = function(bs, source)
                            GS().ApplyBlazeDebuff(0.018, 0.03, 8, 5.0, source.atk)
                        end,
                    }},
                    { template = "CTL_field", params = {
                        radius = 120, dmgMul = 0.30, tickRate = 0.5, duration = 8.0, cd = 13.0,
                        effect = function(bs, source)
                            GS().ApplyBlazeDebuff(0.018, 0.03, 8, 5.0, source.atk)
                            GS().ApplyAntiHeal(0.40, 1.0)
                        end,
                    }},
                    { template = "DEF_armor", params = { hpThreshold = 0.40, dmgReduce = 0.55, duration = 5.0, cd = 12.0 } },
                    { template = "DEF_crystal", params = {
                        count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 11.0, spawnRadius = 85,
                        onDestroy = function(bs, source)
                            -- 摧毁焰核: 清除玩家3层灼烧
                            local gs = GS()
                            gs.blazeStacks = math.max(0, gs.blazeStacks - 3)
                            if gs.blazeStacks == 0 then
                                gs.blazeTimer = 0
                                gs.blazeDmgPct = 0
                                gs.blazeAtkSpdReduce = 0
                                gs.blazeMaxStacks = 0
                                gs.blazeTickCD = 0
                                gs.blazeBossAtk = 0
                            end
                        end,
                    }},
                },
            },
        },
    },
    -- 章末Boss: 焚天魔君·萨拉曼德 (新模板系统, 3阶段)
    boss_inferno_sovereign = {
        name = "焚天魔君·萨拉曼德", hp = 3609600, atk = 1074, speed = 12, def = 156,
        atkInterval = 2.0, element = "fire", isBoss = true,
        expDrop = 173000, dropTemplate = "boss",
        image = "Textures/mobs/boss_inferno_sovereign.png", radius = 50,
        color = { 255, 60, 20 },
        resist = { water = -0.25, ice = -0.15, fire = 0.60, poison = 0.35, arcane = -0.10, physical = 0.10 },
        phases = {
            -- 阶段一 (100%→60%): 灼热试探
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 75, range = 165, dmgMul = 0.50, tickRate = 0.3, duration = 2.0, interval = 7.0,
                        onHit = function(bs, source)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                        end,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 4, radius = 35, delay = 1.0, dmgMul = 1.2, lingerTime = 6.0, interval = 8.0,
                        lingerEffect = function(bs, source)
                            GS().ApplyAntiHeal(0.40, 1.0)
                        end,
                    }},
                    { template = "SUM_guard", params = {
                        count = 2, hpPct = 0.014, atkMul = 0.40, tauntWeight = 0.55, interval = 13.0,
                        scorchOnHit = { dmgAmpPct = 0.03, maxStacks = 10, duration = 8.0 },
                    }},
                },
                transition = { hpThreshold = 0.60, duration = 1.5, text = "焦土焚天！" },
            },
            -- 阶段二 (60%→30%): 焦土碾压
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 105, range = 165, dmgMul = 0.60, tickRate = 0.3, duration = 2.0, interval = 7.0,
                        onHit = function(bs, source)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                        end,
                    }},
                    { template = "CTL_decay", params = { stat = "atkSpeed", reducePerSec = 0.018, maxReduce = 0.35, bonusOnHit = 0.04 } },
                    { template = "CTL_barrier", params = {
                        count = 2, duration = 7.0, contactDmgMul = 0.40, interval = 12.0,
                        onContact = function(bs, source)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                        end,
                    }},
                    { template = "CTL_field", params = {
                        radius = 135, dmgMul = 0.35, tickRate = 0.5, duration = 9.0, cd = 15.0,
                        effect = function(bs, source)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                            GS().ApplyAntiHeal(0.55, 1.0)
                        end,
                    }},
                    { template = "DEF_shield", params = {
                        hpPct = 0.04, bossDmgReduce = 0.80, duration = 10.0, cd = 20.0, hpThreshold = 0.50, baseResist = 0.50,
                        shield_reaction = {
                            weakReaction = "quench", weakElement = "water", weakMultiplier = 2.8,
                            wrongHitEffects = {
                                fire     = { shieldHeal = 0.10, bossHeal = 0.03 },
                                poison   = { dmgFactor = 0.5, dotOnSelf = 0.015 },
                                ice      = { dmgFactor = 0.7, scorchSelf = 2 },
                                physical = { reflect = 0.25, atkSpeedReduce = 0.10 },
                                arcane   = { dmgFactor = 0.60 },
                            },
                            timeoutPenalty = { type = "explode", dmgMul = 1.5, scorchStacks = 5 },
                        },
                    }},
                },
                transition = { hpThreshold = 0.30, duration = 2.0, text = "万物终将化为灰烬！" },
            },
            -- 阶段三 (30%→0%): 焚天终焉
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_armor", params = { hpThreshold = 0.30, dmgReduce = 0.68, duration = 6.0, cd = 14.0 } },
                    { template = "DEF_regen", params = { hpThreshold = 0.30, regenPct = 0.028 } },
                    { template = "CTL_vortex", params = {
                        radius = 115, pullSpeed = 38, coreDmgMul = 0.60, coreRadius = 35, duration = 4.5, interval = 11.0,
                        coreEffect = function(bs, source)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                            GS().ApplyScorchDebuff(0.03, 10, 8.0)
                        end,
                    }},
                    { template = "ATK_detonate", params = {
                        count = 3, hpPct = 0.012, timer = 8.0, dmgMul = 2.4, bossHealPct = 0.09, interval = 0,
                        onExplode = function(bs, source)
                            -- 焚天风暴: 6s全场火伤 + 攻速-50% + 5层焚灼
                            for i = 1, 5 do
                                GS().ApplyScorchDebuff(0.03, 10, 8.0)
                            end
                        end,
                    }},
                },
            },
        },
    },

    -- ==================== 第16章: 深渊潮汐 (water) ====================
    -- 蜂群: 潮汐蟹群
    tidal_crab = {
        name = "潮汐蟹群", hp = 200, atk = 130, speed = 74, def = 8,
        atkInterval = 1.0, element = "water",
        packBonus = 0.48, packThreshold = 4,
        deathExplode = { element = "water", dmgMul = 0.4, radius = 18 },
        drenchStack = { perStack = 1, duration = 6.0, maxStacks = 8 },
        expDrop = 17, dropTemplate = "common",
        image = "Textures/mobs/tidal_crab.png", radius = 14,
        color = { 30, 90, 200 },
        resist = { fire = -0.20, ice = -0.25, poison = 0, water = 0.35, arcane = -0.15, physical = 0 },
    },
    -- 精锐打手: 深渊刺鳐
    abyssal_stingray = {
        name = "深渊刺鳐", hp = 268, atk = 170, speed = 72, def = 16,
        atkInterval = 0.9, element = "water",
        defPierce = 0.55, firstStrikeMul = 3.0,
        drenchStack = { perStack = 1, duration = 6.0, maxStacks = 8 },
        expDrop = 23, dropTemplate = "common",
        image = "Textures/mobs/abyssal_stingray.png", radius = 13,
        color = { 60, 40, 160 },
        resist = { fire = -0.15, ice = -0.25, poison = 0, water = 0.30, arcane = -0.20, physical = 0 },
    },
    -- 坦克肉盾: 珊瑚巨龟
    coral_tortoise = {
        name = "珊瑚巨龟", hp = 936, atk = 114, speed = 16, def = 75,
        atkInterval = 1.6, element = "water",
        hpRegen = 0.025, hpRegenInterval = 5.0,
        slowOnHit = 0.40, slowDuration = 2.0,
        expDrop = 37, dropTemplate = "elite",
        image = "Textures/mobs/coral_tortoise.png", radius = 20,
        color = { 40, 180, 160 },
        resist = { fire = -0.15, ice = -0.20, poison = -0.15, water = 0.40, arcane = 0, physical = 0.20 },
    },
    -- 远程法师: 深海巫师
    deepsea_warlock = {
        name = "深海巫师", hp = 518, atk = 156, speed = 34, def = 29,
        atkInterval = 1.2, element = "water", isRanged = true,
        lifesteal = 0.20,
        drenchStack = { perStack = 1, duration = 6.0, maxStacks = 8 },
        expDrop = 31, dropTemplate = "elite",
        image = "Textures/mobs/deepsea_warlock.png", radius = 16,
        color = { 20, 60, 140 },
        resist = { fire = -0.15, ice = -0.20, poison = -0.10, water = 0.45, arcane = -0.15, physical = 0 },
    },
    -- 自爆型: 膨胀水母
    bloat_jellyfish = {
        name = "膨胀水母", hp = 233, atk = 136, speed = 76, def = 6,
        atkInterval = 0.9, element = "water",
        deathExplode = { element = "water", dmgMul = 1.8, radius = 55 },
        packBonus = 0.35, packThreshold = 5,
        drenchStack = { perStack = 1, duration = 6.0, maxStacks = 8 },
        expDrop = 20, dropTemplate = "common",
        image = "Textures/mobs/bloat_jellyfish.png", radius = 14,
        color = { 80, 140, 220 },
        resist = { fire = -0.20, ice = -0.25, poison = 0, water = 0.30, arcane = -0.15, physical = 0 },
    },
    -- 控制型: 缠绕海蛇
    coil_serpent = {
        name = "缠绕海蛇", hp = 397, atk = 149, speed = 42, def = 23,
        atkInterval = 1.1, element = "water",
        venomStack = { dmgPctPerStack = 0.035, stackMax = 7, duration = 5.0 },
        slowOnHit = 0.35, slowDuration = 2.5,
        drenchStack = { perStack = 1, duration = 6.0, maxStacks = 8 },
        expDrop = 26, dropTemplate = "elite",
        image = "Textures/mobs/coil_serpent.png", radius = 15,
        color = { 30, 80, 170 },
        resist = { fire = -0.15, ice = -0.20, poison = 0.15, water = 0.35, arcane = -0.15, physical = 0 },
    },
    -- 超级坦克: 远古海魔
    ancient_kraken = {
        name = "远古海魔", hp = 2016, atk = 101, speed = 5, def = 150,
        atkInterval = 2.0, element = "water",
        sporeCloud = { atkSpeedReducePct = 0.30, duration = 5.0 },
        hpRegen = 0.025, hpRegenInterval = 5.0,
        expDrop = 46, dropTemplate = "elite",
        image = "Textures/mobs/ancient_kraken.png", radius = 24,
        color = { 40, 30, 120 },
        resist = { fire = -0.10, ice = -0.15, poison = -0.15, water = 0.40, arcane = 0, physical = 0.25 },
    },
    -- 精英祭司: 潮汐祭司
    tide_hierophant = {
        name = "潮汐祭司", hp = 830, atk = 166, speed = 30, def = 41,
        atkInterval = 1.3, element = "water", isRanged = true,
        antiHeal = true,
        healAura = { pct = 0.06, interval = 7.0, radius = 115 },
        drenchStack = { perStack = 1, duration = 6.0, maxStacks = 8 },
        expDrop = 41, dropTemplate = "elite",
        image = "Textures/mobs/tide_hierophant.png", radius = 16,
        color = { 50, 120, 200 },
        resist = { fire = -0.15, ice = -0.20, poison = 0, water = 0.45, arcane = -0.15, physical = 0 },
    },
    -- 中Boss: 潮涌将领·塞壬 (模板系统, 2阶段)
    boss_tide_commander = {
        name = "潮涌将领·塞壬", hp = 2952000, atk = 994, speed = 18, def = 128,
        atkInterval = 1.8, element = "water", isBoss = true,
        expDrop = 146000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_tide_commander.png", radius = 44,
        color = { 30, 90, 200 },
        resist = { fire = -0.15, ice = -0.25, poison = 0.15, water = 0.50, arcane = -0.15, physical = 0 },
        phases = {
            -- 阶段一 (100%→50%): 潮涌洗礼
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 18, spread = 140, dmgMul = 0.80, speed = 190, interval = 5.5,
                        onHit = function(bs, source)
                            GS().ApplyDrenchDebuff(1, 8, 6.0)
                        end,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 5, radius = 30, delay = 1.0, dmgMul = 1.0, lingerTime = 7.0, interval = 7.0,
                        lingerOnTick = function(bs, source)
                            GS().ApplyDrenchDebuff(1, 8, 6.0)
                        end,
                    }},
                    { template = "SUM_minion", params = { monsterId = "tidal_crab", count = 5, interval = 9.0 } },
                },
                transition = { hpThreshold = 0.50, duration = 1.0, text = "潮汐将吞没一切！" },
            },
            -- 阶段二 (50%→0%): 涌潮领域
            {
                hpThreshold = 0.50,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 14, spread = 360, dmgMul = 0.80, speed = 165, interval = 6.5,
                        onHit = function(bs, source)
                            GS().ApplyDrenchDebuff(1, 8, 6.0)
                        end,
                    }},
                    { template = "CTL_field", params = {
                        radius = 115, dmgMul = 0.28, tickRate = 0.5, duration = 8.0, cd = 14.0, hpThreshold = 0.50,
                        onTick = function(bs, source)
                            GS().ApplyDrenchDebuff(1, 8, 6.0)
                        end,
                    }},
                    { template = "DEF_armor", params = {
                        hpThreshold = 0.35, dmgReduce = 0.58, duration = 5.0, cd = 12.0,
                    }},
                    { template = "DEF_crystal", params = {
                        count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 12.0, spawnRadius = 85,
                    }},
                },
            },
        },
    },
    -- 终Boss: 万潮海主·勒维坦 (模板系统, 3阶段)
    boss_abyssal_leviathan = {
        name = "万潮海主·勒维坦", hp = 6768000, atk = 1289, speed = 10, def = 187,
        atkInterval = 2.0, element = "water", isBoss = true,
        expDrop = 208000, dropTemplate = "boss",
        image = "Textures/mobs/boss_abyssal_leviathan.png", radius = 50,
        color = { 20, 60, 180 },
        resist = { fire = -0.10, ice = -0.25, poison = 0.15, water = 0.60, arcane = -0.15, physical = 0.10 },
        phases = {
            -- 阶段一 (100%→60%): 深渊试探
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 70, range = 160, dmgMul = 0.50, tickRate = 0.3, duration = 2.0, interval = 7.0,
                        onHit = function(bs, source)
                            GS().ApplyTidalCorrosionDebuff(1, 10, 8.0)
                        end,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 4, radius = 32, delay = 1.0, dmgMul = 1.1, lingerTime = 7.0, interval = 8.0,
                        lingerOnTick = function(bs, source)
                            GS().ApplyDrenchDebuff(1, 8, 6.0)
                        end,
                    }},
                    { template = "SUM_guard", params = {
                        count = 2, hpPct = 0.014, atkMul = 0.40, tauntWeight = 0.55, interval = 13.0,
                    }},
                },
                transition = { hpThreshold = 0.60, duration = 1.5, text = "深渊万潮吞噬万物！" },
            },
            -- 阶段二 (60%→30%): 深渊碾压
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 100, range = 160, dmgMul = 0.55, tickRate = 0.3, duration = 2.0, interval = 7.0,
                        onHit = function(bs, source)
                            GS().ApplyTidalCorrosionDebuff(1, 10, 8.0)
                        end,
                    }},
                    { template = "CTL_decay", params = {
                        hpThreshold = 0.60, stat = "crit", reducePerSec = 0.015, maxReduce = 0.35, bonusOnHit = 0.035,
                    }},
                    { template = "CTL_barrier", params = {
                        count = 2, duration = 7.0, contactDmgMul = 0.40, interval = 12.0,
                        onContact = function(bs, source)
                            for i = 1, 3 do
                                GS().ApplyTidalCorrosionDebuff(1, 10, 8.0)
                            end
                        end,
                    }},
                    { template = "CTL_field", params = {
                        radius = 130, dmgMul = 0.32, tickRate = 0.5, duration = 9.0, cd = 15.0, hpThreshold = 0.60,
                        onTick = function(bs, source)
                            GS().ApplyTidalCorrosionDebuff(1, 10, 8.0)
                        end,
                    }},
                    { template = "DEF_shield", params = {
                        hpPct = 0.04, bossDmgReduce = 0.80, duration = 10.0, cd = 20.0, hpThreshold = 0.50,
                        baseResist = 0.50,
                        shieldElement = "water",
                        weakReaction = "freeze", weakElement = "ice", weakMultiplier = 2.8,
                        wrongHitEffects = {
                            water    = { shieldHeal = 0.10, bossHeal = 0.03 },
                            fire     = { dmgFactor = 0.6, selfBurn = 0.012 },
                            poison   = { dmgFactor = 0.5, drenchSelf = 2 },
                            physical = { reflect = 0.20, critReduce = 0.08 },
                            arcane   = { dmgFactor = 0.65 },
                        },
                        timeoutPenalty = { type = "tsunami", dmgMul = 1.5, drenchStacks = 5 },
                    }},
                },
                transition = { hpThreshold = 0.30, duration = 2.0, text = "万潮归一，众生沉沦！" },
            },
            -- 阶段三 (30%→0%): 万潮终焉
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_armor", params = {
                        hpThreshold = 0.30, dmgReduce = 0.65, duration = 6.0, cd = 14.0,
                    }},
                    { template = "DEF_regen", params = {
                        hpThreshold = 0.30, regenPct = 0.026,
                    }},
                    { template = "CTL_vortex", params = {
                        radius = 110, pullSpeed = 36, coreDmgMul = 0.55, coreRadius = 32, duration = 4.5, interval = 11.0,
                        onCoreTick = function(bs, source)
                            for i = 1, 2 do
                                GS().ApplyTidalCorrosionDebuff(1, 10, 8.0)
                            end
                        end,
                    }},
                    { template = "ATK_detonate", params = {
                        count = 3, hpPct = 0.012, timer = 8.0, dmgMul = 2.2, bossHealPct = 0.08, interval = 0,
                        onExplode = function(bs, source)
                            -- 万潮海啸: 6s全场水伤 + 5层潮蚀
                            for i = 1, 5 do
                                GS().ApplyTidalCorrosionDebuff(1, 10, 8.0)
                            end
                        end,
                    }},
                },
            },
        },
    },
    -- ==================== 第17章: 焰息回廊 (fire) ====================
    -- 复用第一章「灰烬荒原」怪物结构, 数值按章节17系数缩放
    -- 蜂群: 焰息蜂虫
    ember_swarm = {
        name = "焰息蜂虫", hp = 230, atk = 148, speed = 58, def = 9,
        atkInterval = 1.1, element = "fire",
        packBonus = 0.45, packThreshold = 4,
        deathExplode = { element = "fire", dmgMul = 0.35, radius = 16 },
        expDrop = 19, dropTemplate = "common",
        image = "Textures/mobs/ash_rat.png", radius = 14,
        color = { 200, 120, 40 },
        resist = { fire = 0.35, ice = -0.25, poison = -0.15, water = -0.20, arcane = -0.15, physical = 0 },
    },
    -- 肉盾: 熔壳蠕虫
    molten_worm = {
        name = "熔壳蠕虫", hp = 560, atk = 125, speed = 22, def = 45,
        atkInterval = 1.4, element = "fire", antiHeal = true,
        hpRegen = 0.02, hpRegenInterval = 5.0,
        expDrop = 28, dropTemplate = "common",
        image = "Textures/mobs/rot_worm.png", radius = 16,
        color = { 180, 80, 30 },
        resist = { fire = 0.40, ice = -0.25, poison = -0.15, water = -0.20, arcane = 0, physical = 0.15 },
    },
    -- 脆皮高速: 灰烬蝙蝠
    cinder_bat = {
        name = "灰烬蝙蝠", hp = 140, atk = 165, speed = 78, def = 4,
        atkInterval = 0.8, element = "fire",
        defPierce = 0.50,
        expDrop = 15, dropTemplate = "common",
        image = "Textures/mobs/void_bat.png", radius = 12,
        color = { 255, 100, 30 },
        resist = { fire = 0.30, ice = -0.30, poison = 0, water = -0.25, arcane = -0.20, physical = 0 },
    },
    -- 精英打手: 焰卫劫匪
    flame_bandit = {
        name = "焰卫劫匪", hp = 420, atk = 175, speed = 44, def = 30,
        atkInterval = 1.0, element = "fire",
        burnOnHit = { dmgPctPerTick = 0.02, tickInterval = 1.0, duration = 4.0 },
        expDrop = 32, dropTemplate = "elite",
        image = "Textures/mobs/bandit.png", radius = 16,
        color = { 220, 140, 50 },
        resist = { fire = 0.35, ice = -0.20, poison = -0.10, water = -0.15, arcane = -0.15, physical = 0.10 },
    },
    -- 减速毒菇: 焰孢菇
    ember_shroom = {
        name = "焰孢菇", hp = 380, atk = 140, speed = 26, def = 20,
        atkInterval = 1.0, element = "fire", antiHeal = true,
        slowOnHit = 0.35, slowDuration = 2.5,
        sporeCloud = { atkSpeedReducePct = 0.20, duration = 4.0 },
        expDrop = 24, dropTemplate = "common",
        image = "Textures/mobs/spore_shroom.png", radius = 14,
        color = { 200, 160, 40 },
        resist = { fire = 0.35, ice = -0.25, poison = 0.15, water = -0.20, arcane = -0.10, physical = 0 },
    },
    -- 中速跳跃: 焰蛙
    magma_frog = {
        name = "焰蛙", hp = 320, atk = 155, speed = 48, def = 18,
        atkInterval = 1.0, element = "fire",
        slowOnHit = 0.25, slowDuration = 1.5,
        burnOnHit = { dmgPctPerTick = 0.015, tickInterval = 1.0, duration = 3.0 },
        expDrop = 22, dropTemplate = "common",
        image = "Textures/mobs/swamp_frog.png", radius = 15,
        color = { 230, 100, 30 },
        resist = { fire = 0.35, ice = -0.25, poison = -0.10, water = -0.20, arcane = -0.15, physical = 0 },
    },
    -- 水元素对应: 焰灵
    fire_wisp = {
        name = "焰灵", hp = 180, atk = 138, speed = 54, def = 8,
        atkInterval = 1.0, element = "fire",
        burnOnHit = { dmgPctPerTick = 0.01, tickInterval = 1.0, duration = 3.0 },
        expDrop = 16, dropTemplate = "common",
        image = "Textures/mobs/water_spirit.png", radius = 13,
        color = { 255, 160, 40 },
        resist = { fire = 0.35, ice = -0.30, poison = 0, water = -0.25, arcane = -0.15, physical = 0 },
    },
    -- 水系肉盾对应: 熔岩甲蟹
    lava_crab = {
        name = "熔岩甲蟹", hp = 650, atk = 130, speed = 28, def = 55,
        atkInterval = 1.3, element = "fire",
        slowOnHit = 0.30, slowDuration = 2.0,
        hpRegen = 0.02, hpRegenInterval = 5.0,
        expDrop = 34, dropTemplate = "elite",
        image = "Textures/mobs/tide_crab.png", radius = 17,
        color = { 200, 80, 20 },
        resist = { fire = 0.40, ice = -0.20, poison = -0.15, water = -0.20, arcane = 0, physical = 0.20 },
    },
    -- 中Boss: 焰息守卫·炎魔
    boss_ember_guard = {
        name = "焰息守卫·炎魔", hp = 3400000, atk = 1080, speed = 20, def = 140,
        atkInterval = 1.8, element = "fire", isBoss = true,
        expDrop = 168000, dropTemplate = "miniboss",
        image = "Textures/mobs/boss_corrupt_guard.png", radius = 44,
        color = { 220, 100, 30 },
        resist = { fire = 0.50, ice = -0.25, poison = -0.15, water = -0.20, arcane = -0.15, physical = 0 },
        phases = {
            -- 阶段一 (100%→50%): 焰息风暴
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 16, spread = 130, dmgMul = 0.85, speed = 185, interval = 5.5,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 5, radius = 28, delay = 1.0, dmgMul = 1.0, lingerTime = 6.0, interval = 7.0,
                    }},
                    { template = "SUM_minion", params = { monsterId = "ember_swarm", count = 5, interval = 9.0 } },
                },
                transition = { hpThreshold = 0.50, duration = 1.0, text = "烈焰将焚尽一切！" },
            },
            -- 阶段二 (50%→0%): 焚天领域
            {
                hpThreshold = 0.50,
                skills = {
                    { template = "ATK_barrage", params = {
                        count = 12, spread = 360, dmgMul = 0.85, speed = 160, interval = 6.5,
                    }},
                    { template = "CTL_field", params = {
                        radius = 110, dmgMul = 0.30, tickRate = 0.5, duration = 7.0, cd = 14.0, hpThreshold = 0.50,
                    }},
                    { template = "DEF_armor", params = {
                        hpThreshold = 0.35, dmgReduce = 0.55, duration = 5.0, cd = 12.0,
                    }},
                    { template = "DEF_crystal", params = {
                        count = 2, hpPct = 0.02, healPct = 0.015, spawnInterval = 12.0, spawnRadius = 80,
                    }},
                },
            },
        },
    },
    -- 终Boss: 灰烬巨像·炎狱
    boss_ember_golem = {
        name = "灰烬巨像·炎狱", hp = 7800000, atk = 1400, speed = 12, def = 200,
        atkInterval = 2.0, element = "fire", isBoss = true,
        expDrop = 240000, dropTemplate = "boss",
        image = "Textures/mobs/boss_golem.png", radius = 50,
        color = { 200, 80, 20 },
        resist = { fire = 0.60, ice = -0.25, poison = -0.15, water = -0.15, arcane = -0.15, physical = 0.10 },
        phases = {
            -- 阶段一 (100%→60%): 灰烬试探
            {
                hpThreshold = 1.0,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 70, range = 155, dmgMul = 0.55, tickRate = 0.3, duration = 2.0, interval = 7.0,
                    }},
                    { template = "ATK_spikes", params = {
                        count = 4, radius = 30, delay = 1.0, dmgMul = 1.1, lingerTime = 7.0, interval = 8.0,
                    }},
                    { template = "SUM_guard", params = {
                        count = 2, hpPct = 0.014, atkMul = 0.40, tauntWeight = 0.55, interval = 13.0,
                    }},
                },
                transition = { hpThreshold = 0.60, duration = 1.5, text = "灰烬燃尽天地！" },
            },
            -- 阶段二 (60%→30%): 焚天碾压
            {
                hpThreshold = 0.60,
                skills = {
                    { template = "ATK_breath", params = {
                        angle = 100, range = 155, dmgMul = 0.60, tickRate = 0.3, duration = 2.0, interval = 7.0,
                    }},
                    { template = "CTL_decay", params = {
                        hpThreshold = 0.60, stat = "crit", reducePerSec = 0.015, maxReduce = 0.35, bonusOnHit = 0.035,
                    }},
                    { template = "CTL_barrier", params = {
                        count = 2, duration = 7.0, contactDmgMul = 0.40, interval = 12.0,
                    }},
                    { template = "CTL_field", params = {
                        radius = 125, dmgMul = 0.35, tickRate = 0.5, duration = 9.0, cd = 15.0, hpThreshold = 0.60,
                    }},
                    { template = "DEF_shield", params = {
                        hpPct = 0.04, bossDmgReduce = 0.80, duration = 10.0, cd = 20.0, hpThreshold = 0.50,
                        baseResist = 0.50,
                        shieldElement = "fire",
                        weakReaction = "melt", weakElement = "water", weakMultiplier = 2.8,
                        wrongHitEffects = {
                            fire     = { shieldHeal = 0.10, bossHeal = 0.03 },
                            water    = { dmgFactor = 0.6, selfBurn = 0.012 },
                            ice      = { dmgFactor = 0.7 },
                            poison   = { dmgFactor = 0.5 },
                            physical = { reflect = 0.20, critReduce = 0.08 },
                            arcane   = { dmgFactor = 0.65 },
                        },
                        timeoutPenalty = { type = "eruption", dmgMul = 1.5 },
                    }},
                },
                transition = { hpThreshold = 0.30, duration = 2.0, text = "焰息回廊，万物成灰！" },
            },
            -- 阶段三 (30%→0%): 焰息终焉
            {
                hpThreshold = 0.30,
                skills = {
                    { template = "DEF_armor", params = {
                        hpThreshold = 0.30, dmgReduce = 0.65, duration = 6.0, cd = 14.0,
                    }},
                    { template = "DEF_regen", params = {
                        hpThreshold = 0.30, regenPct = 0.028,
                    }},
                    { template = "CTL_vortex", params = {
                        radius = 105, pullSpeed = 38, coreDmgMul = 0.60, coreRadius = 30, duration = 4.5, interval = 11.0,
                    }},
                    { template = "ATK_detonate", params = {
                        count = 3, hpPct = 0.012, timer = 8.0, dmgMul = 2.3, bossHealPct = 0.08, interval = 0,
                    }},
                },
            },
        },
    },
}

-- ============================================================================
-- 章节定义
-- 每关 2-3 波, 总血量池约 7000-12000 (1级基准, scaleMul 递增)
-- ============================================================================

-- ============================================================================
-- 关卡自动编排模板 (10关标准模式)
-- 有 families 字段的章节使用此模板自动生成 waves
-- 设计文档: docs/系统设计/怪物家族重构设计.md §6
-- ============================================================================

local STAGE_TEMPLATES = {
    -- 关1: 纯蜂群入门
    {
        pattern = "swarm_only",
        waves = {
            { roles = { { role = "swarm", count = 25, family = "primary" } } },
            { roles = { { role = "swarm", count = 30, family = "primary" } } },
        },
    },
    -- 关2: 引入肉盾
    {
        pattern = "intro_tank",
        waves = {
            { roles = { { role = "swarm", count = 20, family = "primary" }, { role = "tank", count = 6, family = "primary" } } },
            { roles = { { role = "swarm", count = 15, family = "primary" }, { role = "tank", count = 8, family = "primary" } } },
        },
    },
    -- 关3: 脆皮海
    {
        pattern = "glass_rush",
        waves = {
            { roles = { { role = "glass", count = 30, family = "primary" } } },
            { roles = { { role = "glass", count = 35, family = "primary" } } },
        },
    },
    -- 关4: 引入精英
    {
        pattern = "intro_bruiser",
        waves = {
            { roles = { { role = "swarm", count = 20, family = "primary" }, { role = "bruiser", count = 8, family = "primary" } } },
            { roles = { { role = "bruiser", count = 10, family = "primary" }, { role = "tank", count = 6, family = "primary" } } },
        },
    },
    -- 关5: 中Boss
    {
        pattern = "mid_boss",
        waves = {
            { roles = { { role = "bruiser", count = 12, family = "primary" }, { role = "tank", count = 6, family = "primary" } } },
            { roles = { { role = "boss_mid", count = 1 }, { role = "swarm", count = 20, family = "primary" } } },
        },
    },
    -- 关6: 混合（引入辅助家族）
    {
        pattern = "mixed_intro",
        waves = {
            { roles = { { role = "debuffer", count = 8, family = "primary" }, { role = "caster", count = 4, family = "secondary" }, { role = "swarm", count = 10, family = "secondary" } } },
            { roles = { { role = "swarm", count = 15, family = "secondary" }, { role = "debuffer", count = 8, family = "primary" } } },
        },
    },
    -- 关7: 减速地狱
    {
        pattern = "slow_hell",
        waves = {
            { roles = { { role = "debuffer", count = 10, family = "primary" }, { role = "tank", count = 6, family = "primary" }, { role = "swarm", count = 10, family = "secondary" } } },
            { roles = { { role = "tank", count = 8, family = "primary" }, { role = "debuffer", count = 8, family = "secondary" } } },
        },
    },
    -- 关8: 三波大混战
    {
        pattern = "triple_wave",
        waves = {
            { roles = { { role = "glass", count = 20, family = "primary" }, { role = "bruiser", count = 8, family = "secondary" } } },
            { roles = { { role = "bruiser", count = 10, family = "primary" }, { role = "tank", count = 6, family = "secondary" } } },
            { roles = { { role = "glass", count = 15, family = "secondary" }, { role = "exploder", count = 8, family = "primary" } } },
        },
    },
    -- 关9: 高密度三波
    {
        pattern = "high_density",
        waves = {
            { roles = { { role = "glass", count = 25, family = "primary" }, { role = "debuffer", count = 8, family = "secondary" } } },
            { roles = { { role = "debuffer", count = 12, family = "secondary" }, { role = "bruiser", count = 10, family = "primary" } } },
            { roles = { { role = "glass", count = 20, family = "primary" }, { role = "tank", count = 6, family = "secondary" } } },
        },
    },
    -- 关10: 终Boss
    {
        pattern = "final_boss",
        waves = {
            { roles = { { role = "swarm", count = 20, family = "primary" }, { role = "caster", count = 4, family = "primary" }, { role = "bruiser", count = 8, family = "secondary" } } },
            { roles = { { role = "boss_final", count = 1 }, { role = "swarm", count = 15, family = "secondary" }, { role = "exploder", count = 6, family = "primary" } } },
        },
    },
}

--- 自动编排：将章节配置 + 编排模板 → 10 关 waves
--- 仅对有 families 字段且无 stages 的章节调用
---@param chapterCfg table  章节配置（含 families, tagLevels, boss）
---@param chapter number    章节号
---@return table[] stages   10关配置（与手写 stages 格式完全一致）
local function generateStages(chapterCfg, chapter)
    local families = chapterCfg.families
    local primaryFamilyId  = families[1]
    local secondaryFamilyId = families[2] or families[1]
    local tagLevels = chapterCfg.tagLevels or {}

    local stages = {}
    for i, template in ipairs(STAGE_TEMPLATES) do
        local stage = { waves = {} }
        for _, waveDef in ipairs(template.waves) do
            local wave = { monsters = {} }
            for _, roleDef in ipairs(waveDef.roles) do
                if roleDef.role == "boss_mid" then
                    -- Boss 走原型解析，生成临时 ID 并注册到 MONSTERS
                    local bossConfig = chapterCfg.boss and chapterCfg.boss.mid
                    if bossConfig then
                        local bossId = BA().MakeBossId(bossConfig) .. "_ch" .. chapter
                        if not StageConfig.MONSTERS[bossId] then
                            StageConfig.MONSTERS[bossId] = BA().Resolve(bossConfig, chapter)
                        end
                        table.insert(wave.monsters, { id = bossId, count = 1 })
                    end
                elseif roleDef.role == "boss_final" then
                    local bossConfig = chapterCfg.boss and chapterCfg.boss.final
                    if bossConfig then
                        local bossId = BA().MakeBossId(bossConfig) .. "_ch" .. chapter
                        if not StageConfig.MONSTERS[bossId] then
                            StageConfig.MONSTERS[bossId] = BA().Resolve(bossConfig, chapter)
                        end
                        table.insert(wave.monsters, { id = bossId, count = 1 })
                    end
                else
                    -- 通过家族+行为模板组装怪物 ID
                    local familyId = roleDef.family == "secondary" and secondaryFamilyId or primaryFamilyId
                    local monsterId = familyId .. "_" .. roleDef.role
                    -- 惰性注册到 MONSTERS（首次访问时生成）
                    if not StageConfig.MONSTERS[monsterId] then
                        StageConfig.MONSTERS[monsterId] = MF().Resolve(familyId, roleDef.role, chapter, tagLevels)
                    end
                    table.insert(wave.monsters, { id = monsterId, count = roleDef.count })
                end
            end
            table.insert(stage.waves, wave)
        end
        table.insert(stages, stage)
    end
    return stages
end

--- 生成并缓存自动编排关卡（避免重复计算）
---@type table<number, table[]>
local generatedStagesCache_ = {}

--- 获取自动编排关卡（带缓存）
---@param chapterCfg table  章节配置
---@param chapter number    章节号
---@return table[] stages
local function getGeneratedStages(chapterCfg, chapter)
    if not generatedStagesCache_[chapter] then
        generatedStagesCache_[chapter] = generateStages(chapterCfg, chapter)
    end
    return generatedStagesCache_[chapter]
end

-- ============================================================================
-- 怪物解析接口 (供 Spawner 调用)
-- 支持三种来源: MONSTERS 表 / 家族组合ID / Boss 原型
-- ============================================================================

--- 解析怪物ID为 Spawner 兼容定义
--- 优先查 MONSTERS 表（含自动注册的家族怪和 Boss），
--- 若未命中则尝试家族解析
---@param monsterId string   怪物ID
---@param chapter? number    章节号 (家族解析时需要)
---@param tagLevels? table   章节标签等级
---@return table|nil monsterDef
function StageConfig.ResolveMonster(monsterId, chapter, tagLevels)
    -- 1. MONSTERS 表直接命中（含惰性注册的家族怪/原型Boss）
    if StageConfig.MONSTERS[monsterId] then
        return StageConfig.MONSTERS[monsterId]
    end

    -- 2. 尝试家族组合ID解析: "familyId_behaviorId"
    local def = MF().ResolveById(monsterId, chapter, tagLevels)
    if def then
        -- 惰性注册，后续访问直接命中
        StageConfig.MONSTERS[monsterId] = def
        return def
    end

    return nil
end

-- ============================================================================
-- 章节视觉主题 (17个主题循环使用，仅用于 UI 显示)
-- ============================================================================

local CHAPTER_VISUALS = {
    { name = "灰烬荒原", desc = "焰息城外的第一步" },
    { name = "冰封深渊", desc = "永冻之地的严酷考验" },
    { name = "熔岩炼狱", desc = "岩浆与瘴气交织的地下深渊" },
    { name = "幽暗墓域", desc = "亡灵横行的地下墓穴" },
    { name = "深海渊域", desc = "潮汐与深渊交织的海底世界" },
    { name = "雷鸣荒漠", desc = "雷暴与黄沙交织的远古废墟" },
    { name = "瘴毒密林", desc = "瘴气与毒雾弥漫的远古密林" },
    { name = "虚空裂隙", desc = "时空碎裂的虚空异界" },
    { name = "天穹圣域", desc = "众神栖居的金色天界" },
    { name = "永夜深渊", desc = "堕落与毁灭的黑暗深渊" },
    { name = "焚天炼狱", desc = "焚尽万物的炼狱烈焰" },
    { name = "时渊回廊", desc = "时间法则崩塌的混沌维度" },
    { name = "寒渊冰域", desc = "远古冰封的极寒领域" },
    { name = "腐蚀魔域", desc = "瘴毒侵蚀的腐朽领域" },
    { name = "天火之泉", desc = "天火涌动的灼热泉源" },
    { name = "深渊潮汐", desc = "潮汐与暗涌交织的深渊海域" },
    { name = "焰息回廊", desc = "灰烬荒原的烈焰重生" },
}

-- ============================================================================
-- 无限章节生成器
-- 基于怪物家族 + Boss 原型公式化生成，不再手写 stages
-- ============================================================================

--- 8 个怪物家族，章节轮换使用
local FAMILY_IDS = {
    "undead", "beast", "elemental_fire", "elemental_ice",
    "elemental_poison", "arcane", "divine", "aquatic",
}

--- 家族对应元素
local FAMILY_ELEMENT = {
    undead = "arcane", beast = "physical", elemental_fire = "fire",
    elemental_ice = "ice", elemental_poison = "poison", arcane = "arcane",
    divine = "holy", aquatic = "water",
}

--- Boss 原型轮换池
local MID_BOSS_ARCHETYPES   = { "striker_2p", "charger_2p", "summoner_2p", "fortress_2p" }
local FINAL_BOSS_ARCHETYPES = { "sovereign_3p", "overlord_3p", "herald_3p" }

--- 生成第 n 章配置（纯公式，惰性缓存）
---@param n number 章节号 (从1开始)
---@return table chapterCfg  含 families + boss，供 generateStages() 使用
local function GenerateChapter(n)
    -- 视觉主题循环
    local vi = ((n - 1) % #CHAPTER_VISUALS) + 1
    local visual = CHAPTER_VISUALS[vi]

    -- 主/副家族轮换（相邻家族配对，保证不同）
    local nFam = #FAMILY_IDS
    local pi = ((n - 1) % nFam) + 1
    local si = (n % nFam) + 1
    local primaryFamily   = FAMILY_IDS[pi]
    local secondaryFamily = FAMILY_IDS[si]

    -- Boss 原型轮换
    local midArchetype   = MID_BOSS_ARCHETYPES[((n - 1) % #MID_BOSS_ARCHETYPES) + 1]
    local finalArchetype = FINAL_BOSS_ARCHETYPES[((n - 1) % #FINAL_BOSS_ARCHETYPES) + 1]
    local element        = FAMILY_ELEMENT[primaryFamily] or "physical"

    return {
        id   = n,
        name = visual.name,
        desc = visual.desc,
        families = { primaryFamily, secondaryFamily },
        boss = {
            mid   = { archetype = midArchetype,   element = element, family = primaryFamily },
            final = { archetype = finalArchetype, element = element, family = primaryFamily },
        },
    }
end

--- 章节缓存（惰性生成，避免重复计算）
local chapterCache_ = {}

--- 章节代理表：通过 metatable 实现无限章节的惰性生成
StageConfig.CHAPTERS = setmetatable({}, {
    __index = function(_, k)
        if type(k) ~= "number" or k < 1 then return nil end
        if not chapterCache_[k] then
            chapterCache_[k] = GenerateChapter(k)
        end
        return chapterCache_[k]
    end,
    __len = function()
        return 999  -- 无限章节上限（UI/逻辑安全边界）
    end,
})

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取指定章节关卡配置（双轨：手写 stages 或自动编排 families）
---@param chapter number 章节编号 (从1开始)
---@param stage number 关卡编号 (从1开始)
---@return table|nil stageCfg, table|nil chapterCfg
function StageConfig.GetStage(chapter, stage)
    local ch = StageConfig.CHAPTERS[chapter]
    if not ch then return nil, nil end

    -- 双轨: 有 stages → 旧逻辑; 有 families 且无 stages → 自动编排
    if ch.stages then
        return ch.stages[stage], ch
    elseif ch.families then
        local generated = getGeneratedStages(ch, chapter)
        return generated[stage], ch
    end
    return nil, ch
end

--- 获取章节总关卡数（双轨兼容）
function StageConfig.GetStageCount(chapter)
    local ch = StageConfig.CHAPTERS[chapter]
    if not ch then return 0 end
    if ch.stages then
        return #ch.stages
    elseif ch.families then
        return #STAGE_TEMPLATES  -- 自动编排固定 10 关
    end
    return 0
end

--- 获取总章节数
function StageConfig.GetChapterCount()
    return #StageConfig.CHAPTERS
end

-- ============================================================================
-- 动态 scaleMul 计算 (v1.9.1: 替代硬编码值, 与 tierMul 对齐)
-- ============================================================================
-- 设计目标:
--   scaleMul = difficultyRatio × tierMul(chapter)
--   difficultyRatio 在章节内从 s1 到 s10 指数递增 (~5.57x)
--   difficultyRatio 随章节缓慢增长 (每章 +8%), 模拟玩家技能/套装的额外成长
--
-- 效果 (v4, 技能百分比体系):
--   ch1 s1=4.6  s10=25.6   (swarm 40hp → fire_bolt ~8次击杀)
--   ch5 s1=72   s10=399    (swarm 40hp → fireball ~10次击杀)
--   ch10 s1=227 s10=1266   (swarm 40hp → fire_storm ~12次击杀)
--   ch17 s1=558 s10=3110   (swarm 40hp → fire_storm ~16次击杀)
-- ============================================================================

--- 章节内关卡难度插值系数 (指数插值, s1=1.0, s10=5.5714)
local STAGE_RAMP = 3.5  -- 章节内 boss 是初始的 3.5 倍 (削弱: 原 5.57)

-- ============================================================================
-- 玩家战力乘数 (v4: 技能百分比伤害体系)
-- ============================================================================
-- 背景: 技能系统改为 100%~1000% 武器伤害, 装备用 IP 体系
--   - 玩家 ATK = baseAtk(18) + 70*(IP/100), IP = 100+825*ln(ch)/ln(100)
--   - ch1 ATK≈88, ch5≈290, ch10≈377, ch17≈443 (仅 ~5x 增长)
--   - 技能倍率: fire_bolt 27%, fireball 96%, fire_storm 320%, meteor 800%
--
-- 旧 powerMul (1~217) 是为分裂弹体系设计的, 假设玩家DPS增长200+倍,
-- 但新体系下玩家总DPS增长仅 ~60x (ATK 5x × 技能升级 12x), 导致怪物血量超标.
--
-- 新设计: powerMul 只补偿 ATK 增长与 tierMul 之间的差距
--   tierMul = 1+99*ln(ch)/ln(100), ATK_ratio ≈ 1+4*ln(ch)/ln(100)
--   两者都随 ln(ch) 增长, 但 tierMul 系数(99)远大于 ATK_ratio 系数(~4)
--   powerMul ≈ ATK_ratio / tierMul × 调节常数K
--   K=4.0 使 swarm(hp=40) 被当前章节主力技能打 8~16 次击杀
--
-- 效果 (swarm, hp=40, stage 1):
--   ch1:  fire_bolt 27%  → ~8 次击杀
--   ch5:  fireball  96%  → ~10 次击杀
--   ch10: fire_storm 320% → ~12 次击杀
--   ch17: fire_storm 320% → ~16 次击杀
-- ============================================================================

--- 计算玩家战力乘数 (公式化, 无需手动维护)
---@param chapter number 章节编号
---@return number powerMul
local function getPlayerPowerMul(chapter)
    if chapter <= 1 then return 4.0 end

    local Config = require("Config")
    local tierMul = Config.GetChapterTier(chapter)  -- 1+99*ln(ch)/ln(100)

    -- 玩家ATK相对ch1的增长倍率
    local ip = Config.CalcBaseIP(chapter)
    local atkCh = 18 + 70 * (ip / 100)   -- totalATK(ch)
    local atkCh1 = 18 + 70 * 1.0         -- totalATK(ch1) = 88
    local atkRatio = atkCh / atkCh1       -- ~1x(ch1) ~ 5x(ch17)

    -- 技能解锁带来的DPS跳跃 (玩家在不同章节使用不同主力技能)
    -- fire_bolt=0.27, fireball=0.96, fire_storm=3.2, meteor=8.0
    local skillFactor
    if chapter <= 3 then
        skillFactor = 1.0     -- 基础技能(fire_bolt), 基准
    elseif chapter <= 8 then
        skillFactor = 3.56    -- fireball/96% 相对 fire_bolt/27%
    else
        skillFactor = 11.85   -- fire_storm/320% 相对 fire_bolt/27%
    end

    -- DPS比率 = ATK增长 × 技能升级
    local dpsRatio = atkRatio * skillFactor

    -- K=4.0: 调节常数, 控制基准击杀次数
    local K = 4.0
    return dpsRatio / tierMul * K
end

--- 计算动态 scaleMul (替代硬编码值)
---@param chapter number 章节编号 (从1开始)
---@param stageIdx number 关卡编号 (从1开始)
---@return number scaleMul
function StageConfig.CalcScaleMul(chapter, stageIdx)
    local Config = require("Config")
    local tierMul = Config.GetChapterTier(chapter)

    -- 难度比率: 随章节缓慢增长 (每章 +3%, 削弱: 原 6%)
    local chGrowth = 1 + 0.03 * (chapter - 1)
    local baseRatio_s1 = 1.15 * chGrowth
    -- 章节内指数插值
    local stageCount = StageConfig.GetStageCount(chapter)
    local t = (stageIdx - 1) / math.max(1, stageCount - 1)  -- 0.0 ~ 1.0
    local difficultyRatio = baseRatio_s1 * (STAGE_RAMP ^ t)

    -- 玩家战力乘数: 补偿ATK增长与tierMul之间的差距 + 技能解锁DPS跳跃
    local powerMul = getPlayerPowerMul(chapter)

    return difficultyRatio * tierMul * powerMul
end

--- 获取关卡的 scaleMul (优先动态计算)
---@param chapter number 章节编号
---@param stage number 关卡编号
---@return number scaleMul
function StageConfig.GetScaleMul(chapter, stage)
    if chapter and stage and chapter >= 1 and stage >= 1 then
        return StageConfig.CalcScaleMul(chapter, stage)
    end
    return 1.0
end

return StageConfig
