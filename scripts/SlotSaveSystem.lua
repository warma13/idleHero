-- ============================================================================
-- SlotSaveSystem.lua - 多槽位云端存档系统
--
-- 设计原则:
--   1. 云端加载: 启动时只读云端, 本地存档不参与启动加载 (WASM 每次启动为空)
--   2. 本地缓存: 运行中先写本地(同步) → 再异步上传云端
--   3. 多槽位: 10 个独立存档 save_slot_N, save_meta 存概要
--   4. 向后兼容: 每次保存同步回写旧 save_data Key
--   5. 旧存档迁移: auto_save → slot_1, manual_save → slot_2
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local GameState = require("GameState")
local Config    = require("Config")

local SlotSaveSystem = {}

-- ============================================================================
-- 常量
-- ============================================================================

local SAVE_INTERVAL        = 30     -- 自动存档间隔(秒)
local DIRTY_DELAY          = 3      -- 脏标记延迟保存(秒)
local CLOUD_TIMEOUT        = 10     -- 云端请求超时(秒)
local MAX_RETRY            = 3      -- 最大重试次数
local MIN_OFFLINE_SEC      = 300    -- 离线奖励最短时间(秒)
local MAX_OFFLINE_SEC      = 28800  -- 离线奖励最长时间(秒)
local CURRENT_SAVE_VERSION = 14
local MAX_SLOTS            = 10
local SAVE_FORMAT          = 2      -- 分片存档格式版本
local CHUNK_MAX_BYTES      = 9 * 1024  -- 单 key 最大字节数 (9KB, 留1KB安全余量)

-- ============================================================================
-- 内部状态
-- ============================================================================

local initialized_    = false
local saveConfirmed_  = false   -- 只有 LoadSlot/CreateNewSlot 成功后才为 true

local currentSlot_    = 0       -- 当前活跃槽位 (1-10)
local saveMeta_       = nil     -- save_meta 完整对象
local lastMetaSnapshot_ = nil   -- 用于 meta 更新优化 { level, chapter, stage, maxFloor }

-- 计时器
local saveTimer_      = 0
local dirtyTimer_     = 0

-- 云端重试
local retryCount_     = 0
local retryTimer_     = 0
local pendingSaveData_ = nil

-- 通用延迟重试队列 (Init/Migration 阶段用)
local pendingRetry_   = nil     -- { timer, fn }

-- Init 阶段回调
local onMetaReady_    = nil
local initTimeout_    = 0
local initPhase_      = "idle"  -- "idle" | "loading_meta" | "migrating" | "done"

-- playTime 追踪
local playTime_       = 0
local createdAt_      = 0
local migratedFrom_   = nil

-- 公开字段
SlotSaveSystem.offlineSeconds = 0
SlotSaveSystem._saveCount     = 0

-- Toast (延迟获取)
local Toast_ = nil
local function getToast()
    if not Toast_ then
        local ok, t = pcall(require, "ui.Toast")
        if ok then Toast_ = t end
    end
    return Toast_
end

-- ============================================================================
-- 存档域注册 (模块自注册 serialize/deserialize, 消除硬编码字段)
-- ============================================================================

--- 已注册的存档域列表
--- @type { name:string, keys:string[], group:string, serialize:fun(GS:table):table, deserialize:fun(GS:table, data:table) }[]
local domains_ = {}

--- 域拥有的 key 集合 (快速查找)
local domainKeySet_ = {}

--- 注册存档域: 模块在自身文件末尾调用, 将序列化/反序列化逻辑从 SlotSaveSystem 移至模块
---@param cfg { name:string, keys:string[], group:string, serialize:fun(GS:table):table, deserialize:fun(GS:table, data:table) }
function SlotSaveSystem.RegisterDomain(cfg)
    table.insert(domains_, cfg)
    for _, key in ipairs(cfg.keys) do
        domainKeySet_[key] = true
    end
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 原子写入: 先写 .tmp 再 rename
local function SafeWriteFile(path, content)
    local tmpPath = path .. ".tmp"
    local ok, err = pcall(function()
        local file = File(tmpPath, FILE_WRITE)
        if not file:IsOpen() then error("Cannot open: " .. tmpPath) end
        file:WriteString(content)
        file:Close()
    end)
    if not ok then
        print("[SlotSave] SafeWrite failed: " .. tostring(err))
        return false
    end
    local renamed = fileSystem:Rename(tmpPath, path)
    if not renamed then
        local copied = fileSystem:Copy(tmpPath, path)
        if copied then fileSystem:Delete(tmpPath) else return false end
    end
    return true
end

--- 读取 JSON 文件 → table
local function ReadJsonFile(path)
    if not fileSystem:FileExists(path) then return nil end
    local result = nil
    pcall(function()
        local file = File(path, FILE_READ)
        if file:IsOpen() then
            local json = file:ReadString()
            file:Close()
            local ok, data = pcall(cjson.decode, json)
            if ok and data then result = data end
        end
    end)
    return result
end

-- ============================================================================
-- 分片存储：工具函数
-- ============================================================================

--- DJB2 哈希校验码 (32位无符号)
local function CalcChecksum(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash << 5) + hash + string.byte(str, i)) & 0xFFFFFFFF
    end
    return hash
end

-- ============================================================================
-- 装备数据压缩/解压 (缩短 key + 去除可推导字段)
-- ============================================================================

--- slot → slotName 查找表 (运行时构建一次)
local SLOT_NAME_MAP_ = nil
local function GetSlotNameMap()
    if not SLOT_NAME_MAP_ then
        SLOT_NAME_MAP_ = {}
        for _, cfg in ipairs(Config.EQUIP_SLOTS) do
            SLOT_NAME_MAP_[cfg.id] = cfg.name
        end
    end
    return SLOT_NAME_MAP_
end

--- 压缩单件装备 (写入存档时调用)
--- 缩短 key 名 + 删除可从 Config 推导的冗余字段
--- v8: 去除 ms/mv/ss/t/tm/bmv, 新增 ip/af(含 value)
local function CompressItem(item)
    if not item or type(item) ~= "table" then return item end
    local c = {}
    c.s   = item.slot           -- slot
    c.q   = item.qualityIdx     -- qualityIdx
    c.ip  = item.itemPower      -- itemPower (v8 新增)
    c.si  = item.setId          -- setId
    -- (v4.0: c.e = element 已移除, 武器不再有元素)
    c.n   = item.name           -- name (display name, if exists)

    -- 锁定状态 (仅锁定时写入)
    if item.locked then c.lk = true end

    -- 强化相关 (仅存在时写入)
    if item.upgradeLv and item.upgradeLv > 0 then
        c.ul  = item.upgradeLv
        c.us  = item.upgradeStonesSpent  -- 旧版兼容
        c.ums = item.upgradeMatSpent     -- v13: 多材料消耗记录
        c.ugs = item.upgradeGoldSpent    -- v14: 升级金币消耗记录
    end
    -- 终局强化标记 (v14)
    if item.endgameEnhanced then c.eg = true end

    -- 宝石孔位
    if item.sockets and item.sockets > 0 then
        c.sk = item.sockets
    end
    if item.gems then
        local hasGem = false
        local cg = {}
        for idx, gem in pairs(item.gems) do
            if gem then
                cg[tostring(idx)] = { t = gem.type, q = gem.quality }
                hasGem = true
            end
        end
        if hasGem then c.gm = cg end
    end

    -- 主属性 (固有, 不占词缀格)
    if item.mainStatId then
        c.msi = item.mainStatId
        c.msb = item.mainStatBase
    end

    -- 统一词缀压缩 (v8: id + value + greater)
    if item.affixes and #item.affixes > 0 then
        local ca = {}
        for i, aff in ipairs(item.affixes) do
            local entry = { i = aff.id, v = aff.value }
            if aff.greater then entry.g = 1 end
            if aff.baseValue then entry.bv = aff.baseValue end
            if aff.milestoneCount and aff.milestoneCount > 0 then entry.mc = aff.milestoneCount end
            ca[i] = entry
        end
        c.af = ca
    end

    -- 删除的冗余字段: slotName, qualityName, qualityColor
    -- 这些可从 Config.EQUIP_SLOTS[slot] 和 Config.EQUIP_QUALITY[qualityIdx] 推导

    return c
end

--- 解压单件装备 (读取存档时调用)
--- 恢复完整 key 名 + 补回可推导字段
--- v8: 读取 ip/af(含 value/greater), 不再有 ms/mv/ss/t/tm
local function DecompressItem(c)
    if not c or type(c) ~= "table" then return c end

    -- 检测是否为压缩格式 (有 's' 字段而没有 'slot' 字段)
    if c.slot then return c end  -- 已是完整格式，无需解压

    local item = {}
    item.slot       = c.s
    item.qualityIdx = c.q
    item.itemPower  = c.ip
    item.setId      = c.si
    item.element    = c.e
    item.name       = c.n

    -- 恢复可推导字段
    local slotNameMap = GetSlotNameMap()
    item.slotName = slotNameMap[item.slot] or item.slot

    local quality = Config.EQUIP_QUALITY[item.qualityIdx]
    if quality then
        item.qualityName  = quality.name
        item.qualityColor = quality.color
    else
        item.qualityName  = "未知"
        item.qualityColor = { 200, 200, 200 }
    end

    -- 锁定状态
    if c.lk then item.locked = true end

    -- 强化字段
    if c.ul and c.ul > 0 then
        item.upgradeLv         = c.ul
        item.upgradeStonesSpent = c.us  -- 旧版兼容
        item.upgradeMatSpent   = c.ums  -- v13: 多材料消耗记录
        item.upgradeGoldSpent  = c.ugs  -- v14: 升级金币消耗记录
    end
    -- 终局强化标记 (v14)
    if c.eg then item.endgameEnhanced = true end

    -- 宝石孔位解压
    if c.sk and c.sk > 0 then
        item.sockets = c.sk
    end
    if c.gm then
        item.gems = {}
        for idx, cg in pairs(c.gm) do
            item.gems[tonumber(idx)] = { type = cg.t, quality = cg.q }
        end
    end

    -- 词缀解压 (兼容 v7 和 v8 两种格式)
    if c.af and #c.af > 0 then
        item.affixes = {}
        for i, ca in ipairs(c.af) do
            if ca.v ~= nil then
                -- v8+ 格式: 有 value 字段
                local aff = {
                    id = ca.i,
                    value = ca.v,
                    greater = ca.g == 1,
                }
                if ca.bv then aff.baseValue = ca.bv end
                if ca.mc then aff.milestoneCount = ca.mc end
                item.affixes[i] = aff
            else
                -- v7 格式: 旧 proc 词缀, 只有 id + enhanced
                item.affixes[i] = {
                    id = ca.i,
                    enhanced = ca.e == 1,
                }
            end
        end
    end

    -- 主属性 (固有, 不占词缀格) — 从压缩字段恢复, value 由 IP+升级等级 重算
    if c.msi then
        item.mainStatId   = c.msi
        item.mainStatBase = c.msb
        item.mainStatValue = Config.CalcMainStatValueFull(c.msb, item.itemPower or 100, item.upgradeLv)
    end

    -- 旧字段解压 (v7 兼容: ms/mv/bmv/ss/t/tm → 供迁移代码使用)
    if c.ms then item.mainStat      = c.ms end
    if c.mv then item.mainValue     = c.mv end
    if c.bmv then item.baseMainValue = c.bmv end
    if c.t  then item.tier          = c.t  end
    if c.tm then item.tierMul       = c.tm end
    if c.ss then
        item.subStats = {}
        for i, cs in ipairs(c.ss) do
            if cs.key then
                item.subStats[i] = cs  -- 未压缩格式
            else
                item.subStats[i] = { key = cs.k, value = cs.v }
            end
        end
    end

    return item
end

--- 压缩装备表 (equipment 或 inventory)
local function CompressEquipmentTable(tbl, isArray)
    if not tbl then return tbl end
    if isArray then
        -- inventory: 数组
        local result = {}
        for i, item in ipairs(tbl) do
            result[i] = CompressItem(item)
        end
        return result
    else
        -- equipment: key-value (slotId → item)
        local result = {}
        for slotId, item in pairs(tbl) do
            result[slotId] = CompressItem(item)
        end
        return result
    end
end

--- 解压装备表
local function DecompressEquipmentTable(tbl, isArray)
    if not tbl then return tbl end
    if isArray then
        local result = {}
        for i, item in ipairs(tbl) do
            result[i] = DecompressItem(item)
        end
        return result
    else
        local result = {}
        for slotId, item in pairs(tbl) do
            result[slotId] = DecompressItem(item)
        end
        return result
    end
end

--- 分片组定义：将 Serialize() 输出拆分为独立功能组
--- 返回 { groupName = subTable, ... }
local function SplitIntoGroups(saveData)
    local groups = {
        core = {
            version   = saveData.version,
            timestamp = saveData.timestamp,
            _meta     = saveData._meta,
            player    = saveData.player,
            stage     = saveData.stage,
            records   = saveData.records,
            migrated_elemDmg_nerf = saveData.migrated_elemDmg_nerf,
        },
        currency = {
            materials   = saveData.materials,
            expandCount = saveData.expandCount,
            gemBagExpandCount = saveData.gemBagExpandCount,
        },
        equip = {
            equipment = CompressEquipmentTable(saveData.equipment, false),
        },
        inv = {
            inventory = CompressEquipmentTable(saveData.inventory, true),
        },
        skills = {
            skills       = saveData.skills,
            skillLoadout = saveData.skillLoadout,
            potionBuffs  = saveData.potionBuffs,
        },
        misc = {
            -- 硬编码保留的 misc 字段 (未迁移至域注册的)
            autoDecompConfig      = saveData.autoDecompConfig,
            bag                   = saveData.bag,
            gemBag                = saveData.gemBag,
            redeemedCodes         = saveData.redeemedCodes,
            claimedVersionRewards = saveData.claimedVersionRewards,
        },
    }

    -- 域注册的字段: 按声明的 group 注入对应分组
    for _, domain in ipairs(domains_) do
        local g = groups[domain.group or "misc"]
        if g then
            for _, key in ipairs(domain.keys) do
                g[key] = saveData[key]
            end
        end
    end

    return groups
end

--- 从功能组合并还原为完整 saveData
local function MergeGroups(groups)
    local data = {}
    for _, group in pairs(groups) do
        if type(group) == "table" then
            for k, v in pairs(group) do
                data[k] = v
            end
        end
    end
    return data
end

--- 将 JSON 字符串拆为 <=CHUNK_MAX_BYTES 的分片列表
--- @param jsonStr string 待拆分的 JSON 字符串
--- @return string[] chunks 分片列表
local function ChunkString(jsonStr)
    local len = #jsonStr
    if len <= CHUNK_MAX_BYTES then
        return { jsonStr }
    end
    local chunks = {}
    local pos = 1
    while pos <= len do
        local endPos = math.min(pos + CHUNK_MAX_BYTES - 1, len)
        chunks[#chunks + 1] = string.sub(jsonStr, pos, endPos)
        pos = endPos + 1
    end
    return chunks
end

--- 构建分片 key 前缀: s_{slotId}_
local function SlotPrefix(slotId)
    return "s_" .. slotId .. "_"
end

--- 编码分片存储：将功能组 encode+分片，返回 {keyName=value} 和 head 结构
--- @param slotId number 槽位号
--- @param groups table {groupName=subTable}
--- @return table kvPairs {key=value} 所有需要写入的 kv 对
--- @return table headData head 结构 (不含自身)
local function EncodeChunkedGroups(slotId, groups)
    local prefix = SlotPrefix(slotId)
    local kvPairs = {}
    local keysInfo = {}  -- head.keys

    local GROUP_NAMES = { "core", "currency", "equip", "inv", "skills", "misc" }

    for _, gName in ipairs(GROUP_NAMES) do
        local gData = groups[gName]
        if gData then
            local jsonStr = cjson.encode(gData)
            local chunks = ChunkString(jsonStr)
            local numChunks = #chunks

            if numChunks == 1 then
                -- 单 key: s_N_groupName
                local key = prefix .. gName
                kvPairs[key] = jsonStr  -- 存原始 JSON 字符串
                keysInfo[gName] = {
                    cs = CalcChecksum(jsonStr),
                    len = #jsonStr,
                }
            else
                -- 多分片: s_N_groupName_0, s_N_groupName_1, ...
                local checksums = {}
                local lengths = {}
                for ci = 1, numChunks do
                    local key = prefix .. gName .. "_" .. (ci - 1)
                    kvPairs[key] = chunks[ci]
                    checksums[ci] = CalcChecksum(chunks[ci])
                    lengths[ci] = #chunks[ci]
                end
                keysInfo[gName] = {
                    chunks = numChunks,
                    cs = checksums,
                    len = lengths,
                }
            end
        end
    end

    local headData = {
        format    = SAVE_FORMAT,
        version   = CURRENT_SAVE_VERSION,
        timestamp = os.time(),
        slotId    = slotId,
        keys      = keysInfo,
    }

    return kvPairs, headData
end

--- 解码分片存储：从 values 中读取并合并功能组
--- @param headData table head 结构
--- @param values table BatchGet 返回的 values
--- @param slotId number 槽位号
--- @return table|nil mergedData 合并后的完整 saveData
--- @return string|nil error 错误信息
local function DecodeChunkedGroups(headData, values, slotId)
    local prefix = SlotPrefix(slotId)
    local groups = {}
    local GROUP_NAMES = { "core", "currency", "equip", "inv", "skills", "misc" }

    for _, gName in ipairs(GROUP_NAMES) do
        local info = headData.keys and headData.keys[gName]
        if not info then
            print("[SlotSave] Group '" .. gName .. "' not in head, skipping")
            goto continue
        end

        local jsonStr
        if info.chunks and info.chunks > 0 then
            -- 多分片：拼接
            local parts = {}
            for ci = 0, info.chunks - 1 do
                local key = prefix .. gName .. "_" .. ci
                local chunk = values[key]
                if type(chunk) ~= "string" then
                    return nil, "分片丢失: " .. key
                end
                -- 校验分片
                local expectedCs = info.cs[ci + 1]
                if expectedCs and CalcChecksum(chunk) ~= expectedCs then
                    return nil, "分片校验失败: " .. key
                end
                parts[ci + 1] = chunk
            end
            jsonStr = table.concat(parts)
        else
            -- 单 key
            local key = prefix .. gName
            local raw = values[key]
            if raw == nil then
                print("[SlotSave] Group '" .. gName .. "' key missing, skipping")
                goto continue
            end
            -- raw 可能是 string (原始JSON) 或 table (云端自动解码)
            if type(raw) == "table" then
                groups[gName] = raw
                goto continue
            end
            jsonStr = raw
            -- 校验
            if info.cs and type(info.cs) == "number" then
                if CalcChecksum(jsonStr) ~= info.cs then
                    return nil, "校验失败: " .. key
                end
            end
        end

        -- 解码 JSON
        local ok, decoded = pcall(cjson.decode, jsonStr)
        if not ok or type(decoded) ~= "table" then
            return nil, "JSON解码失败: " .. gName
        end
        groups[gName] = decoded

        ::continue::
    end

    return MergeGroups(groups), nil
end

--- 收集分片格式使用的所有 key 名列表 (用于 BatchGet/Delete)
--- @param headData table head 结构
--- @param slotId number 槽位号
--- @return string[] keys
local function CollectChunkedKeys(headData, slotId)
    local prefix = SlotPrefix(slotId)
    local keys = {}
    local GROUP_NAMES = { "core", "currency", "equip", "inv", "skills", "misc" }

    for _, gName in ipairs(GROUP_NAMES) do
        local info = headData.keys and headData.keys[gName]
        if info then
            if info.chunks and info.chunks > 0 then
                for ci = 0, info.chunks - 1 do
                    keys[#keys + 1] = prefix .. gName .. "_" .. ci
                end
            else
                keys[#keys + 1] = prefix .. gName
            end
        end
    end
    return keys
end

-- ============================================================================
-- 结构校验 (严格模式)
-- ============================================================================

--- 严格校验存档结构完整性
--- @param data table 存档数据
--- @return boolean 是否合法
function SlotSaveSystem.ValidateStructure(data)
    if type(data) ~= "table" then return false end
    if type(data.version) ~= "number" then return false end
    if type(data.timestamp) ~= "number" then return false end
    if type(data.player) ~= "table" then return false end
    if type(data.player.level) ~= "number" then return false end
    return true
end

-- ============================================================================
-- 存档版本迁移 (与 SaveSystem.lua 完全一致, 保兼容)
-- ============================================================================

local MIGRATIONS = {
    -- v1 → v2: elemDmg 词条值缩减为 1/5
    [1] = function(data)
        if not data.migrated_elemDmg_nerf then
            local function nerfElemDmg(item)
                if not item then return end
                if item.mainStat and item.mainStat.key == "elemDmg" then
                    item.mainStat.value = item.mainStat.value / 5
                end
                if item.subStats then
                    for _, sub in ipairs(item.subStats) do
                        if sub.key == "elemDmg" then sub.value = sub.value / 5 end
                    end
                end
            end
            if data.equipment then
                for _, item in pairs(data.equipment) do nerfElemDmg(item) end
            end
            if data.inventory then
                for _, item in ipairs(data.inventory) do nerfElemDmg(item) end
            end
            data.migrated_elemDmg_nerf = true
        end
        data.version = 2
        return data
    end,

    -- v2 → v3: 技能ID调和 + 装备字段规范化 + 材料规范化
    [2] = function(data)
        if data.skills and type(data.skills) == "table" then
            local SkillTreeConfig = require("SkillTreeConfig")
            local refundedPts = 0
            local orphaned = {}
            local SKILL_RENAMES = {}
            for id, level in pairs(data.skills) do
                if type(level) == "number" and level > 0 then
                    if SKILL_RENAMES[id] then
                        local newId = SKILL_RENAMES[id]
                        data.skills[newId] = math.max(data.skills[newId] or 0, level)
                        table.insert(orphaned, id)
                    elseif not SkillTreeConfig.SKILL_MAP[id] then
                        refundedPts = refundedPts + level
                        table.insert(orphaned, id)
                    else
                        local cfg = SkillTreeConfig.SKILL_MAP[id]
                        if level > cfg.maxLevel then
                            refundedPts = refundedPts + (level - cfg.maxLevel)
                            data.skills[id] = cfg.maxLevel
                        end
                    end
                end
            end
            for _, id in ipairs(orphaned) do data.skills[id] = nil end
            if refundedPts > 0 then data._refundedSkillPts = refundedPts end
        end
        local function normalizeItem(item)
            if not item or type(item) ~= "table" then return end
            if not item.tier then item.tier = 1; item.tierMul = 1.0 end
            if not item.tierMul then item.tierMul = 2 ^ (item.tier - 1) end
            if item.slot == "weapon" and not item.element then item.element = "physical" end
            if not item.subStats then item.subStats = {} end
            if not item.qualityIdx or item.qualityIdx < 1 or item.qualityIdx > 5 then item.qualityIdx = 1 end
        end
        if data.equipment then
            for _, item in pairs(data.equipment) do normalizeItem(item) end
        end
        if data.inventory then
            for _, item in ipairs(data.inventory) do normalizeItem(item) end
        end
        data.materials = data.materials or {}
        data.materials.stone = data.materials.stone or 0
        data.materials.soulCrystal = data.materials.soulCrystal or 0
        data.version = 3
        return data
    end,

    -- v3 → v4: 缩放公式从指数改为对数, 装备非百分比词条按比例缩放
    [3] = function(data)
        local function migrateItem(item)
            if not item or type(item) ~= "table" then return end
            local ch = item.tier or 1
            local oldTier = item.tierMul or (2 ^ ((item.tier or 1) - 1))
            local newTier = Config.GetChapterTier(ch)
            if oldTier <= 1.0 then item.tierMul = newTier; return end
            local ratio = newTier / oldTier
            local mainDef = Config.EQUIP_STATS[item.mainStat]
            if not (mainDef and mainDef.isPercent) then
                item.mainValue = item.mainValue * ratio
                if item.baseMainValue then item.baseMainValue = item.baseMainValue * ratio end
            end
            if item.subStats then
                for _, sub in ipairs(item.subStats) do
                    local subDef = Config.EQUIP_STATS[sub.key]
                    if not (subDef and subDef.isPercent) then
                        sub.value = sub.value * ratio
                        if sub.baseValue then sub.baseValue = sub.baseValue * ratio end
                    end
                end
            end
            item.tierMul = newTier
        end
        if data.equipment then
            for _, item in pairs(data.equipment) do migrateItem(item) end
        end
        if data.inventory then
            for _, item in ipairs(data.inventory) do migrateItem(item) end
        end
        data.version = 4
        return data
    end,

    -- v4 → v5: 经济重平衡
    [4] = function(data)
        data.version = 5
        return data
    end,

    -- v5 → v6: 删除已移除套装的装备（22个单章套装已从配置中删除），分解为强化石补偿
    [5] = function(data)
        local function isDeletedSet(item)
            if not item or type(item) ~= "table" then return false end
            if not item.setId then return false end
            -- setId 存在但不在当前配置中 → 该套装已被删除
            return Config.EQUIP_SET_MAP[item.setId] == nil
        end

        local removedCount = 0
        local stonesGained = 0
        data.materials = data.materials or {}
        data.materials.stone = data.materials.stone or 0

        -- 已装备: 移除已删除套装的装备
        if data.equipment then
            local toRemove = {}
            for slotId, item in pairs(data.equipment) do
                if isDeletedSet(item) then
                    local stones = Config.DECOMPOSE_STONES[item.qualityIdx] or 0
                    if item.upgradeStonesSpent then
                        stones = stones + math.floor(item.upgradeStonesSpent * 0.8)
                    end
                    stonesGained = stonesGained + stones
                    removedCount = removedCount + 1
                    table.insert(toRemove, slotId)
                end
            end
            for _, slotId in ipairs(toRemove) do
                data.equipment[slotId] = nil
            end
        end

        -- 背包: 移除已删除套装的装备
        if data.inventory then
            local newInv = {}
            for _, item in ipairs(data.inventory) do
                if isDeletedSet(item) then
                    local stones = Config.DECOMPOSE_STONES[item.qualityIdx] or 0
                    if item.upgradeStonesSpent then
                        stones = stones + math.floor(item.upgradeStonesSpent * 0.8)
                    end
                    stonesGained = stonesGained + stones
                    removedCount = removedCount + 1
                else
                    table.insert(newInv, item)
                end
            end
            data.inventory = newInv
        end

        data.materials.stone = data.materials.stone + stonesGained
        if removedCount > 0 then
            print(string.format("[Migration v5→v6] Removed %d deleted-set items, +%d stones", removedCount, stonesGained))
        end
        data.version = 6
        return data
    end,

    -- v6 → v7: P1 属性系统重构 (10独立加点 → 4核心属性 STR/DEX/INT/WIL)
    -- 策略: 全额退点 — 累加旧 10 属性已分配点数 → freePoints, 重置为 4 新 key
    [6] = function(data)
        local sp = data.savePlayer
        if sp and sp.allocatedPoints then
            local oldPoints = sp.allocatedPoints
            local totalRefund = 0
            -- 累加所有旧属性点数
            for key, val in pairs(oldPoints) do
                if type(val) == "number" and val > 0 then
                    totalRefund = totalRefund + val
                end
            end
            -- 重置为新 4 属性
            sp.allocatedPoints = { STR = 0, DEX = 0, INT = 0, WIL = 0 }
            -- 退还所有点数
            sp.freePoints = (sp.freePoints or 0) + totalRefund
            if totalRefund > 0 then
                print(string.format("[Migration v6→v7] Refunded %d attribute points to freePoints", totalRefund))
            end
        end
        data.version = 7
        return data
    end,

    -- v7 → v8: P2 装备词缀统一 (mainStat/subStats/proc affixes → unified affixes[] + itemPower)
    [7] = function(data)
        -- tier → chapter 反查: tier = 1 + 99 × ln(ch)/ln(100) → ch = 100^((tier-1)/99)
        local function tierToChapter(tier)
            if not tier or tier <= 1 then return 1 end
            return math.max(1, math.floor(100 ^ ((tier - 1) / 99) + 0.5))
        end

        local function migrateItem(item)
            if not item or type(item) ~= "table" then return end
            -- 已迁移过的跳过 (必须同时有 itemPower 和非空 affixes 才认为已迁移)
            if item.itemPower and item.affixes and #item.affixes > 0 then return end

            local newAffixes = {}

            -- 1. mainStat → 第一条词缀 (保留原始数值)
            if item.mainStat then
                table.insert(newAffixes, {
                    id = item.mainStat,
                    value = item.mainValue or 0,
                    greater = false,
                })
            end

            -- 2. subStats → 后续词缀
            if item.subStats then
                for _, sub in ipairs(item.subStats) do
                    table.insert(newAffixes, {
                        id = sub.key,
                        value = sub.value or 0,
                        greater = false,
                    })
                end
            end

            -- 3. 旧 proc 词缀 → 合并 (baseValue 来自旧 AFFIX_MAP)
            if item.affixes then
                for _, aff in ipairs(item.affixes) do
                    local def = Config.AFFIX_MAP[aff.id]
                    local base = def and def.baseValue or 0.2
                    local isGreater = aff.enhanced or false
                    table.insert(newAffixes, {
                        id = aff.id,
                        value = isGreater and (base * 1.5) or base,
                        greater = isGreater,
                    })
                end
            end

            -- 4. 计算 IP (从旧 tier 推导 chapter，再算 baseIP)
            local chapter = tierToChapter(item.tier or 1)
            local baseIP = Config.CalcBaseIP(chapter)
            local qi = item.qualityIdx or 1
            local ipQMul = Config.IP_QUALITY_MUL[qi] or 0.5
            -- v4.0: IP_PER_UPGRADE 已移除; 旧迁移路径仍需旧值 5
            local OLD_IP_PER_UPGRADE = 5
            item.itemPower = math.floor(baseIP * ipQMul + (item.upgradeLv or 0) * OLD_IP_PER_UPGRADE)

            -- 5. 写入新结构, 删除旧字段
            item.affixes = newAffixes
            item.mainStat = nil
            item.mainValue = nil
            item.baseMainValue = nil
            item.subStats = nil
            item.tier = nil
            item.tierMul = nil
        end

        if data.equipment then
            for _, item in pairs(data.equipment) do migrateItem(item) end
        end
        if data.inventory then
            for _, item in ipairs(data.inventory) do migrateItem(item) end
        end

        data.version = 8
        return data
    end,

    -- v8 → v9: 法师技能系统重写 — 旧技能 ID 全部退还技能点
    [8] = function(data)
        if data.skills and type(data.skills) == "table" then
            local SkillTreeConfig = require("SkillTreeConfig")
            local refundedPts = 0
            local orphaned = {}
            for id, level in pairs(data.skills) do
                if type(level) == "number" and level > 0 then
                    if not SkillTreeConfig.SKILL_MAP[id] then
                        refundedPts = refundedPts + level
                        table.insert(orphaned, id)
                    else
                        local cfg = SkillTreeConfig.SKILL_MAP[id]
                        if level > cfg.maxLevel then
                            refundedPts = refundedPts + (level - cfg.maxLevel)
                            data.skills[id] = cfg.maxLevel
                        end
                    end
                end
            end
            for _, id in ipairs(orphaned) do data.skills[id] = nil end
            if refundedPts > 0 then data._refundedSkillPts = refundedPts end
        end
        data.version = 9
        return data
    end,

    -- v9 → v10: 六桶词缀系统 — 清理已废弃的旧元素词缀(poison/water/arcane)
    [9] = function(data)
        local VALID = Config.AFFIX_POOL_MAP
        local STATS = Config.EQUIP_STATS

        local function cleanAffixes(item)
            if not item or not item.affixes then return end
            local cleaned = {}
            for _, aff in ipairs(item.affixes) do
                if VALID[aff.id] or STATS[aff.id] then
                    table.insert(cleaned, aff)
                end
            end
            if #cleaned ~= #item.affixes then
                item.affixes = cleaned
            end
        end

        if data.equipment and type(data.equipment) == "table" then
            for _, item in pairs(data.equipment) do
                cleanAffixes(item)
            end
        end
        if data.inventory and type(data.inventory) == "table" then
            for _, item in ipairs(data.inventory) do
                cleanAffixes(item)
            end
        end

        data.version = 10
        return data
    end,

    -- v10 → v11: 升级系统重设计 — IP 不再含升级加成, 词缀改用里程碑机制
    -- 旧公式: ip += upgradeLv * 5, affValue *= (1 + upgradeLv * 0.03)
    -- v10→v11: IP 纯净化, 词缀反推 baseValue, 里程碑计数归零
    [10] = function(data)
        local OLD_IP_PER_UPGRADE = 5
        local OLD_AFFIX_GROWTH   = 0.03  -- 旧版每级词缀增长率

        local function migrateItem(item)
            if not item or type(item) ~= "table" then return end
            local upgLv = item.upgradeLv or 0
            if upgLv <= 0 then return end

            -- 1. 回滚 IP: 去除旧的升级 IP 加成
            if item.itemPower then
                item.itemPower = item.itemPower - upgLv * OLD_IP_PER_UPGRADE
                if item.itemPower < 1 then item.itemPower = 1 end
            end

            -- 2. 词缀: 反推 baseValue, 里程碑计数归零
            -- (旧存档无法还原随机选择历史, 迁移后词缀回到基础值)
            if item.affixes then
                for _, aff in ipairs(item.affixes) do
                    if aff.value and aff.value > 0 then
                        local oldMul = 1 + upgLv * OLD_AFFIX_GROWTH
                        local baseVal = aff.value / oldMul
                        aff.baseValue = baseVal
                        aff.value = baseVal  -- 里程碑归零, value = baseValue
                        aff.milestoneCount = 0
                    end
                end
            end

            -- 3. 重算主属性 (用新公式, 含升级加成)
            if item.mainStatId and item.mainStatBase then
                item.mainStatValue = Config.CalcMainStatValueFull(
                    item.mainStatBase, item.itemPower, upgLv)
            end
        end

        if data.equipment and type(data.equipment) == "table" then
            for _, item in pairs(data.equipment) do migrateItem(item) end
        end
        if data.inventory and type(data.inventory) == "table" then
            for _, item in ipairs(data.inventory) do migrateItem(item) end
        end

        local count = 0
        local function countUpgraded(item)
            if item and type(item) == "table" and (item.upgradeLv or 0) > 0 then
                count = count + 1
            end
        end
        if data.equipment then for _, item in pairs(data.equipment) do countUpgraded(item) end end
        if data.inventory then for _, item in ipairs(data.inventory) do countUpgraded(item) end end
        if count > 0 then
            print(string.format("[Migration v10→v11] Migrated %d upgraded items: IP rollback, affix milestone", count))
        end

        data.version = 11
        return data
    end,

    -- v11 → v12: 套装秘境系统 — 套装不再从普通掉落获得, 改为秘境副本产出
    -- 已穿戴/背包中的套装装备保留不动 (不剥夺), 仅初始化秘境状态字段
    [11] = function(data)
        -- 初始化套装秘境存档字段
        if not data.setDungeon then
            data.setDungeon = {
                attemptsToday = 0,
                lastDate      = "",
                totalRuns     = 0,
            }
        end

        data.version = 12
        return data
    end,

    -- v12 → v13: D4 多材料系统 — stone → iron, upgradeStonesSpent → upgradeMatSpent
    [12] = function(data)
        -- 1. 材料迁移: stone → iron (1:1)
        data.materials = data.materials or {}
        local oldStone = data.materials.stone or 0
        if oldStone > 0 and not data.materials.iron then
            data.materials.iron = oldStone
        end
        -- 初始化新材料字段
        data.materials.iron       = data.materials.iron or 0
        data.materials.crystal    = data.materials.crystal or 0
        data.materials.wraith     = data.materials.wraith or 0
        data.materials.eternal    = data.materials.eternal or 0
        data.materials.abyssHeart = data.materials.abyssHeart or 0
        data.materials.riftEcho   = data.materials.riftEcho or 0

        -- 2. 装备迁移: upgradeStonesSpent → upgradeMatSpent.iron
        local migratedCount = 0
        local function migrateItem(item)
            if not item or type(item) ~= "table" then return end
            local spent = item.upgradeStonesSpent
            if spent and spent > 0 and not item.upgradeMatSpent then
                item.upgradeMatSpent = { iron = spent }
                migratedCount = migratedCount + 1
            end
        end

        if data.equipment and type(data.equipment) == "table" then
            for _, item in pairs(data.equipment) do migrateItem(item) end
        end
        if data.inventory and type(data.inventory) == "table" then
            for _, item in ipairs(data.inventory) do migrateItem(item) end
        end

        if oldStone > 0 or migratedCount > 0 then
            print(string.format("[Migration v12→v13] Materials: stone=%d→iron, %d items migrated upgradeMatSpent",
                oldStone, migratedCount))
        end

        data.version = 13
        return data
    end,

    -- v13 → v14: D4 式 4 级固定升级 — 旧升级等级 clamp 到 4, 退还多余材料/金币
    -- 旧公式: 50级渐进式 → 新: 每品质最多4级查表
    -- 词缀: 旧里程碑随机 → 新: 全词缀统一 +5%/级
    [13] = function(data)
        local NEW_MAX = 4  -- 所有品质统一最多4级

        local function migrateItem(item)
            if not item or type(item) ~= "table" then return end
            local oldLv = item.upgradeLv or 0
            if oldLv <= 0 then return end

            -- 1. clamp 升级等级
            local newLv = math.min(oldLv, NEW_MAX)
            item.upgradeLv = newLv

            -- 2. 退还多余的材料投入 (超出部分全额退还)
            if oldLv > NEW_MAX and item.upgradeMatSpent then
                -- 计算新4级应消耗的材料总量
                local qi = item.qualityIdx or 2
                local newTotalMats = {}
                local costTable = Config.UPGRADE_COSTS[qi]
                if costTable then
                    for lv = 1, NEW_MAX do
                        local entry = costTable[lv]
                        if entry and entry.mats then
                            for matId, amt in pairs(entry.mats) do
                                newTotalMats[matId] = (newTotalMats[matId] or 0) + amt
                            end
                        end
                    end
                end
                -- 退还: spent - newTotal (差值归入材料池)
                data.materials = data.materials or {}
                for matId, spent in pairs(item.upgradeMatSpent) do
                    local kept = newTotalMats[matId] or 0
                    local refund = spent - kept
                    if refund > 0 then
                        data.materials[matId] = (data.materials[matId] or 0) + refund
                    end
                end
                -- 更新 spent 记录为新的总量
                item.upgradeMatSpent = newTotalMats
            end

            -- 3. 词缀: 清除旧 milestoneCount, 用新公式重算 value
            -- 新公式: value = baseValue * (1 + newLv * 0.05)
            if item.affixes then
                local affixMul = 1.0 + newLv * (Config.UPGRADE_AFFIX_GROWTH or 0.05)
                for _, aff in ipairs(item.affixes) do
                    if aff.baseValue and aff.baseValue > 0 then
                        aff.value = aff.baseValue * affixMul
                    end
                    aff.milestoneCount = nil  -- 移除旧里程碑字段
                end
            end

            -- 4. 重算主属性 (用新乘法公式)
            if item.mainStatId and item.mainStatBase then
                item.mainStatValue = Config.CalcMainStatValueFull(
                    item.mainStatBase, item.itemPower or 100, newLv)
            end

            -- 5. 初始化新字段
            item.upgradeGoldSpent = nil  -- 旧存档无金币消耗记录
            item.endgameEnhanced = nil
        end

        local count = 0
        local function countAndMigrate(item)
            if item and type(item) == "table" and (item.upgradeLv or 0) > 0 then
                count = count + 1
                migrateItem(item)
            end
        end

        if data.equipment and type(data.equipment) == "table" then
            for _, item in pairs(data.equipment) do countAndMigrate(item) end
        end
        if data.inventory and type(data.inventory) == "table" then
            for _, item in ipairs(data.inventory) do countAndMigrate(item) end
        end

        if count > 0 then
            print(string.format("[Migration v13→v14] Migrated %d upgraded items: clamp to %d levels, affix unified +5%%/lv",
                count, NEW_MAX))
        end

        data.version = 14
        return data
    end,
}

local function MigrateData(data)
    local v = data.version or 1
    if MIGRATIONS[v] then
        pcall(function()
            SafeWriteFile("pre_migrate_v" .. v .. "_backup.json", cjson.encode(data))
        end)
    end
    while MIGRATIONS[v] do
        data = MIGRATIONS[v](data)
        v = data.version
    end
    return data
end

-- ============================================================================
-- 序列化
-- ============================================================================

function SlotSaveSystem.Serialize()
    local p = GameState.player

    local equipment = {}
    for slotId, item in pairs(GameState.equipment) do
        if item then equipment[slotId] = item end
    end

    local skills = {}
    for id, skill in pairs(GameState.skills) do
        if skill.level > 0 then skills[id] = skill.level end
    end

    local potionBuffs = {}
    for typeId, queue in pairs(GameState.potionBuffs) do
        if type(queue) == "table" and not queue.timer then
            local filtered = {}
            for _, entry in ipairs(queue) do
                if entry.timer > 0 then
                    table.insert(filtered, { timer = entry.timer, value = entry.value })
                end
            end
            if #filtered > 0 then potionBuffs[typeId] = filtered end
        elseif type(queue) == "table" and queue.timer and queue.timer > 0 then
            potionBuffs[typeId] = { { timer = queue.timer, value = queue.value or 0 } }
        end
    end

    SlotSaveSystem._saveCount = (SlotSaveSystem._saveCount or 0) + 1

    local saveData = {
        version = CURRENT_SAVE_VERSION,
        timestamp = os.time(),
        _meta = {
            saveCount  = SlotSaveSystem._saveCount,
            slotId     = currentSlot_,
            playTime   = playTime_,
            createdAt  = createdAt_,
            migratedFrom = migratedFrom_,
        },
        player = {
            level       = p.level,
            exp         = p.exp,
            expVersion  = Config.EXP_VERSION,
            gold        = p.gold,
            freePoints  = p.freePoints,
            allocatedPoints = (function()
                local t = {}
                local StatDefs = require("state.StatDefs")
                for _, def in ipairs(StatDefs.POINT_STATS) do
                    t[def.key] = p.allocatedPoints[def.key] or 0
                end
                return t
            end)(),
        },
        equipment   = equipment,
        inventory   = GameState.inventory,
        materials   = {
            iron = GameState.materials.iron or 0,
            crystal = GameState.materials.crystal or 0,
            wraith = GameState.materials.wraith or 0,
            eternal = GameState.materials.eternal or 0,
            abyssHeart = GameState.materials.abyssHeart or 0,
            riftEcho = GameState.materials.riftEcho or 0,
            soulCrystal = GameState.materials.soulCrystal or 0,
            forestDew = GameState.materials.forestDew or 0,
            stone = GameState.materials.iron or 0,  -- 旧版兼容: stone = iron
        },
        expandCount = GameState.expandCount or 0,
        gemBagExpandCount = GameState.gemBagExpandCount or 0,
        skills      = skills,
        skillLoadout = (function()
            if not GameState.skillLoadout then return nil end
            local lo = GameState.skillLoadout
            local active = {}
            for i = 1, 4 do
                active[i] = lo.active[i] or false  -- false 占位保持索引
            end
            return { basic = lo.basic or false, active = active }
        end)(),
        stage       = { chapter = GameState.stage.chapter, stage = GameState.stage.stage },
        potionBuffs = potionBuffs,
        records     = {
            maxPower   = GameState.records.maxPower,
            maxChapter = GameState.records.maxChapter,
            maxStage   = GameState.records.maxStage,
        },
        autoDecompConfig = GameState.autoDecompConfig,
        bag = GameState.bag or {},
        gemBag = GameState.gemBag or {},
        redeemedCodes = GameState.redeemedCodes or {},
        claimedVersionRewards = GameState.claimedVersionRewards or {},
        -- 域注册字段 (endlessTrial/worldBoss/resourceDungeon/forge/dailyRewards/titles)
        -- 由 RegisterDomain 的 serialize 回调在下方循环中填充
        migrated_elemDmg_nerf = true,
    }

    -- 域注册的序列化: 各模块提供自己的字段
    for _, domain in ipairs(domains_) do
        local kv = domain.serialize(GameState)
        if kv then
            for k, v in pairs(kv) do
                saveData[k] = v
            end
        end
    end

    return saveData
end

-- ============================================================================
-- 反序列化
-- ============================================================================

function SlotSaveSystem.Deserialize(data)
    if not data or type(data) ~= "table" then return false end
    if not SlotSaveSystem.ValidateStructure(data) then return false end

    data = MigrateData(data)

    -- _meta (新系统字段, 旧存档用默认值)
    local meta = data._meta or {}
    SlotSaveSystem._saveCount = meta.saveCount or 0
    playTime_     = meta.playTime or 0
    createdAt_    = meta.createdAt or data.timestamp or os.time()
    migratedFrom_ = meta.migratedFrom

    local p = GameState.player

    -- 玩家基础
    if data.player then
        local sp = data.player
        p.level      = sp.level      or 1
        p.exp        = sp.exp        or 0
        p.gold       = sp.gold       or 0
        p.freePoints = sp.freePoints or 0
        if sp.allocatedPoints then
            for stat, val in pairs(sp.allocatedPoints) do
                if p.allocatedPoints[stat] ~= nil then
                    p.allocatedPoints[stat] = val
                end
            end
        end

        -- 经验迁移: 保留等级，按比例对齐经验
        local savedExpVer = sp.expVersion or 1
        if savedExpVer < Config.EXP_VERSION then
            -- 根据旧版本号选择对应的旧经验公式
            local oldNeeded
            if savedExpVer == 1 then
                oldNeeded = Config.OldLevelExp(p.level)
            elseif savedExpVer == 2 then
                oldNeeded = Config.V2LevelExp(p.level)
            else
                oldNeeded = Config.LevelExp(p.level)
            end
            local progress = (oldNeeded > 0) and (p.exp / oldNeeded) or 0
            progress = math.max(0, math.min(progress, 0.999))
            local newNeeded = Config.LevelExp(p.level)
            p.exp = math.floor(progress * newNeeded)
            print(string.format("[ExpMigration] v%d→v%d: Lv.%d, progress=%.2f%%, old=%.0f→new=%.0f",
                savedExpVer, Config.EXP_VERSION, p.level, progress * 100, oldNeeded, newNeeded))
        end
    end

    -- 装备
    if data.equipment and type(data.equipment) == "table" then
        for slotId, item in pairs(data.equipment) do
            if type(item) == "table" then GameState.equipment[slotId] = item end
        end
    end

    -- 背包
    if data.inventory and type(data.inventory) == "table" then
        GameState.inventory = data.inventory
    end

    -- 材料 (v13 多材料兼容)
    if data.materials then
        -- 新材料字段
        GameState.materials.iron       = data.materials.iron or 0
        GameState.materials.crystal    = data.materials.crystal or 0
        GameState.materials.wraith     = data.materials.wraith or 0
        GameState.materials.eternal    = data.materials.eternal or 0
        GameState.materials.abyssHeart = data.materials.abyssHeart or 0
        GameState.materials.riftEcho   = data.materials.riftEcho or 0
        GameState.materials.soulCrystal = data.materials.soulCrystal or 0
        GameState.materials.forestDew  = data.materials.forestDew or 0

        -- 旧存档迁移: 如果有 stone 但无 iron，将 stone 全部转为 iron
        if (data.materials.stone or 0) > 0 and (data.materials.iron or 0) == 0 then
            GameState.materials.iron = data.materials.stone
        end
    end

    GameState.expandCount = data.expandCount or 0
    GameState.gemBagExpandCount = data.gemBagExpandCount or 0

    if data.bag and type(data.bag) == "table" then
        GameState.bag = data.bag
    end

    if data.gemBag and type(data.gemBag) == "table" then
        GameState.gemBag = data.gemBag
    end

    -- 技能（包含强化分支节点，恢复时可能尚未初始化，需动态创建）
    if data.skills and type(data.skills) == "table" then
        for id, level in pairs(data.skills) do
            if not GameState.skills[id] then
                GameState.skills[id] = { id = id, level = 0 }
            end
            GameState.skills[id].level = level
        end
    end

    -- 技能装备槽位
    if data.skillLoadout and type(data.skillLoadout) == "table" then
        GameState.InitSkillLoadout()
        local lo = data.skillLoadout
        if lo.basic and lo.basic ~= false then
            GameState.skillLoadout.basic = lo.basic
        end
        if lo.active and type(lo.active) == "table" then
            for i = 1, 4 do
                local sid = lo.active[i]
                if sid and sid ~= false then
                    GameState.skillLoadout.active[i] = sid
                end
            end
        end
    end

    -- 关卡进度
    if data.stage then
        GameState.stage.chapter = data.stage.chapter or 1
        GameState.stage.stage   = data.stage.stage   or 1
    end
    -- 药水buff
    if data.potionBuffs and type(data.potionBuffs) == "table" then
        for typeId, saved in pairs(data.potionBuffs) do
            if type(saved) == "table" then
                if saved.timer then
                    if saved.timer > 0 then
                        GameState.potionBuffs[typeId] = { { timer = saved.timer, value = saved.value or 0 } }
                    end
                elseif #saved > 0 then
                    local queue = {}
                    for _, entry in ipairs(saved) do
                        if type(entry) == "table" and (entry.timer or 0) > 0 then
                            table.insert(queue, { timer = entry.timer, value = entry.value or 0 })
                        end
                    end
                    if #queue > 0 then
                        table.sort(queue, function(a, b) return a.value > b.value end)
                        GameState.potionBuffs[typeId] = queue
                    end
                end
            end
        end
    end

    -- 个人记录
    if data.records then
        GameState.records.maxPower   = data.records.maxPower   or 0
        GameState.records.maxChapter = data.records.maxChapter or 1
        GameState.records.maxStage   = data.records.maxStage   or 1
    end

    -- 自动分解配置
    if data.autoDecompConfig then
        for i = 1, 5 do
            GameState.autoDecompConfig[i] = data.autoDecompConfig[i] or 0
        end
    elseif data.autoDecomposeLevel and data.autoDecomposeLevel > 0 then
        local keepSets = (data.autoDecompKeepSets ~= false)
        for i = 1, data.autoDecomposeLevel do
            GameState.autoDecompConfig[i] = keepSets and 2 or 1
        end
    end
    GameState.redeemedCodes = data.redeemedCodes or {}
    GameState.claimedVersionRewards = data.claimedVersionRewards or {}
    -- 域注册的反序列化: 各模块自行从 data 读取并写入 GameState
    for _, domain in ipairs(domains_) do
        domain.deserialize(GameState, data)
    end

    GameState.ResetHP()

    -- 离线时间计算
    local savedTime = data.timestamp or 0
    if savedTime > 0 then
        local elapsed = os.time() - savedTime
        if elapsed >= MIN_OFFLINE_SEC then
            SlotSaveSystem.offlineSeconds = math.min(elapsed, MAX_OFFLINE_SEC)
        else
            SlotSaveSystem.offlineSeconds = 0
        end
    end

    -- 迁移退还技能点通知
    if data._refundedSkillPts and data._refundedSkillPts > 0 then
        GameState.migrationMsg = "技能树更新: 已退还 " .. data._refundedSkillPts .. " 技能点，请重新分配"
    end

    -- 测试账号
    SlotSaveSystem.ApplyTestAccountOverrides()

    -- 属性点/技能点校验
    GameState.ValidatePoints()

    return true
end

--- 测试账号覆盖
function SlotSaveSystem.ApplyTestAccountOverrides()
    pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        local myId = tostring(lobby:GetMyUserId())
        for _, tid in ipairs(Config.TEST_USER_IDS) do
            if tostring(tid) == myId then
                local p = GameState.player
                local StageConfig = require("StageConfig")
                local totalCh = StageConfig.GetChapterCount()
                local maxLv = totalCh * 10  -- 自然内容上限: 总章节 × 每章10关
                if p.level < maxLv then
                    local gained = (maxLv - p.level) * Config.POINTS_PER_LEVEL
                    p.level = maxLv
                    p.exp = 0
                    p.freePoints = p.freePoints + gained
                end
                local lastStageCount = StageConfig.GetStageCount(totalCh)
                GameState.records.maxChapter = totalCh
                GameState.records.maxStage   = lastStageCount
                -- 测试账号: 每次启动强制触发8小时离线奖励
                SlotSaveSystem.offlineSeconds = 28800
                break
            end
        end
    end)
end

-- ============================================================================
-- Meta 辅助
-- ============================================================================

--- 从当前 GameState 构建一个 meta 槽位概要
local function BuildMetaSlot()
    return {
        timestamp = os.time(),
        level     = GameState.player.level,
        chapter   = GameState.stage.chapter,
        stage     = GameState.stage.stage,
        maxFloor  = GameState.endlessTrial.maxFloor or 0,
        playTime  = playTime_,
        saveCount = SlotSaveSystem._saveCount,
    }
end

--- 检查 meta 显示字段是否发生变化 (用于优化: 没变则不写 save_meta)
local function IsMetaChanged(newSlot)
    if not lastMetaSnapshot_ then return true end
    return newSlot.level    ~= lastMetaSnapshot_.level
        or newSlot.chapter  ~= lastMetaSnapshot_.chapter
        or newSlot.stage    ~= lastMetaSnapshot_.stage
        or newSlot.maxFloor ~= lastMetaSnapshot_.maxFloor
end

--- 更新 lastMetaSnapshot_
local function UpdateMetaSnapshot(slotMeta)
    lastMetaSnapshot_ = {
        level    = slotMeta.level,
        chapter  = slotMeta.chapter,
        stage    = slotMeta.stage,
        maxFloor = slotMeta.maxFloor,
    }
end

-- ============================================================================
-- 本地存档 (运行时缓存, WASM 重启后丢失)
-- ============================================================================

function SlotSaveSystem.SaveLocal(saveData)
    if currentSlot_ < 0 then return end
    local ok, err = pcall(function()
        local data = saveData or SlotSaveSystem.Serialize()
        local saveFile   = "save_slot_" .. currentSlot_ .. ".json"
        local backupFile = "save_slot_" .. currentSlot_ .. "_backup.json"
        if fileSystem:FileExists(saveFile) then
            fileSystem:Copy(saveFile, backupFile)
        end
        local json = cjson.encode(data)
        if not SafeWriteFile(saveFile, json) then
            error("SafeWriteFile failed")
        end
        print("[SlotSave] Local OK (slot=" .. currentSlot_ .. " v=" .. (data._meta and data._meta.saveCount or 0) .. ")")
    end)
    if not ok then
        print("[SlotSave] Local FAILED: " .. tostring(err))
    end
end

-- ============================================================================
-- 云端存档 (异步, 含 meta + 旧 key 回写)
-- ============================================================================

--- 内部记录上次写入的 head，用于 Delete 清理旧分片 key
local lastSavedHead_ = nil  -- { [slotId] = headData }

local function DoCloudSave(saveData, isRetry)
    if currentSlot_ < 0 then return end

    local ok, _ = pcall(function()
        GameState.UpdateRecords()
        local stageVal = GameState.records.maxChapter * 100 + GameState.records.maxStage

        -- 构建当前槽位的 meta 概要
        local slotMeta = BuildMetaSlot()
        local metaChanged = IsMetaChanged(slotMeta)

        -- === 分片编码 ===
        local groups = SplitIntoGroups(saveData)
        local kvPairs, headData = EncodeChunkedGroups(currentSlot_, groups)
        local headKey = SlotPrefix(currentSlot_) .. "head"

        local batch = clientCloud:BatchSet()

        -- 写入 head
        batch:Set(headKey, headData)

        -- 写入所有分组 key
        for key, value in pairs(kvPairs) do
            batch:Set(key, value)
        end

        -- 清理旧分片残留 key (如果上次有更多 chunks，本次减少了)
        lastSavedHead_ = lastSavedHead_ or {}
        local oldHead = lastSavedHead_[currentSlot_]
        if oldHead and oldHead.keys then
            local oldKeys = CollectChunkedKeys(oldHead, currentSlot_)
            for _, oldKey in ipairs(oldKeys) do
                if not kvPairs[oldKey] then
                    batch:Delete(oldKey)
                end
            end
        end

        -- meta 优化: 仅在显示字段变化时才写入 save_meta
        if metaChanged then
            saveMeta_.slots[tostring(currentSlot_)] = slotMeta
            saveMeta_.activeSlot = currentSlot_
            batch:Set("save_meta", saveMeta_)
            UpdateMetaSnapshot(slotMeta)
        end

        -- 向后兼容: 回写旧 key (完整 saveData)
        batch:Set("save_data", saveData)

        -- 排行榜 iscores（按槽位分离 key）
        local slotSuffix = "_s" .. currentSlot_
        batch:SetInt("max_power_v2" .. slotSuffix, math.floor(GameState.records.maxPower / 1000))
            :SetInt("max_stage_v2" .. slotSuffix, stageVal)
            :SetInt("max_trial_floor_v3" .. slotSuffix, GameState.endlessTrial.maxFloor or 0)
            :SetInt("active_slot", currentSlot_)
            :Save("自动存档", {
                ok = function()
                    print("[SlotSave] Cloud OK (slot " .. currentSlot_ .. ", format=" .. SAVE_FORMAT .. ")")
                    lastSavedHead_[currentSlot_] = headData
                    retryCount_ = 0
                    retryTimer_ = 0
                    pendingSaveData_ = nil
                end,
                error = function(code, reason)
                    print("[SlotSave] Cloud error: " .. tostring(reason))
                    retryCount_ = retryCount_ + 1
                    if retryCount_ <= MAX_RETRY then
                        retryTimer_ = math.min(3 ^ retryCount_, 30)
                        pendingSaveData_ = saveData
                    else
                        retryCount_ = 0
                        retryTimer_ = 0
                        pendingSaveData_ = nil
                        local toast = getToast()
                        if toast then toast.Warn("云端保存失败，已保存到本地") end
                    end
                end,
            })
    end)

    if not ok then
        if not isRetry then
            local toast = getToast()
            if toast then toast.Warn("云端存档不可用，已保存到本地") end
        end
    end
end

-- ============================================================================
-- 保存入口
-- ============================================================================

function SlotSaveSystem.Save()
    if not saveConfirmed_ then return end

    retryCount_ = 0
    retryTimer_ = 0
    pendingSaveData_ = nil

    local saveData = SlotSaveSystem.Serialize()

    -- 1. 先写本地 (同步)
    SlotSaveSystem.SaveLocal(saveData)

    -- 2. 再异步上传云端
    DoCloudSave(saveData, false)
end

--- 立即保存 (关卡通关等关键事件)
function SlotSaveSystem.SaveNow()
    if not saveConfirmed_ then return end
    saveTimer_ = 0
    dirtyTimer_ = 0
    SlotSaveSystem.Save()
end

--- 标记脏数据, 延迟合并保存
function SlotSaveSystem.MarkDirty()
    if not saveConfirmed_ then return end
    dirtyTimer_ = DIRTY_DELAY
end

-- ============================================================================
-- 旧存档迁移 (save_data → slot_1, manual_save → slot_2)
-- ============================================================================

--- 从存档数据中提取 meta 概要
local function ExtractMetaSlot(saveData, source)
    return {
        timestamp = saveData.timestamp or os.time(),
        level     = saveData.player and saveData.player.level or 1,
        chapter   = saveData.stage and saveData.stage.chapter or 1,
        stage     = saveData.stage and saveData.stage.stage or 1,
        maxFloor  = saveData.endlessTrial and saveData.endlessTrial.maxFloor or 0,
        playTime  = 0,
        saveCount = (saveData._meta and saveData._meta.saveCount) or 0,
        migratedFrom = source,  -- "auto_save" | "manual_save" | nil
    }
end

--- 为迁移数据注入 _meta 字段
local function InjectMigrationMeta(saveData, slotId, source)
    saveData._meta = saveData._meta or {}
    saveData._meta.slotId = slotId
    saveData._meta.migratedFrom = source
    saveData._meta.createdAt = saveData.timestamp or os.time()
    saveData._meta.saveCount = saveData._meta.saveCount or 0
    saveData._meta.playTime = 0
end

local function RunMigration(callback, attempt)
    attempt = attempt or 1
    print("[SlotSave] Running migration (attempt " .. attempt .. ")...")

    clientCloud:BatchGet()
        :Key("save_data")
        :Key("manual_save")
        :Fetch({
            ok = function(values, iscores)
                local autoSave = values["save_data"]
                local manualRaw = values["manual_save"]

                -- 解析手动存档 (string 或 table)
                local manualSave = nil
                if manualRaw then
                    if type(manualRaw) == "string" then
                        local decOk, decoded = pcall(cjson.decode, manualRaw)
                        if decOk and type(decoded) == "table" then manualSave = decoded end
                    elseif type(manualRaw) == "table" then
                        manualSave = manualRaw
                    end
                end

                -- 校验
                local autoValid = autoSave and type(autoSave) == "table"
                    and SlotSaveSystem.ValidateStructure(autoSave)
                local manualValid = manualSave and type(manualSave) == "table"
                    and SlotSaveSystem.ValidateStructure(manualSave)

                if not autoValid and not manualValid then
                    -- 新玩家: 无旧存档
                    local meta = { version = 1, activeSlot = 0, slots = {} }
                    saveMeta_ = meta
                    print("[SlotSave] No old saves found, new player")
                    callback(meta, true)
                    return
                end

                -- 执行版本迁移
                if autoValid then autoSave = MigrateData(autoSave) end
                if manualValid then manualSave = MigrateData(manualSave) end

                -- 构建新 meta
                local meta = { version = 1, activeSlot = 1, slots = {} }
                local batch = clientCloud:BatchSet()

                if autoValid then
                    InjectMigrationMeta(autoSave, 1, "auto_save")
                    -- 分片格式写入 slot 1
                    local groups1 = SplitIntoGroups(autoSave)
                    local kv1, head1 = EncodeChunkedGroups(1, groups1)
                    batch:Set(SlotPrefix(1) .. "head", head1)
                    for k, v in pairs(kv1) do batch:Set(k, v) end
                    -- 兼容旧格式
                    batch:Set("save_slot_1", autoSave)
                    meta.slots["1"] = ExtractMetaSlot(autoSave, "auto_save")
                    lastSavedHead_ = lastSavedHead_ or {}
                    lastSavedHead_[1] = head1
                end

                if manualValid then
                    InjectMigrationMeta(manualSave, 2, "manual_save")
                    -- 分片格式写入 slot 2
                    local groups2 = SplitIntoGroups(manualSave)
                    local kv2, head2 = EncodeChunkedGroups(2, groups2)
                    batch:Set(SlotPrefix(2) .. "head", head2)
                    for k, v in pairs(kv2) do batch:Set(k, v) end
                    -- 兼容旧格式
                    batch:Set("save_slot_2", manualSave)
                    meta.slots["2"] = ExtractMetaSlot(manualSave, "manual_save")
                    lastSavedHead_ = lastSavedHead_ or {}
                    lastSavedHead_[2] = head2
                end

                -- activeSlot: 优先自动存档, 仅手动存档时激活 slot 2
                if not autoValid and manualValid then
                    meta.activeSlot = 2
                end

                batch:Set("save_meta", meta)
                    :Save("存档迁移", {
                        ok = function()
                            print("[SlotSave] Migration OK")
                            saveMeta_ = meta
                            callback(meta, false)
                        end,
                        error = function(code, reason)
                            print("[SlotSave] Migration write failed: " .. tostring(reason))
                            if attempt < MAX_RETRY then
                                -- 指数退避重试
                                local delay = 3 ^ attempt
                                print("[SlotSave] Migration retry in " .. delay .. "s...")
                                pendingRetry_ = {
                                    timer = delay,
                                    fn = function()
                                        RunMigration(callback, attempt + 1)
                                    end,
                                }
                            else
                                callback(nil, false, "存档迁移失败，请检查网络后重启游戏")
                            end
                        end,
                    })
            end,
            error = function(code, reason)
                print("[SlotSave] Migration read failed: " .. tostring(reason))
                if attempt < MAX_RETRY then
                    local delay = 3 ^ attempt
                    pendingRetry_ = {
                        timer = delay,
                        fn = function()
                            RunMigration(callback, attempt + 1)
                        end,
                    }
                else
                    callback(nil, false, "读取旧存档失败，请检查网络后重启游戏")
                end
            end,
        })
end

-- ============================================================================
-- 加载槽位 (用户在开始界面选择后调用)
-- ============================================================================

--- 完成加载后的公共处理
local function FinalizeLoad(slotId, slotData, onComplete, headData)
    if not SlotSaveSystem.ValidateStructure(slotData) then
        print("[SlotSave] Slot " .. slotId .. " data validation failed")
        if onComplete then onComplete(false, "存档数据为空") end
        return
    end
    -- 解压装备数据 (兼容新旧格式: DecompressItem 检测到旧格式自动跳过)
    if slotData.equipment then
        slotData.equipment = DecompressEquipmentTable(slotData.equipment, false)
    end
    if slotData.inventory then
        slotData.inventory = DecompressEquipmentTable(slotData.inventory, true)
    end
    local ok = SlotSaveSystem.Deserialize(slotData)
    if ok then
        currentSlot_ = slotId
        saveConfirmed_ = true
        saveTimer_ = 0
        UpdateMetaSnapshot(BuildMetaSlot())
        if saveMeta_ then
            saveMeta_.activeSlot = slotId
        end
        -- 记录 head 用于后续清理
        if headData then
            lastSavedHead_ = lastSavedHead_ or {}
            lastSavedHead_[slotId] = headData
        end
        print("[SlotSave] Slot " .. slotId .. " loaded OK (Lv." .. GameState.player.level .. ")")
        if onComplete then onComplete(true) end
    else
        print("[SlotSave] Deserialize failed for slot " .. slotId)
        if onComplete then onComplete(false, "存档数据损坏") end
    end
end

--- 从云端加载指定槽位的完整存档数据 (支持分片格式 + 旧格式兼容)
--- @param slotId number 槽位号 (1-10)
--- @param onComplete fun(ok: boolean, err?: string)
function SlotSaveSystem.LoadSlot(slotId, onComplete)
    local headKey = SlotPrefix(slotId) .. "head"
    local oldKey  = "save_slot_" .. slotId
    print("[SlotSave] Loading slot " .. slotId .. " (trying chunked format)...")

    -- 第一步：同时读取 head 和旧 key
    clientCloud:BatchGet()
        :Key(headKey)
        :Key(oldKey)
        :Fetch({
            ok = function(values)
                local headData = values[headKey]

                --- 回退到旧格式
                local function loadOldFormat(fallbackReason)
                    local slotData = values[oldKey]
                    if slotData and type(slotData) == "table" then
                        print("[SlotSave] Old single-key format loaded" .. (fallbackReason and (" (" .. fallbackReason .. ")") or ""))
                        FinalizeLoad(slotId, slotData, onComplete, nil)
                    else
                        print("[SlotSave] No data in slot " .. slotId)
                        if onComplete then onComplete(false, fallbackReason or "存档数据为空") end
                    end
                end

                -- 判断格式
                if headData and type(headData) == "table" and headData.format == SAVE_FORMAT then
                    -- === 分片格式 ===
                    print("[SlotSave] Chunked format detected (format=" .. headData.format .. ")")
                    local subKeys = CollectChunkedKeys(headData, slotId)

                    if #subKeys == 0 then
                        print("[SlotSave] No sub-keys in head, falling back to old format")
                        loadOldFormat("head无分组key")
                        return
                    end

                    -- 第二步：读取所有分组 key
                    local batchGet = clientCloud:BatchGet()
                    for _, k in ipairs(subKeys) do
                        batchGet:Key(k)
                    end
                    batchGet:Fetch({
                        ok = function(subValues)
                            local merged, err = DecodeChunkedGroups(headData, subValues, slotId)
                            if merged then
                                FinalizeLoad(slotId, merged, onComplete, headData)
                            else
                                print("[SlotSave] Chunked decode error: " .. tostring(err))
                                loadOldFormat("分片解码失败: " .. tostring(err))
                            end
                        end,
                        error = function(code, reason)
                            print("[SlotSave] Sub-keys fetch failed: " .. tostring(reason))
                            loadOldFormat("分片读取失败: " .. tostring(reason))
                        end,
                    })
                else
                    -- === 旧格式 (save_slot_N 单 key) ===
                    loadOldFormat(nil)
                end
            end,
            error = function(code, reason)
                print("[SlotSave] Load slot " .. slotId .. " failed: " .. tostring(reason))
                if onComplete then onComplete(false, "加载失败: " .. tostring(reason)) end
            end,
        })
end

-- ============================================================================
-- 新建存档 (空槽位点击后调用)
-- ============================================================================

--- 在指定槽位创建全新存档
--- @param slotId number 槽位号 (1-10)
--- @param onComplete fun(ok: boolean, err?: string)
function SlotSaveSystem.CreateNewSlot(slotId, onComplete)
    print("[SlotSave] Creating new save in slot " .. slotId .. "...")

    -- 重置 GameState 到初始状态
    GameState.Init()

    currentSlot_ = slotId
    playTime_ = 0
    createdAt_ = os.time()
    migratedFrom_ = nil
    SlotSaveSystem._saveCount = 0
    SlotSaveSystem.offlineSeconds = 0

    saveConfirmed_ = true
    saveTimer_ = 0

    local saveData = SlotSaveSystem.Serialize()
    local slotMeta = BuildMetaSlot()

    -- 更新 meta
    saveMeta_.slots[tostring(slotId)] = slotMeta
    saveMeta_.activeSlot = slotId
    UpdateMetaSnapshot(slotMeta)

    -- 先写本地
    SlotSaveSystem.SaveLocal(saveData)

    -- 分片编码
    local groups = SplitIntoGroups(saveData)
    local kvPairs, headData = EncodeChunkedGroups(slotId, groups)
    local headKey = SlotPrefix(slotId) .. "head"

    -- 再写云端 (分片格式 + meta + 兼容回写)
    local apiOk, _ = pcall(function()
        local batch = clientCloud:BatchSet()
        batch:Set(headKey, headData)
        for key, value in pairs(kvPairs) do
            batch:Set(key, value)
        end
        batch:Set("save_meta", saveMeta_)
        batch:Set("save_data", saveData)
        batch:Save("新建存档", {
            ok = function()
                print("[SlotSave] New slot " .. slotId .. " saved to cloud (chunked)")
                lastSavedHead_ = lastSavedHead_ or {}
                lastSavedHead_[slotId] = headData
                if onComplete then onComplete(true) end
            end,
            error = function(code, reason)
                print("[SlotSave] New slot cloud save failed: " .. tostring(reason))
                -- 本地已有, 不阻塞游戏
                if onComplete then onComplete(true) end
            end,
        })
    end)

    if not apiOk then
        -- 云端不可用, 本地已保存, 继续游戏
        if onComplete then onComplete(true) end
    end
end

-- ============================================================================
-- 删除存档
-- ============================================================================

--- 删除指定槽位的存档
--- @param slotId number 槽位号 (1-10)
--- @param onComplete fun(ok: boolean, err?: string)
function SlotSaveSystem.DeleteSlot(slotId, onComplete)
    if not saveMeta_ then
        if onComplete then onComplete(false, "系统未初始化") end
        return
    end
    if slotId == currentSlot_ and saveConfirmed_ then
        if onComplete then onComplete(false, "不能删除当前正在使用的存档") end
        return
    end

    print("[SlotSave] Deleting slot " .. slotId .. "...")

    -- 从 meta 中移除
    saveMeta_.slots[tostring(slotId)] = nil
    -- 如果删的是 activeSlot, 重置
    if saveMeta_.activeSlot == slotId then
        saveMeta_.activeSlot = 0
    end

    local apiOk, _ = pcall(function()
        local batch = clientCloud:BatchSet()

        -- 删除旧格式 key
        batch:Delete("save_slot_" .. slotId)

        -- 删除分片格式 key (head + 所有分组)
        local headKey = SlotPrefix(slotId) .. "head"
        batch:Delete(headKey)

        -- 尝试从缓存的 head 中获取要删除的 key
        lastSavedHead_ = lastSavedHead_ or {}
        local cachedHead = lastSavedHead_[slotId]
        if cachedHead and cachedHead.keys then
            local subKeys = CollectChunkedKeys(cachedHead, slotId)
            for _, k in ipairs(subKeys) do
                batch:Delete(k)
            end
        else
            -- 没有缓存，删除所有可能的组名 key (保守清理)
            local prefix = SlotPrefix(slotId)
            local GROUP_NAMES = { "core", "currency", "equip", "inv", "skills", "misc" }
            for _, gName in ipairs(GROUP_NAMES) do
                batch:Delete(prefix .. gName)
                -- 也删除可能的分片 (最多假设 10 个分片)
                for ci = 0, 9 do
                    batch:Delete(prefix .. gName .. "_" .. ci)
                end
            end
        end

        -- 清除缓存
        lastSavedHead_[slotId] = nil

        batch:Set("save_meta", saveMeta_)
        batch:Save("删除存档", {
            ok = function()
                print("[SlotSave] Slot " .. slotId .. " deleted (chunked + legacy)")
                if onComplete then onComplete(true) end
            end,
            error = function(code, reason)
                print("[SlotSave] Delete failed: " .. tostring(reason))
                if onComplete then onComplete(false, "删除失败: " .. tostring(reason)) end
            end,
        })
    end)

    if not apiOk then
        if onComplete then onComplete(false, "云端 API 不可用") end
    end
end

-- ============================================================================
-- 切换存档 (保存当前 → 返回开始界面)
-- ============================================================================

--- 保存当前槽位并重置为未加载状态 (由 UI 调用后重新展示 StartScreen)
--- @param onComplete fun()
function SlotSaveSystem.SaveAndUnload(onComplete)
    if saveConfirmed_ then
        -- 同步保存当前槽位
        SlotSaveSystem.SaveNow()
    end

    saveConfirmed_ = false
    currentSlot_ = 0
    saveTimer_ = 0
    dirtyTimer_ = 0
    retryCount_ = 0
    retryTimer_ = 0
    pendingSaveData_ = nil
    lastMetaSnapshot_ = nil

    -- 重新加载最新 meta
    local apiOk, _ = pcall(function()
        clientCloud:BatchGet()
            :Key("save_meta")
            :Fetch({
                ok = function(values)
                    local meta = values["save_meta"]
                    if meta and type(meta) == "table" then
                        saveMeta_ = meta
                    end
                    if onComplete then onComplete() end
                end,
                error = function()
                    -- 用缓存的 meta
                    if onComplete then onComplete() end
                end,
            })
    end)

    if not apiOk then
        if onComplete then onComplete() end
    end
end

-- ============================================================================
-- 初始化 (加载 save_meta 或触发迁移)
-- ============================================================================

--- @param onMetaReady fun(meta: table|nil, isNewPlayer: boolean, err?: string)
function SlotSaveSystem.Init(onMetaReady)
    onMetaReady_ = onMetaReady
    initPhase_ = "loading_meta"
    initTimeout_ = 0

    print("[SlotSave] Init (version=" .. CURRENT_SAVE_VERSION .. ")...")

    local function HandleMetaResult(meta, isNew, err)
        initPhase_ = "done"
        initialized_ = true
        if onMetaReady_ then
            onMetaReady_(meta, isNew, err)
            onMetaReady_ = nil
        end
    end

    local function TryLoadMeta(attempt)
        attempt = attempt or 1
        clientCloud:BatchGet()
            :Key("save_meta")
            :Fetch({
                ok = function(values)
                    local meta = values["save_meta"]
                    if meta and type(meta) == "table" and meta.version then
                        -- 已有 meta → 正常流程
                        saveMeta_ = meta
                        print("[SlotSave] Meta loaded, " .. SlotSaveSystem.GetSlotCount() .. " slot(s)")
                        HandleMetaResult(meta, false)
                    else
                        -- 无 meta → 检查旧存档, 执行迁移
                        initPhase_ = "migrating"
                        RunMigration(function(newMeta, isNewPlayer, migErr)
                            HandleMetaResult(newMeta, isNewPlayer, migErr)
                        end)
                    end
                end,
                error = function(code, reason)
                    print("[SlotSave] Meta load error (attempt " .. attempt .. "): " .. tostring(reason))
                    if attempt < MAX_RETRY then
                        local delay = 3 ^ attempt
                        pendingRetry_ = {
                            timer = delay,
                            fn = function()
                                TryLoadMeta(attempt + 1)
                            end,
                        }
                    else
                        HandleMetaResult(nil, false, "网络错误，无法加载存档数据")
                    end
                end,
            })
    end

    TryLoadMeta(1)
end

-- ============================================================================
-- 主循环 Update
-- ============================================================================

function SlotSaveSystem.Update(dt)
    -- 处理延迟重试 (Init/Migration 阶段)
    if pendingRetry_ then
        pendingRetry_.timer = pendingRetry_.timer - dt
        if pendingRetry_.timer <= 0 then
            local fn = pendingRetry_.fn
            pendingRetry_ = nil
            fn()
        end
        return
    end

    if not initialized_ then return end
    if not saveConfirmed_ then return end

    -- playTime 累计
    playTime_ = playTime_ + dt

    -- 云端重试计时
    if retryTimer_ > 0 and pendingSaveData_ then
        retryTimer_ = retryTimer_ - dt
        if retryTimer_ <= 0 then
            retryTimer_ = 0
            DoCloudSave(pendingSaveData_, true)
        end
    end

    -- 自动存档
    saveTimer_ = saveTimer_ + dt
    if saveTimer_ >= SAVE_INTERVAL then
        saveTimer_ = 0
        SlotSaveSystem.Save()
        dirtyTimer_ = 0
    end

    -- 脏标记延迟保存
    if dirtyTimer_ > 0 then
        dirtyTimer_ = dirtyTimer_ - dt
        if dirtyTimer_ <= 0 then
            dirtyTimer_ = 0
            saveTimer_ = 0
            SlotSaveSystem.Save()
        end
    end
end

-- ============================================================================
-- 公开查询 API
-- ============================================================================

--- 获取当前 save_meta
function SlotSaveSystem.GetMeta()
    return saveMeta_
end

--- 获取当前活跃槽位号 (0 = 未选择)
function SlotSaveSystem.GetActiveSlot()
    return currentSlot_
end

--- 获取 meta 中的槽位数量
function SlotSaveSystem.GetSlotCount()
    if not saveMeta_ or not saveMeta_.slots then return 0 end
    local count = 0
    for _ in pairs(saveMeta_.slots) do count = count + 1 end
    return count
end

--- 获取最大槽位数
function SlotSaveSystem.GetMaxSlots()
    return MAX_SLOTS
end

--- 获取累计游戏时长 (秒)
function SlotSaveSystem.GetPlayTime()
    return playTime_
end

--- 存档健康状态
function SlotSaveSystem.IsSaveHealthy()
    if not initialized_ then return false, "not_initialized" end
    if initPhase_ ~= "done" then return false, "loading" end
    if not saveConfirmed_ then return false, "load_failed" end
    return true, nil
end

-- ============================================================================
-- 复制当前存档到指定槽位 ("另存为")
-- ============================================================================

--- 将当前游戏进度保存到指定槽位 (不切换活跃槽)
--- @param targetSlot number 目标槽位号 (1~MAX_SLOTS)
--- @param onComplete fun(ok: boolean, err?: string) 完成回调
function SlotSaveSystem.CopyToSlot(targetSlot, onComplete)
    if not saveConfirmed_ then
        if onComplete then onComplete(false, "存档未加载") end
        return
    end
    if targetSlot < 1 or targetSlot > MAX_SLOTS then
        if onComplete then onComplete(false, "无效槽位") end
        return
    end

    local saveData = SlotSaveSystem.Serialize()

    -- 更新 _meta 中的 slotId 为目标槽位 (不改 createdAt)
    saveData._meta = saveData._meta or {}
    saveData._meta.slotId = targetSlot

    -- 构建目标槽的 meta 概要
    local slotMeta = BuildMetaSlot()

    -- 分片编码
    local groups = SplitIntoGroups(saveData)
    local kvPairs, headData = EncodeChunkedGroups(targetSlot, groups)
    local headKey = SlotPrefix(targetSlot) .. "head"

    local apiOk, _ = pcall(function()
        local batch = clientCloud:BatchSet()

        -- 写入 head + 分组 key
        batch:Set(headKey, headData)
        for key, value in pairs(kvPairs) do
            batch:Set(key, value)
        end

        -- 清理目标槽位旧分片残留
        lastSavedHead_ = lastSavedHead_ or {}
        local oldHead = lastSavedHead_[targetSlot]
        if oldHead and oldHead.keys then
            local oldKeys = CollectChunkedKeys(oldHead, targetSlot)
            for _, oldKey in ipairs(oldKeys) do
                if not kvPairs[oldKey] then
                    batch:Delete(oldKey)
                end
            end
        end

        -- 更新 meta
        saveMeta_.slots = saveMeta_.slots or {}
        saveMeta_.slots[tostring(targetSlot)] = slotMeta
        batch:Set("save_meta", saveMeta_)

        -- 兼容回写
        batch:Set("save_data", saveData)

        batch:Save("另存到槽位" .. targetSlot, {
            ok = function()
                print("[SlotSave] CopyToSlot OK → slot " .. targetSlot .. " (chunked)")
                lastSavedHead_[targetSlot] = headData
                -- 若保存到当前活跃槽, 同步 snapshot
                if targetSlot == currentSlot_ then
                    UpdateMetaSnapshot(slotMeta)
                end
                if onComplete then onComplete(true) end
            end,
            error = function(code, reason)
                print("[SlotSave] CopyToSlot FAILED: " .. tostring(reason))
                if onComplete then onComplete(false, reason or "云端保存失败") end
            end,
        })
    end)

    if not apiOk then
        if onComplete then onComplete(false, "保存异常") end
    end
end

-- ============================================================================
-- 内联域注册: forge (无独立模块)
-- ============================================================================

SlotSaveSystem.RegisterDomain({
    name  = "forge",
    keys  = { "forge" },
    group = "misc",
    serialize = function(GS)
        return {
            forge = {
                usedFree = GS.forge.usedFree,
                usedPaid = GS.forge.usedPaid,
                lastDate = GS.forge.lastDate,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.forge and type(data.forge) == "table" then
            GS.forge.usedFree = data.forge.usedFree or 0
            GS.forge.usedPaid = data.forge.usedPaid or 0
            GS.forge.lastDate = data.forge.lastDate or ""
        end
    end,
})

-- ============================================================================
-- 内联域注册: manaPotion (魔力之源)
-- ============================================================================

SlotSaveSystem.RegisterDomain({
    name  = "manaPotion",
    keys  = { "manaPotion" },
    group = "misc",
    serialize = function(GS)
        return {
            manaPotion = {
                count        = GS.manaPotion.count,
                level        = GS.manaPotion.level,
                autoUse      = GS.manaPotion.autoUse,
                freeRegenEnd = GS.manaPotion.freeRegenEnd,
                adWatchCount = GS.manaPotion.adWatchCount,
                adWatchDate  = GS.manaPotion.adWatchDate,
            },
        }
    end,
    deserialize = function(GS, data)
        if data.manaPotion and type(data.manaPotion) == "table" then
            GS.manaPotion.count        = data.manaPotion.count or 0
            GS.manaPotion.level        = data.manaPotion.level or 0
            GS.manaPotion.autoUse      = data.manaPotion.autoUse or false
            GS.manaPotion.freeRegenEnd = data.manaPotion.freeRegenEnd or 0
            GS.manaPotion.adWatchCount = data.manaPotion.adWatchCount or 0
            GS.manaPotion.adWatchDate  = data.manaPotion.adWatchDate or ""
        end
    end,
})

return SlotSaveSystem
