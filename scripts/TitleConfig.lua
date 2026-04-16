-- ============================================================================
-- TitleConfig.lua - 称号定义 & userId 映射表
-- ============================================================================
--
-- 首期排行榜结算快照 (2026-03-13)
-- IP榜: 前10名 (第8名置空跳过, 实际9人)
-- 关卡榜: 全部20名
-- 试炼榜: 前20名
-- ============================================================================

local TitleConfig = {}

-- ============================================================================
-- 称号定义
-- ============================================================================

TitleConfig.TITLES = {
    -- 战力榜 1~10 (各自独特)
    power_1  = { name = "战力榜1",       desc = "首期结算 战力第1名",   flavorText = "全服战力之巅的王者",             category = "power", effects = { atk = 0.05, critDmg = 0.03 } },
    power_2  = { name = "战力榜2",       desc = "首期结算 战力第2名",   flavorText = "一人之下的绝世强者",             category = "power", effects = { atk = 0.04, critDmg = 0.02 } },
    power_3  = { name = "战力榜3",       desc = "首期结算 战力第3名",   flavorText = "三甲之列，实力不凡",             category = "power", effects = { atk = 0.03, crit = 0.02 } },
    power_4  = { name = "战力榜4",       desc = "首期结算 战力第4名",   flavorText = "稳居前列的实力派",               category = "power", effects = { atk = 0.02 } },
    power_5  = { name = "战力榜5",       desc = "首期结算 战力第5名",   flavorText = "稳居前列的实力派",               category = "power", effects = { atk = 0.02 } },
    power_6  = { name = "战力榜6",       desc = "首期结算 战力第6名",   flavorText = "不可小觑的战斗精英",             category = "power", effects = { atk = 0.015 } },
    power_7  = { name = "战力榜7",       desc = "首期结算 战力第7名",   flavorText = "不可小觑的战斗精英",             category = "power", effects = { atk = 0.015 } },
    power_9  = { name = "战力榜9",       desc = "首期结算 战力第9名",   flavorText = "跻身十强的勇者",                 category = "power", effects = { atk = 0.01 } },
    power_10 = { name = "战力榜10",      desc = "首期结算 战力第10名",  flavorText = "跻身十强的勇者",                 category = "power", effects = { atk = 0.01 } },

    -- 关卡榜 (统一称号)
    brave    = { name = "勇敢者",        desc = "首期结算 关卡上榜",    flavorText = "勇往直前，无所畏惧",             category = "stage", effects = { hp = 0.03, def = 0.02, exp = 0.05 } },

    -- 试炼榜
    trial_1  = { name = "巅峰试炼玩家",  desc = "首期结算 试炼第1名",   flavorText = "在无尽试炼中登顶的传奇",         category = "trial", effects = { allElemDmg = 0.05, debuffResist = 0.05, luck = 0.20 } },
    trial_top = { name = "顶级试炼玩家", desc = "首期结算 试炼前20名",  flavorText = "在无尽试炼中证明了自己的实力",   category = "trial", effects = { allElemDmg = 0.02, debuffResist = 0.02, luck = 0.12 } },

    -- 特殊称号
    build_master = { name = "搭配大师", desc = "装备搭配达人", flavorText = "精通装备搭配的策略大师",   category = "special", effects = { atk = 0.03, crit = 0.01, exp = 0.05, luck = 0.10 } },
}

-- ============================================================================
-- userId → 称号ID 映射
-- ============================================================================
-- 同一玩家多榜上榜时, 合并到同一个数组中

TitleConfig.USER_TITLES = {
    -- === 特别授予 ===
    [1779057459] = { "power_1",  "brave", "trial_1" },

    -- === 战力 + 关卡 + 试炼 (三榜均上) ===
    [1525922029] = { "power_1",  "brave", "trial_top" },  -- 于天佑技术好
    [1366077302] = { "power_2",  "brave", "trial_top" },  -- 木呐嘞
    [863104848]  = { "power_3",  "brave", "trial_top" },  -- 天堂MMMMMMMMMMM
    [1349979336] = { "power_4",  "brave", "trial_top" },  -- BIC8O1Rc6
    [391522248]  = { "power_5",  "brave", "trial_top" },  -- 许墨
    [1021567960] = { "power_6",  "brave", "trial_top" },  -- 鱼鱼鱼鱼
    [833175829]  = { "power_7",  "brave", "trial_top" },  -- 斯年华
    [916728443]  = { "power_9",  "brave", "trial_top" },  -- 我要这铁棒有用

    -- === 战力 only ===
    [1402441299] = { "power_10" },                         -- 41563475

    -- === 关卡 + 试炼 ===
    [111592145]  = { "brave", "trial_top" },               -- User491848246
    [136053625]  = { "brave", "trial_top" },               -- 明
    [2086568482] = { "brave", "trial_top" },               -- 假然自得
    [1358656625] = { "brave", "trial_top" },               -- La.
    [1734900833] = { "brave", "trial_top" },               -- 不知名佳能韭菜用户

    -- === 关卡 only ===
    [248409614]  = { "brave" },                            -- 手机用户57496404
    [1308524730] = { "brave" },                            -- 氪金玩家
    [1477729816] = { "brave" },                            -- 子帆
    [1707507554] = { "brave" },                            -- 。
    [1989206441] = { "brave" },                            -- 我是卡卡卡
    [638778458]  = { "brave" },                            -- 肉蛋葱鸡
    [1250669800] = { "brave" },                            -- 你蛙哥丶

    -- === 试炼 only ===
    [778429489]  = { "trial_1" },                          -- 听风来丶 (试炼第1)
    [284952024]  = { "trial_top" },                        -- 喝喝酒
    [963690954]  = { "trial_top" },                        -- 滮__少Ye爺
    [172906132]  = { "trial_top" },                        -- 手机用户67211348
    [699348668]  = { "trial_top" },                        -- am2srbf58
    [799359540]  = { "trial_top" },                        -- 手机用户55339427
    [880530203]  = { "trial_top" },                        -- 你丑啥
    [2097086369] = { "trial_top" },                        -- 云先生
}

return TitleConfig
