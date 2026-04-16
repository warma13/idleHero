# 战斗系统架构速查

> AI 辅助开发用文档。每次新会话修改战斗/经济相关逻辑时，先读此文件。
>
> 最后更新: 2026-03-14 (v7: +称号系统 TitleSystem, CharacterPage 标签化重构)

---

## 1. 伤害管线 (五区乘算)

### 公式

```
最终伤害 = 基础区 × 增伤区 × 双爆区 × 减防区 × 抗性区  (× 反应区, 若触发)
         + 沧溟固伤 (管线外平加)
```

### 五区详解

| 区 | 函数 | 公式 | 内部合并方式 |
|----|------|------|-------------|
| 基础区 | CalcBase | `totalAtk × multiplier` 或 `baseDmg`(弹体) | 绝对值 |
| 增伤区 | CalcDmgBonus | `1 + Σ(元素增伤 + 药水 + 印记 + 套装标记 + 收敛 + 冰碎 + 碎冰者 + 冰域 + 灰焰 + 魂焰 + extraBonuses)` | 区内加算 |
| 双爆区 | CalcCrit | 暴击时=critDmg(如1.8), 非暴击=1.0 | — |
| 减防区 | CalcDef | `1 - effectiveDef / (effectiveDef + ENEMY_DEF_K)` | — |
| 抗性区 | CalcResistance | `max(0, 1 - effectiveResist)` | — |
| 反应区 | ApplyReaction | `reactionDmgBonus + 五元素天赋boost` (管线外, 反应触发后) | — |

### 调用链路

```
所有伤害源 (普攻/技能/分裂弹/陨石/区域tick/精灵)
  │
  ▼
DamageFormula.BuildContext(opts)          battle/DamageFormula.lua
  ├─ 解析元素: "weapon"→武器元素, 具体字符串→直接使用
  ├─ ATK / 暴击 roll / 元素增伤(按攻击元素) / 所有加成
  └─ 返回 ctx
  │
  ▼
DamageFormula.Calculate(ctx)             battle/DamageFormula.lua
  ├─ 基础区 × 增伤区 × 双爆区 × 减防区 × 抗性区
  ├─ + 沧溟固伤 (管线外)
  └─ 返回 max(1, floor(dmg))
  │
  ▼
元素附着 + 反应判定
  │  (若触发反应)
  ▼
DamageFormula.ApplyReaction(dmg, reaction)
  │
  ▼
EnemySystem.ApplyDamageReduction(e, dmg)
  │
  ▼
target.hp -= dmg
  ├─ CombatUtils.RecordBossDmg(dmg)
  │     ├─ DamageTracker.Record(dmg)
  │     └─ WorldBoss.RecordDamage(dmg)
  └─ if hp <= 0 → OnEnemyKilled()
```

### damageTag 与元素解析

| 伤害源 | damageTag | element | 说明 |
|--------|-----------|---------|------|
| 普攻 (紫焰弹) | `"normal"` | `"weapon"` → 武器元素 | CombatCore.HitEnemy |
| 分裂弹 | `"normal"` | `"weapon"` → 武器元素 | BulletSystem (baseDmg=预计算) |
| 主动技能 | `"skill"` | 技能自身元素(如`"fire"`) | SkillCaster |
| 陨石/区域tick | `"skill"` | 陨石/区域元素 | MeteorSystem |
| 元素精灵 | `"skill"` | `sp.element`(水) | SpiritSystem |

### 关键设计点

- **元素增伤修正**: 按攻击元素计算(非固定武器元素), 如冰技能用冰增伤而非火武器增伤
- **forceCrit**: `true`=必暴, `false`=不暴, `nil`=正常roll (AoE技能默认不暴击)
- **extraBonuses**: 技能天赋专属加成(如 empower/doom/shatter), 作为 `{key=value}` 传入增伤区
- **baseDmg**: 弹体/tick 预计算伤害, 跳过 totalAtk×multiplier
- `CombatUtils.ApplySharedDmgBonus()` **已废弃**, 全部功能并入管线增伤区
- **所有伤害源**最终都走 `CombatUtils.RecordBossDmg(dmg)` (42+ 处调用)
- `DamageTracker` 独立于 Boss 生死状态，始终累计

### RNG 范围因子

```
技能施法距离 = skillCfg.range(lv) × GameState.GetRangeFactor()
GetRangeFactor() = GetRange() / baseRange  (基础 1.0, 随 RNG 属性提升)
```

影响: elem_blast 施法距离, elem_spirit 攻击范围

---

## 2. 经验/金币掉落链路

```
怪物死亡
  │
  ▼
StageManager.OnEnemyKilled()             battle/StageManager.lua:36
  ├─ Loot.Spawn("exp", enemy.expDrop)    battle/StageManager.lua:54
  ├─ Loot.Spawn("gold", randGold)
  └─ 试炼模式: EndlessTrial.AdvanceFloor(gold, exp)
                                          EndlessTrial.lua:174
玩家拾取掉落物
  │
  ▼
Loot.Collect(loot)                       battle/Loot.lua:159
  ├─ type=="exp"  → GameState.AddExp()   GameState.lua:202
  └─ type=="gold" → GameState.AddGold()  GameState.lua:221
```

### 经验倍率

| 模式 | expDrop 计算 | 位置 |
|------|-------------|------|
| 主线关卡 | `template.expDrop × scaleMul` | Spawner.lua:195 |
| 无尽试炼 | `template.expDrop × expScaleMul` (= scaleMul^0.3) | Spawner.lua:195, EndlessTrial.lua:141 |
| 世界Boss | `expDrop = 0` (不掉经验) | WorldBoss.lua:478 |

### 金币倍率

所有模式统一: `goldDrop × sqrt(scaleMul)` (Spawner.lua:196-197)

---

## 3. 世界 Boss 生命周期

```
WorldBoss.EnterFight()                   WorldBoss.lua:161
  ├─ WorldBoss.active = true
  ├─ fightDamage = 0
  ├─ DamageTracker.StartSession()        DamageTracker.lua:109
  └─ attempts++
       │
       ▼
  战斗循环 (60秒倒计时)
  BattleSystem.Update() 中:              BattleSystem.lua:305
    bossTimer -= dt
       │
       ▼  (倒计时归零)
WorldBoss.EndFight()                     WorldBoss.lua:198
  ├─ sessionDmg = DamageTracker.EndSession()
  ├─ fightDamage = sessionDmg
  ├─ totalDamage += sessionDmg
  ├─ WorldBoss.UploadDamage()            WorldBoss.lua:319
  │     拆分为 hi/lo int32 上传排行榜
  ├─ WorldBoss.GrantParticipationReward() WorldBoss.lua:252
  │     当前最高章节Boss掉落 ×3
  └─ SaveSystem.SaveNow()
       │
       ▼
  WorldBossResult.Show() 结算面板
       │
       ▼
WorldBoss.ExitToMain()                   WorldBoss.lua:224
  └─ 恢复关卡进度
```

### 关键配置

| 常量 | 值 | 位置 |
|------|----|------|
| BOSS_HP_BASE | 1e100 (浮点,不可击杀) | WorldBoss.lua:28 |
| FIGHT_DURATION | 60 秒 | WorldBoss.lua:27 |
| MAX_ATTEMPTS | 3 次/赛季 | WorldBoss.lua:26 |
| SEASON_DURATION | 86400 秒 (24h) | WorldBoss.lua:24 |
| BOSS_ROSTER | 4 个Boss轮换 | WorldBoss.lua:31 |

### 排行榜存储 (int32 拆分)

```
totalDmg = hi × 1e9 + lo
排序字段: wb_dmg_k = totalDmg / 1000 (上限 INT32_MAX ≈ 2.15e12 原始伤害)
```

---

## 4. 无尽试炼生命周期

```
GameState.EnterTrial()                   GameState.lua:782
  ├─ endlessTrial.active = true
  ├─ endlessTrial.floor = 1
  └─ 保存当前关卡进度
       │
       ▼
  每层战斗:
  EndlessTrial.BuildTrialQueue(floor)    EndlessTrial.lua:129
    ├─ scaleMul = 2.0 × 1.25^(floor-1)  EndlessTrial.lua:78
    ├─ expScaleMul = scaleMul^0.3        EndlessTrial.lua:141
    ├─ Boss层(每10层) scaleMul ×2        EndlessTrial.lua:82
    └─ 返回 { templateId, template, scaleMul, expScaleMul, resistOverride }
       │
       ▼  (通关)
  EndlessTrial.AdvanceFloor(gold, exp)   EndlessTrial.lua:174
    ├─ totalGold += gold
    ├─ totalExp += exp
    └─ floor++
       │
       ▼  (玩家死亡)
  EndlessTrial.OnTrialDeath()            EndlessTrial.lua:186
    └─ 生成 result { floor, gold, exp, isNewRecord }
       │
       ▼
  TrialResultOverlay.Show() 结算面板
       │
       ▼
  GameState.ExitTrial()                  GameState.lua:798
    └─ 恢复关卡进度
```

### 试炼数值缩放

| 层数 | scaleMul (战斗) | expScaleMul (经验) | 怪物数量 |
|------|----------------|-------------------|---------|
| 1 | 2.0 | 1.23 | 8 |
| 5 | 4.9 | 1.58 | 10 |
| 10 | 14.9 (Boss×2=29.8) | 2.33 | 1 (Boss) |
| 20 | 177 (Boss×2=354) | 4.82 | 1 (Boss) |
| 30 | 2,112 | 9.99 | 16 |

怪物数量: `8 + floor(层/5) × 2`，上限 30 (EndlessTrial.lua:162)

---

## 5. 世界 Boss 血条分层系统

```
DamageTracker.GetSessionDamage()          DamageTracker.lua:74
  │
  ▼
DamageTracker.GetLayerInfo(sessionDmg)    DamageTracker.lua:178
  ├─ 反推层号: floor(log(D*(R-1)/B + 1) / log(R))
  ├─ 层内进度: (D - 前N层累计) / 当前层HP
  └─ 颜色: 每5层循环 (绿→蓝→紫→橙→红)
       │
       ▼
BattleView:DrawBossTimer()                BattleView.lua:871
  ├─ WorldBoss.active → 分层血条
  │     ├─ 背景黑条
  │     ├─ 层颜色填充 (barW × progress)
  │     ├─ 击穿闪白 (层变化时 1.0→0, 衰减 3.0/s)
  │     ├─ 层颜色边框
  │     └─ 层数标签 "×N" (血条右侧)
  └─ 普通Boss → 原有 hp/maxHp 血条
```

### 分层公式

| 参数 | 值 | 位置 |
|------|----|------|
| LAYER_BASE | 100,000 (10万) | DamageTracker.lua:145 |
| LAYER_RATIO | 1.5 | DamageTracker.lua:146 |
| 第n层HP | `BASE × RATIO^(n-1)` | DamageTracker.lua:155 |
| 累计击穿n层 | `BASE × (RATIO^n - 1) / (RATIO - 1)` | DamageTracker.lua:162 |

### 数值参考

| 层数 | 该层HP | 累计击穿所需 |
|------|--------|-------------|
| 1 | 10万 | 10万 |
| 5 | ~50.6万 | ~181万 |
| 10 | ~1,930万 | ~1.13亿 |
| 20 | ~19.4亿 | ~25.3亿 |

### 颜色循环 (每5层一轮)

| 层范围 | 颜色 | RGB |
|--------|------|-----|
| 1-5 | 绿 | (100, 220, 100) |
| 6-10 | 蓝 | (80, 160, 255) |
| 11-15 | 紫 | (180, 100, 255) |
| 16-20 | 橙 | (255, 160, 40) |
| 21-25 | 红 | (255, 60, 60) |
| 26+ | 循环回绿 | ... |

### 击穿闪白

- 触发: `info.layer > self._bossLayerPrev` (BattleView.lua:880)
- 动画: 全条白色叠加, alpha 从 200→0, 衰减速率 3.0/s
- 状态: `self._bossLayerFlash`, `self._bossLayerPrev`

---

## 6. DPS 显示

| 场景 | 数据来源 | 位置 |
|------|---------|------|
| 战斗中 (有实际伤害) | DamageTracker.GetRealtimeDPS() — 5秒滑动窗口 | HUD.lua:80 |
| 非战斗/无伤害 | GameState.GetDPS() — 理论值 ATK×SPD×(1+暴击期望) | HUD.lua:83, StatCalc.lua:377 |

---

## 7. 装备词条系统

### 数据结构 (装备对象)

```lua
{
    slot, slotName,                   -- 槽位: weapon/gloves/amulet/ring/boots/necklace
    qualityIdx, qualityName, qualityColor,  -- 品质: 1白/2绿/3蓝/4紫/5橙
    tier,                             -- 章节Tier (1,2,3...)
    tierMul,                          -- 词条乘数: 2^(chapter-1)
    mainStat, mainValue,              -- 主词条: key + 数值
    subStats = { {key, value}, ... }, -- 副词条数组
    setId,                            -- 套装ID (蓝+以上, 50%概率)
    upgradeLv,                        -- 强化等级 (0 ~ maxUpgrade)
    baseMainValue,                    -- 原始主词条值 (首次强化时记录)
    upgradeStonesSpent,               -- 已投入强化石总数
    element,                          -- 武器元素 (仅weapon槽位)
    locked,                           -- 锁定状态
}
```

### 词条生成公式

| 词条 | 公式 | 位置 |
|------|------|------|
| 主词条 | `base × mainMul × qualityMul × tierMul` | Equipment.lua:187 |
| 副词条 | `base × rand(0.8~1.0) × tierMul` | Equipment.lua:216 |

### Tier 缩放 (章节驱动换装)

```
tierMul = 2^(chapter-1)                Config.lua:13-19
```

| 章节 | tierMul | 橙装ATK主词条 |
|------|---------|-------------|
| 1 | 1.0 | 200 |
| 2 | 2.0 | 400 |
| 3 | 4.0 | 800 |
| 5 | 16.0 | 3,200 |
| 9 | 256.0 | 51,200 |

### 品质配置

| 品质 | qualityMul | 副词条数 | 最大强化 | 可套装 |
|------|-----------|---------|---------|-------|
| 白 | 1.0 | 0 | 0 | 否 |
| 绿 | 1.5 | 1 | 5 | 否 |
| 蓝 | 2.0 | 2 | 10 | 是 |
| 紫 | 3.0 | 3 | 15 | 是 |
| 橙 | 5.0 | 4 | 20 | 是 |

### 强化系统

| 机制 | 公式 | 位置 |
|------|------|------|
| 主词条成长 | `baseMainValue × (1 + lv × 0.05)` | Equipment.lua:93 |
| 每5级副词条提升 | 随机1条 `+baseValue × 0.5` | Equipment.lua:98 |
| 升级消耗 | `floor((2 + lv×1.2 + lv²×0.06) × chapter)` | Config.lua:131 |
| 分解退还 | 已投入强化石 × 80% | Equipment.lua:493 |

### 材料系统

```lua
GameState.materials = {
    stone = 0,        -- 强化石
    soulCrystal = 0,  -- 魂晶 (背包扩容用)
}
```

### 背包配置

| 常量 | 值 | 位置 |
|------|----|------|
| 初始容量 | 20 格 | Config.lua:1438 |
| 每次扩容 | +4 格 | Config.lua:1439 |
| 容量上限 | 100 格 | Config.lua:1440 |
| 首次扩容费 | 100 魂晶 | Config.lua:1449 |
| 每次递增 | +50 魂晶 | Config.lua:1450 |

### 装备槽位 (6个)

| 槽位 | ID | 主词条候选 | 特殊 |
|------|----|-----------|------|
| 武器 | weapon | atk/reactionDmg | 有元素属性 |
| 手套 | gloves | spd/crit/skillCdReduce | — |
| 护符 | amulet | crit/hpPct/skillCdReduce | — |
| 戒指 | ring | critDmg/reactionDmg/atk | — |
| 靴子 | boots | def/hpPct/spd | — |
| 项链 | necklace | luck/skillDmg/skillCdReduce | — |

### 关键函数速查

| 函数 | 位置 | 说明 |
|------|------|------|
| GenerateEquip(waveLevel, isBoss, chapter) | Equipment.lua:143 | 随机生成装备 |
| CreateEquip(qualityIdx, chapter, slotId) | Equipment.lua:295 | 确定性构造装备 |
| UpgradeEquip(slotId) | Equipment.lua:83 | 强化已穿戴装备 |
| AddToInventory(item) | Equipment.lua:383 | 入包(含自动分解) |
| EquipItem(invIndex) | Equipment.lua:400 | 穿戴 |
| AutoEquipBest() | Equipment.lua:449 | 一键穿戴最强 |
| DecomposeItem(invIndex) | Equipment.lua:487 | 分解 |
| DecomposeByFilter(maxQ, keepSets) | Equipment.lua:515 | 批量分解 |
| ItemPower(item) | StatCalc.lua:288 | 装备战力评分 |
| CanTierUpgrade(item, targetTier) | Equipment.lua:653 | 检查装备能否提升Tier |
| GetAvailableMagicStones(item) | Equipment.lua:667 | 获取可用魔法石列表 |
| TierUpgradeEquip(slotId, stoneItemId) | Equipment.lua:703 | 执行Tier提升(缩放词条) |
| PreviewTierUpgrade(item, targetTier) | Equipment.lua:745 | 预览Tier提升后词条值 |
| ForgeEquip(segmentId, lockSlotId) | Equipment.lua:475 | 锻造橙装(通用套,日限11) |
| GetForgeInfo() | Equipment.lua:693 | 锻造状态(免费/剩余次数) |

---

## 8. 魔法石 Tier 提升系统

### 道具类型

| 道具ID | 名称 | targetTier | 获取方式 | 使用条件 |
|--------|------|-----------|---------|---------|
| magic_stone:1~12 | T1~T12魔法石 | 1~12 | Boss掉落(程序化生成ITEM_MAP) | maxChapter >= n |
| magic_stone_top | 顶级魔法石 | 使用时=maxChapter | 兑换码/世界Boss(未定) | 无限制 |

### 掉落规则

- Boss击杀时独立判定: S10(大Boss)=1%, S5(小Boss)=0.7%, 不受幸运加成
- **不受幸运加成影响** (与 attr_reset/skill_reset 同模式)
- 当前章节Boss只掉当前章节的Tn魔法石
- 存储在通用道具背包 `GameState.bag` 中

### 提升逻辑

- **品质限制**: 蓝色(qualityIdx >= 3)及以上才能提升
- **Tier缩放公式**: `scale = GetChapterTier(targetTier) / GetChapterTier(oldTier)` = `2^(target-1) / 2^(old-1)`
- **受影响字段**: `mainValue`, `baseMainValue`, `subStats[].value`, `subStats[].baseValue`
- **保留字段**: `upgradeLv`, `upgradeStonesSpent`, `qualityIdx`, `setId`, `slot` (升级等级不重置)

### UI 入口

- 装备详情面板 → [提升Tier] 按钮 → 魔法石选择面板(预览词条变化) → 确认

---

## 9. 文件职责速查表

| 文件 | 职责 | 关键函数 |
|------|------|---------|
| **DamageTracker.lua** | 统一伤害统计 (全局累计+会话+实时DPS+血条分层) | Record, Update, StartSession, EndSession, GetRealtimeDPS, GetLayerInfo |
| **WorldBoss.lua** | 世界Boss系统 (赛季/挑战/排行榜/奖励) | EnterFight, EndFight, UploadDamage, FetchLeaderboard, GenerateBossTemplate |
| **BattleSystem.lua** | 战斗主循环编排器 | Init:123, Update:259, OnEnemyKilled:88, CleanupDead:463 |
| **battle/DamageFormula.lua** | 五区乘算伤害管线 (基础/增伤/暴击/减防/抗性) | BuildContext, Calculate, ApplyReaction, Zones |
| **battle/CombatCore.lua** | 普攻命中→管线→扣血→死亡 | HitEnemy:25, PlayerAttack:436 |
| **battle/CombatUtils.lua** | 战斗工具 (音效/击退/震屏/弹道) | RecordBossDmg:245 (ApplySharedDmgBonus已废弃) |
| **battle/SpiritSystem.lua** | 元素精灵 AI (水元素自主攻击) | UpdateElementSpirits |
| **battle/Spawner.lua** | 怪物生成 (队列→实例化) | BuildQueue:26, SpawnFromQueue:147 (expDrop在:195) |
| **battle/StageManager.lua** | 关卡/波次管理 (击杀→掉落→魔法石掉落→推进) | OnEnemyKilled:36, NextWave:151, RetryStage:300 |
| **battle/EnemySystem.lua** | 敌人AI/能力/分裂/死亡 | UpdateEnemyAI:87, OnEnemyDeath:517 (分裂:520, 召唤:299) |
| **battle/Loot.lua** | 掉落物生成/拾取 | Spawn:17, Collect:159 (exp→AddExp, gold→AddGold) |
| **EndlessTrial.lua** | 无尽试炼 (层推进/数值缩放/结算) | BuildTrialQueue:129, GetScaleMul:76, AdvanceFloor:174 |
| **GameState.lua** | 全局状态 (玩家属性/经济/存档) | AddExp:202, AddGold:221, EnterTrial:782, ExitTrial:798 |
| **state/StatCalc.lua** | 属性计算 (ATK/DEF/暴击/DPS等) | Install:7 (挂载到 GameState), GetDPS ≈:377 |
| **ui/HUD.lua** | 顶部状态栏 (等级/DPS/战力/魂晶) | Create:12, Refresh:68 |
| **StageConfig.lua** | 关卡/怪物配置 (章节/Boss/数值) | MONSTERS表, GetStage, GetStageCount |
| **BattleView.lua** | 战斗区NanoVG渲染 (敌人/弹道/Boss血条/伤害HUD) | DrawBossTimer:817 (分层血条), DrawBossDamageHUD:963 (伤害统计) |
| **state/Equipment.lua** | 装备生成/强化/背包/分解/Tier提升/锻造 (Install挂载到GameState) | GenerateEquip:143, CreateEquip:295, UpgradeEquip:83, TierUpgradeEquip:703, ForgeEquip:475, AddToInventory:383, DecomposeItem:487 |
| **Config.lua** | 全局常量 (MONSTERS/品质/词条/套装/Tier缩放) | GetChapterTier:13, EQUIP_QUALITY:240, EQUIP_STATS:256, EQUIP_SLOTS:291, UpgradeCost:131 |
| **TitleConfig.lua** | 称号定义 (12个) + userId→titleId 映射 (30人) | TITLES, USER_TITLES |
| **TitleSystem.lua** | 称号运行时 (解锁/属性加成/UI查询) | Init, GetBonus, GetUnlockedTitles, FormatEffects |
| **ui/InventoryPage.lua** | 背包UI (装备列表/详情/强化/分解) | — |
| **ui/InventoryCompare.lua** | 装备详情/对比浮层 (含Tier提升面板) | ShowCompare:325, ShowTierUpgradePanel:640 |

---

## 10. 关键数据结构

### GameState 核心字段

```lua
GameState.player = {
    level, exp, gold, hp, atk, def, ...
    allocatedPoints = { str, agi, vit, ... },
    inventory = { ... },  -- 装备背包
    equipped = { ... },   -- 已装备
}
GameState.stage = { chapter, stage, waveIdx, cleared }
GameState.records = { maxPower, maxChapter, maxStage }
GameState.endlessTrial = { active, floor, maxFloor, savedStage, totalGold, totalExp, result }
GameState.worldBoss = { season, attempts, totalDamage, lastReward }
GameState.materials = { stone, soulCrystal }
```

### 敌人实例字段 (bs.enemies[] 中每个元素)

```lua
{
    x, y,                    -- 位置
    hp, maxHp, atk, def,     -- 战斗属性
    speed, radius,           -- 移动/碰撞
    expDrop, goldMin, goldMax, -- 掉落
    isBoss, isWorldBoss,     -- 类型标记
    dead,                    -- 死亡标记
    element,                 -- 元素属性
    attachedElement,         -- 当前附着元素
    knockbackVx, knockbackVy, -- 击退速度
    atkTimer, atkCd, atkRange, -- 攻击节奏
    -- Boss 专有:
    barrage, dragonBreath, iceArmor, splitOnDeath, summon, ...
}
```

---

## 11. 称号系统

### 概述

基于首期排行榜快照的一次性称号奖励系统。userId 与称号映射硬编码在配置中，玩家首次登录时自动解锁匹配称号，效果永久叠加生效。

### 文件结构

| 文件 | 职责 |
|------|------|
| **TitleConfig.lua** | 称号定义 (12个) + userId→titleId 映射表 (30人) |
| **TitleSystem.lua** | 运行时核心：Init解锁、GetBonus属性查询、GetUnlockedTitles UI查询 |

### 数据流

```
游戏启动 → main.lua: TitleSystem.Init()
  │
  ▼
TitleSystem.Init()
  ├─ 检查 GameState.unlockedTitles 是否已有数据 (有则跳过)
  ├─ lobby:GetMyUserId() 获取当前玩家ID
  ├─ TitleConfig.USER_TITLES[userId] 查找映射
  ├─ 写入 GameState.unlockedTitles = { "power_1", "brave", ... }
  └─ SaveSystem.MarkDirty() 标记存档
```

### 属性加成集成 (StatCalc)

通过 `getTitleBonus(statKey)` 懒加载 TitleSystem，避免循环依赖。

| 属性函数 | statKey | 加成方式 |
|---------|---------|---------|
| GetTotalAtk | `"atk"` | `base × (1 + titleAtk)` — 力量灌注之后，怨魂之怒之前 |
| GetCritRateRaw | `"crit"` | `base + titleCrit` — arcane_sense 之后 |
| GetCritDmg | `"critDmg"` | `base × (1 + titleCritDmg)` — 套装乘算之后 |
| GetMaxHP | `"hp"` | `hpMul += titleHp` — 药水buff之后 |
| GetTotalDEF | `"def"` | `base × (1 + titleDef)` — 套装之后 |
| GetElemDmg | `"allElemDmg"` | 直接加算到返回值 |
| GetDebuffResist | `"debuffResist"` | `resist += titleResist` — cap之前 |

### 存档

- **GameState.Init**: `unlockedTitles = {}`
- **SlotSaveSystem.Serialize**: `unlockedTitles = GameState.unlockedTitles or {}`
- **SlotSaveSystem.Deserialize**: `GameState.unlockedTitles = data.unlockedTitles or {}`

### UI 展示

CharacterPage 中称号面板 (`char_title_panel`)，通过 dirty check (`CharKey()` 包含 `#unlockedTitles`) 按需刷新，显示格式：`【战力榜1】 攻击力+5% 暴击伤害+3%`

---

## 12. 已知设计债务

| 问题 | 位置 | 影响 |
|------|------|------|
| 分裂/召唤怪的 scaleMul 从主线 StageConfig 取,不从试炼队列取 | EnemySystem.lua:304, :525 | 试炼中分裂怪数值偏低 |
| BuffManager.lua 2467 行,StageConfig.lua 2396 行 | — | 超过 1500 行阈值,需拆分 |
| WorldBoss.RecordDamage 仍保留 (冗余) | WorldBoss.lua:242 | DamageTracker 已接管,但 RecordDamage 仍在累加 fightDamage (兼容) |
