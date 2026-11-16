import { Color, Font, Size } from '../common/Tokens';
import { Capsule, CapsuleStatus, CapsuleTab } from '../model/Capsule';
import { TimeUtil } from '../common/TimeUtil';
import { CapsuleCard } from '../view/CapsuleCard';

/**
 * 首页 · 胶囊架（F4）
 * 三组标签：待开启 / 已开启 / 草稿。到期卡片置顶并高亮。
 */
@Component
export struct HomePage {
  @Link capsules: Capsule[];
  /** 由根页面每 30 秒推一次，「今天到期」才会在打开着的时候自己翻过来 */
  @Prop nowMs: number = 0;
  @State tab: CapsuleTab = CapsuleTab.Pending;
  /**
   * 外部（根页面）想强制回到「待开启」时把这个数加一。
   * 典型场景：刚封存完一个胶囊，用户必须立刻在待开启列表里看到它，
   * 而不是还停在草稿标签页上以为没封进去。
   */
  @Prop @Watch('onResetTokenChanged') resetToken: number = 0;
  onNewCapsule: () => void = () => {};
  onOpenCapsule: (c: Capsule) => void = () => {};

  private onResetTokenChanged(propName: string): void {
    this.tab = CapsuleTab.Pending;
  }

  private filterByTab(tab: CapsuleTab): Capsule[] {
    const list = this.capsules.filter((c: Capsule) => {
      if (tab === CapsuleTab.Pending) {
        return c.status === CapsuleStatus.Pending;
      }
      if (tab === CapsuleTab.Opened) {
        return c.status === CapsuleStatus.Opened;
      }
      return c.status === CapsuleStatus.Draft;
    });
    if (tab === CapsuleTab.Pending) {
      // 到期在前，其次按距离开启时间由近到远
      list.sort((a: Capsule, b: Capsule) => a.openAt - b.openAt);
    } else if (tab === CapsuleTab.Opened) {
      list.sort((a: Capsule, b: Capsule) => (b.openedAt ?? 0) - (a.openedAt ?? 0));
    }
    return list;
  }

  private countOf(tab: CapsuleTab): number {
    return this.filterByTab(tab).length;
  }

  private dueCount(): number {
    return this.capsules.filter((c: Capsule) =>
      c.status === CapsuleStatus.Pending && TimeUtil.isDue(c.openAt, this.nowMs)).length;
  }

  /**
   * 副标题。空列表和「一个约定都没了」要说不同的话：
   * 后者意味着胶囊都开完了，不该再显示「还没有和未来约定过什么」。
   */
  private subtitle(): string {
    const pending = this.countOf(CapsuleTab.Pending);
    const due = this.dueCount();
    const drafts = this.countOf(CapsuleTab.Draft);
    if (due > 0) {
      return `${due} 个约定已经到时间了`;
    }
    if (pending > 0) {
      return `还有 ${pending} 个约定在时间里等着`;
    }
    if (this.countOf(CapsuleTab.Opened) > 0) {
      return '打开的都在下面，要不要再写一封';
    }
    // 只有草稿时不能再说"还没有约定过"——草稿就是写了一半的约定
    if (drafts > 0) {
      return `${drafts} 篇还没封存的草稿，随时可以接着写`;
    }
    return '还没有和未来约定过什么';
  }

  @Builder
  tabItem(tab: CapsuleTab, label: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(Font.body)
          .fontWeight(this.tab === tab ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.tab === tab ? Color.ink : Color.muted)
        if (this.countOf(tab) > 0) {
          Text(`${this.countOf(tab)}`)
            .fontSize(10)
            .fontColor(this.tab === tab ? Color.green : Color.muted2)
            .margin({ left: 3, bottom: 7 })
        }
      }
      .height(40)

      Row()
        .width(this.tab === tab ? 22 : 0)
        .height(2.5)
        .backgroundColor(Color.green)
        .borderRadius(2)
    }
    .margin({ right: 26 })
    .onClick(() => {
      this.tab = tab;
    })
  }

  @Builder
  emptyState() {
    Column() {
      Column()
        .width(96)
        .height(96)
        .borderRadius(48)
        .border({ width: 1.5, color: Color.dash, style: BorderStyle.Dashed })
        .margin({ top: 96 })

      Text('时间还没有开始')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.ink)
        .margin({ top: 24 })

      Text('写下此刻想说的话\n交给未来某一天的自己')
        .fontSize(Font.caption)
        .fontColor(Color.muted)
        .textAlign(TextAlign.Center)
        .lineHeight(22)
        .margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      // 顶部：大标题 + 副标题
      Column() {
        Text('我的胶囊')
          .fontSize(Font.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.ink)
          .width('100%')

        Text(this.subtitle())
          .fontSize(Font.caption)
          .fontColor(Color.muted)
          .margin({ top: 6 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: Size.pageH, right: Size.pageH, top: 16, bottom: 8 })

      // 分组标签
      Row() {
        this.tabItem(CapsuleTab.Pending, '待开启')
        this.tabItem(CapsuleTab.Opened, '已开启')
        this.tabItem(CapsuleTab.Draft, '草稿')
      }
      .width('100%')
      .padding({ left: Size.pageH, right: Size.pageH })

      // 列表
      if (this.countOf(this.tab) === 0) {
        this.emptyState()
      } else {
        List({ space: 12 }) {
          ForEach(this.filterByTab(this.tab), (item: Capsule) => {
            ListItem() {
              CapsuleCard({
                capsule: item,
                nowMs: this.nowMs,
                onOpen: (c: Capsule) => this.onOpenCapsule(c)
              })
            }
          }, (item: Capsule) => item.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Size.pageH, right: Size.pageH, top: 16 })
        .scrollBar(BarState.Off)
      }

      // 底部通栏新建按钮（底部 Tab 栏已由 Tabs 承担，这里只留 12 的间距）
      Column() {
        Text(this.capsules.length === 0 ? '+ 与时间的第一个约定' : '+ 与时间约定')
          .width('100%')
          .height(50)
          .textAlign(TextAlign.Center)
          .fontSize(Font.body)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor(Color.green)
          .borderRadius(16)
          .onClick(() => this.onNewCapsule())
      }
      .padding({ left: Size.pageH, right: Size.pageH, top: 12, bottom: 10 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.bg)
  }
}
