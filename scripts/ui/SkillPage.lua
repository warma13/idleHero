-- ============================================================================
-- ui/SkillPage.lua - D4式技能树面板 (v4.0)
-- 垂直分支树布局 + 增强卫星 + 装备槽 + 关键被动选择
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local SkillTreeConfig = require("SkillTreeConfig")
local Config = require("Config")
local Colors = require("ui.Colors")
local Toast = require("ui.Toast")
local Utils = require("Utils")
local SaveSystem = require("SaveSystem")
local SkillTreeCanvas = require("ui.SkillTreeCanvas")

local SkillPage = {}
local resetOverlay_ = nil
local downgradeOverlay_ = nil
local skipDowngradeConfirm_ = false
local RequestDowngrade  -- 前向声明

-- ============================================================================
-- 元素颜色 (从 SkillTreeConfig.ELEMENTS 获取)
-- ============================================================================

local ELEM_COLORS = {}
for _, e in ipairs(SkillTreeConfig.ELEMENTS) do
    ELEM_COLORS[e.id] = e.color
end
ELEM_COLORS["none"] = { 180, 180, 180 }

--- 获取技能的元素颜色
local function GetSkillColor(skill)
    return ELEM_COLORS[skill.element or "none"] or ELEM_COLORS["none"]
end

-- ============================================================================
-- 布局常量 (保留 UI chrome 区域用)
-- ============================================================================

local LOADOUT_H = 42
local SLOT_SIZE = 32
local SLOT_GAP  = 6
local INFO_H    = 60

-- ============================================================================
-- SkillPage 主模块
-- ============================================================================

---@type Widget
local page_ = nil
---@type Widget
local treeWidget_ = nil
local selectedSkill_ = nil

function SkillPage.Create()
    treeWidget_ = SkillTreeCanvas {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        onSelect = function(skill)
            selectedSkill_ = skill
            SkillPage.RefreshInfo()
        end,
    }

    page_ = UI.Panel {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        flexDirection = "column",
        children = {
            -- 顶部: 技能点信息
            UI.Panel {
                id = "skill_header",
                width = "100%", height = 24,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                paddingHorizontal = 12,
                backgroundColor = { 28, 33, 46, 240 },
                borderBottomWidth = 1, borderBottomColor = { 50, 60, 80, 120 },
                children = {
                    UI.Label { id = "skill_pts_label", text = "技能点: 0", fontSize = 11, fontColor = { 255, 215, 0, 240 } },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { id = "skill_pts_total", text = "已用: 0/0", fontSize = 9, fontColor = Colors.textDim },
                            UI.Button {
                                id = "skill_reset_btn",
                                text = "重置",
                                height = 20, fontSize = 9,
                                paddingHorizontal = 8,
                                backgroundColor = { 120, 50, 50, 200 },
                                fontColor = { 255, 180, 180, 230 },
                                onClick = Utils.Debounce(function()
                                    SkillPage.ShowResetConfirm()
                                end, 0.3),
                            },
                        },
                    },
                },
            },

            -- 技能树画布 + 缩放按钮
            UI.Panel {
                width = "100%", flexGrow = 1, flexBasis = 0,
                children = {
                    treeWidget_,
                    -- 缩放按钮 (绝对定位右侧)
                    UI.Panel {
                        position = "absolute", right = 8, top = "40%",
                        flexDirection = "column", alignItems = "center", gap = 6,
                        children = {
                            UI.Panel {
                                width = 28, height = 28,
                                borderRadius = 14,
                                backgroundColor = { 40, 45, 60, 200 },
                                borderWidth = 1, borderColor = { 100, 110, 140, 150 },
                                alignItems = "center", justifyContent = "center",
                                onClick = function() treeWidget_:ZoomStep(1) end,
                                children = {
                                    UI.Label { text = "+", fontSize = 16, fontColor = { 220, 220, 240, 230 } },
                                },
                            },
                            UI.Panel {
                                width = 28, height = 28,
                                borderRadius = 14,
                                backgroundColor = { 40, 45, 60, 200 },
                                borderWidth = 1, borderColor = { 100, 110, 140, 150 },
                                alignItems = "center", justifyContent = "center",
                                onClick = function() treeWidget_:ZoomStep(-1) end,
                                children = {
                                    UI.Label { text = "-", fontSize = 16, fontColor = { 220, 220, 240, 230 } },
                                },
                            },
                        },
                    },
                },
            },

            -- 装备槽位区域
            UI.Panel {
                id = "loadout_bar",
                width = "100%", height = LOADOUT_H,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "center",
                gap = SLOT_GAP,
                paddingHorizontal = 6,
                backgroundColor = { 20, 24, 36, 250 },
                borderTopWidth = 1, borderTopColor = { 60, 70, 100, 100 },
                children = {
                    -- 魔力之源药水图标
                    UI.Panel {
                        id = "mana_potion_slot",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 30, 50, 80, 200 },
                        borderRadius = 6,
                        borderWidth = 1.5, borderColor = { 60, 140, 255, 180 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            SkillPage.ShowManaPotionPopup()
                        end, 0.2),
                        children = {
                            UI.Panel {
                                width = 22, height = 22,
                                backgroundImage = "image/mana_potion.png",
                                backgroundFit = "contain",
                                pointerEvents = "none",
                            },
                            UI.Label {
                                id = "mana_potion_count",
                                text = "0",
                                fontSize = 7, fontColor = { 150, 210, 255, 230 },
                                position = "absolute", bottom = 0, right = 1,
                                pointerEvents = "none",
                            },
                        },
                    },
                    -- 自动喝药按钮
                    UI.Panel {
                        id = "auto_potion_btn",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 40, 40, 50, 200 },
                        borderRadius = 6,
                        borderWidth = 1, borderColor = { 100, 100, 120, 120 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            GameState.manaPotion.autoUse = not GameState.manaPotion.autoUse
                            SaveSystem.MarkDirty()
                            SkillPage.RefreshManaPotionUI()
                            if GameState.manaPotion.autoUse then
                                Toast.Success("自动喝药 已开启")
                            else
                                Toast.Warn("自动喝药 已关闭")
                            end
                        end, 0.2),
                        children = {
                            UI.Label { id = "auto_potion_text", text = "自动", fontSize = 8, fontColor = { 120, 120, 140, 200 } },
                        },
                    },
                    -- 分隔线
                    UI.Panel { width = 1, height = 30, backgroundColor = { 80, 90, 120, 80 } },
                    -- 基础技能槽 (黄框)
                    UI.Panel {
                        id = "slot_basic",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 50, 45, 30, 200 },
                        borderRadius = 6,
                        borderWidth = 1.5, borderColor = { 200, 180, 80, 180 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            SkillPage.OnLoadoutSlotClick("basic", 0)
                        end, 0.2),
                        children = {
                            UI.Label { id = "slot_basic_text", text = "基础", fontSize = 8, fontColor = { 200, 180, 80, 160 } },
                        },
                    },
                    -- 分隔线
                    UI.Panel { width = 1, height = 30, backgroundColor = { 80, 90, 120, 80 } },
                    -- 主动技能槽 1-4
                    UI.Panel {
                        id = "slot_active_1",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 35, 40, 55, 200 },
                        borderRadius = 6,
                        borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            SkillPage.OnLoadoutSlotClick("active", 1)
                        end, 0.2),
                        children = {
                            UI.Label { id = "slot_active_1_text", text = "1", fontSize = 8, fontColor = Colors.textDim },
                        },
                    },
                    UI.Panel {
                        id = "slot_active_2",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 35, 40, 55, 200 },
                        borderRadius = 6,
                        borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            SkillPage.OnLoadoutSlotClick("active", 2)
                        end, 0.2),
                        children = {
                            UI.Label { id = "slot_active_2_text", text = "2", fontSize = 8, fontColor = Colors.textDim },
                        },
                    },
                    UI.Panel {
                        id = "slot_active_3",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 35, 40, 55, 200 },
                        borderRadius = 6,
                        borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            SkillPage.OnLoadoutSlotClick("active", 3)
                        end, 0.2),
                        children = {
                            UI.Label { id = "slot_active_3_text", text = "3", fontSize = 8, fontColor = Colors.textDim },
                        },
                    },
                    UI.Panel {
                        id = "slot_active_4",
                        width = SLOT_SIZE, height = SLOT_SIZE,
                        backgroundColor = { 35, 40, 55, 200 },
                        borderRadius = 6,
                        borderWidth = 1, borderColor = { 100, 120, 180, 120 },
                        alignItems = "center", justifyContent = "center",
                        onClick = Utils.Debounce(function()
                            SkillPage.OnLoadoutSlotClick("active", 4)
                        end, 0.2),
                        children = {
                            UI.Label { id = "slot_active_4_text", text = "4", fontSize = 8, fontColor = Colors.textDim },
                        },
                    },
                },
            },

            -- 底部: 选中技能信息 + 升级按钮
            UI.Panel {
                id = "skill_info_bar",
                width = "100%", height = INFO_H,
                flexDirection = "row",
                alignItems = "center",
                paddingHorizontal = 10,
                gap = 8,
                backgroundColor = { 25, 30, 42, 250 },
                borderTopWidth = 1, borderTopColor = { 50, 60, 80, 120 },
                children = {
                    -- 技能图标
                    UI.Panel {
                        id = "info_icon",
                        width = 36, height = 36,
                        backgroundColor = { 40, 45, 60, 200 },
                        borderRadius = 6,
                        alignItems = "center", justifyContent = "center",
                        children = {
                            UI.Label { id = "info_icon_lv", text = "-", fontSize = 12, fontColor = Colors.text },
                        },
                    },
                    -- 技能详情
                    UI.Panel {
                        flexGrow = 1, flexBasis = 0,
                        gap = 1,
                        children = {
                            UI.Panel {
                                flexDirection = "row", gap = 4, alignItems = "center",
                                children = {
                                    UI.Label { id = "info_name", text = "选择技能", fontSize = 12, fontColor = Colors.text },
                                    UI.Label { id = "info_type", text = "", fontSize = 8, fontColor = Colors.textDim },
                                    UI.Label { id = "info_mana", text = "", fontSize = 8, fontColor = { 100, 160, 255, 200 } },
                                },
                            },
                            UI.Label { id = "info_desc", text = "点击技能节点查看详情", fontSize = 9, fontColor = Colors.textDim,
                                       whiteSpace = "normal", maxLines = 2 },
                            UI.Label { id = "info_req", text = "", fontSize = 8, fontColor = { 255, 180, 80, 180 } },
                        },
                    },
                    -- 升级 / 降级 按钮（左）
                    UI.Panel {
                        gap = 2,
                        alignItems = "center",
                        children = {
                            UI.Button {
                                id = "info_upgrade_btn",
                                text = "升级",
                                width = 48, height = 22,
                                fontSize = 10,
                                variant = "primary",
                                disabled = true,
                                onClick = function()
                                    if selectedSkill_ then
                                        local ok, err = GameState.UpgradeSkill(selectedSkill_.id)
                                        if ok then
                                            SaveSystem.MarkDirty()
                                            SkillPage.Refresh()
                                        elseif err then
                                            Toast.Warn(err)
                                        end
                                    end
                                end,
                            },
                            UI.Button {
                                id = "info_downgrade_btn",
                                text = "降级",
                                width = 48, height = 18,
                                fontSize = 9,
                                backgroundColor = { 90, 50, 60, 200 },
                                fontColor = { 255, 180, 180, 255 },
                                disabled = true,
                                onClick = function()
                                    if selectedSkill_ then
                                        RequestDowngrade(selectedSkill_)
                                    end
                                end,
                            },
                        },
                    },
                    -- 装备按钮（右）
                    UI.Button {
                        id = "info_equip_btn",
                        text = "装备",
                        width = 52, height = 28,
                        fontSize = 10,
                        backgroundColor = { 50, 80, 60, 200 },
                        fontColor = { 180, 255, 200, 255 },
                        disabled = true,
                        onClick = function()
                            if selectedSkill_ then
                                SkillPage.QuickEquip(selectedSkill_)
                            end
                        end,
                    },
                },
            },
        },
    }

    SkillPage.Refresh()
    return page_
end

-- ============================================================================
-- 装备槽点击逻辑
-- ============================================================================

function SkillPage.OnLoadoutSlotClick(slotType, slotIdx)
    if slotType == "basic" then
        local cur = GameState.GetEquippedBasicSkill()
        if cur then
            GameState.EquipBasicSkill(nil)
            SaveSystem.MarkDirty()
            SkillPage.RefreshLoadout()
            Toast.Show("已卸下基础技能")
        end
    else
        local active = GameState.GetEquippedActiveSkills()
        if active[slotIdx] then
            GameState.EquipActiveSkill(slotIdx, nil)
            SaveSystem.MarkDirty()
            SkillPage.RefreshLoadout()
            Toast.Show("已卸下槽位 " .. slotIdx)
        end
    end
end

--- 快速装备选中技能
function SkillPage.QuickEquip(skill)
    if not skill then return end
    local lv = GameState.GetSkillLevel(skill.id)
    if lv <= 0 then
        Toast.Warn("未学习此技能")
        return
    end

    if skill.isBasic or skill.tier == 2 then
        local ok, err = GameState.EquipBasicSkill(skill.id)
        if ok then
            SaveSystem.MarkDirty()
            SkillPage.RefreshLoadout()
            SkillPage.RefreshInfo()
            Toast.Success("已装备: " .. skill.name)
        else
            Toast.Warn(err)
        end
    elseif skill.nodeType == "active" and not skill.isKeyPassive then
        local active = GameState.GetEquippedActiveSkills()
        local targetSlot = nil
        for i = 1, 4 do
            if active[i] == skill.id then
                Toast.Show("已在槽位 " .. i)
                return
            end
        end
        for i = 1, 4 do
            if not active[i] then
                targetSlot = i
                break
            end
        end
        if not targetSlot then targetSlot = 4 end

        local ok, err = GameState.EquipActiveSkill(targetSlot, skill.id)
        if ok then
            SaveSystem.MarkDirty()
            SkillPage.RefreshLoadout()
            SkillPage.RefreshInfo()
            Toast.Success("已装备至槽位 " .. targetSlot .. ": " .. skill.name)
        else
            Toast.Warn(err)
        end
    else
        Toast.Warn("此类技能无需装备")
    end
end

-- ============================================================================
-- 刷新
-- ============================================================================

function SkillPage.Refresh()
    if not page_ then return end
    -- 重新计算布局 (技能升级后节点状态变化)
    if treeWidget_ and treeWidget_.RefreshLayout then
        treeWidget_:RefreshLayout()
    end
    SkillPage.RefreshHeader()
    SkillPage.RefreshInfo()
    SkillPage.RefreshLoadout()
    SkillPage.RefreshManaPotionUI()
end

function SkillPage.RefreshHeader()
    if not page_ then return end
    local function set(id, text)
        local w = page_:FindById(id)
        if w then w:SetText(tostring(text)) end
    end

    local avail = GameState.GetAvailableSkillPts()
    local spent = GameState.GetSpentSkillPts()
    local total = GameState.GetTotalSkillPts()

    set("skill_pts_label", "技能点: " .. avail)
    set("skill_pts_total", "已用: " .. spent .. "/" .. total)
end

function SkillPage.RefreshInfo()
    if not page_ then return end
    local function set(id, text)
        local w = page_:FindById(id)
        if w then w:SetText(tostring(text)) end
    end

    if not selectedSkill_ then return end
    local skill = selectedSkill_
    local lv = GameState.GetSkillLevel(skill.id)
    local canUp, reason = GameState.CanUpgradeSkill(skill.id)
    local isMaxed = lv >= skill.maxLevel
    local ec = GetSkillColor(skill)

    -- 图标面板 (增强节点使用其所增强的父技能图标)
    local iconLookupId = skill.id
    if skill.nodeType == "enhance" and skill.parentSkill then
        iconLookupId = skill.parentSkill
    end
    local iconPath = Config.SKILL_ICON_PATHS[iconLookupId]
    local iconPanel = page_:FindById("info_icon")
    if iconPanel then
        local iconBg = lv > 0
            and { math.floor(ec[1] * 0.5), math.floor(ec[2] * 0.5), math.floor(ec[3] * 0.5), 200 }
            or { 40, 45, 60, 200 }
        iconPanel:SetStyle({ backgroundColor = iconBg })
        if iconPath then
            iconPanel:SetStyle({ backgroundImage = iconPath, backgroundFit = "contain" })
            set("info_icon_lv", "")
        else
            iconPanel:SetStyle({ backgroundImage = "" })
            set("info_icon_lv", lv > 0 and ("Lv" .. lv) or "")
        end
    end

    -- 名称
    local elemName = ""
    if skill.element then
        for _, e in ipairs(SkillTreeConfig.ELEMENTS) do
            if e.id == skill.element then elemName = e.name; break end
        end
    end

    set("info_name", skill.name)

    local typeText = ""
    if skill.nodeType == "enhance" then
        typeText = "[增强]"
    elseif skill.isBasic then
        typeText = "[基础·" .. elemName .. "]"
    elseif skill.isUltimate then
        typeText = "[终极·" .. elemName .. "]"
    elseif skill.isKeyPassive then
        typeText = "[关键被动]"
    elseif skill.nodeType == "active" then
        local tierName = SkillTreeConfig.TIERS[skill.tier] and SkillTreeConfig.TIERS[skill.tier].name or ""
        typeText = "[" .. tierName .. "·" .. elemName .. "]"
    end
    set("info_type", typeText)

    -- 法力消耗
    local manaCost = skill.manaCost or 0
    set("info_mana", manaCost > 0 and ("法力消耗:" .. manaCost) or "")

    -- 效果描述
    local eLv = math.max(1, lv)
    local descText
    if skill.descArgs then
        descText = string.format(skill.desc, skill.descArgs(eLv))
    elseif skill.effect then
        local effVal = skill.effect(eLv)
        if type(effVal) == "number" then
            effVal = math.floor(effVal)
            descText = string.format(skill.desc, effVal)
        else
            descText = skill.desc
        end
    else
        descText = skill.desc or ""
    end
    if lv > 0 and not isMaxed and skill.effect then
        local nextVal = skill.effect(lv + 1)
        if type(nextVal) == "number" then
            nextVal = math.floor(nextVal)
            local nextDesc = string.format(skill.desc, nextVal)
            descText = descText .. " → " .. nextDesc
        end
    end
    set("info_desc", descText)

    -- 需求
    local reqText = ""
    if not canUp and reason then
        reqText = reason
    elseif isMaxed then
        reqText = "已满级"
    end
    set("info_req", reqText)

    -- 升级按钮
    local btn = page_:FindById("info_upgrade_btn")
    if btn then
        btn:SetDisabled(not canUp)
        if isMaxed then
            btn:SetText("满级")
        else
            btn:SetText("升级")
        end
    end

    -- 降级按钮
    local downBtn = page_:FindById("info_downgrade_btn")
    if downBtn then
        local canDown = GameState.CanDowngradeSkill(skill.id)
        downBtn:SetDisabled(not canDown)
    end

    -- 装备按钮
    local equipBtn = page_:FindById("info_equip_btn")
    if equipBtn then
        local canEquip = lv > 0 and (skill.isBasic or (skill.nodeType == "active" and not skill.isKeyPassive))
        equipBtn:SetDisabled(not canEquip)
        if skill.isBasic then
            local curBasic = GameState.GetEquippedBasicSkill()
            equipBtn:SetText(curBasic == skill.id and "已装备" or "装备")
            if curBasic == skill.id then equipBtn:SetDisabled(true) end
        elseif skill.nodeType == "active" and not skill.isKeyPassive then
            local active = GameState.GetEquippedActiveSkills()
            local equipped = false
            for i = 1, 4 do
                if active[i] == skill.id then equipped = true; break end
            end
            equipBtn:SetText(equipped and "已装备" or "装备")
            if equipped then equipBtn:SetDisabled(true) end
        else
            equipBtn:SetText("装备")
            equipBtn:SetDisabled(true)
        end
    end

    SkillPage.RefreshHeader()
end

--- 刷新装备槽显示
function SkillPage.RefreshLoadout()
    if not page_ then return end
    local function set(id, text)
        local w = page_:FindById(id)
        if w then w:SetText(tostring(text)) end
    end

    -- 基础技能槽
    local basicId = GameState.GetEquippedBasicSkill()
    local basicSlot = page_:FindById("slot_basic")
    if basicSlot then
        if basicId then
            local cfg = SkillTreeConfig.SKILL_MAP[basicId]
            local ec = cfg and GetSkillColor(cfg) or { 200, 180, 80 }
            basicSlot:SetStyle({
                backgroundColor = { math.floor(ec[1] * 0.3 + 20), math.floor(ec[2] * 0.3 + 20), math.floor(ec[3] * 0.3 + 20), 220 },
                borderColor = { ec[1], ec[2], ec[3], 200 },
            })
            local iconPath = cfg and Config.SKILL_ICON_PATHS[basicId]
            if iconPath then
                basicSlot:SetStyle({ backgroundImage = iconPath, backgroundFit = "contain" })
                set("slot_basic_text", "")
            else
                basicSlot:SetStyle({ backgroundImage = "" })
                set("slot_basic_text", cfg and cfg.name or "基础")
            end
        else
            basicSlot:SetStyle({
                backgroundColor = { 50, 45, 30, 200 },
                borderColor = { 200, 180, 80, 180 },
                backgroundImage = "",
            })
            set("slot_basic_text", "基础")
        end
    end

    -- 主动技能槽 1-4
    local activeSkills = GameState.GetEquippedActiveSkills()
    for i = 1, 4 do
        local slotId = "slot_active_" .. i
        local textId = "slot_active_" .. i .. "_text"
        local slot = page_:FindById(slotId)
        local sid = activeSkills[i]

        if slot then
            if sid then
                local cfg = SkillTreeConfig.SKILL_MAP[sid]
                local ec = cfg and GetSkillColor(cfg) or { 100, 120, 180 }
                slot:SetStyle({
                    backgroundColor = { math.floor(ec[1] * 0.3 + 15), math.floor(ec[2] * 0.3 + 15), math.floor(ec[3] * 0.3 + 15), 220 },
                    borderColor = { ec[1], ec[2], ec[3], 180 },
                })
                local iconPath = cfg and Config.SKILL_ICON_PATHS[sid]
                if iconPath then
                    slot:SetStyle({ backgroundImage = iconPath, backgroundFit = "contain" })
                    set(textId, "")
                else
                    slot:SetStyle({ backgroundImage = "" })
                    set(textId, cfg and cfg.name or tostring(i))
                end
            else
                slot:SetStyle({
                    backgroundColor = { 35, 40, 55, 200 },
                    borderColor = { 100, 120, 180, 120 },
                    backgroundImage = "",
                })
                set(textId, tostring(i))
            end
        end
    end
end

-- ============================================================================
-- 降级技能确认弹窗
-- ============================================================================

local function CloseDowngradeConfirm()
    if downgradeOverlay_ and page_ then
        page_:RemoveChild(downgradeOverlay_)
    end
    downgradeOverlay_ = nil
end

local function ExecDowngrade(skill)
    local ok, err = GameState.DowngradeSkill(skill.id)
    if ok then
        SaveSystem.MarkDirty()
        SkillPage.Refresh()
    elseif err then
        Toast.Warn(err)
    end
end

local function ShowDowngradeConfirm(skill)
    CloseDowngradeConfirm()
    local lv = GameState.GetSkillLevel(skill.id)
    local cost, refundPts = GameState.GetDowngradeSkillCost(skill.id)
    local cur = GameState.GetSoulCrystal()
    local willSkip = false

    downgradeOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 120 },
        alignItems = "center", justifyContent = "center",
        onClick = function() CloseDowngradeConfirm() end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 160, 80, 80, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 14, gap = 8,
                alignItems = "center",
                onClick = function() end,
                children = {
                    UI.Label { text = "降级技能", fontSize = 14, fontColor = { 255, 160, 140, 240 } },
                    UI.Label {
                        text = skill.name .. " Lv." .. lv .. " → Lv." .. (lv - 1),
                        fontSize = 12, fontColor = Colors.text,
                    },
                    UI.Label {
                        text = "将归还 " .. refundPts .. " 个技能点",
                        fontSize = 11, fontColor = Colors.textDim,
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "消耗: " .. cost .. " 魂晶", fontSize = 12, fontColor = { 160, 80, 255, 230 } },
                            UI.Label {
                                text = "(拥有 " .. cur .. ")",
                                fontSize = 10,
                                fontColor = cur >= cost and { 140, 200, 140, 200 } or { 255, 100, 100, 200 },
                            },
                        },
                    },
                    UI.Checkbox {
                        label = "本次登录不再提示",
                        size = 16, fontSize = 10,
                        checked = false,
                        onChange = function(self, checked)
                            willSkip = checked
                        end,
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 4,
                        children = {
                            UI.Button {
                                text = "确认降级",
                                height = 30, fontSize = 13, width = 100,
                                backgroundColor = { 160, 60, 60, 230 },
                                onClick = Utils.Debounce(function()
                                    if willSkip then skipDowngradeConfirm_ = true end
                                    CloseDowngradeConfirm()
                                    ExecDowngrade(skill)
                                end, 0.3),
                            },
                            UI.Button {
                                text = "取消", height = 30, fontSize = 13, width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function() CloseDowngradeConfirm() end,
                            },
                        },
                    },
                },
            },
        },
    }

    if page_ then
        page_:AddChild(downgradeOverlay_)
    end
end

RequestDowngrade = function(skill)
    local canDown, err = GameState.CanDowngradeSkill(skill.id)
    if not canDown then
        Toast.Warn(err)
        return
    end
    if skipDowngradeConfirm_ then
        ExecDowngrade(skill)
    else
        ShowDowngradeConfirm(skill)
    end
end

-- ============================================================================
-- 重置技能点确认弹窗
-- ============================================================================

function SkillPage.CloseResetConfirm()
    if resetOverlay_ then
        resetOverlay_:Destroy()
        resetOverlay_ = nil
    end
end

function SkillPage.ShowResetConfirm()
    SkillPage.CloseResetConfirm()

    local spent = GameState.GetSpentSkillPts()
    if spent <= 0 then
        Toast.Warn("没有已分配的技能点")
        return
    end

    local cost = GameState.GetResetSkillCost()
    local cur = GameState.GetSoulCrystal()
    local canReset = cur >= cost

    local detailLines = {}
    for _, skillCfg in ipairs(SkillTreeConfig.SKILLS) do
        local lv = GameState.GetSkillLevel(skillCfg.id)
        if lv > 0 then
            table.insert(detailLines, skillCfg.name .. " Lv." .. lv)
        end
    end

    resetOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 120 },
        alignItems = "center", justifyContent = "center",
        onClick = function() SkillPage.CloseResetConfirm() end,
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 120, 50, 50, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 14, gap = 8,
                alignItems = "center",
                onClick = function() end,
                children = {
                    UI.Label { text = "重置技能点", fontSize = 14, fontColor = { 255, 140, 140, 240 } },
                    UI.Label { text = "回收全部 " .. spent .. " 个技能点", fontSize = 11, fontColor = { 200, 210, 230, 220 } },
                    UI.Label {
                        text = table.concat(detailLines, ", "),
                        fontSize = 9, fontColor = Colors.textDim,
                        whiteSpace = "normal", maxLines = 3,
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4, marginTop = 4,
                        children = {
                            UI.Label { text = "消耗: " .. cost .. " 魂晶", fontSize = 12, fontColor = { 160, 80, 255, 230 } },
                            UI.Label {
                                text = "(拥有 " .. cur .. ")",
                                fontSize = 10,
                                fontColor = canReset and { 140, 200, 140, 200 } or { 255, 100, 100, 200 },
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12, marginTop = 6,
                        children = {
                            UI.Button {
                                text = canReset and "确认重置" or "魂晶不足",
                                height = 32, fontSize = 13, width = 120,
                                backgroundColor = canReset and { 160, 50, 50, 230 } or { 60, 60, 70, 200 },
                                onClick = Utils.Debounce(function()
                                    if not canReset then return end
                                    local ok, err = GameState.ResetSkillPoints()
                                    if ok then
                                        SaveSystem.SaveNow()
                                        Toast.Success("技能点已重置")
                                        SkillPage.CloseResetConfirm()
                                        SkillPage.Refresh()
                                    elseif err then
                                        Toast.Warn(err)
                                    end
                                end, 0.5),
                            },
                            UI.Button {
                                text = "取消", height = 32, fontSize = 13, width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function() SkillPage.CloseResetConfirm() end,
                            },
                        },
                    },
                },
            },
        },
    }

    if page_ then
        page_:AddChild(resetOverlay_)
    end
end

function SkillPage.InvalidateCache()
    -- 接口兼容
end

-- ============================================================================
-- 魔力之源 UI
-- ============================================================================

local manaPotionOverlay_ = nil

function SkillPage.RefreshManaPotionUI()
    if not page_ then return end
    local countLabel = page_:FindById("mana_potion_count")
    if countLabel then
        countLabel:SetText(tostring(GameState.manaPotion.count or 0))
    end
    local isOn = GameState.manaPotion.autoUse
    local autoBtn = page_:FindById("auto_potion_btn")
    if autoBtn then
        autoBtn:SetStyle({
            backgroundColor = isOn and { 30, 80, 60, 220 } or { 40, 40, 50, 200 },
            borderColor     = isOn and { 80, 220, 120, 200 } or { 100, 100, 120, 120 },
        })
    end
    local autoText = page_:FindById("auto_potion_text")
    if autoText then
        autoText:SetStyle({ fontColor = isOn and { 80, 220, 120, 240 } or { 120, 120, 140, 200 } })
    end
end

function SkillPage.CloseManaPotionPopup()
    if manaPotionOverlay_ then
        manaPotionOverlay_:Destroy()
        manaPotionOverlay_ = nil
    end
end

function SkillPage.ShowManaPotionPopup()
    SkillPage.CloseManaPotionPopup()

    local mp = GameState.manaPotion
    local lv = mp.level or 0
    local maxLv = 10
    local pct = GameState.GetManaPotionPct()
    local pctStr = math.floor(pct * 100 + 0.5) .. "%"
    local nextPctStr = lv < maxLv and (math.floor((pct + 0.03) * 100 + 0.5) .. "%") or "MAX"
    local canUpgrade = lv < maxLv
    local adRemain = GameState.GetManaPotionAdRemain()
    local freeRemain = GameState.GetFreeRegenRemain()
    local isFreeActive = freeRemain > 0

    -- 格式化剩余时间
    local function FmtTime(sec)
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        if h > 0 then return h .. "时" .. m .. "分" end
        return m .. "分"
    end

    local actionChildren = {}

    -- 免费回复状态
    if isFreeActive then
        table.insert(actionChildren, UI.Label {
            text = "无消耗回复中: 剩余 " .. FmtTime(freeRemain),
            fontSize = 11, fontColor = { 80, 220, 160, 240 },
        })
    end

    -- 看广告 +1小时
    local adBtnText = adRemain > 0
        and ("▶ 看广告 +1小时无消耗回复 (" .. adRemain .. "/24)")
        or "今日次数已用完"
    table.insert(actionChildren, UI.Button {
        text = adBtnText,
        height = 34, fontSize = 11, width = "100%",
        backgroundColor = adRemain > 0 and { 40, 100, 180, 230 } or { 60, 60, 70, 200 },
        onClick = Utils.Debounce(function()
            if adRemain <= 0 then
                Toast.Warn("今日广告次数已用完")
                return
            end
            local ok, err = pcall(function()
                ---@diagnostic disable-next-line: undefined-global
                sdk:ShowRewardVideoAd(function(result)
                    if result.success then
                        GameState.RecordManaPotionAd()
                        SaveSystem.MarkDirty()
                        Toast.Success("获得 1小时无消耗回复！")
                        SkillPage.CloseManaPotionPopup()
                        SkillPage.ShowManaPotionPopup()
                        SkillPage.RefreshManaPotionUI()
                    else
                        if result.msg == "embed manual close" then
                            Toast.Warn("需完整观看广告才能获得奖励")
                        else
                            Toast.Warn("广告播放失败")
                        end
                    end
                end)
            end)
            if not ok then
                Toast.Warn("广告功能暂不可用")
            end
        end, 0.5),
    })

    -- 消耗森之露升级
    if canUpgrade then
        local upgradeCost = GameState.GetManaPotionUpgradeCost() or 0
        local haveDew = GameState.materials.forestDew or 0
        local canAfford = haveDew >= upgradeCost
        table.insert(actionChildren, UI.Button {
            text = canAfford
                and ("升级 (消耗 " .. upgradeCost .. " 森之露)")
                or ("森之露不足 (" .. haveDew .. "/" .. upgradeCost .. ")"),
            height = 34, fontSize = 12, width = "100%",
            backgroundColor = canAfford and { 60, 160, 100, 230 } or { 80, 80, 90, 180 },
            onClick = Utils.Debounce(function()
                local success, errMsg = GameState.UpgradeManaPotionWithDew()
                if success then
                    SaveSystem.MarkDirty()
                    Toast.Success("魔力之源升级成功！")
                    SkillPage.CloseManaPotionPopup()
                    SkillPage.ShowManaPotionPopup()
                    SkillPage.RefreshManaPotionUI()
                else
                    Toast.Warn(errMsg or "升级失败")
                end
            end, 0.5),
        })
    end

    -- 关闭按钮
    table.insert(actionChildren, UI.Button {
        text = "关闭", height = 28, fontSize = 11, width = "100%",
        backgroundColor = { 60, 65, 75, 200 },
        onClick = function() SkillPage.CloseManaPotionPopup() end,
    })

    manaPotionOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 120 },
        alignItems = "center", justifyContent = "center",
        onClick = function() SkillPage.CloseManaPotionPopup() end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 60, 140, 255, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 14, gap = 10,
                alignItems = "center",
                onClick = function() end,  -- 阻止冒泡
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Panel {
                                width = 28, height = 28,
                                backgroundImage = "image/mana_potion.png",
                                backgroundFit = "contain",
                                pointerEvents = "none",
                            },
                            UI.Label { text = "魔力之源", fontSize = 16, fontColor = { 100, 180, 255, 255 } },
                        },
                    },
                    -- 信息
                    UI.Label {
                        text = "每瓶恢复 " .. pctStr .. " 最大MP",
                        fontSize = 12, fontColor = { 180, 210, 240, 230 },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 12,
                        children = {
                            UI.Label {
                                text = "持有: " .. (mp.count or 0) .. " 瓶",
                                fontSize = 11, fontColor = { 150, 210, 255, 220 },
                            },
                            UI.Label {
                                text = "等级: " .. lv .. "/" .. maxLv,
                                fontSize = 11, fontColor = { 200, 160, 255, 220 },
                            },
                        },
                    },
                    -- 升级预览
                    canUpgrade and UI.Label {
                        text = "升级后: " .. pctStr .. " → " .. nextPctStr,
                        fontSize = 10, fontColor = { 160, 255, 160, 200 },
                    } or UI.Label {
                        text = "已满级！每瓶恢复 60% MP",
                        fontSize = 10, fontColor = { 255, 215, 0, 220 },
                    },
                    -- 分隔
                    UI.Panel { width = "90%", height = 1, backgroundColor = { 80, 90, 120, 80 }, marginVertical = 2 },
                    -- 操作按钮
                    UI.Panel {
                        width = "100%", gap = 6, alignItems = "center",
                        children = actionChildren,
                    },
                },
            },
        },
    }

    if page_ then
        page_:AddChild(manaPotionOverlay_)
    end
end

return SkillPage
