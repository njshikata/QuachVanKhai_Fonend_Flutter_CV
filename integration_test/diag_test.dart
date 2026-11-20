// Chẩn đoán: bước nào trong đường tải dữ liệu "tối ưu" bị treo (SQLite / compute isolate / mạng).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qlpt_frontend/Source/api/JsonIsolate.dart';
import 'package:qlpt_frontend/Source/api/Login/LoginAPI.dart';
import 'package:qlpt_frontend/Source/api/SyncedApi.dart';
import 'package:qlpt_frontend/Source/local/LocalDb.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';

const _email = String.fromEnvironment('TEST_EMAIL');
const _pass = String.fromEnvironment('TEST_PASS');

dynamic _dec(Uint8List b) => jsonDecode(utf8.decode(b));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> step(String name, Future<Object?> Function() f) async {
    final sw = Stopwatch()..start();
    try {
      final r = await f().timeout(const Duration(seconds: 25));
      final s = r.toString();
      debugPrint('[DIAG] OK   $name ${sw.elapsedMilliseconds}ms -> ${s.length > 80 ? s.substring(0, 80) : s}');
    } catch (e) {
      debugPrint('[DIAG] FAIL $name ${sw.elapsedMilliseconds}ms -> $e');
    }
  }

  testWidgets('diag', (tester) async {
    await tester.runAsync(() async {
      await PerfFlags.load();
      await PerfFlags.setAllOptimizations(true);
      await step('login', () => LoginAPI.login(_email, _pass));
      await step('LocalDb.get', () => LocalDb.get('/x', 'o'));
      await step('LocalDb.clear', () => LocalDb.clear());
      await step('compute small', () => compute(_dec, Uint8List.fromList(utf8.encode('[1,2,3]'))));
      await step('JsonIsolate 100KB', () => JsonIsolate.decode(Uint8List.fromList(utf8.encode(jsonEncode(List.generate(5000, (i) => {'id': i, 'n': 'phong $i'})))))
          .then((v) => (v as List).length));
      final h = Map<String, String>.from(await ApiTotal.getAuthHeaders() as Map)..remove('Content-Type');
      await step('authHeaders', () async => h.keys.toList());
      late http.Response res;
      await step('http.get', () async {
        res = await http.get(Uri.parse('${ApiTotal.baseUrl}/api/landlord/properties/dashboard'), headers: h).timeout(const Duration(seconds: 15));
        return '${res.statusCode} ${res.bodyBytes.length}B etag=${res.headers['etag']}';
      });
      await step('JsonIsolate.decode 163KB', () => JsonIsolate.decode(res.bodyBytes).then((v) => (v as List).length));
      await step('compute decode 163KB', () => compute(_dec, res.bodyBytes).then((v) => (v as List).length));
      await step('main decode 163KB', () async => (_dec(res.bodyBytes) as List).length);
      await step('SyncedApi dashboard', () => SyncedApi.getJson('/api/landlord/properties/dashboard').then((v) => (v as List).length));
      await step('SyncedApi dashboard (304)', () => SyncedApi.getJson('/api/landlord/properties/dashboard').then((v) => (v as List).length));
    });
    // Không runAsync: giống bài đo hiệu năng (tester.pump trong vòng chờ)
    var done = false;
    Object? res;
    SyncedApi.clear().then((_) => SyncedApi.getJson('/api/landlord/properties/dashboard')).then((v) {
      res = (v as List).length;
      done = true;
    }, onError: (e) {
      res = e;
      done = true;
    });
    final sw = Stopwatch()..start();
    while (!done && sw.elapsed.inSeconds < 40) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    debugPrint('[DIAG] ${done ? "OK  " : "TREO"} getJson trong vòng pump ${sw.elapsedMilliseconds}ms -> $res');
  });
}
