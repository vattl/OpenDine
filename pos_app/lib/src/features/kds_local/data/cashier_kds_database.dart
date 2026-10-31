import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/cashier_kds_models.dart';
import '../domain/cashier_kds_interaction_log.dart';

class CashierKdsDatabase {
  CashierKdsDatabase._(this._database) {
    _migrate();
  }

  factory CashierKdsDatabase.open(String path) =>
      CashierKdsDatabase._(sqlite3.open(path));

  factory CashierKdsDatabase.inMemory() =>
      CashierKdsDatabase._(sqlite3.openInMemory());

  final Database _database;
  int _droppedInteractionLogCount = 0;
  int _interactionWritesSinceCleanup = 0;

  int get droppedInteractionLogCount => _droppedInteractionLogCount;

  void close() => _database.close();

  void _safeBegin() {
    try {
      _database.execute('BEGIN IMMEDIATE');
    } catch (e1) {
      try {
        _database.execute('BEGIN');
      } catch (e2) {
        throw StateError('无法获取 KDS 数据库事务锁: $e1 / $e2');
      }
    }
  }

  void _safeRollback() {
    try {
      _database.execute('ROLLBACK');
    } catch (_) {
      // Suppress rollback failures when transaction is already closed or inactive
    }
  }

  void walCheckpointPassive() {
    try {
      _database.execute('PRAGMA wal_checkpoint(PASSIVE)');
    } catch (_) {}
  }

  void _migrate() {
    _database.execute('PRAGMA foreign_keys = ON');
    _database.execute('PRAGMA busy_timeout = 30000');
    final currentJournalMode =
        '${_database.select('PRAGMA journal_mode').first.values.first}'
            .toLowerCase();
    if (currentJournalMode != 'wal') {
      _database.execute('PRAGMA journal_mode = WAL');
    }
    _database.execute('PRAGMA synchronous = NORMAL');
    _database.execute('PRAGMA temp_store = MEMORY');
    _database.execute('PRAGMA cache_size = -8000');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        order_no TEXT NOT NULL UNIQUE,
        table_number TEXT NOT NULL,
        fulfillment_type TEXT NOT NULL,
        remark TEXT NOT NULL DEFAULT '',
        number_of_diners INTEGER NOT NULL DEFAULT 1,
        order_status TEXT NOT NULL DEFAULT 'kitchen_pending',
        local_revision INTEGER NOT NULL DEFAULT 1,
        cloud_order_id INTEGER,
        cloud_order_no TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_order_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES local_orders(id),
        dish_id INTEGER NOT NULL,
        dish_name TEXT NOT NULL,
        specification TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT '份',
        line_quantity INTEGER NOT NULL,
        prep_remaining INTEGER NOT NULL,
        cook_remaining INTEGER NOT NULL,
        ready_remaining INTEGER NOT NULL,
        workflow_queue TEXT NOT NULL,
        done_line INTEGER NOT NULL DEFAULT 0,
        local_revision INTEGER NOT NULL DEFAULT 1,
        cloud_detail_id INTEGER,
        completed_at_ms INTEGER,
        is_combo INTEGER NOT NULL DEFAULT 0,
        combo_name TEXT,
        combo_id INTEGER,
        serving_duration_minutes INTEGER NOT NULL DEFAULT 10,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_operation_events (
        operation_id TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        aggregate_key TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        result_json TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cloud_outbox (
        event_id TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        aggregate_key TEXT NOT NULL,
        aggregate_sequence INTEGER NOT NULL DEFAULT 1,
        payload_json TEXT NOT NULL,
        request_fingerprint TEXT,
        state TEXT NOT NULL DEFAULT 'pending',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at_ms INTEGER NOT NULL,
        last_http_status INTEGER,
        last_code INTEGER,
        last_error TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        delivered_at_ms INTEGER
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_dead_letter_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actor_device_code TEXT NOT NULL,
        action TEXT NOT NULL,
        reason TEXT NOT NULL,
        old_event_id TEXT NOT NULL,
        new_event_id TEXT,
        old_payload_fingerprint TEXT NOT NULL,
        new_payload_fingerprint TEXT,
        occurred_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS kds_pairing_codes (
        code_hash TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        used_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS kds_devices (
        device_code TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        device_name TEXT NOT NULL,
        screen_tag TEXT NOT NULL,
        workflows_json TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        enabled INTEGER NOT NULL DEFAULT 1,
        paired_at_ms INTEGER NOT NULL,
        last_heartbeat_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_dish_catalog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_id INTEGER NOT NULL,
        dish_id INTEGER NOT NULL,
        dish_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        sort_index INTEGER NOT NULL,
        category_id INTEGER,
        category_name TEXT,
        category_sequence INTEGER,
        dish_sequence INTEGER,
        stock INTEGER,
        onsale INTEGER NOT NULL DEFAULT 1,
        sold_out INTEGER NOT NULL DEFAULT 0,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_event_journal (
        event_seq INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        shop_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        aggregate_key TEXT NOT NULL,
        patches_json TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        retained_until_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS edge_kds_event_journal (
        shop_id INTEGER NOT NULL,
        event_seq INTEGER NOT NULL,
        event_id TEXT NOT NULL,
        envelope_json TEXT NOT NULL,
        received_at_ms INTEGER NOT NULL,
        PRIMARY KEY (shop_id, event_seq),
        UNIQUE (shop_id, event_id)
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS edge_kds_proxy_cursor (
        shop_id INTEGER PRIMARY KEY,
        last_event_seq INTEGER NOT NULL,
        synced_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS edge_kds_http_cache (
        cache_key TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        path TEXT NOT NULL,
        vary_hash TEXT NOT NULL,
        etag TEXT,
        authority_cursor INTEGER NOT NULL DEFAULT 0,
        body_json TEXT NOT NULL,
        cached_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_kds_config (
        shop_id INTEGER PRIMARY KEY,
        config_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS local_kds_meta (
        meta_key TEXT PRIMARY KEY,
        meta_value TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cloud_outbox_sequence_watermarks (
        aggregate_key TEXT PRIMARY KEY,
        high_water_sequence INTEGER NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cloud_delivery_inbox (
        event_id TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        cursor INTEGER NOT NULL,
        order_id INTEGER NOT NULL,
        projection_version INTEGER NOT NULL,
        received_at_ms INTEGER NOT NULL
      )
    ''');
    final _pcCols = _database.select("PRAGMA table_info(pending_commands)");
    final _needsPcMig =
        _pcCols.isNotEmpty && !_pcCols.any((r) => r['name'] == 'actor_id');
    if (_needsPcMig) {
      _database.execute(
        'ALTER TABLE pending_commands RENAME TO pending_commands_legacy',
      );
    }

    _database.execute('''
      CREATE TABLE IF NOT EXISTS pending_commands (
        shop_id INTEGER NOT NULL,
        command_id TEXT NOT NULL,
        actor_id TEXT NOT NULL,
        actor_type TEXT NOT NULL,
        command_type TEXT NOT NULL,
        request_hash TEXT NOT NULL,
        target_json TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        result_json TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at_ms INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (shop_id, command_id)
      )
    ''');
    _migrateLegacyPendingCommands();
    _database.execute(
      "UPDATE pending_commands SET status = 'UNKNOWN', "
      "last_error = COALESCE(last_error, 'process restarted during send'), "
      'updated_at = ? WHERE status = ?',
      [DateTime.now().millisecondsSinceEpoch, 'SENDING'],
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_pending_due '
      'ON pending_commands(status, next_attempt_at_ms, occurred_at_ms)',
    );
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cached_orders (
        id INTEGER PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        order_no TEXT NOT NULL,
        table_number TEXT,
        fulfillment_type TEXT,
        remark TEXT,
        order_status TEXT,
        created_at_ms INTEGER,
        updated_at_ms INTEGER,
        payload_json TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS cached_order_lines (
        id INTEGER PRIMARY KEY,
        order_id INTEGER NOT NULL,
        dish_id INTEGER,
        dish_name TEXT,
        payload_json TEXT NOT NULL
      )
    ''');
    _database.execute('''
      CREATE TABLE IF NOT EXISTS kds_interaction_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trace_id TEXT NOT NULL,
        shop_id INTEGER NOT NULL,
        order_id INTEGER,
        order_no TEXT,
        event_id TEXT,
        operation_id TEXT,
        cursor INTEGER,
        source_side TEXT NOT NULL,
        target_side TEXT NOT NULL,
        direction TEXT NOT NULL,
        stage TEXT NOT NULL,
        action TEXT NOT NULL,
        status TEXT NOT NULL,
        attempt INTEGER NOT NULL DEFAULT 1,
        http_status INTEGER,
        business_code TEXT,
        duration_ms INTEGER,
        device_code TEXT,
        error_type TEXT,
        error_summary TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        occurred_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');
    _ensureColumn(
      'local_orders',
      'number_of_diners',
      'INTEGER NOT NULL DEFAULT 1',
    );
    _ensureColumn(
      'local_orders',
      'order_status',
      "TEXT NOT NULL DEFAULT 'kitchen_pending'",
    );
    _ensureColumn('local_orders', 'cloud_order_id', 'INTEGER');
    _ensureColumn('local_orders', 'cloud_order_no', 'TEXT');
    _ensureColumn(
      'local_order_lines',
      'done_line',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn('local_order_lines', 'cloud_detail_id', 'INTEGER');
    _ensureColumn('local_order_lines', 'completed_at_ms', 'INTEGER');
    _ensureColumn('local_dish_catalog', 'stock', 'INTEGER');
    _ensureColumn('local_dish_catalog', 'category_id', 'INTEGER');
    _ensureColumn('local_dish_catalog', 'category_name', 'TEXT');
    _ensureColumn('local_dish_catalog', 'category_sequence', 'INTEGER');
    _ensureColumn('local_dish_catalog', 'dish_sequence', 'INTEGER');
    _ensureColumn('local_dish_catalog', 'onsale', 'INTEGER NOT NULL DEFAULT 1');
    _ensureColumn(
      'local_dish_catalog',
      'sold_out',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn(
      'cloud_outbox',
      'aggregate_sequence',
      'INTEGER NOT NULL DEFAULT 1',
    );
    _ensureColumn('cloud_outbox', 'last_http_status', 'INTEGER');
    _ensureColumn('cloud_outbox', 'last_code', 'INTEGER');
    _ensureColumn('cloud_outbox', 'last_error', 'TEXT');
    _ensureColumn('cloud_outbox', 'delivered_at_ms', 'INTEGER');
    _ensureColumn('cloud_outbox', 'request_fingerprint', 'TEXT');
    _ensureColumn('local_orders', 'rushed', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('local_orders', 'completed', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('local_orders', 'archived', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('local_orders', 'completed_at_ms', 'INTEGER');
    _ensureColumn('local_orders', 'archived_at_ms', 'INTEGER');
    _ensureColumn(
      'local_orders',
      'cloud_projection_version',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn('local_orders', 'source_channel', 'TEXT');
    _ensureColumn('local_order_lines', 'held', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('local_order_lines', 'rushed', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn('local_order_lines', 'lacked', 'INTEGER NOT NULL DEFAULT 0');
    _ensureColumn(
      'local_order_lines',
      'refunded_quantity',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn(
      'local_order_lines',
      'is_combo',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _ensureColumn('local_order_lines', 'combo_name', 'TEXT');
    _ensureColumn('local_order_lines', 'combo_id', 'INTEGER');
    _ensureColumn(
      'local_order_lines',
      'serving_duration_minutes',
      'INTEGER NOT NULL DEFAULT 10',
    );
    _ensureColumn('local_operation_events', 'command_fingerprint', 'TEXT');
    _ensureColumn('local_operation_events', 'event_seq', 'INTEGER');
    _ensureColumn('local_operation_events', 'actor_device_code', 'TEXT');
    _ensureColumn(
      'local_operation_events',
      'before_state_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    _ensureColumn(
      'local_operation_events',
      'after_state_json',
      "TEXT NOT NULL DEFAULT '{}'",
    );
    _database.execute(
      'DROP INDEX IF EXISTS idx_cloud_outbox_aggregate_sequence',
    );
    _migrateServePrintAggregates();
    _discardPrematureServePrintEventsOnce();
    _resequenceOutboxOnce();
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_kds_lines_queue '
      'ON local_order_lines(workflow_queue, created_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_outbox_due '
      'ON cloud_outbox(state, next_attempt_at_ms, aggregate_key, '
      'aggregate_sequence)',
    );
    _database.execute(
      'CREATE UNIQUE INDEX idx_cloud_outbox_aggregate_sequence '
      'ON cloud_outbox(aggregate_key, aggregate_sequence) '
      "WHERE state != 'discarded'",
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_outbox_active_aggregate_sequence '
      'ON cloud_outbox(aggregate_key, aggregate_sequence) '
      "WHERE state NOT IN ('delivered', 'discarded')",
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_outbox_terminal_retention '
      'ON cloud_outbox(state, delivered_at_ms, updated_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cloud_delivery_inbox_retention '
      'ON cloud_delivery_inbox(received_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_operation_events_retention '
      'ON local_operation_events(occurred_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_kds_devices_shop_heartbeat '
      'ON kds_devices(shop_id, enabled, last_heartbeat_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_event_journal_shop_seq '
      'ON local_event_journal(shop_id, event_seq)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_edge_kds_event_received '
      'ON edge_kds_event_journal(shop_id, received_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_edge_kds_http_cache_expiry '
      'ON edge_kds_http_cache(expires_at_ms, cached_at_ms)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_local_lines_cloud_detail '
      'ON local_order_lines(order_id, cloud_detail_id)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_kds_interaction_shop_time '
      'ON kds_interaction_logs(shop_id, occurred_at_ms DESC)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_kds_interaction_trace_time '
      'ON kds_interaction_logs(trace_id, occurred_at_ms ASC)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_kds_interaction_order_time '
      'ON kds_interaction_logs(shop_id, order_id, occurred_at_ms DESC)',
    );
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_kds_interaction_event_time '
      'ON kds_interaction_logs(event_id, occurred_at_ms ASC)',
    );
    final catalogColumns = _database
        .select("PRAGMA table_info('local_dish_catalog')")
        .map((row) => '${row['name']}'.toLowerCase())
        .toSet();
    if (catalogColumns.isNotEmpty && !catalogColumns.contains('id')) {
      _database.execute('''
        CREATE TABLE local_dish_catalog_v2 (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shop_id INTEGER NOT NULL,
          dish_id INTEGER NOT NULL,
          dish_name TEXT NOT NULL,
          unit TEXT NOT NULL,
          sort_index INTEGER NOT NULL,
          category_id INTEGER,
          category_name TEXT,
          category_sequence INTEGER,
          dish_sequence INTEGER,
          stock INTEGER,
          onsale INTEGER NOT NULL DEFAULT 1,
          sold_out INTEGER NOT NULL DEFAULT 0,
          updated_at_ms INTEGER NOT NULL
        )
      ''');
      _database.execute('''
        INSERT INTO local_dish_catalog_v2 (
          shop_id, dish_id, dish_name, unit, sort_index, category_id,
          category_name, category_sequence, dish_sequence, stock, onsale,
          sold_out, updated_at_ms
        )
        SELECT shop_id, dish_id, dish_name, unit, sort_index, category_id,
          category_name, category_sequence, dish_sequence, stock, onsale,
          sold_out, updated_at_ms
        FROM local_dish_catalog
        ORDER BY COALESCE(category_sequence, sort_index) ASC,
          COALESCE(category_id, 0) ASC,
          COALESCE(dish_sequence, sort_index) ASC, dish_id ASC
      ''');
      _database.execute('DROP TABLE local_dish_catalog');
      _database.execute(
        'ALTER TABLE local_dish_catalog_v2 RENAME TO local_dish_catalog',
      );
    }
    _database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_dish_catalog_shop_dish '
      'ON local_dish_catalog(shop_id, dish_id)',
    );
    // D026 设备级岗分流：菜品所属岗（收银端随菜品数据传入）+ 设备可见岗集合。
    _ensureColumn('local_dish_catalog', 'screen_tag', 'TEXT');
    _ensureColumn('kds_devices', 'screen_tags_json', 'TEXT');
    _database.execute(
      'CREATE INDEX IF NOT EXISTS idx_dish_catalog_shop_id '
      'ON local_dish_catalog(shop_id, id)',
    );
    _database.execute(
      "INSERT OR REPLACE INTO local_kds_meta(meta_key, meta_value) "
      "VALUES ('schema_version', '2')",
    );
    _database.execute(
      "INSERT OR IGNORE INTO local_kds_meta(meta_key, meta_value) VALUES "
      "('primary_node_id', ?)",
      ['cashier-${DateTime.now().microsecondsSinceEpoch}'],
    );
  }

  void _migrateLegacyPendingCommands() {
    try {
      _database.execute('SELECT 1 FROM pending_commands_legacy LIMIT 1');
    } catch (_) {
      return; // No legacy table to migrate
    }
    final legacyRows = _database.select(
      'SELECT * FROM pending_commands_legacy',
    );
    if (legacyRows.isEmpty) {
      _database.execute('DROP TABLE pending_commands_legacy');
      return;
    }
    final migratedAt = DateTime.now().millisecondsSinceEpoch;
    _safeBegin();
    try {
      for (final row in legacyRows) {
        final shopId = _int(row['shop_id']);
        final commandId = '${row['command_id'] ?? ''}'.trim();
        final payloadJson = '${row['payload_json'] ?? '{}'}';
        if (shopId <= 0 || commandId.isEmpty) continue;
        final payload = _jsonMap(payloadJson);
        final fingerprint = commandRequestFingerprint(shopId, payload);
        final legacyStatus = '${row['status'] ?? 'pending'}'.toLowerCase();
        final status = legacyStatus == 'completed'
            ? 'APPLIED'
            : legacyStatus == 'failed'
            ? 'REJECTED'
            : 'PENDING';
        final occurredAt = _int(row['occurred_at_ms']);
        _database.execute(
          'INSERT OR IGNORE INTO pending_commands '
          '(shop_id, command_id, actor_id, actor_type, command_type, '
          'request_hash, target_json, payload_json, occurred_at_ms, status, '
          'result_json, attempt_count, next_attempt_at_ms, created_at, updated_at) '
          "VALUES (?, ?, 'MIGRATED', 'KDS', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [
            shopId,
            commandId,
            '${row['command_type'] ?? 'unknown'}',
            fingerprint,
            '${row['target_json'] ?? '{}'}',
            payloadJson,
            occurredAt,
            status,
            row['result_json'],
            _int(row['attempt_count']),
            _int(row['next_attempt_at_ms']),
            occurredAt > 0 ? occurredAt : migratedAt,
            migratedAt,
          ],
        );
      }
      _database.execute('DROP TABLE pending_commands_legacy');
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  static String commandRequestFingerprint(
    int shopId,
    Map<String, Object?> request,
  ) {
    final requestWithoutId = Map<String, Object?>.from(request)
      ..remove('command_id');
    final canonical = jsonEncode(
      _canonicalJson({'shop_id': shopId, 'request': requestWithoutId}),
    );
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  void insertPendingCommand({
    required String commandId,
    required int shopId,
    required String commandType,
    required String targetJson,
    required String payloadJson,
    required int occurredAtMs,
    required String actorId,
  }) {
    final fingerprint = commandRequestFingerprint(
      shopId,
      _jsonMap(payloadJson),
    );
    _safeBegin();
    try {
      _database.execute(
        'INSERT OR IGNORE INTO pending_commands '
        '(shop_id, command_id, actor_id, actor_type, command_type, '
        'request_hash, target_json, payload_json, '
        'occurred_at_ms, status, created_at, updated_at) '
        "VALUES (?, ?, ?, 'KDS', ?, ?, ?, ?, ?, 'PENDING', ?, ?)",
        [
          shopId,
          commandId,
          actorId,
          commandType,
          fingerprint,
          targetJson,
          payloadJson,
          occurredAtMs,
          occurredAtMs,
          occurredAtMs,
        ],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  Map<String, Object?>? readPendingCommand(int shopId, String commandId) {
    final rows = _database.select(
      'SELECT * FROM pending_commands '
      'WHERE shop_id = ? AND command_id = ? LIMIT 1',
      [shopId, commandId],
    );
    if (rows.isEmpty) return null;
    final row = Map<String, Object?>.from(rows.single);
    row['request_fingerprint'] = row['request_hash'];
    return row;
  }

  void updatePendingCommandStatus(
    int shopId,
    String commandId,
    String status, {
    String? resultJson,
    String? lastError,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _safeBegin();
    try {
      if (resultJson != null) {
        _database.execute(
          'UPDATE pending_commands SET status = ?, result_json = ?, '
          'last_error = ?, updated_at = ? '
          'WHERE shop_id = ? AND command_id = ?',
          [status, resultJson, lastError, nowMs, shopId, commandId],
        );
      } else {
        _database.execute(
          'UPDATE pending_commands SET status = ?, last_error = ?, '
          'updated_at = ? WHERE shop_id = ? AND command_id = ?',
          [status, lastError, nowMs, shopId, commandId],
        );
      }
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  List<Map<String, Object?>> readAllPendingCommands() {
    return _database.select(
      "SELECT * FROM pending_commands WHERE status IN ('PENDING', 'UNKNOWN') "
      'ORDER BY occurred_at_ms ASC',
    );
  }

  List<Map<String, Object?>> readDuePendingCommands({
    required int nowMs,
    int limit = 50,
  }) {
    final boundedLimit = limit.clamp(1, 500);
    return _database.select(
      "SELECT * FROM pending_commands WHERE status IN ('PENDING', 'UNKNOWN') "
      'AND next_attempt_at_ms <= ? '
      'ORDER BY next_attempt_at_ms ASC, occurred_at_ms ASC LIMIT ?',
      [nowMs, boundedLimit],
    );
  }

  void markPendingCommandSending(int shopId, String commandId, int nowMs) {
    _database.execute(
      "UPDATE pending_commands SET status = 'SENDING', "
      'updated_at = ? '
      "WHERE shop_id = ? AND command_id = ? AND status IN ('PENDING', 'UNKNOWN')",
      [nowMs, shopId, commandId],
    );
  }

  void reschedulePendingCommand(
    int shopId,
    String commandId,
    int nextAttemptAtMs,
    int attemptCount,
    String lastError,
  ) {
    _database.execute(
      "UPDATE pending_commands SET status = 'UNKNOWN', "
      'next_attempt_at_ms = ?, attempt_count = ?, last_error = ?, '
      'updated_at = ? WHERE shop_id = ? AND command_id = ?',
      [
        nextAttemptAtMs,
        attemptCount,
        lastError,
        DateTime.now().millisecondsSinceEpoch,
        shopId,
        commandId,
      ],
    );
  }

  CashierOrderReceipt createOrder(
    CashierOrderDraft draft, {
    required String eventId,
    int? cloudOrderId,
    String? cloudOrderNo,
    bool enqueueCloudEvent = true,
  }) {
    if (draft.shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    if (draft.lines.isEmpty) {
      throw const CashierKdsValidation('order lines cannot be empty');
    }
    if (!const {
      'dine_in',
      'takeout',
      'pickup',
      'pack',
      'delivery',
    }.contains(draft.fulfillmentType.trim())) {
      throw const CashierKdsValidation('invalid fulfillment_bucket');
    }
    for (final line in draft.lines) {
      if (line.dishId <= 0 ||
          line.dishName.trim().isEmpty ||
          line.quantity <= 0) {
        throw const CashierKdsValidation('invalid order line');
      }
    }

    final requestFingerprint = _orderRequestFingerprint(draft);
    _safeBegin();
    try {
      if (cloudOrderId != null && cloudOrderId > 0) {
        final existing = _database.select(
          'SELECT id, order_no FROM local_orders '
          'WHERE shop_id = ? AND cloud_order_id = ?',
          [draft.shopId, cloudOrderId],
        );
        if (existing.isNotEmpty) {
          final result = CashierOrderReceipt(
            orderId: _int(existing.first['id']),
            orderNo: '${existing.first['order_no']}',
            duplicate: true,
            eventSeq: _eventSeqFor(eventId),
            eventId: eventId,
          );
          _database.execute('COMMIT');
          return result;
        }
      }
      final duplicate = _database.select(
        'SELECT payload_json, request_fingerprint FROM cloud_outbox '
        'WHERE event_id = ?',
        [eventId],
      );
      if (duplicate.isNotEmpty) {
        final storedFingerprint =
            '${duplicate.first['request_fingerprint'] ?? ''}';
        if (storedFingerprint.isNotEmpty &&
            storedFingerprint != requestFingerprint) {
          throw const CashierKdsValidation(
            'clientRequestId was already used with different order data',
          );
        }
        final payload = _jsonMap(duplicate.first['payload_json']);
        final result = CashierOrderReceipt(
          orderId: _int(payload['local_order_id']),
          orderNo: '${payload['order_no'] ?? ''}',
          duplicate: true,
          eventSeq: _eventSeqFor(eventId),
          eventId: eventId,
        );
        _database.execute('COMMIT');
        return result;
      }

      _database.execute(
        'INSERT INTO local_orders '
        '(shop_id, order_no, table_number, fulfillment_type, remark, '
        'number_of_diners, cloud_order_id, cloud_order_no, created_at_ms, '
        'updated_at_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          draft.shopId,
          cloudOrderNo?.trim().isNotEmpty == true
              ? cloudOrderNo!.trim()
              : 'pending:$eventId',
          draft.tableNumber.trim(),
          draft.fulfillmentType.trim(),
          draft.remark.trim(),
          draft.numberOfDiners,
          cloudOrderId,
          cloudOrderNo?.trim(),
          draft.createdAtMs,
          draft.createdAtMs,
        ],
      );
      final orderId = _database.lastInsertRowId;
      final orderNo = cloudOrderNo?.trim().isNotEmpty == true
          ? cloudOrderNo!.trim()
          : 'L${draft.createdAtMs}-$orderId';
      if (cloudOrderNo?.trim().isNotEmpty != true) {
        _database.execute('UPDATE local_orders SET order_no = ? WHERE id = ?', [
          orderNo,
          orderId,
        ]);
      }
      final payloadLines = <Map<String, Object?>>[];
      for (final line in draft.lines) {
        _database.execute(
          'INSERT INTO local_order_lines '
          '(order_id, dish_id, dish_name, specification, unit, line_quantity, '
          'prep_remaining, cook_remaining, ready_remaining, workflow_queue, '
          'cloud_detail_id, is_combo, combo_name, combo_id, '
          'serving_duration_minutes, created_at_ms, updated_at_ms) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            orderId,
            line.dishId,
            line.dishName.trim(),
            line.specification.trim(),
            line.unit.trim().isEmpty ? '份' : line.unit.trim(),
            line.quantity,
            line.quantity,
            line.quantity,
            line.quantity,
            'pending_prep',
            line.cloudDetailId,
            line.isCombo ? 1 : 0,
            line.comboName?.trim().isNotEmpty == true
                ? line.comboName!.trim()
                : null,
            line.comboId != null && line.comboId! > 0 ? line.comboId : null,
            line.servingDurationMinutes,
            draft.createdAtMs,
            draft.createdAtMs,
          ],
        );
        payloadLines.add({
          'local_detail_id': _database.lastInsertRowId,
          ...line.toJson(),
        });
      }
      final payload = <String, Object?>{
        'event_id': eventId,
        'local_order_id': orderId,
        'order_no': orderNo,
        'shop_id': draft.shopId,
        'table_number': draft.tableNumber.trim(),
        'fulfillment_type': draft.fulfillmentType.trim(),
        'remark': draft.remark.trim(),
        'number_of_diners': draft.numberOfDiners,
        'created_at_ms': draft.createdAtMs,
        'lines': payloadLines,
        // KDS 侧用 cloud_order_id 显示云端订单数字 ID；缺失时回退订单号。
        if (cloudOrderId != null && cloudOrderId > 0)
          'cloud_order_id': cloudOrderId,
        if (cloudOrderNo != null && cloudOrderNo.trim().isNotEmpty)
          'cloud_order_no': cloudOrderNo,
      };
      final journalRows = _database.select(
        'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
        'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
        'WHERE l.order_id = ? ORDER BY l.id',
        [orderId],
      );
      final journalPatches = journalRows
          .map(_linePatch)
          .toList(growable: false);
      final eventSeq = _insertJournalEvent(
        eventId: eventId,
        shopId: draft.shopId,
        eventType: 'order_created',
        aggregateKey: 'order:$orderId',
        patches: journalPatches,
        occurredAtMs: draft.createdAtMs,
      );
      for (final patch in journalPatches) {
        patch['event_seq'] = eventSeq;
      }
      _database.execute(
        'UPDATE local_event_journal SET patches_json = ? WHERE event_seq = ?',
        [jsonEncode(journalPatches), eventSeq],
      );
      payload['event_seq'] = eventSeq;
      if (enqueueCloudEvent) {
        _insertCloudEvent(
          eventId: eventId,
          shopId: draft.shopId,
          eventType: 'order_created',
          aggregateKey: 'order:$orderId',
          payload: payload,
          nowMs: draft.createdAtMs,
          requestFingerprint: requestFingerprint,
        );
      }
      _database.execute('COMMIT');
      return CashierOrderReceipt(
        orderId: orderId,
        orderNo: orderNo,
        eventSeq: eventSeq,
        eventId: eventId,
      );
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierOrderReceipt appendOrderLines({
    required int shopId,
    required String orderNo,
    required List<CashierOrderLineDraft> lines,
    required String eventId,
    String? clientRequestId,
    bool enqueueCloudEvent = true,
  }) {
    if (shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    if (orderNo.trim().isEmpty) {
      throw const CashierKdsValidation('orderNo cannot be empty');
    }
    if (lines.isEmpty) {
      throw const CashierKdsValidation('lines cannot be empty');
    }
    for (final line in lines) {
      if (line.dishId <= 0 ||
          line.dishName.trim().isEmpty ||
          line.quantity <= 0) {
        throw const CashierKdsValidation('invalid order line');
      }
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _safeBegin();
    try {
      final orderRows = _database.select(
        'SELECT * FROM local_orders WHERE shop_id = ? AND (order_no = ? OR cloud_order_no = ?)',
        [shopId, orderNo.trim(), orderNo.trim()],
      );
      if (orderRows.isEmpty) {
        throw const CashierKdsValidation('order not found');
      }
      final orderRow = orderRows.first;
      final orderId = _int(orderRow['id']);
      final resolvedOrderNo = '${orderRow['order_no']}';
      final cloudOrderId = _int(orderRow['cloud_order_id']);
      final cloudOrderNo = '${orderRow['cloud_order_no'] ?? ''}'.trim();
      final tableNumber = '${orderRow['table_number'] ?? ''}'.trim();

      final duplicate = _database.select(
        'SELECT payload_json FROM cloud_outbox WHERE event_id = ?',
        [eventId],
      );
      if (duplicate.isNotEmpty) {
        final result = CashierOrderReceipt(
          orderId: orderId,
          orderNo: resolvedOrderNo,
          duplicate: true,
          eventSeq: _eventSeqFor(eventId),
          eventId: eventId,
        );
        _database.execute('COMMIT');
        return result;
      }

      final payloadLines = <Map<String, Object?>>[];
      for (final line in lines) {
        _database.execute(
          'INSERT INTO local_order_lines '
          '(order_id, dish_id, dish_name, specification, unit, line_quantity, '
          'prep_remaining, cook_remaining, ready_remaining, workflow_queue, '
          'cloud_detail_id, is_combo, combo_name, combo_id, '
          'serving_duration_minutes, created_at_ms, updated_at_ms) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            orderId,
            line.dishId,
            line.dishName.trim(),
            line.specification.trim(),
            line.unit.trim().isEmpty ? '份' : line.unit.trim(),
            line.quantity,
            line.quantity,
            line.quantity,
            line.quantity,
            'pending_prep',
            line.cloudDetailId,
            line.isCombo ? 1 : 0,
            line.comboName?.trim().isNotEmpty == true
                ? line.comboName!.trim()
                : null,
            line.comboId != null && line.comboId! > 0 ? line.comboId : null,
            line.servingDurationMinutes,
            nowMs,
            nowMs,
          ],
        );
        final localDetailId = _database.lastInsertRowId;
        payloadLines.add({'local_detail_id': localDetailId, ...line.toJson()});
      }

      _database.execute(
        'UPDATE local_orders SET updated_at_ms = ? WHERE id = ?',
        [nowMs, orderId],
      );

      final journalRows = _database.select(
        'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
        'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
        'WHERE l.order_id = ? ORDER BY l.id',
        [orderId],
      );
      final journalPatches = journalRows
          .map(_linePatch)
          .toList(growable: false);
      final eventSeq = _insertJournalEvent(
        eventId: eventId,
        shopId: shopId,
        eventType: 'dishes_added',
        aggregateKey: 'order:$orderId',
        patches: journalPatches,
        occurredAtMs: nowMs,
      );
      for (final patch in journalPatches) {
        patch['event_seq'] = eventSeq;
      }
      _database.execute(
        'UPDATE local_event_journal SET patches_json = ? WHERE event_seq = ?',
        [jsonEncode(journalPatches), eventSeq],
      );

      final payload = <String, Object?>{
        'event_id': eventId,
        'local_order_id': orderId,
        'order_no': resolvedOrderNo,
        'shop_id': shopId,
        'table_number': tableNumber,
        'created_at_ms': nowMs,
        'lines': payloadLines,
        'event_seq': eventSeq,
        if (cloudOrderId > 0) 'cloud_order_id': cloudOrderId,
        if (cloudOrderNo.isNotEmpty) 'cloud_order_no': cloudOrderNo,
      };

      if (enqueueCloudEvent) {
        _insertCloudEvent(
          eventId: eventId,
          shopId: shopId,
          eventType: 'dishes_added',
          aggregateKey: 'order:$orderId',
          payload: payload,
          nowMs: nowMs,
          requestFingerprint: clientRequestId,
        );
      }
      _database.execute('COMMIT');
      return CashierOrderReceipt(
        orderId: orderId,
        orderNo: resolvedOrderNo,
        eventSeq: eventSeq,
        eventId: eventId,
      );
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierOrderReceipt refundOrderLine({
    required int shopId,
    required String orderNo,
    required int detailId,
    required int quantity,
    String? stockAction,
    String? reason,
    required String eventId,
    bool enqueueCloudEvent = true,
  }) {
    if (shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    if (orderNo.trim().isEmpty) {
      throw const CashierKdsValidation('orderNo cannot be empty');
    }
    if (detailId <= 0) {
      throw const CashierKdsValidation('detailId must be positive');
    }
    if (quantity <= 0) {
      throw const CashierKdsValidation('quantity must be positive');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _safeBegin();
    try {
      final orderRows = _database.select(
        'SELECT * FROM local_orders WHERE shop_id = ? AND (order_no = ? OR cloud_order_no = ?)',
        [shopId, orderNo.trim(), orderNo.trim()],
      );
      if (orderRows.isEmpty) {
        throw const CashierKdsValidation('order not found');
      }
      final orderRow = orderRows.first;
      final orderId = _int(orderRow['id']);
      final resolvedOrderNo = '${orderRow['order_no']}';
      final cloudOrderId = _int(orderRow['cloud_order_id']);
      final cloudOrderNo = '${orderRow['cloud_order_no'] ?? ''}'.trim();

      final duplicate = _database.select(
        'SELECT payload_json FROM cloud_outbox WHERE event_id = ?',
        [eventId],
      );
      if (duplicate.isNotEmpty) {
        final result = CashierOrderReceipt(
          orderId: orderId,
          orderNo: resolvedOrderNo,
          duplicate: true,
          eventSeq: _eventSeqFor(eventId),
          eventId: eventId,
        );
        _database.execute('COMMIT');
        return result;
      }

      final lineRows = _database.select(
        'SELECT * FROM local_order_lines WHERE order_id = ? AND (id = ? OR cloud_detail_id = ?)',
        [orderId, detailId, detailId],
      );
      if (lineRows.isEmpty) {
        throw const CashierKdsValidation('order line not found');
      }
      final lineRow = lineRows.first;
      final localLineId = _int(lineRow['id']);
      final cloudDetailId = _int(lineRow['cloud_detail_id']);
      final lineQuantity = _int(lineRow['line_quantity']);
      final currentRefunded = _int(lineRow['refunded_quantity']);

      if (currentRefunded + quantity > lineQuantity) {
        throw const CashierKdsValidation(
          'refund quantity exceeds remaining quantity',
        );
      }

      final newRefunded = currentRefunded + quantity;
      final visible = lineQuantity - newRefunded;
      final newReady = min(_int(lineRow['ready_remaining']), visible);
      final newCook = min(_int(lineRow['cook_remaining']), newReady);
      final newPrep = min(_int(lineRow['prep_remaining']), newCook);
      final newRevision = _int(lineRow['local_revision']) + 1;
      final isDone = newRefunded >= lineQuantity ? 1 : 0;
      final queue = _summaryQueue(newPrep, newCook, newReady);

      _database.execute(
        'UPDATE local_order_lines SET refunded_quantity = ?, prep_remaining = ?, '
        'cook_remaining = ?, ready_remaining = ?, workflow_queue = ?, done_line = ?, '
        'local_revision = ?, updated_at_ms = ? WHERE id = ?',
        [
          newRefunded,
          newPrep,
          newCook,
          newReady,
          queue,
          isDone,
          newRevision,
          nowMs,
          localLineId,
        ],
      );

      _database.execute(
        'UPDATE local_orders SET updated_at_ms = ? WHERE id = ?',
        [nowMs, orderId],
      );

      final journalRows = _database.select(
        'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
        'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
        'WHERE l.order_id = ? ORDER BY l.id',
        [orderId],
      );
      final journalPatches = journalRows
          .map(_linePatch)
          .toList(growable: false);
      final eventSeq = _insertJournalEvent(
        eventId: eventId,
        shopId: shopId,
        eventType: 'refund_item',
        aggregateKey: 'order:$orderId',
        patches: journalPatches,
        occurredAtMs: nowMs,
      );
      for (final patch in journalPatches) {
        patch['event_seq'] = eventSeq;
      }
      _database.execute(
        'UPDATE local_event_journal SET patches_json = ? WHERE event_seq = ?',
        [jsonEncode(journalPatches), eventSeq],
      );

      final payload = <String, Object?>{
        'event_id': eventId,
        'local_order_id': orderId,
        'order_no': resolvedOrderNo,
        'shop_id': shopId,
        'local_detail_id': localLineId,
        if (cloudDetailId > 0) 'cloud_detail_id': cloudDetailId,
        if (cloudOrderId > 0) 'cloud_order_id': cloudOrderId,
        if (cloudOrderNo.isNotEmpty) 'cloud_order_no': cloudOrderNo,
        'quantity': quantity,
        'stock_action': stockAction ?? 'RESTORE',
        'reason': reason ?? '',
        'created_at_ms': nowMs,
        'event_seq': eventSeq,
      };

      if (enqueueCloudEvent) {
        _insertCloudEvent(
          eventId: eventId,
          shopId: shopId,
          eventType: 'refund_item',
          aggregateKey: 'order:$orderId',
          payload: payload,
          nowMs: nowMs,
        );
      }
      _database.execute('COMMIT');
      return CashierOrderReceipt(
        orderId: orderId,
        orderNo: resolvedOrderNo,
        eventSeq: eventSeq,
        eventId: eventId,
      );
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierOrderReceipt applyCloudDeliveryEvent(
    Map<String, Object?> event, {
    bool manageTransaction = true,
  }) {
    final eventId = '${event['eventId'] ?? ''}'.trim();
    final cursor = _int(event['cursor']);
    final projection = event['projection'];
    if (eventId.isEmpty || cursor <= 0 || projection is! Map) {
      throw const CashierKdsValidation('invalid cloud KDS delivery event');
    }
    final p = projection.cast<String, Object?>();
    final shopId = _int(p['shopId'] ?? event['shopId']);
    final cloudOrderId = _int(p['orderId'] ?? event['orderId']);
    final rawVersion =
        p['projectionVersion'] ?? event['projectionVersion'] ?? p['version'];
    final version = _int(rawVersion) > 0 ? _int(rawVersion) : 1;
    final cloudOrderNo =
        '${p['orderNo'] ?? p['order_no'] ?? event['orderNo'] ?? event['order_no'] ?? ''}'
            .trim();
    final rawLines = p['lines'] ?? p['details'] ?? const [];
    if (shopId <= 0 ||
        cloudOrderId <= 0 ||
        version <= 0 ||
        cloudOrderNo.isEmpty ||
        rawLines is! List) {
      throw CashierKdsValidation(
        'invalid cloud order projection: shopId=$shopId, orderId=$cloudOrderId, version=$version, orderNo=$cloudOrderNo, linesType=${rawLines.runtimeType}',
      );
    }
    // 云端投递事件类型：ORDER_ACCEPTED / ORDER_READY / ORDER_UPDATED /
    // ORDER_LINE_VOIDED / ORDER_CANCELLED / ORDER_VOIDED / ORDER_RUSHED /
    // ORDER_CLOSED。投影 state 枚举为 READY / VOIDED / CLOSED；事件类型
    // 在 state 缺失时兜底，并携带整单加急等事件级语义。
    final eventType = '${event['eventType'] ?? ''}'.trim().toUpperCase();
    var state = '${p['state'] ?? ''}'.trim().toUpperCase();
    if (state.isEmpty) {
      state = switch (eventType) {
        'ORDER_CANCELLED' || 'ORDER_VOIDED' => 'VOIDED',
        'ORDER_CLOSED' => 'CLOSED',
        _ => 'READY',
      };
    }
    final orderRushed = eventType == 'ORDER_RUSHED';
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (manageTransaction) _safeBegin();
    try {
      final duplicate = _database.select(
        'SELECT order_id FROM cloud_delivery_inbox WHERE event_id = ?',
        [eventId],
      );
      if (duplicate.isNotEmpty) {
        final localId = _int(duplicate.first['order_id']);
        final order = _database.select(
          'SELECT order_no FROM local_orders WHERE id = ?',
          [localId],
        );
        if (manageTransaction) _database.execute('COMMIT');
        return CashierOrderReceipt(
          orderId: localId,
          orderNo: order.isEmpty ? cloudOrderNo : '${order.first['order_no']}',
          duplicate: true,
          eventId: eventId,
        );
      }
      final existing = _database.select(
        'SELECT id, cloud_projection_version FROM local_orders '
        'WHERE shop_id = ? AND cloud_order_id = ?',
        [shopId, cloudOrderId],
      );
      late final int localOrderId;
      final priorVersion = existing.isEmpty
          ? 0
          : _int(existing.first['cloud_projection_version']);
      if (existing.isEmpty) {
        _database.execute(
          'INSERT INTO local_orders '
          '(shop_id,order_no,table_number,fulfillment_type,remark,'
          'number_of_diners,cloud_order_id,cloud_order_no,cloud_projection_version,'
          'source_channel,created_at_ms,updated_at_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            shopId,
            cloudOrderNo,
            '${p['tableNumber'] ?? ''}',
            _localFulfillment(
              '${p['fulfillmentType'] ?? p['fulfillment_type'] ?? ''}',
              tableNumber: '${p['tableNumber'] ?? ''}',
            ),
            '${p['orderRemark'] ?? ''}',
            _int(p['numberOfDiners']),
            cloudOrderId,
            cloudOrderNo,
            version,
            '${p['sourceChannel'] ?? ''}',
            _int(p['createdAtMs']) > 0 ? _int(p['createdAtMs']) : nowMs,
            nowMs,
          ],
        );
        localOrderId = _database.lastInsertRowId;
      } else {
        localOrderId = _int(existing.first['id']);
      }
      if (version > priorVersion) {
        for (final raw in rawLines.whereType<Map>()) {
          _applyCloudProjectionLine(
            localOrderId: localOrderId,
            line: raw.cast<String, Object?>(),
            nowMs: nowMs,
          );
        }
        _database.execute(
          "UPDATE local_orders SET order_no=?,cloud_order_no=?,table_number=?,"
          "fulfillment_type=?,remark=?,number_of_diners=?,cloud_projection_version=?,"
          "source_channel=?,order_status=?,completed=?,archived=?,"
          "rushed=MAX(rushed,?),updated_at_ms=? WHERE id=?",
          [
            cloudOrderNo,
            cloudOrderNo,
            '${p['tableNumber'] ?? ''}',
            _localFulfillment(
              '${p['fulfillmentType'] ?? p['fulfillment_type'] ?? ''}',
              tableNumber: '${p['tableNumber'] ?? ''}',
            ),
            '${p['orderRemark'] ?? ''}',
            _int(p['numberOfDiners']),
            version,
            '${p['sourceChannel'] ?? ''}',
            state == 'READY' ? 'kitchen_pending' : state.toLowerCase(),
            state == 'CLOSED' ? 1 : 0,
            state == 'READY' ? 0 : 1,
            orderRushed ? 1 : 0,
            nowMs,
            localOrderId,
          ],
        );
        if (state != 'READY') {
          _database.execute(
            'UPDATE local_order_lines SET prep_remaining=0,cook_remaining=0,'
            'ready_remaining=0,done_line=1,updated_at_ms=? WHERE order_id=?',
            [nowMs, localOrderId],
          );
        }
      } else {
        _database.execute(
          'UPDATE local_orders SET order_status=?,completed=?,archived=?,'
          'rushed=MAX(rushed,?),updated_at_ms=? WHERE id=?',
          [
            state == 'READY' ? 'kitchen_pending' : state.toLowerCase(),
            state == 'CLOSED' ? 1 : 0,
            state == 'READY' ? 0 : 1,
            orderRushed ? 1 : 0,
            nowMs,
            localOrderId,
          ],
        );
      }
      final journalRows = _database.select(
        'SELECT l.*,o.order_no,o.table_number,o.fulfillment_type,o.remark '
        'FROM local_order_lines l JOIN local_orders o ON o.id=l.order_id '
        'WHERE l.order_id=? ORDER BY l.id',
        [localOrderId],
      );
      final patches = journalRows.map(_linePatch).toList(growable: false);
      final eventSeq = _insertJournalEvent(
        eventId: 'cloud:$eventId',
        shopId: shopId,
        eventType: '${event['eventType'] ?? 'order_updated'}'.toLowerCase(),
        aggregateKey: 'order:$localOrderId',
        patches: patches,
        occurredAtMs: _int(event['occurredAtMs']) > 0
            ? _int(event['occurredAtMs'])
            : nowMs,
      );
      _database.execute(
        'INSERT INTO cloud_delivery_inbox '
        '(event_id,shop_id,cursor,order_id,projection_version,received_at_ms) '
        'VALUES (?,?,?,?,?,?)',
        [eventId, shopId, cursor, localOrderId, version, nowMs],
      );
      if (manageTransaction) _database.execute('COMMIT');
      return CashierOrderReceipt(
        orderId: localOrderId,
        orderNo: cloudOrderNo,
        duplicate: version <= priorVersion,
        eventSeq: eventSeq,
        eventId: 'cloud:$eventId',
      );
    } catch (_) {
      if (manageTransaction) _safeRollback();
      rethrow;
    }
  }

  CashierOrderReceipt applyCloudLineStatusEvent(
    Map<String, Object?> event, {
    bool manageTransaction = true,
  }) {
    final eventId = '${event['eventId'] ?? ''}'.trim();
    final cursor = _int(event['cursor']);
    final projection = event['projection'];
    if (eventId.isEmpty || cursor <= 0 || projection is! Map) {
      throw const CashierKdsValidation('invalid cloud KDS line-status event');
    }
    final p = projection.cast<String, Object?>();
    final shopId = _int(p['shopId'] ?? event['shopId']);
    final cloudOrderId = _int(p['orderId'] ?? event['orderId']);
    final rawLines = p['lines'] ?? p['details'] ?? const [];
    if (shopId <= 0 || cloudOrderId <= 0 || rawLines is! List) {
      throw CashierKdsValidation(
        'invalid cloud KDS line-status payload: shopId=$shopId, orderId=$cloudOrderId, linesType=${rawLines.runtimeType}',
      );
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (manageTransaction) _safeBegin();
    try {
      final duplicate = _database.select(
        'SELECT order_id FROM cloud_delivery_inbox WHERE event_id = ?',
        [eventId],
      );
      if (duplicate.isNotEmpty) {
        final localOrderId = _int(duplicate.single['order_id']);
        final order = _database.select(
          'SELECT order_no FROM local_orders WHERE id = ?',
          [localOrderId],
        );
        if (manageTransaction) _database.execute('COMMIT');
        return CashierOrderReceipt(
          orderId: localOrderId,
          orderNo: order.isEmpty ? '' : '${order.single['order_no']}',
          duplicate: true,
          eventId: 'cloud:$eventId',
        );
      }

      final order = _database.select(
        'SELECT id,order_no FROM local_orders '
        'WHERE shop_id=? AND cloud_order_id=? LIMIT 1',
        [shopId, cloudOrderId],
      );
      if (order.isEmpty) {
        throw const CashierKdsValidation(
          'cloud line-status order projection has not arrived',
        );
      }
      final localOrderId = _int(order.single['id']);
      var changed = false;
      for (final raw in rawLines.whereType<Map>()) {
        final delta = raw.cast<String, Object?>();
        final cloudDetailId = _int(delta['detailId'] ?? delta['detail_id']);
        if (cloudDetailId <= 0) continue;
        final rows = _database.select(
          'SELECT * FROM local_order_lines '
          'WHERE order_id=? AND cloud_detail_id=? LIMIT 1',
          [localOrderId, cloudDetailId],
        );
        if (rows.isEmpty) continue;
        final line = rows.single;
        final quantity = _int(line['line_quantity']);
        final archived = _int(delta['archived']) == 1;
        final targetPrep = archived
            ? 0
            : (quantity - _int(delta['prepQuantity'] ?? delta['prep_quantity']))
                  .clamp(0, quantity)
                  .toInt();
        final targetCook = archived
            ? 0
            : (quantity -
                      _int(delta['cookedQuantity'] ?? delta['cooked_quantity']))
                  .clamp(0, quantity)
                  .toInt();
        final targetReady = archived
            ? 0
            : (quantity -
                      _int(delta['servedQuantity'] ?? delta['served_quantity']))
                  .clamp(0, quantity)
                  .toInt();
        // Cloud status deltas may confirm forward progress but must never rewind the
        // cashier's locally acknowledged kitchen state.
        final prep = min(_int(line['prep_remaining']), targetPrep);
        final cook = min(_int(line['cook_remaining']), targetCook);
        final ready = min(_int(line['ready_remaining']), targetReady);
        final queue = _summaryQueue(prep, cook, ready);
        final rushed = max(
          _int(line['rushed']),
          _int(delta['rushFlag'] ?? delta['rush_flag']),
        );
        if (prep == _int(line['prep_remaining']) &&
            cook == _int(line['cook_remaining']) &&
            ready == _int(line['ready_remaining']) &&
            rushed == _int(line['rushed'])) {
          continue;
        }
        _database.execute(
          'UPDATE local_order_lines SET prep_remaining=?,cook_remaining=?,'
          'ready_remaining=?,workflow_queue=?,done_line=?,rushed=?,'
          'completed_at_ms=CASE WHEN ?=1 AND completed_at_ms IS NULL THEN ? '
          'ELSE completed_at_ms END,local_revision=local_revision+1,'
          'updated_at_ms=? WHERE id=?',
          [
            prep,
            cook,
            ready,
            queue,
            queue == 'done' ? 1 : 0,
            rushed,
            queue == 'done' ? 1 : 0,
            _int(delta['updatedAtMs'] ?? delta['updated_at_ms']) > 0
                ? _int(delta['updatedAtMs'] ?? delta['updated_at_ms'])
                : nowMs,
            nowMs,
            line['id'],
          ],
        );
        changed = true;
      }

      final activeCount = _database.select(
        'SELECT COUNT(*) AS total FROM local_order_lines '
        'WHERE order_id=? AND ready_remaining>0',
        [localOrderId],
      );
      final completed = _int(activeCount.single['total']) == 0;
      _database.execute(
        "UPDATE local_orders SET completed=?,order_status=?,updated_at_ms=? "
        'WHERE id=?',
        [
          completed ? 1 : 0,
          completed ? 'completed' : 'kitchen_pending',
          nowMs,
          localOrderId,
        ],
      );
      final journalRows = _database.select(
        'SELECT l.*,o.order_no,o.table_number,o.fulfillment_type,o.remark '
        'FROM local_order_lines l JOIN local_orders o ON o.id=l.order_id '
        'WHERE l.order_id=? ORDER BY l.id',
        [localOrderId],
      );
      final eventSeq = _insertJournalEvent(
        eventId: 'cloud:$eventId',
        shopId: shopId,
        eventType: 'order_line_status_changed',
        aggregateKey: 'order:$localOrderId',
        patches: journalRows.map(_linePatch).toList(growable: false),
        occurredAtMs: _int(event['occurredAtMs']) > 0
            ? _int(event['occurredAtMs'])
            : nowMs,
      );
      _database.execute(
        'INSERT INTO cloud_delivery_inbox '
        '(event_id,shop_id,cursor,order_id,projection_version,received_at_ms) '
        'VALUES (?,?,?,?,0,?)',
        [eventId, shopId, cursor, localOrderId, nowMs],
      );
      if (manageTransaction) _database.execute('COMMIT');
      return CashierOrderReceipt(
        orderId: localOrderId,
        orderNo: '${order.single['order_no']}',
        duplicate: !changed,
        eventSeq: eventSeq,
        eventId: 'cloud:$eventId',
      );
    } catch (_) {
      if (manageTransaction) _safeRollback();
      rethrow;
    }
  }

  List<CashierOrderReceipt> applyCloudBootstrap({
    required int shopId,
    required int baseCursor,
    required List<Map<String, Object?>> orders,
  }) {
    final receipts = <CashierOrderReceipt>[];
    final runId = DateTime.now().microsecondsSinceEpoch;
    _safeBegin();
    try {
      _database.execute(
        "UPDATE local_orders SET archived=1,order_status='snapshot_replaced',updated_at_ms=? "
        'WHERE shop_id=? AND cloud_order_id IS NOT NULL',
        [DateTime.now().millisecondsSinceEpoch, shopId],
      );
      for (final projection in orders) {
        final orderId = _int(projection['orderId']);
        if (orderId <= 0) {
          continue;
        }
        receipts.add(
          applyCloudDeliveryEvent({
            'eventId':
                'bootstrap:$runId:${projection['orderId']}:${projection['projectionVersion']}',
            'cursor': baseCursor == 0 ? 1 : baseCursor,
            'eventType': 'ORDER_READY',
            'occurredAtMs': DateTime.now().millisecondsSinceEpoch,
            'projection': projection,
          }, manageTransaction: false),
        );
      }
      final staleOrders = _database.select(
        "SELECT id,order_no FROM local_orders WHERE shop_id=? AND archived=1 "
        "AND order_status='snapshot_replaced' AND cloud_order_id IS NOT NULL",
        [shopId],
      );
      for (final stale in staleOrders) {
        final orderId = _int(stale['id']);
        _database.execute(
          'UPDATE local_order_lines SET prep_remaining=0,cook_remaining=0,'
          'ready_remaining=0,done_line=1,updated_at_ms=? WHERE order_id=?',
          [DateTime.now().millisecondsSinceEpoch, orderId],
        );
        final rows = _database.select(
          'SELECT l.*,o.order_no,o.table_number,o.fulfillment_type,o.remark '
          'FROM local_order_lines l JOIN local_orders o ON o.id=l.order_id '
          'WHERE l.order_id=? ORDER BY l.id',
          [orderId],
        );
        final eventId = 'bootstrap-removed:$runId:$orderId';
        final eventSeq = _insertJournalEvent(
          eventId: eventId,
          shopId: shopId,
          eventType: 'order_voided',
          aggregateKey: 'order:$orderId',
          patches: rows.map(_linePatch).toList(growable: false),
          occurredAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        receipts.add(
          CashierOrderReceipt(
            orderId: orderId,
            orderNo: '${stale['order_no']}',
            eventSeq: eventSeq,
            eventId: eventId,
          ),
        );
      }
      commitCloudDeliveryCursor(shopId, baseCursor);
      _database.execute('COMMIT');
      return receipts;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  int readCloudDeliveryCursor(int shopId) {
    final rows = _database.select(
      'SELECT meta_value FROM local_kds_meta WHERE meta_key = ?',
      ['cloud_delivery_cursor:$shopId'],
    );
    return rows.isEmpty ? 0 : _int(rows.first['meta_value']);
  }

  void commitCloudDeliveryCursor(int shopId, int cursor) {
    _database.execute(
      'INSERT OR REPLACE INTO local_kds_meta(meta_key,meta_value) VALUES (?,?)',
      ['cloud_delivery_cursor:$shopId', '$cursor'],
    );
  }

  void writeKdsHttpCache({
    required String cacheKey,
    required int shopId,
    required String path,
    required String varyHash,
    required String bodyJson,
    required int authorityCursor,
    required int cachedAtMs,
    required int expiresAtMs,
    String? etag,
  }) {
    if (cacheKey.isEmpty ||
        shopId <= 0 ||
        path.isEmpty ||
        varyHash.isEmpty ||
        bodyJson.isEmpty ||
        cachedAtMs <= 0 ||
        expiresAtMs <= cachedAtMs) {
      throw const CashierKdsValidation('invalid edge KDS HTTP cache entry');
    }
    _database.execute(
      'INSERT OR REPLACE INTO edge_kds_http_cache '
      '(cache_key,shop_id,path,vary_hash,etag,authority_cursor,body_json,'
      'cached_at_ms,expires_at_ms) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        cacheKey,
        shopId,
        path,
        varyHash,
        etag,
        authorityCursor,
        bodyJson,
        cachedAtMs,
        expiresAtMs,
      ],
    );
    _database.execute(
      'DELETE FROM edge_kds_http_cache WHERE expires_at_ms < ?',
      [cachedAtMs],
    );
    _database.execute(
      'DELETE FROM edge_kds_http_cache WHERE cache_key IN ('
      'SELECT cache_key FROM edge_kds_http_cache '
      'ORDER BY cached_at_ms DESC LIMIT -1 OFFSET 64)',
    );
  }

  ({String bodyJson, String? etag, int authorityCursor, int cachedAtMs})?
  readKdsHttpCache({required String cacheKey, required int nowMs}) {
    final rows = _database.select(
      'SELECT body_json,etag,authority_cursor,cached_at_ms '
      'FROM edge_kds_http_cache '
      'WHERE cache_key=? AND expires_at_ms>=? LIMIT 1',
      [cacheKey, nowMs],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return (
      bodyJson: '${row['body_json']}',
      etag: row['etag'] == null ? null : '${row['etag']}',
      authorityCursor: _int(row['authority_cursor']),
      cachedAtMs: _int(row['cached_at_ms']),
    );
  }

  Map<String, int>? readBusinessDayWindow(int shopId) {
    final rows = _database.select(
      'SELECT meta_key,meta_value FROM local_kds_meta WHERE meta_key IN (?,?)',
      ['business_day_start_ms:$shopId', 'business_day_end_ms:$shopId'],
    );
    final values = <String, int>{
      for (final row in rows) '${row['meta_key']}': _int(row['meta_value']),
    };
    final start = values['business_day_start_ms:$shopId'];
    final end = values['business_day_end_ms:$shopId'];
    if (start == null || end == null || end <= start) return null;
    return {'start_ms': start, 'end_ms': end};
  }

  void commitBusinessDayWindow(
    int shopId, {
    required int startMs,
    required int endMs,
  }) {
    if (endMs <= startMs)
      throw const CashierKdsValidation('invalid business-day range');
    _database.execute(
      'INSERT OR REPLACE INTO local_kds_meta(meta_key,meta_value) VALUES (?,?),(?,?)',
      [
        'business_day_start_ms:$shopId',
        '$startMs',
        'business_day_end_ms:$shopId',
        '$endMs',
      ],
    );
  }

  void _applyCloudProjectionLine({
    required int localOrderId,
    required Map<String, Object?> line,
    required int nowMs,
  }) {
    final cloudDetailId = _int(
      line['detailId'] ??
          line['detail_id'] ??
          line['order_detail_id'] ??
          line['id'],
    );
    final quantity = _int(
      line['quantity'] ?? line['line_quantity'] ?? line['count'] ?? line['qty'],
    );
    final rawCloudRemaining =
        line['remainingQuantity'] ??
        line['remaining_quantity'] ??
        line['prep_remaining'];
    final cloudRemaining = rawCloudRemaining != null
        ? _int(rawCloudRemaining)
        : quantity;
    final dishId = _int(
      line['dishId'] ?? line['dish_id'] ?? line['goods_id'] ?? line['mId'],
    );
    // dishId<=0（套餐头/第三方未映射行）不具备厨房可操作性，
    // 且会让 KDS 严格校验整盘失败，直接跳过不落入状态池
    if (cloudDetailId <= 0 || quantity <= 0 || dishId <= 0) return;
    final existing = _database.select(
      'SELECT * FROM local_order_lines WHERE order_id=? AND cloud_detail_id=?',
      [localOrderId, cloudDetailId],
    );
    // 新版投影行字段：lineType（NORMAL/COMBO_HEADER/COMBO_COMPONENT）、
    // lineStatus（NORMAL/REFUNDED/CANCELLED）、workflowQueue（云端可确定
    // 时给出台位路由）。旧版布尔/下划线字段继续兼容。
    final lineType = '${line['lineType'] ?? line['line_type'] ?? ''}'
        .trim()
        .toUpperCase();
    final lineStatus = '${line['lineStatus'] ?? line['line_status'] ?? ''}'
        .trim()
        .toUpperCase();
    final lineVoided = lineStatus == 'REFUNDED' || lineStatus == 'CANCELLED';
    final cloudQueue =
        '${line['workflowQueue'] ?? line['workflow_queue'] ?? ''}'.trim();
    final isCombo =
        _bool(
          line['is_combo'] ??
              line['is_package'] ??
              line['isCombo'] ??
              line['isPackage'] ??
              line['combo'] ??
              line['set_meal'],
        ) ||
        lineType == 'COMBO_HEADER' ||
        lineType == 'COMBO_COMPONENT' ||
        (line['combo_id'] != null && _int(line['combo_id']) > 0) ||
        (line['comboId'] != null && _int(line['comboId']) > 0) ||
        (line['package_id'] != null && _int(line['package_id']) > 0);
    final comboName =
        '${line['combo_name'] ?? line['package_name'] ?? line['comboName'] ?? line['packageName'] ?? ''}'
            .trim();
    final rawComboId =
        line['combo_id'] ??
        line['package_id'] ??
        line['comboId'] ??
        line['packageId'] ??
        line['parentId'];
    final comboId = rawComboId == null ? null : _int(rawComboId);
    final held = _bool(line['held'] ?? line['is_held'] ?? line['isHeld']);
    final rushed = _bool(
      line['rushed'] ?? line['is_rushed'] ?? line['isRushed'],
    );
    final lacked = _bool(
      line['lacked'] ?? line['is_lacked'] ?? line['isLacked'],
    );
    final refunded = _int(
      line['refundedQuantity'] ??
          line['refunded_quantity'] ??
          line['refund_quantity'],
    );
    final dishName =
        '${line['dishName'] ?? line['dish_name'] ?? line['goods_name'] ?? line['name'] ?? ''}'
            .trim();
    final specification =
        '${line['specification'] ?? line['spec'] ?? line['specs'] ?? line['selectedSpicy'] ?? ''}'
            .trim();
    final unit = '${line['unit'] ?? line['unit_name'] ?? '份'}'.trim();
    final servingDurationMinutes =
        _int(
              line['serving_duration_minutes'] ??
                  line['servingDurationMinutes'],
            ) >
            0
        ? _int(
            line['serving_duration_minutes'] ?? line['servingDurationMinutes'],
          )
        : 10;

    if (existing.isEmpty) {
      final remaining = lineVoided ? 0 : cloudRemaining;
      // 三池是累计语义（prep=未离开配菜、cook=未离开制作、ready=未完成传菜）。
      // 必须按云端队列分配，否则中间队列可见量（cook-prep / ready-cook）恒为 0，
      // KDS 在制作/传菜队列首次划菜必报 quantity exceeds remaining。
      final queue = cloudQueue.isNotEmpty ? cloudQueue : 'pending_prep';
      final (prep, cook, ready) = switch (queue) {
        'pending_cook' => (0, remaining, remaining),
        'ready_serve' || 'done' => (0, 0, remaining),
        _ => (remaining, remaining, remaining),
      };
      _database.execute(
        'INSERT INTO local_order_lines '
        '(order_id,dish_id,dish_name,specification,unit,line_quantity,'
        'prep_remaining,cook_remaining,ready_remaining,workflow_queue,'
        'cloud_detail_id,refunded_quantity,is_combo,combo_name,combo_id,'
        'held,rushed,lacked,serving_duration_minutes,created_at_ms,updated_at_ms) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          localOrderId,
          dishId,
          dishName,
          specification,
          unit.isNotEmpty ? unit : '份',
          quantity,
          prep,
          cook,
          ready,
          queue,
          cloudDetailId,
          lineVoided && refunded < quantity ? quantity : refunded,
          isCombo ? 1 : 0,
          comboName.isNotEmpty ? comboName : null,
          comboId != null && comboId > 0 ? comboId : null,
          held ? 1 : 0,
          rushed ? 1 : 0,
          lacked ? 1 : 0,
          servingDurationMinutes,
          nowMs,
          nowMs,
        ],
      );
      if (lineVoided) {
        _database.execute(
          'UPDATE local_order_lines SET done_line=1 WHERE order_id=? '
          'AND cloud_detail_id=?',
          [localOrderId, cloudDetailId],
        );
      }
      return;
    }
    final old = existing.first;
    final oldQuantity = _int(old['line_quantity']);
    final wasFullyDone =
        _int(old['done_line']) == 1 &&
        _int(old['prep_remaining']) == 0 &&
        _int(old['cook_remaining']) == 0 &&
        _int(old['ready_remaining']) == 0;
    int adjusted(String key) {
      final consumed = (oldQuantity - _int(old[key])).clamp(0, oldQuantity);
      return (quantity - consumed).clamp(0, cloudRemaining).toInt();
    }

    // 三池为累计语义（prep=未离开配菜、cook=未离开制作、ready=未完成传菜）。
    // 以云端队列（缺省取本地摘要队列）为目标：目标队列可见量必须 > 0，
    // 否则说明本地分布与队列语义矛盾（例如历史遗留的三池相等行、或云端
    // 队列权威变更把中间队列可见量压成 0），按目标队列重分配三池，
    // 避免划菜必败（quantity exceeds remaining）。部分划过的行（可见量>0）
    // 保持 adjusted 进度，不得重分配抹掉已划菜进度。
    final localQueue = '${old['workflow_queue'] ?? ''}';
    final targetQueue = cloudQueue.isNotEmpty ? cloudQueue : localQueue;

    // 加菜防回退保护（Fix C）：
    // 若云端投影携带的 workflowQueue 比本地已推进的队列"更靠前"（退步），
    // 且该行已经被部分/全部划走过（三池不全等于 quantity，说明 KDS 已操作过），
    // 则跳过本次覆盖，保留本地进度。
    // 根本原因：服务端 loadLines() 未读 t_kds_ticket，全量投影为 pending_prep；
    // 本保护确保即使服务端发来旧位置，本地 KDS 进度也不会被回退。
    bool _isQueueRewind(String cloud, String local) {
      const order = ['pending_prep', 'pending_cook', 'ready_serve', 'done'];
      final ci = order.indexOf(cloud);
      final li = order.indexOf(local);
      return ci >= 0 && li >= 0 && ci < li;
    }

    final locallyAdvanced =
        !lineVoided &&
        cloudRemaining > 0 &&
        (_int(old['prep_remaining']) < oldQuantity ||
            _int(old['cook_remaining']) < oldQuantity ||
            _int(old['ready_remaining']) < oldQuantity);
    if (!lineVoided &&
        cloudQueue.isNotEmpty &&
        _isQueueRewind(cloudQueue, localQueue) &&
        locallyAdvanced) {
      // 云端投影回退，本地进度领先，保护本地状态不被覆盖。
      // 仅更新菜品描述类字段（名称、规格、单位、备注），不触碰三池和队列。
      _database.execute(
        'UPDATE local_order_lines SET dish_id=?,dish_name=?,specification=?,unit=?,'
        'line_quantity=?,refunded_quantity=?,is_combo=?,combo_name=?,combo_id=?,'
        'held=?,rushed=?,lacked=?,serving_duration_minutes=?,updated_at_ms=? WHERE id=?',
        [
          dishId > 0 ? dishId : _int(old['dish_id']),
          dishName.isNotEmpty ? dishName : '${old['dish_name'] ?? ''}',
          specification.isNotEmpty
              ? specification
              : '${old['specification'] ?? ''}',
          unit.isNotEmpty ? unit : '${old['unit'] ?? '份'}',
          quantity,
          refunded > _int(old['refunded_quantity'])
              ? refunded
              : _int(old['refunded_quantity']),
          isCombo ? 1 : 0,
          comboName.isNotEmpty ? comboName : null,
          comboId != null && comboId > 0 ? comboId : null,
          held ? 1 : 0,
          rushed ? 1 : 0,
          lacked ? 1 : 0,
          servingDurationMinutes,
          nowMs,
          _int(old['id']),
        ],
      );
      return;
    }

    final basePrep = lineVoided ? 0 : adjusted('prep_remaining');
    final baseCook = lineVoided ? 0 : adjusted('cook_remaining');
    final baseReady = lineVoided ? 0 : adjusted('ready_remaining');
    var consistent = true;
    if (!lineVoided && cloudRemaining > 0) {
      consistent = switch (targetQueue) {
        'pending_cook' => (baseCook - basePrep) > 0,
        'ready_serve' || 'done' => (baseReady - baseCook) > 0,
        _ => basePrep > 0,
      };
    }
    late final int prepValue, cookValue, readyValue;
    final addedAfterDone = wasFullyDone
        ? (quantity - oldQuantity).clamp(0, cloudRemaining).toInt()
        : 0;
    if (wasFullyDone) {
      final (nPrep, nCook, nReady) = switch (targetQueue) {
        'pending_cook' => (0, addedAfterDone, addedAfterDone),
        'ready_serve' || 'done' => (0, 0, addedAfterDone),
        _ => (addedAfterDone, addedAfterDone, addedAfterDone),
      };
      prepValue = nPrep;
      cookValue = nCook;
      readyValue = nReady;
    } else if (consistent) {
      prepValue = basePrep;
      cookValue = baseCook;
      readyValue = baseReady;
    } else {
      final (nPrep, nCook, nReady) = switch (targetQueue) {
        'pending_cook' => (0, cloudRemaining, cloudRemaining),
        'ready_serve' || 'done' => (0, 0, cloudRemaining),
        _ => (cloudRemaining, cloudRemaining, cloudRemaining),
      };
      prepValue = nPrep;
      cookValue = nCook;
      readyValue = nReady;
    }

    _database.execute(
      'UPDATE local_order_lines SET dish_id=?,dish_name=?,specification=?,unit=?,'
      'line_quantity=?,prep_remaining=?,cook_remaining=?,ready_remaining=?,'
      'refunded_quantity=?,done_line=?,is_combo=?,combo_name=?,combo_id=?,'
      'held=?,rushed=?,lacked=?,serving_duration_minutes=?,updated_at_ms=? WHERE id=?',
      [
        // 云端行 dishId 缺失时保留既有有效值，不回写为 0
        dishId > 0 ? dishId : _int(old['dish_id']),
        dishName.isNotEmpty ? dishName : '${old['dish_name'] ?? ''}',
        specification.isNotEmpty
            ? specification
            : '${old['specification'] ?? ''}',
        unit.isNotEmpty ? unit : '${old['unit'] ?? '份'}',
        quantity,
        lineVoided ? 0 : prepValue,
        lineVoided ? 0 : cookValue,
        lineVoided ? 0 : readyValue,
        refunded > _int(old['refunded_quantity'])
            ? refunded
            : (lineVoided ? quantity : _int(old['refunded_quantity'])),
        lineVoided ||
                cloudRemaining == 0 ||
                (wasFullyDone && addedAfterDone == 0)
            ? 1
            : 0,
        isCombo ? 1 : 0,
        comboName.isNotEmpty ? comboName : null,
        comboId != null && comboId > 0 ? comboId : null,
        held ? 1 : 0,
        rushed ? 1 : 0,
        lacked ? 1 : 0,
        servingDurationMinutes,
        nowMs,
        _int(old['id']),
      ],
    );
  }

  static String _localFulfillment(String value, {String? tableNumber}) {
    final v = value.toUpperCase().trim();
    if (v == 'PICKUP' ||
        v == 'SELF_PICKUP' ||
        v == 'PACK' ||
        v == '打包' ||
        v == '自提') {
      return 'pickup';
    }
    if (v == 'TAKEOUT' || v == 'TAKEAWAY' || v == '外卖') {
      return 'takeout';
    }
    if (v == 'DELIVERY' || v == '配送') {
      return 'delivery';
    }
    if (v == 'DINE_IN' || v == 'DINEIN' || v == '堂食') {
      return 'dine_in';
    }
    final table = (tableNumber ?? '').trim().toUpperCase();
    if (table == '打包' ||
        table.contains('自提') ||
        RegExp(r'^A\d+').hasMatch(table)) {
      return 'pickup';
    }
    if (table.contains('外卖') || RegExp(r'^B\d+').hasMatch(table)) {
      return 'takeout';
    }
    if (v.isNotEmpty) return value.trim().toLowerCase();
    return 'dine_in';
  }

  CashierAdvancePatch advanceLine({
    required int shopId,
    required int detailId,
    required String fromQueue,
    required int quantity,
    required String operationId,
    required int expectedRevision,
    required int occurredAtMs,
  }) {
    final result = executeKdsCommand(
      LocalKdsCommand(
        commandId: operationId,
        type: LocalKdsCommandType.advanceItem,
        shopId: shopId,
        target: LocalKdsCommandTarget(detailId: detailId, fromQueue: fromQueue),
        quantity: quantity,
        expectedRevision: expectedRevision,
        occurredAtMs: occurredAtMs,
      ),
    );
    final patch = result.patches.single;
    return CashierAdvancePatch(
      operationId: operationId,
      detailId: _int(patch['detail_id']),
      orderId: _int(patch['order_id']),
      fromQueue: '${patch['from_queue'] ?? fromQueue}',
      workflowQueue: '${patch['workflow_queue']}',
      prepRemaining: _int(patch['prep_remaining']),
      cookRemaining: _int(patch['cook_remaining']),
      readyRemaining: _int(patch['ready_remaining']),
      localRevision: _int(patch['local_revision']),
      duplicate: result.duplicate,
    );
  }

  LocalKdsCommandResult executeKdsCommand(LocalKdsCommand command) {
    if (command.commandId.trim().isEmpty || command.commandId.length > 128) {
      throw const CashierKdsValidation('command_id must be 1..128 chars');
    }
    if (command.shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    final actorDeviceCode = command.actorDeviceCode?.trim().isNotEmpty == true
        ? command.actorDeviceCode!.trim()
        : ensureCashierDeviceCode(null);
    final effectiveCommandJson = <String, Object?>{
      ...command.fingerprintJson(),
      'actor_device_code': actorDeviceCode,
    };
    final fingerprint = jsonEncode(_canonicalJson(effectiveCommandJson));
    _safeBegin();
    try {
      final replay = _database.select(
        'SELECT command_fingerprint, result_json FROM local_operation_events '
        'WHERE operation_id = ?',
        [command.commandId],
      );
      if (replay.isNotEmpty) {
        if ('${replay.first['command_fingerprint'] ?? ''}' != fingerprint) {
          throw const CashierKdsValidation(
            'command_id was already used with different command data',
          );
        }
        final result = LocalKdsCommandResult.fromJson(
          _jsonMap(replay.first['result_json']),
        ).asDuplicate();
        _database.execute('COMMIT');
        return result;
      }

      final beforeState = _captureCommandState(command);

      final patches = <Map<String, Object?>>[];
      Map<String, Object?>? orderSummary;
      var aggregateKey = 'shop:${command.shopId}';
      final type = command.type;

      if (type == LocalKdsCommandType.archiveClear) {
        final completedBefore =
            command.occurredAtMs - const Duration(days: 30).inMilliseconds;
        final archived = _database.select(
          'SELECT o.id FROM local_orders o WHERE o.shop_id = ? '
          'AND o.archived = 1 AND o.completed = 1 AND o.completed_at_ms <= ? '
          'AND NOT EXISTS (SELECT 1 FROM cloud_outbox e WHERE '
          "e.aggregate_key = 'order:' || o.id "
          "AND e.state NOT IN ('delivered', 'discarded'))",
          [command.shopId, completedBefore],
        );
        final ids = archived.map((row) => _int(row['id'])).toList();
        for (final orderId in ids) {
          final lines = _database.select(
            'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, '
            'o.remark, o.local_revision AS order_revision '
            'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
            'WHERE l.order_id = ?',
            [orderId],
          );
          patches.addAll(
            lines.map((row) => {..._linePatch(row), 'removed': true}),
          );
          _database.execute(
            'DELETE FROM local_order_lines WHERE order_id = ?',
            [orderId],
          );
          _database.execute('DELETE FROM local_orders WHERE id = ?', [orderId]);
        }
        orderSummary = {'cleared_count': ids.length};
      } else if (_isOrderCommand(type)) {
        final targetOrderId = command.target.orderId;
        if (targetOrderId == null) {
          throw const CashierKdsValidation('target.order_id is required');
        }
        final orderRows = _database.select(
          'SELECT * FROM local_orders WHERE (id = ? OR cloud_order_id = ?) AND shop_id = ?',
          [targetOrderId, targetOrderId, command.shopId],
        );
        if (orderRows.isEmpty) {
          throw const CashierKdsValidation('order not found');
        }
        final order = orderRows.first;
        final orderId = _int(order['id']);
        if (command.expectedRevision == null) {
          throw const CashierKdsValidation('expected_revision is required');
        }
        if (command.expectedRevision != _int(order['local_revision'])) {
          throw const CashierKdsConflict('order revision mismatch');
        }
        aggregateKey = 'order:$orderId';
        if (type == LocalKdsCommandType.advanceOrder) {
          final fromQueue = command.target.fromQueue ?? 'pending_prep';
          final lines = _database
              .select(
                'SELECT l.* FROM local_order_lines l WHERE l.order_id = ? '
                'AND l.held = 0 ORDER BY l.id',
                [orderId],
              )
              .where((row) => _visibleQuantity(row, fromQueue) > 0)
              .toList(growable: false);
          if (lines.isEmpty) {
            throw const CashierKdsConflict('order has no advanceable lines');
          }
          for (final row in lines) {
            _advanceRow(
              row,
              fromQueue: fromQueue,
              quantity: command.quantity,
              occurredAtMs: command.occurredAtMs,
            );
          }
        } else if (type == LocalKdsCommandType.rushOrder) {
          _database.execute(
            'UPDATE local_orders SET rushed = 1, updated_at_ms = ? WHERE id = ?',
            [command.occurredAtMs, orderId],
          );
        } else if (type == LocalKdsCommandType.completeOrder) {
          _database.execute(
            "UPDATE local_order_lines SET workflow_queue = 'done', done_line = 1, "
            'prep_remaining = 0, cook_remaining = 0, ready_remaining = 0, '
            'completed_at_ms = CASE WHEN ready_remaining > 0 THEN ? '
            'ELSE completed_at_ms END, local_revision = local_revision + 1, '
            'updated_at_ms = ? WHERE order_id = ?',
            [command.occurredAtMs, command.occurredAtMs, orderId],
          );
          _database.execute(
            "UPDATE local_orders SET completed = 1, order_status = 'completed', "
            'completed_at_ms = ?, updated_at_ms = ? WHERE id = ?',
            [command.occurredAtMs, command.occurredAtMs, orderId],
          );
        } else if (type == LocalKdsCommandType.archiveOrder) {
          _database.execute(
            'UPDATE local_orders SET archived = 1, archived_at_ms = ?, '
            'updated_at_ms = ? WHERE id = ?',
            [command.occurredAtMs, command.occurredAtMs, orderId],
          );
        }
        final lineRows = _database.select(
          'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
          'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
          'WHERE l.order_id = ? ORDER BY l.id',
          [orderId],
        );
        patches.addAll(lineRows.map((row) => _linePatch(row)));
        orderSummary = _orderSummary(orderId);
      } else {
        final ids = command.target.detailIds.isNotEmpty
            ? command.target.detailIds
            : [if (command.target.detailId != null) command.target.detailId!];
        if (ids.isEmpty) {
          throw const CashierKdsValidation('target.detail_id is required');
        }
        final isMergedAdvance =
            type == LocalKdsCommandType.advanceItem && ids.length > 1;
        if (isMergedAdvance) {
          patches.addAll(_advanceMergedRows(command, ids));
        }
        for (final detailId in isMergedAdvance ? const <int>[] : ids) {
          final rows = _database.select(
            'SELECT l.*, o.shop_id, o.order_no, o.table_number, '
            'o.fulfillment_type, o.remark FROM local_order_lines l '
            'JOIN local_orders o ON o.id = l.order_id '
            'WHERE l.id = ? AND o.shop_id = ?',
            [detailId, command.shopId],
          );
          if (rows.isEmpty) throw const CashierKdsValidation('line not found');
          final row = rows.first;
          final revision = _int(row['local_revision']);
          if (command.expectedRevision == null) {
            throw const CashierKdsValidation('expected_revision is required');
          }
          if (command.expectedRevision != null &&
              command.expectedRevision != revision) {
            throw const CashierKdsConflict('local revision mismatch');
          }
          aggregateKey = 'order:${row['order_id']}';
          if (type == LocalKdsCommandType.advanceItem) {
            final fromQueue = command.target.fromQueue;
            if (fromQueue == null) {
              throw const CashierKdsValidation('target.from_queue is required');
            }
            _advanceRow(
              row,
              fromQueue: fromQueue,
              quantity: command.quantity,
              expectedRevision: command.expectedRevision,
              occurredAtMs: command.occurredAtMs,
            );
          } else if (type == LocalKdsCommandType.revokeItem) {
            _revokeRow(
              row,
              fromQueue: command.target.fromQueue,
              quantity: command.quantity,
              occurredAtMs: command.occurredAtMs,
            );
          } else if (type == LocalKdsCommandType.lackItem) {
            _database.execute(
              'UPDATE local_order_lines SET lacked = 1, local_revision = local_revision + 1, '
              'updated_at_ms = ? WHERE id = ?',
              [command.occurredAtMs, detailId],
            );
            if (command.payload['set_sold_out'] == true) {
              _database.execute(
                'UPDATE local_dish_catalog SET sold_out = 1, updated_at_ms = ? '
                'WHERE shop_id = ? AND dish_id = ?',
                [command.occurredAtMs, command.shopId, row['dish_id']],
              );
            }
          } else if (type == LocalKdsCommandType.refundItem) {
            final quantity = command.quantity ?? 1;
            final fromQueue = command.target.fromQueue;
            if (fromQueue == null) {
              throw const CashierKdsValidation('target.from_queue is required');
            }
            final refunded = _int(row['refunded_quantity']) + quantity;
            final available = _visibleQuantity(row, fromQueue);
            if (quantity <= 0 ||
                quantity > available ||
                refunded > _int(row['line_quantity'])) {
              throw const CashierKdsValidation('invalid refund quantity');
            }
            var prep = _int(row['prep_remaining']);
            var cook = _int(row['cook_remaining']);
            var ready = _int(row['ready_remaining']);
            if (fromQueue == 'pending_prep') {
              prep -= quantity;
              cook -= quantity;
              ready -= quantity;
            } else if (fromQueue == 'pending_cook') {
              cook -= quantity;
              ready -= quantity;
            } else if (fromQueue == 'ready_serve') {
              ready -= quantity;
            } else if (fromQueue != 'done') {
              throw const CashierKdsValidation('invalid refund queue');
            }
            final active = _int(row['line_quantity']) - refunded;
            _database.execute(
              'UPDATE local_order_lines SET refunded_quantity = ?, '
              'prep_remaining = ?, cook_remaining = ?, ready_remaining = ?, '
              'workflow_queue = ?, done_line = ?, '
              'local_revision = local_revision + 1, updated_at_ms = ? WHERE id = ?',
              [
                refunded,
                prep,
                cook,
                ready,
                _summaryQueue(prep, cook, ready),
                active == 0 ? 1 : 0,
                command.occurredAtMs,
                detailId,
              ],
            );
          } else if (type == LocalKdsCommandType.rushItem) {
            _setLineFlag(detailId, 'rushed', true, command.occurredAtMs);
          } else if (type == LocalKdsCommandType.holdItem) {
            _setLineFlag(detailId, 'held', true, command.occurredAtMs);
          } else if (type == LocalKdsCommandType.releaseItem) {
            _setLineFlag(detailId, 'held', false, command.occurredAtMs);
          }
          final updated = _database.select(
            'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
            'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
            'WHERE l.id = ?',
            [detailId],
          ).single;
          patches.add(
            _linePatch(updated, fromQueue: '${row['workflow_queue']}'),
          );
        }
      }

      // removed=true 的行（如全额退菜）依然属于其订单，必须参与订单归属
      // 判定；否则该命令会丢失订单上下文，云端事件落入无订单身份的补丁
      // 分支，云端无法解析 aggregate 前置映射而返回 4090。
      final affectedOrderIds = patches
          .map((patch) => _int(patch['order_id']))
          .where((id) => id > 0)
          .toSet();
      if (affectedOrderIds.length == 1) {
        aggregateKey = 'order:${affectedOrderIds.single}';
      } else if (affectedOrderIds.length > 1) {
        aggregateKey = 'multi:${command.commandId}';
      }
      final orderRevisions = <int, int>{};
      for (final orderId in affectedOrderIds) {
        _database.execute(
          'UPDATE local_orders SET local_revision = local_revision + 1, '
          'updated_at_ms = ? WHERE id = ?',
          [command.occurredAtMs, orderId],
        );
        final rows = _database.select(
          'SELECT local_revision FROM local_orders WHERE id = ?',
          [orderId],
        );
        if (rows.isNotEmpty) {
          orderRevisions[orderId] = _int(rows.single['local_revision']);
        }
      }
      for (final patch in patches) {
        final orderId = _int(patch['order_id']);
        if (orderRevisions[orderId] case final revision?) {
          patch['order_revision'] = revision;
        }
      }
      if (affectedOrderIds.length == 1 &&
          orderRevisions.containsKey(affectedOrderIds.single)) {
        orderSummary = _orderSummary(affectedOrderIds.single);
      }
      final servePrintLines = _servePrintLines(
        command: command,
        beforeState: beforeState,
        patches: patches,
      );

      final eventSeq = _insertJournalEvent(
        eventId: command.commandId,
        shopId: command.shopId,
        eventType: command.type.wireName,
        aggregateKey: aggregateKey,
        patches: patches,
        occurredAtMs: command.occurredAtMs,
      );
      final window = readBusinessDayWindow(command.shopId);
      final result = LocalKdsCommandResult(
        commandId: command.commandId,
        eventSeq: eventSeq,
        patches: patches,
        queueCounts: readQueueCounts(
          command.shopId,
          startMs: window?['start_ms'],
          endMs: window?['end_ms'],
        ),
        orderSummary: orderSummary,
        actorDeviceCode: actorDeviceCode,
      );
      _database.execute(
        'INSERT INTO local_operation_events '
        '(operation_id, shop_id, aggregate_key, operation_type, payload_json, '
        'result_json, occurred_at_ms, command_fingerprint, event_seq, '
        'actor_device_code, before_state_json, after_state_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          command.commandId,
          command.shopId,
          aggregateKey,
          command.type.wireName,
          jsonEncode(effectiveCommandJson),
          jsonEncode(result.toJson()),
          command.occurredAtMs,
          fingerprint,
          eventSeq,
          actorDeviceCode,
          jsonEncode(beforeState),
          jsonEncode(_captureOrderState(affectedOrderIds)),
        ],
      );
      if (type == LocalKdsCommandType.archiveClear ||
          affectedOrderIds.isEmpty) {
        // archiveClear：订单已物理删除，属于本地保留期确认，无可同步的
        // aggregate。affectedOrderIds 为空只可能出现在该场景。
      } else if (affectedOrderIds.length == 1) {
        final orderId = affectedOrderIds.single;
        _insertCloudEvent(
          eventId: command.commandId,
          shopId: command.shopId,
          eventType: 'kds_state_changed',
          aggregateKey: _cloudOrderAggregateKey(orderId),
          payload: _cloudStatePayload(
            orderId: orderId,
            operationType: command.type.wireName,
            commandId: command.commandId,
            operationId: command.commandId,
            eventSeq: eventSeq,
            actorDeviceCode: actorDeviceCode,
          ),
          nowMs: command.occurredAtMs,
          requestFingerprint: fingerprint,
        );
        _insertServePrintEvent(
          command: command,
          orderId: orderId,
          lines: servePrintLines,
          multipleOrders: false,
        );
      } else {
        for (final orderId in affectedOrderIds) {
          final operationId = _derivedCloudEventId(
            command.commandId,
            'order:$orderId',
          );
          _insertCloudEvent(
            eventId: operationId,
            shopId: command.shopId,
            eventType: 'kds_state_changed',
            aggregateKey: _cloudOrderAggregateKey(orderId),
            payload: _cloudStatePayload(
              orderId: orderId,
              operationType: command.type.wireName,
              commandId: command.commandId,
              operationId: operationId,
              eventSeq: eventSeq,
              actorDeviceCode: actorDeviceCode,
            ),
            nowMs: command.occurredAtMs,
            requestFingerprint: fingerprint,
          );
        }
        for (final orderId in affectedOrderIds) {
          _insertServePrintEvent(
            command: command,
            orderId: orderId,
            lines: servePrintLines,
            multipleOrders: true,
          );
        }
      }
      _database.execute('COMMIT');
      return result;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierWorkflowBoard readWorkflowBoard({
    required int shopId,
    required String queue,
    int? startMs,
    int? endMs,
  }) {
    final visibleExpression = switch (queue) {
      'pending_prep' => 'l.prep_remaining > 0',
      'pending_cook' => 'l.cook_remaining - l.prep_remaining > 0',
      'ready_serve' => 'l.ready_remaining - l.cook_remaining > 0',
      'done' => 'l.line_quantity - l.refunded_quantity - l.ready_remaining > 0',
      _ => throw const CashierKdsValidation('invalid workflow queue'),
    };
    final windowClause = (startMs != null && endMs != null && endMs > startMs)
        ? ' AND o.created_at_ms >= ? AND o.created_at_ms < ?'
        : '';
    final args = <Object?>[shopId];
    if (windowClause.isNotEmpty) args.addAll([startMs, endMs]);
    final rows = _database.select('''
      SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark,
        o.local_revision AS order_revision
      FROM local_order_lines l
      JOIN local_orders o ON o.id = l.order_id
      WHERE o.shop_id = ? AND $visibleExpression
        AND o.archived = 0
        AND l.dish_id > 0$windowClause
      ORDER BY l.created_at_ms ASC, l.id ASC
    ''', args);
    return CashierWorkflowBoard(
      queue: queue,
      lines: rows
          .map((row) => _lineFromRow(row, queueOverride: queue))
          .toList(growable: false),
    );
  }

  /// Returns every local order in a business-day window, including completed
  /// and archived orders. Results are stable for pagination and reconciliation.
  List<Map<String, Object?>> readBusinessDayOrders({
    required int shopId,
    required int startMs,
    required int endMs,
    int afterId = 0,
    int? afterCreatedMs,
    int limit = 200,
  }) {
    if (endMs <= startMs) {
      throw const CashierKdsValidation('invalid business-day range');
    }
    final pageSize = limit.clamp(1, 200);
    final cursorClause = afterCreatedMs == null
        ? 'AND o.id > ?'
        : 'AND (o.created_at_ms > ? OR (o.created_at_ms = ? AND o.id > ?))';
    final cursorArgs = afterCreatedMs == null
        ? <Object?>[afterId]
        : <Object?>[afterCreatedMs, afterCreatedMs, afterId];
    final rows = _database.select(
      '''
      SELECT o.*
      FROM local_orders o
      WHERE o.shop_id = ? AND o.created_at_ms >= ? AND o.created_at_ms < ?
        $cursorClause
      ORDER BY o.created_at_ms ASC, o.id ASC
      LIMIT ?
      ''',
      [shopId, startMs, endMs, ...cursorArgs, pageSize + 1],
    );
    return rows
        .map((row) {
          final orderId = _int(row['id']);
          final details = readOrderDetailsProjection(
            shopId: shopId,
            orderIds: [orderId],
          );
          return <String, Object?>{
            'order_id': orderId,
            'order_no': '${row['order_no'] ?? ''}',
            'cloud_order_id': row['cloud_order_id'],
            'cloud_order_no': row['cloud_order_no'],
            'table_number': '${row['table_number'] ?? ''}',
            'fulfillment_type': '${row['fulfillment_type'] ?? 'dine_in'}',
            'remark': '${row['remark'] ?? ''}',
            'order_status': '${row['order_status'] ?? ''}',
            'source_channel': '${row['source_channel'] ?? ''}',
            'created_at_ms': _int(row['created_at_ms']),
            'updated_at_ms': _int(row['updated_at_ms']),
            'completed': _int(row['completed']) == 1,
            'archived': _int(row['archived']) == 1,
            'completed_at_ms': row['completed_at_ms'] == null
                ? null
                : _int(row['completed_at_ms']),
            'details': details,
          };
        })
        .toList(growable: false);
  }

  /// Returns a display-only, complete line projection for the requested
  /// orders. Workflow patches remain the source of truth for KDS commands.
  List<Map<String, Object?>> readOrderDetailsProjection({
    required int shopId,
    required Iterable<int> orderIds,
  }) {
    final ids = orderIds.where((id) => id > 0).toSet().toList()..sort();
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = _database.select(
      '''
      SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type,
        o.remark AS order_remark, o.created_at_ms AS order_created_at_ms,
        o.rushed AS order_rushed
      FROM local_order_lines l
      JOIN local_orders o ON o.id = l.order_id
      WHERE o.shop_id = ? AND o.id IN ($placeholders)
      ORDER BY o.created_at_ms ASC, o.id ASC, l.created_at_ms ASC, l.id ASC
      ''',
      [shopId, ...ids],
    );
    return rows
        .map((row) {
          final quantity = _int(row['line_quantity']);
          final refundedQuantity = _int(
            row['refunded_quantity'],
          ).clamp(0, quantity);
          final status = refundedQuantity <= 0
              ? 'active'
              : refundedQuantity >= quantity
              ? 'refunded'
              : 'partially_refunded';
          final doneLine = _int(row['done_line']) == 1;
          return <String, Object?>{
            'order_id': _int(row['order_id']),
            if (_int(row['cloud_order_id']) > 0)
              'cloud_order_id': _int(row['cloud_order_id']),
            'order_no': '${row['order_no'] ?? ''}',
            'table_number': '${row['table_number'] ?? ''}',
            'fulfillment_type': '${row['fulfillment_type'] ?? 'dine_in'}',
            'fulfillment_channel': '${row['fulfillment_type'] ?? 'dine_in'}',
            'order_remark': '${row['order_remark'] ?? ''}',
            'order_rushed': _int(row['order_rushed']) == 1,
            'detail_id': _int(row['id']),
            'dish_id': _int(row['dish_id']),
            'dish_name': '${row['dish_name'] ?? ''}',
            'specification': '${row['specification'] ?? ''}',
            'unit': '${row['unit'] ?? '份'}',
            'quantity': quantity,
            'refunded_quantity': refundedQuantity,
            'remaining_quantity': quantity - refundedQuantity,
            'status': status,
            'removed': refundedQuantity >= quantity,
            // 厨房行队列标记（与云端 /business-day/orders/detail 字段一致）。
            // 完成行（done_line=1）的剩余队列数量恒为 0，
            // 不直接透传数据库值，避免历史残留/时序差异破坏完成语义。
            'doneLine': doneLine ? 1 : 0,
            'workflowQueue': doneLine
                ? 'done'
                : '${row['workflow_queue'] ?? ''}',
            'readyRemaining': doneLine ? 0 : _int(row['ready_remaining']),
            'prepRemaining': doneLine ? 0 : _int(row['prep_remaining']),
            'cookRemaining': doneLine ? 0 : _int(row['cook_remaining']),
            'remark': '${row['remark'] ?? ''}',
            'is_combo': _int(row['is_combo']) == 1,
            'combo': _int(row['is_combo']) == 1,
            'set_meal': _int(row['is_combo']) == 1,
            if (row['combo_name'] != null && '${row['combo_name']}'.isNotEmpty)
              'combo_name': '${row['combo_name']}',
            if (row['combo_id'] != null && _int(row['combo_id']) > 0)
              'combo_id': _int(row['combo_id']),
          };
        })
        .toList(growable: false);
  }

  /// Returns workflow patches for all lines belonging to the given order.
  /// Useful for fallback broadcasts when a journal event is missing or
  /// when retrieving the full line state across all workflow queues.
  List<Map<String, Object?>> readOrderPatches(int orderId) {
    if (orderId <= 0) return const [];
    final rows = _database.select(
      'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, '
      'o.fulfillment_type, o.remark, o.local_revision AS order_revision '
      'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
      'WHERE l.order_id = ? ORDER BY l.created_at_ms ASC, l.id ASC',
      [orderId],
    );
    return rows.map(_linePatch).toList(growable: false);
  }

  Map<String, Object?>? readOperationAudit(String operationId) {
    final rows = _database.select(
      'SELECT operation_id, shop_id, aggregate_key, operation_type, '
      'payload_json, result_json, occurred_at_ms, command_fingerprint, '
      'event_seq, actor_device_code, before_state_json, after_state_json '
      'FROM local_operation_events WHERE operation_id = ?',
      [operationId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return {
      'operation_id': '${row['operation_id']}',
      'shop_id': _int(row['shop_id']),
      'aggregate_key': '${row['aggregate_key']}',
      'operation_type': '${row['operation_type']}',
      'payload': _jsonMap(row['payload_json']),
      'result': _jsonMap(row['result_json']),
      'occurred_at_ms': _int(row['occurred_at_ms']),
      'command_fingerprint': '${row['command_fingerprint']}',
      'event_seq': _int(row['event_seq']),
      'actor_device_code': '${row['actor_device_code']}',
      'before_state': _jsonMap(row['before_state_json']),
      'after_state': _jsonMap(row['after_state_json']),
    };
  }

  List<CashierCloudEvent> readPendingCloudEvents() {
    final rows = _database.select(
      "SELECT * FROM cloud_outbox WHERE state IN ('pending', 'retry_wait') "
      'ORDER BY created_at_ms ASC, rowid ASC',
    );
    return rows
        .map(
          (row) => CashierCloudEvent(
            eventId: '${row['event_id']}',
            shopId: _int(row['shop_id']),
            eventType: '${row['event_type']}',
            aggregateKey: '${row['aggregate_key']}',
            aggregateSequence: _int(row['aggregate_sequence']),
            payload: _jsonMap(row['payload_json']),
            createdAtMs: _int(row['created_at_ms']),
            attemptCount: _int(row['attempt_count']),
          ),
        )
        .toList(growable: false);
  }

  List<CashierCloudEvent> readDueCloudEvents({
    required int nowMs,
    int limit = 50,
  }) {
    final rows = _database.select(
      "SELECT e.* FROM cloud_outbox e WHERE e.state IN ('pending', 'retry_wait') "
      'AND e.next_attempt_at_ms <= ? AND NOT EXISTS ('
      'SELECT 1 FROM cloud_outbox previous '
      'WHERE previous.aggregate_key = e.aggregate_key '
      'AND previous.aggregate_sequence < e.aggregate_sequence '
      "AND previous.state NOT IN ('delivered', 'discarded')) "
      'ORDER BY e.created_at_ms ASC, e.rowid ASC LIMIT ?',
      [nowMs, limit],
    );
    final due = <CashierCloudEvent>[];
    for (final row in rows) {
      if (_cloudEventReadyToSend(row)) {
        due.add(_cloudEventFromRow(row));
      }
    }
    return due;
  }

  List<List<CashierCloudEvent>> readDueCloudEventBatches({
    required int nowMs,
    int maxAggregates = 4,
    int maxEventsPerAggregate = 50,
  }) {
    // Never pre-send a later fact from the same aggregate. A failed head event
    // must be retried, replaced or explicitly discarded before sequence N+1.
    final perAggregateLimit = maxEventsPerAggregate.clamp(1, 50);
    final aggregateLimit = maxAggregates.clamp(1, 4);
    final heads = _database.select(
      'WITH aggregate_heads AS ('
      'SELECT aggregate_key, MIN(aggregate_sequence) AS aggregate_sequence '
      'FROM cloud_outbox '
      "WHERE state NOT IN ('delivered', 'discarded') "
      'GROUP BY aggregate_key'
      ') '
      'SELECT e.* FROM cloud_outbox e '
      'JOIN aggregate_heads h '
      'ON h.aggregate_key = e.aggregate_key '
      'AND h.aggregate_sequence = e.aggregate_sequence '
      "WHERE e.state IN ('pending', 'retry_wait') "
      'AND e.next_attempt_at_ms <= ? '
      'ORDER BY CASE WHEN e.event_type = ? THEN 0 ELSE 1 END, '
      'e.created_at_ms ASC, e.rowid ASC LIMIT ?',
      [nowMs, cashierServeTicketPrintEventType, aggregateLimit],
    );
    final batches = <List<CashierCloudEvent>>[];
    for (final head in heads) {
      final rows = _database.select(
        "SELECT * FROM cloud_outbox WHERE aggregate_key = ? "
        "AND state NOT IN ('delivered', 'discarded') "
        'AND aggregate_sequence >= ? '
        'ORDER BY aggregate_sequence ASC LIMIT ?',
        [
          '${head['aggregate_key']}',
          _int(head['aggregate_sequence']),
          perAggregateLimit,
        ],
      );
      final batch = <Row>[];
      for (final row in rows) {
        final state = '${row['state']}';
        if (state != 'pending' && state != 'retry_wait') break;
        if (_int(row['next_attempt_at_ms']) > nowMs) break;
        if (!_cloudEventReadyToSend(row)) break;
        batch.add(row);
        if (batch.length >= perAggregateLimit) break;
      }
      if (batch.isNotEmpty) {
        batches.add(batch.map(_cloudEventFromRow).toList(growable: false));
      }
    }
    return batches;
  }

  void applyCloudAckAndMarkDelivered(
    CashierCloudEvent event,
    CashierCloudEventAck ack, {
    required int deliveredAtMs,
  }) {
    if (ack.eventId != event.eventId) {
      throw const CashierKdsValidation('cloud ACK event_id mismatch');
    }
    _safeBegin();
    try {
      final rows = _database.select(
        'SELECT event_type FROM cloud_outbox WHERE event_id = ?',
        [event.eventId],
      );
      if (rows.isEmpty || '${rows.first['event_type']}' != event.eventType) {
        throw const CashierKdsValidation(
          'cloud ACK has no matching outbox event',
        );
      }
      if (event.eventType == 'order_created') {
        final localOrderId = _int(event.payload['local_order_id']);
        if (localOrderId <= 0 ||
            ack.cloudOrderId == null ||
            (ack.cloudOrderNo ?? '').trim().isEmpty) {
          throw const CashierKdsValidation(
            'order ACK is missing cloud mapping',
          );
        }
        _database.execute(
          'UPDATE local_orders SET cloud_order_id = ?, cloud_order_no = ?, '
          'updated_at_ms = ? WHERE id = ? AND shop_id = ?',
          [
            ack.cloudOrderId,
            ack.cloudOrderNo,
            deliveredAtMs,
            localOrderId,
            event.shopId,
          ],
        );
        if (_database.updatedRows != 1) {
          throw const CashierKdsValidation('local order for ACK was not found');
        }
        final localDetailIds = _database
            .select('SELECT id FROM local_order_lines WHERE order_id = ?', [
              localOrderId,
            ])
            .map((row) => _int(row['id']))
            .toSet();
        if (localDetailIds.isEmpty ||
            !localDetailIds.every(ack.detailMappings.containsKey)) {
          throw const CashierKdsValidation(
            'order ACK is missing detail mappings',
          );
        }
        for (final mapping in ack.detailMappings.entries) {
          _database.execute(
            'UPDATE local_order_lines SET cloud_detail_id = ?, '
            'updated_at_ms = ? WHERE id = ? AND order_id = ?',
            [mapping.value, deliveredAtMs, mapping.key, localOrderId],
          );
          if (_database.updatedRows != 1) {
            throw const CashierKdsValidation(
              'local detail for ACK was not found',
            );
          }
        }
      } else if (ack.detailMappings.isNotEmpty) {
        // kds_state_changed：云端为本地新加、尚未映射的行返回正式明细映射
        // 时（如云端出生订单的本地加菜），回写本地行，后续事件即可使用
        // 正式 detail_id。尽力而为：事件已被云端接受，映射缺失不应让
        // 事件陷入重试。
        var localOrderId = _int(event.payload['local_order_id']);
        if (localOrderId <= 0) {
          final payloadOrderId = _int(event.payload['order_id']);
          final orderRows = _database.select(
            'SELECT id FROM local_orders WHERE shop_id = ? '
            'AND (id = ? OR cloud_order_id = ?)',
            [event.shopId, payloadOrderId, payloadOrderId],
          );
          if (orderRows.isNotEmpty) {
            localOrderId = _int(orderRows.first['id']);
          }
        }
        if (localOrderId > 0) {
          for (final mapping in ack.detailMappings.entries) {
            _database.execute(
              'UPDATE local_order_lines SET cloud_detail_id = ?, '
              'updated_at_ms = ? WHERE id = ? AND order_id = ? '
              'AND cloud_detail_id IS NULL',
              [mapping.value, deliveredAtMs, mapping.key, localOrderId],
            );
          }
        }
      }
      _database.execute(
        "UPDATE cloud_outbox SET state = 'delivered', updated_at_ms = ?, "
        'delivered_at_ms = ?, last_error = NULL WHERE event_id = ?',
        [deliveredAtMs, deliveredAtMs, event.eventId],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  String resolveCloudOrderNo(int shopId, String orderNo) {
    final rows = _database.select(
      'SELECT cloud_order_no FROM local_orders WHERE shop_id = ? AND order_no = ?',
      [shopId, orderNo],
    );
    if (rows.isEmpty) return orderNo;
    final mapped = '${rows.first['cloud_order_no'] ?? ''}'.trim();
    if (mapped.isEmpty) throw const CashierLocalOrderPendingSync();
    return mapped;
  }

  int resolveCloudOrderId(int shopId, int orderId) {
    final rows = _database.select(
      'SELECT cloud_order_id FROM local_orders WHERE shop_id = ? AND id = ?',
      [shopId, orderId],
    );
    if (rows.isEmpty) return orderId;
    final mapped = _int(rows.first['cloud_order_id']);
    if (mapped <= 0) throw const CashierLocalOrderPendingSync();
    return mapped;
  }

  int resolveCloudDetailId(int shopId, int detailId) {
    final rows = _database.select(
      'SELECT l.cloud_detail_id FROM local_order_lines l '
      'JOIN local_orders o ON o.id = l.order_id '
      'WHERE o.shop_id = ? AND l.id = ?',
      [shopId, detailId],
    );
    if (rows.isEmpty) return detailId;
    final mapped = _int(rows.first['cloud_detail_id']);
    if (mapped <= 0) throw const CashierLocalOrderPendingSync();
    return mapped;
  }

  void rescheduleCloudEvent(
    String eventId, {
    required int nextAttemptAtMs,
    required int updatedAtMs,
    String? error,
    int? httpStatus,
    int? code,
  }) {
    _database.execute(
      'UPDATE cloud_outbox SET attempt_count = attempt_count + 1, '
      "state = 'retry_wait', next_attempt_at_ms = ?, updated_at_ms = ?, "
      'last_error = ?, last_http_status = COALESCE(?, last_http_status), '
      'last_code = COALESCE(?, last_code) '
      'WHERE event_id = ?',
      [nextAttemptAtMs, updatedAtMs, error, httpStatus, code, eventId],
    );
  }

  void pauseCloudEventsForAuthentication({
    required int updatedAtMs,
    required String error,
    int? httpStatus,
    int? code,
  }) {
    _database.execute(
      "UPDATE cloud_outbox SET state = 'auth_paused', updated_at_ms = ?, "
      'last_error = ?, last_http_status = COALESCE(?, last_http_status), '
      'last_code = COALESCE(?, last_code) '
      "WHERE state NOT IN ('delivered', 'dead_letter', 'discarded')",
      [updatedAtMs, error, httpStatus, code],
    );
  }

  void markCloudEventDeadLetter(
    String eventId, {
    required int updatedAtMs,
    required String error,
    int? httpStatus,
    int? code,
  }) {
    _database.execute(
      "UPDATE cloud_outbox SET state = 'dead_letter', attempt_count = "
      'attempt_count + 1, updated_at_ms = ?, last_error = ?, '
      'last_http_status = COALESCE(?, last_http_status), '
      'last_code = COALESCE(?, last_code) WHERE event_id = ? '
      "AND state NOT IN ('delivered', 'discarded')",
      [updatedAtMs, error, httpStatus, code, eventId],
    );
  }

  List<CashierDeadLetter> readDeadLetters({int? shopId, int limit = 100}) {
    final rows = _database.select(
      "SELECT * FROM cloud_outbox WHERE state = 'dead_letter' "
      '${shopId == null ? '' : 'AND shop_id = ? '} '
      'ORDER BY updated_at_ms DESC LIMIT ?',
      [if (shopId != null) shopId, limit.clamp(1, 500)],
    );
    return rows
        .map(
          (row) => CashierDeadLetter(
            eventId: '${row['event_id']}',
            shopId: _int(row['shop_id']),
            eventType: '${row['event_type']}',
            aggregateKey: '${row['aggregate_key']}',
            attemptCount: _int(row['attempt_count']),
            createdAtMs: _int(row['created_at_ms']),
            updatedAtMs: _int(row['updated_at_ms']),
            lastHttpStatus: row['last_http_status'] == null
                ? null
                : _int(row['last_http_status']),
            lastCode: row['last_code'] == null ? null : _int(row['last_code']),
            lastError: row['last_error'] == null
                ? null
                : '${row['last_error']}',
          ),
        )
        .toList(growable: false);
  }

  void retryCloudEvent(
    String eventId, {
    required String actorDeviceCode,
    required String reason,
    required int nowMs,
  }) {
    _manageDeadLetter(
      eventId: eventId,
      actorDeviceCode: actorDeviceCode,
      reason: reason,
      nowMs: nowMs,
      action: 'retry',
    );
  }

  void discardCloudEvent(
    String eventId, {
    required String actorDeviceCode,
    required String reason,
    required int nowMs,
  }) {
    _manageDeadLetter(
      eventId: eventId,
      actorDeviceCode: actorDeviceCode,
      reason: reason,
      nowMs: nowMs,
      action: 'discard',
    );
  }

  void replaceCloudEvent(
    String eventId, {
    required String newEventId,
    required Map<String, Object?> payload,
    required String actorDeviceCode,
    required String reason,
    required int nowMs,
  }) {
    _manageDeadLetter(
      eventId: eventId,
      newEventId: newEventId,
      newPayload: payload,
      actorDeviceCode: actorDeviceCode,
      reason: reason,
      nowMs: nowMs,
      action: 'replace',
    );
  }

  List<Map<String, Object?>> readDeadLetterAudit({int limit = 100}) => _database
      .select(
        'SELECT * FROM local_dead_letter_audit '
        'ORDER BY occurred_at_ms DESC, id DESC LIMIT ?',
        [limit.clamp(1, 500)],
      )
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  void _manageDeadLetter({
    required String eventId,
    required String actorDeviceCode,
    required String reason,
    required int nowMs,
    required String action,
    String? newEventId,
    Map<String, Object?>? newPayload,
  }) {
    final actor = actorDeviceCode.trim();
    final auditReason = reason.trim();
    if (actor.isEmpty || auditReason.isEmpty) {
      throw const CashierKdsValidation('actor and reason are required');
    }
    if (!const {'retry', 'replace', 'discard'}.contains(action)) {
      throw const CashierKdsValidation('invalid dead-letter action');
    }
    _safeBegin();
    try {
      final rows = _database.select(
        "SELECT * FROM cloud_outbox WHERE event_id = ? AND state = 'dead_letter'",
        [eventId],
      );
      if (rows.isEmpty) {
        throw const CashierKdsValidation('dead-letter event not found');
      }
      final row = rows.single;
      final oldPayload = _jsonMap(row['payload_json']);
      final oldFingerprint = '${row['request_fingerprint'] ?? ''}'.isNotEmpty
          ? '${row['request_fingerprint']}'
          : jsonEncode(_canonicalJson(oldPayload));
      String? replacementFingerprint;
      if (action == 'retry') {
        _database.execute(
          "UPDATE cloud_outbox SET state = 'pending', next_attempt_at_ms = ?, "
          'updated_at_ms = ?, last_error = NULL WHERE event_id = ?',
          [nowMs, nowMs, eventId],
        );
      } else if (action == 'discard') {
        _database.execute(
          "UPDATE cloud_outbox SET state = 'discarded', updated_at_ms = ? "
          'WHERE event_id = ?',
          [nowMs, eventId],
        );
      } else {
        final replacementId = newEventId?.trim() ?? '';
        if (replacementId.isEmpty || replacementId.length > 128) {
          throw const CashierKdsValidation(
            'replacement event_id must be 1..128 chars',
          );
        }
        if (newPayload == null || newPayload.isEmpty) {
          throw const CashierKdsValidation('replacement payload is required');
        }
        _validateReplacementPayload('${row['event_type']}', newPayload);
        replacementFingerprint = jsonEncode(_canonicalJson(newPayload));
        _database.execute(
          "UPDATE cloud_outbox SET state = 'discarded', updated_at_ms = ? "
          'WHERE event_id = ?',
          [nowMs, eventId],
        );
        _database.execute(
          'INSERT INTO cloud_outbox '
          '(event_id, shop_id, event_type, aggregate_key, aggregate_sequence, '
          'payload_json, request_fingerprint, state, attempt_count, '
          'next_attempt_at_ms, created_at_ms, updated_at_ms) '
          "VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?)",
          [
            replacementId,
            row['shop_id'],
            row['event_type'],
            row['aggregate_key'],
            row['aggregate_sequence'],
            jsonEncode(newPayload),
            replacementFingerprint,
            nowMs,
            nowMs,
            nowMs,
          ],
        );
      }
      _database.execute(
        'INSERT INTO local_dead_letter_audit '
        '(actor_device_code, action, reason, old_event_id, new_event_id, '
        'old_payload_fingerprint, new_payload_fingerprint, occurred_at_ms) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          actor,
          action,
          auditReason,
          eventId,
          newEventId?.trim(),
          oldFingerprint,
          replacementFingerprint,
          nowMs,
        ],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  void _validateReplacementPayload(
    String eventType,
    Map<String, Object?> payload,
  ) {
    if (eventType == 'order_created') {
      if (_int(payload['local_order_id']) <= 0 || payload['lines'] is! List) {
        throw const CashierKdsValidation('invalid order_created payload');
      }
    } else if (eventType == 'kds_state_changed') {
      if (_int(payload['order_id'] ?? payload['local_order_id']) <= 0 ||
          payload['orders'] is! List ||
          payload['lines'] is! List ||
          '${payload['device_code'] ?? ''}'.trim().isEmpty) {
        throw const CashierKdsValidation('invalid kds_state_changed payload');
      }
    }
    try {
      jsonEncode(payload);
    } catch (_) {
      throw const CashierKdsValidation('replacement payload must be JSON');
    }
  }

  void resumeAuthenticationPausedEvents({required int nowMs}) {
    _database.execute(
      "UPDATE cloud_outbox SET state = 'pending', next_attempt_at_ms = ?, "
      "updated_at_ms = ?, last_error = NULL WHERE state = 'auth_paused'",
      [nowMs, nowMs],
    );
  }

  bool hasAuthenticationPausedEvents() {
    final rows = _database.select(
      "SELECT 1 FROM cloud_outbox WHERE state = 'auth_paused' LIMIT 1",
    );
    return rows.isNotEmpty;
  }

  void retryAllUndeliveredCloudEvents({required int nowMs}) {
    _database.execute(
      "UPDATE cloud_outbox SET state = 'pending', next_attempt_at_ms = ?, "
      "updated_at_ms = ? WHERE state NOT IN ('delivered', 'dead_letter', 'discarded')",
      [nowMs, nowMs],
    );
  }

  int clearSyncQueue({
    required String actorDeviceCode,
    String? reason,
    required int nowMs,
  }) {
    _safeBegin();
    try {
      final rows = _database.select(
        "SELECT event_id FROM cloud_outbox "
        "WHERE state IN ('pending', 'retry_wait', 'auth_paused', 'dead_letter')",
      );
      if (rows.isEmpty) {
        _database.execute('COMMIT');
        return 0;
      }
      _database.execute(
        "UPDATE cloud_outbox SET state = 'discarded', updated_at_ms = ?, "
        "last_error = COALESCE(last_error, 'manually cleared') "
        "WHERE state IN ('pending', 'retry_wait', 'auth_paused', 'dead_letter')",
        [nowMs],
      );
      final clearedCount = _database.updatedRows;
      _database.execute(
        'INSERT INTO local_operation_events '
        '(operation_id, shop_id, aggregate_key, operation_type, payload_json, '
        'result_json, occurred_at_ms, command_fingerprint, event_seq, '
        'actor_device_code, before_state_json, after_state_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'clear_outbox_${nowMs}_${DateTime.now().microsecondsSinceEpoch}',
          0,
          'outbox:cleared',
          'clear_sync_queue',
          jsonEncode({
            'reason': reason ?? 'operator manually cleared sync queue',
          }),
          jsonEncode({'cleared_count': clearedCount}),
          nowMs,
          'clear_sync_queue:$clearedCount',
          null,
          actorDeviceCode,
          jsonEncode({'events_count': rows.length}),
          jsonEncode({'cleared_count': clearedCount}),
        ],
      );
      _database.execute('COMMIT');
      return clearedCount;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  void createPairingCode({
    required int shopId,
    required String codeHash,
    required int expiresAtMs,
    required int createdAtMs,
  }) {
    if (shopId <= 0 || codeHash.isEmpty || expiresAtMs <= createdAtMs) {
      throw const CashierKdsValidation('invalid pairing code');
    }
    _safeBegin();
    try {
      _database.execute(
        'DELETE FROM kds_pairing_codes WHERE shop_id = ? OR expires_at_ms <= ?',
        [shopId, createdAtMs],
      );
      _database.execute(
        'INSERT INTO kds_pairing_codes '
        '(code_hash, shop_id, expires_at_ms, created_at_ms) VALUES (?, ?, ?, ?)',
        [codeHash, shopId, expiresAtMs, createdAtMs],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierKdsDevice pairDevice({
    required String pairingCodeHash,
    required String tokenHash,
    required String deviceCode,
    required String deviceName,
    required String screenTag,
    required List<String> workflows,
    List<String> screenTags = const [],
    required int nowMs,
  }) {
    _safeBegin();
    try {
      final codes = _database.select(
        'SELECT shop_id FROM kds_pairing_codes WHERE code_hash = ? '
        'AND used_at_ms IS NULL AND expires_at_ms > ?',
        [pairingCodeHash, nowMs],
      );
      if (codes.isEmpty) {
        throw const CashierKdsValidation('pairing code is invalid or expired');
      }
      final shopId = _int(codes.first['shop_id']);
      // 同码冲突保护：设备码已被启用且近期有心跳（在线屏幕）时，
      // 拒绝静默顶号——旧设备 token 会被替换导致其被踢下线。
      // 离线/陈旧设备允许接管（覆盖重装、token 丢失的恢复场景）。
      // 拒绝发生在配对码核销之前，操作员可换设备码后重试同一配对码。
      final existing = _database.select(
        'SELECT token_hash, enabled, last_heartbeat_at_ms FROM kds_devices '
        'WHERE device_code = ?',
        [deviceCode],
      );
      if (existing.isNotEmpty) {
        final row = existing.first;
        final sameToken = '${row['token_hash']}' == tokenHash;
        final online =
            _int(row['enabled']) == 1 &&
            nowMs - _int(row['last_heartbeat_at_ms']) < 90 * 1000;
        if (!sameToken && online) {
          throw const CashierKdsValidation('设备码已绑定到其他在线屏幕，请更换设备码，或先在诊断页移除原设备');
        }
      }
      _database.execute(
        'UPDATE kds_pairing_codes SET used_at_ms = ? WHERE code_hash = ?',
        [nowMs, pairingCodeHash],
      );
      final normalizedScreenTags = screenTags
          .where(kIsGrillTag)
          .toList(growable: false);
      _database.execute(
        'INSERT INTO kds_devices '
        '(device_code, shop_id, device_name, screen_tag, workflows_json, '
        'screen_tags_json, token_hash, enabled, paired_at_ms, last_heartbeat_at_ms) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?) '
        'ON CONFLICT(device_code) DO UPDATE SET shop_id = excluded.shop_id, '
        'device_name = excluded.device_name, screen_tag = excluded.screen_tag, '
        'workflows_json = excluded.workflows_json, '
        'screen_tags_json = excluded.screen_tags_json, '
        'token_hash = excluded.token_hash, '
        'enabled = 1, paired_at_ms = excluded.paired_at_ms, '
        'last_heartbeat_at_ms = excluded.last_heartbeat_at_ms',
        [
          deviceCode,
          shopId,
          deviceName,
          screenTag,
          jsonEncode(workflows),
          jsonEncode(normalizedScreenTags),
          tokenHash,
          nowMs,
          nowMs,
        ],
      );
      final device = _readDeviceByTokenHash(tokenHash)!;
      _database.execute('COMMIT');
      return device;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierKdsDevice upsertBoundDevice({
    required int shopId,
    required String deviceCode,
    required String deviceName,
    required String screenTag,
    List<String> workflows = const ['prep', 'cook', 'serve'],
    List<String> screenTags = const [],
    bool enabled = true,
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final normalizedScreenTags = screenTags
        .where(kIsGrillTag)
        .toList(growable: false);
    final normalizedWorkflows = workflows
        .where((value) => const {'prep', 'cook', 'serve'}.contains(value))
        .toList(growable: false);
    final effectiveWorkflows = normalizedWorkflows.isEmpty
        ? const ['prep', 'cook', 'serve']
        : normalizedWorkflows;

    _safeBegin();
    try {
      final existing = _database.select(
        'SELECT token_hash, paired_at_ms, last_heartbeat_at_ms FROM kds_devices WHERE device_code = ?',
        [deviceCode],
      );

      final tokenHash = existing.isNotEmpty
          ? '${existing.first['token_hash']}'
          : 'pending:$deviceCode';
      final pairedAt = existing.isNotEmpty
          ? _int(existing.first['paired_at_ms'])
          : now;
      final lastHeartbeatAt = existing.isNotEmpty
          ? _int(existing.first['last_heartbeat_at_ms'])
          : 0;

      _database.execute(
        'INSERT INTO kds_devices '
        '(device_code, shop_id, device_name, screen_tag, workflows_json, '
        'screen_tags_json, token_hash, enabled, paired_at_ms, last_heartbeat_at_ms) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(device_code) DO UPDATE SET '
        'shop_id = excluded.shop_id, '
        'device_name = excluded.device_name, '
        'screen_tag = excluded.screen_tag, '
        'workflows_json = excluded.workflows_json, '
        'screen_tags_json = excluded.screen_tags_json, '
        'enabled = excluded.enabled',
        [
          deviceCode,
          shopId,
          deviceName,
          screenTag,
          jsonEncode(effectiveWorkflows),
          jsonEncode(normalizedScreenTags),
          tokenHash,
          enabled ? 1 : 0,
          pairedAt,
          lastHeartbeatAt,
        ],
      );
      final device = readDeviceByCode(deviceCode)!;
      _database.execute('COMMIT');
      return device;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierKdsDevice loginBoundDevice({
    required String deviceCode,
    required String tokenHash,
    String? deviceName,
    String? screenTag,
    List<String>? workflows,
    List<String>? screenTags,
    required int nowMs,
  }) {
    _safeBegin();
    try {
      final existing = _database.select(
        'SELECT * FROM kds_devices WHERE device_code = ?',
        [deviceCode],
      );
      if (existing.isEmpty) {
        throw const CashierKdsValidation('设备未绑定，请先在收银端绑定此设备编码');
      }
      final row = existing.first;
      final enabled = _int(row['enabled']) == 1;
      if (!enabled) {
        throw const CashierKdsValidation('设备已被禁用，请先在收银端重新启用此设备');
      }
      // 硬件编码唯一性：匹配到已绑定设备直接签发 token，不再限制是否已被绑定到其他在线屏幕（移除 isOnlineOther 冲突拦截）
      final existingName = '${row['device_name']}';
      final effectiveName =
          (deviceName != null &&
              deviceName.trim().isNotEmpty &&
              (existingName.isEmpty || existingName == deviceCode))
          ? deviceName.trim()
          : existingName;

      _database.execute(
        'UPDATE kds_devices SET '
        'token_hash = ?, '
        'device_name = ?, '
        'last_heartbeat_at_ms = ?, '
        'enabled = 1 '
        'WHERE device_code = ?',
        [tokenHash, effectiveName, nowMs, deviceCode],
      );

      final device = _readDeviceByTokenHash(tokenHash);
      if (device == null) {
        throw const CashierKdsValidation('设备登录失败');
      }
      _database.execute('COMMIT');
      return device;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierKdsDevice syncCloudDeviceSession({
    required int shopId,
    required String deviceCode,
    required String tokenHash,
    String? deviceName,
    String? screenTag,
    List<String>? workflows,
    List<String>? screenTags,
    required int nowMs,
  }) {
    _safeBegin();
    try {
      final existing = _database.select(
        'SELECT * FROM kds_devices WHERE device_code = ?',
        [deviceCode],
      );
      final effectiveName = (deviceName != null && deviceName.trim().isNotEmpty)
          ? deviceName.trim()
          : (existing.isNotEmpty
                ? '${existing.first['device_name']}'
                : deviceCode);
      final effectiveTag = (screenTag != null && screenTag.trim().isNotEmpty)
          ? screenTag.trim()
          : (existing.isNotEmpty
                ? '${existing.first['screen_tag']}'
                : 'workflow_board');
      final effectiveWorkflows = (workflows != null && workflows.isNotEmpty)
          ? workflows
          : (existing.isNotEmpty
                ? (jsonDecode('${existing.first['workflows_json']}') as List)
                      .map((e) => '$e')
                      .toList()
                : const ['prep', 'cook', 'serve']);
      final normalizedScreenTags = (screenTags != null)
          ? screenTags
          : (existing.isNotEmpty
                ? (jsonDecode('${existing.first['screen_tags_json'] ?? '[]'}')
                          as List)
                      .map((e) => '$e')
                      .toList()
                : const <String>[]);
      final pairedAt = existing.isNotEmpty
          ? _int(existing.first['paired_at_ms'])
          : nowMs;

      _database.execute(
        'INSERT INTO kds_devices '
        '(device_code, shop_id, device_name, screen_tag, workflows_json, '
        'screen_tags_json, token_hash, enabled, paired_at_ms, last_heartbeat_at_ms) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?) '
        'ON CONFLICT(device_code) DO UPDATE SET '
        'shop_id = excluded.shop_id, '
        'device_name = excluded.device_name, '
        'screen_tag = excluded.screen_tag, '
        'workflows_json = excluded.workflows_json, '
        'screen_tags_json = excluded.screen_tags_json, '
        'token_hash = excluded.token_hash, '
        'enabled = 1, '
        'last_heartbeat_at_ms = excluded.last_heartbeat_at_ms',
        [
          deviceCode,
          shopId,
          effectiveName,
          effectiveTag,
          jsonEncode(effectiveWorkflows),
          jsonEncode(normalizedScreenTags),
          tokenHash,
          pairedAt,
          nowMs,
        ],
      );
      final device = _readDeviceByTokenHash(tokenHash);
      if (device == null) {
        throw const CashierKdsValidation('设备缓存同步失败');
      }
      _database.execute('COMMIT');
      return device;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  void appendCloudEventEnvelope({
    required int shopId,
    required int eventSeq,
    required String eventId,
    required String envelopeJson,
    required int receivedAtMs,
  }) {
    if (shopId <= 0 || eventSeq <= 0 || eventId.trim().isEmpty) {
      throw const CashierKdsValidation('invalid cloud event envelope');
    }
    _safeBegin();
    try {
      final bySeq = _database.select(
        'SELECT event_id,envelope_json FROM edge_kds_event_journal '
        'WHERE shop_id=? AND event_seq=?',
        [shopId, eventSeq],
      );
      if (bySeq.isNotEmpty) {
        if ('${bySeq.first['event_id']}' != eventId ||
            '${bySeq.first['envelope_json']}' != envelopeJson) {
          throw const CashierKdsConflict(
            'cloud event sequence was reused with different data',
          );
        }
      } else {
        final byId = _database.select(
          'SELECT event_seq,envelope_json FROM edge_kds_event_journal '
          'WHERE shop_id=? AND event_id=?',
          [shopId, eventId],
        );
        if (byId.isNotEmpty &&
            (_int(byId.first['event_seq']) != eventSeq ||
                '${byId.first['envelope_json']}' != envelopeJson)) {
          throw const CashierKdsConflict(
            'cloud event id was reused with different data',
          );
        }
        if (byId.isEmpty) {
          _database.execute(
            'INSERT INTO edge_kds_event_journal '
            '(shop_id,event_seq,event_id,envelope_json,received_at_ms) '
            'VALUES (?,?,?,?,?)',
            [shopId, eventSeq, eventId, envelopeJson, receivedAtMs],
          );
        }
      }
      _database.execute(
        'INSERT INTO edge_kds_proxy_cursor '
        '(shop_id,last_event_seq,synced_at_ms) VALUES (?,?,?) '
        'ON CONFLICT(shop_id) DO UPDATE SET '
        'last_event_seq=MAX(last_event_seq,excluded.last_event_seq), '
        'synced_at_ms=excluded.synced_at_ms',
        [shopId, eventSeq, receivedAtMs],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  int readCloudProxyCursor(int shopId) {
    final rows = _database.select(
      'SELECT last_event_seq FROM edge_kds_proxy_cursor WHERE shop_id=?',
      [shopId],
    );
    return rows.isEmpty ? 0 : _int(rows.first['last_event_seq']);
  }

  CashierKdsDevice? authenticateDevice(String tokenHash, {int? heartbeatAtMs}) {
    final device = _readDeviceByTokenHash(tokenHash);
    if (device == null || !device.enabled) return null;
    if (heartbeatAtMs != null) {
      _database.execute(
        'UPDATE kds_devices SET last_heartbeat_at_ms = ? WHERE token_hash = ?',
        [heartbeatAtMs, tokenHash],
      );
      return _readDeviceByTokenHash(tokenHash);
    }
    return device;
  }

  CashierKdsDevice? disableDevice(String deviceCode) {
    final rows = _database.select(
      'SELECT token_hash FROM kds_devices WHERE device_code = ?',
      [deviceCode],
    );
    if (rows.isEmpty) return null;
    final device = _readDeviceByTokenHash('${rows.first['token_hash']}');
    _database.execute(
      'UPDATE kds_devices SET enabled = 0 WHERE device_code = ?',
      [deviceCode],
    );
    return device;
  }

  bool removeDevice(String deviceCode) {
    _database.execute('DELETE FROM kds_devices WHERE device_code = ?', [
      deviceCode,
    ]);
    return true;
  }

  List<CashierKdsDevice> readDevices({required int shopId}) {
    final rows = _database.select(
      'SELECT token_hash FROM kds_devices WHERE shop_id = ? '
      'ORDER BY paired_at_ms DESC, device_code',
      [shopId],
    );
    return rows
        .map((row) => _readDeviceByTokenHash('${row['token_hash']}'))
        .whereType<CashierKdsDevice>()
        .toList(growable: false);
  }

  Map<String, Object?> readHealthSnapshot({required int nowMs}) {
    final integrity =
        '${_database.select('PRAGMA quick_check(1)').first.values.first}';
    final journalMode =
        '${_database.select('PRAGMA journal_mode').first.values.first}';
    final node = _database
        .select(
          "SELECT meta_value FROM local_kds_meta WHERE meta_key = 'primary_node_id'",
        )
        .single;
    final oldest = _database
        .select(
          "SELECT MIN(created_at_ms) AS oldest FROM cloud_outbox "
          "WHERE state NOT IN ('delivered', 'discarded')",
        )
        .single['oldest'];
    final stats = readOutboxStats();
    return {
      'sqlite': {
        'status': integrity == 'ok' ? 'ok' : 'degraded',
        'quick_check': integrity,
        'journal_mode': journalMode,
      },
      'primary_node': {
        'node_id': '${node['meta_value']}',
        'role': 'primary',
        'authoritative': true,
      },
      'outbox': {
        'pending': stats.pending,
        'retrying': stats.retrying,
        'dead_letter': stats.deadLetter,
        'auth_paused': stats.authPaused,
        'oldest_pending_age_ms': oldest == null
            ? 0
            : (nowMs - _int(oldest)).clamp(0, 1 << 62),
      },
    };
  }

  int onlineDeviceCount({required int shopId, required int seenSinceMs}) {
    final rows = _database.select(
      'SELECT COUNT(*) AS count FROM kds_devices WHERE shop_id = ? '
      'AND enabled = 1 AND last_heartbeat_at_ms >= ?',
      [shopId, seenSinceMs],
    );
    return _int(rows.first['count']);
  }

  CashierOutboxStats readOutboxStats() {
    int count(String state) {
      final rows = _database.select(
        'SELECT COUNT(*) AS count FROM cloud_outbox WHERE state = ?',
        [state],
      );
      return _int(rows.first['count']);
    }

    final delivered = _database.select(
      'SELECT MAX(delivered_at_ms) AS delivered_at_ms FROM cloud_outbox',
    );
    final lastDelivered = delivered.first['delivered_at_ms'];
    final failures = _database.select(
      "SELECT last_error FROM cloud_outbox "
      "WHERE state NOT IN ('delivered', 'discarded') "
      "AND last_error IS NOT NULL AND TRIM(last_error) != '' "
      'ORDER BY updated_at_ms DESC, rowid DESC LIMIT 1',
    );
    return CashierOutboxStats(
      pending: count('pending'),
      retrying: count('retry_wait'),
      deadLetter: count('dead_letter'),
      authPaused: count('auth_paused'),
      lastDeliveredAtMs: lastDelivered == null ? null : _int(lastDelivered),
      lastError: failures.isEmpty ? null : '${failures.first['last_error']}',
    );
  }

  bool readPrintOnAdvance({required int shopId}) {
    if (shopId <= 0) return false;
    final rows = _database.select(
      'SELECT meta_value FROM local_kds_meta WHERE meta_key = ?',
      ['print_on_advance:$shopId'],
    );
    if (rows.isEmpty) return false;
    final value = '${rows.single['meta_value']}'.trim().toLowerCase();
    return value == '1' || value == 'true';
  }

  CashierCatalogChange? setPrintOnAdvance({
    required int shopId,
    required bool enabled,
    required int updatedAtMs,
  }) {
    if (shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    if (readPrintOnAdvance(shopId: shopId) == enabled) return null;
    _safeBegin();
    try {
      _database.execute(
        'INSERT INTO local_kds_meta(meta_key, meta_value) VALUES (?, ?) '
        'ON CONFLICT(meta_key) DO UPDATE SET meta_value = excluded.meta_value',
        ['print_on_advance:$shopId', enabled ? '1' : '0'],
      );
      final version = _nextLanConfigVersion(shopId);
      final eventSeq = _insertJournalEvent(
        eventId: 'print-on-advance:$shopId:$version',
        shopId: shopId,
        eventType: 'config_changed',
        aggregateKey: 'config:$shopId',
        patches: const [],
        occurredAtMs: updatedAtMs,
      );
      _database.execute('COMMIT');
      return CashierCatalogChange(eventSeq: eventSeq, configVersion: version);
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  bool readEnablePrepWorkflow({required int shopId}) {
    final rows = _database.select(
      'SELECT meta_value FROM local_kds_meta WHERE meta_key = ?',
      ['enable_prep_workflow:$shopId'],
    );
    if (rows.isNotEmpty) {
      final value = '${rows.single['meta_value']}'.trim().toLowerCase();
      return value == '1' || value == 'true';
    }
    final snapshot = readConfigSnapshot(
      shopId: shopId,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      allowExpired: true,
    );
    final workflow = snapshot?.payload['workflow'];
    if (workflow is Map) {
      final val = workflow['enable_prep_workflow'] ?? workflow['prep_enabled'];
      if (val != null) {
        final str = '$val'.trim().toLowerCase();
        return str == '1' || str == 'true';
      }
    }
    return true;
  }

  CashierCatalogChange? setEnablePrepWorkflow({
    required int shopId,
    required bool enabled,
    required int updatedAtMs,
  }) {
    if (shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    if (readEnablePrepWorkflow(shopId: shopId) == enabled) return null;
    _safeBegin();
    try {
      _database.execute(
        'INSERT INTO local_kds_meta(meta_key, meta_value) VALUES (?, ?) '
        'ON CONFLICT(meta_key) DO UPDATE SET meta_value = excluded.meta_value',
        ['enable_prep_workflow:$shopId', enabled ? '1' : '0'],
      );
      final version = _nextLanConfigVersion(shopId);
      final eventSeq = _insertJournalEvent(
        eventId: 'enable-prep-workflow:$shopId:$version',
        shopId: shopId,
        eventType: 'config_changed',
        aggregateKey: 'config:$shopId',
        patches: const [],
        occurredAtMs: updatedAtMs,
      );
      _database.execute('COMMIT');
      return CashierCatalogChange(eventSeq: eventSeq, configVersion: version);
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierCatalogChange? replaceDishCatalog({
    required int shopId,
    required List<CashierDishCatalogItem> items,
    required int updatedAtMs,
  }) {
    if (shopId <= 0) {
      throw const CashierKdsValidation('shopId must be positive');
    }
    final normalized =
        items
            .where((item) => item.dishId > 0 && item.dishName.trim().isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) {
            final catSeqA = a.categorySequence ?? a.sequence;
            final catSeqB = b.categorySequence ?? b.sequence;
            final catSeqCompare = catSeqA.compareTo(catSeqB);
            if (catSeqCompare != 0) return catSeqCompare;
            final catIdA = a.categoryId ?? 0;
            final catIdB = b.categoryId ?? 0;
            final catIdCompare = catIdA.compareTo(catIdB);
            if (catIdCompare != 0) return catIdCompare;
            final dishSeqA = a.dishSequence ?? a.sequence;
            final dishSeqB = b.dishSequence ?? b.sequence;
            final dishSeqCompare = dishSeqA.compareTo(dishSeqB);
            if (dishSeqCompare != 0) return dishSeqCompare;
            return a.dishId.compareTo(b.dishId);
          });
    final previousFingerprint = _catalogStructureFingerprint(
      readDishCatalog(shopId: shopId),
    );
    final nextFingerprint = _catalogStructureFingerprint(normalized);
    final structureChanged = previousFingerprint != nextFingerprint;
    _safeBegin();
    try {
      _database.execute('DELETE FROM local_dish_catalog WHERE shop_id = ?', [
        shopId,
      ]);
      for (final item in normalized) {
        _database.execute(
          'INSERT INTO local_dish_catalog '
          '(shop_id, dish_id, dish_name, unit, sort_index, category_id, '
          'category_name, category_sequence, dish_sequence, stock, onsale, '
          'sold_out, screen_tag, updated_at_ms) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            shopId,
            item.dishId,
            item.dishName.trim(),
            item.unit.trim(),
            item.sequence,
            item.categoryId,
            item.categoryName,
            item.categorySequence,
            item.dishSequence,
            item.stock,
            item.onSale ? 1 : 0,
            item.soldOut ? 1 : 0,
            item.screenTag,
            updatedAtMs,
          ],
        );
      }
      CashierCatalogChange? change;
      if (structureChanged) {
        final version = _nextLanConfigVersion(shopId);
        final eventSeq = _insertJournalEvent(
          eventId: 'catalog:$shopId:$version',
          shopId: shopId,
          eventType: 'config_changed',
          aggregateKey: 'config:$shopId',
          patches: const [],
          occurredAtMs: updatedAtMs,
        );
        change = CashierCatalogChange(
          eventSeq: eventSeq,
          configVersion: version,
        );
      }
      _database.execute('COMMIT');
      return change;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  List<CashierDishCatalogItem> readDishCatalog({required int shopId}) {
    final rows = _database.select(
      'SELECT id, dish_id, dish_name, unit, sort_index, category_id, '
      'category_name, category_sequence, dish_sequence, stock, onsale, '
      'sold_out, screen_tag '
      'FROM local_dish_catalog WHERE shop_id = ? '
      'ORDER BY id ASC',
      [shopId],
    );
    return rows
        .map(
          (row) => CashierDishCatalogItem(
            id: _int(row['id']),
            dishId: _int(row['dish_id']),
            dishName: '${row['dish_name']}',
            unit: '${row['unit']}',
            sequence: _int(row['sort_index']),
            categoryId: row['category_id'] == null
                ? null
                : _int(row['category_id']),
            categoryName: row['category_name'] == null
                ? null
                : '${row['category_name']}',
            categorySequence: row['category_sequence'] == null
                ? null
                : _int(row['category_sequence']),
            dishSequence: row['dish_sequence'] == null
                ? null
                : _int(row['dish_sequence']),
            stock: row['stock'] == null ? null : _int(row['stock']),
            onSale: _int(row['onsale']) == 1,
            soldOut: _int(row['sold_out']) == 1,
            screenTag: row['screen_tag'] == null
                ? null
                : '${row['screen_tag']}'.trim(),
          ),
        )
        .toList(growable: false);
  }

  int readLanConfigVersion(int shopId) {
    final key = 'lan_config_version:$shopId';
    final local = _database.select(
      'SELECT meta_value FROM local_kds_meta WHERE meta_key = ?',
      [key],
    );
    final cloud = _database.select(
      'SELECT config_version FROM local_kds_config WHERE shop_id = ?',
      [shopId],
    );
    final localVersion = local.isEmpty ? 0 : _int(local.single['meta_value']);
    final cloudVersion = cloud.isEmpty
        ? 0
        : _int(cloud.single['config_version']);
    return localVersion > cloudVersion ? localVersion : cloudVersion;
  }

  int _nextLanConfigVersion(
    int shopId, {
    int minimum = 0,
    bool cloudRefresh = false,
  }) {
    final local = _database.select(
      'SELECT meta_value FROM local_kds_meta WHERE meta_key = ?',
      ['lan_config_version:$shopId'],
    );
    final localVersion = local.isEmpty ? 0 : _int(local.single['meta_value']);
    final current = cloudRefresh ? localVersion : readLanConfigVersion(shopId);
    final next = current + 1 > minimum ? current + 1 : minimum;
    _database.execute(
      'INSERT INTO local_kds_meta(meta_key, meta_value) VALUES (?, ?) '
      'ON CONFLICT(meta_key) DO UPDATE SET meta_value = excluded.meta_value',
      ['lan_config_version:$shopId', '$next'],
    );
    return next;
  }

  String _catalogStructureFingerprint(List<CashierDishCatalogItem> items) {
    final rows =
        items
            .map(
              (item) => <String, Object?>{
                'dish_id': item.dishId,
                'dish_name': item.dishName.trim(),
                'unit': item.unit.trim(),
                'sequence': item.sequence,
                'category_id': item.categoryId,
                'category_name': item.categoryName?.trim(),
                'category_sequence': item.categorySequence,
                'dish_sequence': item.dishSequence,
              },
            )
            .toList(growable: false)
          ..sort((a, b) => _int(a['dish_id']).compareTo(_int(b['dish_id'])));
    return jsonEncode(rows);
  }

  List<CashierKdsChange> readChanges({
    required int shopId,
    required int afterSeq,
    int limit = 500,
  }) {
    final rows = _database.select(
      'SELECT * FROM local_event_journal WHERE shop_id = ? AND event_seq > ? '
      'ORDER BY event_seq ASC LIMIT ?',
      [shopId, afterSeq, limit.clamp(1, 1000)],
    );
    return rows
        .map((row) {
          final decoded = jsonDecode('${row['patches_json']}');
          return CashierKdsChange(
            eventSeq: _int(row['event_seq']),
            eventId: '${row['event_id']}',
            type: '${row['event_type']}',
            shopId: _int(row['shop_id']),
            occurredAtMs: _int(row['occurred_at_ms']),
            patches: decoded is List
                ? decoded
                      .whereType<Map>()
                      .map((value) => value.cast<String, Object?>())
                      .toList(growable: false)
                : const [],
          );
        })
        .toList(growable: false);
  }

  int get earliestRetainedEventSeq {
    final row = _database
        .select(
          'SELECT COALESCE(MIN(event_seq), 0) AS seq FROM local_event_journal',
        )
        .single;
    return _int(row['seq']);
  }

  int get latestEventSeq {
    final row = _database
        .select(
          'SELECT COALESCE(MAX(event_seq), 0) AS seq FROM local_event_journal',
        )
        .single;
    return _int(row['seq']);
  }

  Map<String, int> readQueueCounts(int shopId, {int? startMs, int? endMs}) {
    const queues = ['pending_prep', 'pending_cook', 'ready_serve', 'done'];
    final windowClause = (startMs != null && endMs != null && endMs > startMs)
        ? ' AND o.created_at_ms >= ? AND o.created_at_ms < ?'
        : '';
    final args = <Object?>[shopId];
    if (windowClause.isNotEmpty) args.addAll([startMs, endMs]);
    // 口径必须与 readWorkflowBoard / 划菜校验的可见量一致：
    // 按各队列可见数量（SUM）统计，而不是按 workflow_queue 字段分组数行数。
    // 否则三池相等的行会被计入中间队列，KDS 角标显示有量、实际可划为 0，
    // 划菜必然被 _advanceRow 拒绝（quantity exceeds remaining）。
    final row = _database.select('''
      SELECT
        SUM(CASE WHEN l.prep_remaining > 0 THEN l.prep_remaining ELSE 0 END)
          AS pending_prep,
        SUM(CASE WHEN l.cook_remaining - l.prep_remaining > 0
            THEN l.cook_remaining - l.prep_remaining ELSE 0 END)
          AS pending_cook,
        SUM(CASE WHEN l.ready_remaining - l.cook_remaining > 0
            THEN l.ready_remaining - l.cook_remaining ELSE 0 END)
          AS ready_serve,
        SUM(CASE WHEN l.line_quantity - l.refunded_quantity - l.ready_remaining > 0
            THEN l.line_quantity - l.refunded_quantity - l.ready_remaining ELSE 0 END)
          AS done
      FROM local_order_lines l
      JOIN local_orders o ON o.id = l.order_id
      WHERE o.shop_id = ? AND o.archived = 0$windowClause
      ''', args).single;
    return {for (final queue in queues) queue: _int(row[queue])};
  }

  int purgeExpiredJournal({required int nowMs, int limit = 50}) {
    _database.execute(
      'DELETE FROM local_event_journal WHERE rowid IN ('
      'SELECT rowid FROM local_event_journal WHERE retained_until_ms < ? LIMIT ?)',
      [nowMs, limit.clamp(1, 500)],
    );
    return _database.updatedRows;
  }

  void recordInteraction(CashierKdsInteractionLogDraft draft) {
    final traceId = draft.traceId.trim();
    if (draft.shopId <= 0 || traceId.isEmpty) {
      throw const CashierKdsValidation(
        'interaction trace and shop are required',
      );
    }
    final metadata = <String, Object?>{};
    for (final entry in draft.metadata.entries) {
      if (_interactionMetadataKeys.contains(entry.key)) {
        metadata[entry.key] = entry.value;
      }
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _database.execute(
      'INSERT INTO kds_interaction_logs ('
      'trace_id, shop_id, order_id, order_no, event_id, operation_id, cursor, '
      'source_side, target_side, direction, stage, action, status, attempt, '
      'http_status, business_code, duration_ms, device_code, error_type, '
      'error_summary, metadata_json, occurred_at_ms, created_at_ms'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _bounded(traceId, 200),
        draft.shopId,
        draft.orderId,
        _nullableBounded(draft.orderNo, 120),
        _nullableBounded(draft.eventId, 200),
        _nullableBounded(draft.operationId, 200),
        draft.cursor,
        draft.source.wireName,
        draft.target.wireName,
        draft.direction.wireName,
        draft.stage.wireName,
        _bounded(draft.action.trim(), 100),
        draft.status.wireName,
        draft.attempt.clamp(1, 1000000),
        draft.httpStatus,
        _nullableBounded(draft.businessCode, 100),
        draft.durationMs?.clamp(0, 86400000),
        _nullableBounded(draft.deviceCode, 120),
        _nullableBounded(draft.errorType, 100),
        _sanitizeInteractionError(draft.errorSummary),
        jsonEncode(metadata),
        draft.occurredAtMs,
        nowMs,
      ],
    );
  }

  bool tryRecordInteraction(CashierKdsInteractionLogDraft draft) {
    try {
      recordInteraction(draft);
      _interactionWritesSinceCleanup++;
      if (_interactionWritesSinceCleanup >= 1000) {
        _interactionWritesSinceCleanup = 0;
        cleanupInteractionLogRetention(
          nowMs: DateTime.now().millisecondsSinceEpoch,
        );
      }
      return true;
    } catch (_) {
      _droppedInteractionLogCount++;
      return false;
    }
  }

  bool recordInboundDeadLetter({
    required int shopId,
    required String eventId,
    required String eventType,
    required String error,
    required Map<String, Object?> rawEvent,
  }) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return tryRecordInteraction(
      CashierKdsInteractionLogDraft(
        traceId: eventId,
        shopId: shopId,
        eventId: eventId,
        cursor: _int(rawEvent['cursor']),
        source: KdsInteractionSide.cloud,
        target: KdsInteractionSide.cashier,
        direction: KdsInteractionDirection.inbound,
        stage: KdsInteractionStage.cloudDeliveryApply,
        action: eventType,
        status: KdsInteractionStatus.deadLetter,
        errorType: 'inbound_dead_letter',
        errorSummary: error,
        metadata: {'raw_event': rawEvent, 'quarantined': true},
        occurredAtMs: nowMs,
      ),
    );
  }

  List<CashierKdsInteractionLog> readInteractionLogs(
    CashierKdsInteractionLogFilter filter,
  ) {
    if (filter.shopId <= 0) return const [];
    final clauses = <String>['shop_id = ?'];
    final parameters = <Object?>[filter.shopId];
    if (filter.traceId?.trim().isNotEmpty == true) {
      clauses.add('trace_id = ?');
      parameters.add(filter.traceId!.trim());
    }
    if (filter.keyword?.trim().isNotEmpty == true) {
      clauses.add(
        '(trace_id LIKE ? OR order_no LIKE ? OR event_id LIKE ? OR operation_id LIKE ?)',
      );
      final pattern = '%${filter.keyword!.trim()}%';
      parameters.addAll([pattern, pattern, pattern, pattern]);
    }
    if (filter.fromMs != null) {
      clauses.add('occurred_at_ms >= ?');
      parameters.add(filter.fromMs);
    }
    if (filter.toMs != null) {
      clauses.add('occurred_at_ms <= ?');
      parameters.add(filter.toMs);
    }
    if (filter.statuses.isNotEmpty) {
      clauses.add(
        'status IN (${List.filled(filter.statuses.length, '?').join(', ')})',
      );
      parameters.addAll(filter.statuses.map((item) => item.wireName));
    }
    if (filter.stages.isNotEmpty) {
      clauses.add(
        'stage IN (${List.filled(filter.stages.length, '?').join(', ')})',
      );
      parameters.addAll(filter.stages.map((item) => item.wireName));
    }
    parameters.add(filter.limit.clamp(1, 500));
    parameters.add(filter.offset.clamp(0, 1000000));
    final rows = _database.select(
      'SELECT * FROM kds_interaction_logs WHERE ${clauses.join(' AND ')} '
      'ORDER BY occurred_at_ms DESC, id DESC LIMIT ? OFFSET ?',
      parameters,
    );
    return rows.map(_interactionLogFromRow).toList(growable: false);
  }

  int cleanupInteractionLogRetention({
    required int nowMs,
    Duration retention = const Duration(days: 30),
    int maxRows = 100000,
  }) {
    final boundedMax = maxRows.clamp(1, 1000000);
    _database.execute(
      'DELETE FROM kds_interaction_logs WHERE occurred_at_ms < ?',
      [nowMs - retention.inMilliseconds],
    );
    var deleted = _database.updatedRows;
    final count = _int(
      _database
          .select('SELECT COUNT(*) AS count FROM kds_interaction_logs')
          .single['count'],
    );
    if (count > boundedMax) {
      _database.execute(
        'DELETE FROM kds_interaction_logs WHERE id IN ('
        'SELECT id FROM kds_interaction_logs ORDER BY occurred_at_ms ASC, id ASC LIMIT ?)',
        [count - boundedMax],
      );
      deleted += _database.updatedRows;
    }
    return deleted;
  }

  CashierKdsInteractionLog _interactionLogFromRow(Row row) {
    Map<String, Object?> metadata = const {};
    try {
      final decoded = jsonDecode('${row['metadata_json']}');
      if (decoded is Map) metadata = decoded.cast<String, Object?>();
    } catch (_) {
      // A corrupt diagnostic row must not make the diagnostics page unusable.
    }
    return CashierKdsInteractionLog(
      id: _int(row['id']),
      traceId: '${row['trace_id']}',
      shopId: _int(row['shop_id']),
      orderId: row['order_id'] == null ? null : _int(row['order_id']),
      orderNo: row['order_no']?.toString(),
      eventId: row['event_id']?.toString(),
      operationId: row['operation_id']?.toString(),
      cursor: row['cursor'] == null ? null : _int(row['cursor']),
      source: KdsInteractionSide.parse(row['source_side']),
      target: KdsInteractionSide.parse(row['target_side']),
      direction: KdsInteractionDirection.parse(row['direction']),
      stage: KdsInteractionStage.parse(row['stage']),
      action: '${row['action']}',
      status: KdsInteractionStatus.parse(row['status']),
      attempt: _int(row['attempt']),
      httpStatus: row['http_status'] == null ? null : _int(row['http_status']),
      businessCode: row['business_code']?.toString(),
      durationMs: row['duration_ms'] == null ? null : _int(row['duration_ms']),
      deviceCode: row['device_code']?.toString(),
      errorType: row['error_type']?.toString(),
      errorSummary: row['error_summary']?.toString(),
      metadata: metadata,
      occurredAtMs: _int(row['occurred_at_ms']),
      createdAtMs: _int(row['created_at_ms']),
    );
  }

  static const _interactionMetadataKeys = <String>{
    'method',
    'path',
    'served_via',
    'recipient_count',
    'online_device_count',
    'attempt_delay_ms',
    'quantity',
    'detail_id',
    'detail_count',
    'projection_version',
    'queue',
    'queue_state',
    'event_type',
    'duplicate',
    'pending_frames',
    'pending_bytes',
    'unacknowledged_frames',
    'unacknowledged_bytes',
  };

  static String _bounded(String value, int limit) =>
      value.length <= limit ? value : value.substring(0, limit);

  static String? _nullableBounded(String? value, int limit) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return _bounded(normalized, limit);
  }

  static String? _sanitizeInteractionError(String? value) {
    var normalized = value?.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    if (normalized == null || normalized.isEmpty) return null;
    normalized = normalized
        .replaceAll(
          RegExp(r'Bearer\s+\S+', caseSensitive: false),
          'Bearer [REDACTED]',
        )
        .replaceAll(RegExp(r'\b1[3-9]\d{9}\b'), '[REDACTED_PHONE]')
        .replaceAll(
          RegExp(
            r'(authorization|token|password|secret)\s*[:=]\s*\S+',
            caseSensitive: false,
          ),
          '[REDACTED_SECRET]',
        );
    return _bounded(normalized, 500);
  }

  Map<String, int> cleanupRetention({
    required int nowMs,
    int maxJournalEvents = 100000,
    Duration completedOrderRetention = const Duration(days: 30),
    Duration terminalOutboxRetention = const Duration(days: 30),
    Duration terminalCommandRetention = const Duration(days: 30),
    Duration deliveryInboxRetention = const Duration(days: 30),
    Duration operationIdempotencyRetention = const Duration(days: 30),
    int maxTerminalRowsPerRun = 2000,
  }) {
    _safeBegin();
    try {
      _database.execute(
        'DELETE FROM local_event_journal WHERE retained_until_ms < ?',
        [nowMs],
      );
      var journalDeleted = _database.updatedRows;
      final count = _int(
        _database
            .select('SELECT COUNT(*) AS count FROM local_event_journal')
            .single['count'],
      );
      if (count > maxJournalEvents) {
        final cutoff = _int(
          _database.select(
            'SELECT event_seq FROM local_event_journal '
            'ORDER BY event_seq DESC LIMIT 1 OFFSET ?',
            [maxJournalEvents.clamp(1, 100000)],
          ).single['event_seq'],
        );
        _database.execute(
          'DELETE FROM local_event_journal WHERE event_seq <= ?',
          [cutoff],
        );
        journalDeleted += _database.updatedRows;
      }
      final completedBefore = nowMs - completedOrderRetention.inMilliseconds;
      final removable = _database.select(
        'SELECT o.id FROM local_orders o WHERE o.completed = 1 '
        'AND o.completed_at_ms <= ? AND NOT EXISTS ('
        'SELECT 1 FROM cloud_outbox e WHERE e.aggregate_key = '
        "'order:' || o.id AND e.state NOT IN ('delivered', 'discarded')) "
        'LIMIT ?',
        [completedBefore, min(maxTerminalRowsPerRun.clamp(1, 10000), 50)],
      );
      var completedOrdersDeleted = 0;
      for (final row in removable) {
        final orderId = _int(row['id']);
        _database.execute('DELETE FROM local_order_lines WHERE order_id = ?', [
          orderId,
        ]);
        _database.execute('DELETE FROM local_orders WHERE id = ?', [orderId]);
        completedOrdersDeleted += _database.updatedRows;
      }
      final boundedTerminalRows = maxTerminalRowsPerRun.clamp(1, 10000);
      final terminalOutboxBefore =
          nowMs - terminalOutboxRetention.inMilliseconds;
      _database.execute(
        'DELETE FROM cloud_outbox WHERE rowid IN ('
        'SELECT rowid FROM cloud_outbox '
        "WHERE state IN ('delivered', 'discarded') "
        'AND COALESCE(delivered_at_ms, updated_at_ms) <= ? '
        'ORDER BY COALESCE(delivered_at_ms, updated_at_ms) ASC LIMIT ?)',
        [terminalOutboxBefore, boundedTerminalRows],
      );
      final terminalOutboxDeleted = _database.updatedRows;
      final terminalCommandBefore =
          nowMs - terminalCommandRetention.inMilliseconds;
      _database.execute(
        'DELETE FROM pending_commands WHERE rowid IN ('
        'SELECT rowid FROM pending_commands '
        "WHERE status IN ('APPLIED', 'REJECTED', 'ACKED', 'CONFLICT') "
        'AND updated_at <= ? '
        'ORDER BY updated_at ASC LIMIT ?)',
        [terminalCommandBefore, boundedTerminalRows],
      );
      final terminalCommandsDeleted = _database.updatedRows;
      final deliveryInboxBefore = nowMs - deliveryInboxRetention.inMilliseconds;
      _database.execute(
        'DELETE FROM cloud_delivery_inbox WHERE rowid IN ('
        'SELECT rowid FROM cloud_delivery_inbox WHERE received_at_ms <= ? '
        'ORDER BY received_at_ms ASC LIMIT ?)',
        [deliveryInboxBefore, boundedTerminalRows],
      );
      final deliveryInboxDeleted = _database.updatedRows;
      final operationBefore =
          nowMs - operationIdempotencyRetention.inMilliseconds;
      _database.execute(
        'DELETE FROM local_operation_events WHERE rowid IN ('
        'SELECT rowid FROM local_operation_events WHERE occurred_at_ms <= ? '
        'ORDER BY occurred_at_ms ASC LIMIT ?)',
        [operationBefore, boundedTerminalRows],
      );
      final operationIdempotencyDeleted = _database.updatedRows;
      _database.execute('COMMIT');
      return {
        'journal_deleted': journalDeleted,
        'completed_orders_deleted': completedOrdersDeleted,
        'terminal_outbox_deleted': terminalOutboxDeleted,
        'terminal_commands_deleted': terminalCommandsDeleted,
        'delivery_inbox_deleted': deliveryInboxDeleted,
        'operation_idempotency_deleted': operationIdempotencyDeleted,
      };
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  void writeConfigSnapshot(CashierKdsConfigSnapshot snapshot) {
    if (snapshot.shopId <= 0 || snapshot.version < 0) {
      throw const CashierKdsValidation('invalid configuration snapshot');
    }
    _database.execute(
      'INSERT INTO local_kds_config '
      '(shop_id, config_version, payload_json, updated_at_ms, expires_at_ms) '
      'VALUES (?, ?, ?, ?, ?) ON CONFLICT(shop_id) DO UPDATE SET '
      'config_version = excluded.config_version, payload_json = excluded.payload_json, '
      'updated_at_ms = excluded.updated_at_ms, expires_at_ms = excluded.expires_at_ms '
      'WHERE excluded.config_version >= local_kds_config.config_version',
      [
        snapshot.shopId,
        snapshot.version,
        jsonEncode(snapshot.payload),
        snapshot.updatedAtMs,
        snapshot.expiresAtMs,
      ],
    );
  }

  String ensureCashierDeviceCode(String? configuredCode) {
    final rows = _database.select(
      "SELECT meta_value FROM local_kds_meta WHERE meta_key = 'cashier_device_code'",
    );
    if (rows.isNotEmpty) return '${rows.first['meta_value']}';
    final configured = configuredCode?.trim() ?? '';
    final node = _database
        .select(
          "SELECT meta_value FROM local_kds_meta WHERE meta_key = 'primary_node_id'",
        )
        .single;
    final value = configured.isEmpty ? '${node['meta_value']}' : configured;
    _database.execute(
      "INSERT INTO local_kds_meta(meta_key, meta_value) VALUES ('cashier_device_code', ?)",
      [value],
    );
    return value;
  }

  int? readConfiguredLanPort() {
    final rows = _database.select(
      "SELECT meta_value FROM local_kds_meta WHERE meta_key = 'kds_lan_port'",
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['meta_value'];
    return int.tryParse('$raw');
  }

  void setConfiguredLanPort(int port) {
    if (port < 1024 || port > 65535) {
      throw CashierKdsValidation('端口号必须在 1024 到 65535 之间：$port');
    }
    _database.execute(
      "INSERT INTO local_kds_meta(meta_key, meta_value) VALUES ('kds_lan_port', ?) "
      "ON CONFLICT(meta_key) DO UPDATE SET meta_value = excluded.meta_value",
      ['$port'],
    );
  }

  int applyConfigSnapshot(CashierKdsConfigSnapshot snapshot) {
    if (snapshot.authorityDeviceCode == null ||
        snapshot.authorityEnforcement != 'primary_only') {
      throw const CashierKdsValidation(
        'configuration must contain a primary_only authority device',
      );
    }
    _safeBegin();
    try {
      final current = _database.select(
        'SELECT config_version FROM local_kds_config WHERE shop_id = ?',
        [snapshot.shopId],
      );
      if (current.isNotEmpty &&
          _int(current.first['config_version']) >= snapshot.version) {
        _database.execute('COMMIT');
        return 0;
      }
      _database.execute(
        'INSERT INTO local_kds_config '
        '(shop_id, config_version, payload_json, updated_at_ms, expires_at_ms) '
        'VALUES (?, ?, ?, ?, ?) ON CONFLICT(shop_id) DO UPDATE SET '
        'config_version = excluded.config_version, payload_json = excluded.payload_json, '
        'updated_at_ms = excluded.updated_at_ms, expires_at_ms = excluded.expires_at_ms',
        [
          snapshot.shopId,
          snapshot.version,
          jsonEncode(snapshot.payload),
          snapshot.updatedAtMs,
          snapshot.expiresAtMs,
        ],
      );
      // Cloud owns catalog metadata, but this cashier owns runtime
      // availability. Mark missing catalog entries off-sale without deleting
      // their stock/sold-out facts or their local availability revision.
      _database.execute(
        'UPDATE local_dish_catalog SET onsale = 0 WHERE shop_id = ?',
        [snapshot.shopId],
      );
      final rawCatalog = snapshot.payload['catalog'];
      if (rawCatalog is List) {
        var fallbackSort = 0;
        for (final raw in rawCatalog.whereType<Map>()) {
          final dishId = _int(raw['dish_id'] ?? raw['id']);
          final name = '${raw['dish_name'] ?? raw['name'] ?? ''}'.trim();
          if (dishId <= 0 || name.isEmpty) continue;
          final dishScreenTag = '${raw['screen_tag'] ?? raw['screenTag'] ?? ''}'
              .trim();
          _database.execute(
            'INSERT INTO local_dish_catalog '
            '(shop_id, dish_id, dish_name, unit, sort_index, category_id, '
            'category_name, category_sequence, dish_sequence, stock, onsale, '
            'sold_out, screen_tag, updated_at_ms) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
            'ON CONFLICT(shop_id, dish_id) DO UPDATE SET '
            'dish_name = excluded.dish_name, unit = excluded.unit, '
            'sort_index = excluded.sort_index, '
            'category_id = excluded.category_id, '
            'category_name = excluded.category_name, '
            'category_sequence = excluded.category_sequence, '
            'dish_sequence = excluded.dish_sequence, '
            'onsale = excluded.onsale, screen_tag = excluded.screen_tag',
            [
              snapshot.shopId,
              dishId,
              name,
              '${raw['unit'] ?? '份'}',
              _int(raw['sorting'] ?? raw['sort_index'] ?? fallbackSort++),
              raw['category_id'],
              raw['category_name'],
              raw['category_sequence'],
              raw['dish_sequence'],
              raw['stock'],
              _bool(raw['onsale'], fallback: true) ? 1 : 0,
              _bool(raw['sold_out']) ? 1 : 0,
              dishScreenTag.isEmpty ? null : dishScreenTag,
              snapshot.updatedAtMs,
            ],
          );
        }
      }
      _nextLanConfigVersion(
        snapshot.shopId,
        minimum: snapshot.version,
        cloudRefresh: true,
      );
      final eventId = 'config:${snapshot.shopId}:${snapshot.version}';
      final eventSeq = _insertJournalEvent(
        eventId: eventId,
        shopId: snapshot.shopId,
        eventType: 'config_changed',
        aggregateKey: 'config:${snapshot.shopId}',
        patches: const [],
        occurredAtMs: snapshot.updatedAtMs,
      );
      _database.execute('COMMIT');
      return eventSeq;
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  CashierKdsConfigSnapshot? readConfigSnapshot({
    required int shopId,
    required int nowMs,
    bool allowExpired = false,
  }) {
    final rows = _database.select(
      'SELECT * FROM local_kds_config WHERE shop_id = ?',
      [shopId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final expiresAtMs = _int(row['expires_at_ms']);
    if (!allowExpired && expiresAtMs < nowMs) return null;
    return CashierKdsConfigSnapshot(
      shopId: shopId,
      version: _int(row['config_version']),
      payload: _jsonMap(row['payload_json']),
      updatedAtMs: _int(row['updated_at_ms']),
      expiresAtMs: expiresAtMs,
    );
  }

  bool _isOrderCommand(LocalKdsCommandType type) =>
      type == LocalKdsCommandType.advanceOrder ||
      type == LocalKdsCommandType.rushOrder ||
      type == LocalKdsCommandType.completeOrder ||
      type == LocalKdsCommandType.archiveOrder;

  Map<String, Object?> _captureCommandState(LocalKdsCommand command) {
    final orderIds = <int>{};
    if (command.type == LocalKdsCommandType.archiveClear) {
      final completedBefore =
          command.occurredAtMs - const Duration(days: 30).inMilliseconds;
      orderIds.addAll(
        _database
            .select(
              'SELECT o.id FROM local_orders o WHERE o.shop_id = ? '
              'AND o.archived = 1 AND o.completed = 1 '
              'AND o.completed_at_ms <= ? AND NOT EXISTS ('
              'SELECT 1 FROM cloud_outbox e WHERE '
              "e.aggregate_key = 'order:' || o.id "
              "AND e.state NOT IN ('delivered', 'discarded'))",
              [command.shopId, completedBefore],
            )
            .map((row) => _int(row['id'])),
      );
    } else if (command.target.orderId case final targetOrderId?) {
      final rows = _database.select(
        'SELECT id FROM local_orders WHERE (id = ? OR cloud_order_id = ?) AND shop_id = ?',
        [targetOrderId, targetOrderId, command.shopId],
      );
      if (rows.isNotEmpty) {
        orderIds.add(_int(rows.first['id']));
      } else {
        orderIds.add(targetOrderId);
      }
    } else {
      final detailIds = <int>{
        if (command.target.detailId case final detailId?) detailId,
        ...command.target.detailIds,
      };
      for (final detailId in detailIds) {
        final rows = _database.select(
          'SELECT l.order_id FROM local_order_lines l '
          'JOIN local_orders o ON o.id = l.order_id '
          'WHERE l.id = ? AND o.shop_id = ?',
          [detailId, command.shopId],
        );
        if (rows.isNotEmpty) orderIds.add(_int(rows.single['order_id']));
      }
    }
    return _captureOrderState(orderIds);
  }

  Map<String, Object?> _captureOrderState(Iterable<int> orderIds) {
    final orders = <Map<String, Object?>>[];
    final lines = <Map<String, Object?>>[];
    for (final orderId in orderIds.toSet()) {
      final orderRows = _database.select(
        'SELECT * FROM local_orders WHERE id = ?',
        [orderId],
      );
      if (orderRows.isEmpty) continue;
      orders.add(Map<String, Object?>.from(orderRows.single));
      lines.addAll(
        _database
            .select(
              'SELECT * FROM local_order_lines WHERE order_id = ? ORDER BY id',
              [orderId],
            )
            .map((row) => Map<String, Object?>.from(row)),
      );
    }
    return {'orders': orders, 'lines': lines};
  }

  List<Map<String, Object?>> _servePrintLines({
    required LocalKdsCommand command,
    required Map<String, Object?> beforeState,
    required List<Map<String, Object?>> patches,
  }) {
    if ((command.type != LocalKdsCommandType.advanceItem &&
            command.type != LocalKdsCommandType.advanceOrder) ||
        command.target.fromQueue != 'ready_serve') {
      return const [];
    }
    final rawBeforeLines = beforeState['lines'];
    if (rawBeforeLines is! List) return const [];
    final readyBefore = <int, int>{};
    for (final raw in rawBeforeLines.whereType<Map>()) {
      final detailId = _int(raw['id']);
      if (detailId > 0) readyBefore[detailId] = _int(raw['ready_remaining']);
    }
    final lines = <Map<String, Object?>>[];
    for (final patch in patches) {
      final detailId = _int(patch['detail_id']);
      final quantity =
          (readyBefore[detailId] ?? 0) - _int(patch['ready_remaining']);
      if (detailId > 0 && quantity > 0) {
        lines.add({
          'order_id': _int(patch['order_id']),
          'local_detail_id': detailId,
          'quantity': quantity,
        });
      }
    }
    return lines;
  }

  void _insertServePrintEvent({
    required LocalKdsCommand command,
    required int orderId,
    required List<Map<String, Object?>> lines,
    required bool multipleOrders,
  }) {
    if (!_servePrintEnabled(command.shopId)) return;
    final orderLines = lines
        .where((line) => _int(line['order_id']) == orderId)
        .map(
          (line) => <String, Object?>{
            'local_detail_id': _int(line['local_detail_id']),
            'quantity': _int(line['quantity']),
          },
        )
        .toList(growable: false);
    if (orderLines.isEmpty) return;
    _insertCloudEvent(
      eventId: _derivedCloudEventId(
        command.commandId,
        multipleOrders ? 'serve-print:order:$orderId' : 'serve-print',
      ),
      shopId: command.shopId,
      eventType: cashierServeTicketPrintEventType,
      aggregateKey: 'serve-print:${_cloudOrderAggregateKey(orderId)}',
      payload: {'lines': orderLines},
      nowMs: command.occurredAtMs,
    );
  }

  bool _servePrintEnabled(int shopId) {
    final snapshot = readConfigSnapshot(
      shopId: shopId,
      nowMs: DateTime.now().millisecondsSinceEpoch,
      allowExpired: true,
    );
    final rawWorkflow = snapshot?.payload['workflow'];
    final workflow = rawWorkflow is Map
        ? rawWorkflow.cast<String, Object?>()
        : const <String, Object?>{};
    return _bool(workflow['serve_print_enabled'], fallback: true);
  }

  String _derivedCloudEventId(String commandId, String suffix) {
    final candidate = '$commandId:$suffix';
    if (candidate.length <= 128) return candidate;
    final digest = sha256.convert(utf8.encode(candidate)).toString();
    final prefix = commandId.length <= 63
        ? commandId
        : commandId.substring(0, 63);
    return '$prefix:$digest';
  }

  List<Map<String, Object?>> _advanceMergedRows(
    LocalKdsCommand command,
    List<int> detailIds,
  ) {
    if (command.expectedRevision != null) {
      throw const CashierKdsValidation(
        'expected_revision is only valid for a single detail',
      );
    }
    final rows = <Row>[];
    for (final detailId in detailIds.toSet()) {
      final found = _database.select(
        'SELECT l.*, o.shop_id, o.order_no, o.table_number, '
        'o.fulfillment_type, o.remark FROM local_order_lines l '
        'JOIN local_orders o ON o.id = l.order_id '
        'WHERE l.id = ? AND o.shop_id = ?',
        [detailId, command.shopId],
      );
      if (found.isEmpty) throw const CashierKdsValidation('line not found');
      rows.add(found.single);
    }
    rows.sort((left, right) {
      final byTime = _int(
        left['created_at_ms'],
      ).compareTo(_int(right['created_at_ms']));
      return byTime != 0
          ? byTime
          : _int(left['id']).compareTo(_int(right['id']));
    });
    final first = rows.first;
    final fromQueue = command.target.fromQueue;
    if (fromQueue == null || fromQueue.isEmpty) {
      throw const CashierKdsValidation('target.from_queue is required');
    }
    for (final row in rows) {
      if (_int(row['dish_id']) != _int(first['dish_id']) ||
          '${row['fulfillment_type']}' != '${first['fulfillment_type']}') {
        throw const CashierKdsValidation(
          'merged details must share dish, fulfillment and from_queue',
        );
      }
      if (_int(row['held']) == 1) {
        throw const CashierKdsConflict('held line cannot be advanced');
      }
    }
    final rawExpected = command.payload['expected_revisions'];
    if (rawExpected is! Map) {
      throw const CashierKdsValidation('expected_revisions must be an object');
    }
    final expected = <int, Object?>{};
    for (final entry in rawExpected.entries) {
      final id = int.tryParse('${entry.key}');
      if (id == null || id <= 0 || expected.containsKey(id)) {
        throw const CashierKdsValidation(
          'expected_revisions contains an invalid or duplicate detail id',
        );
      }
      expected[id] = entry.value;
    }
    final targetIds = detailIds.toSet();
    if (expected.keys.toSet().difference(targetIds).isNotEmpty ||
        targetIds.difference(expected.keys.toSet()).isNotEmpty) {
      throw const CashierKdsValidation(
        'expected_revisions must exactly cover target.detail_ids',
      );
    }
    for (final row in rows) {
      final detailId = _int(row['id']);
      final value = expected[detailId];
      if (value is! num || value.toInt() != _int(row['local_revision'])) {
        throw const CashierKdsConflict('local revision mismatch');
      }
    }
    final total = command.quantity ?? 0;
    if (total <= 0) {
      throw const CashierKdsValidation(
        'quantity must be positive for merged advance',
      );
    }
    var unallocated = total;
    final affectedIds = <int>[];
    for (final row in rows) {
      if (unallocated == 0) break;
      final remaining = _visibleQuantity(row, fromQueue);
      if (remaining <= 0) continue;
      final allocated = unallocated < remaining ? unallocated : remaining;
      _advanceRow(
        row,
        fromQueue: fromQueue,
        quantity: allocated,
        occurredAtMs: command.occurredAtMs,
      );
      affectedIds.add(_int(row['id']));
      unallocated -= allocated;
    }
    if (unallocated != 0) {
      throw const CashierKdsValidation('quantity exceeds merged remaining');
    }
    return affectedIds
        .map((detailId) {
          final updated = _database.select(
            'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
            'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
            'WHERE l.id = ?',
            [detailId],
          ).single;
          return _linePatch(updated, fromQueue: fromQueue);
        })
        .toList(growable: false);
  }

  void _advanceRow(
    Row row, {
    required String fromQueue,
    int? quantity,
    int? expectedRevision,
    required int occurredAtMs,
  }) {
    final revision = _int(row['local_revision']);
    if (expectedRevision != null && revision != expectedRevision) {
      throw const CashierKdsConflict('local revision mismatch');
    }
    var prep = _int(row['prep_remaining']);
    var cook = _int(row['cook_remaining']);
    var ready = _int(row['ready_remaining']);
    final remaining = _visibleQuantity(row, fromQueue);
    final amount = quantity ?? remaining;
    if (amount <= 0 || amount > remaining) {
      throw CashierKdsValidation(
        'quantity exceeds remaining: detail=${row['id']} queue=$fromQueue '
        'amount=$amount remaining=$remaining',
      );
    }
    if (fromQueue == 'pending_prep') prep -= amount;
    if (fromQueue == 'pending_cook') cook -= amount;
    if (fromQueue == 'ready_serve') ready -= amount;
    final nextQueue = _summaryQueue(prep, cook, ready);
    _database.execute(
      'UPDATE local_order_lines SET workflow_queue = ?, prep_remaining = ?, '
      'cook_remaining = ?, ready_remaining = ?, done_line = ?, '
      'completed_at_ms = CASE WHEN ? = 1 THEN ? ELSE completed_at_ms END, '
      'local_revision = local_revision + 1, updated_at_ms = ? WHERE id = ?',
      [
        nextQueue,
        prep,
        cook,
        ready,
        nextQueue == 'done' ? 1 : 0,
        fromQueue == 'ready_serve' ? 1 : 0,
        occurredAtMs,
        occurredAtMs,
        row['id'],
      ],
    );
  }

  void _revokeRow(
    Row row, {
    required String? fromQueue,
    int? quantity,
    required int occurredAtMs,
  }) {
    if (fromQueue == null) {
      throw const CashierKdsValidation('target.from_queue is required');
    }
    var prep = _int(row['prep_remaining']);
    var cook = _int(row['cook_remaining']);
    var ready = _int(row['ready_remaining']);
    final available = _visibleQuantity(row, fromQueue);
    final amount = quantity ?? available;
    if (amount <= 0 || amount > available) {
      throw const CashierKdsValidation('quantity exceeds revocable amount');
    }
    if (fromQueue == 'pending_cook') prep += amount;
    if (fromQueue == 'ready_serve') cook += amount;
    if (fromQueue == 'done') ready += amount;
    if (fromQueue == 'pending_prep') {
      throw const CashierKdsValidation('prep queue is not revocable');
    }
    _database.execute(
      'UPDATE local_order_lines SET workflow_queue = ?, prep_remaining = ?, '
      'cook_remaining = ?, ready_remaining = ?, '
      'done_line = 0, '
      'local_revision = local_revision + 1, updated_at_ms = ? WHERE id = ?',
      [
        _summaryQueue(prep, cook, ready),
        prep,
        cook,
        ready,
        occurredAtMs,
        row['id'],
      ],
    );
  }

  int _visibleQuantity(Row row, String queue) {
    final active = _int(row['line_quantity']) - _int(row['refunded_quantity']);
    final prep = _int(row['prep_remaining']);
    final cook = _int(row['cook_remaining']);
    final ready = _int(row['ready_remaining']);
    return switch (queue) {
      'pending_prep' => prep,
      'pending_cook' => cook - prep,
      'ready_serve' => ready - cook,
      'done' => active - ready,
      _ => throw const CashierKdsValidation('queue is not advanceable'),
    };
  }

  String _summaryQueue(int prep, int cook, int ready) => prep > 0
      ? 'pending_prep'
      : cook > 0
      ? 'pending_cook'
      : ready > 0
      ? 'ready_serve'
      : 'done';

  void _setLineFlag(int detailId, String column, bool value, int nowMs) {
    if (column != 'rushed' && column != 'held') {
      throw const CashierKdsValidation('invalid line flag');
    }
    _database.execute(
      'UPDATE local_order_lines SET $column = ?, '
      'local_revision = local_revision + 1, updated_at_ms = ? WHERE id = ?',
      [value ? 1 : 0, nowMs, detailId],
    );
  }

  Map<String, Object?> _linePatch(Row row, {String? fromQueue}) {
    final orderId = _int(row['order_id']);
    final rawOrderRevision = row['order_revision'];
    final orderRevision = rawOrderRevision == null
        ? _int(
            _database.select(
              'SELECT local_revision FROM local_orders WHERE id = ?',
              [orderId],
            ).single['local_revision'],
          )
        : _int(rawOrderRevision);
    return {
      'detail_id': _int(row['id']),
      'order_id': orderId,
      if (_int(row['cloud_order_id']) > 0)
        'cloud_order_id': _int(row['cloud_order_id']),
      'dish_id': _int(row['dish_id']),
      'dish_name': '${row['dish_name']}',
      'line_quantity': _int(row['line_quantity']),
      'refunded_quantity': _int(row['refunded_quantity']),
      'prep_remaining': _int(row['prep_remaining']),
      'cook_remaining': _int(row['cook_remaining']),
      'ready_remaining': _int(row['ready_remaining']),
      'local_revision': _int(row['local_revision']),
      'order_revision': orderRevision > 0 ? orderRevision : 1,
      'fulfillment_bucket': '${row['fulfillment_type']}',
      'fulfillment_channel': '${row['fulfillment_type']}',
      'table_number': '${row['table_number']}',
      'order_no': '${row['order_no']}',
      'specification': '${row['specification']}',
      'unit': '${row['unit']}',
      'remark': '${row['remark']}',
      'created_at_ms': _int(row['created_at_ms']),
      'serving_duration_minutes': _int(row['serving_duration_minutes']) > 0
          ? _int(row['serving_duration_minutes'])
          : 10,
      'completed_at_ms': row['completed_at_ms'] == null
          ? null
          : _int(row['completed_at_ms']),
      'held': _int(row['held']) == 1,
      'rushed': _int(row['rushed']) == 1,
      'lacked': _int(row['lacked']) == 1,
      'removed': _int(row['refunded_quantity']) >= _int(row['line_quantity']),
      'workflow_queue': '${row['workflow_queue']}',
      'is_combo': _int(row['is_combo']) == 1,
      'combo': _int(row['is_combo']) == 1,
      'set_meal': _int(row['is_combo']) == 1,
      if (row['combo_name'] != null && '${row['combo_name']}'.isNotEmpty)
        'combo_name': '${row['combo_name']}',
      if (row['combo_id'] != null && _int(row['combo_id']) > 0)
        'combo_id': _int(row['combo_id']),
    };
  }

  Map<String, Object?> _orderSummary(int orderId) {
    final row = _database.select(
      'SELECT id, order_no, table_number, order_status, local_revision, rushed, '
      'completed, archived, completed_at_ms, archived_at_ms '
      'FROM local_orders WHERE id = ?',
      [orderId],
    ).single;
    return {
      'order_id': _int(row['id']),
      'order_no': '${row['order_no']}',
      'table_number': '${row['table_number']}',
      'status': '${row['order_status']}',
      'order_status': '${row['order_status']}',
      'order_revision': _int(row['local_revision']),
      'local_revision': _int(row['local_revision']),
      'rushed': _int(row['rushed']) == 1,
      'completed': _int(row['completed']) == 1,
      'archived': _int(row['archived']) == 1,
      if (row['completed_at_ms'] != null)
        'completed_at_ms': _int(row['completed_at_ms']),
      if (row['archived_at_ms'] != null)
        'archived_at_ms': _int(row['archived_at_ms']),
    };
  }

  Map<String, Object?> _cloudStatePayload({
    required int orderId,
    required String operationType,
    required String commandId,
    required String operationId,
    required int eventSeq,
    required String actorDeviceCode,
  }) {
    final order = _database.select('SELECT * FROM local_orders WHERE id = ?', [
      orderId,
    ]).single;
    final mappedOrderId = _int(order['cloud_order_id']);
    final lineRows = _database.select(
      'SELECT l.*, o.order_no, o.cloud_order_id, o.table_number, o.fulfillment_type, o.remark '
      'FROM local_order_lines l JOIN local_orders o ON o.id = l.order_id '
      'WHERE l.order_id = ? ORDER BY l.id',
      [orderId],
    );
    // 云端出生的订单（delivery 下行，source_channel 非空）：云端只认识正式
    // id，订单级 id 必须始终使用正式 id；行级按映射情况逐行选择——已映射行
    // 用正式 detail_id，本地新加未映射行用本地 id 并携带 local_detail_id
    // 别名，由云端建立映射后在 ACK 的 detail_mappings 中返回。
    final cloudBorn =
        mappedOrderId > 0 &&
        '${order['source_channel'] ?? ''}'.trim().isNotEmpty;
    // 本地出生的订单：aggregate 固定为本地 id，云端校验「aggregate_key 与
    // payload 本地订单 id 必须一致」（实测 4000），因此 local_order_id /
    // local_detail_id 别名必须始终携带，与是否已映射无关；已映射时
    // order_id / detail_id 可同时使用正式 id。
    final orderMapped = mappedOrderId > 0;
    final formalOrderId = orderMapped ? mappedOrderId : orderId;
    final includeLocalOrderId = !cloudBorn;
    final lines = lineRows
        .map((row) {
          final patch = _linePatch(row);
          final localDetailId = _int(patch['detail_id']);
          final mappedDetailId = _int(row['cloud_detail_id']);
          return <String, Object?>{
            ...patch,
            'order_id': formalOrderId,
            'detail_id': mappedDetailId > 0 ? mappedDetailId : localDetailId,
            if (includeLocalOrderId) 'local_order_id': orderId,
            if (includeLocalOrderId || mappedDetailId <= 0)
              'local_detail_id': localDetailId,
          };
        })
        .toList(growable: false);
    final dishIds = lineRows.map((row) => _int(row['dish_id'])).toSet();
    final availability = <Map<String, Object?>>[];
    for (final dishId in dishIds) {
      final rows = _database.select(
        'SELECT stock, sold_out, updated_at_ms FROM local_dish_catalog '
        'WHERE shop_id = ? AND dish_id = ?',
        [_int(order['shop_id']), dishId],
      );
      if (rows.isNotEmpty) {
        // §2 sentinel conversion: local stock=-1 means "不限量" (unlimited);
        // omit (null) so the cloud keeps its existing stock value and only
        // updates sold_out.  stock>=0 is sent as-is.
        final rawStock = rows.single['stock'];
        final stock = rawStock == null ? null : _int(rawStock);
        availability.add({
          'dish_id': dishId,
          'availability_revision': _int(
            rows.single['updated_at_ms'],
          ).clamp(1, 1 << 62),
          'stock': stock != null && stock < 0 ? null : stock,
          'sold_out': _int(rows.single['sold_out']) == 1,
        });
      }
    }
    final orderRevision = _int(order['local_revision']);
    final orderState = <String, Object?>{
      'order_id': formalOrderId,
      if (includeLocalOrderId) 'local_order_id': orderId,
      'order_no': '${order['order_no']}',
      'order_revision': orderRevision,
      'status': '${order['order_status']}',
      'order_status': '${order['order_status']}',
      'table_number': '${order['table_number']}',
      'rushed': _int(order['rushed']) == 1,
      'completed': _int(order['completed']) == 1,
      'archived': _int(order['archived']) == 1,
      'updated_at_ms': _int(order['updated_at_ms']),
    };
    return {
      'device_code': ensureCashierDeviceCode(null),
      'actor_device_code': actorDeviceCode,
      'command_id': commandId,
      'operation_id': operationId,
      'event_seq': eventSeq,
      'operation_type': operationType,
      'order_id': formalOrderId,
      if (includeLocalOrderId) 'local_order_id': orderId,
      'order_revision': orderRevision,
      'orders': [orderState],
      'lines': lines,
      'dish_availability': availability,
    };
  }

  String _cloudOrderAggregateKey(int localOrderId) {
    // aggregate key 必须在订单生命周期内稳定，且云端可解析：
    // - 本地出生的订单：固定使用本地 id。云端从 order_created 事件学习
    //   本地 id ↔ 正式订单的映射，后续事件必须沿用同一 aggregate。
    // - 云端出生的订单（经 delivery 下行，source_channel 非空）：本地从未
    //   发送 order_created，云端不存在本地 id 映射，必须使用云端正式 id，
    //   否则云端前置映射检查返回 4090 且永远不会恢复。
    final rows = _database.select(
      'SELECT cloud_order_id, source_channel FROM local_orders WHERE id = ?',
      [localOrderId],
    );
    if (rows.isEmpty) return 'order:$localOrderId';
    final cloudOrderId = _int(rows.first['cloud_order_id']);
    final sourceChannel = '${rows.first['source_channel'] ?? ''}'.trim();
    if (cloudOrderId > 0 && sourceChannel.isNotEmpty) {
      return 'order:$cloudOrderId';
    }
    return 'order:$localOrderId';
  }

  int _insertJournalEvent({
    required String eventId,
    required int shopId,
    required String eventType,
    required String aggregateKey,
    required List<Map<String, Object?>> patches,
    required int occurredAtMs,
  }) {
    const retentionMs = 7 * 24 * 60 * 60 * 1000;
    _database.execute(
      'INSERT INTO local_event_journal '
      '(event_id, shop_id, event_type, aggregate_key, patches_json, '
      'occurred_at_ms, retained_until_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        eventId,
        shopId,
        eventType,
        aggregateKey,
        jsonEncode(patches),
        occurredAtMs,
        occurredAtMs + retentionMs,
      ],
    );
    final eventSeq = _database.lastInsertRowId;
    _database.execute(
      "INSERT OR REPLACE INTO local_kds_meta(meta_key, meta_value) "
      "VALUES ('local_event_seq', ?)",
      ['$eventSeq'],
    );
    return eventSeq;
  }

  int _eventSeqFor(String eventId) {
    final rows = _database.select(
      'SELECT event_seq FROM local_event_journal WHERE event_id = ?',
      [eventId],
    );
    return rows.isEmpty ? 0 : _int(rows.first['event_seq']);
  }

  void _insertCloudEvent({
    required String eventId,
    required int shopId,
    required String eventType,
    required String aggregateKey,
    required Map<String, Object?> payload,
    required int nowMs,
    String? requestFingerprint,
  }) {
    final aggregateSequence = _nextCloudAggregateSequence(aggregateKey);
    _database.execute(
      'INSERT INTO cloud_outbox '
      '(event_id, shop_id, event_type, aggregate_key, payload_json, request_fingerprint, '
      'aggregate_sequence, next_attempt_at_ms, created_at_ms, updated_at_ms) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        eventId,
        shopId,
        eventType,
        aggregateKey,
        jsonEncode(payload),
        requestFingerprint,
        aggregateSequence,
        nowMs,
        nowMs,
        nowMs,
      ],
    );
  }

  CashierCloudEvent _cloudEventFromRow(Row row) {
    final eventType = '${row['event_type']}';
    final shopId = _int(row['shop_id']);
    final payload = _jsonMap(row['payload_json']);
    if (eventType == cashierServeTicketPrintEventType &&
        payload['lines'] is List) {
      payload['lines'] = (payload['lines'] as List)
          .whereType<Map>()
          .map((raw) {
            final line = raw.cast<String, Object?>();
            final localDetailId = _int(line['local_detail_id']);
            final rows = _database.select(
              'SELECT l.cloud_detail_id FROM local_order_lines l '
              'JOIN local_orders o ON o.id = l.order_id '
              'WHERE l.id = ? AND o.shop_id = ?',
              [localDetailId, shopId],
            );
            final cloudDetailId = rows.isEmpty
                ? 0
                : _int(rows.single['cloud_detail_id']);
            return <String, Object?>{
              ...line,
              if (cloudDetailId > 0) 'detail_id': cloudDetailId,
            };
          })
          .toList(growable: false);
    } else if (eventType == 'dishes_added') {
      final localOrderId = _int(payload['local_order_id']);
      if (localOrderId > 0 &&
          (payload['cloud_order_no'] == null ||
              '${payload['cloud_order_no']}'.trim().isEmpty)) {
        final orderRows = _database.select(
          'SELECT cloud_order_id, cloud_order_no FROM local_orders WHERE id = ?',
          [localOrderId],
        );
        if (orderRows.isNotEmpty) {
          final cNo = '${orderRows.first['cloud_order_no'] ?? ''}'.trim();
          final cId = _int(orderRows.first['cloud_order_id']);
          if (cNo.isNotEmpty) payload['cloud_order_no'] = cNo;
          if (cId > 0) payload['cloud_order_id'] = cId;
        }
      }
    } else if (eventType == 'refund_item') {
      final localOrderId = _int(payload['local_order_id']);
      if (localOrderId > 0 &&
          (payload['cloud_order_no'] == null ||
              '${payload['cloud_order_no']}'.trim().isEmpty)) {
        final orderRows = _database.select(
          'SELECT cloud_order_id, cloud_order_no FROM local_orders WHERE id = ?',
          [localOrderId],
        );
        if (orderRows.isNotEmpty) {
          final cNo = '${orderRows.first['cloud_order_no'] ?? ''}'.trim();
          final cId = _int(orderRows.first['cloud_order_id']);
          if (cNo.isNotEmpty) payload['cloud_order_no'] = cNo;
          if (cId > 0) payload['cloud_order_id'] = cId;
        }
      }
      final localDetailId = _int(payload['local_detail_id']);
      if (localDetailId > 0 &&
          (payload['cloud_detail_id'] == null ||
              _int(payload['cloud_detail_id']) <= 0)) {
        final lineRows = _database.select(
          'SELECT cloud_detail_id FROM local_order_lines WHERE id = ?',
          [localDetailId],
        );
        if (lineRows.isNotEmpty) {
          final cDetailId = _int(lineRows.first['cloud_detail_id']);
          if (cDetailId > 0) payload['cloud_detail_id'] = cDetailId;
        }
      }
    }
    return CashierCloudEvent(
      eventId: '${row['event_id']}',
      shopId: shopId,
      eventType: eventType,
      aggregateKey: '${row['aggregate_key']}',
      aggregateSequence: _int(row['aggregate_sequence']),
      payload: payload,
      createdAtMs: _int(row['created_at_ms']),
      attemptCount: _int(row['attempt_count']),
    );
  }

  bool _cloudEventReadyToSend(Row row) {
    final eventType = '${row['event_type']}';
    final payload = _jsonMap(row['payload_json']);
    final shopId = _int(row['shop_id']);

    if (eventType == cashierServeTicketPrintEventType) {
      final lines = payload['lines'];
      if (lines is! List || lines.isEmpty) return true;
      for (final raw in lines.whereType<Map>()) {
        final localDetailId = _int(raw['local_detail_id']);
        final mapping = _database.select(
          'SELECT l.cloud_detail_id FROM local_order_lines l '
          'JOIN local_orders o ON o.id = l.order_id '
          'WHERE l.id = ? AND o.shop_id = ?',
          [localDetailId, shopId],
        );
        if (mapping.isEmpty || _int(mapping.single['cloud_detail_id']) <= 0) {
          return false;
        }
      }
      return lines.whereType<Map>().length == lines.length;
    }

    if (eventType == 'dishes_added') {
      final localOrderId = _int(payload['local_order_id']);
      if (localOrderId > 0) {
        final orderRows = _database.select(
          'SELECT cloud_order_no FROM local_orders WHERE id = ?',
          [localOrderId],
        );
        if (orderRows.isNotEmpty) {
          final cNo = '${orderRows.first['cloud_order_no'] ?? ''}'.trim();
          if (cNo.isEmpty ||
              cNo.startsWith('L') ||
              cNo.startsWith('pending:')) {
            return false;
          }
        }
      }
      return true;
    }

    if (eventType == 'refund_item') {
      final localOrderId = _int(payload['local_order_id']);
      if (localOrderId > 0) {
        final orderRows = _database.select(
          'SELECT cloud_order_no FROM local_orders WHERE id = ?',
          [localOrderId],
        );
        if (orderRows.isNotEmpty) {
          final cNo = '${orderRows.first['cloud_order_no'] ?? ''}'.trim();
          if (cNo.isEmpty ||
              cNo.startsWith('L') ||
              cNo.startsWith('pending:')) {
            return false;
          }
        }
      }
      final localDetailId = _int(payload['local_detail_id']);
      if (localDetailId > 0) {
        final lineRows = _database.select(
          'SELECT cloud_detail_id FROM local_order_lines WHERE id = ?',
          [localDetailId],
        );
        if (lineRows.isEmpty || _int(lineRows.first['cloud_detail_id']) <= 0) {
          return false;
        }
      }
      return true;
    }

    return true;
  }

  String _orderRequestFingerprint(CashierOrderDraft draft) => jsonEncode(
    _canonicalJson({
      'shop_id': draft.shopId,
      'table_number': draft.tableNumber.trim(),
      'fulfillment_type': draft.fulfillmentType.trim(),
      'remark': draft.remark.trim(),
      'number_of_diners': draft.numberOfDiners,
      'lines': draft.lines.map((line) => line.toJson()).toList(),
    }),
  );

  CashierKdsDevice _mapDeviceRow(Map<String, Object?> row) {
    final workflows = jsonDecode('${row['workflows_json']}');
    final rawTags = row['screen_tags_json'] == null
        ? null
        : jsonDecode('${row['screen_tags_json']}');
    return CashierKdsDevice(
      shopId: _int(row['shop_id']),
      deviceCode: '${row['device_code']}',
      deviceName: '${row['device_name']}',
      screenTag: '${row['screen_tag']}',
      workflows: workflows is List
          ? workflows.map((value) => '$value').toList(growable: false)
          : const [],
      screenTags: rawTags is List
          ? rawTags
                .whereType<String>()
                .where(kIsGrillTag)
                .toList(growable: false)
          : const [],
      pairedAtMs: _int(row['paired_at_ms']),
      lastHeartbeatAtMs: _int(row['last_heartbeat_at_ms']),
      enabled: _int(row['enabled']) == 1,
    );
  }

  CashierKdsDevice? _readDeviceByTokenHash(String tokenHash) {
    final rows = _database.select(
      'SELECT * FROM kds_devices WHERE token_hash = ?',
      [tokenHash],
    );
    if (rows.isEmpty) return null;
    return _mapDeviceRow(rows.first);
  }

  CashierKdsDevice? readDeviceByCode(String deviceCode) {
    final rows = _database.select(
      'SELECT * FROM kds_devices WHERE device_code = ?',
      [deviceCode],
    );
    if (rows.isEmpty) return null;
    return _mapDeviceRow(rows.first);
  }

  void _ensureColumn(String table, String column, String definition) {
    final columns = _database.select('PRAGMA table_info($table)');
    if (columns.any((row) => '${row['name']}' == column)) return;
    _database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  void _resequenceOutboxOnce() {
    const migrationKey = 'cloud_outbox_aggregate_sequence_migrated_v1';
    final migrated = _database.select(
      'SELECT 1 FROM local_kds_meta WHERE meta_key = ? LIMIT 1',
      [migrationKey],
    );
    if (migrated.isNotEmpty) return;
    _safeBegin();
    try {
      _resequenceOutbox();
      _database.execute('DELETE FROM cloud_outbox_sequence_watermarks');
      _database.execute(
        'INSERT INTO cloud_outbox_sequence_watermarks '
        '(aggregate_key, high_water_sequence) '
        'SELECT aggregate_key, MAX(aggregate_sequence) FROM cloud_outbox '
        'GROUP BY aggregate_key',
      );
      _database.execute(
        'INSERT INTO local_kds_meta(meta_key, meta_value) VALUES (?, ?)',
        [migrationKey, '${DateTime.now().millisecondsSinceEpoch}'],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _safeRollback();
      rethrow;
    }
  }

  void _resequenceOutbox() {
    final rows = _database.select(
      'SELECT event_id, aggregate_key FROM cloud_outbox '
      'ORDER BY aggregate_key ASC, created_at_ms ASC, rowid ASC',
    );
    final sequences = <String, int>{};
    for (final row in rows) {
      final key = '${row['aggregate_key']}';
      final sequence = (sequences[key] ?? 0) + 1;
      sequences[key] = sequence;
      _database.execute(
        'UPDATE cloud_outbox SET aggregate_sequence = ? WHERE event_id = ?',
        [sequence, row['event_id']],
      );
    }
  }

  int _nextCloudAggregateSequence(String aggregateKey) {
    final watermark = _database.select(
      'SELECT high_water_sequence FROM cloud_outbox_sequence_watermarks '
      'WHERE aggregate_key = ?',
      [aggregateKey],
    );
    final eventMax = _database.select(
      'SELECT COALESCE(MAX(aggregate_sequence), 0) AS sequence '
      'FROM cloud_outbox WHERE aggregate_key = ?',
      [aggregateKey],
    );
    final current = [
      if (watermark.isNotEmpty) _int(watermark.single['high_water_sequence']),
      _int(eventMax.single['sequence']),
    ].reduce((left, right) => left > right ? left : right);
    final next = current + 1;
    _database.execute(
      'INSERT INTO cloud_outbox_sequence_watermarks '
      '(aggregate_key, high_water_sequence) VALUES (?, ?) '
      'ON CONFLICT(aggregate_key) DO UPDATE SET '
      'high_water_sequence = excluded.high_water_sequence',
      [aggregateKey, next],
    );
    return next;
  }

  void _migrateServePrintAggregates() {
    _database.execute(
      "UPDATE cloud_outbox SET aggregate_key = 'serve-print:' || aggregate_key "
      'WHERE event_type = ? '
      "AND aggregate_key NOT LIKE 'serve-print:%' "
      "AND state NOT IN ('delivered', 'discarded')",
      [cashierServeTicketPrintEventType],
    );
  }

  void _discardPrematureServePrintEventsOnce() {
    const migrationKey = 'serve_print_ready_serve_migrated_v1';
    final migrated = _database.select(
      'SELECT 1 FROM local_kds_meta WHERE meta_key = ? LIMIT 1',
      [migrationKey],
    );
    if (migrated.isNotEmpty) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _database.execute(
      "UPDATE cloud_outbox SET state = 'discarded', updated_at_ms = ?, "
      "last_error = 'discarded after correcting serve print trigger to ready_serve' "
      'WHERE event_type = ? '
      "AND state NOT IN ('delivered', 'discarded')",
      [nowMs, cashierServeTicketPrintEventType],
    );
    _database.execute(
      'INSERT INTO local_kds_meta(meta_key, meta_value) VALUES (?, ?)',
      [migrationKey, '$nowMs'],
    );
  }

  /// 测试辅助：清除指定订单所有行的云端明细映射，模拟“云端出生订单上
  /// 存在本地未映射行”（如本地加菜）的场景。
  void debugClearLineCloudMapping(int orderId) {
    _database.execute(
      'UPDATE local_order_lines SET cloud_detail_id = NULL WHERE order_id = ?',
      [orderId],
    );
  }

  CashierWorkflowLine _lineFromRow(Row row, {String? queueOverride}) {
    return CashierWorkflowLine(
      detailId: _int(row['id']),
      orderId: _int(row['order_id']),
      orderNo: '${row['order_no']}',
      tableNumber: '${row['table_number']}',
      fulfillmentType: '${row['fulfillment_type']}',
      orderRemark: '${row['remark']}',
      dishId: _int(row['dish_id']),
      dishName: '${row['dish_name']}',
      specification: '${row['specification']}',
      unit: '${row['unit']}',
      lineQuantity: _int(row['line_quantity']),
      prepRemaining: _int(row['prep_remaining']),
      cookRemaining: _int(row['cook_remaining']),
      readyRemaining: _int(row['ready_remaining']),
      refundedQuantity: _int(row['refunded_quantity']),
      held: _int(row['held']) == 1,
      rushed: _int(row['rushed']) == 1,
      lacked: _int(row['lacked']) == 1,
      workflowQueue: queueOverride ?? '${row['workflow_queue']}',
      localRevision: _int(row['local_revision']),
      orderRevision: _int(row['order_revision']),
      createdAtMs: _int(row['created_at_ms']),
      cloudDetailId: _int(row['cloud_detail_id']) > 0
          ? _int(row['cloud_detail_id'])
          : null,
      cloudOrderId: _int(row['cloud_order_id']) > 0
          ? _int(row['cloud_order_id'])
          : null,
      completedAtMs: row['completed_at_ms'] == null
          ? null
          : _int(row['completed_at_ms']),
      isCombo: _int(row['is_combo']) == 1,
      comboName: row['combo_name'] == null || '${row['combo_name']}'.isEmpty
          ? null
          : '${row['combo_name']}',
      comboId: row['combo_id'] == null ? null : _int(row['combo_id']),
      servingDurationMinutes: _int(row['serving_duration_minutes']) > 0
          ? _int(row['serving_duration_minutes'])
          : 10,
    );
  }

  static Map<String, Object?> _jsonMap(Object? raw) {
    final decoded = jsonDecode('$raw');
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
  }

  static Object? _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalJson(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalJson).toList(growable: false);
    }
    return value;
  }

  static int _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true' || value == '1') return true;
      if (value.toLowerCase() == 'false' || value == '0') return false;
    }
    return fallback;
  }
}
