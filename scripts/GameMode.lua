-- ============================================================================
-- GameMode.lua - 游戏模式统一调度器
--
-- 用策略模式替代 battle/ 和 main.lua 中对各模式的直接 require 和
-- if/elseif 链. 新增游戏模式只需实现适配器接口并注册, 不用改其他文件.
--
-- 适配器接口 (所有方法可选, 未实现则走默认章节逻辑):
--
--   ── 生命周期 ──
--   :OnEnter()                     -> bool (进入模式, false=失败中止)
--   :OnExit()                      -> nil  (退出模式, 清理状态)
--
--   ── 战斗 (battle/ 层调用) ──
--   :BuildSpawnQueue()             -> queue (Spawner 兼容队列)
--   :GetBattleConfig()             -> { isBossWave, bossTimerMax, startTimerImmediately }
--   :OnEnemyKilled(bs, enemy)      -> handled (true=跳过默认逻辑)
--   :CheckWaveComplete(bs)         -> handled
--   :OnNextWave(bs)                -> handled
--   :OnDeath(bs)                   -> handled
--   :OnTimeout(bs)                 -> handled
--   :SkipNormalExpDrop()            -> bool
--   :IsTimerMode()                 -> bool (是否使用限时计时器)
--   :GetDisplayName()              -> string (顶栏显示)
--
--   ── 显示 (BattleView 层调用) ──
--   .background                    -> string|nil (背景图路径)
--   :DrawWaveInfo(nvg, l, bs, a)   -> nil  (波次信息渲染)
-- ============================================================================

local GameMode = {}

---@type table<string, table>
local adapters_ = {}

---@type string|nil
local activeName_ = nil

---@type function|nil
local onTransition_ = nil

-- ============================================================================
-- 注册
-- ============================================================================

--- 注册一个游戏模式适配器
---@param name string 模式标识 (如 "endlessTrial", "worldBoss", "abyss")
---@param adapter table 适配器对象, 需实现上述接口
function GameMode.Register(name, adapter)
    adapters_[name] = adapter
end

-- ============================================================================
-- 过渡回调
-- ============================================================================

--- 注册模式切换后的统一过渡回调 (BattleSystem.Init + RefreshStageInfo)
--- 只需调用一次, 通常在 main.lua BuildGameUI 中
---@param fn function
function GameMode.SetTransitionCallback(fn)
    onTransition_ = fn
end

-- ============================================================================
-- 统一切换
-- ============================================================================

--- 切换到指定模式 (完整流程: 退出旧模式 → 进入新模式 → 过渡回调)
---@param name string|nil nil=回到章节模式
---@return boolean success 切换是否成功 (新模式 OnEnter 返回 false 时失败)
function GameMode.SwitchTo(name)
    -- 1. 退出当前模式
    if activeName_ then
        local cur = adapters_[activeName_]
        if cur and cur.OnExit then
            cur:OnExit()
        end
        activeName_ = nil
    end

    -- 2. 进入新模式
    if name then
        local nxt = adapters_[name]
        if not nxt then
            print("[GameMode] WARNING: adapter '" .. name .. "' not registered")
            if onTransition_ then onTransition_() end
            return false
        end
        if nxt.OnEnter then
            local ok = nxt:OnEnter()
            if ok == false then
                -- 进入失败 (如次数用完), 回到章节
                if onTransition_ then onTransition_() end
                return false
            end
        end
        activeName_ = name
    end

    -- 3. 过渡回调
    if onTransition_ then onTransition_() end
    return true
end

--- 仅退出当前模式, 不触发过渡回调 (用于存档切换等销毁场景)
function GameMode.ExitCurrent()
    if activeName_ then
        local cur = adapters_[activeName_]
        if cur and cur.OnExit then
            cur:OnExit()
        end
        activeName_ = nil
    end
end

-- ============================================================================
-- 兼容: 直接激活/停用 (battle/ 内部、结算面板仍可用)
-- ============================================================================

--- 激活指定模式 (不调用 OnEnter, 适配尚未迁移的旧路径)
---@param name string|nil
function GameMode.Activate(name)
    activeName_ = name
end

--- 回到章节模式 (不调用 OnExit, 适配尚未迁移的旧路径)
function GameMode.Deactivate()
    activeName_ = nil
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 获取当前活跃的适配器 (章节模式返回 nil)
---@return table|nil adapter
function GameMode.GetActive()
    if activeName_ then
        return adapters_[activeName_]
    end
    return nil
end

--- 获取当前模式名
---@return string|nil
function GameMode.GetName()
    return activeName_
end

--- 检查是否在某个特定模式中
---@param name string
---@return boolean
function GameMode.Is(name)
    return activeName_ == name
end

--- 是否在任何特殊模式中 (非章节)
---@return boolean
function GameMode.IsAnyActive()
    return activeName_ ~= nil
end

-- ============================================================================
-- 显示层查询 (BattleView 调用)
-- ============================================================================

--- 获取当前模式的背景图路径 (nil = 使用章节背景)
---@return string|nil
function GameMode.GetBackground()
    if activeName_ then
        local a = adapters_[activeName_]
        return a and a.background or nil
    end
    return nil
end

--- 委托当前模式绘制波次信息 (nil = 使用章节默认)
---@return boolean handled true=已绘制, false=走默认
function GameMode.DrawWaveInfo(nvg, l, bs, alpha)
    if activeName_ then
        local a = adapters_[activeName_]
        if a and a.DrawWaveInfo then
            a:DrawWaveInfo(nvg, l, bs, alpha)
            return true
        end
    end
    return false
end

return GameMode
