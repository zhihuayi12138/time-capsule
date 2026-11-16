# 时间胶囊 TimeCapsule

> 把话锁进时间里。

鸿蒙原生应用「时间胶囊」的产品设计与高保真原型仓库。写完之后**真正封存**，不到约定那一天，连自己都打不开。

本仓库当前阶段：**阶段二 静态界面**（页面原型已完成，HarmonyOS 工程骨架已可编译出 HAP，业务逻辑待实现）。

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
│       │   ├── entryability/        EntryAbility.ets
│       │   ├── entrybackupability/  EntryBackupAbility.ets
│       │   ├── common/              Tokens.ets 设计令牌、TimeUtil.ets、Constants.ets
│       │   ├── model/               Capsule.ets 数据模型与状态枚举
│       │   ├── view/                CommonViews.ets（NavBar/PrimaryButton）、CapsuleCard.ets
│       │   └── pages/               Index.ets（根 + Navigation + 封存弹层）
│       │                            HomePage / EditorPage / DetailPage / MinePage / BackupPage
│       └── resources/           color/string/float 资源 + main_pages + backup_config
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
├─ 约定时间 ──封存──→ 封存确认（bindSheet）──→ 回到首页
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

## 技术难点（开发阶段需优先验证）

1. **到期判定准确性** —— 不能只靠"打开 App 时比对时间"，需在启动、回前台、卡片刷新三处统一校准。
2. **通知送达** —— 单点失败风险。通知权限被拒时，桌面服务卡片是兜底通路（见 09 / 12）。
3. **"真的打不开"** —— 第一版只做到**界面层不可达**，数据仍在应用沙盒内；加密方案待评估。
4. **AVPlayer 音频** —— 录音与回放，详情页内嵌进度条不跳页。
5. **数据模型** —— 胶囊 + 内容块两张表，一对多。
6. **卡片与主应用同步** —— FormComponent 倒计时需与主应用一致。

---

## 开发计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| 一 | 立项与设计（需求、竞品、页面结构、原型） | ✅ 已完成 |
| 二 | 静态界面（工程骨架 + 五页静态布局） | ✅ 已完成 |
| 三 | 导航与状态（草稿 / 待开启 / 已开启三态打通） | 进行中 |
| 四 | 数据与业务（RDB 两表、内容块、到期计算） | 待开始 |
| 五 | 通知、卡片、备份 | 待开始 |
| 六 | 测试与优化 | 待开始 |

---

## ArkUI 组件映射

| 页面 | 主要组件 | 实现状态 |
|---|---|---|
| 首页胶囊架 | `Tabs` 手写分组标签、`List`、`ForEach`、`@Builder` | ✅ 已实现 |
| 约定时间 | `TextInput`、`Scroll`、`@Builder`、键盘避让 | ✅ 已实现（图片/音频待接） |
| 封存确认 | `bindSheet` + 自定义内容 | ✅ 已实现 |
| 详情 · 封存中 | `Text`、自绘进度条 | ✅ 已实现 |
| 详情 · 已开启 | `ForEach`、`Image`（占位）、内嵌音频条 | ⚠️ 音频待接 AVPlayer |
| 我的 | `Toggle`、自定义行 | ✅ 已实现 |
| 备份与导出 | 统计栏、操作卡 | ✅ 静态 |
| 桌面卡片 | ArkTS 卡片 + `FormExtensionAbility` | ❌ 未开始 |

**当前为纯静态骨架**：`Index.ets` 里的胶囊列表是空数组，数据层（RDB / Preferences）
与通知、卡片均未接入。页面间导航与状态流转已打通，可运行查看。

---

## 团队

- 张恒毅 —— 产品设计、交互、页面实现、文档
- 刘裕钿 —— 本地存储、图片音频、到期通知、桌面卡片
