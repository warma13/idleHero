-- ============================================================================
-- VersionReward.lua - 版本更新奖励系统
-- 支持领取最近3个版本的奖励（版本号 <= 当前版本）
-- ============================================================================

local GameState  = require("GameState")
local SaveSystem = require("SaveSystem")
local Config     = require("Config")
local UI         = require("urhox-libs/UI")
local Colors     = require("ui.Colors")
local Toast      = require("ui.Toast")
local Utils      = require("Utils")

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local VersionReward = {}

-- ============================================================================
-- 当前游戏版本（每次发版时手动同步）
-- ============================================================================

local CURRENT_VERSION = "1.17.0"

-- 可领取的最大历史版本数
local MAX_CLAIMABLE_VERSIONS = 3

-- ============================================================================
-- 版本号比较工具
-- ============================================================================

--- 将版本字符串解析为 {major, minor, patch}
--- @param ver string 如 "1.5.0"
--- @return number, number, number
local function ParseVersion(ver)
    local major, minor, patch = ver:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return 0, 0, 0 end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

--- 比较两个版本号，返回 -1, 0, 1
--- @param a string
--- @param b string
--- @return number
local function CompareVersions(a, b)
    local a1, a2, a3 = ParseVersion(a)
    local b1, b2, b3 = ParseVersion(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end

-- ============================================================================
-- 版本奖励配置
-- 每个版本对应一组奖励，支持: gold, soulCrystal, stone, equips
-- equips: { { minQuality = 3 }, ... }  (minQuality: 1白 2绿 3蓝 4紫 5橙)
-- ============================================================================

VersionReward.REWARDS = {
    ["1.1.1"] = {
        title   = "v1.1.1 更新奖励",
        desc    = "感谢更新！领取丰厚奖励",
        rewards = {
            gold        = 5000,
            soulCrystal = 100,
            stone       = 20,
            equips      = {
                { minQuality = 3 },  -- 至少蓝色品质装备
            },
        },
    },
    ["1.2.0"] = {
        title   = "v1.2.0 更新奖励",
        desc    = "新版本已上线，领取专属奖励！",
        rewards = {
            soulCrystal = 300,
            stone       = 100,
            equips      = {
                { minQuality = 5, slot = "weapon" },  -- 橙色品质武器
            },
        },
    },
    ["1.3.0"] = {
        title   = "v1.3.0 更新奖励",
        desc    = "增加全新章节，第四章、第五章\n属性与技能支持逐级降级，自由调整加点方案\n排行榜全新升级，支持百人榜单与实时排名查看\n修复若干已知问题，提升整体稳定性",
        rewards = {
            soulCrystal = 200,
            equips      = {
                { minQuality = 5, slot = "weapon" },  -- 橙色武器
                { minQuality = 5 },                    -- 随机橙色装备
                { minQuality = 5 },                    -- 随机橙色装备
                { minQuality = 5 },                    -- 随机橙色装备
            },
        },
    },
    ["1.3.1"] = {
        title   = "v1.3.1 更新奖励",
        desc    = "修复在小部分场景下意外丢失装备的情况\n改进了一些其它问题",
        rewards = {
            equips      = {
                { minQuality = 5, slot = "weapon" },  -- 橙色武器
                { minQuality = 5, slot = "weapon" },  -- 橙色武器
            },
        },
    },
    ["1.4.0"] = {
        title   = "v1.4.0 更新奖励",
        desc    = "新增雷鸣荒漠和瘴毒密林\n新增试炼\n优化了元素、技能、装备、存档",
        rewards = {
            soulCrystal = 500,
            bagItems    = {
                { id = "attr_reset",  count = 2 },
                { id = "skill_reset", count = 2 },
            },
        },
    },
    ["1.5.0"] = {
        title   = "v1.5.0 更新奖励",
        desc    = "新增第8章、第9章\n修复了技能系统的一些问题\n提升了存档稳定性，新增手动存档/恢复功能",
        rewards = {
            stone       = 1000,
            soulCrystal = 500,
            bagItems    = {
                { id = "attr_reset",    count = 2 },
                { id = "skill_reset",   count = 2 },
                { id = "exp_potion_100m", count = 1 },
            },
            equips      = {
                { minQuality = 5, slot = "weapon",  chapter = 5 },
                { minQuality = 5, slot = "gloves",  chapter = 5 },
                { minQuality = 5, slot = "amulet",  chapter = 5 },
                { minQuality = 5, slot = "ring",    chapter = 5 },
                { minQuality = 5, slot = "armor",   chapter = 5 },
                { minQuality = 5, slot = "boots",   chapter = 5 },
                { minQuality = 5, slot = "necklace", chapter = 5 },
            },
        },
    },
    ["1.5.1"] = {
        title   = "v1.5.1 更新奖励",
        desc    = "优化存档系统",
        rewards = {
            bagItems    = {
                { id = "exp_potion_250", count = 1 },
            },
            equips      = {
                { minQuality = 5, slot = "weapon",   chapter = 7 },
                { minQuality = 5, slot = "gloves",   chapter = 7 },
                { minQuality = 5, slot = "amulet",   chapter = 7 },
                { minQuality = 5, slot = "ring",     chapter = 7 },
                { minQuality = 5, slot = "boots",    chapter = 7 },
                { minQuality = 5, slot = "necklace", chapter = 7 },
            },
        },
    },
    ["1.5.2"] = {
        title   = "v1.5.2 更新奖励",
        desc    = "重写存档系统，修复闪退",
        rewards = {
            bagItems    = {
                { id = "exp_potion_10m", count = 1 },
            },
        },
    },
    ["1.6.0"] = {
        title   = "v1.6.0 更新奖励",
        desc    = "新增第10章、第11章\n优化装备套装效果\n新增特效等级设置",
        rewards = {
            soulCrystal = 500,
            bagItems    = {
                { id = "attr_reset",  count = 2 },
                { id = "skill_reset", count = 2 },
            },
        },
    },
    ["1.6.2"] = {
        title   = "v1.6.2 更新奖励",
        desc    = "优化世界BOSS挑战",
        rewards = {
            bagItems    = {
                { id = "wb_ticket", count = 3 },
            },
        },
    },
    ["1.7.0"] = {
        title   = "v1.7.0 更新奖励",
        desc    = "新增第12章「时渊回廊」\n优化离线奖励：新增离线Boss爆橙装和魂晶\n非橙装自动分解为强化石",
        rewards = {
            soulCrystal = 2000,
            bagItems    = {
                { id = "wb_ticket", count = 3 },
            },
            equips      = {
                { minQuality = 5, slot = "weapon", chapter = 9 },
                { minQuality = 5, slot = "weapon", chapter = 9 },
                { minQuality = 5, slot = "weapon", chapter = 9 },
                { minQuality = 5, slot = "weapon", chapter = 9 },
                { minQuality = 5, slot = "weapon", chapter = 9 },
            },
        },
    },
    ["1.7.1"] = {
        title   = "v1.7.1 更新奖励",
        desc    = "调整了伤害计算公式",
        rewards = {
            soulCrystal = 500,
            bagItems    = {
                { id = "attr_reset",  count = 2 },
                { id = "skill_reset", count = 2 },
            },
        },
    },
    ["1.8.0"] = {
        title   = "v1.8.0 更新奖励",
        desc    = "新增装备锻造，调整了装备，调整了属性产出，优化了一些显示问题，优化了一些bug",
        rewards = {
            bagItems    = {
                { id = "skill_reset", count = 2 },
                { id = "attr_reset",  count = 2 },
            },
            -- setPool: 领取时随机选一个setId, 所有equips共享同一setId
            setPool = { "shadow_hunter", "iron_bastion" },
            equips  = {
                { minQuality = 5, slot = "weapon",   chapter = 8 },
                { minQuality = 5, slot = "gloves",   chapter = 8 },
                { minQuality = 5, slot = "amulet",   chapter = 8 },
                { minQuality = 5, slot = "ring",     chapter = 8 },
                { minQuality = 5, slot = "boots",    chapter = 8 },
                { minQuality = 5, slot = "necklace", chapter = 8 },
            },
        },
    },
    ["1.9.0"] = {
        title   = "v1.9.0 更新奖励",
        desc    = "修复装备页初始不显示问题\n修复生命属性点存档遗漏\n优化UI交互体验",
        rewards = {
            soulCrystal = 1000,
            stone       = 1000,
            bagItems    = {
                { id = "attr_reset",  count = 2 },
                { id = "skill_reset", count = 2 },
            },
            equips      = {
                -- 龙息之怒 套装 (完整6件)
                { minQuality = 5, slot = "weapon",   chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "gloves",   chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "amulet",   chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "ring",     chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "boots",    chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "necklace", chapter = 9, setId = "dragon_fury" },
                -- 符文编织 套装 (完整6件)
                { minQuality = 5, slot = "weapon",   chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "gloves",   chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "amulet",   chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "ring",     chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "boots",    chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "necklace", chapter = 9, setId = "rune_weaver" },
            },
        },
    },
    ["1.9.1"] = {
        title   = "v1.9.1 更新奖励",
        desc    = "重新校准怪物难度曲线\n怪物缩放与装备成长对齐\n优化各章节难度平衡",
        rewards = {
            soulCrystal = 2000,
            stone       = 10000,
            bagItems    = {
                { id = "exp_potion_250", count = 2 },
            },
        },
    },
    ["1.10.0"] = {
        title   = "v1.10.0 更新奖励",
        desc    = "称号系统上线\n搭配大师称号\n兑换码系统",
        rewards = {
            gold        = 10000000,
            soulCrystal = 2000,
            stone       = 10000,
            bagItems    = {
                { id = "exp_potion_250", count = 2 },
                { id = "skill_reset",    count = 2 },
                { id = "attr_reset",     count = 2 },
            },
            equips = {
                -- 龙息之怒 套装 (完整6件)
                { minQuality = 5, slot = "weapon",   chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "gloves",   chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "amulet",   chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "ring",     chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "boots",    chapter = 9, setId = "dragon_fury" },
                { minQuality = 5, slot = "necklace", chapter = 9, setId = "dragon_fury" },
                -- 符文编织 套装 (完整6件)
                { minQuality = 5, slot = "weapon",   chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "gloves",   chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "amulet",   chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "ring",     chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "boots",    chapter = 9, setId = "rune_weaver" },
                { minQuality = 5, slot = "necklace", chapter = 9, setId = "rune_weaver" },
            },
        },
    },
    ["1.11.0"] = {
        title   = "v1.11.0 更新奖励",
        desc    = "优化了数值系统",
        rewards = {
            soulCrystal = 500,
            stone       = 1000,
            bagItems    = {
                { id = "skill_reset", count = 2 },
                { id = "attr_reset",  count = 2 },
            },
            equips      = {
                { minQuality = 5, slot = "weapon",   chapter = 9 },
                { minQuality = 5, slot = "gloves",   chapter = 9 },
                { minQuality = 5, slot = "amulet",   chapter = 9 },
                { minQuality = 5, slot = "ring",     chapter = 9 },
                { minQuality = 5, slot = "boots",    chapter = 9 },
                { minQuality = 5, slot = "necklace", chapter = 9 },
            },
        },
    },
    ["1.12.0"] = {
        title   = "v1.12.0 更新奖励",
        desc    = "新增第13章\n对卡顿进行优化\n优化了BOSS系统",
        rewards = {
            stone       = 1000,
            soulCrystal = 500,
        },
    },
    ["1.12.1"] = {
        title   = "v1.12.1 更新奖励",
        desc    = "修复离线奖励\n修复装备掉落问题",
        rewards = {
            bagItems    = {
                { id = "skill_reset", count = 1 },
                { id = "attr_reset",  count = 1 },
            },
        },
    },
    ["1.13.0"] = {
        title   = "v1.13.0 更新奖励",
        desc    = "新增第14章「蚀毒深渊」\n新增日常任务系统\n优化战斗体验",
        rewards = {
            stone       = 1000,
            bagItems    = {
                { id = "attr_reset",  count = 1 },
                { id = "skill_reset", count = 1 },
            },
            equips      = {
                { minQuality = 5, slot = "weapon",   chapter = 9 },
                { minQuality = 5, slot = "gloves",   chapter = 9 },
                { minQuality = 5, slot = "amulet",   chapter = 9 },
                { minQuality = 5, slot = "ring",     chapter = 9 },
                { minQuality = 5, slot = "boots",    chapter = 9 },
                { minQuality = 5, slot = "necklace", chapter = 9 },
            },
        },
    },
    ["1.13.2"] = {
        title   = "v1.13.2 更新奖励",
        desc    = "提升了幸运词条的数值",
        rewards = {
            equips = {
                { minQuality = 5, slot = "necklace", chapter = 12 },
            },
        },
    },
    ["1.14.0"] = {
        title   = "v1.14.0 更新奖励",
        desc    = "增加宝石系统",
        rewards = {
            gems = {
                { allTypes = true, qualityIdx = 1, count = 3 },  -- 7种碎裂宝石各3颗
            },
            bagItems = {
                { id = "skill_reset", count = 2 },
                { id = "attr_reset",  count = 2 },
            },
        },
    },
    ["1.15.0"] = {
        title   = "v1.15.0 更新奖励",
        desc    = "新增折光矿脉副本\n专属矿脉怪物与战斗背景",
        rewards = {
            bagItems = {
                { id = "skill_reset", count = 1 },
                { id = "attr_reset",  count = 1 },
            },
            gems = {
                { allTypes = true, qualityIdx = 1, count = 3 },  -- 7种碎裂宝石各3颗
            },
        },
    },
    ["1.16.0"] = {
        title   = "v1.16.0 更新奖励",
        desc    = "新增第16章「深渊潮汐」",
        rewards = {
            stone       = 1000,
            soulCrystal = 500,
            bagItems = {
                { id = "skill_reset", count = 1 },
                { id = "attr_reset",  count = 1 },
            },
        },
    },
    ["1.17.0"] = {
        title   = "v1.17.0 更新奖励",
        desc    = "进行了优化",
        rewards = {
            equips = {
                { minQuality = 5, slot = "weapon",   chapter = 9 },
                { minQuality = 5, slot = "gloves",   chapter = 9 },
                { minQuality = 5, slot = "amulet",   chapter = 9 },
                { minQuality = 5, slot = "ring",     chapter = 9 },
                { minQuality = 5, slot = "boots",    chapter = 9 },
                { minQuality = 5, slot = "necklace", chapter = 9 },
                { minQuality = 5, slot = "necklace", chapter = 9 },
            },
        },
    },
}

-- ============================================================================
-- UI 图标
-- ============================================================================

local ICON = "icon_version_reward_20260308_20260308025301.png"

function VersionReward.GetIcon()
    return ICON
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 获取当前版本
function VersionReward.GetCurrentVersion()
    return CURRENT_VERSION
end

--- 获取可领取的版本列表（最近 MAX_CLAIMABLE_VERSIONS 个，版本号 <= 当前版本）
--- 返回按版本号从新到旧排列的列表 { { version = "1.5.0", config = {...} }, ... }
--- @return table[]
function VersionReward.GetClaimableVersions()
    -- 收集所有 <= 当前版本的奖励版本
    local candidates = {}
    for ver, cfg in pairs(VersionReward.REWARDS) do
        if CompareVersions(ver, CURRENT_VERSION) <= 0 then
            table.insert(candidates, { version = ver, config = cfg })
        end
    end
    -- 按版本号从新到旧排序
    table.sort(candidates, function(a, b)
        return CompareVersions(a.version, b.version) > 0
    end)
    -- 取最近 N 个
    local result = {}
    for i = 1, math.min(#candidates, MAX_CLAIMABLE_VERSIONS) do
        table.insert(result, candidates[i])
    end
    return result
end

--- 获取当前版本的奖励配置（兼容旧调用）
function VersionReward.GetCurrentRewardConfig()
    return VersionReward.REWARDS[CURRENT_VERSION]
end

--- 指定版本是否已领取
--- @param ver string|nil 版本号，nil 则检查当前版本
--- @return boolean
function VersionReward.IsClaimed(ver)
    ver = ver or CURRENT_VERSION
    if not GameState.claimedVersionRewards then
        GameState.claimedVersionRewards = {}
    end
    return GameState.claimedVersionRewards[ver] == true
end

--- 是否有任何可领取的未领奖励（用于红点提示）
function VersionReward.HasUnclaimedReward()
    local versions = VersionReward.GetClaimableVersions()
    for _, entry in ipairs(versions) do
        if not VersionReward.IsClaimed(entry.version) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 背包容量预检
-- ============================================================================

--- 检查背包是否能容纳指定数量的装备
--- @param equipCount number 需要放入的装备数量
--- @return boolean canFit
--- @return number freeSlots 剩余空位数
function VersionReward.CheckInventorySpace(equipCount)
    local capacity = GameState.GetInventorySize()
    local used = #GameState.inventory
    local free = capacity - used
    return free >= equipCount, free
end

-- ============================================================================
-- 装备生成（保证最低品质）
-- ============================================================================

--- 为版本奖励生成一件装备
--- @param minQuality number 最低品质 (1~5)
--- @param slotId string|nil 指定槽位 (如 "weapon")，nil 则随机
--- @param chapter number|nil 指定章节(tier)，nil 则取玩家最高章节
--- @param setId string|nil 强制指定套装ID
--- @return table item
local function GenerateRewardEquip(minQuality, slotId, chapter, setId)
    local ch = chapter
            or (GameState.records and GameState.records.maxChapter)
            or (GameState.stage and GameState.stage.chapter or 1)
    return GameState.CreateEquip(minQuality, ch, slotId, setId)
end

-- ============================================================================
-- 领取奖励
-- ============================================================================

--- 尝试领取指定版本的奖励
--- @param ver string|nil 版本号，nil 则领取当前版本
--- @return boolean success
--- @return string message
function VersionReward.Claim(ver)
    ver = ver or CURRENT_VERSION

    local cfg = VersionReward.REWARDS[ver]
    if not cfg then
        return false, "该版本无可用奖励"
    end

    if VersionReward.IsClaimed(ver) then
        return false, "已领取过此版本奖励"
    end

    local rewards = cfg.rewards
    local equipCount = rewards.equips and #rewards.equips or 0

    -- 预检背包容量
    if equipCount > 0 then
        local canFit, freeSlots = VersionReward.CheckInventorySpace(equipCount)
        if not canFit then
            return false, "背包空间不足（需" .. equipCount .. "格，剩余" .. freeSlots .. "格），请先清理背包"
        end
    end

    -- 发放金币
    if rewards.gold and rewards.gold > 0 then
        GameState.player.gold = GameState.player.gold + rewards.gold
    end

    -- 发放魂晶
    if rewards.soulCrystal and rewards.soulCrystal > 0 then
        GameState.AddSoulCrystal(rewards.soulCrystal)
    end

    -- 发放强化石 (兼容旧版本奖励stone→iron)
    if rewards.stone and rewards.stone > 0 then
        GameState.AddStone(rewards.stone)
    end
    -- 发放材料
    if rewards.materials then
        GameState.AddMaterials(rewards.materials)
    end

    -- 发放背包道具
    if rewards.bagItems then
        for _, bi in ipairs(rewards.bagItems) do
            GameState.AddBagItem(bi.id, bi.count or 1)
        end
    end

    -- 发放宝石
    if rewards.gems then
        local gemTypes = Config.GEM_TYPES
        for _, gemCfg in ipairs(rewards.gems) do
            if gemCfg.allTypes then
                -- 每种宝石都给
                for _, gt in ipairs(gemTypes) do
                    GameState.AddGem(gt.id, gemCfg.qualityIdx, gemCfg.count)
                end
            else
                GameState.AddGem(gemCfg.typeId, gemCfg.qualityIdx, gemCfg.count)
            end
        end
    end

    -- 生成并发放装备
    if rewards.equips then
        -- setPool: 随机选一个setId, 所有equips共享
        local sharedSetId = nil
        if rewards.setPool and #rewards.setPool > 0 then
            sharedSetId = rewards.setPool[math.random(1, #rewards.setPool)]
        end
        for _, equipCfg in ipairs(rewards.equips) do
            local sid = equipCfg.setId or sharedSetId
            local item = GenerateRewardEquip(equipCfg.minQuality or 1, equipCfg.slot, equipCfg.chapter, sid)
            GameState.AddToInventory(item)
        end
    end

    -- 标记已领取
    if not GameState.claimedVersionRewards then
        GameState.claimedVersionRewards = {}
    end
    GameState.claimedVersionRewards[ver] = true

    -- 立即保存
    SaveSystem.Save()

    print("[VersionReward] Claimed rewards for version " .. ver)
    return true, "领取成功！"
end

-- ============================================================================
-- 奖励描述文本生成
-- ============================================================================

local QUALITY_NAMES = { "白色", "绿色", "蓝色", "紫色", "橙色" }
local QUALITY_COLORS = {
    { 200, 200, 200 }, { 100, 220, 100 }, { 80, 140, 255 },
    { 180, 80, 220 },  { 255, 165, 0 },
}

--- 生成奖励描述列表（用于UI展示）
--- @param ver string|nil 版本号，nil 则使用当前版本
--- @return table[] items  { { text=string, color=table } }
function VersionReward.GetRewardDescList(ver)
    local cfg = ver and VersionReward.REWARDS[ver] or VersionReward.GetCurrentRewardConfig()
    if not cfg then return {} end

    local list = {}
    local r = cfg.rewards

    if r.gold and r.gold > 0 then
        table.insert(list, { text = "金币 ×" .. r.gold, color = { 255, 215, 0, 255 } })
    end
    if r.soulCrystal and r.soulCrystal > 0 then
        table.insert(list, { text = "魂晶 ×" .. r.soulCrystal, color = { 180, 100, 255, 255 } })
    end
    if r.stone and r.stone > 0 then
        table.insert(list, { text = "锈蚀铁块 ×" .. r.stone, color = { 160, 180, 200, 255 } })
    end
    if r.materials then
        for matId, amt in pairs(r.materials) do
            local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
            local name = def and def.name or matId
            local clr = def and def.color or { 160, 180, 200 }
            table.insert(list, { text = name .. " ×" .. amt, color = { clr[1], clr[2], clr[3], 255 } })
        end
    end
    if r.bagItems then
        for _, bi in ipairs(r.bagItems) do
            local itemCfg = Config.ITEM_MAP[bi.id]
            if itemCfg then
                table.insert(list, {
                    text = itemCfg.name .. " ×" .. (bi.count or 1),
                    color = { itemCfg.color[1], itemCfg.color[2], itemCfg.color[3], 255 },
                })
            end
        end
    end
    if r.gems then
        local gemTypes = Config.GEM_TYPES
        local gemQualities = Config.GEM_QUALITIES
        for _, gemCfg in ipairs(r.gems) do
            local qDef = gemQualities[gemCfg.qualityIdx]
            local qName = qDef and qDef.name or "碎裂"
            local qColor = qDef and qDef.color or { 200, 200, 200 }
            if gemCfg.allTypes then
                table.insert(list, {
                    text = qName .. "宝石(全7种) ×" .. gemCfg.count,
                    color = { qColor[1], qColor[2], qColor[3], 255 },
                })
            else
                local typeName = gemCfg.typeId or "宝石"
                for _, gt in ipairs(gemTypes) do
                    if gt.id == gemCfg.typeId then typeName = gt.name; break end
                end
                table.insert(list, {
                    text = qName .. typeName .. " ×" .. gemCfg.count,
                    color = { qColor[1], qColor[2], qColor[3], 255 },
                })
            end
        end
    end
    local SLOT_NAMES = { weapon = "武器", gloves = "手套", amulet = "护符", ring = "戒指", armor = "铠甲", boots = "靴子", necklace = "项链" }
    if r.equips then
        for _, eq in ipairs(r.equips) do
            local qIdx = eq.minQuality or 1
            local qName = QUALITY_NAMES[qIdx] or "白色"
            local qColor = QUALITY_COLORS[qIdx] or { 200, 200, 200 }
            local slotStr = eq.slot and SLOT_NAMES[eq.slot] or "装备"
            local tierStr = eq.chapter and ("T" .. eq.chapter .. " ") or ""
            table.insert(list, {
                text = tierStr .. qName .. "品质" .. slotStr .. " ×1",
                color = { qColor[1], qColor[2], qColor[3], 255 },
            })
        end
    end

    return list
end

-- ============================================================================
-- UI 弹窗
-- ============================================================================

---@type Widget
local overlay_     = nil
---@type Widget
local overlayRoot_ = nil

function VersionReward.SetOverlayRoot(root)
    overlayRoot_ = root
end

function VersionReward.Hide()
    if overlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
end

--- 构建单个版本的奖励区块 UI
--- @param ver string
--- @param cfg table
--- @return Widget
local function BuildVersionBlock(ver, cfg)
    local claimed = VersionReward.IsClaimed(ver)
    local rewardItems = VersionReward.GetRewardDescList(ver)

    -- 奖励条目
    local rewardChildren = {}
    for _, item in ipairs(rewardItems) do
        table.insert(rewardChildren, UI.Panel {
            width = "100%", height = 26,
            flexDirection = "row", alignItems = "center", gap = 6,
            paddingHorizontal = 10,
            backgroundColor = { 40, 45, 60, 150 },
            borderRadius = 5,
            children = {
                UI.Label { text = "•", fontSize = 12, fontColor = item.color },
                UI.Label { text = item.text, fontSize = 11, fontColor = item.color },
            },
        })
    end

    -- 领取/已领取按钮
    local actionButton
    if claimed then
        actionButton = UI.Panel {
            width = "100%", height = 30,
            backgroundColor = { 60, 65, 75, 200 },
            borderRadius = 6,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "已领取", fontSize = 12, fontColor = { 120, 130, 140, 200 } },
            },
        }
    else
        actionButton = UI.Button {
            text = "领取奖励",
            width = "100%", height = 30, fontSize = 12,
            variant = "primary",
            onClick = Utils.Debounce(function()
                local ok, msg = VersionReward.Claim(ver)
                if ok then
                    Toast.Success("v" .. ver .. " 奖励领取成功！")
                    if VersionReward._embeddedRefreshFn then
                        VersionReward._embeddedRefreshFn()
                    else
                        VersionReward.Hide()
                        VersionReward.Show()
                    end
                else
                    Toast.Warn(msg)
                end
            end, 0.5),
        }
    end

    -- 版本块整体：标题 + 描述 + 奖励列表 + 按钮
    return UI.Panel {
        width = "100%",
        backgroundColor = { 35, 40, 55, 200 },
        borderRadius = 8,
        borderWidth = 1,
        borderColor = claimed and { 60, 70, 90, 80 } or { 120, 140, 200, 120 },
        padding = 10,
        gap = 8,
        children = {
            -- 版本标题行
            UI.Panel {
                width = "100%", gap = 2,
                children = {
                    UI.Label {
                        text = cfg.title or ("v" .. ver .. " 更新奖励"),
                        fontSize = 13,
                        fontColor = claimed and { 140, 150, 160, 180 } or { 255, 220, 100, 255 },
                    },
                    UI.Label {
                        text = cfg.desc or "",
                        fontSize = 9,
                        fontColor = claimed and { 100, 110, 120, 150 } or Colors.textDim,
                    },
                },
            },
            -- 奖励列表
            UI.Panel { width = "100%", gap = 4, children = rewardChildren },
            -- 按钮
            actionButton,
        },
    }
end

function VersionReward.Show()
    if overlay_ then VersionReward.Hide() end

    local versions = VersionReward.GetClaimableVersions()
    if #versions == 0 then
        Toast.Show("当前无可用更新奖励")
        return
    end

    -- 构建各版本区块（从新到旧）
    local versionBlocks = {}
    for _, entry in ipairs(versions) do
        table.insert(versionBlocks, BuildVersionBlock(entry.version, entry.config))
    end

    overlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() VersionReward.Hide() end,
        children = {
            UI.Panel {
                width = "82%", maxWidth = 320,
                maxHeight = "88%",
                backgroundColor = { 28, 32, 48, 250 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                padding = 12,
                gap = 10,
                overflow = "scroll",
                onClick = function() end, -- 阻止穿透关闭
                children = {
                    -- 顶部标题
                    UI.Panel {
                        width = "100%",
                        alignItems = "center", justifyContent = "center",
                        children = {
                            UI.Label {
                                text = "版本更新奖励",
                                fontSize = 16,
                                fontColor = { 255, 220, 100, 255 },
                                textAlign = "center",
                            },
                        },
                    },
                    -- 分割线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 90, 120, 80 },
                    },
                    -- 版本区块列表
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        children = versionBlocks,
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        width = "100%", height = 30, fontSize = 12,
                        onClick = function() VersionReward.Hide() end,
                    },
                },
            },
        },
    }

    overlayRoot_:AddChild(overlay_)
end

function VersionReward.Toggle()
    if overlay_ then VersionReward.Hide() else VersionReward.Show() end
end

--- 刷新嵌入模式的回调（RewardPanel 调用）
function VersionReward.SetEmbeddedRefresh(fn)
    VersionReward._embeddedRefreshFn = fn
end

--- 将版本奖励内容构建到指定容器中（用于 RewardPanel 嵌入）
--- 保留原始卡片样式（背景、圆角、边框、标题、分割线）
function VersionReward.BuildContent(container)
    if not container then return end

    local versions = VersionReward.GetClaimableVersions()

    -- 内容子元素
    local cardChildren = {
        -- 顶部标题
        UI.Panel {
            width = "100%",
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label {
                    text = "版本更新奖励",
                    fontSize = 16,
                    fontColor = { 255, 220, 100, 255 },
                    textAlign = "center",
                },
            },
        },
        -- 分割线
        UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 80, 90, 120, 80 },
        },
    }

    if #versions == 0 then
        table.insert(cardChildren, UI.Panel {
            width = "100%", alignItems = "center", justifyContent = "center",
            paddingVertical = 40,
            children = {
                UI.Label { text = "当前无可用更新奖励", fontSize = 13, fontColor = { 160, 165, 180, 180 } },
            },
        })
    else
        -- 版本区块列表
        local versionBlocks = {}
        for _, entry in ipairs(versions) do
            table.insert(versionBlocks, BuildVersionBlock(entry.version, entry.config))
        end
        table.insert(cardChildren, UI.Panel {
            width = "100%", gap = 8,
            children = versionBlocks,
        })
    end

    -- 原始卡片样式（flexShrink=1 配合 RewardPanel 的 overflow hidden 限高）
    container:AddChild(UI.Panel {
        width = "100%", maxWidth = 320,
        flexShrink = 1,
        backgroundColor = { 28, 32, 48, 250 },
        borderRadius = 12,
        borderWidth = 1, borderColor = { 100, 120, 180, 120 },
        padding = 12,
        gap = 10,
        overflow = "scroll",
        onClick = function() end,
        children = cardChildren,
    })
end

return VersionReward
