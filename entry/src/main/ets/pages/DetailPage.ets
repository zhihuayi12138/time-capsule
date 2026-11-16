import { Color, Font, Size } from '../common/Tokens';
import { BlockType, Capsule, CapsuleStatus, ContentBlock } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { NavBar } from '../view/CommonViews';
import { AudioService } from '../data/AudioService';
import { MediaRepo } from '../data/MediaRepo';

/**
 * 胶囊详情 · 两状态
 * 封存中：内容遮蔽（界面层不可达，数据仍在本地），显示锁定说明与倒计时。
 * 已开启：完整内容 + 内嵌音频。
 */
@Component
export struct DetailPage {
  @Link capsule: Capsule;
  /** 正在播放的块 id，空串表示没在播 */
  @State playingId: string = '';
  onBack: () => void = () => {};
  /** 用户确认删除胶囊（只有已开启的才能删，封存中的不给删） */
  onDelete: () => void = () => {};

  aboutToDisappear(): void {
    AudioService.stopPlay();
  }

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

  private async playBlock(block: ContentBlock): Promise<void> {
    if (this.playingId === block.id) {
      await AudioService.stopPlay();
      this.playingId = '';
      return;
    }
    if (block.audioUri === undefined || block.audioUri.length === 0) {
      return;
    }
    this.playingId = block.id;
    await AudioService.play(block.audioUri, () => {
      this.playingId = '';
    });
  }

  private confirmDelete(): void {
    this.getUIContext().showAlertDialog({
      title: '删除这个胶囊',
      message: '删除后内容不会再有，也没有办法找回。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.warmInk,
        action: () => this.onDelete()
      }
    });
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
          // 多图一行两张，超出换行
          Flex({ wrap: FlexWrap.Wrap }) {
            if (block.uris !== undefined) {
              ForEach(block.uris!, (uri: string) => {
                Image(MediaRepo.toDisplayUri(uri))
                  .width(block.uris!.length === 1 ? '100%' : 140)
                  .height(block.uris!.length === 1 ? 220 : 140)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(12)
                  .margin({ right: 8, bottom: 8 })
              }, (uri: string) => uri)
            }
          }
          .width('100%')
          .margin({ bottom: 8 })
        } else {
          Row() {
            Text(this.playingId === block.id ? '❚❚' : '▶')
              .fontSize(12)
              .fontColor(Color.green)
              .width(32)
              .height(32)
              .textAlign(TextAlign.Center)
              .backgroundColor(Color.greenSoft)
              .borderRadius(16)
              .onClick(() => { this.playBlock(block); })
            Row()
              .width(this.playingId === block.id ? 160 : 120)
              .height(3)
              .backgroundColor(Color.green)
              .borderRadius(2)
              .margin({ left: 12 })
            Text(block.duration === undefined ? '0:00' : TimeUtil.clock(block.duration!))
              .fontSize(Font.tiny)
              .fontColor(Color.muted)
              .margin({ left: 10 })
            Blank()
            Text(this.playingId === block.id ? '正在播放' : '点击播放')
              .fontSize(Font.tiny)
              .fontColor(Color.muted2)
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
        onLeft: () => this.onBack(),
        rightText: this.capsule.status === CapsuleStatus.Opened ? '删除' : '',
        onRight: () => this.confirmDelete()
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
