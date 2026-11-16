/**
 * 胶囊状态：与产品文档「草稿 / 待开启 / 已开启」三态一致。
 * 文档里的「已封存」与「待开启」语义重叠，此处合并为 PENDING。
 */
export enum CapsuleStatus {
  /** 草稿：内容还没写完，用户还可以改 */
  Draft = 'draft',
  /** 待开启：已封存，内容不可读，等到点才解锁 */
  Pending = 'pending',
  /** 已开启：到期后读过，内容保持只读 */
  Opened = 'opened'
}

/** 内容块类型：对应 F3 多形态内容 */
export enum BlockType {
  Text = 'text',
  Image = 'image',
  Audio = 'audio'
}

export interface ContentBlock {
  id: string;
  type: BlockType;
  /** 文字内容；图片为本地 uri 列表的 JSON；语音为空 */
  text?: string;
  /** 图片本地 uri（可多张） */
  uris?: string[];
  /** 语音本地 uri */
  audioUri?: string;
  /** 语音时长（秒） */
  duration?: number;
  /** 同一胶囊内的排序 */
  order: number;
}

export interface Capsule {
  id: string;
  title: string;
  status: CapsuleStatus;
  /** 创建时间（毫秒时间戳） */
  createdAt: number;
  /** 预定开启时间（毫秒时间戳） */
  openAt: number;
  /** 实际开启时间，仅 Opened 有值 */
  openedAt?: number;
  /** 内容块，按 order 升序 */
  blocks: ContentBlock[];
  /** 是否已经提醒过 */
  notified: boolean;
}

/** 首页分组标签 */
export enum CapsuleTab {
  Pending = 0,
  Opened = 1,
  Draft = 2
}
