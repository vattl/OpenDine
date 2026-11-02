import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// 收银端核心操作审计日志。
///
/// 职责：记录所有核心业务操作（下单/结账/退款/充值/开班/营业开关/配置变更等），
/// 独立于 KDS 本地库（CashierKdsDatabase）与崩溃日志（CrashLog），
/// 本地 SQLite 落盘，异步批量写入，不阻塞主流程。
///
/// 与既有机制分工：
/// - 崩溃/异常 → CrashLog（app.log）
/// - 每个 HTTP 请求 → ApiDebugLogStore（内存）
/// - KDS 命令/事件 → kds_interaction_logs / local_operation_events
/// - 核心操作审计 → 本组件（cashier_audit.db / cashier_operation_audit 表）
class CashierOperationAuditStore {
  CashierOperationAuditStore._();

  static final CashierOperationAuditStore instance =
      CashierOperationAuditStore._();

  static const _defaultMaxRows = 200000;
  static const _defaultRetentionDays = 30;
  static const _flushWindow = Duration(milliseconds: 200);
  static const _flushBatchSize = 50;
  static const _maxQueuedDrafts = 2000;

  Database? _db;
  final List<CashierOperationAuditDraft> _queue = [];
  Timer? _flushTimer;
  int _seq = 0;
  bool _closed = false;
  int _droppedCount = 0;

  /// 当前操作者上下文（登录/切店时由 AppState 维护，埋点免传）。
  String? currentActorName;
  int? currentShopId;

  /// 记录失败时丢弃的条数（仅诊断用，不影响业务）。
  int get droppedCount => _droppedCount;

  bool get isReady => _db != null;

  /// 初始化：打开数据库、建表、执行保留清理。
  /// 失败时静默降级（不阻塞应用启动），后续 record 自动丢弃并计数。
  Future<void> init({String? overridePath}) async {
    if (_db != null) return;
    _closed = false;
    try {
      final path =
          overridePath ??
          p.join((await _applicationDataRoot()).path, 'cashier_audit.db');
      final db = sqlite3.open(path);
      db.execute('PRAGMA busy_timeout = 30000');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
      db.execute('PRAGMA temp_store = MEMORY');
      db.execute('''
        CREATE TABLE IF NOT EXISTS cashier_operation_audit (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_id TEXT NOT NULL UNIQUE,
          shop_id INTEGER NOT NULL DEFAULT 0,
          module TEXT NOT NULL,
          action TEXT NOT NULL,
          result TEXT NOT NULL,
          actor_id TEXT,
          actor_name TEXT,
          target_type TEXT,
          target_id TEXT,
          amount_fen INTEGER,
          detail_json TEXT,
          error_code TEXT,
          error_msg TEXT,
          device_code TEXT,
          cost_ms INTEGER,
          synced INTEGER NOT NULL DEFAULT 0,
          occurred_at_ms INTEGER NOT NULL
        )
      ''');
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_time ON cashier_operation_audit(occurred_at_ms)',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_module ON cashier_operation_audit(module, action, result)',
      );
      _db = db;
      trim();
    } catch (error, stack) {
      debugPrint('CashierOperationAuditStore init failed: $error\n$stack');
      _droppedCount = 0;
    }
  }

  /// 记录一条核心操作日志（异步批量落库，幂等）。
  void record(CashierOperationAuditDraft draft) {
    final db = _db;
    if (db == null || _closed) {
      _droppedCount++;
      return;
    }
    if (_queue.length >= _maxQueuedDrafts) {
      // SQLite is temporarily unavailable or under heavy contention. Keep
      // memory bounded and make the loss visible to diagnostics.
      _droppedCount++;
      return;
    }
    _queue.add(draft);
    _flushTimer ??= Timer(_flushWindow, _flush);
    if (_queue.length >= _flushBatchSize) {
      _flushTimer?.cancel();
      _flush();
    }
  }

  void _flush() {
    _flushTimer = null;
    final db = _db;
    if (db == null || _queue.isEmpty) return;
    final batch = List<CashierOperationAuditDraft>.from(_queue);
    _queue.clear();
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      db.execute('BEGIN IMMEDIATE');
      var committed = false;
      try {
        for (final d in batch) {
          _seq++;
          final operationId =
              d.operationId ?? 'op:${d.actorId ?? 'system'}:$now:$_seq';
          db.execute(
            '''
            INSERT OR IGNORE INTO cashier_operation_audit (
              operation_id, shop_id, module, action, result,
              actor_id, actor_name, target_type, target_id, amount_fen,
              detail_json, error_code, error_msg, device_code, cost_ms,
              synced, occurred_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            ''',
            [
              operationId,
              d.shopId ?? currentShopId ?? 0,
              d.module,
              d.action,
              d.result,
              d.actorId ?? currentActorName,
              d.actorName ?? currentActorName,
              d.targetType,
              d.targetId,
              d.amountFen,
              d.detail != null ? redactJson(d.detail!) : null,
              d.errorCode,
              d.errorMsg,
              d.deviceCode,
              d.costMs,
              now,
            ],
          );
        }
        db.execute('COMMIT');
        committed = true;
      } finally {
        if (!committed) {
          try {
            db.execute('ROLLBACK');
          } catch (_) {
            // Ignore rollback errors if transaction was never active or db is locked.
          }
        }
      }
    } catch (error, stack) {
      _droppedCount += batch.length;
      debugPrint('CashierOperationAuditStore flush failed: $error\n$stack');
    }
  }

  /// 查询审计日志（分页，按时间倒序）。
  List<CashierOperationAuditEntry> query({
    String? module,
    String? action,
    String? result,
    int? shopId,
    int limit = 100,
    int? beforeMs,
  }) {
    final db = _db;
    if (db == null) return const [];
    final conditions = <String>[];
    final args = <Object?>[];
    if (module != null && module.isNotEmpty) {
      conditions.add('module = ?');
      args.add(module);
    }
    if (action != null && action.isNotEmpty) {
      conditions.add('action = ?');
      args.add(action);
    }
    if (result != null && result.isNotEmpty) {
      conditions.add('result = ?');
      args.add(result);
    }
    if (shopId != null && shopId > 0) {
      conditions.add('shop_id = ?');
      args.add(shopId);
    }
    if (beforeMs != null) {
      conditions.add('occurred_at_ms < ?');
      args.add(beforeMs);
    }
    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final rows = db.select(
      'SELECT * FROM cashier_operation_audit $where '
      'ORDER BY occurred_at_ms DESC, id DESC LIMIT ?',
      [...args, limit],
    );
    return rows.map(_entryFromRow).toList();
  }

  /// 未上云记录条数（供三期上报 worker 使用）。
  int pendingSyncCount() {
    final db = _db;
    if (db == null) return 0;
    return db
            .select(
              'SELECT COUNT(*) AS c FROM cashier_operation_audit WHERE synced = 0',
            )
            .first['c']
        as int;
  }

  List<CashierOperationAuditEntry> pendingSync(int limit) {
    final db = _db;
    if (db == null) return const [];
    final rows = db.select(
      'SELECT * FROM cashier_operation_audit WHERE synced = 0 '
      'ORDER BY occurred_at_ms ASC LIMIT ?',
      [limit],
    );
    return rows.map(_entryFromRow).toList();
  }

  void markSynced(List<String> operationIds) {
    final db = _db;
    if (db == null || operationIds.isEmpty) return;
    db.execute(
      'UPDATE cashier_operation_audit SET synced = 1 '
      'WHERE operation_id IN (${List.filled(operationIds.length, '?').join(',')})',
      operationIds,
    );
  }

  /// 保留策略：按天数与行数上限裁剪（启动及后台周期性维护时调用）。
  void trim({
    int retentionDays = _defaultRetentionDays,
    int maxRows = _defaultMaxRows,
  }) {
    final db = _db;
    if (db == null) return;
    try {
      final cutoff = DateTime.now()
          .subtract(Duration(days: retentionDays))
          .millisecondsSinceEpoch;
      db.execute(
        'DELETE FROM cashier_operation_audit WHERE occurred_at_ms < ?',
        [cutoff],
      );
      final total =
          db
                  .select('SELECT COUNT(*) AS c FROM cashier_operation_audit')
                  .first['c']
              as int;
      if (total > maxRows) {
        final deleteCount = total - maxRows;
        db.execute(
          'DELETE FROM cashier_operation_audit WHERE id IN '
          '(SELECT id FROM cashier_operation_audit ORDER BY occurred_at_ms ASC, id ASC LIMIT ?)',
          [deleteCount],
        );
      }
    } catch (error, stack) {
      debugPrint('CashierOperationAuditStore trim failed: $error\n$stack');
    }
  }

  void close() {
    _closed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    // Persist the final batch before releasing SQLite; otherwise a normal
    // logout/restart would silently discard queued audit records.
    _flush();
    _db?.close();
    _db = null;
  }

  static CashierOperationAuditEntry _entryFromRow(Row row) {
    return CashierOperationAuditEntry(
      id: row['id'] as int,
      operationId: row['operation_id'] as String,
      shopId: row['shop_id'] as int,
      module: row['module'] as String,
      action: row['action'] as String,
      result: row['result'] as String,
      actorId: row['actor_id'] as String?,
      actorName: row['actor_name'] as String?,
      targetType: row['target_type'] as String?,
      targetId: row['target_id'] as String?,
      amountFen: row['amount_fen'] as int?,
      detailJson: row['detail_json'] as String?,
      errorCode: row['error_code'] as String?,
      errorMsg: row['error_msg'] as String?,
      deviceCode: row['device_code'] as String?,
      costMs: row['cost_ms'] as int?,
      synced: row['synced'] as int,
      occurredAtMs: row['occurred_at_ms'] as int,
    );
  }

  static Future<Directory> _applicationDataRoot() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        return await getApplicationSupportDirectory();
      } catch (_) {
        // ignore
      }
    }
    final appData = Platform.environment['LOCALAPPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) return Directory(appData);
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, '.local', 'share'));
    }
    return Directory.current;
  }

  /// 敏感字段脱敏（键名命中即打码，长值截断）。
  static const _sensitiveKeys = <String>{
    'phone',
    'mobile',
    'password',
    'pwd',
    'token',
    'access_token',
    'refresh_token',
    'secret',
    'app_secret',
    'appSecret',
    'mch_id',
    'mchId',
    'api_key',
    'apiKey',
    'balance',
    'card_no',
    'cardNo',
    'cert',
    'private_key',
    'authorization',
    'Authorization',
  };

  static String redactJson(Map<String, Object?> detail) {
    try {
      final out = <String, Object?>{};
      detail.forEach((key, value) {
        if (_sensitiveKeys.contains(key)) {
          out[key] = '***redacted***';
        } else if (value is String && value.length > 200) {
          out[key] = '${value.substring(0, 200)}…(${value.length} chars)';
        } else if (value is Map) {
          out[key] = redactJson(Map<String, Object?>.from(value));
        } else {
          out[key] = value;
        }
      });
      return jsonEncode(out);
    } catch (_) {
      return '{"redact_error": true}';
    }
  }
}

/// 操作审计草稿（埋点处构造，一行调用）。
class CashierOperationAuditDraft {
  const CashierOperationAuditDraft({
    required this.module,
    required this.action,
    required this.result,
    this.operationId,
    this.shopId,
    this.actorId,
    this.actorName,
    this.targetType,
    this.targetId,
    this.amountFen,
    this.detail,
    this.errorCode,
    this.errorMsg,
    this.deviceCode,
    this.costMs,
  });

  /// 幂等键（可选；不传则自动生成）。
  final String? operationId;
  final int? shopId;
  final String module;
  final String action;

  /// success / failed / blocked
  final String result;
  final String? actorId;
  final String? actorName;
  final String? targetType;
  final String? targetId;
  final int? amountFen;
  final Map<String, Object?>? detail;
  final String? errorCode;
  final String? errorMsg;
  final String? deviceCode;
  final int? costMs;
}

/// 查询结果行。
class CashierOperationAuditEntry {
  const CashierOperationAuditEntry({
    required this.id,
    required this.operationId,
    required this.shopId,
    required this.module,
    required this.action,
    required this.result,
    this.actorId,
    this.actorName,
    this.targetType,
    this.targetId,
    this.amountFen,
    this.detailJson,
    this.errorCode,
    this.errorMsg,
    this.deviceCode,
    this.costMs,
    required this.synced,
    required this.occurredAtMs,
  });

  final int id;
  final String operationId;
  final int shopId;
  final String module;
  final String action;
  final String result;
  final String? actorId;
  final String? actorName;
  final String? targetType;
  final String? targetId;
  final int? amountFen;
  final String? detailJson;
  final String? errorCode;
  final String? errorMsg;
  final String? deviceCode;
  final int? costMs;
  final int synced;
  final int occurredAtMs;

  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(occurredAtMs);

  Map<String, Object?>? get detail {
    final raw = detailJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
