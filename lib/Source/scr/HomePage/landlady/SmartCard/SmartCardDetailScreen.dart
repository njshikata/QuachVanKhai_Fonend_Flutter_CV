// Đường dẫn: lib/Source/scr/HomePage/landlady/SmartCard/SmartCardDetailScreen.dart
//
// CHI TIẾT THẺ (chủ trọ) – 1 trang cuộn, không còn tab nhỏ:
//   [Hình thẻ cư dân] -> [Ra vào / tủ đồ: chỉ cần PIN] -> [Ví: OTP gửi về điện thoại người thuê]
//   -> [Chip & PIN] -> [Thông tin] -> [Quẹt thẻ gần đây | Giao dịch gần đây + "Xem tất cả"].
// Nhận ValueNotifier của dòng trong danh sách -> cập nhật ở đây thì dòng ngoài danh sách tự đổi theo.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardAPI.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart';

import 'CardDialogs.dart';
import 'ResidentCardView.dart';

/// Lỗi OTP/PIN có thể nhập lại với CÙNG mã (sai mã, sai PIN còn lượt) – trả false nếu phải gửi mã mới.
bool walletErrorRetryable(Object e) {
  if (e is! CardApiException) return false;
  final m = e.message.toLowerCase();
  const fatal = ['hết hạn', 'bị hủy', 'không tồn tại', 'bị khóa', 'không khớp với giao dịch'];
  if (fatal.any(m.contains)) return false;
  if (e.pinTriesRemaining != null) return e.pinTriesRemaining! > 0;
  return e.statusCode == 400 && (m.contains('sai mã') || m.contains('pin'));
}

class SmartCardDetailScreen extends StatefulWidget {
  final ValueNotifier<SmartCardItem> item;

  const SmartCardDetailScreen({super.key, required this.item});

  @override
  State<SmartCardDetailScreen> createState() => _SmartCardDetailScreenState();
}

class _SmartCardDetailScreenState extends State<SmartCardDetailScreen> {
  SmartCardDetail? _detail;
  bool _busy = false;
  Object? _error;
  int _historyToken = 0; // tăng -> 2 khối "gần đây" tải lại

  int get _id => widget.item.value.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await SmartCardAPI.detail(_id);
      if (!mounted) return;
      widget.item.value = d.card;
      setState(() {
        _detail = d;
        _error = null;
        _historyToken++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Chạy 1 thao tác có lớp phủ chờ. [rethrowError] = true -> ném lỗi cho caller tự xử lý.
  Future<T?> _run<T>(Future<T> Function() action, {String? success, bool rethrowError = false}) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final r = await action();
      if (mounted && success != null) CardDialogs.toast(context, success);
      return r;
    } catch (e) {
      if (rethrowError) rethrow;
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ============================ RA VÀO / TỦ ĐỒ (PIN) ============================
  Future<void> _swipe(String action) async {
    final label = CardLogItem.actionLabels[action] ?? action;
    final pin = await CardDialogs.askPin(context, title: label, message: 'Người thuê nhập PIN của thẻ để xác nhận "$label".');
    if (pin == null || !mounted) return;
    final r = await _run(() => SmartCardAPI.swipe(_id, action, pin));
    if (r == null || !mounted) return;
    final tries = r.pinTriesRemaining;
    final suffix = !r.granted && tries != null ? ' (còn $tries lần thử PIN)' : '';
    CardDialogs.toast(context, '${r.granted ? '✔ Cho phép' : '✘ Từ chối'}: ${r.message}$suffix', error: !r.granted);
    setState(() => _historyToken++);
  }

  // ============================ VÍ (OTP) ============================
  Future<void> _wallet(bool credit) async {
    final title = credit ? 'Nạp tiền vào thẻ' : 'Thanh toán bằng thẻ';
    final input = await CardDialogs.askAmount(context, title: title);
    if (input == null || !mounted) return;

    // 1) Server gửi mã OTP tới điện thoại người thuê
    final ticket = await _run(() => SmartCardAPI.walletOtp(_id, credit ? 'CREDIT' : 'DEBIT', input.amount));
    if (ticket == null || !mounted) return;
    final expiresAt = DateTime.now().add(Duration(seconds: ticket.expiresInSeconds));

    // 2) Nhập OTP (+PIN khi thanh toán). Sai mã / sai PIN -> nhập lại với CÙNG mã cho tới khi hết hạn.
    String? lastError;
    while (mounted) {
      final left = expiresAt.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        CardDialogs.toast(context, 'Mã xác nhận đã hết hạn, hãy thực hiện lại', error: true);
        return;
      }
      final where = ticket.pushSent ? 'điện thoại' : 'app (mục Thẻ của tôi)';
      final msg = StringBuffer('${credit ? 'Nạp' : 'Thanh toán'} ${CardDialogs.money(ticket.amount)} – '
          '${ticket.holderName ?? 'người thuê'}${ticket.roomNumber == null ? '' : ' (phòng ${ticket.roomNumber})'}.\n'
          'Mã 6 số đã gửi tới $where của người thuê.');
      if (lastError != null) msg.write('\n\n⚠ $lastError');
      final code = await CardDialogs.askOtp(context,
          title: title, message: msg.toString(), expiresInSeconds: left, needPin: !credit);
      if (code == null || !mounted) return;

      try {
        final r = await _run(
          () => credit
              ? SmartCardAPI.credit(_id, ticket.amount, requestId: ticket.requestId, otp: code.otp, description: input.note)
              : SmartCardAPI.debit(_id, ticket.amount, code.pin!,
                  requestId: ticket.requestId, otp: code.otp, description: input.note),
          rethrowError: true,
        );
        if (r == null || !mounted) return;
        widget.item.value = widget.item.value.copyWith(lastKnownBalance: r.balance);
        setState(() => _historyToken++);
        CardDialogs.toast(
          context,
          '${credit ? 'Đã nạp' : 'Đã thanh toán'} ${CardDialogs.money(ticket.amount)} • Số dư ${CardDialogs.money(r.balance)}'
          '${r.macValid ? '' : ' – MAC KHÔNG hợp lệ!'}',
          error: !r.macValid,
        );
        return;
      } catch (e) {
        if (!mounted) return;
        if (!walletErrorRetryable(e)) {
          CardDialogs.toast(context, e.toString(), error: true);
          return;
        }
        lastError = e.toString();
      }
    }
  }

  // ============================ CHIP / PIN ============================
  Future<void> _readChip() async {
    final pin = await CardDialogs.askPin(context);
    if (pin == null || !mounted) return;
    final r = await _run(() => SmartCardAPI.readCard(_id, pin));
    if (r == null || !mounted) return;
    if (r.balance != null) widget.item.value = widget.item.value.copyWith(lastKnownBalance: r.balance);
    Uint8List? img;
    if (r.photoBase64 != null && r.photoBase64!.isNotEmpty) {
      try {
        img = base64Decode(r.photoBase64!);
      } catch (_) {
        img = null; // dữ liệu ảnh hỏng không làm sập dialog
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(r.matchesServer ? Icons.verified : Icons.warning_amber, color: r.matchesServer ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          const Expanded(child: Text('Dữ liệu trên chip')),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (img != null)
              Center(
                child: Image.memory(img, width: 96, height: 96, fit: BoxFit.cover,
                    cacheWidth: (96 * MediaQuery.devicePixelRatioOf(ctx)).round(), gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 48)),
              ),
            const SizedBox(height: 8),
            Text('Họ tên: ${r.holderName ?? '—'}'),
            Text('Ngày sinh: ${r.dateOfBirth ?? '—'}'),
            Text('Ngày đăng ký: ${r.issuedDate ?? '—'}'),
            Text('Hạn sử dụng: ${r.expiryDate ?? '—'}'),
            Text('Phòng: ${r.roomNumber ?? '—'}'),
            Text('Số dư: ${CardDialogs.money(r.balance)}'),
            if (r.pinTriesRemaining != null) Text('PIN còn: ${r.pinTriesRemaining} lần thử'),
            const SizedBox(height: 8),
            Text(r.matchesServer ? 'Khớp với dữ liệu server' : 'KHÔNG khớp với server – nên ghi lại thông tin',
                style: TextStyle(color: r.matchesServer ? Colors.green : Colors.orange, fontWeight: FontWeight.w600)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  Future<void> _pin(bool reset) async {
    final ok = await CardDialogs.confirm(context, reset ? 'Đặt lại PIN' : 'Mở khóa PIN',
        reset ? 'PIN sẽ về mặc định và số lần thử được đặt lại. Tiếp tục?' : 'Mở khóa PIN cho thẻ đang cắm ở đầu đọc?');
    if (!ok || !mounted) return;
    await _run(() => reset ? SmartCardAPI.resetPin(_id) : SmartCardAPI.unblockPin(_id),
        success: reset ? 'Đã đặt lại PIN' : 'Đã mở khóa PIN');
  }

  Future<void> _changePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (x == null || !mounted) return;
    final bytes = await x.readAsBytes();
    final d = await _run(() => SmartCardAPI.updatePhoto(_id, bytes), success: 'Đã cập nhật ảnh (server + chip)');
    if (d == null || !mounted) return;
    widget.item.value = d.card; // photoVersion tăng -> cacheKey mới
    setState(() => _detail = d);
  }

  Future<void> _editInfo() async {
    final d = _detail;
    if (d == null) return;
    final r = await showDialog<({String name, DateTime? dob, DateTime? exp})>(
      context: context,
      builder: (_) => _EditInfoDialog(name: d.card.holderName ?? '', dob: d.dateOfBirth, exp: d.card.expiryDate),
    );
    if (r == null || !mounted) return;
    final res = await _run(() => SmartCardAPI.updateInfo(_id, holderName: r.name, dateOfBirth: r.dob, expiryDate: r.exp),
        success: 'Đã cập nhật thông tin');
    if (res == null || !mounted) return;
    widget.item.value = res.card;
    setState(() => _detail = res);
  }

  Future<void> _setStatus(String status) async {
    if (status == 'REVOKED' &&
        !await CardDialogs.confirm(context, 'Thu hồi thẻ', 'Thẻ sẽ không dùng được nữa. Tiếp tục?')) {
      return;
    }
    final r = await _run(() => SmartCardAPI.setStatus(_id, status), success: 'Đã đổi trạng thái');
    if (r != null) widget.item.value = r;
  }

  // ============================ UI ============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F4),
      appBar: AppBar(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        title: ValueListenableBuilder<SmartCardItem>(
          valueListenable: widget.item,
          builder: (_, c, _) => Text(c.holderName ?? 'Thẻ #${c.id}'),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Trạng thái thẻ',
            onSelected: _setStatus,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'ACTIVE', child: Text('Kích hoạt')),
              PopupMenuItem(value: 'LOCKED', child: Text('Khóa thẻ')),
              PopupMenuItem(value: 'REVOKED', child: Text('Thu hồi thẻ')),
            ],
          ),
        ],
      ),
      body: Stack(children: [
        _body(),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator())),
          ),
      ]),
    );
  }

  Widget _body() {
    if (_error != null && _detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            Text(_error.toString(), textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Thử lại')),
          ]),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ValueListenableBuilder<SmartCardItem>(
        valueListenable: widget.item,
        builder: (context, c, _) {
          final usable = c.isActive && !c.expired; // khóa / thu hồi / hết hạn -> không quẹt, không giao dịch
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ResidentCardView(
                card: c,
                dateOfBirth: _detail?.dateOfBirth,
                photoCacheKey: c.photoCacheKey,
                photoGroup: c.photoGroup,
                onChangePhoto: c.isRevoked ? null : _changePhoto,
              ),
              if (!usable)
                _notice(c.isRevoked
                    ? 'Thẻ đã thu hồi – chỉ xem lịch sử.'
                    : c.expired
                        ? 'Thẻ đã hết hạn – sửa "Hạn sử dụng" để dùng tiếp.'
                        : 'Thẻ đang khóa – mở khóa ở menu ⋮ để dùng.'),
              const SizedBox(height: 16),
              _section('Ra vào & tủ đồ', 'Chỉ cần PIN của thẻ – dùng được cả khi người thuê không mang điện thoại', [
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.15,
                  children: [
                    for (final e in CardLogItem.actionLabels.entries)
                      CardActionButton(
                        icon: _actionIcon(e.key),
                        label: e.value,
                        color: Colors.indigo,
                        onTap: usable ? () => _swipe(e.key) : null,
                      ),
                  ],
                ),
              ]),
              _section('Ví trên thẻ', 'Mỗi giao dịch cần mã OTP gửi về điện thoại người thuê', [
                Row(children: [
                  Expanded(
                    child: CardActionButton(
                      icon: Icons.add_card,
                      label: 'Nạp tiền',
                      color: Colors.green,
                      onTap: usable ? () => _wallet(true) : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CardActionButton(
                      icon: Icons.point_of_sale,
                      label: 'Thanh toán',
                      color: Colors.deepOrange,
                      onTap: usable ? () => _wallet(false) : null,
                    ),
                  ),
                ]),
              ]),
              _section('Chip & PIN', 'Thẻ phải đang cắm ở đầu đọc', [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _btn(Icons.memory, 'Đọc chip', c.isRevoked ? null : _readChip),
                  _btn(Icons.lock_open, 'Mở khóa PIN', c.isRevoked ? null : () => _pin(false)),
                  _btn(Icons.restart_alt, 'Đặt lại PIN', c.isRevoked ? null : () => _pin(true)),
                ]),
              ]),
              _section('Thông tin', null, [
                _row('Email', _detail?.tenantEmail),
                _row('Ngày sinh', CardDialogs.date(_detail?.dateOfBirth)),
                _row('Phòng', '${c.roomNumber ?? '—'} • ${c.propertyName ?? ''}'),
                _row('Ngày cấp', CardDialogs.date(_detail?.issuedDate)),
                _row('Hạn sử dụng', '${CardDialogs.date(c.expiryDate)}${c.expired ? ' (hết hạn)' : ''}'),
                _row('Lần dùng cuối', CardDialogs.dateTime(c.lastSeenAt)),
                _row('Card UID', c.cardUid),
                _row('Phiên bản', 'info v${c.infoVersion} • ảnh v${c.photoVersion}'),
                if (!c.photoAvailable && _detail?.photoPurgedAt != null) _row('Ảnh', 'Đã hết hạn lưu trữ trên server'),
              ], trailing: IconButton(icon: const Icon(Icons.edit), onPressed: c.isRevoked ? null : _editInfo)),
              RecentPreview<CardTransactionItem>(
                title: 'Giao dịch gần đây',
                icon: Icons.receipt_long,
                emptyText: 'Chưa có giao dịch',
                refreshToken: _historyToken,
                fetch: (p, s) => SmartCardAPI.transactions(_id, page: p, size: s),
                tileBuilder: (t) => CardTransactionTile(tx: t),
              ),
              RecentPreview<CardLogItem>(
                title: 'Quẹt thẻ gần đây',
                icon: Icons.history,
                emptyText: 'Chưa có lượt quẹt thẻ',
                refreshToken: _historyToken,
                fetch: (p, s) => SmartCardAPI.logs(_id, page: p, size: s),
                tileBuilder: (l) => CardLogTile(log: l),
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _actionIcon(String action) => switch (action) {
        'DOOR_IN' => Icons.login,
        'DOOR_OUT' => Icons.logout,
        'LOCKER_OPEN' => Icons.markunread_mailbox,
        'ITEM_BORROW' => Icons.handshake,
        'ITEM_RETURN' => Icons.assignment_return,
        _ => Icons.touch_app,
      };

  Widget _notice(String text) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _btn(IconData icon, String label, VoidCallback? onTap) =>
      OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 18), label: Text(label));

  Widget _section(String title, String? subtitle, List<Widget> children, {Widget? trailing}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
              ),
              if (trailing != null) trailing,
            ]),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  Widget _row(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(v == null || v.isEmpty ? '—' : v)),
        ]),
      );
}

/// Dialog sửa thông tin – tự quản lý controller (dispose trong State.dispose).
class _EditInfoDialog extends StatefulWidget {
  final String name;
  final DateTime? dob, exp;

  const _EditInfoDialog({required this.name, this.dob, this.exp});

  @override
  State<_EditInfoDialog> createState() => _EditInfoDialogState();
}

class _EditInfoDialogState extends State<_EditInfoDialog> {
  late final _name = TextEditingController(text: widget.name);
  late DateTime? _dob = widget.dob;
  late DateTime? _exp = widget.exp;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Sửa thông tin thẻ'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              maxLength: 64,
              decoration: InputDecoration(labelText: 'Họ tên', errorText: _error, counterText: ''),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ngày sinh'),
              subtitle: Text(CardDialogs.date(_dob)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final p = await showDatePicker(
                    context: context, initialDate: _dob ?? DateTime(2000), firstDate: DateTime(1900), lastDate: DateTime.now());
                if (p != null && mounted) setState(() => _dob = p);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hạn sử dụng'),
              subtitle: Text(CardDialogs.date(_exp)),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final p = await showDatePicker(
                    context: context, initialDate: _exp ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (p != null && mounted) setState(() => _exp = p);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final n = _name.text.trim();
              if (n.isEmpty) {
                setState(() => _error = 'Nhập họ tên');
                return;
              }
              Navigator.pop(context, (name: n, dob: _dob, exp: _exp));
            },
            child: const Text('Lưu & ghi chip'),
          ),
        ],
      );
}

/// Dòng nhật ký quẹt thẻ (dùng chung chủ trọ + người thuê).
class CardLogTile extends StatelessWidget {
  final CardLogItem log;

  const CardLogTile({super.key, required this.log});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(log.granted ? Icons.check_circle : Icons.cancel, color: log.granted ? Colors.green : Colors.redAccent),
        title: Text(log.actionLabel),
        subtitle: Text([
          CardDialogs.dateTime(log.createdAt),
          if (log.deviceId != null) log.deviceId!,
          if (!log.granted && log.reason != null) log.reason!,
          if (log.note != null) log.note!,
        ].join(' • ')),
      );
}

/// Dòng giao dịch ví (dùng chung chủ trọ + người thuê).
class CardTransactionTile extends StatelessWidget {
  final CardTransactionItem tx;

  const CardTransactionTile({super.key, required this.tx});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(tx.isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: tx.isCredit ? Colors.green : Colors.orange),
        title: Text('${tx.isCredit ? '+' : '-'}${CardDialogs.money(tx.amount)}  •  Số dư ${CardDialogs.money(tx.balanceAfter)}'),
        subtitle: Text('${CardDialogs.dateTime(tx.createdAt)}${tx.description == null ? '' : ' • ${tx.description}'}'),
        trailing: Icon(tx.macValid ? Icons.verified_user : Icons.gpp_bad, size: 18, color: tx.macValid ? Colors.green : Colors.red),
      );
}
