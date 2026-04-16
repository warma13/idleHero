-- ============================================================================
-- DamageTracker.lua - 统一伤害统计模块
--
-- 设计:
--   1. 全局累计伤害 (所有模式通用)
--   2. 会话伤害 (世界Boss单次战斗等)
--   3. 实时 DPS (滑动窗口)
--   4. 独立于 Boss 生死状态,不受 hp 重算影响
-- ============================================================================

local DamageTracker = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

local totalDamage_   = 0       -- 全局累计伤害
local sessionDamage_ = 0       -- 当前会话伤害
local sessionActive_ = false   -- 会话是否进行中

-- 滑动窗口 DPS
local DPS_WINDOW     = 5.0     -- DPS 统计窗口 (秒)
local DPS_BUCKET_DUR = 0.5     -- 每个桶的时长 (秒)
local DPS_BUCKET_CNT = math.ceil(DPS_WINDOW / DPS_BUCKET_DUR)

local dpsBuckets_    = {}      -- { dmg, elapsed }
local currentBucket_ = { dmg = 0, elapsed = 0 }

-- ============================================================================
-- 核心 API
-- ============================================================================

--- 记录一次伤害
--- @param amount number 伤害数值
function DamageTracker.Record(amount)
    if not amount or amount <= 0 then return end

    totalDamage_ = totalDamage_ + amount

    if sessionActive_ then
        sessionDamage_ = sessionDamage_ + amount
    end

    -- 累加到当前桶
    currentBucket_.dmg = currentBucket_.dmg + amount
end

--- 每帧更新 (供 BattleSystem 调用,驱动 DPS 滑动窗口)
--- @param dt number 帧间隔
function DamageTracker.Update(dt)
    if dt <= 0 then return end

    currentBucket_.elapsed = currentBucket_.elapsed + dt

    -- 当前桶满了,推入队列
    if currentBucket_.elapsed >= DPS_BUCKET_DUR then
        table.insert(dpsBuckets_, { dmg = currentBucket_.dmg, elapsed = currentBucket_.elapsed })
        currentBucket_ = { dmg = 0, elapsed = 0 }

        -- 移除超出窗口的旧桶
        while #dpsBuckets_ > DPS_BUCKET_CNT do
            table.remove(dpsBuckets_, 1)
        end
    end
end

-- ============================================================================
-- 查询 API
-- ============================================================================

--- 获取全局累计伤害
--- @return number
function DamageTracker.GetTotal()
    return totalDamage_
end

--- 获取当前会话伤害
--- @return number
function DamageTracker.GetSessionDamage()
    return sessionDamage_
end

--- 获取实时 DPS (滑动窗口均值)
--- @return number
function DamageTracker.GetRealtimeDPS()
    local totalDmg = currentBucket_.dmg
    local totalTime = currentBucket_.elapsed

    for _, b in ipairs(dpsBuckets_) do
        totalDmg = totalDmg + b.dmg
        totalTime = totalTime + b.elapsed
    end

    if totalTime < 0.1 then return 0 end
    return math.floor(totalDmg / totalTime)
end

--- 会话是否活跃
--- @return boolean
function DamageTracker.IsSessionActive()
    return sessionActive_
end

-- ============================================================================
-- 会话管理
-- ============================================================================

--- 开始新会话 (世界Boss战斗开始时调用)
function DamageTracker.StartSession()
    sessionDamage_ = 0
    sessionActive_ = true
    -- 重置 DPS 窗口
    dpsBuckets_ = {}
    currentBucket_ = { dmg = 0, elapsed = 0 }
    print("[DamageTracker] Session started")
end

--- 结束会话,返回会话伤害
--- @return number sessionDamage 本次会话总伤害
function DamageTracker.EndSession()
    sessionActive_ = false
    local dmg = sessionDamage_
    print("[DamageTracker] Session ended, damage=" .. dmg)
    return dmg
end

--- 全部重置 (通常不需要)
function DamageTracker.Reset()
    totalDamage_ = 0
    sessionDamage_ = 0
    sessionActive_ = false
    dpsBuckets_ = {}
    currentBucket_ = { dmg = 0, elapsed = 0 }
end

-- ============================================================================
-- Boss 血条分层系统
--
-- 指数递增分层: layer_n_hp = BASE × RATIO^(n-1)
-- 累计击穿第 n 层所需总伤害: BASE × (RATIO^n - 1) / (RATIO - 1)
-- 从总伤害 D 反推当前层号: floor(log(D*(RATIO-1)/BASE + 1) / log(RATIO))
-- ============================================================================

local LAYER_BASE  = 100000   -- 第1层血量: 10万
local LAYER_RATIO = 1.5      -- 每层递增倍率

-- 颜色循环 (每5层一轮)
local LAYER_COLORS = {
    { 100, 220, 100 },   -- 绿色 (层 1-5)
    {  80, 160, 255 },   -- 蓝色 (层 6-10)
    { 180, 100, 255 },   -- 紫色 (层 11-15)
    { 255, 160,  40 },   -- 橙色 (层 16-20)
    { 255,  60,  60 },   -- 红色 (层 21-25)
}

--- 计算第 n 层的血量 (n 从 1 开始)
--- @param n number
--- @return number
local function LayerHP(n)
    return LAYER_BASE * (LAYER_RATIO ^ (n - 1))
end

--- 计算击穿前 n 层所需的累计伤害
--- @param n number
--- @return number
local function CumulativeDamage(n)
    if n <= 0 then return 0 end
    return LAYER_BASE * (LAYER_RATIO ^ n - 1) / (LAYER_RATIO - 1)
end

--- 根据累计伤害计算分层信息
--- @param totalDmg number 累计伤害
--- @return table { layer: number, progress: number(0-1), layerHp: number, layerDmg: number, color: table }
function DamageTracker.GetLayerInfo(totalDmg)
    if totalDmg <= 0 then
        return {
            layer    = 1,
            progress = 0,
            layerHp  = LayerHP(1),
            layerDmg = 0,
            color    = LAYER_COLORS[1],
        }
    end

    -- 反推已完整击穿的层数
    local ratio_m1 = LAYER_RATIO - 1
    local completedLayers = math.floor(
        math.log(totalDmg * ratio_m1 / LAYER_BASE + 1) / math.log(LAYER_RATIO)
    )

    local currentLayer = completedLayers + 1
    local prevCumDmg   = CumulativeDamage(completedLayers)
    local currentHP    = LayerHP(currentLayer)
    local dmgInLayer   = totalDmg - prevCumDmg
    local progress     = math.min(1, dmgInLayer / currentHP)

    -- 颜色: 每5层循环
    local colorIdx = ((currentLayer - 1) // 5) % #LAYER_COLORS + 1
    local color    = LAYER_COLORS[colorIdx]

    return {
        layer    = currentLayer,
        progress = progress,
        layerHp  = currentHP,
        layerDmg = dmgInLayer,
        color    = color,
    }
end

return DamageTracker
