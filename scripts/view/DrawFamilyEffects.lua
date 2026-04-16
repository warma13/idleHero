-- ============================================================================
-- view/DrawFamilyEffects.lua - 家族机制 & 精英视觉特效渲染
-- ============================================================================
-- 渲染内容:
--   1. 家族区域效果 (地面层, Enemies 之前)
--      - 潮池 (drowned): 蓝色水圈 + 波纹
--      - 孢子云 (fungal): 绿色毒雾
--   2. 精英/冠军标识 (Enemies 之后, 叠加层)
--      - 名字颜色: 精英=橙色, 冠军=红色
--      - 护盾条: 蓝色条覆盖血条上方
--      - 词缀图标: 小标签
--      - 闪光效果: 不死/传送/复活/重组/狂热/献祭
--   3. 家族视觉附加 (Enemies 之后)
--      - 群猎光环 (beasts): 红色边框
--      - 领袖光环 (fiends): 紫色辐射
--      - 相位闪烁 (voidborn): 半透明
--      - 逃跑标记 (coward/flee): 图标
-- ============================================================================

local DrawFamilyEffects = {}

function DrawFamilyEffects.Install(BattleView, imgHandles)

    -- ====================================================================
    -- 家族区域效果 (地面层, 在 DrawEnemies 之前调用)
    -- ====================================================================

    function BattleView:DrawFamilyZones(nvg, l, bs)
        local FamilyMechanics = require("battle.FamilyMechanics")
        local fState = FamilyMechanics.GetState()
        if not fState then return end

        local time = bs.time or 0
        local cullMargin = 80

        -- ── 潮池 (drowned): 蓝色水面圆 ──
        for _, pool in ipairs(fState.tidePools) do
            local sx = l.x + pool.x
            local sy = l.y + pool.y
            if sx < l.x - cullMargin or sx > l.x + l.w + cullMargin
                or sy < l.y - cullMargin or sy > l.y + l.h + cullMargin then
                goto next_pool
            end
            local lifeRatio = math.max(0.01, pool.duration / pool.maxDuration)
            local r = pool.radius or 40
            -- 水面底色
            local waterAlpha = math.floor(70 * lifeRatio)
            local waterGlow = nvgRadialGradient(nvg, sx, sy, 0, r,
                nvgRGBA(40, 120, 200, waterAlpha),
                nvgRGBA(20, 80, 160, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r)
            nvgFillPaint(nvg, waterGlow)
            nvgFill(nvg)

            -- 波纹环 (脉动)
            local ripple = math.sin(time * 3 + pool.x * 0.1) * 0.15 + 0.85
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r * ripple)
            nvgStrokeColor(nvg, nvgRGBA(80, 180, 255, math.floor(100 * lifeRatio)))
            nvgStrokeWidth(nvg, 1.5 * lifeRatio)
            nvgStroke(nvg)

            -- 第二层波纹 (相位偏移)
            local ripple2 = math.sin(time * 3 + pool.x * 0.1 + 2.0) * 0.12 + 0.7
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r * ripple2)
            nvgStrokeColor(nvg, nvgRGBA(60, 150, 230, math.floor(60 * lifeRatio)))
            nvgStrokeWidth(nvg, 1.0 * lifeRatio)
            nvgStroke(nvg)

            ::next_pool::
        end

        -- ── 孢子云 (fungal): 绿色毒雾 ──
        for _, cloud in ipairs(fState.sporeClouds) do
            local sx = l.x + cloud.x
            local sy = l.y + cloud.y
            if sx < l.x - cullMargin or sx > l.x + l.w + cullMargin
                or sy < l.y - cullMargin or sy > l.y + l.h + cullMargin then
                goto next_cloud
            end
            local lifeRatio = math.max(0.01, cloud.life / (cloud.maxLife or cloud.life + 0.01))
            local r = cloud.radius or 35
            -- 毒雾底色
            local sporeAlpha = math.floor(55 * lifeRatio)
            local sporeGlow = nvgRadialGradient(nvg, sx, sy, 0, r,
                nvgRGBA(80, 180, 40, sporeAlpha),
                nvgRGBA(50, 120, 20, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, r)
            nvgFillPaint(nvg, sporeGlow)
            nvgFill(nvg)

            -- 浮动孢子点 (3个旋转小圆)
            for i = 1, 3 do
                local angle = time * 1.5 + i * 2.094  -- 120° 间隔
                local dist = r * 0.5
                local px = sx + math.cos(angle) * dist
                local py = sy + math.sin(angle) * dist
                local dotR = 2.5 + math.sin(time * 4 + i) * 1
                nvgBeginPath(nvg)
                nvgCircle(nvg, px, py, dotR)
                nvgFillColor(nvg, nvgRGBA(120, 220, 60, math.floor(140 * lifeRatio)))
                nvgFill(nvg)
            end

            ::next_cloud::
        end
    end

    -- ====================================================================
    -- 精英/冠军标识 + 家族视觉附加 (Enemies 之后调用)
    -- ====================================================================

    function BattleView:DrawEliteOverlays(nvg, l, bs)
        local FamilyMechanics = require("battle.FamilyMechanics")
        local fState = FamilyMechanics.GetState()
        local time = bs.time or 0
        local cullMargin = 60

        for _, e in ipairs(bs.enemies) do
            if e.dead then goto next_enemy end

            local sx = l.x + e.x
            local sy = l.y + e.y
            if sx < l.x - cullMargin or sx > l.x + l.w + cullMargin
                or sy < l.y - cullMargin or sy > l.y + l.h + cullMargin then
                goto next_enemy
            end

            local r = e.radius or 16
            local imgSize = r * 3.3

            -- ── 精英/冠军名字颜色覆盖 ──
            if e.eliteRank then
                local hpW = imgSize * 1.1
                local hpY = sy - imgSize * 0.5 - 10

                -- 精英/冠军标签
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 7)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                if e.eliteRank == "champion" then
                    nvgFillColor(nvg, nvgRGBA(255, 50, 50, 240))
                    nvgText(nvg, sx, hpY - 12, "★冠军")
                else
                    nvgFillColor(nvg, nvgRGBA(255, 165, 0, 240))
                    nvgText(nvg, sx, hpY - 12, "◆精英")
                end

                -- 精英边框光环 (已移除: 不再渲染圆圈描边)
            end

            -- ── 精英护盾条 (蓝色, 血条上方) ──
            if e._shieldHP and e._shieldHP > 0 and e._shieldMax and e._shieldMax > 0 then
                local hpW = imgSize * 1.1
                local shieldH = 3
                local shieldX = sx - hpW / 2
                local shieldY = sy - imgSize * 0.5 - 15
                -- 护盾背景
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, shieldX, shieldY, hpW, shieldH, 1.5)
                nvgFillColor(nvg, nvgRGBA(20, 40, 80, 160))
                nvgFill(nvg)
                -- 护盾值
                local shieldPct = math.min(1, e._shieldHP / e._shieldMax)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, shieldX, shieldY, hpW * shieldPct, shieldH, 1.5)
                nvgFillColor(nvg, nvgRGBA(60, 160, 255, 220))
                nvgFill(nvg)
            end

            -- ── 闪光效果 ──
            local flashFields = {
                { field = "_undyingFlash",    r = 255, g = 255, b = 200 },  -- 金色
                { field = "_teleportFlash",   r = 160, g = 80,  b = 255 },  -- 紫色
                { field = "_reviveFlash",     r = 100, g = 255, b = 100 },  -- 绿色
                { field = "_reassembleFlash", r = 200, g = 200, b = 255 },  -- 银色
                { field = "_fanaticFlash",    r = 255, g = 80,  b = 80 },   -- 红色
                { field = "_sacrificeFlash",  r = 255, g = 200, b = 50 },   -- 金黄
            }
            for _, ff in ipairs(flashFields) do
                local v = e[ff.field]
                if v and v > 0 then
                    local alpha = math.floor(math.min(1.0, v / 0.3) * 120)
                    local flashGlow = nvgRadialGradient(nvg, sx, sy, 0, r * 1.8,
                        nvgRGBA(ff.r, ff.g, ff.b, alpha),
                        nvgRGBA(ff.r, ff.g, ff.b, 0))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r * 1.8)
                    nvgFillPaint(nvg, flashGlow)
                    nvgFill(nvg)
                end
            end

            -- ── 虚空相位半透明 (已移除光环) ──

            -- ── 群猎光环 (已移除) ──

            -- ── 领袖光环 (已移除光环, 保留文字标记) ──
            if fState and fState.leaderAlive == e then
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 7)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(nvg, nvgRGBA(200, 120, 255, 200))
                nvgText(nvg, sx, sy + r + 2, "领袖")
            end

            -- ── 逃跑标记 ──
            if FamilyMechanics.IsFleeing(e) then
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 7)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(nvg, nvgRGBA(200, 200, 100, 180))
                nvgText(nvg, sx, sy + r + 2, "逃跑")
            end

            -- ── 毒液层数 (venomkin) ──
            if e.familyType == "venomkin" and e._venomStacks and e._venomStacks > 0 then
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 7)
                nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
                nvgFillColor(nvg, nvgRGBA(100, 220, 60, 200))
                local hpY = sy - imgSize * 0.5 - 10
                nvgText(nvg, sx + imgSize * 0.55 + 2, hpY + 4,
                    "毒×" .. tostring(e._venomStacks))
            end

            -- ── 碎片标记 (constructs) ──
            if e._isFragment then
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 7)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(nvg, nvgRGBA(180, 200, 220, 180))
                nvgText(nvg, sx, sy + r + 2, "碎片")
            end

            -- ── 重组进度条 (constructs: _pendingRevive + _reassembleTimer) ──
            if e._pendingRevive and e._reassembleTimer and e._reassembleDuration then
                local prog = 1.0 - (e._reassembleTimer / e._reassembleDuration)
                prog = math.max(0, math.min(1, prog))
                local barW = imgSize * 0.8
                local barH = 3
                local barX = sx - barW / 2
                local barY = sy + r + 12
                -- 背景
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW, barH, 1)
                nvgFillColor(nvg, nvgRGBA(40, 40, 60, 140))
                nvgFill(nvg)
                -- 进度
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW * prog, barH, 1)
                nvgFillColor(nvg, nvgRGBA(180, 200, 255, 200))
                nvgFill(nvg)
                -- 文字
                nvgFontFace(nvg, "sans")
                nvgFontSize(nvg, 6)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                nvgFillColor(nvg, nvgRGBA(200, 210, 255, 180))
                nvgText(nvg, sx, barY + barH + 1, "重组中")
            end

            ::next_enemy::
        end
    end

end  -- DrawFamilyEffects.Install

return DrawFamilyEffects
