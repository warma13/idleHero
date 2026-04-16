-- ============================================================================
-- view/DrawEntities.lua - 实体渲染（掉落物/敌人/玩家/精灵/狂热光环）
-- ============================================================================

local EnemyAnim = require("battle.EnemyAnim")

local DrawEntities = {}

function DrawEntities.Install(BattleView, imgHandles)
    -- Private handles (only used within these functions)
    local playerSheetHandle = nil   -- 攻击序列帧 sprite sheet (4帧横排)
    local SHEET_COLS        = 4     -- 序列帧列数
    local iceArmorShieldHandle = nil -- 寒冰甲屏障图片
    local flameShieldHandle = nil   -- 火焰护盾屏障图片
    local coinFrameHandles  = {}   -- {1..4 -> handle}
    local COIN_FRAME_PATHS  = {
        "coin_frame1_20260306122454.png",
        "coin_frame2_20260306122502.png",
        "coin_frame3_20260306122506.png",
        "coin_frame4_20260306122503.png",
    }
    local COIN_ANIM_FPS     = 6

    -- 魂晶帧
    local soulCrystalFrameHandles = {}
    local SOUL_CRYSTAL_FRAME_PATHS = {
        "Textures/Loot/soul_crystal_f1.png",
        "Textures/Loot/soul_crystal_f2.png",
        "Textures/Loot/soul_crystal_f3.png",
        "Textures/Loot/soul_crystal_f4.png",
    }
    -- 属性洗点券帧
    local attrTicketFrameHandles = {}
    local ATTR_TICKET_FRAME_PATHS = {
        "Textures/Loot/attr_ticket_f1.png",
        "Textures/Loot/attr_ticket_f2.png",
        "Textures/Loot/attr_ticket_f3.png",
        "Textures/Loot/attr_ticket_f4.png",
    }
    -- 技能重置券帧
    local skillTicketFrameHandles = {}
    local SKILL_TICKET_FRAME_PATHS = {
        "Textures/Loot/skill_ticket_f1.png",
        "Textures/Loot/skill_ticket_f2.png",
        "Textures/Loot/skill_ticket_f3.png",
        "Textures/Loot/skill_ticket_f4.png",
    }
    local LOOT_ANIM_FPS     = 6

    local expOrbHandle      = nil
    local EXP_ORB_PATH      = "exp_orb_20260306122455.png"
    local ELEM_ICON_PATHS   = {
        fire     = "elem_fire_20260306122305.png",
        ice      = "elem_ice_20260306122259.png",
        poison   = "elem_poison_20260306122303.png",
        arcane   = "elem_arcane_20260306122359.png",
        water    = "elem_water_20260306122300.png",
        physical = "elem_physical_20260306122306.png",
    }
    local equipIconHandles  = {}   -- 装备图标缓存 {slotId -> handle}

    -- ========================================================================
    -- 掉落物
    -- ========================================================================

    function BattleView:DrawLoots(nvg, l, bs)
        local time = bs.time or 0
        local margin = 30
        for _, loot in ipairs(bs.loots) do
            local sx = l.x + loot.x
            local sy = l.y + loot.y
            -- 视口外剔除
            if sx < l.x - margin or sx > l.x + l.w + margin
                or sy < l.y - margin or sy > l.y + l.h + margin then
                goto continue_loot
            end
            local pulse = 1.0 + math.sin(time * 4 + loot.x) * 0.2

            if loot.type == "exp" then
                -- 延迟加载经验球图片
                if not expOrbHandle then
                    expOrbHandle = nvgCreateImage(nvg, EXP_ORB_PATH, 0)
                end
                local iconSz = math.floor(14 * pulse)
                if expOrbHandle and expOrbHandle > 0 then
                    local ip = nvgImagePattern(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz, 0, expOrbHandle, 1.0)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz)
                    nvgFillPaint(nvg, ip)
                    nvgFill(nvg)
                else
                    -- fallback 圆形
                    local r = 5 * pulse
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r)
                    nvgFillColor(nvg, nvgRGBA(80, 255, 120, 200))
                    nvgFill(nvg)
                end
                -- 光晕
                local glowR = 7 * pulse
                local glow = nvgRadialGradient(nvg, sx, sy, glowR, glowR * 2.5, nvgRGBA(80, 255, 120, 50), nvgRGBA(80, 255, 120, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, glowR * 2.5)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
            elseif loot.type == "gold" then
                -- 延迟加载金币帧图片
                if #coinFrameHandles == 0 then
                    for i, path in ipairs(COIN_FRAME_PATHS) do
                        coinFrameHandles[i] = nvgCreateImage(nvg, path, 0)
                    end
                end
                -- 4帧动画：根据时间选帧
                local frameIdx = math.floor(time * COIN_ANIM_FPS) % #COIN_FRAME_PATHS + 1
                local coinH = coinFrameHandles[frameIdx]
                local iconSz = math.floor(16 * pulse)
                if coinH and coinH > 0 then
                    local ip = nvgImagePattern(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz, 0, coinH, 1.0)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz)
                    nvgFillPaint(nvg, ip)
                    nvgFill(nvg)
                else
                    -- fallback 圆形
                    local r = 6 * pulse
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r)
                    nvgFillColor(nvg, nvgRGBA(255, 215, 0, 220))
                    nvgFill(nvg)
                end
                -- 金光
                local glowR = 8 * pulse
                local glow = nvgRadialGradient(nvg, sx, sy, glowR * 0.5, glowR * 2, nvgRGBA(255, 215, 0, 40), nvgRGBA(255, 215, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, glowR * 2)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
            elseif loot.type == "equip" then
                local c = loot.color or { 200, 200, 200 }
                local iconSz = math.floor(22 * pulse)
                local slotId = loot.extra and loot.extra.slotId
                local setId = loot.extra and loot.extra.setId
                local Config = require("Config")
                local iconPath = slotId and Config.GetEquipSlotIcon(slotId, setId)
                local iconKey = (setId or "") .. "_" .. (slotId or "")
                local drawnIcon = false

                -- 品质底色光晕
                local glow = nvgRadialGradient(nvg, sx, sy, iconSz * 0.3, iconSz * 1.2,
                    nvgRGBA(c[1], c[2], c[3], math.floor(80 * pulse)),
                    nvgRGBA(c[1], c[2], c[3], 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, iconSz * 1.2)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)

                if iconPath and iconPath ~= "" then
                    if not equipIconHandles[iconKey] then
                        equipIconHandles[iconKey] = nvgCreateImage(nvg, iconPath, 0)
                    end
                    local h = equipIconHandles[iconKey]
                    if h and h > 0 then
                        local ip = nvgImagePattern(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz, 0, h, 1.0)
                        nvgBeginPath(nvg)
                        nvgRoundedRect(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz, 3)
                        nvgFillPaint(nvg, ip)
                        nvgFill(nvg)
                        drawnIcon = true
                    end
                end

                if not drawnIcon then
                    -- fallback 菱形
                    local r = 10 * pulse
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, sx, sy - r)
                    nvgLineTo(nvg, sx + r * 0.7, sy)
                    nvgLineTo(nvg, sx, sy + r)
                    nvgLineTo(nvg, sx - r * 0.7, sy)
                    nvgClosePath(nvg)
                    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 230))
                    nvgFill(nvg)
                end

                -- 品质色光柱
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - 1.5, sy - iconSz / 2 - 18, 3, 16)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(80 * pulse)))
                nvgFill(nvg)

                -- 装备名字 (显示在图标下方)
                local equipName = loot.extra and loot.extra.name
                if equipName then
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 8)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    -- 描边增加可读性
                    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 200))
                    local nameY = sy + iconSz / 2 + 2
                    for dx = -1, 1 do
                        for dy = -1, 1 do
                            if dx ~= 0 or dy ~= 0 then
                                nvgText(nvg, sx + dx, nameY + dy, equipName)
                            end
                        end
                    end
                    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 230))
                    nvgText(nvg, sx, nameY, equipName)
                end
            elseif loot.type == "soulCrystal" then
                -- 延迟加载魂晶帧图片
                if #soulCrystalFrameHandles == 0 then
                    for i, path in ipairs(SOUL_CRYSTAL_FRAME_PATHS) do
                        soulCrystalFrameHandles[i] = nvgCreateImage(nvg, path, 0)
                    end
                end
                local frameIdx = math.floor(time * LOOT_ANIM_FPS) % #SOUL_CRYSTAL_FRAME_PATHS + 1
                local h = soulCrystalFrameHandles[frameIdx]
                local iconSz = math.floor(18 * pulse)
                if h and h > 0 then
                    local ip = nvgImagePattern(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz, 0, h, 1.0)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz)
                    nvgFillPaint(nvg, ip)
                    nvgFill(nvg)
                else
                    local r = 6 * pulse
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r)
                    nvgFillColor(nvg, nvgRGBA(160, 80, 255, 220))
                    nvgFill(nvg)
                end
                -- 紫色光晕
                local glowR = 9 * pulse
                local glow = nvgRadialGradient(nvg, sx, sy, glowR * 0.3, glowR * 2, nvgRGBA(160, 80, 255, 50), nvgRGBA(160, 80, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, glowR * 2)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
            elseif loot.type == "bagItem" then
                -- 背包道具掉落渲染 (属性洗点券 / 技能重置券)
                local itemId = loot.extra and loot.extra.itemId
                local frames, handles
                if itemId == "attr_reset" then
                    if #attrTicketFrameHandles == 0 then
                        for i, path in ipairs(ATTR_TICKET_FRAME_PATHS) do
                            attrTicketFrameHandles[i] = nvgCreateImage(nvg, path, 0)
                        end
                    end
                    frames = ATTR_TICKET_FRAME_PATHS
                    handles = attrTicketFrameHandles
                elseif itemId == "skill_reset" then
                    if #skillTicketFrameHandles == 0 then
                        for i, path in ipairs(SKILL_TICKET_FRAME_PATHS) do
                            skillTicketFrameHandles[i] = nvgCreateImage(nvg, path, 0)
                        end
                    end
                    frames = SKILL_TICKET_FRAME_PATHS
                    handles = skillTicketFrameHandles
                end
                if frames and handles then
                    local frameIdx = math.floor(time * LOOT_ANIM_FPS) % #frames + 1
                    local h = handles[frameIdx]
                    local iconSz = math.floor(20 * pulse)
                    if h and h > 0 then
                        local ip = nvgImagePattern(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz, 0, h, 1.0)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, sx - iconSz / 2, sy - iconSz / 2, iconSz, iconSz)
                        nvgFillPaint(nvg, ip)
                        nvgFill(nvg)
                    else
                        local r = 7 * pulse
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, sx, sy, r)
                        local c = loot.color or { 255, 200, 80 }
                        nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 220))
                        nvgFill(nvg)
                    end
                    -- 道具名称
                    local Config = require("Config")
                    local cfg = Config.ITEM_MAP[itemId]
                    if cfg then
                        nvgFontFace(nvg, "sans")
                        nvgFontSize(nvg, 8)
                        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                        local c = cfg.color or { 255, 255, 255 }
                        -- 描边
                        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 200))
                        local nameY = sy + iconSz / 2 + 2
                        for ddx = -1, 1 do
                            for ddy = -1, 1 do
                                if ddx ~= 0 or ddy ~= 0 then
                                    nvgText(nvg, sx + ddx, nameY + ddy, cfg.name)
                                end
                            end
                        end
                        nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], 230))
                        nvgText(nvg, sx, nameY, cfg.name)
                    end
                    -- 光晕
                    local glowR = 10 * pulse
                    local gc = loot.color or { 255, 200, 80 }
                    local glow = nvgRadialGradient(nvg, sx, sy, glowR * 0.3, glowR * 2, nvgRGBA(gc[1], gc[2], gc[3], 50), nvgRGBA(gc[1], gc[2], gc[3], 0))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, glowR * 2)
                    nvgFillPaint(nvg, glow)
                    nvgFill(nvg)
                end
            end
            ::continue_loot::
        end
    end

    -- ========================================================================
    -- 敌人 (含元素附着特效)
    -- ========================================================================

    function BattleView:DrawEnemies(nvg, l, bs)
        -- 非常弱模式: 最多渲染 5 只敌人 (Boss 优先)
        local Settings = require("ui.Settings")
        local fxLv = Settings.GetFxLevel()
        local MAX_DRAW_ENEMIES = (fxLv == 3) and 5 or nil
        local drawnCount = 0
        -- Boss 优先渲染
        if MAX_DRAW_ENEMIES then
            for _, e in ipairs(bs.enemies) do
                if (not e.dead or EnemyAnim.IsDying(e)) and e.isBoss and drawnCount < MAX_DRAW_ENEMIES then
                    e._fxDraw = true
                    drawnCount = drawnCount + 1
                end
            end
            for _, e in ipairs(bs.enemies) do
                if (not e.dead or EnemyAnim.IsDying(e)) and not e.isBoss then
                    if drawnCount < MAX_DRAW_ENEMIES then
                        e._fxDraw = true
                        drawnCount = drawnCount + 1
                    else
                        e._fxDraw = false
                    end
                end
            end
        end
        local cullMargin = 60  -- 敌人图片较大，用更大的边距
        for _, e in ipairs(bs.enemies) do
            if (not e.dead or EnemyAnim.IsDying(e)) and (not MAX_DRAW_ENEMIES or e._fxDraw) then
                local sx = l.x + e.x
                local sy = l.y + e.y
                -- 视口外剔除
                if sx < l.x - cullMargin or sx > l.x + l.w + cullMargin
                    or sy < l.y - cullMargin or sy > l.y + l.h + cullMargin then
                    goto continue_enemy
                end
                local r = e.radius or 16
                local imgSize = r * 3.3  -- 图片显示尺寸略大于碰撞半径 (2.2 * 1.5)

                -- 怪物图片渲染
                local imgH = nil
                if e.image then
                    if not imgHandles.mob[e.image] then
                        imgHandles.mob[e.image] = nvgCreateImage(nvg, e.image, 0)
                    end
                    imgH = imgHandles.mob[e.image]
                end

                -- 获取动画变换
                local animT = EnemyAnim.GetDrawTransform(e)
                local animOX, animOY = animT.offsetX, animT.offsetY
                local animSX, animSY = animT.scaleX, animT.scaleY
                local animAlpha = animT.alpha
                local animFlash = animT.flashWhite

                if imgH and imgH > 0 then
                    local half = imgSize * 0.5

                    -- 脚底阴影 (不跟随呼吸偏移)
                    nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
                    nvgGlobalAlpha(nvg, 1)
                    nvgBeginPath(nvg)
                    nvgEllipse(nvg, sx + animOX, sy + half * 0.7, half * 0.5 * animSX, half * 0.15 * animSY)
                    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(40 * animAlpha)))
                    nvgFill(nvg)

                    -- 朝向判断: 图片默认朝右, 敌人在玩家右侧时翻转朝左
                    local px = bs.playerBattle and bs.playerBattle.x or e.x
                    local faceLeft = e.x > px
                    nvgSave(nvg)
                    -- 应用动画偏移
                    local drawCX = sx + animOX
                    local drawCY = sy + animOY
                    -- 缩放: 以怪物脚底为锚点缩放
                    nvgTranslate(nvg, drawCX, drawCY + half * 0.5)
                    nvgScale(nvg, animSX, animSY)
                    nvgTranslate(nvg, -drawCX, -(drawCY + half * 0.5))
                    if faceLeft then
                        nvgTranslate(nvg, drawCX, 0)
                        nvgScale(nvg, -1, 1)
                        nvgTranslate(nvg, -drawCX, 0)
                    end
                    local drawX = drawCX - half
                    local drawY = drawCY - half
                    nvgGlobalAlpha(nvg, animAlpha)
                    local imgPaint = nvgImagePattern(nvg, drawX, drawY, imgSize, imgSize, 0, imgH, 1)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                    nvgFillPaint(nvg, imgPaint)
                    nvgFill(nvg)

                    -- 闪白效果 (受击反馈, 4-pass blend)
                    if animFlash > 0 then
                        local flashInt = animFlash * 0.6
                        nvgShapeAntiAlias(nvg, false)
                        -- 1) 清 alpha
                        nvgGlobalCompositeBlendFuncSeparate(nvg, NVG_ZERO, NVG_ONE, NVG_ZERO, NVG_ZERO)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 0))
                        nvgFill(nvg)
                        -- 2) 重绘建立 alpha 蒙版
                        nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                        -- 3) 白色叠加 (仅不透明像素)
                        nvgGlobalCompositeBlendFuncSeparate(nvg, NVG_DST_ALPHA, NVG_ONE, NVG_ZERO, NVG_ONE)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(255 * flashInt)))
                        nvgFill(nvg)
                        -- 4) 恢复 alpha
                        nvgGlobalCompositeBlendFuncSeparate(nvg, NVG_ZERO, NVG_ONE, NVG_ONE, NVG_ONE)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 255))
                        nvgFill(nvg)
                        nvgShapeAntiAlias(nvg, true)
                        nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
                    end

                    nvgGlobalAlpha(nvg, 1)
                    nvgRestore(nvg)
                else
                    -- 兜底：无图片时用统一红色圆圈（不再按 e.color 区分色调）
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r)
                    nvgFillColor(nvg, nvgRGBA(255, 50, 50, 220))
                    nvgFill(nvg)
                    nvgStrokeColor(nvg, nvgRGBA(255, 50, 50, 120))
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStroke(nvg)
                end

                -- 血条 (跟随动画偏移)
                local hpW = imgSize * 1.1
                local hpH = 4
                local hpX = sx + animOX - hpW / 2
                local hpY = sy + animOY - imgSize * 0.5 - 10
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, hpX, hpY, hpW, hpH, 2)
                nvgFillColor(nvg, nvgRGBA(40, 0, 0, 180))
                nvgFill(nvg)

                local hpPct = math.max(0, e.hp / e.maxHp)
                if hpPct > 0 then
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, hpX, hpY, hpW * hpPct, hpH, 2)
                    nvgFillColor(nvg, nvgRGBA(220, 40, 40, 230))
                    nvgFill(nvg)
                end

                -- 怪物名字 + 附着元素图标
                if e.name then
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 8)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                    -- 精英/冠军名字颜色
                    if e.eliteRank == "champion" then
                        nvgFillColor(nvg, nvgRGBA(255, 70, 70, 240))
                    elseif e.eliteRank == "elite" then
                        nvgFillColor(nvg, nvgRGBA(255, 180, 50, 230))
                    else
                        nvgFillColor(nvg, nvgRGBA(220, 220, 220, 180))
                    end

                    local hasAttach = e.attachedElement and e.attachedElementTimer and e.attachedElementTimer > 0
                    if hasAttach then
                        -- 名字左移，给图标腾位置
                        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                        nvgText(nvg, sx, hpY - 1, e.name)

                        -- 延迟加载元素图标
                        local iconPath = ELEM_ICON_PATHS[e.attachedElement]
                        if iconPath then
                            if not imgHandles.elemIcon[e.attachedElement] then
                                imgHandles.elemIcon[e.attachedElement] = nvgCreateImage(nvg, iconPath, 0)
                            end
                            local iconH = imgHandles.elemIcon[e.attachedElement]
                            if iconH and iconH > 0 then
                                local iconSz = 10
                                local fadeAlpha = math.min(1.0, e.attachedElementTimer / 2.0)
                                local iconPaint = nvgImagePattern(nvg, sx + 1, hpY - 1 - iconSz, iconSz, iconSz, 0, iconH, fadeAlpha)
                                nvgBeginPath(nvg)
                                nvgRect(nvg, sx + 1, hpY - 1 - iconSz, iconSz, iconSz)
                                nvgFillPaint(nvg, iconPaint)
                                nvgFill(nvg)
                            end
                        end
                    else
                        nvgText(nvg, sx, hpY - 1, e.name)
                    end
                end

                -- 防御降低debuff标记
                if e.defReduceTimer and e.defReduceTimer > 0 then
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 7)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                    nvgFillColor(nvg, nvgRGBA(255, 200, 100, 200))
                    nvgText(nvg, sx, sy + r + 2, "减防")
                end

                -- BOSS标记
                if e.isBoss then
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 10)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                    nvgFillColor(nvg, nvgRGBA(255, 80, 80, 255))
                    nvgText(nvg, sx, hpY - 11, "BOSS")
                end
                ::continue_enemy::
            end
        end
    end

    -- ========================================================================
    -- 术士主角 (紫色菱形)
    -- ========================================================================

    function BattleView:DrawPlayer(nvg, l, bs)
        local p = bs.playerBattle
        if not p then return end

        local GameState = require("GameState")
        local sx = l.x + p.x
        local sy = l.y + p.y
        local imgSize = 72  -- 角色图片显示尺寸 (48 * 1.5)

        -- 玩家呼吸浮动 (1Hz, 2px) — 死亡时停止呼吸
        local isDead = bs.isPlayerDead
        local playerBob = 0
        if not isDead then
            playerBob = math.sin((bs.time or 0) * 1.0 * 6.2831853) * 2.0
        end

        -- 延迟加载序列帧 sprite sheet
        if not playerSheetHandle then
            playerSheetHandle = nvgCreateImage(nvg, "术士法杖攻击序列帧_20260305191604.png", 0)
        end

        -- 根据 atkFlash 选择当前帧 (0-indexed column)
        -- atkFlash: 1.0 → 0, 衰减速度 dt*4, 约 0.25s
        local flash = p.atkFlash or 0
        local col
        local Settings = require("ui.Settings")
        local fxLv = Settings.GetFxLevel()
        if isDead then
            col = 0  -- 死亡时固定待机帧
        elseif fxLv >= 2 and flash > 0.05 then
            -- 特效减弱/非常弱: 攻击时固定施法帧，不播放完整动画
            col = 2
        elseif flash > 0.7 then
            col = 1  -- 蓄力
        elseif flash > 0.3 then
            col = 2  -- 施法
        elseif flash > 0.05 then
            col = 3  -- 收招
        else
            col = 0  -- 待机
        end

        -- ================================================================
        -- 代码动画参数计算
        -- ================================================================
        local pSX, pSY = 1.0, 1.0      -- 缩放
        local pAlpha = 1.0              -- 透明度
        local pOffX, pOffY = 0, 0       -- 位移偏移
        local pRotation = 0             -- 旋转角度(弧度)

        -- (A) 攻击挤压拉伸 —— 同步 atkFlash 阶段
        if not isDead and flash > 0.05 then
            if flash > 0.7 then
                -- 蓄力阶段: 水平压缩 + 垂直拉伸 (弓弦拉满感)
                local t = (flash - 0.7) / 0.3  -- 1→0 (刚触发→即将进入施法)
                pSX = 1.0 - 0.15 * (1.0 - t)   -- 0.85~1.0
                pSY = 1.0 + 0.12 * (1.0 - t)   -- 1.0~1.12
            elseif flash > 0.3 then
                -- 施法阶段: 水平拉伸 + 垂直压缩 (释放弹出感)
                local t = (flash - 0.3) / 0.4  -- 1→0
                pSX = 1.0 + 0.18 * t            -- 1.0~1.18
                pSY = 1.0 - 0.14 * t            -- 0.86~1.0
            else
                -- 收招阶段: 缓回到 1.0
                local t = (flash - 0.05) / 0.25 -- 1→0
                pSX = 1.0 + 0.06 * t            -- 微微拉伸收回
                pSY = 1.0 - 0.04 * t
            end
        end

        -- (B) 受击后退位移
        local hitFlash = bs.playerHitFlash or 0
        if not isDead and hitFlash > 0 then
            -- hitFlash: 0.5/0.3 → 0, 取归一化进度
            local hitMax = 0.5
            local hitT = math.min(1.0, hitFlash / hitMax)
            -- easeOut: 快速弹出然后缓回
            local easeT = 1.0 - (1.0 - hitT) * (1.0 - hitT)
            local recoilDist = 4.0 * easeT

            -- 找最近敌人方向作为后退方向
            local rdx, rdy = 0, -1  -- 默认向上退
            if bs.enemies then
                local bestD = math.huge
                for _, e in ipairs(bs.enemies) do
                    if not e.dead then
                        local dx = p.x - e.x
                        local dy = p.y - e.y
                        local d = dx * dx + dy * dy
                        if d < bestD then
                            bestD = d
                            if d > 0.01 then
                                local inv = 1.0 / math.sqrt(d)
                                rdx, rdy = dx * inv, dy * inv
                            end
                        end
                    end
                end
            end
            pOffX = pOffX + rdx * recoilDist
            pOffY = pOffY + rdy * recoilDist
        end

        -- (C) 死亡动画: 缩小 + 淡出 + 倾斜
        if isDead then
            -- playerDeadTimer: 2.5 → 0
            local deadT = bs.playerDeadTimer or 0
            local progress = 1.0 - math.min(1.0, deadT / 2.5)  -- 0→1
            -- 前 0.4 进度: 快速缩小倾斜; 后 0.6: 缓慢淡出
            if progress < 0.4 then
                local t = progress / 0.4  -- 0→1
                local ease = t * t  -- easeIn
                pSX = 1.0 - 0.3 * ease
                pSY = 1.0 - 0.5 * ease
                pRotation = 0.3 * ease  -- ~17度倾斜
                pAlpha = 1.0
                pOffY = pOffY + 8 * ease  -- 下沉
            else
                local t = (progress - 0.4) / 0.6  -- 0→1
                pSX = 0.7 - 0.3 * t
                pSY = 0.5 - 0.2 * t
                pRotation = 0.3
                pAlpha = 1.0 - t * t  -- easeIn 淡出
                pOffY = pOffY + 8 + 4 * t
            end
        end

        if playerSheetHandle and playerSheetHandle >= 0 then
            local half = imgSize * 0.5

            -- 脚底阴影 (不跟随浮动, 但跟随死亡缩放)
            nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
            nvgGlobalAlpha(nvg, 1)
            nvgBeginPath(nvg)
            local shadowAlpha = math.floor(45 * pAlpha)
            nvgEllipse(nvg, sx + pOffX, sy + half * 0.7, half * 0.45 * pSX, half * 0.13 * pSY)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, shadowAlpha))
            nvgFill(nvg)

            -- 应用呼吸浮动 + 代码动画偏移
            local drawCX = sx + pOffX
            local drawCY = sy + playerBob + pOffY
            local drawX = drawCX - half
            local drawY = drawCY - half

            -- 朝向翻转：faceDirX < 0 时水平镜像
            local faceDirX = p.faceDirX or 1
            nvgSave(nvg)

            -- 代码动画缩放 + 旋转: 以脚底为锚点
            local footY = drawCY + half * 0.5
            nvgTranslate(nvg, drawCX, footY)
            if pRotation ~= 0 then
                nvgRotate(nvg, pRotation)
            end
            nvgScale(nvg, pSX, pSY)
            nvgTranslate(nvg, -drawCX, -footY)

            if faceDirX < 0 then
                nvgTranslate(nvg, drawCX, 0)
                nvgScale(nvg, -1, 1)
                nvgTranslate(nvg, -drawCX, 0)
            end

            -- sprite sheet 切帧：将整图宽度映射为 imgSize * SHEET_COLS
            -- 然后通过 ox 偏移选择对应列
            local sheetW = imgSize * SHEET_COLS
            local sheetH = imgSize
            local ox = drawX - col * imgSize

            nvgGlobalAlpha(nvg, pAlpha)
            nvgBeginPath(nvg)
            nvgRect(nvg, drawX, drawY, imgSize, imgSize)
            local imgPaint = nvgImagePattern(nvg, ox, drawY, sheetW, sheetH, 0, playerSheetHandle, 1)
            nvgFillPaint(nvg, imgPaint)
            nvgFill(nvg)

            -- 受击闪红：仅在角色不透明像素上叠红色
            if hitFlash > 0 and not isDead then
                local flashIntensity = math.min(1.0, hitFlash / 0.3) * 0.5
                nvgShapeAntiAlias(nvg, false)  -- 禁用 AA 避免边缘黑框

                -- 1) 清除角色区域的 alpha，保留 RGB
                nvgGlobalCompositeBlendFuncSeparate(nvg, NVG_ZERO, NVG_ONE, NVG_ZERO, NVG_ZERO)
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                nvgFillColor(nvg, nvgRGBA(0, 0, 0, 0))
                nvgFill(nvg)

                -- 2) 重绘角色，建立 alpha 蒙版（仅精灵不透明像素有 alpha）
                nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                local maskPaint = nvgImagePattern(nvg, ox, drawY, sheetW, sheetH, 0, playerSheetHandle, 1)
                nvgFillPaint(nvg, maskPaint)
                nvgFill(nvg)

                -- 3) 红色叠加，仅 dstAlpha > 0 处（即角色像素）生效
                nvgGlobalCompositeBlendFuncSeparate(nvg, NVG_DST_ALPHA, NVG_ONE, NVG_ZERO, NVG_ONE)
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                nvgFillColor(nvg, nvgRGBA(255, 40, 40, math.floor(255 * flashIntensity)))
                nvgFill(nvg)

                -- 4) 恢复 alpha 为 1，避免后续渲染异常
                nvgGlobalCompositeBlendFuncSeparate(nvg, NVG_ZERO, NVG_ONE, NVG_ONE, NVG_ONE)
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, imgSize, imgSize)
                nvgFillColor(nvg, nvgRGBA(0, 0, 0, 255))
                nvgFill(nvg)

                nvgShapeAntiAlias(nvg, true)   -- 恢复 AA
                nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
            end

            nvgGlobalAlpha(nvg, 1)
            nvgRestore(nvg)
        end

        -- 寒冰甲屏障持续显示 (死亡时不显示)
        if not isDead and GameState.iceArmorActive then
            if not iceArmorShieldHandle then
                iceArmorShieldHandle = nvgCreateImage(nvg, "image/ice_armor_shield_20260327041930.png", 0)
            end
            if iceArmorShieldHandle and iceArmorShieldHandle >= 0 then
                local shieldSize = imgSize * 1.6
                local halfShield = shieldSize * 0.5
                -- 呼吸脉动动画
                local t = bs.time or 0
                local pulse = 1.0 + math.sin(t * 3) * 0.05
                local drawSize = shieldSize * pulse
                local halfDraw = drawSize * 0.5
                -- 透明度呼吸
                local baseAlpha = 0.65 + math.sin(t * 2.5 + 1) * 0.15
                nvgSave(nvg)
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - halfDraw, sy - halfDraw, drawSize, drawSize)
                local paint = nvgImagePattern(nvg, sx - halfDraw, sy - halfDraw,
                    drawSize, drawSize, 0, iceArmorShieldHandle, baseAlpha)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
                nvgRestore(nvg)
            end
        end

        -- 火焰护盾持续显示 (死亡时不显示)
        if not isDead and GameState.flameShieldTimer and GameState.flameShieldTimer > 0 then
            if not flameShieldHandle then
                flameShieldHandle = nvgCreateImage(nvg, "image/flame_shield_20260410130944.png", 0)
            end
            if flameShieldHandle and flameShieldHandle >= 0 then
                local shieldSize = imgSize * 1.6
                -- 呼吸脉动动画（频率略快于寒冰甲，体现火焰跳动感）
                local t = bs.time or 0
                local pulse = 1.0 + math.sin(t * 3.8) * 0.06
                local drawSize = shieldSize * pulse
                local halfDraw = drawSize * 0.5
                -- 透明度呼吸
                local baseAlpha = 0.7 + math.sin(t * 3.0 + 0.5) * 0.15
                nvgSave(nvg)
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - halfDraw, sy - halfDraw, drawSize, drawSize)
                local paint = nvgImagePattern(nvg, sx - halfDraw, sy - halfDraw,
                    drawSize, drawSize, 0, flameShieldHandle, baseAlpha)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
                nvgRestore(nvg)
            end
        end
    end

    -- ========================================================================
    -- 玩家血条 + 护盾条 + 受击闪烁
    -- ========================================================================

    function BattleView:DrawPlayerHP(nvg, l, bs)
        local p = bs.playerBattle
        if not p then return end

        local GameState = require("GameState")
        local ShieldManager = require("state.ShieldManager")
        local shield = ShieldManager.GetTotal()

        local sx = l.x + p.x
        local sy = l.y + p.y

        -- 头顶状态图标行 (元素附着 + debuff)
        local iconSz = 12
        local iconGap = 2
        local icons = {}  -- { {type, r, g, b, alpha, label, elemKey} }

        -- 元素附着图标
        if GameState.attachedElement and GameState.attachedElementTimer > 0 then
            local Config = require("Config")
            local ec = Config.ELEMENTS.colors[GameState.attachedElement]
            if ec then
                local fadeAlpha = math.min(1.0, GameState.attachedElementTimer / 2.0)
                icons[#icons + 1] = { type = "elem", r = ec[1], g = ec[2], b = ec[3], alpha = fadeAlpha, elemKey = GameState.attachedElement }
            end
        end

        -- 减疗 debuff
        if GameState.antiHealTimer > 0 then
            icons[#icons + 1] = { type = "label", r = 255, g = 80, b = 80, alpha = 1.0, label = "减疗" }
        end

        -- 减速 debuff
        if GameState.playerSlowTimer > 0 then
            icons[#icons + 1] = { type = "label", r = 80, g = 140, b = 255, alpha = 1.0, label = "减速" }
        end

        if #icons > 0 then
            local totalW = #icons * iconSz + (#icons - 1) * iconGap
            local startX = sx - totalW / 2
            local iconY = math.max(l.y, sy - 24 - iconSz - 4)  -- 角色头顶上方，不超出战斗区

            for idx, ic in ipairs(icons) do
                local ix = startX + (idx - 1) * (iconSz + iconGap)

                if ic.type == "elem" then
                    -- 元素图标
                    local iconPath = ELEM_ICON_PATHS[ic.elemKey]
                    if iconPath then
                        if not imgHandles.elemIcon[ic.elemKey] then
                            imgHandles.elemIcon[ic.elemKey] = nvgCreateImage(nvg, iconPath, 0)
                        end
                        local iconH = imgHandles.elemIcon[ic.elemKey]
                        if iconH and iconH > 0 then
                            local pulse = 0.7 + math.sin((bs.time or 0) * 5) * 0.3
                            local drawAlpha = ic.alpha * pulse
                            local ip = nvgImagePattern(nvg, ix, iconY, iconSz, iconSz, 0, iconH, drawAlpha)
                            nvgBeginPath(nvg)
                            nvgRect(nvg, ix, iconY, iconSz, iconSz)
                            nvgFillPaint(nvg, ip)
                            nvgFill(nvg)
                        end
                    end
                elseif ic.type == "label" then
                    -- 文字标签 debuff (小圆角背景 + 文字)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, ix - 1, iconY + 1, iconSz + 2, iconSz - 2, 2)
                    nvgFillColor(nvg, nvgRGBA(ic.r, ic.g, ic.b, math.floor(140 * ic.alpha)))
                    nvgFill(nvg)
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 7)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(230 * ic.alpha)))
                    nvgText(nvg, ix + iconSz / 2, iconY + iconSz / 2, ic.label)
                end
            end
        end

        -- 护盾脉冲光环 (有护盾时显示)
        if shield > 0 then
            local time = bs.time or 0
            local pulse = 0.3 + math.sin(time * 3) * 0.15
            local shieldGlow = nvgRadialGradient(nvg, sx, sy, 20, 35,
                nvgRGBA(80, 160, 255, math.floor(60 * pulse)),
                nvgRGBA(80, 160, 255, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, 35)
            nvgFillPaint(nvg, shieldGlow)
            nvgFill(nvg)
        end
    end

    -- ========================================================================
    -- 元素精灵 (水蓝色光球环绕玩家)
    -- ========================================================================

    -- 技能精灵图片句柄 (延迟加载)
    local hydraImgHandle = nil
    local lightningSpearImgHandle = nil

    function BattleView:DrawSpirits(nvg, l, bs)
        local GameState = require("GameState")
        local spirits = GameState.spirits
        if not spirits or #spirits == 0 then return end

        -- 延迟加载精灵图片
        if not hydraImgHandle then
            hydraImgHandle = nvgCreateImage(nvg, "image/hydra_snake_20260410144843.png", 0)
            if not hydraImgHandle or hydraImgHandle <= 0 then hydraImgHandle = 0 end
        end
        if not lightningSpearImgHandle then
            lightningSpearImgHandle = nvgCreateImage(nvg, "image/lightning_spear_20260410152150.png", 0)
            if not lightningSpearImgHandle or lightningSpearImgHandle <= 0 then lightningSpearImgHandle = 0 end
        end

        local time = bs.time or 0
        for _, sp in ipairs(spirits) do
            local sx = l.x + sp.x
            local sy = l.y + sp.y

            if sp.source == "hydra" and hydraImgHandle > 0 then
                -- 🔥 九头蛇: 独立移动的火蛇精灵
                local size = 40
                local bob = math.sin(time * 4 + (sp.orbitAngle or 0)) * 3
                local drawY = sy + bob
                -- 使用 AI 层计算的朝向
                local facing = (sp._faceDirX or 1)
                nvgSave(nvg)
                nvgTranslate(nvg, sx, drawY)
                nvgScale(nvg, facing, 1)
                local pat = nvgImagePattern(nvg, -size/2, -size/2, size, size, 0, hydraImgHandle, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, -size/2, -size/2, size, size)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                nvgRestore(nvg)

            elseif sp.source == "lightning_spear" and lightningSpearImgHandle > 0 then
                -- ⚡ 闪电矛: 追踪穿透弹体，朝移动方向旋转
                local imgW = 48
                local imgH = 32
                -- 使用 AI 层同步的 moveAngle (即 orbitAngle)
                local angle = sp.orbitAngle or 0
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)
                nvgRotate(nvg, angle)
                local pat = nvgImagePattern(nvg, -imgW/2, -imgH/2, imgW, imgH, 0, lightningSpearImgHandle, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, -imgW/2, -imgH/2, imgW, imgH)
                nvgFillPaint(nvg, pat)
                nvgFill(nvg)
                nvgRestore(nvg)

            else
                -- 默认: 通用精灵 (水蓝色圆)
                local pulse = 0.7 + math.sin(time * 6 + (sp.orbitAngle or 0)) * 0.3
                local r = 6 * pulse
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgFillColor(nvg, nvgRGBA(60, 180, 255, 220))
                nvgFill(nvg)
                local glow = nvgRadialGradient(nvg, sx, sy, r, r * 2.5,
                    nvgRGBA(60, 180, 255, 80), nvgRGBA(60, 180, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r * 2.5)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                if sp.atkCD and sp.atkCD < 0.1 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r * 1.5)
                    nvgFillColor(nvg, nvgRGBA(180, 230, 255, 120))
                    nvgFill(nvg)
                end
            end
        end
    end

    -- ========================================================================
    -- 佩戴称号 (特效框 + 粒子)
    -- ========================================================================

    local titleFrameHandle_ = nil
    local particleStarHandle_ = nil
    local particleGlowHandle_ = nil

    -- 粒子池 (固定数量, 循环复用)
    local TITLE_PARTICLE_COUNT = 8
    local titleParticles_ = nil

    local function InitTitleParticles()
        if titleParticles_ then return end
        titleParticles_ = {}
        for i = 1, TITLE_PARTICLE_COUNT do
            titleParticles_[i] = {
                phase = (i - 1) / TITLE_PARTICLE_COUNT,  -- 0~1 均匀分布
                speed = 0.3 + math.random() * 0.4,       -- 上升速度
                drift = (math.random() - 0.5) * 0.6,     -- 水平漂移
                size = 4 + math.random() * 6,             -- 粒子大小
                kind = (i % 2 == 0) and 1 or 2,           -- 1=star, 2=glow
            }
        end
    end

    function BattleView:DrawPlayerTitle(nvg, l, bs)
        local TitleSystem = require("TitleSystem")
        local tid = TitleSystem.GetEquipped()
        if not tid then return end

        local TitleConfig = require("TitleConfig")
        local def = TitleConfig.TITLES[tid]
        if not def then return end

        local p = bs.playerBattle
        if not p then return end

        -- 延迟加载图片
        if not titleFrameHandle_ then
            titleFrameHandle_ = nvgCreateImage(nvg, "title_frame_20260314051751.png", 0)
        end
        if not particleStarHandle_ then
            particleStarHandle_ = nvgCreateImage(nvg, "particle_star_20260313211331.png", 0)
        end
        if not particleGlowHandle_ then
            particleGlowHandle_ = nvgCreateImage(nvg, "particle_glow_20260313211330.png", 0)
        end

        InitTitleParticles()

        local sx = l.x + p.x
        local sy = l.y + p.y
        local time = bs.time or 0

        -- 边框尺寸与位置
        local frameW = 130
        local frameH = 42
        local frameX = sx - frameW / 2

        -- 检测是否有 debuff 图标，有则上移避免遮挡
        local GameState = require("GameState")
        local hasStatusIcons = (GameState.attachedElement and GameState.attachedElementTimer and GameState.attachedElementTimer > 0)
            or (GameState.antiHealTimer and GameState.antiHealTimer > 0)
            or (GameState.playerSlowTimer and GameState.playerSlowTimer > 0)
        local baseOffY = hasStatusIcons and 50 or 32
        local frameY = math.max(l.y, sy - baseOffY - frameH / 2)

        -- 绘制特效边框
        if titleFrameHandle_ and titleFrameHandle_ >= 0 then
            local fp = nvgImagePattern(nvg, frameX, frameY, frameW, frameH, 0, titleFrameHandle_, 0.85)
            nvgBeginPath(nvg)
            nvgRect(nvg, frameX, frameY, frameW, frameH)
            nvgFillPaint(nvg, fp)
            nvgFill(nvg)
        end

        -- 框内绘制称号文字 (金色)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 12)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 230, 160, 240))
        nvgText(nvg, sx, frameY + frameH / 2, def.name)

        -- 绘制粒子
        if not titleParticles_ then return end
        for i = 1, TITLE_PARTICLE_COUNT do
            local pt = titleParticles_[i]
            -- 循环动画: 每个粒子基于 phase 偏移
            local life = (time * pt.speed * 0.5 + pt.phase) % 1.0

            -- 从框两侧随机位置升起
            local spawnX = frameX + (pt.phase * frameW)
            local px = spawnX + pt.drift * life * 30
            local py = frameY - life * 25  -- 向上飘
            local alpha = math.sin(life * 3.14159) -- 淡入淡出
            local sz = pt.size * (0.5 + alpha * 0.5)

            local handle = (pt.kind == 1) and particleStarHandle_ or particleGlowHandle_
            if handle and handle >= 0 and alpha > 0.05 then
                local pp = nvgImagePattern(nvg, px - sz / 2, py - sz / 2, sz, sz, 0, handle, alpha * 0.7)
                nvgBeginPath(nvg)
                nvgRect(nvg, px - sz / 2, py - sz / 2, sz, sz)
                nvgFillPaint(nvg, pp)
                nvgFill(nvg)
            end
        end
    end
end

return DrawEntities
