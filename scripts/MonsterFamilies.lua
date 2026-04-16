--- 怪物家族系统
--- 8 个家族 × 7 行为模板 = 56 种怪物，动态等级 + 世界层级倍率取代 scaleMul
--- 设计文档: docs/数值/怪物家族系统设计.md §4, §12

local MonsterTemplates = require("MonsterTemplates")

local M = {}

---------------------------------------------------------------------------
-- 〇、种族档位定义 (五档, §12.1)
-- 每只怪的种族决定基准 HP/ATK/DEF，取代行为模板中的 hp/atk/def
---------------------------------------------------------------------------

---@alias RaceTierId "S"|"A"|"B"|"C"|"D"

---@class RaceTierDef
---@field hp  number 基准 HP
---@field atk number 基准 ATK
---@field def number 基准 DEF (护甲固定值, 不随等级增长)

---@type table<RaceTierId, RaceTierDef>
M.RACE_TIERS = {
    S = { hp = 55,  atk = 8,  def = 0  },  -- S-飞行小型: 蝙蝠,幽灵,微粒
    A = { hp = 85,  atk = 12, def = 5  },  -- A-远程: 术士,弓手,祭司
    B = { hp = 110, atk = 13, def = 15 },  -- B-标准近战: 骸骨,劫匪,鱼人
    C = { hp = 240, atk = 18, def = 35 },  -- C-重型近战: 骑士,蟹,蝎,守卫
    D = { hp = 400, atk = 24, def = 50 },  -- D-超重型: 泰坦,巨像,树人
}

---------------------------------------------------------------------------
-- 怪物 → 种族档位映射 (136+怪, §12.2)
-- key = MONSTERS ID, value = RaceTierId
-- 行为模板成员可通过 family.members[behaviorId].raceTier 覆盖
---------------------------------------------------------------------------

---@type table<string, RaceTierId>
M.MONSTER_RACE = {
    -- ── 虫潮 ──
    ash_rat          = "S", grave_rat        = "S",
    plague_beetle    = "B", sand_beetle      = "B", glacier_beetle = "B",
    rot_worm         = "B", dune_worm        = "C", magma_worm     = "C",
    venom_wasp       = "S", flame_wasp       = "S",
    frost_mite       = "S", plague_mites     = "S", chrono_mites   = "S",
    -- ── 亡灵 ──
    wraith           = "S", ice_wraith       = "S", ash_specter    = "S",
    abyss_shadow     = "S", skeleton_warrior = "B", cursed_knight  = "C",
    night_reaper     = "C", shadow_assassin  = "B", undead_priest  = "A",
    shadow_oracle    = "A", bone_golem       = "C", corrupt_mage   = "A",
    doom_wisp        = "S",
    -- ── 恶鬼 ──
    frost_imp        = "S", fire_imp         = "S", blaze_imp      = "S",
    molten_sprite    = "S", radiant_sprite   = "S", flame_spirit   = "S",
    void_wisp        = "S", holy_wisp        = "S", void_bat       = "S",
    ash_bat          = "S", volcano_moth     = "S",
    water_elemental  = "C", swamp_frog       = "B",
    -- ── 蛛蝎 ──
    corpse_spider    = "S", stasis_spider    = "S",
    rock_scorpion    = "C", thunder_scorpion = "C",
    thorn_viper      = "A", coil_serpent     = "B", venom_hunter   = "B",
    frost_hunter     = "B", poison_broodmother = "C", vine_strangler = "C",
    -- ── 野兽 ──
    snow_wolf        = "B", jungle_panther   = "B", lava_hound     = "B",
    lava_lizard      = "B", thunder_lizard   = "B", storm_hawk     = "S",
    flame_frog       = "A", tidal_crab       = "C",
    frost_behemoth   = "D", blight_behemoth  = "D", magma_behemoth = "D",
    -- ── 海民 ──
    abyss_angler     = "S", storm_seahorse   = "A",
    venom_jelly      = "B", bloat_jellyfish  = "B", abyss_jelly    = "B",
    abyss_crab       = "C", tidal_crab_swarm = "S", coral_guardian = "C",
    coral_tortoise   = "D", tidal_fishman    = "B", abyssal_stingray = "S",
    ink_octopus      = "C", sea_anemone      = "B",
    deepsea_warlock  = "A", tide_hierophant  = "A", ancient_kraken = "D",
    -- ── 菌落 ──
    spore_shroom     = "B", toxin_shroom     = "B", flame_shroom   = "B",
    spore_lurker     = "B", miasma_weaver    = "A", frost_weaver   = "A",
    hellfire_weaver  = "A", ironbark_treant  = "D", swamp_shaman   = "A",
    -- ── 构造体 ──
    frost_golem      = "C", molten_golem     = "C",
    obsidian_guard   = "C", golden_guard     = "C",
    eternal_sentinel = "C", void_sentinel    = "C", desert_golem   = "C",
    void_colossus    = "D", holy_colossus    = "D", epoch_colossus = "D",
    abyss_titan      = "D", inferno_titan    = "D", glacier_titan  = "D",
    plague_titan     = "D", pyre_titan       = "D", magma_shellcrab = "D",
    -- ── 教团 ──
    bandit           = "B", flame_bandit     = "B",
    cryo_mage        = "A", blight_mage      = "A", pyro_mage      = "A",
    chrono_mage      = "A", zealot_knight    = "C", scorch_knight  = "C",
    rewind_assassin  = "B", rift_hunter      = "B",
    aura_lancer      = "A", thunder_shaman   = "A",
    flame_priest     = "A", frost_priest     = "A", blight_priest  = "A",
    pyre_priest      = "A", eternal_priest   = "A",
    celestial_healer = "A", seraph_summoner  = "A",
    -- ── 虚空体 ──
    entropy_mote     = "S", sand_phantom     = "S",
    rift_ripper      = "B", rift_phantom     = "B",
    phase_weaver     = "A", star_oracle      = "A",
    dark_sentinel    = "C",
    -- ── 补充 ──
    void_lancer      = "A",  -- #137
}

--- 查询怪物种族档位
---@param monsterId string MONSTERS ID
---@return RaceTierDef|nil tier
function M.GetRaceTier(monsterId)
    local tierId = M.MONSTER_RACE[monsterId]
    if not tierId then return nil end
    return M.RACE_TIERS[tierId]
end

--- 查询种族档位ID
---@param monsterId string
---@return RaceTierId|nil
function M.GetRaceTierId(monsterId)
    return M.MONSTER_RACE[monsterId]
end

---------------------------------------------------------------------------
-- 一、家族定义
-- 每个家族 7 个成员（对应 7 个行为模板），一次定义终身复用
---------------------------------------------------------------------------

---@alias FamilyId "undead"|"beast"|"elemental_fire"|"elemental_ice"|"elemental_poison"|"arcane"|"divine"|"aquatic"

---@class FamilyMember
---@field name string            成员名称
---@field image string           贴图路径
---@field color number[]|nil     覆盖色调（nil 则用家族基础色调）
---@field resistId string|nil    覆盖抗性模板（nil 则用家族默认）
---@field tags table|nil         额外能力标签 { tagName = level }
---@field overrides table|nil    属性覆盖 { hp = 50, speed = 60, ... }

---@class MonsterFamily
---@field id string              家族ID
---@field name string            家族名称（显示用）
---@field theme string           视觉主题描述
---@field element string         家族主属元素
---@field colorBase number[]     基础色调 {r, g, b}
---@field resistProfile string   家族默认抗性模板ID
---@field members table<string, FamilyMember>  成员表（按行为模板索引）

---@type table<FamilyId, MonsterFamily>
local FAMILIES = {

    -- ━━━━━━━━━━ 不死族 ━━━━━━━━━━
    undead = {
        id = "undead",
        name = "不死族",
        theme = "骨质、暗紫、亡灵光效",
        element = "arcane",
        colorBase = { 120, 90, 160 },
        resistProfile = "arcane_res",
        members = {
            swarm    = { name = "骸骨鼠",     image = "Textures/mobs/grave_rat.png" },
            tank     = { name = "骨傀儡",     image = "Textures/mobs/bone_golem.png",     resistId = "phys_armor" },
            glass    = { name = "暗影刺客",   image = "Textures/mobs/shadow_assassin.png",    resistId = "all_low" },
            bruiser  = { name = "诅咒骑士",   image = "Textures/mobs/cursed_knight.png" },
            debuffer = { name = "尸蛛",       image = "Textures/mobs/corpse_spider.png", resistId = "poison_res" },
            caster   = { name = "亡灵侍祭",  image = "Textures/mobs/necro_acolyte.png" },
            exploder = { name = "骨爆亡灵",   image = "Textures/mobs/wraith.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 野兽族 ━━━━━━━━━━
    beast = {
        id = "beast",
        name = "野兽族",
        theme = "毛皮、獠牙、自然色调",
        element = "physical",
        colorBase = { 160, 140, 100 },
        resistProfile = "balanced",
        members = {
            swarm    = { name = "荒原鼠",   image = "Textures/mobs/ash_rat.png" },
            tank     = { name = "巨甲兽",   image = "Textures/mobs/desert_golem.png",     resistId = "all_high" },
            glass    = { name = "迅影豹",   image = "Textures/mobs/ember_stalker.png",    resistId = "all_low" },
            bruiser  = { name = "狂狼",     image = "Textures/mobs/snow_wolf.png" },
            debuffer = { name = "毒蛙",     image = "Textures/mobs/swamp_frog.png", resistId = "poison_res" },
            caster   = { name = "巫蛛",     image = "Textures/mobs/corpse_spider.png" },
            exploder = { name = "爆蛙",     image = "Textures/mobs/swamp_frog.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 火元素族 ━━━━━━━━━━
    elemental_fire = {
        id = "elemental_fire",
        name = "火元素族",
        theme = "熔岩、火焰、橙红色调",
        element = "fire",
        colorBase = { 220, 100, 40 },
        resistProfile = "fire_res",
        members = {
            swarm    = { name = "熔岩蜥蜴",   image = "Textures/mobs/lava_lizard.png" },
            tank     = { name = "岩甲巨蝎",   image = "Textures/mobs/rock_scorpion.png",     resistId = "all_high" },
            glass    = { name = "火山飞蛾",   image = "Textures/mobs/volcano_moth.png",    resistId = "all_low" },
            bruiser  = { name = "熔岩猎犬",   image = "Textures/mobs/lava_hound.png" },
            debuffer = { name = "毒焰蘑菇",   image = "Textures/mobs/toxiflame_shroom.png", resistId = "poison_res" },
            caster   = { name = "烈焰术士",   image = "Textures/mobs/inferno_caster.png" },
            exploder = { name = "熔核精灵",   image = "Textures/mobs/molten_sprite.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 冰元素族 ━━━━━━━━━━
    elemental_ice = {
        id = "elemental_ice",
        name = "冰元素族",
        theme = "冰晶、霜蓝、寒冷光效",
        element = "ice",
        colorBase = { 100, 180, 230 },
        resistProfile = "ice_res",
        members = {
            swarm    = { name = "霜魔小鬼",   image = "Textures/mobs/frost_imp.png" },
            tank     = { name = "永冻傀儡",   image = "Textures/mobs/permafrost_golem.png",     resistId = "all_high" },
            glass    = { name = "寒魂幽灵",   image = "Textures/mobs/ice_wraith.png",    resistId = "all_low" },
            bruiser  = { name = "雪原狼",     image = "Textures/mobs/snow_wolf.png" },
            debuffer = { name = "冰霜蛛",     image = "Textures/mobs/frost_mite.png" },
            caster   = { name = "冰霜术士",   image = "Textures/mobs/cryo_mage.png" },
            exploder = { name = "冰封亡灵",   image = "Textures/mobs/frozen_revenant.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 毒元素族 ━━━━━━━━━━
    elemental_poison = {
        id = "elemental_poison",
        name = "毒元素族",
        theme = "孢子、腐蚀、黄绿色调",
        element = "poison",
        colorBase = { 80, 160, 60 },
        resistProfile = "poison_res",
        members = {
            swarm    = { name = "瘟疫甲虫",   image = "Textures/mobs/plague_beetle.png" },
            tank     = { name = "铁木树人",   image = "Textures/mobs/ironbark_treant.png",   resistId = "all_high" },
            glass    = { name = "丛林黑豹",   image = "Textures/mobs/jungle_panther.png",  resistId = "all_low" },
            bruiser  = { name = "荆棘蝮蛇",   image = "Textures/mobs/thorn_viper.png" },
            debuffer = { name = "绞杀藤蔓",   image = "Textures/mobs/vine_strangler.png" },
            caster   = { name = "沼地巫师",   image = "Textures/mobs/mire_shaman.png" },
            exploder = { name = "孢子潜伏者", image = "Textures/mobs/spore_lurker.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 奥术族 ━━━━━━━━━━
    arcane = {
        id = "arcane",
        name = "奥术族",
        theme = "虚空、裂隙、紫黑色调",
        element = "arcane",
        colorBase = { 100, 60, 160 },
        resistProfile = "arcane_res",
        members = {
            swarm    = { name = "虚空游光",   image = "Textures/mobs/void_wisp.png" },
            tank     = { name = "虚空巨像",   image = "Textures/mobs/void_colossus.png",     resistId = "all_high" },
            glass    = { name = "裂隙潜行者", image = "Textures/mobs/rift_stalker.png",    resistId = "all_low" },
            bruiser  = { name = "空间撕裂者", image = "Textures/mobs/spatial_ripper.png" },
            debuffer = { name = "虚无哨兵",   image = "Textures/mobs/null_sentinel.png" },
            caster   = { name = "相位编织者", image = "Textures/mobs/phase_weaver.png" },
            exploder = { name = "熵灭微粒",   image = "Textures/mobs/entropy_mote.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 圣光族 ━━━━━━━━━━
    divine = {
        id = "divine",
        name = "圣光族",
        theme = "金光、圣洁、暖白色调",
        element = "holy",
        colorBase = { 220, 200, 140 },
        resistProfile = "holy_res",
        members = {
            swarm    = { name = "辉光精灵",     image = "Textures/mobs/radiant_sprite.png" },
            tank     = { name = "圣域巨灵",     image = "Textures/mobs/divine_colossus.png",     resistId = "all_high" },
            glass    = { name = "狂信骑士",     image = "Textures/mobs/zealot_knight.png",    resistId = "all_low" },
            bruiser  = { name = "光环枪兵",     image = "Textures/mobs/halo_lancer.png" },
            debuffer = { name = "金甲守卫",     image = "Textures/mobs/golden_guardian.png" },
            caster   = { name = "炽天使祈唤者", image = "Textures/mobs/seraph_invoker.png" },
            exploder = { name = "圣光游魂",     image = "Textures/mobs/sanctum_wisp.png", resistId = "all_low" },
        },
    },

    -- ━━━━━━━━━━ 深海族 ━━━━━━━━━━
    aquatic = {
        id = "aquatic",
        name = "深海族",
        theme = "珊瑚、鳞甲、蓝绿色调",
        element = "water",
        colorBase = { 40, 120, 200 },
        resistProfile = "water_res",
        members = {
            swarm    = { name = "深海灯笼鱼", image = "Textures/mobs/abyss_angler.png" },
            tank     = { name = "深渊巨蟹",   image = "Textures/mobs/abyssal_crab.png",     resistId = "phys_armor" },
            glass    = { name = "风暴海马",   image = "Textures/mobs/storm_seahorse.png",    resistId = "all_low" },
            bruiser  = { name = "潮汐鲛人",   image = "Textures/mobs/tide_merfolk.png" },
            debuffer = { name = "毒刺水母",   image = "Textures/mobs/venom_jelly.png", resistId = "poison_res" },
            caster   = { name = "海葵祭司",   image = "Textures/mobs/sea_anemone.png" },
            exploder = { name = "膨胀河豚",   image = "Textures/mobs/bloat_jellyfish.png", resistId = "all_low" },
        },
    },
}

---------------------------------------------------------------------------
-- 二、查询接口
---------------------------------------------------------------------------

--- 获取家族定义
---@param familyId FamilyId
---@return MonsterFamily|nil
function M.Get(familyId)
    return FAMILIES[familyId]
end

--- 获取所有家族ID列表
---@return FamilyId[]
function M.GetAllIds()
    local ids = {}
    for id in pairs(FAMILIES) do
        ids[#ids + 1] = id
    end
    return ids
end

---------------------------------------------------------------------------
-- 三、标签合并逻辑
-- 将章节 tagLevels 与行为模板的 optionalTags 交叉匹配，
-- 只有当标签引入章节 <= 当前章节时才激活。
---------------------------------------------------------------------------

--- 合并行为模板的默认/可选标签与章节标签等级
---@param behaviorId string  行为模板ID
---@param chapter number     当前章节号
---@param tagLevels table<string, number>  章节声明的标签等级
---@return table<string, number|boolean>   合并后的标签表
local function mergeTags(behaviorId, chapter, tagLevels)
    local beh = MonsterTemplates.Behaviors[behaviorId]
    if not beh then return {} end

    local merged = {}

    -- 1) 默认标签（始终携带）
    for k, v in pairs(beh.defaultTags) do
        merged[k] = v
    end

    -- 2) 可选标签：章节 tagLevels 声明 + 引入章节门槛
    if tagLevels and beh.optionalTags then
        for tagName, introChapter in pairs(beh.optionalTags) do
            if chapter >= introChapter and tagLevels[tagName] then
                merged[tagName] = tagLevels[tagName]
            end
        end
    end

    return merged
end

---------------------------------------------------------------------------
-- 四、怪物解析
---------------------------------------------------------------------------

--- 将 "familyId_behaviorId" 格式的怪物ID解析为 Spawner 兼容定义
--- 通过 MonsterTemplates.Assemble 组装, 并用种族基准值覆盖 hp/atk/def
---@param familyId string    家族ID
---@param behaviorId string  行为模板ID
---@param chapter number     章节号（决定抗性系数、元素、标签等级）
---@param tagLevels table<string, number>|nil  章节标签等级表
---@param monsterId string|nil  MONSTERS ID (用于种族档位查询, nil 时无种族覆盖)
---@return table monsterDef  Spawner 兼容的怪物定义 (含 raceBaseHP/raceBaseATK/raceBaseDEF/raceTierId)
function M.Resolve(familyId, behaviorId, chapter, tagLevels, monsterId)
    local family = FAMILIES[familyId]
    if not family then
        error("MonsterFamilies.Resolve: unknown family '" .. tostring(familyId) .. "'")
    end

    local member = family.members[behaviorId]
    if not member then
        error("MonsterFamilies.Resolve: family '" .. familyId .. "' has no member '" .. tostring(behaviorId) .. "'")
    end

    local resistId = member.resistId or family.resistProfile
    local tags = mergeTags(behaviorId, chapter, tagLevels or {})

    -- 合并成员级额外标签
    if member.tags then
        for k, v in pairs(member.tags) do
            tags[k] = v
        end
    end

    local opts = {
        name  = member.name,
        image = member.image,
        color = member.color or family.colorBase,
        tags  = tags,
    }

    -- 成员级属性覆盖
    if member.overrides then
        for k, v in pairs(member.overrides) do
            opts[k] = v
        end
    end

    local def = MonsterTemplates.Assemble(behaviorId, resistId, chapter, opts)

    -- 种族基准值覆盖: 用种族档位的 hp/atk/def 替代行为模板的基准值
    local raceId = (member.raceTier)                                -- 成员级覆盖
                or (monsterId and M.MONSTER_RACE[monsterId])        -- ID查表
                or nil
    if raceId then
        local race = M.RACE_TIERS[raceId]
        if race then
            def.hp          = race.hp
            def.atk         = race.atk
            def.def         = race.def
            def.raceBaseHP  = race.hp
            def.raceBaseATK = race.atk
            def.raceBaseDEF = race.def
            def.raceTierId  = raceId
        end
    end

    -- 记录家族/行为元数据, 供 DynamicLevel 等模块使用
    def.familyId   = familyId
    def.behaviorId = behaviorId

    return def
end

--- 从组合ID解析（供 Spawner 调用）
--- 格式: "familyId_behaviorId"，例如 "undead_swarm"
---@param compositeId string  组合ID
---@param chapter number      章节号
---@param tagLevels table<string, number>|nil  章节标签等级
---@param monsterId string|nil  MONSTERS ID (种族档位查询, nil 则用 compositeId)
---@return table|nil monsterDef  Spawner 兼容定义，解析失败返回 nil
function M.ResolveById(compositeId, chapter, tagLevels, monsterId)
    -- 从末尾匹配行为模板ID（behaviorId 不含下划线）
    local familyId, behaviorId = compositeId:match("^(.+)_(%w+)$")
    if not familyId or not FAMILIES[familyId] then
        return nil
    end
    if not FAMILIES[familyId].members[behaviorId] then
        return nil
    end
    return M.Resolve(familyId, behaviorId, chapter, tagLevels, monsterId or compositeId)
end

return M
