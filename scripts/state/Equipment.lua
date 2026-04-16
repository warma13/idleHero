-- ============================================================================
-- state/Equipment.lua — 装备系统编排层 (薄入口)
-- ============================================================================
-- 职责: 初始化共享上下文 (ctx), 依次安装各子模块
-- 子模块位于 state/equip/ 目录:
--   ItemFactory — 物品生成 (GenerateEquip, CreateEquip) + 共享 helper
--   Materials   — 材料管理 & 背包容量
--   Inventory   — 背包操作 (穿戴, 排序, 锁定, 分解)
--   Upgrade     — 装备改造 (升级, IP注入, 附魔)
--   Forge       — 锻造系统
--   Migration   — 运行时旧格式迁移
-- ============================================================================

local Equipment = {}

function Equipment.Install(GameState)
    local Config      = require("Config")
    local AffixHelper = require("state.AffixHelper")

    -- 共享上下文 — ItemFactory 会向其中注入 helper 函数
    local ctx = {
        Config      = Config,
        AffixHelper = AffixHelper,
    }

    -- 安装顺序:
    -- 1. ItemFactory 最先 (向 ctx 注入 calcItemPower 等共享 helper)
    -- 2. Materials 在 Inventory 前 (Inventory 的分解需要 AddStone/AddGold)
    -- 3. Inventory, Upgrade, Forge 无互相依赖, 顺序任意
    -- 4. Migration 最后 (启动时遍历已有装备, 需要所有方法就绪)
    require("state.equip.ItemFactory").Install(GameState, ctx)
    require("state.equip.Materials").Install(GameState, ctx)
    require("state.equip.Inventory").Install(GameState, ctx)
    require("state.equip.Upgrade").Install(GameState, ctx)
    require("state.equip.Forge").Install(GameState, ctx)
    require("state.equip.Migration").Install(GameState, ctx)
end

return Equipment
