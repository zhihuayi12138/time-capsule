import { Color, Font, Size } from '../common/Tokens';
import { BlockType, Capsule, CapsuleStatus, ContentBlock } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { NavBar, PrimaryButton } from '../view/CommonViews';

/**
 * 约定时间 · 编辑器（新建 / 编辑草稿）
 * 顶部导航：左取消、右封存；开启时间右对齐绿色加粗；内容区三个虚线添加按钮。
 */
@Component
export struct EditorPage {
  /** 传入草稿则进入编辑态 */
  @Link draft: Capsule;
  onCancel: () => void = () => {};
  /** 点击封存 → 由外层弹出封存确认弹层 */
  onRequestSeal: () => void = () => {};

  private canSeal(): boolean {
    return this.draft.title.trim().length > 0 && this.draft.blocks.length > 0;
  }

  private addBlock(type: BlockType): void {
    const order = this.draft.blocks.length;
    const block: ContentBlock = {
      id: `blk_${Date.now()}_${order}`,
      type: type,
      order: order
    };
    if (type === BlockType.Text) {
      block.text = '';
    }
    this.draft.blocks.push(block);
  }

  @Builder
  addButton(label: string, type: BlockType) {
    Text(label)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(Font.caption)
      .fontColor(Color.muted)
      .borderRadius(18)
      .border({ width: 1, color: Color.dash, style: BorderStyle.Dashed })
      .margin({ right: 8 })
      .onClick(() => this.addBlock(type))
  }

  build() {
    Column() {
      NavBar({
        title: '约定时间',
        leftText: '取消',
        rightText: '封存',
        rightEnabled: this.canSeal(),
        onLeft: () => this.onCancel(),
        onRight: () => this.onRequestSeal()
      })

      Scroll() {
        Column() {
          // 标题输入
          TextInput({ text: this.draft.title, placeholder: '给这一刻起个名字' })
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.ink)
            .placeholderColor(Color.muted2)
            .backgroundColor('#00000000')
            .padding(0)
            .height(56)
            .width('100%')
            .onChange((v: string) => {
              this.draft.title = v;
            })

          Divider().color(Color.line).strokeWidth(1)

          // 开启时间（右对齐绿色加粗 + chevron）
          Row() {
            Text('开启时间')
              .fontSize(Font.body)
              .fontColor(Color.ink2)
            Blank()
            Text(TimeUtil.format(this.draft.openAt))
              .fontSize(Font.body)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.green)
            Text('›')
              .fontSize(18)
              .fontColor(Color.muted2)
              .margin({ left: 4 })
          }
          .width('100%')
          .height(52)

          // 创建时间（只读）
          Row() {
            Text('创建时间')
              .fontSize(Font.body)
              .fontColor(Color.ink2)
            Blank()
            Text(TimeUtil.format(this.draft.createdAt))
              .fontSize(Font.caption)
              .fontColor(Color.muted2)
          }
          .width('100%')
          .height(48)

          Divider().color(Color.line).strokeWidth(1).margin({ top: 4, bottom: 16 })

          // 内容块
          ForEach(this.draft.blocks, (block: ContentBlock) => {
            this.blockView(block)
          }, (block: ContentBlock) => block.id)

          // 添加按钮组
          Row() {
            this.addButton('+ 文字', BlockType.Text)
            this.addButton('+ 图片', BlockType.Image)
            this.addButton('+ 语音', BlockType.Audio)
          }
          .width('100%')
          .margin({ top: 8, bottom: 24 })
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Size.pageH, right: Size.pageH, top: 8 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Column() {
        PrimaryButton({
          label: '封存胶囊',
          isEnabled: this.canSeal(),
          onTap: () => this.onRequestSeal()
        })
      }
      .padding({ left: Size.pageH, right: Size.pageH, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }

  @Builder
  blockView(block: ContentBlock) {
    Column() {
      if (block.type === BlockType.Text) {
        Text(block.text === undefined || block.text!.length === 0 ? '写下此刻想说的话…' : block.text!)
          .fontSize(Font.body)
          .fontColor(block.text === undefined || block.text!.length === 0 ? Color.muted2 : Color.ink)
          .lineHeight(24)
          .width('100%')
      } else if (block.type === BlockType.Image) {
        Row() {
          if (block.uris !== undefined) {
            ForEach(block.uris!, (uri: string) => {
              // 占位：接入 photoAccessHelper 后替换为 Image(uri)
              Row().width(72).height(72).backgroundColor(Color.line).borderRadius(10).margin({ right: 8 })
            }, (uri: string) => uri)
          }
          Row()
            .width(72)
            .height(72)
            .borderRadius(10)
            .border({ width: 1, color: Color.dash, style: BorderStyle.Dashed })
          Blank()
        }
        .width('100%')
      } else {
        // 语音：内嵌进度条，不跳页
        Row() {
          Text('▶')
            .fontSize(12)
            .fontColor(Color.green)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .backgroundColor(Color.greenSoft)
            .borderRadius(14)
          Row()
            .width(block.duration === undefined ? 0 : Math.min(120, (block.duration!) * 3))
            .height(3)
            .backgroundColor(Color.green)
            .borderRadius(2)
            .margin({ left: 10 })
          Text(block.duration === undefined ? '0:00' : `0:${block.duration!}`)
            .fontSize(Font.tiny)
            .fontColor(Color.muted)
            .margin({ left: 8 })
          Blank()
        }
        .width('100%')
        .height(48)
        .padding({ left: 10, right: 10 })
        .backgroundColor(Color.card)
        .borderRadius(12)
        .border({ width: 1, color: Color.line })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(block.type === BlockType.Text ? Color.card : '#00000000')
    .borderRadius(Size.radiusCard)
    .border({
      width: block.type === BlockType.Text ? 1 : 0,
      color: Color.line
    })
    .margin({ bottom: 12 })
  }
}
