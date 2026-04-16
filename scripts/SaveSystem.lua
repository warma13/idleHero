-- ============================================================================
-- SaveSystem.lua - 代理层 (转发到 SlotSaveSystem)
--
-- 保留此模块是为了向后兼容: 大量文件引用 SaveSystem.Save() / SaveNow() /
-- MarkDirty() / offlineSeconds 等。此代理将所有调用转发到新的多槽位系统,
-- 无需逐个修改使用方。
--
-- ⚠️ Init / Update / Load 不再由此模块实现, 由 main.lua 直接调用 SlotSaveSystem。
-- ============================================================================

local SlotSaveSystem = require("SlotSaveSystem")

local SaveSystem = {}

-- ============================================================================
-- 转发公开字段 (属性代理)
-- ============================================================================

--- offlineSeconds: 读写均代理到 SlotSaveSystem
---@type number
SaveSystem.offlineSeconds = 0

--- _saveCount: 读写均代理到 SlotSaveSystem
---@type number
SaveSystem._saveCount = 0

-- ============================================================================
-- 转发方法
-- ============================================================================

--- 保存 (本地+云端)
function SaveSystem.Save()
    SlotSaveSystem.Save()
end

--- 立即保存 (关卡通关等关键事件)
function SaveSystem.SaveNow()
    SlotSaveSystem.SaveNow()
end

--- 标记脏数据, 延迟合并保存
function SaveSystem.MarkDirty()
    SlotSaveSystem.MarkDirty()
end

--- 序列化当前 GameState
function SaveSystem.Serialize()
    return SlotSaveSystem.Serialize()
end

--- 反序列化存档数据到 GameState
function SaveSystem.Deserialize(data)
    return SlotSaveSystem.Deserialize(data)
end

--- 本地存档
function SaveSystem.SaveLocal(saveData)
    SlotSaveSystem.SaveLocal(saveData)
end

--- 结构校验
function SaveSystem.ValidateStructure(data)
    return SlotSaveSystem.ValidateStructure(data)
end

--- 存档健康状态
function SaveSystem.IsSaveHealthy()
    return SlotSaveSystem.IsSaveHealthy()
end

--- 测试账号覆盖
function SaveSystem.ApplyTestAccountOverrides()
    SlotSaveSystem.ApplyTestAccountOverrides()
end

-- ============================================================================
-- offlineSeconds 属性同步
--
-- 因为 Lua table 不支持属性拦截, 采用 Update 时同步方案:
-- SlotSaveSystem 是权威值, 在 main.lua 的 HandleUpdate 中同步给本代理。
-- 直接修改 SaveSystem.offlineSeconds 也会写回 SlotSaveSystem。
-- ============================================================================

--- 由 main.lua 每帧调用, 同步字段
function SaveSystem.SyncFields()
    SaveSystem.offlineSeconds = SlotSaveSystem.offlineSeconds
    SaveSystem._saveCount = SlotSaveSystem._saveCount
end

--- 由 OfflineChest.Close() 等设置 offlineSeconds = 0 时调用
function SaveSystem.SetOfflineSeconds(val)
    SaveSystem.offlineSeconds = val
    SlotSaveSystem.offlineSeconds = val
end

-- ============================================================================
-- 废弃方法 (保留接口, 不执行)
-- ============================================================================

--- Init 已由 SlotSaveSystem.Init 替代, 保留空壳避免报错
function SaveSystem.Init(onComplete)
    print("[SaveSystem] WARN: Init() is deprecated, use SlotSaveSystem.Init()")
    if onComplete then onComplete() end
end

--- Update 已由 SlotSaveSystem.Update 替代
function SaveSystem.Update(dt)
    -- 由 main.lua 调用 SlotSaveSystem.Update(dt) 替代
end

--- Load 已由 SlotSaveSystem 的 Init+LoadSlot 替代
function SaveSystem.Load()
    print("[SaveSystem] WARN: Load() is deprecated")
end

--- ReadLocalData 已废弃
function SaveSystem.ReadLocalData()
    print("[SaveSystem] WARN: ReadLocalData() is deprecated")
end

return SaveSystem
