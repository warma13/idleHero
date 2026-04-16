-- ============================================================================
-- view/DrawEffects.lua - 技能特效 & Boss 特效渲染
-- ============================================================================

local DrawEffects = {}

function DrawEffects.Install(BattleView, imgHandles)
    -- Boss 技能特效图片句柄
    local bossBarrageIceHandle   = nil
    local bossBarrageFireHandle  = nil
    local bossBarrageArcaneHandle = nil
    local bossBreathIceHandle    = nil
    local bossBreathFireHandle   = nil
    local bossBreathArcaneHandle = nil
    local bossExplodeIceHandle   = nil
    local bossExplodeFireHandle  = nil
    local bossExplodeArcaneHandle = nil
    local bossFrozenFieldHandle  = nil
    local bossLavaFieldHandle    = nil
    local bossArcaneFieldHandle  = nil
    local bossIceArmorHandle     = nil
    local bossFireArmorHandle    = nil
    local bossArcaneArmorHandle  = nil
    local bossBarragePoisonHandle   = nil
    local bossBreathPoisonHandle    = nil
    local bossExplodePoisonHandle   = nil
    local bossPoisonFieldHandle     = nil
    local bossPoisonArmorHandle     = nil
    local bossBarragePhysicalHandle = nil
    local bossBreathPhysicalHandle  = nil
    local bossExplodePhysicalHandle = nil
    local bossPhysicalFieldHandle   = nil
    local bossPhysicalArmorHandle   = nil
    local bossBarrageWaterHandle    = nil
    local bossBreathWaterHandle     = nil
    local bossExplodeWaterHandle    = nil
    local bossFieldWaterHandle      = nil
    local bossArmorWaterHandle      = nil

    -- Boss 技能 → 图片映射表 (element → {varName, path})
    -- 统一命名规范: Textures/skills/boss_{templateId}_{element}.png
    local BOSS_SKILL_IMAGES = {
        barrage = {
            fire     = { var = "bossBarrageFireHandle",     path = "Textures/skills/boss_barrage_fire.png" },
            ice      = { var = "bossBarrageIceHandle",      path = "Textures/skills/boss_barrage_ice.png" },
            arcane   = { var = "bossBarrageArcaneHandle",   path = "Textures/skills/boss_barrage_arcane.png" },
            poison   = { var = "bossBarragePoisonHandle",   path = "Textures/skills/boss_barrage_poison.png" },
            physical = { var = "bossBarragePhysicalHandle", path = "Textures/skills/boss_barrage_physical.png" },
            water    = { var = "bossBarrageWaterHandle",    path = "Textures/skills/boss_barrage_water.png" },
        },
        dragonBreath = {
            fire     = { var = "bossBreathFireHandle",     path = "Textures/skills/boss_breath_fire.png" },
            ice      = { var = "bossBreathIceHandle",      path = "Textures/skills/boss_breath_ice.png" },
            arcane   = { var = "bossBreathArcaneHandle",   path = "Textures/skills/boss_breath_arcane.png" },
            poison   = { var = "bossBreathPoisonHandle",   path = "Textures/skills/boss_breath_poison.png" },
            physical = { var = "bossBreathPhysicalHandle", path = "Textures/skills/boss_breath_physical.png" },
            water    = { var = "bossBreathWaterHandle",    path = "Textures/skills/boss_breath_water.png" },
        },
        deathExplode = {
            fire     = { var = "bossExplodeFireHandle",     path = "Textures/skills/boss_detonate_fire.png" },
            ice      = { var = "bossExplodeIceHandle",      path = "Textures/skills/boss_detonate_ice.png" },
            arcane   = { var = "bossExplodeArcaneHandle",   path = "Textures/skills/boss_detonate_arcane.png" },
            poison   = { var = "bossExplodePoisonHandle",   path = "Textures/skills/boss_detonate_poison.png" },
            physical = { var = "bossExplodePhysicalHandle", path = "Textures/skills/boss_detonate_physical.png" },
            water    = { var = "bossExplodeWaterHandle",    path = "Textures/skills/boss_detonate_water.png" },
        },
        frozenField = {
            fire     = { var = "bossLavaFieldHandle",      path = "Textures/skills/boss_field_fire.png" },
            ice      = { var = "bossFrozenFieldHandle",     path = "Textures/skills/boss_field_ice.png" },
            arcane   = { var = "bossArcaneFieldHandle",    path = "Textures/skills/boss_field_arcane.png" },
            poison   = { var = "bossPoisonFieldHandle",    path = "Textures/skills/boss_field_poison.png" },
            physical = { var = "bossPhysicalFieldHandle",  path = "Textures/skills/boss_field_physical.png" },
            water    = { var = "bossFieldWaterHandle",     path = "Textures/skills/boss_field_water.png" },
        },
        iceArmor = {
            fire     = { var = "bossFireArmorHandle",      path = "Textures/skills/boss_armor_fire.png" },
            ice      = { var = "bossIceArmorHandle",       path = "Textures/skills/boss_armor_ice.png" },
            arcane   = { var = "bossArcaneArmorHandle",    path = "Textures/skills/boss_armor_arcane.png" },
            poison   = { var = "bossPoisonArmorHandle",    path = "Textures/skills/boss_armor_poison.png" },
            physical = { var = "bossPhysicalArmorHandle",  path = "Textures/skills/boss_armor_physical.png" },
            water    = { var = "bossArmorWaterHandle",     path = "Textures/skills/boss_armor_water.png" },
        },
    }

    -- handle 变量名 → 实际变量的 setter/getter (用闭包避免 upvalue 限制)
    local bossHandleSetters = {
        bossBarrageFireHandle = function(h) bossBarrageFireHandle = h end,
        bossBarrageIceHandle  = function(h) bossBarrageIceHandle  = h end,
        bossBreathFireHandle  = function(h) bossBreathFireHandle  = h end,
        bossBreathIceHandle   = function(h) bossBreathIceHandle   = h end,
        bossExplodeFireHandle = function(h) bossExplodeFireHandle = h end,
        bossExplodeIceHandle  = function(h) bossExplodeIceHandle  = h end,
        bossLavaFieldHandle   = function(h) bossLavaFieldHandle   = h end,
        bossFrozenFieldHandle = function(h) bossFrozenFieldHandle = h end,
        bossFireArmorHandle    = function(h) bossFireArmorHandle    = h end,
        bossIceArmorHandle     = function(h) bossIceArmorHandle    = h end,
        bossBarrageArcaneHandle = function(h) bossBarrageArcaneHandle = h end,
        bossBreathArcaneHandle  = function(h) bossBreathArcaneHandle  = h end,
        bossExplodeArcaneHandle = function(h) bossExplodeArcaneHandle = h end,
        bossArcaneFieldHandle   = function(h) bossArcaneFieldHandle   = h end,
        bossArcaneArmorHandle   = function(h) bossArcaneArmorHandle   = h end,
        bossBarragePoisonHandle   = function(h) bossBarragePoisonHandle   = h end,
        bossBreathPoisonHandle    = function(h) bossBreathPoisonHandle    = h end,
        bossExplodePoisonHandle   = function(h) bossExplodePoisonHandle   = h end,
        bossPoisonFieldHandle     = function(h) bossPoisonFieldHandle     = h end,
        bossPoisonArmorHandle     = function(h) bossPoisonArmorHandle     = h end,
        bossBarragePhysicalHandle = function(h) bossBarragePhysicalHandle = h end,
        bossBreathPhysicalHandle  = function(h) bossBreathPhysicalHandle  = h end,
        bossExplodePhysicalHandle = function(h) bossExplodePhysicalHandle = h end,
        bossPhysicalFieldHandle   = function(h) bossPhysicalFieldHandle   = h end,
        bossPhysicalArmorHandle   = function(h) bossPhysicalArmorHandle   = h end,
        bossBarrageWaterHandle    = function(h) bossBarrageWaterHandle    = h end,
        bossBreathWaterHandle     = function(h) bossBreathWaterHandle     = h end,
        bossExplodeWaterHandle    = function(h) bossExplodeWaterHandle    = h end,
        bossFieldWaterHandle      = function(h) bossFieldWaterHandle      = h end,
        bossArmorWaterHandle      = function(h) bossArmorWaterHandle      = h end,
    }
    local bossHandleGetters = {
        bossBarrageFireHandle = function() return bossBarrageFireHandle end,
        bossBarrageIceHandle  = function() return bossBarrageIceHandle  end,
        bossBreathFireHandle  = function() return bossBreathFireHandle  end,
        bossBreathIceHandle   = function() return bossBreathIceHandle   end,
        bossExplodeFireHandle = function() return bossExplodeFireHandle end,
        bossExplodeIceHandle  = function() return bossExplodeIceHandle  end,
        bossLavaFieldHandle   = function() return bossLavaFieldHandle   end,
        bossFrozenFieldHandle = function() return bossFrozenFieldHandle end,
        bossFireArmorHandle     = function() return bossFireArmorHandle     end,
        bossIceArmorHandle      = function() return bossIceArmorHandle      end,
        bossBarrageArcaneHandle = function() return bossBarrageArcaneHandle end,
        bossBreathArcaneHandle  = function() return bossBreathArcaneHandle  end,
        bossExplodeArcaneHandle = function() return bossExplodeArcaneHandle end,
        bossArcaneFieldHandle   = function() return bossArcaneFieldHandle   end,
        bossArcaneArmorHandle   = function() return bossArcaneArmorHandle   end,
        bossBarragePoisonHandle   = function() return bossBarragePoisonHandle   end,
        bossBreathPoisonHandle    = function() return bossBreathPoisonHandle    end,
        bossExplodePoisonHandle   = function() return bossExplodePoisonHandle   end,
        bossPoisonFieldHandle     = function() return bossPoisonFieldHandle     end,
        bossPoisonArmorHandle     = function() return bossPoisonArmorHandle     end,
        bossBarragePhysicalHandle = function() return bossBarragePhysicalHandle end,
        bossBreathPhysicalHandle  = function() return bossBreathPhysicalHandle  end,
        bossExplodePhysicalHandle = function() return bossExplodePhysicalHandle end,
        bossPhysicalFieldHandle   = function() return bossPhysicalFieldHandle   end,
        bossPhysicalArmorHandle   = function() return bossPhysicalArmorHandle   end,
        bossBarrageWaterHandle    = function() return bossBarrageWaterHandle    end,
        bossBreathWaterHandle     = function() return bossBreathWaterHandle     end,
        bossExplodeWaterHandle    = function() return bossExplodeWaterHandle    end,
        bossFieldWaterHandle      = function() return bossFieldWaterHandle      end,
        bossArmorWaterHandle      = function() return bossArmorWaterHandle      end,
    }

    --- 统一的 Boss 技能图片加载辅助函数
    --- @param nvg userdata
    --- @param skillType string BOSS_SKILL_IMAGES 的 key (barrage/dragonBreath/deathExplode/frozenField/iceArmor)
    --- @param element string 元素类型
    --- @return number nvg image handle, 0 表示加载失败
    local function getBossSkillImage(nvg, skillType, element)
        local elemMap = BOSS_SKILL_IMAGES[skillType]
        if not elemMap then return 0 end
        local info = elemMap[element or "ice"]
        if not info then
            -- 回退到 ice
            info = elemMap["ice"]
        end
        if not info then return 0 end
        local getter = bossHandleGetters[info.var]
        if getter then
            local h = getter()
            if h then return h end
        end
        -- 首次加载
        local h = nvgCreateImage(nvg, info.path, 0)
        if not h or h <= 0 then h = 0 end
        local setter = bossHandleSetters[info.var]
        if setter then setter(h) end
        return h
    end

    -- Boss 图片分帧预加载队列
    local bossPreloadQueue   = {}   -- { {var="bossBarrageIceHandle", path="..."}, ... }
    local bossPreloadIdx     = 0    -- 当前已加载到的索引
    local bossPreloadChapter = 0    -- 已为哪个章节预加载
    local bossPreloadStage   = 0    -- 已为哪个关卡预加载
    local _barrageCountCache = {}   -- barrage 弹幕计数缓存（每帧重置）

    --- 构建 boss 图片预加载队列 (根据当前关卡 boss 的技能和元素)
    local function BuildBossPreloadQueue(chapter, stage)
        local StageConfig = require("StageConfig")
        local stageCfg = StageConfig.GetStage(chapter, stage)
        if not stageCfg then return end

        bossPreloadQueue = {}
        bossPreloadIdx   = 0
        bossPreloadChapter = chapter
        bossPreloadStage   = stage

        -- 从 waves 中找出 boss 怪物 ID
        local bossIds = {}
        if stageCfg.waves then
            for _, wave in ipairs(stageCfg.waves) do
                if wave.monsters then
                    for _, m in ipairs(wave.monsters) do
                        local monsterCfg = StageConfig.MONSTERS[m.id]
                        if monsterCfg and monsterCfg.isBoss then
                            bossIds[m.id] = monsterCfg
                        end
                    end
                end
            end
        end

        -- 为每个 boss 收集需要预加载的图片
        for bossId, monsterCfg in pairs(bossIds) do
            local elemKey = monsterCfg.element or "ice"

            -- boss 自身图片
            if monsterCfg.image and not imgHandles.mob[monsterCfg.image] then
                table.insert(bossPreloadQueue, { type = "mob", path = monsterCfg.image })
            end

            -- boss 技能图片
            for skillName, elemMap in pairs(BOSS_SKILL_IMAGES) do
                if monsterCfg[skillName] then
                    local info = elemMap[elemKey] or elemMap["ice"]
                    if info and not bossHandleGetters[info.var]() then
                        table.insert(bossPreloadQueue, { type = "boss", var = info.var, path = info.path })
                    end
                end
            end
        end

        -- 预加载非 boss 怪物的 deathExplode 特效图片（避免渲染时懒加载卡顿）
        if stageCfg.waves then
            for _, wave in ipairs(stageCfg.waves) do
                if wave.monsters then
                    for _, m in ipairs(wave.monsters) do
                        local monsterCfg = StageConfig.MONSTERS[m.id]
                        if monsterCfg and not monsterCfg.isBoss and monsterCfg.deathExplode then
                            local elemKey = monsterCfg.deathExplode.element or monsterCfg.element or "ice"
                            -- 预加载 deathExplode 对应的爆炸图片
                            local explodeInfo = BOSS_SKILL_IMAGES.deathExplode and BOSS_SKILL_IMAGES.deathExplode[elemKey]
                            if not explodeInfo then
                                explodeInfo = BOSS_SKILL_IMAGES.barrage and BOSS_SKILL_IMAGES.barrage[elemKey]
                            end
                            if explodeInfo and not bossHandleGetters[explodeInfo.var]() then
                                table.insert(bossPreloadQueue, { type = "boss", var = explodeInfo.var, path = explodeInfo.path })
                            end
                            -- 预加载怪物自身图片
                            if monsterCfg.image and not imgHandles.mob[monsterCfg.image] then
                                table.insert(bossPreloadQueue, { type = "mob", path = monsterCfg.image })
                            end
                        end
                    end
                end
            end
        end

        if #bossPreloadQueue > 0 then
            print("[BattleView] Boss preload queue built: " .. #bossPreloadQueue .. " images for " .. chapter .. "-" .. stage)
        end
    end

    --- 每帧预加载 1 张 boss 图片 (分帧避免卡顿)
    local function TickBossPreload(nvg)
        if bossPreloadIdx >= #bossPreloadQueue then return end
        bossPreloadIdx = bossPreloadIdx + 1
        local item = bossPreloadQueue[bossPreloadIdx]
        if not item then return end

        local h = nvgCreateImage(nvg, item.path, 0)
        if item.type == "mob" then
            imgHandles.mob[item.path] = h
        elseif item.type == "boss" and item.var then
            local setter = bossHandleSetters[item.var]
            if setter then setter(h) end
        end
        print("[BattleView] Preloaded [" .. bossPreloadIdx .. "/" .. #bossPreloadQueue .. "] " .. item.path)
    end

    -- ========================================================================
    -- 技能特效 (v3.0 D4模型: 3元素 fire/ice/lightning)
    -- ========================================================================

    -- 元素颜色查表
    local ELEM_COLORS = {
        fire      = { 255, 120, 30 },
        ice       = { 100, 200, 255 },
        lightning = { 255, 230, 80 },
    }

    function BattleView:DrawSkillEffects(nvg, l, bs)
        -- LOD 降级: 根据同屏特效数量决定绘制精度
        -- 0 = 完整, 1 = 中等(去装饰), 2 = 极简(只画主体)
        local effCount = #bs.skillEffects
        local lod = effCount <= 8 and 0 or (effCount <= 16 and 1 or 2)

        for _, eff in ipairs(bs.skillEffects) do
            local sx = l.x + (eff.x or 0)
            local sy = l.y + (eff.y or 0)
            local lifeRatio = math.max(0.01, eff.life / eff.maxLife)
            local alpha = math.floor(255 * lifeRatio)

            -- ==============================================================
            -- 🔥 fire_bolt — 火焰弹: 橙红弹丸飞向目标
            -- ==============================================================
            if eff.type == "fire_bolt" then
                local progress = 1.0 - lifeRatio
                local tx = l.x + (eff.targetX or eff.x or 0)
                local ty = l.y + (eff.targetY or eff.y or 0)
                local bx = sx + (tx - sx) * progress
                local by = sy + (ty - sy) * progress
                local r = (eff.radius or 20) * 0.4
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r)
                nvgFillColor(nvg, nvgRGBA(255, 120, 30, alpha))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r * 0.4)
                nvgFillColor(nvg, nvgRGBA(255, 240, 180, alpha))
                nvgFill(nvg)
                if lod < 2 then
                    local trailGlow = nvgRadialGradient(nvg, bx, by, r * 0.5, r * 2.5,
                        nvgRGBA(255, 80, 0, math.floor(alpha * 0.4)),
                        nvgRGBA(255, 40, 0, 0))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, bx, by, r * 2.5)
                    nvgFillPaint(nvg, trailGlow)
                    nvgFill(nvg)
                end

            -- ==============================================================
            -- ❄️ frost_bolt — 冰霜弹: 冰蓝弹丸飞向目标
            -- ==============================================================
            elseif eff.type == "frost_bolt" then
                local progress = 1.0 - lifeRatio
                local tx = l.x + (eff.targetX or eff.x or 0)
                local ty = l.y + (eff.targetY or eff.y or 0)
                local bx = sx + (tx - sx) * progress
                local by = sy + (ty - sy) * progress
                local r = (eff.radius or 20) * 0.4
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r)
                nvgFillColor(nvg, nvgRGBA(100, 200, 255, alpha))
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r * 0.4)
                nvgFillColor(nvg, nvgRGBA(220, 240, 255, alpha))
                nvgFill(nvg)
                if lod < 2 then
                    local trailGlow = nvgRadialGradient(nvg, bx, by, r * 0.5, r * 2.5,
                        nvgRGBA(60, 160, 255, math.floor(alpha * 0.4)),
                        nvgRGBA(60, 160, 255, 0))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, bx, by, r * 2.5)
                    nvgFillPaint(nvg, trailGlow)
                    nvgFill(nvg)
                end

            -- ==============================================================
            -- ⚡ spark — 电花: 从玩家到目标的多段闪电链
            -- ==============================================================
            elseif eff.type == "spark" then
                local time = bs.time or 0
                local tx = l.x + (eff.targetX or eff.x or 0)
                local ty = l.y + (eff.targetY or eff.y or 0)
                local hits = eff.hitCount or 4

                -- 每段闪电依次亮起 (按生命周期分段)
                local segDur = 1.0 / hits
                local curSeg = math.floor((1.0 - lifeRatio) / segDur) + 1
                if curSeg > hits then curSeg = hits end

                -- 从玩家到目标的锯齿闪电链
                for si = 1, math.min(curSeg, hits) do
                    local segAlpha = alpha
                    if si < curSeg then
                        -- 前几段逐渐变暗
                        segAlpha = math.floor(alpha * 0.3)
                    end
                    -- 每段闪电用不同随机偏移模拟锯齿
                    local segments = lod == 0 and 6 or (lod == 1 and 4 or 3)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, sx, sy)
                    for j = 1, segments - 1 do
                        local t = j / segments
                        local mx = sx + (tx - sx) * t
                        local my = sy + (ty - sy) * t
                        -- 锯齿偏移，每段每帧不同
                        local seed = si * 71.3 + j * 37.1 + time * 12
                        local offX = math.sin(seed) * 12
                        local offY = math.cos(seed * 1.7) * 10
                        nvgLineTo(nvg, mx + offX, my + offY)
                    end
                    nvgLineTo(nvg, tx, ty)
                    nvgStrokeColor(nvg, nvgRGBA(255, 240, 100, segAlpha))
                    nvgStrokeWidth(nvg, si == curSeg and 2.5 or 1.5)
                    nvgStroke(nvg)
                end

                -- 目标处电击光晕
                local glowR = 15 + 5 * math.sin(time * 25)
                local glowA = math.floor(alpha * 0.6)
                if lod < 2 then
                    local glow = nvgRadialGradient(nvg, tx, ty, glowR * 0.3, glowR,
                        nvgRGBA(255, 240, 100, glowA),
                        nvgRGBA(255, 240, 100, 0))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, tx, ty, glowR)
                    nvgFillPaint(nvg, glow)
                    nvgFill(nvg)
                end
                -- 目标处火花
                nvgBeginPath(nvg)
                nvgCircle(nvg, tx, ty, 4 * lifeRatio)
                nvgFillColor(nvg, nvgRGBA(255, 255, 200, alpha))
                nvgFill(nvg)

            -- ==============================================================
            -- ⚔️ arcane_strike — 奥术打击: 近战弧形闪光
            -- ==============================================================
            elseif eff.type == "arcane_strike" then
                local r = eff.radius or 80
                local progress = 1.0 - lifeRatio
                -- 弧形斩击
                nvgSave(nvg)
                nvgTranslate(nvg, sx, sy)
                nvgBeginPath(nvg)
                nvgArc(nvg, 0, 0, r * 0.8, -math.pi * 0.3 - progress * 1.5, -math.pi * 0.3 + 1.0 - progress * 0.5, 1)
                nvgStrokeColor(nvg, nvgRGBA(255, 200, 80, alpha))
                nvgStrokeWidth(nvg, 4 * lifeRatio)
                nvgStroke(nvg)
                nvgRestore(nvg)
                -- 中心冲击光晕
                local glowR = r * 0.4 * (1.0 + progress * 0.5)
                local glow = nvgRadialGradient(nvg, sx, sy, 0, glowR,
                    nvgRGBA(255, 220, 120, math.floor(alpha * 0.5)),
                    nvgRGBA(255, 160, 40, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, glowR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)

            -- ==============================================================
            -- 🔥 generic_aoe — 通用AoE: 元素色脉冲
            -- ==============================================================
            elseif eff.type == "generic_aoe" then
                local aw = eff.areaW or l.w
                local ah = eff.areaH or l.h
                local cx = l.x + aw * 0.5
                local cy = l.y + ah * 0.5
                local progress = 1.0 - lifeRatio
                local ec = ELEM_COLORS[eff.element] or { 255, 220, 120 }
                -- 全屏闪光
                local flashA = math.floor(80 * lifeRatio * (progress < 0.3 and (progress / 0.3) or 1.0))
                nvgBeginPath(nvg)
                nvgRect(nvg, l.x, l.y, aw, ah)
                nvgFillColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], flashA))
                nvgFill(nvg)
                -- 冲击环
                local shockR = math.max(aw, ah) * 0.4 * math.min(1.0, progress * 2.0)
                nvgBeginPath(nvg)
                nvgCircle(nvg, cx, cy, shockR)
                nvgStrokeColor(nvg, nvgRGBA(ec[1], ec[2], ec[3], math.floor(alpha * 0.7)))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)

            -- ==============================================================
            -- 🔥 fireball_cast — 火球飞行弹道: 从玩家飞向目标
            -- ==============================================================
            elseif eff.type == "fireball_cast" then
                local progress = 1.0 - lifeRatio  -- 0→1 飞行进度
                local tx = l.x + (eff.targetX or eff.x or 0)
                local ty = l.y + (eff.targetY or eff.y or 0)
                -- 弹丸当前位置 (线性插值)
                local bx = sx + (tx - sx) * progress
                local by = sy + (ty - sy) * progress
                local r = 8 + progress * 4  -- 飞行中逐渐膨胀

                -- 火球主体 (橙红实心)
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r)
                nvgFillColor(nvg, nvgRGBA(255, 140, 30, alpha))
                nvgFill(nvg)

                -- 火球内芯 (亮黄)
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r * 0.45)
                nvgFillColor(nvg, nvgRGBA(255, 240, 160, alpha))
                nvgFill(nvg)

                -- 外层火焰光晕
                local trailGlow = nvgRadialGradient(nvg, bx, by, r * 0.5, r * 2.5,
                    nvgRGBA(255, 80, 0, math.floor(alpha * 0.5)),
                    nvgRGBA(255, 40, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, bx, by, r * 2.5)
                nvgFillPaint(nvg, trailGlow)
                nvgFill(nvg)

                -- 尾焰拖尾 (lod < 2)
                if lod < 2 then
                    local dx, dy = tx - sx, ty - sy
                    local tailCount = lod == 0 and 4 or 2
                    for ti = 1, tailCount do
                        local tt = math.max(0, progress - ti * 0.06)
                        local tailX = sx + (tx - sx) * tt
                        local tailY = sy + (ty - sy) * tt
                        local tailR = r * (0.7 - ti * 0.12)
                        local tailA = math.floor(alpha * (0.5 - ti * 0.1))
                        if tailR > 0 and tailA > 0 then
                            nvgBeginPath(nvg)
                            nvgCircle(nvg, tailX, tailY, tailR)
                            nvgFillColor(nvg, nvgRGBA(255, 100, 0, tailA))
                            nvgFill(nvg)
                        end
                    end
                end

            -- ==============================================================
            -- 🔥 fireball — 火球术: AoE橙红爆炸扩散环
            -- ==============================================================
            elseif eff.type == "fireball" then
                local expand = 1.0 + (1.0 - lifeRatio) * 0.4
                local r = eff.radius * expand
                local glow = nvgRadialGradient(nvg, sx, sy, r * 0.2, r,
                    nvgRGBA(255, 140, 30, math.floor(alpha * 0.5)),
                    nvgRGBA(255, 60, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgStrokeColor(nvg, nvgRGBA(255, 100, 30, alpha))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)
                if lod == 0 then
                    for fi = 1, 5 do
                        local angle = fi * 1.257 + (1.0 - lifeRatio) * 3
                        local dr = r * 0.6
                        local fx2 = sx + math.cos(angle) * dr
                        local fy2 = sy + math.sin(angle) * dr
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, fx2, fy2, 2)
                        nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(alpha * 0.7)))
                        nvgFill(nvg)
                    end
                end

            -- ==============================================================
            -- 🔥 incinerate_channel — 焚烧引导: 从玩家到目标的火焰射线
            -- ==============================================================
            elseif eff.type == "incinerate_channel" then
                local time = bs.time or 0
                -- 从 ChannelSystem 实时读取玩家和目标坐标 (支持重定向)
                local ok_cs, CS = pcall(require, "battle.ChannelSystem")
                local csState = ok_cs and CS.GetState() or nil
                if csState and csState.skillId == "incinerate" then
                    local p = csState.bs and csState.bs.playerBattle
                    local target = csState.target
                    if p and target and not target.dead then
                        local bx = l.x + p.x
                        local by = l.y + p.y
                        local tx = l.x + target.x
                        local ty = l.y + target.y
                        local dx, dy = tx - bx, ty - by
                        local dist = math.sqrt(dx * dx + dy * dy)
                        local angle = math.atan(dy, dx)

                        -- 引导进度 (用于射线宽度递增)
                        local channelProg = 1.0 - lifeRatio -- 0→1
                        local beamW = 4 + channelProg * 6 -- 4→10 逐渐变粗
                        local pulse = 1.0 + math.sin(time * 10) * 0.15
                        beamW = beamW * pulse

                        -- 射线主体: 渐变矩形 (从玩家到目标)
                        nvgSave(nvg)
                        nvgTranslate(nvg, bx, by)
                        nvgRotate(nvg, angle)
                        local grad = nvgLinearGradient(nvg, 0, 0, dist, 0,
                            nvgRGBA(255, 200, 60, math.floor(alpha * 0.9)),
                            nvgRGBA(255, 80, 0, math.floor(alpha * 0.7)))
                        nvgBeginPath(nvg)
                        nvgRect(nvg, 0, -beamW / 2, dist, beamW)
                        nvgFillPaint(nvg, grad)
                        nvgFill(nvg)

                        -- 射线内芯 (更亮更窄)
                        local coreW = beamW * 0.35
                        local coreGrad = nvgLinearGradient(nvg, 0, 0, dist, 0,
                            nvgRGBA(255, 255, 200, math.floor(alpha * 0.8)),
                            nvgRGBA(255, 220, 100, math.floor(alpha * 0.5)))
                        nvgBeginPath(nvg)
                        nvgRect(nvg, 0, -coreW / 2, dist, coreW)
                        nvgFillPaint(nvg, coreGrad)
                        nvgFill(nvg)
                        nvgRestore(nvg)

                        -- 射线外层光晕 (lod < 2)
                        if lod < 2 then
                            nvgSave(nvg)
                            nvgTranslate(nvg, bx, by)
                            nvgRotate(nvg, angle)
                            local glowW = beamW * 2.5
                            local glowGrad = nvgLinearGradient(nvg, 0, 0, dist, 0,
                                nvgRGBA(255, 120, 0, math.floor(alpha * 0.2)),
                                nvgRGBA(255, 60, 0, 0))
                            nvgBeginPath(nvg)
                            nvgRect(nvg, 0, -glowW / 2, dist, glowW)
                            nvgFillPaint(nvg, glowGrad)
                            nvgFill(nvg)
                            nvgRestore(nvg)
                        end

                        -- 沿射线的火花粒子 (lod == 0)
                        if lod == 0 then
                            for fi = 1, 6 do
                                local seed = time * 7 + fi * 53.7
                                local t = math.fmod(seed * 0.3, 1.0)
                                local px = bx + dx * t + math.sin(seed * 4) * beamW * 1.2
                                local py = by + dy * t + math.cos(seed * 3) * beamW * 1.2
                                local pSize = 1.5 + math.sin(seed * 2) * 1.0
                                nvgBeginPath(nvg)
                                nvgCircle(nvg, px, py, pSize)
                                nvgFillColor(nvg, nvgRGBA(255, 200, 60, math.floor(alpha * 0.6)))
                                nvgFill(nvg)
                            end
                        end

                        -- 起点光源 (玩家手部)
                        local srcGlow = nvgRadialGradient(nvg, bx, by, 2, 12,
                            nvgRGBA(255, 240, 150, math.floor(alpha * 0.7)),
                            nvgRGBA(255, 120, 0, 0))
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, bx, by, 12)
                        nvgFillPaint(nvg, srcGlow)
                        nvgFill(nvg)

                        -- 目标命中光点 (持续脉动)
                        local hitR = 8 + 4 * math.sin(time * 12)
                        local hitGlow = nvgRadialGradient(nvg, tx, ty, hitR * 0.2, hitR,
                            nvgRGBA(255, 160, 30, math.floor(alpha * 0.8)),
                            nvgRGBA(255, 60, 0, 0))
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, tx, ty, hitR)
                        nvgFillPaint(nvg, hitGlow)
                        nvgFill(nvg)
                    end
                end

            -- ==============================================================
            -- 🔥 incinerate_tick — 焚烧每跳: 射线闪亮 + 目标爆裂
            -- ==============================================================
            elseif eff.type == "incinerate_tick" then
                local progress = 1.0 - lifeRatio
                local tick = eff.tick or 1
                local totalTicks = eff.totalTicks or 4
                -- 命中强度随 tick 递增 (ramp 视觉)
                local intensity = 0.6 + 0.4 * (tick / totalTicks)

                -- 射线闪白 (从玩家到目标的一道白光, 快速消散)
                local tx = l.x + (eff.targetX or eff.x or 0)
                local ty = l.y + (eff.targetY or eff.y or 0)
                local flashW = 3 * lifeRatio * intensity
                local dx2, dy2 = tx - sx, ty - sy
                local dist2 = math.sqrt(dx2 * dx2 + dy2 * dy2)
                local angle2 = math.atan(dy2, dx2)
                if dist2 > 1 then
                    nvgSave(nvg)
                    nvgTranslate(nvg, sx, sy)
                    nvgRotate(nvg, angle2)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, 0, -flashW / 2, dist2, flashW)
                    nvgFillColor(nvg, nvgRGBA(255, 255, 220, math.floor(alpha * 0.7 * intensity)))
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end

                -- 目标位置爆裂光晕
                local burstR = (15 + 12 * intensity) * (1.0 + progress * 0.4)
                local glow = nvgRadialGradient(nvg, tx, ty, burstR * 0.1, burstR,
                    nvgRGBA(255, 120, 0, math.floor(alpha * 0.8 * intensity)),
                    nvgRGBA(255, 60, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, tx, ty, burstR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 中心亮点
                nvgBeginPath(nvg)
                nvgCircle(nvg, tx, ty, 4 * lifeRatio * intensity)
                nvgFillColor(nvg, nvgRGBA(255, 250, 200, alpha))
                nvgFill(nvg)
                -- 冲击环
                nvgBeginPath(nvg)
                nvgCircle(nvg, tx, ty, burstR * 0.8)
                nvgStrokeColor(nvg, nvgRGBA(255, 180, 40, math.floor(alpha * 0.5 * intensity)))
                nvgStrokeWidth(nvg, 2 * lifeRatio * intensity)
                nvgStroke(nvg)

            -- ==============================================================
            -- ❄️ ice_shards — 冰碎片: 施放瞬间冰蓝闪光 (弹道由 DrawFrostShards 渲染)
            -- ==============================================================
            elseif eff.type == "ice_shards" then
                -- 施放闪光: 玩家周围短暂冰蓝光环
                local flashR = 25
                local flashGlow = nvgRadialGradient(nvg, sx, sy, flashR * 0.3, flashR * 1.5,
                    nvgRGBA(140, 220, 255, math.floor(120 * lifeRatio)),
                    nvgRGBA(100, 200, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, flashR * 1.5)
                nvgFillPaint(nvg, flashGlow)
                nvgFill(nvg)

            -- ==============================================================
            -- ⚡ charged_bolts — 电荷弹: 从玩家散射到各目标的电弧
            -- ==============================================================
            elseif eff.type == "charged_bolts" then
                local time = bs.time or 0
                local progress = 1.0 - lifeRatio  -- 0→1 飞行进度
                local boltCount = eff.boltCount or 5
                local targets = eff.boltTargets

                -- 起点光源 (玩家手部电弧汇聚)
                local srcGlow = nvgRadialGradient(nvg, sx, sy, 2, 14,
                    nvgRGBA(255, 255, 200, math.floor(alpha * 0.7)),
                    nvgRGBA(255, 240, 80, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, 14)
                nvgFillPaint(nvg, srcGlow)
                nvgFill(nvg)

                -- 每枚弹体: 从玩家飞向目标的锯齿电弧
                for bi = 1, boltCount do
                    local tgt = targets and targets[bi]
                    if tgt then
                        local tx = l.x + tgt.x
                        local ty = l.y + tgt.y
                        -- 每枚弹体有时间偏移 (散射感)
                        local boltDelay = (bi - 1) * 0.04
                        local boltProg = math.max(0, math.min(1.0, (progress - boltDelay) / 0.8))

                        if boltProg > 0 then
                            -- 弹丸当前位置
                            local bx = sx + (tx - sx) * boltProg
                            local by = sy + (ty - sy) * boltProg

                            -- 锯齿电弧路径 (从玩家到弹丸当前位置)
                            local segCount = lod == 0 and 5 or 3
                            local dx, dy = bx - sx, by - sy
                            local arcDist = math.sqrt(dx * dx + dy * dy)
                            nvgBeginPath(nvg)
                            nvgMoveTo(nvg, sx, sy)
                            for si = 1, segCount - 1 do
                                local t = si / segCount
                                local mx = sx + dx * t
                                local my = sy + dy * t
                                local seed = bi * 31.7 + si * 17.3 + time * 15
                                local jitter = 6 + arcDist * 0.02
                                mx = mx + math.sin(seed) * jitter
                                my = my + math.cos(seed * 1.4) * jitter
                                nvgLineTo(nvg, mx, my)
                            end
                            nvgLineTo(nvg, bx, by)
                            local boltAlpha = math.floor(alpha * (0.7 + 0.3 * math.sin(time * 20 + bi * 2)))
                            nvgStrokeColor(nvg, nvgRGBA(255, 240, 100, boltAlpha))
                            nvgStrokeWidth(nvg, 2 * lifeRatio)
                            nvgStroke(nvg)

                            -- 弹丸头部光点
                            local headR = 4 + math.sin(time * 18 + bi) * 1.5
                            nvgBeginPath(nvg)
                            nvgCircle(nvg, bx, by, headR)
                            nvgFillColor(nvg, nvgRGBA(255, 255, 200, boltAlpha))
                            nvgFill(nvg)

                            -- 命中闪光 (弹丸到达目标时)
                            if boltProg > 0.9 then
                                local hitA = math.floor(alpha * (boltProg - 0.9) / 0.1)
                                local hitGlow = nvgRadialGradient(nvg, tx, ty, 2, 12,
                                    nvgRGBA(255, 255, 180, hitA),
                                    nvgRGBA(255, 240, 80, 0))
                                nvgBeginPath(nvg)
                                nvgCircle(nvg, tx, ty, 12)
                                nvgFillPaint(nvg, hitGlow)
                                nvgFill(nvg)
                            end
                        end
                    end
                end

            -- ==============================================================
            -- ⚡ chain_lightning — 连锁闪电: 沿弹跳路径的顺序闪电链
            -- ==============================================================
            elseif eff.type == "chain_lightning" then
                local time = bs.time or 0
                local path = eff.chainPath
                local totalBounces = eff.bounces or 6

                if path and #path >= 2 then
                    local progress = 1.0 - lifeRatio  -- 0→1 链传播进度
                    -- 当前已传播到第几段 (含小数)
                    local totalSegs = #path - 1
                    local activeSegs = progress * totalSegs

                    for si = 1, totalSegs do
                        -- 每段的可见度 (顺序点亮, 依次消散)
                        local segStart = (si - 1)
                        local segVis = math.max(0, math.min(1.0, activeSegs - segStart))
                        if segVis <= 0 then break end

                        -- 前方段逐渐消散
                        local fadeOut = 1.0
                        if activeSegs > si + 2 then
                            fadeOut = math.max(0, 1.0 - (activeSegs - si - 2) * 0.3)
                        end
                        if fadeOut <= 0 then goto continue_chain end

                        local p1 = path[si]
                        local p2 = path[si + 1]
                        local x1 = l.x + p1.x
                        local y1 = l.y + p1.y
                        local x2 = l.x + p2.x
                        local y2 = l.y + p2.y
                        -- 部分可见: 截取到当前传播位置
                        if segVis < 1.0 then
                            x2 = x1 + (x2 - x1) * segVis
                            y2 = y1 + (y2 - y1) * segVis
                        end

                        local segAlpha = math.floor(alpha * fadeOut)

                        -- 锯齿闪电弧线
                        local segCount = lod == 0 and 4 or 2
                        local dx, dy = x2 - x1, y2 - y1
                        nvgBeginPath(nvg)
                        nvgMoveTo(nvg, x1, y1)
                        for ji = 1, segCount - 1 do
                            local t = ji / segCount
                            local mx = x1 + dx * t
                            local my = y1 + dy * t
                            local seed = si * 53.1 + ji * 17.9 + time * 12
                            mx = mx + math.sin(seed) * 10
                            my = my + math.cos(seed * 1.6) * 8
                            nvgLineTo(nvg, mx, my)
                        end
                        nvgLineTo(nvg, x2, y2)
                        -- 主线
                        nvgStrokeColor(nvg, nvgRGBA(255, 255, 180, segAlpha))
                        nvgStrokeWidth(nvg, 2.5 * lifeRatio)
                        nvgStroke(nvg)

                        -- 外层光晕线 (lod < 2)
                        if lod < 2 then
                            nvgBeginPath(nvg)
                            nvgMoveTo(nvg, x1, y1)
                            nvgLineTo(nvg, x2, y2)
                            nvgStrokeColor(nvg, nvgRGBA(255, 240, 80, math.floor(segAlpha * 0.25)))
                            nvgStrokeWidth(nvg, 6 * lifeRatio)
                            nvgStroke(nvg)
                        end

                        -- 弹跳节点光点 (目标位置)
                        if segVis >= 1.0 then
                            local nodeR = 5 + math.sin(time * 15 + si * 2) * 2
                            local nodeGlow = nvgRadialGradient(nvg, x2, y2, nodeR * 0.2, nodeR,
                                nvgRGBA(255, 255, 200, segAlpha),
                                nvgRGBA(255, 240, 80, 0))
                            nvgBeginPath(nvg)
                            nvgCircle(nvg, x2, y2, nodeR)
                            nvgFillPaint(nvg, nodeGlow)
                            nvgFill(nvg)
                        end

                        ::continue_chain::
                    end

                    -- 起点光源
                    local srcGlow = nvgRadialGradient(nvg, sx, sy, 2, 10,
                        nvgRGBA(255, 255, 200, math.floor(alpha * 0.6)),
                        nvgRGBA(255, 240, 80, 0))
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, 10)
                    nvgFillPaint(nvg, srcGlow)
                    nvgFill(nvg)
                end

            -- ==============================================================
            -- 🔥 fireball_secondary — 火球二次爆炸: 较小的橙红脉冲
            -- ==============================================================
            elseif eff.type == "fireball_secondary" then
                local r = eff.radius or 60
                local progress = 1.0 - lifeRatio
                local expandR = r * math.min(1.0, progress * 2.5)
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.1, expandR,
                    nvgRGBA(255, 180, 60, math.floor(alpha * 0.6)),
                    nvgRGBA(255, 100, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(255, 200, 80, math.floor(alpha * 0.8)))
                nvgStrokeWidth(nvg, 2 * lifeRatio)
                nvgStroke(nvg)

            -- ==============================================================
            -- 🔥 incinerate_explosion — 焚烧结束爆炸: 全屏橙红闪光
            -- ==============================================================
            elseif eff.type == "incinerate_explosion" then
                local aw = eff.areaW or l.w
                local ah = eff.areaH or l.h
                local cx = l.x + aw * 0.5
                local cy = l.y + ah * 0.5
                local progress = 1.0 - lifeRatio
                local flashA = math.floor(100 * lifeRatio * (progress < 0.2 and (progress / 0.2) or 1.0))
                nvgBeginPath(nvg)
                nvgRect(nvg, l.x, l.y, aw, ah)
                nvgFillColor(nvg, nvgRGBA(255, 100, 0, flashA))
                nvgFill(nvg)
                local shockR = math.max(aw, ah) * 0.35 * math.min(1.0, progress * 2.5)
                nvgBeginPath(nvg)
                nvgCircle(nvg, cx, cy, shockR)
                nvgStrokeColor(nvg, nvgRGBA(255, 180, 40, math.floor(alpha * 0.7)))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)

            -- ==============================================================
            -- ⚡ charged_bolts_overload — 电荷过载: 黄色电弧爆发
            -- ==============================================================
            elseif eff.type == "charged_bolts_overload" then
                local r = eff.radius or 80
                local progress = 1.0 - lifeRatio
                local expandR = r * math.min(1.0, progress * 2.0)
                -- 中心电弧爆发
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.1, expandR,
                    nvgRGBA(255, 255, 120, math.floor(alpha * 0.5)),
                    nvgRGBA(255, 220, 60, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 外环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(255, 255, 180, alpha))
                nvgStrokeWidth(nvg, 2.5 * lifeRatio)
                nvgStroke(nvg)
                -- 辐射电弧
                if lod < 2 then
                    local arcCount = lod == 0 and 6 or 3
                    for ai = 1, arcCount do
                        local angle = ai * (math.pi * 2 / arcCount) + progress * 4
                        local ax2 = sx + math.cos(angle) * expandR * 0.9
                        local ay2 = sy + math.sin(angle) * expandR * 0.9
                        nvgBeginPath(nvg)
                        nvgMoveTo(nvg, sx, sy)
                        local midX2 = (sx + ax2) * 0.5 + math.sin(angle * 3) * 8
                        local midY2 = (sy + ay2) * 0.5 + math.cos(angle * 5) * 8
                        nvgLineTo(nvg, midX2, midY2)
                        nvgLineTo(nvg, ax2, ay2)
                        nvgStrokeColor(nvg, nvgRGBA(255, 255, 200, math.floor(alpha * 0.7)))
                        nvgStrokeWidth(nvg, 2 * lifeRatio)
                        nvgStroke(nvg)
                    end
                end

            -- ==============================================================
            -- ⚡ chain_lightning_thunder — 末尾雷暴AOE: 紫黄色冲击
            -- ==============================================================
            elseif eff.type == "chain_lightning_thunder" then
                local r = eff.radius or 90
                local progress = 1.0 - lifeRatio
                local expandR = r * math.min(1.0, progress * 2.0)
                -- 紫黄色冲击光晕
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.15, expandR,
                    nvgRGBA(220, 200, 255, math.floor(alpha * 0.5)),
                    nvgRGBA(255, 240, 100, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 双层冲击环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(255, 240, 120, alpha))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)
                if lod < 2 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, expandR * 0.5)
                    nvgStrokeColor(nvg, nvgRGBA(200, 180, 255, math.floor(alpha * 0.6)))
                    nvgStrokeWidth(nvg, 2 * lifeRatio)
                    nvgStroke(nvg)
                end
                -- 闪电劈落
                if lod == 0 then
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, sx, sy - expandR)
                    nvgLineTo(nvg, sx + 6, sy - expandR * 0.5)
                    nvgLineTo(nvg, sx - 4, sy - expandR * 0.3)
                    nvgLineTo(nvg, sx, sy)
                    nvgStrokeColor(nvg, nvgRGBA(255, 255, 200, alpha))
                    nvgStrokeWidth(nvg, 2.5 * lifeRatio)
                    nvgStroke(nvg)
                end

            -- ==============================================================
            -- 🔥 flame_shield — 火焰护盾: 橙红光罩
            -- ==============================================================
            elseif eff.type == "flame_shield" then
                local r = eff.radius or 60
                local pulse = 1.0 + math.sin((bs.time or 0) * 8) * 0.1
                local pr = r * pulse
                -- 光罩
                local glow = nvgRadialGradient(nvg, sx, sy, pr * 0.3, pr,
                    nvgRGBA(255, 120, 30, math.floor(alpha * 0.3)),
                    nvgRGBA(255, 80, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 外环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                nvgStrokeColor(nvg, nvgRGBA(255, 160, 40, alpha))
                nvgStrokeWidth(nvg, 2)
                nvgStroke(nvg)

            -- ==============================================================
            -- ❄️ ice_armor — 寒冰甲: 冰蓝光罩
            -- ==============================================================
            elseif eff.type == "ice_armor" then
                local r = eff.radius or 60
                local pulse = 1.0 + math.sin((bs.time or 0) * 8) * 0.1
                local pr = r * pulse
                local glow = nvgRadialGradient(nvg, sx, sy, pr * 0.3, pr,
                    nvgRGBA(80, 180, 255, math.floor(alpha * 0.3)),
                    nvgRGBA(60, 140, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                nvgStrokeColor(nvg, nvgRGBA(140, 220, 255, alpha))
                nvgStrokeWidth(nvg, 2)
                nvgStroke(nvg)

            -- ==============================================================
            -- ❄️ frost_nova — 冰霜新星: 扩散冰环
            -- ==============================================================
            elseif eff.type == "frost_nova" then
                local r = eff.radius or 120
                local progress = 1.0 - lifeRatio
                local expandR = r * math.min(1.0, progress * 1.8)
                -- 冰霜扩散光晕
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.3, expandR,
                    nvgRGBA(100, 200, 255, math.floor(alpha * 0.4)),
                    nvgRGBA(100, 200, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 外环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(140, 220, 255, alpha))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)
                -- 冰晶 (lod < 2)
                if lod < 2 then
                    local shardCount = lod == 0 and 6 or 3
                    for si = 1, shardCount do
                        local angle = si * (math.pi * 2 / shardCount) + progress * 3
                        local shx = sx + math.cos(angle) * expandR * 0.8
                        local shy = sy + math.sin(angle) * expandR * 0.8
                        nvgSave(nvg)
                        nvgTranslate(nvg, shx, shy)
                        nvgRotate(nvg, angle)
                        nvgBeginPath(nvg)
                        nvgMoveTo(nvg, 0, -4)
                        nvgLineTo(nvg, 3, 0)
                        nvgLineTo(nvg, 0, 4)
                        nvgLineTo(nvg, -3, 0)
                        nvgClosePath(nvg)
                        nvgFillColor(nvg, nvgRGBA(180, 230, 255, math.floor(alpha * 0.7)))
                        nvgFill(nvg)
                        nvgRestore(nvg)
                    end
                end

            -- ==============================================================
            -- ⚡ teleport — 传送: 闪电闪光
            -- ==============================================================
            elseif eff.type == "teleport" then
                local r = eff.radius or 80
                local progress = 1.0 - lifeRatio
                -- 闪光爆发
                local flashR = r * math.min(1.0, progress * 3.0)
                local glow = nvgRadialGradient(nvg, sx, sy, 0, flashR,
                    nvgRGBA(200, 180, 255, math.floor(alpha * 0.7)),
                    nvgRGBA(120, 100, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, flashR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 电弧辐射 (lod < 2)
                if lod < 2 then
                    local arcCount = lod == 0 and 6 or 3
                    for ai = 1, arcCount do
                        local angle = ai * (math.pi * 2 / arcCount) + (bs.time or 0) * 8
                        local ax2 = sx + math.cos(angle) * flashR * 0.8
                        local ay2 = sy + math.sin(angle) * flashR * 0.8
                        nvgBeginPath(nvg)
                        nvgMoveTo(nvg, sx, sy)
                        nvgLineTo(nvg, ax2, ay2)
                        nvgStrokeColor(nvg, nvgRGBA(220, 200, 255, math.floor(alpha * 0.5)))
                        nvgStrokeWidth(nvg, 1.5 * lifeRatio)
                        nvgStroke(nvg)
                    end
                end

            -- ==============================================================
            -- 🔥 hydra_summon — 九头蛇召唤: 火焰爆发光环
            -- ==============================================================
            elseif eff.type == "hydra_summon" then
                local progress = 1.0 - lifeRatio
                local expandR = 30 * math.min(1.0, progress * 3.0)
                -- 扩散火焰环
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.3, expandR,
                    nvgRGBA(255, 140, 30, alpha), nvgRGBA(255, 80, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 召唤环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(255, 180, 60, alpha))
                nvgStrokeWidth(nvg, 2 * lifeRatio)
                nvgStroke(nvg)

            -- ==============================================================
            -- ❄️ blizzard — 暴风雪: 冰蓝区域 + 下落粒子
            -- ==============================================================
            elseif eff.type == "blizzard" then
                local r = eff.radius or 100
                local progress = 1.0 - lifeRatio
                -- 区域光晕
                local glow = nvgRadialGradient(nvg, sx, sy, r * 0.2, r,
                    nvgRGBA(80, 180, 255, math.floor(alpha * 0.3)),
                    nvgRGBA(80, 180, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, r)
                nvgStrokeColor(nvg, nvgRGBA(120, 200, 255, math.floor(alpha * 0.5)))
                nvgStrokeWidth(nvg, 2 * lifeRatio)
                nvgStroke(nvg)
                -- 冰晶下落粒子 (LOD: 8→4→0)
                local iceCount = lod == 0 and 8 or (lod == 1 and 4 or 0)
                for ci = 1, iceCount do
                    local seed = ci * 97.3 + (bs.time or 0) * 3
                    local px = sx + (math.sin(seed) * 0.5 - 0.25) * r * 2
                    local py = sy + ((seed * 40 + (bs.time or 0) * 150) % (r * 2)) - r
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, px, py, 2 + math.sin(seed * 2))
                    nvgFillColor(nvg, nvgRGBA(180, 230, 255, math.floor(alpha * 0.7)))
                    nvgFill(nvg)
                end

            -- ==============================================================
            -- ⚡ lightning_spear — 闪电矛: 电弧爆发光环
            -- ==============================================================
            elseif eff.type == "lightning_spear" then
                local progress = 1.0 - lifeRatio
                local expandR = 25 * math.min(1.0, progress * 3.0)
                -- 扩散电弧环
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.2, expandR,
                    nvgRGBA(255, 240, 100, alpha), nvgRGBA(255, 230, 60, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 电弧闪光
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(255, 255, 180, alpha))
                nvgStrokeWidth(nvg, 2 * lifeRatio)
                nvgStroke(nvg)

            -- ==============================================================
            -- 🔥 firewall — 火墙: 圆形火焰区域
            -- ==============================================================
            elseif eff.type == "firewall" then
                local r = eff.radius or 70
                local pulse = 1.0 + math.sin((bs.time or 0) * 6) * 0.08
                local pr = r * pulse
                -- 火焰区域光晕
                local glow = nvgRadialGradient(nvg, sx, sy, pr * 0.2, pr,
                    nvgRGBA(255, 100, 20, math.floor(alpha * 0.4)),
                    nvgRGBA(255, 60, 0, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 外环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                nvgStrokeColor(nvg, nvgRGBA(255, 140, 30, math.floor(alpha * 0.7)))
                nvgStrokeWidth(nvg, 2)
                nvgStroke(nvg)
                -- 火焰条纹 (lod=0)
                if lod == 0 then
                    for fi = 1, 4 do
                        local angle = fi * 1.571 + (bs.time or 0) * 2
                        local fx = sx + math.cos(angle) * pr * 0.6
                        local fy = sy + math.sin(angle) * pr * 0.6
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, fx, fy, 3)
                        nvgFillColor(nvg, nvgRGBA(255, 200, 60, math.floor(alpha * 0.6)))
                        nvgFill(nvg)
                    end
                end

            -- ==============================================================
            -- 🔥 fire_storm — 烈焰风暴: 全屏火焰旋风
            -- ==============================================================
            elseif eff.type == "fire_storm" then
                local aw = eff.areaW or l.w
                local ah = eff.areaH or l.h
                local cx = l.x + aw * 0.5
                local cy = l.y + ah * 0.5
                local spin = (bs.time or 0) * 4
                local bgGlow = nvgRadialGradient(nvg, cx, cy, 0, math.max(aw, ah) * 0.6,
                    nvgRGBA(255, 80, 0, math.floor(60 * lifeRatio)),
                    nvgRGBA(255, 40, 0, 0))
                nvgBeginPath(nvg)
                nvgRect(nvg, l.x, l.y, aw, ah)
                nvgFillPaint(nvg, bgGlow)
                nvgFill(nvg)
                local flameCount = lod == 0 and 6 or (lod == 1 and 3 or 0)
                for fi = 1, flameCount do
                    local angle = spin + fi * 1.047
                    local r1 = 30 + (1.0 - lifeRatio) * 60
                    local r2 = r1 + 40
                    local x1 = cx + math.cos(angle) * r1
                    local y1 = cy + math.sin(angle) * r1
                    local x2 = cx + math.cos(angle + 0.3) * r2
                    local y2 = cy + math.sin(angle + 0.3) * r2
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, x1, y1)
                    nvgLineTo(nvg, x2, y2)
                    nvgStrokeColor(nvg, nvgRGBA(255, 140, 30, math.floor(alpha * 0.7)))
                    nvgStrokeWidth(nvg, 3 * lifeRatio)
                    nvgStroke(nvg)
                end

            -- ==============================================================
            -- ❄️ frozen_orb — 冰封球: 冰蓝爆炸 + 冰晶扩散
            -- ==============================================================
            elseif eff.type == "frozen_orb" then
                local r = eff.radius or 100
                local progress = 1.0 - lifeRatio
                local expandR = r * math.min(1.0, progress * 1.5)
                -- 冰蓝爆炸
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.2, expandR,
                    nvgRGBA(80, 180, 255, math.floor(alpha * 0.5)),
                    nvgRGBA(100, 200, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(140, 220, 255, alpha))
                nvgStrokeWidth(nvg, 2.5 * lifeRatio)
                nvgStroke(nvg)
                -- 旋转冰晶 (lod < 2)
                if lod < 2 then
                    local orbCount = lod == 0 and 6 or 3
                    for oi = 1, orbCount do
                        local angle = oi * (math.pi * 2 / orbCount) + (bs.time or 0) * 4
                        local ox2 = sx + math.cos(angle) * expandR * 0.6
                        local oy2 = sy + math.sin(angle) * expandR * 0.6
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, ox2, oy2, 3)
                        nvgFillColor(nvg, nvgRGBA(200, 240, 255, alpha))
                        nvgFill(nvg)
                    end
                end

            -- ==============================================================
            -- ⚡ thunderstorm — 雷暴召唤: 中心劈一道大闪电 (图片)
            -- ==============================================================
            elseif eff.type == "thunderstorm" then
                -- 延迟加载闪电柱图片
                if not eff._boltImg then
                    eff._boltImg = nvgCreateImage(nvg, "image/lightning_bolt_1_20260410155330.png", 0)
                    if not eff._boltImg or eff._boltImg <= 0 then eff._boltImg = 0 end
                end
                if not eff._impactImg then
                    eff._impactImg = nvgCreateImage(nvg, "image/lightning_ground_impact_20260410155131.png", 0)
                    if not eff._impactImg or eff._impactImg <= 0 then eff._impactImg = 0 end
                end
                -- 中心一道大闪电柱
                if eff._boltImg > 0 then
                    local boltW = 48
                    local boltHt = 160
                    local imgPaint = nvgImagePattern(nvg,
                        sx - boltW / 2, sy - boltHt,
                        boltW, boltHt, 0, eff._boltImg, alpha)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - boltW / 2, sy - boltHt, boltW, boltHt)
                    nvgFillPaint(nvg, imgPaint)
                    nvgFill(nvg)
                end
                -- 地面冲击标记
                if eff._impactImg > 0 then
                    local impSz = 40
                    local ip = nvgImagePattern(nvg,
                        sx - impSz / 2, sy - impSz / 2,
                        impSz, impSz, 0, eff._impactImg, alpha)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, sx - impSz / 2, sy - impSz / 2, impSz, impSz)
                    nvgFillPaint(nvg, ip)
                    nvgFill(nvg)
                end

            -- ==============================================================
            -- ⚡ energy_pulse — 能量脉冲: 扩散黄色冲击环
            -- ==============================================================
            elseif eff.type == "energy_pulse" then
                local r = eff.radius or 130
                local progress = 1.0 - lifeRatio
                local expandR = r * math.min(1.0, progress * 1.8)
                -- 脉冲光晕
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.2, expandR,
                    nvgRGBA(255, 230, 100, math.floor(alpha * 0.4)),
                    nvgRGBA(255, 200, 60, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)
                -- 双层环
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(255, 240, 120, alpha))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)
                if lod < 2 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, expandR * 0.6)
                    nvgStrokeColor(nvg, nvgRGBA(255, 255, 200, math.floor(alpha * 0.5)))
                    nvgStrokeWidth(nvg, 2 * lifeRatio)
                    nvgStroke(nvg)
                end

            -- ==============================================================
            -- 🔥 meteor — 陨石坠落: 图片下落 + 爆炸冲击波
            -- ==============================================================
            elseif eff.type == "meteor" then
                local aw = eff.areaW or l.w
                local ah = eff.areaH or l.h
                local cx = l.x + aw * 0.5
                local cy = l.y + ah * 0.5
                local progress = 1.0 - lifeRatio
                local impactT = 0.4 -- 前40%为下落阶段, 后60%为爆炸阶段

                if progress < impactT then
                    -- === 下落阶段: 陨石从上方落下 ===
                    local fallRatio = progress / impactT
                    local meteorSize = 60 + fallRatio * 20
                    -- 从画面上方偏右落向中心
                    local startX = cx + aw * 0.15
                    local startY = l.y - 40
                    local mx = startX + (cx - startX) * fallRatio
                    local my = startY + (cy - startY) * fallRatio
                    -- 旋转
                    local rot = fallRatio * 3.0
                    -- 延迟加载陨石图片
                    if not eff._meteorImg then
                        eff._meteorImg = nvgCreateImage(nvg, "image/meteor_rock_20260410152202.png", 0)
                        if not eff._meteorImg or eff._meteorImg <= 0 then eff._meteorImg = 0 end
                    end
                    if eff._meteorImg > 0 then
                        nvgSave(nvg)
                        nvgTranslate(nvg, mx, my)
                        nvgRotate(nvg, rot)
                        local pat = nvgImagePattern(nvg, -meteorSize/2, -meteorSize/2, meteorSize, meteorSize, 0, eff._meteorImg, 1.0)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, -meteorSize/2, -meteorSize/2, meteorSize, meteorSize)
                        nvgFillPaint(nvg, pat)
                        nvgFill(nvg)
                        nvgRestore(nvg)
                    end
                    -- 拖尾火焰
                    if lod < 2 then
                        local tailLen = 40 * fallRatio
                        local dx = (cx - startX)
                        local dy = (cy - startY)
                        local d = math.sqrt(dx * dx + dy * dy)
                        if d > 0 then
                            local nx, ny = -dx / d, -dy / d
                            local grad = nvgLinearGradient(nvg, mx, my,
                                mx + nx * tailLen, my + ny * tailLen,
                                nvgRGBA(255, 160, 40, math.floor(200 * fallRatio)),
                                nvgRGBA(255, 80, 0, 0))
                            nvgBeginPath(nvg)
                            nvgMoveTo(nvg, mx - 8, my)
                            nvgLineTo(nvg, mx + nx * tailLen, my + ny * tailLen)
                            nvgLineTo(nvg, mx + 8, my)
                            nvgClosePath(nvg)
                            nvgFillPaint(nvg, grad)
                            nvgFill(nvg)
                        end
                    end
                else
                    -- === 爆炸阶段: 冲击波扩散 ===
                    local explodeRatio = (progress - impactT) / (1.0 - impactT)
                    local shockR = math.max(aw, ah) * 0.5 * explodeRatio
                    local explodeAlpha = math.floor(200 * (1.0 - explodeRatio))
                    -- 全屏闪光 (快速衰减)
                    if explodeRatio < 0.3 then
                        local flashA = math.floor(100 * (1.0 - explodeRatio / 0.3))
                        nvgBeginPath(nvg)
                        nvgRect(nvg, l.x, l.y, aw, ah)
                        nvgFillColor(nvg, nvgRGBA(255, 100, 20, flashA))
                        nvgFill(nvg)
                    end
                    -- 冲击波环
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, cx, cy, shockR)
                    nvgStrokeColor(nvg, nvgRGBA(255, 200, 60, explodeAlpha))
                    nvgStrokeWidth(nvg, 4 * (1.0 - explodeRatio))
                    nvgStroke(nvg)
                    -- 核心火焰
                    if lod < 2 then
                        local coreR = shockR * 0.3 * (1.0 - explodeRatio)
                        local coreGlow = nvgRadialGradient(nvg, cx, cy, 0, coreR,
                            nvgRGBA(255, 240, 150, explodeAlpha),
                            nvgRGBA(255, 100, 0, 0))
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, cx, cy, coreR)
                        nvgFillPaint(nvg, coreGlow)
                        nvgFill(nvg)
                    end
                end

            -- ==============================================================
            -- ❄️ deep_freeze — 深度冻结: 玩家身上冰壳护盾
            -- ==============================================================
            elseif eff.type == "deep_freeze" then
                -- 在玩家位置绘制冰壳 (使用 bs.playerBattle 获取位置)
                local p = bs.playerBattle
                local px = p and (l.x + p.x) or (l.x + (eff.areaW or l.w) * 0.5)
                local py = p and (l.y + p.y) or (l.y + (eff.areaH or l.h) * 0.5)
                local progress = 1.0 - lifeRatio
                local shieldSize = 70
                local pulse = 0.95 + math.sin((bs.time or 0) * 3) * 0.05

                -- 延迟加载冰盾图片
                if not eff._freezeImg then
                    eff._freezeImg = nvgCreateImage(nvg, "image/deep_freeze_shield_20260410152400.png", 0)
                    if not eff._freezeImg or eff._freezeImg <= 0 then eff._freezeImg = 0 end
                end
                -- 冰壳图片 (覆盖在玩家身上)
                if eff._freezeImg and eff._freezeImg > 0 then
                    local sz = shieldSize * pulse
                    local imgAlpha = math.min(1.0, progress * 4.0) * lifeRatio
                    local pat = nvgImagePattern(nvg, px - sz/2, py - sz/2, sz, sz, 0, eff._freezeImg, imgAlpha)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, px - sz/2, py - sz/2, sz, sz)
                    nvgFillPaint(nvg, pat)
                    nvgFill(nvg)
                end
                -- 冰霜光晕
                local glowR = shieldSize * 0.5 * pulse
                local iceGlow = nvgRadialGradient(nvg, px, py, glowR * 0.3, glowR,
                    nvgRGBA(120, 200, 255, math.floor(60 * lifeRatio)),
                    nvgRGBA(80, 180, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, px, py, glowR)
                nvgFillPaint(nvg, iceGlow)
                nvgFill(nvg)

            -- ==============================================================
            -- ❄️ deep_freeze_burst — 深度冻结结束爆炸: 冰蓝冲击波
            -- ==============================================================
            elseif eff.type == "deep_freeze_burst" then
                local ex = l.x + (eff.x or 0)
                local ey = l.y + (eff.y or 0)
                local maxR = eff.radius or 120
                local progress = 1.0 - lifeRatio
                local waveR = maxR * math.min(1.0, progress * 2.0)
                -- 扩散冲击波环
                nvgBeginPath(nvg)
                nvgCircle(nvg, ex, ey, waveR)
                nvgStrokeColor(nvg, nvgRGBA(140, 220, 255, math.floor(alpha * 0.9)))
                nvgStrokeWidth(nvg, 4 * lifeRatio)
                nvgStroke(nvg)
                -- 内部冰霜闪光
                local flashA = math.floor(150 * lifeRatio * lifeRatio)
                local burstGlow = nvgRadialGradient(nvg, ex, ey, 0, waveR * 0.8,
                    nvgRGBA(180, 240, 255, flashA), nvgRGBA(100, 200, 255, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, ex, ey, waveR * 0.8)
                nvgFillPaint(nvg, burstGlow)
                nvgFill(nvg)
                -- 冰晶碎片飞散
                if lod < 2 then
                    local shardCount = lod == 0 and 12 or 6
                    for si = 1, shardCount do
                        local angle = si * (math.pi * 2 / shardCount)
                        local sr = waveR * 0.5 + waveR * 0.5 * progress
                        local shx = ex + math.cos(angle) * sr
                        local shy = ey + math.sin(angle) * sr
                        local sz = 4 * lifeRatio
                        nvgSave(nvg)
                        nvgTranslate(nvg, shx, shy)
                        nvgRotate(nvg, angle + progress * 3)
                        nvgBeginPath(nvg)
                        nvgMoveTo(nvg, 0, -sz)
                        nvgLineTo(nvg, sz * 0.6, 0)
                        nvgLineTo(nvg, 0, sz)
                        nvgLineTo(nvg, -sz * 0.6, 0)
                        nvgClosePath(nvg)
                        nvgFillColor(nvg, nvgRGBA(200, 240, 255, math.floor(alpha * 0.8)))
                        nvgFill(nvg)
                        nvgRestore(nvg)
                    end
                end

            -- ==============================================================
            -- ⚡ thunder_storm — 雷霆风暴: 全屏闪电风暴
            -- ==============================================================
            elseif eff.type == "thunder_storm" then
                local aw = eff.areaW or l.w
                local ah = eff.areaH or l.h
                local cx = l.x + aw * 0.5
                local cy = l.y + ah * 0.5
                local time = bs.time or 0

                -- 延迟加载闪电图片 (复用全局路径常量)
                if not eff._boltImgs then
                    eff._boltImgs = {}
                    local paths = {
                        "image/lightning_bolt_1_20260410155330.png",
                        "image/lightning_bolt_2_20260410155116.png",
                        "image/lightning_bolt_3_20260410155117.png",
                    }
                    for i, p in ipairs(paths) do
                        eff._boltImgs[i] = nvgCreateImage(nvg, p, 0)
                    end
                end
                if not eff._impactImg then
                    eff._impactImg = nvgCreateImage(nvg, "image/lightning_ground_impact_20260410155131.png", 0)
                end

                -- 全屏闪黄（保留，快速闪烁表示风暴降临）
                local flashA = math.floor(60 * lifeRatio * (0.5 + math.sin(time * 15) * 0.5))
                nvgBeginPath(nvg)
                nvgRect(nvg, l.x, l.y, aw, ah)
                nvgFillColor(nvg, nvgRGBA(255, 240, 80, flashA))
                nvgFill(nvg)

                -- 多道闪电柱图片劈落
                local boltCount = lod == 0 and 6 or (lod == 1 and 4 or 2)
                for bi = 1, boltCount do
                    local seed = time * 3.5 + bi * 61.7
                    local bx = l.x + (math.sin(seed) * 0.5 + 0.5) * aw
                    local by = l.y + (math.cos(seed * 1.3 + 5) * 0.3 + 0.6) * ah
                    local variant = (bi % 3) + 1
                    local boltH = eff._boltImgs[variant]
                    local flicker = 0.6 + math.sin(seed * 7) * 0.4
                    local boltAlpha = lifeRatio * flicker

                    if boltH and boltH > 0 and boltAlpha > 0.02 then
                        local boltW = 52
                        local boltHt = 160
                        local imgPaint = nvgImagePattern(nvg,
                            bx - boltW / 2, by - boltHt,
                            boltW, boltHt, 0, boltH, boltAlpha)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, bx - boltW / 2, by - boltHt, boltW, boltHt)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                    end

                    -- 地面电击
                    if eff._impactImg and eff._impactImg > 0 then
                        local impactSize = 40
                        local ip = nvgImagePattern(nvg,
                            bx - impactSize / 2, by - impactSize / 2,
                            impactSize, impactSize, 0, eff._impactImg, boltAlpha * 0.85)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, bx - impactSize / 2, by - impactSize / 2, impactSize, impactSize)
                        nvgFillPaint(nvg, ip)
                        nvgFill(nvg)
                    end
                end

            end
        end
    end

    -- ========================================================================
    -- Boss 技能特效
    -- ========================================================================

    function BattleView:DrawBossSkillEffects(nvg, l, bs)
        if not bs.bossSkillEffects then return end
        local time = bs.time or 0
        _barrageCountCache = {}  -- 每帧重置弹幕计数缓存

        for _, eff in ipairs(bs.bossSkillEffects) do
            local lifeRatio = math.max(0.01, eff.life / eff.maxLife)
            local alpha = math.floor(255 * lifeRatio)

            if eff.type == "barrage" then
                -- 弹幕: 多颗弹丸从boss向外扩散飞出
                local progress = 1.0 - lifeRatio  -- 0→1
                local isFireElem = (eff.element == "fire")
                local isArcaneElem = (eff.element == "arcane")

                -- 统一加载图片
                local imgH = getBossSkillImage(nvg, "barrage", eff.element)

                -- 计算每颗弹丸的插值位置（使用缓存避免 O(n²) 遍历）
                local cacheKey = eff.srcX .. "_" .. eff.srcY .. "_" .. eff.maxLife
                local count = _barrageCountCache[cacheKey]
                if not count then
                    count = 0
                    for _, e2 in ipairs(bs.bossSkillEffects) do
                        if e2.type == "barrage" and e2.srcX == eff.srcX and e2.srcY == eff.srcY and e2.maxLife == eff.maxLife then
                            count = count + 1
                        end
                    end
                    if count < 1 then count = 6 end
                    _barrageCountCache[cacheKey] = count
                end
                local totalDuration = eff.maxLife
                local shotInterval = totalDuration / (count + 2)

                -- 每颗弹丸生成
                for i = 1, math.min(count, 8) do
                    local shotTime = (i - 1) * shotInterval
                    local elapsed = (1.0 - lifeRatio) * totalDuration
                    local shotProgress = (elapsed - shotTime) / (totalDuration * 0.4)
                    if shotProgress > 0 and shotProgress <= 1.0 then
                        local angle = (i / count) * math.pi * 2 + time * 2
                        local startX = l.x + eff.srcX
                        local startY = l.y + eff.srcY
                        local endX = l.x + eff.tgtX + math.cos(angle) * 15
                        local endY = l.y + eff.tgtY + math.sin(angle) * 15
                        local cx = startX + (endX - startX) * shotProgress
                        local cy = startY + (endY - startY) * shotProgress
                        local size = 18
                        local shotAlpha = math.floor(240 * (1.0 - shotProgress * 0.5))

                        if imgH and imgH > 0 then
                            local pat = nvgImagePattern(nvg, cx - size/2, cy - size/2, size, size, 0, imgH, shotAlpha / 255)
                            nvgBeginPath(nvg)
                            nvgRect(nvg, cx - size/2, cy - size/2, size, size)
                            nvgFillPaint(nvg, pat)
                            nvgFill(nvg)
                        else
                            -- 回退: 纯色圆
                            local r, g, b = 100, 200, 255
                            if isFireElem then r, g, b = 255, 120, 30
                            elseif isArcaneElem then r, g, b = 180, 130, 255 end
                            nvgBeginPath(nvg)
                            nvgCircle(nvg, cx, cy, size * 0.3)
                            nvgFillColor(nvg, nvgRGBA(r, g, b, shotAlpha))
                            nvgFill(nvg)
                        end
                    end
                end

            elseif eff.type == "dragonBreath" then
                -- 龙息: 锥形喷射 + 粒子图
                local isFireElem = (eff.element == "fire")
                local isArcaneElem = (eff.element == "arcane")

                -- 统一加载图片
                local imgH = getBossSkillImage(nvg, "dragonBreath", eff.element)

                local sx = l.x + eff.srcX
                local sy = l.y + eff.srcY
                local tx = l.x + eff.tgtX
                local ty = l.y + eff.tgtY
                local dx, dy = tx - sx, ty - sy
                local dist = math.sqrt(dx * dx + dy * dy)
                local progress = 1.0 - lifeRatio

                -- 龙息锥形扩展
                local breathLen = dist * math.min(1.0, progress * 2.0)
                local breathW = 20 + breathLen * 0.3
                local angle = math.atan(dy, dx)

                if imgH and imgH > 0 then
                    -- 用图片渲染龙息
                    local imgW = breathLen
                    local imgH2 = breathW
                    nvgSave(nvg)
                    nvgTranslate(nvg, sx, sy)
                    nvgRotate(nvg, angle)
                    local pat = nvgImagePattern(nvg, 0, -imgH2/2, imgW, imgH2, 0, imgH, alpha / 255)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, 0, -imgH2/2, imgW, imgH2)
                    nvgFillPaint(nvg, pat)
                    nvgFill(nvg)
                    nvgRestore(nvg)
                else
                    -- 回退: 渐变锥形
                    local r, g, b = 100, 200, 255
                    if isFireElem then r, g, b = 255, 120, 30
                    elseif isArcaneElem then r, g, b = 180, 130, 255 end
                    nvgSave(nvg)
                    nvgTranslate(nvg, sx, sy)
                    nvgRotate(nvg, angle)
                    local grad = nvgLinearGradient(nvg, 0, 0, breathLen, 0,
                        nvgRGBA(r, g, b, alpha), nvgRGBA(r, g, b, 0))
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, 0, -5)
                    nvgLineTo(nvg, breathLen, -breathW/2)
                    nvgLineTo(nvg, breathLen, breathW/2)
                    nvgLineTo(nvg, 0, 5)
                    nvgClosePath(nvg)
                    nvgFillPaint(nvg, grad)
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end

                -- 散落粒子
                for si = 1, 4 do
                    local seed = time * 5 + si * 97.3
                    local t = math.fmod(seed, 1.0)
                    local px = sx + dx * t + math.sin(seed * 3) * breathW * 0.3
                    local py = sy + dy * t + math.cos(seed * 2) * breathW * 0.3
                    local sparkA = math.floor(180 * lifeRatio * (0.5 + math.sin(seed * 4) * 0.5))
                    local r, g, b = 160, 220, 255
                    if isFireElem then r, g, b = 255, 200, 80
                    elseif isArcaneElem then r, g, b = 200, 160, 255 end
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, px, py, 2 + math.sin(seed * 2) * 1.5)
                    nvgFillColor(nvg, nvgRGBA(r, g, b, sparkA))
                    nvgFill(nvg)
                end

            elseif eff.type == "deathExplode" then
                -- 死亡爆炸: 扩散冲击波
                local isFireElem = (eff.element == "fire")
                local isArcaneElem = (eff.element == "arcane")

                -- 统一加载图片
                local imgH = getBossSkillImage(nvg, "deathExplode", eff.element)

                local sx = l.x + eff.x
                local sy = l.y + eff.y
                local progress = 1.0 - lifeRatio
                local expandR = eff.radius * math.min(1.0, progress * 2.0)
                local size = expandR * 2

                if imgH and imgH > 0 then
                    local pat = nvgImagePattern(nvg, sx - size/2, sy - size/2, size, size, 0, imgH, alpha / 255)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, size / 2)
                    nvgFillPaint(nvg, pat)
                    nvgFill(nvg)
                end

                -- 冲击波外环
                local r, g, b = 140, 200, 255
                if isFireElem then r, g, b = 255, 140, 40
                elseif isArcaneElem then r, g, b = 180, 130, 255 end
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgStrokeColor(nvg, nvgRGBA(r, g, b, math.floor(alpha * 0.7)))
                nvgStrokeWidth(nvg, 3 * lifeRatio)
                nvgStroke(nvg)

                -- 内圈光晕
                local glow = nvgRadialGradient(nvg, sx, sy, expandR * 0.2, expandR,
                    nvgRGBA(r, g, b, math.floor(alpha * 0.3)), nvgRGBA(r, g, b, 0))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, expandR)
                nvgFillPaint(nvg, glow)
                nvgFill(nvg)

            elseif eff.type == "frozenField" then
                -- 冰封/熔岩/奥术领域: 跟随boss的地面圈
                local isFireElem = (eff.element == "fire")
                local isArcaneElem = (eff.element == "arcane")

                -- 统一加载图片
                local fieldImgH = getBossSkillImage(nvg, "frozenField", eff.element)
                local enemy = eff.enemyRef
                if enemy and not enemy.dead then
                    local sx = l.x + enemy.x
                    local sy = l.y + enemy.y
                    local r = eff.radius
                    local pulse = 1.0 + math.sin(time * 4) * 0.05
                    local size = r * 2 * pulse
                    local fieldAlpha = math.floor(math.min(200, alpha) * (0.6 + math.sin(time * 3) * 0.2))

                    if fieldImgH and fieldImgH > 0 then
                        local pat = nvgImagePattern(nvg, sx - size/2, sy - size/2, size, size, 0, fieldImgH, fieldAlpha / 255)
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, sx, sy, size / 2)
                        nvgFillPaint(nvg, pat)
                        nvgFill(nvg)
                    end

                    -- 外圈脉冲
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r * pulse)
                    local elemR, elemG, elemB = 80, 160, 255
                    if eff.element == "fire" then elemR, elemG, elemB = 255, 100, 30
                    elseif eff.element == "arcane" then elemR, elemG, elemB = 180, 130, 255 end
                    nvgStrokeColor(nvg, nvgRGBA(elemR, elemG, elemB, math.floor(fieldAlpha * 0.6)))
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStroke(nvg)

                    -- 旋转雪花纹路
                    nvgSave(nvg)
                    nvgTranslate(nvg, sx, sy)
                    nvgRotate(nvg, time * 0.5)
                    for spoke = 1, 6 do
                        local a = (spoke / 6) * math.pi * 2
                        nvgBeginPath(nvg)
                        nvgMoveTo(nvg, 0, 0)
                        nvgLineTo(nvg, math.cos(a) * r * 0.7, math.sin(a) * r * 0.7)
                        nvgStrokeColor(nvg, nvgRGBA(elemR, elemG, elemB, math.floor(fieldAlpha * 0.3)))
                        nvgStrokeWidth(nvg, 1)
                        nvgStroke(nvg)
                    end
                    nvgRestore(nvg)
                else
                    eff.life = 0  -- boss 死亡则结束特效
                end

            elseif eff.type == "iceArmor" then
                -- 冰甲/火甲/奥术甲: 跟随boss的护盾光罩
                local isFireElem = (eff.element == "fire")
                local isArcaneElem = (eff.element == "arcane")

                -- 统一加载图片
                local armorImgH = getBossSkillImage(nvg, "iceArmor", eff.element)
                local enemy = eff.enemyRef
                if enemy and not enemy.dead and enemy.iceArmorActive then
                    local sx = l.x + enemy.x
                    local sy = l.y + enemy.y
                    local r = (enemy.radius or 16) + 10
                    local pulse = 1.0 + math.sin(time * 6) * 0.08
                    local size = r * 2 * pulse
                    local armorAlpha = math.floor(180 * (0.7 + math.sin(time * 5) * 0.3))

                    if armorImgH and armorImgH > 0 then
                        local pat = nvgImagePattern(nvg, sx - size/2, sy - size/2, size, size, 0, armorImgH, armorAlpha / 255)
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, sx, sy, size / 2)
                        nvgFillPaint(nvg, pat)
                        nvgFill(nvg)
                    end

                    -- 边缘闪光环
                    local elemR, elemG, elemB = 100, 200, 255
                    if eff.element == "fire" then elemR, elemG, elemB = 255, 160, 40
                    elseif eff.element == "arcane" then elemR, elemG, elemB = 180, 130, 255 end
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, r * pulse)
                    nvgStrokeColor(nvg, nvgRGBA(elemR, elemG, elemB, armorAlpha))
                    nvgStrokeWidth(nvg, 2)
                    nvgStroke(nvg)
                else
                    eff.life = 0  -- boss死亡或冰甲结束
                end
            end
        end
    end

    -- ========================================================================
    -- 模板系统 Boss 技能特效 (弹幕/区域/阶段转换/可摧毁物)
    -- ========================================================================

    local DrawBossTemplates = require("view.DrawBossTemplates")

    function BattleView:DrawBossTemplateEffects(nvg, l, bs)
        DrawBossTemplates.DrawAll(nvg, l, bs)
    end

    -- Return preload functions for BattleView.Render() to use
    return {
        BuildBossPreloadQueue = BuildBossPreloadQueue,
        TickBossPreload = TickBossPreload,
        GetPreloadState = function()
            return bossPreloadChapter, bossPreloadStage
        end,
    }
end

return DrawEffects
