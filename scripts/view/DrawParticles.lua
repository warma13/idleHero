-- ============================================================================
-- view/DrawParticles.lua - 粒子系统渲染
-- ============================================================================

local DrawParticles = {}

function DrawParticles.Install(BattleView, imgHandles)
    -- Image handles used exclusively by DrawParticles
    local explosionImgHandle = nil
    local smokeImgHandle     = nil
    local emberImgHandle     = nil
    local frostShardHandle   = nil
    local frostMistHandle    = nil
    local frostSnowHandle    = nil

    -- 同屏伤害数字上限 (普通特效等级也生效)
    local MAX_VISIBLE_DMGTEXT = 20
    local MAX_VISIBLE_REACTION = 8

    function BattleView:DrawParticles(nvg, l, bs)
        local margin = 40  -- 视口外裁剪边距
        local lx, ly, lw, lh = l.x, l.y, l.w, l.h
        local visibleDmg = 0
        local visibleReaction = 0

        for _, p in ipairs(bs.particles) do
            local sx = lx + p.x
            local sy = ly + p.y
            local lifeRatio = math.max(0, p.life / p.maxLife)
            local alpha = math.floor(255 * lifeRatio)
            local size = (p.size or 3) * lifeRatio

            -- 视口外剔除: 粒子超出战斗区域+边距则跳过绘制
            if sx < lx - margin or sx > lx + lw + margin
                or sy < ly - margin or sy > ly + lh + margin then
                goto continue_particle
            end

            -- 同屏数量限制
            if p.ptype == "dmgText" then
                visibleDmg = visibleDmg + 1
                if visibleDmg > MAX_VISIBLE_DMGTEXT then
                    goto continue_particle
                end
            elseif p.ptype == "reactionText" then
                visibleReaction = visibleReaction + 1
                if visibleReaction > MAX_VISIBLE_REACTION then
                    goto continue_particle
                end
            end

            if p.ptype == "reactionText" then
                -- 元素反应跳字: 弹出缩放 + 淡出
                local progress = 1.0 - lifeRatio  -- 0→1
                local scale
                if progress < 0.15 then
                    -- 弹出放大: 1.0 → 2.0
                    scale = 1.0 + (progress / 0.15) * 1.0
                elseif progress < 0.3 then
                    -- 回弹缩小: 2.0 → 1.2
                    scale = 2.0 - ((progress - 0.15) / 0.15) * 0.8
                else
                    -- 稳定后缓慢缩小
                    scale = 1.2 - ((progress - 0.3) / 0.7) * 0.2
                end
                local fs = (p.fontSize or 14) * scale
                nvgSave(nvg)
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, fs)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local c = p.color or { 255, 255, 100 }
                -- 描边 (4-pass: 上下左右)
                nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.7)))
                nvgText(nvg, sx - 1, sy, p.text)
                nvgText(nvg, sx + 1, sy, p.text)
                nvgText(nvg, sx, sy - 1, p.text)
                nvgText(nvg, sx, sy + 1, p.text)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
                nvgText(nvg, sx, sy, p.text)
                nvgRestore(nvg)

            elseif p.ptype == "dmgText" then
                -- 限位: 飘字不超出战斗区边界
                local clampMargin = 20
                sx = math.max(lx + clampMargin, math.min(lx + lw - clampMargin, sx))
                sy = math.max(ly + clampMargin, math.min(ly + lh - clampMargin, sy))

                nvgFontFace(nvg, "sans")
                local fontSize = p.fontSize or 12
                if p.isCrit then fontSize = fontSize * 1.4 end
                nvgFontSize(nvg, fontSize)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                local c = p.color or { 255, 255, 255 }
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
                nvgText(nvg, sx, sy, p.text)

            elseif p.ptype == "meteorExplosion" then
                -- 延迟加载图片
                if not explosionImgHandle then
                    explosionImgHandle = nvgCreateImage(nvg, "Textures/explosion.png", 0)
                end
                if not smokeImgHandle then
                    smokeImgHandle = nvgCreateImage(nvg, "Textures/smoke.png", 0)
                end
                if not emberImgHandle then
                    emberImgHandle = nvgCreateImage(nvg, "Textures/ember.png", 0)
                end

                local imgH = nil
                local drawSize = p.size or 20

                if p.subtype == "fireball" then
                    imgH = explosionImgHandle
                    -- 火球快速放大后收缩
                    local progress = 1.0 - lifeRatio
                    local scale = progress < 0.3 and (progress / 0.3) or 1.0
                    drawSize = drawSize * scale
                elseif p.subtype == "smoke" then
                    imgH = smokeImgHandle
                    -- 烟雾缓慢膨胀
                    drawSize = drawSize * (0.5 + (1.0 - lifeRatio) * 0.8)
                elseif p.subtype == "ember" then
                    imgH = emberImgHandle
                    -- 碎片逐渐缩小
                    drawSize = drawSize * lifeRatio
                end

                if imgH and imgH > 0 and drawSize > 1 then
                    local halfS = drawSize / 2
                    local imgPaint = nvgImagePattern(nvg, sx - halfS, sy - halfS,
                        drawSize, drawSize, 0, imgH, lifeRatio)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - halfS, sy - halfS, drawSize, drawSize)
                    nvgFillPaint(nvg, imgPaint)
                    nvgFill(nvg)
                end

            elseif p.ptype == "frostExplosion" then
                -- 延迟加载冰霜粒子图片
                if not frostShardHandle then
                    frostShardHandle = nvgCreateImage(nvg, "frost_shard_20260306235536.png", 0)
                end
                if not frostMistHandle then
                    frostMistHandle = nvgCreateImage(nvg, "frost_mist_20260306235530.png", 0)
                end
                if not frostSnowHandle then
                    frostSnowHandle = nvgCreateImage(nvg, "frost_snowflake_20260306235527.png", 0)
                end

                local imgH = nil
                local drawSize = p.size or 20

                if p.subtype == "iceShard" then
                    imgH = frostShardHandle
                    -- 冰晶碎片: 快速爆裂后缩小 + 旋转
                    local progress = 1.0 - lifeRatio
                    local scale = progress < 0.2 and (progress / 0.2) or (1.0 - (progress - 0.2) * 0.5)
                    drawSize = drawSize * math.max(0.3, scale)
                elseif p.subtype == "frostMist" then
                    imgH = frostMistHandle
                    -- 霜雾: 缓慢膨胀 + 淡出
                    drawSize = drawSize * (0.4 + (1.0 - lifeRatio) * 0.9)
                elseif p.subtype == "snowflake" then
                    imgH = frostSnowHandle
                    -- 雪花: 缓慢缩小 + 飘动
                    drawSize = drawSize * (0.5 + lifeRatio * 0.5)
                end

                if imgH and imgH > 0 and drawSize > 1 then
                    local halfS = drawSize / 2
                    -- 冰晶碎片和雪花加旋转
                    if p.subtype == "iceShard" or p.subtype == "snowflake" then
                        nvgSave(nvg)
                        nvgTranslate(nvg, sx, sy)
                        local rotSpeed = p.subtype == "iceShard" and 8.0 or 2.0
                        nvgRotate(nvg, (bs.time or 0) * rotSpeed + (p.x or 0) * 0.1)
                        local imgPaint = nvgImagePattern(nvg, -halfS, -halfS,
                            drawSize, drawSize, 0, imgH, lifeRatio)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, -halfS, -halfS, drawSize, drawSize)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                        nvgRestore(nvg)
                    else
                        local imgPaint = nvgImagePattern(nvg, sx - halfS, sy - halfS,
                            drawSize, drawSize, 0, imgH, lifeRatio)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, sx - halfS, sy - halfS, drawSize, drawSize)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                    end
                else
                    -- fallback: 纯色圆形
                    local fr, fg, fb = 140, 220, 255
                    if p.subtype == "frostMist" then
                        fr, fg, fb = 180, 230, 250
                    elseif p.subtype == "snowflake" then
                        fr, fg, fb = 220, 240, 255
                    end
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, drawSize * 0.4)
                    nvgFillColor(nvg, nvgRGBA(fr, fg, fb, alpha))
                    nvgFill(nvg)
                end

            elseif p.ptype == "levelUpSparkle" then
                -- 金色光点: 上飘 + 闪烁 + 淡出
                local sparkAlpha = math.floor(255 * lifeRatio * (0.6 + 0.4 * math.sin((p.life or 0) * 12)))
                local sparkSize = (p.size or 3) * (0.5 + lifeRatio * 0.5)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, sparkSize)
                nvgFillColor(nvg, nvgRGBA(255, 230, 80, sparkAlpha))
                nvgFill(nvg)
                -- 外发光
                if sparkSize > 1.5 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, sparkSize * 2.5)
                    nvgFillColor(nvg, nvgRGBA(255, 200, 50, math.floor(sparkAlpha * 0.2)))
                    nvgFill(nvg)
                end

            elseif p.ptype == "levelUpRing" then
                -- 光环扩散: 从0扩大到40半径, 淡出
                local progress = 1.0 - lifeRatio
                local ringR = progress * 40
                local ringAlpha = math.floor(200 * lifeRatio)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, ringR)
                nvgStrokeWidth(nvg, 2.5 * lifeRatio)
                nvgStrokeColor(nvg, nvgRGBA(255, 215, 0, ringAlpha))
                nvgStroke(nvg)

            elseif p.ptype == "levelUpText" then
                -- "LEVEL UP!" 跳字: 弹出缩放 + 描边 + 淡出
                local progress = 1.0 - lifeRatio
                local scale
                if progress < 0.12 then
                    scale = 1.0 + (progress / 0.12) * 0.6
                elseif progress < 0.25 then
                    scale = 1.6 - ((progress - 0.12) / 0.13) * 0.4
                else
                    scale = 1.2
                end
                local fs = (p.fontSize or 14) * scale
                local c = p.color or { 255, 230, 80 }
                nvgSave(nvg)
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, fs)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                -- 描边 (4-pass: 上下左右)
                nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.8)))
                nvgText(nvg, sx - 1, sy, p.text)
                nvgText(nvg, sx + 1, sy, p.text)
                nvgText(nvg, sx, sy - 1, p.text)
                nvgText(nvg, sx, sy + 1, p.text)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
                nvgText(nvg, sx, sy, p.text)
                nvgRestore(nvg)

            elseif p.ptype == "equipDrop" then
                -- 装备掉落: 彩色方块 + 槽位文字 + 名字
                local c = p.color or { 200, 200, 200 }
                local boxSize = 22

                -- 弹跳缩放 (刚出现时放大)
                local progress = 1.0 - lifeRatio
                local bScale = 1.0
                if progress < 0.15 then
                    bScale = 1.0 + (progress / 0.15) * 0.4
                elseif progress < 0.3 then
                    bScale = 1.4 - ((progress - 0.15) / 0.15) * 0.4
                end
                local drawBox = boxSize * bScale

                -- 方块背景
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, sx - drawBox / 2, sy - drawBox / 2, drawBox, drawBox, 4)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.35)))
                nvgFill(nvg)
                nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)

                -- 槽位首字
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 10)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
                local iconText = p.slotName and string.sub(p.slotName, 1, 3) or "?"
                nvgText(nvg, sx, sy, iconText)

                -- 品质名称
                nvgFontSize(nvg, 8)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], math.floor(alpha * 0.8)))
                nvgText(nvg, sx, sy + drawBox / 2 + 8, p.text or "")

            else
                local c = p.color or { 255, 200, 100 }
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, size)
                nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], alpha))
                nvgFill(nvg)
            end
            ::continue_particle::
        end
    end
end

return DrawParticles
