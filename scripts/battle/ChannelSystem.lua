-- ============================================================================
-- battle/ChannelSystem.lua - 引导技能框架
--
-- 管理引导状态: 启动/逐段触发/打断/完成
-- 引导期间: 锁定普攻, 可选降低移速, 受击可打断(强化可免疫)
--
-- 调用链:
--   CombatCore.PlayerAttack → ChannelSystem.Start()
--   BattleSystem.Update     → ChannelSystem.Update()
--   DamagePlayer             → ChannelSystem.TryInterrupt()
--   StageManager.NextWave   → ChannelSystem.Reset()
-- ============================================================================

local GameState = require("GameState")
local ChannelSystem = {}

--- 当前引导状态 (nil = 未引导)
---@class ChannelState
---@field skillId string
---@field skillCfg table
---@field lv number
---@field bs table               -- BattleSystem 引用
---@field totalTicks number
---@field currentTick number     -- 已完成的段数
---@field tickInterval number    -- 每段间隔(秒)
---@field tickTimer number       -- 下一段倒计时
---@field target table|nil       -- 当前目标
---@field data table             -- 技能特有数据 (屏障累计等)
---@field canInterrupt boolean   -- 是否可被打断
---@field moveSpeedMul number    -- 引导期间移速倍率 (1.0=正常, 0=不动)
---@field onTick fun(cs: ChannelState, tick: number)
---@field onEnd fun(cs: ChannelState, completed: boolean)
local channelState_ = nil

--- 注册的引导技能处理器 { skillId = { onStart, onTick, onEnd } }
local handlers_ = {}

-- ============================================================================
-- 公开API
-- ============================================================================

--- 注册一个引导技能的处理器
---@param skillId string
---@param handler table { onStart(bs, cfg, lv, p) -> data, onTick(state, tick), onEnd(state, completed) }
function ChannelSystem.Register(skillId, handler)
    handlers_[skillId] = handler
end

--- 当前是否在引导中
---@return boolean
function ChannelSystem.IsChanneling()
    return channelState_ ~= nil
end

--- 获取当前引导状态 (用于渲染等)
---@return ChannelState|nil
function ChannelSystem.GetState()
    return channelState_
end

--- 启动引导
---@param bs table BattleSystem
---@param skillCfg table 技能配置
---@param lv number 技能等级
---@return boolean 是否成功启动
function ChannelSystem.Start(bs, skillCfg, lv)
    if channelState_ then return false end -- 已在引导中

    local id = skillCfg.id
    local handler = handlers_[id]
    if not handler then
        print("[ChannelSystem] No handler for " .. id .. ", fallback instant cast")
        return false
    end

    local p = bs.playerBattle
    local ticks = skillCfg.channelTicks or 4
    local interval = skillCfg.channelInterval or 0.5

    -- 调用技能特有的初始化, 获取技能数据和配置覆盖
    local data, opts = handler.onStart(bs, skillCfg, lv, p)
    if not data then return false end -- 初始化失败 (如无目标)

    opts = opts or {}

    channelState_ = {
        skillId = id,
        skillCfg = skillCfg,
        lv = lv,
        bs = bs,
        totalTicks = ticks,
        currentTick = 0,
        tickInterval = interval,
        tickTimer = 0, -- 第一段立即触发
        target = opts.target,
        data = data,
        canInterrupt = opts.canInterrupt ~= false, -- 默认可打断
        moveSpeedMul = opts.moveSpeedMul or 0.3,   -- 默认引导时30%移速
        onTick = handler.onTick,
        onEnd = handler.onEnd,
    }

    return true
end

--- 每帧更新 (由 BattleSystem.Update 在 PlayerAI.Update 之前调用)
---@param dt number
---@return boolean isChanneling 是否仍在引导中
function ChannelSystem.Update(dt)
    if not channelState_ then return false end

    local cs = channelState_

    -- 目标死亡时尝试切换目标
    if cs.target and cs.target.dead then
        local H = require("battle.skills.Helpers")
        local newTarget = H.FindNearestEnemy(cs.bs.enemies, cs.bs.playerBattle.x, cs.bs.playerBattle.y, 9999)
        if newTarget then
            cs.target = newTarget
        else
            -- 没有存活敌人, 结束引导
            ChannelSystem._Finish(false)
            return false
        end
    end

    -- 段计时
    cs.tickTimer = cs.tickTimer - dt
    if cs.tickTimer <= 0 then
        cs.currentTick = cs.currentTick + 1

        -- 触发当前段
        if cs.onTick then
            cs.onTick(cs, cs.currentTick)
        end

        -- 检查是否完成所有段
        if cs.currentTick >= cs.totalTicks then
            ChannelSystem._Finish(true)
            return false
        end

        -- 重置下一段计时
        cs.tickTimer = cs.tickInterval
    end

    return true
end

--- 获取引导期间移速倍率 (由 PlayerAI 使用)
---@return number 1.0 = 正常, 0 = 不动
function ChannelSystem.GetMoveSpeedMul()
    if not channelState_ then return 1.0 end
    return channelState_.moveSpeedMul
end

--- 尝试打断引导 (由 DamagePlayer 调用)
---@return boolean 是否被打断
function ChannelSystem.TryInterrupt()
    if not channelState_ then return false end
    if not channelState_.canInterrupt then return false end

    ChannelSystem._Finish(false)
    return true
end

--- 强制重置 (波次切换时)
function ChannelSystem.Reset()
    if channelState_ then
        -- 静默结束, 不触发 onEnd (波次重置不算正常结束)
        channelState_ = nil
    end
end

-- ============================================================================
-- 内部
-- ============================================================================

--- 完成或中断引导
---@param completed boolean 是否完成所有段
function ChannelSystem._Finish(completed)
    if not channelState_ then return end
    local cs = channelState_
    channelState_ = nil -- 先清状态, 防止 onEnd 中再次触发

    if cs.onEnd then
        cs.onEnd(cs, completed)
    end
end

return ChannelSystem
