-- ============================================================================
-- ui/Leaderboard.lua - 排行榜浮层 (分页加载, 最多100人)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local Colors = require("ui.Colors")

---@diagnostic disable-next-line: undefined-global
local lobby = lobby  -- 引擎内置全局

local SlotSaveSystem = require("SlotSaveSystem")

local Leaderboard = {}

-- 排行榜云存储 key（按槽位分离，后缀 _s{N}）
local KEY_POWER_BASE = "max_power_v3"
local KEY_STAGE_BASE = "max_stage_v2"
local KEY_TRIAL_BASE = "max_trial_floor_v3"

--- 获取带槽位后缀的 key
local function SlotKey(base)
    local slot = SlotSaveSystem.GetActiveSlot()
    if slot <= 0 then slot = 1 end
    return base .. "_s" .. slot
end

-- 当前槽位的实际 key（在 Show/LoadRank 时刷新）
local KEY_POWER = KEY_POWER_BASE
local KEY_STAGE = KEY_STAGE_BASE
local KEY_TRIAL = KEY_TRIAL_BASE

--- 刷新当前槽位 key
local function RefreshSlotKeys()
    KEY_POWER = SlotKey(KEY_POWER_BASE)
    KEY_STAGE = SlotKey(KEY_STAGE_BASE)
    KEY_TRIAL = SlotKey(KEY_TRIAL_BASE)
end

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local visible_ = false

-- 分页常量
local PAGE_LIMIT   = 21   -- 每次 API 请求条数 (多1条用于补偿测试账号过滤)
local PAGE_DISPLAY = 20   -- 每页期望显示条数
local MAX_DISPLAY  = 100  -- 最多显示条数

-- 分页状态
local currentRankKey_ = KEY_POWER
local currentOffset_  = 0
local allItems_       = {}   -- 已显示的全部条目
local loading_        = false
local hasMore_        = true
local myRankInfo_     = nil  -- { displayRank, nickname, displayScore }
local testSet_        = {}   -- 测试账号集合

-- UI 引用
local listPanel_      = nil
local loadMoreWidget_ = nil

function Leaderboard.SetOverlayRoot(root)
    overlayRoot_ = root
end

-- ============================================================================
-- 切换显示
-- ============================================================================

function Leaderboard.Toggle()
    if visible_ then
        Leaderboard.Hide()
    else
        Leaderboard.Show()
    end
end

function Leaderboard.Hide()
    if overlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
    listPanel_ = nil
    loadMoreWidget_ = nil
    visible_ = false
end

function Leaderboard.Show()
    if visible_ then Leaderboard.Hide() end
    visible_ = true

    -- 刷新当前槽位 key
    RefreshSlotKeys()

    -- 构建过滤集合 (测试账号 + 封禁用户)
    testSet_ = {}
    for _, tid in ipairs(Config.TEST_USER_IDS) do testSet_[tostring(tid)] = true end
    for _, bid in ipairs(Config.BANNED_USER_IDS or {}) do testSet_[tostring(bid)] = true end

    listPanel_ = UI.Panel { id = "lb_list", width = "100%", gap = 4 }

    overlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        zIndex = 1000,
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() Leaderboard.Hide() end,
        children = {
            UI.Panel {
                width = "80%", maxWidth = 320,
                maxHeight = "80%",
                backgroundColor = { 30, 35, 50, 250 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 80, 100, 140, 120 },
                padding = 16,
                gap = 10,
                onClick = function() end, -- 阻止穿透关闭
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 8,
                        children = {
                            UI.Panel { width = 24, height = 24, backgroundImage = Config.LEADERBOARD_ICON, backgroundFit = "contain" },
                            UI.Label { text = "服务器排行榜", fontSize = 16, fontColor = { 255, 215, 0, 255 } },
                        },
                    },
                    -- 排行榜标签
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", gap = 6,
                        children = {
                            UI.Panel {
                                id = "lb_tab_power",
                                flexGrow = 1, flexBasis = 0, height = 28,
                                alignItems = "center", justifyContent = "center",
                                borderRadius = 6,
                                backgroundColor = { 60, 100, 180, 230 },
                                onClick = function() Leaderboard.LoadRank(KEY_POWER) end,
                                children = {
                                    UI.Label { id = "lb_tab_power_lbl", text = "最高IP", fontSize = 10, fontColor = { 255, 255, 255, 255 } },
                                },
                            },
                            UI.Panel {
                                id = "lb_tab_stage",
                                flexGrow = 1, flexBasis = 0, height = 28,
                                alignItems = "center", justifyContent = "center",
                                borderRadius = 6,
                                backgroundColor = { 40, 45, 60, 200 },
                                onClick = function() Leaderboard.LoadRank(KEY_STAGE) end,
                                children = {
                                    UI.Label { id = "lb_tab_stage_lbl", text = "最高关卡", fontSize = 10, fontColor = { 180, 180, 190, 200 } },
                                },
                            },
                            UI.Panel {
                                id = "lb_tab_trial",
                                flexGrow = 1, flexBasis = 0, height = 28,
                                alignItems = "center", justifyContent = "center",
                                borderRadius = 6,
                                backgroundColor = { 40, 45, 60, 200 },
                                onClick = function() Leaderboard.LoadRank(KEY_TRIAL) end,
                                children = {
                                    UI.Label { id = "lb_tab_trial_lbl", text = "试炼最高层", fontSize = 10, fontColor = { 180, 180, 190, 200 } },
                                },
                            },
                        },
                    },
                    -- 列表区
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexBasis = 0,
                        children = { listPanel_ },
                    },
                    -- 底部固定: 我的排名
                    UI.Panel {
                        id = "lb_my_rank",
                        width = "100%", height = 30,
                        flexDirection = "row", alignItems = "center",
                        paddingHorizontal = 6,
                        backgroundColor = { 80, 140, 255, 40 },
                        borderRadius = 4,
                        borderWidth = 1, borderColor = { 80, 140, 255, 60 },
                        children = {
                            UI.Label { id = "lb_my_rank_pos", text = "#?", width = 24, fontSize = 11, fontColor = { 120, 180, 255, 255 } },
                            UI.Label { id = "lb_my_rank_name", text = "查询中...", flexGrow = 1, flexBasis = 0, fontSize = 11, fontColor = { 120, 180, 255, 255 } },
                            UI.Label { id = "lb_my_rank_score", text = "", width = 72, fontSize = 11, fontColor = Colors.text, textAlign = "right" },
                        },
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        width = "100%", height = 32, fontSize = 12,
                        variant = "secondary",
                        onClick = function() Leaderboard.Hide() end,
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end

    -- 默认加载IP排行榜
    Leaderboard.LoadRank(KEY_POWER)
end

-- ============================================================================
-- 加载排行榜数据 (切换 tab 时调用, 重置分页)
-- ============================================================================

function Leaderboard.LoadRank(rankKey)
    if not overlay_ then return end

    -- 更新 tab 高亮状态
    local tabs = {
        { key = KEY_POWER, panelId = "lb_tab_power", lblId = "lb_tab_power_lbl" },
        { key = KEY_STAGE, panelId = "lb_tab_stage", lblId = "lb_tab_stage_lbl" },
        { key = KEY_TRIAL, panelId = "lb_tab_trial", lblId = "lb_tab_trial_lbl" },
    }
    for _, t in ipairs(tabs) do
        local active = (rankKey == t.key)
        local panel = overlay_:FindById(t.panelId)
        local lbl   = overlay_:FindById(t.lblId)
        if panel then
            panel:SetStyle({ backgroundColor = active and { 60, 100, 180, 230 } or { 40, 45, 60, 200 } })
        end
        if lbl then
            lbl:SetFontColor(active and { 255, 255, 255, 255 } or { 180, 180, 190, 200 })
        end
    end

    -- 重置分页状态
    currentRankKey_ = rankKey
    currentOffset_  = 0
    allItems_       = {}
    loading_        = false
    hasMore_        = true
    myRankInfo_     = nil
    loadMoreWidget_ = nil

    -- 先上传自己的数据
    Leaderboard.UploadMyScore()

    -- 清空列表, 添加表头
    if listPanel_ then
        listPanel_:ClearChildren()
        listPanel_:AddChild(UI.Panel {
            id = "lb_header",
            width = "100%", height = 24,
            flexDirection = "row", alignItems = "center",
            paddingHorizontal = 6,
            backgroundColor = { 40, 50, 70, 100 },
            borderRadius = 4,
            children = {
                UI.Label { text = "#", width = 24, fontSize = 10, fontColor = Colors.textDim },
                UI.Label { text = "玩家", flexGrow = 1, flexBasis = 0, fontSize = 10, fontColor = Colors.textDim },
                UI.Label { text = rankKey == KEY_POWER and "IP" or (rankKey == KEY_TRIAL and "最高层" or "关卡"), width = 72, fontSize = 10, fontColor = Colors.textDim, textAlign = "right" },
            },
        })
    end

    -- 重置我的排名显示
    Leaderboard.UpdateMyRankPanel()

    -- 独立查询当前用户排名
    Leaderboard.QueryMyRank()

    -- 加载第一页
    Leaderboard.LoadPage()
end

-- ============================================================================
-- 分页加载
-- ============================================================================

--- 格式化大数值 (统一调用 Utils.FormatNumber)
local FormatBigNumber = require("Utils").FormatNumber

--- 格式化分数显示
local function FormatScore(rankKey, score)
    if rankKey == KEY_STAGE and score > 0 then
        local ch = math.floor(score / 100)
        local st = score % 100
        return ch .. "-" .. st
    elseif rankKey == KEY_TRIAL then
        return "F" .. tostring(score)
    elseif rankKey == KEY_POWER then
        return FormatBigNumber(score)
    end
    return tostring(score)
end

--- 加载下一页数据
function Leaderboard.LoadPage()
    if loading_ or not hasMore_ or not overlay_ then return end
    if #allItems_ >= MAX_DISPLAY then
        hasMore_ = false
        Leaderboard.UpdateLoadMore()
        return
    end

    loading_ = true
    Leaderboard.UpdateLoadMore()

    local ok, _ = pcall(function()
        clientCloud:GetRankList(currentRankKey_, currentOffset_, PAGE_LIMIT, {
            ok = function(rankList)
                if not overlay_ or not listPanel_ then return end

                local isLastPage = (#rankList < PAGE_LIMIT)

                -- 过滤测试账号和封禁用户
                local filtered = {}
                local testFoundInBatch = false
                for _, item in ipairs(rankList) do
                    if testSet_[tostring(item.userId)] then
                        testFoundInBatch = true
                    else
                        table.insert(filtered, item)
                    end
                end

                -- 决定本页显示条目和偏移量调整
                local toDisplay
                if isLastPage then
                    -- 最后一页: 全部显示, 不需要留给下页
                    toDisplay = filtered
                    hasMore_ = false
                elseif testFoundInBatch then
                    -- 测试账号在本批: 过滤后刚好 PAGE_DISPLAY 条
                    toDisplay = filtered
                    currentOffset_ = currentOffset_ + PAGE_LIMIT
                else
                    -- 测试账号不在本批: 取前 PAGE_DISPLAY 条, 偏移量少进1
                    toDisplay = {}
                    for i = 1, math.min(PAGE_DISPLAY, #filtered) do
                        toDisplay[i] = filtered[i]
                    end
                    currentOffset_ = currentOffset_ + PAGE_DISPLAY
                end

                -- 空数据
                if #toDisplay == 0 then
                    hasMore_ = false
                    loading_ = false
                    Leaderboard.UpdateLoadMore()
                    Leaderboard.UpdateMyRankPanel()
                    if #allItems_ == 0 then
                        listPanel_:AddChild(UI.Label { text = "暂无数据", fontSize = 12, fontColor = Colors.textDim, textAlign = "center" })
                    end
                    return
                end

                -- 获取当前用户ID
                local myUserId = nil
                pcall(function() myUserId = lobby:GetMyUserId() end)

                -- 构建新条目
                local newEntries = {}
                for _, item in ipairs(toDisplay) do
                    local displayRank = #allItems_ + #newEntries + 1
                    local score = item.iscore[currentRankKey_] or 0
                    local isMe = (myUserId ~= nil and item.userId == myUserId)

                    local entry = {
                        userId = item.userId,
                        displayRank = displayRank,
                        score = score,
                        displayScore = FormatScore(currentRankKey_, score),
                        isMe = isMe,
                    }
                    table.insert(newEntries, entry)

                    if isMe then
                        myRankInfo_ = entry
                    end
                end

                -- 累加到总列表
                for _, e in ipairs(newEntries) do
                    table.insert(allItems_, e)
                end
                if #allItems_ >= MAX_DISPLAY then
                    hasMore_ = false
                end

                -- 收集 userId 查询昵称
                local userIds = {}
                for _, item in ipairs(toDisplay) do
                    table.insert(userIds, item.userId)
                end

                local function renderNewEntries(nickMap)
                    if not overlay_ or not listPanel_ then return end

                    -- 移除旧的加载提示
                    if loadMoreWidget_ then
                        listPanel_:RemoveChild(loadMoreWidget_)
                        loadMoreWidget_ = nil
                    end

                    -- 追加新行
                    for _, entry in ipairs(newEntries) do
                        local nickname = (nickMap and nickMap[entry.userId]) or ("ID:" .. tostring(entry.userId))
                        entry.nickname = nickname

                        local rankColor = entry.displayRank <= 3 and { 255, 215, 0, 255 } or Colors.text
                        local bgColor = entry.isMe and { 80, 140, 255, 40 } or { 0, 0, 0, 0 }

                        listPanel_:AddChild(UI.Panel {
                            width = "100%", height = 28,
                            flexDirection = "row", alignItems = "center",
                            paddingHorizontal = 6,
                            backgroundColor = bgColor,
                            borderRadius = 4,
                            children = {
                                UI.Label { text = tostring(entry.displayRank), width = 24, fontSize = 11, fontColor = rankColor },
                                UI.Label { text = nickname, flexGrow = 1, flexBasis = 0, fontSize = 11, fontColor = entry.isMe and { 120, 180, 255, 255 } or Colors.text },
                                UI.Label { text = entry.displayScore, width = 72, fontSize = 11, fontColor = Colors.text, textAlign = "right" },
                            },
                        })
                    end

                    loading_ = false
                    Leaderboard.UpdateLoadMore()
                    Leaderboard.UpdateMyRankPanel()
                end

                -- 查询昵称
                local nameOk, _ = pcall(function()
                    GetUserNickname({
                        userIds = userIds,
                        onSuccess = function(nicknames)
                            local map = {}
                            for _, info in ipairs(nicknames) do
                                map[info.userId] = info.nickname or ""
                            end
                            renderNewEntries(map)
                        end,
                        onError = function()
                            renderNewEntries(nil)
                        end,
                    })
                end)
                if not nameOk then
                    renderNewEntries(nil)
                end
            end,
            error = function(code, reason)
                if not overlay_ then return end
                loading_ = false
                hasMore_ = false
                Leaderboard.UpdateLoadMore()
                Leaderboard.UpdateMyRankPanel()
            end,
        }, KEY_POWER, KEY_STAGE, KEY_TRIAL)
    end)

    if not ok then
        -- clientCloud 不可用(本地测试)
        loading_ = false
        hasMore_ = false
        if listPanel_ then
            listPanel_:ClearChildren()
            listPanel_:AddChild(UI.Label { text = "本地模式 - 无法连接服务器", fontSize = 11, fontColor = Colors.textDim, textAlign = "center" })
            listPanel_:AddChild(UI.Panel { width = "100%", height = 8 })

            local records = GameState.records
            listPanel_:AddChild(UI.Panel {
                width = "100%", height = 30,
                flexDirection = "row", alignItems = "center",
                paddingHorizontal = 6,
                backgroundColor = { 80, 140, 255, 40 },
                borderRadius = 4,
                children = {
                    UI.Label { text = "#1", width = 24, fontSize = 11, fontColor = { 255, 215, 0, 255 } },
                    UI.Label { text = "我", flexGrow = 1, flexBasis = 0, fontSize = 11, fontColor = { 120, 180, 255, 255 } },
                    UI.Label {
                        text = FormatScore(currentRankKey_,
                            currentRankKey_ == KEY_POWER and records.maxPower
                            or currentRankKey_ == KEY_TRIAL and (GameState.endlessTrial.maxFloor or 0)
                            or (records.maxChapter * 100 + records.maxStage)),
                        width = 72, fontSize = 11, fontColor = Colors.text, textAlign = "right",
                    },
                },
            })
        end
        Leaderboard.UpdateMyRankPanel()
    end
end

-- ============================================================================
-- "加载更多" 提示管理
-- ============================================================================

function Leaderboard.UpdateLoadMore()
    if not listPanel_ then return end

    -- 移除旧提示
    if loadMoreWidget_ then
        listPanel_:RemoveChild(loadMoreWidget_)
        loadMoreWidget_ = nil
    end

    if loading_ then
        loadMoreWidget_ = UI.Panel {
            width = "100%", height = 32,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "加载中...", fontSize = 11, fontColor = Colors.textDim },
            },
        }
        listPanel_:AddChild(loadMoreWidget_)
    elseif hasMore_ then
        loadMoreWidget_ = UI.Panel {
            width = "100%", height = 32,
            alignItems = "center", justifyContent = "center",
            backgroundColor = { 50, 60, 80, 120 },
            borderRadius = 6,
            onClick = function() Leaderboard.LoadPage() end,
            children = {
                UI.Label { text = "点击加载更多...", fontSize = 11, fontColor = { 150, 170, 200, 220 } },
            },
        }
        listPanel_:AddChild(loadMoreWidget_)
    else
        if #allItems_ > 0 then
            loadMoreWidget_ = UI.Panel {
                width = "100%", height = 24,
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Label { text = "— 已显示全部 —", fontSize = 10, fontColor = Colors.textDim },
                },
            }
            listPanel_:AddChild(loadMoreWidget_)
        end
    end
end

-- ============================================================================
-- 底部 "我的排名" 更新
-- ============================================================================

function Leaderboard.UpdateMyRankPanel()
    if not overlay_ then return end
    local posLbl   = overlay_:FindById("lb_my_rank_pos")
    local nameLbl  = overlay_:FindById("lb_my_rank_name")
    local scoreLbl = overlay_:FindById("lb_my_rank_score")
    if not posLbl or not nameLbl or not scoreLbl then return end

    if myRankInfo_ then
        posLbl:SetText("#" .. myRankInfo_.displayRank)
        nameLbl:SetText(myRankInfo_.nickname or "我")
        scoreLbl:SetText(myRankInfo_.displayScore)
    elseif not hasMore_ and not loading_ then
        -- 加载完所有数据仍未找到自己
        posLbl:SetText(">" .. MAX_DISPLAY)
        nameLbl:SetText("我")
        local records = GameState.records
        local myScore
        if currentRankKey_ == KEY_POWER then
            myScore = records.maxPower
        elseif currentRankKey_ == KEY_TRIAL then
            myScore = GameState.endlessTrial.maxFloor or 0
        else
            myScore = records.maxChapter * 100 + records.maxStage
        end
        scoreLbl:SetText(FormatScore(currentRankKey_, myScore))
    else
        posLbl:SetText("#?")
        nameLbl:SetText("查询中...")
        scoreLbl:SetText("")
    end
end

-- ============================================================================
-- 独立查询当前用户排名
-- ============================================================================

function Leaderboard.QueryMyRank()
    pcall(function()
        local myUserId = lobby:GetMyUserId()
        clientCloud:GetUserRank(myUserId, currentRankKey_, {
            ok = function(rank, scoreValue)
                if not overlay_ then return end
                -- 列表回调中已找到自己, 优先使用列表中的精确排名
                if myRankInfo_ then return end

                local myNickname = "我"
                pcall(function()
                    GetUserNickname({
                        userIds = { myUserId },
                        onSuccess = function(nicknames)
                            if nicknames and #nicknames > 0 and nicknames[1].nickname then
                                myNickname = nicknames[1].nickname
                            end
                            Leaderboard.SetMyRank(rank, myNickname, scoreValue)
                        end,
                        onError = function()
                            Leaderboard.SetMyRank(rank, myNickname, scoreValue)
                        end,
                    })
                end)
            end,
            error = function() end,
        })
    end)
end

function Leaderboard.SetMyRank(rank, nickname, scoreValue)
    if not overlay_ then return end
    -- 列表回调中已找到自己, 不覆盖
    if myRankInfo_ then return end

    if rank then
        myRankInfo_ = {
            displayRank = rank,
            nickname = nickname,
            displayScore = FormatScore(currentRankKey_, scoreValue or 0),
        }
    else
        -- 未上榜
        myRankInfo_ = {
            displayRank = "-",
            nickname = nickname,
            displayScore = "未上榜",
        }
    end
    Leaderboard.UpdateMyRankPanel()
end

-- ============================================================================
-- 上传自己的成绩
-- ============================================================================

function Leaderboard.UploadMyScore()
    local records = GameState.records
    local power = GameState.GetPower()
    if power > records.maxPower then records.maxPower = power end

    local stageVal = records.maxChapter * 100 + records.maxStage

    local trialFloor = GameState.endlessTrial.maxFloor or 0

    pcall(function()
        clientCloud:BatchSet()
            :SetInt(KEY_POWER, records.maxPower)
            :SetInt(KEY_STAGE, stageVal)
            :SetInt(KEY_TRIAL, trialFloor)
            :Save("排行榜更新")
    end)
end

return Leaderboard
