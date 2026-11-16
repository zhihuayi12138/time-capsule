import { media } from '@kit.MediaKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppCtx } from '../common/AppCtx';
import { MediaRepo } from './MediaRepo';

const DOMAIN: number = 0x0001;
const TAG: string = 'TimeCapsuleAudio';

/**
 * 语音录制与播放。
 *
 * 录制用 AVRecorder（m4a/AAC，单声道，低码率——语音备忘不需要高保真），
 * 播放用 AVPlayer，复用同一个实例，切块时先 reset 再设置新的 uri。
 *
 * 录音文件直接录到应用沙箱，不经过相册/文件 picker，避免额外权限。
 */
export class AudioService {
  /** 最近一次失败原因，空串表示成功 */
  static lastError: string = '';
  private static recorder?: media.AVRecorder = undefined;
  private static player?: media.AVPlayer = undefined;
  private static recording: boolean = false;
  private static recordStartAt: number = 0;
  private static currentPath: string = '';
  /** 录制时打开的 fd，停止后必须关闭，否则文件句柄泄漏 */
  private static recordFile?: fs.File = undefined;
  /** 播放时打开的 fd */
  private static playFile?: fs.File = undefined;

  // ---------------- 录制 ----------------

  static isRecording(): boolean {
    return AudioService.recording;
  }

  /** 开始录音，返回目标文件路径 */
  static async start(): Promise<string> {
    if (AudioService.recording) {
      return AudioService.currentPath;
    }
    MediaRepo.ensureDir();
    const path = `${AppCtx.mediaDir()}/voice_${Date.now()}.m4a`;
    // AVRecorder 的 url 只接受 fd://<fd号>，所以先创建文件拿到 fd
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);

    // createAVRecorder / prepare / start 任一步失败都必须把 fd 和文件收掉。
    // 以前没有 try/catch：一旦 prepare 抛错，fd 泄漏、文件残留 0 字节，
    // 而 recorder 字段还是 undefined，于是后续 stop() 直接返回空结果，
    // 界面上表现为「点了录音没反应」。
    let recorder: media.AVRecorder | undefined = undefined;
    try {
      recorder = await media.createAVRecorder();
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 48000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 44100,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${file.fd}`
      };
      await recorder.prepare(config);
      await recorder.start();
    } catch (e) {
      const err = e as BusinessError;
      AudioService.lastError = `录音启动失败 ${err.code === undefined ? '' : err.code}: ${err.message}`;
      hilog.error(DOMAIN, TAG, 'audio start failed: %{public}s', AudioService.lastError);
      if (recorder !== undefined) {
        try {
          await recorder.release();
        } catch (e2) {
          // 忽略
        }
      }
      try {
        fs.closeSync(file);
      } catch (e2) {
        // 忽略
      }
      MediaRepo.removeQuietly(path);
      throw e as Error;
    }

    AudioService.recorder = recorder;
    AudioService.recordFile = file;
    AudioService.recording = true;
    AudioService.recordStartAt = Date.now();
    AudioService.currentPath = path;
    AudioService.lastError = '';
    return path;
  }

  /**
   * 停止录音，返回 {path, duration}。
   * duration 是秒数，至少 1 秒，避免显示「0:00」。
   */
  static async stop(): Promise<RecordResult> {
    const recorder = AudioService.recorder;
    if (recorder === undefined || !AudioService.recording) {
      return { path: '', duration: 0 };
    }
    const path = AudioService.currentPath;
    try {
      await recorder.stop();
    } catch (e) {
      // 没录到数据时 stop 会抛，仍然按成功处理
    }
    try {
      await recorder.release();
    } catch (e) {
      // 忽略
    }
    const file = AudioService.recordFile;
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (e) {
        // 忽略
      }
    }
    AudioService.recorder = undefined;
    AudioService.recordFile = undefined;
    AudioService.recording = false;
    const secs = Math.max(1, Math.round((Date.now() - AudioService.recordStartAt) / 1000));
    AudioService.recordStartAt = 0;
    AudioService.currentPath = '';
    return { path: path, duration: secs };
  }

  /** 放弃当前录音并删除文件 */
  static async discard(): Promise<void> {
    const path = AudioService.currentPath;
    await AudioService.stop();
    MediaRepo.removeQuietly(path);
  }

  /** 录音过程中已经过去的秒数（用于计时显示） */
  static elapsedSeconds(): number {
    if (!AudioService.recording || AudioService.recordStartAt === 0) {
      return 0;
    }
    return Math.floor((Date.now() - AudioService.recordStartAt) / 1000);
  }

  // ---------------- 播放 ----------------

  private static async ensurePlayer(): Promise<media.AVPlayer> {
    if (AudioService.player === undefined) {
      AudioService.player = await media.createAVPlayer();
    }
    return AudioService.player;
  }

  /** 播放指定文件（从 0 开始），onFinish 在播放结束时回调 */
  static async play(path: string, onFinish: () => void): Promise<void> {
    if (path.length === 0) {
      onFinish();
      return;
    }
    const player = await AudioService.ensurePlayer();
    try {
      if (player.state !== 'idle') {
        await player.reset();
      }
      player.on('stateChange', (state: string) => {
        if (state === 'completed') {
          onFinish();
        }
      });
      // 用 fdSrc 而不是 url：沙箱内的私有路径只能通过文件描述符交给播放器
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      AudioService.playFile = file;
      player.fdSrc = { fd: file.fd, offset: 0, length: fs.statSync(path).size };
      await player.prepare();
      await player.play();
    } catch (e) {
      AudioService.closePlayFile();
      onFinish();
    }
  }

  private static closePlayFile(): void {
    const file = AudioService.playFile;
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (e) {
        // 忽略
      }
      AudioService.playFile = undefined;
    }
  }

  /** 停止播放并释放 */
  static async stopPlay(): Promise<void> {
    const player = AudioService.player;
    if (player === undefined) {
      return;
    }
    try {
      if (player.state === 'playing' || player.state === 'paused' || player.state === 'prepared') {
        await player.reset();
      }
    } catch (e) {
      // 忽略
    }
    AudioService.closePlayFile();
  }

  /** 页面销毁时整体释放 */
  static async releaseAll(): Promise<void> {
    if (AudioService.recorder !== undefined) {
      try {
        await AudioService.recorder.release();
      } catch (e) {
        // 忽略
      }
      AudioService.recorder = undefined;
      AudioService.recording = false;
    }
    const recordFile = AudioService.recordFile;
    if (recordFile !== undefined) {
      try {
        fs.closeSync(recordFile);
      } catch (e) {
        // 忽略
      }
      AudioService.recordFile = undefined;
    }
    const player = AudioService.player;
    if (player !== undefined) {
      try {
        await player.release();
      } catch (e) {
        // 忽略
      }
      AudioService.player = undefined;
    }
    AudioService.closePlayFile();
  }
}

/** stop() 的返回值 */
export interface RecordResult {
  path: string;
  /** 秒 */
  duration: number;
}
