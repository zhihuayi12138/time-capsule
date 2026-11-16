import { Color, Font, Size } from '../common/Tokens';
import { BlockType, Capsule, CapsuleStatus } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { Routes } from '../common/Constants';
import { HomePage } from './HomePage';
import { EditorPage } from './EditorPage';
import { DetailPage } from './DetailPage';
import { MinePage } from './MinePage';
import { BackupPage, AboutPage } from './BackupPage';
import { PrimaryButton } from '../view/CommonViews';

/**
 * 根页面。
 *
 * 结构：Navigation（承载全部二级页） → Tabs（底部两个主入口：胶囊架 / 我的）。
 * 一级页面用 Tabs 平级切换，二级页面（约定时间、胶囊详情、备份与导出、关于）
 * 用 NavPathStack 压栈；压栈后的页面覆盖整屏，包括底部 Tab 栏。
 */
@Entry
@Component
struct Index {
  @State capsules: Capsule[] = Index.demoCapsules();
  @State current: Capsule = Index.emptyCapsule();
  @State notifyEnabled: boolean = true;
  @State lastBackupAt: number = 0;
  @State showSealSheet: boolean = false;
  @State activeTab: number = 0;

  private stack: NavPathStack = new NavPathStack();

  static emptyCapsule(): Capsule {
    return {
      id: '',
      title: '',
      status: CapsuleStatus.Draft,
      createdAt: Date.now(),
      openAt: Date.now() + 30 * TimeUtil.DAY,
      blocks: [],
      notified: false
    };
  }

  /**
   * 演示数据：仅用于让页面在模拟器上立刻有内容可看。
   * 接入数据层（RDB）后整段删除，改由数据仓库提供。
   */
  static demoCapsules(): Capsule[] {
    const now = Date.now();
    const day = TimeUtil.DAY;
    return [
      {
        id: 'cap_due',
        title: '给三年后的自己',
        status: CapsuleStatus.Pending,
        createdAt: now - 300 * day,
        openAt: now - 2 * 60 * 60 * 1000,
        blocks: [{ id: 'b1', type: BlockType.Text, text: '不知道你现在在哪儿。', order: 0 }],
        notified: false
      },
      {
        id: 'cap_87',
        title: '毕业那天的下午',
        status: CapsuleStatus.Pending,
        createdAt: now - 45 * day,
        openAt: now + 87 * day,
        blocks: [
          { id: 'b2', type: BlockType.Text, text: '今天答辩结束了。', order: 0 },
          { id: 'b3', type: BlockType.Image, uris: ['a', 'b'], order: 1 }
        ],
        notified: false
      },
      {
        id: 'cap_180',
        title: '搬去新城市之前',
        status: CapsuleStatus.Pending,
        createdAt: now - 12 * day,
        openAt: now + 180 * day,
        blocks: [{ id: 'b4', type: BlockType.Audio, duration: 42, order: 0 }],
        notified: false
      },
      {
        id: 'cap_draft',
        title: '还没写完的一段话',
        status: CapsuleStatus.Draft,
        createdAt: now - 3 * day,
        openAt: now + 30 * day,
        blocks: [{ id: 'b5', type: BlockType.Text, text: '想写给……', order: 0 }],
        notified: false
      },
      {
        id: 'cap_open',
        title: '写给一年前开始学编程的自己',
        status: CapsuleStatus.Opened,
        createdAt: now - 365 * day,
        openAt: now - 3 * day,
        openedAt: now - 3 * day,
        blocks: [
          { id: 'b6', type: BlockType.Text, text: '如果一年后你还在写代码，就把这段读一遍。', order: 0 },
          { id: 'b7', type: BlockType.Image, uris: ['c', 'd'], order: 1 },
          { id: 'b8', type: BlockType.Audio, duration: 68, order: 2 }
        ],
        notified: true
      }
    ];
  }

  private startNew(): void {
    this.current = Index.emptyCapsule();
    this.stack.pushPathByName(Routes.EDITOR, null);
  }

  private openCapsule(c: Capsule): void {
    this.current = c;
    // 草稿还没封存，点击直接回到编辑器继续写
    if (c.status === CapsuleStatus.Draft) {
      this.stack.pushPathByName(Routes.EDITOR, null);
      return;
    }
    // 到期的待开启胶囊：第一次打开即转为已开启
    if (c.status === CapsuleStatus.Pending && TimeUtil.isDue(c.openAt)) {
      c.status = CapsuleStatus.Opened;
      c.openedAt = Date.now();
      const idx = this.capsules.findIndex((x: Capsule) => x.id === c.id);
      if (idx >= 0) {
        this.capsules[idx] = c;
      }
    }
    this.stack.pushPathByName(Routes.DETAIL, null);
  }

  private confirmSeal(): void {
    this.current.status = CapsuleStatus.Pending;
    const idx = this.capsules.findIndex((c: Capsule) => c.id === this.current.id);
    if (this.current.id.length === 0) {
      this.current.id = `cap_${Date.now()}`;
      this.capsules.push(this.current);
    } else if (idx >= 0) {
      this.capsules[idx] = this.current;
    }
    this.showSealSheet = false;
    this.stack.pop();
    this.activeTab = 0;
  }

  private openedCount(): number {
    return this.capsules.filter((c: Capsule) => c.status === CapsuleStatus.Opened).length;
  }

  // ---------------- 底部 Tab ----------------

  @Builder
  capsuleIcon(active: boolean) {
    Stack() {
      Row()
        .width(15)
        .height(20)
        .borderRadius(7.5)
        .border({ width: 1.6, color: active ? Color.green : Color.muted2 })
      Row()
        .width(15)
        .height(1.6)
        .backgroundColor(active ? Color.green : Color.muted2)
    }
    .width(22)
    .height(22)
  }

  @Builder
  personIcon(active: boolean) {
    Column() {
      Circle()
        .width(7)
        .height(7)
        .fill(active ? Color.green : Color.muted2)
      Row()
        .width(14)
        .height(7)
        .borderRadius({ topLeft: 7, topRight: 7 })
        .backgroundColor(active ? Color.green : Color.muted2)
        .margin({ top: 2 })
    }
    .width(22)
    .height(22)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * 底部单个 Tab。
   * 注意：@Builder 按值传参不会随状态变化重建，所以这里不传 active，
   * 而是直接在属性里读 this.activeTab，才能跟着选中态刷新。
   */
  @Builder
  tabItem(index: number, label: string) {
    Column() {
      if (index === 0) {
        Stack() {
          Row()
            .width(15)
            .height(20)
            .borderRadius(7.5)
            .border({ width: 1.6, color: this.activeTab === index ? Color.green : Color.muted2 })
          Row()
            .width(15)
            .height(1.6)
            .backgroundColor(this.activeTab === index ? Color.green : Color.muted2)
        }
        .width(22)
        .height(22)
      } else {
        Column() {
          Circle()
            .width(7)
            .height(7)
            .fill(this.activeTab === index ? Color.green : Color.muted2)
          Row()
            .width(14)
            .height(7)
            .borderRadius({ topLeft: 7, topRight: 7 })
            .backgroundColor(this.activeTab === index ? Color.green : Color.muted2)
            .margin({ top: 2 })
        }
        .width(22)
        .height(22)
        .justifyContent(FlexAlign.Center)
      }

      Text(label)
        .fontSize(11)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? Color.green : Color.muted2)
        .margin({ top: 3 })
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
  }

  // ---------------- 封存确认弹层 ----------------

  @Builder
  sealSheet() {
    Column() {
      Row().width(36).height(4).backgroundColor(Color.dash).borderRadius(2).margin({ top: 10, bottom: 18 })

      Text('封存之后，就改不了了')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.ink)
        .width('100%')

      Column() {
        this.summaryRow('标题', this.current.title.length === 0 ? '未命名' : this.current.title)
        Divider().color(Color.line).strokeWidth(1)
        this.summaryRow('开启时间', TimeUtil.format(this.current.openAt))
        Divider().color(Color.line).strokeWidth(1)
        this.summaryRow('内容', `${this.current.blocks.length} 个内容块`)
      }
      .width('100%')
      .margin({ top: 14 })

      Row() {
        Text('封存后内容无法修改，也无法提前打开')
          .fontSize(Font.tiny)
          .fontColor(Color.warmInk)
          .lineHeight(18)
      }
      .width('100%')
      .padding(14)
      .backgroundColor(Color.warmBg)
      .borderRadius(12)
      .border({ width: 1, color: Color.warmLine })
      .margin({ top: 16 })

      Column() {
        PrimaryButton({ label: '确认封存', onTap: () => this.confirmSeal() })
      }
      .padding({ top: 20 })

      Text('再想想')
        .fontSize(Font.caption)
        .fontColor(Color.muted)
        .margin({ top: 16, bottom: 28 })
        .onClick(() => {
          this.showSealSheet = false;
        })
    }
    .width('100%')
    .padding({ left: Size.pageH, right: Size.pageH })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Color.bg)
    .borderRadius({ topLeft: 24, topRight: 24 })
  }

  @Builder
  summaryRow(k: string, v: string) {
    Row() {
      Text(k).fontSize(Font.caption).fontColor(Color.muted)
      Blank()
      Text(v).fontSize(Font.caption).fontColor(Color.ink2)
    }
    .width('100%')
    .height(44)
  }

  // ---------------- 二级页路由 ----------------

  /**
   * Navigation 的路由表。
   * 每个分支都必须包一层 NavDestination：它是 NavPathStack 里的一个"页面壳"，
   * 负责整屏铺满与返回手势。页面内部自带 NavBar，所以这里 hideTitleBar。
   */
  @Builder
  destination(name: string) {
    if (name === Routes.EDITOR) {
      NavDestination() {
        EditorPage({
          draft: this.current,
          onCancel: () => {
            this.stack.pop();
          },
          onRequestSeal: () => {
            this.showSealSheet = true;
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.bg)
    } else if (name === Routes.DETAIL) {
      NavDestination() {
        DetailPage({
          capsule: this.current,
          onBack: () => {
            this.stack.pop();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.bg)
    } else if (name === Routes.BACKUP) {
      NavDestination() {
        BackupPage({
          total: this.capsules.length,
          opened: this.openedCount(),
          bytes: 0,
          lastBackupAt: this.lastBackupAt,
          onBack: () => {
            this.stack.pop();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.bg)
    } else if (name === Routes.ABOUT) {
      NavDestination() {
        AboutPage({
          onBack: () => {
            this.stack.pop();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.bg)
    }
  }

  build() {
    Navigation(this.stack) {
      Tabs({ barPosition: BarPosition.End, index: this.activeTab }) {
        TabContent() {
          HomePage({
            capsules: this.capsules,
            onNewCapsule: () => this.startNew(),
            onOpenCapsule: (c: Capsule) => this.openCapsule(c)
          })
        }
        .tabBar(this.tabItem(0, '胶囊架'))

        TabContent() {
          MinePage({
            notifyEnabled: this.notifyEnabled,
            lastBackupAt: this.lastBackupAt,
            onOpenBackup: () => {
              this.stack.pushPathByName(Routes.BACKUP, null);
            },
            onOpenAbout: () => {
              this.stack.pushPathByName(Routes.ABOUT, null);
            }
          })
        }
        .tabBar(this.tabItem(1, '我的'))
      }
      .barMode(BarMode.Fixed)
      .barBackgroundColor(Color.bg)
      .divider({ strokeWidth: 1, color: Color.line })
      .scrollable(false)
      .animationDuration(0)
      .onChange((index: number) => {
        this.activeTab = index;
      })
      .width('100%')
      .height('100%')
    }
    .navDestination(this.destination)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
    .bindSheet(this.showSealSheet, this.sealSheet(), {
      height: 460,
      dragBar: false,
      backgroundColor: Color.bg,
      onDisappear: () => {
        this.showSealSheet = false;
      }
    })
  }
}
