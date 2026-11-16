import { Color, Font, Size } from '../common/Tokens';

/**
 * 我的（底部 Tab 一级页面）。
 * 三组设置：提醒、数据、其他。开关状态由根页面持有，这里只展示与回调。
 */
@Component
export struct MinePage {
  @Link notifyEnabled: boolean;
  /** @Prop：备份完成后根页面会改这个值，普通成员不会触发重绘 */
  @Prop lastBackupAt: number = 0;
  /**
   * 系统通知是否真的被授权。
   * 和 notifyEnabled 分开：notifyEnabled 是"用户想不想要提醒"，
   * 这个是"系统让不让"，两者不一致时界面必须说清楚，否则用户会以为设了提醒。
   */
  @Prop notifyGranted: boolean = false;
  /**
   * 系统排程提醒时的失败原因（云能力校验、未签名包等）。
   * 通知权限开着也可能排不上，这种情况同样要告诉用户，
   * 否则「我明明开了提醒」和「怎么没响」之间会出现无法解释的落差。
   */
  @Prop scheduleFail: string = '';
  /**
   * 提醒时间的时分（24 小时制）。
   * 之前这一行是硬编码「当天 09:00」+ 空回调，等于摆了一个改不动的设置项，
   * 用户点上去没有任何反应。现在由根页面持有，点开弹时间选择器。
   */
  @Prop remindHour: number = 9;
  @Prop remindMinute: number = 0;
  onOpenBackup: () => void = () => {};
  onOpenAbout: () => void = () => {};
  onNotifyToggle: (v: boolean) => void = () => {};
  onOpenNotifySettings: () => void = () => {};
  onPickRemindTime: () => void = () => {};

  /** 09:00 形式，分钟补零 */
  private remindLabel(): string {
    const mm = this.remindMinute < 10 ? `0${this.remindMinute}` : `${this.remindMinute}`;
    const hh = this.remindHour < 10 ? `0${this.remindHour}` : `${this.remindHour}`;
    return `当天 ${hh}:${mm}`;
  }

  @Builder
  groupTitle(text: string) {
    Text(text)
      .fontSize(Font.caption)
      .fontColor(Color.muted)
      .width('100%')
      .padding({ left: 4, top: 20, bottom: 8 })
  }

  /** 提醒开着但系统没授权时的提示行，点一下去系统设置 */
  @Builder
  warnRow() {
    Row() {
      Text('通知没有打开，到期可能不会提醒你')
        .fontSize(Font.caption)
        .fontColor(Color.warmInk)
        .layoutWeight(1)
      Text('去设置')
        .fontSize(Font.caption)
        .fontColor(Color.warmInk)
        .fontWeight(FontWeight.Medium)
        .margin({ right: 2 })
      Text('›').fontSize(16).fontColor(Color.warmInk)
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.warmBg)
    .onClick(() => this.onOpenNotifySettings())
  }

  /** 有权限但系统不让排程时的提示行（模拟器、未签名包常见） */
  @Builder
  scheduleWarnRow() {
    Column() {
      Text('系统提醒没有排上，到时间不会自动弹通知')
        .fontSize(Font.caption)
        .fontColor(Color.warmInk)
        .width('100%')
      Text('打开应用时会自动标成到期，不会漏掉')
        .fontSize(Font.tiny)
        .fontColor(Color.warmInk)
        .opacity(0.8)
        .width('100%')
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.warmBg)
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
      // 与胶囊架一致的大标题
      Column() {
        Text('我的')
          .fontSize(Font.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.ink)
          .width('100%')

        Text('设置、备份与关于')
          .fontSize(Font.caption)
          .fontColor(Color.muted)
          .margin({ top: 6 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Size.pageH, right: Size.pageH, top: 16, bottom: 4 })

      Scroll() {
        Column() {
          // 提醒
          this.groupTitle('提醒')
          Column() {
            this.rowToggle('到期提醒', this.notifyEnabled, (v: boolean) => this.onNotifyToggle(v))
            if (this.notifyEnabled && !this.notifyGranted) {
              Divider().color(Color.line).strokeWidth(1).margin({ left: 16 })
              this.warnRow()
            } else if (this.notifyEnabled && this.scheduleFail.length > 0) {
              Divider().color(Color.line).strokeWidth(1).margin({ left: 16 })
              this.scheduleWarnRow()
            }
            Divider().color(Color.line).strokeWidth(1).margin({ left: 16 })
            // 提醒时间直接内联而不是走 rowArrow(@Builder)：
            // @Builder 的参数是值传递，改时分不会重绘，文案会停在旧值上。
            Row() {
              Text('提醒时间').fontSize(Font.body).fontColor(Color.ink)
              Blank()
              Text(this.remindLabel())
                .fontSize(Font.caption)
                .fontColor(Color.green)
                .fontWeight(FontWeight.Medium)
                .margin({ right: 4 })
              Text('›').fontSize(18).fontColor(Color.muted2)
            }
            .width('100%')
            .height(52)
            .padding({ left: 16, right: 16 })
            .backgroundColor(Color.card)
            .onClick(() => this.onPickRemindTime())
          }
          .borderRadius(Size.radiusCard)
          .clip(true)
          // 数据
          this.groupTitle('数据')
          Column() {
            this.rowArrow('备份与导出',
              this.lastBackupAt > 0 ? '已备份' : '还没备份过',
              () => this.onOpenBackup())
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
        .alignItems(HorizontalAlign.Start)
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
