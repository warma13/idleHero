-- ============================================================================
-- BattleView.lua - 自定义 NanoVG Widget 渲染战斗区域 (术士版)
-- ============================================================================

local Widget = require("urhox-libs/UI/Core/Widget")
local EndlessTrial = require("EndlessTrial")
local MonsterTemplates = require("MonsterTemplates")
local WorldBoss = require("WorldBoss")
local ResourceDungeon = require("ResourceDungeon")
local DamageTracker = require("DamageTracker")
local Utils = require("Utils")

---@class BattleView : Widget
local BattleView = Widget:Extend("BattleView")

-- 图片句柄（仅本文件使用的，延迟加载）
local projImgHandle      = nil  -- 弹道图片
local hydraFbImgHandle   = nil  -- 九头蛇火球弹体图片
local trailImgHandle     = nil  -- 紫焰拖尾图片
local bgImgHandle        = nil  -- 战斗背景图
local bgImgChapter       = 0   -- 当前背景对应的章节号
-- 待机模式
local idleMode_          = false  -- 全屏待机
local battleIdleMode_    = false  -- 战斗待机（战斗区域显示背景图，UI保留）
local idleBgHandle_      = nil
local IDLE_BG_PATH       = "idle_bg_20260310191041.png"
-- 火焰地带 sprite sheet (4帧横排动画)
local fireSheetHandle    = nil
local FIRE_SHEET_COLS    = 4
local FIRE_ANIM_FPS      = 6

-- 雷暴闪电柱 (3 变体 + 地面冲击)
local thunderBoltHandles = nil  -- {1..3 -> handle}
local thunderImpactHandle = nil
local THUNDER_BOLT_PATHS = {
    "image/lightning_bolt_1_20260410155330.png",
    "image/lightning_bolt_2_20260410155116.png",
    "image/lightning_bolt_3_20260410155117.png",
}
local THUNDER_IMPACT_PATH = "image/lightning_ground_impact_20260410155131.png"

-- 暴风雪冰晶碎片调试参数 (F8 调试面板可调)
local blizzardShardHandle = nil
local BlizzardVFX = {
    speed       = 190,   -- 沿倾斜方向的运动速度 (px/s)
    speedRange  = 30,    -- 速度随机范围
    count       = 10,    -- 冰晶数量
    sizeBase    = 20,    -- 冰晶基础尺寸
    sizeRange   = 4,     -- 冰晶尺寸随机范围
    wobbleFreq  = 2.0,   -- 摆动频率
    wobbleAmp   = 0.15,  -- 摆动幅度
    tiltBase    = 0.785, -- 倾斜基础角度 (45°, 左下方向)
    tiltRange   = 0,     -- 倾斜随机范围
}
local blizzardDebugShow = false
local blizzardDebugFont = nil

-- 共享图片句柄表（子模块通过 Install 注入时共享）
local imgHandles = { mob = {}, elemIcon = {}, equipIcon = {} }

-- 安装子模块（将 Draw* 方法注入 BattleView）
local effectsAPI = require("view.DrawEffects").Install(BattleView, imgHandles)
require("view.DrawParticles").Install(BattleView, imgHandles)
require("view.DrawEntities").Install(BattleView, imgHandles)
require("view.DrawFamilyEffects").Install(BattleView, imgHandles)

function BattleView:Init(props)
    props = props or {}
    props.pointerEvents = props.pointerEvents or "none"
    Widget.Init(self, props)
end

function BattleView:IsStateful()
    return true
end

-- ============================================================================
-- 主渲染
-- ============================================================================

function BattleView:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    local bs = self.props.battleSystem
    if not bs then return end

    -- 全屏待机：跳过所有战斗绘制（覆盖层由 main.lua 处理）
    if idleMode_ then return end

    -- 战斗待机：只渲染背景图，跳过战斗绘制，UI保留可操作
    if battleIdleMode_ then
        nvgSave(nvg)
        nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)
        if not idleBgHandle_ then
            idleBgHandle_ = nvgCreateImage(nvg, IDLE_BG_PATH, 0)
        end
        if idleBgHandle_ and idleBgHandle_ > 0 then
            local paint = nvgImagePattern(nvg, l.x, l.y, l.w, l.h, 0, idleBgHandle_, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, l.x, l.y, l.w, l.h)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
        end
        nvgRestore(nvg)
        return
    end

    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- 震屏偏移（受设置乘数影响）
    local Settings = require("ui.Settings")
    local shakeMul = Settings.GetShakeMultiplier()
    local shake = (bs.screenShake or 0) * shakeMul
    if shake > 0.2 then
        local sx = (math.random() * 2 - 1) * shake
        local sy = (math.random() * 2 - 1) * shake
        l = { x = l.x + sx, y = l.y + sy, w = l.w, h = l.h }
    end

    -- Boss 图片分帧预加载：进入 boss 关卡时每帧加载 1 张图，避免技能触发时集中阻塞
    if bs.isBossWave then
        local GameState = require("GameState")
        local ch = GameState.stage.chapter
        local st = GameState.stage.stage
        local plCh, plSt = effectsAPI.GetPreloadState()
        if ch ~= plCh or st ~= plSt then
            effectsAPI.BuildBossPreloadQueue(ch, st)
        end
        effectsAPI.TickBossPreload(nvg)
    end

    self:DrawBackground(nvg, l)
    self:DrawFireZones(nvg, l, bs)
    self:DrawFamilyZones(nvg, l, bs)
    self:DrawLoots(nvg, l, bs)
    self:DrawEnemies(nvg, l, bs)
    self:DrawEliteOverlays(nvg, l, bs)
    self:DrawPlayer(nvg, l, bs)
    self:DrawSpirits(nvg, l, bs)
    self:DrawPlayerHP(nvg, l, bs)
    self:DrawPlayerTitle(nvg, l, bs)
    self:DrawProjectiles(nvg, l, bs)
    self:DrawBullets(nvg, l, bs)
    self:DrawFrostShards(nvg, l, bs)
    self:DrawSkillEffects(nvg, l, bs)
    self:DrawBossSkillEffects(nvg, l, bs)
    self:DrawBossTemplateEffects(nvg, l, bs)
    self:DrawParticles(nvg, l, bs)
    self:DrawSkillCooldowns(nvg, l, bs)
    self:DrawWaveInfo(nvg, l, bs)
    self:DrawTrialHUD(nvg, l, bs)
    self:DrawBossTimer(nvg, l, bs)
    self:DrawBossDamageHUD(nvg, l, bs)
    self:DrawDeathOverlay(nvg, l, bs)

    -- F8 切换暴风雪调试面板
    if input:GetKeyPress(KEY_F8) then
        blizzardDebugShow = not blizzardDebugShow
    end
    if blizzardDebugShow then
        self:DrawBlizzardDebugPanel(nvg, l)
    end

    nvgRestore(nvg)
end

-- ============================================================================
-- 背景
-- ============================================================================

-- 章节 → 战斗背景图路径
local CHAPTER_BG = {
    [1] = "battle_bg_topdown_20260306122427.png",
    [2] = "battle_bg_ch2_ice_20260307085530.png",
    [3] = "battle_bg_ch3_lava_20260307162630.png",
    [4] = "Textures/battle_bg_ch4.png",
    [5] = "Textures/battle_bg_ch5.png",
    [6] = "battle_bg_ch6_20260309155343.png",
    [7] = "Textures/battle_bg_ch7.png",
    [8] = "Textures/battle_bg_ch8.png",
    [9] = "Textures/battle_bg_ch9.png",
    [10] = "battle_bg_ch10_20260310091528.png",
    [11] = "battle_bg_ch11_20260310091515.png",
    [12] = "Textures/battle_bg_ch12.png",
    [13] = "Textures/battle_bg_ch13.png",
    [14] = "Textures/battle_bg_ch14.png",
    [15] = "Textures/battle_bg_ch15.png",
    [16] = "Textures/battle_bg_ch16.png",
}
function BattleView:DrawBackground(nvg, l)
    -- 通过 GameMode 适配器获取背景路径，无特殊模式则走章节背景
    local GameState = require("GameState")
    local GameMode  = require("GameMode")
    local modeBg    = GameMode.GetBackground()
    local bgKey     = modeBg or (GameState.stage.chapter or 1)

    if bgKey ~= bgImgChapter then
        if bgImgHandle and bgImgHandle > 0 then
            nvgDeleteImage(nvg, bgImgHandle)
        end
        local path = modeBg or (CHAPTER_BG[bgKey] or CHAPTER_BG[1])
        bgImgHandle = nvgCreateImage(nvg, path, 0)
        bgImgChapter = bgKey
    end

    if not bgImgHandle then
        local path = modeBg or (CHAPTER_BG[bgKey] or CHAPTER_BG[1])
        bgImgHandle = nvgCreateImage(nvg, path, 0)
        bgImgChapter = bgKey
    end

    if bgImgHandle and bgImgHandle > 0 then
        -- Cover 策略：等比缩放填满区域，居中裁切多余部分
        local imgW, imgH = nvgImageSize(nvg, bgImgHandle)
        local drawX, drawY, drawW, drawH = l.x, l.y, l.w, l.h
        if imgW > 0 and imgH > 0 then
            local areaRatio = l.w / l.h
            local imgRatio  = imgW / imgH
            if imgRatio > areaRatio then
                -- 图片更宽，以高度为基准，水平居中裁切
                drawH = l.h
                drawW = l.h * imgRatio
                drawX = l.x - (drawW - l.w) * 0.5
                drawY = l.y
            else
                -- 图片更高，以宽度为基准，垂直居中裁切
                drawW = l.w
                drawH = l.w / imgRatio
                drawX = l.x
                drawY = l.y - (drawH - l.h) * 0.5
            end
        end
        local paint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, bgImgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, l.h)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)

        -- 底部加一层渐变遮罩，让地面更暗
        local gradBot = nvgLinearGradient(nvg, l.x, l.y + l.h * 0.7, l.x, l.y + l.h,
            nvgRGBA(0, 0, 0, 0), nvgRGBA(0, 0, 0, 120))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y + l.h * 0.7, l.w, l.h * 0.3)
        nvgFillPaint(nvg, gradBot)
        nvgFill(nvg)
    else
        -- 回退: 纯色背景
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, l.h)
        nvgFillColor(nvg, nvgRGBA(18, 22, 30, 255))
        nvgFill(nvg)
    end

    -- 底部地面线
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, l.x, l.y + l.h - 2)
    nvgLineTo(nvg, l.x + l.w, l.y + l.h - 2)
    nvgStrokeColor(nvg, nvgRGBA(60, 70, 90, 150))
    nvgStrokeWidth(nvg, 2)
    nvgStroke(nvg)
end

-- ============================================================================
-- 火焰地带 (残焰/火雨/毁灭领域)
-- ============================================================================

function BattleView:DrawFireZones(nvg, l, bs)
    -- 延迟加载 sprite sheet
    if not fireSheetHandle then
        fireSheetHandle = nvgCreateImage(nvg, "fire_zone_sheet_20260306001727.png", 0)
    end
    -- 延迟加载冰晶碎片贴图
    if not blizzardShardHandle then
        blizzardShardHandle = nvgCreateImage(nvg, "image/ice_crystal_shard_20260327062601.png", 0)
    end

    local time = bs.time or 0
    local zoneCullMargin = 80
    for _, zone in ipairs(bs.fireZones) do
        local sx = l.x + zone.x
        local sy = l.y + zone.y
        -- 视口外剔除
        if sx < l.x - zoneCullMargin or sx > l.x + l.w + zoneCullMargin
            or sy < l.y - zoneCullMargin or sy > l.y + l.h + zoneCullMargin then
            goto continue_zone
        end
        local lifeRatio = math.max(0.01, zone.duration / zone.maxDuration)
        local flicker = 1.0 + math.sin(time * 6 + zone.x * 0.1) * 0.15
        local radius = zone.radius * flicker
        local drawSize = radius * 2

        -- 冰晶区域特殊渲染
        if zone.source == "frost_crystal" then
            -- 冰蓝色半透明底圈
            local iceAlpha = math.floor(100 * lifeRatio)
            local iceGlow = nvgRadialGradient(nvg, sx, sy, 0, radius,
                nvgRGBA(140, 220, 255, iceAlpha), nvgRGBA(80, 180, 255, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgFillPaint(nvg, iceGlow)
            nvgFill(nvg)

            -- 旋转冰晶图案 (6角雪花)
            local rot = time * 0.8 + zone.x * 0.1
            local spikes = 6
            for si = 1, spikes do
                local ang = rot + (si - 1) * math.pi * 2 / spikes
                local x1 = sx + math.cos(ang) * radius * 0.3
                local y1 = sy + math.sin(ang) * radius * 0.3
                local x2 = sx + math.cos(ang) * radius * 0.8
                local y2 = sy + math.sin(ang) * radius * 0.8
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, x1, y1)
                nvgLineTo(nvg, x2, y2)
                nvgStrokeColor(nvg, nvgRGBA(200, 240, 255, math.floor(150 * lifeRatio)))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            end

            -- 边缘冰霜环
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgStrokeColor(nvg, nvgRGBA(160, 230, 255, math.floor(120 * lifeRatio)))
            nvgStrokeWidth(nvg, 2.0 * lifeRatio)
            nvgStroke(nvg)

        -- ❄️ 暴风雪区域: 冰蓝底圈 + 冰晶碎片斜向下坠
        elseif zone.source == "blizzard" then
            -- 暴风雪使用稳定半径，不受 flicker 抖动影响
            radius = zone.radius
            -- 冰蓝色半透明底圈
            local iceAlpha = math.floor(80 * lifeRatio)
            local iceGlow = nvgRadialGradient(nvg, sx, sy, 0, radius,
                nvgRGBA(100, 200, 255, iceAlpha), nvgRGBA(60, 150, 230, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgFillPaint(nvg, iceGlow)
            nvgFill(nvg)

            -- 边缘冰霜环
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgStrokeColor(nvg, nvgRGBA(140, 220, 255, math.floor(100 * lifeRatio)))
            nvgStrokeWidth(nvg, 1.5 * lifeRatio)
            nvgStroke(nvg)

            -- 冰晶碎片沿倾斜角度下坠
            local V = BlizzardVFX
            if blizzardShardHandle and blizzardShardHandle > 0 then
                local travelLen = radius * 2.4  -- 沿运动方向的循环长度
                for si = 1, V.count do
                    local seed = si * 137.5 + zone.x * 0.37
                    local spd = V.speed + (math.sin(seed * 2.1) * 0.5 + 0.5) * V.speedRange
                    local shardSize = V.sizeBase + (math.sin(seed * 3.7) * 0.5 + 0.5) * V.sizeRange
                    local tilt = V.tiltBase + math.sin(seed * 1.3) * V.tiltRange

                    -- 沿 tilt 角度的运动方向 (tilt=0 → 正下方, tilt<0 → 右下)
                    local dirX = -math.sin(tilt)
                    local dirY = math.cos(tilt)

                    -- 起始位置：在垂直于运动方向的轴上随机分布
                    local perpX = dirY
                    local perpY = -dirX
                    local perpOffset = (math.sin(seed * 0.73) * 2 - 1) * radius * 0.8

                    -- 沿运动方向循环前进
                    local t = (time * spd + seed * 137) % travelLen
                    local px = perpOffset * perpX + (t - travelLen * 0.5) * dirX
                    local py = perpOffset * perpY + (t - travelLen * 0.5) * dirY

                    local dist = math.sqrt(px * px + py * py)
                    if dist < radius * 0.95 then
                        local halfSize = shardSize * 0.5

                        nvgSave(nvg)
                        nvgTranslate(nvg, sx + px, sy + py)
                        nvgRotate(nvg, tilt + math.sin(time * V.wobbleFreq + seed) * V.wobbleAmp)
                        local imgPaint = nvgImagePattern(nvg,
                            -halfSize, -halfSize, shardSize, shardSize,
                            0, blizzardShardHandle, 1.0)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, -halfSize, -halfSize, shardSize, shardSize)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                        nvgRestore(nvg)
                    end
                end
            end

        -- ❄️ 深度冻结区域: 冰封光环 + 旋转冰晶 + 脉动
        elseif zone.source == "deep_freeze" then
            radius = zone.radius  -- 稳定半径
            -- 冰封底圈 (较强的冰蓝色)
            local iceAlpha = math.floor(120 * lifeRatio)
            local iceGlow = nvgRadialGradient(nvg, sx, sy, 0, radius,
                nvgRGBA(80, 180, 255, iceAlpha), nvgRGBA(40, 120, 220, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgFillPaint(nvg, iceGlow)
            nvgFill(nvg)

            -- 脉动光环 (呼吸效果)
            local pulse = 0.85 + math.sin(time * 3) * 0.15
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius * pulse)
            nvgStrokeColor(nvg, nvgRGBA(160, 230, 255, math.floor(180 * lifeRatio)))
            nvgStrokeWidth(nvg, 2.5 * lifeRatio)
            nvgStroke(nvg)

            -- 旋转冰晶 (8个围绕中心)
            local crystalCount = 8
            local rot = time * 1.2
            for ci = 1, crystalCount do
                local ang = rot + (ci - 1) * math.pi * 2 / crystalCount
                local cr = radius * 0.7
                local cx = sx + math.cos(ang) * cr
                local cy = sy + math.sin(ang) * cr
                -- 小菱形冰晶
                local sz = 5 * lifeRatio
                nvgSave(nvg)
                nvgTranslate(nvg, cx, cy)
                nvgRotate(nvg, ang + math.pi * 0.25)
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, 0, -sz)
                nvgLineTo(nvg, sz * 0.6, 0)
                nvgLineTo(nvg, 0, sz)
                nvgLineTo(nvg, -sz * 0.6, 0)
                nvgClosePath(nvg)
                nvgFillColor(nvg, nvgRGBA(200, 240, 255, math.floor(220 * lifeRatio)))
                nvgFill(nvg)
                nvgRestore(nvg)
            end

            -- 内圈冰霜闪光
            local innerGlow = nvgRadialGradient(nvg, sx, sy, 0, radius * 0.3,
                nvgRGBA(220, 245, 255, math.floor(60 * lifeRatio * pulse)), nvgRGBA(200, 240, 255, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius * 0.3)
            nvgFillPaint(nvg, innerGlow)
            nvgFill(nvg)

        -- ⚡ 雷暴区域: 闪电柱图片随机劈落 + 地面电击标记
        elseif zone.source == "thunderstorm" then
            radius = zone.radius  -- 稳定半径

            -- 延迟加载闪电图片
            if not thunderBoltHandles then
                thunderBoltHandles = {}
                for i, path in ipairs(THUNDER_BOLT_PATHS) do
                    thunderBoltHandles[i] = nvgCreateImage(nvg, path, 0)
                end
            end
            if not thunderImpactHandle then
                thunderImpactHandle = nvgCreateImage(nvg, THUNDER_IMPACT_PATH, 0)
            end

            -- 用确定性种子生成多道闪电，每道有独立的生命周期
            -- 每 0.25s 一道新闪电，同时存在 ~3 道
            local BOLT_INTERVAL = 0.25
            local BOLT_LIFE     = 0.4   -- 每道闪电持续时间
            local BOLT_SLOTS    = 5     -- 最多同时计算的槽位

            for slot = 0, BOLT_SLOTS - 1 do
                -- 每个槽位的出生时间
                local bornTime = math.floor(time / BOLT_INTERVAL) * BOLT_INTERVAL - slot * BOLT_INTERVAL
                local age = time - bornTime
                if age >= 0 and age < BOLT_LIFE then
                    -- 用 bornTime 做种子，位置确定且不随帧变化
                    local seed = bornTime * 127.1 + zone.x * 3.7 + slot * 53
                    local rx = math.sin(seed) * 0.7              -- -0.7 ~ 0.7
                    local ry = math.cos(seed * 1.3 + 7) * 0.5    -- -0.5 ~ 0.5
                    local bx = sx + rx * radius
                    local by = sy + ry * radius

                    -- 闪电柱图片选择 (3 变体)
                    local variant = math.floor(math.abs(math.sin(seed * 2.9)) * 3) % 3 + 1
                    local boltH = thunderBoltHandles[variant]

                    -- 淡入淡出: 0~0.1 淡入, 0.1~0.25 全亮, 0.25~0.4 淡出
                    local boltAlpha
                    if age < 0.1 then
                        boltAlpha = age / 0.1
                    elseif age < 0.25 then
                        boltAlpha = 1.0
                    else
                        boltAlpha = 1.0 - (age - 0.25) / 0.15
                    end
                    boltAlpha = boltAlpha * lifeRatio

                    -- 绘制闪电柱 (从上方劈到 by)
                    if boltH and boltH > 0 and boltAlpha > 0.02 then
                        local boltW = 36
                        local boltHt = 120
                        local imgPaint = nvgImagePattern(nvg,
                            bx - boltW / 2, by - boltHt,
                            boltW, boltHt, 0, boltH, boltAlpha)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, bx - boltW / 2, by - boltHt, boltW, boltHt)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                    end

                    -- 地面电击标记 (稍晚出现，持续更久)
                    if thunderImpactHandle and thunderImpactHandle > 0 and age > 0.05 then
                        local impactAlpha = boltAlpha * 0.9
                        local impactSize = 28
                        local ip = nvgImagePattern(nvg,
                            bx - impactSize / 2, by - impactSize / 2,
                            impactSize, impactSize, 0, thunderImpactHandle, impactAlpha)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, bx - impactSize / 2, by - impactSize / 2, impactSize, impactSize)
                        nvgFillPaint(nvg, ip)
                        nvgFill(nvg)
                    end
                end
            end

        -- ⚡ 雷霆风暴区域: 全屏级密集闪电柱图片劈落
        elseif zone.source == "thunder_storm" then
            radius = zone.radius

            -- 复用雷暴的闪电图片（延迟加载）
            if not thunderBoltHandles then
                thunderBoltHandles = {}
                for i, path in ipairs(THUNDER_BOLT_PATHS) do
                    thunderBoltHandles[i] = nvgCreateImage(nvg, path, 0)
                end
            end
            if not thunderImpactHandle then
                thunderImpactHandle = nvgCreateImage(nvg, THUNDER_IMPACT_PATH, 0)
            end

            -- 更密集的闪电: 间隔更短、槽位更多
            local BOLT_INTERVAL = 0.15
            local BOLT_LIFE     = 0.4
            local BOLT_SLOTS    = 8

            for slot = 0, BOLT_SLOTS - 1 do
                local bornTime = math.floor(time / BOLT_INTERVAL) * BOLT_INTERVAL - slot * BOLT_INTERVAL
                local age = time - bornTime
                if age >= 0 and age < BOLT_LIFE then
                    local seed = bornTime * 97.3 + zone.x * 5.1 + slot * 41
                    local rx = math.sin(seed) * 0.85
                    local ry = math.cos(seed * 1.7 + 3) * 0.7
                    local bx = sx + rx * radius
                    local by = sy + ry * radius

                    local variant = math.floor(math.abs(math.sin(seed * 3.1)) * 3) % 3 + 1
                    local boltH = thunderBoltHandles[variant]

                    -- 淡入淡出
                    local boltAlpha
                    if age < 0.08 then
                        boltAlpha = age / 0.08
                    elseif age < 0.2 then
                        boltAlpha = 1.0
                    else
                        boltAlpha = 1.0 - (age - 0.2) / 0.2
                    end
                    boltAlpha = boltAlpha * lifeRatio

                    -- 闪电柱（更大）
                    if boltH and boltH > 0 and boltAlpha > 0.02 then
                        local boltW = 44
                        local boltHt = 140
                        local imgPaint = nvgImagePattern(nvg,
                            bx - boltW / 2, by - boltHt,
                            boltW, boltHt, 0, boltH, boltAlpha)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, bx - boltW / 2, by - boltHt, boltW, boltHt)
                        nvgFillPaint(nvg, imgPaint)
                        nvgFill(nvg)
                    end

                    -- 地面电击
                    if thunderImpactHandle and thunderImpactHandle > 0 and age > 0.04 then
                        local impactAlpha = boltAlpha * 0.9
                        local impactSize = 32
                        local ip = nvgImagePattern(nvg,
                            bx - impactSize / 2, by - impactSize / 2,
                            impactSize, impactSize, 0, thunderImpactHandle, impactAlpha)
                        nvgBeginPath(nvg)
                        nvgRect(nvg, bx - impactSize / 2, by - impactSize / 2, impactSize, impactSize)
                        nvgFillPaint(nvg, ip)
                        nvgFill(nvg)
                    end
                end
            end

        else
            -- 帧动画: 根据时间选择当前帧 (每个 zone 用自身位置做偏移避免同步)
            local frameIdx = math.floor((time * FIRE_ANIM_FPS + zone.x * 0.05) % FIRE_SHEET_COLS)

            -- sprite sheet 切帧渲染
            if fireSheetHandle and fireSheetHandle > 0 then
                local imgAlpha = lifeRatio * 0.85
                -- sheet 宽度 = drawSize * FIRE_SHEET_COLS, 高度 = drawSize
                -- 通过 ox 偏移选择对应列
                local sheetW = drawSize * FIRE_SHEET_COLS
                local ox = (sx - radius) - frameIdx * drawSize
                local imgPaint = nvgImagePattern(nvg, ox, sy - radius,
                    sheetW, drawSize, 0, fireSheetHandle, imgAlpha)
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - radius, sy - radius, drawSize, drawSize)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
            end

            -- 外圈光晕 (颜色按元素区分)
            local r, g, b
            if zone.element then
                local Config = require("Config")
                local ec = Config.ELEMENTS.colors[zone.element]
                if ec then
                    r, g, b = ec[1], ec[2], ec[3]
                else
                    r, g, b = 180, 80, 255
                end
            elseif zone.source == "destruction" then
                r, g, b = 255, 40, 40
            else
                r, g, b = 180, 80, 255
            end

            local glowAlpha = math.floor(60 * lifeRatio)
            local glow = nvgRadialGradient(nvg, sx, sy, radius * 0.5, radius * 1.3,
                nvgRGBA(r, g, b, glowAlpha), nvgRGBA(r, g, b, 0))
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius * 1.3)
            nvgFillPaint(nvg, glow)
            nvgFill(nvg)

            -- 边缘脉冲环
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgStrokeColor(nvg, nvgRGBA(r, g, b, math.floor(80 * lifeRatio)))
            nvgStrokeWidth(nvg, 1.5 * lifeRatio)
            nvgStroke(nvg)
        end
        ::continue_zone::
    end
end

-- ============================================================================
-- 暴风雪 VFX 调试面板 (F8)
-- ============================================================================

local debugParams = {
    { key = "speed",      label = "运动速度",   step = 10,   min = 0 },
    { key = "speedRange", label = "速度范围",   step = 5,    min = 0 },
    { key = "count",      label = "冰晶数量",   step = 1,    min = 1,  int = true },
    { key = "sizeBase",   label = "基础尺寸",   step = 2,    min = 4 },
    { key = "sizeRange",  label = "尺寸范围",   step = 2,    min = 0 },
    { key = "wobbleFreq", label = "摆动频率",   step = 0.2,  min = 0 },
    { key = "wobbleAmp",  label = "摆动幅度",   step = 0.05, min = 0 },
    { key = "tiltBase",   label = "倾斜角度",   step = 0.05 },
    { key = "tiltRange",  label = "倾斜范围",   step = 0.05, min = 0 },
}
local debugSelIdx = 1

function BattleView:DrawBlizzardDebugPanel(nvg, l)
    -- 创建字体
    if not blizzardDebugFont then
        blizzardDebugFont = nvgCreateFont(nvg, "dbg", "Fonts/MiSans-Regular.ttf")
    end

    -- 键盘操作
    if input:GetKeyPress(KEY_UP) then
        debugSelIdx = math.max(1, debugSelIdx - 1)
    elseif input:GetKeyPress(KEY_DOWN) then
        debugSelIdx = math.min(#debugParams, debugSelIdx + 1)
    elseif input:GetKeyPress(KEY_LEFT) or input:GetKeyPress(KEY_MINUS) then
        local p = debugParams[debugSelIdx]
        local v = BlizzardVFX[p.key] - p.step
        if p.min then v = math.max(p.min, v) end
        if p.int then v = math.floor(v) end
        BlizzardVFX[p.key] = v
    elseif input:GetKeyPress(KEY_RIGHT) or input:GetKeyPress(KEY_EQUALS) then
        local p = debugParams[debugSelIdx]
        local v = BlizzardVFX[p.key] + p.step
        if p.int then v = math.floor(v) end
        BlizzardVFX[p.key] = v
    end

    -- 面板背景
    local pw, ph = 260, 20 + #debugParams * 22 + 30
    local px, py = l.x + l.w - pw - 10, l.y + 10
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, px, py, pw, ph, 6)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 180))
    nvgFill(nvg)
    nvgStrokeColor(nvg, nvgRGBA(100, 200, 255, 150))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 标题
    nvgFontFace(nvg, "dbg")
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(100, 220, 255, 255))
    nvgText(nvg, px + 8, py + 5, "Blizzard VFX [F8]")

    -- 参数列表
    local cy = py + 24
    for i, p in ipairs(debugParams) do
        local selected = (i == debugSelIdx)
        local val = BlizzardVFX[p.key]
        local txt
        if p.int then
            txt = string.format("%-10s %d", p.label, val)
        else
            txt = string.format("%-10s %.2f", p.label, val)
        end

        if selected then
            -- 选中行高亮背景
            nvgBeginPath(nvg)
            nvgRect(nvg, px + 4, cy - 1, pw - 8, 20)
            nvgFillColor(nvg, nvgRGBA(60, 140, 200, 80))
            nvgFill(nvg)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 255))
        else
            nvgFillColor(nvg, nvgRGBA(200, 200, 200, 200))
        end

        nvgFontSize(nvg, 13)
        nvgText(nvg, px + 10, cy + 2, txt)

        if selected then
            nvgFillColor(nvg, nvgRGBA(100, 200, 255, 200))
            nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgText(nvg, px + pw - 10, cy + 2, "< >")
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        end
        cy = cy + 22
    end

    -- 底部提示
    nvgFontSize(nvg, 11)
    nvgFillColor(nvg, nvgRGBA(150, 150, 150, 180))
    nvgText(nvg, px + 8, cy + 4, "Up/Down=选择  Left/Right=调节")
end

-- ============================================================================
-- 死亡覆盖层
-- ============================================================================

function BattleView:DrawDeathOverlay(nvg, l, bs)
    if not bs.isPlayerDead then return end

    -- 试炼结束后不显示死亡遮罩 (由结算面板接管)
    if bs.trialEnded then return end

    -- 半透明红色遮罩
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillColor(nvg, nvgRGBA(80, 0, 0, 140))
    nvgFill(nvg)

    -- 区分 BOSS 超时和普通死亡
    local isBossTimeout = bs.bossTimeout or false
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 28)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if isBossTimeout then
        nvgFillColor(nvg, nvgRGBA(255, 180, 40, 255))
        nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.4, "时间到!")
        nvgFontSize(nvg, 14)
        nvgFillColor(nvg, nvgRGBA(255, 220, 150, 220))
        nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.4 + 28, "未能在限时内击败 BOSS")
    else
        nvgFillColor(nvg, nvgRGBA(255, 60, 60, 255))
        nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.4, "你死了!")
    end

    -- 重试提示
    local timer = bs.playerDeadTimer or 0
    nvgFontSize(nvg, 14)
    nvgFillColor(nvg, nvgRGBA(255, 200, 150, 220))
    nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.4 + 50,
        string.format("%.1f秒后重试本关...", math.max(0, timer)))
end

-- ============================================================================
-- 紫焰弹道 (视觉投射物)
-- ============================================================================

function BattleView:DrawProjectiles(nvg, l, bs)
    -- 延迟加载弹道图片
    if not projImgHandle then
        projImgHandle = nvgCreateImage(nvg, "紫焰弹_20260305190228.png", 0)
    end

    -- 特效等级: 跳过部分弹道渲染 (伤害不受影响)
    local Settings = require("ui.Settings")
    local fxLv = Settings.GetFxLevel()
    local skipTrail = fxLv >= 2

    -- 非常弱: 每秒最多渲染10个弹道 (每帧预算 = 10/60 ≈ 0.17)
    -- 减弱: 每3个画1个
    self._projFrame = (self._projFrame or 0) + 1
    local total = #bs.projectiles
    local maxPerFrame = 0  -- 0 = 不限制
    if fxLv == 3 and total > 0 then
        -- 每秒10个, 假设60fps -> 每帧~0.17个, 用累加器保证均匀
        self._projBudget = (self._projBudget or 0) + 10 / 60
        maxPerFrame = math.floor(self._projBudget)
        self._projBudget = self._projBudget - maxPerFrame
        if maxPerFrame <= 0 then return end
    end
    local skipMod = (fxLv == 2) and 3 or 0
    local drawnCount = 0

    local projCullMargin = 30
    for idx, proj in ipairs(bs.projectiles) do
        -- 视口外剔除
        local sx = l.x + proj.x
        local sy = l.y + proj.y
        if sx < l.x - projCullMargin or sx > l.x + l.w + projCullMargin
            or sy < l.y - projCullMargin or sy > l.y + l.h + projCullMargin then
            goto continue_proj
        end
        -- 减弱: 按索引跳过
        if skipMod > 0 and (idx % skipMod) ~= 1 then
            goto continue_proj
        end
        -- 非常弱: 帧预算限制
        if maxPerFrame > 0 then
            drawnCount = drawnCount + 1
            if drawnCount > maxPerFrame then
                goto continue_proj
            end
        end
        local size = proj.isCrit and 28 or 20

        -- 延迟加载拖尾图片
        if not trailImgHandle then
            trailImgHandle = nvgCreateImage(nvg, "Textures/purple_trail.png", 0)
        end

        -- 尾焰粒子 (从旧到新逐渐变亮，使用图片) — 减弱以上关闭
        if skipTrail then goto skip_proj_trail end
        for _, t in ipairs(proj.trail) do
            if t.alpha > 0.05 then
                local tx = l.x + t.x + t.offsetX
                local ty = l.y + t.y + t.offsetY
                local ts = size * t.scale

                -- 拖尾图片粒子
                if trailImgHandle and trailImgHandle > 0 then
                    local half = ts * 0.5
                    local tp = nvgImagePattern(nvg, tx - half, ty - half, ts, ts, 0, trailImgHandle, t.alpha * 0.7)
                    nvgBeginPath(nvg)
                    nvgRect(nvg, tx - half, ty - half, ts, ts)
                    nvgFillPaint(nvg, tp)
                    nvgFill(nvg)
                end
            end
        end
        ::skip_proj_trail::

        -- 弹体图片 (区分九头蛇火球 vs 紫焰弹)
        local isHydraFb = proj.source == "hydra_fireball"
        if isHydraFb then
            -- 延迟加载火球图片
            if not hydraFbImgHandle then
                hydraFbImgHandle = nvgCreateImage(nvg, "image/hydra_fireball_20260410152201.png", 0)
            end
            if hydraFbImgHandle and hydraFbImgHandle > 0 then
                local fbSize = 20
                local half = fbSize * 0.5
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - half, sy - half, fbSize, fbSize)
                local imgPaint = nvgImagePattern(nvg, sx - half, sy - half, fbSize, fbSize, 0, hydraFbImgHandle, 1)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
            end
            -- 火球光晕
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, 12)
            nvgFillColor(nvg, nvgRGBA(255, 140, 30, 40))
            nvgFill(nvg)
        else
            if projImgHandle and projImgHandle >= 0 then
                local half = size * 0.5
                nvgBeginPath(nvg)
                nvgRect(nvg, sx - half, sy - half, size, size)
                local imgPaint = nvgImagePattern(nvg, sx - half, sy - half, size, size, 0, projImgHandle, 1)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
            end
            -- 弹体外层光晕
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, size * 0.7)
            nvgFillColor(nvg, proj.isCrit and nvgRGBA(255, 150, 255, 35) or nvgRGBA(180, 100, 255, 25))
            nvgFill(nvg)
        end
        ::continue_proj::
    end
end

-- ============================================================================
-- 碎裂弹体 (物理弹体 + 尾迹)
-- ============================================================================

function BattleView:DrawBullets(nvg, l, bs)
    -- 特效等级: 跳过部分弹体渲染 (伤害不受影响)
    local Settings = require("ui.Settings")
    local fxLv = Settings.GetFxLevel()
    local skipTrail = fxLv >= 2

    -- 非常弱: 每秒最多渲染10个碎裂弹 (帧预算累加器)
    local total = #bs.bullets
    local maxPerFrame = 0
    if fxLv == 3 and total > 0 then
        self._bulletBudget = (self._bulletBudget or 0) + 10 / 60
        maxPerFrame = math.floor(self._bulletBudget)
        self._bulletBudget = self._bulletBudget - maxPerFrame
        if maxPerFrame <= 0 then return end
    end
    local skipMod = (fxLv == 2) and 3 or 0
    local drawnCount = 0

    local bulletCullMargin = 20
    for idx, b in ipairs(bs.bullets) do
        -- 视口外剔除
        local sx = l.x + b.x
        local sy = l.y + b.y
        if sx < l.x - bulletCullMargin or sx > l.x + l.w + bulletCullMargin
            or sy < l.y - bulletCullMargin or sy > l.y + l.h + bulletCullMargin then
            goto continue_bullet
        end
        -- 减弱: 按索引跳过渲染
        if skipMod > 0 and (idx % skipMod) ~= 1 then
            goto continue_bullet
        end
        -- 非常弱: 帧预算限制
        if maxPerFrame > 0 then
            drawnCount = drawnCount + 1
            if drawnCount > maxPerFrame then
                goto continue_bullet
            end
        end

        -- 尾迹渲染 (从旧到新逐渐变亮) — 减弱以上关闭
        if skipTrail then goto skip_trail end
        for _, t in ipairs(b.trail) do
            if t.alpha > 0.05 then
                local tx = l.x + t.x
                local ty = l.y + t.y
                local trailR = 3
                local a = math.floor(t.alpha * 180)
                if b.isSplit then
                    -- 分裂弹尾迹: 青绿色
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, tx, ty, trailR)
                    nvgFillColor(nvg, nvgRGBA(100, 255, 200, a))
                    nvgFill(nvg)
                else
                    -- 主弹尾迹: 紫色
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, tx, ty, trailR)
                    nvgFillColor(nvg, nvgRGBA(200, 120, 255, a))
                    nvgFill(nvg)
                end
            end
        end
        ::skip_trail::

        -- 弹体核心
        local radius = b.isSplit and 4 or 6
        if b.isSplit then
            -- 分裂弹: 青绿色核心 + 白芯
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius + 2)
            nvgFillColor(nvg, nvgRGBA(80, 220, 180, 60))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgFillColor(nvg, nvgRGBA(120, 255, 220, 220))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius * 0.4)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
            nvgFill(nvg)
        else
            -- 主弹: 紫色核心 + 光晕
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius + 3)
            nvgFillColor(nvg, nvgRGBA(160, 80, 255, 50))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius)
            nvgFillColor(nvg, nvgRGBA(200, 140, 255, 230))
            nvgFill(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, radius * 0.4)
            nvgFillColor(nvg, nvgRGBA(255, 220, 255, 220))
            nvgFill(nvg)

            -- 棱镜层数可视化: 高层数时外圈加亮
            if b.prismStacks and b.prismStacks > 0 then
                local glow = math.min(b.prismStacks * 30, 180)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, radius + 5)
                nvgStrokeWidth(nvg, 1.5)
                nvgStrokeColor(nvg, nvgRGBA(255, 200, 100, glow))
                nvgStroke(nvg)
            end
        end
        ::continue_bullet::
    end
end

-- ============================================================================
-- 冰晶碎片 (frost_shatter 技能产生的飞行冰晶)
-- ============================================================================

function BattleView:DrawFrostShards(nvg, l, bs)
    if not bs.frostShards then return end
    for _, s in ipairs(bs.frostShards) do
        local sx = l.x + s.x
        local sy = l.y + s.y
        local lifeRatio = s.life / 1.5
        local alpha = math.floor(220 * lifeRatio)

        -- 外圈光晕
        nvgBeginPath(nvg)
        nvgCircle(nvg, sx, sy, s.radius + 3)
        nvgFillColor(nvg, nvgRGBA(100, 200, 255, math.floor(40 * lifeRatio)))
        nvgFill(nvg)

        -- 冰晶核心 (菱形)
        local r = s.radius
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, sx, sy - r)
        nvgLineTo(nvg, sx + r * 0.6, sy)
        nvgLineTo(nvg, sx, sy + r)
        nvgLineTo(nvg, sx - r * 0.6, sy)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(160, 230, 255, alpha))
        nvgFill(nvg)

        -- 白芯
        nvgBeginPath(nvg)
        nvgCircle(nvg, sx, sy, r * 0.3)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, math.floor(200 * lifeRatio)))
        nvgFill(nvg)
    end
end

-- ============================================================================
-- 无尽试炼 HUD (左上角常驻信息)
-- ============================================================================

function BattleView:DrawTrialHUD(nvg, l, bs)
    if not EndlessTrial.IsActive() then return end

    local floor = EndlessTrial.GetFloor()
    local maxFloor = EndlessTrial.GetMaxFloor()

    -- 左上角半透明背景
    local px = l.x + 6
    local py = l.y + 6
    local pw = 100
    local ph = 36

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, px, py, pw, ph, 6)
    nvgFillColor(nvg, nvgRGBA(20, 10, 40, 180))
    nvgFill(nvg)
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, px, py, pw, ph, 6)
    nvgStrokeColor(nvg, nvgRGBA(180, 140, 255, 120))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 层数
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(nvg, nvgRGBA(220, 200, 255, 255))
    nvgText(nvg, px + 8, py + 4, "试炼 F" .. floor)

    -- 最高纪录
    nvgFontSize(nvg, 10)
    nvgFillColor(nvg, nvgRGBA(160, 140, 200, 200))
    nvgText(nvg, px + 8, py + 20, "最高: F" .. maxFloor)

    -- 抗性提示 (每5层轮换, 从模板基准值中找最低元素)
    local resistId = EndlessTrial.GetFloorResistId(floor)
    local resistBase = MonsterTemplates.Resists[resistId]
    local weakElem = nil
    if resistBase then
        local minVal = math.huge
        for elem, val in pairs(resistBase) do
            if val < minVal then minVal = val; weakElem = elem end
        end
        -- 均衡型(balanced)等全正模板不显示弱点
        if minVal >= 10 then weakElem = nil end
    end
    if weakElem then
        local elemNames = { fire = "火", ice = "冰", poison = "毒", arcane = "奥", water = "水", physical = "物理" }
        local elemColors = { fire = {255,100,50}, ice = {100,200,255}, poison = {100,220,80}, arcane = {180,100,255}, water = {60,140,255}, physical = {200,200,200} }
        local eName = elemNames[weakElem] or weakElem
        local eColor = elemColors[weakElem] or {255,255,255}
        nvgFontSize(nvg, 10)
        nvgFillColor(nvg, nvgRGBA(eColor[1], eColor[2], eColor[3], 220))
        nvgText(nvg, px + pw + 6, py + 6, "弱点:" .. eName)
    end
end

-- ============================================================================
-- 波次信息
-- ============================================================================

function BattleView:DrawWaveInfo(nvg, l, bs)
    local GameState = require("GameState")
    local GameMode  = require("GameMode")
    local StageConfig = require("StageConfig")
    local gs = GameState.stage

    if bs.waveAnnounce and bs.waveAnnounce > 0 then
        local alpha = math.floor(255 * math.min(1, bs.waveAnnounce))
        nvgFontFace(nvg, "sans")

        -- 特殊模式: 委托适配器渲染
        if GameMode.DrawWaveInfo(nvg, l, bs, alpha) then
            return
        end

        -- 章节默认
        local stageCfg, chapterCfg = StageConfig.GetStage(gs.chapter, gs.stage)
        local stageName = stageCfg and stageCfg.name or ""

        if bs.isBossWave then
            nvgFontSize(nvg, 22)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 60, 60, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32, "BOSS 来袭!")
            nvgFontSize(nvg, 14)
            nvgFillColor(nvg, nvgRGBA(255, 180, 80, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32 + 24, stageName)
        else
            nvgFontSize(nvg, 16)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 220, 150, alpha))
            nvgText(nvg, l.x + l.w / 2, l.y + l.h * 0.32, gs.chapter .. "-" .. gs.stage .. " " .. stageName)
        end
    end
end

-- ============================================================================
-- 主动技能 CD 图标 (战斗区上半区域, 右侧纵列)
-- ============================================================================

local skillIconHandles = {}  -- { skillId -> nvgImageHandle }

function BattleView:DrawSkillCooldowns(nvg, l, bs)
    local GameState = require("GameState")
    local Config    = require("Config")

    local p = bs.playerBattle
    if not p or not p.skillTimers then return end

    -- v3.0: 收集已装备的主动技能 (SkillTreeConfig 驱动)
    local activeSkills = GameState.GetEquippedSkillList()
    if #activeSkills == 0 then return end

    local cdMul = GameState.GetSkillCdMul()

    -- 布局: 右上角纵列, 位于战斗区上半部分
    local iconSize = 28
    local gap = 4
    local marginRight = 6
    local marginTop = 8
    local startX = l.x + l.w - marginRight - iconSize
    local startY = l.y + marginTop

    for i, entry in ipairs(activeSkills) do
        local skillCfg = entry.cfg
        local ix = startX
        local iy = startY + (i - 1) * (iconSize + gap)

        -- 不超过战斗区 50% 高度
        if iy + iconSize > l.y + l.h * 0.5 then break end

        local timer = p.skillTimers[entry.id] or 0
        local cd = skillCfg.cooldown or 0
        local maxCD = cd > 0 and cd * cdMul or 1
        local cdPct = math.max(0, math.min(1, timer / maxCD))  -- 1=满CD, 0=就绪
        local isReady = cdPct <= 0

        -- 图标背景 (暗色圆角方块)
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, ix, iy, iconSize, iconSize, 4)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, 140))
        nvgFill(nvg)

        -- 技能图标
        local iconPath = Config.SKILL_ICON_PATHS[skillCfg.id]
        if iconPath then
            if not skillIconHandles[skillCfg.id] then
                skillIconHandles[skillCfg.id] = nvgCreateImage(nvg, iconPath, 0)
            end
            local imgH = skillIconHandles[skillCfg.id]
            if imgH and imgH > 0 then
                local imgPaint = nvgImagePattern(nvg, ix, iy, iconSize, iconSize, 0, imgH, isReady and 1.0 or 0.5)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, ix, iy, iconSize, iconSize, 4)
                nvgFillPaint(nvg, imgPaint)
                nvgFill(nvg)
            end
        end

        -- CD 旋转黑色遮罩 (扇形从上方顺时针消退)
        if cdPct > 0 then
            local cx = ix + iconSize / 2
            local cy = iy + iconSize / 2
            local r  = iconSize / 2 + 1

            -- 用扇形遮罩: 从 12 点钟方向顺时针, 覆盖 cdPct 比例
            local startAngle = -math.pi / 2  -- 12 点钟方向
            local sweepAngle = cdPct * math.pi * 2  -- CD 比例对应的角度

            nvgBeginPath(nvg)
            nvgMoveTo(nvg, cx, cy)
            nvgArc(nvg, cx, cy, r, startAngle, startAngle + sweepAngle, NVG_CW)
            nvgClosePath(nvg)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 160))
            nvgFill(nvg)

            -- CD 剩余时间文字
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 10)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(255, 255, 255, 220))
            nvgText(nvg, cx, cy, string.format("%.0f", math.ceil(timer)))
        end

        -- 就绪时加发光边框
        if isReady then
            local time = bs.time or 0
            local pulse = 0.5 + math.sin(time * 4) * 0.3
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, ix - 1, iy - 1, iconSize + 2, iconSize + 2, 5)
            nvgStrokeColor(nvg, nvgRGBA(255, 220, 100, math.floor(200 * pulse)))
            nvgStrokeWidth(nvg, 1.5)
            nvgStroke(nvg)
        else
            -- CD 中淡色边框
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, ix, iy, iconSize, iconSize, 4)
            nvgStrokeColor(nvg, nvgRGBA(80, 80, 100, 120))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end
    end
end

-- ============================================================================
-- BOSS 限时倒计时
-- ============================================================================

function BattleView:DrawBossTimer(nvg, l, bs)
    if not bs.isBossWave or bs.bossTimer <= 0 then return end
    if bs.isPlayerDead then return end

    local timer = bs.bossTimer

    -- 找到Boss敌人
    local bossEnemy = nil
    for _, e in ipairs(bs.enemies) do
        if e.isBoss and not e.dead then
            bossEnemy = e
            break
        end
    end

    -- 倒计时位置: 快捷栏下方 (两行按钮各32px = 64px)
    local cx = l.x + l.w / 2
    local cy = l.y + 72

    -- 时间紧迫时变红闪烁
    local urgent = timer <= 10
    local r, g, b = 255, 220, 150
    if urgent then
        r, g, b = 255, 60, 60
        local blink = math.sin((bs.time or 0) * 8)
        if blink < 0 then r, g, b = 255, 120, 80 end
    elseif timer <= 20 then
        r, g, b = 255, 180, 80
    end

    -- 倒计时数字 (保留)
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 16)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg, nvgRGBA(r, g, b, 240))
    nvgText(nvg, cx, cy, string.format("⏱ %d", math.ceil(timer)))

    -- Boss血条 + 名字 (替代旧的时间进度条)
    if bossEnemy then
        local barW = l.w * 0.8
        local barH = 10
        local barX = cx - barW / 2
        local bossName = bossEnemy.name or "BOSS"
        local bc = bossEnemy.color or { 255, 80, 80 }

        -- Boss名字
        local nameY = cy + 13
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], 220))
        nvgText(nvg, cx, nameY, bossName)

        -- 血条
        local barY = nameY + 10

        if WorldBoss.active then
            -- ====== 世界Boss: 分层血条 ======
            local sessionDmg = DamageTracker.GetSessionDamage()
            local info = DamageTracker.GetLayerInfo(sessionDmg)
            local lc = info.color

            -- 检测击穿层变化,触发闪白动画
            if not self._bossLayerPrev then self._bossLayerPrev = 1 end
            if not self._bossLayerFlash then self._bossLayerFlash = 0 end
            if info.layer > self._bossLayerPrev then
                self._bossLayerFlash = 1.0  -- 击穿闪白
            end
            self._bossLayerPrev = info.layer
            local flashDt = 0
            if self._lastBossBarTime then
                flashDt = math.min((bs.time or 0) - self._lastBossBarTime, 0.1)
            end
            self._lastBossBarTime = bs.time or 0
            self._bossLayerFlash = math.max(0, self._bossLayerFlash - flashDt * 3.0)

            -- 血条背景
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 3)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 180))
            nvgFill(nvg)

            -- 当前层进度填充
            local fillW = barW * info.progress
            if fillW > 0 then
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, fillW, barH, 3)
                nvgFillColor(nvg, nvgRGBA(lc[1], lc[2], lc[3], 220))
                nvgFill(nvg)
            end

            -- 击穿闪白叠加
            if self._bossLayerFlash > 0.05 then
                local fa = math.floor(self._bossLayerFlash * 200)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW, barH, 3)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, fa))
                nvgFill(nvg)
            end

            -- 边框 (用层颜色)
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 3)
            nvgStrokeColor(nvg, nvgRGBA(lc[1], lc[2], lc[3], 120))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)

            -- 层数标签 (血条右侧)
            nvgFontSize(nvg, 9)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgFillColor(nvg, nvgRGBA(lc[1], lc[2], lc[3], 220))
            nvgText(nvg, barX + barW + 4, barY + barH / 2, "×" .. info.layer)
        else
            -- ====== 普通Boss: 原有 hp/maxHp 血条 ======
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 3)
            nvgFillColor(nvg, nvgRGBA(0, 0, 0, 180))
            nvgFill(nvg)

            local hpPct = math.max(0, math.min(1, bossEnemy.hp / (bossEnemy.maxHp or 1)))
            if hpPct > 0 then
                local hr, hg, hb
                if hpPct > 0.5 then
                    hr, hg, hb = 200, 60, 60
                elseif hpPct > 0.25 then
                    hr, hg, hb = 255, 160, 40
                else
                    hr, hg, hb = 255, 50, 50
                end
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW * hpPct, barH, 3)
                nvgFillColor(nvg, nvgRGBA(hr, hg, hb, 220))
                nvgFill(nvg)
            end

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 3)
            nvgStrokeColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], 80))
            nvgStrokeWidth(nvg, 1)
            nvgStroke(nvg)
        end
    end
end

-- ============================================================================
-- Boss 伤害累计 HUD (右上角)
-- ============================================================================

function BattleView:DrawBossDamageHUD(nvg, l, bs)
    if not bs.isBossWave then
        self._bossDmgTotal = nil
        self._bossDmgPulse = 0
        self._bossDmgFlow = nil
        self._lastBossHp = nil
        self._lastBossDmgTime = nil
        return
    end
    if bs.isPlayerDead then return end

    if not self._bossDmgFlow then self._bossDmgFlow = {} end
    if not self._bossDmgPulse then self._bossDmgPulse = 0 end

    -- 找Boss
    local bossEnemy = nil
    for _, e in ipairs(bs.enemies) do
        if e.isBoss and not e.dead then
            bossEnemy = e
            break
        end
    end
    if not bossEnemy then return end

    -- 计算帧间 dt
    local curTime = bs.time or 0
    local dt = 0
    if self._lastBossDmgTime then
        dt = math.min(curTime - self._lastBossDmgTime, 0.1)
    end
    self._lastBossDmgTime = curTime

    -- 追踪伤害增量
    local totalDmg
    if WorldBoss.active then
        totalDmg = WorldBoss.fightDamage or 0
    else
        totalDmg = math.max(0, (bossEnemy.maxHp or 1) - bossEnemy.hp)
    end

    if not self._bossDmgTotal then self._bossDmgTotal = totalDmg end
    local dmgDelta = totalDmg - self._bossDmgTotal
    if dmgDelta > 0 then
        self._bossDmgPulse = 1.0
        table.insert(self._bossDmgFlow, 1, { dmg = dmgDelta, age = 0 })
        if #self._bossDmgFlow > 6 then
            table.remove(self._bossDmgFlow)
        end
    end
    self._bossDmgTotal = totalDmg

    -- 衰减 pulse
    self._bossDmgPulse = math.max(0, (self._bossDmgPulse or 0) - dt * 2.5)

    -- 衰减 flow 条目
    for i = #self._bossDmgFlow, 1, -1 do
        self._bossDmgFlow[i].age = self._bossDmgFlow[i].age + dt
        if self._bossDmgFlow[i].age > 2.0 then
            table.remove(self._bossDmgFlow, i)
        end
    end

    -- 格式化数字 (统一调用 Utils.FormatNumber)
    local function FormatDmg(n)
        return Utils.FormatNumber(n)
    end

    -- ── 绘制累计总伤害 (右上角, pulse缩放) ──
    local rx = l.x + l.w - 8
    local ry = l.y + 12
    local pulse = self._bossDmgPulse or 0
    local scale = 1.0 + pulse * 0.3

    nvgFontFace(nvg, "sans")
    nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)

    -- 标签
    nvgFontSize(nvg, 9)
    nvgFillColor(nvg, nvgRGBA(255, 200, 150, 160))
    nvgText(nvg, rx, ry, "伤害")

    -- 数字 (pulse动画)
    local numY = ry + 14
    local fontSize = 16 * scale
    nvgFontSize(nvg, fontSize)
    local pulseAlpha = math.floor(255 * (0.8 + pulse * 0.2))

    if pulse > 0.1 then
        nvgFillColor(nvg, nvgRGBA(255, 255, 200, math.floor(pulse * 100)))
        nvgText(nvg, rx + 1, numY + 1, FormatDmg(totalDmg))
    end
    nvgFillColor(nvg, nvgRGBA(255, 220, 100, pulseAlpha))
    nvgText(nvg, rx, numY, FormatDmg(totalDmg))

    -- ── 绘制每次伤害流水 (+damage, 右侧渐隐) ──
    local flowY = numY + 18
    nvgFontSize(nvg, 10)
    for _, entry in ipairs(self._bossDmgFlow) do
        local alpha = math.floor(255 * math.max(0, 1.0 - entry.age / 2.0))
        local offsetX = -entry.age * 8
        nvgTextAlign(nvg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(255, 180, 80, alpha))
        nvgText(nvg, rx + offsetX, flowY, "+" .. FormatDmg(entry.dmg))
        flowY = flowY + 13
    end
end

-- ============================================================================
-- 待机模式
-- ============================================================================

function BattleView.SetIdleMode(enabled)
    idleMode_ = enabled
    if enabled then battleIdleMode_ = false end
end

function BattleView.IsIdleMode()
    return idleMode_
end

function BattleView.SetBattleIdleMode(enabled)
    battleIdleMode_ = enabled
    if enabled then idleMode_ = false end
end

function BattleView.IsBattleIdleMode()
    return battleIdleMode_
end

return BattleView
