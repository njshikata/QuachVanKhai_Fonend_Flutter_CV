// Test thẻ thông minh phía Flutter: DTO, lỗi HTTP, dialog OTP/PIN, luồng nạp tiền bằng OTP (chủ trọ),
// màn "Thẻ của tôi" hiện mã OTP + "Không phải tôi" (người thuê). HTTP giả bằng MockClient – không cần server.
//
// Chạy: flutter test test/smart_card_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardAPI.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/User/Card/MyCardScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/CardDialogs.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/SmartCardDetailScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _cardJson({int balance = 1000, String status = 'ACTIVE'}) => {
      'id': 7,
      'cardUid': 'ABCDEF0123456789',
      'holderName': 'Nguyễn Văn A',
      'tenantId': 3,
      'roomId': 2,
      'roomNumber': '101',
      'propertyName': 'Nhà A',
      'status': status,
      'expiryDate': '2030-01-01',
      'expired': false,
      'photoVersion': 1,
      'photoAvailable': false,
      'photoUrl': null,
      'infoVersion': 1,
      'lastKnownBalance': balance,
    };

const _emptyPage = {'items': [], 'page': 0, 'hasNext': false};

/// Bọc màn hình trong MaterialApp + 1 khung điện thoại đủ cao.
Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: w)));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'jwt_token': 'test'}));

  // ======================================================================== DTO
  group('DTO', () {
    test('WalletOtpTicket parse + mặc định', () {
      final t = WalletOtpTicket.fromJson({'requestId': 'r1', 'type': 'DEBIT', 'amount': 500, 'pushSent': true});
      expect(t.requestId, 'r1');
      expect(t.isDebit, isTrue);
      expect(t.amount, 500);
      expect(t.expiresInSeconds, 300); // thiếu -> 5 phút
      expect(t.pushSent, isTrue);
    });

    test('PendingOtp parse, số dạng chuỗi vẫn đọc được', () {
      final o = PendingOtp.fromJson(
          {'requestId': 'r2', 'type': 'CREDIT', 'amount': '1200', 'code': '482915', 'secondsLeft': 250, 'source': 'APP'});
      expect(o.isCredit, isTrue);
      expect(o.typeLabel, 'Nạp tiền');
      expect(o.amount, 1200);
      expect(o.code, '482915');
      expect(o.secondsLeft, 250);
    });

    test('SwipeResult có số lần thử PIN còn lại', () {
      final s = SwipeResult.fromJson({'granted': false, 'message': 'Sai PIN', 'pinTriesRemaining': 3});
      expect(s.granted, isFalse);
      expect(s.pinTriesRemaining, 3);
      expect(SwipeResult.fromJson({'granted': true}).pinTriesRemaining, isNull);
    });

    test('WalletResult đủ trường', () {
      final w = WalletResult.fromJson({'balance': 900, 'amount': 100, 'macValid': true, 'type': 'DEBIT', 'transactionId': 5});
      expect([w.balance, w.amount, w.macValid, w.type, w.transactionId], [900, 100, true, 'DEBIT', 5]);
    });
  });

  // ======================================================================== CardHttp
  group('CardHttp.handle', () {
    Uint8List b(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));

    test('2xx trả dữ liệu', () async {
      expect(await CardHttp.handle(200, b({'a': 1})), {'a': 1});
      expect(await CardHttp.handle(204, Uint8List(0)), isNull);
    });

    test('4xx -> CardApiException kèm pinTriesRemaining', () async {
      await expectLater(
        CardHttp.handle(403, b({'message': 'Sai PIN', 'pinTriesRemaining': 2})),
        throwsA(isA<CardApiException>()
            .having((e) => e.statusCode, 'status', 403)
            .having((e) => e.pinTriesRemaining, 'tries', 2)
            .having((e) => e.toString(), 'text', contains('Còn 2 lần'))),
      );
    });

    test('lỗi dạng text (không phải JSON)', () async {
      await expectLater(CardHttp.handle(429, Uint8List.fromList(utf8.encode('Quá nhiều yêu cầu'))),
          throwsA(isA<CardApiException>().having((e) => e.message, 'msg', 'Quá nhiều yêu cầu')));
    });
  });

  // ======================================================================== helpers
  group('CardDialogs.money / walletErrorRetryable', () {
    test('định dạng tiền', () {
      expect(CardDialogs.money(0), '0');
      expect(CardDialogs.money(999), '999');
      expect(CardDialogs.money(1000), '1.000');
      expect(CardDialogs.money(30000), '30.000');
      expect(CardDialogs.money(1234567), '1.234.567');
      expect(CardDialogs.money(-2500), '-2.500');
      expect(CardDialogs.money(null), '—');
    });

    test('lỗi nhập lại được với cùng mã', () {
      expect(walletErrorRetryable(CardApiException(400, 'Sai mã xác nhận (còn 4 lần)')), isTrue);
      expect(walletErrorRetryable(CardApiException(403, 'Sai PIN', pinTriesRemaining: 2)), isTrue);
    });

    test('lỗi phải làm lại từ đầu', () {
      expect(walletErrorRetryable(CardApiException(400, 'Mã xác nhận đã hết hạn, hãy yêu cầu mã mới')), isFalse);
      expect(walletErrorRetryable(CardApiException(400, 'Sai mã xác nhận quá 5 lần, yêu cầu đã bị hủy')), isFalse);
      expect(walletErrorRetryable(CardApiException(403, 'PIN bị khóa', pinTriesRemaining: 0)), isFalse);
      expect(walletErrorRetryable(CardApiException(503, 'Card Bridge offline')), isFalse);
      expect(walletErrorRetryable(Exception('x')), isFalse);
    });
  });

  // ======================================================================== dialogs
  group('Dialog', () {
    testWidgets('askAmount: chặn 0 và > 30000, nhận 1500', (t) async {
      ({int amount, String? note})? r;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => r = await CardDialogs.askAmount(ctx, title: 'Nạp'),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, '0');
      await t.tap(find.text('Gửi mã OTP'));
      await t.pump();
      expect(find.text('Số tiền từ 1 đến 30.000'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '99999');
      await t.tap(find.text('Gửi mã OTP'));
      await t.pump();
      expect(find.text('Số tiền từ 1 đến 30.000'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '1500');
      await t.enterText(find.byType(TextField).last, '  tiền điện ');
      await t.tap(find.text('Gửi mã OTP'));
      await t.pumpAndSettle();
      expect(r?.amount, 1500);
      expect(r?.note, 'tiền điện');
    });

    testWidgets('askOtp: OTP phải 6 số, thanh toán bắt buộc PIN', (t) async {
      ({String otp, String? pin})? r;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async =>
                  r = await CardDialogs.askOtp(ctx, title: 'TT', message: 'm', expiresInSeconds: 120, needPin: true),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pump();
      expect(find.text('Hết hạn sau 2:00'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '123');
      await t.tap(find.text('Xác nhận'));
      await t.pump();
      expect(find.text('Mã OTP gồm 6 chữ số'), findsOneWidget);
      expect(find.text('PIN gồm 4 - 8 chữ số'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, '12a34x56'); // ký tự lạ bị lọc
      await t.enterText(find.byType(TextField).last, '2703');
      await t.tap(find.text('Xác nhận'));
      await t.pump();
      expect(r, isNotNull);
      expect(r!.otp, '123456');
      expect(r!.pin, '2703');
      await t.pumpAndSettle();
    });

    testWidgets('askOtp: hết giờ thì khóa nút Xác nhận', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () => CardDialogs.askOtp(ctx, title: 'Nạp', message: 'm', expiresInSeconds: 2),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pump();
      // Đếm ngược theo đồng hồ thật (đúng cả khi app bị treo/ẩn) -> chờ thời gian thật rồi cho Timer chạy
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2300)));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Mã đã hết hạn – đóng và gửi lại'), findsOneWidget);
      final btn = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Xác nhận'));
      expect(btn.onPressed, isNull);
      await t.tap(find.text('Hủy'));
      await t.pumpAndSettle();
    });

  });

  // ======================================================================== CHỦ TRỌ: nạp tiền bằng OTP
  group('SmartCardDetailScreen', () {
    testWidgets('nạp tiền: gửi OTP -> sai mã -> nhập lại CÙNG requestId -> thành công', (t) async {
      final calls = <String>[];
      var creditCalls = 0;
      final mock = MockClient((req) async {
        final path = req.url.path;
        calls.add('${req.method} $path');
        if (path == '/api/landlady/cards/7') return _json({'card': _cardJson(), 'tenantEmail': 'a@x.vn'});
        if (path.endsWith('/logs') || path.endsWith('/transactions')) return _json(_emptyPage);
        if (path.endsWith('/wallet/otp')) {
          final b = jsonDecode(req.body);
          expect(b, {'type': 'CREDIT', 'amount': 2000});
          return _json({'requestId': 'REQ-1', 'type': 'CREDIT', 'amount': 2000, 'expiresInSeconds': 300, 'pushSent': true});
        }
        if (path.endsWith('/credit')) {
          creditCalls++;
          final b = jsonDecode(req.body);
          expect(b['requestId'], 'REQ-1');
          expect(b['amount'], 2000);
          if (creditCalls == 1) {
            expect(b['otp'], '111111');
            return _json({'message': 'Sai mã xác nhận (còn 4 lần)'}, 400);
          }
          expect(b['otp'], '482915');
          return _json({'balance': 3000, 'amount': 2000, 'macValid': true, 'type': 'CREDIT'});
        }
        return _json({'message': 'unexpected $path'}, 404);
      });

      await http.runWithClient(() async {
        final item = ValueNotifier(SmartCardItem.fromJson(_cardJson()));
        await _pump(t, SmartCardDetailScreen(item: item));
        await t.pumpAndSettle();

        // Bố cục mới: thẻ lớn + các khối, không còn TabBar
        expect(find.byType(TabBar), findsNothing);
        expect(find.text('THẺ CƯ DÂN'), findsOneWidget);
        expect(find.text('Ra vào & tủ đồ'), findsOneWidget);

        await t.tap(find.text('Nạp tiền'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, '2000');
        await t.tap(find.text('Gửi mã OTP'));
        await t.pumpAndSettle();

        // Dialog OTP (nạp tiền không hỏi PIN)
        expect(find.textContaining('Mã 6 số đã gửi tới điện thoại'), findsOneWidget);
        expect(find.text('PIN của thẻ'), findsNothing);
        await t.enterText(find.byType(TextField).first, '111111');
        await t.tap(find.text('Xác nhận'));
        await t.pumpAndSettle();

        // Sai mã -> dialog mở lại, kèm cảnh báo, vẫn là REQ-1
        expect(find.textContaining('Sai mã xác nhận (còn 4 lần)'), findsOneWidget);
        await t.enterText(find.byType(TextField).first, '482915');
        await t.tap(find.text('Xác nhận'));
        await t.pumpAndSettle();

        expect(creditCalls, 2);
        expect(item.value.lastKnownBalance, 3000);
        expect(find.textContaining('Đã nạp 2.000'), findsOneWidget);
        expect(calls.where((c) => c.endsWith('/wallet/otp')).length, 1, reason: 'không gửi mã mới khi chỉ nhập sai');
      }, () => mock);
    });

    testWidgets('quẹt thẻ: hỏi PIN, gửi pin lên server, báo số lần còn lại', (t) async {
      Map<String, dynamic>? swipeBody;
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/landlady/cards/7') return _json({'card': _cardJson()});
        if (path.endsWith('/logs') || path.endsWith('/transactions')) return _json(_emptyPage);
        if (path.endsWith('/swipe')) {
          swipeBody = Map<String, dynamic>.from(jsonDecode(req.body));
          return _json({'granted': false, 'message': 'Sai PIN', 'pinTriesRemaining': 4});
        }
        return _json({}, 404);
      });
      await http.runWithClient(() async {
        await _pump(t, SmartCardDetailScreen(item: ValueNotifier(SmartCardItem.fromJson(_cardJson()))));
        await t.pumpAndSettle();
        await t.tap(find.text('Vào cổng'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), '1111');
        await t.tap(find.text('Xác nhận'));
        await t.pumpAndSettle();
        expect(swipeBody?['action'], 'DOOR_IN');
        expect(swipeBody?['pin'], '1111');
        expect(find.textContaining('còn 4 lần thử PIN'), findsOneWidget);
      }, () => mock);
    });

    testWidgets('thẻ đang khóa: nút ra vào / nạp / thanh toán bị vô hiệu', (t) async {
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/landlady/cards/7') return _json({'card': _cardJson(status: 'LOCKED')});
        return _json(_emptyPage);
      });
      await http.runWithClient(() async {
        await _pump(t, SmartCardDetailScreen(item: ValueNotifier(SmartCardItem.fromJson(_cardJson(status: 'LOCKED')))));
        await t.pumpAndSettle();
        expect(find.textContaining('Thẻ đang khóa'), findsOneWidget);
        await t.tap(find.text('Nạp tiền'));
        await t.pumpAndSettle();
        expect(find.text('Gửi mã OTP'), findsNothing); // không mở dialog
      }, () => mock);
    });
  });

  // ======================================================================== NGƯỜI THUÊ: mã OTP
  group('MyCardScreen', () {
    testWidgets('hiện mã OTP đang chờ, đếm ngược, "Không phải tôi" gọi DELETE', (t) async {
      var cancelled = false;
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/tenant/card') return _json({'card': _cardJson(balance: 5000)});
        if (path == '/api/tenant/card/otp') {
          return _json(cancelled
              ? []
              : [
                  {'requestId': 'R9', 'type': 'DEBIT', 'amount': 1500, 'code': '482915', 'secondsLeft': 120, 'source': 'TERMINAL'}
                ]);
        }
        if (req.method == 'DELETE' && path == '/api/tenant/card/otp/R9') {
          cancelled = true;
          return http.Response('', 204);
        }
        if (path.endsWith('/logs') || path.endsWith('/transactions')) return _json(_emptyPage);
        return _json({}, 404);
      });

      await http.runWithClient(() async {
        await _pump(t, const MyCardScreen(otpPollInterval: Duration(seconds: 5)));
        await t.pumpAndSettle();

        expect(find.byType(TabBar), findsNothing);
        expect(find.text('482 915'), findsOneWidget);
        expect(find.text('Mã xác nhận thanh toán'), findsOneWidget);
        expect(find.text('2:00'), findsOneWidget);
        expect(find.text('5.000'), findsOneWidget); // số dư trên hình thẻ

        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2200)));
        await t.pump(const Duration(seconds: 1));
        expect(find.textContaining(RegExp(r'^1:5[78]$')), findsOneWidget); // đếm ngược cục bộ

        await t.tap(find.text('Không phải tôi'));
        await t.pumpAndSettle();
        await t.tap(find.text('Đồng ý'));
        await t.pumpAndSettle();
        expect(cancelled, isTrue);
        expect(find.text('482 915'), findsNothing);

        await t.pumpWidget(const SizedBox()); // hủy timer
      }, () => mock);
    });

    testWidgets('chưa được cấp thẻ (204)', (t) async {
      final mock = MockClient((req) async =>
          req.url.path == '/api/tenant/card/otp' ? _json([]) : http.Response('', 204));
      await http.runWithClient(() async {
        await _pump(t, const MyCardScreen());
        await t.pumpAndSettle();
        expect(find.textContaining('chưa được cấp thẻ'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      }, () => mock);
    });
  });
}
