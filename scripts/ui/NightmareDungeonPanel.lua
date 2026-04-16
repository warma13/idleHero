-- ============================================================================
-- ui/NightmareDungeonPanel.lua - 噩梦地牢入口面板 (钥石选择 + 词缀预览)
-- ============================================================================

local UI               = require("urhox-libs/UI")
local Config           = require("Config")
local GameState        = require("GameState")
local NightmareDungeon = require("NightmareDungeon")

local NightmareDungeonPanel = {}

local onStartCallback_ = nil
local selectedSigilIdx_ = 1  -- 当前选中的钥石索引

---@type Widget
local overlay_ = nil
---@type Widget
local overlayRoot_ = nil

-- 主题色 (暗紫)
local TC = { 180, 60, 220 }

function NightmareDungeonPanel.SetStartCallback(fn)
    onStartCallback_ = fn
end

function NightmareDungeonPanel.SetOverlayRoot(root)
    overlayRoot_ = root
end

function NightmareDungeonPanel.IsOpen()
    return overlay_ ~= nil
end

function NightmareDungeonPanel.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

function NightmareDungeonPanel.Toggle()
    if overlay_ then
        NightmareDungeonPanel.Close()
    else
        NightmareDungeonPanel.Show()
    end
end

--- 获取词缀定义
---@param affixId string
---@return table|nil
local function getAffixDef(affixId)
    local ND = Config.NIGHTMARE_DUNGEON
    for _, def in ipairs(ND.POSITIVE_AFFIXES) do
        if def.id == affixId then return def end
    end
    for _, def in ipairs(ND.NEGATIVE_AFFIXES) do
        if def.id == affixId then return def end
    end
    return nil
end

--- 构建钥石列表项
---@param sigil table
---@param idx number
---@param isSelected boolean
---@param onSelect function
---@return Widget
local function BuildSigilRow(sigil, idx, isSelected, onSelect)
    -- 词缀简称
    local affixParts = {}
    for _, id in ipairs(sigil.positives or {}) do
        local def = getAffixDef(id)
        if def then table.insert(affixParts, "+" .. def.name) end
    end
    for _, id in ipairs(sigil.negatives or {}) do
        local def = getAffixDef(id)
        if def then table.insert(affixParts, "-" .. def.name) end
    end
    local affixStr = #affixParts > 0 and table.concat(affixParts, " ") or "无词缀"

    local elemNames = { fire = "火", ice = "冰", poison = "毒", arcane = "奥术" }
    local elemName = elemNames[sigil.element] or "未知"

    return UI.Panel {
        width = "100%", paddingAll = 6,
        backgroundColor = isSelected
            and { TC[1], TC[2], TC[3], 60 }
            or { 30, 35, 50, 180 },
        borderRadius = 6,
        borderWidth = isSelected and 1.5 or 0,
        borderColor = isSelected and { TC[1], TC[2], TC[3], 200 } or { 0, 0, 0, 0 },
        marginBottom = 4,
        onClick = function() onSelect(idx) end,
        children = {
            -- 层级 + 元素
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                marginBottom = 2,
                children = {
                    UI.Label {
                        text = "Lv." .. sigil.tier,
                        fontSize = 14, color = { 220, 180, 255, 255 },
                    },
                    UI.Label {
                        text = elemName .. "属性",
                        fontSize = 11, color = { 160, 160, 200, 200 },
                    },
                },
            },
            -- 词缀
            UI.Label {
                text = affixStr,
                fontSize = 10, color = { 180, 180, 200, 180 },
                width = "100%",
            },
        },
    }
end

function NightmareDungeonPanel.Show()
    if overlay_ then NightmareDungeonPanel.Close() end
    if not overlayRoot_ then return end

    local contentArea = UI.Panel {
        width = "100%", flexGrow = 1,
        justifyContent = "center", alignItems = "center",
    }
    local closeFn = function() NightmareDungeonPanel.Close() end
    NightmareDungeonPanel.BuildContent(contentArea, closeFn)

    overlay_ = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function() NightmareDungeonPanel.Close() end,
        children = { contentArea },
    }
    overlayRoot_:AddChild(overlay_)
end

--- 构建内容到指定容器
---@param container Widget
---@param closeCallback function|nil
function NightmareDungeonPanel.BuildContent(container, closeCallback)
    local closeFn = closeCallback or function() end

    NightmareDungeon.EnsureState()
    local unlocked, unlockReason = NightmareDungeon.IsUnlocked()
    local sigils = NightmareDungeon.GetSigils()
    local sigilCount = #sigils
    local maxTierCleared = GameState.nightmareDungeon and GameState.nightmareDungeon.maxTierCleared or 0
    local totalRuns = GameState.nightmareDungeon and GameState.nightmareDungeon.totalRuns or 0

    -- 修正选择索引
    if selectedSigilIdx_ > sigilCount then selectedSigilIdx_ = math.max(1, sigilCount) end

    local canEnter, enterReason = NightmareDungeon.CanEnter()

    -- 钥石列表
    local sigilRows = {}
    if sigilCount == 0 then
        table.insert(sigilRows, UI.Label {
            text = unlocked and "暂无钥石" or (unlockReason or "未解锁"),
            fontSize = 12, color = { 140, 140, 160, 180 },
            textAlign = "center", width = "100%", marginVertical = 8,
        })
    else
        for i, sigil in ipairs(sigils) do
            table.insert(sigilRows, BuildSigilRow(sigil, i, i == selectedSigilIdx_, function(idx)
                selectedSigilIdx_ = idx
                container:RemoveAllChildren()
                NightmareDungeonPanel.BuildContent(container, closeCallback)
            end))
        end
    end

    -- 选中的钥石词缀详情
    local affixDetails = {}
    if sigilCount > 0 and sigils[selectedSigilIdx_] then
        local sigil = sigils[selectedSigilIdx_]
        for _, id in ipairs(sigil.positives or {}) do
            local def = getAffixDef(id)
            if def then
                table.insert(affixDetails, UI.Panel {
                    width = "100%", flexDirection = "row", gap = 4, marginBottom = 2,
                    children = {
                        UI.Label { text = "+", fontSize = 11, color = { 80, 220, 80, 255 } },
                        UI.Label { text = def.name, fontSize = 11, color = { 80, 220, 80, 240 } },
                        UI.Label { text = def.desc, fontSize = 10, color = { 140, 200, 140, 180 } },
                    },
                })
            end
        end
        for _, id in ipairs(sigil.negatives or {}) do
            local def = getAffixDef(id)
            if def then
                table.insert(affixDetails, UI.Panel {
                    width = "100%", flexDirection = "row", gap = 4, marginBottom = 2,
                    children = {
                        UI.Label { text = "-", fontSize = 11, color = { 220, 80, 80, 255 } },
                        UI.Label { text = def.name, fontSize = 11, color = { 220, 80, 80, 240 } },
                        UI.Label { text = def.desc, fontSize = 10, color = { 200, 140, 140, 180 } },
                    },
                })
            end
        end
    end

    -- 构建主面板
    local content = UI.Panel {
        width = 290, paddingAll = 16,
        backgroundColor = { 15, 12, 28, 245 },
        borderRadius = 12, borderWidth = 1.5,
        borderColor = { TC[1], TC[2], TC[3], 180 },
        alignItems = "center",
        onClick = function() end,  -- 阻止冒泡
        children = {
            -- 标题
            UI.Label {
                text = "噩梦地牢",
                fontSize = 18, color = { TC[1], TC[2], TC[3], 255 },
                textAlign = "center", width = "100%", marginBottom = 3,
            },
            UI.Label {
                text = "消耗钥石进入，通关获得高品质装备\n层级越高，掉落越好",
                fontSize = 11, color = { 160, 150, 180, 200 },
                textAlign = "center", width = "100%", marginBottom = 10,
            },
            -- 统计
            UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 25, 20, 45, 200 },
                borderRadius = 6, marginBottom = 8,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 3,
                        children = {
                            UI.Label { text = "最高通关", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = maxTierCleared > 0 and ("Lv." .. maxTierCleared) or "--",
                                fontSize = 12, color = { 200, 160, 255, 230 },
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        marginBottom = 3,
                        children = {
                            UI.Label { text = "挑战次数", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = tostring(totalRuns) .. " 次",
                                fontSize = 11, color = { 180, 180, 200, 200 },
                            },
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label { text = "钥石数量", fontSize = 11, color = { 140, 140, 160, 180 } },
                            UI.Label {
                                text = tostring(sigilCount),
                                fontSize = 12,
                                color = sigilCount > 0 and { 100, 220, 100, 255 } or { 200, 80, 80, 255 },
                            },
                        },
                    },
                },
            },
            -- 钥石选择列表 (可滚动)
            UI.Panel {
                width = "100%", maxHeight = 120, overflow = "scroll",
                marginBottom = 6,
                children = sigilRows,
            },
            -- 词缀详情
            #affixDetails > 0 and UI.Panel {
                width = "100%", paddingAll = 6,
                backgroundColor = { 20, 15, 40, 160 },
                borderRadius = 4, marginBottom = 8,
                children = affixDetails,
            } or UI.Panel { width = 0, height = 0 },
            -- 看广告得钥石
            (function()
                local remaining = NightmareDungeon.GetAdSigilRemaining()
                local used = NightmareDungeon.GetAdSigilCount()
                local maxAd = Config.NIGHTMARE_DUNGEON.AD_SIGIL_DAILY_MAX
                return UI.Panel {
                    width = "100%", alignItems = "center", marginBottom = 6,
                    children = {
                        UI.Button {
                            text = remaining > 0
                                and ("看广告得钥石 (" .. used .. "/" .. maxAd .. ")")
                                or ("今日已用完 (" .. maxAd .. "/" .. maxAd .. ")"),
                            variant = remaining > 0 and "secondary" or "secondary",
                            width = 200, height = 30,
                            disabled = remaining <= 0,
                            backgroundColor = remaining > 0
                                and { 60, 140, 60, 220 }
                                or { 60, 60, 60, 160 },
                            color = remaining > 0
                                and { 255, 255, 255, 255 }
                                or { 140, 140, 140, 200 },
                            onClick = function()
                                if remaining <= 0 then return end
                                NightmareDungeon.WatchAdForSigil(function(sigil)
                                    -- 刷新面板
                                    container:RemoveAllChildren()
                                    NightmareDungeonPanel.BuildContent(container, closeCallback)
                                end)
                            end,
                        },
                    },
                }
            end)(),
            -- 按钮
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 12,
                children = {
                    UI.Button {
                        text = canEnter and "进入地牢" or (enterReason or "无法进入"),
                        variant = canEnter and "primary" or "secondary",
                        width = 120, height = 34,
                        disabled = not canEnter,
                        onClick = function()
                            if not canEnter then return end
                            closeFn()
                            NightmareDungeon.EnterFight(selectedSigilIdx_)
                            if onStartCallback_ then onStartCallback_() end
                        end,
                    },
                    UI.Button {
                        text = "返回", variant = "secondary",
                        width = 70, height = 34,
                        onClick = function() closeFn() end,
                    },
                },
            },
        },
    }
    container:AddChild(content)
end

return NightmareDungeonPanel
