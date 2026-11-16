import { Color, Font, Size } from '../common/Tokens';
import { NavBar, PrimaryButton } from '../view/CommonViews';

/** 备份与导出：统计三栏 + 两个操作 + 上次备份时间 */
@Component
export struct BackupPage {
  total: number = 0;
  opened: number = 0;
  /** 字节 */
  bytes: number = 0;
  lastBackupAt: number = 0;
  onBack: () => void = () => {};

  private mb(): string {
    const v = this.bytes / (1024 * 1024);
    return v.toFixed(1);
  }

  @Builder
  stat(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.ink)
      Text(label)
        .fontSize(Font.tiny)
        .fontColor(Color.muted)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
  }

  @Builder
  actionCard(title: string, desc: string, onTap: () => void) {
    Column() {
      Text(title).fontSize(Font.body).fontWeight(FontWeight.Medium).fontColor(Color.ink)
      Text(desc).fontSize(Font.caption).fontColor(Color.muted).margin({ top: 6 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(Color.card)
    .borderRadius(Size.radiusCard)
    .border({ width: 1, color: Color.line })
    .onClick(onTap)
  }

  build() {
    Column() {
      NavBar({ title: '备份与导出', leftText: '返回', onLeft: () => this.onBack() })

      Scroll() {
        Column() {
          // 统计
          Row() {
            this.stat(`${this.total}`, '胶囊总数')
            this.stat(`${this.opened}`, '已开启')
            this.stat(this.mb(), 'MB')
          }
          .width('100%')
          .padding({ top: 20, bottom: 20 })
          .backgroundColor(Color.card)
          .borderRadius(Size.radiusCard)
          .border({ width: 1, color: Color.line })

          // 两个操作
          Row({ space: 12 }) {
            this.actionCard('导出备份', '存成文件，换机不丢', () => {})
            this.actionCard('从备份恢复', '选择之前导出的文件', () => {})
          }
          .width('100%')
          .margin({ top: 16 })

          // 上次备份
          Row() {
            Text('上次备份').fontSize(Font.caption).fontColor(Color.muted)
            Blank()
            Text('还没有备份过').fontSize(Font.caption).fontColor(Color.muted2)
          }
          .width('100%')
          .padding(16)
          .backgroundColor(Color.card)
          .borderRadius(Size.radiusCard)
          .border({ width: 1, color: Color.line })
          .margin({ top: 16 })

          // 暖色警示
          Row() {
            Text('备份文件包含全部胶囊内容，请自行妥善保管')
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
        }
        .padding({ left: Size.pageH, right: Size.pageH, top: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Column() {
        PrimaryButton({ label: '立即导出', onTap: () => {} })
      }
      .padding({ left: Size.pageH, right: Size.pageH, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }
}

/** 关于 */
@Component
export struct AboutPage {
  onBack: () => void = () => {};

  build() {
    Column() {
      NavBar({ title: '关于', leftText: '返回', onLeft: () => this.onBack() })

      Column() {
        // App 图标：绿色圆角底 + 竖向胶囊 + 中缝
        Stack({ alignContent: Alignment.Center }) {
          Row()
            .width(76)
            .height(76)
            .borderRadius(20)
            .backgroundColor(Color.green)

          Stack({ alignContent: Alignment.Center }) {
            Row()
              .width(26)
              .height(40)
              .borderRadius(13)
              .border({ width: 2, color: '#FDF6E8' })
            Row()
              .width(26)
              .height(2)
              .backgroundColor('#FDF6E8')
          }
          .width(26)
          .height(40)
        }
        .width(76)
        .height(76)
        .margin({ top: 48 })

        Text('时间胶囊')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.ink)
          .margin({ top: 16 })

        Text('v1.0.0')
          .fontSize(Font.caption)
          .fontColor(Color.muted)
          .margin({ top: 6 })

        Text('把话锁进时间里')
          .fontSize(Font.caption)
          .fontColor(Color.ink2)
          .margin({ top: 20 })

        Text('所有内容仅保存在本机，不上传任何服务器')
          .fontSize(Font.tiny)
          .fontColor(Color.muted2)
          .textAlign(TextAlign.Center)
          .lineHeight(18)
          .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }
}
