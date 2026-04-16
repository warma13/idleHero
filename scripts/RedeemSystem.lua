-- ============================================================================
-- RedeemSystem.lua - 兑换码系统
-- 支持: 全服码 / 限定用户码 / 存档恢复（等级/关卡/装备/物资）
-- ============================================================================

local GameState   = require("GameState")
local SaveSystem  = require("SaveSystem")
local Config      = require("Config")
local StageConfig = require("StageConfig")

local RedeemSystem = {}

-- ============================================================================
-- 兑换码配置 (新增兑换码在此添加)
-- ============================================================================
--
-- 字段说明:
--   userIds   : number[]|nil   限定用户ID列表, nil=全服可用
--   desc      : string         兑换描述(显示给玩家)
--   rewards   : table          物资奖励 (gold/soulCrystal/stone/bagItems)
--   equips    : table[]        装备奖励 { minQuality, slot?, chapter?, setId? }
--   setLevel  : number|nil     直接设置玩家等级(含属性点补发)
--   setChapter: number|nil     设置当前章节(关卡推进)
--   setStage  : number|nil     设置当前关卡(配合 setChapter 使用, 默认1)
--
-- 示例:
--   ["RESTORE-12345"] = {
--       userIds   = { 12345 },
--       desc      = "存档恢复: Lv.600 第9章 + 全身橙装",
--       setLevel  = 600,
--       setChapter = 9,
--       setStage   = 1,
--       rewards   = { soulCrystal = 2000, stone = 5000 },
--       equips    = {
--           { minQuality = 5, slot = "gloves",   chapter = 9 },
--           { minQuality = 5, slot = "amulet",   chapter = 9 },
--           { minQuality = 5, slot = "ring",     chapter = 9 },
--           { minQuality = 5, slot = "boots",    chapter = 9 },
--           { minQuality = 5, slot = "necklace", chapter = 9 },
--       },
--   },

RedeemSystem.CODES = {
    ["DAPEI-MASTER-2026"] = {
        userIds = {
            2006244731, 1145203078, 778429489, 111592145,
            1250669800, 136053625, 2137328851, 1730486538,
            683645456, 1349979336, 172906132, 41248671,
            611110485, 1289149946, 436521164,
        },
        desc = "搭配大师奖励: 顶级魔法石×6 + 搭配大师称号",
        rewards = {
            bagItems = {
                { id = "magic_stone_top", count = 6 },
            },
        },
        titles = { "build_master" },
    },
    ["TEST-T13-GEAR-3"] = {
        userIds    = { 1779057459 },
        desc       = "测试奖励: T13 熔岩征服者 + 极寒之心 全套橙装",
        equips     = {
            -- 熔岩征服者 (攻击套)
            { minQuality = 5, slot = "weapon",   chapter = 13, setId = "lava_conqueror" },
            { minQuality = 5, slot = "gloves",   chapter = 13, setId = "lava_conqueror" },
            { minQuality = 5, slot = "amulet",   chapter = 13, setId = "lava_conqueror" },
            { minQuality = 5, slot = "ring",     chapter = 13, setId = "lava_conqueror" },
            { minQuality = 5, slot = "boots",    chapter = 13, setId = "lava_conqueror" },
            { minQuality = 5, slot = "necklace", chapter = 13, setId = "lava_conqueror" },
            -- 极寒之心 (防御套)
            { minQuality = 5, slot = "weapon",   chapter = 13, setId = "permafrost_heart" },
            { minQuality = 5, slot = "gloves",   chapter = 13, setId = "permafrost_heart" },
            { minQuality = 5, slot = "amulet",   chapter = 13, setId = "permafrost_heart" },
            { minQuality = 5, slot = "ring",     chapter = 13, setId = "permafrost_heart" },
            { minQuality = 5, slot = "boots",    chapter = 13, setId = "permafrost_heart" },
            { minQuality = 5, slot = "necklace", chapter = 13, setId = "permafrost_heart" },
        },
    },
    ["PRISM-GIFT-100"] = {
        userIds = { 1779057459 },
        desc = "散光棱镜×100",
        rewards = {
            bagItems = {
                { id = "prism", count = 100 },
            },
        },
    },
    ["GEM-STARTER-7"] = {
        userIds = { 1779057459 },
        desc = "宝石入门礼包: 每种碎裂宝石×3",
        rewards = {
            gems = {
                { type = "ruby",     quality = 1, count = 3 },
                { type = "sapphire", quality = 1, count = 3 },
                { type = "emerald",  quality = 1, count = 3 },
                { type = "topaz",    quality = 1, count = 3 },
                { type = "amethyst", quality = 1, count = 3 },
                { type = "diamond",  quality = 1, count = 3 },
                { type = "skull",    quality = 1, count = 3 },
            },
        },
    },
    ["RESTORE-629673956"] = {
        userIds    = { 629673956 },
        desc       = "存档恢复: Lv.260 第6章第10关 + T6全身橙装",
        setLevel   = 260,
        setChapter = 6,
        setStage   = 10,
        rewards    = { soulCrystal = 1000, stone = 2000 },
        equips     = {
            { minQuality = 5, slot = "weapon",   chapter = 6, setId = "shadow_hunter" },
            { minQuality = 5, slot = "gloves",   chapter = 6, setId = "shadow_hunter" },
            { minQuality = 5, slot = "amulet",   chapter = 6, setId = "shadow_hunter" },
            { minQuality = 5, slot = "ring",     chapter = 6, setId = "iron_bastion" },
            { minQuality = 5, slot = "boots",    chapter = 6, setId = "iron_bastion" },
            { minQuality = 5, slot = "necklace", chapter = 6, setId = "iron_bastion" },
        },
    },
}

-- ============================================================================
-- 已兑换记录 (由 SaveSystem 持久化)
-- ============================================================================

--- 获取已兑换列表
--- @return table<string, boolean>
function RedeemSystem.GetRedeemed()
    if not GameState.redeemedCodes then
        GameState.redeemedCodes = {}
    end
    return GameState.redeemedCodes
end

--- 判断某个码是否已被兑换
--- @param code string
--- @return boolean
function RedeemSystem.IsRedeemed(code)
    local redeemed = RedeemSystem.GetRedeemed()
    return redeemed[code] == true
end

-- ============================================================================
-- 内部: 用户ID检查
-- ============================================================================

--- 获取当前用户ID (安全)
--- @return number|nil
local function GetMyUserId()
    local ok, uid = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        return lobby:GetMyUserId()
    end)
    return ok and uid or nil
end

--- 检查当前用户是否在允许列表中
--- @param userIds number[]|nil nil=全服可用
--- @return boolean
local function IsUserAllowed(userIds)
    if not userIds then return true end
    local myId = GetMyUserId()
    if not myId then return false end
    for _, uid in ipairs(userIds) do
        if uid == myId then return true end
    end
    return false
end

-- ============================================================================
-- 内部: 装备生成 (支持指定套装)
-- ============================================================================

--- 生成奖励装备
--- @param cfg table { minQuality, slot?, chapter?, setId? }
--- @return table item
local function GenerateRewardEquip(cfg)
    local ch = cfg.chapter
            or (GameState.records and GameState.records.maxChapter)
            or (GameState.stage and GameState.stage.chapter or 1)
    local qualityIdx = cfg.minQuality or 5
    return GameState.CreateEquip(qualityIdx, ch, cfg.slot, cfg.setId)
end

-- ============================================================================
-- 内部: 存档恢复 (等级/关卡)
-- ============================================================================

--- 设置玩家等级 (补发属性点, 不回退)
--- @param targetLevel number
local function ApplySetLevel(targetLevel)
    local p = GameState.player
    if targetLevel <= p.level then return end

    if targetLevel <= p.level then return end

    local gained = (targetLevel - p.level) * Config.POINTS_PER_LEVEL
    p.level = targetLevel
    p.exp = 0
    p.freePoints = p.freePoints + gained
    print("[RedeemSystem] SetLevel -> " .. targetLevel .. " (+" .. gained .. " points)")
end

--- 设置关卡进度 (只前进不回退)
--- @param chapter number
--- @param stage number|nil 默认1
local function ApplySetStage(chapter, stage)
    stage = stage or 1

    -- 校验章节合法性
    local totalChapters = StageConfig.GetChapterCount()
    chapter = math.min(chapter, totalChapters)
    local totalStages = StageConfig.GetStageCount(chapter)
    stage = math.min(stage, totalStages)

    -- 只前进不回退
    local curCh = GameState.stage.chapter
    local curSt = GameState.stage.stage
    local curVal = curCh * 1000 + curSt
    local newVal = chapter * 1000 + stage
    if newVal <= curVal then return end

    GameState.stage.chapter = chapter
    GameState.stage.stage = stage

    -- 更新记录
    if GameState.records then
        if chapter > (GameState.records.maxChapter or 1) then
            GameState.records.maxChapter = chapter
        end
        if stage > (GameState.records.maxStage or 1) or chapter > curCh then
            GameState.records.maxStage = stage
        end
    end

    print("[RedeemSystem] SetStage -> Ch." .. chapter .. " St." .. stage)
end

-- ============================================================================
-- 兑换逻辑
-- ============================================================================

--- 尝试兑换
--- @param inputCode string 用户输入的兑换码
--- @return boolean success
--- @return string message 提示信息
function RedeemSystem.Redeem(inputCode)
    if not inputCode or inputCode == "" then
        return false, "请输入兑换码"
    end

    -- 统一转大写, 去首尾空白
    local code = string.upper(inputCode)
    code = code:match("^%s*(.-)%s*$") or code

    -- 查找码
    local entry = RedeemSystem.CODES[code]
    if not entry then
        return false, "无效的兑换码"
    end

    -- 用户ID限定检查
    if not IsUserAllowed(entry.userIds) then
        return false, "无效的兑换码"
    end

    -- 检查是否已兑换
    if RedeemSystem.IsRedeemed(code) then
        return false, "该兑换码已使用"
    end

    -- 背包容量预检 (装备)
    local equipCount = entry.equips and #entry.equips or 0
    if equipCount > 0 then
        local capacity = GameState.GetInventorySize()
        local used = #GameState.inventory
        local free = capacity - used
        if free < equipCount then
            return false, "背包空间不足（需要" .. equipCount .. "格，剩余" .. free .. "格）\n请先清理背包后再领取"
        end
    end

    -- ================================================================
    -- 1. 存档恢复: 等级
    -- ================================================================
    if entry.setLevel then
        ApplySetLevel(entry.setLevel)
    end

    -- ================================================================
    -- 2. 存档恢复: 关卡推进
    -- ================================================================
    if entry.setChapter then
        ApplySetStage(entry.setChapter, entry.setStage)
    end

    -- ================================================================
    -- 3. 物资奖励
    -- ================================================================
    local rewards = entry.rewards
    if rewards then
        if rewards.gold and rewards.gold > 0 then
            GameState.player.gold = GameState.player.gold + rewards.gold
        end
        if rewards.soulCrystal and rewards.soulCrystal > 0 then
            GameState.AddSoulCrystal(rewards.soulCrystal)
        end
        if rewards.stone and rewards.stone > 0 then
            GameState.AddStone(rewards.stone)  -- 兼容旧兑换码(stone→iron)
        end
        if rewards.materials then
            GameState.AddMaterials(rewards.materials)
        end
        if rewards.bagItems then
            for _, bi in ipairs(rewards.bagItems) do
                GameState.AddBagItem(bi.id, bi.count or 1)
            end
        end
        if rewards.gems then
            for _, g in ipairs(rewards.gems) do
                GameState.AddGem(g.type, g.quality, g.count or 1)
            end
        end
    end

    -- ================================================================
    -- 4. 称号奖励
    -- ================================================================
    if entry.titles then
        local ok, TitleSystem = pcall(require, "TitleSystem")
        if ok and TitleSystem then
            if not GameState.unlockedTitles then
                GameState.unlockedTitles = {}
            end
            for _, titleId in ipairs(entry.titles) do
                -- 去重: 已有则跳过
                local found = false
                for _, ut in ipairs(GameState.unlockedTitles) do
                    if ut == titleId then found = true; break end
                end
                if not found then
                    table.insert(GameState.unlockedTitles, titleId)
                    print("[RedeemSystem] Title granted: " .. titleId)
                end
            end

        end
    end

    -- ================================================================
    -- 5. 装备奖励 (支持指定套装)
    -- ================================================================
    if entry.equips then
        for _, equipCfg in ipairs(entry.equips) do
            local item = GenerateRewardEquip(equipCfg)
            GameState.AddToInventory(item)
        end
    end

    -- 标记已兑换
    RedeemSystem.GetRedeemed()[code] = true

    -- 立即保存
    SaveSystem.Save()

    print("[RedeemSystem] Redeemed: " .. code .. " -> " .. (entry.desc or ""))
    return true, "兑换成功！" .. (entry.desc or "")
end

return RedeemSystem
