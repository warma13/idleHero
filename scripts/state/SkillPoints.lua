-- ============================================================================
-- state/SkillPoints.lua - 技能点系统 (Install 模式注入 GameState)
-- v3.0: D4模型 — 层级门槛、增强互斥、装备槽位
-- ============================================================================

local Config = require("Config")
local SkillTreeConfig = require("SkillTreeConfig")
local AffixHelper = require("state.AffixHelper")

local M = {}

function M.Install(GS)

    --- 获得的总技能点
    function GS.GetTotalSkillPts()
        return math.floor(GS.player.level / Config.SKILL_PT_INTERVAL)
    end

    --- 已消耗的技能点 (每级消耗1点)
    function GS.GetSpentSkillPts()
        local spent = 0
        for id, skill in pairs(GS.skills) do
            if SkillTreeConfig.SKILL_MAP[id] then
                spent = spent + SkillTreeConfig.GetTotalCostForLevel(id, skill.level)
            end
        end
        return spent
    end

    --- 可用技能点
    function GS.GetAvailableSkillPts()
        return GS.GetTotalSkillPts() - GS.GetSpentSkillPts()
    end

    --- 检查技能是否可升级
    function GS.CanUpgradeSkill(skillId)
        local cfg = SkillTreeConfig.SKILL_MAP[skillId]
        if not cfg then return false, "配置不存在" end

        -- 确保 skills 表中有此技能记录
        if not GS.skills[skillId] then
            GS.skills[skillId] = { level = 0 }
        end
        local skill = GS.skills[skillId]

        if skill.level >= cfg.maxLevel then return false, "已满级" end

        local upgradeCost = SkillTreeConfig.GetUpgradeCost(skillId, skill.level)
        if GS.GetAvailableSkillPts() < upgradeCost then
            return false, "技能点不足"
        end

        -- 层级门槛 + 增强互斥 + 关键被动互斥
        local totalSpent = GS.GetSpentSkillPts()
        local ok, reason = SkillTreeConfig.AreRequirementsMet(skillId, GS.GetSkillLevel, totalSpent)
        if not ok then
            return false, reason
        end

        return true, nil
    end

    --- 升级技能
    function GS.UpgradeSkill(skillId)
        local ok, err = GS.CanUpgradeSkill(skillId)
        if not ok then return false, err end

        if not GS.skills[skillId] then
            GS.skills[skillId] = { level = 0 }
        end
        GS.skills[skillId].level = GS.skills[skillId].level + 1
        return true, nil
    end

    --- 获取技能等级（含装备词缀加成）
    --- 词缀 "skill_level_<skillId>"   → 特定技能 +N 级
    --- 词缀 "element_skill_level_<element>" → 该元素所有技能 +N 级
    --- 仅当基础等级 > 0（已学习）时才叠加装备加成
    function GS.GetSkillLevel(skillId)
        local skill = GS.skills[skillId]
        local baseLv = skill and skill.level or 0
        if baseLv <= 0 then return 0 end

        -- 特定技能等级加成
        local bonus = AffixHelper.GetAffixValue("skill_level_" .. skillId)

        -- 元素技能等级加成
        local cfg = SkillTreeConfig.SKILL_MAP[skillId]
        if cfg and cfg.element then
            bonus = bonus + AffixHelper.GetAffixValue("element_skill_level_" .. cfg.element)
        end

        return baseLv + math.floor(bonus)
    end

    --- 获取技能基础等级（不含装备加成，用于技能点相关判断）
    function GS.GetSkillBaseLevel(skillId)
        local skill = GS.skills[skillId]
        return skill and skill.level or 0
    end

    --- 获取装备词缀带来的技能等级加成
    function GS.GetSkillEquipBonus(skillId)
        return GS.GetSkillLevel(skillId) - GS.GetSkillBaseLevel(skillId)
    end

    --- 检查增强节点是否已学
    function GS.HasEnhance(enhanceId)
        return GS.GetSkillLevel(enhanceId) > 0
    end

    --- 获取降级技能的魂晶消耗
    --- @param skillId string
    --- @return number crystalCost, number refundPts
    function GS.GetDowngradeSkillCost(skillId)
        local skill = GS.skills[skillId]
        if not skill or skill.level <= 0 then return 0, 0 end
        local refund = SkillTreeConfig.GetUpgradeCost(skillId, skill.level - 1)
        return refund * Config.RESET_SKILL_UNIT_COST, refund
    end

    --- 检查是否可以降级技能
    function GS.CanDowngradeSkill(skillId)
        local skill = GS.skills[skillId]
        if not skill then return false, "技能不存在" end
        if skill.level <= 0 then return false, "未学习" end

        local cfg = SkillTreeConfig.SKILL_MAP[skillId]
        if not cfg then return false, "配置不存在" end

        -- 魂晶检查
        local cost = GS.GetDowngradeSkillCost(skillId)
        if GS.GetSoulCrystal() < cost then
            return false, "魂晶不足 (" .. GS.GetSoulCrystal() .. "/" .. cost .. ")"
        end

        -- 降到0级时: 检查增强节点依赖
        if skill.level == 1 and cfg.nodeType == "active" then
            -- 如果此技能有增强节点被学了, 不能降级
            if cfg.enhances then
                for _, line in ipairs(cfg.enhances) do
                    for _, enh in ipairs(line) do
                        if GS.GetSkillLevel(enh.id) > 0 then
                            return false, "增强节点 " .. enh.name .. " 依赖此技能"
                        end
                    end
                end
            end
        end

        -- 降到低于满级时: 增强节点需要满级, 检查是否有增强
        if cfg.nodeType == "active" and skill.level == cfg.maxLevel then
            if cfg.enhances then
                for _, line in ipairs(cfg.enhances) do
                    for _, enh in ipairs(line) do
                        if GS.GetSkillLevel(enh.id) > 0 then
                            return false, "增强节点 " .. enh.name .. " 需要本技能满级"
                        end
                    end
                end
            end
        end

        -- 降级后总点数是否会导致高层技能无法维持门槛
        -- (简化: 重置时一次性处理, 单个降级暂不校验)

        return true, nil
    end

    --- 降级技能
    function GS.DowngradeSkill(skillId)
        local ok, err = GS.CanDowngradeSkill(skillId)
        if not ok then return false, err end
        local cost = GS.GetDowngradeSkillCost(skillId)
        GS.materials.soulCrystal = GS.materials.soulCrystal - cost
        GS.skills[skillId].level = GS.skills[skillId].level - 1
        return true, nil
    end

    --- 计算重置技能点的魂晶消耗
    function GS.GetResetSkillCost()
        return GS.GetSpentSkillPts() * Config.RESET_SKILL_UNIT_COST
    end

    --- 重置技能点 (全部回收, 含增强节点)
    --- @return boolean success, string|nil reason
    function GS.ResetSkillPoints()
        local spent = GS.GetSpentSkillPts()
        if spent <= 0 then return false, "没有已分配的技能点" end
        local cost = GS.GetResetSkillCost()
        local cur = GS.GetSoulCrystal()
        if cur < cost then
            return false, "魂晶不足 (" .. cur .. "/" .. cost .. ")"
        end
        GS.materials.soulCrystal = GS.materials.soulCrystal - cost
        for _, skill in pairs(GS.skills) do
            skill.level = 0
        end
        -- 清空装备槽位
        if GS.skillLoadout then
            GS.skillLoadout.basic = nil
            GS.skillLoadout.active = {}
            GS.skillLoadout.keyPassive = nil
        end
        print("[SkillPoints] Reset all, returned " .. spent .. " pts, cost " .. cost .. " crystals")
        return true, nil
    end

    -- ================================================================
    -- 装备槽位系统
    -- ================================================================

    --- 初始化装备槽位 (GameState.Init 调用)
    function GS.InitSkillLoadout()
        if not GS.skillLoadout then
            GS.skillLoadout = {
                basic = nil,        -- string|nil 装备的基础技能ID
                active = {},        -- string[] 装备的主动技能ID列表 (最多4个)
                keyPassive = nil,   -- string|nil 已选的关键被动 (由技能点自动确定)
            }
        end
    end

    --- 装备基础技能 (替代普攻, 只能装1个)
    --- @param skillId string|nil nil=卸下
    --- @return boolean, string|nil
    function GS.EquipBasicSkill(skillId)
        GS.InitSkillLoadout()
        if skillId == nil then
            GS.skillLoadout.basic = nil
            return true, nil
        end
        local cfg = SkillTreeConfig.SKILL_MAP[skillId]
        if not cfg or (not cfg.isBasic and cfg.tier ~= 2) then
            return false, "不是基础/核心技能"
        end
        if GS.GetSkillLevel(skillId) <= 0 then
            return false, "未学习此技能"
        end
        GS.skillLoadout.basic = skillId
        return true, nil
    end

    --- 装备主动技能到槽位
    --- @param slotIdx number 槽位索引 (1-4)
    --- @param skillId string|nil nil=清空槽位
    --- @return boolean, string|nil
    function GS.EquipActiveSkill(slotIdx, skillId)
        GS.InitSkillLoadout()
        local maxSlots = SkillTreeConfig.LOADOUT.activeSlots
        if slotIdx < 1 or slotIdx > maxSlots then
            return false, "槽位索引无效 (1-" .. maxSlots .. ")"
        end
        if skillId == nil then
            GS.skillLoadout.active[slotIdx] = nil
            return true, nil
        end
        local cfg = SkillTreeConfig.SKILL_MAP[skillId]
        if not cfg or cfg.nodeType ~= "active" then
            return false, "不是主动技能"
        end
        if cfg.isBasic or cfg.tier == 2 then
            return false, "基础/核心技能请使用基础技能槽"
        end
        if GS.GetSkillLevel(skillId) <= 0 then
            return false, "未学习此技能"
        end
        -- 终极技能互斥: 检查其他槽位是否已有终极技能
        if cfg.isUltimate then
            for i = 1, maxSlots do
                if i ~= slotIdx and GS.skillLoadout.active[i] then
                    local otherCfg = SkillTreeConfig.SKILL_MAP[GS.skillLoadout.active[i]]
                    if otherCfg and otherCfg.isUltimate then
                        return false, "只能装备一个终极技能"
                    end
                end
            end
        end
        -- 检查是否已装备在其他槽位
        for i = 1, maxSlots do
            if i ~= slotIdx and GS.skillLoadout.active[i] == skillId then
                GS.skillLoadout.active[i] = nil -- 从旧槽位移除
            end
        end
        GS.skillLoadout.active[slotIdx] = skillId
        return true, nil
    end

    --- 获取已装备的基础技能
    --- @return string|nil skillId
    function GS.GetEquippedBasicSkill()
        GS.InitSkillLoadout()
        return GS.skillLoadout.basic
    end

    --- 获取已装备的主动技能列表
    --- @return table active { [1..4] = skillId|nil }
    function GS.GetEquippedActiveSkills()
        GS.InitSkillLoadout()
        return GS.skillLoadout.active
    end

    --- 获取所有已装备技能 (基础+主动, 用于战斗循环)
    --- @return table[] { {id=string, cfg=table, level=number}, ... }
    function GS.GetEquippedSkillList()
        GS.InitSkillLoadout()
        local result = {}
        -- 基础技能 (由 CombatCore 普攻使用, 不加入主动列表)
        -- 主动技能
        for i = 1, SkillTreeConfig.LOADOUT.activeSlots do
            local sid = GS.skillLoadout.active[i]
            if sid then
                local cfg = SkillTreeConfig.SKILL_MAP[sid]
                local lv = GS.GetSkillLevel(sid)
                if cfg and lv > 0 then
                    result[#result + 1] = { id = sid, cfg = cfg, level = lv }
                end
            end
        end
        return result
    end

    --- 获取当前选择的关键被动
    --- @return string|nil skillId
    function GS.GetEquippedKeyPassive()
        -- 关键被动不走槽位, 直接从技能点判断 (7选1, 只有1个level>0)
        for _, skill in ipairs(SkillTreeConfig.SKILLS) do
            if skill.isKeyPassive and GS.GetSkillLevel(skill.id) > 0 then
                return skill.id
            end
        end
        return nil
    end
end

return M
