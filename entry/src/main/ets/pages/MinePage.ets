import { Color, Font, Size } from '../common/Tokens';
import { NavBar } from '../view/CommonViews';

/**
 * 我的：三组设置。
 * 提醒（通知开关 / 提醒时间）、数据（备份与导出）、其他（关于）。
 * 开关状态由外层页面持有，这里只负责展示与回调。
 */
@Component
export struct MinePage {
  @Link notifyEnabled: boolean;
  lastBackupAt: number = 0;
  onBack: () => void = () => {};
  onOpenBackup: () => void = () => {};
  onOpenAbout: () => void = () => {};
  onNotifyToggle: (v: boolean) => void = () => {};

  @Builder
  groupTitle(text: string) {
    Text(text)
      .fontSize(Font.caption)
      .fontColor(Color.muted)
      .width('100%')
      .padding({ left: 4, top: 20, bottom: 8 })
  }

  @Builder
  rowArrow(label: string, value: string, onTap: () => void) {
    Row() {
      Text(label).fontSize(Font.body).fontColor(Color.ink)
      Blank()
      if (value.length > 0) {
        Text(value).fontSize(Font.caption).fontColor(Color.muted2).margin({ right: 4 })
      }
      Text('›').fontSize(18).fontColor(Color.muted2)
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.card)
    .onClick(onTap)
  }

  @Builder
  rowToggle(label: string, value: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(Font.body).fontColor(Color.ink)
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor(Color.green)
        .onChange((isOn: boolean) => onChange(isOn))
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.card)
  }

  build() {
    Column() {
      NavBar({ title: '我的', leftText: '返回', onLeft: () => this.onBack() })

      Scroll() {
        Column() {
          // 提醒
          this.groupTitle('提醒')
          Column() {
            this.rowToggle('到期提醒', this.notifyEnabled, (v: boolean) => this.onNotifyToggle(v))
            Divider().color(Color.line).strokeWidth(1).margin({ left: 16 })
            this.rowArrow('提醒时间', '当天 09:00', () => {})
          }
          .borderRadius(Size.radiusCard)
          .clip(true)

          // 数据
          this.groupTitle('数据')
          Column() {
            this.rowArrow('备份与导出', this.lastBackupAt > 0 ? '上次备份 3 天前' : '还没备份过', () => this.onOpenBackup())
          }
          .borderRadius(Size.radiusCard)
          .clip(true)

          // 其他
          this.groupTitle('其他')
          Column() {
            this.rowArrow('关于时间胶囊', 'v1.0.0', () => this.onOpenAbout())
          }
          .borderRadius(Size.radiusCard)
          .clip(true)

          Text('所有胶囊都只保存在这台设备上')
            .fontSize(Font.tiny)
            .fontColor(Color.muted2)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 28, bottom: 24 })
        }
        .padding({ left: Size.pageH, right: Size.pageH })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }
}
