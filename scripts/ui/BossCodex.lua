-- ============================================================================
-- ui/BossCodex.lua - Boss 图鉴 (全屏覆盖，章节Boss/世界Boss分栏)
-- ============================================================================

local UI          = require("urhox-libs/UI")
local Widget      = require("urhox-libs/UI/Core/Widget")
local StageConfig = require("StageConfig")
local GameState   = require("GameState")
local WorldBoss   = require("WorldBoss")

local BossCodex = {}

---@type Widget
local overlay_     = nil
---@type Widget
local overlayRoot_ = nil
local currentTab_  = "chapter"  -- "chapter" | "world"

-- ============================================================================
-- Boss 图片 NanoVG Widget (复用 WorldBossPanel 的渲染模式)
-- ============================================================================

---@class CodexBossIcon : Widget
local CodexBossIcon = Widget:Extend("CodexBossIcon")

function CodexBossIcon:Init(props)
    Widget.Init(self, props)
    self._imgHandle = nil
end

function CodexBossIcon:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end

    local locked = self.props.locked
    local bc = self.props.borderColor or { 150, 150, 150 }
    local radius = math.min(l.w, l.h) / 2

    -- 背景圆
    nvgBeginPath(nvg)
    nvgCircle(nvg, l.x + l.w / 2, l.y + l.h / 2, radius)
    if locked then
        nvgFillColor(nvg, nvgRGBA(40, 40, 50, 200))
    else
        nvgFillColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], 40))
    end
    nvgFill(nvg)

    if not locked and not self._imgHandle and self.props.imageSrc then
        self._imgHandle = nvgCreateImage(nvg, self.props.imageSrc, 0)
    end

    if not locked and self._imgHandle and self._imgHandle > 0 then
        local imgPaint = nvgImagePattern(nvg, l.x, l.y, l.w, l.h, 0, self._imgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgCircle(nvg, l.x + l.w / 2, l.y + l.h / 2, radius - 1)
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    else
        -- 锁定或无图 fallback
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, locked and 16 or 12)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg, nvgRGBA(120, 120, 140, locked and 120 or 200))
        nvgText(nvg, l.x + l.w / 2, l.y + l.h / 2, locked and "?" or "BOSS")
    end

    -- 边框
    nvgBeginPath(nvg)
    nvgCircle(nvg, l.x + l.w / 2, l.y + l.h / 2, radius)
    local ba = locked and 60 or 180
    nvgStrokeColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], ba))
    nvgStrokeWidth(nvg, locked and 1 or 1.5)
    nvgStroke(nvg)
end

-- ============================================================================
-- 数据收集
-- ============================================================================

--- 收集章节Boss列表
local function CollectChapterBosses()
    local bosses = {}
    local maxCh = GameState.records.maxChapter or 1
    local maxSt = GameState.records.maxStage or 1
    local totalChapters = StageConfig.GetChapterCount()

    for ch = 1, totalChapters do
        local chapter = StageConfig.CHAPTERS[ch]
        if not chapter then break end
        for st = 1, #chapter.stages do
            local stage = chapter.stages[st]
            if stage.isBoss then
                -- 从 waves 中找 boss monster id
                local bossId = nil
                for _, wave in ipairs(stage.waves) do
                    for _, m in ipairs(wave.monsters) do
                        local mobDef = StageConfig.MONSTERS[m.id]
                        if mobDef and mobDef.isBoss then
                            bossId = m.id
                            break
                        end
                    end
                    if bossId then break end
                end

                local mobDef = bossId and StageConfig.MONSTERS[bossId] or nil
                local encountered = (ch < maxCh) or (ch == maxCh and st <= maxSt)
                table.insert(bosses, {
                    chapterIdx  = ch,
                    stageIdx    = st,
                    chapterName = chapter.name,
                    stageName   = stage.name,
                    mobId       = bossId,
                    name        = mobDef and mobDef.name or stage.name,
                    hp          = mobDef and mobDef.hp or 0,
                    atk         = mobDef and mobDef.atk or 0,
                    def         = mobDef and mobDef.def or 0,
                    element     = mobDef and mobDef.element or "physical",
                    image       = mobDef and mobDef.image or nil,
                    color       = mobDef and mobDef.color or { 150, 150, 150 },
                    encountered = encountered,
                })
            end
        end
    end
    return bosses
end

--- 收集世界Boss列表 (BOSS_ROSTER)
local function CollectWorldBosses()
    -- 世界Boss都已公开(轮换制, 玩家可见所有)
    local bosses = {}
    local currentBoss = WorldBoss.GetCurrentBoss()
    -- 通过内部访问 BOSS_ROSTER
    -- WorldBoss 模块没有直接暴露 roster，我们通过 GetCurrentBoss + season 推算
    -- 但这里我们直接读取 4 个固定 Boss
    local roster = {
        { name = "深渊领主·莫格拉斯", element = "fire",   color = { 255, 100, 30 },  image = "Textures/mobs/boss_fire_world.png",   desc = "来自炼狱深渊的火焰领主，掌控着毁灭之焰。他的每一次攻击都带着灼热的怒火，能在瞬间将一切化为灰烬。" },
        { name = "冰霜巨龙·霜息",     element = "ice",    color = { 80, 160, 255 },  image = "Textures/mobs/boss_ice_world.png",    desc = "远古冰龙的后裔，沉睡万年后再度苏醒。它的吐息能冻结一切生命，霜之领域所到之处万物凋零。" },
        { name = "剧毒女皇·薇诺莎",   element = "poison", color = { 120, 220, 60 },  image = "Textures/mobs/boss_poison_world.png", desc = "丛林深处的毒雾女王，操纵着致命的瘴气。她的毒素可以腐蚀最坚硬的铠甲，无人能在她的领域中幸存。" },
        { name = "奥术魔导·星辰之主", element = "arcane", color = { 180, 100, 255 }, image = "Textures/mobs/boss_arcane_world.png",  desc = "精通奥术的远古魔导，驾驭着星辰之力。他能撕裂空间、操控时间，是最神秘也最危险的世界Boss。" },
    }
    for i, r in ipairs(roster) do
        local isCurrent = (currentBoss and currentBoss.name == r.name)
        table.insert(bosses, {
            name      = r.name,
            element   = r.element,
            color     = r.color,
            image     = r.image,
            desc      = r.desc,
            isCurrent = isCurrent,
        })
    end
    return bosses
end

-- ============================================================================
-- 元素颜色 / 翻译
-- ============================================================================

local ELEM_NAMES = {
    fire = "火", ice = "冰", poison = "毒", arcane = "奥术",
    physical = "物理", water = "水", earth = "地",
}

local ELEM_COLORS = {
    fire    = { 255, 120, 40 },
    ice     = { 100, 180, 255 },
    poison  = { 120, 220, 60 },
    arcane  = { 180, 120, 255 },
    physical = { 200, 200, 200 },
    water   = { 60, 140, 220 },
    earth   = { 180, 140, 80 },
}

-- ============================================================================
-- 构建 UI
-- ============================================================================

function BossCodex.Build()
    if overlay_ then overlay_:Destroy() end

    local chapterBosses = CollectChapterBosses()
    local worldBosses   = CollectWorldBosses()

    -- 选中 Boss 详情
    local selectedBoss = nil

    -- Tab 按钮样式
    local function TabBtn(label, tabId)
        local isActive = (currentTab_ == tabId)
        return UI.Panel {
            flex = 1, height = 30,
            backgroundColor = isActive and { 60, 70, 100, 255 } or { 35, 40, 55, 200 },
            borderRadius = 6,
            justifyContent = "center", alignItems = "center",
            onClick = function()
                currentTab_ = tabId
                BossCodex.Build()
            end,
            children = {
                UI.Label {
                    text = label,
                    fontSize = 13,
                    fontColor = isActive and { 255, 255, 255, 255 } or { 150, 155, 170, 200 },
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end

    -- Boss 卡片
    local function BossCard(boss, isWorld)
        local locked = (not isWorld) and (not boss.encountered)
        local bc = locked and { 80, 80, 100 } or (boss.color or { 150, 150, 150 })
        local nameText = locked and "???" or boss.name
        local isCurrent = isWorld and boss.isCurrent

        return UI.Panel {
            width = "100%", height = 56,
            flexDirection = "row", alignItems = "center", gap = 10,
            paddingHorizontal = 10,
            backgroundColor = isCurrent and { bc[1], bc[2], bc[3], 50 } or { 30, 35, 50, 200 },
            borderRadius = 8,
            borderWidth = isCurrent and 1.5 or 1,
            borderColor = isCurrent and { bc[1], bc[2], bc[3], 200 } or { bc[1], bc[2], bc[3], locked and 40 or 100 },
            marginBottom = 6,
            onClick = (not locked) and function()
                -- 弹出详情
                BossCodex.ShowDetail(boss, isWorld)
            end or nil,
            children = {
                -- Boss 图标
                CodexBossIcon {
                    width = 42, height = 42,
                    imageSrc = boss.image,
                    borderColor = bc,
                    locked = locked,
                },
                -- 信息区
                UI.Panel {
                    flex = 1, height = 42,
                    justifyContent = "center", gap = 2,
                    children = {
                        UI.Label {
                            text = nameText,
                            fontSize = 13,
                            fontColor = locked and { 100, 100, 120, 160 } or (isCurrent and { bc[1], bc[2], bc[3], 255 } or { 240, 240, 255, 240 }),
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = locked and "尚未遇见" or (
                                isWorld
                                    and (boss.isCurrent and "当前轮换中" or "已轮换")
                                    or string.format("第%d章 · %s", boss.chapterIdx, boss.chapterName)
                            ),
                            fontSize = 10,
                            fontColor = locked and { 90, 90, 110, 140 } or (isCurrent and { 100, 230, 100, 240 } or { 120, 120, 140, 160 }),
                        },
                    },
                },
                -- 元素标签
                (not locked) and UI.Panel {
                    height = 18, paddingHorizontal = 6,
                    backgroundColor = { (ELEM_COLORS[boss.element] or { 150, 150, 150 })[1],
                                         (ELEM_COLORS[boss.element] or { 150, 150, 150 })[2],
                                         (ELEM_COLORS[boss.element] or { 150, 150, 150 })[3], 60 },
                    borderRadius = 9,
                    justifyContent = "center", alignItems = "center",
                    children = {
                        UI.Label {
                            text = ELEM_NAMES[boss.element] or boss.element,
                            fontSize = 10,
                            fontColor = { (ELEM_COLORS[boss.element] or { 200, 200, 200 })[1],
                                          (ELEM_COLORS[boss.element] or { 200, 200, 200 })[2],
                                          (ELEM_COLORS[boss.element] or { 200, 200, 200 })[3], 240 },
                        },
                    },
                } or nil,
            },
        }
    end

    -- Boss 列表
    local listChildren = {}
    if currentTab_ == "chapter" then
        for _, boss in ipairs(chapterBosses) do
            table.insert(listChildren, BossCard(boss, false))
        end
        if #listChildren == 0 then
            table.insert(listChildren, UI.Label {
                text = "暂无数据", fontSize = 12,
                fontColor = { 140, 140, 160, 160 }, textAlign = "center", width = "100%",
                marginTop = 20,
            })
        end
    else
        for _, boss in ipairs(worldBosses) do
            table.insert(listChildren, BossCard(boss, true))
        end
    end

    overlay_ = UI.Panel {
        id = "bossCodexOverlay",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self, x, y) end,  -- 拦截穿透
        children = {
            UI.Panel {
                width = "92%", maxWidth = 400, maxHeight = "85%",
                backgroundColor = { 22, 26, 38, 245 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { 80, 90, 120, 120 },
                flexDirection = "column",
                overflow = "hidden",
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%", height = 44,
                        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                        paddingHorizontal = 14,
                        backgroundColor = { 28, 32, 48, 255 },
                        children = {
                            UI.Label {
                                text = "Boss 图鉴",
                                fontSize = 16, fontWeight = "bold",
                                fontColor = { 220, 225, 240, 240 },
                            },
                            UI.Panel {
                                width = 28, height = 28,
                                backgroundColor = { 60, 60, 80, 180 },
                                borderRadius = 14,
                                justifyContent = "center", alignItems = "center",
                                onClick = function() BossCodex.Close() end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 14, fontColor = { 180, 180, 200, 220 } },
                                },
                            },
                        },
                    },
                    -- Tab 栏
                    UI.Panel {
                        width = "100%", height = 40,
                        flexDirection = "row", alignItems = "center", gap = 6,
                        paddingHorizontal = 10, paddingVertical = 5,
                        backgroundColor = { 25, 28, 42, 255 },
                        children = {
                            TabBtn("章节Boss", "chapter"),
                            TabBtn("世界Boss", "world"),
                        },
                    },
                    -- Boss 列表 (可滚动)
                    UI.ScrollView {
                        width = "100%", flex = 1,
                        paddingHorizontal = 10, paddingVertical = 8,
                        children = listChildren,
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end
end

-- ============================================================================
-- Boss 详情弹窗
-- ============================================================================

--- 从 MONSTERS 数据中提取 Boss 技能描述列表
local function GetBossSkillDescs(mobId)
    if not mobId then return {} end
    local mob = StageConfig.MONSTERS[mobId]
    if not mob then return {} end
    local descs = {}
    if mob.barrage then
        local elem = ELEM_NAMES[mob.barrage.element] or mob.barrage.element
        table.insert(descs, string.format("弹幕: 每%.0fs发射%d枚%s弹幕(×%.1f)", mob.barrage.interval, mob.barrage.count, elem, mob.barrage.dmgMul))
    end
    if mob.dragonBreath then
        local elem = ELEM_NAMES[mob.dragonBreath.element] or mob.dragonBreath.element
        table.insert(descs, string.format("龙息: 每%.0fs释放%s龙息(×%.1f)", mob.dragonBreath.interval, elem, mob.dragonBreath.dmgMul))
    end
    if mob.iceArmor then
        table.insert(descs, string.format("护甲: HP<%.0f%%时减伤%.0f%%(%ds)", mob.iceArmor.hpThreshold * 100, mob.iceArmor.dmgReduce * 100, mob.iceArmor.duration))
    end
    if mob.frozenField then
        table.insert(descs, string.format("领域: HP<%.0f%%时减速%.0f%%(%ds)", mob.frozenField.hpThreshold * 100, mob.frozenField.slowRate * 100, mob.frozenField.duration))
    end
    if mob.summon then
        table.insert(descs, string.format("召唤: 每%.0fs召唤%d只小怪", mob.summon.interval, mob.summon.count))
    end
    if mob.iceRegen then
        table.insert(descs, string.format("回血: HP<%.0f%%时每秒回复%.0f%%HP", mob.iceRegen.hpThreshold * 100, mob.iceRegen.regenPct * 100))
    end
    if mob.deathExplode then
        table.insert(descs, string.format("爆炸: 死亡时%s爆炸(×%.1f)", ELEM_NAMES[mob.deathExplode.element] or "", mob.deathExplode.dmgMul))
    end
    if mob.chainLightning then
        table.insert(descs, string.format("闪电: 弹射%d次(×%.1f)", mob.chainLightning.bounces, mob.chainLightning.dmgMul))
    end
    return descs
end

function BossCodex.ShowDetail(boss, isWorld)
    -- 关闭图鉴列表，打开详情
    if overlay_ then overlay_:Destroy() overlay_ = nil end

    local bc = boss.color or { 150, 150, 150 }
    local elemName = ELEM_NAMES[boss.element] or boss.element
    local elemColor = ELEM_COLORS[boss.element] or { 200, 200, 200 }

    -- 构建滚动内容
    local contentChildren = {}

    -- Boss 图标
    table.insert(contentChildren, UI.Panel {
        width = "100%", alignItems = "center",
        children = {
            CodexBossIcon {
                width = 64, height = 64,
                imageSrc = boss.image,
                borderColor = bc,
                locked = false,
            },
        },
    })

    -- Boss 名称
    table.insert(contentChildren, UI.Label {
        text = boss.name,
        fontSize = 15, fontWeight = "bold",
        fontColor = { bc[1], bc[2], bc[3], 240 },
        marginTop = 8, textAlign = "center", width = "100%",
    })

    -- 元素标签
    table.insert(contentChildren, UI.Panel {
        width = "100%", alignItems = "center", marginTop = 6,
        children = {
            UI.Panel {
                height = 20, paddingHorizontal = 8,
                backgroundColor = { elemColor[1], elemColor[2], elemColor[3], 50 },
                borderRadius = 10,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = elemName, fontSize = 10,
                        fontColor = { elemColor[1], elemColor[2], elemColor[3], 230 },
                    },
                },
            },
        },
    })

    if isWorld then
        -- 世界Boss 描述
        table.insert(contentChildren, UI.Label {
            text = boss.desc or "神秘的世界Boss。",
            fontSize = 11, fontColor = { 180, 185, 200, 200 },
            width = "100%", marginTop = 10,
        })
        -- 当前轮换标记
        if boss.isCurrent then
            table.insert(contentChildren, UI.Panel {
                width = "100%", alignItems = "center", marginTop = 10,
                children = {
                    UI.Panel {
                        height = 24, paddingHorizontal = 12,
                        backgroundColor = { 80, 200, 80, 50 },
                        borderRadius = 12, borderWidth = 1, borderColor = { 80, 200, 80, 120 },
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Label { text = "当前轮换中", fontSize = 11, fontColor = { 100, 230, 100, 240 } },
                        },
                    },
                },
            })
        end
    else
        -- 章节Boss 属性表
        local function StatRow(label, value)
            return UI.Panel {
                width = "100%", height = 20,
                flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                children = {
                    UI.Label { text = label, fontSize = 11, fontColor = { 150, 155, 170, 200 } },
                    UI.Label { text = tostring(value), fontSize = 11, fontColor = { 220, 225, 240, 230 } },
                },
            }
        end
        table.insert(contentChildren, UI.Panel {
            width = "100%", marginTop = 10, flexDirection = "column", gap = 3,
            children = {
                StatRow("基础HP", boss.hp),
                StatRow("基础ATK", boss.atk),
                StatRow("基础DEF", boss.def),
                StatRow("元素", elemName),
                StatRow("章节", string.format("第%d章 · %s", boss.chapterIdx, boss.chapterName)),
                StatRow("关卡", boss.stageName),
            },
        })

        -- Boss 技能描述
        local skillDescs = GetBossSkillDescs(boss.mobId)
        if #skillDescs > 0 then
            table.insert(contentChildren, UI.Label {
                text = "技能", fontSize = 12, fontWeight = "bold",
                fontColor = { 220, 180, 100, 230 },
                width = "100%", marginTop = 10,
            })
            for _, desc in ipairs(skillDescs) do
                table.insert(contentChildren, UI.Label {
                    text = "· " .. desc,
                    fontSize = 10, fontColor = { 170, 175, 190, 200 },
                    width = "100%", marginTop = 2,
                })
            end
        end
    end

    -- 返回按钮
    table.insert(contentChildren, UI.Panel {
        width = "80%", height = 30, marginTop = 14, alignSelf = "center",
        backgroundColor = { 50, 55, 75, 220 },
        borderRadius = 8,
        justifyContent = "center", alignItems = "center",
        onClick = function()
            if overlay_ then overlay_:Destroy() overlay_ = nil end
            BossCodex.Build()
        end,
        children = {
            UI.Label { text = "返回图鉴", fontSize = 12, fontColor = { 200, 210, 230, 230 } },
        },
    })

    overlay_ = UI.Panel {
        id = "bossCodexDetail",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        onClick = function()
            -- 点击遮罩关闭
            if overlay_ then overlay_:Destroy() overlay_ = nil end
            BossCodex.Build()
        end,
        children = {
            UI.Panel {
                width = "85%", maxWidth = 360, maxHeight = "75%",
                backgroundColor = { 22, 26, 38, 245 },
                borderRadius = 12,
                borderWidth = 1, borderColor = { bc[1], bc[2], bc[3], 120 },
                flexDirection = "column",
                overflow = "hidden",
                onClick = function() end,  -- 阻止穿透到遮罩
                children = {
                    -- 标题栏 + X按钮
                    UI.Panel {
                        width = "100%", height = 36,
                        flexDirection = "row", alignItems = "center", justifyContent = "flex-end",
                        paddingHorizontal = 8,
                        children = {
                            UI.Panel {
                                width = 26, height = 26,
                                backgroundColor = { 60, 60, 80, 180 },
                                borderRadius = 13,
                                justifyContent = "center", alignItems = "center",
                                onClick = function()
                                    if overlay_ then overlay_:Destroy() overlay_ = nil end
                                    BossCodex.Build()
                                end,
                                children = {
                                    UI.Label { text = "✕", fontSize = 13, fontColor = { 180, 180, 200, 220 } },
                                },
                            },
                        },
                    },
                    -- 可滚动内容区
                    UI.ScrollView {
                        width = "100%", flex = 1,
                        paddingHorizontal = 16, paddingBottom = 16,
                        children = contentChildren,
                    },
                },
            },
        },
    }

    if overlayRoot_ then
        overlayRoot_:AddChild(overlay_)
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

function BossCodex.SetOverlayRoot(root)
    overlayRoot_ = root
end

function BossCodex.IsOpen()
    return overlay_ ~= nil
end

function BossCodex.Close()
    if overlay_ then
        overlay_:Destroy()
        overlay_ = nil
    end
end

function BossCodex.Open()
    if overlay_ then BossCodex.Close() end
    currentTab_ = "chapter"
    BossCodex.Build()
end

function BossCodex.Toggle()
    if overlay_ then
        BossCodex.Close()
    else
        BossCodex.Open()
    end
end

return BossCodex
