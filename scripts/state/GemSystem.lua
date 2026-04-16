-- ============================================================================
-- state/GemSystem.lua - 宝石系统 (Install 模式注入 GameState)
-- ============================================================================

local Config = require("Config")

local M = {}

function M.Install(GS)

    --- 生成宝石背包 key
    --- @param gemTypeId string 宝石类型 id (如 "ruby")
    --- @param qualityIdx number 品质索引 (1-5)
    --- @return string key (如 "ruby:3")
    function GS.GemKey(gemTypeId, qualityIdx)
        return gemTypeId .. ":" .. qualityIdx
    end

    --- 添加宝石到背包
    --- @param gemTypeId string
    --- @param qualityIdx number
    --- @param count number (默认1)
    function GS.AddGem(gemTypeId, qualityIdx, count)
        count = count or 1
        local key = GS.GemKey(gemTypeId, qualityIdx)
        GS.gemBag[key] = (GS.gemBag[key] or 0) + count
    end

    --- 获取宝石数量
    --- @param gemTypeId string
    --- @param qualityIdx number
    --- @return number
    function GS.GetGemCount(gemTypeId, qualityIdx)
        return GS.gemBag[GS.GemKey(gemTypeId, qualityIdx)] or 0
    end

    --- 消耗宝石
    --- @param gemTypeId string
    --- @param qualityIdx number
    --- @param count number (默认1)
    --- @return boolean success
    function GS.RemoveGem(gemTypeId, qualityIdx, count)
        count = count or 1
        local key = GS.GemKey(gemTypeId, qualityIdx)
        local cur = GS.gemBag[key] or 0
        if cur < count then return false end
        GS.gemBag[key] = cur - count
        if GS.gemBag[key] <= 0 then GS.gemBag[key] = nil end
        return true
    end

    --- 宝石背包容量
    function GS.GetGemBagSize()
        return Config.GEM_BAG_SIZE + (GS.gemBagExpandCount or 0) * Config.GEM_BAG_EXPAND_SLOTS
    end

    --- 宝石背包已用格数（不同种类宝石的数量）
    function GS.GetGemBagUsedSlots()
        local count = 0
        for _, c in pairs(GS.gemBag or {}) do
            if c and c > 0 then count = count + 1 end
        end
        return count
    end

    --- 下次宝石背包扩容消耗的魂晶数量
    function GS.GetGemBagExpandCost()
        local n = (GS.gemBagExpandCount or 0) + 1
        return Config.EXPAND_BASE_COST + (n - 1) * Config.EXPAND_COST_INCREMENT
    end

    --- 尝试扩容宝石背包
    --- @return boolean success, string|nil reason
    function GS.ExpandGemBag()
        local curSize = GS.GetGemBagSize()
        if curSize >= Config.GEM_BAG_MAX_SIZE then
            return false, "宝石背包已达上限 " .. Config.GEM_BAG_MAX_SIZE .. " 格"
        end
        local cost = GS.GetGemBagExpandCost()
        local cur = GS.GetSoulCrystal()
        if cur < cost then
            return false, "魂晶不足 (" .. cur .. "/" .. cost .. ")"
        end
        GS.materials.soulCrystal = GS.materials.soulCrystal - cost
        GS.gemBagExpandCount = (GS.gemBagExpandCount or 0) + 1
        return true, nil
    end

    --- 镶嵌宝石到装备孔位
    --- @param slotId string 装备槽位 id
    --- @param socketIdx number 孔位索引 (1-based)
    --- @param gemTypeId string 宝石类型 id
    --- @param qualityIdx number 宝石品质索引
    --- @return boolean success, string|nil message
    function GS.SocketGem(slotId, socketIdx, gemTypeId, qualityIdx)
        local item = GS.equipment[slotId]
        if not item then return false, "槽位无装备" end
        if not item.sockets or item.sockets <= 0 then return false, "装备无孔位" end
        if socketIdx < 1 or socketIdx > item.sockets then return false, "无效孔位" end
        if not item.gems then item.gems = {} end
        -- 检查该孔位是否已有宝石
        if item.gems[socketIdx] then return false, "该孔位已镶嵌宝石" end
        -- 检查背包中是否有足够宝石
        if GS.GetGemCount(gemTypeId, qualityIdx) <= 0 then return false, "宝石不足" end

        -- 消耗宝石
        GS.RemoveGem(gemTypeId, qualityIdx, 1)
        -- 镶嵌
        item.gems[socketIdx] = { type = gemTypeId, quality = qualityIdx }

        local SaveSystem = require("SaveSystem")
        SaveSystem.MarkDirty()

        local gemDef = Config.GEM_TYPE_MAP[gemTypeId]
        local qualDef = Config.GEM_QUALITIES[qualityIdx]
        print("[Gem] 镶嵌 " .. (qualDef and qualDef.name or "?") .. (gemDef and gemDef.name or "?")
            .. " → " .. (item.name or slotId) .. " 孔位" .. socketIdx)
        return true, "镶嵌成功"
    end

    --- 拆卸宝石 (免费, 宝石返还背包)
    --- @param slotId string 装备槽位 id
    --- @param socketIdx number 孔位索引 (1-based)
    --- @return boolean success, string|nil message
    function GS.UnsocketGem(slotId, socketIdx)
        local item = GS.equipment[slotId]
        if not item then return false, "槽位无装备" end
        if not item.gems or not item.gems[socketIdx] then return false, "该孔位无宝石" end

        local gem = item.gems[socketIdx]
        -- 返还宝石到背包
        GS.AddGem(gem.type, gem.quality, 1)
        -- 移除
        item.gems[socketIdx] = nil

        local SaveSystem = require("SaveSystem")
        SaveSystem.MarkDirty()

        print("[Gem] 拆卸宝石 ← " .. (item.name or slotId) .. " 孔位" .. socketIdx)
        return true, "拆卸成功"
    end

    --- 合成宝石 (3 颗低品质 → 1 颗高品质)
    --- @param gemTypeId string 宝石类型 id
    --- @param qualityIdx number 当前品质索引 (将升级到 qualityIdx+1)
    --- @return boolean success, string|nil message
    function GS.SynthesizeGem(gemTypeId, qualityIdx)
        local maxQuality = #Config.GEM_QUALITIES
        if qualityIdx >= maxQuality then return false, "已是最高品质" end
        local cost = Config.GEM_SYNTH_COST  -- 3
        local cur = GS.GetGemCount(gemTypeId, qualityIdx)
        if cur < cost then return false, "宝石不足 (" .. cur .. "/" .. cost .. ")" end

        -- 消耗 3 颗
        GS.RemoveGem(gemTypeId, qualityIdx, cost)
        -- 获得 1 颗高品质
        GS.AddGem(gemTypeId, qualityIdx + 1, 1)

        local SaveSystem = require("SaveSystem")
        SaveSystem.MarkDirty()

        local gemDef = Config.GEM_TYPE_MAP[gemTypeId]
        local fromQ = Config.GEM_QUALITIES[qualityIdx]
        local toQ = Config.GEM_QUALITIES[qualityIdx + 1]
        print("[Gem] 合成 " .. cost .. "×" .. (fromQ and fromQ.name or "?")
            .. (gemDef and gemDef.name or "?") .. " → 1×" .. (toQ and toQ.name or "?")
            .. (gemDef and gemDef.name or "?"))
        return true, "合成成功"
    end

    --- 打孔 (消耗散光棱镜增加1个孔位)
    --- @param slotId string 装备槽位 id
    --- @return boolean success, string|nil message
    function GS.PunchSocket(slotId)
        local item = GS.equipment[slotId]
        if not item then return false, "槽位无装备" end
        if item.qualityIdx ~= 5 then return false, "仅橙色装备可打孔" end
        local curSockets = item.sockets or 0
        if curSockets >= Config.MAX_SOCKETS then return false, "孔位已满 (" .. Config.MAX_SOCKETS .. ")" end

        -- 计算消耗 (第N次打孔的消耗)
        local punchIdx = curSockets + 1  -- 即将打的是第几个孔
        local cost = Config.PUNCH_COSTS[punchIdx]
        if not cost then return false, "打孔配置异常" end

        -- 检查散光棱镜数量
        local prismCount = GS.GetBagItemCount("prism")
        if prismCount < cost then
            return false, "散光棱镜不足 (" .. prismCount .. "/" .. cost .. ")"
        end

        -- 消耗散光棱镜
        GS.DiscardBagItem("prism", cost)
        -- 增加孔位
        item.sockets = curSockets + 1
        if not item.gems then item.gems = {} end

        local SaveSystem = require("SaveSystem")
        SaveSystem.MarkDirty()

        print("[Gem] 打孔 " .. (item.name or slotId) .. " → " .. item.sockets .. "孔 (消耗 " .. cost .. " 散光棱镜)")
        return true, "打孔成功! 当前 " .. item.sockets .. " 孔"
    end

    --- 获取装备的宝石属性汇总 (用于 StatCalc)
    --- @param item table 装备对象
    --- @return table statBonuses { [statKey] = value, ... }
    function GS.GetGemStats(item)
        local bonuses = {}
        if not item or not item.gems or not item.sockets then return bonuses end

        local category = Config.EQUIP_CATEGORIES[item.slot]
        if not category then return bonuses end

        for i = 1, item.sockets do
            local gem = item.gems[i]
            if gem then
                local statKey, value = Config.CalcGemStat(gem.type, gem.quality, category, Config.IPToTierMul(item.itemPower))
                if statKey and value > 0 then
                    if statKey == "allRes" then
                        -- 钻石首饰: 拆分到 5 种抗性
                        for _, resKey in ipairs(Config.DIAMOND_ALLRES_STATS) do
                            bonuses[resKey] = (bonuses[resKey] or 0) + value
                        end
                    else
                        bonuses[statKey] = (bonuses[statKey] or 0) + value
                    end
                end
            end
        end
        return bonuses
    end
end

return M
