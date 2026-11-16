# 时间胶囊 TimeCapsule

> 把话锁进时间里。

鸿蒙原生应用「时间胶囊」的完整实现与设计仓库。写完之后**真正封存**，不到约定那一天，连自己都打不开。

本仓库当前阶段：**阶段六 已完成**（六阶段全部落地：数据持久化、图片音频、到期提醒、备份导出、桌面卡片全部接通，并在 HarmonyOS 7.0.0 / API 26 模拟器上端到端跑通、逐页验收）。

功能一览：

- **真封存**：封存后进「封存中」，详情页不存在任何渲染内容的代码分支，界面上没有任何通往内容的路径
- **三种内容**：文字（直接编辑）、图片（相册多选，复制进沙箱）、语音（AVRecorder 录音，详情页内嵌播放）
- **到期提醒**：系统级日历提醒 + 打开应用时比对 + 页面停留时每 30 秒翻页，三条腿
- **备份迁移**：导出 `zip`（`capsules.json` + 媒体文件）到「我的手机」，可从 zip 整库恢复
- **桌面卡片**：2×2 / 2×4 / 4×4，显示最近的约定与剩余天数，点击直达应用

---

## 快速开始

环境：DevEco Studio 26.0.0.821（内置 hvigor 6.26.4、JBR、API 26 SDK）。

```bash
build.cmd            # 编译，产物 entry/build/default/outputs/default/entry-default-unsigned.hap
build.cmd clean      # 先清理再编译
```

工程也可以直接用 DevEco Studio 打开根目录运行。

> **本机踩坑记录**：hvigor / ohpm / java 都不在 PATH 上，且
> `libimage_transcoder_shared.dll` 依赖的 `libcjson`、`libhilog`、`libskia_canvaskit`
> 分散在 `openharmony\previewer\common\bin` 等其他目录。直接调用 hvigor 会在
> 资源编译阶段报 `An Application Control policy has blocked this file`
> （Windows 错误 4551 实际是"找不到依赖库"，不是被策略拦截）。
> `build.cmd` 已经把这些目录拼进 PATH，绕开这个问题。

---

## 一句话说清这个产品

系统备忘录给的是一份**随时可翻的记录**，时间胶囊给的是一段**距离**。

它不是"更漂亮的备忘录"——那样做完就输给系统备忘录了。它补的是**时间**这一层：内容被封存后，界面上不存在任何通往它的路径，直到到期那天由通知或桌面卡片把用户带回来。

---

## 目录结构

```
time-capsule/
├── AppScope/                   应用级配置与图标（分层图标 background/foreground）
├── entry/                      entry 模块
│   └── src/main/
│       ├── ets/
│       │   ├── entryability/        EntryAbility.ets（初始化全局 context 与数据层）
│       │   ├── entrybackupability/  EntryBackupAbility.ets
│       │   ├── common/              Tokens 设计令牌、TimeUtil、Constants、AppCtx
│       │   ├── model/               Capsule.ets 数据模型与状态枚举
│       │   ├── data/                CapsuleRepo（RDB 两表）、SettingsRepo（preferences）
│       │   │                        MediaRepo（图片导入/导出）、AudioService（录音与回放）
│       │   │                        ReminderService（系统提醒）、BackupService（zip 备份）
│       │   │                        PermService、CardData、FormRegistry
│       │   ├── view/                CommonViews.ets（NavBar/PrimaryButton）、CapsuleCard.ets
│       │   ├── form/                CapsuleCardAbility.ets（FormExtensionAbility）
│       │   ├── capsule_card/pages/  CapsuleCard.ets（桌面卡片 UI）
│       │   └── pages/               Index.ets（根 + Navigation + 封存弹层）
│       │                            HomePage / EditorPage / DetailPage / MinePage / BackupPage
│       └── resources/           color/string/float 资源 + main_pages + backup_config + form_config
├── build-profile.json5         构建配置（compatibleSdkVersion 26.0.0）
├── hvigor/hvigor-config.json5  modelVersion 26.0.0
├── build.cmd                   离线编译入口（已处理 PATH 依赖）
├── make_icon.py                图标生成（Pillow）
├── prototypes/                 页面原型（537×1163 PNG，逻辑尺寸 375×812）
│   ├── 01.png               首页 · 胶囊架
│   ├── 02.png               首页 · 空状态
│   ├── 03.png               约定时间 · 初始
│   ├── 04.png               约定时间 · 编辑中
│   ├── 05.png               封存确认
│   ├── 06.png               胶囊详情 · 封存中
│   ├── 07.png               胶囊详情 · 已开启
│   ├── 08.png               我的
│   ├── 09.png               通知与卡片设置
│   ├── 10.png               备份与导出
│   ├── 11.png               关于
│   ├── 12.png               通知授权引导
│   ├── 13.png               到期通知（系统通知）
│   ├── 14.png               桌面服务卡片
│   ├── overview.png         14 图总览
│   └── index.html           原型索引页（双击打开）
├── doc_media/               立项书内嵌配图
├── render_proto.py          原型渲染脚本（Pillow 绘制）
├── make_overview.py         生成 overview.png
└── make_index.py            生成 index.html
```

---

## 页面架构

```
时间胶囊
├─ 首页 · 胶囊架
│   ├─ 待开启 ──进详情──→ 胶囊详情 · 封存中（内容遮蔽）
│   ├─ 已开启 ──进详情──→ 胶囊详情 · 已开启
│   └─ 草稿   ──进详情──→ 约定时间（继续编辑）
├─ 约定时间 ──封存──→ 封存确认（底部弹层）──→ 回到首页
├─ 我的
│   ├─ 通知与卡片
│   ├─ 备份与导出
│   └─ 关于
│
└─ 外部入口：到期通知 / 桌面服务卡片 ──→ 胶囊详情 · 已开启（直达）
```

> 立项书结构图把「待开启」指向了「详情 · 已开启」，且「已封存」与「待开启」语义重叠。
> 工程实现按修正后的三态走：**待开启 / 已开启 / 草稿**——「待开启」进「封存中」，
> 草稿回到编辑器，「已封存」并入「待开启」。

**两条关键路径的步数**

| 路径 | 步数 |
|---|---|
| 封一个胶囊 | 首页 → 约定时间 → 封存确认，**3 步** |
| 打开到期胶囊 | 通知 → 详情，**2 步**（绕开首页） |

---

## 需求与功能映射

| 编号 | 内容 | 优先级 | 落点 |
|---|---|---|---|
| R1 | 真封存：封存后不可改、不可提前开 | 高 | 05 封存确认 / 06 封存中 |
| R2 | 到期提醒：到点主动来找用户 | 高 | 12 引导 / 13 通知 / 14 卡片 |
| R3 | 多形态内容：文字 + 图片 + 语音 | 高 | 03 / 04 |
| R4 | 集中管理：分组标签 + 卡片列表 | 中 | 01 / 02 |
| R5 | 备份迁移 | 中 | 10 |

| 编号 | 功能 | 定位 |
|---|---|---|
| F1 | 胶囊封存 | 核心 |
| F2 | 到期提醒 | 核心 |
| F3 | 多形态内容 | 核心 |
| F4 | 胶囊架 | 重要 |
| F5 | 备份导出 | 扩展 |

**明确不做**：社交、社区、广场、排行榜——会让一个安静的产品变吵。

---

## 设计令牌

| 用途 | 值 |
|---|---|
| 背景 | `#F5F1EA` |
| 主文字 | `#1E2420` |
| 次级文字 | `#454B47` |
| 弱文字 | `#8C8A82` |
| 更弱文字 | `#B4B0A5` |
| 主色 | `#2C5F55` |
| 主色浅底 | `#E6F0EC` |
| 分隔线 | `#E8E2D6` |
| 卡片 | `#FFFFFF` |
| 暖色底（到期） | `#FDF6E8` |
| 暖色描边 | `#EAD9B4` |
| 暖色文字 | `#A8742A` |

字体：PingFang SC / 微软雅黑。

---

## 原型生成

原型由 `render_proto.py` 用 Pillow 直接绘制，逻辑坐标 375×812，2× 超采样后缩放到 537×1163。

```bash
# 依赖：Python 3 + Pillow
python render_proto.py            # 重绘全部 14 帧
python render_proto.py 05 03      # 只重绘指定帧
python make_overview.py           # 生成总览图
python make_index.py              # 生成索引页 index.html
```

---

## 数据与实现

### 存储

两张表，一对多（立项书要求）：

```sql
capsule(id, title, status, createdAt, openAt, openedAt, notified, reminderId)
block(id, capsuleId, type, text, uris, audioUri, duration, sortOrder)
```

`securityLevel: S2`，落在应用沙箱 `rdb/timecapsule.db`。图片与录音**复制进沙箱**（`files/media/`）而不是只存 picker 授权 uri——picker 的授权在清缓存或换设备后会失效，封存五年的胶囊不能冒这个险。

### 到期判定的三条腿

| 场景 | 机制 |
|---|---|
| 应用不在前台 | `reminderAgentManager` 日历提醒（系统闹钟级） |
| 应用被打开 | 启动时比对 `openAt`，到期的立刻转暖色卡并补前台通知 |
| 应用停在这一页 | 根页面每 30 秒推一次 `nowMs`，卡片与副标题自动翻页 |

三条腿都指向同一个 `TimeUtil`，避免三处各算一套导致显示不一致。

### 备份格式

zip 内含 `capsules.json` + `media/`。`formatVersion: 1`，恢复时**整库替换**，媒体按内容重新落盘并重写 uri。用 `zlib.compressFile / decompressFile`（`zipFile` 已废弃）。

---

## 技术难点（已实测验证）

1. **到期判定准确性** —— 已按上表三条腿实现。注意 `daysLeft` 用向上取整、`daysWaited` 用向下取整，否则「刚封存」会显示「已等待 1 天」。
2. **通知送达** —— `PUBLISH_AGENT_REMINDER` 是 system_grant，不弹窗；但 reminderAgent 还要求 `reminder_capability` 云能力校验通过 + 应用已签名。
3. **"真的打不开"** —— 第一版是**界面层不可达**：封存中的胶囊详情不含任何内容渲染分支，数据仍在沙箱内。加密方案待评估。
4. **AVPlayer / AVRecorder** —— 沙箱内录制必须用 `url: 'fd://' + file.fd`（写路径会失败）；播放用 `fdSrc = {fd, offset, length}`。
5. **图片显示** —— `Image()` 拿到裸沙箱路径**不报错但空白**，必须补 `file://` scheme（`MediaRepo.toDisplayUri`）。
6. **卡片与主应用同步** —— `formProvider.updateForm` 推送数据；卡片页必须用 `@LocalStorageProp` 接收，普通 `@State` 收不到。
7. **ArkUI 刷新模型**（最耗时的一类坑）—— 普通成员、`@Builder` 值参数、`@Link` 的深层数组改动**都不会触发刷新**。需要 `@Prop` 或整体替换数组。

---

## 开发计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| 一 | 立项与设计（需求、竞品、页面结构、原型） | ✅ 已完成 |
| 二 | 静态界面（工程骨架 + 五页静态布局） | ✅ 已完成 |
| 三 | 导航与状态（Tab + Navigation，三态打通） | ✅ 已完成 |
| 四 | 数据与业务（RDB 两表、内容块、到期计算、图片音频） | ✅ 已完成 |
| 五 | 通知、卡片、备份 | ✅ 已完成（模拟器已验证，真机签名后需复测提醒） |
| 六 | 测试与优化 | ✅ 已完成（换 API 26 模拟器复测，修 6 处交互与状态缺陷） |

---

## ArkUI 组件映射

| 页面 | 主要组件 | 实现状态 |
|---|---|---|
| 首页胶囊架 | `Tabs` 底部导航、手写分组标签、`List`/`ForEach`、`CapsuleCard` | ✅ 接通 RDB |
| 约定时间 | `TextInput`/`TextArea`、`showDatePickerDialog`/`showTimePickerDialog`、图片块、录音块 | ✅ 全通 |
| 封存确认 | `Stack` 遮罩 + `TransitionEffect.translate` 底部弹层 | ✅ 已实现（不用 `bindSheet`，见下） |
| 详情 · 封存中 | 锁形虚线卡 `dashed`、自绘进度条 | ✅ 已实现 |
| 详情 · 已开启 | `Image` 真实渲染、`AudioService` 内嵌播放、删除入口 | ✅ 已实现 |
| 我的 | `Toggle`、自定义行 | ✅ 已实现 |
| 备份与导出 | `StatCell` 统计、`DocumentViewPicker` 导出、`DocumentSelectPicker` 恢复 | ✅ 已实现 |
| 桌面卡片 | `FormExtensionAbility` + ArkTS 卡片 + `formProvider` | ✅ 已实现 |
| 到期通知 | `reminderAgentManager` + `notificationManager` | ✅ 代码就绪，模拟器受云能力限制 |

> **封存弹层的实现选择**：原本用 `bindSheet` 挂在 `Navigation` 上，压栈的 `NavDestination` 会盖住弹层 overlay，点了没反应。改为在根 `Stack` 里手写遮罩 + `TransitionEffect.translate`，行为可控且不依赖导航栈层级。

### 模拟器环境说明

当前验证环境为 **HarmonyOS 7.0.0 (API 26)** 模拟器（Mate 90 Pro），因此 `compatibleSdkVersion` 与 `targetSdkVersion` 都写 `"26.0.0"`。

版本号格式有硬约束：API ≥ 26 用 `"26.0.0"` 这种纯平台版本，API 10–25 必须带括号写 `"6.1.0(23)"`，写成裸 `"23"` 会被 hvigor 以 `00306042 Specification Limit Violation` 拒绝。

**已知环境限制**：模拟器上 `reminderAgentManager.publishReminder` 会因 `reminder_capability` 云能力校验失败而拒绝（`VerifyCloudCapability failed`），且未签名 HAP 无证书。这是环境限制而非代码缺陷，真机签名后可用。

降级路径已实现并验证：应用打开时比对时间自动把过期胶囊标成到期 + 桌面卡片显示倒计时。**这类降级不能悄悄发生**——「我的」页在排程失败时会显示「系统提醒没有排上，到时间不会自动弹通知 / 打开应用时会自动标成到期」，封存时的提示也会如实说明，避免用户以为设了提醒而实际没有。

---

## 团队

- 张恒毅 —— 产品设计、交互、页面实现、文档
- 刘裕钿 —— 本地存储、图片音频、到期通知、桌面卡片
