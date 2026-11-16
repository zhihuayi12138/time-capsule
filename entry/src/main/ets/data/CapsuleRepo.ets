import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Capsule, CapsuleStatus, ContentBlock, BlockType } from '../model/Capsule';
import { AppCtx } from '../common/AppCtx';
import { StoreKey } from '../common/Constants';

/**
 * 胶囊数据仓库（RDB）。
 *
 * 两张表：capsule（胶囊本身）+ block（内容块，一对多）。
 * 语音与图片只存 uri，二进制放在应用沙箱 filesDir/media 下，
 * 这样 RDB 里没有大字段，列表查询不会被二进制拖慢。
 */
export class CapsuleRepo {
  private static store?: relationalStore.RdbStore = undefined;

  private static readonly TABLE_CAPSULE: string = 'capsule';
  private static readonly TABLE_BLOCK: string = 'block';

  /** 建表语句（IF NOT EXISTS，重复执行安全） */
  private static readonly SQL_CREATE_CAPSULE: string =
    'CREATE TABLE IF NOT EXISTS capsule (' +
    'id TEXT PRIMARY KEY, ' +
    'title TEXT NOT NULL, ' +
    'status TEXT NOT NULL, ' +
    'createdAt INTEGER NOT NULL, ' +
    'openAt INTEGER NOT NULL, ' +
    'openedAt INTEGER, ' +
    'notified INTEGER NOT NULL DEFAULT 0, ' +
    'reminderId INTEGER)';

  private static readonly SQL_CREATE_BLOCK: string =
    'CREATE TABLE IF NOT EXISTS block (' +
    'id TEXT PRIMARY KEY, ' +
    'capsuleId TEXT NOT NULL, ' +
    'type TEXT NOT NULL, ' +
    'text TEXT, ' +
    'uris TEXT, ' +
    'audioUri TEXT, ' +
    'duration INTEGER, ' +
    'sortOrder INTEGER NOT NULL DEFAULT 0)';

  /** 打开（或复用）数据库，并保证表结构就绪 */
  static async init(context?: common.Context): Promise<void> {
    if (CapsuleRepo.store !== undefined) {
      return;
    }
    const ctx: common.Context = context === undefined ? AppCtx.get() : context;
    const config: relationalStore.StoreConfig = {
      name: StoreKey.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S2
    };
    const store = await relationalStore.getRdbStore(ctx, config);
    await store.executeSql(CapsuleRepo.SQL_CREATE_CAPSULE);
    await store.executeSql(CapsuleRepo.SQL_CREATE_BLOCK);
    CapsuleRepo.store = store;
  }

  private static db(): relationalStore.RdbStore {
    const s = CapsuleRepo.store;
    if (s === undefined) {
      throw new Error('CapsuleRepo.init() 必须先执行');
    }
    return s;
  }

  /** 读出全部胶囊（含内容块），按创建时间倒序 */
  static async listAll(): Promise<Capsule[]> {
    const store = CapsuleRepo.db();
    const rs = await store.querySql('SELECT * FROM capsule ORDER BY createdAt DESC');
    const capsules: Capsule[] = [];
    const idIndex = rs.getColumnIndex('id');
    const resultIds: string[] = [];
    while (rs.goToNextRow()) {
      const id = rs.getString(idIndex);
      resultIds.push(id);
      capsules.push(CapsuleRepo.readCapsule(rs));
    }
    rs.close();

    if (resultIds.length === 0) {
      return capsules;
    }
    // 一次取出全部内容块并按胶囊分组，避免 N+1 查询
    const grouped = await CapsuleRepo.listBlocks(resultIds);
    for (const c of capsules) {
      const arr = grouped.get(c.id);
      c.blocks = arr === undefined ? [] : arr;
    }
    return capsules;
  }

  /** 只取一组胶囊的内容块，按 capsuleId 分组返回 */
  private static async listBlocks(capsuleIds: string[]): Promise<Map<string, ContentBlock[]>> {
    const store = CapsuleRepo.db();
    const rs = await store.querySql('SELECT * FROM block ORDER BY sortOrder ASC');
    const grouped: Map<string, ContentBlock[]> = new Map();
    const capIndex = rs.getColumnIndex('capsuleId');
    const idIndex = rs.getColumnIndex('id');
    const typeIndex = rs.getColumnIndex('type');
    const textIndex = rs.getColumnIndex('text');
    const urisIndex = rs.getColumnIndex('uris');
    const audioIndex = rs.getColumnIndex('audioUri');
    const durIndex = rs.getColumnIndex('duration');
    const orderIndex = rs.getColumnIndex('sortOrder');
    while (rs.goToNextRow()) {
      const owner = rs.getString(capIndex);
      if (capsuleIds.indexOf(owner) < 0) {
        continue;
      }
      const b: ContentBlock = {
        id: rs.getString(idIndex),
        type: rs.getString(typeIndex) as BlockType,
        order: rs.getLong(orderIndex)
      };
      if (!rs.isColumnNull(textIndex)) {
        b.text = rs.getString(textIndex);
      }
      if (!rs.isColumnNull(urisIndex)) {
        b.uris = CapsuleRepo.decodeUris(rs.getString(urisIndex));
      }
      if (!rs.isColumnNull(audioIndex)) {
        b.audioUri = rs.getString(audioIndex);
      }
      if (!rs.isColumnNull(durIndex)) {
        b.duration = rs.getLong(durIndex);
      }
      const arr = grouped.get(owner);
      if (arr === undefined) {
        grouped.set(owner, [b]);
      } else {
        arr.push(b);
      }
    }
    rs.close();
    return grouped;
  }

  private static readCapsule(rs: relationalStore.ResultSet): Capsule {
    const c: Capsule = {
      id: rs.getString(rs.getColumnIndex('id')),
      title: rs.getString(rs.getColumnIndex('title')),
      status: rs.getString(rs.getColumnIndex('status')) as CapsuleStatus,
      createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
      openAt: rs.getLong(rs.getColumnIndex('openAt')),
      blocks: [],
      notified: rs.getLong(rs.getColumnIndex('notified')) === 1
    };
    const openedIndex = rs.getColumnIndex('openedAt');
    if (!rs.isColumnNull(openedIndex)) {
      c.openedAt = rs.getLong(openedIndex);
    }
    const remIndex = rs.getColumnIndex('reminderId');
    if (!rs.isColumnNull(remIndex)) {
      c.reminderId = rs.getLong(remIndex);
    }
    return c;
  }

  /** 保存胶囊：存在则更新，否则插入；内容块整体重建（数量少，简单可靠） */
  static async save(c: Capsule): Promise<void> {
    const store = CapsuleRepo.db();
    const values: relationalStore.ValuesBucket = {
      'id': c.id,
      'title': c.title,
      'status': c.status,
      'createdAt': c.createdAt,
      'openAt': c.openAt,
      'notified': c.notified ? 1 : 0
    };
    if (c.openedAt !== undefined) {
      values['openedAt'] = c.openedAt;
    } else {
      values['openedAt'] = null;
    }
    if (c.reminderId !== undefined) {
      values['reminderId'] = c.reminderId;
    } else {
      values['reminderId'] = null;
    }
    await store.insert(CapsuleRepo.TABLE_CAPSULE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);

    // 内容块先清后插，保证顺序与删除都正确
    const delPred = new relationalStore.RdbPredicates(CapsuleRepo.TABLE_BLOCK);
    delPred.equalTo('capsuleId', c.id);
    await store.delete(delPred);

    const blocks: relationalStore.ValuesBucket[] = [];
    for (let i = 0; i < c.blocks.length; i++) {
      const b = c.blocks[i];
      const row: relationalStore.ValuesBucket = {
        'id': b.id,
        'capsuleId': c.id,
        'type': b.type,
        'sortOrder': i
      };
      if (b.text !== undefined) {
        row['text'] = b.text;
      }
      if (b.uris !== undefined && b.uris.length > 0) {
        row['uris'] = b.uris.join('\n');
      }
      if (b.audioUri !== undefined) {
        row['audioUri'] = b.audioUri;
      }
      if (b.duration !== undefined) {
        row['duration'] = b.duration;
      }
      blocks.push(row);
    }
    if (blocks.length > 0) {
      await store.batchInsert(CapsuleRepo.TABLE_BLOCK, blocks);
    }
  }

  /** 批量保存（导入备份时用） */
  static async saveAll(list: Capsule[]): Promise<void> {
    for (const c of list) {
      await CapsuleRepo.save(c);
    }
  }

  /** 删除胶囊及其内容块 */
  static async remove(id: string): Promise<void> {
    const store = CapsuleRepo.db();
    const pred = new relationalStore.RdbPredicates(CapsuleRepo.TABLE_CAPSULE);
    pred.equalTo('id', id);
    await store.delete(pred);
    const bpred = new relationalStore.RdbPredicates(CapsuleRepo.TABLE_BLOCK);
    bpred.equalTo('capsuleId', id);
    await store.delete(bpred);
  }

  /** 清空（恢复备份前用） */
  static async clearAll(): Promise<void> {
    const store = CapsuleRepo.db();
    await store.executeSql('DELETE FROM capsule');
    await store.executeSql('DELETE FROM block');
  }

  /** uris 列用换行分隔存取，避免引入 JSON 解析开销 */
  private static decodeUris(raw: string): string[] {
    if (raw.length === 0) {
      return [];
    }
    return raw.split('\n').filter((s: string) => s.length > 0);
  }
}
