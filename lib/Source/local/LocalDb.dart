// Đường dẫn: lib/Source/local/LocalDb.dart
//
// DATABASE PHỤ PHÍA APP (SQLite)
//  - Lưu bản sao JSON của các API ít thay đổi (danh sách phòng, dịch vụ, hóa đơn...) + ETag của server.
//  - Mở app: hiện ngay dữ liệu cũ từ máy, đồng thời hỏi server "có gì mới không?" (If-None-Match).
//    Server trả 304 -> dùng luôn bản trong máy, không tải/parse lại JSON.
//  - Mỗi dòng gắn owner (hash của user đang đăng nhập) -> đổi tài khoản không đọc nhầm dữ liệu người khác.
//  - Dòng nào quá [maxAge] chưa được server xác nhận lại sẽ bị xóa. Đăng xuất -> xóa sạch.
//  - KHÔNG lưu dữ liệu nhạy cảm (SĐT, email, CCCD, PIN, OTP, số dư...): xem SyncedApi.sensitiveKeys.
//
// Chỉ chạy trên Android/iOS/macOS (sqflite). Web/Windows/Linux: trả null -> app vẫn chạy, chỉ là không có cache đĩa.

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalRow {
  final String? etag;
  final String body;
  final DateTime savedAt;

  const LocalRow({required this.etag, required this.body, required this.savedAt});
}

class LocalDb {
  static const String _file = 'qlpt_local.db';
  static const String _table = 'api_cache';
  static const Duration maxAge = Duration(days: 30);

  static Future<Database?>? _db;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static Future<Database?> get _database => _db ??= _open();

  static Future<Database?> _open() async {
    if (!supported) return null;
    try {
      final db = await openDatabase(
        p.join(await getDatabasesPath(), _file),
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE $_table(
            cache_key TEXT NOT NULL,
            owner     TEXT NOT NULL,
            etag      TEXT,
            body      TEXT NOT NULL,
            saved_at  INTEGER NOT NULL,
            PRIMARY KEY (cache_key, owner)
          )'''),
      );
      // Dọn dữ liệu quá hạn mỗi lần mở app
      final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      final n = await db.delete(_table, where: 'saved_at < ?', whereArgs: [cutoff]);
      if (n > 0) debugPrint('[LocalDb] Đã xóa $n bản ghi quá ${maxAge.inDays} ngày');
      return db;
    } catch (e) {
      debugPrint('[LocalDb] Không mở được database, chạy không cache: $e');
      return null;
    }
  }

  static Future<LocalRow?> get(String key, String owner) async {
    final db = await _database;
    if (db == null) return null;
    final rows = await db.query(_table,
        columns: ['etag', 'body', 'saved_at'], where: 'cache_key = ? AND owner = ?', whereArgs: [key, owner], limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(r['saved_at'] as int);
    if (DateTime.now().difference(savedAt) > maxAge) return null;
    return LocalRow(etag: r['etag'] as String?, body: r['body'] as String, savedAt: savedAt);
  }

  static Future<void> put(String key, String owner, {required String? etag, required String body}) async {
    final db = await _database;
    if (db == null) return;
    await db.insert(
      _table,
      {'cache_key': key, 'owner': owner, 'etag': etag, 'body': body, 'saved_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Server xác nhận dữ liệu vẫn đúng (304) -> gia hạn.
  static Future<void> touch(String key, String owner) async {
    final db = await _database;
    if (db == null) return;
    await db.update(_table, {'saved_at': DateTime.now().millisecondsSinceEpoch},
        where: 'cache_key = ? AND owner = ?', whereArgs: [key, owner]);
  }

  static Future<void> clear() async {
    final db = await _database;
    if (db == null) return;
    await db.delete(_table);
  }
}
