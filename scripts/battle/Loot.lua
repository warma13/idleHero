-- ============================================================================
-- battle/Loot.lua - 掉落物生成与磁吸拾取 (含散落动画+延迟吸收)
-- ============================================================================

local GameState  = require("GameState")
local SaveSystem = require("SaveSystem")
local EventBus   = require("EventBus")
local FloatTip   = require("ui.FloatTip")

local Loot = {}

-- 散落参数
local SCATTER_SPEED_MIN = 100  -- 初始散射最小速度
local SCATTER_SPEED_MAX = 200  -- 初始散射最大速度
local SCATTER_FRICTION  = 2.0  -- 摩擦力衰减系数 (越小散得越远)
local ABSORB_DELAY      = 2.0  -- 掉落后多少秒自动吸收全屏物品
local MAX_GROUND_EQUIPS = 100  -- 地面装备最大堆积数量

function Loot.Spawn(loots, x, y, lootType, value, color, extra)
    -- 随机散射方向
    local angle = math.random() * math.pi * 2
    local speed = SCATTER_SPEED_MIN + math.random() * (SCATTER_SPEED_MAX - SCATTER_SPEED_MIN)
    local vx = math.cos(angle) * speed
    local vy = math.sin(angle) * speed

    local loot = {
        x = x, y = y,
        vx = vx, vy = vy,         -- 散射速度
        type  = lootType,
        value = value,
        color = color,
        extra = extra,             -- 额外数据 (装备的 slotId 等)
        life  = 15,
        age   = 0,                 -- 存在时间
        attracted = false,
        scattering = true,         -- 正在散落阶段
    }
    table.insert(loots, loot)
end

function Loot.Update(dt, loots, playerBattle, pickupRadius)
    if not playerBattle then return end
    local px, py = playerBattle.x, playerBattle.y

    -- 背包是否有空位（缓存，避免每个 loot 都查）
    local invFull = #GameState.inventory >= GameState.GetInventorySize()

    for i = #loots, 1, -1 do
        local loot = loots[i]
        loot.life = loot.life - dt
        loot.age  = loot.age + dt

        if loot.life <= 0 then
            -- 装备类掉落物：背包满时不消失，延长生命
            if loot.type == "equip" and invFull then
                loot.life = 10  -- 续命，等背包腾出空间
            else
                table.remove(loots, i)
            end
        else
            -- 散落物理
            if loot.scattering then
                loot.x = loot.x + loot.vx * dt
                loot.y = loot.y + loot.vy * dt
                local friction = math.exp(-SCATTER_FRICTION * dt)
                loot.vx = loot.vx * friction
                loot.vy = loot.vy * friction
                local spd = math.sqrt(loot.vx * loot.vx + loot.vy * loot.vy)
                if spd < 5 then
                    loot.scattering = false
                    loot.vx = 0
                    loot.vy = 0
                end
            end

            local dx, dy = px - loot.x, py - loot.y
            local dist = math.sqrt(dx * dx + dy * dy)

            -- 散落阶段不触发磁吸，让掉落物先散开
            if not loot.scattering then
                -- 背包满时装备不吸收，留在地上（除非符合自动分解条件）
                local canAttract = true
                if loot.type == "equip" and invFull then
                    local qi = loot.value and loot.value.qualityIdx or 0
                    -- 找到激活的品质阈值
                    local aLv, aMode = 0, 0
                    for k = #GameState.autoDecompConfig, 1, -1 do
                        if GameState.autoDecompConfig[k] > 0 then
                            aLv = k; aMode = GameState.autoDecompConfig[k]; break
                        end
                    end
                    local isSet = loot.value and loot.value.setId
                    if aLv > 0 and qi > 0 and qi <= aLv and (aMode == 1 or not (isSet and qi == aLv)) then
                        canAttract = true  -- 符合自动分解，允许磁吸
                    else
                        canAttract = false
                    end
                end

                if canAttract then
                    if dist < pickupRadius then
                        loot.attracted = true
                    elseif loot.age > ABSORB_DELAY then
                        loot.attracted = true
                    end
                end
            end

            if loot.attracted then
                local speed = 300 + (200 - math.min(dist, 200)) * 3
                if dist > 5 then
                    local nx, ny = dx / dist, dy / dist
                    loot.x = loot.x + nx * speed * dt
                    loot.y = loot.y + ny * speed * dt
                end
                if dist < 12 then
                    local ok = Loot.Collect(loot)
                    if ok ~= false then
                        table.remove(loots, i)
                    else
                        -- 背包满, 取消吸引, 落回地面
                        loot.attracted = false
                    end
                end
            end
        end
    end

    -- 地面装备上限：超过100件时销毁最早掉落的
    if invFull then
        Loot.EnforceGroundEquipCap(loots)
    end
end

--- 强制执行地面装备数量上限 (优先移除低品质)
function Loot.EnforceGroundEquipCap(loots)
    -- 收集地面装备索引
    local equipIndices = {}
    for i, loot in ipairs(loots) do
        if loot.type == "equip" then
            table.insert(equipIndices, i)
        end
    end
    -- 超出上限时，按品质升序排列，优先移除低品质
    if #equipIndices > MAX_GROUND_EQUIPS then
        -- 按品质升序 + 掉落时间升序（品质相同时先移除更老的）
        table.sort(equipIndices, function(a, b)
            local qa = loots[a].value and loots[a].value.qualityIdx or 0
            local qb = loots[b].value and loots[b].value.qualityIdx or 0
            if qa ~= qb then return qa < qb end
            return a < b  -- 索引小 = 更早掉落
        end)
        local toRemove = #equipIndices - MAX_GROUND_EQUIPS
        -- 收集要移除的索引，倒序删除避免索引偏移
        local removeSet = {}
        for i = 1, toRemove do
            removeSet[equipIndices[i]] = true
        end
        for i = #loots, 1, -1 do
            if removeSet[i] then
                table.remove(loots, i)
            end
        end
    end
end

--- @return boolean ok 是否收集成功 (false = 背包满, 掉落物应保留在地面)
function Loot.Collect(loot)
    if loot.type == "exp" then
        GameState.AddExp(loot.value)
    elseif loot.type == "gold" then
        GameState.AddGold(loot.value)
    elseif loot.type == "equip" then
        local ok, decompInfo = GameState.AddToInventory(loot.value)
        if not ok then return false end
        if decompInfo then FloatTip.Decompose(decompInfo) end
        SaveSystem.MarkDirty()
    elseif loot.type == "soulCrystal" then
        GameState.AddSoulCrystal(loot.value)
    elseif loot.type == "bagItem" then
        local itemId = loot.extra and loot.extra.itemId
        if itemId then
            local added = GameState.AddBagItem(itemId, loot.value or 1)
            if added > 0 then
                SaveSystem.MarkDirty()
                local Config = require("Config")
                local cfg = Config.ITEM_MAP[itemId]
                if cfg then
                    EventBus.Emit("loot:rare_item", cfg.name)
                end
            end
        end
    end
    return true
end

return Loot
