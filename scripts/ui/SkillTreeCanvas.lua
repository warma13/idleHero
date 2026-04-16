-- ============================================================================
-- ui/SkillTreeCanvas.lua - D4 风格技能树 NanoVG 画布 Widget
-- 垂直分支树渲染 + 拖拽/缩放交互
-- ============================================================================

local UI = require("urhox-libs/UI")
local GameState = require("GameState")
local SkillTreeConfig = require("SkillTreeConfig")
local Config = require("Config")
local SkillTreeLayout = require("ui.SkillTreeLayout")

-- ============================================================================
-- 元素颜色
-- ============================================================================

local ELEM_COLORS = {}
for _, e in ipairs(SkillTreeConfig.ELEMENTS) do
    ELEM_COLORS[e.id] = e.color
end
ELEM_COLORS["none"] = { 180, 180, 180 }

local function GetSkillColor(skill)
    return ELEM_COLORS[skill.element or "none"] or ELEM_COLORS["none"]
end

-- ============================================================================
-- 颜色常量
-- ============================================================================

local COL_SPINE       = { 60, 80, 120 }       -- 脊柱线
local COL_SPINE_GLOW  = { 80, 120, 180 }      -- 脊柱发光
local COL_BG          = { 12, 14, 22 }        -- 画布背景
local COL_BRANCH      = { 50, 60, 90 }        -- 分支线
local COL_GATE_LOCK   = { 60, 55, 70 }        -- 锁定门槛
local COL_GATE_OPEN   = { 80, 100, 140 }      -- 解锁门槛
local COL_NODE_LOCKED = { 30, 35, 50 }        -- 锁定节点底色
local COL_SELECT      = { 255, 255, 255 }     -- 选中高亮
local COL_TIER_LABEL  = { 140, 150, 180 }     -- 层级标签

-- ============================================================================
-- Widget 定义
-- ============================================================================

local SkillTreeCanvas = UI.Widget:Extend("SkillTreeCanvas")

function SkillTreeCanvas:Init(props)
    props = props or {}
    props.height = props.height or 300
    props.width = props.width or "100%"
    UI.Widget.Init(self, props)

    -- 变换状态
    self.panX_   = 0
    self.panY_   = 0
    self.zoom_   = 0.55  -- 默认缩放, 让树在窄视口下可见
    self.minZoom_ = 0.25
    self.maxZoom_ = 2.0

    -- 拖拽状态
    self.dragging_    = false
    self.dragStartX_  = 0
    self.dragStartY_  = 0
    self.dragStartPX_ = 0
    self.dragStartPY_ = 0
    self.dragDist_    = 0

    -- 惯性
    self.velX_ = 0
    self.velY_ = 0

    -- 上一帧鼠标位置 (惯性计算用)
    self.lastMoveX_ = 0
    self.lastMoveY_ = 0

    -- 选中
    self.selectedId_ = nil
    self.onSelect_   = props.onSelect

    -- 缩放手势
    self.pinchStartZoom_ = nil

    -- 布局缓存
    self.layout_ = SkillTreeLayout.Build()

    -- 背景纹理 (自动加载)
    self.bgHandle_ = nil
    self.bgReady_  = false
    self.bgPath_   = "image/skill_tree_bg_20260325184632.png"

    -- 动画计时
    self.animTime_ = 0

    -- 初始平移: 居中到 T3-T4 区域
    self:CenterOnTier(3)
end

-- ============================================================================
-- 坐标变换
-- ============================================================================

--- 屏幕坐标 → 画布坐标
function SkillTreeCanvas:ScreenToCanvas(sx, sy)
    local l = self:GetAbsoluteLayout()
    if not l then return 0, 0 end
    return (sx - l.x - self.panX_) / self.zoom_,
           (sy - l.y - self.panY_) / self.zoom_
end

--- 将指定层居中显示
function SkillTreeCanvas:CenterOnTier(tierIdx)
    local l = self:GetAbsoluteLayout()
    local visW = l and l.w or 360
    local visH = l and l.h or 400

    local targetY = self.layout_.TIER_START_Y + (tierIdx - 1) * self.layout_.TIER_SPACING_Y
    local targetX = self.layout_.SPINE_X

    self.panX_ = visW / 2 - targetX * self.zoom_
    self.panY_ = visH / 2 - targetY * self.zoom_
end

--- 将指定节点居中显示
function SkillTreeCanvas:CenterOnNode(skillId)
    local l = self:GetAbsoluteLayout()
    local visW = l and l.w or 360
    local visH = l and l.h or 400

    local nd = self.layout_.nodes[skillId] or self.layout_.enhNodes[skillId]
    if not nd then return end

    self.panX_ = visW / 2 - nd.x * self.zoom_
    self.panY_ = visH / 2 - nd.y * self.zoom_
end

--- 限制平移范围, 保证树内容不会完全移出视口
function SkillTreeCanvas:ClampPan()
    local l = self:GetAbsoluteLayout()
    if not l or l.w <= 0 or l.h <= 0 then return end

    local layout = self.layout_
    local z = self.zoom_
    -- 画布内容在屏幕空间的尺寸
    local contentW = layout.canvasW * z
    local contentH = layout.canvasH * z
    -- 允许至少 30% 的内容留在视口内
    local marginX = l.w * 0.3
    local marginY = l.h * 0.3

    -- panX 范围: 内容右边至少 marginX 在视口内, 左边至少 marginX 在视口内
    local minPanX = l.w - contentW - marginX   -- 向左拖到头
    local maxPanX = marginX                     -- 向右拖到头
    -- panY 范围
    local minPanY = l.h - contentH - marginY
    local maxPanY = marginY

    -- 如果内容比视口小, 居中
    if contentW < l.w then
        local center = (l.w - contentW) / 2
        minPanX = center
        maxPanX = center
    end
    if contentH < l.h then
        local center = (l.h - contentH) / 2
        minPanY = center
        maxPanY = center
    end

    self.panX_ = math.max(minPanX, math.min(maxPanX, self.panX_))
    self.panY_ = math.max(minPanY, math.min(maxPanY, self.panY_))
end

-- ============================================================================
-- 渲染
-- ============================================================================

function SkillTreeCanvas:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if not l then return end
    if l.w <= 0 or l.h <= 0 then return end
    local layout = self.layout_
    local time = self.animTime_

    -- 首帧校正: Init 时 layout 不可用, 首帧用真实尺寸重新居中
    if not self.initialCentered_ then
        self.initialCentered_ = true
        self:CenterOnTier(3)
    end

    -- 1. 裁剪
    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- 背景填充 (画布外围)
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillColor(nvg, nvgRGBA(COL_BG[1], COL_BG[2], COL_BG[3], 255))
    nvgFill(nvg)

    -- 2. 应用画布变换
    nvgSave(nvg)
    nvgTranslate(nvg, l.x + self.panX_, l.y + self.panY_)
    nvgScale(nvg, self.zoom_, self.zoom_)

    -- 3. 背景纹理 (首次渲染时自动加载)
    if not self.bgReady_ and self.bgPath_ then
        self:LoadBackground(nvg, self.bgPath_)
    end
    self:DrawBackground(nvg, layout)

    -- 4. 脊柱线
    self:DrawSpine(nvg, layout, time)

    -- 5. 分支连线 (脊柱→技能)
    self:DrawBranchLines(nvg, layout)

    -- 6. 门槛节点
    self:DrawGates(nvg, layout)

    -- 7. 增强连线
    self:DrawEnhanceLines(nvg, layout)

    -- 8-10. 技能节点 + 增强节点 + 文字
    self:DrawSkillNodes(nvg, layout, time)
    self:DrawEnhanceNodes(nvg, layout)

    -- 13. 层级标签 (脊柱旁)
    self:DrawTierLabels(nvg, layout)

    -- 恢复画布变换
    nvgRestore(nvg)

    -- 恢复裁剪
    nvgRestore(nvg)
end

-- ============================================================================
-- 绘制子函数
-- ============================================================================

--- 背景纹理 (平铺覆盖整个可见视口)
function SkillTreeCanvas:DrawBackground(nvg, layout)
    if self.bgHandle_ and self.bgHandle_ > 0 then
        -- 计算可见区域 (在画布空间中)
        local l = self:GetAbsoluteLayout()
        if not l then return end
        local z = self.zoom_
        local visL = -self.panX_ / z
        local visT = -self.panY_ / z
        local visW = l.w / z
        local visH = l.h / z
        -- 扩展一些边距确保覆盖
        local margin = 100
        local rx = visL - margin
        local ry = visT - margin
        local rw = visW + margin * 2
        local rh = visH + margin * 2

        local patW, patH = 512, 512
        local pat = nvgImagePattern(nvg, 0, 0, patW, patH, 0, self.bgHandle_, 0.25)
        nvgBeginPath(nvg)
        nvgRect(nvg, rx, ry, rw, rh)
        nvgFillPaint(nvg, pat)
        nvgFill(nvg)
    end
end

--- 脊柱线 (中央垂直发光线)
function SkillTreeCanvas:DrawSpine(nvg, layout, time)
    local sx = layout.SPINE_X
    local sy1 = layout.TIER_START_Y - 30
    local sy2 = layout.TIER_START_Y + 6 * layout.TIER_SPACING_Y + 30

    -- 发光层
    local glowAlpha = math.floor(40 + 15 * math.sin(time * 1.5))
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, sx, sy1)
    nvgLineTo(nvg, sx, sy2)
    nvgStrokeWidth(nvg, 6)
    nvgStrokeColor(nvg, nvgRGBA(COL_SPINE_GLOW[1], COL_SPINE_GLOW[2], COL_SPINE_GLOW[3], glowAlpha))
    nvgStroke(nvg)

    -- 主线
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, sx, sy1)
    nvgLineTo(nvg, sx, sy2)
    nvgStrokeWidth(nvg, 2)
    nvgStrokeColor(nvg, nvgRGBA(COL_SPINE[1], COL_SPINE[2], COL_SPINE[3], 160))
    nvgStroke(nvg)
end

--- 分支连线 (脊柱→技能节点)
function SkillTreeCanvas:DrawBranchLines(nvg, layout)
    for _, nd in pairs(layout.nodes) do
        local spineY = nd.y
        local alpha = 50
        local lv = GameState.GetSkillLevel(nd.skill.id)
        if lv > 0 then alpha = 100 end

        -- 从脊柱画到节点
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, layout.SPINE_X, spineY)
        nvgLineTo(nvg, nd.x, nd.y)
        nvgStrokeWidth(nvg, lv > 0 and 1.5 or 0.8)
        nvgStrokeColor(nvg, nvgRGBA(COL_BRANCH[1], COL_BRANCH[2], COL_BRANCH[3], alpha))
        nvgStroke(nvg)
    end
end

--- 门槛节点
function SkillTreeCanvas:DrawGates(nvg, layout)
    local spent = GameState.GetSpentSkillPts()

    for t = 2, 7 do
        local g = layout.gates[t]
        if not g then goto continue_gate end

        local unlocked = spent >= g.gate
        local col = unlocked and COL_GATE_OPEN or COL_GATE_LOCK
        local tier = SkillTreeConfig.TIERS[t]
        local tc = tier and tier.color or col

        -- 圆形门槛
        nvgBeginPath(nvg)
        nvgCircle(nvg, g.x, g.y, layout.GATE_RADIUS)
        nvgFillColor(nvg, nvgRGBA(col[1], col[2], col[3], unlocked and 180 or 100))
        nvgFill(nvg)

        -- 边框
        nvgStrokeWidth(nvg, unlocked and 2 or 1)
        nvgStrokeColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], unlocked and 200 or 80))
        nvgStroke(nvg)

        -- 门槛数字
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 10)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if unlocked then
            nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], 220))
            nvgText(nvg, g.x, g.y, "✓")
        else
            nvgFillColor(nvg, nvgRGBA(200, 200, 220, 160))
            nvgText(nvg, g.x, g.y, tostring(g.gate))
        end

        ::continue_gate::
    end
end

--- 增强连线 (父技能→增强卫星, 前置增强→依赖增强)
function SkillTreeCanvas:DrawEnhanceLines(nvg, layout)
    for enhId, en in pairs(layout.enhNodes) do
        local parent = layout.nodes[en.parentId]
        if not parent then goto continue_enh end

        local parentSkill = parent.skill
        local enhLv = GameState.GetSkillLevel(en.enh.id)
        local ec = GetSkillColor(parentSkill)

        -- 检查此 line 是否有 requires 前置依赖
        local info = SkillTreeConfig.ENHANCE_MAP[enhId]
        local line = info and parentSkill.enhances[info.lineIdx]
        local reqId = line and line.requires

        -- 隐式Y形子节点: 从Y根节点连过来
        local implicitParentId = en.implicitYParent
        if implicitParentId then
            local rootNode = layout.enhNodes[implicitParentId]
            if rootNode then
                local rootLv = GameState.GetSkillLevel(implicitParentId)
                local alpha = (rootLv > 0 and enhLv > 0) and 150 or 40
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, rootNode.x, rootNode.y)
                nvgLineTo(nvg, en.x, en.y)
                nvgStrokeWidth(nvg, enhLv > 0 and 1.5 or 0.6)
                nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], alpha))
                nvgStroke(nvg)
            end
        elseif reqId then
            -- 显式前置: 从前置增强节点连过来
            local reqNode = layout.enhNodes[reqId]
            if reqNode then
                local reqLv = GameState.GetSkillLevel(reqId)
                local alpha = (reqLv > 0 and enhLv > 0) and 150 or 40
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, reqNode.x, reqNode.y)
                nvgLineTo(nvg, en.x, en.y)
                nvgStrokeWidth(nvg, enhLv > 0 and 1.5 or 0.6)
                nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], alpha))
                nvgStroke(nvg)
            end
        else
            -- 无前置: 从父技能节点连过来
            local alpha = enhLv > 0 and 150 or 50
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, parent.x, parent.y)
            nvgLineTo(nvg, en.x, en.y)
            nvgStrokeWidth(nvg, enhLv > 0 and 1.5 or 0.6)
            nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], alpha))
            nvgStroke(nvg)
        end

        ::continue_enh::
    end
end

--- 技能节点 (方形/菱形)
function SkillTreeCanvas:DrawSkillNodes(nvg, layout, time)
    local NS = layout.NODE_SIZE

    for skillId, nd in pairs(layout.nodes) do
        local skill = nd.skill
        local lv = GameState.GetSkillLevel(skillId)
        local canUp, _ = GameState.CanUpgradeSkill(skillId)
        local isSelected = self.selectedId_ == skillId
        local isMaxed = lv >= skill.maxLevel
        local isUnlocked = lv > 0
        local ec = GetSkillColor(skill)
        local cx, cy = nd.x, nd.y
        local hs = NS * 0.5

        -- 选中高亮环
        if isSelected then
            local pulseA = math.floor(180 + 40 * math.sin(time * 4))
            nvgBeginPath(nvg)
            if skill.isKeyPassive then
                nvgCircle(nvg, cx, cy, hs + 5)
            else
                nvgRoundedRect(nvg, cx - hs - 4, cy - hs - 4, NS + 8, NS + 8, 10)
            end
            nvgStrokeWidth(nvg, 2.5)
            nvgStrokeColor(nvg, nvgRGBA(COL_SELECT[1], COL_SELECT[2], COL_SELECT[3], pulseA))
            nvgStroke(nvg)
        end

        -- 可升级脉冲环
        if canUp and not isMaxed then
            local pulseA = math.floor(100 + 80 * math.sin(time * 3))
            nvgBeginPath(nvg)
            if skill.isKeyPassive then
                nvgCircle(nvg, cx, cy, hs + 2)
            else
                nvgRoundedRect(nvg, cx - hs - 2, cy - hs - 2, NS + 4, NS + 4, 9)
            end
            nvgStrokeWidth(nvg, 1.5)
            nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], pulseA))
            nvgStroke(nvg)
        end

        -- 背景色计算
        local bgR, bgG, bgB, bgA
        if isMaxed then
            bgR, bgG, bgB, bgA = ec[1], ec[2], ec[3], 200
        elseif isUnlocked then
            bgR = math.floor(ec[1] * 0.4 + 25)
            bgG = math.floor(ec[2] * 0.4 + 25)
            bgB = math.floor(ec[3] * 0.4 + 25)
            bgA = 220
        else
            bgR, bgG, bgB, bgA = COL_NODE_LOCKED[1], COL_NODE_LOCKED[2], COL_NODE_LOCKED[3], 160
        end

        -- 绘制节点形状
        if skill.isKeyPassive then
            -- 圆形
            nvgBeginPath(nvg)
            nvgCircle(nvg, cx, cy, hs)
            nvgFillColor(nvg, nvgRGBA(bgR, bgG, bgB, bgA))
            nvgFill(nvg)
            nvgStrokeWidth(nvg, isUnlocked and 1.5 or 1)
            if isUnlocked then
                nvgStrokeColor(nvg, nvgRGBA(220, 180, 255, 200))
            else
                nvgStrokeColor(nvg, nvgRGBA(80, 70, 100, 100))
            end
            nvgStroke(nvg)
        else
            -- 方形
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, cx - hs, cy - hs, NS, NS, 7)
            nvgFillColor(nvg, nvgRGBA(bgR, bgG, bgB, bgA))
            nvgFill(nvg)
            nvgStrokeWidth(nvg, isUnlocked and 1.5 or 1)
            if isUnlocked then
                nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], 180))
            else
                nvgStrokeColor(nvg, nvgRGBA(50, 60, 80, 120))
            end
            nvgStroke(nvg)
        end

        -- 终极标记 (右上金色菱形)
        if skill.isUltimate then
            local dx = cx + hs - 6
            local dy = cy - hs + 6
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, dx, dy - 4)
            nvgLineTo(nvg, dx + 4, dy)
            nvgLineTo(nvg, dx, dy + 4)
            nvgLineTo(nvg, dx - 4, dy)
            nvgClosePath(nvg)
            nvgFillColor(nvg, nvgRGBA(255, 215, 0, isUnlocked and 240 or 80))
            nvgFill(nvg)
        end

        -- 技能图标 (文字回退)
        local iconPath = Config.SKILL_ICON_PATHS and Config.SKILL_ICON_PATHS[skillId]
        local iconDrawn = false
        if iconPath then
            if not self.iconHandles_ then self.iconHandles_ = {} end
            if not self.iconHandles_[skillId] then
                self.iconHandles_[skillId] = nvgCreateImage(nvg, iconPath, 0)
            end
            local imgH = self.iconHandles_[skillId]
            if imgH and imgH > 0 then
                local iconAlpha = isUnlocked and 1.0 or 0.35
                local pad = 4
                local imgPaint = nvgImagePattern(nvg, cx - hs + pad, cy - hs + pad,
                    NS - pad * 2, NS - pad * 2, 0, imgH, iconAlpha)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, cx - hs + pad, cy - hs + pad,
                    NS - pad * 2, NS - pad * 2, 5)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
                iconDrawn = true
            end
        end

        if not iconDrawn then
            -- 文字回退: 技能名
            local nameAlpha = isUnlocked and 230 or 100
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 9)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, nameAlpha))
            local shortName = skill.name
            if #shortName > 12 then shortName = string.sub(shortName, 1, 12) end
            nvgText(nvg, cx, cy - 3, shortName)
        end

        -- 等级显示 (底部)
        local lvText = lv .. "/" .. skill.maxLevel
        if isMaxed then lvText = "MAX" end
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 8)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if isMaxed then
            nvgFillColor(nvg, nvgRGBA(255, 215, 0, 230))
        else
            nvgFillColor(nvg, nvgRGBA(200, 210, 230, isUnlocked and 200 or 80))
        end
        nvgText(nvg, cx, cy + hs - 5, lvText)

        -- 元素色点 (左上)
        if skill.element and not skill.isKeyPassive then
            local eCol = ELEM_COLORS[skill.element]
            if eCol then
                nvgBeginPath(nvg)
                nvgCircle(nvg, cx - hs + 5, cy - hs + 5, 3)
                nvgFillColor(nvg, nvgRGBA(eCol[1], eCol[2], eCol[3], isUnlocked and 220 or 70))
                nvgFill(nvg)
            end
        end
    end
end

--- 增强节点 (菱形小节点)
function SkillTreeCanvas:DrawEnhanceNodes(nvg, layout)
    local ES = layout.ENH_SIZE

    for enhId, en in pairs(layout.enhNodes) do
        local parent = layout.nodes[en.parentId]
        if not parent then goto continue_enh end

        local parentSkill = parent.skill
        local lv = GameState.GetSkillLevel(enhId)
        local isSelected = self.selectedId_ == enhId
        local ec = GetSkillColor(parentSkill)
        local cx, cy = en.x, en.y
        local hs = ES * 0.5

        -- 前置依赖检查
        local info = SkillTreeConfig.ENHANCE_MAP[enhId]
        local isRequiresLocked = false
        if info then
            local line = parentSkill.enhances[info.lineIdx]
            if line then
                -- 跨线前置依赖: requires 指定的增强节点未学则锁定
                if line.requires and GameState.GetSkillLevel(line.requires) <= 0 then
                    isRequiresLocked = true
                end
                -- 隐式Y形子节点: Y根节点未学则锁定
                if en.implicitYParent and GameState.GetSkillLevel(en.implicitYParent) <= 0 then
                    isRequiresLocked = true
                end
            end
        end
        local isLocked = isRequiresLocked

        -- 选中高亮
        if isSelected then
            nvgBeginPath(nvg)
            local selHs = hs + 3
            nvgMoveTo(nvg, cx, cy - selHs)
            nvgLineTo(nvg, cx + selHs, cy)
            nvgLineTo(nvg, cx, cy + selHs)
            nvgLineTo(nvg, cx - selHs, cy)
            nvgClosePath(nvg)
            nvgStrokeWidth(nvg, 2)
            nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 200))
            nvgStroke(nvg)
        end

        -- 背景
        local bgR, bgG, bgB, bgA
        if lv > 0 then
            bgR, bgG, bgB, bgA = ec[1], ec[2], ec[3], 200
        elseif isLocked then
            bgR, bgG, bgB, bgA = 50, 40, 40, 120
        else
            bgR, bgG, bgB, bgA = 40, 45, 60, 150
        end

        -- 菱形
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cx, cy - hs)
        nvgLineTo(nvg, cx + hs, cy)
        nvgLineTo(nvg, cx, cy + hs)
        nvgLineTo(nvg, cx - hs, cy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(bgR, bgG, bgB, bgA))
        nvgFill(nvg)

        if lv > 0 then
            nvgStrokeWidth(nvg, 1.5)
            nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], 200))
        elseif isLocked then
            nvgStrokeWidth(nvg, 0.8)
            nvgStrokeColor(nvg, nvgRGBA(100, 60, 60, 100))
        else
            nvgStrokeWidth(nvg, 1)
            nvgStrokeColor(nvg, nvgRGBA(80, 90, 110, 100))
        end
        nvgStroke(nvg)

        -- 图标 (使用父技能图标) + 文字回退
        local parentIconPath = Config.SKILL_ICON_PATHS and Config.SKILL_ICON_PATHS[en.parentId]
        local enhIconDrawn = false
        if parentIconPath then
            if not self.iconHandles_ then self.iconHandles_ = {} end
            local iconKey = "enh_" .. enhId
            if not self.iconHandles_[iconKey] then
                self.iconHandles_[iconKey] = nvgCreateImage(nvg, parentIconPath, 0)
            end
            local imgH = self.iconHandles_[iconKey]
            if imgH and imgH > 0 then
                local iconAlpha = (lv > 0) and 1.0 or (isLocked and 0.2 or 0.35)
                local pad = 3
                local imgSize = ES - pad * 2
                -- 菱形内绘制图标 (正方形裁剪区域)
                local innerHs = hs * 0.65
                local imgPaint = nvgImagePattern(nvg, cx - innerHs, cy - innerHs,
                    innerHs * 2, innerHs * 2, 0, imgH, iconAlpha)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, cx - innerHs, cy - innerHs,
                    innerHs * 2, innerHs * 2, 3)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
                enhIconDrawn = true
            end
        end
        -- 状态标记覆盖在图标上方
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 9)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if lv > 0 then
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 240))
            nvgText(nvg, cx, cy, "✓")
        elseif isRequiresLocked then
            nvgFillColor(nvg, nvgRGBA(120, 80, 80, 120))
            nvgText(nvg, cx, cy, "🔒")
        elseif not enhIconDrawn then
            nvgFillColor(nvg, nvgRGBA(200, 210, 230, 100))
            nvgText(nvg, cx, cy, "+")
        end

        ::continue_enh::
    end
end

--- 层级标签 (脊柱右侧)
function SkillTreeCanvas:DrawTierLabels(nvg, layout)
    local spent = GameState.GetSpentSkillPts()

    for t = 1, 7 do
        local tier = SkillTreeConfig.TIERS[t]
        if not tier then goto continue_tier end

        local ty = layout.TIER_START_Y + (t - 1) * layout.TIER_SPACING_Y
        local unlocked = spent >= tier.gate
        local tc = tier.color

        -- 标签背景 (脊柱右侧偏移)
        local labelX = layout.SPINE_X + 8
        local labelW = 60
        local labelH = 16
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, labelX, ty - labelH - 25, labelW, labelH, 3)
        nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], unlocked and 25 or 10))
        nvgFill(nvg)

        -- 标签文字
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 8)
        nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], unlocked and 180 or 60))
        local label = tier.name
        nvgText(nvg, labelX + 4, ty - labelH - 25 + labelH / 2, label)

        ::continue_tier::
    end
end

-- ============================================================================
-- 交互处理
-- ============================================================================

function SkillTreeCanvas:OnPointerDown(event)
    self.dragging_ = true
    self.dragStartX_ = event.x
    self.dragStartY_ = event.y
    self.dragStartPX_ = self.panX_
    self.dragStartPY_ = self.panY_
    self.dragDist_ = 0
    self.velX_ = 0
    self.velY_ = 0
    self.lastMoveX_ = event.x
    self.lastMoveY_ = event.y
    return true
end

function SkillTreeCanvas:OnPointerMove(event)
    if not self.dragging_ then return end
    local dx = event.x - self.dragStartX_
    local dy = event.y - self.dragStartY_
    self.panX_ = self.dragStartPX_ + dx
    self.panY_ = self.dragStartPY_ + dy
    self:ClampPan()

    self.dragDist_ = self.dragDist_
        + math.abs(event.x - self.lastMoveX_)
        + math.abs(event.y - self.lastMoveY_)

    self.velX_ = (event.x - self.lastMoveX_) * 0.5
    self.velY_ = (event.y - self.lastMoveY_) * 0.5

    self.lastMoveX_ = event.x
    self.lastMoveY_ = event.y
end

function SkillTreeCanvas:OnPointerUp(event)
    if not self.dragging_ then return end
    self.dragging_ = false
    if self.dragDist_ < 8 then
        self:HandleTap(event)
    end
end

function SkillTreeCanvas:HandleTap(event)
    local cx, cy = self:ScreenToCanvas(event.x, event.y)
    local hit, nodeType = SkillTreeLayout.GetNodeAt(self.layout_, cx, cy)

    if hit then
        self.selectedId_ = hit.id
        if self.onSelect_ then
            self.onSelect_(hit)
        end
    end
end

--- 滚轮缩放 (以鼠标位置为锚点)
function SkillTreeCanvas:OnWheel(dx, dy)
    local l = self:GetAbsoluteLayout()
    if not l then return end

    local mx = self.lastMoveX_ or (l.x + l.w / 2)
    local my = self.lastMoveY_ or (l.y + l.h / 2)

    -- 缩放前的画布坐标
    local canvasX = (mx - l.x - self.panX_) / self.zoom_
    local canvasY = (my - l.y - self.panY_) / self.zoom_

    -- 固定每次滚轮 5% 缩放，只取方向
    local dir = dy > 0 and 1 or -1
    local factor = 1 + dir * 0.05
    local newZoom = math.max(self.minZoom_, math.min(self.maxZoom_, self.zoom_ * factor))

    -- 调整平移使锚点不变
    self.panX_ = (mx - l.x) - canvasX * newZoom
    self.panY_ = (my - l.y) - canvasY * newZoom
    self.zoom_ = newZoom

    self:ClampPan()
end

--- 双指缩放
function SkillTreeCanvas:OnPinchStart(event)
    self.pinchStartZoom_ = self.zoom_
end

function SkillTreeCanvas:OnPinchMove(event)
    if not self.pinchStartZoom_ then return end
    local l = self:GetAbsoluteLayout()
    if not l then return end

    local newZoom = math.max(self.minZoom_, math.min(self.maxZoom_, self.pinchStartZoom_ * event.scale))

    -- 以捏合中心为锚点
    local cx = (event.centerX - l.x - self.panX_) / self.zoom_
    local cy = (event.centerY - l.y - self.panY_) / self.zoom_

    self.panX_ = (event.centerX - l.x) - cx * newZoom
    self.panY_ = (event.centerY - l.y) - cy * newZoom
    self.zoom_ = newZoom

    self:ClampPan()
end

function SkillTreeCanvas:OnPinchEnd(event)
    self.pinchStartZoom_ = nil
end

--- 以画布中心为锚点缩放 (供外部按钮调用)
---@param direction number  1=放大, -1=缩小
function SkillTreeCanvas:ZoomStep(direction)
    local l = self:GetAbsoluteLayout()
    if not l then return end
    local cx = l.w / 2
    local cy = l.h / 2
    local canvasX = (cx - self.panX_) / self.zoom_
    local canvasY = (cy - self.panY_) / self.zoom_
    local factor = 1 + (direction > 0 and 0.15 or -0.15)
    local newZoom = math.max(self.minZoom_, math.min(self.maxZoom_, self.zoom_ * factor))
    self.panX_ = cx - canvasX * newZoom
    self.panY_ = cy - canvasY * newZoom
    self.zoom_ = newZoom
    self:ClampPan()
end

-- ============================================================================
-- Update (惯性 + 动画)
-- ============================================================================

function SkillTreeCanvas:Update(dt)
    self.animTime_ = self.animTime_ + dt

    -- 惯性
    if not self.dragging_ then
        local hasVX = math.abs(self.velX_) > 0.3
        local hasVY = math.abs(self.velY_) > 0.3
        if hasVX or hasVY then
            if hasVX then
                self.panX_ = self.panX_ + self.velX_
                self.velX_ = self.velX_ * 0.92
            else
                self.velX_ = 0
            end
            if hasVY then
                self.panY_ = self.panY_ + self.velY_
                self.velY_ = self.velY_ * 0.92
            else
                self.velY_ = 0
            end
            self:ClampPan()
        end
    end
end

-- ============================================================================
-- 公共 API
-- ============================================================================

function SkillTreeCanvas:SetSelected(id)
    self.selectedId_ = id
end

function SkillTreeCanvas:GetSelectedId()
    return self.selectedId_
end

function SkillTreeCanvas:SetOnSelect(fn)
    self.onSelect_ = fn
end

function SkillTreeCanvas:RefreshLayout()
    self.layout_ = SkillTreeLayout.Build()
end

--- 加载背景纹理
function SkillTreeCanvas:LoadBackground(nvg, path)
    if self.bgHandle_ and self.bgHandle_ > 0 then return end
    self.bgHandle_ = nvgCreateImage(nvg, path, NVG_IMAGE_REPEATX + NVG_IMAGE_REPEATY)
    self.bgReady_ = (self.bgHandle_ and self.bgHandle_ > 0)
end

return SkillTreeCanvas
