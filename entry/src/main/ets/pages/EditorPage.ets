import { Color, Font, Size } from '../common/Tokens';
import { BlockType, Capsule, ContentBlock } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { NavBar, PrimaryButton } from '../view/CommonViews';
import { MediaRepo } from '../data/MediaRepo';
import { AudioService } from '../data/AudioService';
import { PermService } from '../data/PermService';

/**
 * 约定时间 · 编辑器（新建 / 编辑草稿）
 * 顶部导航：左取消、右封存；开启时间可点，弹日期 + 时间两级选择；
 * 内容区三种块：文字直接写、图片走相册、语音现场录。
 */
@Component
export struct EditorPage {
  /** 传入草稿则进入编辑态 */
  @Link draft: Capsule;
  /**
   * 内容块的本地副本。
   * @Link 只观察顶层重新赋值，直接 push 进 draft.blocks 不会触发刷新，
   * 所以这里用独立 @State 数组承载渲染，改动后整体替换再回写到 draft。
   */
  @State blocks: ContentBlock[] = [];
  @State title: string = '';
  /** 录音中 */
  @State recording: boolean = false;
  /** 录音已进行的秒数（用于计时显示） */
  @State recordSecs: number = 0;
  /** 正在播放的块 id，空串表示没在播 */
  @State playingId: string = '';
  onCancel: () => void = () => {};
  /**
   * 点击封存 → 由外层弹出封存确认弹层。
   * 这里把标题、内容块、开启时间一并交出去，而不是让外层去读 this.draft：
   * 编辑器内部对 blocks 用的是整体替换（this.blocks = next），
   * 回写的 this.draft.blocks 在外层不一定能及时被观察到（实测封存后正文为空就是这个原因）。
   */
  onRequestSeal: (title: string, blocks: ContentBlock[], openAt: number) => void =
    (title: string, blocks: ContentBlock[], openAt: number) => {};

  private timer: number = -1;

  aboutToAppear(): void {
    this.title = this.draft.title;
    this.blocks = this.draft.blocks.slice();
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    AudioService.stopPlay();
  }

  private canSeal(): boolean {
    return this.title.trim().length > 0 && this.blocks.length > 0;
  }

  /** 整体替换数组以触发刷新，再回写给外层草稿 */
  private commit(next: ContentBlock[]): void {
    this.blocks = next;
    this.draft.blocks = this.blocks;
  }

  private patchBlock(id: string, apply: (b: ContentBlock) => void): void {
    const next: ContentBlock[] = [];
    for (const b of this.blocks) {
      if (b.id === id) {
        apply(b);
      }
      next.push(b);
    }
    this.commit(next);
  }

  private removeBlock(id: string): void {
    this.commit(this.blocks.filter((b: ContentBlock) => b.id !== id));
  }

  // ---------------- 时间选择 ----------------

  private pickOpenAt(): void {
    const cur = new Date(this.draft.openAt);
    this.getUIContext().showDatePickerDialog({
      start: new Date(Date.now() + TimeUtil.DAY),
      end: new Date(Date.now() + 365 * 40 * TimeUtil.DAY),
      selected: cur,
      onDateAccept: (picked: Date) => {
        // 先定日期，再弹时间；两级选择比一个混合 picker 更好点
        this.getUIContext().showTimePickerDialog({
          selected: new Date(this.draft.openAt),
          useMilitaryTime: true,
          onAccept: (value: TimePickerResult) => {
            const hh = value.hour === undefined ? 9 : value.hour;
            const mm = value.minute === undefined ? 0 : value.minute;
            const merged = new Date(picked.getFullYear(), picked.getMonth(), picked.getDate(), hh, mm, 0, 0);
            this.draft.openAt = merged.getTime();
            this.draft.openAt = this.draft.openAt;
          }
        });
      }
    });
  }

  // ---------------- 内容块 ----------------

  private addText(): void {
    const block: ContentBlock = {
      id: `blk_${Date.now()}_${this.blocks.length}`,
      type: BlockType.Text,
      text: '',
      order: this.blocks.length
    };
    this.commit(this.blocks.concat([block]));
  }

  private async addImages(): Promise<void> {
    try {
      const picked = await MediaRepo.pickImages(9);
      if (picked.length === 0) {
        return;
      }
      const block: ContentBlock = {
        id: `blk_${Date.now()}_${this.blocks.length}`,
        type: BlockType.Image,
        uris: picked,
        order: this.blocks.length
      };
      this.commit(this.blocks.concat([block]));
    } catch (e) {
      // 用户取消选择
    }
  }

  private async appendImages(blockId: string): Promise<void> {
    try {
      const picked = await MediaRepo.pickImages(9);
      if (picked.length === 0) {
        return;
      }
      this.patchBlock(blockId, (b: ContentBlock) => {
        const old = b.uris === undefined ? [] : b.uris;
        b.uris = old.concat(picked);
      });
    } catch (e) {
      // 用户取消选择
    }
  }

  /** 语音块：点一次开始录，再点一次停止 */
  private async toggleRecord(blockId: string): Promise<void> {
    if (this.recording) {
      const result = await AudioService.stop();
      this.stopTimer();
      this.recording = false;
      this.recordSecs = 0;
      if (result.path.length === 0) {
        return;
      }
      this.patchBlock(blockId, (b: ContentBlock) => {
        b.audioUri = result.path;
        b.duration = result.duration;
      });
      return;
    }
    const granted = await PermService.ensureMicrophone();
    if (!granted) {
      return;
    }
    // 语音块先占位进列表，录完再写 uri
    if (this.blocks.findIndex((b: ContentBlock) => b.id === blockId) < 0) {
      const block: ContentBlock = {
        id: blockId,
        type: BlockType.Audio,
        order: this.blocks.length
      };
      this.commit(this.blocks.concat([block]));
    }
    try {
      await AudioService.start();
      this.recording = true;
      this.recordSecs = 0;
      this.startTimer();
    } catch (e) {
      this.recording = false;
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timer = setInterval(() => {
      this.recordSecs = AudioService.elapsedSeconds();
    }, 500);
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
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

  // ---------------- 视图 ----------------

  @Builder
  addButton(label: string, onTap: () => void) {
    Text(label)
      .height(36)
      .padding({ left: 14, right: 14 })
      .fontSize(Font.caption)
      .fontColor(Color.muted)
      .borderRadius(18)
      .border({ width: 1, color: Color.dash, style: BorderStyle.Dashed })
      .margin({ right: 8 })
      .onClick(onTap)
  }

  build() {
    Column() {
      NavBar({
        title: '约定时间',
        leftText: '取消',
        rightText: '封存',
        rightEnabled: this.canSeal(),
        onLeft: () => this.onCancel(),
        onRight: () => this.onRequestSeal(this.title, this.blocks, this.draft.openAt)
      })

      Scroll() {
        Column() {
          // 标题输入
          TextInput({ text: this.title, placeholder: '给这一刻起个名字' })
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.ink)
            .placeholderColor(Color.muted2)
            .backgroundColor('#00000000')
            .padding(0)
            .height(56)
            .width('100%')
            .onChange((v: string) => {
              this.title = v;
              this.draft.title = v;
            })

          Divider().color(Color.line).strokeWidth(1)

          // 开启时间（可点，右对齐绿色加粗 + chevron）
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
          .onClick(() => this.pickOpenAt())

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
          ForEach(this.blocks, (block: ContentBlock) => {
            this.blockView(block)
          }, (block: ContentBlock) => block.id)

          // 添加按钮组
          Row() {
            this.addButton('+ 文字', () => this.addText())
            this.addButton('+ 图片', () => { this.addImages(); })
            this.addButton('+ 语音', () => { this.toggleRecord(`blk_${Date.now()}`); })
          }
          .width('100%')
          .margin({ top: 8, bottom: 24 })
        }
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Size.pageH, right: Size.pageH, top: 8 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Column() {
        PrimaryButton({
          label: '封存胶囊',
          isEnabled: this.canSeal(),
          onTap: () => this.onRequestSeal(this.title, this.blocks, this.draft.openAt)
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
        TextArea({ text: block.text === undefined ? '' : block.text, placeholder: '写下此刻想说的话…' })
          .fontSize(Font.body)
          .fontColor(Color.ink)
          .placeholderColor(Color.muted2)
          .lineHeight(24)
          .backgroundColor('#00000000')
          .padding(0)
          .constraintSize({ minHeight: 44 })
          .width('100%')
          .onChange((v: string) => {
            this.patchBlock(block.id, (b: ContentBlock) => {
              b.text = v;
            });
          })
      } else if (block.type === BlockType.Image) {
        Flex({ wrap: FlexWrap.Wrap }) {
          if (block.uris !== undefined) {
            ForEach(block.uris!, (uri: string) => {
              Image(MediaRepo.toDisplayUri(uri))
                .width(72)
                .height(72)
                .borderRadius(10)
                .objectFit(ImageFit.Cover)
                .margin({ right: 8, bottom: 8 })
            }, (uri: string) => uri)
          }
          Row() {
            Text('+').fontSize(20).fontColor(Color.muted2)
          }
          .width(72)
          .height(72)
          .justifyContent(FlexAlign.Center)
          .borderRadius(10)
          .border({ width: 1, color: Color.dash, style: BorderStyle.Dashed })
          .margin({ bottom: 8 })
          .onClick(() => { this.appendImages(block.id); })
        }
        .width('100%')
      } else {        // 语音：内嵌进度条，不跳页
        Row() {
          Text(this.playingId === block.id ? '❚❚' : '▶')
            .fontSize(12)
            .fontColor(Color.green)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .backgroundColor(Color.greenSoft)
            .borderRadius(15)
            .onClick(() => { this.playBlock(block); })

          Text(this.recording
            ? `录音中 ${TimeUtil.clock(this.recordSecs)}`
            : (block.duration === undefined ? '点左侧按钮开始录音' : TimeUtil.clock(block.duration)))
            .fontSize(Font.caption)
            .fontColor(block.duration === undefined && !this.recording ? Color.muted2 : Color.ink2)
            .margin({ left: 10 })

          Blank()

          if (block.duration !== undefined && !this.recording) {
            Text('重录')
              .fontSize(Font.tiny)
              .fontColor(Color.muted)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => { this.toggleRecord(block.id); })
          }
        }
        .width('100%')
        .height(54)
        .padding({ left: 12, right: 12 })
        .backgroundColor(Color.card)
        .borderRadius(12)
        .border({ width: 1, color: Color.line })
      }

      if (block.type === BlockType.Text) {
        Row() {
          Blank()
          Text('删除')
            .fontSize(Font.tiny)
            .fontColor(Color.muted2)
            .onClick(() => this.removeBlock(block.id))
        }
        .width('100%')
        .margin({ top: 4 })
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
