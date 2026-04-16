-- ============================================================================
-- ui/StartScreen.lua - 存档选择界面 (多槽位)
--
-- 启动时或切换存档时展示, 显示 10 个槽位, 玩家选择后进入游戏。
-- API:
--   StartScreen.Show(meta, onEnterGame)  -- 展示选档界面
--   StartScreen.ShowError(errMsg, onRetry) -- 展示错误界面
--   StartScreen.Hide()                   -- 隐藏 (由内部调用)
--   StartScreen.IsVisible()              -- 查询
-- ============================================================================

local UI     = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local Config = require("Config")

local StartScreen = {}

---@type Widget
local root_        = nil
local onEnterGame_ = nil   -- fun(): 槽位加载成功后回调, 由调用方负责构建游戏 UI
local loading_     = false -- 防止重复点击

-- 延迟 require, 避免循环依赖
local SlotSaveSystem_ = nil
local function getSlotSave()
    if not SlotSaveSystem_ then
        SlotSaveSystem_ = require("SlotSaveSystem")
    end
    return SlotSaveSystem_
end

local Toast_ = nil
local function getToast()
    if not Toast_ then
        local ok, t = pcall(require, "ui.Toast")
        if ok then Toast_ = t end
    end
    return Toast_
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 格式化游戏时长 (秒 → 可读字符串)
local function FormatPlayTime(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then return "不到1分钟" end
    local hours = math.floor(seconds / 3600)
    local mins  = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return hours .. "小时" .. (mins > 0 and (mins .. "分") or "")
    end
    return mins .. "分钟"
end

--- 格式化时间戳
local function FormatTimestamp(ts)
    if not ts or ts <= 0 then return "" end
    local ok, t = pcall(os.date, "*t", ts)
    if not ok or not t then return "" end
    return string.format("%d-%02d-%02d %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
end

-- ============================================================================
-- 颜色常量 (与游戏暗色主题一致)
-- ============================================================================

local C = {
    pageBg     = { 14, 18, 28, 255 },
    cardBg     = { 28, 32, 44, 235 },
    cardEmpty  = { 24, 28, 40, 180 },
    border     = { 50, 58, 75, 120 },
    borderEmpty = { 45, 52, 68, 100 },
    borderActive = { 70, 150, 255, 200 },
    title      = { 220, 225, 240, 255 },
    subtitle   = { 110, 120, 145, 150 },
    text       = { 200, 205, 220, 240 },
    textDim    = { 120, 130, 155, 160 },
    textMuted  = { 80, 90, 110, 110 },
    accent     = { 90, 130, 210, 180 },
    badge      = { 55, 120, 220, 200 },
    migBadge   = { 100, 80, 45, 170 },
    migText    = { 255, 210, 130, 210 },
    delete     = { 200, 90, 90, 160 },
    divider    = { 50, 58, 75, 80 },
    errorRed   = { 230, 80, 80, 255 },
}

-- ============================================================================
-- 槽位卡片构建 (紧凑布局)
-- ============================================================================

--- 空槽位卡片 (紧凑: 单行)
local function BuildEmptyCard(slotId)
    return UI.Panel {
        width = "100%",
        height = 44,
        backgroundColor = C.cardEmpty,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = C.borderEmpty,
        marginBottom = 6,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        onClick = function()
            if loading_ then return end
            StartScreen._CreateSlot(slotId)
        end,
        children = {
            UI.Label {
                text = "槽位 " .. slotId,
                fontSize = 12,
                fontColor = C.textDim,
            },
            UI.Panel { flexGrow = 1 },
            UI.Label {
                text = "+ 新建存档",
                fontSize = 12,
                fontColor = C.accent,
            },
        },
    }
end

--- 已有存档卡片 (紧凑: 信息一行 + 按钮一行)
local function BuildUsedCard(slotId, slotData, isActive)
    local borderColor = isActive and C.borderActive or C.border
    local borderW     = isActive and 2 or 1

    local levelStr = "Lv." .. (slotData.level or 1)
    local stageStr = "第" .. (slotData.chapter or 1) .. "章-" .. (slotData.stage or 1) .. "关"

    -- 构建标题+徽章
    local titleParts = {
        UI.Label {
            text = "存档 " .. slotId,
            fontSize = 13, fontWeight = "bold",
            fontColor = C.title,
        },
    }
    if isActive then
        table.insert(titleParts, UI.Panel {
            backgroundColor = C.badge,
            borderRadius = 3,
            paddingHorizontal = 5, paddingVertical = 1,
            marginLeft = 5,
            children = {
                UI.Label { text = "活跃", fontSize = 8, fontColor = { 255, 255, 255, 230 } },
            },
        })
    end
    if slotData.migratedFrom then
        local migLabel = slotData.migratedFrom == "auto_save" and "自动迁移"
            or slotData.migratedFrom == "manual_save" and "手动迁移"
            or nil
        if migLabel then
            table.insert(titleParts, UI.Panel {
                backgroundColor = C.migBadge,
                borderRadius = 3,
                paddingHorizontal = 4, paddingVertical = 1,
                marginLeft = 4,
                children = {
                    UI.Label { text = migLabel, fontSize = 8, fontColor = C.migText },
                },
            })
        end
    end

    -- 信息摘要 (合并为一行)
    local infoParts = levelStr .. " · " .. stageStr
    if slotData.maxFloor and slotData.maxFloor > 0 then
        infoParts = infoParts .. " · 试炼" .. slotData.maxFloor .. "层"
    end

    -- 次要信息
    local subInfo = FormatPlayTime(slotData.playTime) .. "    " .. FormatTimestamp(slotData.timestamp)

    return UI.Panel {
        width = "100%",
        backgroundColor = C.cardBg,
        borderRadius = 8,
        borderWidth = borderW,
        borderColor = borderColor,
        marginBottom = 6,
        paddingHorizontal = 12, paddingVertical = 8,
        gap = 4,
        children = {
            -- 第一行: 标题 + 徽章
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                width = "100%",
                children = titleParts,
            },
            -- 第二行: 等级·章节·试炼
            UI.Label {
                text = infoParts,
                fontSize = 12, fontColor = C.text,
            },
            -- 第三行: 时长 + 日期
            UI.Label {
                text = subInfo,
                fontSize = 10, fontColor = C.textDim,
            },
            -- 第四行: 按钮
            UI.Panel {
                flexDirection = "row", gap = 8,
                width = "100%", marginTop = 2,
                children = {
                    UI.Button {
                        text = "加载存档",
                        variant = "primary",
                        flexGrow = 1, height = 32, fontSize = 12,
                        onClick = function()
                            if loading_ then return end
                            StartScreen._LoadSlot(slotId)
                        end,
                    },
                    UI.Button {
                        text = "删除",
                        variant = "secondary",
                        width = 60, height = 32, fontSize = 12,
                        fontColor = { 255, 100, 90, 255 },
                        onClick = function()
                            if loading_ then return end
                            StartScreen._DeleteSlot(slotId)
                        end,
                    },
                },
            },
        },
    }
end

--- 根据数据选择构建空卡片或已有卡片
local function BuildSlotCard(slotId, slotData, isActive)
    if not slotData then
        return BuildEmptyCard(slotId)
    end
    return BuildUsedCard(slotId, slotData, isActive)
end

-- ============================================================================
-- 操作处理
-- ============================================================================

--- 加载已有存档
function StartScreen._LoadSlot(slotId)
    loading_ = true
    local toast = getToast()
    if toast then toast.Show("加载存档 " .. slotId .. "...") end

    getSlotSave().LoadSlot(slotId, function(ok, err)
        loading_ = false
        if ok then
            StartScreen.Hide()
            if onEnterGame_ then onEnterGame_() end
        else
            if toast then toast.Warn("加载失败: " .. (err or "未知错误")) end
        end
    end)
end

--- 创建新存档
function StartScreen._CreateSlot(slotId)
    loading_ = true
    local toast = getToast()
    if toast then toast.Show("创建存档...") end

    getSlotSave().CreateNewSlot(slotId, function(ok, err)
        loading_ = false
        if ok then
            StartScreen.Hide()
            if onEnterGame_ then onEnterGame_() end
        else
            if toast then toast.Warn("创建失败: " .. (err or "未知错误")) end
        end
    end)
end

--- 删除存档 (二次确认) — 用自定义浮层替代 Modal.Confirm，避免 PushOverlay 卡死
---@type Widget|nil
local deleteOverlay_ = nil

function StartScreen._DeleteSlot(slotId)
    if deleteOverlay_ then
        root_:RemoveChild(deleteOverlay_)
        deleteOverlay_ = nil
    end

    local function closeOverlay()
        if deleteOverlay_ and root_ then
            root_:RemoveChild(deleteOverlay_)
        end
        deleteOverlay_ = nil
    end

    deleteOverlay_ = UI.Panel {
        position = "absolute", left = 0, top = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        onClick = function() closeOverlay() end,
        children = {
            UI.Panel {
                width = "80%", maxWidth = 300,
                backgroundColor = { 28, 32, 48, 250 },
                borderRadius = 12, borderWidth = 1, borderColor = { 60, 70, 90, 120 },
                padding = 20, gap = 16,
                alignItems = "center",
                onClick = function() end, -- 阻止穿透
                children = {
                    UI.Label {
                        text = "删除存档",
                        fontSize = 16, fontWeight = "bold",
                        fontColor = C.title,
                    },
                    UI.Label {
                        text = "确定要删除存档 " .. slotId .. " 吗？\n此操作不可撤销。",
                        fontSize = 13, fontColor = C.text,
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12,
                        children = {
                            UI.Button {
                                text = "取消", variant = "secondary",
                                width = 100, height = 36, fontSize = 13,
                                onClick = function() closeOverlay() end,
                            },
                            UI.Button {
                                text = "确认删除", variant = "primary",
                                width = 100, height = 36, fontSize = 13,
                                backgroundColor = { 180, 60, 60, 255 },
                                onClick = function()
                                    closeOverlay()
                                    local toast = getToast()
                                    getSlotSave().DeleteSlot(slotId, function(ok, err)
                                        if ok then
                                            if toast then toast.Show("存档 " .. slotId .. " 已删除") end
                                            StartScreen._Refresh()
                                        else
                                            if toast then toast.Warn("删除失败: " .. (err or "未知错误")) end
                                        end
                                    end)
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if root_ then
        root_:AddChild(deleteOverlay_)
    end
end

--- 刷新槽位列表 (删除后重建)
function StartScreen._Refresh()
    -- 重建存档选择浮层
    StartScreen._CloseSlotOverlay()
    StartScreen._ShowSlotOverlay()
end

-- ============================================================================
-- 服务器选择浮层
-- ============================================================================

---@type Widget|nil
local serverOverlay_ = nil

--- 关闭服务器选择浮层
function StartScreen._CloseServerOverlay()
    if serverOverlay_ and root_ then
        root_:RemoveChild(serverOverlay_)
    end
    serverOverlay_ = nil
end

--- 构建服务器卡片
local function BuildServerCard(name, desc, statusText, statusColor, onClick)
    return UI.Panel {
        width = "100%",
        backgroundColor = C.cardBg,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = C.border,
        marginBottom = 10,
        paddingHorizontal = 16, paddingVertical = 14,
        gap = 4,
        onClick = onClick,
        children = {
            -- 第一行: 服务器名 + 状态
            UI.Panel {
                flexDirection = "row", alignItems = "center",
                width = "100%",
                children = {
                    UI.Label {
                        text = name,
                        fontSize = 15, fontWeight = "bold",
                        fontColor = C.title,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Panel {
                        backgroundColor = statusColor,
                        borderRadius = 3,
                        paddingHorizontal = 6, paddingVertical = 2,
                        children = {
                            UI.Label { text = statusText, fontSize = 9, fontColor = { 255, 255, 255, 220 } },
                        },
                    },
                },
            },
            -- 第二行: 描述
            UI.Label {
                text = desc,
                fontSize = 11, fontColor = C.textDim,
            },
        },
    }
end

--- 起始之地: 使用独立 slot 0, 已有存档则加载, 否则新建
function StartScreen._EnterStarterServer()
    if loading_ then return end
    loading_ = true
    local toast = getToast()
    if toast then toast.Show("正在进入起始之地...") end

    local SlotSave = getSlotSave()
    local meta = SlotSave.GetMeta()
    local hasSlot0 = meta and meta.slots and meta.slots["0"] ~= nil

    local function onDone(ok, err)
        loading_ = false
        if ok then
            StartScreen.Hide()
            if onEnterGame_ then onEnterGame_() end
        else
            if toast then toast.Warn("进入失败: " .. (err or "未知错误")) end
        end
    end

    if hasSlot0 then
        SlotSave.LoadSlot(0, onDone)
    else
        SlotSave.CreateNewSlot(0, onDone)
    end
end

--- 打开服务器选择浮层
function StartScreen._ShowServerOverlay()
    if serverOverlay_ then StartScreen._CloseServerOverlay() end
    loading_ = false

    -- 统计灰烬荒原的存档数量
    local meta = getSlotSave().GetMeta()
    local slotCount = 0
    if meta and meta.slots then
        for k, _ in pairs(meta.slots) do
            local n = tonumber(k)
            if n and n >= 1 and n <= 10 then
                slotCount = slotCount + 1
            end
        end
    end
    local ashDesc = slotCount > 0
        and (slotCount .. " 个存档")
        or "无存档"

    serverOverlay_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() StartScreen._CloseServerOverlay() end,
        children = {
            UI.Panel {
                width = "85%", maxWidth = 340,
                backgroundColor = { 18, 22, 34, 245 },
                borderRadius = 14,
                borderWidth = 1, borderColor = { 80, 70, 130, 100 },
                padding = 16,
                gap = 10,
                onClick = function() end, -- 阻止穿透
                children = {
                    -- 标题
                    UI.Label {
                        text = "选择服务器",
                        fontSize = 16, fontWeight = "bold",
                        fontColor = { 240, 230, 255, 255 },
                        textAlign = "center",
                        width = "100%",
                        marginBottom = 4,
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 120, 100, 180, 40 },
                    },
                    -- 灰烬荒原 服
                    BuildServerCard(
                        "灰烬荒原",
                        ashDesc,
                        "老服",
                        { 70, 130, 200, 200 },
                        function()
                            if loading_ then return end
                            if slotCount == 0 then
                                local toast = getToast()
                                if toast then toast.Warn("已停止注册") end
                                return
                            end
                            StartScreen._CloseServerOverlay()
                            StartScreen._ShowSlotOverlay()
                        end
                    ),
                    -- 起始之地 服
                    BuildServerCard(
                        "起始之地",
                        "全新冒险，即刻出发",
                        "新服",
                        { 80, 170, 90, 200 },
                        function()
                            StartScreen._EnterStarterServer()
                        end
                    ),
                    -- 返回按钮
                    UI.Button {
                        text = "返回",
                        variant = "secondary",
                        width = "100%", height = 36, fontSize = 13,
                        onClick = function() StartScreen._CloseServerOverlay() end,
                    },
                },
            },
        },
    }

    if root_ then
        root_:AddChild(serverOverlay_)
    end
end

-- ============================================================================
-- 存档选择浮层 (弹出在门面之上)
-- ============================================================================

---@type Widget|nil
local slotOverlay_ = nil

--- 关闭存档选择浮层
function StartScreen._CloseSlotOverlay()
    if slotOverlay_ and root_ then
        root_:RemoveChild(slotOverlay_)
    end
    slotOverlay_ = nil
end

--- 打开存档选择浮层
function StartScreen._ShowSlotOverlay()
    if slotOverlay_ then StartScreen._CloseSlotOverlay() end
    loading_ = false

    local meta = getSlotSave().GetMeta()
    if not meta then return end

    local activeSlot = meta.activeSlot or 0
    local slots = meta.slots or {}
    local maxSlots = getSlotSave().GetMaxSlots()

    -- 构建紧凑槽位卡片
    local slotCards = {}
    for i = 1, maxSlots do
        local slotData = slots[tostring(i)]
        local isActive = (i == activeSlot)
        table.insert(slotCards, BuildSlotCard(i, slotData, isActive))
    end

    -- 底部统计
    local slotCount = getSlotSave().GetSlotCount()
    table.insert(slotCards, UI.Label {
        text = slotCount .. " / " .. maxSlots .. " 个存档槽位已使用",
        fontSize = 10,
        fontColor = C.textMuted,
        textAlign = "center",
        width = "100%",
        marginTop = 4,
        marginBottom = 12,
    })

    slotOverlay_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() StartScreen._CloseSlotOverlay() end,
        children = {
            UI.Panel {
                width = "88%", maxWidth = 360, maxHeight = "85%",
                backgroundColor = { 18, 22, 34, 245 },
                borderRadius = 14,
                borderWidth = 1, borderColor = { 80, 70, 130, 100 },
                padding = 14,
                gap = 8,
                onClick = function() end, -- 阻止穿透
                children = {
                    -- 标题
                    UI.Label {
                        text = "选择存档",
                        fontSize = 16, fontWeight = "bold",
                        fontColor = { 240, 230, 255, 255 },
                        textAlign = "center",
                        width = "100%",
                        marginBottom = 4,
                    },
                    -- 分隔线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 120, 100, 180, 40 },
                    },
                    -- 可滚动槽位列表
                    UI.ScrollView {
                        flexGrow = 1, flexBasis = 0,
                        width = "100%",
                        paddingTop = 8,
                        children = slotCards,
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "返回",
                        variant = "secondary",
                        width = "100%", height = 36, fontSize = 13,
                        onClick = function() StartScreen._CloseSlotOverlay() end,
                    },
                },
            },
        },
    }

    if root_ then
        root_:AddChild(slotOverlay_)
    end
end

-- ============================================================================
-- 公开 API
-- ============================================================================

local VersionReward_ = nil
local function getVersionReward()
    if not VersionReward_ then
        local ok, m = pcall(require, "VersionReward")
        if ok then VersionReward_ = m end
    end
    return VersionReward_
end

--- 展示主界面门面 (标题 + 开始游戏按钮)
--- @param meta table save_meta 数据对象
--- @param onEnterGame fun() 玩家选择存档并加载/创建成功后的回调
function StartScreen.Show(meta, onEnterGame)
    -- 清理旧引用 (新 root 通过 SetRoot 的 destroyOld=true 清理)
    root_ = nil
    slotOverlay_ = nil

    onEnterGame_ = onEnterGame
    loading_ = false

    local safeInsets = UI.GetSafeAreaInsets()

    -- 版本号
    local verText = ""
    local vr = getVersionReward()
    if vr then verText = "v" .. vr.GetCurrentVersion() end

    root_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = C.pageBg,
        children = {
            -- 背景图 (绝对定位铺满)
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundImage = "start_screen_bg_20260313065945.png",
                backgroundFit = "cover",
            },
            -- 半透明遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundColor = { 10, 14, 24, 100 },
            },
            -- 前景内容 (门面)
            UI.Panel {
                width = "100%", height = "100%",
                flexDirection = "column",
                flexGrow = 1,
                alignItems = "center",
                paddingTop = safeInsets.top,
                paddingBottom = safeInsets.bottom,
                paddingLeft = safeInsets.left,
                paddingRight = safeInsets.right,
                children = {
                    -- 上部留白
                    UI.Panel { flexGrow = 3 },
                    -- 游戏标题
                    UI.Label {
                        text = Config.Title or "挂机英雄",
                        fontSize = 28, fontWeight = "bold",
                        fontColor = { 240, 230, 255, 255 },
                    },
                    -- 副标题
                    UI.Label {
                        text = "术士的挂机冒险",
                        fontSize = 13,
                        fontColor = { 180, 170, 220, 160 },
                        marginTop = 6,
                    },
                    -- 中部留白
                    UI.Panel { flexGrow = 4 },
                    -- 选择服务器按钮
                    UI.Button {
                        text = "选择服务器",
                        variant = "primary",
                        width = 200, height = 48, fontSize = 16,
                        borderRadius = 24,
                        onClick = function()
                            StartScreen._ShowServerOverlay()
                        end,
                    },
                    -- 底部留白
                    UI.Panel { flexGrow = 2 },
                    -- 版本号 (底部)
                    UI.Label {
                        text = verText,
                        fontSize = 9,
                        fontColor = { 255, 255, 255, 60 },
                        marginBottom = 8,
                    },
                },
            },
        },
    }

    UI.SetRoot(root_, true)

    -- 挂载 Toast 到当前根
    local toast = getToast()
    if toast then toast.SetRoot(root_) end
end

--- 展示错误界面 (meta 加载或迁移全部失败时)
--- @param errMsg string 错误信息
--- @param onRetry fun()|nil 重试回调 (由 main.lua 提供)
function StartScreen.ShowError(errMsg, onRetry)
    root_ = nil
    loading_ = false

    local safeInsets = UI.GetSafeAreaInsets()

    local children = {
        UI.Label {
            text = "加载失败",
            fontSize = 20, fontWeight = "bold",
            fontColor = C.errorRed,
            marginBottom = 12,
        },
        UI.Label {
            text = errMsg or "未知错误",
            fontSize = 13,
            fontColor = { 180, 185, 200, 220 },
            textAlign = "center",
            whiteSpace = "normal",
            width = "80%",
            marginBottom = 24,
        },
    }

    if onRetry then
        table.insert(children, UI.Button {
            text = "重试",
            variant = "primary",
            width = 140, height = 40,
            onClick = function()
                if loading_ then return end
                loading_ = true
                onRetry()
            end,
        })
    end

    root_ = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = C.pageBg,
        justifyContent = "center", alignItems = "center",
        paddingTop = safeInsets.top,
        paddingBottom = safeInsets.bottom,
        paddingHorizontal = 32,
        children = children,
    }

    UI.SetRoot(root_, true)
end

--- 隐藏开始界面 (由 _LoadSlot / _CreateSlot 成功后调用)
function StartScreen.Hide()
    root_ = nil
    serverOverlay_ = nil
    slotOverlay_ = nil
    loading_ = false
    -- 不清 onEnterGame_: 它在回调中使用, 之后自然失效
end

--- 是否正在显示
function StartScreen.IsVisible()
    return root_ ~= nil
end

-- ============================================================================
-- 保存模式浮层 (覆盖在游戏 UI 上, 选择槽位保存)
-- ============================================================================

---@type Widget
local saveOverlay_    = nil
local saveOverlayRoot_ = nil
local saveBusy_       = false

--- 设置 SavePicker 挂载根 (由 main.lua 在 BuildGameUI 后调用)
function StartScreen.SetSaveOverlayRoot(root)
    saveOverlayRoot_ = root
end

--- 关闭保存浮层
function StartScreen.HideSavePicker()
    if saveOverlay_ and saveOverlayRoot_ then
        saveOverlayRoot_:RemoveChild(saveOverlay_)
    end
    saveOverlay_ = nil
    saveBusy_ = false
end

--- 内嵌确认浮层 (覆盖保存二次确认)
---@type Widget|nil
local saveConfirmOverlay_ = nil

local function showSaveConfirm(parentOverlay, msg, onConfirm)
    if saveConfirmOverlay_ and parentOverlay then
        parentOverlay:RemoveChild(saveConfirmOverlay_)
    end

    local function closeConfirm()
        if saveConfirmOverlay_ and parentOverlay then
            parentOverlay:RemoveChild(saveConfirmOverlay_)
        end
        saveConfirmOverlay_ = nil
    end

    saveConfirmOverlay_ = UI.Panel {
        position = "absolute", left = 0, top = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() closeConfirm() end,
        children = {
            UI.Panel {
                width = "80%", maxWidth = 280,
                backgroundColor = { 28, 32, 48, 250 },
                borderRadius = 12, borderWidth = 1, borderColor = { 60, 70, 90, 120 },
                padding = 20, gap = 16,
                alignItems = "center",
                onClick = function() end, -- 阻止穿透
                children = {
                    UI.Label {
                        text = "保存确认",
                        fontSize = 16, fontWeight = "bold",
                        fontColor = C.title,
                    },
                    UI.Label {
                        text = msg,
                        fontSize = 13, fontColor = C.text,
                        textAlign = "center",
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12,
                        children = {
                            UI.Button {
                                text = "取消", variant = "secondary",
                                width = 100, height = 36, fontSize = 13,
                                onClick = function() closeConfirm() end,
                            },
                            UI.Button {
                                text = "确认", variant = "primary",
                                width = 100, height = 36, fontSize = 13,
                                onClick = function()
                                    closeConfirm()
                                    if onConfirm then onConfirm() end
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if parentOverlay then
        parentOverlay:AddChild(saveConfirmOverlay_)
    end
end

--- 执行保存到指定槽位
local function doSaveToSlot(SlotSave, slotId, onAfterSave)
    saveBusy_ = true
    local toast = getToast()
    if toast then toast.Show("保存中...") end
    SlotSave.CopyToSlot(slotId, function(ok, err)
        saveBusy_ = false
        if ok then
            if toast then toast.Success("已保存到存档 " .. slotId) end
            StartScreen.HideSavePicker()
            if onAfterSave then onAfterSave() end
        else
            if toast then toast.Warn("保存失败: " .. (err or "未知错误")) end
        end
    end)
end

--- 展示保存槽位选择浮层
--- @param onAfterSave? fun() 保存成功后的额外回调 (如返回主界面)
function StartScreen.ShowSavePicker(onAfterSave)
    if saveOverlay_ then StartScreen.HideSavePicker() end
    saveBusy_ = false

    local SlotSave = getSlotSave()
    local meta = SlotSave.GetMeta()
    if not meta then return end

    local activeSlot = SlotSave.GetActiveSlot()
    local slots = meta.slots or {}
    local maxSlots = SlotSave.GetMaxSlots()

    local slotCards = {}
    for i = 1, maxSlots do
        local slotData = slots[tostring(i)]
        local isActive = (i == activeSlot)
        local slotId = i

        if slotData then
            local labelParts = "存档 " .. i
            if isActive then labelParts = labelParts .. " (当前)" end
            local stageStr = "Lv." .. (slotData.level or 1) .. " 第" .. (slotData.chapter or 1) .. "章"
            local timeStr = FormatTimestamp(slotData.timestamp)

            table.insert(slotCards, UI.Panel {
                width = "100%",
                backgroundColor = isActive and { 35, 50, 75, 240 } or C.cardBg,
                borderRadius = 8,
                borderWidth = isActive and 2 or 1,
                borderColor = isActive and C.borderActive or C.border,
                marginBottom = 6,
                paddingHorizontal = 14, paddingVertical = 8,
                gap = 4,
                children = {
                    UI.Label { text = labelParts, fontSize = 13, fontWeight = "bold", fontColor = C.title },
                    UI.Label { text = stageStr .. "  " .. timeStr, fontSize = 10, fontColor = C.textDim },
                    UI.Button {
                        text = "保存到此槽位", variant = isActive and "primary" or "secondary",
                        width = "100%", height = 30, fontSize = 12,
                        marginTop = 4,
                        onClick = function()
                            if saveBusy_ then return end
                            local msg = isActive and "保存到当前存档？" or ("覆盖存档 " .. slotId .. "？\n原有数据将被替换。")
                            showSaveConfirm(saveOverlay_, msg, function()
                                doSaveToSlot(SlotSave, slotId, onAfterSave)
                            end)
                        end,
                    },
                },
            })
        else
            table.insert(slotCards, UI.Panel {
                width = "100%",
                backgroundColor = C.cardEmpty,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = C.borderEmpty,
                marginBottom = 6,
                paddingHorizontal = 14, paddingVertical = 8,
                gap = 4,
                children = {
                    UI.Label { text = "槽位 " .. i .. " (空)", fontSize = 13, fontColor = C.textDim },
                    UI.Button {
                        text = "保存到此槽位", variant = "secondary",
                        width = "100%", height = 30, fontSize = 12,
                        marginTop = 4,
                        onClick = function()
                            if saveBusy_ then return end
                            doSaveToSlot(SlotSave, slotId, onAfterSave)
                        end,
                    },
                },
            })
        end
    end

    -- 底部按钮
    local bottomBtns = {}
    if onAfterSave then
        table.insert(bottomBtns, UI.Button {
            text = "不保存，直接返回",
            width = "100%", height = 32, fontSize = 12,
            variant = "secondary",
            onClick = function()
                StartScreen.HideSavePicker()
                onAfterSave()
            end,
        })
    end
    table.insert(bottomBtns, UI.Button {
        text = "取消",
        width = "100%", height = 32, fontSize = 12,
        variant = "secondary",
        onClick = function() StartScreen.HideSavePicker() end,
    })

    saveOverlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() StartScreen.HideSavePicker() end,
        children = {
            UI.Panel {
                width = "85%", maxWidth = 340, maxHeight = "80%",
                backgroundColor = { 22, 26, 38, 250 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 60, 70, 90, 120 },
                padding = 14,
                gap = 8,
                onClick = function() end, -- 阻止穿透关闭
                children = {
                    UI.Label {
                        text = "保存到...",
                        fontSize = 16, fontWeight = "bold",
                        fontColor = C.title,
                        textAlign = "center",
                        width = "100%",
                        marginBottom = 4,
                    },
                    UI.ScrollView {
                        flexGrow = 1, flexBasis = 0,
                        width = "100%",
                        children = slotCards,
                    },
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = bottomBtns,
                    },
                },
            },
        },
    }

    if saveOverlayRoot_ then
        saveOverlayRoot_:AddChild(saveOverlay_)
    end
end

return StartScreen
