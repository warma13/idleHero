-- InventoryCompare.lua
-- Equipment compare/detail overlay system.
-- Extracted sub-module from InventoryPage; uses the Install() pattern
-- to inject ShowCompare and CloseCompare onto the parent table.

local InventoryCompare = {}

function InventoryCompare.Install(Parent, shared)
    -- Parent = InventoryPage table
    -- shared = { overlayRoot, compareOverlay, compareSlotId, compareInvIdx, compareSource, gridDirty }
    -- shared fields are read/written by both main file and this module

    local Config     = require("Config")
    local GameState  = require("GameState")
    local SaveSystem = require("SaveSystem")
    local UI         = require("urhox-libs/UI")
    local Utils      = require("Utils")
    local Toast      = require("ui.Toast")
    local FloatTip   = require("ui.FloatTip")

    ---------------------------------------------------------------------------
    -- 打孔确认浮层 (自定义实现，避免 Modal.Confirm PushOverlay 卡死)
    ---------------------------------------------------------------------------
    ---@type Widget|nil
    local punchConfirmOverlay_ = nil
    ---@type Widget|nil
    local gemSocketOverlay_ = nil

    ---@param cost number
    ---@param owned number
    ---@param onConfirm fun()
    local function ShowPunchConfirm(cost, owned, onConfirm)
        local root = shared.overlayRoot
        if not root then return end
        if punchConfirmOverlay_ then
            root:RemoveChild(punchConfirmOverlay_)
            punchConfirmOverlay_ = nil
        end
        local function closeOverlay()
            if punchConfirmOverlay_ and root then
                root:RemoveChild(punchConfirmOverlay_)
            end
            punchConfirmOverlay_ = nil
        end
        punchConfirmOverlay_ = UI.Panel {
            position = "absolute", left = 0, top = 0,
            width = "100%", height = "100%",
            backgroundColor = { 0, 0, 0, 160 },
            zIndex = 500,
            justifyContent = "center", alignItems = "center",
            onClick = function() closeOverlay() end,
            children = {
                UI.Panel {
                    width = 280,
                    backgroundColor = { 28, 32, 48, 250 },
                    borderColor = { 80, 100, 160, 200 },
                    borderWidth = 1, borderRadius = 10,
                    padding = 20, gap = 14,
                    alignItems = "center",
                    onClick = function() end,  -- 阻止冒泡关闭
                    children = {
                        UI.Label {
                            text = "打孔确认",
                            fontSize = 16, fontWeight = "bold",
                            fontColor = { 220, 225, 240, 255 },
                        },
                        UI.Label {
                            text = "消耗 " .. cost .. " 个散光棱镜打孔？\n当前持有: " .. owned .. " 个",
                            fontSize = 13,
                            fontColor = { 170, 180, 200, 220 },
                            textAlign = "center",
                        },
                        UI.Panel {
                            flexDirection = "row", gap = 16,
                            justifyContent = "center",
                            marginTop = 4,
                            children = {
                                UI.Button {
                                    text = "取消", width = 90, height = 34, fontSize = 13,
                                    backgroundColor = { 60, 65, 80, 200 },
                                    onClick = function() closeOverlay() end,
                                },
                                UI.Button {
                                    text = "确认打孔", variant = "primary",
                                    width = 110, height = 34, fontSize = 13,
                                    onClick = function()
                                        closeOverlay()
                                        onConfirm()
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        }
        root:AddChild(punchConfirmOverlay_)
    end

    ---------------------------------------------------------------------------
    -- 拆卸宝石确认弹窗
    ---------------------------------------------------------------------------
    local unsocketConfirmOverlay_ = nil
    local function ShowUnsocketConfirm(gemName, onConfirm)
        local root = shared.overlayRoot
        if not root then return end
        if unsocketConfirmOverlay_ then
            root:RemoveChild(unsocketConfirmOverlay_)
            unsocketConfirmOverlay_ = nil
        end
        local function closeOverlay()
            if unsocketConfirmOverlay_ and root then
                root:RemoveChild(unsocketConfirmOverlay_)
            end
            unsocketConfirmOverlay_ = nil
        end
        unsocketConfirmOverlay_ = UI.Panel {
            position = "absolute", left = 0, top = 0,
            width = "100%", height = "100%",
            backgroundColor = { 0, 0, 0, 160 },
            zIndex = 500,
            justifyContent = "center", alignItems = "center",
            onClick = function() closeOverlay() end,
            children = {
                UI.Panel {
                    width = 260,
                    backgroundColor = { 28, 32, 48, 250 },
                    borderColor = { 80, 100, 160, 200 },
                    borderWidth = 1, borderRadius = 10,
                    padding = 20, gap = 14,
                    alignItems = "center",
                    onClick = function() end,
                    children = {
                        UI.Label {
                            text = "拆卸宝石",
                            fontSize = 16, fontWeight = "bold",
                            fontColor = { 220, 225, 240, 255 },
                        },
                        UI.Label {
                            text = "确认拆卸 " .. gemName .. " ？\n宝石将返还至背包",
                            fontSize = 13,
                            fontColor = { 170, 180, 200, 220 },
                            textAlign = "center",
                        },
                        UI.Panel {
                            flexDirection = "row", gap = 16,
                            justifyContent = "center",
                            marginTop = 4,
                            children = {
                                UI.Button {
                                    text = "取消", width = 90, height = 34, fontSize = 13,
                                    backgroundColor = { 60, 65, 80, 200 },
                                    onClick = function() closeOverlay() end,
                                },
                                UI.Button {
                                    text = "确认拆卸", variant = "primary",
                                    width = 110, height = 34, fontSize = 13,
                                    onClick = function()
                                        closeOverlay()
                                        onConfirm()
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        }
        root:AddChild(unsocketConfirmOverlay_)
    end

    ---------------------------------------------------------------------------
    -- BuildHalfCard  (one side of the compare view)
    ---------------------------------------------------------------------------
    local function BuildHalfCard(item, title, powerArrow, side)
        if not item then
            return UI.Panel {
                flexGrow = 1, flexBasis = 0, flexShrink = 1,
                padding = 6, gap = 2,
                children = {
                    UI.Label { text = title, fontSize = 10, fontColor = { 140, 150, 170, 200 }, fontWeight = "bold" },
                    UI.Label { text = "无装备", fontSize = 10, fontColor = { 80, 80, 80, 160 }, marginTop = 4 },
                },
            }
        end

        local c = item.qualityColor
        local iconPath = Config.GetEquipSlotIcon(item.slot, item.setId)

        -- 左侧文字列
        local textChildren = {}

        local nameText = item.name or ""
        local upgLv = item.upgradeLv or 0
        if upgLv > 0 then nameText = nameText .. " +" .. upgLv end
        local nameRow = {
            UI.Label { text = nameText, fontSize = 12, fontColor = { c[1], c[2], c[3], 255 }, fontWeight = "bold" },
        }
        if item.locked then
            table.insert(nameRow, UI.Panel {
                width = 12, height = 12,
                backgroundImage = "Textures/icon_lock.png",
                backgroundFit = "contain",
                pointerEvents = "none",
            })
        end
        table.insert(textChildren, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 3,
            children = nameRow,
        })

        local ip = item.itemPower or 0
        local ipText = "IP " .. ip
        if powerArrow then ipText = ipText .. " " .. powerArrow end
        local ipColor = powerArrow == "↑" and { 80, 255, 80, 230 } or { 130, 130, 130, 160 }
        table.insert(textChildren, UI.Label { text = ipText, fontSize = 10, fontColor = ipColor })

        local qualityText = item.qualityName or ""
        table.insert(textChildren, UI.Label { text = qualityText, fontSize = 8, fontColor = { c[1], c[2], c[3], 140 }, marginTop = 1 })

        -- 主属性 (固有, 金色高亮)
        if item.mainStatId and item.mainStatValue then
            local msDef = Config.AFFIX_POOL_MAP[item.mainStatId] or Config.EQUIP_STATS[item.mainStatId]
            local msName = msDef and msDef.name or item.mainStatId
            local msVal = GameState.FormatStatValue(item.mainStatId, item.mainStatValue)
            table.insert(textChildren, UI.Label {
                text = "◆ " .. msName .. " " .. msVal .. " [主属性]",
                fontSize = 9, fontColor = { 255, 220, 80, 240 },
            })
        end

        -- 统一词缀（桶分类颜色 + 标签）
        if item.affixes and #item.affixes > 0 then
            for _, aff in ipairs(item.affixes) do
                local def = Config.AFFIX_POOL_MAP[aff.id] or Config.EQUIP_STATS[aff.id]
                if def then
                    local prefix = aff.greater and "★ " or ""
                    local fc = (def.category and Config.AFFIX_CATEGORY_COLORS[def.category]) or { 190, 195, 200 }
                    local valStr = GameState.FormatStatValue(aff.id, aff.value)
                    local bucketTag = def.bucket and Config.AFFIX_BUCKET_LABELS[def.bucket] or ""
                    local label = prefix .. (def.name or aff.id) .. " " .. valStr
                    if bucketTag ~= "" then label = label .. " " .. bucketTag end
                    local mc = aff.milestoneCount or 0
                    if mc > 0 then label = label .. " (+" .. (mc * 2) .. "%)" end
                    table.insert(textChildren, UI.Label {
                        text = label,
                        fontSize = 9, fontColor = { fc[1], fc[2], fc[3], 210 },
                    })
                end
            end
        end

        -- 宝石孔位 (在图标下方显示)
        local gemSocketRow = nil
        if item.qualityIdx == 5 and item.sockets and item.sockets > 0 then
            local gemIcons = {}
            local gems = item.gems or {}
            for i = 1, item.sockets do
                local gem = gems[i]
                if gem then
                    table.insert(gemIcons, UI.Panel {
                        width = 14, height = 14,
                        backgroundImage = Config.GetGemIcon(gem.type, gem.quality),
                        backgroundFit = "contain",
                    })
                else
                    table.insert(gemIcons, UI.Panel {
                        width = 12, height = 12,
                        backgroundImage = "Textures/Gems/gem_socket_empty.png",
                        backgroundFit = "contain",
                    })
                end
            end
            gemSocketRow = UI.Panel {
                flexDirection = "row", gap = 3, alignItems = "center", justifyContent = "center",
                marginTop = 3,
                children = gemIcons,
            }
        end

        -- 套装效果
        local setChildren = {}
        if item.setId then
            local setCfg = Config.EQUIP_SET_MAP[item.setId]
            if setCfg then
                local sc = setCfg.color
                table.insert(setChildren, UI.Label { text = setCfg.name, fontSize = 9, fontColor = { sc[1], sc[2], sc[3], 220 }, marginTop = 2 })
                local setCounts = GameState.GetEquippedSetCounts()
                local curCount = setCounts[item.setId] or 0
                local thresholds = {}
                for k, _ in pairs(setCfg.bonuses) do table.insert(thresholds, k) end
                table.sort(thresholds)
                for _, threshold in ipairs(thresholds) do
                    local bonus = setCfg.bonuses[threshold]
                    local activated = curCount >= threshold
                    local prefix = "(" .. threshold .. "件) "
                    local fc = activated
                        and { sc[1], sc[2], sc[3], 255 }
                        or  { 100, 105, 115, 140 }
                    table.insert(setChildren, UI.Label {
                        text = prefix .. bonus.desc,
                        fontSize = 8,
                        fontColor = fc,
                    })
                end
            end
        end

        -- 右侧图标 + 宝石孔位纵向容器
        local iconColumn = nil
        if iconPath and iconPath ~= "" then
            local iconColumnChildren = {
                UI.Panel {
                    width = 48, height = 48,
                    flexShrink = 0,
                    backgroundColor = { c[1], c[2], c[3], 30 },
                    borderColor = { c[1], c[2], c[3], 80 },
                    borderWidth = 1, borderRadius = 6,
                    alignItems = "center", justifyContent = "center",
                    children = {
                        UI.Panel {
                            width = 38, height = 38,
                            backgroundImage = iconPath,
                            backgroundFit = "contain",
                            pointerEvents = "none",
                        },
                    },
                },
            }
            if gemSocketRow then
                table.insert(iconColumnChildren, gemSocketRow)
            end
            iconColumn = UI.Panel {
                flexShrink = 0,
                alignItems = "center",
                marginLeft = 4,
                children = iconColumnChildren,
            }
        elseif gemSocketRow then
            iconColumn = UI.Panel {
                flexShrink = 0,
                alignItems = "center",
                marginLeft = 4,
                children = { gemSocketRow },
            }
        end

        -- 横排：左文字 + 右图标列
        local rowChildren = {
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 1,
                children = textChildren,
            },
        }
        if iconColumn then
            table.insert(rowChildren, iconColumn)
        end

        -- 整体：标题 + 横排内容 + 套装效果
        local cardChildren = {
            UI.Label { text = title, fontSize = 10, fontColor = { 140, 150, 170, 220 }, fontWeight = "bold" },
            UI.Panel {
                flexDirection = "row", alignItems = "flex-start", width = "100%",
                children = rowChildren,
            },
        }
        for _, sc in ipairs(setChildren) do
            table.insert(cardChildren, sc)
        end

        return UI.Panel {
            flexGrow = 1, flexBasis = 0, flexShrink = 1,
            padding = 6, gap = 1,
            children = cardChildren,
        }
    end

    ---------------------------------------------------------------------------
    -- BuildDetailCard  (single-card detail view for equipped items)
    ---------------------------------------------------------------------------
    local function BuildDetailCard(item)
        local c = item.qualityColor
        local children = {}

        -- 装备图标 + 名称横排
        local iconPath = Config.GetEquipSlotIcon(item.slot, item.setId)
        local nameText = item.name or ""
        local upgLv = item.upgradeLv or 0
        if upgLv > 0 then nameText = nameText .. " +" .. upgLv end
        local nameRow = {}
        if iconPath and iconPath ~= "" then
            table.insert(nameRow, UI.Panel {
                width = 36, height = 36,
                backgroundColor = { c[1], c[2], c[3], 30 },
                borderColor = { c[1], c[2], c[3], 80 },
                borderWidth = 1, borderRadius = 6,
                alignItems = "center", justifyContent = "center",
                children = {
                    UI.Panel {
                        width = 28, height = 28,
                        backgroundImage = iconPath,
                        backgroundFit = "contain",
                        pointerEvents = "none",
                    },
                },
            })
        end
        table.insert(nameRow, UI.Label { text = nameText, fontSize = 13, fontColor = { c[1], c[2], c[3], 255 }, fontWeight = "bold" })
        if item.locked then
            table.insert(nameRow, UI.Panel {
                width = 14, height = 14,
                backgroundImage = "Textures/icon_lock.png",
                backgroundFit = "contain",
                pointerEvents = "none",
            })
        end
        -- ---- Header left column ----
        local headerLeftChildren = {}
        table.insert(headerLeftChildren, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            children = nameRow,
        })

        local ip = item.itemPower or 0
        table.insert(headerLeftChildren, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 8, marginTop = 2,
            children = {
                UI.Label { text = "IP " .. ip, fontSize = 10, fontColor = { 255, 215, 0, 230 } },
                UI.Label { text = item.qualityName or "", fontSize = 9, fontColor = { c[1], c[2], c[3], 180 } },
            },
        })

        local q = Config.EQUIP_QUALITY[item.qualityIdx]
        local maxLv = q and q.maxUpgrade or 0
        if maxLv > 0 then
            local curLv = item.upgradeLv or 0
            table.insert(headerLeftChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, marginTop = 2,
                children = {
                    UI.Label { text = "强化 Lv." .. curLv .. "/" .. maxLv, fontSize = 8, fontColor = { 180, 220, 255, 200 } },
                    UI.Panel {
                        width = 60, height = 5, backgroundColor = { 40, 45, 55, 200 }, borderRadius = 2,
                        children = {
                            UI.Panel {
                                width = math.floor(60 * curLv / maxLv), height = 5,
                                backgroundColor = { 80, 180, 255, 220 }, borderRadius = 2,
                            },
                        },
                    },
                },
            })
        end

        -- ---- Header right column: gem sockets (orange items only) ----
        local socketPanel = nil
        if item.qualityIdx == 5 then
            local socketChildren = {}
            local sockets = item.sockets or 0
            local gems = item.gems or {}
            local prismCount = GameState.GetBagItemCount("prism")
            for i = 1, Config.MAX_SOCKETS do
                local gem = gems[i]
                if i <= sockets then
                    -- 已开孔: 有宝石 or 空孔位
                    if gem then
                        local gemType = Config.GEM_TYPE_MAP[gem.type]
                        local gemQual = Config.GEM_QUALITIES[gem.quality]
                        local gc = gemType and gemType.color or { 180, 180, 180 }
                        local qName = gemQual and gemQual.name or ""
                        local gemIcon = UI.Panel {
                            width = 36, height = 36,
                            backgroundImage = Config.GetGemIcon(gem.type, gem.quality),
                            backgroundFit = "contain",
                            pointerEvents = "none",
                            imageTint = { 180, 180, 180, 220 },
                        }
                        local socketIdx = i
                        local gemName = (qName) .. (gemType and gemType.name or "")
                        local gemSocket = UI.Panel {
                            width = 44, height = 44,
                            borderRadius = 6,
                            backgroundImage = "Textures/Gems/gem_socket_empty.png",
                            backgroundFit = "contain",
                            alignItems = "center", justifyContent = "center",
                            onClick = Utils.Debounce(function()
                                local sid = shared.compareSlotId
                                if not sid then return end
                                ShowUnsocketConfirm(gemName, function()
                                    local ok, msg = GameState.UnsocketGem(sid, socketIdx)
                                    if ok then
                                        Toast.Success("拆卸成功: " .. gemName)
                                    else
                                        Toast.Warn(msg or "拆卸失败")
                                    end
                                    shared.gridDirty = true
                                    Parent.CloseCompare()
                                    Parent.Refresh()
                                    Parent.ShowCompare(sid, nil, "equipped")
                                end)
                            end, 0.3),
                            children = { gemIcon },
                        }
                        gemSocket.props.onPointerEnter = function()
                            gemIcon:SetStyle({ imageTint = { 255, 255, 255, 255 } })
                        end
                        gemSocket.props.onPointerLeave = function()
                            gemIcon:SetStyle({ imageTint = { 180, 180, 180, 220 } })
                        end
                        table.insert(socketChildren, gemSocket)
                    else
                        -- 空孔位 — 悬浮图片变亮，点击镶嵌
                        local emptySocket = UI.Panel {
                            width = 44, height = 44,
                            backgroundImage = "Textures/Gems/gem_socket_empty.png",
                            backgroundFit = "contain",
                            borderRadius = 6,
                            imageTint = { 160, 170, 190, 180 },
                            onClick = Utils.Debounce(function()
                                local sid = shared.compareSlotId
                                if sid then
                                    Parent.ShowGemSocketPanel(sid, i)
                                end
                            end, 0.3),
                        }
                        emptySocket.props.onPointerEnter = function()
                            emptySocket:SetStyle({ imageTint = { 255, 255, 255, 255 } })
                        end
                        emptySocket.props.onPointerLeave = function()
                            emptySocket:SetStyle({ imageTint = { 160, 170, 190, 180 } })
                        end
                        table.insert(socketChildren, emptySocket)
                    end
                else
                    -- 未开孔: 锁定孔位 — 悬浮图片变亮，点击打孔
                    local punchCost = Config.PUNCH_COSTS[sockets + 1] or 999
                    local hasPrism = prismCount >= punchCost
                    local lockedSocket = UI.Panel {
                        width = 44, height = 44,
                        backgroundImage = "Textures/Gems/gem_socket_locked.png",
                        backgroundFit = "contain",
                        borderRadius = 6,
                        imageTint = { 130, 130, 140, 160 },
                        onClick = Utils.Debounce(function()
                            local sid = shared.compareSlotId
                            if not sid then return end
                            if not hasPrism then
                                Toast.Warn("散光棱镜不足 (" .. prismCount .. "/" .. punchCost .. ")")
                                return
                            end
                            ShowPunchConfirm(punchCost, prismCount, function()
                                local ok, msg = GameState.PunchSocket(sid)
                                if ok then
                                    Toast.Success(msg)
                                else
                                    Toast.Warn(msg)
                                end
                                shared.compareSlotId = nil
                                shared.gridDirty = true
                                Parent.ShowCompare(sid, nil, "equipped")
                                Parent.Refresh()
                            end)
                        end, 0.3),
                    }
                    lockedSocket.props.onPointerEnter = function()
                        lockedSocket:SetStyle({ imageTint = { 220, 225, 240, 255 } })
                    end
                    lockedSocket.props.onPointerLeave = function()
                        lockedSocket:SetStyle({ imageTint = { 130, 130, 140, 160 } })
                    end
                    table.insert(socketChildren, lockedSocket)
                end
            end
            socketPanel = UI.Panel {
                flexShrink = 0,
                flexDirection = "row", gap = 4,
                alignItems = "center",
                marginLeft = 6,
                children = socketChildren,
            }
        end

        -- ---- Combine header row ----
        local headerRowChildren = {
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 2,
                children = headerLeftChildren,
            },
        }
        if socketPanel then
            table.insert(headerRowChildren, socketPanel)
        end
        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center", width = "100%",
            children = headerRowChildren,
        })

        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 70, 90, 120 }, marginTop = 4, marginBottom = 2 })

        -- ==== 左列: 主属性 + 统一词缀  |  右列: 宝石属性 ====
        local leftColChildren = {}

        -- 主属性 (固有, 金色高亮)
        if item.mainStatId and item.mainStatValue then
            local msDef = Config.AFFIX_POOL_MAP[item.mainStatId] or Config.EQUIP_STATS[item.mainStatId]
            local msName = msDef and msDef.name or item.mainStatId
            local msVal = GameState.FormatStatValue(item.mainStatId, item.mainStatValue)
            table.insert(leftColChildren, UI.Label {
                text = "◆ " .. msName .. " " .. msVal .. " [主属性]",
                fontSize = 9, fontColor = { 255, 220, 80, 240 },
            })
        end

        if item.affixes and #item.affixes > 0 then
            for _, aff in ipairs(item.affixes) do
                local def = Config.AFFIX_POOL_MAP[aff.id] or Config.EQUIP_STATS[aff.id]
                if def then
                    local prefix = aff.greater and "★ " or ""
                    local fc = (def.category and Config.AFFIX_CATEGORY_COLORS[def.category]) or { 190, 195, 200 }
                    local valStr = GameState.FormatStatValue(aff.id, aff.value)
                    local bucketTag = def.bucket and Config.AFFIX_BUCKET_LABELS[def.bucket] or ""
                    local label = prefix .. (def.name or aff.id) .. " " .. valStr
                    if bucketTag ~= "" then label = label .. " " .. bucketTag end
                    local mc = aff.milestoneCount or 0
                    if mc > 0 then label = label .. " (+" .. (mc * 2) .. "%)" end
                    table.insert(leftColChildren, UI.Label {
                        text = label,
                        fontSize = 9, fontColor = { fc[1], fc[2], fc[3], 210 },
                    })
                end
            end
        end

        -- 右列: 宝石属性
        local rightColChildren = {}
        if item.qualityIdx == 5 and item.sockets and item.sockets > 0 then
            local gems = item.gems or {}
            local hasAnyGem = false
            for i = 1, item.sockets do
                if gems[i] then hasAnyGem = true; break end
            end
            if hasAnyGem then
                table.insert(rightColChildren, UI.Label { text = "宝石属性", fontSize = 8, fontColor = { 140, 180, 220, 180 }, marginBottom = 2 })
                local category = Config.EQUIP_CATEGORIES[item.slot]
                for i = 1, item.sockets do
                    local gem = gems[i]
                    if gem then
                        local gemType = Config.GEM_TYPE_MAP[gem.type]
                        local gemQual = Config.GEM_QUALITIES[gem.quality]
                        local gc = gemType and gemType.color or { 180, 180, 180 }
                        local gemName = (gemQual and gemQual.name or "") .. (gemType and gemType.name or "")
                        local statKey, statVal = Config.CalcGemStat(gem.type, gem.quality, category, Config.IPToTierMul(item.itemPower))
                        local statText = ""
                        if statKey == "allRes" then
                            statText = "全抗 " .. GameState.FormatStatValue("fireRes", statVal)
                        else
                            local sd = Config.EQUIP_STATS[statKey]
                            statText = (sd and sd.name or statKey) .. " " .. GameState.FormatStatValue(statKey, statVal)
                        end
                        table.insert(rightColChildren, UI.Panel {
                            flexDirection = "row", alignItems = "center", gap = 4,
                            children = {
                                UI.Panel {
                                    width = 16, height = 16,
                                    backgroundImage = Config.GetGemIcon(gem.type, gem.quality),
                                    backgroundFit = "contain",
                                },
                                UI.Label { text = statText, fontSize = 8, fontColor = { 140, 200, 140, 200 } },
                            },
                        })
                    end
                end
            end
        end

        -- 双列容器
        local statsRowChildren = {
            UI.Panel { flexShrink = 1, flex = 1, gap = 2, children = leftColChildren },
        }
        if #rightColChildren > 0 then
            table.insert(statsRowChildren, UI.Panel {
                flexShrink = 1, flex = 1, gap = 2,
                paddingLeft = 8,
                borderLeftWidth = 1, borderColor = { 60, 70, 90, 100 },
                children = rightColChildren,
            })
        end
        table.insert(children, UI.Panel {
            flexDirection = "row", width = "100%", gap = 6,
            children = statsRowChildren,
        })

        if item.setId then
            local setCfg = Config.EQUIP_SET_MAP[item.setId]
            if setCfg then
                local sc = setCfg.color
                table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 70, 90, 120 }, marginTop = 4, marginBottom = 2 })
                table.insert(children, UI.Label { text = setCfg.name, fontSize = 9, fontColor = { sc[1], sc[2], sc[3], 230 }, fontWeight = "bold" })
                local setCounts = GameState.GetEquippedSetCounts()
                local curCount = setCounts[item.setId] or 0
                local thresholds = {}
                for k, _ in pairs(setCfg.bonuses) do table.insert(thresholds, k) end
                table.sort(thresholds)
                for _, threshold in ipairs(thresholds) do
                    local bonus = setCfg.bonuses[threshold]
                    local activated = curCount >= threshold
                    local fc = activated
                        and { sc[1], sc[2], sc[3], 255 }
                        or  { 100, 105, 115, 140 }
                    table.insert(children, UI.Label {
                        text = "(" .. threshold .. "件) " .. bonus.desc,
                        fontSize = 8, fontColor = fc,
                    })
                end
            end
        end

        return UI.Panel {
            width = "100%",
            padding = 10, gap = 2,
            children = children,
        }
    end

    ---------------------------------------------------------------------------
    -- CloseCompare
    ---------------------------------------------------------------------------
    Parent.CloseCompare = function()
        -- 关闭镶嵌面板覆盖层（如果存在）
        if gemSocketOverlay_ and shared.overlayRoot then
            shared.overlayRoot:RemoveChild(gemSocketOverlay_)
            gemSocketOverlay_ = nil
        end
        if shared.compareOverlay then
            shared.compareOverlay:Destroy()
            shared.compareOverlay = nil
            shared.compareSlotId = nil
            shared.compareInvIdx = nil
            shared.compareSource = nil
            if shared.gridDirty then
                Parent.Refresh()
            end
        end
    end

    ---------------------------------------------------------------------------
    -- ShowCompare
    ---------------------------------------------------------------------------
    Parent.ShowCompare = function(slotId, invIndex, source)
        -- 点击同一件装备 → 关闭（toggle）
        if shared.compareOverlay and shared.compareSource == source and shared.compareSlotId == slotId and shared.compareInvIdx == invIndex then
            Parent.CloseCompare()
            return
        end

        -- 关闭旧浮层
        Parent.CloseCompare()

        local equipped = GameState.equipment[slotId]
        local newItem = invIndex and GameState.inventory[invIndex] or nil

        -- ================================================================
        -- 已穿戴装备 → 单卡详情面板
        -- ================================================================
        if source == "equipped" then
            if not equipped then return end

            local c = equipped.qualityColor
            local headerBg = { math.floor(c[1] * 0.25 + 20), math.floor(c[2] * 0.25 + 20), math.floor(c[3] * 0.25 + 20), 250 }

            -- 升级按钮
            local actionBtns = {}
            local canUp, reason, isEndgame = GameState.CanUpgradeEquip(equipped)
            local curLv = equipped.upgradeLv or 0
            local q = Config.EQUIP_QUALITY[equipped.qualityIdx]
            local maxLv = q and q.maxUpgrade or 0
            -- 终局强化: 橙装满级且未终局强化
            local showEndgame = isEndgame

            -- 构建升级按钮内容: 材料图标 (可升级时仅显示材料消耗)
            local upgBtnChildren = {}
            local btnLabel
            if maxLv <= 0 then
                btnLabel = "无法升级"
            elseif showEndgame then
                btnLabel = "终局强化"
            elseif curLv >= maxLv then
                btnLabel = "已满级"
            end
            if btnLabel then
                table.insert(upgBtnChildren, UI.Label {
                    text = btnLabel, fontSize = 11,
                    fontColor = { 255, 255, 255, 240 },
                    pointerEvents = "none",
                })
            end

            -- 材料消耗图标 (仅可升级时显示)
            if maxLv > 0 and (curLv < maxLv or showEndgame) then
                local costEntry = Config.UpgradeCost(equipped.qualityIdx, curLv)
                if costEntry then
                    -- 金币图标
                    if costEntry.gold and costEntry.gold > 0 then
                        table.insert(upgBtnChildren, UI.Panel {
                            width = 14, height = 14, marginLeft = 6,
                            backgroundImage = Config.GOLD_ICON,
                            backgroundFit = "contain",
                            pointerEvents = "none",
                        })
                        table.insert(upgBtnChildren, UI.Label {
                            text = tostring(costEntry.gold), fontSize = 10,
                            fontColor = { 255, 215, 0, 230 }, marginLeft = 1,
                            pointerEvents = "none",
                        })
                    end
                    -- 材料图标
                    if costEntry.mats then
                        for matId, amt in pairs(costEntry.mats) do
                            local matDef = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                            local iconPath = Config.MATERIAL_ICON_PATHS[matId]
                            local mc = matDef and matDef.color or { 200, 200, 200 }
                            if iconPath then
                                table.insert(upgBtnChildren, UI.Panel {
                                    width = 14, height = 14, marginLeft = 5,
                                    backgroundImage = iconPath,
                                    backgroundFit = "contain",
                                    pointerEvents = "none",
                                })
                            end
                            table.insert(upgBtnChildren, UI.Label {
                                text = tostring(amt), fontSize = 10,
                                fontColor = { mc[1], mc[2], mc[3], 230 }, marginLeft = 1,
                                pointerEvents = "none",
                            })
                        end
                    end
                end
            end

            table.insert(actionBtns, UI.Button {
                height = 30, fontSize = 12,
                flexGrow = 1, flexBasis = 0,
                flexDirection = "row", alignItems = "center", justifyContent = "center",
                flexWrap = "nowrap",
                backgroundColor = canUp and { 50, 120, 220, 230 } or { 60, 65, 75, 200 },
                children = upgBtnChildren,
                onClick = Utils.Debounce(function()
                    if not canUp then return end
                    local ok, msg = GameState.UpgradeEquip(slotId)
                    if ok then
                        local eqName = GameState.equipment[slotId] and GameState.equipment[slotId].name or "装备"
                        FloatTip.Upgrade(eqName .. " " .. (msg or "升级成功"))
                        -- 清除身份后重新打开，避免 toggle 逻辑误关
                        shared.compareSlotId = nil
                        Parent.ShowCompare(slotId, nil, "equipped")
                        Parent.Refresh()
                    end
                end, 0.3),
            })
            -- 锁定/解锁按钮
            local isLocked = equipped.locked
            table.insert(actionBtns, UI.Button {
                text = isLocked and "解锁" or "锁定",
                height = 30, fontSize = 12,
                width = 56,
                backgroundColor = isLocked and { 180, 150, 40, 220 } or { 70, 75, 85, 200 },
                onClick = Utils.Debounce(function()
                    GameState.ToggleEquipLock(slotId)
                    shared.gridDirty = true
                    shared.compareSlotId = nil
                    Parent.ShowCompare(slotId, nil, "equipped")
                end, 0.3),
            })
            -- IP注入按钮 (蓝色品质以上，且有可用魔法石时显示)
            local stones = GameState.GetAvailableMagicStones(equipped)
            local hasStones = #stones > 0
            local infuseBtnText = "IP注入"
            if equipped.qualityIdx < 3 then
                infuseBtnText = "注入(需蓝+)"
            elseif not hasStones then
                infuseBtnText = "注入(无石)"
            end
            local canInfuse = equipped.qualityIdx >= 3 and hasStones
            table.insert(actionBtns, UI.Button {
                text = infuseBtnText,
                height = 30, fontSize = 11,
                flexGrow = 1, flexBasis = 0,
                backgroundColor = canInfuse and { 180, 120, 40, 230 } or { 60, 65, 75, 200 },
                onClick = Utils.Debounce(function()
                    if not canInfuse then
                        if equipped.qualityIdx < 3 then
                            Toast.Warn("蓝色品质以上才能IP注入")
                        else
                            Toast.Warn("没有可用的魔法石")
                        end
                        return
                    end
                    Parent.CloseCompare()
                    Parent.ShowInfusePanel(slotId)
                end, 0.3),
            })
            -- 卸下按钮
            table.insert(actionBtns, UI.Button {
                text = "卸下",
                height = 30, fontSize = 12,
                width = 56,
                backgroundColor = { 140, 60, 60, 220 },
                onClick = Utils.Debounce(function()
                    if #GameState.inventory >= GameState.GetInventorySize() then
                        Toast.Warn("背包已满，无法卸下")
                        return
                    end
                    local item = GameState.equipment[slotId]
                    if not item then return end
                    local itemName = item.name or "装备"
                    table.insert(GameState.inventory, item)
                    GameState.equipment[slotId] = nil
                    SaveSystem.SaveNow()
                    shared.gridDirty = true
                    FloatTip.Equip("已卸下 " .. itemName)
                    Parent.CloseCompare()
                    Parent.Refresh()
                    require("ui.TabBar").MarkAllDirty()
                    Toast.Success("已卸下 " .. itemName)
                end, 0.3),
            })

            local panelChildren = {
                -- 标题栏
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    width = "100%",
                    backgroundColor = headerBg,
                    paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
                    children = {
                        UI.Label { text = "装备详情", fontSize = 12, fontColor = { 200, 210, 230, 245 } },
                        UI.Panel {
                            width = 24, height = 24,
                            backgroundColor = { 160, 50, 50, 200 },
                            borderRadius = 12,
                            alignItems = "center", justifyContent = "center",
                            onClick = function() Parent.CloseCompare() end,
                            children = {
                                UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                            },
                        },
                    },
                },
                -- 装备详情卡
                BuildDetailCard(equipped),
                -- 操作按钮
                UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%",
                    paddingLeft = 8, paddingRight = 8, paddingBottom = 2,
                    children = actionBtns,
                },
            }

            -- 底部间距
            do
                local lastBtn = panelChildren[#panelChildren]
                if lastBtn then lastBtn.paddingBottom = 6 end
            end

            shared.compareOverlay = UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = "50%",
                zIndex = 200,
                paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
                children = {
                    UI.Panel {
                        width = "100%",
                        backgroundColor = { 18, 22, 34, 245 },
                        borderColor = { 60, 70, 95, 200 },
                        borderWidth = 1, borderRadius = 8,
                        gap = 4,
                        overflow = "hidden",
                        children = panelChildren,
                    },
                },
            }

            local root = shared.overlayRoot
            if root then root:AddChild(shared.compareOverlay) end
            shared.compareSlotId = slotId
            shared.compareInvIdx = invIndex
            shared.compareSource = source
            return
        end

        -- ================================================================
        -- 背包装备 → 对比面板（原有逻辑）
        -- ================================================================
        local equippedIP = equipped and (equipped.itemPower or 0) or 0
        local newIP = newItem and (newItem.itemPower or 0) or 0

        local leftItem = newItem
        local leftTitle = "新装备"
        local leftArrow = (newIP > equippedIP) and "↑" or nil
        local rightItem = equipped
        local rightTitle = "当前穿戴"
        local rightArrow = (equippedIP > newIP) and "↑" or nil

        local headerBg = { 35, 40, 55, 250 }
        local headerItem = leftItem or rightItem
        if headerItem and headerItem.qualityColor then
            local lc = headerItem.qualityColor
            headerBg = { math.floor(lc[1] * 0.25 + 20), math.floor(lc[2] * 0.25 + 20), math.floor(lc[3] * 0.25 + 20), 250 }
        end

        local cardsRow = {}
        table.insert(cardsRow, BuildHalfCard(leftItem, leftTitle, leftArrow, "left"))
        table.insert(cardsRow, UI.Panel {
            width = 24, alignSelf = "center",
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label { text = "→", fontSize = 16, fontColor = { 180, 190, 210, 200 } },
            },
        })
        table.insert(cardsRow, BuildHalfCard(rightItem, rightTitle, rightArrow, "right"))

        local actionBtns = {}
        if invIndex then
            local invItem = GameState.inventory[invIndex]
            local invLocked = invItem and invItem.locked
            table.insert(actionBtns, UI.Button {
                text = "穿戴", height = 28, fontSize = 11, variant = "primary",
                flexGrow = 1, flexBasis = 0,
                onClick = Utils.Debounce(function()
                    local itemName = GameState.inventory[invIndex] and GameState.inventory[invIndex].name or "装备"
                    GameState.EquipItem(invIndex)
                    SaveSystem.MarkDirty()
                    FloatTip.Equip("已穿戴 " .. itemName)
                    Parent.CloseCompare()
                    Parent.Refresh()
                    require("ui.TabBar").MarkAllDirty()
                end, 0.3),
            })
            table.insert(actionBtns, UI.Button {
                text = "分解", height = 28, fontSize = 11,
                flexGrow = 1, flexBasis = 0,
                backgroundColor = invLocked and { 80, 80, 80, 150 } or { 120, 60, 60, 200 },
                onClick = Utils.Debounce(function()
                    if invLocked then return end
                    -- 橙装分解二次确认
                    local item = GameState.inventory[invIndex]
                    if item and item.qualityIdx >= 5 then
                        InventoryCompare.ShowDecomposeConfirm(item, invIndex)
                        return
                    end
                    local itemName = item and item.name or "装备"
                    local gold, mats = GameState.DecomposeItem(invIndex)
                    if gold > 0 or (mats and next(mats)) then
                        local matParts = {}
                        if mats then
                            for matId, amt in pairs(mats) do
                                local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                                table.insert(matParts, amt .. (def and def.name or matId))
                            end
                        end
                        FloatTip.Decompose("分解 " .. itemName .. " → " .. table.concat(matParts, " + "))
                        print("分解获得 " .. gold .. " 金币, " .. table.concat(matParts, " + "))
                        SaveSystem.MarkDirty()
                    end
                    Parent.CloseCompare()
                    Parent.Refresh()
                end, 0.3),
            })
            table.insert(actionBtns, UI.Button {
                text = invLocked and "解锁" or "锁定",
                height = 28, fontSize = 11,
                width = 46,
                backgroundColor = invLocked and { 180, 150, 40, 220 } or { 70, 75, 85, 200 },
                onClick = Utils.Debounce(function()
                    GameState.ToggleLock(invIndex)
                    shared.gridDirty = true
                    shared.compareSlotId = nil
                    shared.compareInvIdx = nil
                    Parent.ShowCompare(slotId, invIndex, "inventory")
                end, 0.3),
            })
        end

        local panelChildren = {
            UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                width = "100%",
                backgroundColor = headerBg,
                paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
                children = {
                    UI.Label { text = "装备对比", fontSize = 12, fontColor = { 200, 210, 230, 245 } },
                    UI.Panel {
                        width = 24, height = 24,
                        backgroundColor = { 160, 50, 50, 200 },
                        borderRadius = 12,
                        alignItems = "center", justifyContent = "center",
                        onClick = function() Parent.CloseCompare() end,
                        children = {
                            UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                        },
                    },
                },
            },
            UI.Panel {
                flexDirection = "row", width = "100%",
                children = cardsRow,
            },
        }

        if #actionBtns > 0 then
            table.insert(panelChildren, UI.Panel {
                flexDirection = "row", width = "100%",
                paddingBottom = 6,
                children = {
                    UI.Panel {
                        width = "50%",
                        flexDirection = "row", gap = 4,
                        paddingLeft = 8, paddingRight = 4,
                        children = actionBtns,
                    },
                },
            })
        end

        shared.compareOverlay = UI.Panel {
            position = "absolute",
            left = 0, right = 0, bottom = "50%",
            zIndex = 200,
            paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
            children = {
                UI.Panel {
                    width = "100%",
                    backgroundColor = { 18, 22, 34, 245 },
                    borderColor = { 60, 70, 95, 200 },
                    borderWidth = 1, borderRadius = 8,
                    gap = 4,
                    overflow = "hidden",
                    children = panelChildren,
                },
            },
        }

        local root = shared.overlayRoot
        if root then
            root:AddChild(shared.compareOverlay)
        end
        shared.compareSlotId = slotId
        shared.compareInvIdx = invIndex
        shared.compareSource = source
    end

    ---------------------------------------------------------------------------
    -- ShowInfusePanel: 魔法石 IP 注入确认面板
    ---------------------------------------------------------------------------
    Parent.ShowInfusePanel = function(slotId)
        local equipped = GameState.equipment[slotId]
        if not equipped then return end

        Parent.CloseCompare()

        local stones = GameState.GetAvailableMagicStones(equipped)
        if #stones == 0 then
            Toast.Warn("没有可用的魔法石")
            return
        end

        -- 默认选中第一个可用的魔法石
        local selectedIdx = 1
        for i, s in ipairs(stones) do
            if s.canUse then selectedIdx = i; break end
        end

        local function buildPanel()
            local sel = stones[selectedIdx]
            local preview = sel and sel.canUse and GameState.PreviewInfuse(equipped, sel.targetTier) or nil

            -- 魔法石选择列表
            local stoneButtons = {}
            for i, s in ipairs(stones) do
                local isSel = (i == selectedIdx)
                table.insert(stoneButtons, UI.Button {
                    text = s.name .. " x" .. s.count,
                    height = 26, fontSize = 11,
                    flexGrow = 1, flexBasis = 0,
                    backgroundColor = isSel
                        and (s.canUse and { s.color[1], s.color[2], s.color[3], 220 } or { 80, 80, 80, 200 })
                        or { 40, 44, 55, 200 },
                    borderWidth = isSel and 2 or 0,
                    borderColor = { 255, 255, 255, isSel and 180 or 0 },
                    onClick = function()
                        selectedIdx = i
                        Parent.CloseCompare()
                        Parent.ShowInfusePanel(slotId)
                    end,
                })
            end

            -- 词缀预览
            local previewChildren = {}
            if preview and sel then
                -- IP 变化
                local oldIP = equipped.itemPower or 100
                table.insert(previewChildren, UI.Panel {
                    flexDirection = "row", width = "100%", gap = 4, paddingLeft = 6, paddingRight = 6,
                    children = {
                        UI.Label { text = "Item Power", fontSize = 11, fontColor = { 255, 220, 80, 240 }, flexGrow = 1, fontWeight = "bold" },
                        UI.Label { text = tostring(oldIP), fontSize = 11, fontColor = { 160, 160, 160, 180 } },
                        UI.Label { text = "->", fontSize = 11, fontColor = { 255, 220, 80, 220 } },
                        UI.Label { text = tostring(preview.itemPower), fontSize = 11, fontColor = { 100, 255, 100, 240 }, fontWeight = "bold" },
                    },
                })

                -- 词缀值变化对比
                if equipped.affixes then
                    for i, aff in ipairs(equipped.affixes) do
                        local pAff = preview.affixes[i]
                        local def = Config.AFFIX_POOL_MAP[aff.id] or Config.EQUIP_STATS[aff.id]
                        local affName = def and def.name or aff.id
                        local oldVal = GameState.FormatStatValue(aff.id, aff.value)
                        local newVal = pAff and GameState.FormatStatValue(aff.id, pAff.value) or oldVal
                        local greaterMark = aff.greater and " *" or ""
                        table.insert(previewChildren, UI.Panel {
                            flexDirection = "row", width = "100%", gap = 4, paddingLeft = 6, paddingRight = 6,
                            children = {
                                UI.Label { text = affName .. greaterMark, fontSize = 10, fontColor = aff.greater and { 255, 180, 60, 220 } or { 150, 160, 180, 200 }, flexGrow = 1 },
                                UI.Label { text = oldVal, fontSize = 10, fontColor = { 140, 140, 140, 160 } },
                                UI.Label { text = "->", fontSize = 10, fontColor = { 255, 220, 80, 200 } },
                                UI.Label { text = newVal, fontSize = 10, fontColor = { 100, 255, 100, 220 } },
                            },
                        })
                    end
                end
            elseif sel and not sel.canUse then
                table.insert(previewChildren, UI.Label {
                    text = sel.reason or "无法使用",
                    fontSize = 11, fontColor = { 255, 100, 100, 220 },
                    textAlign = "center", width = "100%", marginTop = 8, marginBottom = 8,
                })
            end

            local panelChildren = {
                -- 标题栏
                UI.Panel {
                    flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    width = "100%",
                    backgroundColor = { 80, 60, 20, 250 },
                    paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
                    children = {
                        UI.Label { text = "IP注入 - " .. (equipped.name or "装备") .. " (IP " .. (equipped.itemPower or 100) .. ")", fontSize = 12, fontColor = { 255, 220, 120, 245 } },
                        UI.Panel {
                            width = 24, height = 24,
                            backgroundColor = { 160, 50, 50, 200 },
                            borderRadius = 12,
                            alignItems = "center", justifyContent = "center",
                            onClick = function() Parent.CloseCompare() end,
                            children = {
                                UI.Label { text = "X", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                            },
                        },
                    },
                },
                -- 选择魔法石
                UI.Label { text = "选择魔法石:", fontSize = 11, fontColor = { 180, 190, 210, 200 }, paddingLeft = 8, paddingTop = 4 },
                UI.Panel {
                    flexDirection = "row", gap = 4, width = "100%",
                    paddingLeft = 8, paddingRight = 8, flexWrap = "wrap",
                    children = stoneButtons,
                },
                -- 词缀变化预览
                UI.Label { text = "词缀变化预览:", fontSize = 11, fontColor = { 180, 190, 210, 200 }, paddingLeft = 8, paddingTop = 6 },
                UI.Panel {
                    width = "100%", gap = 2, paddingBottom = 4,
                    children = previewChildren,
                },
                -- 确认/取消按钮
                UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%",
                    paddingLeft = 8, paddingRight = 8, paddingBottom = 8, paddingTop = 4,
                    children = {
                        UI.Button {
                            text = "确认注入",
                            height = 32, fontSize = 13, fontWeight = "bold",
                            flexGrow = 1, flexBasis = 0,
                            backgroundColor = (sel and sel.canUse) and { 200, 140, 30, 240 } or { 60, 65, 75, 200 },
                            onClick = Utils.Debounce(function()
                                if not sel or not sel.canUse then
                                    Toast.Warn(sel and sel.reason or "无法使用")
                                    return
                                end
                                local ok, msg = GameState.InfuseEquip(slotId, sel.itemId)
                                if ok then
                                    Toast.Success(msg)
                                else
                                    Toast.Warn(msg)
                                end
                                Parent.CloseCompare()
                                Parent.Refresh()
                            end, 0.3),
                        },
                        UI.Button {
                            text = "取消",
                            height = 32, fontSize = 12,
                            width = 64,
                            backgroundColor = { 70, 75, 85, 220 },
                            onClick = function()
                                Parent.CloseCompare()
                            end,
                        },
                    },
                },
            }

            return panelChildren
        end

        local panelChildren = buildPanel()

        shared.compareOverlay = UI.Panel {
            position = "absolute",
            left = 0, right = 0, bottom = "50%",
            zIndex = 200,
            paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
            children = {
                UI.Panel {
                    width = "100%",
                    backgroundColor = { 18, 22, 34, 245 },
                    borderColor = { 180, 140, 40, 200 },
                    borderWidth = 1, borderRadius = 8,
                    gap = 4,
                    overflow = "hidden",
                    children = panelChildren,
                },
            },
        }

        local root = shared.overlayRoot
        if root then root:AddChild(shared.compareOverlay) end
        shared.compareSlotId = slotId
        shared.compareInvIdx = nil
        shared.compareSource = "infuse"
    end
    -- 兼容旧引用
    Parent.ShowTierUpgradePanel = Parent.ShowInfusePanel

    ---------------------------------------------------------------------------
    -- ShowGemSocketPanel: 选择宝石镶嵌到孔位
    ---------------------------------------------------------------------------
    local function CloseGemSocketOverlay()
        if gemSocketOverlay_ and shared.overlayRoot then
            shared.overlayRoot:RemoveChild(gemSocketOverlay_)
        end
        gemSocketOverlay_ = nil
    end

    Parent.ShowGemSocketPanel = function(slotId, socketIdx)
        local equipped = GameState.equipment[slotId]
        if not equipped then return end

        CloseGemSocketOverlay()

        local sockets = equipped.sockets or 0
        local gems = equipped.gems or {}
        local category = Config.EQUIP_CATEGORIES[equipped.slot]

        -- 如果未指定孔位，找第一个空孔位
        if not socketIdx then
            for i = 1, sockets do
                if not gems[i] then socketIdx = i; break end
            end
        end
        if not socketIdx then
            Toast.Warn("没有空孔位")
            return
        end

        local selectedSocket = socketIdx

        -- 收集背包中所有宝石
        local availableGems = {}
        for key, count in pairs(GameState.gemBag or {}) do
            if count and count > 0 then
                local parts = {}
                for s in string.gmatch(key, "[^:]+") do table.insert(parts, s) end
                local gemTypeId = parts[1]
                local qualityIdx = tonumber(parts[2])
                if gemTypeId and qualityIdx then
                    local gemType = Config.GEM_TYPE_MAP[gemTypeId]
                    local gemQual = Config.GEM_QUALITIES[qualityIdx]
                    if gemType and gemQual then
                        table.insert(availableGems, {
                            typeId = gemTypeId,
                            quality = qualityIdx,
                            count = count,
                            name = gemQual.name .. gemType.name,
                            color = gemType.color,
                            qualColor = gemQual.color,
                        })
                    end
                end
            end
        end
        -- 按品质降序排列
        table.sort(availableGems, function(a, b)
            if a.quality ~= b.quality then return a.quality > b.quality end
            return a.typeId < b.typeId
        end)

        local function buildPanel()
            local panelChildren = {}

            -- 标题栏
            table.insert(panelChildren, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                width = "100%",
                backgroundColor = { 30, 70, 50, 250 },
                paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
                children = {
                    UI.Label { text = "镶嵌宝石 - " .. (equipped.name or "装备") .. " 孔位" .. selectedSocket, fontSize = 12, fontColor = { 140, 230, 170, 245 } },
                    UI.Panel {
                        width = 24, height = 24,
                        backgroundColor = { 160, 50, 50, 200 },
                        borderRadius = 12,
                        alignItems = "center", justifyContent = "center",
                        onClick = function() CloseGemSocketOverlay() end,
                        children = {
                            UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                        },
                    },
                },
            })

            -- 宝石列表
            table.insert(panelChildren, UI.Label { text = "选择宝石:", fontSize = 10, fontColor = { 160, 170, 190, 200 }, paddingLeft = 8, paddingTop = 4 })

            if #availableGems == 0 then
                table.insert(panelChildren, UI.Label { text = "没有可用的宝石", fontSize = 10, fontColor = { 140, 100, 100, 180 }, paddingLeft = 8, paddingBottom = 8 })
            else
                local gemRows = {}
                for _, g in ipairs(availableGems) do
                    local gc = g.color
                    local statKey, statVal = Config.CalcGemStat(g.typeId, g.quality, category, Config.IPToTierMul(equipped.itemPower))
                    local statText = ""
                    if statKey == "allRes" then
                        statText = "全抗 " .. GameState.FormatStatValue("fireRes", statVal)
                    else
                        local sd = Config.EQUIP_STATS[statKey]
                        statText = (sd and sd.name or statKey) .. " " .. GameState.FormatStatValue(statKey, statVal)
                    end
                    table.insert(gemRows, UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        width = "100%", paddingLeft = 8, paddingRight = 8, paddingTop = 2, paddingBottom = 2,
                        backgroundColor = { gc[1], gc[2], gc[3], 15 },
                        borderRadius = 4,
                        onClick = Utils.Debounce(function()
                            local ok, msg = GameState.SocketGem(slotId, selectedSocket, g.typeId, g.quality)
                            if ok then
                                Toast.Success("镶嵌成功: " .. g.name)
                            else
                                Toast.Warn(msg or "镶嵌失败")
                            end
                            CloseGemSocketOverlay()
                            shared.gridDirty = true
                            -- 刷新装备详情
                            shared.compareSlotId = nil
                            Parent.ShowCompare(slotId, nil, "equipped")
                            Parent.Refresh()
                        end, 0.3),
                        children = {
                            UI.Panel {
                                width = 24, height = 24,
                                backgroundImage = Config.GetGemIcon(g.typeId, g.quality),
                                backgroundFit = "contain",
                            },
                            UI.Label { text = g.name, fontSize = 10, fontColor = { gc[1], gc[2], gc[3], 230 }, flexGrow = 1, pointerEvents = "none" },
                            UI.Label { text = statText, fontSize = 9, fontColor = { 130, 200, 130, 200 }, pointerEvents = "none" },
                            UI.Label { text = "×" .. g.count, fontSize = 9, fontColor = { 180, 190, 200, 160 }, pointerEvents = "none" },
                        },
                    })
                end
                table.insert(panelChildren, UI.Panel {
                    width = "100%", gap = 2,
                    paddingBottom = 8, paddingLeft = 4, paddingRight = 4,
                    maxHeight = 180,
                    overflow = "scroll",
                    children = gemRows,
                })
            end

            -- 取消按钮
            table.insert(panelChildren, UI.Panel {
                width = "100%", paddingLeft = 8, paddingRight = 8, paddingBottom = 8,
                children = {
                    UI.Button {
                        text = "取消", height = 28, fontSize = 11, width = "100%",
                        backgroundColor = { 70, 75, 85, 220 },
                        onClick = function() CloseGemSocketOverlay() end,
                    },
                },
            })

            return panelChildren
        end

        local panelChildren = buildPanel()

        gemSocketOverlay_ = UI.Panel {
            position = "absolute",
            left = 0, top = 0, width = "100%", height = "100%",
            zIndex = 300,
            backgroundColor = { 0, 0, 0, 120 },
            justifyContent = "center", alignItems = "center",
            onClick = function() CloseGemSocketOverlay() end,
            children = {
                UI.Panel {
                    width = "90%", maxWidth = 400,
                    backgroundColor = { 18, 22, 34, 245 },
                    borderColor = { 60, 160, 100, 200 },
                    borderWidth = 1, borderRadius = 8,
                    gap = 4,
                    overflow = "hidden",
                    onClick = function() end,  -- 阻止冒泡
                    children = panelChildren,
                },
            },
        }

        local root = shared.overlayRoot
        if root then root:AddChild(gemSocketOverlay_) end
    end

    ---------------------------------------------------------------------------
    -- ShowGemUnsocketPanel: 选择拆卸宝石
    ---------------------------------------------------------------------------
    Parent.ShowGemUnsocketPanel = function(slotId)
        local equipped = GameState.equipment[slotId]
        if not equipped then return end

        Parent.CloseCompare()

        local sockets = equipped.sockets or 0
        local gems = equipped.gems or {}
        local category = Config.EQUIP_CATEGORIES[equipped.slot]

        local panelChildren = {}

        -- 标题栏
        table.insert(panelChildren, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            width = "100%",
            backgroundColor = { 80, 55, 20, 250 },
            paddingLeft = 10, paddingRight = 6, paddingTop = 5, paddingBottom = 5,
            children = {
                UI.Label { text = "拆卸宝石 - " .. (equipped.name or "装备"), fontSize = 12, fontColor = { 255, 200, 120, 245 } },
                UI.Panel {
                    width = 24, height = 24,
                    backgroundColor = { 160, 50, 50, 200 },
                    borderRadius = 12,
                    alignItems = "center", justifyContent = "center",
                    onClick = function() Parent.CloseCompare() end,
                    children = {
                        UI.Label { text = "✕", fontSize = 12, fontColor = { 255, 255, 255, 240 } },
                    },
                },
            },
        })

        table.insert(panelChildren, UI.Label { text = "选择要拆卸的宝石 (免费拆卸):", fontSize = 10, fontColor = { 180, 170, 140, 200 }, paddingLeft = 8, paddingTop = 4 })

        -- 列出已镶嵌的宝石
        local gemRows = {}
        for i = 1, sockets do
            local gem = gems[i]
            if gem then
                local gemType = Config.GEM_TYPE_MAP[gem.type]
                local gemQual = Config.GEM_QUALITIES[gem.quality]
                local gc = gemType and gemType.color or { 180, 180, 180 }
                local gemName = (gemQual and gemQual.name or "") .. (gemType and gemType.name or "")
                local statKey, statVal = Config.CalcGemStat(gem.type, gem.quality, category, Config.IPToTierMul(equipped.itemPower))
                local statText = ""
                if statKey == "allRes" then
                    statText = "全抗 " .. GameState.FormatStatValue("fireRes", statVal)
                else
                    local sd = Config.EQUIP_STATS[statKey]
                    statText = (sd and sd.name or statKey) .. " " .. GameState.FormatStatValue(statKey, statVal)
                end
                local socketIdx = i
                table.insert(gemRows, UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    width = "100%", paddingLeft = 8, paddingRight = 8, paddingTop = 4, paddingBottom = 4,
                    backgroundColor = { gc[1], gc[2], gc[3], 15 },
                    borderRadius = 4,
                    onClick = Utils.Debounce(function()
                        local ok, msg = GameState.UnsocketGem(slotId, socketIdx)
                        if ok then
                            Toast.Success("拆卸成功: " .. gemName)
                        else
                            Toast.Warn(msg or "拆卸失败")
                        end
                        shared.gridDirty = true
                        Parent.CloseCompare()
                        Parent.Refresh()
                    end, 0.3),
                    children = {
                        UI.Label { text = "孔位" .. i, fontSize = 9, fontColor = { 160, 170, 190, 160 }, width = 32, pointerEvents = "none" },
                        UI.Panel {
                            width = 20, height = 20,
                            backgroundImage = Config.GetGemIcon(gem.type, gem.quality),
                            backgroundFit = "contain",
                        },
                        UI.Label { text = gemName, fontSize = 10, fontColor = { gc[1], gc[2], gc[3], 230 }, flexGrow = 1, pointerEvents = "none" },
                        UI.Label { text = statText, fontSize = 9, fontColor = { 200, 160, 100, 180 }, pointerEvents = "none" },
                    },
                })
            end
        end

        if #gemRows == 0 then
            table.insert(panelChildren, UI.Label { text = "没有已镶嵌的宝石", fontSize = 10, fontColor = { 140, 100, 100, 180 }, paddingLeft = 8, paddingBottom = 8 })
        else
            table.insert(panelChildren, UI.Panel {
                width = "100%", gap = 2,
                paddingBottom = 4, paddingLeft = 4, paddingRight = 4,
                children = gemRows,
            })
        end

        -- 取消按钮
        table.insert(panelChildren, UI.Panel {
            width = "100%", paddingLeft = 8, paddingRight = 8, paddingBottom = 8,
            children = {
                UI.Button {
                    text = "取消", height = 28, fontSize = 11, width = "100%",
                    backgroundColor = { 70, 75, 85, 220 },
                    onClick = function() Parent.CloseCompare() end,
                },
            },
        })

        shared.compareOverlay = UI.Panel {
            position = "absolute",
            left = 0, right = 0, bottom = "50%",
            zIndex = 200,
            paddingLeft = 8, paddingRight = 8, paddingBottom = 4,
            children = {
                UI.Panel {
                    width = "100%",
                    backgroundColor = { 18, 22, 34, 245 },
                    borderColor = { 180, 140, 40, 200 },
                    borderWidth = 1, borderRadius = 8,
                    gap = 4,
                    overflow = "hidden",
                    children = panelChildren,
                },
            },
        }

        local root = shared.overlayRoot
        if root then root:AddChild(shared.compareOverlay) end
        shared.compareSlotId = slotId
        shared.compareInvIdx = nil
        shared.compareSource = "gemUnsocket"
    end

    -- ================================================================
    -- 橙装分解二次确认
    -- ================================================================

    local decompConfirmOverlay_ = nil

    function InventoryCompare.ShowDecomposeConfirm(item, invIndex)
        InventoryCompare.CloseDecomposeConfirm()
        local qualityCfg = Config.EQUIP_QUALITY[item.qualityIdx]
        local qColor = qualityCfg and qualityCfg.color or { 255, 165, 0 }

        decompConfirmOverlay_ = UI.Panel {
            position = "absolute", width = "100%", height = "100%",
            zIndex = 300,
            backgroundColor = { 0, 0, 0, 180 },
            justifyContent = "center", alignItems = "center",
            onClick = function() InventoryCompare.CloseDecomposeConfirm() end,
            children = {
                UI.Panel {
                    width = 250,
                    backgroundColor = { 45, 40, 55, 250 },
                    borderRadius = 10, padding = 16, gap = 10,
                    alignItems = "center",
                    borderWidth = 1, borderColor = { qColor[1], qColor[2], qColor[3], 150 },
                    onClick = function() end,
                    children = {
                        UI.Label {
                            text = "分解确认",
                            fontSize = 14, fontColor = { 255, 100, 100, 255 },
                        },
                        UI.Label {
                            text = item.name or "装备",
                            fontSize = 12, fontColor = { qColor[1], qColor[2], qColor[3], 255 },
                        },
                        UI.Label {
                            text = "这是一件珍贵的橙色装备！\n分解后无法恢复，确定要分解吗？",
                            fontSize = 10, fontColor = { 220, 200, 180, 220 },
                            textAlign = "center",
                        },
                        UI.Panel {
                            flexDirection = "row", gap = 12, marginTop = 4,
                            children = {
                                UI.Button {
                                    text = "取消", height = 30, fontSize = 11,
                                    backgroundColor = { 60, 65, 80, 200 },
                                    onClick = function() InventoryCompare.CloseDecomposeConfirm() end,
                                },
                                UI.Button {
                                    text = "确认分解", height = 30, fontSize = 11,
                                    backgroundColor = { 160, 50, 50, 220 },
                                    onClick = function()
                                        InventoryCompare.CloseDecomposeConfirm()
                                        local itemName = item.name or "装备"
                                        local gold, mats = GameState.DecomposeItem(invIndex)
                                        if gold > 0 or (mats and next(mats)) then
                                            local matParts = {}
                                            if mats then
                                                for matId, amt in pairs(mats) do
                                                    local def = Config.MATERIAL_MAP and Config.MATERIAL_MAP[matId]
                                                    table.insert(matParts, amt .. (def and def.name or matId))
                                                end
                                            end
                                            FloatTip.Decompose("分解 " .. itemName .. " → " .. table.concat(matParts, " + "))
                                            print("分解获得 " .. gold .. " 金币, " .. table.concat(matParts, " + "))
                                            SaveSystem.MarkDirty()
                                        end
                                        Parent.CloseCompare()
                                        Parent.Refresh()
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        }
        local root = shared.overlayRoot
        if root then root:AddChild(decompConfirmOverlay_) end
    end

    function InventoryCompare.CloseDecomposeConfirm()
        if decompConfirmOverlay_ then
            decompConfirmOverlay_:Remove()
            decompConfirmOverlay_ = nil
        end
    end
end

return InventoryCompare
