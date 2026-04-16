-- ============================================================================
-- ui/Settings.lua - 设置浮层（音乐/音效音量）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Colors = require("ui.Colors")
local RedeemSystem = require("RedeemSystem")
local TabBar = require("ui.TabBar")


---@diagnostic disable-next-line: undefined-global
local cjson = cjson
---@diagnostic disable-next-line: undefined-global
local fileSystem = fileSystem

local Settings = {}

local SETTINGS_FILE = "settings.json"
local ICON = "icon_settings_20260307145457.png"

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil
local visible_ = false

-- 兑换码弹窗
---@type Widget
local redeemOverlay_ = nil
local redeemInput_   = ""



-- 当前音量 (0~100)
local musicVol_ = 100
local sfxVol_   = 100

-- 屏幕震动模式: 2=开启, 1=减弱, 0=关闭
local shakeMode_ = 2

-- 特效等级: 1=正常, 2=减弱, 3=非常弱
local fxLevel_ = 1

-- 待机模式回调
local idleCallback_ = nil
local battleIdleCallback_ = nil

-- ============================================================================
-- 持久化
-- ============================================================================

local function LoadSettings()
    pcall(function()
        if fileSystem:FileExists(SETTINGS_FILE) then
            local file = File(SETTINGS_FILE, FILE_READ)
            if file:IsOpen() then
                local json = file:ReadString()
                file:Close()
                local ok, data = pcall(cjson.decode, json)
                if ok and data then
                    musicVol_ = data.musicVol or 100
                    sfxVol_   = data.sfxVol   or 100
                    if data.shakeMode ~= nil then
                        shakeMode_ = data.shakeMode
                    end
                    if data.fxLevel ~= nil then
                        fxLevel_ = data.fxLevel
                    end
                end
            end
        end
    end)
end

local function SaveSettings()
    pcall(function()
        local json = cjson.encode({ musicVol = musicVol_, sfxVol = sfxVol_, shakeMode = shakeMode_, fxLevel = fxLevel_ })
        local file = File(SETTINGS_FILE, FILE_WRITE)
        if file:IsOpen() then
            file:WriteString(json)
            file:Close()
        end
    end)
end

local function ApplyVolume()
    audio:SetMasterGain("Music", musicVol_ / 100)
    audio:SetMasterGain("Effect", sfxVol_ / 100)
end

-- ============================================================================
-- 初始化（启动时调用一次）
-- ============================================================================

function Settings.Init()
    LoadSettings()
    ApplyVolume()
end

function Settings.GetIcon()
    return ICON
end

-- ============================================================================
-- 浮层
-- ============================================================================

function Settings.SetOverlayRoot(root)
    overlayRoot_ = root
end

function Settings.Toggle()
    if visible_ then Settings.Hide() else Settings.Show() end
end

function Settings.Hide()
    SaveSettings()
    if overlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(overlay_)
    end
    overlay_ = nil
    visible_ = false
end

function Settings.Show()
    if visible_ then Settings.Hide() end
    visible_ = true

    overlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 180 },
        alignItems = "center", justifyContent = "center",
        onClick = function() Settings.Hide() end,
        children = {
            UI.Panel {
                width = "80%", maxWidth = 300,
                backgroundColor = { 30, 35, 50, 250 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 80, 100, 140, 120 },
                padding = 16,
                gap = 14,
                onClick = function() end, -- 阻止穿透关闭
                children = {
                    -- 标题
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", alignItems = "center", justifyContent = "center", gap = 8,
                        children = {
                            UI.Panel { width = 24, height = 24, backgroundImage = ICON, backgroundFit = "contain" },
                            UI.Label { text = "设置", fontSize = 16, fontColor = Colors.text },
                        },
                    },
                    -- 音乐音量
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "音乐音量", fontSize = 13, fontColor = Colors.text },
                                    UI.Label { id = "musicVolLabel", text = musicVol_ .. "%", fontSize = 12, fontColor = Colors.textDim },
                                },
                            },
                            UI.Slider {
                                id = "musicSlider",
                                width = "100%", height = 28,
                                min = 0, max = 100, value = musicVol_,
                                onChange = function(self, value)
                                    musicVol_ = math.floor(value)
                                    audio:SetMasterGain("Music", musicVol_ / 100)
                                    if overlay_ then
                                        local lbl = overlay_:FindById("musicVolLabel")
                                        if lbl then lbl:SetText(musicVol_ .. "%") end
                                    end
                                end,
                            },
                        },
                    },
                    -- 音效音量
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = {
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "音效音量", fontSize = 13, fontColor = Colors.text },
                                    UI.Label { id = "sfxVolLabel", text = sfxVol_ .. "%", fontSize = 12, fontColor = Colors.textDim },
                                },
                            },
                            UI.Slider {
                                id = "sfxSlider",
                                width = "100%", height = 28,
                                min = 0, max = 100, value = sfxVol_,
                                onChange = function(self, value)
                                    sfxVol_ = math.floor(value)
                                    audio:SetMasterGain("Effect", sfxVol_ / 100)
                                    if overlay_ then
                                        local lbl = overlay_:FindById("sfxVolLabel")
                                        if lbl then lbl:SetText(sfxVol_ .. "%") end
                                    end
                                end,
                            },
                        },
                    },
                    -- 屏幕震动
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = {
                            UI.Label { text = "命中震动", fontSize = 13, fontColor = Colors.text },
                            UI.Panel {
                                id = "shakeSegment",
                                width = "100%", height = 30,
                                flexDirection = "row", gap = 0,
                                borderRadius = 6, overflow = "hidden",
                                borderWidth = 1, borderColor = { 80, 100, 140, 120 },
                                children = (function()
                                    local opts = { { label = "开启", val = 2 }, { label = "减弱", val = 1 }, { label = "关闭", val = 0 } }
                                    local btns = {}
                                    for _, opt in ipairs(opts) do
                                        local isActive = (shakeMode_ == opt.val)
                                        table.insert(btns, UI.Panel {
                                            id = "shake_" .. opt.val,
                                            flexGrow = 1, height = 30,
                                            alignItems = "center", justifyContent = "center",
                                            backgroundColor = isActive and { 60, 100, 180, 230 } or { 40, 45, 60, 200 },
                                            onClick = function()
                                                shakeMode_ = opt.val
                                                -- 更新按钮视觉状态
                                                if overlay_ then
                                                    for _, o in ipairs(opts) do
                                                        local btn = overlay_:FindById("shake_" .. o.val)
                                                        local lbl = overlay_:FindById("shake_lbl_" .. o.val)
                                                        local active = (shakeMode_ == o.val)
                                                        if btn then
                                                            btn:SetStyle({ backgroundColor = active and { 60, 100, 180, 230 } or { 40, 45, 60, 200 } })
                                                        end
                                                        if lbl then
                                                            lbl:SetFontColor(active and { 255, 255, 255, 255 } or { 180, 180, 190, 200 })
                                                        end
                                                    end
                                                end
                                            end,
                                            children = {
                                                UI.Label {
                                                    id = "shake_lbl_" .. opt.val,
                                                    text = opt.label,
                                                    fontSize = 12,
                                                    fontColor = isActive and { 255, 255, 255, 255 } or { 180, 180, 190, 200 },
                                                },
                                            },
                                        })
                                    end
                                    return btns
                                end)(),
                            },
                        },
                    },
                    -- 特效等级
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = {
                            UI.Label { text = "特效等级", fontSize = 13, fontColor = Colors.text },
                            UI.Panel {
                                id = "fxSegment",
                                width = "100%", height = 30,
                                flexDirection = "row", gap = 0,
                                borderRadius = 6, overflow = "hidden",
                                borderWidth = 1, borderColor = { 80, 100, 140, 120 },
                                children = (function()
                                    local opts = { { label = "正常", val = 1 }, { label = "减弱", val = 2 }, { label = "非常弱", val = 3 } }
                                    local btns = {}
                                    for _, opt in ipairs(opts) do
                                        local isActive = (fxLevel_ == opt.val)
                                        table.insert(btns, UI.Panel {
                                            id = "fx_" .. opt.val,
                                            flexGrow = 1, height = 30,
                                            alignItems = "center", justifyContent = "center",
                                            backgroundColor = isActive and { 60, 100, 180, 230 } or { 40, 45, 60, 200 },
                                            onClick = function()
                                                fxLevel_ = opt.val
                                                print("[Settings] fxLevel set to " .. fxLevel_)
                                                if overlay_ then
                                                    for _, o in ipairs(opts) do
                                                        local btn = overlay_:FindById("fx_" .. o.val)
                                                        local lbl = overlay_:FindById("fx_lbl_" .. o.val)
                                                        local active = (fxLevel_ == o.val)
                                                        if btn then
                                                            btn:SetStyle({ backgroundColor = active and { 60, 100, 180, 230 } or { 40, 45, 60, 200 } })
                                                        end
                                                        if lbl then
                                                            lbl:SetFontColor(active and { 255, 255, 255, 255 } or { 180, 180, 190, 200 })
                                                        end
                                                    end
                                                end
                                            end,
                                            children = {
                                                UI.Label {
                                                    id = "fx_lbl_" .. opt.val,
                                                    text = opt.label,
                                                    fontSize = 12,
                                                    fontColor = isActive and { 255, 255, 255, 255 } or { 180, 180, 190, 200 },
                                                },
                                            },
                                        })
                                    end
                                    return btns
                                end)(),
                            },
                        },
                    },
                    -- 兑换码按钮
                    UI.Button {
                        text = "兑换码",
                        width = "100%", height = 32, fontSize = 12,
                        variant = "primary",
                        onClick = function()
                            Settings.ShowRedeemDialog()
                        end,
                    },
                    -- 返回主界面 (起始之地直接保存返回, 灰烬荒原弹出存档选择)
                    UI.Button {
                        text = "返回主界面",
                        width = "100%", height = 32, fontSize = 12,
                        variant = "secondary",
                        onClick = function()
                            Settings.Hide()
                            local SlotSave = require("SlotSaveSystem")
                            local activeSlot = SlotSave.GetActiveSlot()
                            if activeSlot == 0 then
                                -- 起始之地: 直接保存到 slot 0 并返回主界面
                                if SwitchSaveSlot then SwitchSaveSlot() end
                            else
                                -- 灰烬荒原: 弹出存档选择浮层
                                local StartScreen = require("ui.StartScreen")
                                StartScreen.ShowSavePicker(function()
                                    if SwitchSaveSlot then SwitchSaveSlot() end
                                end)
                            end
                        end,
                    },
                    -- 待机模式
                    UI.Panel {
                        flexDirection = "row", gap = 8, width = "100%",
                        children = {
                            UI.Button {
                                text = "全屏待机",
                                flexGrow = 1, height = 32, fontSize = 12,
                                variant = "secondary",
                                backgroundColor = { 30, 40, 55, 220 },
                                onClick = function()
                                    SaveSettings()
                                    Settings.Hide()
                                    if idleCallback_ then idleCallback_() end
                                end,
                            },
                            UI.Button {
                                text = "战斗待机",
                                flexGrow = 1, height = 32, fontSize = 12,
                                variant = "secondary",
                                backgroundColor = { 30, 40, 55, 220 },
                                onClick = function()
                                    SaveSettings()
                                    Settings.Hide()
                                    if battleIdleCallback_ then battleIdleCallback_() end
                                end,
                            },
                        },
                    },
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭",
                        width = "100%", height = 32, fontSize = 12,
                        variant = "secondary",
                        onClick = function()
                            SaveSettings()
                            Settings.Hide()
                        end,
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end
end

-- ============================================================================
-- 兑换码弹窗
-- ============================================================================

function Settings.HideRedeemDialog()
    if redeemOverlay_ and overlayRoot_ then
        overlayRoot_:RemoveChild(redeemOverlay_)
    end
    redeemOverlay_ = nil
    redeemInput_ = ""
end

function Settings.ShowRedeemDialog()
    if redeemOverlay_ then Settings.HideRedeemDialog() end
    redeemInput_ = ""

    redeemOverlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = { 0, 0, 0, 200 },
        alignItems = "center", justifyContent = "center",
        onClick = function() Settings.HideRedeemDialog() end,
        children = {
            UI.Panel {
                width = "80%", maxWidth = 280,
                backgroundColor = { 30, 35, 50, 250 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                padding = 16,
                gap = 12,
                onClick = function() end,
                children = {
                    -- 标题
                    UI.Label {
                        text = "兑换码",
                        fontSize = 16, fontColor = Colors.text,
                        textAlign = "center", width = "100%",
                    },
                    -- 输入框
                    UI.TextField {
                        id = "redeemInput",
                        placeholder = "请输入兑换码",
                        width = "100%",
                        onChange = function(_, text)
                            redeemInput_ = text or ""
                        end,
                    },
                    -- 提示文本
                    UI.Label {
                        id = "redeemMsg",
                        text = "",
                        fontSize = 12, fontColor = { 180, 180, 180, 200 },
                        textAlign = "center", width = "100%",
                        height = 16,
                    },
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", gap = 8,
                        children = {
                            UI.Button {
                                text = "兑换",
                                flexGrow = 1, height = 32, fontSize = 12,
                                variant = "primary",
                                onClick = function()
                                    local ok, msg = RedeemSystem.Redeem(redeemInput_)
                                    if redeemOverlay_ then
                                        local lbl = redeemOverlay_:FindById("redeemMsg")
                                        if lbl then
                                            lbl.fontColor = ok
                                                and { 80, 220, 120, 255 }
                                                or  { 255, 100, 80, 255 }
                                            lbl.text = msg
                                        end
                                    end
                                    -- 兑换成功后标脏所有 tab 页，确保数据刷新
                                    if ok then
                                        TabBar.MarkAllDirty()
                                    end
                                end,
                            },
                            UI.Button {
                                text = "关闭",
                                flexGrow = 1, height = 32, fontSize = 12,
                                variant = "secondary",
                                onClick = function()
                                    Settings.HideRedeemDialog()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(redeemOverlay_)
    end
end



--- 获取屏幕震动倍率 (供 BattleView 调用)
--- @return number 0.0 / 0.5 / 1.0
function Settings.GetShakeMultiplier()
    if shakeMode_ == 2 then return 1.0 end
    if shakeMode_ == 1 then return 0.5 end
    return 0.0
end

--- 获取特效等级 (供战斗系统调用)
--- @return number 1=正常, 2=减弱, 3=非常弱
function Settings.GetFxLevel()
    return fxLevel_
end

--- 设置待机模式回调 (供 main.lua 注入)
function Settings.SetIdleCallback(fn)
    idleCallback_ = fn
end

function Settings.SetBattleIdleCallback(fn)
    battleIdleCallback_ = fn
end

-- ============================================================================
return Settings
