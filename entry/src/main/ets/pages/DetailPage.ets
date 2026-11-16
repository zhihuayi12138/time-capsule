import { Color, Font, Size } from '../common/Tokens';
import { BlockType, Capsule, CapsuleStatus, ContentBlock } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { NavBar } from '../view/CommonViews';

/**
 * 胶囊详情 · 两状态
 * 封存中：内容遮蔽（界面层不可达，数据仍在本地），显示锁定说明与倒计时。
 * 已开启：完整内容 + 内嵌音频。
 */
@Component
export struct DetailPage {
  @Link capsule: Capsule;
  onBack: () => void = () => {};

  private isSealed(): boolean {
    return this.capsule.status === CapsuleStatus.Pending && !TimeUtil.isDue(this.capsule.openAt);
  }

  /** 返回 0–100 的整数百分比；0% 时调用方不画填充条 */
  private progress(): number {
    const total = this.capsule.openAt - this.capsule.createdAt;
    if (total <= 0) {
      return 100;
    }
    return Math.round(Math.min(1, Math.max(0, (Date.now() - this.capsule.createdAt) / total)) * 100);
  }

  @Builder
  pill(text: string, fg: string, bg: string) {
    Text(text)
      .fontSize(Font.tiny)
      .fontColor(fg)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(bg)
      .borderRadius(12)
      .alignSelf(ItemAlign.Start)
  }

  @Builder
  sealedBody() {
    Column() {
      // 锁形遮蔽卡
      Column() {
        Text('🔒').fontSize(28)
        Text('内容已封存')
          .fontSize(Font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.ink)
          .margin({ top: 12 })
        Text('到期之前，谁都没有办法提前打开')
          .fontSize(Font.caption)
          .fontColor(Color.muted)
          .margin({ top: 6 })
      }
      .width('100%')
      .padding({ top: 40, bottom: 40 })
      .borderRadius(Size.radiusCard)
      .border({ width: 1.5, color: Color.dash, style: BorderStyle.Dashed })

      // 倒计时
      Column() {
        Text(`${TimeUtil.daysLeft(this.capsule.openAt)}`)
          .fontSize(52)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.ink)
        Text('天后开启')
          .fontSize(Font.caption)
          .fontColor(Color.muted)
          .margin({ top: 2 })

        Stack({ alignContent: Alignment.Start }) {
          Row().width('100%').height(4).backgroundColor(Color.line).borderRadius(2)
          if (this.progress() > 0) {
            Row().width(`${this.progress()}%`).height(4).backgroundColor(Color.green).borderRadius(2)
          }
        }
        .width('100%')
        .height(4)
        .margin({ top: 20 })
      }
      .width('100%')
      .margin({ top: 28 })

      // 元信息
      Column() {
        this.metaRow('内含', `${this.capsule.blocks.length} 个内容块`)
        Divider().color(Color.line).strokeWidth(1)
        this.metaRow('开启时间', TimeUtil.format(this.capsule.openAt))
        Divider().color(Color.line).strokeWidth(1)
        this.metaRow('提醒', '到期当天 09:00')
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(Color.card)
      .borderRadius(Size.radiusCard)
      .border({ width: 1, color: Color.line })
      .margin({ top: 28 })

      Text('封存后内容无法修改，也不支持提前开启')
        .fontSize(Font.tiny)
        .fontColor(Color.muted2)
        .margin({ top: 16 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  metaRow(k: string, v: string) {
    Row() {
      Text(k).fontSize(Font.caption).fontColor(Color.muted)
      Blank()
      Text(v).fontSize(Font.caption).fontColor(Color.ink2)
    }
    .width('100%')
    .height(46)
  }

  @Builder
  openedBody() {
    Column() {
      ForEach(this.capsule.blocks, (block: ContentBlock) => {
        if (block.type === BlockType.Text) {
          Text(block.text === undefined ? '' : block.text!)
            .fontSize(Font.body)
            .fontColor(Color.ink)
            .lineHeight(26)
            .width('100%')
            .margin({ bottom: 16 })
        } else if (block.type === BlockType.Image) {
          Row() {
            if (block.uris !== undefined) {
              ForEach(block.uris!, (uri: string) => {
                Row().width(140).height(140).backgroundColor(Color.line).borderRadius(12).margin({ right: 8 })
              }, (uri: string) => uri)
            }
          }
          .width('100%')
          .margin({ bottom: 16 })
        } else {
          Row() {
            Text('▶')
              .fontSize(12)
              .fontColor(Color.green)
              .width(32)
              .height(32)
              .textAlign(TextAlign.Center)
              .backgroundColor(Color.greenSoft)
              .borderRadius(16)
            Row().width(120).height(3).backgroundColor(Color.green).borderRadius(2).margin({ left: 12 })
            Text(block.duration === undefined ? '0:00' : `0:${block.duration!}`)
              .fontSize(Font.tiny)
              .fontColor(Color.muted)
              .margin({ left: 10 })
            Blank()
          }
          .width('100%')
          .height(56)
          .padding({ left: 12, right: 12 })
          .backgroundColor(Color.card)
          .borderRadius(14)
          .border({ width: 1, color: Color.line })
          .margin({ bottom: 16 })
        }
      }, (block: ContentBlock) => block.id)

      Text(`封存于 ${TimeUtil.format(this.capsule.createdAt)}`)
        .fontSize(Font.tiny)
        .fontColor(Color.muted2)
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      NavBar({
        title: '',
        leftText: '返回',
        onLeft: () => this.onBack()
      })

      Scroll() {
        Column() {
          if (this.capsule.status === CapsuleStatus.Opened) {
            this.pill(`已等待 ${TimeUtil.daysWaited(this.capsule.createdAt, this.capsule.openedAt)} 天 · 刚刚开启`,
              Color.green, Color.greenSoft)
          } else {
            this.pill(`已封存 · ${TimeUtil.pendingLabel(this.capsule.openAt)}`, Color.warmInk, Color.warmBg)
          }

          Text(this.capsule.title)
            .fontSize(Font.title)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.ink)
            .width('100%')
            .margin({ top: 14, bottom: 20 })

          if (this.isSealed()) {
            this.sealedBody()
          } else {
            this.openedBody()
          }
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Size.pageH, right: Size.pageH, top: 12, bottom: 40 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }
}
