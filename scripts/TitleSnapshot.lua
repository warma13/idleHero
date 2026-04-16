-- ============================================================================
-- TitleSnapshot.lua - 排行榜快照导出 (一次性运行, 拉取排行榜数据存本地)
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local SlotSaveSystem = require("SlotSaveSystem")

local TitleSnapshot = {}

local SNAPSHOT_FILE = "title_snapshot.json"

--- 获取带槽位后缀的 key
local function SlotKey(base)
    local slot = SlotSaveSystem.GetActiveSlot()
    if slot <= 0 then slot = 1 end
    return base .. "_s" .. slot
end

--- 获取当前槽位的排行榜 key 列表
local function GetRankKeys()
    return { SlotKey("max_power_v2"), SlotKey("max_stage_v2"), SlotKey("max_trial_floor_v3") }
end
local FETCH_LIMIT = 100  -- 每个榜拉取条数
local POWER_SKIP_TOP = 3 -- 战力榜跳过前 N 名异常分数

-- 状态
local pending_ = 0
local results_ = {}  -- { max_power = { ... }, max_stage = { ... }, max_trial_floor = { ... } }
local nickMap_ = {}  -- userId → nickname 全局昵称缓存

-- ============================================================================
-- 拉取单个排行榜
-- ============================================================================

local function FetchRank(key, allKeys, callback)
    local powerKey = allKeys[1]  -- 战力榜 key（用于判断跳过逻辑）
    local ok, _ = pcall(function()
        clientCloud:GetRankList(key, 0, FETCH_LIMIT + (key == powerKey and POWER_SKIP_TOP or 0), {
            ok = function(rankList)
                -- 收集 userId 查昵称
                local userIds = {}
                for _, item in ipairs(rankList) do
                    table.insert(userIds, item.userId)
                end

                local function onNicksDone(nMap)
                    -- 合并昵称
                    if nMap then
                        for uid, nick in pairs(nMap) do
                            nickMap_[uid] = nick
                        end
                    end

                    -- 构建排名条目
                    local entries = {}
                    local rank = 0
                    for i, item in ipairs(rankList) do
                        local score = item.iscore[key] or 0
                        -- 战力榜跳过前 POWER_SKIP_TOP 名
                        if key == powerKey and i <= POWER_SKIP_TOP then
                            -- 跳过异常分数
                        else
                            rank = rank + 1
                            table.insert(entries, {
                                rank = rank,
                                userId = item.userId,
                                nickname = nickMap_[item.userId] or ("ID:" .. tostring(item.userId)),
                                score = score,
                            })
                        end
                    end

                    callback(entries)
                end

                -- 查昵称
                local nickOk, _ = pcall(function()
                    GetUserNickname({
                        userIds = userIds,
                        onSuccess = function(nicknames)
                            local map = {}
                            for _, info in ipairs(nicknames) do
                                map[info.userId] = info.nickname or ""
                            end
                            onNicksDone(map)
                        end,
                        onError = function()
                            onNicksDone(nil)
                        end,
                    })
                end)
                if not nickOk then
                    onNicksDone(nil)
                end
            end,
            error = function(code, reason)
                print("[TitleSnapshot] GetRankList error for " .. key .. ": " .. tostring(reason))
                callback({})
            end,
        }, table.unpack(allKeys))
    end)

    if not ok then
        print("[TitleSnapshot] clientCloud not available for " .. key)
        callback({})
    end
end

-- ============================================================================
-- 保存快照
-- ============================================================================

local function SaveSnapshot()
    local snapshot = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        note = "战力榜已去除前" .. POWER_SKIP_TOP .. "名异常分数",
        leaderboards = results_,
    }

    local json = cjson.encode(snapshot)

    local ok, err = pcall(function()
        local file = File(SNAPSHOT_FILE, FILE_WRITE)
        if not file:IsOpen() then error("Cannot open: " .. SNAPSHOT_FILE) end
        file:WriteString(json)
        file:Close()
    end)

    if ok then
        -- 统计
        local total = 0
        for _, entries in pairs(results_) do
            total = total + #entries
        end
        print("[TitleSnapshot] ===== 快照已保存 =====")
        print("[TitleSnapshot] 文件: " .. SNAPSHOT_FILE)
        print("[TitleSnapshot] 时间: " .. snapshot.timestamp)
        for key, entries in pairs(results_) do
            print("[TitleSnapshot]   " .. key .. ": " .. #entries .. " 条")
        end
        print("[TitleSnapshot] 总计: " .. total .. " 条记录")
    else
        print("[TitleSnapshot] 保存失败: " .. tostring(err))
    end
end

-- ============================================================================
-- 入口：拉取全部排行榜并保存
-- ============================================================================

function TitleSnapshot.Run()
    print("[TitleSnapshot] 开始拉取排行榜快照...")
    local keys = GetRankKeys()
    pending_ = #keys
    results_ = {}

    for _, key in ipairs(keys) do
        FetchRank(key, keys, function(entries)
            results_[key] = entries
            pending_ = pending_ - 1
            print("[TitleSnapshot] " .. key .. " 完成, " .. #entries .. " 条")

            if pending_ <= 0 then
                SaveSnapshot()
            end
        end)
    end
end

return TitleSnapshot
