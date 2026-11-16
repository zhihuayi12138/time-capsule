import { Color, Font, Size } from '../common/Tokens';
import { Capsule, CapsuleStatus, CapsuleTab } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { Routes } from '../common/Constants';
import { HomePage } from './HomePage';
import { EditorPage } from './EditorPage';
import { DetailPage } from './DetailPage';
import { MinePage } from './MinePage';
import { BackupPage, AboutPage } from './BackupPage';
import { NavBar, PrimaryButton } from '../view/CommonViews';

/**
 * 根页面：Navigation 承载「首页 → 编辑 → 详情」的主链路。
 * 封存确认用 bindSheet 底部弹层，压暗背景，与原型 05 一致。
 */
@Entry
@Component
struct Index {
  @State capsules: Capsule[] = [];
  @State current: Capsule = Index.emptyCapsule();
  @State notifyEnabled: boolean = true;
  @State showSealSheet: boolean = false;
  @State showMine: boolean = false;
  @State showBackup: boolean = false;
  @State showAbout: boolean = false;

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

  private startNew(): void {
    this.current = Index.emptyCapsule();
    this.showMine = false;
    this.showBackup = false;
    this.showAbout = false;
    this.stack.pushPathByName(Routes.EDITOR, null);
  }

  private openCapsule(c: Capsule): void {
    this.current = c;
    this.showMine = false;
    this.showBackup = false;
    this.showAbout = false;
    this.stack.pushPathByName(Routes.DETAIL, null);
  }

  private confirmSeal(): void {
    this.current.status = CapsuleStatus.Pending;
    this.current.openAt = this.current.openAt;
    const idx = this.capsules.findIndex((c: Capsule) => c.id === this.current.id);
    if (this.current.id.length === 0) {
      this.current.id = `cap_${Date.now()}`;
      this.capsules.push(this.current);
    } else if (idx >= 0) {
      this.capsules[idx] = this.current;
    }
    this.showSealSheet = false;
    this.stack.pop();
  }

  /** 封存确认弹层 */
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

  @Builder
  destination(name: string) {
    if (name === Routes.EDITOR) {
      EditorPage({
        draft: this.current,
        onCancel: () => this.stack.pop(),
        onRequestSeal: () => {
          this.showSealSheet = true;
        }
      })
    } else if (name === Routes.DETAIL) {
      DetailPage({
        capsule: this.current,
        onBack: () => this.stack.pop()
      })
    }
  }

  build() {
    Stack() {
      if (this.showAbout) {
        AboutPage({ onBack: () => { this.showAbout = false; } })
      } else if (this.showBackup) {
        BackupPage({
          total: this.capsules.length,
          opened: this.capsules.filter((c: Capsule) => c.status === CapsuleStatus.Opened).length,
          onBack: () => { this.showBackup = false; }
        })
      } else if (this.showMine) {
        MinePage({
          notifyEnabled: this.notifyEnabled,
          onBack: () => { this.showMine = false; },
          onOpenBackup: () => { this.showBackup = true; },
          onOpenAbout: () => { this.showAbout = true; }
        })
      } else {
        Navigation(this.stack) {
          HomePage({
            capsules: this.capsules,
            onNewCapsule: () => this.startNew(),
            onOpenCapsule: (c: Capsule) => this.openCapsule(c)
          })
        }
        .navDestination(this.destination)
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }

      // 我的入口：右下角悬浮，仅首页显示
      if (!this.showMine && !this.showBackup && !this.showAbout) {
        Text('我的')
          .fontSize(Font.tiny)
          .fontColor(Color.muted)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(Color.card)
          .borderRadius(14)
          .border({ width: 1, color: Color.line })
          .position({ x: 24, y: 52 })
          .onClick(() => {
            this.showMine = true;
          })
      }
    }
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
