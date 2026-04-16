# 存档系统 Schema (v2 - 云端多槽位)

> 版本: 2.1
> 最后更新: 2026-03-13

---

## 1. 架构概述

### 设计原则

- **云端加载**: 启动时必须从云端加载存档，本地存档不参与启动加载，避免空本地覆盖云端
- **本地缓存**: 运行中先同步写本地（快），再异步上传云端（慢），本地存档是运行时缓存
- **多槽位**: 10 个独立存档槽位，每个槽位对应不同的云端 Key
- **轻量元数据**: 独立的 `save_meta` Key 存储所有槽位的概要信息，用于快速展示存档列表
- **向后兼容**: 支持从旧版 `clientScore` / `clientCloud` 单槽位存档迁移

### 本地 vs 云端的职责划分

```
┌─────────────┬──────────────────────────────────────────────────┐
│   阶段       │  行为                                           │
├─────────────┼──────────────────────────────────────────────────┤
│ 启动/加载    │  只读云端, 本地存档不参与 (WASM 每次启动本地为空) │
│ 运行中保存   │  先写本地 (同步) → 再异步写云端                  │
│ 云端失败时   │  本地已保存, 下次云端重试; 不影响游戏体验         │
│ 关键事件     │  立即 SaveNow: 本地+云端双写                    │
│ 浏览器崩溃   │  本地数据随 WASM 丢失, 但最近一次云端保存仍在    │
└─────────────┴──────────────────────────────────────────────────┘
```

### 云端 Key 结构

| Cloud Key | 类型 | 用途 |
|-----------|------|------|
| `save_meta` | values (JSON) | 所有槽位的元数据概览 |
| `save_slot_1` | values (JSON) | 1号存档完整数据 |
| `save_slot_2` | values (JSON) | 2号存档完整数据 |
| ... | ... | ... |
| `save_slot_10` | values (JSON) | 10号存档完整数据 |
| `save_data` | values (JSON) | **旧版存档** (clientCloud, 迁移用) |

### 本地文件结构

| 本地文件 | 用途 | 生命周期 |
|----------|------|---------|
| `save_slot_N.json` | 当前槽位的运行时缓存 | 运行中持续写入, WASM 重启后丢失 |
| `save_slot_N_backup.json` | 当前槽位的备份 | 每次写入前, 将上一份复制为备份 |

> **注意**: WASM 平台的本地文件系统是临时的，浏览器关闭/刷新后文件丢失。
> 本地文件仅在单次会话内提供以下价值：
> 1. 同步写入，保证保存操作不阻塞游戏循环
> 2. 云端异步上传失败时，本地仍有最新数据，可在后续重试中使用
> 3. 备份文件防止单次写入损坏

### iscores 排行榜字段 (每个玩家全局, 不分槽位)

| iscore Key | 类型 | 用途 |
|------------|------|------|
| `max_power` | int | 最高战力 ÷ 1000 |
| `max_stage` | int | 最高章节×100 + 关卡 |
| `max_trial_floor` | int | 无尽试炼最高层 |
| `active_slot` | int | 当前活跃槽位 (1-10) |

---

## 2. save_meta (元数据)

用于开始界面快速展示 10 个存档槽位的概要，无需加载完整存档数据。

```jsonc
{
  "version": 1,                   // meta 格式版本
  "activeSlot": 1,                // 上次使用的槽位 (1-10)
  "slots": {
    "1": {
      "timestamp": 1710300000,    // 最后保存时间 (Unix 秒)
      "level": 85,                // 玩家等级
      "chapter": 12,              // 当前章节
      "stage": 3,                 // 当前关卡
      "maxFloor": 42,             // 无尽试炼最高层
      "playTime": 36000,          // 累计游戏时长 (秒)
      "saveCount": 150            // 存档计数 (用于版本仲裁)
    },
    "2": {
      "timestamp": 1710200000,
      "level": 30,
      "chapter": 5,
      "stage": 1,
      "maxFloor": 10,
      "playTime": 7200,
      "saveCount": 45
    }
    // 空槽位不写入, 即 "3"~"10" 不存在 = 空存档
  }
}
```

### 字段说明

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `version` | number | 是 | meta 格式版本, 当前为 1 |
| `activeSlot` | number | 是 | 上次使用的槽位号 (1-10) |
| `slots` | object | 是 | 以槽位号为 key (字符串 "1"~"10") |
| `slots[N].timestamp` | number | 是 | 最后保存的 Unix 时间戳 |
| `slots[N].level` | number | 是 | 玩家等级 |
| `slots[N].chapter` | number | 是 | 当前章节 |
| `slots[N].stage` | number | 是 | 当前关卡 |
| `slots[N].maxFloor` | number | 否 | 无尽试炼最高层, 默认 0 |
| `slots[N].playTime` | number | 否 | 累计游戏时长(秒), 默认 0 |
| `slots[N].saveCount` | number | 否 | 存档计数, 默认 0 |

---

## 3. save_slot_N (完整存档数据)

每个槽位的完整存档结构，与现有 `SaveSystem.Serialize()` 输出一致，增加少量新字段。

```jsonc
{
  // ─── 存档元信息 ───
  "version": 5,                    // 存档格式版本 (当前 CURRENT_SAVE_VERSION = 5)
  "timestamp": 1710300000,         // 保存时间 (Unix 秒)
  "_meta": {
    "saveCount": 150,              // 递增计数, 用于版本仲裁
    "slotId": 1,                   // 所属槽位号 (1-10)
    "playTime": 36000,             // 累计游戏时长 (秒)
    "createdAt": 1708000000,       // 该存档首次创建时间
    "migratedFrom": null           // 迁移来源: "clientScore" | "clientCloud" | null
  },

  // ─── 玩家基础数据 ───
  "player": {
    "level": 85,                   // 等级 (≥1)
    "exp": 12340,                  // 当前经验
    "gold": 9999999,               // 金币
    "freePoints": 5,               // 未分配属性点
    "allocatedPoints": {           // 已分配属性点 (8个方向)
      "atk": 50,                   // 攻击力
      "spd": 30,                   // 攻速
      "crit": 20,                  // 暴击率
      "critDmg": 15,               // 暴击伤害
      "range": 10,                 // 攻击范围
      "luck": 10,                  // 幸运
      "vit": 20,                   // 生命力 (HP)
      "ten": 10                    // 韧性 (减伤)
    }
  },

  // ─── 装备系统 ───
  "equipment": {                   // 已穿戴装备 (6槽位)
    "weapon": {                    // 槽位ID: weapon | gloves | amulet | ring | boots | necklace
      "slot": "weapon",            // 槽位
      "tier": 10,                  // 章节等级 (决定 tierMul)
      "tierMul": 50.5,             // 章节倍率 (对数公式计算)
      "qualityIdx": 5,             // 品质 (1=白 2=绿 3=蓝 4=紫 5=橙)
      "setId": "ash_flame",        // 套装ID (可选, 非套装装备无此字段)
      "element": "fire",           // 元素 (weapon 专有): fire|ice|lightning|poison|physical
      "mainStat": "atk",           // 主词条类型
      "mainValue": 120.5,          // 主词条值
      "baseMainValue": 100.0,      // 主词条基础值 (强化前)
      "subStats": [                // 副词条 (0-4条)
        {
          "key": "critRate",       // 副词条类型
          "value": 0.08,           // 副词条当前值
          "baseValue": 0.05        // 副词条基础值
        }
      ],
      "enhanceLevel": 5,           // 强化等级
      "enhanceBonusMain": 20.5     // 强化加成值
    }
    // 其他槽位同理, 空槽位不写入
  },

  // ─── 背包 (装备) ───
  "inventory": [                   // 装备背包列表
    // 每个元素与 equipment 中的装备结构相同
  ],

  // ─── 材料 ───
  "materials": {
    "stone": 500,                  // 强化石
    "soulCrystal": 120             // 魂晶
  },

  // ─── 背包扩容 ───
  "expandCount": 3,                // 扩容次数

  // ─── 技能 ───
  "skills": {                      // 已学习技能 { [skillId]: level }
    "fire_bolt": 5,
    "ice_shard": 3,
    "chain_lightning": 2
    // level=0 的技能不写入
  },

  // ─── 关卡进度 ───
  "stage": {
    "chapter": 12,                 // 当前章节
    "stage": 3                     // 当前关卡
  },

  // ─── 药水Buff ───
  "potionBuffs": {                 // { [typeId]: Queue }
    "exp": [                       // 按 value 降序排列的队列
      { "timer": 1800, "value": 0.5 },   // 高品质优先消耗
      { "timer": 3600, "value": 0.2 }    // 低品质后续
    ],
    "atk": [
      { "timer": 900, "value": 0.3 }
    ]
    // typeId: "exp" | "hp" | "atk" | "luck"
    // timer > 0 的才写入
  },

  // ─── 个人记录 ───
  "records": {
    "maxPower": 125000,            // 历史最高战力
    "maxChapter": 12,              // 历史最高章节
    "maxStage": 5                  // 历史最高关卡
  },

  // ─── 自动分解配置 ───
  "autoDecompConfig": [0, 1, 2, 0, 0],
  // 索引 [1]白 [2]绿 [3]蓝 [4]紫 [5]橙
  // 值: 0=关闭, 1=全分解(含套装), 2=留套装(只分解非套装)

  // ─── 通用道具背包 ───
  "bag": {                         // { [itemId]: count }
    "attr_reset": 2,
    "skill_reset": 1
  },

  // ─── 兑换码 ───
  "redeemedCodes": {               // { [code]: true }
    "WELCOME2024": true
  },

  // ─── 版本奖励 ───
  "claimedVersionRewards": {       // { [version]: true }
    "1.5.0": true,
    "1.8.0": true
  },

  // ─── 每日/每周/月卡奖励 ───
  "dailyRewards": {
    "daily": {
      "currentDay": 5,             // 当前连续签到天数 (0-7)
      "lastClaimDate": "2026-03-12" // 上次领取日期
    },
    "weekly": {
      "currentDay": 3,             // 当前周签到天数
      "weekId": "2026-W11",        // 周标识
      "lastClaimDate": "2026-03-12"
    },
    "monthCard": {
      "active": true,              // 月卡是否激活
      "activateDate": "2026-03-01", // 激活日期
      "claimedDays": 12,           // 已领取天数
      "lastClaimDate": "2026-03-12"
    }
  },

  // ─── 无尽试炼 ───
  "endlessTrial": {
    "maxFloor": 42                 // 历史最高层数
  },

  // ─── 世界Boss ───
  "worldBoss": {
    "season": 20260312,            // 赛季ID (YYYYMMDD)
    "attempts": 2,                 // 本赛季已用挑战次数 (上限3)
    "totalDamage": 8500000,        // 本赛季累计伤害
    "lastReward": 20260311         // 上次领取奖励的赛季ID
  },

  // ─── 锻造 ───
  "forge": {
    "usedFree": 1,                 // 今日已用免费次数
    "usedPaid": 3,                 // 今日已用付费次数
    "lastDate": "2026-03-12"       // 上次使用日期 (YYYY-MM-DD, 用于每日重置)
  },

  // ─── 迁移标记 ───
  "migrated_elemDmg_nerf": true    // elemDmg 数值缩减迁移已完成
}
```

---

## 4. 数据类型速查

### 装备词条类型 (mainStat / subStats[].key)

| key | 含义 | 数值类型 | 示例值 |
|-----|------|---------|--------|
| `atk` | 攻击力 | 整数 | 120 |
| `atkSpeed` | 攻速 | 浮点 | 0.3 |
| `critRate` | 暴击率 | 浮点(0~1) | 0.08 |
| `critDmg` | 暴击伤害 | 浮点 | 0.5 |
| `range` | 攻击范围 | 整数 | 15 |
| `luck` | 幸运 | 整数 | 10 |
| `elemDmg` | 元素伤害 | 浮点 | 0.12 |
| `hpPct` | 生命百分比 | 浮点(0~1) | 0.15 |
| `skillCdReduce` | 技能CD减少 | 浮点(0~1) | 0.10 |
| `def` | 防御 | 整数 | 50 |
| `vit` | 生命力 | 整数 | 20 |

### 装备品质 (qualityIdx)

| 值 | 品质 | 颜色 |
|----|------|------|
| 1 | 白色 (普通) | 白 |
| 2 | 绿色 (优秀) | 绿 |
| 3 | 蓝色 (精良) | 蓝 |
| 4 | 紫色 (史诗) | 紫 |
| 5 | 橙色 (传说) | 橙 |

### 装备槽位 (slot)

| id | 名称 |
|----|------|
| `weapon` | 武器 |
| `gloves` | 手套 |
| `amulet` | 护符 |
| `ring` | 戒指 |
| `boots` | 靴子 |
| `necklace` | 项链 |

### 武器元素 (element)

`fire` | `ice` | `lightning` | `poison` | `physical`

---

## 5. 存档版本迁移链

```
v1 → v2: elemDmg 词条值缩减 1/5
v2 → v3: 技能ID调和 + 装备字段规范化 + 材料规范化
v3 → v4: 缩放公式从指数(2^(ch-1))改为对数, 装备非百分比词条按比例缩放
v4 → v5: 经济重平衡 (Boss金币改为小怪3倍)
```

当前版本: **CURRENT_SAVE_VERSION = 5**

---

## 6. 旧存档迁移策略

### 6.1 旧系统的两个存档来源

旧版本有两套独立的存档机制，共用同一个 `clientCloud` 存储空间（`clientScore` 是其废弃别名）：

| 来源 | Cloud Key (values) | Cloud Key (iscores) | 触发方式 | 说明 |
|------|-------------------|---------------------|---------|------|
| 自动存档 (SaveSystem) | `save_data` | `max_power`, `max_stage`, `max_trial_floor` | 每30秒自动 | 存储为 table |
| 手动存档 (ManualSave) | `manual_save` | `manual_checksum` (DJB2校验) | 用户手动触发 | 存储为 JSON 字符串 |

> **注意**: `clientScore` 和 `clientCloud` 是同一个对象（`clientScore` 已废弃），
> 不存在"不同存储空间"的问题。两个来源的区别仅在于 Key 名称不同。

### 6.2 迁移流程 (分槽位保存, 不合并)

**设计思路**: 自动存档和手动存档是用户在旧版本中两条独立的存档线，各自可能包含不同的游戏进度。
迁移时**不做仲裁**，直接分别放入不同槽位，让用户自行选择继续哪一份。

```
首次启动 (save_meta 不存在)
  ↓
并行读取两个旧 Key:
  clientCloud:BatchGet()
    :Key("save_data")              ← 自动存档
    :Key("manual_save")            ← 手动存档
    :Fetch(...)
  ↓
解析两份数据:
  autoSave  ← values["save_data"]   (table)
  manualRaw ← values["manual_save"] (string 或 table)
    → 如果是 string, cjson.decode 为 table
  ↓
对两份数据分别做 ValidateStructure 校验
  ↓
分别写入不同槽位 (不合并, 不仲裁):
  ├── autoSave 有效   → 写入 slot_1, _meta.migratedFrom = "auto_save"
  ├── manualSave 有效 → 写入 slot_2, _meta.migratedFrom = "manual_save"
  ├── 两者都有效      → slot_1 = autoSave, slot_2 = manualSave
  └── 都无效/为空     → 确认为新玩家
  ↓
一次 BatchSet 原子写入 (所有数据在同一次调用中):
  clientCloud:BatchSet()
    :Set("save_slot_1", autoSave)      -- 仅在 autoSave 有效时
    :Set("save_slot_2", manualSave)    -- 仅在 manualSave 有效时
    :Set("save_meta", {
        version = 1,
        activeSlot = 1,                -- 默认激活自动存档
        slots = {
          ["1"] = { ... },             -- 仅在 autoSave 有效时
          ["2"] = { ... },             -- 仅在 manualSave 有效时
        }
    })
    :Save("存档迁移", callbacks)
  ↓
迁移完成 → 展示开始界面, 用户可看到两份存档
```

> **activeSlot 优先级**: 如果只有 manualSave 有效, `activeSlot` 设为 2。

### 6.3 迁移部分失败处理

```
BatchSet 回调:
  ├── ok   → 迁移成功, 展示开始界面
  └── fail → 迁移失败
               ↓
             重试 (3/9/27秒指数退避, 最多3次)
               ↓
             ├── 重试成功 → 展示开始界面
             └── 重试全部失败 → 弹出提示:
                   "存档迁移失败，请检查网络后重启游戏"
                   ⚠️ 不进入游戏, 不创建空存档, 防止数据丢失
```

**关键**: 迁移使用单次 `BatchSet` 写入所有数据 (slot_1 + slot_2 + save_meta)，
保证原子性。不存在"meta 写成功但 slot 写失败"的中间状态。

### 6.4 ManualSave 数据格式兼容

手动存档的 `manual_save` 值有两种可能的格式：

| 格式 | 判断方式 | 处理 |
|------|---------|------|
| JSON 字符串 | `type(raw) == "string"` | `cjson.decode(raw)` 得到 table |
| 原始 table | `type(raw) == "table"` | 直接使用 |

两种情况都需要处理，因为 ManualSave 存的是 `cjson.encode(saveData)` 字符串，
但 clientCloud 返回时可能已经自动反序列化为 table。

### 6.5 迁移后

- 旧 Key (`save_data`, `manual_save`) 不删除, 保留作为最后的数据恢复手段
- 新系统只读写 `save_meta` + `save_slot_N`
- 迁移只执行一次 (检查 `save_meta` 是否存在来判断)
- 迁移成功后, ManualSave 模块不再使用, 其功能由多槽位系统取代

### 6.6 新旧版本兼容性

#### 旧存档 → 新代码 (前向兼容, 安全)

旧存档没有 `_meta` 块，新代码 Deserialize 时必须对所有新字段提供默认值：

```lua
local meta = saveData._meta or {}
GameState.saveCount  = meta.saveCount or 0
GameState.slotId     = meta.slotId or 1
GameState.playTime   = meta.playTime or 0
GameState.createdAt  = meta.createdAt or saveData.timestamp or os.time()
GameState.sessionId  = meta.sessionId or nil
```

#### 新存档 → 旧代码 (反向兼容, 安全)

新存档多了 `_meta` 字段，旧代码的 `Deserialize` 不认识这个字段，
但 Lua table 会直接忽略未使用的字段，不会报错也不会影响其他数据的读取。

#### ⚠️ 云端 Key 切换风险

新系统写 `save_slot_N`，**不再写 `save_data`**。如果用户在新版本保存后
回退到旧版本（如浏览器缓存了旧 WASM），旧代码从 `save_data` 读到的是
迁移前的陈旧数据，迁移后的所有进度丢失。

**防护方案: 新系统每次保存时同步回写旧 Key**

```lua
-- 新系统每次自动存档的 BatchSet 中，同时更新旧 Key:
clientCloud:BatchSet()
  :Set("save_slot_N", slotData)        -- 新 Key
  :Set("save_meta", updatedMeta)       -- 新 meta
  :Set("save_data", slotData)          -- ← 同步回写旧 Key (仅活跃槽位)
  :SetInt("max_power", ...)
  :Save(...)
```

这样即使用户回退旧版本，`save_data` 也是最新的。
额外成本很小 (BatchSet 中多一个 Key)，且只回写当前活跃槽位的数据。

**可选的替代方案** (如果不想回写旧 Key):
在旧 `save_data` 中写入一个标记 `{ _redirectTo = "save_slot_1" }`，
但这需要旧版本代码能识别该标记——已发布的旧版本做不到，所以不推荐。

---

## 7. 运行时流程

### 7.1 游戏启动

```
App 启动
  ↓
从云端加载 save_meta (clientCloud)          ← 只读云端, 不读本地
  ↓
├── save_meta 存在
│     ↓
│   展示开始界面 (10个槽位, 显示元数据)
│     ↓
│   用户选择槽位 N
│     ↓
│   从云端加载 save_slot_N (clientCloud)     ← 只读云端, 不读本地
│     ↓
│   Deserialize → 进入游戏
│     ↓
│   此时才开始写本地缓存 (saveConfirmed_ = true)
│
└── save_meta 不存在 (首次/迁移)
      ↓
    执行迁移流程 (§6.2)
      ↓
    ├── 迁移成功 → 展示开始界面 (槽位1已有数据)
    └── 新玩家 → 展示开始界面 (全部空槽位)
```

**关键规则**: 启动时绝不读取本地文件。WASM 每次启动本地文件系统为空，
读本地只会得到空数据，如果用空数据与云端仲裁，会导致覆盖云端存档。

### 7.2 自动存档 (每30秒)

```
SaveSystem.Update(dt)
  ↓ saveTimer >= 30s
Serialize() → 完整存档数据
  ↓
1. 写入本地 save_slot_N.json (同步)             ← 先本地
  ↓
2. 一次 BatchSet 原子写入云端:                   ← 再云端 (单次调用)
   clientCloud:BatchSet()
     :Set("save_slot_N", slotData)               -- 完整存档
     :Set("save_meta", updatedMeta)               -- 元数据同步 (仅字段变化时)
     :Set("save_data", slotData)                  -- 回写旧 Key (兼容旧版本, §6.6)
     :SetInt("max_power", ...)                    -- 排行榜
     :SetInt("max_stage", ...)
     :SetInt("max_trial_floor", ...)
     :Save("自动存档", callbacks)
```

**关键**: `save_slot_N` 和 `save_meta` 必须在同一个 `BatchSet` 中写入，
保证原子性，避免中途失败导致两者不一致。

**云端上传失败时**: 本地已有最新数据, 安排重试 (3/9/27秒指数退避, 最多3次)。
下次自动存档触发时，新数据会覆盖旧重试，始终保证上传最新版本。

**save_meta 更新优化**: save_meta 中的字段 (level/chapter/stage) 不会每30秒都变化。
实现时应维护一份 `lastMetaSnapshot`，在构建 BatchSet 前对比当前 meta 和上次快照：
- 字段有变化 → 将 `save_meta` 加入 BatchSet，更新快照
- 字段无变化 → 跳过 `save_meta`，只写 `save_slot_N` 和排行榜字段
- 这可以减少约 60-80% 的 meta 写入次数

### 7.3 切换存档

```
用户在设置中点击"切换存档"
  ↓
立即保存当前槽位 (SaveNow)
  ↓
返回开始界面
  ↓
加载 save_meta (获取最新槽位概要)
  ↓
用户选择新槽位
  ↓
加载 save_slot_N → Deserialize → 进入游戏
```

### 7.4 新建存档

```
用户点击空槽位
  ↓
GameState.Init() (全新初始化)
  ↓
_meta.slotId = N, _meta.createdAt = now
  ↓
立即 SaveNow → 写入 save_slot_N + 更新 save_meta
  ↓
进入游戏
```

### 7.5 删除存档

```
用户长按/点击删除按钮
  ↓
二次确认弹窗
  ↓
清空 save_slot_N (写入 null 或空对象)
  ↓
删除 save_meta.slots[N]
  ↓
更新 save_meta 到云端
```

---

## 8. 错误处理

### 加载阶段 (只涉及云端)

| 场景 | 处理方式 |
|------|---------|
| save_meta 加载失败 (网络) | 重试 3 次, 间隔 3/9/27 秒, 超时弹出错误提示, 不读本地 |
| save_slot_N 加载失败 | 重试 3 次, 失败后提示"存档加载失败, 请检查网络", 不读本地 |
| save_meta 与 slot 不一致 | 以 slot 实际数据为准, 更新 meta |
| Deserialize 失败 (数据损坏) | 不加载, 提示用户"存档损坏", 该槽位标记为异常 |
| 云端返回空数据 (已有 meta 的槽位) | 视为异常, 提示"存档数据丢失", 不覆盖不初始化 |

### 保存阶段 (本地 + 云端)

| 场景 | 处理方式 |
|------|---------|
| 本地写入失败 | 打印日志, 不影响云端上传 (罕见: WASM 磁盘满) |
| 云端上传失败 | 本地已有最新数据, 指数退避重试 3 次 (3/9/27秒) |
| 云端重试全部失败 | Toast "云端保存失败", 本地仍有数据, 下次自动存档会再次尝试 |
| 云端成功 | 不反写本地 (避免时序回档) |

---

## 9. 开始界面 UI 规格

### 存档槽位卡片

```
┌──────────────────────────────────────┐
│  📁 存档 1                    ⭐ 活跃  │
│                                      │
│  Lv.85  ·  第12章-3关               │
│  无尽试炼: 42层                       │
│  游戏时长: 10小时                     │
│                                      │
│  最后保存: 2026-03-12 15:30          │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│  📁 存档 2                           │
│                                      │
│  Lv.30  ·  第5章-1关                │
│  无尽试炼: 10层                       │
│  游戏时长: 2小时                      │
│                                      │
│  最后保存: 2026-03-10 08:15          │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│             + 新建存档                │
│                                      │
│          (空存档槽位)                 │
└──────────────────────────────────────┘
```

### 交互

- 点击已有存档: 加载该存档进入游戏
- 点击空槽位: 创建新存档并进入游戏
- 长按已有存档: 弹出"删除存档"确认
- 列表可上下滚动, 最多 10 个槽位
- 迁移过来的存档可添加标签提示来源 (如 "自动存档迁移"、"手动存档迁移")

---

## 10. 实现注意事项

### 10.1 playTime (累计游戏时长) 追踪

当前 GameState 中没有 `playTime` 字段，需要新增：

```lua
-- GameState 新增字段
GameState.playTime = 0          -- 累计游戏时长 (秒)
GameState.sessionStartTime = 0  -- 本次会话开始时的 os.time()

-- 在 HandleUpdate 中累加 (使用 dt)
GameState.playTime = GameState.playTime + dt

-- Serialize 时写入
saveData._meta.playTime = GameState.playTime

-- Deserialize 时恢复
GameState.playTime = saveData._meta and saveData._meta.playTime or 0
```

### 10.2 离线收益时间计算

离线收益的时间差 = `当前时间 - 存档中的 timestamp`。

**潜在问题**: 如果最后一次云端保存是在 30 秒自动存档周期中较早的时刻，
而用户实际又玩了一段时间后才关闭浏览器（期间云端保存失败或未触发），
则离线时间会被虚增。

**建议处理**:
- 离线收益设置合理上限 (如最多计算 24 小时)
- 在 SaveNow (关键事件保存) 中同步更新 timestamp，尽量让最后一次保存贴近实际退出时间
- 可选: 监听浏览器 `beforeunload` 事件触发最后一次保存 (WASM 平台可能不支持，需验证)

### 10.3 多标签页/多设备冲突

同一账号在多个浏览器标签页或多个设备上同时游戏时，两端都会写入同一个 `save_slot_N`，
后写入的会覆盖先写入的，导致进度回退。

**建议处理**:
- 每次保存时在 `_meta` 中写入一个 `sessionId` (启动时生成的随机字符串)
- 每次加载时检查 `sessionId` 是否与本地一致
- 如果不一致，说明另一个会话修改了存档，弹出警告:
  "检测到存档在其他设备上被修改，请选择使用哪份数据"
- 这不是强一致锁，但能在下次加载时发现冲突并提示用户

### 10.4 旧 Key 清理策略

迁移后旧 Key (`save_data`, `manual_save`, `manual_checksum`) 不立即删除，
保留作为最后的数据恢复手段。

**建议**: 在迁移版本稳定运行 N 个版本后 (如 v2.1.0+)，
可以通过一次性清理脚本在后台 BatchSet 中 Delete 这些旧 Key，释放存储空间。
清理前在 `save_meta` 中记录 `oldKeysCleanedAt` 时间戳，避免重复清理。

### 10.5 存档数据大小监控

随着游戏内容增加，单个存档的 JSON 大小会增长。建议：

- 在 Serialize 后记录 `#cjson.encode(saveData)` 的字节数
- 如果超过 500KB，打印警告日志
- clientCloud 单 Key 限制需确认 (参考引擎文档)
- 如果接近限制，考虑压缩策略 (如精简 inventory 中已分解装备的历史记录)
