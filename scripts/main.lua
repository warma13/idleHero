-- ============================================================================
-- main.lua - 挂机自动战斗游戏 入口
-- ============================================================================

local UI             = require("urhox-libs/UI")
local Config         = require("Config")
local GameState      = require("GameState")
local BattleSystem   = require("BattleSystem")
local BattleView     = require("BattleView")
local HUD            = require("ui.HUD")
local TabBar         = require("ui.TabBar")
local InventoryPage  = require("ui.InventoryPage")
local StatusBars     = require("ui.StatusBars")
local Leaderboard    = require("ui.Leaderboard")
local Settings       = require("ui.Settings")
local VersionReward  = require("VersionReward")
local SaveSystem     = require("SaveSystem")       -- 代理层, 转发到 SlotSaveSystem
local SlotSaveSystem = require("SlotSaveSystem")
local StartScreen    = require("ui.StartScreen")
local StageSelect    = require("ui.StageSelect")
local StageConfig    = require("StageConfig")
local Toast          = require("ui.Toast")
local FloatTip       = require("ui.FloatTip")
local EventBus       = require("EventBus")
local OfflineChest   = require("ui.OfflineChest")
local Particles      = require("battle.Particles")
local Utils          = require("Utils")
local EndlessTrial      = require("EndlessTrial")
local EndlessTrialPanel = require("ui.EndlessTrialPanel")
local TrialResultOverlay = require("ui.TrialResultOverlay")
local WorldBoss         = require("WorldBoss")
local WorldBossPanel    = require("ui.WorldBossPanel")
local ChallengePanel    = require("ui.ChallengePanel")
local WorldBossResult   = require("ui.WorldBossResult")
local BossCodex         = require("ui.BossCodex")
local ResourceDungeon        = require("ResourceDungeon")
local ResourceDungeonResult  = require("ui.ResourceDungeonResult")
local SetDungeon             = require("SetDungeon")
local SetDungeonResult       = require("ui.SetDungeonResult")
local ManaForest             = require("ManaForest")
local ManaForestResult       = require("ui.ManaForestResult")
local ManaForestPanel        = require("ui.ManaForestPanel")
local NightmareDungeon            = require("NightmareDungeon")
local NightmareDungeonResult      = require("ui.NightmareDungeonResult")
local NightmareDungeonPanel       = require("ui.NightmareDungeonPanel")
local GameMode               = require("GameMode")
local RewardPanel            = require("ui.RewardPanel")
local AbyssMode              = require("AbyssMode")
local DamageTracker     = require("DamageTracker")
local TitleSystem       = require("TitleSystem")
local DailyRewards      = require("DailyRewards")
local AdExchange        = require("ui.AdExchange")

---@diagnostic disable-next-line: undefined-global
local lobby = lobby  -- 引擎内置全局

-- ============================================================================
-- 状态
-- ============================================================================

local bgmScene_      = nil   -- 背景音乐场景（防 GC）
---@type Widget
local uiRoot_       = nil

---@type BattleView
local battleView_    = nil
local battleInited_  = false
local pendingOfflineCheck_ = false
local uiRefreshTimer_ = 0

-- 待机覆盖层
---@type Widget
local idleOverlay_   = nil
local UI_REFRESH_INTERVAL = 0.3

-- 升级检测
local prevLevel_     = 1
local levelUpCooldown_ = 0   -- 防连续升级音效叠加
local debugHud_        = nil -- F2 性能面板

-- 音效节点
local sfxNode_       = nil

-- ============================================================================
-- 待机模式
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")

---@type Label
local idleTimeLabel_ = nil
---@type Label
local idleDateLabel_ = nil
local idleSavedMusicVol_ = nil
local idleSavedSfxVol_   = nil

-- ── IdleSkyWidget: 流星 + 星星闪烁 (NanoVG) ──

---@class IdleSkyWidget : Widget
local IdleSkyWidget = Widget:Extend("IdleSkyWidget")

function IdleSkyWidget:Init(props)
    Widget.Init(self, props)
    self._time = 0
    -- 流星列表
    self._meteors = {}
    self._meteorTimer = 1.0 + math.random() * 2  -- 首颗 1~3 秒后
    -- 星星列表 (固定位置，alpha 周期闪烁)
    self._stars = {}
    self._starTimer = 0
    self._needInitStars = true  -- 首帧批量生成星星
end

function IdleSkyWidget:_spawnMeteor(w, h)
    local startX = w * (0.4 + math.random() * 0.55)  -- 右侧 40%~95%
    local startY = h * (0.02 + math.random() * 0.25)  -- 顶部 2%~27%
    local angle = math.rad(10 + math.random() * 20)   -- 10~30 度
    local speed = 300 + math.random() * 200            -- 300~500 px/s
    local life = 0.8 + math.random() * 0.8             -- 0.8~1.6 秒
    table.insert(self._meteors, {
        x = startX, y = startY,
        vx = -math.cos(angle) * speed,
        vy = math.sin(angle) * speed,
        life = life, maxLife = life,
        len = 60 + math.random() * 50,  -- 拖尾长度
    })
end

function IdleSkyWidget:_spawnStar(w, h)
    table.insert(self._stars, {
        x = math.random() * w,
        y = math.random() * h * 0.6,  -- 上方 60%
        phase = math.random() * math.pi * 2,
        period = 1.5 + math.random() * 2.5,  -- 1.5~4 秒闪烁周期
        size = 2.5 + math.random() * 2.5,    -- 2.5~5.0 px
        ttl = 6 + math.random() * 10,  -- 存活 6~16 秒
    })
end

function IdleSkyWidget:IsStateful()
    return true
end

function IdleSkyWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    -- 用引擎时间计算 dt（os.clock 在 WASM 下不可靠）
    local now = GetTime():GetElapsedTime()
    local dt = 0
    if self._lastClock then
        dt = math.min(now - self._lastClock, 0.1)
    end
    self._lastClock = now
    self._time = self._time + dt

    -- ── 首帧批量生成星星 ──
    if self._needInitStars and l.w > 0 and l.h > 0 then
        self._needInitStars = false
        for _ = 1, 12 do
            self:_spawnStar(l.w, l.h)
        end
    end

    -- ── 星星闪烁 ──
    self._starTimer = self._starTimer - dt
    if self._starTimer <= 0 then
        self._starTimer = 0.8 + math.random() * 1.5
        if #self._stars < 25 then
            self:_spawnStar(l.w, l.h)
        end
    end
    for i = #self._stars, 1, -1 do
        local s = self._stars[i]
        s.ttl = s.ttl - dt
        if s.ttl <= 0 then
            table.remove(self._stars, i)
        else
            local alpha = (math.sin(self._time * math.pi * 2 / s.period + s.phase) * 0.5 + 0.5)
            alpha = 0.3 + alpha * 0.7  -- 最低 30% 亮度，避免完全消失
            -- 淡入淡出
            if s.ttl < 1.0 then alpha = alpha * s.ttl end
            local a = math.floor(alpha * 255)
            -- 外发光
            nvgBeginPath(nvg)
            nvgCircle(nvg, l.x + s.x, l.y + s.y, s.size * 2.0)
            nvgFillColor(nvg, nvgRGBA(200, 200, 255, math.floor(a * 0.25)))
            nvgFill(nvg)
            -- 内核
            nvgBeginPath(nvg)
            nvgCircle(nvg, l.x + s.x, l.y + s.y, s.size)
            nvgFillColor(nvg, nvgRGBA(230, 225, 255, a))
            nvgFill(nvg)
        end
    end

    -- ── 流星 ──
    self._meteorTimer = self._meteorTimer - dt
    if self._meteorTimer <= 0 then
        self._meteorTimer = 4 + math.random() * 8  -- 4~12 秒间隔
        self:_spawnMeteor(l.w, l.h)
    end
    for i = #self._meteors, 1, -1 do
        local m = self._meteors[i]
        m.life = m.life - dt
        if m.life <= 0 then
            table.remove(self._meteors, i)
        else
            m.x = m.x + m.vx * dt
            m.y = m.y + m.vy * dt
            local progress = 1.0 - m.life / m.maxLife
            local headAlpha = math.floor((1.0 - progress * 0.3) * 255)
            local tailAlpha = 0
            -- 拖尾方向 (反向)
            local speed = math.sqrt(m.vx * m.vx + m.vy * m.vy)
            local nx, ny = -m.vx / speed, -m.vy / speed
            local tx, ty = l.x + m.x + nx * m.len, l.y + m.y + ny * m.len

            -- 外发光拖尾 (粗)
            local glowPaint = nvgLinearGradient(nvg,
                l.x + m.x, l.y + m.y, tx, ty,
                nvgRGBA(200, 200, 255, math.floor(headAlpha * 0.3)),
                nvgRGBA(150, 140, 220, 0))
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, l.x + m.x, l.y + m.y)
            nvgLineTo(nvg, tx, ty)
            nvgStrokeWidth(nvg, 6.0)
            nvgStrokePaint(nvg, glowPaint)
            nvgStroke(nvg)

            -- 核心拖尾 (细)
            local paint = nvgLinearGradient(nvg,
                l.x + m.x, l.y + m.y, tx, ty,
                nvgRGBA(255, 255, 255, headAlpha),
                nvgRGBA(180, 170, 255, tailAlpha))
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, l.x + m.x, l.y + m.y)
            nvgLineTo(nvg, tx, ty)
            nvgStrokeWidth(nvg, 2.5)
            nvgStrokePaint(nvg, paint)
            nvgStroke(nvg)

            -- 头部亮点
            nvgBeginPath(nvg)
            nvgCircle(nvg, l.x + m.x, l.y + m.y, 4.0)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, headAlpha))
            nvgFill(nvg)
        end
    end
end

-- ── 覆盖层管理 ──

function ShowIdleOverlay()
    if idleOverlay_ then return end
    if not uiRoot_ then return end

    -- 静音：保存当前音量，设为 0
    idleSavedMusicVol_ = audio:GetMasterGain("Music")
    idleSavedSfxVol_   = audio:GetMasterGain("Effect")
    audio:SetMasterGain("Music", 0)
    audio:SetMasterGain("Effect", 0)

    local t = os.date("*t")
    local timeStr = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
    local dateStr = string.format("%d年%d月%d日", t.year, t.month, t.day)

    idleTimeLabel_ = UI.Label {
        text = timeStr, fontSize = 42,
        fontColor = { 210, 200, 245, 235 },
    }
    idleDateLabel_ = UI.Label {
        text = dateStr, fontSize = 14,
        fontColor = { 160, 150, 200, 180 },
        marginTop = 4,
    }

    idleOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundImage = "idle_bg_20260310191041.png",
        backgroundFit = "cover",
        justifyContent = "center", alignItems = "center",
        onClick = function() end,
        children = {
            -- 流星 + 星星动画层 (全屏 NanoVG)
            IdleSkyWidget {
                position = "absolute",
                left = 0, top = 0, right = 0, bottom = 0,
                pointerEvents = "none",
            },
            -- 左上角恢复按钮
            UI.Panel {
                position = "absolute",
                left = 12, top = 12,
                height = 32,
                flexDirection = "row", alignItems = "center", gap = 5,
                paddingHorizontal = 14,
                backgroundColor = { 50, 55, 75, 220 },
                borderRadius = 8,
                borderWidth = 1, borderColor = { 100, 130, 200, 150 },
                onClick = function()
                    BattleView.SetIdleMode(false)
                    CloseIdleOverlay()
                end,
                children = {
                    UI.Label { text = "恢复", fontSize = 14, fontColor = { 180, 200, 255, 240 } },
                },
            },
            -- 中央信息
            UI.Panel {
                alignItems = "center",
                children = {
                    idleTimeLabel_,
                    idleDateLabel_,
                    UI.Label {
                        text = "战斗进行中...",
                        fontSize = 12,
                        fontColor = { 140, 130, 180, 140 },
                        marginTop = 16,
                    },
                },
            },
        },
    }
    uiRoot_:AddChild(idleOverlay_)
end

function CloseIdleOverlay()
    if idleOverlay_ then
        idleOverlay_:Destroy()
        idleOverlay_ = nil
    end
    idleTimeLabel_ = nil
    idleDateLabel_ = nil
    -- 恢复音量
    if idleSavedMusicVol_ then
        audio:SetMasterGain("Music", idleSavedMusicVol_)
        idleSavedMusicVol_ = nil
    end
    if idleSavedSfxVol_ then
        audio:SetMasterGain("Effect", idleSavedSfxVol_)
        idleSavedSfxVol_ = nil
    end
end

function RefreshIdleClock()
    if not idleTimeLabel_ then return end
    local t = os.date("*t")
    idleTimeLabel_:SetText(string.format("%02d:%02d:%02d", t.hour, t.min, t.sec))
    idleDateLabel_:SetText(string.format("%d年%d月%d日", t.year, t.month, t.day))
end

-- ============================================================================
-- 生命周期
-- ============================================================================

-- ============================================================================
-- 构建游戏主界面 (由 StartScreen 选档成功后回调)
-- ============================================================================

local function BuildGameUI()
    print("[Main] Building game UI...")

    -- 加载存档后校验点数，异常则 Toast 提醒
    if GameState.pointsValidationMsg then
        Toast.Warn(GameState.pointsValidationMsg)
        GameState.pointsValidationMsg = nil
    end
    -- 存档迁移结果通知
    if GameState.migrationMsg then
        Toast.Show(GameState.migrationMsg)
        GameState.migrationMsg = nil
    end

    prevLevel_ = GameState.player.level

    -- 称号系统初始化 (存档加载后, 根据 userId 发放称号)
    TitleSystem.Init()

    -- 构建 UI 树
    battleView_ = BattleView {
        id = "battleView",
        flexGrow = 1, flexBasis = 0, width = "100%",
        battleSystem = BattleSystem,
    }

    -- 功能快捷栏 (绝对定位, 浮在 battleView 上方)
    local ICON_SZ = 29
    local ROW_H = 42    -- 每行高度
    local BTN_FONT = 14
    local LABEL_COLOR = { 220, 220, 220, 200 }
    local BTN_BG = { 20, 24, 36, 160 }      -- 按钮半透明背景
    local BTN_RAD = 8                        -- 按钮圆角
    local BTN_PH = 8                         -- 按钮水平内边距
    local BTN_PV = 4                         -- 按钮垂直内边距
    local quickBar = UI.Panel {
        id = "quickBar",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = ROW_H,
        flexDirection = "row", alignItems = "center",
        paddingHorizontal = 8, gap = 4,
        children = {
            -- 当前章节显示
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = function() StageSelect.Toggle() end,
                children = {
                    UI.Panel { width = ICON_SZ, height = ICON_SZ, backgroundImage = "book_icon_20260307140038.png", backgroundFit = "contain" },
                    UI.Label { id = "quickbar_chapter_label", text = "章节", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
            -- 排行榜
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = Utils.Debounce(function() Leaderboard.Toggle() end, 0.3),
                children = {
                    UI.Panel { width = ICON_SZ, height = ICON_SZ, backgroundImage = Config.LEADERBOARD_ICON, backgroundFit = "contain" },
                    UI.Label { text = "排行", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
            -- 广告兑换
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = Utils.Debounce(function() AdExchange.Toggle() end, 0.3),
                children = {
                    UI.Panel { width = ICON_SZ, height = ICON_SZ, backgroundImage = AdExchange.GetIcon(), backgroundFit = "contain" },
                    UI.Label { text = "兑换", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
        },
    }

    -- 第三行：试炼 / 世界Boss / 切换存档 + 药水buff (绝对定位)
    local bossCfg = WorldBoss.GetCurrentBoss()
    local quickBuffsBar = UI.Panel {
        id = "quickBuffsBar",
        position = "absolute", top = ROW_H, left = 0,
        width = "100%", height = ROW_H,
        flexDirection = "row", alignItems = "center", justifyContent = "flex-start", gap = 4,
        paddingHorizontal = 8,
        children = {
            -- 挑战（无尽试炼 + 世界Boss）
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = Utils.Debounce(function()
                    if not GameMode.IsAnyActive() or GameMode.Is("abyss") then
                        ChallengePanel.Toggle()
                    end
                end, 0.3),
                children = {
                    UI.Panel { width = ICON_SZ, height = ICON_SZ, backgroundImage = "icon_trial_tower_20260311105357.png", backgroundFit = "contain" },
                    UI.Label { text = "挑战", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
            -- 魔力之森（独立入口）
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = Utils.Debounce(function()
                    if not GameMode.IsAnyActive() or GameMode.Is("abyss") then
                        ManaForestPanel.Toggle()
                    end
                end, 0.3),
                children = {
                    UI.Label { text = "魔力之森", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
            -- 噩梦地牢（暂时隐藏）
            -- UI.Panel {
            --     flexDirection = "row", alignItems = "center", gap = 2,
            --     backgroundColor = BTN_BG, borderRadius = BTN_RAD,
            --     paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
            --     onClick = Utils.Debounce(function()
            --         if not GameMode.IsAnyActive() or GameMode.Is("abyss") then
            --             NightmareDungeonPanel.Toggle()
            --         end
            --     end, 0.3),
            --     children = {
            --         UI.Label { text = "噩梦地牢", fontSize = BTN_FONT, color = { 200, 140, 255, 240 } },
            --     },
            -- },
            -- 退出副本按钮（仅副本模式下可见）
            UI.Panel {
                id = "btn_exit_dungeon",
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = { 160, 40, 40, 200 }, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                width = 0, overflow = "hidden",
                onClick = Utils.Debounce(function()
                    if GameMode.IsAnyActive() and not GameMode.Is("abyss") then
                        GameMode.SwitchTo(nil)
                    end
                end, 0.3),
                children = {
                    UI.Label { text = "退出", fontSize = BTN_FONT, color = { 255, 200, 200, 255 } },
                },
            },
            -- 设置
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = Utils.Debounce(function() Settings.Toggle() end, 0.3),
                children = {
                    UI.Panel { width = ICON_SZ, height = ICON_SZ, backgroundImage = Settings.GetIcon(), backgroundFit = "contain" },
                    UI.Label { text = "设置", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
            -- 保存
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2,
                backgroundColor = BTN_BG, borderRadius = BTN_RAD,
                paddingHorizontal = BTN_PH, paddingVertical = BTN_PV,
                onClick = Utils.Debounce(function()
                    local activeSlot = SlotSaveSystem.GetActiveSlot()
                    if activeSlot == 0 then
                        -- 起始之地: 直接保存云端
                        SlotSaveSystem.SaveNow()
                        Toast.Success("已保存")
                    else
                        -- 灰烬荒原: 弹出存档选择
                        StartScreen.ShowSavePicker(function()
                            if SwitchSaveSlot then SwitchSaveSlot() end
                        end)
                    end
                end, 0.5),
                children = {
                    UI.Label { text = "保存", fontSize = BTN_FONT, color = LABEL_COLOR },
                },
            },
            -- 分隔符
            UI.Panel { width = 1, height = 26, backgroundColor = { 100, 100, 100, 60 } },
            -- 药水buff状态 (文字模式)
            UI.Panel {
                id = "quickBuffs",
                flexDirection = "row", alignItems = "center", gap = 4,
            },
        },
    }

    -- battleArea: battleView + 浮动图标栏 (quickBar 在此容器内, 与 overlay 操作隔离)
    local battleArea = UI.Panel {
        id = "battleArea",
        flexGrow = 1, flexBasis = 0, width = "100%",
        children = {
            battleView_,
            -- 绝对定位浮在 battleView 上方 (相对 battleArea 定位)
            quickBar,
            quickBuffsBar,
        },
    }

    -- 刘海屏安全区域适配 (方案B: 分层偏移, 战场保持全屏)
    local safeInsets = UI.GetSafeAreaInsets()

    uiRoot_ = UI.Panel {
        id = "gameRoot",
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = { 18, 22, 30, 255 },
        paddingTop = safeInsets.top,
        paddingBottom = safeInsets.bottom,
        paddingLeft = safeInsets.left,
        paddingRight = safeInsets.right,
        children = {
            HUD.Create(),
            battleArea,
            -- 当前关卡信息行
            UI.Panel {
                id = "stageInfoBar",
                width = "100%", height = 20,
                flexDirection = "row", alignItems = "center", justifyContent = "center",
                backgroundColor = { 14, 18, 28, 250 },
                onClick = function() StageSelect.Toggle() end,
                children = {
                    UI.Label { id = "stage_info_text", text = "", fontSize = 10, fontColor = { 255, 220, 150, 200 }, textAlign = "center" },
                },
            },
            StatusBars.Create(),
            TabBar.Create(),
            -- 左下角版本号 (绝对定位)
            UI.Label {
                text = "v" .. VersionReward.GetCurrentVersion(),
                fontSize = 9,
                fontColor = { 255, 255, 255, 80 },
                position = "absolute",
                bottom = 2,
                left = 4,
            },
        }
    }
    UI.SetRoot(uiRoot_, true)

    -- 存档加载后强制刷新当前活跃标签页 (角色页), 确保首帧显示正确数据
    TabBar.ForceRefreshActive()

    -- overlay 挂载到 uiRoot (quickBar 在 battleArea 内, 不受影响)
    InventoryPage.SetOverlayRoot(uiRoot_)
    Leaderboard.SetOverlayRoot(uiRoot_)
    AdExchange.SetOverlayRoot(uiRoot_)
    Settings.SetOverlayRoot(uiRoot_)
    Settings.Init()
    Settings.SetIdleCallback(function()
        BattleView.SetIdleMode(true)
        ShowIdleOverlay()
    end)
    Settings.SetBattleIdleCallback(function()
        BattleView.SetBattleIdleMode(not BattleView.IsBattleIdleMode())
    end)
    VersionReward.SetOverlayRoot(uiRoot_)
    DailyRewards.SetOverlayRoot(uiRoot_)
    RewardPanel.SetOverlayRoot(uiRoot_)
    Toast.SetRoot(uiRoot_)
    FloatTip.SetRoot(uiRoot_)
    EventBus.On("loot:rare_item", function(name)
        Toast.Success("获得稀有道具: " .. name)
    end)

    OfflineChest.SetOverlayRoot(uiRoot_)
    -- 延迟到战斗初始化完成后再弹出，避免背后是空白画面
    pendingOfflineCheck_ = true

    -- 统一模式切换过渡回调 (只注册一次)
    GameMode.SetTransitionCallback(function()
        BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
        RefreshStageInfo()
    end)

    -- 挑战面板（统一入口：无尽试炼 + 世界Boss + 折光矿脉）
    ChallengePanel.SetOverlayRoot(uiRoot_)
    ChallengePanel.SetTrialStartCallback(function()
        GameMode.SwitchTo("endlessTrial")
    end)
    ChallengePanel.SetBossStartCallback(function()
        GameMode.SwitchTo("worldBoss")
    end)

    TrialResultOverlay.SetOverlayRoot(uiRoot_)
    TrialResultOverlay.SetCloseCallback(function()
        GameMode.SwitchTo(nil)
    end)

    WorldBossResult.SetOverlayRoot(uiRoot_)
    BossCodex.SetOverlayRoot(uiRoot_)
    StartScreen.SetSaveOverlayRoot(uiRoot_)
    StageSelect.SetOverlayRoot(uiRoot_)
    StageSelect.SetJumpCallback(function(chapter, stage)
        -- 判断是否为回刷（跳回已通关的关卡）
        local maxCh = GameState.records and GameState.records.maxChapter or 1
        local maxSt = GameState.records and GameState.records.maxStage or 1
        local isReplay = (chapter < maxCh) or (chapter == maxCh and stage < maxSt)
        GameState.stage.chapter = chapter
        GameState.stage.stage = stage
        BattleSystem.Init(BattleSystem.areaW, BattleSystem.areaH)
        -- Init 会清除 isReplay，所以必须在 Init 之后设置
        BattleSystem.isReplay = isReplay
        if isReplay then
            print("[StageSelect] Replay mode: jumping to cleared stage " .. chapter .. "-" .. stage)
        end
        RefreshStageInfo()
        SlotSaveSystem.SaveNow()
    end)

    WorldBossResult.SetCloseCallback(function()
        GameMode.SwitchTo(nil)
    end)

    ChallengePanel.SetMineStartCallback(function()
        GameMode.SwitchTo("resourceDungeon")
    end)
    ResourceDungeonResult.SetOverlayRoot(uiRoot_)
    ResourceDungeonResult.SetCloseCallback(function()
        GameMode.SwitchTo(nil)
    end)

    ChallengePanel.SetSetDungeonStartCallback(function()
        GameMode.SwitchTo("setDungeon")
    end)
    SetDungeonResult.SetOverlayRoot(uiRoot_)
    SetDungeonResult.SetCloseCallback(function()
        GameMode.SwitchTo(nil)
    end)

    ManaForestPanel.SetOverlayRoot(uiRoot_)
    ManaForestPanel.SetStartCallback(function()
        GameMode.SwitchTo("manaForest")
    end)
    ManaForestResult.SetOverlayRoot(uiRoot_)
    ManaForestResult.SetCloseCallback(function()
        GameMode.SwitchTo(nil)
    end)

    NightmareDungeonPanel.SetOverlayRoot(uiRoot_)
    NightmareDungeonPanel.SetStartCallback(function()
        GameMode.SwitchTo("nightmareDungeon")
    end)
    NightmareDungeonResult.SetOverlayRoot(uiRoot_)
    NightmareDungeonResult.SetCloseCallback(function()
        GameMode.SwitchTo(nil)
    end)

    -- 重置战斗初始化标记 (切换存档时需要重新初始化)
    battleInited_ = false

    print("[Main] Game UI built, slot=" .. SlotSaveSystem.GetActiveSlot())
end

-- ============================================================================
-- 拆除游戏界面 (BuildGameUI 的逆操作)
-- ============================================================================

local function TeardownGameUI()
    print("[Main] Tearing down game UI...")

    -- 1. 关闭所有可能打开的浮层/弹窗
    CloseIdleOverlay()
    Leaderboard.Hide()
    Settings.Hide()
    StageSelect.Close()
    VersionReward.Hide()
    OfflineChest.Close()
    ChallengePanel.Close()
    EndlessTrialPanel.Close()
    TrialResultOverlay.Close()
    WorldBossPanel.Close()
    WorldBossResult.Close()
    BossCodex.Close()
    ResourceDungeonResult.Close()
    SetDungeonResult.Close()
    ManaForestPanel.Close()
    ManaForestResult.Close()
    NightmareDungeonPanel.Close()
    NightmareDungeonResult.Close()
    AdExchange.Close()

    -- 2. 退出特殊模式 (统一走适配器 OnExit)
    GameMode.ExitCurrent()

    -- 3. 重置 BattleView 待机模式
    BattleView.SetIdleMode(false)
    BattleView.SetBattleIdleMode(false)

    -- 4. 重置 DPS 追踪
    DamageTracker.Reset()

    -- 5. 置空战斗状态 — 让 HandleUpdate 的 `if not battleView_` 守卫生效
    battleView_   = nil
    battleInited_ = false
    uiRoot_       = nil
    idleOverlay_  = nil
    idleTimeLabel_ = nil
    idleDateLabel_ = nil
    uiRefreshTimer_ = 0
    prevLevel_     = 1
    levelUpCooldown_ = 0

    -- 6. 重置 GameState (为新存档做准备)
    GameState.Init()

    print("[Main] Game UI torn down")
end

-- ============================================================================
-- 切换存档 (保存当前 → 拆除游戏 → 返回开始界面)
-- ============================================================================

function SwitchSaveSlot()
    Toast.Show("保存存档中...")
    SlotSaveSystem.SaveAndUnload(function()
        -- 先拆除游戏界面，停止所有战斗逻辑
        TeardownGameUI()
        local meta = SlotSaveSystem.GetMeta()
        if meta then
            StartScreen.Show(meta, BuildGameUI)
        end
    end)
end

-- ============================================================================
-- SlotSaveSystem 初始化流程
-- ============================================================================

local function InitSlotSaveSystem()
    SlotSaveSystem.Init(function(meta, isNewPlayer, err)
        if err then
            -- 全部失败: 展示错误界面
            print("[Main] SlotSaveSystem init error: " .. tostring(err))
            StartScreen.ShowError(err, function()
                -- 重试: 重新初始化
                InitSlotSaveSystem()
            end)
            return
        end

        -- 成功: 展示开始界面
        print("[Main] Meta ready, showing start screen...")
        StartScreen.Show(meta, BuildGameUI)
    end)
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = Config.Title

    -- PC 端窗口适配: 限制窗口高度不超过屏幕 90%, 保持 9:16 竖屏比例
    local platform = GetPlatform()
    if platform == "Windows" or platform == "Linux" or platform == "Mac" then
        local monitor = graphics:GetCurrentMonitor()
        local desktop = graphics:GetDesktopResolution(monitor)
        local maxH = math.floor(desktop.y * 0.9)
        local curW = graphics.width
        local curH = graphics.height
        if curH > maxH then
            local newH = maxH
            local newW = math.floor(newH * 9 / 16)
            graphics:SetMode(newW, newH)
        end
    end

    UI.Init({
        fonts = { { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } } },
        scale = UI.Scale.DEFAULT,
    })

    GameState.Init()

    -- 打印当前用户ID（调试用）+ 封禁检查
    local myUserId_ = nil
    pcall(function() myUserId_ = lobby:GetMyUserId() end)
    if myUserId_ then
        print("[Main] 当前用户ID: " .. tostring(myUserId_))
        -- 封禁检查
        local bannedSet = {}
        for _, bid in ipairs(Config.BANNED_USER_IDS or {}) do bannedSet[bid] = true end
        if bannedSet[myUserId_] then
            print("[Main] 用户已被封禁: " .. tostring(myUserId_))
            uiRoot_ = UI.CreateRoot()
            uiRoot_:AddChild(UI.Panel {
                width = "100%", height = "100%",
                backgroundColor = { 10, 5, 20, 255 },
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label { text = "账号已被封禁", fontSize = 22, color = { 220, 60, 60, 255 }, marginBottom = 12 },
                    UI.Label { text = "由于违规行为，该账号已被永久封禁。", fontSize = 13, color = { 160, 160, 180, 200 } },
                },
            })
            return  -- 阻止后续初始化
        end
    end

    -- 音效节点（复用，避免每次新建）
    sfxNode_ = Scene():CreateChild("SFX")

    -- 背景音乐
    local bgmSound = cache:GetResource("Sound", "audio/music_1772788413520.ogg")
    if bgmSound then
        bgmSound.looped = true
        bgmScene_ = Scene()
        local bgmNode = bgmScene_:CreateChild("BGM")
        local bgmSrc  = bgmNode:CreateComponent("SoundSource")
        bgmSrc.soundType = SOUND_MUSIC
        bgmSrc.gain = 0.35
        bgmSrc:Play(bgmSound)
    end

    -- 初始化多槽位存档系统 → 展示开始界面 → 选档后构建游戏 UI
    InitSlotSaveSystem()

    -- DebugHud: F2 切换性能面板
    debugHud_ = engine:CreateDebugHud()
    debugHud_:SetDefaultStyle(cache:GetResource("XMLFile", "UI/DefaultStyle.xml"))
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    SubscribeToEvent("Update", "HandleUpdate")
    print("=== " .. Config.Title .. " Started ===")
end

function Stop()
    UI.Shutdown()
end

-- ============================================================================
-- DebugHud 切换
-- ============================================================================

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_F2 then
        debugHud_:ToggleAll()
    end
end

-- ============================================================================
-- 主循环
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- SlotSaveSystem 需要每帧 Update (即使在 StartScreen 期间, 处理延迟重试)
    SlotSaveSystem.Update(dt)
    -- 同步代理层字段
    SaveSystem.SyncFields()

    -- StartScreen 期间: 游戏 UI 尚未构建, 只运行存档系统
    if not battleView_ then
        return
    end

    -- 延迟初始化 BattleSystem（等待布局计算完毕）
    if not battleInited_ then
        local layout = battleView_:GetAbsoluteLayout()
        if layout and layout.w > 0 and layout.h > 0 then
            BattleSystem.Init(layout.w, layout.h)
            battleInited_ = true
        else
            return
        end
    end

    local layout = battleView_:GetAbsoluteLayout()
    if layout and layout.w > 0 then
        BattleSystem.SetAreaSize(layout.w, layout.h)
    end

    GameState.UpdatePotionBuffs(dt)
    BattleSystem.Update(dt)

    -- GameMode adapter OnUpdate 调度
    local activeMode = GameMode.GetActive()
    if activeMode and activeMode.OnUpdate then
        activeMode:OnUpdate(dt, BattleSystem)
    end

    Toast.Update(dt)
    FloatTip.Update(dt)
    OfflineChest.Update(dt)

    -- 延迟离线奖励检查：等战斗已运行一帧后再弹出，背后有实际画面
    if pendingOfflineCheck_ then
        pendingOfflineCheck_ = false
        OfflineChest.Check()
    end

    -- 无尽试炼结算检测
    if BattleSystem.trialEnded and not TrialResultOverlay.IsOpen() then
        TrialResultOverlay.Show()
    end

    -- 世界Boss结算检测 (延迟展示掉落物后再弹面板)
    if BattleSystem.worldBossEndDelay then
        BattleSystem.worldBossEndDelay = BattleSystem.worldBossEndDelay - dt
        if BattleSystem.worldBossEndDelay <= 0 then
            BattleSystem.worldBossEndDelay = nil
            BattleSystem.worldBossEnded = true
        end
    end
    if BattleSystem.worldBossEnded and not WorldBossResult.IsOpen() then
        WorldBossResult.Show()
        BattleSystem.worldBossEnded = false
    end

    -- 折光矿脉结算检测
    if BattleSystem.resourceDungeonEnded and not ResourceDungeonResult.IsOpen() then
        ResourceDungeonResult.Show(ResourceDungeon.fightResult)
        BattleSystem.resourceDungeonEnded = false
    end
    -- 折光矿脉连续挑战倒计时
    ResourceDungeonResult.Update(dt)

    -- 套装秘境结算检测
    if BattleSystem.setDungeonEnded and not SetDungeonResult.IsOpen() then
        SetDungeonResult.Show(SetDungeon.fightResult)
        BattleSystem.setDungeonEnded = false
    end

    -- 魔力之森结算检测
    if BattleSystem.manaForestEnded and not ManaForestResult.IsOpen() then
        ManaForestResult.Show(ManaForest.fightResult)
        BattleSystem.manaForestEnded = false
    end

    -- 噩梦地牢结算检测
    if BattleSystem.nightmareDungeonEnded and not NightmareDungeonResult.IsOpen() then
        NightmareDungeonResult.Show(NightmareDungeon.fightResult)
        BattleSystem.nightmareDungeonEnded = false
    end

    -- 升级检测: 等级变化时触发音效 + 粒子
    levelUpCooldown_ = math.max(0, levelUpCooldown_ - dt)
    local curLevel = GameState.player.level
    if curLevel > prevLevel_ then
        prevLevel_ = curLevel
        if levelUpCooldown_ <= 0 then
            levelUpCooldown_ = 0.5  -- 0.5秒内连续升级只播一次
            PlaySFX("audio/sfx/sfx_levelup.ogg")
            -- 在玩家位置生成粒子
            local pb = BattleSystem.playerBattle
            if pb and BattleSystem.particles then
                Particles.SpawnLevelUp(BattleSystem.particles, pb.x, pb.y)
            end
        end
    end

    -- 定时刷新 UI
    uiRefreshTimer_ = uiRefreshTimer_ + dt
    if uiRefreshTimer_ >= UI_REFRESH_INTERVAL then
        uiRefreshTimer_ = 0
        HUD.Refresh(uiRoot_)
        StatusBars.Refresh(uiRoot_)
        TabBar.RefreshActive()
        GameState.UpdateRecords()
        RefreshQuickBuffs()
        RefreshStageInfo()
        WorldBossPanel.RefreshTimer()
        RefreshIdleClock()
        -- 领取后移除红点
        if not VersionReward.HasUnclaimedReward() then
            local dot = uiRoot_:FindById("versionRewardDot")
            if dot then
                local btn = uiRoot_:FindById("versionRewardBtn")
                if btn then btn:RemoveChild(dot) end
            end
        end

    end
end

-- ============================================================================
-- 关卡信息刷新
-- ============================================================================

function RefreshStageInfo()
    if not uiRoot_ then return end
    local label = uiRoot_:FindById("stage_info_text")
    if not label then return end

    -- 特殊模式: 通过 GameMode 适配器获取显示名称
    local mode = GameMode.GetActive()
    local inDungeon = mode and not GameMode.Is("abyss")
    if mode and mode.GetDisplayName then
        local displayName = mode:GetDisplayName()
        label:SetText(displayName)
    else
        local gs = GameState.stage
        local stageCfg = StageConfig.GetStage(gs.chapter, gs.stage)
        local stageName = stageCfg and stageCfg.name or ""
        label:SetText(gs.chapter .. "-" .. gs.stage .. " " .. stageName)
    end

    -- 退出按钮: 副本模式下显示, 主线/深渊隐藏
    local exitBtn = uiRoot_:FindById("btn_exit_dungeon")
    if exitBtn then
        if inDungeon then
            exitBtn:SetStyle({ width = "auto", overflow = "visible", paddingHorizontal = 8, paddingVertical = 4 })
        else
            exitBtn:SetStyle({ width = 0, overflow = "hidden", paddingHorizontal = 0, paddingVertical = 0 })
        end
    end
end

-- ============================================================================
-- 快捷栏药水buff状态刷新
-- ============================================================================

-- POTION_SHORT 已废弃，药水buff改为图标显示

-- ============================================================================
-- 音效播放 (支持 fxLevel 冷却合并)
-- ============================================================================

local sfxCooldowns_ = {}  -- { [path] = lastPlayTime }

function PlaySFX(path, gain)
    if not sfxNode_ then return end

    -- 特效等级: 命中类音效冷却合并
    local fxLv = Settings.GetFxLevel()
    if fxLv >= 2 then
        local cooldown = fxLv == 3 and 0.5 or 0.3
        local now = time:GetElapsedTime()
        local last = sfxCooldowns_[path] or 0
        if now - last < cooldown then return end
        sfxCooldowns_[path] = now
    end

    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    local src = sfxNode_:CreateComponent("SoundSource")
    src.soundType = SOUND_EFFECT
    src.gain = gain or 0.5
    src.autoRemoveMode = REMOVE_COMPONENT
    src:Play(sound)
end

-- ============================================================================
-- 快捷栏药水buff状态刷新
-- ============================================================================

function RefreshQuickBuffs()
    if not uiRoot_ then return end
    local panel = uiRoot_:FindById("quickBuffs")
    if not panel then return end

    panel:ClearChildren()

    for _, pt in ipairs(Config.POTION_TYPES) do
        local timer = GameState.GetPotionTimer(pt.id)
        if timer > 0 then
            local c = pt.color or { 180, 220, 255 }
            panel:AddChild(UI.Panel {
                backgroundColor = { c[1], c[2], c[3], 40 },
                borderRadius = 4,
                paddingHorizontal = 5, paddingVertical = 2,
                children = {
                    UI.Label {
                        text = pt.name,
                        fontSize = 10,
                        color = { c[1], c[2], c[3], 220 },
                    },
                },
            })
        end
    end
end
