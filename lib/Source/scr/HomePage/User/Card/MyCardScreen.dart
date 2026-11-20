// Đường dẫn: lib/Source/scr/HomePage/User/Card/MyCardScreen.dart
//
// THẺ CỦA TÔI (người thuê) – 1 trang cuộn, không còn tab nhỏ:
//   [Mã xác nhận đang chờ (OTP nạp/thanh toán)] -> [Hình thẻ cư dân] -> [Đổi PIN]
//   -> [Giao dịch gần đây | Ra vào gần đây + "Xem tất cả"].
// Mã OTP được hỏi lại server mỗi 5 giây khi màn hình đang mở (phòng khi thông báo đẩy không tới);
// app vào nền thì ngừng hỏi để tiết kiệm pin.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qlpt_frontend/Source/api/User/Card/MyCardAPI.dart';
import 'package:qlpt_frontend/Source/api/User/Card/MyCardDTO.dart';
import 'package:qlpt_frontend/Source/cache/MediaCachePolicy.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/CardDialogs.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/ResidentCardView.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/SmartCardDetailScreen.dart'
    show CardLogTile, CardTransactionTile;

class MyCardScreen extends StatefulWidget {
  /// Chu kỳ hỏi mã OTP (test có thể đặt nhỏ hơn).
  final Duration otpPollInterval;

  const MyCardScreen({super.key, this.otpPollInterval = const Duration(seconds: 5)});

  @override
  State<MyCardScreen> createState() => _MyCardScreenState();
}

class _MyCardScreenState extends State<MyCardScreen> with WidgetsBindingObserver {
  late Future<SmartCardDetail?> _future = _load();
  int _historyToken = 0;

  // ---- OTP đang chờ ----
  List<PendingOtp> _otps = const [];
  DateTime _otpFetchedAt = DateTime.now();
  Timer? _pollTimer, _tickTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
      _tickTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollOtp();
    _pollTimer = Timer.periodic(widget.otpPollInterval, (_) => _pollOtp());
    _tickTimer?.cancel();
    // Đếm ngược cục bộ mỗi giây (không gọi mạng)
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _otps.isNotEmpty) setState(() {});
    });
  }

  Future<void> _pollOtp() async {
    if (_polling) return; // tránh chồng request khi mạng chậm
    _polling = true;
    try {
      final list = await MyCardAPI.pendingOtps();
      if (!mounted) return;
      final hadNew = list.any((o) => !_otps.any((x) => x.requestId == o.requestId));
      final finished = _otps.any((o) => !list.any((x) => x.requestId == o.requestId));
      setState(() {
        _otps = list;
        _otpFetchedAt = DateTime.now();
        if (finished) _historyToken++; // giao dịch vừa xong -> tải lại lịch sử
      });
      if (hadNew) HapticFeedback.mediumImpact();
    } catch (_) {
      // Lỗi mạng tạm thời: giữ danh sách cũ, lần sau hỏi lại
    } finally {
      _polling = false;
    }
  }

  int _secondsLeft(PendingOtp o) {
    final left = o.secondsLeft - DateTime.now().difference(_otpFetchedAt).inSeconds;
    return left < 0 ? 0 : left;
  }

  Future<void> _rejectOtp(PendingOtp o) async {
    final ok = await CardDialogs.confirm(context, 'Không phải bạn?',
        'Hủy yêu cầu ${o.typeLabel.toLowerCase()} ${CardDialogs.money(o.amount)}. Mã sẽ không dùng được nữa.');
    if (!ok || !mounted) return;
    try {
      await MyCardAPI.cancelOtp(o.requestId);
      if (!mounted) return;
      setState(() => _otps = _otps.where((x) => x.requestId != o.requestId).toList());
      CardDialogs.toast(context, 'Đã hủy yêu cầu');
    } catch (e) {
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
    }
  }

  Future<SmartCardDetail?> _load() async {
    final d = await MyCardAPI.myCard();
    if (d != null) {
      final c = d.card;
      await MediaCachePolicy.onRoomOwner(
        roomId: c.roomId,
        currentOwnerId: c.tenantId,
        previousOwnerId: c.previousOwnerId,
        ownerChangedAt: c.ownerChangedAt,
      );
    }
    return d;
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() {
      _future = f;
      _historyToken++;
    });
    unawaited(_pollOtp());
    try {
      await f;
    } catch (_) {
      // FutureBuilder hiện lỗi
    }
  }

  Future<void> _changePin() async {
    final oldPin = await CardDialogs.askPin(context, title: 'PIN hiện tại');
    if (oldPin == null || !mounted) return;
    final newPin = await CardDialogs.askPin(context, title: 'PIN mới (4 - 8 số)');
    if (newPin == null || !mounted) return;
    final again = await CardDialogs.askPin(context, title: 'Nhập lại PIN mới');
    if (again == null || !mounted) return;
    if (again != newPin) {
      CardDialogs.toast(context, 'Hai lần nhập PIN mới không khớp', error: true);
      return;
    }
    if (newPin == oldPin) {
      CardDialogs.toast(context, 'PIN mới phải khác PIN cũ', error: true);
      return;
    }
    try {
      await MyCardAPI.changePin(oldPin, newPin);
      if (mounted) CardDialogs.toast(context, 'Đổi PIN thành công');
    } catch (e) {
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3F6F4),
      child: FutureBuilder<SmartCardDetail?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text(snap.error.toString(), textAlign: TextAlign.center),
                  TextButton(onPressed: _refresh, child: const Text('Thử lại')),
                ]),
              ),
            );
          }
          final d = snap.data;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                for (final o in _otps) _OtpCard(otp: o, secondsLeft: _secondsLeft(o), onReject: () => _rejectOtp(o)),
                if (d == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Column(children: [
                      Icon(Icons.credit_card_off, size: 64, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Bạn chưa được cấp thẻ. Liên hệ chủ trọ.', textAlign: TextAlign.center),
                    ]),
                  )
                else
                  ..._cardContent(d),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _cardContent(SmartCardDetail d) {
    final c = d.card;
    return [
      ResidentCardView(
        card: c,
        dateOfBirth: d.dateOfBirth,
        photoCacheKey: 'my-card-photo:${c.id}:v${c.photoVersion}',
        photoGroup: 'my-card-photo:${c.id}',
      ),
      const SizedBox(height: 12),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Dùng lần cuối'),
            trailing: Text(CardDialogs.dateTime(c.lastSeenAt)),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline, color: Colors.blueGrey),
            title: Text('Ra vào cổng, tủ đồ: chỉ cần PIN thẻ.\nNạp tiền, thanh toán: cần thêm mã gửi về điện thoại này.',
                style: TextStyle(fontSize: 13)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.password, color: Colors.green),
            title: const Text('Đổi mã PIN'),
            subtitle: const Text('Cắm thẻ vào đầu đọc trước khi đổi'),
            trailing: const Icon(Icons.chevron_right),
            enabled: c.isActive,
            onTap: c.isActive ? _changePin : null,
          ),
        ]),
      ),
      const SizedBox(height: 12),
      RecentPreview<CardTransactionItem>(
        title: 'Giao dịch gần đây',
        icon: Icons.receipt_long,
        emptyText: 'Chưa có giao dịch',
        refreshToken: _historyToken,
        fetch: (p, s) => MyCardAPI.transactions(page: p, size: s),
        tileBuilder: (t) => CardTransactionTile(tx: t),
      ),
      RecentPreview<CardLogItem>(
        title: 'Ra vào gần đây',
        icon: Icons.history,
        emptyText: 'Chưa có lượt quẹt thẻ',
        refreshToken: _historyToken,
        fetch: (p, s) => MyCardAPI.logs(page: p, size: s),
        tileBuilder: (l) => CardLogTile(log: l),
      ),
    ];
  }
}

/// Thẻ hiển thị mã OTP đang chờ + đếm ngược + "Không phải tôi".
class _OtpCard extends StatelessWidget {
  final PendingOtp otp;
  final int secondsLeft;
  final VoidCallback onReject;

  const _OtpCard({required this.otp, required this.secondsLeft, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final color = otp.isCredit ? Colors.green : Colors.deepOrange;
    final mm = secondsLeft ~/ 60;
    final ss = (secondsLeft % 60).toString().padLeft(2, '0');
    final code = otp.code.length == 6 ? '${otp.code.substring(0, 3)} ${otp.code.substring(3)}' : otp.code;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.sms, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Mã xác nhận ${otp.typeLabel.toLowerCase()}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
            ),
            Text(secondsLeft > 0 ? '$mm:$ss' : 'Hết hạn',
                style: TextStyle(color: secondsLeft > 0 ? Colors.grey.shade700 : Colors.red)),
          ]),
          const SizedBox(height: 6),
          Text('${otp.typeLabel} ${CardDialogs.money(otp.amount)}'
              '${otp.roomNumber == null ? '' : ' • phòng ${otp.roomNumber}'}'
              '${otp.source == null ? '' : ' • tại ${otp.source}'}'),
          const SizedBox(height: 8),
          Center(
            child: SelectableText(code,
                key: const ValueKey('otp-code'),
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 6, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 4),
          const Text('Chỉ đọc mã này cho người đang thực hiện giao dịch với bạn. Không chia sẻ cho ai khác.',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReject,
              icon: const Icon(Icons.block, color: Colors.red),
              label: const Text('Không phải tôi', style: TextStyle(color: Colors.red)),
            ),
          ),
        ]),
      ),
    );
  }
}
