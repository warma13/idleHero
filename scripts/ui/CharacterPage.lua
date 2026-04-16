-- ============================================================================
-- ui/CharacterPage.lua - 角色属性页 (标签式: 属性/生存/元素/套装/称号)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local GameState = require("GameState")
local Colors = require("ui.Colors")
local Toast = require("ui.Toast")
local Utils = require("Utils")
local SaveSystem = require("SaveSystem")

local TitleSystem = require("TitleSystem")
local StatDefs = require("state.StatDefs")

local CharacterPage = {}

---@type Widget
local page_ = nil
-- 手动 tab 实现（避免 UI.Tabs 的 OnPointerDown 递归 bug）
local charTabContent_   = nil   -- 当前显示的 tab 内容容器
local charTabPages_     = nil   -- { [tabId] = widget }
local charTabButtons_   = nil   -- { { id, bg, label } }
local charActiveTab_    = "stats"
local resetOverlay_ = nil   -- 重置确认弹窗

-- +10 / -10 按钮引用表
local bulkButtons_ = {}      -- { [statKey] = widget }  (+10)
local bulkMinusButtons_ = {} -- { [statKey] = widget }  (-10)

-- 称号行引用
local titleRows_ = {}        -- { [titleId] = { btn, detail } }
local titleExpanded_ = {}    -- { [titleId] = true/false }

local skipDeallocConfirm_ = false   -- 本次登录免确认
local deallocOverlay_ = nil         -- 减点确认弹窗

-- 脏检测：只有属性源数据变化时才全量刷新非动态标签
local lastCharKey_ = ""
local lastHP_ = ""


-- 属性定义 → 从 StatDefs 动态生成 (单一数据源)
local STAT_DEFS = {}
for _, src in ipairs(StatDefs.POINT_STATS) do
    -- 收集子效果描述模板 (通用 + 职业)
    local subEffects = {}
    for _, eff in ipairs(src.effects) do
        subEffects[#subEffects + 1] = { target = eff.target, desc = eff.desc, descMul = eff.descMul or 1, perPoint = eff.perPoint, kind = "universal" }
    end
    if src.classEffects and src.classEffects[StatDefs.CURRENT_CLASS] then
        for _, eff in ipairs(src.classEffects[StatDefs.CURRENT_CLASS]) do
            subEffects[#subEffects + 1] = { target = eff.target, desc = eff.desc, descMul = eff.descMul or 1, perPoint = eff.perPoint, kind = "class" }
        end
    end
    STAT_DEFS[#STAT_DEFS + 1] = { key = src.key, label = src.label, fmt = src.fmtFn, subEffects = subEffects }
end

-- ============================================================================
-- 辅助构建
-- ============================================================================

--- 执行减点操作
local function ExecDeallocate(def, count)
    if count == 1 then
        local ok, err = GameState.DeallocatePoint(def.key)
        if ok then
            SaveSystem.MarkDirty()
            CharacterPage.Refresh()
        elseif err then
            Toast.Warn(err)
        end
    else
        local removed, err = GameState.DeallocatePoints(def.key, count)
        if removed > 0 then
            SaveSystem.MarkDirty()
            CharacterPage.Refresh()
            Toast.Success("-" .. removed .. "点 " .. def.label .. " (消耗" .. removed * 2 .. "魂晶)")
        elseif err then
            Toast.Warn(err)
        end
    end
end

--- 关闭减点确认弹窗
local function CloseDeallocConfirm()
    if deallocOverlay_ then
        deallocOverlay_:Destroy()
        deallocOverlay_ = nil
    end
end

--- 显示减点确认弹窗
---@param def table  属性定义 { key, label }
---@param count integer  减几点
local function ShowDeallocConfirm(def, count)
    CloseDeallocConfirm()
    local cost = count * 2
    local cur = GameState.GetSoulCrystal()
    local allocated = GameState.player.allocatedPoints[def.key] or 0
    local actual = math.min(count, allocated, math.floor(cur / 2))
    local actualCost = actual * 2
    local canDo = actual > 0

    local willSkip = false

    deallocOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 120 },
        alignItems = "center", justifyContent = "center",
        onClick = function() CloseDeallocConfirm() end,
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
                    UI.Label { text = "减少属性点", fontSize = 14, fontColor = { 255, 160, 140, 240 } },
                    UI.Label {
                        text = def.label .. " -" .. actual .. "点",
                        fontSize = 12, fontColor = Colors.text,
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label { text = "消耗: " .. actualCost .. " 魂晶", fontSize = 12, fontColor = { 160, 80, 255, 230 } },
                            UI.Label {
                                text = "(拥有 " .. cur .. ")",
                                fontSize = 10,
                                fontColor = canDo and { 140, 200, 140, 200 } or { 255, 100, 100, 200 },
                            },
                        },
                    },
                    -- 免提示勾选
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
                                text = canDo and "确认" or "魂晶不足",
                                height = 30, fontSize = 13, width = 100,
                                backgroundColor = canDo and { 160, 60, 60, 230 } or { 60, 60, 70, 200 },
                                onClick = Utils.Debounce(function()
                                    if not canDo then return end
                                    if willSkip then skipDeallocConfirm_ = true end
                                    CloseDeallocConfirm()
                                    ExecDeallocate(def, count)
                                end, 0.3),
                            },
                            UI.Button {
                                text = "取消", height = 30, fontSize = 13, width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function() CloseDeallocConfirm() end,
                            },
                        },
                    },
                },
            },
        },
    }

    if page_ then
        page_:AddChild(deallocOverlay_)
    end
end

--- 减点入口（前置检查 + 是否跳过弹窗）
local function RequestDeallocate(def, count)
    local allocated = GameState.player.allocatedPoints[def.key] or 0
    if allocated <= 0 then
        Toast.Warn(def.label .. " 无已分配点数")
        return
    end
    local cur = GameState.GetSoulCrystal()
    if cur < 2 then
        Toast.Warn("魂晶不足 (拥有 " .. cur .. "，需要 2)")
        return
    end
    if skipDeallocConfirm_ then
        ExecDeallocate(def, count)
    else
        ShowDeallocConfirm(def, count)
    end
end

-- 屏幕尺寸分段：根据逻辑宽度返回缩放系数 (1.0 / 1.25 / 1.5)
local function GetScreenScale()
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    if logicalW > 600 then return 1.5
    elseif logicalW > 400 then return 1.25
    else return 1.0 end
end

--- 区块标题行 (图标 + 文字)
local function CreateSectionHeader(text, iconKey)
    local sc = GetScreenScale()
    local iconPath = Config.SECTION_ICON_PATHS[iconKey]
    local children = {}
    if iconPath then
        table.insert(children, UI.Panel {
            width = math.floor(18 * sc), height = math.floor(18 * sc),
            backgroundImage = iconPath,
            backgroundFit = "contain",
        })
    end
    table.insert(children, UI.Label { text = text, fontSize = math.floor(13 * sc), fontColor = Colors.text })
    return UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 5, marginBottom = 4,
        children = children,
    }
end

local function CreateStatRow(def, valueId)
    local sc = GetScreenScale()
    local iconPath = Config.STAT_ICON_PATHS[def.key]
    local rowChildren = {}

    -- 分段缩放字体和控件
    local fsLabel = math.floor(12 * sc)
    local fsValue = math.floor(13 * sc)
    local fsBtn   = math.floor(13 * sc)
    local fsBulk  = math.floor(11 * sc)
    local fsAlloc = math.floor(12 * sc)
    local iconSz  = math.floor(18 * sc)
    local btnW    = math.floor(28 * sc)
    local btnH    = math.floor(24 * sc)
    local bulkW   = math.floor(36 * sc)
    local allocW  = math.floor(30 * sc)
    local rowH    = math.floor(30 * sc)
    local fsSub   = math.floor(10 * sc)

    if iconPath then
        table.insert(rowChildren, UI.Panel {
            width = iconSz, height = iconSz,
            backgroundImage = iconPath,
            backgroundFit = "contain",
        })
    end
    table.insert(rowChildren, UI.Label { text = def.label, fontSize = fsLabel, fontColor = Colors.textDim })
    table.insert(rowChildren, UI.Label { id = valueId, text = "0", fontSize = fsValue, fontColor = Colors.text, marginLeft = 6, flexGrow = 1 })

    -- -10 批量减点按钮
    local bulkMinusBtn = UI.Button {
        text = "-10",
        width = bulkW, height = btnH, fontSize = fsBulk,
        backgroundColor = { 100, 50, 50, 220 },
        fontColor = { 255, 180, 180, 255 },
        visible = false,
        onClick = function()
            RequestDeallocate(def, 10)
        end,
    }
    bulkMinusButtons_[def.key] = bulkMinusBtn
    table.insert(rowChildren, bulkMinusBtn)

    -- - 单点减点按钮
    table.insert(rowChildren, UI.Button {
        text = "-",
        width = btnW, height = btnH, fontSize = fsBtn,
        backgroundColor = { 90, 50, 60, 200 },
        fontColor = { 255, 180, 180, 255 },
        onClick = function()
            RequestDeallocate(def, 1)
        end,
    })

    -- 已分配点数显示
    table.insert(rowChildren, UI.Label {
        id = "char_alloc_" .. def.key,
        text = "0",
        fontSize = fsAlloc,
        fontColor = { 200, 200, 120, 220 },
        width = allocW,
        textAlign = "center",
    })

    -- + 按钮
    table.insert(rowChildren, UI.Button {
        text = "+",
        width = btnW, height = btnH, fontSize = fsBtn,
        backgroundColor = { 60, 70, 90, 200 },
        onClick = function()
            if GameState.AllocatePoint(def.key) then
                SaveSystem.MarkDirty()
                CharacterPage.Refresh()
            end
        end,
    })

    -- +10 批量加点按钮
    local bulkBtn = UI.Button {
        text = "+10",
        width = bulkW, height = btnH, fontSize = fsBulk,
        backgroundColor = { 80, 100, 50, 220 },
        fontColor = { 220, 255, 180, 255 },
        visible = false,
        onClick = function()
            local added = GameState.AllocatePoints(def.key, 10)
            if added > 0 then
                SaveSystem.MarkDirty()
                CharacterPage.Refresh()
            end
        end,
    }
    bulkButtons_[def.key] = bulkBtn
    table.insert(rowChildren, bulkBtn)

    -- 子效果描述行 (通用效果 + 职业效果)
    local subChildren = {}
    if def.subEffects then
        for i, sub in ipairs(def.subEffects) do
            local color = sub.kind == "class"
                and { 120, 200, 255, 200 }   -- 职业效果: 浅蓝
                or  { 160, 180, 160, 200 }   -- 通用效果: 浅灰绿
            local prefix = sub.kind == "class" and "[术]" or ""
            subChildren[#subChildren + 1] = UI.Label {
                id = "char_sub_" .. def.key .. "_" .. i,
                text = prefix .. "...",
                fontSize = fsSub,
                fontColor = color,
            }
        end
    end

    -- 外层容器: 主行 + 子效果行
    return UI.Panel {
        width = "100%",
        gap = 1,
        paddingBottom = 3,
        children = {
            -- 主行: 图标 + 名称 + 点数 + 按钮
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                height = rowH,
                gap = 4,
                children = rowChildren,
            },
            -- 子效果行 (缩进)
            UI.Panel {
                width = "100%",
                paddingLeft = iconPath and (iconSz + 4) or 0,
                gap = 1,
                children = subChildren,
            },
        },
    }
end

local function CreateInfoRow(label, valueId)
    local sc = GetScreenScale()
    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        width = "100%",
        height = math.floor(24 * sc),
        gap = 6,
        children = {
            UI.Label { text = label, fontSize = math.floor(11 * sc), fontColor = Colors.textDim },
            UI.Label { id = valueId, text = "0", fontSize = math.floor(12 * sc), fontColor = Colors.text },
        }
    }
end

-- ============================================================================
-- 各标签页内容构建
-- ============================================================================

--- 属性标签: 固定加点行 + 可滚动属性列表
local function BuildStatsTab()
    local sc = GetScreenScale()
    local statRows = {}
    for _, def in ipairs(STAT_DEFS) do
        table.insert(statRows, CreateStatRow(def, "char_" .. def.key))
    end

    local fsPoints = math.floor(11 * sc)
    local fsReset  = math.floor(10 * sc)
    local resetH   = math.floor(22 * sc)

    return UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        children = {
            -- 固定顶部: 可用点数 + 重置按钮
            UI.Panel {
                width = "100%",
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                paddingHorizontal = 10, paddingVertical = 6,
                backgroundColor = { 16, 20, 32, 230 },
                borderColor = { 160, 130, 60, 140 },
                borderWidth = 1,
                borderRadius = 6,
                flexShrink = 0,
                children = {
                    UI.Label { id = "char_points", text = "可用点数: 0", fontSize = fsPoints, fontColor = Colors.gold },
                    UI.Button {
                        id = "char_reset_btn",
                        text = "重置",
                        height = resetH, fontSize = fsReset,
                        paddingHorizontal = 8,
                        backgroundColor = { 120, 50, 50, 200 },
                        fontColor = { 255, 180, 180, 230 },
                        onClick = Utils.Debounce(function()
                            CharacterPage.ShowResetConfirm()
                        end, 0.3),
                    },
                },
            },
            -- 可滚动: 属性行列表
            UI.Panel {
                width = "100%",
                flexGrow = 1, flexBasis = 0,
                overflow = "scroll",
                paddingHorizontal = 10, paddingVertical = 6,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 2,
                        children = statRows,
                    },
                },
            },
        },
    }
end

--- 生存标签: 生存属性（左列）+ 抗性属性（右列）
local function BuildSurvivalTab()
    return UI.Panel {
        width = "100%", height = "100%",
        overflow = "scroll",
        padding = 10,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                children = {
                    -- 左列：生存属性
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1, gap = 4,
                        children = {
                            CreateSectionHeader("生存属性", "survival"),
                            CreateInfoRow("生命值 HP",   "char_hp"),
                            CreateInfoRow("防御力 DEF",  "char_def"),
                            CreateInfoRow("减伤率",      "char_def_red"),
                            CreateInfoRow("闪避率",      "char_dodge"),
                            CreateInfoRow("回血/秒",     "char_hpreg"),
                            CreateInfoRow("治疗倍率",    "char_healmul"),
                            CreateInfoRow("护盾倍率",    "char_shldmul"),
                            CreateInfoRow("吸血%",       "char_ls"),
                        },
                    },
                    -- 右列：抗性属性
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1, gap = 4,
                        children = {
                            CreateSectionHeader("抗性属性", "resist"),
                            CreateInfoRow("全元素抗性",   "char_all_resist"),
                            CreateInfoRow("减益抗性",     "char_debuff_resist"),
                            CreateInfoRow("火焰抗性",     "char_resist_fire"),
                            CreateInfoRow("冰霜抗性",     "char_resist_ice"),
                            CreateInfoRow("毒素抗性",     "char_resist_poison"),
                            CreateInfoRow("奥术抗性",     "char_resist_arcane"),
                            CreateInfoRow("流水抗性",     "char_resist_water"),
                        },
                    },
                },
            },
        },
    }
end

--- 元素标签: 纯展示
local function BuildElementTab()
    return UI.Panel {
        width = "100%", height = "100%",
        overflow = "scroll",
        padding = 10,
        children = {
            UI.Panel {
                width = "100%", gap = 4,
                children = {
                    CreateSectionHeader("元素属性", "element"),
                    CreateInfoRow("火焰增伤",   "char_fire_dmg"),
                    CreateInfoRow("冰霜增伤",   "char_ice_dmg"),
                    CreateInfoRow("毒素增伤",   "char_poison_dmg"),
                    CreateInfoRow("奥术增伤",   "char_arcane_dmg"),
                    CreateInfoRow("流水增伤",   "char_water_dmg"),
                    CreateInfoRow("反应增伤",   "char_reaction_dmg"),
                },
            },
        },
    }
end

--- 套装标签: 纯展示
local function BuildSetTab()
    local sc = GetScreenScale()
    return UI.Panel {
        width = "100%", height = "100%",
        overflow = "scroll",
        padding = 10,
        children = {
            UI.Panel {
                id = "char_set_panel",
                width = "100%", gap = 2,
                children = {
                    CreateSectionHeader("套装效果", "setbonus"),
                    UI.Panel { id = "char_set_container", width = "100%", gap = 2 },
                },
            },
        },
    }
end

--- 称号标签: 折叠/展开式
local function BuildTitleTab()
    local sc = GetScreenScale()
    titleRows_ = {}
    local allTitles = TitleSystem.GetAllDisplayTitles()
    local equipped = TitleSystem.GetEquipped()

    local children = {
        CreateSectionHeader("称号", "title"),
    }

    if #allTitles == 0 then
        table.insert(children, UI.Label {
            id = "char_title_info",
            text = "无称号", fontSize = math.floor(10 * sc), fontColor = Colors.textDim,
        })
    else
        for _, t in ipairs(allTitles) do
            local tid = t.id
            local owned = t.owned
            local isEquipped = owned and (equipped == tid)

            -- 名称颜色：已拥有金色，未拥有灰色
            local nameColor = owned and Colors.gold or { 100, 105, 115, 180 }
            local descColor = owned and { 180, 185, 195, 200 } or { 90, 95, 105, 150 }

            -- 佩戴/卸下按钮（已拥有时常驻显示）
            local equipBtn = nil
            if owned then
                equipBtn = UI.Button {
                    text = isEquipped and "卸下" or "佩戴",
                    height = math.floor(22 * sc), fontSize = math.floor(9 * sc),
                    paddingHorizontal = 8,
                    backgroundColor = isEquipped and { 120, 60, 60, 220 } or { 60, 80, 120, 220 },
                    fontColor = { 255, 255, 255, 230 },
                    onClick = (function(id)
                        return function()
                            if TitleSystem.GetEquipped() == id then
                                TitleSystem.Unequip()
                            else
                                TitleSystem.Equip(id)
                            end
                            CharacterPage.RefreshTitleButtons()
                        end
                    end)(tid),
                }
            end

            -- 预构建展开详情面板
            local detailChildren = {}
            table.insert(detailChildren, UI.Label {
                text = TitleSystem.FormatEffects(t.effects),
                fontSize = math.floor(10 * sc),
                fontColor = owned and { 140, 220, 140, 230 } or { 100, 110, 120, 160 },
            })
            if owned then
                local timeText = t.unlockedAt and ("获得于 " .. t.unlockedAt) or "获得于早期版本"
                table.insert(detailChildren, UI.Label {
                    text = timeText,
                    fontSize = math.floor(9 * sc),
                    fontColor = { 120, 125, 140, 160 },
                })
            else
                table.insert(detailChildren, UI.Label {
                    text = "尚未获得",
                    fontSize = math.floor(9 * sc),
                    fontColor = { 120, 100, 100, 160 },
                })
            end
            local detailPanel = UI.Panel {
                width = "100%", gap = 3,
                paddingLeft = 10, paddingTop = 4, paddingBottom = 2,
                children = detailChildren,
            }

            -- 箭头标签
            local arrowLabel = UI.Label {
                text = titleExpanded_[tid] and "v" or ">",
                fontSize = math.floor(9 * sc), fontColor = descColor, width = math.floor(12 * sc),
            }

            -- 头部行子元素
            local headerChildren = {
                arrowLabel,
                UI.Label {
                    text = (owned and "【" or "  ") .. t.name .. (owned and "】" or "  "),
                    fontSize = math.floor(11 * sc), fontColor = nameColor,
                },
                UI.Label {
                    text = t.flavorText or t.desc or "",
                    fontSize = math.floor(9 * sc), fontColor = descColor, flexGrow = 1, flexShrink = 1,
                },
            }
            if equipBtn then
                table.insert(headerChildren, equipBtn)
            end

            -- 行容器
            local row = UI.Panel {
                width = "100%",
                paddingVertical = 5, paddingHorizontal = 6,
                backgroundColor = owned and { 40, 45, 60, 120 } or { 30, 32, 40, 80 },
                borderRadius = 6,
                gap = 0,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center",
                        width = "100%", gap = 6,
                        children = headerChildren,
                    },
                },
            }

            -- 存储引用
            titleRows_[tid] = { btn = equipBtn, row = row, detail = detailPanel, arrow = arrowLabel }

            -- 如果初始就是展开状态，直接加上详情
            if titleExpanded_[tid] then
                row:AddChild(detailPanel)
            end

            -- 点击行切换展开/收起（不重建整个页面）
            row:SetStyle({
                onClick = (function(id, rowRef, detailRef, arrowRef)
                    return function()
                        if titleExpanded_[id] then
                            titleExpanded_[id] = false
                            rowRef:RemoveChild(detailRef)
                            arrowRef:SetText(">")
                        else
                            titleExpanded_[id] = true
                            rowRef:AddChild(detailRef)
                            arrowRef:SetText("v")
                        end
                    end
                end)(tid, row, detailPanel, arrowLabel),
            })

            table.insert(children, row)
        end
    end

    return UI.Panel {
        width = "100%", height = "100%",
        overflow = "scroll",
        padding = 10,
        children = {
            UI.Panel {
                id = "char_title_panel",
                width = "100%", gap = 4,
                children = children,
            },
        },
    }
end

-- ============================================================================
-- 创建 & 刷新
-- ============================================================================

function CharacterPage.Create()
    local CHAR_TAB_DEFS = {
        { id = "stats",    label = "属性" },
        { id = "survival", label = "生存" },
        { id = "element",  label = "元素" },
        { id = "set",      label = "套装" },
        { id = "title",    label = "称号" },
    }

    -- 构建各 tab 内容
    charTabPages_ = {
        stats    = BuildStatsTab(),
        survival = BuildSurvivalTab(),
        element  = BuildElementTab(),
        set      = BuildSetTab(),
        title    = BuildTitleTab(),
    }

    charActiveTab_ = "stats"

    -- 内容容器
    charTabContent_ = UI.Panel {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        overflow = "hidden",
        children = { charTabPages_.stats },
    }

    -- tab 按钮样式
    local TAB_ACTIVE_BG   = { 60, 90, 180, 255 }
    local TAB_INACTIVE_BG = { 30, 36, 50, 200 }
    local TAB_ACTIVE_FG   = { 255, 255, 255, 255 }
    local TAB_INACTIVE_FG = { 140, 150, 170, 220 }

    local function updateCharTabStyles()
        if not charTabButtons_ then return end
        for _, info in ipairs(charTabButtons_) do
            local isActive = info.id == charActiveTab_
            info.bg:SetStyle({ backgroundColor = isActive and TAB_ACTIVE_BG or TAB_INACTIVE_BG })
            info.label:SetStyle({ fontColor = isActive and TAB_ACTIVE_FG or TAB_INACTIVE_FG })
        end
    end

    local function switchCharTab(tabId)
        if tabId == charActiveTab_ then return end
        charActiveTab_ = tabId
        charTabContent_:ClearChildren()
        charTabContent_:AddChild(charTabPages_[tabId])
        updateCharTabStyles()
    end

    -- 构建 tab 按钮行
    local sc = GetScreenScale()
    local tabH = math.floor(30 * sc)
    local tabFs = math.floor(11 * sc)
    charTabButtons_ = {}
    local btnChildren = {}
    for _, def in ipairs(CHAR_TAB_DEFS) do
        local isActive = def.id == charActiveTab_
        local label = UI.Label {
            text = def.label,
            fontSize = tabFs,
            fontColor = isActive and TAB_ACTIVE_FG or TAB_INACTIVE_FG,
        }
        local bg = UI.Panel {
            flexGrow = 1, flexBasis = 0,
            height = tabH,
            alignItems = "center", justifyContent = "center",
            backgroundColor = isActive and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
            borderRadius = 4,
            onClick = (function(tid)
                return function() switchCharTab(tid) end
            end)(def.id),
            children = { label },
        }
        table.insert(charTabButtons_, { id = def.id, bg = bg, label = label })
        table.insert(btnChildren, bg)
    end

    page_ = UI.Panel {
        width = "100%",
        flexGrow = 1, flexBasis = 0,
        flexDirection = "column",
        children = {
            -- tab 按钮行
            UI.Panel {
                width = "100%", height = tabH,
                flexDirection = "row",
                gap = 2,
                paddingHorizontal = 4,
                backgroundColor = { 22, 26, 36, 230 },
                flexShrink = 0,
                children = btnChildren,
            },
            -- tab 内容区
            charTabContent_,
        },
    }
    return page_
end

-- 智能格式化: 整数不带小数, 非整数最多1位
local function fmtPct(val)
    local v = val * 100
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then
        return string.format("%.0f%%", v)
    else
        return string.format("%.1f%%", v)
    end
end
local function fmtMul(val)
    if math.abs(val - math.floor(val + 0.5)) < 0.005 then
        return string.format("x%.0f", val)
    else
        return string.format("x%.1f", val)
    end
end

--- 构建非动态数据的快照 key
local function CharKey()
    local p = GameState.player
    local parts = { p.freePoints, p.level }
    for _, def in ipairs(STAT_DEFS) do
        parts[#parts + 1] = p.allocatedPoints[def.key] or 0
    end
    -- 装备状态
    local equipped = GameState.equipped or {}
    for i = 1, #equipped do
        local eq = equipped[i]
        parts[#parts + 1] = eq and eq.id or 0
    end
    -- 魂晶影响减点按钮可见性
    parts[#parts + 1] = GameState.GetSoulCrystal()
    -- 称号数量 + 佩戴状态
    parts[#parts + 1] = GameState.unlockedTitles and #GameState.unlockedTitles or 0
    parts[#parts + 1] = GameState.equippedTitle or ""
    return table.concat(parts, ",")
end

--- 在所有标签内容中查找控件
local function findWidget(id)
    if not charTabPages_ then return nil end
    -- 先在 page_ 中找
    if page_ then
        local w = page_:FindById(id)
        if w then return w end
    end
    -- 在各标签内容中找
    for _, content in pairs(charTabPages_) do
        local w = content:FindById(id)
        if w then return w end
    end
    return nil
end

--- 刷新称号佩戴按钮状态
function CharacterPage.RefreshTitleButtons()
    local equipped = TitleSystem.GetEquipped()
    for tid, ref in pairs(titleRows_) do
        if ref.btn then
            local isEquipped = (equipped == tid)
            ref.btn:SetText(isEquipped and "卸下" or "佩戴")
            ref.btn:SetStyle({
                backgroundColor = isEquipped and { 120, 60, 60, 220 } or { 60, 80, 120, 220 },
            })
        end
    end
end

--- 重置脏标记，强制下次 Refresh 执行完整刷新
function CharacterPage.InvalidateCache()
    lastCharKey_ = ""
    lastHP_ = ""
    -- 重建称号 tab（称号列表是一次性构建的，需要整体替换）
    if charTabPages_ then
        charTabPages_.title = BuildTitleTab()
        -- 如果称号 tab 正在显示，立即替换内容
        if charActiveTab_ == "title" and charTabContent_ then
            charTabContent_:ClearChildren()
            charTabContent_:AddChild(charTabPages_.title)
        end
    end
end

function CharacterPage.Refresh()
    if not page_ then return end
    local p = GameState.player

    local function set(id, text)
        local w = findWidget(id)
        if w then w:SetText(tostring(text)) end
    end

    -- ── 动态层：HP（战斗中持续变化）──────────────────
    local hpStr = Utils.FormatNumber(GameState.playerHP) .. " / " .. Utils.FormatNumber(GameState.GetMaxHP())
    if hpStr ~= lastHP_ then
        lastHP_ = hpStr
        set("char_hp", hpStr)
    end

    -- ── 非动态层：属性 / 按钮 / 套装（仅数据变化时刷新）──
    local curKey = CharKey()
    if curKey == lastCharKey_ then return end
    lastCharKey_ = curKey

    set("char_points", "可用点数: " .. p.freePoints)

    -- +10 按钮可见性
    local showBulk = p.freePoints > 10
    for _, def in ipairs(STAT_DEFS) do
        local btn = bulkButtons_[def.key]
        if btn then btn:SetVisible(showBulk) end
    end

    -- -10 按钮可见性
    for _, def in ipairs(STAT_DEFS) do
        local btn = bulkMinusButtons_[def.key]
        if btn then
            local allocated = p.allocatedPoints[def.key] or 0
            btn:SetVisible(allocated >= 10)
        end
    end

    -- 已分配点数 & 属性值 & 子效果
    for _, def in ipairs(STAT_DEFS) do
        local allocated = p.allocatedPoints[def.key] or 0
        set("char_alloc_" .. def.key, tostring(allocated))
        set("char_" .. def.key, def.fmt())

        -- 子效果数值刷新
        if def.subEffects then
            local maxCh = (GameState.records and GameState.records.maxChapter)
                       or (GameState.stage and GameState.stage.chapter)
                       or 1
            for i, sub in ipairs(def.subEffects) do
                local totalVal = allocated * sub.perPoint * sub.descMul
                -- STR 护甲需乘 attrScale (绝对值属性跟随章节缩放)
                if sub.target == "def" then
                    local attrScale = Config.GetAttrScale(maxCh)
                    totalVal = allocated * sub.perPoint * attrScale * sub.descMul
                end
                -- Lua 5.4: %d 要求整数表示, 浮点数需先 floor
                if sub.desc:find("%%d") then
                    totalVal = math.floor(totalVal)
                end
                local prefix = sub.kind == "class" and "[术] " or ""
                local text = prefix .. string.format(sub.desc, totalVal)
                set("char_sub_" .. def.key .. "_" .. i, text)
            end
        end
    end

    -- 生存属性（排除 HP，已在动态层处理）
    set("char_def",     Utils.FormatNumber(GameState.GetTotalDEF()))
    set("char_def_red", fmtPct(1 - GameState.GetDEFMul()))
    set("char_dodge",   fmtPct(GameState.GetDodgeChance()))
    set("char_hpreg",   string.format("%.1f", GameState.GetHPRegen()))
    set("char_healmul", fmtPct(GameState.GetHealMul()))
    set("char_shldmul", fmtPct(GameState.GetShieldMul()))
    set("char_ls",      fmtPct(GameState.GetLifeSteal()))

    -- 抗性属性
    set("char_all_resist",    fmtPct(GameState.GetAllResist()))
    set("char_debuff_resist", fmtPct(GameState.GetDebuffResist()))
    set("char_resist_fire",   fmtPct(GameState.GetElementResist("fire")))
    set("char_resist_ice",    fmtPct(GameState.GetElementResist("ice")))
    set("char_resist_poison", fmtPct(GameState.GetElementResist("poison")))
    set("char_resist_arcane", fmtPct(GameState.GetElementResist("arcane")))
    set("char_resist_water",  fmtPct(GameState.GetElementResist("water")))

    -- 元素增伤
    set("char_fire_dmg",    "+" .. fmtPct(GameState.GetSpecificElemDmg("fireDmg")))
    set("char_ice_dmg",     "+" .. fmtPct(GameState.GetSpecificElemDmg("iceDmg")))
    set("char_poison_dmg",  "+" .. fmtPct(GameState.GetSpecificElemDmg("poisonDmg")))
    set("char_arcane_dmg",  "+" .. fmtPct(GameState.GetSpecificElemDmg("arcaneDmg")))
    set("char_water_dmg",   "+" .. fmtPct(GameState.GetSpecificElemDmg("waterDmg")))
    set("char_reaction_dmg", fmtMul(GameState.GetReactionDmgBonus()))

    -- 套装信息（逐行构建，激活项高亮）
    local sc = GetScreenScale()
    local setContainer = findWidget("char_set_container")
    if setContainer then
        setContainer:ClearChildren()
        local setCounts = GameState.GetEquippedSetCounts()
        local hasSet = false
        for setId, count in pairs(setCounts) do
            local setCfg = Config.EQUIP_SET_MAP[setId]
            if setCfg then
                hasSet = true
                -- 套装名称行
                setContainer:AddChild(UI.Label {
                    text = setCfg.name .. " (" .. count .. "件)",
                    fontSize = math.floor(11 * sc),
                    fontColor = Colors.gold,
                    marginTop = 4,
                })
                -- 各阈值效果
                local thresholds = {}
                for threshold, _ in pairs(setCfg.bonuses) do
                    table.insert(thresholds, threshold)
                end
                table.sort(thresholds)
                for _, threshold in ipairs(thresholds) do
                    local bonus = setCfg.bonuses[threshold]
                    local active = count >= threshold
                    local iconSize = math.floor(12 * sc)
                    local row = UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        gap = math.floor(3 * sc),
                        paddingLeft = math.floor(4 * sc),
                    }
                    row:AddChild(UI.Panel {
                        width = iconSize, height = iconSize,
                        backgroundImage = active
                            and "set_active_check_20260314130321.png"
                            or  "set_inactive_slash_20260314131510.png",
                    })
                    row:AddChild(UI.Label {
                        text = threshold .. "件: " .. bonus.desc,
                        fontSize = math.floor(10 * sc),
                        fontColor = active
                            and { 100, 230, 120, 255 }
                            or  { 120, 120, 140, 160 },
                    })
                    setContainer:AddChild(row)
                end
            end
        end
        if not hasSet then
            setContainer:AddChild(UI.Label {
                text = "无激活套装",
                fontSize = math.floor(10 * sc),
                fontColor = Colors.textDim,
            })
        end
    end

    -- 称号佩戴按钮
    CharacterPage.RefreshTitleButtons()
end

-- ============================================================================
-- 重置属性点确认弹窗
-- ============================================================================

function CharacterPage.CloseResetConfirm()
    if resetOverlay_ then
        resetOverlay_:Destroy()
        resetOverlay_ = nil
    end
end

function CharacterPage.ShowResetConfirm()
    CharacterPage.CloseResetConfirm()

    local allocated = GameState.GetTotalAllocatedPoints()
    if allocated <= 0 then
        Toast.Warn("没有已分配的属性点")
        return
    end

    local cost = GameState.GetResetAttrCost()
    local cur = GameState.GetSoulCrystal()
    local canReset = cur >= cost

    -- 构建各属性已分配点数明细
    local detailLines = {}
    for _, def in ipairs(STAT_DEFS) do
        local pts = GameState.player.allocatedPoints[def.key] or 0
        if pts > 0 then
            table.insert(detailLines, def.label .. ": " .. pts .. "点")
        end
    end

    resetOverlay_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        zIndex = 300,
        backgroundColor = { 0, 0, 0, 120 },
        alignItems = "center", justifyContent = "center",
        onClick = function() CharacterPage.CloseResetConfirm() end,
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = { 18, 22, 34, 245 },
                borderColor = { 120, 50, 50, 200 },
                borderWidth = 1, borderRadius = 8,
                padding = 14, gap = 8,
                alignItems = "center",
                onClick = function() end,  -- 阻止穿透
                children = {
                    UI.Label { text = "重置属性点", fontSize = 14, fontColor = { 255, 140, 140, 240 } },
                    UI.Label { text = "回收全部 " .. allocated .. " 个属性点", fontSize = 11, fontColor = { 200, 210, 230, 220 } },
                    UI.Label { text = table.concat(detailLines, "  "), fontSize = 9, fontColor = Colors.textDim },
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
                                    local ok, err = GameState.ResetAttributePoints()
                                    if ok then
                                        SaveSystem.SaveNow()
                                        Toast.Success("属性点已重置")
                                        CharacterPage.CloseResetConfirm()
                                        CharacterPage.Refresh()
                                    elseif err then
                                        Toast.Warn(err)
                                    end
                                end, 0.5),
                            },
                            UI.Button {
                                text = "取消", height = 32, fontSize = 13, width = 80,
                                backgroundColor = { 60, 65, 75, 200 },
                                onClick = function() CharacterPage.CloseResetConfirm() end,
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

return CharacterPage
