# Skill: code-animation

> 为 2D 静态贴图/序列帧角色添加代码驱动的程序化动画，无需额外动画资源，仅通过 NanoVG 变换（缩放、位移、旋转、透明度）实现生动的角色表现力。

---

## 触发条件

MUST trigger when：

1. 用户要求给 2D 角色添加"代码动画"、"程序化动画"、"无骨骼动画"
2. 用户要求给静态贴图角色添加"呼吸"、"攻击反馈"、"受击后退"、"死亡动画"等表现
3. 用户使用 NanoVG 渲染 2D 精灵并希望增强视觉反馈
4. 角色只有静态图片或简单序列帧，没有骨骼/Spine 动画

---

## 核心概念

### 什么是"代码动画"

代码动画 = 不依赖动画文件，完全通过代码在每帧计算 **缩放 / 位移 / 旋转 / 透明度** 这四个变换参数，叠加到精灵渲染上，让静态贴图产生生动的动态效果。

### 架构模式

```
┌─────────────────────────────────────────┐
│  AI 逻辑层（BattleSystem / GameState）     │
│  ├─ 触发事件: 攻击、受击、死亡、出生        │
│  └─ 驱动计时器: atkFlash, hitFlash, etc.  │
└───────────────┬─────────────────────────┘
                │ 每帧传递状态
                ▼
┌─────────────────────────────────────────┐
│  动画计算层（Anim 模块 / 渲染函数内）       │
│  ├─ 读取计时器 → 计算动画进度 (0→1)        │
│  ├─ 应用缓动函数 → 计算变换参数             │
│  └─ 输出: offsetX/Y, scaleX/Y,           │
│          rotation, alpha, flashWhite      │
└───────────────┬─────────────────────────┘
                │ 变换参数
                ▼
┌─────────────────────────────────────────┐
│  渲染层（NanoVG Draw 函数）                 │
│  ├─ nvgSave → Translate → Rotate →      │
│  │   Scale → Translate（锚点变换）         │
│  ├─ 绘制精灵                              │
│  ├─ [可选] 闪白/闪红叠加                   │
│  └─ nvgRestore                           │
└─────────────────────────────────────────┘
```

---

## 规则 1: 锚点必须在脚底

所有缩放和旋转变换的锚点 **必须设在角色脚底**，而不是中心。这样角色缩放时"脚踩地面"不动，头部和身体变化，视觉自然。

```lua
-- ✅ 正确：以脚底为锚点
local footY = drawCY + halfHeight * 0.5
nvgTranslate(nvg, drawCX, footY)      -- 1. 移到脚底
if rotation ~= 0 then
    nvgRotate(nvg, rotation)           -- 2. 旋转
end
nvgScale(nvg, scaleX, scaleY)          -- 3. 缩放
nvgTranslate(nvg, -drawCX, -footY)     -- 4. 移回原点

-- ❌ 错误：以中心为锚点（缩放时角色"悬浮"）
nvgTranslate(nvg, drawCX, drawCY)
nvgScale(nvg, scaleX, scaleY)
nvgTranslate(nvg, -drawCX, -drawCY)
```

**变换顺序**：Translate(到锚点) → Rotate → Scale → Translate(回原位) → 绘制

---

## 规则 2: 阴影独立于呼吸，但跟随死亡

阴影（脚底椭圆阴影）**不跟随**呼吸浮动偏移，否则阴影会随角色上下抖动（不自然）。但阴影 **需跟随** 死亡动画的缩放和透明度变化。

```lua
-- ✅ 正确
-- 阴影位置: 使用 pOffX（受击位移）但 NOT playerBob（呼吸浮动）
nvgEllipse(nvg, sx + pOffX, sy + halfH * 0.7,
           halfH * 0.45 * pSX,                      -- 跟随死亡缩放
           halfH * 0.13 * pSY)
nvgFillColor(nvg, nvgRGBA(0, 0, 0, floor(45 * pAlpha)))  -- 跟随死亡透明度

-- ❌ 错误：阴影跟随呼吸浮动
nvgEllipse(nvg, sx, sy + playerBob + halfH * 0.7, ...)   -- 阴影跟着晃
```

---

## 规则 3: 用计时器驱动，不用帧计数

所有动画通过**秒级计时器**驱动（`timer -= dt`），不用帧计数。这样动画速率与帧率无关。

```lua
-- ✅ 正确：基于时间的计时器
a.flashTimer = FLASH_DURATION  -- 触发时赋初值 (秒)
-- 每帧:
a.flashTimer = a.flashTimer - dt
local progress = 1.0 - (a.flashTimer / FLASH_DURATION)  -- 0→1

-- ❌ 错误：基于帧计数
a.flashFrames = 10
a.flashFrames = a.flashFrames - 1  -- 60fps 和 30fps 速度不同
```

---

## 规则 4: 缓动函数选择

不同动画效果需要不同的缓动曲线：

| 动画类型 | 缓动函数 | 公式 | 视觉效果 |
|---------|---------|------|---------|
| 受击后退 | **easeOut** | `1 - (1-t)^2` | 快速弹出，缓慢归位 |
| 死亡缩小 | **easeIn** | `t^2` | 慢启动，加速消失 |
| 出生弹跳 | **cubicEaseOut + overshoot** | `(1-(1-t)^3) * (1 + 0.2*sin(t*π))` | 弹出+微弹回 |
| 呼吸浮动 | **sin 波** | `sin(time * freq * 2π) * amp` | 周期循环 |
| Boss 脉冲 | **sin 波** | `sin(phase) * amp` | 缓慢胀缩 |

```lua
-- 常用缓动公式
local function easeOutQuad(t) return 1 - (1 - t) * (1 - t) end
local function easeInQuad(t) return t * t end
local function easeOutCubic(t) return 1 - (1 - t)^3 end
local function easeInOutSin(t) return math.sin(t * 3.14159) end  -- 0→1→0
```

---

## 规则 5: 死亡状态互斥

角色死亡时，**停止**呼吸浮动和攻击动画，**禁用**护盾/光环特效。死亡动画是排他的。

```lua
-- ✅ 正确
local isDead = bs.isPlayerDead

-- 呼吸只在活着时
local bob = 0
if not isDead then
    bob = math.sin(time * 1.0 * 2π) * 2.0
end

-- 攻击挤压只在活着时
if not isDead and flash > 0.05 then
    -- 计算攻击缩放...
end

-- 护盾只在活着时显示
if not isDead and hasShield then
    -- 绘制护盾...
end

-- 死亡固定为待机帧
if isDead then col = 0 end
```

---

## 规则 6: 闪白/闪红使用 4-Pass Blend

在 NanoVG 中实现"仅对精灵不透明像素叠色"的效果，需要 4 步混合操作：

```lua
if flashIntensity > 0 then
    nvgShapeAntiAlias(nvg, false)   -- 必须关闭 AA，避免边缘黑框

    -- Pass 1: 清除 alpha（保留 RGB）
    nvgGlobalCompositeBlendFuncSeparate(nvg,
        NVG_ZERO, NVG_ONE,     -- RGB: 保持 dst
        NVG_ZERO, NVG_ZERO)    -- Alpha: 清零
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 0))
    nvgFill(nvg)

    -- Pass 2: 重绘精灵建立 alpha 蒙版
    nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillPaint(nvg, imgPaint)
    nvgFill(nvg)

    -- Pass 3: 叠加颜色，仅 dstAlpha > 0 处生效
    nvgGlobalCompositeBlendFuncSeparate(nvg,
        NVG_DST_ALPHA, NVG_ONE,  -- RGB: src * dstA + dst
        NVG_ZERO, NVG_ONE)       -- Alpha: 保持
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    -- 闪白用白色，闪红用红色
    nvgFillColor(nvg, nvgRGBA(255, 255, 255, floor(255 * intensity)))
    -- nvgFillColor(nvg, nvgRGBA(255, 40, 40, floor(255 * intensity)))  -- 闪红
    nvgFill(nvg)

    -- Pass 4: 恢复 alpha
    nvgGlobalCompositeBlendFuncSeparate(nvg,
        NVG_ZERO, NVG_ONE,    -- RGB: 保持
        NVG_ONE, NVG_ONE)      -- Alpha: 恢复为 1
    nvgBeginPath(nvg)
    nvgRect(nvg, x, y, w, h)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 255))
    nvgFill(nvg)

    nvgShapeAntiAlias(nvg, true)
    nvgGlobalCompositeOperation(nvg, NVG_SOURCE_OVER)
end
```

**关键**：Pass 1 和 Pass 4 不能省略，否则会影响后续渲染的 alpha 通道。

---

## 规则 7: 怪物动画系统化（独立模块）

当怪物数量多时，应将动画逻辑抽成独立模块（如 `EnemyAnim.lua`），做到：

1. **零侵入**：仅在怪物实体上添加 `e.anim` 子表，不修改原有字段
2. **零分配**：复用模块级结果表，避免每帧 GC 压力
3. **事件驱动**：`OnHit(e)` / `OnAttack(e)` / `OnDeath(e)` 触发，`Update(dt)` 逐帧 tick
4. **随机初相位**：每个怪物呼吸相位随机，避免"齐步走"

```lua
-- 模块级复用结果表 (零分配)
local _result = {
    offsetX = 0, offsetY = 0,
    scaleX = 1, scaleY = 1,
    alpha = 1, flashWhite = 0
}

function EnemyAnim.GetDrawTransform(e)
    -- ... 计算并写入 _result ...
    return _result  -- 每次返回同一张表，调用方必须立即使用
end
```

---

## 7 种动画效果速查

### A. 呼吸浮动 (Breathing Bob)

**用途**：让静止角色看起来"活着"，持续循环。

```lua
-- 参数
local BREATHE_FREQ = 1.0    -- Hz 呼吸频率（Boss 可降低至 0.8）
local BREATHE_AMP  = 2.0    -- px 上下浮动幅度（Boss 可降至 1.5-1.8）

-- 计算
local bob = math.sin(time * BREATHE_FREQ * 6.2831853) * BREATHE_AMP

-- 应用：加到 drawY 上（不是 scaleY）
drawCY = sy + bob
```

| 参数 | 普通角色 | Boss | 小精灵 |
|------|---------|------|--------|
| 频率 | 1.0 Hz | 0.8 Hz | 1.5 Hz |
| 幅度 | 2.0 px | 1.5-1.8 px | 3.0 px |

### B. 攻击挤压拉伸 (Attack Squash & Stretch)

**用途**：攻击时先蓄力压缩，再弹出释放，最后缓回。同步攻击计时器。

```lua
-- 驱动源：atkFlash (1.0 → 0, 衰减速度 dt*4, 约 0.25s)
local flash = entity.atkFlash or 0

if flash > 0.05 then
    if flash > 0.7 then
        -- 蓄力：水平压缩 + 垂直拉伸
        local t = (flash - 0.7) / 0.3
        sX = 1.0 - 0.15 * (1.0 - t)    -- 0.85 ~ 1.0
        sY = 1.0 + 0.12 * (1.0 - t)    -- 1.0  ~ 1.12
    elseif flash > 0.3 then
        -- 施法：水平拉伸 + 垂直压缩
        local t = (flash - 0.3) / 0.4
        sX = 1.0 + 0.18 * t             -- 1.0  ~ 1.18
        sY = 1.0 - 0.14 * t             -- 0.86 ~ 1.0
    else
        -- 收招：缓回正常
        local t = (flash - 0.05) / 0.25
        sX = 1.0 + 0.06 * t
        sY = 1.0 - 0.04 * t
    end
end
```

**参数调整**：幅度越大动作感越强，但超过 ±0.25 会显得"果冻化"。

| 力度 | 蓄力 sX/sY | 施法 sX/sY | 适用 |
|------|-----------|-----------|------|
| 轻微 | 0.92/1.06 | 1.10/0.92 | 远程法师 |
| 中等 | 0.85/1.12 | 1.18/0.86 | 通用战士 |
| 夸张 | 0.78/1.18 | 1.25/0.80 | 搞笑/卡通 |

### C. 受击后退位移 (Hit Recoil)

**用途**：被打时角色沿反方向位移，增强打击感。

```lua
-- 驱动源：hitFlash (0.3~0.5 → 0, 每帧 -= dt)
local hitFlash = bs.playerHitFlash or 0

if hitFlash > 0 then
    local hitMax = 0.5
    local hitT = math.min(1.0, hitFlash / hitMax)
    -- easeOut: 快速弹出，缓慢回正
    local easeT = 1.0 - (1.0 - hitT) * (1.0 - hitT)
    local recoilDist = 4.0 * easeT  -- 最大位移像素

    -- 方向：远离最近敌人
    local rdx, rdy = 0, -1  -- 默认向上
    -- ...查找最近敌人，计算远离方向...

    offsetX = offsetX + rdx * recoilDist
    offsetY = offsetY + rdy * recoilDist
end
```

**怪物版本**（基于 sin 曲线，弹出→回正更平滑）：

```lua
-- EnemyAnim 使用 (1-t)*sin(t*π) 曲线
local t = 1.0 - (recoilTimer / RECOIL_DURATION)
local mag = (1.0 - t) * math.sin(t * 3.14159) * RECOIL_DIST
offsetX = recoilDirX * mag
offsetY = recoilDirY * mag
```

### D. 死亡动画 (Death Animation)

**用途**：角色死亡时缩小 + 倾斜 + 下沉 + 淡出，分两阶段。

```lua
-- 驱动源：playerDeadTimer (2.5 → 0) 或 deathTimer (0.35 → 0)
local progress = 1.0 - math.min(1.0, deadTimer / TOTAL_DURATION)  -- 0→1

-- 玩家版：两阶段分段动画（慢节奏，2.5秒）
if progress < 0.4 then
    -- 阶段 1：快速缩小倾斜
    local t = progress / 0.4
    local ease = t * t  -- easeIn
    sX = 1.0 - 0.3 * ease
    sY = 1.0 - 0.5 * ease
    rotation = 0.3 * ease       -- ~17° 倾斜
    alpha = 1.0
    offsetY = offsetY + 8 * ease  -- 下沉
else
    -- 阶段 2：持续淡出
    local t = (progress - 0.4) / 0.6
    sX = 0.7 - 0.3 * t
    sY = 0.5 - 0.2 * t
    rotation = 0.3
    alpha = 1.0 - t * t  -- easeIn 淡出
    offsetY = offsetY + 8 + 4 * t
end

-- 怪物版：单阶段快速消失（0.35秒）
local t = 1.0 - (deathTimer / DEATH_DURATION)
local ease = t * t
sX = 1.0 - ease * 0.8       -- → 0.2
sY = 1.0 - ease * 0.8
alpha = 1.0 - ease           -- → 0
```

| 角色类型 | 总时长 | 阶段 | 特点 |
|---------|--------|------|------|
| 玩家 | 2.5s | 二阶段(缩小→淡出) | 加倾斜+下沉，戏剧化 |
| 普通怪 | 0.35s | 单阶段(缩小+淡出) | 快速清场 |

### E. 出生弹跳 (Spawn Bounce)

**用途**：怪物出现时从小弹到大，带微弹回，活力感。

```lua
-- 驱动源：spawnTimer (SPAWN_DURATION → 0)
local t = 1.0 - (spawnTimer / SPAWN_DURATION)       -- 0→1
local ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)  -- cubicEaseOut
local s = ease * (1.0 + 0.2 * math.sin(t * 3.14159))   -- overshoot
scaleX, scaleY = s, s
```

### F. Boss 脉冲 (Boss Pulse)

**用途**：Boss 持续缓慢胀缩，体现压迫感。

```lua
local BOSS_PULSE_FREQ = 0.8   -- Hz
local BOSS_PULSE_AMP  = 0.04  -- ±缩放

if entity.isBoss and not entity.dead then
    local pd = math.sin(pulsePhase) * BOSS_PULSE_AMP
    scaleX = scaleX + pd
    scaleY = scaleY + pd
end
```

### G. 护盾/光环脉冲 (Shield Pulse)

**用途**：叠加在角色上的护盾图片做呼吸脉动。

```lua
local shieldSize = baseSize * 1.6
local t = bs.time or 0
local pulse = 1.0 + math.sin(t * 3.0) * 0.05    -- 尺寸脉动 ±5%
local drawSize = shieldSize * pulse
local baseAlpha = 0.65 + math.sin(t * 2.5 + 1) * 0.15  -- 透明度脉动
```

| 护盾类型 | 尺寸频率 | 尺寸幅度 | 透明度频率 | 视觉风格 |
|---------|---------|---------|-----------|---------|
| 冰系 | 3.0 Hz | ±5% | 2.5 Hz | 沉稳冰冷 |
| 火系 | 3.8 Hz | ±6% | 3.0 Hz | 跳动活跃 |

---

## 完整代码模板

### 模板 A：玩家代码动画（内联在渲染函数中）

适合 **单个主角** 的场景，动画参数直接在 Draw 函数中计算：

```lua
function DrawPlayer(nvg, l, bs)
    local p = bs.playerBattle
    if not p then return end

    local isDead = bs.isPlayerDead
    local sx, sy = l.x + p.x, l.y + p.y
    local imgSize = 72
    local half = imgSize * 0.5

    -- 呼吸（死亡时停止）
    local bob = 0
    if not isDead then
        bob = math.sin((bs.time or 0) * 1.0 * 6.2831853) * 2.0
    end

    -- ======== 计算动画参数 ========
    local pSX, pSY = 1.0, 1.0
    local pAlpha = 1.0
    local pOffX, pOffY = 0, 0
    local pRotation = 0

    -- (A) 攻击挤压拉伸
    local flash = p.atkFlash or 0
    if not isDead and flash > 0.05 then
        -- ...见"攻击挤压拉伸"章节...
    end

    -- (B) 受击后退
    local hitFlash = bs.playerHitFlash or 0
    if not isDead and hitFlash > 0 then
        -- ...见"受击后退位移"章节...
    end

    -- (C) 死亡动画
    if isDead then
        -- ...见"死亡动画"章节...
    end

    -- ======== 渲染 ========
    -- 阴影（不跟随呼吸，跟随死亡）
    nvgEllipse(nvg, sx + pOffX, sy + half * 0.7,
        half * 0.45 * pSX, half * 0.13 * pSY)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(45 * pAlpha)))
    nvgFill(nvg)

    -- 精灵
    local drawCX = sx + pOffX
    local drawCY = sy + bob + pOffY

    nvgSave(nvg)
    -- 锚点变换（脚底）
    local footY = drawCY + half * 0.5
    nvgTranslate(nvg, drawCX, footY)
    if pRotation ~= 0 then nvgRotate(nvg, pRotation) end
    nvgScale(nvg, pSX, pSY)
    nvgTranslate(nvg, -drawCX, -footY)

    nvgGlobalAlpha(nvg, pAlpha)
    -- ...绘制精灵...
    nvgGlobalAlpha(nvg, 1)
    nvgRestore(nvg)
end
```

### 模板 B：怪物动画系统（独立模块）

适合 **多个同类实体** 的场景，动画逻辑完全独立：

```lua
-- EnemyAnim.lua
local EnemyAnim = {}

-- 调节常量
local BREATHE_FREQ    = 1.2       -- Hz
local BREATHE_AMP     = 2.5       -- px
local FLASH_DURATION  = 0.12      -- s
local RECOIL_DURATION = 0.18      -- s
local RECOIL_DIST     = 5.0       -- px
local WINDUP_DURATION = 0.30      -- s
local SPAWN_DURATION  = 0.25      -- s
local DEATH_DURATION  = 0.35      -- s

-- 零分配结果表
local _result = { offsetX=0, offsetY=0, scaleX=1, scaleY=1, alpha=1, flashWhite=0 }

function EnemyAnim.InitAnim(e)
    e.anim = {
        breathePhase = math.random() * 6.2831853,
        flashTimer = 0, recoilTimer = 0,
        recoilDirX = 0, recoilDirY = 0,
        windupTimer = 0, spawnTimer = SPAWN_DURATION,
        deathTimer = 0,
    }
    e._dyingAnim = false
end

function EnemyAnim.Update(dt, bs)
    for _, e in ipairs(bs.enemies) do
        local a = e.anim
        if not a then goto continue end
        -- tick 所有计时器
        if not e.dead then
            a.breathePhase = a.breathePhase + dt * BREATHE_FREQ * 6.2831853
        end
        for _, key in ipairs({"flashTimer","recoilTimer","windupTimer","spawnTimer","deathTimer"}) do
            if a[key] > 0 then a[key] = math.max(0, a[key] - dt) end
        end
        if a.deathTimer <= 0 and e._dyingAnim then e._dyingAnim = false end
        ::continue::
    end
end

function EnemyAnim.OnHit(e, bs)    -- 受击触发
    local a = e.anim; if not a then return end
    a.flashTimer = FLASH_DURATION
    a.recoilTimer = RECOIL_DURATION
    -- 计算远离玩家方向...
end

function EnemyAnim.OnAttack(e)     -- 攻击触发
    local a = e.anim; if not a then return end
    a.windupTimer = WINDUP_DURATION
end

function EnemyAnim.OnDeath(e)      -- 死亡触发
    local a = e.anim; if not a then return end
    a.deathTimer = DEATH_DURATION
    e._dyingAnim = true
end

function EnemyAnim.IsDying(e)
    return e._dyingAnim == true
end

function EnemyAnim.GetDrawTransform(e)
    local a = e.anim
    if not a then
        _result.offsetX=0; _result.offsetY=0
        _result.scaleX=1; _result.scaleY=1
        _result.alpha=1; _result.flashWhite=0
        return _result
    end
    -- 按优先级叠加各动画效果到 _result...
    return _result
end

return EnemyAnim
```

### 渲染端接入

```lua
local EnemyAnim = require("battle.EnemyAnim")

-- 在 BattleSystem.Update 中:
EnemyAnim.Update(dt, bs)

-- 在 DrawEnemies 中:
local animT = EnemyAnim.GetDrawTransform(e)
-- 使用 animT.offsetX/Y, scaleX/Y, alpha, flashWhite

-- 在战斗事件回调中:
EnemyAnim.OnHit(e, bs)     -- 受击时
EnemyAnim.OnAttack(e)       -- 攻击时
EnemyAnim.OnDeath(e)        -- 死亡时（设置 deathTimer 后延迟清除实体）
```

---

## 常见错误

| 错误 | 原因 | 修复 |
|------|------|------|
| 角色缩放时"悬浮"，脚不着地 | 锚点在中心而非脚底 | 改为脚底锚点（见规则 1） |
| 阴影跟着角色一起上下晃 | 阴影 Y 加了呼吸浮动偏移 | 阴影不用 bob，只用 pOffX |
| 闪白后整个画面变亮 | 4-Pass Blend 少了 Pass 4 恢复 alpha | 补全 4 步混合 |
| 闪白/闪红边缘有黑框 | 未关闭抗锯齿 | `nvgShapeAntiAlias(nvg, false)` |
| 所有怪物同步呼吸 | 呼吸初相位都是 0 | 随机初相位 `math.random() * 2π` |
| 死亡后角色还在攻击/呼吸 | 缺少 `isDead` 前置判断 | 所有非死亡动画加 `if not isDead` |
| 每帧创建新表导致 GC 卡顿 | `GetDrawTransform` 每次返回新表 | 复用模块级 `_result` 表 |
| 怪物死亡瞬间消失 | 未设置 deathTimer，直接移除 | 先 `OnDeath(e)` 后在 `IsDying` 返回 false 时清理 |

---

## 检查清单

交付代码动画前自查：

- [ ] 锚点在脚底（不是中心）
- [ ] 阴影不跟随呼吸浮动
- [ ] 阴影跟随死亡缩放/透明度
- [ ] 死亡时停止呼吸、攻击动画
- [ ] 死亡时隐藏护盾/光环
- [ ] 死亡时序列帧固定为待机帧
- [ ] 呼吸初相位随机（多实体时）
- [ ] 闪白/闪红使用 4-Pass Blend
- [ ] 闪白/闪红前后关闭/恢复 AA
- [ ] 变换矩阵 nvgSave/nvgRestore 配对
- [ ] 变换后恢复 `nvgGlobalAlpha(nvg, 1)`
- [ ] `nvgGlobalCompositeOperation` 恢复为 `NVG_SOURCE_OVER`
- [ ] 多实体系统使用零分配结果表
