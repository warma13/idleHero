-- ============================================================================
-- ui/Toast.lua - 轻量顶部 Toast 提示 (自动消失)
-- ============================================================================

local UI = require("urhox-libs/UI")

local Toast = {}

---@type Widget
local overlayRoot_ = nil
local toasts_ = {}   -- { widget, timer }
local TOAST_TOP_BASE = 80   -- HUD(44) + quickBar(28) + margin(8)
local TOAST_SPACING  = 34   -- 每条 Toast 间距 (高度28 + gap6)

--- 设置 Toast 挂载的根节点
function Toast.SetRoot(root)
    overlayRoot_ = root
end

--- 显示一条 Toast (1.8秒自动消失)
--- @param text string 提示文字
--- @param color? table 文字颜色 {r,g,b,a}  默认白色
--- @param bgColor? table 背景色 {r,g,b,a}  默认半透明深灰
function Toast.Show(text, color, bgColor)
    if not overlayRoot_ then
        print("[Toast] overlayRoot_ is nil, cannot show: " .. text)
        return
    end

    local c = color or { 255, 255, 255, 255 }
    local bg = bgColor or { 40, 45, 55, 220 }

    -- 计算当前 Toast 的 top 位置（已有的往下错开）
    local topPos = TOAST_TOP_BASE + #toasts_ * TOAST_SPACING

    local w = UI.Panel {
        position = "absolute",
        top = topPos, left = "15%", right = "15%",
        height = 28,
        zIndex = 900,
        flexDirection = "row", alignItems = "center", justifyContent = "center",
        backgroundColor = bg,
        borderRadius = 14,
        borderWidth = 1, borderColor = { c[1], c[2], c[3], 80 },
        children = {
            UI.Label { text = text, fontSize = 11, fontColor = c, textAlign = "center" },
        },
    }

    overlayRoot_:AddChild(w)
    table.insert(toasts_, { widget = w, timer = 1.8 })
    print("[Toast] Show: " .. text)
end

--- 成功提示 (绿色调)
function Toast.Success(text)
    Toast.Show(text, { 120, 255, 160, 255 }, { 30, 60, 40, 220 })
end

--- 警告提示 (红色调)
function Toast.Warn(text)
    Toast.Show(text, { 255, 120, 100, 255 }, { 60, 30, 30, 220 })
end

--- 每帧更新, 处理自动消失
function Toast.Update(dt)
    for i = #toasts_, 1, -1 do
        local t = toasts_[i]
        t.timer = t.timer - dt
        if t.timer <= 0 then
            if t.widget and overlayRoot_ then
                overlayRoot_:RemoveChild(t.widget)
            end
            table.remove(toasts_, i)
        end
    end
end

return Toast
