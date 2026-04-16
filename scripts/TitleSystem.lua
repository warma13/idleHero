-- ============================================================================
-- TitleSystem.lua - 称号系统 (解锁 / 效果计算 / UI 查询)
-- ============================================================================
-- 首次登录时根据 userId 一次性发放称号, 永久生效, 全部叠加
-- ============================================================================

local TitleConfig = require("TitleConfig")

local TitleSystem = {}

-- 效果 key → 中文名称映射
local EFFECT_NAMES = {
    atk         = "攻击力",
    critDmg     = "暴击伤害",
    crit        = "暴击率",
    hp          = "生命",
    def         = "防御",
    allElemDmg  = "全元素增伤",
    debuffResist = "减益抗性",
    exp         = "经验",
    luck        = "幸运",
}

-- ============================================================================
-- 初始化 (在 BuildGameUI 中调用, 存档加载完成后)
-- ============================================================================

--- 将旧格式 { "brave", "trial_1" } 迁移为新格式 { { id="brave", unlockedAt=nil }, ... }
--- 如果已经是新格式则不动
local function MigrateUnlockedTitles(GameState)
    local titles = GameState.unlockedTitles
    if not titles or #titles == 0 then return end
    -- 检查第一个元素是否为字符串（旧格式）
    if type(titles[1]) == "string" then
        local migrated = {}
        for _, tid in ipairs(titles) do
            table.insert(migrated, { id = tid, unlockedAt = nil }) -- nil = 早期版本
        end
        GameState.unlockedTitles = migrated
        print("[TitleSystem] Migrated " .. #migrated .. " titles to new format")
    end
end

function TitleSystem.Init()
    local GameState = require("GameState")
    GameState.unlockedTitles = GameState.unlockedTitles or {}

    -- 迁移旧格式
    MigrateUnlockedTitles(GameState)

    -- 已经有称号 → 跳过 (避免重复发放)
    if #GameState.unlockedTitles > 0 then
        print("[TitleSystem] Already has " .. #GameState.unlockedTitles .. " titles, skip")
        return
    end

    -- 获取当前用户 ID
    local userId = 0
    pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        userId = lobby:GetMyUserId()
    end)
    if userId == 0 then
        print("[TitleSystem] userId=0, skip")
        return
    end

    -- 查找该用户的称号列表
    local titleIds = TitleConfig.USER_TITLES[userId]
    if not titleIds then
        print("[TitleSystem] No titles for userId=" .. tostring(userId))
        return
    end

    -- 发放称号（新格式，带时间戳）
    local now = os.date("%Y-%m-%d %H:%M")
    for _, tid in ipairs(titleIds) do
        if TitleConfig.TITLES[tid] then
            table.insert(GameState.unlockedTitles, { id = tid, unlockedAt = now })
        end
    end

    if #GameState.unlockedTitles > 0 then
        print("[TitleSystem] Unlocked " .. #GameState.unlockedTitles .. " titles for userId=" .. tostring(userId))
        -- 标记存档脏数据
        local ok, SaveSystem = pcall(require, "SaveSystem")
        if ok and SaveSystem and SaveSystem.MarkDirty then
            SaveSystem.MarkDirty()
        end
    end
end

-- ============================================================================
-- 效果查询 (供 StatCalc 调用)
-- ============================================================================

--- 获取指定属性的称号加成总和
--- @param statKey string 属性 key (如 "atk", "crit", "hp" 等)
--- @return number 加成值 (百分比小数, 如 0.05 = 5%)
function TitleSystem.GetBonus(statKey)
    local ok, GameState = pcall(require, "GameState")
    if not ok or not GameState then return 0 end

    local titles = GameState.unlockedTitles
    if not titles or #titles == 0 then return 0 end

    local total = 0
    for _, entry in ipairs(titles) do
        local tid = type(entry) == "string" and entry or entry.id
        local def = TitleConfig.TITLES[tid]
        if def and def.effects and def.effects[statKey] then
            total = total + def.effects[statKey]
        end
    end
    return total
end

-- ============================================================================
-- UI 查询
-- ============================================================================

--- 获取已解锁称号的详细信息列表
--- @return table[] 每项 { id, name, desc, flavorText, effects, unlockedAt }
function TitleSystem.GetUnlockedTitles()
    local ok, GameState = pcall(require, "GameState")
    if not ok or not GameState then return {} end

    local titles = GameState.unlockedTitles
    if not titles then return {} end

    local result = {}
    for _, entry in ipairs(titles) do
        local tid = type(entry) == "string" and entry or entry.id
        local unlockedAt = type(entry) == "table" and entry.unlockedAt or nil
        local def = TitleConfig.TITLES[tid]
        if def then
            table.insert(result, {
                id = tid,
                name = def.name,
                desc = def.desc,
                flavorText = def.flavorText,
                effects = def.effects,
                category = def.category,
                unlockedAt = unlockedAt,
            })
        end
    end
    return result
end

--- 获取所有应显示的称号（已拥有 + 未拥有，IP榜只显示已拥有的）
--- @return table[] 每项 { id, name, desc, flavorText, effects, category, owned, unlockedAt }
function TitleSystem.GetAllDisplayTitles()
    local unlocked = TitleSystem.GetUnlockedTitles()
    -- 构建已拥有的 id set
    local ownedSet = {}
    local ownedMap = {}
    for _, t in ipairs(unlocked) do
        ownedSet[t.id] = true
        ownedMap[t.id] = t
    end

    local result = {}
    -- 遍历所有定义的称号
    for tid, def in pairs(TitleConfig.TITLES) do
        local owned = ownedSet[tid] == true
        -- IP榜称号：只显示已拥有的
        if def.category == "power" and not owned then
            goto continue
        end
        local entry = {
            id = tid,
            name = def.name,
            desc = def.desc,
            flavorText = def.flavorText,
            effects = def.effects,
            category = def.category,
            owned = owned,
            unlockedAt = owned and ownedMap[tid].unlockedAt or nil,
        }
        table.insert(result, entry)
        ::continue::
    end

    -- 排序：已拥有排前面，同组按名称排
    table.sort(result, function(a, b)
        if a.owned ~= b.owned then return a.owned end
        return a.name < b.name
    end)
    return result
end

-- ============================================================================
-- 佩戴 (纯展示, 不影响属性加成)
-- ============================================================================

--- 佩戴指定称号 (自动卸下之前佩戴的)
--- @param titleId string
function TitleSystem.Equip(titleId)
    local GameState = require("GameState")
    GameState.equippedTitle = titleId
    local ok, SaveSystem = pcall(require, "SaveSystem")
    if ok and SaveSystem and SaveSystem.MarkDirty then
        SaveSystem.MarkDirty()
    end
end

--- 卸下当前佩戴的称号
function TitleSystem.Unequip()
    local GameState = require("GameState")
    GameState.equippedTitle = nil
    local ok, SaveSystem = pcall(require, "SaveSystem")
    if ok and SaveSystem and SaveSystem.MarkDirty then
        SaveSystem.MarkDirty()
    end
end

--- 获取当前佩戴的称号 ID
--- @return string|nil
function TitleSystem.GetEquipped()
    local ok, GameState = pcall(require, "GameState")
    if not ok or not GameState then return nil end
    return GameState.equippedTitle
end

-- ============================================================================
-- 格式化
-- ============================================================================

--- 格式化效果表为可读字符串
--- @param effects table { atk = 0.05, crit = 0.02 }
--- @return string 如 "攻击力+5% 暴击率+2%"
function TitleSystem.FormatEffects(effects)
    if not effects then return "" end
    local parts = {}
    for key, val in pairs(effects) do
        local name = EFFECT_NAMES[key] or key
        table.insert(parts, name .. "+" .. string.format("%.0f%%", val * 100))
    end
    return table.concat(parts, " ")
end

-- ============================================================================
-- 存档域自注册
-- ============================================================================

require("SlotSaveSystem").RegisterDomain({
    name  = "titles",
    keys  = { "unlockedTitles", "equippedTitle" },
    group = "misc",
    serialize = function(GS)
        return {
            unlockedTitles = GS.unlockedTitles,
            equippedTitle  = GS.equippedTitle,
        }
    end,
    deserialize = function(GS, data)
        GS.unlockedTitles = data.unlockedTitles or {}
        GS.equippedTitle  = data.equippedTitle
    end,
})

return TitleSystem
