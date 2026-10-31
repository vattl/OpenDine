import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

enum KdsOutboxStatus {
  persisting('PERSISTING'),
  pending('PENDING'),
  sending('SENDING'),
  retryWait('RETRY_WAIT'),
  unknown('UNKNOWN'),
  acked('ACKED'),
  conflict('CONFLICT');

  const KdsOutboxStatus(this.wireName);
  final String wireName;

  static KdsOutboxStatus fromWireName(String name) {
    for (final val in KdsOutboxStatus.values) {
      if (val.wireName == name) return val;
    }
    return KdsOutboxStatus.pending;
  }
}

class KdsOutboxRecord {
  const KdsOutboxRecord({
    required this.id,
    required this.command,
    required this.hiddenKeys,
    required this.createdAt,
    this.status = KdsOutboxStatus.pending,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.lastError,
    this.originChannel,
    this.requiresResolution = false,
  });

  final String id;
  final KdsV2Command command;
  final Set<String> hiddenKeys;
  final DateTime createdAt;
  final KdsOutboxStatus status;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final String? originChannel;
  final bool requiresResolution;

  KdsOutboxRecord copyWith({
    KdsOutboxStatus? status,
    int? retryCount,
    DateTime? lastAttemptAt,
    String? lastError,
    Set<String>? hiddenKeys,
    String? originChannel,
    bool? requiresResolution,
  }) {
    return KdsOutboxRecord(
      id: id,
      command: command,
      hiddenKeys: hiddenKeys ?? this.hiddenKeys,
      createdAt: createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      originChannel: originChannel ?? this.originChannel,
      requiresResolution: requiresResolution ?? this.requiresResolution,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'command': command.toJson(),
        'hidden_keys': hiddenKeys.toList(),
        'created_at_ms': createdAt.millisecondsSinceEpoch,
        'status': status.wireName,
        'retry_count': retryCount,
        if (lastAttemptAt != null)
          'last_attempt_at_ms': lastAttemptAt!.millisecondsSinceEpoch,
        if (lastError != null) 'last_error': lastError,
        if (originChannel != null) 'origin_channel': originChannel,
        'requires_resolution': requiresResolution,
      };

  factory KdsOutboxRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final rawCommand = json['command'];
    if (rawCommand is! Map<String, dynamic> && rawCommand is! Map) {
      throw const FormatException(
          'KdsOutboxRecord command is missing or invalid');
    }
    final command =
        KdsV2Command.fromJson(Map<String, dynamic>.from(rawCommand as Map));
    final hiddenList = json['hidden_keys'] as List? ?? const [];
    final hiddenKeys = hiddenList.map((e) => '$e').toSet();
    final createdAtMs = json['created_at_ms'] as num? ?? 0;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(createdAtMs.toInt());
    final statusWire = json['status']?.toString() ?? 'PENDING';
    final status = KdsOutboxStatus.fromWireName(statusWire);
    final retryCount = (json['retry_count'] as num?)?.toInt() ?? 0;
    final lastAttemptMs = json['last_attempt_at_ms'] as num?;
    final lastAttemptAt = lastAttemptMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastAttemptMs.toInt())
        : null;
    final lastError = json['last_error']?.toString();
    final originChannel = json['origin_channel']?.toString();
    final requiresResolution = json['requires_resolution'] == true;

    return KdsOutboxRecord(
      id: id,
      command: command,
      hiddenKeys: hiddenKeys,
      createdAt: createdAt,
      status: status,
      retryCount: retryCount,
      lastAttemptAt: lastAttemptAt,
      lastError: lastError,
      originChannel: originChannel,
      requiresResolution: requiresResolution,
    );
  }
}

/// 本地持久化未完成与发送中的指令队列，保证跨进程重启/断网重连时不丢失未确认命令。
class KdsCommandOutboxStore {
  KdsCommandOutboxStore._(this._database, this._legacyPrefs);

  static Future<KdsCommandOutboxStore> open({
    SharedPreferences? legacyPrefs,
    String? databasePath,
  }) async {
    final path = databasePath ?? await _defaultDatabasePath();
    final db = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        try {
          await db.execute('PRAGMA foreign_keys = ON');
        } catch (e) {
          KdsFileLogger.warn('[OUTBOX] 配置 PRAGMA foreign_keys 失败: $e');
        }
        try {
          // Android SQLiteDatabase 限制有返回列的语句必须使用 rawQuery，否则报 code 0 SQLITE_OK
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        } catch (e) {
          KdsFileLogger.warn('[OUTBOX] 配置 PRAGMA busy_timeout 失败: $e');
        }
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
        } catch (e) {
          KdsFileLogger.warn('[OUTBOX] 配置 PRAGMA journal_mode 失败: $e');
        }
      },
    );
    await _createTables(db);
    return KdsCommandOutboxStore._(db, legacyPrefs);
  }

  static Future<KdsCommandOutboxStore> inMemory({SharedPreferences? legacyPrefs}) async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
    );
    await _createTables(db);
    return KdsCommandOutboxStore._(db, legacyPrefs);
  }

  final Database _database;
  final SharedPreferences? _legacyPrefs;

  static const _prefix = 'kds_command_outbox_v1_';

  static String _keyForShop(int? shopId) => '$_prefix${shopId ?? 'default'}';

  static Future<String> _defaultDatabasePath() async {
    final directory = await getApplicationSupportDirectory();
    return '${directory.path}${Platform.pathSeparator}kds_command_outbox.db';
  }

  static Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS t_kds_outbox (
        shop_id INTEGER NOT NULL,
        command_id TEXT NOT NULL,
        request_fingerprint TEXT NOT NULL,
        record_json TEXT NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        last_attempt_at_ms INTEGER,
        last_error TEXT,
        origin_channel TEXT,
        requires_resolution INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (shop_id, command_id)
      )
    ''');
    
    // Migrate old table data if exists
    try {
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='kds_command_outbox'");
      if (tables.isNotEmpty) {
        await db.execute('''
          INSERT OR IGNORE INTO t_kds_outbox (shop_id, command_id, request_fingerprint, record_json, status, retry_count, created_at_ms, updated_at_ms, last_attempt_at_ms, last_error, origin_channel, requires_resolution)
          SELECT shop_id, command_id, request_fingerprint, record_json, status, retry_count, created_at_ms, updated_at_ms, last_attempt_at_ms, last_error, origin_channel, requires_resolution
          FROM kds_command_outbox
        ''');
        await db.execute('DROP TABLE kds_command_outbox');
      }
    } catch (e) {
      KdsFileLogger.warn('[OUTBOX] 迁移历史 kds_command_outbox 表告警: $e');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS kds_outbox_migration_meta (
        migration_key TEXT PRIMARY KEY,
        migrated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_t_kds_outbox_shop_status_created '
      'ON t_kds_outbox(shop_id, status, created_at_ms)',
    );
  }

  Future<List<KdsOutboxRecord>> load({int? expectedShopId}) async {
    final shopId = expectedShopId;
    if (shopId == null || shopId <= 0) return const [];
    await _migrateLegacyShop(shopId);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    
    return await _database.transaction((txn) async {
      await txn.execute(
        "UPDATE t_kds_outbox SET status = 'RETRY_WAIT', "
        "last_error = COALESCE(last_error, 'process restarted during send'), "
        'requires_resolution = 1, updated_at_ms = ? '
        "WHERE shop_id = ? AND status IN ('SENDING', 'PERSISTING')",
        [nowMs, shopId],
      );
      final rows = await txn.rawQuery(
        'SELECT record_json, request_fingerprint, status, retry_count, '
        'last_attempt_at_ms, last_error, origin_channel, requires_resolution '
        "FROM t_kds_outbox "
        "WHERE shop_id = ? AND status IN ('PENDING', 'SENDING', 'RETRY_WAIT', 'UNKNOWN', 'PERSISTING') "
        'ORDER BY created_at_ms ASC, command_id ASC',
        [shopId],
      );
      final records = <KdsOutboxRecord>[];
      for (final row in rows) {
        try {
          final raw = jsonDecode(row['record_json'] as String);
          final json = Map<String, dynamic>.from(raw as Map);
          final fingerprint = _fingerprint(json);
          if (fingerprint != row['request_fingerprint']) {
            throw const FormatException('outbox fingerprint mismatch');
          }
          var record = KdsOutboxRecord.fromJson(json);
          final status = KdsOutboxStatus.fromWireName('${row['status']}');
          final lastAttemptMs = row['last_attempt_at_ms'] as int?;
          record = record.copyWith(
            status: status,
            retryCount: row['retry_count'] as int? ?? record.retryCount,
            lastAttemptAt: lastAttemptMs == null
                ? record.lastAttemptAt
                : DateTime.fromMillisecondsSinceEpoch(lastAttemptMs),
            lastError: row['last_error']?.toString() ?? record.lastError,
            originChannel:
                row['origin_channel']?.toString() ?? record.originChannel,
            requiresResolution: row['requires_resolution'] == 1,
          );
          records.add(record);
        } catch (error) {
          KdsFileLogger.error('[OUTBOX] SQLite 记录校验失败，已原样保留: $error');
        }
      }
      return List.unmodifiable(records);
    });
  }

  /// 获取指定门店待决/重试队列中最老一条命令的等待时长 (ms)
  Future<int?> getOldestPendingAgeMs({required int shopId}) async {
    if (shopId <= 0) return null;
    try {
      final rows = await _database.rawQuery(
        'SELECT MIN(created_at_ms) as oldest_ms FROM t_kds_outbox WHERE shop_id = ? AND status IN (?, ?, ?)',
        [
          shopId,
          KdsOutboxStatus.pending.wireName,
          KdsOutboxStatus.sending.wireName,
          KdsOutboxStatus.retryWait.wireName,
        ],
      );
      if (rows.isEmpty || rows.first['oldest_ms'] == null) return null;
      final oldestMs = rows.first['oldest_ms'] as int;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      return (nowMs - oldestMs).clamp(0, 86400000);
    } catch (e) {
      KdsFileLogger.warn('[OUTBOX] 获取最老待决指令等待时长失败: $e');
      return null;
    }
  }

  static const int maxCapacity = 500;

  Future<void> save(List<KdsOutboxRecord> records, {int? shopId}) async {
    if (shopId == null || shopId <= 0) {
      throw ArgumentError.value(shopId, 'shopId', 'must be positive');
    }
    if (records.length > maxCapacity) {
      throw StateError(
        'Outbox capacity exceeded ($maxCapacity); refusing to discard commands',
      );
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      await _database.transaction((txn) async {
        await txn.execute(
          'DELETE FROM t_kds_outbox WHERE shop_id = ?',
          [shopId],
        );
        for (final record in records) {
          final json = record.toJson();
          await txn.execute(
            'INSERT INTO t_kds_outbox '
            '(shop_id, command_id, request_fingerprint, record_json, status, '
            'retry_count, created_at_ms, updated_at_ms, last_attempt_at_ms, '
            'last_error, origin_channel, requires_resolution) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              shopId,
              record.id,
              _fingerprint(json),
              jsonEncode(json),
              record.status.wireName,
              record.retryCount,
              record.createdAt.millisecondsSinceEpoch,
              nowMs,
              record.lastAttemptAt?.millisecondsSinceEpoch,
              record.lastError,
              record.originChannel,
              record.requiresResolution ? 1 : 0,
            ],
          );
        }
      });
    } catch (e) {
      KdsFileLogger.error('[OUTBOX] 保存 outbox 记录失败: $e');
      rethrow;
    }
  }

  Future<void> enqueue(KdsOutboxRecord record, {required int shopId}) async {
    if (shopId <= 0) {
      throw ArgumentError.value(shopId, 'shopId', 'must be positive');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final json = record.toJson();
    try {
      await _database.execute(
        'INSERT INTO t_kds_outbox '
        '(shop_id, command_id, request_fingerprint, record_json, status, '
        'retry_count, created_at_ms, updated_at_ms, last_attempt_at_ms, '
        'last_error, origin_channel, requires_resolution) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          shopId,
          record.id,
          _fingerprint(json),
          jsonEncode(json),
          record.status.wireName,
          record.retryCount,
          record.createdAt.millisecondsSinceEpoch,
          nowMs,
          record.lastAttemptAt?.millisecondsSinceEpoch,
          record.lastError,
          record.originChannel,
          record.requiresResolution ? 1 : 0,
        ],
      );
    } catch (e) {
      KdsFileLogger.error('[OUTBOX] enqueue 失败: $e');
      rethrow;
    }
  }

  Future<void> updateStatus(KdsOutboxRecord record, {required int shopId}) async {
    if (shopId <= 0) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final json = record.toJson();
    try {
      await _database.execute(
        'UPDATE t_kds_outbox SET '
        'request_fingerprint = ?, record_json = ?, status = ?, '
        'retry_count = ?, updated_at_ms = ?, last_attempt_at_ms = ?, '
        'last_error = ?, origin_channel = ?, requires_resolution = ? '
        'WHERE shop_id = ? AND command_id = ?',
        [
          _fingerprint(json),
          jsonEncode(json),
          record.status.wireName,
          record.retryCount,
          nowMs,
          record.lastAttemptAt?.millisecondsSinceEpoch,
          record.lastError,
          record.originChannel,
          record.requiresResolution ? 1 : 0,
          shopId,
          record.id,
        ],
      );
    } catch (e) {
      KdsFileLogger.error('[OUTBOX] updateStatus 失败: $e');
      rethrow;
    }
  }

  Future<void> remove(String commandId, {required int shopId}) async {
    if (shopId <= 0) return;
    try {
      await _database.execute(
        'DELETE FROM t_kds_outbox WHERE shop_id = ? AND command_id = ?',
        [shopId, commandId],
      );
    } catch (e) {
      KdsFileLogger.error('[OUTBOX] remove 失败: $e');
      rethrow;
    }
  }

  Future<void> clear({int? shopId}) async {
    if (shopId == null) {
      await _database.execute('DELETE FROM t_kds_outbox');
    } else {
      await _database.execute(
        'DELETE FROM t_kds_outbox WHERE shop_id = ?',
        [shopId],
      );
    }
  }

  Future<void> close() async => await _database.close();

  Future<void> _migrateLegacyShop(int shopId) async {
    final prefs = _legacyPrefs;
    if (prefs == null) return;
    final key = _keyForShop(shopId);
    
    final migrated = await _database.rawQuery(
      'SELECT 1 FROM kds_outbox_migration_meta WHERE migration_key = ?',
      [key],
    );
    if (migrated.isNotEmpty) return;
    
    final rawString = prefs.getString(key);
    if (rawString == null || rawString.isEmpty) {
      await _database.execute(
        'INSERT INTO kds_outbox_migration_meta(migration_key, migrated_at_ms) '
        'VALUES (?, ?)',
        [key, DateTime.now().millisecondsSinceEpoch],
      );
      return;
    }

    try {
      await _database.transaction((txn) async {
        final decoded = jsonDecode(rawString);
        if (decoded is List) {
          final records = <KdsOutboxRecord>[];
          for (final item in decoded) {
            if (item is Map) {
              records.add(
                KdsOutboxRecord.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
          if (records.length > maxCapacity) {
            KdsFileLogger.warn(
              '[OUTBOX] 历史待决队列数量(${records.length})超过建议软上限($maxCapacity)，按安全策略完整迁移无损入库，禁止静默截断',
            );
          }
          final bounded = records;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          for (final record in bounded) {
            final json = record.toJson();
            final recoveredStatus = record.status == KdsOutboxStatus.sending
                ? KdsOutboxStatus.retryWait
                : record.status;
            await txn.execute(
              'INSERT OR IGNORE INTO t_kds_outbox '
              '(shop_id, command_id, request_fingerprint, record_json, status, '
              'retry_count, created_at_ms, updated_at_ms, last_attempt_at_ms, '
              'last_error, origin_channel, requires_resolution) '
              'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                shopId,
                record.id,
                _fingerprint(json),
                jsonEncode(json),
                recoveredStatus.wireName,
                record.retryCount,
                record.createdAt.millisecondsSinceEpoch,
                nowMs,
                record.lastAttemptAt?.millisecondsSinceEpoch,
                record.lastError,
                record.originChannel,
                record.status == KdsOutboxStatus.sending ||
                        record.requiresResolution
                    ? 1
                    : 0,
              ],
            );
          }
        }
        await txn.execute(
          'INSERT INTO kds_outbox_migration_meta(migration_key, migrated_at_ms) '
          'VALUES (?, ?)',
          [key, DateTime.now().millisecondsSinceEpoch],
        );
      });
      unawaited(prefs.remove(key));
    } catch (error) {
      KdsFileLogger.error('[OUTBOX] SharedPreferences 迁移 SQLite 失败: $error');
      rethrow;
    }
  }

  static String _fingerprint(Map<String, dynamic> json) {
    final canonical = jsonEncode(_canonical(json));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonical(value[key]),
      };
    }
    if (value is List) return value.map(_canonical).toList(growable: false);
    return value;
  }
}
