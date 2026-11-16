import { Color, Font, Size } from '../common/Tokens';
import { Capsule, CapsuleStatus } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';

/**
 * 胶囊卡片：首页胶囊架的基本单元。
 * 到期那张用暖色底 + 暖色描边 + 绿色「打开胶囊」按钮，其余只显示倒计时与进度条。
 */
@Component
export struct CapsuleCard {
  /** 必须是 @Prop：普通成员只在创建时取值，胶囊状态变化（待开启→已开启）后卡片不会刷新 */
  @Prop capsule: Capsule = {
    id: '',
    title: '',
    status: CapsuleStatus.Pending,
    createdAt: 0,
    openAt: 0,
    blocks: [],
    notified: false
  };
  /** 卡片进入点击 */
  onOpen: (capsule: Capsule) => void = () => {};

  /** 只有当胶囊仍是「待开启」且已到期时，才算真正到期待打开 */
  private isDueNow(): boolean {
    return this.capsule.status === CapsuleStatus.Pending && TimeUtil.isDue(this.capsule.openAt);
  }

  private progress(): number {
    const total = this.capsule.openAt - this.capsule.createdAt;
    if (total <= 0) {
      return 100;
    }
    const done = Date.now() - this.capsule.createdAt;
    return Math.round(Math.min(1, Math.max(0, done / total)) * 100);
  }

  private isDuePending(): boolean {
    return this.isDueNow();
  }

  private countdownText(): string {
    if (this.capsule.status === CapsuleStatus.Opened) {
      return `已等待 ${TimeUtil.daysWaited(this.capsule.createdAt, this.capsule.openedAt)} 天`;
    }
    // 草稿还没封存，不显示倒计时
    if (this.capsule.status === CapsuleStatus.Draft) {
      return '草稿 · 还没封存';
    }
    // 到期的卡片顶部已有一行暖色提示，这里不再重复
    if (this.isDuePending()) {
      return '';
    }
    return `距离开启还有 ${TimeUtil.daysLeft(this.capsule.openAt)} 天`;
  }

  build() {
    Column() {
      if (this.isDueNow()) {
        Row() {
          Circle().width(5).height(5).fill(Color.warmInk)
          Text('今天到期 · 可以打开了')
            .fontSize(Font.tiny)
            .fontColor(Color.warmInk)
            .margin({ left: 6 })
        }
        .width('100%')
        .margin({ bottom: 8 })
      }

      Text(this.capsule.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.ink)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.countdownText().length > 0) {
        Text(this.countdownText())
          .fontSize(Font.caption)
          .fontColor(Color.muted)
          .margin({ top: 6 })
          .width('100%')
      }

      if (this.capsule.status === CapsuleStatus.Pending) {
        // 细进度条：已过时间占全程的比例（0% 时不画填充，避免退化成整条）
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(3).backgroundColor(Color.line).borderRadius(2)
          if (this.progress() > 0) {
            Row().width(`${this.progress()}%`).height(3).backgroundColor(Color.green).borderRadius(2)
          }
        }
        .width('100%')
        .height(3)
        .margin({ top: 12 })
      }

      if (this.isDueNow()) {
        Text('打开胶囊')
          .height(36)
          .padding({ left: 18, right: 18 })
          .fontSize(Font.caption)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(Color.green)
          .borderRadius(18)
          .margin({ top: 12 })
          .alignSelf(ItemAlign.Start)
          .onClick(() => this.onOpen(this.capsule))
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.isDueNow() ? Color.warmBg : Color.card)
    .borderRadius(Size.radiusCard)
    .border({
      width: 1,
      color: this.isDueNow() ? Color.warmLine : Color.line
    })
    .onClick(() => this.onOpen(this.capsule))
  }
}
