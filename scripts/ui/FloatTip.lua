-- ============================================================================
-- ui/FloatTip.lua - 屏幕上方中间飘字提示 (上浮 + 淡出)
-- ============================================================================

local UI = require("urhox-libs/UI")

local FloatTip = {}

---@type Widget
local overlayRoot_ = nil
local tips_ = {}  -- { widget, timer, maxTimer, startTop }

local TIP_DURATION  = 1.6   -- 总持续时间(秒)
local TIP_START_TOP = 120   -- 起始 top 位置
local TIP_FLOAT_PX  = 30    -- 上浮像素量
local TIP_SPACING   = 28    -- 多条之间的间距

--- 设置挂载根节点
function FloatTip.SetRoot(root)
    overlayRoot_ = root
end

--- 显示飘字提示
---@param text string  提示文字
---@param color? table  文字颜色 {r,g,b,a}  默认金色
function FloatTip.Show(text, color)
    if not overlayRoot_ then return end

    local c = color or { 255, 220, 100, 255 }

    -- 已有的条目往下让位
    local startTop = TIP_START_TOP + #tips_ * TIP_SPACING

    local w = UI.Panel {
        position = "absolute",
        top = startTop, left = "10%", right = "10%",
        height = 24,
        zIndex = 950,
        flexDirection = "row", alignItems = "center", justifyContent = "center",
        children = {
            UI.Label {
                text = text, fontSize = 13, fontWeight = "bold",
                fontColor = c, textAlign = "center",
            },
        },
    }

    overlayRoot_:AddChild(w)
    table.insert(tips_, { widget = w, timer = TIP_DURATION, maxTimer = TIP_DURATION, startTop = startTop })
end

--- 装备操作提示 (绿色)
function FloatTip.Equip(text)
    FloatTip.Show(text, { 120, 255, 180, 255 })
end

--- 分解提示 (橙色)
function FloatTip.Decompose(text)
    FloatTip.Show(text, { 255, 200, 80, 255 })
end

--- 升级提示 (蓝色)
function FloatTip.Upgrade(text)
    FloatTip.Show(text, { 130, 200, 255, 255 })
end

--- 每帧更新: 上浮 + 淡出
function FloatTip.Update(dt)
    for i = #tips_, 1, -1 do
        local t = tips_[i]
        t.timer = t.timer - dt
        if t.timer <= 0 then
            if t.widget and overlayRoot_ then
                overlayRoot_:RemoveChild(t.widget)
            end
            table.remove(tips_, i)
        else
            -- 上浮：根据进度计算 top 偏移
            local progress = 1.0 - (t.timer / t.maxTimer) -- 0→1
            local newTop = t.startTop - TIP_FLOAT_PX * progress
            -- 淡出：最后 40% 时间淡出
            local alpha = 1.0
            if progress > 0.6 then
                alpha = (1.0 - progress) / 0.4
            end
            local a = math.floor(alpha * 255)
            t.widget:SetStyle({ top = math.floor(newTop) })
            -- 更新子 Label 透明度
            local lbl = t.widget:GetChildAt(0)
            if lbl then
                local fc = lbl.props.fontColor
                if fc then
                    lbl:SetStyle({ fontColor = { fc[1], fc[2], fc[3], a } })
                end
            end
        end
    end
end

return FloatTip
