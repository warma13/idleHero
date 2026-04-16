-- ============================================================================
-- ui/SkillTreeLayout.lua - D4 风格垂直分支树布局算法
-- 中央脊柱 + 左右分支 + 增强卫星
-- ============================================================================

local SkillTreeConfig = require("SkillTreeConfig")
local GameState = require("GameState")

local Layout = {}

-- ============================================================================
-- 布局常量
-- ============================================================================

local CANVAS_W        = 640     -- 画布宽度
local TIER_SPACING_Y  = 140     -- 层间距 (紧凑)
local TIER_START_Y    = 60      -- 第一层 Y 起点
local BRANCH_OFFSET_X = 110     -- 左右分支偏移
local INTRA_OFFSET_Y  = 48      -- 同侧多技能纵向微调
local NODE_SIZE       = 38      -- 技能节点尺寸
local ENH_SIZE        = 20      -- 增强节点尺寸
local SAT_RADIUS      = 34      -- 增强卫星距父中心距离
local SAT_ARC_SPAN    = 1.2     -- 卫星弧度范围 (弧度)
local GATE_RADIUS     = 16      -- 门槛节点半径
local SPINE_X         = CANVAS_W / 2  -- 脊柱 X 坐标

-- ============================================================================
-- 分支分配表: 每个主动技能分配到左(-1)或右(+1)
-- 按元素: 火=左, 冰=右, 雷=交替
-- ============================================================================

local BRANCH_ASSIGN = {
    -- T1 基础 (4个)
    fire_bolt      = -1,   -- 火 → 左
    frost_bolt     =  1,   -- 冰 → 右
    spark          = -1,   -- 雷 → 左
    arcane_strike  =  1,   -- 火(但第4个) → 右

    -- T2 核心 (5个)
    fireball       = -1,   -- 火 → 左
    incinerate     = -1,   -- 火 → 左
    ice_shards     =  1,   -- 冰 → 右
    charged_bolts  =  1,   -- 雷 → 右
    chain_lightning = -1,  -- 雷 → 左 (平衡)

    -- T3 防御 (4个)
    flame_shield   = -1,   -- 火 → 左
    ice_armor      =  1,   -- 冰 → 右
    frost_nova     =  1,   -- 冰 → 右
    teleport       = -1,   -- 雷 → 左

    -- T4 精通 (4个)
    hydra          = -1,   -- 火 → 左
    blizzard       =  1,   -- 冰 → 右
    lightning_spear = -1,  -- 雷 → 左
    firewall       =  1,   -- 火 → 右 (平衡)

    -- T5 高阶 (4个)
    fire_storm     = -1,   -- 火 → 左
    frozen_orb     =  1,   -- 冰 → 右
    thunderstorm   = -1,   -- 雷 → 左
    energy_pulse   =  1,   -- 雷 → 右

    -- T6 终极 (3个)
    meteor         = -1,   -- 火 → 左
    deep_freeze    =  1,   -- 冰 → 右
    thunder_storm  = -1,   -- 雷 → 左

    -- T7 关键被动 (7个, 交替)
    kp_combustion      = -1,
    kp_avalanche       =  1,
    kp_overcharge      = -1,
    kp_esu_blessing    =  1,
    kp_align_elements  = -1,
    kp_shatter         =  1,
    kp_vyr_mastery     = -1,
}

-- ============================================================================
-- Build() — 计算所有节点坐标, 返回布局数据
-- ============================================================================

---@return table layout { nodes, enhNodes, gates, canvasW, canvasH, SPINE_X }
function Layout.Build()
    local nodes    = {}  -- [skillId] = { x, y, tier, side, skill }
    local enhNodes = {}  -- [enhId]   = { x, y, parentId, lineIdx, nodeIdx, enh }
    local gates    = {}  -- [tierIdx] = { x, y, gate, tierIdx }

    -- 按层分组
    local tierSkills = {}
    for t = 1, 7 do tierSkills[t] = {} end
    for _, sk in ipairs(SkillTreeConfig.SKILLS) do
        if sk.tier and tierSkills[sk.tier] then
            tierSkills[sk.tier][#tierSkills[sk.tier] + 1] = sk
        end
    end

    -- 为每层生成技能节点坐标
    for t = 1, 7 do
        local skills = tierSkills[t]
        local tierY = TIER_START_Y + (t - 1) * TIER_SPACING_Y

        -- 分左右两组
        local leftSkills  = {}
        local rightSkills = {}
        for _, sk in ipairs(skills) do
            local side = BRANCH_ASSIGN[sk.id] or -1
            if side < 0 then
                leftSkills[#leftSkills + 1] = sk
            else
                rightSkills[#rightSkills + 1] = sk
            end
        end

        -- 放置左侧技能 (从脊柱向左偏移)
        local function placeGroup(group, side)
            local count = #group
            if count == 0 then return end
            local baseX = SPINE_X + side * BRANCH_OFFSET_X
            -- 多个技能时纵向微调
            local totalHeight = (count - 1) * INTRA_OFFSET_Y
            local startY = tierY - totalHeight / 2
            for i, sk in ipairs(group) do
                local nx = baseX
                local ny = startY + (i - 1) * INTRA_OFFSET_Y
                -- 第二列偏移 (3个以上时内外交错)
                if count >= 3 then
                    local offset = (i % 2 == 0) and (side * 30) or 0
                    nx = nx + offset
                end
                nodes[sk.id] = {
                    x = nx, y = ny,
                    tier = t, side = side, skill = sk,
                }
            end
        end

        placeGroup(leftSkills, -1)
        placeGroup(rightSkills, 1)
    end

    -- 生成增强卫星节点坐标 (树形布局: 根节点→子节点 Y 形分叉)
    local ENH_BRANCH_X = SAT_RADIUS        -- 根节点到父技能的水平距离
    local ENH_CHILD_X  = SAT_RADIUS * 0.8  -- 子节点到前置节点的水平距离
    local ENH_CHILD_Y  = ENH_SIZE + 6      -- 子节点 Y 形分叉的纵向偏移

    for _, sk in ipairs(SkillTreeConfig.SKILLS) do
        if not sk.enhances then goto continue_skill end
        local parentPos = nodes[sk.id]
        if not parentPos then goto continue_skill end

        local branch = BRANCH_ASSIGN[sk.id] or 0
        local sideDir = branch ~= 0 and branch or -1

        -- 收集所有增强节点，按 line 分类
        local rootLines = {}     -- 无 requires 的 line: { {line, lineIdx}, ... }
        local childLines = {}    -- 有 requires 的 line: { {line, lineIdx, requires}, ... }
        for lineIdx, line in ipairs(sk.enhances) do
            if line.requires then
                childLines[#childLines + 1] = { line = line, lineIdx = lineIdx, requires = line.requires }
            else
                rootLines[#rootLines + 1] = { line = line, lineIdx = lineIdx }
            end
        end

        -- 检测"隐式Y形": 无 requires 但结构为 [1个节点line] + [2个节点line]
        -- 此时把单节点 line 作为Y根，双节点 line 的2个节点作为Y分叉子节点
        local implicitYRoot = nil       -- 单节点 line 的那个节点
        local implicitYChildren = nil   -- 双节点 line 的2个节点
        if #rootLines >= 2 and #childLines == 0 then
            local singleLine, multiLine = nil, nil
            for _, rl in ipairs(rootLines) do
                if #rl.line == 1 and not singleLine then
                    singleLine = rl
                elseif #rl.line >= 2 and not multiLine then
                    multiLine = rl
                end
            end
            if singleLine and multiLine then
                implicitYRoot = { enh = singleLine.line[1], lineIdx = singleLine.lineIdx, nodeIdx = 1 }
                implicitYChildren = {}
                for ni, enh in ipairs(multiLine.line) do
                    implicitYChildren[#implicitYChildren + 1] = {
                        enh = enh, lineIdx = multiLine.lineIdx, nodeIdx = ni,
                    }
                end
            end
        end

        if implicitYRoot then
            -- 隐式Y形布局: 根节点 + 2个子节点Y分叉
            local rootEnh = implicitYRoot
            local ex = parentPos.x + sideDir * ENH_BRANCH_X
            local ey = parentPos.y
            enhNodes[rootEnh.enh.id] = {
                x = ex, y = ey,
                parentId = sk.id,
                lineIdx = rootEnh.lineIdx,
                nodeIdx = rootEnh.nodeIdx,
                enh = rootEnh.enh,
                isImplicitYRoot = true,
            }
            -- 子节点Y形分叉
            local childCount = #implicitYChildren
            local spreadStartY = -(childCount - 1) * ENH_CHILD_Y * 0.5
            for ci, info in ipairs(implicitYChildren) do
                local cex = ex + sideDir * ENH_CHILD_X
                local cey = ey + spreadStartY + (ci - 1) * ENH_CHILD_Y
                enhNodes[info.enh.id] = {
                    x = cex, y = cey,
                    parentId = sk.id,
                    lineIdx = info.lineIdx,
                    nodeIdx = info.nodeIdx,
                    enh = info.enh,
                    implicitYParent = rootEnh.enh.id,
                }
            end
        else
            -- 标准布局: 根节点纵向排列
            local rootCount = 0
            for _, rl in ipairs(rootLines) do
                rootCount = rootCount + #rl.line
            end

            local rootIdx = 0
            local rootStartY = -(rootCount - 1) * (ENH_SIZE + 4) * 0.5
            for _, rl in ipairs(rootLines) do
                for nodeIdx, enh in ipairs(rl.line) do
                    rootIdx = rootIdx + 1
                    local ex = parentPos.x + sideDir * ENH_BRANCH_X
                    local ey = parentPos.y + rootStartY + (rootIdx - 1) * (ENH_SIZE + 4)
                    enhNodes[enh.id] = {
                        x = ex, y = ey,
                        parentId = sk.id,
                        lineIdx = rl.lineIdx,
                        nodeIdx = nodeIdx,
                        enh = enh,
                    }
                end
            end

            -- 显式 requires 的子节点Y形分叉
            local childrenOf = {}
            for _, cl in ipairs(childLines) do
                local reqId = cl.requires
                if not childrenOf[reqId] then childrenOf[reqId] = {} end
                for nodeIdx, enh in ipairs(cl.line) do
                    childrenOf[reqId][#childrenOf[reqId] + 1] = {
                        enh = enh,
                        lineIdx = cl.lineIdx,
                        nodeIdx = nodeIdx,
                    }
                end
            end

            for reqId, children in pairs(childrenOf) do
                local reqPos = enhNodes[reqId]
                if not reqPos then goto continue_req end
                local childCount = #children
                local spreadStartY = -(childCount - 1) * ENH_CHILD_Y * 0.5
                for ci, info in ipairs(children) do
                    local ex = reqPos.x + sideDir * ENH_CHILD_X
                    local ey = reqPos.y + spreadStartY + (ci - 1) * ENH_CHILD_Y
                    enhNodes[info.enh.id] = {
                        x = ex, y = ey,
                        parentId = sk.id,
                        lineIdx = info.lineIdx,
                        nodeIdx = info.nodeIdx,
                        enh = info.enh,
                    }
                end
                ::continue_req::
            end
        end

        ::continue_skill::
    end

    -- 生成门槛节点 (层间脊柱上)
    for t = 2, 7 do
        local tier = SkillTreeConfig.TIERS[t]
        if tier then
            local prevY = TIER_START_Y + (t - 2) * TIER_SPACING_Y
            local curY  = TIER_START_Y + (t - 1) * TIER_SPACING_Y
            local gateY = (prevY + curY) / 2

            gates[t] = {
                x = SPINE_X, y = gateY,
                gate = tier.gate, tierIdx = t,
            }
        end
    end

    -- 计算画布高度
    local maxY = TIER_START_Y + 6 * TIER_SPACING_Y
    -- 考虑增强节点的额外空间
    for _, en in pairs(enhNodes) do
        if en.y + ENH_SIZE > maxY then
            maxY = en.y + ENH_SIZE
        end
    end
    local canvasH = maxY + 80  -- 底部边距

    return {
        nodes    = nodes,
        enhNodes = enhNodes,
        gates    = gates,
        canvasW  = CANVAS_W,
        canvasH  = canvasH,
        SPINE_X  = SPINE_X,
        NODE_SIZE = NODE_SIZE,
        ENH_SIZE  = ENH_SIZE,
        GATE_RADIUS = GATE_RADIUS,
        TIER_START_Y = TIER_START_Y,
        TIER_SPACING_Y = TIER_SPACING_Y,
    }
end

-- ============================================================================
-- GetNodeAt(x, y) — 画布坐标命中测试
-- ============================================================================

---@param layout table Build() 返回的布局数据
---@param cx number 画布空间 X
---@param cy number 画布空间 Y
---@return table|nil skill or enhance config, string|nil nodeType ("skill"|"enhance"|nil)
function Layout.GetNodeAt(layout, cx, cy)
    -- 先检查增强节点 (更小, 优先命中)
    local enhHitR = ENH_SIZE * 0.5 + 6  -- 扩大点击区
    for enhId, en in pairs(layout.enhNodes) do
        local dx = cx - en.x
        local dy = cy - en.y
        if dx * dx + dy * dy <= enhHitR * enhHitR then
            local cfg = SkillTreeConfig.SKILL_MAP[enhId]
            if cfg then return cfg, "enhance" end
        end
    end

    -- 再检查技能节点
    local nodeHitR = NODE_SIZE * 0.5 + 4
    for skillId, nd in pairs(layout.nodes) do
        local dx = cx - nd.x
        local dy = cy - nd.y
        if dx * dx + dy * dy <= nodeHitR * nodeHitR then
            return nd.skill, "skill"
        end
    end

    return nil, nil
end

-- 导出常量供 Canvas 使用
Layout.SPINE_X  = SPINE_X
Layout.CANVAS_W = CANVAS_W
Layout.NODE_SIZE = NODE_SIZE
Layout.ENH_SIZE  = ENH_SIZE
Layout.GATE_RADIUS = GATE_RADIUS

return Layout
