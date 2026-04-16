-- ============================================================================
-- SkillTreeConfig.lua - 法师技能树数据定义 (v3.0 D4巫师模型)
-- 7层结构: 基础→核心→防御→精通→高阶→终极→关键被动
-- 3元素: 火焰(Fire) / 冰霜(Ice) / 闪电(Lightning)
-- 门槛: 1, 2, 11, 16, 23, 33
-- 总计: 31技能 + 7关键被动
-- ============================================================================

local SkillTreeConfig = {}

-- ============================================================================
-- 元素定义 (3元素)
-- ============================================================================

SkillTreeConfig.ELEMENTS = {
    { id = "fire",      name = "火焰", icon = "🔥", color = { 255, 100, 50 } },
    { id = "ice",       name = "冰霜", icon = "❄️", color = { 100, 180, 255 } },
    { id = "lightning", name = "闪电", icon = "⚡", color = { 255, 220, 80 } },
}

-- ============================================================================
-- 层级定义
-- ============================================================================

SkillTreeConfig.TIERS = {
    { id = "basic",       name = "基础技能",   gate = 0,  color = { 180, 180, 180 } },
    { id = "core",        name = "核心技能",   gate = 2,  color = { 100, 200, 255 } },
    { id = "defensive",   name = "防御技能",   gate = 11, color = { 100, 220, 130 } },
    { id = "mastery",     name = "精通技能",   gate = 16, color = { 255, 200, 80 } },
    { id = "advanced",    name = "高阶技能",   gate = 23, color = { 255, 140, 60 } },
    { id = "ultimate",    name = "终极技能",   gate = 33, color = { 255, 80, 80 } },
    { id = "keyPassive",  name = "关键被动",   gate = 33, color = { 220, 180, 255 } },
}

-- ============================================================================
-- 节点类型
-- ============================================================================

SkillTreeConfig.NODE_TYPES = {
    ROOT     = "root",       -- 中心根节点 (圆形)
    GATE     = "gate",       -- 门槛节点 (圆形, 纯节点)
    ACTIVE   = "active",     -- 主动技能 (正方形)
    ENHANCE  = "enhance",    -- 增强节点 (菱形)
    PASSIVE  = "passive",    -- 关键被动 (菱形)
}

-- ============================================================================
-- 技能升级倍率 (1级=1.0, 每级+0.2, 5级=1.8)
-- ============================================================================

SkillTreeConfig.SKILL_LEVEL_MUL = { 1.0, 1.2, 1.4, 1.6, 1.8 }

-- ============================================================================
-- 技能定义
-- tier: 所属层级 (1-7)
-- nodeType: 节点类型
-- element: 技能固有元素 ("fire"/"ice"/"lightning"/nil)
-- maxLevel: 最大等级 (技能=5, 增强=1, 关键被动=1)
-- enhances: 此技能的增强线 (仅主动技能有)
-- enhanceLine: 所属增强线索引 (仅增强节点有)
-- parentSkill: 所增强的技能ID (仅增强节点有)
-- isBasic: 基础技能标记 (替代普攻)
-- isUltimate: 终极技能标记
-- isKeyPassive: 关键被动标记
-- ============================================================================

SkillTreeConfig.SKILLS = {

    -- ====================================================================
    -- T1: 基础技能 (4个, 门槛1) — 替代普攻, 只能装备1个
    -- ====================================================================

    -- 火焰弹
    {
        id = "fire_bolt", name = "火焰弹", tier = 1,
        nodeType = "active", element = "fire", isBasic = true,
        desc = "投掷火焰弹，造成%d%%武器伤害，并使目标燃烧6秒",
        maxLevel = 5,
        effect = function(lv) return 15 + lv * 4 end, -- 直击 19%~35%
        burnDmgPct = function(lv) return (35 + lv * 7) / 100 end, -- 燃烧总量 42%~70% (6秒)
        burnDuration = 6.0,
        cooldown = 0, -- 无CD, 受攻速影响
        enhances = {
            -- line 1: 强化火焰弹 (Y形根节点)
            {
                { id = "fire_bolt_enhanced", name = "强化火焰弹",
                  desc = "火焰弹穿透燃烧中的敌人",
                  effect = function() return 1 end },
            },
            -- line 2: 闪烁火焰弹 (Y形分支A, 依赖强化)
            {
                requires = "fire_bolt_enhanced",
                { id = "fire_bolt_flickering", name = "闪烁火焰弹",
                  desc = "命中敌人时生成2点法力",
                  effect = function() return 2 end },
            },
            -- line 3: 闪耀火焰弹 (Y形分支B, 依赖强化)
            {
                requires = "fire_bolt_enhanced",
                { id = "fire_bolt_glinting", name = "闪耀火焰弹",
                  desc = "对燃烧中的敌人伤害+30%%",
                  effect = function() return 0.30 end },
            },
        },
    },

    -- 冰霜弹
    {
        id = "frost_bolt", name = "冰霜弹", tier = 1,
        nodeType = "active", element = "ice", isBasic = true,
        desc = "发射冰霜弹，造成%d%%武器伤害，施加15%%冻伤",
        maxLevel = 5,
        effect = function(lv) return 81 + lv * 9 end, -- 90%~126%
        cooldown = 0,
        frostbitePct = 15, -- 每次命中施加15%冻伤
        enhances = {
            -- line 1: 碎冰 (前置节点, 无依赖)
            {
                { id = "frost_bolt_shatter", name = "碎冰冰霜弹",
                  desc = "命中冻伤敌人15%%几率范围伤害，命中冻结敌人时几率提至100%%",
                  effect = function() return 0.15 end },
            },
            -- line 2: 冰寒加速 (依赖 line 1 碎冰)
            {
                requires = "frost_bolt_shatter",
                { id = "frost_bolt_cdr", name = "冰寒加速",
                  desc = "冰霜弹命中冻伤或冻结的敌人时生成4点法力",
                  effect = function() return 4 end },
            },
            -- line 3: 易伤 (依赖 line 1 碎冰)
            {
                requires = "frost_bolt_shatter",
                { id = "frost_bolt_vuln", name = "冰霜易伤",
                  desc = "冰霜弹使敌人陷入易伤3秒，伤害×1.2×(1+a伤%%)×(1+x伤%%)",
                  effect = function() return 3.0 end },
            },
        },
    },

    -- 电花
    {
        id = "spark", name = "电花", tier = 1,
        nodeType = "active", element = "lightning", isBasic = true,
        desc = "释放电弧，对目标连续打击4次，每次造成%d%%武器伤害",
        maxLevel = 5,
        effect = function(lv) return 25 + lv * 3 end, -- 28%~40% ×4
        cooldown = 0,
        hitCount = 4,
        enhances = {
            -- line 1: 强化电花 (Y形根节点)
            {
                { id = "spark_enhanced", name = "强化电花",
                  desc = "每次施放暴击率+2%%，最多叠加至8%%",
                  effect = function() return 0.02 end },
            },
            -- line 2: 闪烁电花 (Y形分支A, 依赖强化)
            {
                requires = "spark_enhanced",
                { id = "spark_flickering", name = "闪烁电花",
                  desc = "每段命中生成1点法力（单次施放最多4点）",
                  effect = function() return 1 end },
            },
            -- line 3: 闪耀电花 (Y形分支B, 依赖强化)
            {
                requires = "spark_enhanced",
                { id = "spark_glinting", name = "闪耀电花",
                  desc = "电花额外弹跳2次",
                  effect = function() return 2 end },
            },
        },
    },

    -- 电弧打击 (第4个基础技能, 闪电系)
    {
        id = "arcane_strike", name = "电弧打击", tier = 1,
        nodeType = "active", element = "lightning", isBasic = true,
        desc = "释放电弧冲击波，造成%d%%武器伤害，每10次释放击晕敌人2秒",
        maxLevel = 5,
        effect = function(lv) return 80 + lv * 8 end, -- 88%~120%
        cooldown = 0,
        stunInterval = 10,    -- 每10次释放触发眩晕
        stunDuration = 2.0,   -- 眩晕2秒
        enhances = {
            -- line 1: 强化电弧打击 (Y形根节点)
            {
                { id = "arcane_strike_enhanced", name = "强化电弧打击",
                  desc = "眩晕间隔缩短至每7次，眩晕延长至3秒",
                  effect = function() return 7 end },
            },
            -- line 2: 闪烁电弧打击 (Y形分支A, 依赖强化)
            {
                requires = "arcane_strike_enhanced",
                { id = "arcane_strike_flickering", name = "闪烁电弧打击",
                  desc = "命中时生成3点法力",
                  effect = function() return 3 end },
            },
            -- line 3: 闪耀电弧打击 (Y形分支B, 依赖强化)
            {
                requires = "arcane_strike_enhanced",
                { id = "arcane_strike_glinting", name = "闪耀电弧打击",
                  desc = "命中时获得10%%攻速加成3秒",
                  effect = function() return 0.10 end },
            },
        },
    },

    -- ====================================================================
    -- T2: 核心技能 (5个, 门槛2) — 主力输出
    -- ====================================================================

    -- 火球 — 经典AOE爆破, 燃烧联动
    {
        id = "fireball", name = "火球", tier = 2,
        nodeType = "active", element = "fire",
        desc = "投掷火球在敌群中引爆，造成%d%%武器伤害。命中燃烧中的敌人伤害+25%%",
        maxLevel = 5,
        effect = function(lv) return 60 + lv * 12 end, -- 72%~120%
        manaCost = 25,
        cooldown = 5.0,
        burnBonusPct = 0.25,        -- 对燃烧敌人额外伤害 +25%
        burnApplyPct = 0.20,        -- 命中施加燃烧: 20%武器伤害/秒
        burnApplyDur = 3.0,         -- 燃烧持续3秒 (总60%)
        enhances = {
            -- line 1: 强化火球 (Y形根节点)
            {
                { id = "fireball_enhanced", name = "强化火球",
                  desc = "火球爆炸后留下燃烧地面，持续3秒，每秒造成15%%武器伤害",
                  effect = function() return 1 end },
            },
            -- line 2: 闪烁火球 (依赖强化, 燃烧增伤流)
            {
                requires = "fireball_enhanced",
                { id = "fireball_flickering", name = "闪烁火球",
                  desc = "对燃烧敌人额外伤害提升至50%%(替代25%%)；击杀燃烧敌人回复3法力",
                  effect = function() return 0.50 end },
            },
            -- line 3: 闪耀火球 (依赖强化, 暴击AOE流)
            {
                requires = "fireball_enhanced",
                { id = "fireball_glinting", name = "闪耀火球",
                  desc = "火球暴击时引发二次爆炸，造成原始伤害40%%；爆炸半径+30%%",
                  effect = function() return 0.40 end },
            },
        },
    },

    -- 焚烧 — 递增灼烧, 站桩高DPS
    {
        id = "incinerate", name = "焚烧", tier = 2,
        nodeType = "active", element = "fire",
        desc = "引导火焰射线，每0.5秒造成一段%d%%武器伤害，伤害逐段递增",
        maxLevel = 5,
        effect = function(lv) return 32 + lv * 6 end, -- 每段 38%~62%
        manaCost = 30,
        cooldown = 8.0,
        isChanneled = true,
        channelTicks = 4,                           -- 4段
        channelInterval = 0.5,                      -- 每0.5秒一段
        channelRamp = { 1.0, 1.25, 1.5, 2.0 },     -- 逐段递增倍率
        burnStackPct = 0.10,                        -- 每段施加10%燃烧/秒
        burnStackDur = 3.0,                         -- 燃烧持续3秒
        burnMaxStacks = 4,                          -- 最多4层
        enhances = {
            -- line 1: 强化焚烧 (Y形根节点)
            {
                { id = "incinerate_enhanced", name = "强化焚烧",
                  desc = "引导期间移速+20%%，被击中不再打断引导",
                  effect = function() return 0.20 end },
            },
            -- line 2: 闪烁焚烧 (依赖强化, 燃烧增伤流)
            {
                requires = "incinerate_enhanced",
                { id = "incinerate_flickering", name = "闪烁焚烧",
                  desc = "第4段对燃烧敌人额外伤害+60%%；每段命中回复2法力",
                  effect = function() return 0.60 end },
            },
            -- line 3: 闪耀焚烧 (依赖强化, 防御反击流)
            {
                requires = "incinerate_enhanced",
                { id = "incinerate_glinting", name = "闪耀焚烧",
                  desc = "引导期间每段获得5%%最大生命值屏障；引导结束时释放火焰爆炸，造成80%%武器伤害",
                  effect = function() return 0.80 end },
            },
        },
    },

    -- 冰碎片
    {
        id = "ice_shards", name = "冰碎片", tier = 2,
        nodeType = "active", element = "ice",
        desc = "射出5枚冰片，每枚造成%d%%点伤害。对冻结的敌人伤害提高50%%",
        maxLevel = 5,
        effect = function(lv) return 25 + lv * 5 end, -- 30%~50% ×5片
        manaCost = 30,
        cooldown = 0,      -- 无CD, 依赖攻速时机 (D4核心技能)
        coreSkill = true,  -- 核心技能: 与基础技能共享攻速槽位
        hitCount = 5,
        enhances = {
            -- line 1: 强化冰碎片 (根节点, 无依赖)
            {
                { id = "ice_shards_enhanced", name = "强化冰碎片",
                  desc = "冰碎片有50%%几率弹射向其他敌人。射向冻结敌人的冰碎片总是弹射",
                  effect = function() return 0.50 end },
            },
            -- line 2: 强效冰碎片 (依赖 line 1 强化)
            {
                requires = "ice_shards_enhanced",
                { id = "ice_shards_greater", name = "强效冰碎片",
                  desc = "拥有屏障时，冰碎片总会获得对冻结敌人的额外伤害加成",
                  effect = function() return 1 end },
            },
            -- line 3: 毁灭冰碎片 (依赖 line 1 强化)
            {
                requires = "ice_shards_enhanced",
                { id = "ice_shards_destructive", name = "毁灭冰碎片",
                  desc = "单次施法中5枚冰碎片全部命中同一敌人时，使其陷入易伤2秒",
                  effect = function() return 2.0 end },
            },
        },
    },

    -- 电荷弹 — 散射弹幕, 眩晕概率, Boss杀手
    {
        id = "charged_bolts", name = "电荷弹", tier = 2,
        nodeType = "active", element = "lightning",
        desc = "释放5枚电荷弹向前方散射，每枚造成%d%%武器伤害，20%%概率眩晕0.5秒",
        maxLevel = 5,
        effect = function(lv) return 35 + lv * 7 end, -- 每弹 42%~70%
        manaCost = 25,
        cooldown = 5.0,
        boltCount = 5,              -- 弹体数量
        stunChance = 0.20,          -- 眩晕概率 20%
        stunDuration = 0.5,         -- 眩晕时长 0.5s
        enhances = {
            -- line 1: 强化电荷弹 (Y形根节点)
            {
                { id = "charged_bolts_enhanced", name = "强化电荷弹",
                  desc = "弹体数量+2(共7枚)；眩晕概率提升至30%%",
                  effect = function() return 1 end },
            },
            -- line 2: 闪烁电荷弹 (依赖强化, 眩晕联动流)
            {
                requires = "charged_bolts_enhanced",
                { id = "charged_bolts_flickering", name = "闪烁电荷弹",
                  desc = "命中眩晕中的敌人伤害+40%%；每次眩晕敌人回复2法力",
                  effect = function() return 0.40 end },
            },
            -- line 3: 闪耀电荷弹 (依赖强化, 聚焦爆发流)
            {
                requires = "charged_bolts_enhanced",
                { id = "charged_bolts_glinting", name = "闪耀电荷弹",
                  desc = "3枚以上弹体命中同一目标时，触发电荷过载：额外造成60%%武器伤害并溅射30%%",
                  effect = function() return 0.60 end },
            },
        },
    },

    -- 连锁闪电 — 弹跳链电, 越弹越强
    {
        id = "chain_lightning", name = "连锁闪电", tier = 2,
        nodeType = "active", element = "lightning",
        desc = "释放闪电弹射6次，首次造成%d%%武器伤害，每次弹跳递增10%%",
        maxLevel = 5,
        effect = function(lv) return 40 + lv * 8 end, -- 首次 48%~80%
        manaCost = 30,
        cooldown = 6.0,
        bounceCount = 6,            -- 弹跳次数
        bounceRampPct = 0.10,       -- 每次弹跳伤害递增 +10%
        enhances = {
            -- line 1: 强化连锁闪电 (Y形根节点)
            {
                { id = "chain_lightning_enhanced", name = "强化连锁闪电",
                  desc = "每次弹跳+3%%暴击率；弹跳次数+2(共8次)",
                  effect = function() return 0.03 end },
            },
            -- line 2: 闪烁连锁闪电 (依赖强化, 眩晕延续流)
            {
                requires = "chain_lightning_enhanced",
                { id = "chain_lightning_flickering", name = "闪烁连锁闪电",
                  desc = "弹跳到眩晕敌人时造成双倍伤害并延长眩晕0.5秒；击杀时额外弹跳2次",
                  effect = function() return 2.0 end },
            },
            -- line 3: 闪耀连锁闪电 (依赖强化, 递增爆发流)
            {
                requires = "chain_lightning_enhanced",
                { id = "chain_lightning_glinting", name = "闪耀连锁闪电",
                  desc = "弹跳伤害递增提升至+20%%；最后一次弹跳触发雷暴，对周围造成50%%武器伤害AOE",
                  effect = function() return 0.20 end },
            },
        },
    },

    -- ====================================================================
    -- T3: 防御技能 (4个, 门槛11) — 生存/位移
    -- ====================================================================

    -- 火焰护盾
    {
        id = "flame_shield", name = "火焰护盾", tier = 3,
        nodeType = "active", element = "fire",
        desc = "获得火焰屏障，吸收%d%%最大生命值伤害",
        maxLevel = 5,
        effect = function(lv) return 20 + lv * 5 end, -- 25%~45%
        cooldown = 20.0,
        enhances = {
            {
                { id = "flame_shield_enhanced", name = "强化火焰护盾",
                  desc = "持续时间+2秒",
                  effect = function() return 2.0 end },
            },
            {
                { id = "flame_shield_mystical", name = "神秘火焰护盾",
                  desc = "结束时释放火焰爆炸",
                  effect = function() return 1 end },
                { id = "flame_shield_shimmering", name = "闪光火焰护盾",
                  desc = "激活时移动速度+25%%",
                  effect = function() return 0.25 end },
            },
        },
    },

    -- 寒冰甲
    {
        id = "ice_armor", name = "寒冰甲", tier = 3,
        nodeType = "active", element = "ice",
        desc = "冰霜屏障(6秒)，吸收%d%%生命上限伤害",
        maxLevel = 5,
        effect = function(lv)
            local pcts = { 56, 62, 67, 73, 78 }
            return pcts[lv] or pcts[#pcts]
        end,
        cooldown = 20.0,
        shieldDuration = 6.0,
        enhances = {
            -- line 1: 强化寒冰甲 (Y形根节点)
            {
                { id = "ice_armor_enhanced", name = "强化寒冰甲",
                  desc = "寒冰甲激活时，法力回复速度+30%%[x]",
                  effect = function() return 0.30 end },
            },
            -- line 2: 神秘寒冰甲 (Y形分支A, 依赖强化)
            {
                requires = "ice_armor_enhanced",
                { id = "ice_armor_mystical", name = "神秘寒冰甲",
                  desc = "寒冰甲激活时，周期性对近距离敌人施加20%%冻伤，对冻结敌人伤害+15%%[x]",
                  effect = function() return 0.15 end },
            },
            -- line 3: 微光寒冰甲 (Y形分支B, 依赖强化)
            {
                requires = "ice_armor_enhanced",
                { id = "ice_armor_shimmering", name = "微光寒冰甲",
                  desc = "寒冰甲激活时，每花费50点法力减少1秒冷却时间",
                  effect = function() return 50 end },
            },
        },
    },

    -- 冰霜新星
    {
        id = "frost_nova", name = "冰霜新星", tier = 3,
        nodeType = "active", element = "ice",
        desc = "冻结周围敌人%d秒，造成冰霜伤害",
        maxLevel = 5,
        effect = function(lv) return 2 + lv end, -- 冻结3~7秒
        cooldown = 16.0,
        damageCoeff = function(lv) return 40 + lv * 8 end, -- 48%~80%
        enhances = {
            {
                { id = "frost_nova_enhanced", name = "强化冰霜新星",
                  desc = "冻结时间+1秒",
                  effect = function() return 1.0 end },
            },
            {
                { id = "frost_nova_mystical", name = "神秘冰霜新星",
                  desc = "冻结敌人时使其易伤3秒",
                  effect = function() return 3.0 end },
                { id = "frost_nova_shimmering", name = "闪光冰霜新星",
                  desc = "释放后获得20%%移动速度4秒",
                  effect = function() return 0.20 end },
            },
        },
    },

    -- 传送
    {
        id = "teleport", name = "传送", tier = 3,
        nodeType = "active", element = "lightning",
        desc = "位移至目标点，落地造成%d%%武器闪电伤害",
        maxLevel = 5,
        effect = function(lv) return 50 + lv * 10 end, -- 60%~100%
        cooldown = 14.0,
        enhances = {
            {
                { id = "teleport_enhanced", name = "强化传送",
                  desc = "每命中1个敌人CD-0.5秒(最多-3秒)",
                  effect = function() return 0.5 end },
            },
            {
                { id = "teleport_mystical", name = "神秘传送",
                  desc = "4秒内爆裂电花额外命中2个敌人",
                  effect = function() return 2 end },
                { id = "teleport_shimmering", name = "闪光传送",
                  desc = "获得30%%伤害减免3秒",
                  effect = function() return 0.30 end },
            },
        },
    },

    -- ====================================================================
    -- T4: 精通技能 (4个, 门槛16)
    -- ====================================================================

    -- 九头蛇
    {
        id = "hydra", name = "九头蛇", tier = 4,
        nodeType = "active", element = "fire",
        desc = "召唤3头火蛇，持续%d秒，自动攻击",
        maxLevel = 5,
        effect = function(lv) return 6 + lv end, -- 7~11秒
        cooldown = 15.0,
        summonDamage = function(lv) return 50 + lv * 10 end, -- 每次攻击60%~100%
        enhances = {
            {
                { id = "hydra_enhanced", name = "强化九头蛇",
                  desc = "持续时间+2秒",
                  effect = function() return 2.0 end },
            },
            {
                { id = "hydra_destructive", name = "毁灭九头蛇",
                  desc = "攻击暴击时使敌人易伤2秒",
                  effect = function() return 2.0 end },
                { id = "hydra_greater", name = "强效九头蛇",
                  desc = "召唤数量+1(变为4头)",
                  effect = function() return 1 end },
            },
        },
    },

    -- 暴风雪
    {
        id = "blizzard", name = "暴风雪", tier = 4,
        nodeType = "active", element = "ice",
        tags = { "掌控", "冰霜", "冻伤", "核心" },
        desc = "召唤一阵冰冷的暴风雪，造成[%d]%%点霜噬伤害并在8秒内持续冻伤敌人18%%",
        maxLevel = 5,
        effect = function(lv) return 225 + lv * 25 end, -- 250%~350% 霜噬伤害(每级+25%)
        manaCost = 40,
        luckyHitChance = 0.33,
        cooldown = 15.0,
        castRange = 250,            -- 释放范围 (只在此范围内索敌)
        frostbiteDuration = 8.0,    -- 冻伤持续时间
        frostbitePct = 0.18,        -- 冻伤比例 18%
        enhances = {
            -- line 1: 强化暴风雪 (Y形根节点)
            {
                { id = "blizzard_enhanced", name = "强化暴风雪",
                  desc = "暴风雪对被冻结敌人造成的伤害提高40%%[x]",
                  effect = function() return 0.40 end },
            },
            -- line 2: 法师暴风雪 (Y形分支A, 依赖强化)
            {
                requires = "blizzard_enhanced",
                { id = "blizzard_mage", name = "法师暴风雪",
                  desc = "暴风雪的持续时间延长4秒",
                  effect = function() return 4.0 end },
            },
            -- line 3: 巫师暴风雪 (Y形分支B, 依赖强化)
            {
                requires = "blizzard_enhanced",
                { id = "blizzard_wizard", name = "巫师暴风雪",
                  desc = "暴风雪激活时，你每有20点法力上限，法力回复速度就会提高1点",
                  effect = function() return 20 end }, -- 每20点法力上限+1回复
            },
        },
    },

    -- 闪电矛
    {
        id = "lightning_spear", name = "闪电矛", tier = 4,
        nodeType = "active", element = "lightning",
        desc = "闪电追踪矛，%d%%武器伤害，持续6秒",
        maxLevel = 5,
        effect = function(lv) return 80 + lv * 16 end, -- 96%~160%
        cooldown = 19.7,
        enhances = {
            {
                { id = "lightning_spear_enhanced", name = "强化闪电矛",
                  desc = "暴击后+5%%堆叠暴击率(最多25%%)",
                  effect = function() return 0.05 end },
            },
            {
                { id = "lightning_spear_destructive", name = "毁灭闪电矛",
                  desc = "命中时生成爆裂电花",
                  effect = function() return 1 end },
                { id = "lightning_spear_greater", name = "强效闪电矛",
                  desc = "持续时间+2秒",
                  effect = function() return 2.0 end },
            },
        },
    },

    -- 火墙
    {
        id = "firewall", name = "火墙", tier = 4,
        nodeType = "active", element = "fire",
        desc = "制造火墙，%d%%武器伤害/秒",
        maxLevel = 5,
        effect = function(lv) return 60 + lv * 12 end, -- 72%~120%
        cooldown = 12.0,
        enhances = {
            {
                { id = "firewall_enhanced", name = "强化火墙",
                  desc = "持续时间+2秒",
                  effect = function() return 2.0 end },
            },
            {
                { id = "firewall_destructive", name = "毁灭火墙",
                  desc = "敌人在火墙中时你的火焰伤害+15%%",
                  effect = function() return 0.15 end },
                { id = "firewall_greater", name = "强效火墙",
                  desc = "生成时击退周围敌人",
                  effect = function() return 1 end },
            },
        },
    },

    -- ====================================================================
    -- T5: 高阶技能 (4个, 门槛23)
    -- ====================================================================

    -- 火焰风暴 (自创, 填充T5火系)
    {
        id = "fire_storm", name = "烈焰风暴", tier = 5,
        nodeType = "active", element = "fire",
        desc = "全屏火焰风暴，%d%%武器伤害",
        maxLevel = 5,
        effect = function(lv) return 200 + lv * 40 end, -- 240%~400%
        cooldown = 18.0,
        enhances = {
            {
                { id = "fire_storm_enhanced", name = "强化烈焰风暴",
                  desc = "范围+30%%",
                  effect = function() return 0.30 end },
            },
            {
                { id = "fire_storm_destructive", name = "毁灭烈焰风暴",
                  desc = "命中燃烧敌人时伤害+25%%",
                  effect = function() return 0.25 end },
                { id = "fire_storm_greater", name = "强效烈焰风暴",
                  desc = "风暴后留火焰地面3秒",
                  effect = function() return 3.0 end },
            },
        },
    },

    -- 冰封球
    {
        id = "frozen_orb", name = "冰封球", tier = 5,
        nodeType = "active", element = "ice",
        desc = "滚动冰球，%d%%武器伤害，最终爆炸",
        maxLevel = 5,
        effect = function(lv) return 150 + lv * 30 end, -- 180%~300%
        cooldown = 16.0,
        enhances = {
            {
                { id = "frozen_orb_enhanced", name = "强化冰封球",
                  desc = "移动速度+30%%，持续时间+1秒",
                  effect = function() return 0.30 end },
            },
            {
                { id = "frozen_orb_destructive", name = "毁灭冰封球",
                  desc = "爆炸时冻结敌人2秒",
                  effect = function() return 2.0 end },
                { id = "frozen_orb_greater", name = "强效冰封球",
                  desc = "留下冰霜区域，使敌人冻伤",
                  effect = function() return 1 end },
            },
        },
    },

    -- 雷暴
    {
        id = "thunderstorm", name = "雷暴", tier = 5,
        nodeType = "active", element = "lightning",
        desc = "召唤雷暴区域，%d%%武器伤害/秒，持续6秒",
        maxLevel = 5,
        effect = function(lv) return 120 + lv * 24 end, -- 144%~240%
        cooldown = 18.0,
        enhances = {
            {
                { id = "thunderstorm_enhanced", name = "强化雷暴",
                  desc = "范围+25%%",
                  effect = function() return 0.25 end },
            },
            {
                { id = "thunderstorm_destructive", name = "毁灭雷暴",
                  desc = "区域内敌人受闪电伤害+20%%",
                  effect = function() return 0.20 end },
                { id = "thunderstorm_greater", name = "强效雷暴",
                  desc = "结束时释放雷击，眩晕敌人1.5秒",
                  effect = function() return 1.5 end },
            },
        },
    },

    -- 能量脉冲 (物理/全元素)
    {
        id = "energy_pulse", name = "能量脉冲", tier = 5,
        nodeType = "active", element = "lightning",
        desc = "全方向能量波，%d%%武器伤害",
        maxLevel = 5,
        effect = function(lv) return 180 + lv * 36 end, -- 216%~360%
        cooldown = 15.0,
        enhances = {
            {
                { id = "energy_pulse_enhanced", name = "强化能量脉冲",
                  desc = "击退力度+50%%",
                  effect = function() return 0.50 end },
            },
            {
                { id = "energy_pulse_destructive", name = "毁灭能量脉冲",
                  desc = "对低血量(<30%%)敌人伤害+40%%",
                  effect = function() return 0.40 end },
                { id = "energy_pulse_greater", name = "强效能量脉冲",
                  desc = "暴击时生成护盾(5%%最大生命值)",
                  effect = function() return 0.05 end },
            },
        },
    },

    -- ====================================================================
    -- T6: 终极技能 (3个, 门槛33) — 只能装备1个
    -- ====================================================================

    -- 陨石
    {
        id = "meteor", name = "陨石", tier = 6,
        nodeType = "active", element = "fire", isUltimate = true,
        desc = "召唤陨石坠落爆炸，%d%%武器伤害",
        maxLevel = 5,
        effect = function(lv) return 500 + lv * 100 end, -- 600%~1000%
        cooldown = 50.0,
        enhances = {
            -- 终极技能: 初级 vs 至尊 (2选1)
            {
                { id = "meteor_prime", name = "初级陨石",
                  desc = "爆炸使敌人燃烧8秒，伤害+50%%",
                  effect = function() return 0.50 end },
                { id = "meteor_supreme", name = "至尊陨石",
                  desc = "获得20%%火焰伤害加成8秒",
                  effect = function() return 0.20 end },
            },
        },
    },

    -- 深度冻结
    {
        id = "deep_freeze", name = "深度冻结", tier = 6,
        nodeType = "active", element = "ice", isUltimate = true,
        desc = "冰封自身4秒，免疫CC，持续冰霜伤害+冻伤，结束爆炸%d%%武器伤害",
        maxLevel = 5,
        effect = function(lv) return 110 + 15 * lv end,           -- 爆发伤害%: 125/140/155/170/185...
        tickDmgPct = function(lv) return (22 + 3 * lv) / 100 end, -- 持续伤害%: 25/28/31/34/37...
        frostbitePctPerSec = 14,   -- 冻伤%/秒 (不随等级变化)
        cooldown = 60.0,
        luckyHitChance = 0.02,     -- 2% 幸运一击
        duration = 4.0,            -- 免疫持续时间
        aoeRadius = 120,           -- AOE 范围
        tickRate = 1.0,            -- 每秒 tick 一次
        enhances = {
            {
                { id = "deep_freeze_prime", name = "初级深度冻结",
                  desc = "结束时获得50%%最大生命值屏障8秒",
                  effect = function() return 0.50 end },
                { id = "deep_freeze_supreme", name = "至尊深度冻结",
                  desc = "免疫期间每2秒生成10点法力",
                  effect = function() return 10 end },
            },
        },
    },

    -- 雷霆风暴
    {
        id = "thunder_storm", name = "雷霆风暴", tier = 6,
        nodeType = "active", element = "lightning", isUltimate = true,
        desc = "召唤风暴持续8秒，%d%%武器伤害/秒",
        maxLevel = 5,
        effect = function(lv) return 300 + lv * 60 end, -- 360%~600%
        cooldown = 50.0,
        enhances = {
            {
                { id = "thunder_storm_prime", name = "初级雷霆风暴",
                  desc = "持续时间+2秒，爆裂电花伤害+30%%",
                  effect = function() return 0.30 end },
                { id = "thunder_storm_supreme", name = "至尊雷霆风暴",
                  desc = "期间闪电技能CD-20%%",
                  effect = function() return 0.20 end },
            },
        },
    },

    -- ====================================================================
    -- T7: 关键被动 (7个, 门槛33) — 7选1, 不占槽位
    -- ====================================================================

    {
        id = "kp_combustion", name = "燃爆", tier = 7,
        nodeType = "passive", isKeyPassive = true,
        desc = "燃烧敌人受到的所有伤害+15%%[x]",
        maxLevel = 1,
        effect = function() return 0.15 end,
        bucket = "x", -- X伤来源
    },
    {
        id = "kp_avalanche", name = "雪崩", tier = 7,
        nodeType = "passive", isKeyPassive = true, element = "ice",
        desc = "你的冰霜技能消耗法力减少30%%，伤害提高60%%[x]。对易伤敌人，造成额外25%%[x]的伤害",
        maxLevel = 1,
        effect = function() return { manaCostReduce = 0.30, dmgX = 0.60, vulnX = 0.25 } end,
    },
    {
        id = "kp_overcharge", name = "过载", tier = 7,
        nodeType = "passive", isKeyPassive = true,
        desc = "暴击时生成爆裂电花，电花伤害+25%%[x]",
        maxLevel = 1,
        effect = function() return 0.25 end,
        bucket = "x",
    },
    {
        id = "kp_esu_blessing", name = "伊苏祝福", tier = 7,
        nodeType = "passive", isKeyPassive = true,
        desc = "攻速每超过基础1%%，伤害+0.5%%[x]",
        maxLevel = 1,
        effect = function() return 0.005 end,
        bucket = "x",
    },
    {
        id = "kp_align_elements", name = "元素归一", tier = 7,
        nodeType = "passive", isKeyPassive = true,
        desc = "交替使用不同元素技能时，下一个技能伤害+12%%[x]",
        maxLevel = 1,
        effect = function() return 0.12 end,
        bucket = "x",
    },
    {
        id = "kp_shatter", name = "碎冰", tier = 7,
        nodeType = "passive", isKeyPassive = true, element = "ice",
        desc = "敌人在其受到的冻结效果持续时间结束后会爆炸并受到伤害，相当于你在其冻结期间对其造成伤害的45%%",
        maxLevel = 1,
        effect = function() return 0.45 end,
    },
    {
        id = "kp_vyr_mastery", name = "维尔精通", tier = 7,
        nodeType = "passive", isKeyPassive = true,
        desc = "技能CD-10%%[x]，技能伤害+15%%[x]",
        maxLevel = 1,
        effect = function() return { cdrBonus = 0.10, skillDmg = 0.15 } end,
        bucket = "x",
    },
}

-- ============================================================================
-- 装备槽位配置
-- ============================================================================

SkillTreeConfig.LOADOUT = {
    basicSlots = 1,     -- 基础技能槽 (只能装1个基础技能)
    activeSlots = 4,    -- 主动技能槽
    totalSlots = 5,     -- 1基础 + 4主动
}

-- ============================================================================
-- 索引构建
-- ============================================================================

---@type table<string, table>
SkillTreeConfig.SKILL_MAP = {}

--- 所有增强节点的平面索引 { [enhanceId] = { skill=parentSkill, lineIdx=N, nodeIdx=N } }
---@type table<string, table>
SkillTreeConfig.ENHANCE_MAP = {}

for _, skill in ipairs(SkillTreeConfig.SKILLS) do
    SkillTreeConfig.SKILL_MAP[skill.id] = skill

    -- 索引增强节点
    if skill.enhances then
        for lineIdx, line in ipairs(skill.enhances) do
            for nodeIdx, enh in ipairs(line) do
                enh.maxLevel = 1
                enh.tier = skill.tier
                enh.nodeType = "enhance"
                enh.parentSkill = skill.id
                enh.enhanceLine = lineIdx
                enh.enhanceNodeIdx = nodeIdx
                SkillTreeConfig.SKILL_MAP[enh.id] = enh
                SkillTreeConfig.ENHANCE_MAP[enh.id] = {
                    skill = skill,
                    lineIdx = lineIdx,
                    nodeIdx = nodeIdx,
                }
            end
        end
    end
end

-- ============================================================================
-- 查询函数
-- ============================================================================

--- 获取技能总容量
function SkillTreeConfig.GetTotalCapacity()
    local total = 0
    for _, skill in ipairs(SkillTreeConfig.SKILLS) do
        total = total + skill.maxLevel
    end
    -- 加上所有增强节点
    for _ in pairs(SkillTreeConfig.ENHANCE_MAP) do
        total = total + 1
    end
    return total
end

--- 获取升级消耗 (所有技能每次升级消耗1点)
--- @param skillId string
--- @param currentLevel number 当前等级 (升级前)
--- @return number cost 固定为1
function SkillTreeConfig.GetUpgradeCost(skillId, currentLevel)
    return 1
end

--- 获取技能在指定等级下已累计消耗的总点数
--- @param skillId string
--- @param level number
--- @return number totalCost
function SkillTreeConfig.GetTotalCostForLevel(skillId, level)
    return level -- 每级消耗1点, 总消耗=等级
end

--- 获取指定层级的门槛
--- @param tierIdx number 层级索引 (1-7)
--- @return number gate
function SkillTreeConfig.GetTierGate(tierIdx)
    local tier = SkillTreeConfig.TIERS[tierIdx]
    return tier and tier.gate or 0
end

--- 检查是否达到层级门槛
--- @param tierIdx number 目标层级索引
--- @param totalSpent number 已投入总点数
--- @return boolean
function SkillTreeConfig.IsTierUnlocked(tierIdx, totalSpent)
    return totalSpent >= SkillTreeConfig.GetTierGate(tierIdx)
end

--- 检查增强节点是否可学 (层级门槛 + 跨线前置 + 同线互斥)
--- @param enhanceId string
--- @param getLevel function(id)->number
--- @return boolean canLearn, string|nil reason
function SkillTreeConfig.CanLearnEnhance(enhanceId, getLevel, totalSpent)
    local info = SkillTreeConfig.ENHANCE_MAP[enhanceId]
    if not info then return false, "增强节点不存在" end

    -- 层级门槛 (与父技能同层)
    local parentSkill = info.skill
    if parentSkill.tier then
        if not SkillTreeConfig.IsTierUnlocked(parentSkill.tier, totalSpent or 0) then
            local gate = SkillTreeConfig.GetTierGate(parentSkill.tier)
            return false, "需要投入" .. gate .. "点解锁此层"
        end
    end

    -- 跨线前置依赖: 检查 line.requires 指定的增强节点是否已学
    local line = info.skill.enhances[info.lineIdx]
    if line.requires then
        local reqId = line.requires
        if getLevel(reqId) <= 0 then
            local reqCfg = SkillTreeConfig.SKILL_MAP[reqId]
            local reqName = reqCfg and reqCfg.name or reqId
            return false, "需要先学习: " .. reqName
        end
    end

    -- 隐式Y形前置: 当增强结构为 [1节点line] + [2节点line]（无requires）时,
    -- 多节点line中的节点需要先学单节点line的那个节点
    if not line.requires then
        local enhances = info.skill.enhances
        local hasChildLines = false
        for _, ln in ipairs(enhances) do
            if ln.requires then hasChildLines = true; break end
        end
        if not hasChildLines and #enhances >= 2 then
            -- 检测: 当前节点所在line有多个节点 → 找单节点line作为隐式前置
            if #line >= 2 then
                for _, otherLine in ipairs(enhances) do
                    if otherLine ~= line and #otherLine == 1 then
                        local rootId = otherLine[1].id
                        if getLevel(rootId) <= 0 then
                            local rootCfg = SkillTreeConfig.SKILL_MAP[rootId]
                            local rootName = rootCfg and rootCfg.name or rootId
                            return false, "需要先学习: " .. rootName
                        end
                        break
                    end
                end
            end
        end
    end

    return true, nil
end

--- 检查前置条件是否满足 (统一入口)
--- @param skillId string
--- @param getLevel function(id)->number
--- @param totalSpent number 已投入总点数
--- @return boolean canLearn, string|nil reason
function SkillTreeConfig.AreRequirementsMet(skillId, getLevel, totalSpent)
    local cfg = SkillTreeConfig.SKILL_MAP[skillId]
    if not cfg then return false, "技能不存在" end

    -- 增强节点走专用逻辑
    if cfg.nodeType == "enhance" then
        return SkillTreeConfig.CanLearnEnhance(skillId, getLevel, totalSpent)
    end

    -- 关键被动互斥: 7选1
    if cfg.isKeyPassive then
        for _, skill in ipairs(SkillTreeConfig.SKILLS) do
            if skill.isKeyPassive and skill.id ~= skillId and getLevel(skill.id) > 0 then
                return false, "已选择关键被动: " .. skill.name
            end
        end
    end

    -- 层级门槛
    if cfg.tier then
        if not SkillTreeConfig.IsTierUnlocked(cfg.tier, totalSpent) then
            local gate = SkillTreeConfig.GetTierGate(cfg.tier)
            return false, "需要投入" .. gate .. "点解锁此层"
        end
    end

    return true, nil
end

--- 获取指定层级的所有技能
--- @param tierIdx number
--- @return table[] skills
function SkillTreeConfig.GetSkillsByTier(tierIdx)
    local result = {}
    for _, skill in ipairs(SkillTreeConfig.SKILLS) do
        if skill.tier == tierIdx then
            result[#result + 1] = skill
        end
    end
    return result
end

--- 获取所有主动技能 (非增强、非关键被动)
--- @return table[] skills
function SkillTreeConfig.GetActiveSkills()
    local result = {}
    for _, skill in ipairs(SkillTreeConfig.SKILLS) do
        if skill.nodeType == "active" then
            result[#result + 1] = skill
        end
    end
    return result
end

--- 获取所有基础技能
--- @return table[] skills
function SkillTreeConfig.GetBasicSkills()
    local result = {}
    for _, skill in ipairs(SkillTreeConfig.SKILLS) do
        if skill.isBasic then
            result[#result + 1] = skill
        end
    end
    return result
end

--- 获取所有终极技能
--- @return table[] skills
function SkillTreeConfig.GetUltimateSkills()
    local result = {}
    for _, skill in ipairs(SkillTreeConfig.SKILLS) do
        if skill.isUltimate then
            result[#result + 1] = skill
        end
    end
    return result
end

--- 获取所有关键被动
--- @return table[] skills
function SkillTreeConfig.GetKeyPassives()
    local result = {}
    for _, skill in ipairs(SkillTreeConfig.SKILLS) do
        if skill.isKeyPassive then
            result[#result + 1] = skill
        end
    end
    return result
end

return SkillTreeConfig
