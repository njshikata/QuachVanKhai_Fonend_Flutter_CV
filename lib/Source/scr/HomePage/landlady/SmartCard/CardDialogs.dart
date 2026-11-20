// Đường dẫn: lib/Source/scr/HomePage/landlady/SmartCard/CardDialogs.dart
//
// Dialog dùng chung cho thao tác thẻ (nhập PIN, số tiền, mã OTP, thông báo kết quả).
// Mỗi dialog là StatefulWidget tự giữ TextEditingController và dispose trong State.dispose()
// (không dispose bằng whenComplete -> tránh lỗi "controller used after being disposed" khi dialog đang đóng).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CardDialogs {
  static String date(DateTime? d) =>
      d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String dateTime(DateTime? d) => d == null
      ? '—'
      : '${date(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// 12500 -> "12.500"
  static String money(int? v) {
    if (v == null) return '—';
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  static Color statusColor(String status) => switch (status) {
        'ACTIVE' => Colors.green,
        'LOCKED' => Colors.orange,
        _ => Colors.grey,
      };

  static String statusLabel(String status) => switch (status) {
        'ACTIVE' => 'Hoạt động',
        'LOCKED' => 'Đang khóa',
        'REVOKED' => 'Đã thu hồi',
        _ => status,
      };

  /// Nhập PIN 4-8 số. Trả null nếu hủy.
  static Future<String?> askPin(BuildContext context, {String title = 'Nhập mã PIN của thẻ', String? message}) =>
      showDialog<String>(context: context, builder: (_) => _PinDialog(title: title, message: message));

  /// Nhập số tiền (1 - 30.000 theo giới hạn ví trên chip) + ghi chú.
  static Future<({int amount, String? note})?> askAmount(BuildContext context, {required String title}) =>
      showDialog<({int amount, String? note})>(context: context, builder: (_) => _AmountDialog(title: title));

  /// Nhập mã OTP 6 số người thuê nhận trên điện thoại (+ PIN nếu thanh toán). Có đếm ngược hết hạn.
  static Future<({String otp, String? pin})?> askOtp(
    BuildContext context, {
    required String title,
    required String message,
    required int expiresInSeconds,
    bool needPin = false,
  }) =>
      showDialog<({String otp, String? pin})>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OtpDialog(title: title, message: message, expiresInSeconds: expiresInSeconds, needPin: needPin),
      );

  static Future<bool> confirm(BuildContext context, String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đồng ý')),
        ],
      ),
    );
    return ok == true;
  }

  static void toast(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ));
  }
}

/// Trường nhập số (PIN / OTP / tiền) dùng chung.
class _DigitsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLength;
  final bool obscure;
  final bool autofocus;
  final String? errorText;
  final VoidCallback? onSubmitted;

  const _DigitsField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.maxLength,
    this.obscure = false,
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        maxLength: maxLength,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), errorText: errorText, counterText: ''),
      );
}

class _PinDialog extends StatefulWidget {
  final String title;
  final String? message;

  const _PinDialog({required this.title, this.message});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.length < 4) {
      setState(() => _error = 'PIN gồm 4 - 8 chữ số');
      return;
    }
    Navigator.pop(context, _ctrl.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.message != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.message!)),
          _DigitsField(
            controller: _ctrl,
            label: 'Mã PIN (4 - 8 số)',
            icon: Icons.pin,
            maxLength: 8,
            obscure: true,
            autofocus: true,
            errorText: _error,
            onSubmitted: _submit,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: _submit, child: const Text('Xác nhận')),
        ],
      );
}

class _AmountDialog extends StatefulWidget {
  final String title;

  const _AmountDialog({required this.title});

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_amount.text) ?? 0;
    if (v < 1 || v > 30000) {
      setState(() => _error = 'Số tiền từ 1 đến 30.000');
      return;
    }
    final note = _note.text.trim();
    Navigator.pop(context, (amount: v, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _DigitsField(
              controller: _amount,
              label: 'Số tiền (1 - 30.000)',
              icon: Icons.payments,
              maxLength: 5,
              autofocus: true,
              errorText: _error,
            ),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Ghi chú (không bắt buộc)', prefixIcon: Icon(Icons.notes), counterText: ''),
            ),
            const SizedBox(height: 8),
            const Text('Bước tiếp theo: hệ thống gửi mã xác nhận tới điện thoại người thuê.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          FilledButton(onPressed: _submit, child: const Text('Gửi mã OTP')),
        ],
      );
}

class _OtpDialog extends StatefulWidget {
  final String title;
  final String message;
  final int expiresInSeconds;
  final bool needPin;

  const _OtpDialog({required this.title, required this.message, required this.expiresInSeconds, required this.needPin});

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _otp = TextEditingController();
  final _pin = TextEditingController();
  late final DateTime _expiresAt; // gán ngay trong initState (không để lazy -> mốc hết hạn không bị trễ)
  Timer? _timer;
  int _left = 0;
  String? _otpError, _pinError;

  @override
  void initState() {
    super.initState();
    _expiresAt = DateTime.now().add(Duration(seconds: widget.expiresInSeconds));
    _left = widget.expiresInSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = _expiresAt.difference(DateTime.now()).inSeconds;
      if (!mounted) return;
      setState(() => _left = left < 0 ? 0 : left);
      if (left <= 0) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otp.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    final otpOk = RegExp(r'^\d{6}$').hasMatch(_otp.text);
    final pinOk = !widget.needPin || _pin.text.length >= 4;
    setState(() {
      _otpError = otpOk ? null : 'Mã OTP gồm 6 chữ số';
      _pinError = pinOk ? null : 'PIN gồm 4 - 8 chữ số';
    });
    if (!otpOk || !pinOk) return;
    Navigator.pop(context, (otp: _otp.text, pin: widget.needPin ? _pin.text : null));
  }

  @override
  Widget build(BuildContext context) {
    final expired = _left <= 0;
    final mm = (_left ~/ 60).toString();
    final ss = (_left % 60).toString().padLeft(2, '0');
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.message),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.timer_outlined, size: 18, color: expired ? Colors.red : Colors.grey),
            const SizedBox(width: 4),
            Text(expired ? 'Mã đã hết hạn – đóng và gửi lại' : 'Hết hạn sau $mm:$ss',
                style: TextStyle(color: expired ? Colors.red : Colors.grey.shade700)),
          ]),
          _DigitsField(
            controller: _otp,
            label: 'Mã OTP (6 số)',
            icon: Icons.sms_outlined,
            maxLength: 6,
            autofocus: true,
            errorText: _otpError,
            onSubmitted: widget.needPin ? null : _submit,
          ),
          if (widget.needPin)
            _DigitsField(
              controller: _pin,
              label: 'PIN của thẻ',
              icon: Icons.pin,
              maxLength: 8,
              obscure: true,
              errorText: _pinError,
              onSubmitted: _submit,
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: expired ? null : _submit, child: const Text('Xác nhận')),
      ],
    );
  }
}
