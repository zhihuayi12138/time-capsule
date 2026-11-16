/**
 * 桌面服务卡片 · 2x4
 *
 * 只显示最近要开启的那一个约定。
 * 卡片拿不到 RDB，数据由 CapsuleCardAbility 通过 formProvider.updateForm 推入，
 * 在卡片侧以 @LocalStorageProp 接收（键名必须与 createFormBindingData 的字段一致）。
 */
@Entry
@Component
struct CapsuleCard {
  /** 卡片模式：countdown / due / empty */
  @LocalStorageProp('mode') mode: string = 'empty';
  /** 主视觉文案：还有 87 天 / 可以打开了 */
  @LocalStorageProp('headline') headline: string = '时间在走';
  /** 胶囊标题 */
  @LocalStorageProp('title') title: string = '还没有和未来约定什么';
  /** 辅助说明 */
  @LocalStorageProp('hint') hint: string = '点一下，写下此刻';
  /** 待开启总数 */
  @LocalStorageProp('count') count: number = 0;

  private isDue(): boolean {
    return this.mode === 'due';
  }

  build() {
    Column() {
      Row() {
        Text(this.isDue() ? '可以打开了' : '时间胶囊')
          .fontSize(12)
          .fontColor(this.isDue() ? '#A8742A' : '#8C8A82')
        Blank()
        if (this.count > 0) {
          Text(`${this.count} 个约定`)
            .fontSize(11)
            .fontColor('#B4B0A5')
        }
      }
      .width('100%')

      Text(this.headline)
        .fontSize(this.isDue() ? 26 : 34)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1E2420')
        .width('100%')
        .margin({ top: 10 })

      Text(this.title)
        .fontSize(13)
        .fontColor('#454B47')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 6 })

      Blank()

      Row() {
        Text(this.hint)
          .fontSize(11)
          .fontColor('#8C8A82')
        Blank()
        Text('打开 ›')
          .fontSize(11)
          .fontColor('#2C5F55')
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(this.isDue() ? '#FDF6E8' : '#FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: {
          from: 'card'
        }
      });
    })
  }
}
