import { fileIo as fs } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { AppCtx } from '../common/AppCtx';
import { BlockType, Capsule, CapsuleStatus, ContentBlock } from '../model/Capsule';
import { CapsuleRepo } from './CapsuleRepo';
import { MediaRepo } from './MediaRepo';

/**
 * 备份与恢复（F5）。
 *
 * 备份产物是一个 zip：
 *   capsules.json      —— 全部胶囊元数据 + 内容块（含媒体文件的相对文件名）
 *   media/<文件名>      —— 被引用到的图片 / 语音
 *
 * 只打包"被引用到的"媒体，避免把删掉的残留文件也带走。
 */
export class BackupService {
  /** 当前备份格式版本，将来结构变化时可据此兼容旧包 */
  static readonly FORMAT_VERSION: number = 1;

  // ---------------- 导出 ----------------

  /**
   * 导出备份。
   * 返回值：用户选择的最终文件路径；用户取消时返回空串。
   */
  static async exportAll(): Promise<string> {
    const staging = `${AppCtx.exportDir()}/staging`;
    BackupService.resetDir(staging);
    const mediaDir = `${staging}/media`;
    BackupService.ensureDir(mediaDir);

    const list = await CapsuleRepo.listAll();
    const used: string[] = [];
    for (const c of list) {
      for (const b of c.blocks) {
        if (b.uris !== undefined) {
          for (const u of b.uris) {
            BackupService.pushUnique(used, u);
          }
        }
        if (b.audioUri !== undefined && b.audioUri.length > 0) {
          BackupService.pushUnique(used, b.audioUri);
        }
      }
    }

    // 媒体文件只按文件名归档，capsules.json 里也写文件名，
    // 这样恢复时不用关心原设备的绝对路径。
    const nameMap: Map<string, string> = new Map();
    for (const path of used) {
      const name = BackupService.baseName(path);
      if (name.length === 0) {
        continue;
      }
      try {
        fs.copyFileSync(path, `${mediaDir}/${name}`);
        nameMap.set(path, name);
      } catch (e) {
        // 文件已丢失就跳过，不阻断整体备份
      }
    }

    const payload = BackupService.serialize(list, nameMap);
    MediaRepo.writeText(staging, 'capsules.json', payload);

    const zipPath = `${AppCtx.exportDir()}/timecapsule_${BackupService.stamp()}.zip`;
    BackupService.removeQuietly(zipPath);
    await zlib.compressFile(staging, zipPath, {
      level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION
    });

    // 交给系统文件选择器，让用户放到自己找得到的地方
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`时间胶囊备份_${BackupService.stamp()}.zip`];
    options.fileSuffixChoices = ['.zip'];
    const viewPicker = new picker.DocumentViewPicker(AppCtx.get());
    const uris = await viewPicker.save(options);
    if (uris.length === 0) {
      return '';
    }
    const dest = uris[0];
    const src = fs.openSync(zipPath, fs.OpenMode.READ_ONLY);
    try {
      const out = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, out.fd);
      } finally {
        fs.closeSync(out);
      }
    } finally {
      fs.closeSync(src);
    }
    return dest;
  }

  // ---------------- 恢复 ----------------

  /**
   * 从备份文件恢复。
   * 注意：这是"整库替换"语义 —— 先清空当前数据，再写入备份内容。
   */
  static async importFrom(): Promise<ImportResult> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.zip'];
    const viewPicker = new picker.DocumentViewPicker(AppCtx.get());
    const uris = await viewPicker.select(options);
    if (uris.length === 0) {
      return { ok: false, count: 0, message: '没有选择文件' };
    }

    const work = `${AppCtx.exportDir()}/restore`;
    BackupService.resetDir(work);
    BackupService.ensureDir(work);
    const zipLocal = `${work}/backup.zip`;
    const src = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
    try {
      const out = fs.openSync(zipLocal, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.copyFileSync(src.fd, out.fd);
      } finally {
        fs.closeSync(out);
      }
    } finally {
      fs.closeSync(src);
    }

    const unzipped = `${work}/unzipped`;
    BackupService.ensureDir(unzipped);
    await zlib.decompressFile(zipLocal, unzipped, {});

    const jsonPath = `${unzipped}/capsules.json`;
    if (!fs.accessSync(jsonPath)) {
      return { ok: false, count: 0, message: '备份文件不完整，找不到 capsules.json' };
    }
    const raw = MediaRepo.readText(jsonPath);
    const parsed = BackupService.deserialize(raw, `${unzipped}/media`);

    await CapsuleRepo.clearAll();
    await CapsuleRepo.saveAll(parsed);
    return { ok: true, count: parsed.length, message: '' };
  }

  // ---------------- 序列化 ----------------

  /**
   * 把胶囊列表序列化成 JSON。
   * 手写字符串而不是 JSON.stringify：ArkTS 里 Map 和可选字段的序列化行为不够直观，
   * 这里字段少、结构固定，手写更可控也更省心。
   */
  private static serialize(list: Capsule[], nameMap: Map<string, string>): string {
    const items: string[] = [];
    for (const c of list) {
      const blocks: string[] = [];
      for (const b of c.blocks) {
        const parts: string[] = [];
        parts.push(`"id":${BackupService.q(b.id)}`);
        parts.push(`"type":${BackupService.q(b.type)}`);
        parts.push(`"order":${b.order}`);
        if (b.text !== undefined) {
          parts.push(`"text":${BackupService.q(b.text)}`);
        }
        if (b.uris !== undefined) {
          const names: string[] = [];
          for (const u of b.uris) {
            const n = nameMap.get(u);
            names.push(BackupService.q(n === undefined ? '' : n));
          }
          parts.push(`"names":[${names.join(',')}]`);
        }
        if (b.duration !== undefined) {
          parts.push(`"duration":${b.duration}`);
        }
        blocks.push(`{${parts.join(',')}}`);
      }
      const head: string[] = [];
      head.push(`"id":${BackupService.q(c.id)}`);
      head.push(`"title":${BackupService.q(c.title)}`);
      head.push(`"status":${BackupService.q(c.status)}`);
      head.push(`"createdAt":${c.createdAt}`);
      head.push(`"openAt":${c.openAt}`);
      if (c.openedAt !== undefined) {
        head.push(`"openedAt":${c.openedAt}`);
      }
      head.push(`"notified":${c.notified ? 'true' : 'false'}`);
      head.push(`"blocks":[${blocks.join(',')}]`);
      items.push(`{${head.join(',')}}`);
    }
    return `{"formatVersion":${BackupService.FORMAT_VERSION},"exportedAt":${Date.now()},"capsules":[${items.join(',')}]}`;
  }

  /**
   * 还原胶囊列表。媒体文件名重新映射到本机沙箱的新路径。
   * 同一份备份在别的设备上恢复时，文件名可能撞上已有文件，所以统一重新生成。
   */
  private static deserialize(raw: string, mediaDir: string): Capsule[] {
    const root = JSON.parse(raw) as BackupRoot;
    const list: Capsule[] = [];
    if (root.capsules === undefined) {
      return list;
    }
    for (const c of root.capsules) {
      const blocks = c.blocks === undefined ? [] : c.blocks;
      const restored: Capsule = {
        id: c.id,
        title: c.title,
        status: BackupService.toStatus(c.status),
        createdAt: c.createdAt,
        openAt: c.openAt,
        openedAt: c.openedAt,
        blocks: [],
        notified: c.notified === true
      };
      for (const b of blocks) {
        const block: ContentBlock = {
          id: b.id,
          type: BackupService.toBlockType(b.type),
          order: b.order,
          text: b.text,
          duration: b.duration
        };
        if (b.type === 'image' && b.names !== undefined) {
          const out: string[] = [];
          for (const n of b.names) {
            const p = BackupService.reimport(`${mediaDir}/${n}`, 'img', n);
            if (p.length > 0) {
              out.push(p);
            }
          }
          block.uris = out;
        }
        if (b.type === 'audio' && b.names !== undefined && b.names.length > 0) {
          const p = BackupService.reimport(`${mediaDir}/${b.names[0]}`, 'voice', b.names[0]);
          if (p.length > 0) {
            block.audioUri = p;
          }
        }
        restored.blocks.push(block);
      }
      list.push(restored);
    }
    return list;
  }

  /** 备份文件里的状态字符串 → 枚举；无法识别时按草稿处理，避免把内容误当已开启 */
  private static toStatus(s: string): CapsuleStatus {
    if (s === CapsuleStatus.Pending) {
      return CapsuleStatus.Pending;
    }
    if (s === CapsuleStatus.Opened) {
      return CapsuleStatus.Opened;
    }
    return CapsuleStatus.Draft;
  }

  private static toBlockType(s: string): BlockType {
    if (s === BlockType.Image) {
      return BlockType.Image;
    }
    if (s === BlockType.Audio) {
      return BlockType.Audio;
    }
    return BlockType.Text;
  }

  /** 把备份里的媒体文件复制回沙箱，返回新路径（失败返回空串） */
  private static reimport(srcPath: string, kind: string, originalName: string): string {
    try {
      if (!fs.accessSync(srcPath)) {
        return '';
      }
    } catch (e) {
      return '';
    }
    MediaRepo.ensureDir();
    const ext = BackupService.extOf(originalName);
    const dest = `${AppCtx.mediaDir()}/${kind}_${Date.now()}_${Math.floor(Math.random() * 100000)}.${ext}`;
    try {
      fs.copyFileSync(srcPath, dest);
      return dest;
    } catch (e) {
      return '';
    }
  }

  // ---------------- 小工具 ----------------

  /** JSON 字符串转义（含控制字符） */
  private static q(s: string): string {
    let out = '"';
    for (let i = 0; i < s.length; i++) {
      const ch = s.charAt(i);
      if (ch === '"') {
        out += '\\"';
      } else if (ch === '\\') {
        out += '\\\\';
      } else if (ch === '\n') {
        out += '\\n';
      } else if (ch === '\r') {
        out += '\\r';
      } else if (ch === '\t') {
        out += '\\t';
      } else {
        out += ch;
      }
    }
    return `${out}"`;
  }

  private static baseName(path: string): string {
    const i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  private static extOf(name: string): string {
    const i = name.lastIndexOf('.');
    if (i < 0 || i >= name.length - 1) {
      return 'bin';
    }
    return name.substring(i + 1);
  }

  private static stamp(): string {
    const d = new Date();
    const p = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}`;
  }

  private static pushUnique(arr: string[], v: string): void {
    if (v.length === 0) {
      return;
    }
    if (arr.indexOf(v) < 0) {
      arr.push(v);
    }
  }

  private static ensureDir(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      // 已存在
    }
  }

  /** 清空并重建目录，避免上一次的残留混进这次备份 */
  private static resetDir(dir: string): void {
    BackupService.removeTree(dir);
    BackupService.ensureDir(dir);
  }

  private static removeTree(dir: string): void {
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
    } catch (e) {
      return;
    }
    try {
      const names = fs.listFileSync(dir);
      for (const n of names) {
        const p = `${dir}/${n}`;
        try {
          if (fs.statSync(p).isDirectory()) {
            BackupService.removeTree(p);
          } else {
            fs.unlinkSync(p);
          }
        } catch (e) {
          // 单个删不掉就跳过
        }
      }
      fs.rmdirSync(dir);
    } catch (e) {
      // 忽略
    }
  }

  private static removeQuietly(path: string): void {
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // 忽略
    }
  }
}

/** 备份文件的顶层结构 */
interface BackupRoot {
  formatVersion?: number;
  exportedAt?: number;
  capsules?: BackupCapsule[];
}

interface BackupCapsule {
  id: string;
  title: string;
  status: string;
  createdAt: number;
  openAt: number;
  openedAt?: number;
  notified?: boolean;
  blocks?: BackupBlock[];
}

interface BackupBlock {
  id: string;
  type: string;
  order: number;
  text?: string;
  /** 图片/语音在 zip 内的文件名 */
  names?: string[];
  duration?: number;
}

/** 恢复结果 */
export interface ImportResult {
  ok: boolean;
  count: number;
  message: string;
}
