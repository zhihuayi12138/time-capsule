import { Color, Font, Size } from '../common/Tokens';

/**
 * 统一导航栏：左侧返回/取消，中间标题，右侧动作文字。
 * 标题下方 1px 分隔线，与原型中二级页的处理一致。
 */
@Component
export struct NavBar {
  title: string = '';
  leftText: string = '返回';
  rightText: string = '';
  rightEnabled: boolean = true;
  showDivider: boolean = true;
  onLeft: () => void = () => {};
  onRight: () => void = () => {};

  build() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Text(this.title)
          .fontSize(Font.section)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.ink)

        Row() {
          Text(this.leftText)
            .fontSize(Font.body)
            .fontColor(Color.ink2)
            .onClick(() => this.onLeft())
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: Size.pageH })

        Row() {
          Text(this.rightText)
            .fontSize(Font.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.rightEnabled ? Color.green : Color.muted2)
            .onClick(() => {
              if (this.rightEnabled) {
                this.onRight();
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: Size.pageH })
      }
      .width('100%')
      .height(Size.navBar)

      if (this.showDivider) {
        Divider().color(Color.line).strokeWidth(1)
      }
    }
    .width('100%')
  }
}

/** 主按钮：实心绿，50 高，16 圆角。 */
@Component
export struct PrimaryButton {
  label: string = '';
  /** 注意：不能命名为 enabled，会与 CustomComponent 内置属性冲突 */
  isEnabled: boolean = true;
  onTap: () => void = () => {};

  build() {
    Text(this.label)
      .width('100%')
      .height(50)
      .textAlign(TextAlign.Center)
      .fontSize(Font.body)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.isEnabled ? '#FFFFFF' : Color.muted2)
      .backgroundColor(this.isEnabled ? Color.green : Color.line)
      .borderRadius(16)
      .onClick(() => {
        if (this.isEnabled) {
          this.onTap();
        }
      })
  }
}
