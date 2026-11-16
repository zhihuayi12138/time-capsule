import { Color, Font, Size } from '../common/Tokens';
import { Capsule, CapsuleStatus, ContentBlock } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { Routes, StoreKey } from '../common/Constants';
import { HomePage } from './HomePage';
import { EditorPage } from './EditorPage';
import { DetailPage } from './DetailPage';
import { MinePage } from './MinePage';
import { BackupPage, AboutPage } from './BackupPage';
import { PrimaryButton } from '../view/CommonViews';
import { CapsuleRepo } from '../data/CapsuleRepo';
import { SettingsRepo } from '../data/SettingsRepo';
import { ReminderService } from '../data/ReminderService';
import { BackupService } from '../data/BackupService';
import { MediaRepo } from '../data/MediaRepo';
import { AudioService } from '../data/AudioService';
import { CardData } from '../data/CardData';

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
  @State capsules: Capsule[] = [];
  @State current: Capsule = Index.emptyCapsule();
  @State notifyEnabled: boolean = true;
  /** 系统层面是否真的允许通知；与 notifyEnabled（用户意愿）分开判断 */
  @State notifyGranted: boolean = false;
  /**
   * 上一次给胶囊排系统提醒时的失败原因，空串表示没出问题。
   * 和 notifyGranted 分开看：通知权限开着，系统也照样可能拒绝排程
   * （云能力校验、未签名安装包等），这种情况界面必须说实话。
   */
  @State scheduleFail: string = '';
  /** 提醒时刻（24 小时制），持久化在 preferences 里 */
  @State remindHour: number = 9;
  @State remindMinute: number = 0;
  @State lastBackupAt: number = 0;
  @State showSealSheet: boolean = false;
  @State activeTab: number = 0;
  /** 备份页打开时实时统计的媒体占用字节 */
  @State mediaBytes: number = 0;
  @State loading: boolean = true;
  @State toast: string = '';
  /** 当前时间，每 30 秒推一次；子组件的到期判定都读它 */
  @State nowMs: number = Date.now();
  /** 每次要让胶囊架回到「待开启」就把它加一（封存完成、恢复备份后） */
  @State homeResetToken: number = 0;

  private stack: NavPathStack = new NavPathStack();
  /**
   * Tabs 的 index 属性只在首次构建时生效，之后再改 activeTab 不会真的切页。
   * 封存后要主动回到胶囊架，必须走 TabsController。
   */
  private tabsCtl: TabsController = new TabsController();
  /** 每 30 秒触发一次重算，让倒计时与到期态自然翻页 */
  private tick: number = -1;

  static emptyCapsule(): Capsule {
    return {
      id: '',
      title: '',
      status: CapsuleStatus.Draft,
      createdAt: Date.now(),
      openAt: TimeUtil.shiftDays(Date.now(), 30),
      blocks: [],
      notified: false
    };
  }

  aboutToAppear(): void {
    this.bootstrap();
    // 每 30 秒重新求值一次：让"正好停在这一天到期"的卡片自动变暖。
    // 系统提醒负责应用不在时，这里负责应用开着时。
    this.tick = setInterval(() => {
      this.nowMs = Date.now();
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.tick >= 0) {
      clearInterval(this.tick);
      this.tick = -1;
    }
  }

  /**
   * 启动流程：读库 → 补排程 → 读设置。
   * 任何一步失败都不应该让应用白屏，所以整体包了 try/catch，失败时退化成空列表。
   */
  private async bootstrap(): Promise<void> {
    try {
      await CapsuleRepo.init();
      const list = await CapsuleRepo.listAll();
      this.capsules = list;
      this.notifyEnabled = await SettingsRepo.getBool(StoreKey.KEY_NOTIFY_ENABLED, true);
      this.lastBackupAt = await SettingsRepo.getNumber(StoreKey.KEY_LAST_BACKUP, 0);
      this.remindHour = await SettingsRepo.getNumber(StoreKey.KEY_REMIND_HOUR, 9);
      this.remindMinute = await SettingsRepo.getNumber(StoreKey.KEY_REMIND_MINUTE, 0);
      ReminderService.remindHour = this.remindHour;
      ReminderService.remindMinute = this.remindMinute;
      // 启动时给还没排过提醒的胶囊补上系统提醒
      if (this.notifyEnabled) {
        await this.ensureNotifyPermission();
        await this.refreshNotifyGranted();
        const synced = await ReminderService.syncAll(this.capsules);
        this.capsules = synced;
        this.noteScheduleFail();
      }
      // 到期的补一条前台通知：系统提醒负责"应用不在时"，
      // 这里补的是"应用被打开、发现有胶囊已经过点了"的那一种情况。
      // 只补一次（notified 标记），否则每次冷启动都重复推同一条。
      if (this.notifyEnabled) {
        const fresh = this.capsules.filter(
          (c: Capsule) => c.status === CapsuleStatus.Pending && !c.notified && TimeUtil.isDue(c.openAt)
        );
        for (const c of fresh) {
          c.notified = true;
          await ReminderService.notifyNow(c);
          await this.persistOne(c);
        }
      }
    } catch (e) {
      this.capsules = [];
    } finally {
      this.loading = false;
    }
    // 应用一打开就把卡片对齐一次，避免桌面还停在昨天的数字
    CardData.pushAll(this.capsules);
  }

  private showToast(msg: string): void {
    this.toast = msg;
    setTimeout(() => {
      this.toast = '';
    }, 2200);
  }

  /** 持久化单个胶囊并同步内存列表 */
  private async persistOne(c: Capsule): Promise<void> {
    await CapsuleRepo.save(c);
    const idx = this.capsules.findIndex((x: Capsule) => x.id === c.id);
    if (idx >= 0) {
      this.capsules[idx] = c;
    } else {
      this.capsules.push(c);
    }
    this.capsules = this.capsules.slice();
    // 数据一变就把桌面卡片推一遍：卡片是通知之外的兜底
    CardData.pushAll(this.capsules);
  }

  private startNew(): void {
    this.current = Index.emptyCapsule();
    this.stack.pushPathByName(Routes.EDITOR, null);
  }

  private async openCapsule(c: Capsule): Promise<void> {
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
      c.notified = true;
      if (c.reminderId !== undefined) {
        await ReminderService.cancel(c.reminderId);
        c.reminderId = undefined;
      }
      await ReminderService.cancelNotify(c);
      await this.persistOne(c);
    }
    this.stack.pushPathByName(Routes.DETAIL, null);
  }

  /**
   * 删除胶囊：清库 + 清提醒 + 清列表 + 推卡片，然后退回上一页。
   * 封存中的胶囊不给删（详情页也不显示删除入口），避免「约定」被随手撤销。
   */
  private async removeCapsule(c: Capsule): Promise<void> {
    try {
      if (c.reminderId !== undefined) {
        await ReminderService.cancel(c.reminderId);
      }
      await ReminderService.cancelNotify(c);
      await CapsuleRepo.remove(c.id);
      this.capsules = this.capsules.filter((it: Capsule) => it.id !== c.id);
      CardData.pushAll(this.capsules);
      this.stack.pop();
      this.showToast('已删除');
    } catch (err) {
      this.showToast('删除失败，请再试一次');
    }
  }

  /**
   * 确认封存：写入待开启态，排系统提醒，然后回到胶囊架。
   * 这里的顺序很重要 —— 先落库再排提醒，避免提醒排好了但数据没存住。
   */
  private async confirmSeal(): Promise<void> {
    const c = this.current;
    c.status = CapsuleStatus.Pending;
    if (c.id.length === 0) {
      c.id = `cap_${Date.now()}`;
    }
    let scheduled = false;
    try {
      await this.persistOne(c);
      if (this.notifyEnabled) {
        const rid = await ReminderService.schedule(c);
        if (rid !== undefined) {
          c.reminderId = rid;
          await this.persistOne(c);
          scheduled = true;
        }
      }
    } catch (e) {
      this.showToast('封存失败，请再试一次');
      return;
    }
    this.showSealSheet = false;
    this.stack.pop();
    this.goHomeTab();
    // 系统提醒没排上时不要只说「已经封存」——用户会以为到点一定会收到通知。
    // 这种情况仍能靠打开应用时的到期标记兜底，所以措辞是「打开时会标成到期」。
    if (this.notifyEnabled && !scheduled) {
      this.showToast('已经封存，但系统提醒没排上，打开应用时会标成到期');
    } else {
      this.showToast('已经封存，等它到时间');
    }
  }

  private openedCount(): number {
    return this.capsules.filter((c: Capsule) => c.status === CapsuleStatus.Opened).length;
  }

  /**
   * 回到「胶囊架」标签页。
   * 光改 activeTab 不够：Tabs 的 index 只在创建时生效，之后切页必须用 TabsController，
   * 否则从「我的」进备份页再返回，会停在「我的」而不是回到胶囊架。
   */
  private goHomeTab(): void {
    this.activeTab = 0;
    this.tabsCtl.changeIndex(0);
    this.homeResetToken = this.homeResetToken + 1;
  }

  /**
   * 编辑器点取消且已经写了内容 → 存成草稿。
   * 草稿是「写了半篇，还没决定什么时候封」，所以 openAt 保留编辑器里的值，
   * 之后再点开这张卡会回到编辑器继续写（openCapsule 里已按 Draft 分支处理）。
   */
  private async saveDraft(title: string, blocks: ContentBlock[], openAt: number): Promise<void> {
    const c = this.current;
    c.title = title.trim().length > 0 ? title : '还没想好名字';
    c.blocks = blocks;
    c.openAt = openAt;
    c.status = CapsuleStatus.Draft;
    if (c.id.length === 0) {
      c.id = `cap_${Date.now()}`;
    }
    try {
      await this.persistOne(c);
    } catch (e) {
      this.showToast('草稿没存上，请再试一次');
      return;
    }
    this.stack.pop();
    this.goHomeTab();
    this.showToast('已经存成草稿');
  }

  /**
   * 首次启动时问一次通知权限。
   * 只在没问过的时候问（KEY_NOTIFY_GUIDED），避免每次冷启动都弹窗打扰。
   */
  private async ensureNotifyPermission(): Promise<void> {
    try {
      const guided = await SettingsRepo.getBool(StoreKey.KEY_NOTIFY_GUIDED, false);
      if (guided) {
        return;
      }
      await SettingsRepo.putBool(StoreKey.KEY_NOTIFY_GUIDED, true);
      const on = await ReminderService.requestPermission();
      if (!on) {
        this.showToast('没开通知也行，打开应用时胶囊会标成到期');
      }
    } catch (e) {
      // 拿不到权限不影响主流程
    }
  }

  private async onNotifyToggle(v: boolean): Promise<void> {
    this.notifyEnabled = v;
    await SettingsRepo.putBool(StoreKey.KEY_NOTIFY_ENABLED, v);
    if (v) {
      const ok = await ReminderService.requestPermission();
      this.notifyGranted = ok;
      if (ok) {
        const synced = await ReminderService.syncAll(this.capsules);
        this.capsules = synced;
        this.noteScheduleFail();
      } else {
        this.showToast('没有通知权限，提醒可能不会弹出');
      }
    }
  }

  /**
   * 把 ReminderService 记下的排程失败原因搬到界面上。
   * 没有待开启的胶囊时不会有失败，所以空串是正常状态。
   */
  private noteScheduleFail(): void {
    this.scheduleFail = ReminderService.lastError;
  }

  /** 重新读一次系统通知授权状态（从设置页返回后调用） */
  private async refreshNotifyGranted(): Promise<void> {
    this.notifyGranted = await ReminderService.isGranted();
    if (this.notifyGranted && this.notifyEnabled) {
      const synced = await ReminderService.syncAll(this.capsules);
      this.capsules = synced;
      this.noteScheduleFail();
    }
  }

  /**
   * 选择提醒时刻。改完要重新排一遍：
   * 已经排过的提醒还停在旧的时分上，不重排就等于设置没生效。
   */
  private pickRemindTime(): void {
    const selected = new Date();
    selected.setHours(this.remindHour, this.remindMinute, 0, 0);
    this.getUIContext().showTimePickerDialog({
      selected: selected,
      useMilitaryTime: true,
      onAccept: (value: TimePickerResult) => {
        const hh = value.hour === undefined ? 9 : value.hour;
        const mm = value.minute === undefined ? 0 : value.minute;
        this.applyRemindTime(hh, mm);
      }
    });
  }

  private async applyRemindTime(hh: number, mm: number): Promise<void> {
    this.remindHour = hh;
    this.remindMinute = mm;
    await SettingsRepo.putNumber(StoreKey.KEY_REMIND_HOUR, hh);
    await SettingsRepo.putNumber(StoreKey.KEY_REMIND_MINUTE, mm);
    ReminderService.remindHour = hh;
    ReminderService.remindMinute = mm;
    // 旧提醒按旧时分排的，先全部撤掉再按新时刻重排
    for (const c of this.capsules) {
      if (c.status === CapsuleStatus.Pending && c.reminderId !== undefined) {
        await ReminderService.cancel(c.reminderId);
        c.reminderId = undefined;
      }
    }
    const synced = await ReminderService.syncAll(this.capsules);
    this.capsules = synced.slice();
    this.noteScheduleFail();
    const label = `${hh < 10 ? '0' + hh : hh}:${mm < 10 ? '0' + mm : mm}`;
    this.showToast(`提醒时间改成 ${label}`);
  }

  private async onExport(): Promise<void> {
    try {
      const dest = await BackupService.exportAll();
      if (dest.length === 0) {
        return;
      }
      this.lastBackupAt = Date.now();
      await SettingsRepo.putNumber(StoreKey.KEY_LAST_BACKUP, this.lastBackupAt);
      this.showToast('已导出备份');
    } catch (e) {
      this.showToast('导出失败，请检查存储权限');
    }
  }

  private async onImport(): Promise<void> {
    const result = await BackupService.importFrom();
    if (!result.ok) {
      this.showToast(result.message.length === 0 ? '恢复失败' : result.message);
      return;
    }
    const list = await CapsuleRepo.listAll();
    this.capsules = list;
    this.mediaBytes = MediaRepo.totalBytes();
    CardData.pushAll(this.capsules);
    this.showToast(`已恢复 ${result.count} 个胶囊`);
  }

  private openBackup(): void {
    this.mediaBytes = MediaRepo.totalBytes();
    this.stack.pushPathByName(Routes.BACKUP, null);
  }

  // ---------------- 底部 Tab ----------------

  /**
   * 底部单个 Tab。
   * 注意：@Builder 按值传参不会随状态变化重建，所以这里不传 active，
   * 而是直接在属性里读 this.activeTab，才能跟着选中态刷新。
   */
  @Builder
  tabItem(index: number, label: string) {
    Column() {
      if (index === 0) {
        // 实心胶囊 + 一道底色中缝，跟应用图标同一套语汇
        Stack() {
          Row()
            .width(15)
            .height(20)
            .borderRadius(7.5)
            .backgroundColor(this.activeTab === index ? Color.green : Color.muted2)
          Row()
            .width(15)
            .height(2)
            .backgroundColor(Color.bg)
        }
        .width(22)
        .height(22)
      } else {
        // 人形：头 + 肩，肩用上圆角矩形，比半圆在 11vp 高度里更好辨认
        Column() {
          Circle()
            .width(8)
            .height(8)
            .fill(this.activeTab === index ? Color.green : Color.muted2)
          Row()
            .width(16)
            .height(8)
            .borderRadius({ topLeft: 8, topRight: 8 })
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
        PrimaryButton({ label: '确认封存', onTap: () => { this.confirmSeal(); } })
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
          onSaveDraft: (title: string, blocks: ContentBlock[], openAt: number) => {
            this.saveDraft(title, blocks, openAt);
          },
          onRequestSeal: (title: string, blocks: ContentBlock[], openAt: number) => {
            // 编辑器把当前值回传，这里一次性写进待封存草稿，避免读到过期的 this.current
            const c = this.current;
            c.title = title;
            c.blocks = blocks;
            c.openAt = openAt;
            this.current = c;
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
          },
          onDelete: () => {
            this.removeCapsule(this.current);
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
          bytes: this.mediaBytes,
          lastBackupAt: this.lastBackupAt,
          onBack: () => {
            this.stack.pop();
          },
          onExport: () => {
            this.onExport();
          },
          onImport: () => {
            this.onImport();
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
    Stack() {
      Navigation(this.stack) {
        Tabs({ barPosition: BarPosition.End, index: this.activeTab, controller: this.tabsCtl }) {
          TabContent() {
            HomePage({
              capsules: this.capsules,
              nowMs: this.nowMs,
              resetToken: this.homeResetToken,
              onNewCapsule: () => this.startNew(),
              onOpenCapsule: (c: Capsule) => {
                this.openCapsule(c);
              }
            })
          }
          .tabBar(this.tabItem(0, '胶囊架'))

          TabContent() {
            MinePage({
              notifyEnabled: this.notifyEnabled,
              lastBackupAt: this.lastBackupAt,
              notifyGranted: this.notifyGranted,
              scheduleFail: this.scheduleFail,
              remindHour: this.remindHour,
              remindMinute: this.remindMinute,
              onOpenBackup: () => this.openBackup(),
              onOpenAbout: () => {
                this.stack.pushPathByName(Routes.ABOUT, null);
              },
              onNotifyToggle: (v: boolean) => {
                this.onNotifyToggle(v);
              },
              onOpenNotifySettings: () => {
                ReminderService.openSettings().then(() => this.refreshNotifyGranted());
              },
              onPickRemindTime: () => {
                this.pickRemindTime();
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

      // 封存确认弹层。
      // 刻意不用 bindSheet：弹层绑在 Navigation 上时，压栈后的 NavDestination
      // 会盖在弹层的 overlay 之上，点了「封存胶囊」看起来毫无反应。
      // 这里改成自绘遮罩 + 底部面板，层级在 Navigation 之上，行为可预期。
      if (this.showSealSheet) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#66000000')
            .onClick(() => {
              this.showSealSheet = false;
            })

          Column() {
            this.sealSheet()
          }
          .width('100%')
          .transition(TransitionEffect.translate({ y: 460 })
            .animation({ duration: 240, curve: Curve.FastOutSlowIn }))
        }
        .width('100%')
        .height('100%')
      }

      if (this.toast.length > 0) {
        Column() {
          Text(this.toast)
            .fontSize(Font.caption)
            .fontColor('#FFFFFF')
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .backgroundColor('#E61E2420')
            .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 120 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }
}
