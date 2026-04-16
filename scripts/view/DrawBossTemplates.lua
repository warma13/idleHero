-- ============================================================================
-- view/DrawBossTemplates.lua - 模板系统 Boss 技能视觉渲染
-- 弹幕(bossProjectiles)、区域(bossZones)、阶段转换、可摧毁物
-- ============================================================================

local DrawBossTemplates = {}

-- 元素颜色映射
local ELEM_COLORS = {
    fire     = { 255, 100,  30 },
    ice      = { 100, 200, 255 },
    poison   = { 100, 220,  80 },
    arcane   = { 180, 120, 255 },
    water    = {  60, 160, 255 },
    physical = { 200, 200, 200 },
}

local function elemColor(elem)
    return ELEM_COLORS[elem] or { 200, 200, 200 }
end

-- ============================================================================
-- 贴图缓存系统
-- ============================================================================

--- 贴图句柄缓存: imgCache["barrage_ice"] = nvgImageHandle
local imgCache = {}

--- 根据模板类型和元素获取/加载贴图
--- @param nvg userdata
--- @param templateType string 如 "barrage", "breath", "field" 等
--- @param element string 如 "ice", "fire", "poison" 等
--- @return number nvg image handle, 0 表示加载失败
local function getSkillImage(nvg, templateType, element)
    local key = templateType .. "_" .. (element or "physical")
    local h = imgCache[key]
    if h then return h end
    -- 首次加载
    local path = "Textures/skills/boss_" .. key .. ".png"
    h = nvgCreateImage(nvg, path, 0)
    if not h or h <= 0 then h = 0 end
    imgCache[key] = h
    return h
end

-- ============================================================================
-- 弹幕 (bossProjectiles)
-- ============================================================================

local function DrawProjectiles(nvg, l, bs)
    if not bs.bossProjectiles or #bs.bossProjectiles == 0 then return end
    local time = bs.time or 0

    for _, p in ipairs(bs.bossProjectiles) do
        local sx = l.x + p.x
        local sy = l.y + p.y
        local r = p.radius or 8
        local c = elemColor(p.element)
        local alpha = 220

        -- 尝试使用贴图
        local imgH = getSkillImage(nvg, "barrage", p.element)
        if imgH > 0 then
            -- 贴图渲染: 根据飞行方向旋转
            local size = r * 2.8
            local angle = math.atan(p.vy or 0, p.vx or 0)
            nvgSave(nvg)
            nvgTranslate(nvg, sx, sy)
            nvgRotate(nvg, angle)
            local pat = nvgImagePattern(nvg, -size/2, -size/2, size, size, 0, imgH, alpha / 255)
            nvgBeginPath(nvg)
            nvgRect(nvg, -size/2, -size/2, size, size)
            nvgFillPaint(nvg, pat)
            nvgFill(nvg)
            nvgRestore(nvg)
            -- 外发光（更淡）
            local glow = nvgRadialGradient(nvg, sx, sy, r * 0.3, r * 1.2,
                nvgRGBA(c[1], c[2], c[3], 60), nvgRGBA(c[1], c[2], c[3], 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r * 1.2)
            nvgFillPaint(nvg, glow)
            nvgFill(nvg)
        else
            -- 回退: 程序化绘制
            local paint = nvgRadialGradient(nvg,
                sx, sy, r * 0.3, r * 1.5,
                nvgRGBA(c[1], c[2], c[3], alpha),
                nvgRGBA(c[1], c[2], c[3], 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r * 1.5)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r * 0.6)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
            nvgFill(nvg)
        end
    end
end

-- ============================================================================
-- 区域 (bossZones)
-- ============================================================================

local function DrawZones(nvg, l, bs)
    if not bs.bossZones or #bs.bossZones == 0 then return end
    local time = bs.time or 0

    for _, z in ipairs(bs.bossZones) do
        local c = elemColor(z.element)
        local sx = l.x + (z.x or 0)
        local sy = l.y + (z.y or 0)

        -- 预警阶段 (dmg == 0) 用虚线/闪烁
        local isWarning = (z.dmg == 0)
        local baseAlpha = isWarning and (80 + math.floor(40 * math.sin(time * 6))) or 60

        -- 根据 zoneType 决定贴图模板名
        local zoneTexName = z.zoneType
        if zoneTexName == "spike_warning" or zoneTexName == "spike_linger" then
            zoneTexName = "spikes"
        end

        if z.shape == "circle" then
            local r = z.radius or 30

            -- 尝试使用贴图
            local imgH = zoneTexName and getSkillImage(nvg, zoneTexName, z.element) or 0
            if imgH > 0 then
                local size = r * 2.2
                local texAlpha = isWarning and (baseAlpha + 40) or 180
                -- vortex 类型添加旋转动画
                local rot = (zoneTexName == "vortex") and (time * 3) or 0
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)
                if rot ~= 0 then nvgRotate(nvg, rot) end
                local pat = nvgImagePattern(nvg, -size/2, -size/2, size, size, 0, imgH, texAlpha / 255)
                nvgBeginPath(nvg)
                nvgCircle(nvg, 0, 0, size / 2)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                nvgRestore(nvg)
                -- 边框发光
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(texAlpha * 0.5)))
                nvgStrokeWidth(nvg, isWarning and 1.5 or 2.0)
                nvgStroke(nvg)
            else
                -- 回退: 程序化圆形
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha + 80))
                nvgStrokeWidth(nvg, isWarning and 1.5 or 2.0)
                nvgStroke(nvg)
            end

        elseif z.shape == "sector" then
            -- 扇形区域 (breath)
            local r = z.radius or 50
            local dir = z.dirAngle or 0
            local half = z.halfAngle or (math.pi / 6)
            local startAngle = dir - half
            local endAngle = dir + half

            local imgH = getSkillImage(nvg, "breath", z.element)
            if imgH > 0 then
                -- 贴图渲染: 在扇形区域内铺设旋转后的矩形贴图
                local texAlpha = isWarning and (baseAlpha + 40) or 200
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)
                nvgRotate(nvg, dir)
                local imgW = r
                local imgH2 = r * math.sin(half) * 2
                local pat = nvgImagePattern(nvg, 0, -imgH2/2, imgW, imgH2, 0, imgH, texAlpha / 255)
                -- 使用扇形裁剪
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, 0, 0)
                nvgArc(nvg, 0, 0, r, -half, half, NVG_CW)
                nvgClosePath(nvg)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                nvgRestore(nvg)
                -- 扇形边框
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, sx, sy)
                nvgArc(nvg, sx, sy, r, startAngle, endAngle, NVG_CW)
                nvgClosePath(nvg)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(texAlpha * 0.5)))
                nvgStrokeWidth(nvg, 2.0)
                nvgStroke(nvg)
            else
                -- 回退: 程序化扇形
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, sx, sy)
                nvgArc(nvg, sx, sy, r, startAngle, endAngle, NVG_CW)
                nvgClosePath(nvg)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, sx, sy)
                nvgArc(nvg, sx, sy, r, startAngle, endAngle, NVG_CW)
                nvgClosePath(nvg)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha + 80))
                nvgStrokeWidth(nvg, 2.0)
                nvgStroke(nvg)
            end

        elseif z.shape == "ring" then
            -- 扩展环 (pulse)
            local curR = z.currentRadius or 0
            local w = z.ringWidth or 15
            local innerR = math.max(0, curR - w / 2)
            local outerR = curR + w / 2

            local imgH = getSkillImage(nvg, "pulse", z.element)
            if imgH > 0 then
                -- 贴图渲染: 环形区域用外圈大小铺贴图 + 挖洞
                local size = outerR * 2
                local texAlpha = baseAlpha + 60
                local pat = nvgImagePattern(nvg, sx - size/2, sy - size/2, size, size, 0, imgH, texAlpha / 255)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, outerR)
                nvgCircle(nvg, sx, sy, innerR)
                nvgPathWinding(nvg, NVG_HOLE)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                -- 外框发光
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, outerR)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], texAlpha))
                nvgStrokeWidth(nvg, 2.0)
                nvgStroke(nvg)
            else
                -- 回退: 程序化环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, outerR)
                nvgCircle(nvg, sx, sy, innerR)
                nvgPathWinding(nvg, NVG_HOLE)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha + 30))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, outerR)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha + 100))
                nvgStrokeWidth(nvg, 2.0)
                nvgStroke(nvg)
            end

        elseif z.shape == "rect" then
            -- 矩形区域 (barrier wall)
            local rx = l.x + (z.rx or 0)
            local ry = l.y + (z.ry or 0)
            local rw = z.rw or 20
            local rh = z.rh or 60

            local imgH = getSkillImage(nvg, "barrier", z.element)
            if imgH > 0 then
                local texAlpha = isWarning and (baseAlpha + 40) or 200
                local pat = nvgImagePattern(nvg, rx, ry, rw, rh, 0, imgH, texAlpha / 255)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, 3)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                -- 边框
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, 3)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(texAlpha * 0.6)))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            else
                -- 回退: 程序化矩形
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, 3)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha + 40))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, rx, ry, rw, rh, 3)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], baseAlpha + 100))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            end
        end
    end
end

-- ============================================================================
-- 阶段转换演出
-- ============================================================================

local function DrawPhaseTransition(nvg, l, bs)
    local pt = bs.phaseTransition
    if not pt then return end

    local enemy = pt.enemy
    if not enemy or enemy.dead then return end

    local sx = l.x + enemy.x
    local sy = l.y + enemy.y
    local progress = 1.0 - (pt.timer / pt.maxTimer)
    local c = elemColor(enemy.element)

    -- 闪烁光环
    local pulseR = 30 + 20 * math.sin(progress * math.pi * 6)
    local alpha = math.floor(150 + 100 * math.sin(progress * math.pi * 4))
    nvgBeginPath(nvg)
    nvgCircle(nvg, sx, sy, pulseR)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
    nvgStrokeWidth(nvg, 3)
    nvgStroke(nvg)

    -- 内核能量积聚
    local coreR = 10 + 15 * progress
    local corePaint = nvgRadialGradient(nvg,
        sx, sy, 0, coreR,
        nvgRGBA(255, 255, 255, 200),
        nvgRGBA(c[1], c[2], c[3], 0))
    nvgBeginPath(nvg)
    nvgCircle(nvg, sx, sy, coreR)
    nvgFillPaint(nvg, corePaint)
    nvgFill(nvg)

    -- 阶段转换文字
    if pt.text then
        nvgFontSize(nvg, 14)
        nvgFontFace(nvg, "sans")
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(nvg, nvgRGBA(255, 220, 100, math.floor(220 * math.min(1, progress * 3))))
        nvgText(nvg, sx, sy - pulseR - 8, pt.text)
    end
end

-- ============================================================================
-- 可摧毁物标记 (crystal / shield / detonateTarget)
-- 它们已在 bs.enemies 中作为普通敌人绘制, 这里只加额外指示器
-- ============================================================================

local function DrawDestroyableIndicators(nvg, l, bs)
    if not bs.enemies then return end
    local time = bs.time or 0

    for _, e in ipairs(bs.enemies) do
        if not e.dead and e.isBossDestroyable then
            local sx = l.x + e.x
            local sy = l.y + e.y
            local r = (e.radius or 16) + 4
            local c = elemColor(e.element)

            local dtype = e.destroyableType
            -- detonateTarget 在模板中对应 detonate 贴图
            local texType = (dtype == "detonateTarget") and "detonate" or dtype

            -- 尝试加载贴图
            local imgH = texType and getSkillImage(nvg, texType, e.element) or 0

            if dtype == "crystal" then
                if imgH > 0 then
                    -- 贴图: 旋转水晶
                    local size = r * 2.4
                    local angle = time * 2
                    nvgSave(nvg)
                    nvgTranslate(nvg, sx, sy)
                    nvgRotate(nvg, angle)
                    local pat = nvgImagePattern(nvg, -size/2, -size/2, size, size, 0, imgH, 0.8)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, 0, 0, size / 2)
                    nvgFillPaint(nvg, pat)
                    nvgFill(nvg)
                    nvgRestore(nvg)
                else
                    -- 回退: 菱形旋转标记
                    local angle = time * 2
                    nvgSave(nvg)
                    nvgTranslate(nvg, sx, sy)
                    nvgRotate(nvg, angle)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, 0, -r)
                    nvgLineTo(nvg, r * 0.6, 0)
                    nvgLineTo(nvg, 0, r)
                    nvgLineTo(nvg, -r * 0.6, 0)
                    nvgClosePath(nvg)
                    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], 120))
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStroke(nvg)
                    nvgRestore(nvg)
                end

                -- 治疗标记 (+)
                nvgFontSize(nvg, 12)
                nvgFontFace(nvg, "sans")
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(100, 255, 100, 180))
                nvgText(nvg, sx, sy, "+")

            elseif dtype == "detonateTarget" then
                if imgH > 0 then
                    -- 贴图: 闪烁爆炸标记
                    local flash = (120 + 60 * math.sin(time * 8)) / 255
                    local size = (r + 3) * 2.2
                    local pat = nvgImagePattern(nvg, sx - size/2, sy - size/2, size, size, 0, imgH, flash)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, size / 2)
                    nvgFillPaint(nvg, pat)
                    nvgFill(nvg)
                else
                    -- 回退: 闪烁警告圈
                    local flash = math.floor(180 + 70 * math.sin(time * 8))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r + 3)
                    nvgStrokeColor(nvg, nvgRGBA(255, 80, 40, flash))
                    nvgStrokeWidth(nvg, 2)
                    nvgStroke(nvg)
                end

                -- 倒计时提示
                if e._detonateTimer then
                    nvgFontSize(nvg, 11)
                    nvgFontFace(nvg, "sans")
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                    nvgFillColor(nvg, nvgRGBA(255, 200, 60, 220))
                    nvgText(nvg, sx, sy - r - 4, string.format("%.1f", e._detonateTimer))
                end

            elseif dtype == "shield" then
                if imgH > 0 then
                    -- 贴图: 护盾光罩
                    local pulse = 1.0 + math.sin(time * 4) * 0.06
                    local size = r * 2.4 * pulse
                    local pat = nvgImagePattern(nvg, sx - size/2, sy - size/2, size, size, 0, imgH, 0.7)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, size / 2)
                    nvgFillPaint(nvg, pat)
                    nvgFill(nvg)
                else
                    -- 回退: 六边形边框
                    local n = 6
                    nvgBeginPath(nvg)
                    for i = 0, n - 1 do
                        local a = (i / n) * math.pi * 2 - math.pi / 2
                        local px = sx + r * math.cos(a)
                        local py = sy + r * math.sin(a)
                        if i == 0 then nvgMoveTo(nvg, px, py)
                        else nvgLineTo(nvg, px, py) end
                    end
                    nvgClosePath(nvg)
                    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], 160))
                    nvgStrokeWidth(nvg, 2)
                    nvgStroke(nvg)
                end

                -- HP 条 (在头顶)
                if e.maxHp and e.maxHp > 0 then
                    local barW = 30
                    local barH = 4
                    local bx = sx - barW / 2
                    local by = sy - r - 10
                    local ratio = math.max(0, e.hp / e.maxHp)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, bx, by, barW, barH, 2)
                    nvgFillColor(nvg, nvgRGBA(40, 40, 40, 150))
                    nvgFill(nvg)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, bx, by, barW * ratio, barH, 2)
                    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 200))
                    nvgFill(nvg)
                end
            end
        end
    end
end

-- ============================================================================
-- 衰减状态 UI 提示 (decay debuff 指示器, 显示在玩家附近)
-- ============================================================================

local function DrawDecayIndicators(nvg, l, bs)
    local gs = require("GameState")
    local hasMoveDecay = (gs._bossDecayMoveSpeed or 0) > 0
    local hasAtkDecay  = (gs._bossDecayAtkSpeed or 0) > 0
    local hasAtkReduce = (gs._bossDecayAtk or 0) > 0
    local hasDefReduce = (gs._bossDecayDef or 0) > 0

    if not (hasMoveDecay or hasAtkDecay or hasAtkReduce or hasDefReduce) then return end

    local p = bs.playerBattle
    if not p then return end
    local sx = l.x + p.x
    local sy = l.y + p.y

    local icons = {}
    if hasMoveDecay then table.insert(icons, { text = "Slow", c = { 160, 100, 255 } }) end
    if hasAtkDecay  then table.insert(icons, { text = "-AS",  c = { 200, 100, 100 } }) end
    if hasAtkReduce then table.insert(icons, { text = "-ATK", c = { 255, 120,  60 } }) end
    if hasDefReduce then table.insert(icons, { text = "-DEF", c = { 255,  80,  80 } }) end

    nvgFontSize(nvg, 9)
    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local startX = sx - (#icons - 1) * 14
    for i, ic in ipairs(icons) do
        local ix = startX + (i - 1) * 28
        local iy = sy + (p.radius or 12) + 4
        nvgFillColor(nvg, nvgRGBA(ic.c[1], ic.c[2], ic.c[3], 200))
        nvgText(nvg, ix, iy, ic.text)
    end
end

-- ============================================================================
-- 主入口
-- ============================================================================

function DrawBossTemplates.DrawAll(nvg, l, bs)
    DrawZones(nvg, l, bs)
    DrawProjectiles(nvg, l, bs)
    DrawDestroyableIndicators(nvg, l, bs)
    DrawPhaseTransition(nvg, l, bs)
    DrawDecayIndicators(nvg, l, bs)
end

return DrawBossTemplates
