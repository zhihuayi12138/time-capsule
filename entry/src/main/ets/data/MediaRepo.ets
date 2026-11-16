import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { AppCtx } from '../common/AppCtx';

/**
 * 媒体文件仓库：把用户选的图片 / 录的语音复制进应用沙箱。
 *
 * 为什么要复制：picker 返回的 uri 是"授权 uri"，卸载或清缓存后可能失效；
 * 而且胶囊要求"锁在时间里"，内容必须自己持有，不能依赖外部相册是否还在。
 */
export class MediaRepo {
  private static ensured: boolean = false;

  /** 确保 media 目录存在 */
  static ensureDir(): void {
    const dir = AppCtx.mediaDir();
    if (MediaRepo.ensured) {
      return;
    }
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      // 目录已存在时 mkdirSync 会抛，忽略即可
    }
    MediaRepo.ensured = true;
  }

  /** 生成沙箱内的目标路径 */
  private static targetPath(kind: string, ext: string): string {
    MediaRepo.ensureDir();
    const n = `${kind}_${Date.now()}_${Math.floor(Math.random() * 10000)}.${ext}`;
    return `${AppCtx.mediaDir()}/${n}`;
  }

  /** 从任意 uri 复制进沙箱，返回沙箱内的绝对路径 */
  static async importUri(sourceUri: string, kind: string, ext: string): Promise<string> {
    const dest = MediaRepo.targetPath(kind, ext);
    const src = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(src.fd, dest);
    } finally {
      fs.closeSync(src);
    }
    return dest;
  }

  /** 打开相册选图，返回沙箱内路径列表 */
  static async pickImages(maxCount: number): Promise<string[]> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxCount;
    const picker = new photoAccessHelper.PhotoViewPicker();
    const result = await picker.select(options);
    const out: string[] = [];
    for (const uri of result.photoUris) {
      try {
        out.push(await MediaRepo.importUri(uri, 'img', MediaRepo.extOf(uri, 'jpg')));
      } catch (e) {
        // 单张失败不阻断其它图片
      }
    }
    return out;
  }

  /**
   * 沙箱绝对路径 → ArkUI 能加载的 file:// uri。
   *
   * Image() 吃裸路径时不会报错，但也不显示（实测图片块一片空白）。
   * 相册 picker 返回的本来就是 file:// uri，复制进沙箱后这一步被丢掉了，
   * 所以渲染前必须补回来。
   */
  static toDisplayUri(path: string): string {
    if (path.length === 0) {
      return '';
    }
    if (path.startsWith('file://') || path.startsWith('datashare://') || path.startsWith('http')) {
      return path;
    }
    return `file://${path}`;
  }

  /** 从 uri 推断扩展名，取不到就给默认值 */
  private static extOf(uri: string, fallback: string): string {
    const dot = uri.lastIndexOf('.');
    if (dot < 0 || dot < uri.length - 6) {
      return fallback;
    }
    const ext = uri.substring(dot + 1).toLowerCase();
    if (ext === 'jpg' || ext === 'jpeg' || ext === 'png' || ext === 'webp' || ext === 'heic') {
      return ext === 'jpeg' ? 'jpg' : ext;
    }
    return fallback;
  }

  /** 删除沙箱内的媒体文件（删除胶囊时调用） */
  static removeQuietly(path: string): void {
    try {
      if (path.length > 0 && fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // 删不掉不影响主流程
    }
  }

  /** 统计沙箱 media 目录占用的字节数 */
  static totalBytes(): number {
    MediaRepo.ensureDir();
    let sum = 0;
    try {
      const names = fs.listFileSync(AppCtx.mediaDir());
      for (const name of names) {
        try {
          sum += fs.statSync(`${AppCtx.mediaDir()}/${name}`).size;
        } catch (e) {
          // 跳过异常项
        }
      }
    } catch (e) {
      return 0;
    }
    return sum;
  }

  /** 读取沙箱内文件为文本（备份导入用） */
  static readText(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }

  /** 写文本到沙箱内文件，返回路径 */
  static writeText(dir: string, name: string, content: string): string {
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      // 已存在
    }
    const path = `${dir}/${name}`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, content);
    } finally {
      fs.closeSync(file);
    }
    return path;
  }
}
