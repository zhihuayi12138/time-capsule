import { Color, Font, Size } from '../common/Tokens';
import { Capsule, CapsuleStatus } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';

/**
 * 胶囊卡片：首页胶囊架的基本单元。
 * 到期那张用暖色底 + 暖色描边 + 绿色「打开胶囊」按钮，其余只显示倒计时与进度条。
 */
@Component
export struct CapsuleCard {
  capsule: Capsule = {
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

  private isDue(): boolean {
    return this.capsule.status === CapsuleStatus.Opened ||
      TimeUtil.isDue(this.capsule.openAt);
  }

  private progress(): number {
    const total = this.capsule.openAt - this.capsule.createdAt;
    if (total <= 0) {
      return 1;
    }
    const done = Date.now() - this.capsule.createdAt;
    return Math.min(1, Math.max(0, done / total));
  }

  private countdownText(): string {
    if (this.capsule.status === CapsuleStatus.Opened) {
      return `已等待 ${TimeUtil.daysWaited(this.capsule.createdAt, this.capsule.openedAt)} 天`;
    }
    const left = TimeUtil.daysLeft(this.capsule.openAt);
    if (left <= 0) {
      return '今天到期 · 可以打开了';
    }
    return `距离开启还有 ${left} 天`;
  }

  build() {
    Column() {
      if (this.isDue() && this.capsule.status === CapsuleStatus.Pending) {
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

      Text(this.countdownText())
        .fontSize(Font.caption)
        .fontColor(Color.muted)
        .margin({ top: 6 })
        .width('100%')

      if (this.capsule.status === CapsuleStatus.Pending) {
        // 细进度条：已过时间占全程的比例
        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(3).backgroundColor(Color.line).borderRadius(2)
          Row().width(`${this.progress() * 100}%`).height(3).backgroundColor(Color.green).borderRadius(2)
        }
        .width('100%')
        .height(3)
        .margin({ top: 12 })
      }

      if (this.isDue() && this.capsule.status === CapsuleStatus.Pending) {
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
    .backgroundColor(this.isDue() && this.capsule.status === CapsuleStatus.Pending ? Color.warmBg : Color.card)
    .borderRadius(Size.radiusCard)
    .border({
      width: 1,
      color: this.isDue() && this.capsule.status === CapsuleStatus.Pending ? Color.warmLine : Color.line
    })
    .onClick(() => this.onOpen(this.capsule))
  }
}
