-- ============================================================================
-- ManualSave.lua - 手动存档/读档模块
-- 独立于自动存档系统，使用单独的云端 key 存储
-- 支持: 手动保存快照 + 云端校验值 + 手动恢复
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local SaveSystem = require("SaveSystem")
local GameState  = require("GameState")

local ManualSave = {}

-- 云端 key
local MANUAL_SAVE_KEY     = "manual_save"       -- values: 完整存档数据
local MANUAL_CHECKSUM_KEY = "manual_checksum"    -- iscores: DJB2 校验值

-- 状态
local saving_  = false   -- 防止重复操作
local loading_ = false

-- Toast 引用
local Toast_ = nil
local function getToast()
    if not Toast_ then
        local ok, t = pcall(require, "ui.Toast")
        if ok then Toast_ = t end
    end
    return Toast_
end

--- DJB2 哈希 (与 SaveSystem 保持一致)
--- @param str string
--- @return number
local function ComputeHash(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) & 0x7FFFFFFF
    end
    return hash
end

-- ============================================================================
-- 手动保存
-- ============================================================================

--- 手动保存当前游戏状态到云端
--- @param callback fun(ok: boolean, msg: string)|nil
function ManualSave.Save(callback)
    if saving_ then
        if callback then callback(false, "正在保存中，请稍候") end
        return
    end

    -- 检查存档系统健康
    local healthy, healthReason = SaveSystem.IsSaveHealthy()
    if not healthy then
        local msg = "存档系统异常，无法手动保存"
        if healthReason == "loading" then msg = "存档加载中，请稍候再试" end
        if callback then callback(false, msg) end
        return
    end

    saving_ = true

    local saveData = SaveSystem.Serialize()
    -- 序列化为 JSON 字符串 (存字符串而非 table, 确保读取时 hash 一致)
    local ok, json = pcall(cjson.encode, saveData)
    if not ok then
        saving_ = false
        if callback then callback(false, "序列化失败") end
        return
    end
    local checksum = ComputeHash(json)

    -- 批量写入: JSON 字符串 + 校验值
    local apiOk, _ = pcall(function()
        clientCloud:BatchSet()
            :Set(MANUAL_SAVE_KEY, json)
            :SetInt(MANUAL_CHECKSUM_KEY, checksum)
            :Save("手动存档", {
                ok = function()
                    saving_ = false
                    print("[ManualSave] Save OK, checksum=" .. checksum)
                    local toast = getToast()
                    if toast then toast.Success("手动存档保存成功") end
                    if callback then callback(true, "保存成功") end
                end,
                error = function(code, reason)
                    saving_ = false
                    print("[ManualSave] Save error: " .. tostring(reason))
                    local toast = getToast()
                    if toast then toast.Warn("手动存档保存失败: " .. tostring(reason)) end
                    if callback then callback(false, "保存失败: " .. tostring(reason)) end
                end,
            })
    end)

    if not apiOk then
        saving_ = false
        if callback then callback(false, "云端 API 不可用") end
    end
end

-- ============================================================================
-- 手动读档
-- ============================================================================

--- 从云端读取手动存档并验证校验值，恢复到 GameState
--- @param callback fun(ok: boolean, msg: string)|nil
function ManualSave.Load(callback)
    if loading_ then
        if callback then callback(false, "正在读取中，请稍候") end
        return
    end

    loading_ = true

    local apiOk, _ = pcall(function()
        clientCloud:BatchGet()
            :Key(MANUAL_SAVE_KEY)
            :Key(MANUAL_CHECKSUM_KEY)
            :Fetch({
                ok = function(values, iscores)
                    loading_ = false
                    local rawData = values[MANUAL_SAVE_KEY]
                    local savedChecksum = iscores[MANUAL_CHECKSUM_KEY]

                    if not rawData then
                        print("[ManualSave] No manual save found")
                        if callback then callback(false, "没有找到手动存档") end
                        return
                    end

                    -- rawData 是 JSON 字符串 (保存时存的字符串)
                    -- 兼容旧格式: 如果是 table 则重新编码
                    local json
                    if type(rawData) == "string" then
                        json = rawData
                    elseif type(rawData) == "table" then
                        local encOk, encoded = pcall(cjson.encode, rawData)
                        if not encOk then
                            if callback then callback(false, "存档数据异常") end
                            return
                        end
                        json = encoded
                    else
                        if callback then callback(false, "存档数据类型异常") end
                        return
                    end

                    -- 校验数据完整性 (直接对 JSON 字符串算 hash)
                    if savedChecksum then
                        local computed = ComputeHash(json)
                        if computed ~= savedChecksum then
                            print("[ManualSave] Checksum mismatch! saved=" .. tostring(savedChecksum) .. " computed=" .. computed)
                            local toast = getToast()
                            if toast then toast.Warn("存档校验失败，数据可能已损坏") end
                            if callback then callback(false, "存档校验失败") end
                            return
                        end
                        print("[ManualSave] Checksum verified OK")
                    end

                    -- 解码 JSON 字符串为 table
                    local decOk, saveData = pcall(cjson.decode, json)
                    if not decOk or type(saveData) ~= "table" then
                        print("[ManualSave] JSON decode failed")
                        if callback then callback(false, "存档解析失败") end
                        return
                    end

                    -- 结构校验
                    if not SaveSystem.ValidateStructure(saveData) then
                        print("[ManualSave] Structure validation failed")
                        if callback then callback(false, "存档结构异常") end
                        return
                    end

                    -- 反序列化到 GameState
                    local desOk = SaveSystem.Deserialize(saveData)
                    if not desOk then
                        print("[ManualSave] Deserialize failed")
                        if callback then callback(false, "存档恢复失败") end
                        return
                    end

                    print("[ManualSave] Load OK, restored to Lv." .. GameState.player.level)
                    local toast = getToast()
                    if toast then toast.Success("手动存档恢复成功") end

                    -- 立即触发自动存档同步到云端
                    SaveSystem.SaveNow()

                    if callback then callback(true, "恢复成功") end
                end,
                error = function(code, reason)
                    loading_ = false
                    print("[ManualSave] Load error: " .. tostring(reason))
                    local toast = getToast()
                    if toast then toast.Warn("读取手动存档失败: " .. tostring(reason)) end
                    if callback then callback(false, "读取失败: " .. tostring(reason)) end
                end,
            })
    end)

    if not apiOk then
        loading_ = false
        if callback then callback(false, "云端 API 不可用") end
    end
end

--- 是否正在操作中
function ManualSave.IsBusy()
    return saving_ or loading_
end

return ManualSave
