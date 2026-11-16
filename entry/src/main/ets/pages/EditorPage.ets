import { Color, Font, Size } from '../common/Tokens';
import { BlockType, Capsule, ContentBlock } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { NavBar, PrimaryButton } from '../view/CommonViews';
import { MediaRepo } from '../data/MediaRepo';
import { AudioService, RecordResult } from '../data/AudioService';
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
  /** 录音框是否显示 */
  @State showRecSheet: boolean = false;
  /** 录音框里已经录好的文件路径，空串表示还没录 */
  @State recSheetPath: string = '';
  /** 录音框里录好的时长（秒） */
  @State recSheetSecs: number = 0;
  /** 录音框里的提示（权限被拒、设备没有麦克风等） */
  @State recSheetError: string = '';
  /** 录音框要改写哪个已有的块；空串表示录完追加成新块 */
  @State recSheetEditId: string = '';
  onCancel: () => void = () => {};
  /**
   * 点取消时，如果已经写了东西，交给外层存成草稿。
   * 不自动存的话「草稿」这个分组永远是空的 —— 用户写了半篇关掉就没了。
   * 传空标题空内容时不存，避免每次点取消都留一条空气泡。
   */
  onSaveDraft: (title: string, blocks: ContentBlock[], openAt: number) => void =
    (title: string, blocks: ContentBlock[], openAt: number) => {};
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
    // 页面被销毁时录音可能还开着：停掉并把没人接手的那一段删掉，
    // 否则沙箱里会留一堆孤儿音频
    if (this.recording) {
      const pending = this.recSheetPath;
      AudioService.stop().then((r: RecordResult) => {
        if (pending.length > 0) {
          MediaRepo.removeQuietly(pending);
        }
        if (r.path.length > 0) {
          MediaRepo.removeQuietly(r.path);
        }
      });
    }
    AudioService.stopPlay();
  }

  private canSeal(): boolean {
    return this.title.trim().length > 0 && this.blocks.length > 0;
  }

  /**
   * 离开编辑器：写了东西就存草稿，什么都没写就直接退。
   * 判空看标题与内容块，两者都空视为没写过。
   */
  private leave(): void {
    const hasSomething = this.title.trim().length > 0 || this.blocks.length > 0;
    if (hasSomething) {
      this.onSaveDraft(this.title, this.blocks, this.draft.openAt);
    } else {
      this.onCancel();
    }
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

  // ---------------- 录音框 ----------------

  /** 打开录音框：editId 非空表示重录已有的块，否则是新的一块 */
  private openRecorder(editId: string): void {
    // 录音框已经开着（正在录）就不重入，否则 start/stop 会打架
    if (this.showRecSheet && this.recording) {
      return;
    }
    this.recSheetEditId = editId;
    this.recSheetPath = '';
    this.recSheetSecs = 0;
    this.recSheetError = '';
    this.recordSecs = 0;
    this.showRecSheet = true;
  }

  private async closeRecorder(): Promise<void> {
    // 必须 await：stopRecord 是异步的，不等待的话 recSheetPath 还没填上就开始删，
    // 结果文件留在沙箱里没人清（取消录音后文件残留就是这么来的）。
    if (this.recording) {
      await this.stopRecord();
    }
    // 关掉时把没确认的录音文件删掉，避免沙箱里攒一堆废弃音频
    if (this.recSheetPath.length > 0) {
      MediaRepo.removeQuietly(this.recSheetPath);
    }
    this.recSheetPath = '';
    this.recSheetSecs = 0;
    this.recSheetError = '';
    this.recSheetEditId = '';
    this.showRecSheet = false;
  }

  /** 录音框里的圆钮：点一次开始，再点一次结束 */
  private async toggleSheetRecord(): Promise<void> {
    if (this.recording) {
      this.stopRecord();
      return;
    }
    // 已经有录好的文件时，再点就是重录 —— 先清掉旧的
    if (this.recSheetPath.length > 0) {
      MediaRepo.removeQuietly(this.recSheetPath);
      this.recSheetPath = '';
      this.recSheetSecs = 0;
    }
    const granted = await PermService.ensureMicrophone();
    if (!granted) {
      this.recSheetError = '没有麦克风权限，去设置里打开后再试';
      return;
    }
    try {
      await AudioService.start();
      this.recording = true;
      this.recordSecs = 0;
      this.recSheetError = '';
      this.startTimer();
    } catch (e) {
      this.recording = false;
      this.recSheetError = '这台设备没能打开麦克风，录音不可用';
    }
  }

  /** 结束录音，把结果放进录音框（此时还没提交到内容块） */
  private async stopRecord(): Promise<void> {
    const result = await AudioService.stop();
    this.stopTimer();
    this.recording = false;
    this.recordSecs = 0;
    if (result.path.length === 0) {
      this.recSheetError = '这次没录到声音，再试一次';
      return;
    }
    this.recSheetPath = result.path;
    this.recSheetSecs = result.duration;
    this.recSheetError = '';
  }

  /** 确认使用这段录音：重录则改已有块，否则追加新块 */
  private confirmRecording(): void {
    if (this.recSheetPath.length === 0) {
      return;
    }
    const path = this.recSheetPath;
    const secs = this.recSheetSecs;
    if (this.recSheetEditId.length > 0) {
      this.patchBlock(this.recSheetEditId, (b: ContentBlock) => {
        // 换掉旧文件，别在沙箱里留垃圾
        if (b.audioUri !== undefined && b.audioUri.length > 0 && b.audioUri !== path) {
          MediaRepo.removeQuietly(b.audioUri);
        }
        b.audioUri = path;
        b.duration = secs;
      });
    } else {
      const block: ContentBlock = {
        id: `blk_${Date.now()}_${this.blocks.length}`,
        type: BlockType.Audio,
        audioUri: path,
        duration: secs,
        order: this.blocks.length
      };
      this.commit(this.blocks.concat([block]));
    }
    // 文件已经被内容块接手，不能再让 closeRecorder 删掉
    this.recSheetPath = '';
    this.recSheetSecs = 0;
    this.recSheetEditId = '';
    this.showRecSheet = false;
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
    Stack() {
      Column() {
        NavBar({
          title: '约定时间',
          leftText: '取消',
          rightText: '封存',
          rightEnabled: this.canSeal(),
          onLeft: () => this.leave(),
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
            // key 里带上 duration：重录会用同一个 block.id 换掉音频，
            // 只按 id 做 key 的话 ArkUI 会复用旧组件不重建，
            // 界面上时长就一直停在录音入前的旧值。
            // 文字 / 图片块的 duration 恒为 undefined → 0，key 保持稳定，
            // 输入文字时不会被打断。
            ForEach(this.blocks, (block: ContentBlock) => {
              this.blockView(block)
            }, (block: ContentBlock) => `${block.id}_${block.duration === undefined ? 0 : block.duration}`)

            // 添加按钮组。语音不再原地开录，而是先弹录音框
            Row() {
              this.addButton('+ 文字', () => this.addText())
              this.addButton('+ 图片', () => { this.addImages(); })
              this.addButton('+ 语音', () => this.openRecorder(''))
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

      // 录音框：盖在编辑器上方，遮罩吃掉点击
      if (this.showRecSheet) {
        this.recordSheet()
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 录音框（底部弹层）。
   *
   * 为什么不直接用 bindSheet：这个页面本身是 NavDestination 压栈打开的，
   * bindSheet 挂在 Navigation 上会被 NavDestination 盖住（封存弹层踩过同样的坑），
   * 所以这里用 Stack + 手写遮罩。
   */
  @Builder
  recordSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => { this.closeRecorder(); })

      Column() {
        // 顶部小横条
        Row()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor(Color.line)
          .margin({ top: 8, bottom: 14 })

        Text(this.recSheetEditId.length > 0 ? '重录这段语音' : '录一段语音')
          .fontSize(Font.section)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.ink)

        Text(this.recording ? '正在录音，说完再点一下按钮' : (this.recSheetPath.length > 0 ? '不满意可以再点一次重录' : '点下面的按钮开始'))
          .fontSize(Font.tiny)
          .fontColor(Color.muted)
          .margin({ top: 6 })

        // 主按钮：开始 / 结束
        Stack() {
          if (this.recording) {
            // 录音中：方块 = 停止
            Row()
              .width(26)
              .height(26)
              .borderRadius(5)
              .backgroundColor(Color.warmInk)
          } else {
            // 待录 / 已录：圆点 = 开始
            Row()
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(Color.green)
          }
        }
        .width(84)
        .height(84)
        .borderRadius(42)
        .backgroundColor(Color.greenSoft)
        .margin({ top: 22, bottom: 14 })
        .onClick(() => {
          this.toggleSheetRecord();
        })

        Text(this.recording
          ? TimeUtil.clock(this.recordSecs)
          : (this.recSheetPath.length > 0 ? TimeUtil.clock(this.recSheetSecs) : '0:00'))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.recording ? Color.warmInk : Color.ink)

        if (this.recSheetError.length > 0) {
          Text(this.recSheetError)
            .fontSize(Font.tiny)
            .fontColor(Color.warmInk)
            .margin({ top: 8 })
            .padding({ left: 16, right: 16 })
            .textAlign(TextAlign.Center)
        }

        // 底部两个动作
        Row() {
          Text('取消')
            .fontSize(Font.body)
            .fontColor(Color.muted)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(48)
            .onClick(() => { this.closeRecorder(); })

          Text(this.recSheetEditId.length > 0 ? '换这一条' : '用这一段')
            .fontSize(Font.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.recSheetPath.length > 0 && !this.recording ? Color.green : Color.muted2)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(48)
            .onClick(() => {
              if (this.recording) {
                return;
              }
              this.confirmRecording();
            })
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('100%')
      .padding({ left: Size.pageH, right: Size.pageH, bottom: 26 })
      .backgroundColor(Color.bg)
      .borderRadius({ topLeft: Size.radiusSheet, topRight: Size.radiusSheet })
      .transition(TransitionEffect.translate({ y: 420 }).animation({ duration: 240, curve: Curve.FastOutSlowIn }))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  blockView(block: ContentBlock) {
    Column() {
      if (block.type === BlockType.Text) {
        // 不设 lineHeight、不复位 padding：
        // 之前 .lineHeight(24) + .padding(0) 会把首行基线顶到卡片上沿，
        // 占位文案的上升部直接被裁掉（用户反馈「提示字被遮挡」）。
        TextArea({ text: block.text === undefined ? '' : block.text, placeholder: '写下此刻想说的话…' })
          .fontSize(Font.body)
          .fontColor(Color.ink)
          .placeholderColor(Color.muted2)
          .backgroundColor('#00000000')
          .padding({ top: 6, bottom: 6, left: 0, right: 0 })
          .constraintSize({ minHeight: 60 })
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
      } else {        // 语音：内嵌播放条，不跳页
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

          // 只认这一块自己的 duration。
          // 之前这里写的是 `this.recording ? 录音中 ${this.recordSecs} : ...`，
          // recording/recordSecs 是页面级状态，于是新录一条时
          // 列表里所有语音块都跟着显示新录音的计时 —— 就是这个 bug 的来源。
          Text(block.duration === undefined ? '没有录到声音' : TimeUtil.clock(block.duration))
            .fontSize(Font.caption)
            .fontColor(block.duration === undefined ? Color.muted2 : Color.ink2)
            .margin({ left: 10 })

          Blank()

          Text('重录')
            .fontSize(Font.tiny)
            .fontColor(Color.muted)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => { this.openRecorder(block.id); })

          Text('删除')
            .fontSize(Font.tiny)
            .fontColor(Color.muted2)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ left: 4 })
            .onClick(() => { this.removeBlock(block.id); })
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
