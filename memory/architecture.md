# 项目架构速查表

> **用途**: AI 每次开始新会话时，先读此文件定位目标模块，找不到再去读实际文件。
> **维护规则**: 修改任何模块后，若此表内容已过时，必须同步更新。

---

## 项目概览

**名称**: 挂机英雄·术士 (Idle Hero - Warlock)
**类型**: 挂机 RPG，元素战斗系统
**规模**: 72 个 Lua 文件，~30,000 行代码，163+ 纹理资源
**版本**: 1.15.3

---

## 目录结构

```
scripts/
├── main.lua                    # 入口：初始化所有系统，设置 UI 结构，主循环
├── Config.lua                  # 数值配置(~1650行)：对数缩放公式、基础值、装备属性(EQUIP_STATS 26项含overpowerDmg)、AFFIX_DEFS(8触发词缀)、AFFIX_POOL(26+8=34统一词缀池,含bucket六桶字段+overpowerDmg)、AFFIX_POOL_MAP、AFFIX_BUCKET_COLORS(7桶颜色)/AFFIX_BUCKET_LABELS(7桶标签)、IP_QUALITY_MUL/IP_PER_UPGRADE/AFFIX_COUNT_BY_QUALITY(IP词缀系统)、套装(仅8套)、元素反应、掉落模板、DROP_BATCHES、金币缩放、图标路径; Config.MANA(法力系统: base/perLevel/regenBase/willRegenPer); 尾部调用ConfigCalc.Install(Config)注入计算函数
├── ConfigCalc.lua              # Config计算函数(~260行): Install(Config)模式注入, CalcBaseIP(章节→IP)/IPToTierMul(IP→等效tierMul)/GetChapterTier/GetAttrScale/ResistMul/DefMul/LevelExp/UpgradeCost/GetEquipSlotIcon/GetDropBatch/IsSetInBatch/GetForgeSegmentScaleMul/GetForgeGoldCost/GetForgeStoneCost/GetGemIcon/CalcGemStat
├── GameState.lua               # 中央状态(~450行)：Init(数据声明)、AddExp/AddGold/SpendGold、UpdateRecords、ValidatePoints、离线奖励、试炼进出；方法由8个state/模块Install注入
├── SlotSaveSystem.lua          # 存档系统(核心)：10槽云存档，30秒自动存档，版本迁移(v1→v10, v8→v9: 旧技能ID退还技能点, v9→v10: 清理废弃元素词缀), RegisterDomain域注册, allocatedPoints序列化走StatDefs.POINT_STATS循环
├── SaveSystem.lua              # 存档系统(代理层)：转发至SlotSaveSystem，兼容20+文件的旧引用
├── Utils.lua                   # 工具函数：FormatNumber/FormatNumberInt(统一数字格式化)、Debounce
├── Config/                     #   (空目录, RetiredSets.lua已删除)
├── StageConfig.lua             # 章节/关卡/怪物配置 (~4500行, 16章×10关+怪物定义, scaleMul由CalcScaleMul动态计算); 双轨: ch.stages(旧手工关卡) / ch.families(新家族自动编排); STAGE_TEMPLATES(10种关卡模板); generateStages()自动编排; ResolveMonster(mId,ch,tagLevels)统一解析(MONSTERS直查→家族Resolve→懒注册)
├── MonsterTemplates.lua        # 怪物模板系统: 7行为模板 × 12抗性模板 × 16能力标签 × 14章节主题, Assemble()输出Spawner兼容定义
├── MonsterFamilies.lua         # 怪物家族系统(D4式): 8家族(undead/beast/elemental_fire/ice/poison/arcane/divine/aquatic), 每家族7成员(对应7行为模板); Get/GetAllIds/Resolve/ResolveById; mergeTags处理optionalTags×章节阈值; RACE_TIERS(5种族基础属性: demon/undead/beast/humanoid/construct)、MONSTER_RACE(familyId→raceId映射)
├── BossArchetypes.lua          # Boss原型系统(D4式): 7原型(striker/charger/summoner/fortress_2p + sovereign/overlord/herald_3p); ELEMENT_FLAVOR(6元素注入); Resolve({archetype,element,family},ch)→Spawner兼容Boss定义; MakeBossId/GetArchetype
├── SkillTreeConfig.lua         # 技能树定义：D4术士式3元素(火/冰/雷)7层辐射树，31技能+7关键被动+增强线，D4六桶伤害公式; coreSkill标记(核心技能走攻速槽位)
├── WorldTierConfig.lua         # 世界层级统一配置(D4式): TIERS[1-4](label/cap/hpMul/dmgMul/dropMul/xpMul/resistPen/defK_player_base/defK_player_perLv/defK_enemy_base/defK_enemy_perLv), GetTier(id)→tier表, MAX_TIER=4
├── DynamicLevel.lua            # 动态等级计算(D4式): CalcMonsterLevel(playerLevel, areaFloor, worldTierCap)=clamp(playerLevel, areaFloor, worldTierCap); CalcHPMul/CalcATKMul/CalcDEFBase(monsterLevel)指数缩放; CalcDropMul/CalcXPMul对数缩放; GetEffectiveDifficulty(monsterLevel, playerLevel)
├── DefenseFormula.lua          # 护甲/抗性减伤公式: CalcPlayerDefK/CalcEnemyDefK(monsterLevel)→K值随等级缩放; DefMul(def,K)/PlayerDefMul/EnemyDefMul; ResistMul(resist); CalcEffectiveResist(faceResist,worldTierId)世界层级穿透; ResistMulWithPen
├── SpireTrial.lua              # 尖塔试炼模块(D4式): FLOOR_DEFS(30层定义, 每层areaFloor+familyId+bossArchetype); Enter/Exit/NextFloor/OnKill/BuildQueue; 接入DynamicLevel+MonsterFamilies+WorldTierConfig; GameMode适配器("spireTrial")
│
├── state/                      # 状态模块 (Install模式注入GameState, 共8个)
│   ├── StatModifiers.lua        #   属性修饰器注册系统(~120行): Register/Remove/Collect/Apply, 5类型(pctPool/pctMul/pctReduce/flatAdd/flatSub), conditionFn条件修饰器, 替代StatCalc硬编码if-timer
│   ├── StatDefs.lua            #   属性注册表(单一数据源, P1重构): CORE_STATS(4核心属性STR/DEX/INT/WIL, effects+classEffects声明式), POINT_STATS=CORE_STATS别名, CalcCoreBonus(), MakeAllocatedPoints(), DODGE_CAP/ALL_RESIST_CAP/OVERKILL_HP_THRESHOLD, EQUIP_IMPORTANCE(战力权重), GetTierMul(), GetImportance()
│   ├── BuffRuntime.lua         #   Buff/Debuff运行时(~750行): InitBuffState/ResetBuffs, 11种Apply*Debuff(含ch16浸蚀+潮蚀), UpdateDebuffs, AddShield/OnKillShield, 6个药水Buff函数, 尾部注册SM条件修饰器(atk×4/atkSpeed×7/crit×2); 已移除旧Frenzy/AtkBuff/Berserk tick
│   ├── Combat.lua              #   战斗核心(HP/伤害/法力/击杀): ResetHP, DamagePlayer(rawDmg, monsterLevel)(闪避判定+双返回值; 含last_stand词缀减伤; monsterLevel透传GetDEFMul), CalcElementDamage(rawDmg,element)(含世界层级抗性穿透via DefenseFormula), GetElementResist(含全抗), ResetMana/TickManaRegen/HasMana/SpendMana(D4法力系统), OnKill等
│   ├── Equipment.lua           #   装备系统(6槽位, D4式统一词缀affixes[], IP驱动缩放, CreateEquip/RollAffixes/InfuseEquip/PreviewInfuse, Greater词缀橙品15%×1.5倍)
│   ├── StatCalc.lua            #   属性计算(含GetMaxHP支持hpPct, GetMaxMana/GetManaRegen(D4法力公式), GetSkillCdMul乘算CDR, ItemPower权重委托StatDefs.GetImportance), GetTotalAtk/GetAtkSpeed/GetCritRate走SM.Apply, GetDEFMul(monsterLevel)接入DefenseFormula.PlayerDefMul(延迟require避免循环依赖), 尾部注册3条永久修饰器
│   ├── AttrPoints.lua          #   属性加点: Allocate/Deallocate(单/批量), ResetAttributePoints, GetResetAttrCost
│   ├── SkillPoints.lua         #   技能点: CanUpgrade/Upgrade/Downgrade/ResetSkillPoints, GetSkillLevel, GetAvailableSkillPts
│   ├── BagSystem.lua           #   通用道具背包: AddBagItem/GetBagItemCount/DiscardBagItem/UseBagItem(含重置道具)
│   ├── GemSystem.lua           #   宝石系统: 背包CRUD, 镶嵌/拆卸/合成/打孔, GetGemStats(属性汇总)
│   └── AffixHelper.lua         #   词缀工具模块(非Install): GetAffixValue/HasAffix/GetAllAffixes/FormatDesc, 遍历equipment.affixes汇总词缀数值
│
├── battle/                     # 战斗子系统 (15个文件, ~8000行)
│   ├── Spawner.lua             #   敌人波次生成(已走GameMode适配器, 通过StageConfig.ResolveMonster统一解析怪物ID); enemy对象携带level字段(entry.monsterLevel or template.level)供EnemySystem透传
│   ├── PlayerAI.lua            #   玩家自动瞄准(coreSkill跳过CD通道, 由攻速计时器驱动)
│   ├── CombatCore.lua          #   基础攻击处理(含D4核心技能优先施放: FindEquippedCoreSkill→HasMana→攻速槽位施放; 词缀hook: combo_strike连击/crit_surge暴击强化/kill_heal击杀回复)
│   ├── DamageFormula.lua       #   伤害公式(D4六桶乘算: Base×MainStat×A-Damage×Crit×Vulnerable×X-Damage+Overpower), BuildContext构建上下文(ctx.worldTierId替代旧scaleMul), CalcDef接入DefenseFormula.CalcEnemyDefK(monsterLevel), CalcResistance接入DefenseFormula.CalcEffectiveResist(世界层级穿透)
│   ├── SkillCaster.lua         #   技能施放入口(v4.0模块化): DispatchCast/CastSkill(含manaCost扣蓝检查)/_CastGenericAoe + Register调用 + 向后兼容别名, 具体施放函数按元素拆分到 skills/ 子模块
│   ├── skills/                 #   技能施放子模块 (按元素拆分)
│   │   ├── Helpers.lua         #     公共工具(11函数): HasEnhance/FindBestAoeCenter/FindNearestEnemy/GetAliveEnemies/HitEnemySkill/ApplyChill/ApplyFreeze/ApplyFrostbite/ApplyBurn/ApplyVulnerable/ApplyStun
│   │   ├── FireSkills.lua      #     火系(8技能): fire_bolt/fireball/incinerate/flame_shield/hydra/firewall/fire_storm/meteor
│   │   ├── IceSkills.lua       #     冰系(7技能): frost_bolt/ice_shards(弹道模式: 5枚横向排列碎片→bs.frostShards, onHit回调)/ice_armor(D4屏障6秒: 强化→法力回复+30%[x], 神秘→周期冻伤+冻结伤害+15%[x], 微光→花费50法力减1秒CD)/frost_nova/blizzard/frozen_orb/deep_freeze
│   │   └── LightningSkills.lua #     雷系+奥术(9技能): spark/arcane_strike/charged_bolts/chain_lightning/teleport/lightning_spear/thunderstorm/energy_pulse/thunder_storm
│   ├── BulletSystem.lua        #   弹道物理(已清空, 旧通用分支弹道逻辑已移除)
│   ├── BuffManager.lua         #   套装Buff聚合入口 (~50行, 子模块重导出+GetTotalSetDmgReduce/AtkSpeedBonus, Frenzy/Atk/Berserk tick已迁移至BuffRuntime)
│   ├── buffs/                  #   套装Buff子模块 (22个单章套装已删除, 仅保留跨章+Ch13)
│   │   ├── NewSets.lua         #     跨章套装 (~940行): swift_hunter/fission_force/shadow_hunter/iron_bastion/dragon_fury/rune_weaver
│   │   └── T13Sets.lua         #     Ch13套装 (~340行): lava_conqueror(熔岩征服者: 点燃DOT/熔岩爆发/熔岩领主), permafrost_heart(极寒之心: 受冰伤回血/致命保护冻结/寒冰化身)
│   ├── ElementReactions.lua    #   [已清空] 元素反应系统已移除，仅保留空壳兼容require
│   ├── EnemySystem.lua         #   敌人AI与特殊能力(100-400行); EnemyAttackPlayer读取enemy.level透传至GetDEFMul(monsterLevel)+DamagePlayer(rawDmg,monsterLevel)
│   ├── MeteorSystem.lua        #   陨石/范围延迟效果
│   ├── SpiritSystem.lua        #   元素精灵AI
│   ├── DropManager.lua          #   掉落管理器(数据驱动): DROP_RULES声明式掉落表(7条规则: exp/gold/equip/soulCrystal/tickets/magicStone), ProcessDrops(bs,enemy,mode), AddRule/RemoveRule动态扩展, 词缀hook: greed金币+N%/scholar经验+N%
│   ├── StageManager.lua        #   波次推进(已走GameMode适配器, 掉落委托DropManager.ProcessDrops)
│   ├── Loot.lua                #   掉落物理、拾取(已通过EventBus解耦Toast依赖)
│   ├── Particles.lua           #   视觉特效
│   ├── CombatUtils.lua         #   共享工具(击退、震屏、音效)
│   ├── ThreatSystem.lua        #   威胁表管理+空间碰撞工具(CircleCircle/PointInSector/PointInRing/PointInRect)
│   └── BossSkillTemplates.lua  #   Boss技能模板系统(~1930行): 15模板(ATK×5/DEF×4/CTL×4/SUM×2), 公共helper(_timerUpdate/_hitPlayer), 阶段转换, 可摧毁物, flattenSkillCfg, invokeOrApplyEffect
│
├── view/                       # 渲染层 (NanoVG)
│   ├── DrawEntities.lua        #   玩家、敌人、掉落物、精灵
│   ├── DrawEffects.lua         #   技能效果、Boss能力(含DrawBossTemplates桥接); 25个技能特效渲染器(3元素: fire_bolt/frost_bolt/spark/arcane_strike/fireball/incinerate/ice_shards/charged_bolts/chain_lightning/flame_shield/ice_armor/frost_nova/teleport/hydra_summon/blizzard/lightning_spear/firewall/fire_storm/frozen_orb/thunderstorm/energy_pulse/meteor/deep_freeze/thunder_storm/generic_aoe) + Boss特效
│   ├── DrawBossTemplates.lua   #   Boss模板渲染(~280行): 弹体/区域/阶段转换/可摧毁物/衰减指示器
│   └── DrawParticles.lua       #   粒子系统
│
├── BattleView.lua              # 战斗视图(自定义NanoVG Widget), 伤害数字显示(FormatDmg→Utils.FormatNumber)
├── BattleSystem.lua            # 战斗编排器(薄层, 协调所有battle/子系统, 已走GameMode适配器)
├── DamageTracker.lua           # DPS追踪(滑动窗口, LAYER_BASE=100000, LAYER_RATIO=1.5)
│
├── ui/                         # UI组件 (20个文件, ~12000行)
│   ├── TabBar.lua              #   底部导航(角色/背包/装备/技能/商店)
│   ├── HUD.lua                 #   顶部状态栏(DPS/战力/魂晶, 用Utils.FormatNumber)
│   ├── StatusBars.lua          #   HP/MP/护盾/经验条(D4法力条: 蓝色主题, id=mp_fill/mp_text)
│   ├── StageSelect.lua         #   章节/关卡选择
│   ├── CharacterPage.lua       #   属性加点(P1: STR/DEX/INT/WIL 4核心属性+子效果行, 闪避率/全抗UI, 用Utils.FormatNumber)
│   ├── BagPage.lua             #   道具背包
│   ├── InventoryPage.lua       #   装备管理(强化石数量用Utils.FormatNumber)
│   ├── InventoryCompare.lua    #   装备对比/详情面板(词缀展示: BuildHalfCard紧凑/BuildDetailCard完整, 分类颜色+强化金星)
│   ├── SkillPage.lua           #   技能树UI(v4.0): 编排层, 连接SkillTreeCanvas+header/loadout/info chrome+overlay弹窗+QuickEquip
│   ├── SkillTreeLayout.lua     #   技能树布局算法: 中央脊柱+左右分支(火=左,冰=右,雷=交替)+增强卫星弧排列+门槛节点, Build()/GetNodeAt()
│   ├── SkillTreeCanvas.lua     #   技能树NanoVG画布Widget: 13步渲染管线+拖拽平移+惯性+滚轮/捏合缩放+锚点变换+命中检测
│   ├── ShopPage.lua            #   药水商店(金币用Utils.FormatNumber)
│   ├── Leaderboard.lua         #   云排行榜(FormatBigNumber→Utils.FormatNumber)
│   ├── Settings.lua            #   游戏设置(音量/震动/特效/兑换码/切换存档)
│   ├── StartScreen.lua         #   开始界面：存档槽选择(加载/新建/删除)
│   ├── Toast.lua               #   通知系统
│   ├── Colors.lua              #   UI颜色常量
│   ├── OfflineChest.lua        #   离线奖励弹窗(v1.12: 按最高通关关卡算金币/经验, 橙装≤10件, 魂晶含章节缩放)
│   ├── EndlessTrialPanel.lua   #   无尽试炼UI
│   ├── TrialResultOverlay.lua  #   试炼结算
│   ├── WorldBossPanel.lua      #   世界Boss面板(FormatDamage→Utils.FormatNumber)
│   ├── WorldBossResult.lua     #   Boss排名结算(FormatDamage→Utils.FormatNumber)
│   ├── BossCodex.lua           #   Boss图鉴
│   ├── ResourceDungeonPanel.lua #  折光矿脉入口面板(剩余次数/奖励预览/进入按钮)
│   ├── ResourceDungeonResult.lua #  折光矿脉结算(宝石分品质展示/棱镜/再次挑战)
│   ├── ChallengePanel.lua      #   挑战面板(3Tab: 无尽试炼/世界Boss/折光矿脉)
│   └── RewardPanel.lua         #   奖励面板(3Tab: 奖励/日常/离线, 嵌入VersionReward/DailyRewards/OfflineChest的BuildContent)
│
├── TitleConfig.lua             # 称号定义 & userId→称号ID映射表
├── TitleSystem.lua             # 称号系统：解锁/效果计算/佩戴(展示)/UI查询
├── GameMode.lua                # 游戏模式统一调度器(Strategy+Mediator): SwitchTo/ExitCurrent/SetTransitionCallback + GetBackground/DrawWaveInfo委托 + Register/GetActive/Is/IsAnyActive, 兼容Activate/Deactivate
├── EventBus.lua                # 轻量事件总线: On/Off/Emit/Clear, 用于解耦跨层通信
├── EndlessTrial.lua            # 无尽试炼v2(MonsterTemplates集成, scaleMul锚定玩家章节, 抗性/行为轮换, 逐层一次性经验, Boss查询走StageConfig.ResolveMonster) + GameMode适配器
├── ResourceDungeon.lua          # 折光矿脉(每日3次, 60秒限时击杀, 宝石+棱镜奖励) + GameMode适配器
├── ResourceDungeonConfig.lua    # 折光矿脉怪物配置: 7普通+1精英定义, 出场序列(31波), 专属贴图路径, 章节抗性映射
├── WorldBoss.lua               # 世界Boss(24h赛季, 3次挑战, 科学计数法云存储) + GameMode适配器
├── AbyssMode.lua               # 深渊模式(v2重写): 接入DynamicLevel+MonsterFamilies+WorldTierConfig; BuildQueue按familyId从MonsterFamilies解析, _makeEntry设置monsterLevel/monsterDef/monsterHp; Boss每5层30s限时, 死亡/超时重试 + GameMode适配器
├── AbyssConfig.lua             # 深渊数值配置(v2重写): 接入DynamicLevel替代旧scaleMul; THEMES(5主题轮换每50层, 含familyId/element/bg); GetFloorConfig(floor,playerLevel,worldTierId)→{monsterLevel,hpMul,atkMul,defBase,isBoss,theme,...}; GetBossConfig(floor,...); ABYSS_AREA_FLOOR/REWARDS常量
├── DailyRewards.lua            # 每日/每周/每月奖励
├── VersionReward.lua           # 版本更新奖励
├── RedeemSystem.lua            # 兑换码系统
└── ManualSave.lua              # [已废弃] 旧手动存档槽，被SlotSaveSystem取代
```

---

## 核心数据流

```
启动 → SlotSaveSystem.Init → StartScreen(槽选择) → BuildGameUI → 游戏循环

用户输入 → UI组件 → GameState 修改 → SaveSystem(代理) → SlotSaveSystem(云存档)
                         ↓
               BattleSystem.Update(dt)
                         ↓
               BattleView.Render (NanoVG)

存档切换: SwitchSaveSlot() → SaveAndUnload → StartScreen → LoadSlot → BuildGameUI
```

### 存档系统架构
```
SlotSaveSystem (核心, 分片存储 format=2)
  ├── 域注册 (RegisterDomain): 各模块自注册 {name, keys, group, serialize, deserialize}
  │     已注册域: endlessTrial, worldBoss, resourceDungeon, dailyRewards(含quests), titles(unlockedTitles+equippedTitle), forge, abyss(maxFloor)
  │     Serialize/Deserialize/SplitIntoGroups 均通过域循环实现, 消除硬编码字段知识
  ├── 分片格式 (每个 key ≤9KB, 兼容 clientCloud 10KB 限制):
  │     s_N_head     → 索引 (format/version/timestamp/keys校验信息)
  │     s_N_core     → 玩家基础/关卡/记录
  │     s_N_currency → 材料/扩展槽
  │     s_N_equip    → 装备
  │     s_N_inv      → 背包 (超9KB自动拆为 s_N_inv_0, s_N_inv_1, ...)
  │     s_N_skills   → 技能/药水Buff
  │     s_N_misc     → 杂项(兑换码/bag/gemBag + 域注册的keys)
  ├── 装备压缩: equip/inv 组写入时压缩键名(slot→s, qualityIdx→q等, ip=itemPower, af=affixes{i/v/g}), 删除可推导字段(slotName/qualityName/qualityColor), 加载时自动还原
  ├── DJB2 校验码: 每个分组/分片写入时计算, 存入 head.keys
  ├── 向后兼容: 同时回写 save_data (旧格式, 未压缩), 读取时自动检测格式(新旧均兼容解压)
  ├── 旧格式: save_slot_N (单key), 仍可读取并在下次保存时升级为分片格式
  ├── 元数据: save_meta (JSON, 槽位摘要)
  ├── 迁移: 旧 save_data + manual_save_data → slot 1 + slot 2 (同时写分片+旧格式)
  └── 30秒自动云存档 + MarkDirty即时标记

SaveSystem (代理层, ~110行)
  └── 转发所有调用到 SlotSaveSystem (Save/SaveNow/MarkDirty/Serialize/Deserialize等)
      20+ 文件通过 require("SaveSystem") 使用，无需逐个修改
```

### 战斗循环执行顺序
```
BattleSystem.Update(dt)
  → TickHPRegen    (HP回复)
  → TickManaRegen  (D4法力回复)
  → Spawner        (刷怪)
  → PlayerAI       (选敌, 含威胁感知+优先目标; coreSkill跳过CD通道)
  → CombatCore     (普攻, 含D4核心技能优先施放+可摧毁物分支)
  → SkillCaster    (技能, 动态分发到 skills/{Fire,Ice,Lightning}Skills, 含manaCost检查)
  → BulletSystem   (弹道)
  → EnemySystem    (敌人AI, phases路由守卫)
  → ThreatSystem   (威胁表更新)
  → BossSkillTemplates (模板Boss: 阶段检查/技能施放/弹体/区域/可摧毁物/漩涡)
  → BuffManager    (套装Buff计时)
  → MeteorSystem   (延迟效果)
  → SpiritSystem   (精灵AI)
  → StageManager   (波次推进)
  → Loot           (掉落拾取)
```

---

## 关键模式

### state/ Install 模式
```lua
-- state/Equipment.lua
local M = {}
function M.Install(GS)
    function GS.EquipItem(...) ... end
end
return M
```
state/ 下的模块通过 `Install(GameState)` 向 GameState 注入方法。
Install 顺序: StatCalc → BuffRuntime → Combat → Equipment → AttrPoints → SkillPoints → BagSystem → GemSystem（BuffRuntime 须在 Combat 之前，因 ResetHP 调用 ResetBuffs）
StatModifiers 无 Install，纯数据模块。StatCalc.Install 尾部注册永久修饰器 (3条)，BuffRuntime.Install 尾部注册条件修饰器 (12条)

### 数字格式化 (Utils.FormatNumber)
```
<1万: 原始值   ≥1万: X.XX万   ≥1亿: X.XX亿   ≥1万亿: X.XX万亿   ≥1e16: X.XX×10^N
```
**已接入**: HUD, CharacterPage, ShopPage, InventoryPage, BattleView, Leaderboard, WorldBossPanel, WorldBossResult, StatCalc
**全部已接入**

### WorldBoss 云存储 (科学计数法)
```
SplitDamage(totalDmg) → mantissa(9位) + exponent
MergeDamage(man, exp) → float64
EncodeSortKey(man, exp) → exp × 1e7 + man前7位 (单int32排序键)
云字段: wb_dmg_k(排序键), wb_dmg_hi(mantissa), wb_dmg_lo(exponent)
```

### 章节缩放 (v1.9.1 对齐公式 + P2 IP重构 + v2.0 DynamicLevel迁移)
```
tierMul = 1 + 99 × ln(ch) / ln(100)       -- 对数增长, ch100=100× (仅章节缩放/怪物用)
attrScale = sqrt(tierMul)                  -- 属性点贡献保持10-17%
ch1=1, ch6≈39.5, ch10≈50.5, ch12≈54.4

IP (Item Power) = CalcBaseIP(ch) × IP_QUALITY_MUL[qi] + upgradeLv × IP_PER_UPGRADE
CalcBaseIP(ch) = 100 + 825 × ln(ch) / ln(100)  -- ch1=100, ch100=925
IPToTierMul(ip) = 1.0 + 99 × (ip - 100) / 825  -- IP→等效tierMul桥接(宝石系统用)

装备: affixes[].value = base × ipFactor × roll × greaterMul; ipFactor = 1 + (IP/100 - 1) × ipScale
怪物(章节模式): scaleMul = difficultyRatio × tierMul × playerPowerMul(ch) (v3 校准)
  difficultyRatio_s1 = 1.4 × (1 + 0.08×(ch-1))   -- 每章+8%
  difficultyRatio 在章内指数插值, s10/s1 = 5.5714
  playerPowerMul = PLAYER_POWER_MUL[ch] 查表+线性插值 (追踪分裂弹/攻速/暴击DPS倍增)
  → StageConfig.GetScaleMul(chapter, stage) 统一获取
  怪物DEF: def = template.def × scaleMul (v3, Spawner+EnemySystem共3处)
  → 伤害保留率 = 1 - template.def/(template.def+100), 与章节无关

怪物(深渊/尖塔): 已迁移至 DynamicLevel 动态等级系统 (v2.0)
  monsterLevel = clamp(playerLevel, areaFloor, worldTierCap)  -- D4式动态等级
  HP缩放: 1 + 0.15 × (monsterLevel-1)  (指数)
  ATK缩放: 1 + 0.08 × (monsterLevel-1) (指数)
  DEF基础: 50 × (1 + 0.05 × (monsterLevel-1))
  → DynamicLevel.CalcMonsterLevel/CalcHPMul/CalcATKMul/CalcDEFBase

DEF减伤公式 (v2.0 DefenseFormula):
  玩家DEF: K = 200 × (1 + 0.04 × (monsterLevel-1)), reduction = DEF/(DEF+K)
  敌人DEF: K = 100 × (1 + 0.03 × (monsterLevel-1)), reduction = DEF/(DEF+K)
  世界层级穿透: T1=0%, T2=5%, T3=10%, T4=15% (effectiveResist = resist × (1-pen))
  → DefenseFormula.CalcPlayerDefK/CalcEnemyDefK/CalcEffectiveResist
```

### 边际递减 (v1.8.0)
```
攻速: 渐近线 = 1 + cap×Δ/(Δ+K), cap=baseCap×attrScale(ch), buff乘在递减后
  Config.ATK_SPEED_DR = { baseCap=4.0, K=3.0 }
  GetAtkSpeedRaw() → 递减 → ×buffMul → ×debuff → 下限0.1
范围: 渐近线 = baseRange + maxBonus×raw/(raw+K)
  Config.RANGE_DR = { maxBonus=150, K=40 }
暴击率: 硬顶100%, 溢出→暴伤(3:1), 无额外递减
韧性: 硬顶80%, 线性
```

---

## 游戏模式

### GameMode 统一调度器 (v1.16 重构 → v1.17 模块化)
```
GameMode.lua — 统一调度器 (Strategy + Mediator 模式)

  ── 生命周期 ──
  ├── SwitchTo(name)            退出旧模式→进入新模式→过渡回调 (OnExit→OnEnter→transition)
  ├── ExitCurrent()             仅退出, 不触发过渡 (用于存档切换/章节跳转)
  ├── SetTransitionCallback(fn) 注册一次: BattleSystem.Init + RefreshStageInfo
  ├── Register(name, adapter)   各模式文件尾部自注册
  ├── Activate(name) / Deactivate()   兼容旧路径 (battle/结算面板仍用)
  ├── GetActive() → adapter|nil   battle/ 子系统调用, nil=章节模式
  └── Is(name) / IsAnyActive()

  ── 显示层 (BattleView 调用) ──
  ├── GetBackground() → string|nil   背景图路径 (nil=章节背景)
  └── DrawWaveInfo(nvg,l,bs,alpha) → bool   波次公告渲染 (true=已处理)

适配器接口 (每个模式实现的方法):
  ── 生命周期 ──
  :OnEnter()                → bool (false=进入失败, 如次数用完)
  :OnExit()                 → nil  (清理状态, 恢复关卡)
  .background               → string|nil (背景图路径)
  :DrawWaveInfo(nvg,l,bs,a) → nil  (波次公告渲染)

  ── 战斗 ──
  :BuildSpawnQueue()        → queue           -- Spawner
  :GetBattleConfig()        → {isBossWave, bossTimerMax, startTimerImmediately}  -- BattleSystem.Init
  :OnEnemyKilled(bs, enemy) → handled(bool)   -- StageManager
  :SkipNormalExpDrop()       → bool            -- StageManager
  :CheckWaveComplete(bs)    → handled(bool)    -- StageManager
  :OnNextWave(bs)           → handled(bool)    -- StageManager
  :OnDeath(bs)              → handled(bool)    -- StageManager.RetryStage
  :OnTimeout(bs)            → handled(bool)    -- BattleSystem.Update
  :IsTimerMode()            → bool             -- StageManager / BattleSystem
  :GetDisplayName()         → string           -- main.lua RefreshStageInfo
```

**v1.16 消除**: battle/ 24处 if/elseif → GameMode 调度
**v1.17 消除**: main.lua 散落的模式守卫/BattleSystem.Init/RefreshStageInfo → SwitchTo; BattleView DrawBackground/DrawWaveInfo if/else链 → GetBackground/DrawWaveInfo 委托

| 模式 | 适配器名 | 逻辑文件 | UI文件 | 说明 |
|------|---------|---------|--------|------|
| 章节推进 | *(无, GetActive()=nil)* | BattleSystem + StageConfig | StageSelect | 波次战斗, Boss每5关 |
| 无尽试炼 | `endlessTrial` | EndlessTrial(v2) | EndlessTrialPanel, TrialResultOverlay | MonsterTemplates集成, scaleMul锚定章节, 逐层一次性经验, 排行榜v3 |
| 世界Boss | `worldBoss` | WorldBoss | WorldBossPanel, WorldBossResult | 24h赛季, 全服排行 |
| 折光矿脉 | `resourceDungeon` | ResourceDungeon + ResourceDungeonConfig | ResourceDungeonPanel, ResourceDungeonResult | 两段式: 前3次批量奖励, 第4次+概率掉落, 60秒限时 |
| 深渊 | `abyss` | AbyssMode + AbyssConfig | *(无独立面板, main.lua quickBar按钮)* | v2重写: DynamicLevel+MonsterFamilies, 无限层数, Boss每5层(30s限时), 死亡/超时=重试 |
| 尖塔试炼 | `spireTrial` | SpireTrial | *(待实现UI)* | D4式: 30层定义, DynamicLevel+MonsterFamilies+WorldTierConfig, 世界层级选择 |

---

## 资源路径

```
assets/
├── Textures/
│   ├── Items/       # 装备图标
│   ├── Loot/        # 金币、魂晶等掉落图标
│   ├── mobs/        # 怪物贴图
│   │   ├── mine/    # 折光矿脉专属贴图 (8张: 碎晶虫/折光蝠/矿脉卫兵/辉石蛞蝓/晶能术士/岩晶巨兽/爆晶虫/折光领主)
│   │   └── ch16: tidal_crab/abyssal_stingray/coral_tortoise/deepsea_warlock/bloat_jellyfish/coil_serpent/ancient_kraken/tide_hierophant/boss_tide_commander/boss_abyssal_leviathan
│   └── skills/      # Boss技能释放贴图 (66张: 11模板×6元素, boss_{模板}_{元素}.png)
├── *.png            # 套装徽章/部位图标 (根目录)
└── audio/sfx/       # 音效
```
引用方式: `cache:GetResource("Texture2D", "Textures/skills/boss_barrage_ice.png")` (不加 `assets/` 前缀)

---

## 称号系统

**文件**: TitleConfig.lua (定义) + TitleSystem.lua (逻辑)

**数据流**: userId → TitleConfig.USER_TITLES → 首次登录发放 → GameState.unlockedTitles (存档持久化)

**属性加成**: StatCalc 调用 `TitleSystem.GetBonus(statKey)` 叠加所有已解锁称号效果，不受佩戴状态影响

**佩戴系统**: `GameState.equippedTitle` 存储单个称号ID(string|nil)，纯展示用途
- 佩戴/卸下不影响属性加成（所有已解锁称号效果始终生效）
- 同时只能佩戴一个，佩戴新称号自动卸下旧称号
- 存档字段: `equippedTitle` (SlotSaveSystem 序列化/反序列化)

**UI**: CharacterPage 称号标签，每称号一行（名称 + 效果 + 佩戴/卸下按钮）

---

## 宝石镶嵌系统 (v1.13)

**设计文档**: `docs/数值/宝石镶嵌系统.md`

**涉及文件**:
| 文件 | 改动 |
|------|------|
| Config.lua | `EQUIP_CATEGORIES`, `GEM_TYPES`(7种, diamond带overrides声明式配置), `GEM_TYPE_MAP`, `GEM_QUALITIES`(5级), `GEM_SYNTH_COST=3`, `DIAMOND_*`常量, `MAX_SOCKETS=3`, `SOCKET_WEIGHTS`, `PUNCH_COSTS`, `CalcGemStat()`(数据驱动, 通过overrides消除硬编码特判) |
| state/Equipment.lua | 橙装生成时 `rollInitialSockets()` 按权重随机0-3孔 (50%/39%/10%/1%) |
| GameState.lua | `gemBag`(宝石背包), `GemKey(t,q)`, `AddGem`, `GetGemCount`, `RemoveGem`, `SocketGem`, `UnsocketGem`, `SynthesizeGem`(3→1), `PunchSocket`(消耗棱镜), `GetGemStats(item)` |
| state/StatCalc.lua | `equipSum`和`ItemPower`中调用`GetGemStats`累加宝石属性 |
| SlotSaveSystem.lua | Serialize/Deserialize 新增 `gemBag` 字段; 装备的gems/sockets作为table字段自动序列化 |
| ui/InventoryCompare.lua | 详情面板头部右侧显示孔位指示器; 宝石属性详情区; 镶嵌/拆卸/打孔按钮; `ShowGemSocketPanel`(选宝石镶嵌); `ShowGemUnsocketPanel`(拆卸宝石) |
| ui/InventoryPage.lua | 宝石背包卡片(gem_grid): 显示所有宝石+棱镜数量, 可点击合成 |

**数据结构**:
```
gemBag: { ["ruby:3"] = count, ... }     -- key = "typeId:qualityIdx"
item.sockets: number (0-3)              -- 孔位数量
item.gems: { [1]={type="ruby",quality=3}, [2]=nil, ... }  -- 稀疏数组
```

**宝石属性公式**: `base × gemMul × tierMul`，base复用Config.EQUIP_STATS; tierMul由装备IP通过Config.IPToTierMul(item.itemPower)桥接; 特殊计算通过GEM_TYPES.overrides声明式配置(钻石weapon: `{base="DIAMOND_ELEMDMG_BASE"}`, 钻石jewelry: `{baseStat="fireRes", discount="DIAMOND_ALLRES_DISCOUNT"}`), CalcGemStat无硬编码if-else

**7种宝石**: ruby(攻/血/火抗), sapphire(暴击/防/冰抗), emerald(爆伤/幸运/毒抗), topaz(技伤/速/奥抗), amethyst(反应伤/护盾/水抗), diamond(元素伤/血%/全抗), skull(吸血/回血/防)

**5级品质**: Chipped(碎裂,0.15), Normal(普通,0.25), Flawless(完美,0.40), Royal(皇家,0.60), Grand(宏伟,0.75)

---

## 云/网络功能

| 功能 | 文件 | API |
|------|------|-----|
| 排行榜 | Leaderboard.lua | lobby.GetScores() |
| 世界Boss | WorldBoss.lua | lobby.GetScores(), lobby.IncreaseScore() |
| 10槽云存档 | SlotSaveSystem.lua | clientCloud.BatchSet(), clientCloud.BatchGet() |
| 存档代理 | SaveSystem.lua | 转发至 SlotSaveSystem |
| ~~手动存档~~ | ~~ManualSave.lua~~ | 已废弃，被SlotSaveSystem取代 |

---

## 折光矿脉系统 (v1.15)

**文件**: ResourceDungeon.lua (逻辑) + ResourceDungeonPanel.lua (入口) + ResourceDungeonResult.lua (结算)

**设计**: 两段式掉落资源副本，60秒限时击杀

**两段式机制**:
- 前3次(丰厚奖励): 批量CalcRewards结算(宝石+棱镜, 按章节缩放品质和数量)
- 第4次+(额外探索): 无限次进入, 每次击杀概率掉落碎裂宝石(小怪1%, 精英10%), 无批量奖励

**配置分离**: ResourceDungeonConfig.lua (纯数据) ← ResourceDungeon.lua (逻辑读取)

**关键常量**: `MAX_DAILY=3`(丰厚奖励次数), `FIGHT_DURATION=60`, `SCALE_MUL=0.9`, `ELITE_HP_MUL=3.0`

**怪物阵容** (7普通+1精英, 31波出场序列):
- 先锋(#1-10): swarm碎晶虫 + glass折光蝠
- 主力(#11-20): bruiser矿脉卫兵 + debuffer辉石蛞蝓 + caster晶能术士 + exploder爆晶虫, #16=ELITE折光领主
- 精锐(#21-31): 全类型混合, 含tank岩晶巨兽
- 抗性: resistRule="theme"跟随章节元素, 或固定模板(balanced/all_low/phys_armor)
- 能力标签: 按maxChapter解锁(packBonus/defPierce/hpRegen/healAura等)

**数据流**:
```
ChallengePanel(折光矿脉Tab) → ResourceDungeonPanel(进入) → ResourceDungeon.EnterFight()
  → BattleSystem.Init (复用bossTimer机制, 立即启动计时)
  → Spawner.BuildQueue (ResourceDungeon.BuildMineQueue → MonsterTemplates.Assemble)
  → StageManager.OnEnemyKilled (ResourceDungeon.OnKill: 前3次仅计数, 第4次+概率掉落碎裂宝石)
  → 超时/死亡 → ResourceDungeon.EndFight() (前3次CalcRewards, 第4次+用_combatDrops) → BattleSystem.resourceDungeonEnded
  → main.lua检测 → ResourceDungeonResult.Show(fightResult)
  → 再次挑战/返回 → ResourceDungeon.ExitToMain() → BattleSystem.Init
```

**奖励公式** (CalcRewards):
- 宝石: 总数=ceil(kills×0.5), 精英击杀+2; 品质由随机+章节倾斜决定(完美/普通/碎裂); 类型从7种宝石随机
- 棱镜: floor(kills/10) + 精英击杀时+1

**存档**: GameState.resourceDungeon `{attemptsToday, lastDate, totalRuns}` → SlotSaveSystem misc分片

**战斗集成**: 模式检测优先级 WorldBoss → ResourceDungeon → EndlessTrial → 章节

---

## 已知待办 / 技术债

- [x] OfflineChest.lua: 已接入FormatNumber+游戏图标; v1.12重构离线收益算法(最高通关关卡/橙装≤10/魂晶章节缩放)
- [x] BuffManager.lua: 已拆分为调度入口(~120行) + buffs/NewSets.lua + buffs/T13Sets.lua (OldSets1/OldSets2已删除, 22个单章套装彻底移除)
- [x] GameMode适配器: 消除battle/→mode 24处if/elseif硬编码, Spawner/StageManager/BattleSystem/main.lua统一走GameMode调度
- [x] EventBus.lua: 轻量事件总线, 为后续跨层解耦准备
- [x] battle→UI反向依赖: Loot.lua中Toast引用已通过EventBus解耦(Emit→main.lua监听)
- [x] BuffRuntime提取: 从GameState(~176行)/Combat(~298行)/BuffManager(~44行)提取至state/BuffRuntime.lua(~420行), Install模式零API变更
- [ ] StageConfig.lua: 2887行，需拆分(已删120行scaleMul，M()/关卡工厂评估后跳过)
- [ ] 未来章节(~ch25+): 考虑引入 BigNum 替代 float64
- [x] 新套装效果的BuffManager实现: NewSets.lua(Ch9-12: swift_hunter/fission_force/shadow_hunter/iron_bastion/dragon_fury/rune_weaver), T13Sets.lua(Ch13: lava_conqueror/permafrost_heart)
- [x] StatModifiers注册系统(P0): StatCalc 3个Get*函数(ATK/AtkSpeed/CritRate)硬编码if-timer→SM.Apply, StatCalc注册3条永久修饰器, BuffRuntime注册12条条件修饰器, SlotSaveSystem allocatedPoints走StatDefs循环
- [x] D4怪物家族系统v2.0: WorldTierConfig+DynamicLevel+DefenseFormula+SpireTrial新模块; AbyssConfig/AbyssMode重写接入DynamicLevel; DamageFormula/StatCalc/Combat/Spawner/EnemySystem全部接入新模块; scaleMul在深渊/尖塔模式已废弃
- [ ] BossSkillTemplates.lua DamagePlayer调用(P1): 7处通过_hitPlayer调用DamagePlayer未传monsterLevel, 当前fallback到GameState.player.level(Boss等级≈玩家等级, 数值偏差可接受)
- [ ] SpireTrial UI面板: 尖塔试炼模块逻辑已完成, 缺少入口UI面板(类似EndlessTrialPanel)
- [ ] GameState.worldTier: 当前通过GameState.spireTrial.worldTier间接获取, 未来需要提升为顶层状态字段

---

## 文档目录

```
docs/
├── 章节设计规范.md / 章节实现规范.md   # 通用规范
├── 第四~十二章设计文档.md              # 各章设计
├── 章节设计/                           # Boss设计模板化体系
│   ├── Boss技能模板库.md               #   5大类15个可复用技能模板 + AI威胁通知系统 + 组装规范
│   ├── 第十三章Boss设计.md             #   基于模板库的第13章Boss设计(v2): 格拉西恩2阶段+尼弗海姆3阶段+反应护盾
│   ├── 第十四章Boss设计.md             #   第14章Boss设计(v1): 维诺莎2阶段(蚀毒叠层)+涅克洛斯3阶段(腐蚀+防御衰减+焚净护盾)
│   └── 第十五章Boss设计.md             #   第15章Boss设计(v1): 伊格尼斯2阶段(灼烧叠层+焰核)+萨拉曼德3阶段(焚灼+攻速衰减+淬灭护盾)
├── 技能与元素系统重构设计文档.md        # 技能系统(54KB)
├── equipment-*-analysis.md            # 装备系统分析
├── stat-system-analysis.md            # 属性计算分析
├── skill-*-analysis.md                # 技能系统分析
├── attribute-analysis.md              # 属性系统分析
├── skill-system-complete.md           # 完整技能系统文档(v1.8)
├── equipment-new-stats-plan.md        # hpPct+skillCdReduce方案
├── equipment-set-redesign.md          # 套装重构设计(3批×6套)
├── damage-scaling-redesign.md         # 对数缩放+HP成长分析
├── 数值/
│   ├── 经验与等级公式.md               # 经验v2: 手动曲线lv1-9 + 指数lv10+
│   ├── 掉落与经济公式.md               # 掉落v2: 5模板(common/elite/miniboss/boss/summon) + 金币缩放^0.3
│   ├── 技能伤害公式汇总.md             # 技能v3: 全60节点参数, 六区管线, DPS缩放结构(skillDmg独立乘区/CDR渐近线递减/新增精通属性), 缩放风险标注
│   ├── 怪物模板系统.md                 # 怪物模板v1.5: 7行为模板+12抗性模板+16能力标签+12章节主题+Boss锚点+分配矩阵
│   ├── 数值锚定与战力曲线.md            # v3: 极限DPS精算(分裂弹流)、scaleMul校准(PLAYER_POWER_MUL查表)、怪物DEF缩放、附录参考表
│   ├── 无尽试炼设计.md                 # v1: 试炼scaleMul锚定玩家章节、MonsterTemplates接入、抗性/行为轮换、逐层一次性经验、clearedFloor/maxFloor分离、排行榜v3
│   ├── 宝石镶嵌系统.md                 # v1: 7宝石×5品质×3装备类别, 镶嵌/拆卸/合成/打孔, 属性公式base×gemMul×tierMul
│   ├── 折光矿脉怪物设计.md             # v1: 三梯队出场序列(先锋/主力/精锐), 7普通+1精英, 章节抗性映射, 能力标签解锁
│   └── 怪物家族系统设计.md             # v3: 第九~十三章(世界层级/动态等级/护甲抗性/种族属性/尖塔试炼/深渊重写), D4参考文档
```

---

## Boss 技能模板系统 (v1.9.0)

**文件**: ThreatSystem.lua + BossSkillTemplates.lua + DrawBossTemplates.lua

**适用范围**: 第13章+ Boss（有 `phases` 字段），第1-12章 Boss 使用旧扁平技能字段不受影响

**路由机制**: EnemySystem.UpdateEnemyAbilities 中 `if e.phases then goto continue_abilities end` 跳过旧技能逻辑

**三层架构**:
```
模板层 (BossSkillTemplates)     → 行为逻辑, 元素无关
  ↓ 参数层 (StageConfig phases) → 数值配置, 章节特调
  ↓ 渲染层 (DrawBossTemplates)  → NanoVG 程序化视觉
```

**15个模板**: ATK_barrage/breath/pulse/spikes/detonate, DEF_armor/crystal/shield/regen, CTL_field/barrier/decay/vortex, SUM_minion/guard, PHASE_transition

**关键数据流**:
- Boss 生成 → Spawner 透传 `phases` → BossSkillTemplates.Update 自动初始化 `_phaseIdx`
- 配置桥接: `flattenSkillCfg(skill)` 将 StageConfig 的 `{ template, params }` 展平为模板期望的 flat cfg，处理字段重命名(template→templateId, effect→onTick, coreEffect→onCoreTick, shield_reaction→shieldReaction等)
- 效果统一调用: `invokeOrApplyEffect(handler, bs, source)` 同时支持函数回调和效果描述表(如 `{ slow=0.10, slowDuration=1.5 }`)，自动映射到 GameState.ApplySlowDebuff 等
- 阶段转换: HP 低于 triggerHp → 无敌 + 演出 → 切换技能组（支持3种触发格式: trigger.value / transition.hpThreshold / nextPhase.hpThreshold）
- 可摧毁物(crystal/shield/detonateTarget): 作为 `isBossDestroyable=true` 的敌人插入 bs.enemies
- 威胁通知: 技能注册 dangerZone/priorityTarget/pull 到 ThreatSystem → PlayerAI 读取并影响移动+目标选择
- CombatCore: `_invincible` 检查 + `isBossDestroyable` 委托分支

**第13章Boss**:
- 格拉西恩 (boss_frost_lord): 2阶段, HP=1.7M, ATK_barrage+spikes+SUM → CTL_field+DEF_armor+crystal
- 尼弗海姆 (boss_ice_sovereign): 3阶段, HP=3.9M, ATK_breath+pulse+SUM → CTL_field+barrier+decay+DEF_shield(反应护盾) → DEF_armor+regen+CTL_vortex+ATK_detonate

**第14章Boss**:
- 维诺莎 (boss_venom_mother): 2阶段, HP=2.05M, ATK_barrage(蚀毒叠层)+spikes(lingerOnTick毒池)+SUM_minion → ATK_barrage(360°)+CTL_field(回复压制)+DEF_armor+DEF_crystal(毒腺图腾,DoT倍率)
- 涅克洛斯 (boss_plague_sovereign): 3阶段, HP=4.7M, ATK_breath(腐蚀叠层)+spikes(毒沼)+SUM_guard(腐蚀光环) → ATK_breath+CTL_decay(stat=def)+CTL_barrier+CTL_field+DEF_shield(焚净反应,bossBuff惩罚) → DEF_armor+DEF_regen+CTL_vortex(腐蚀核心)+ATK_detonate(禁回复+毒伤)

**第15章Boss**:
- 伊格尼斯 (boss_flame_lord): 2阶段, HP=2.46M, ATK_barrage(灼烧叠层)+spikes(熔岩池叠灼烧)+SUM_minion(flame_imp) → ATK_barrage(360°)+CTL_field(灼烧+回复压制)+DEF_armor+DEF_crystal(焰核,Boss增攻,摧毁清3层灼烧)
- 萨拉曼德 (boss_inferno_sovereign): 3阶段, HP=5.64M, ATK_breath(焚灼叠层)+spikes(熔岩池+回复压制)+SUM_guard(焚灼光环) → ATK_breath+CTL_decay(stat=atkSpeed)+CTL_barrier(火墙叠焚灼)+CTL_field+DEF_shield(淬灭反应quench,水×2.8,爆炸惩罚) → DEF_armor+DEF_regen+CTL_vortex(焚灼核心+额外减攻速)+ATK_detonate(焚天风暴+5层焚灼)

**第15章Debuff系统** (新增):
- 灼烧(Blaze): Combat.lua ApplyBlazeDebuff — DoT(%BossATK/s×层数) + 攻速降低(3%/层), max8层, 5s, StatCalc.GetAtkSpeed接入, 攻速下限0.15
- 焚灼(Scorch): Combat.lua ApplyScorchDebuff — 受伤增幅(3%/层), max10层, 8s, DamagePlayer中berserk后DEF前乘算
- Spawner.lua: 新增 burnStack/scorchOnHit/burnAura/damageReflect 字段传递
- EnemySystem.lua: ApplyBurnStack/ApplyScorchOnHit/UpdateBurnAura + 召唤/分裂字段透传
- 三章decay对比: Ch13=moveSpeed(跑不动), Ch14=def(扛不住), Ch15=atkSpeed(打不动)

---

*最后更新: 2026-04-05*
*维护者: AI 自动维护*
