-- ============================================================================
-- ui/TabBar.lua - 底部 Tab 切换栏 + 内容容器
-- ============================================================================

local UI = require("urhox-libs/UI")
local CharacterPage = require("ui.CharacterPage")
local BagPage       = require("ui.BagPage")
local InventoryPage = require("ui.InventoryPage")
local SkillPage     = require("ui.SkillPage")
local ShopPage      = require("ui.ShopPage")
local Utils         = require("Utils")

local TabBar = {}

local activeTabId_     = "character"
local contentContainer_ = nil
local buttons_          = {}
local dirtyFlags_       = {}   -- { [tabId] = true/false }

local tabPages_ = nil

local TAB_DEFS = {
    { id = "character", label = "角色", page = CharacterPage },
    { id = "bag",       label = "背包", page = BagPage },
    { id = "inventory", label = "装备", page = InventoryPage },
    { id = "skill",     label = "技能", page = SkillPage },
    { id = "shop",      label = "商店", page = ShopPage },
}

local ACTIVE_BG   = { 80, 140, 255, 255 }
local INACTIVE_BG = { 0, 0, 0, 0 }
local ACTIVE_FG   = { 255, 255, 255, 255 }
local INACTIVE_FG = { 140, 150, 170, 220 }

-- ============================================================================
-- 切换逻辑
-- ============================================================================

local function updateButtonStyles()
    for _, info in ipairs(buttons_) do
        local isActive = info.id == activeTabId_
        info.bg:SetStyle({ backgroundColor = isActive and ACTIVE_BG or INACTIVE_BG })
        info.label:SetStyle({ fontColor = isActive and ACTIVE_FG or INACTIVE_FG })
    end
end

local function switchTab(tabId)
    if tabId == activeTabId_ then return end
    activeTabId_ = tabId
    contentContainer_:ClearChildren()
    contentContainer_:AddChild(tabPages_[tabId])

    -- 如果该页被标脏，先清缓存再刷新
    for _, def in ipairs(TAB_DEFS) do
        if def.id == tabId then
            if dirtyFlags_[tabId] then
                dirtyFlags_[tabId] = false
                if def.page.InvalidateCache then
                    def.page.InvalidateCache()
                end
            end
            def.page.Refresh()
            break
        end
    end

    updateButtonStyles()
end

-- ============================================================================
-- 创建
-- ============================================================================

--- 创建底部面板（内容区 + 按钮栏），返回整个 Panel
---@return Widget
function TabBar.Create()
    -- 每次创建 UI 时重置为默认标签页（角色-属性）
    activeTabId_ = "character"

    -- 创建各页面 Widget
    tabPages_ = {}
    for _, def in ipairs(TAB_DEFS) do
        tabPages_[def.id] = def.page.Create()
    end

    -- 内容容器
    contentContainer_ = UI.Panel {
        id = "tabContent",
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        overflow = "hidden",
        children = { tabPages_.character },
    }

    -- 用 Panel + Label 构建 Tab 按钮（避免 Button 内部主题覆盖样式）
    buttons_ = {}
    local btnChildren = {}
    for _, def in ipairs(TAB_DEFS) do
        local isActive = def.id == activeTabId_
        local label = UI.Label {
            text = def.label,
            fontSize = 13,
            fontColor = isActive and ACTIVE_FG or INACTIVE_FG,
        }
        local bg = UI.Panel {
            flexGrow = 1, flexBasis = 0,
            height = 40,
            alignItems = "center", justifyContent = "center",
            backgroundColor = isActive and ACTIVE_BG or INACTIVE_BG,
            onClick = Utils.Debounce(function() switchTab(def.id) end, 0.2),
            children = { label },
        }
        table.insert(buttons_, { id = def.id, bg = bg, label = label })
        table.insert(btnChildren, bg)
    end

    -- 初始页面立即刷新，避免首帧显示空数据
    for _, def in ipairs(TAB_DEFS) do
        if def.id == activeTabId_ then
            def.page.Refresh()
            break
        end
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        flexDirection = "column",
        backgroundColor = { 22, 26, 36, 250 },
        borderTopWidth = 1, borderTopColor = { 50, 60, 80, 150 },
        children = {
            contentContainer_,
            UI.Panel {
                id = "tabBar",
                width = "100%", height = 40,
                flexDirection = "row",
                backgroundColor = { 25, 30, 42, 250 },
                borderTopWidth = 1, borderTopColor = { 50, 60, 80, 150 },
                children = btnChildren,
            },
        },
    }
end

--- 切换到指定标签页（外部调用）
---@param tabId string
function TabBar.SwitchTo(tabId)
    if not contentContainer_ then return end
    activeTabId_ = tabId
    contentContainer_:ClearChildren()
    if tabPages_[tabId] then
        contentContainer_:AddChild(tabPages_[tabId])
    end
    for _, def in ipairs(TAB_DEFS) do
        if def.id == tabId then
            if dirtyFlags_[tabId] then
                dirtyFlags_[tabId] = false
                if def.page.InvalidateCache then
                    def.page.InvalidateCache()
                end
            end
            def.page.Refresh()
            break
        end
    end
    updateButtonStyles()
end

--- 刷新当前活跃页
function TabBar.RefreshActive()
    for _, def in ipairs(TAB_DEFS) do
        if def.id == activeTabId_ then
            def.page.Refresh()
            break
        end
    end
end

--- 清除当前活跃页缓存并强制完整刷新，同时标脏所有非活跃页
function TabBar.ForceRefreshActive()
    for _, def in ipairs(TAB_DEFS) do
        if def.id == activeTabId_ then
            if def.page.InvalidateCache then
                def.page.InvalidateCache()
            end
            def.page.Refresh()
        else
            dirtyFlags_[def.id] = true
        end
    end
end

--- 标脏所有页面：当前活跃页立即刷新，非活跃页延迟到切换时刷新
function TabBar.MarkAllDirty()
    for _, def in ipairs(TAB_DEFS) do
        if def.id == activeTabId_ then
            if def.page.InvalidateCache then
                def.page.InvalidateCache()
            end
            def.page.Refresh()
        else
            dirtyFlags_[def.id] = true
        end
    end
end

return TabBar
