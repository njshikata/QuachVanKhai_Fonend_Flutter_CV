// Đường dẫn: lib/Source/scr/HomePage/landlady/SmartCard/IssueCardScreen.dart
//
// CẤP THẺ MỚI: chọn phòng đang có người thuê -> chọn ảnh -> server ghi thông tin + ảnh (AES) vào chip,
// lưu public key RSA của thẻ. Nếu phòng đã có thẻ của NGƯỜI KHÁC -> thẻ cũ bị thu hồi, server đánh dấu đổi chủ
// (app sẽ xóa ảnh của chủ cũ khỏi máy sau 30 ngày).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qlpt_frontend/Source/api/Property/PropertyAPI.dart';
import 'package:qlpt_frontend/Source/api/Property/PropertyDTO.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardAPI.dart';

import 'CardDialogs.dart';

class IssueCardScreen extends StatefulWidget {
  const IssueCardScreen({super.key});

  @override
  State<IssueCardScreen> createState() => _IssueCardScreenState();
}

class _IssueCardScreenState extends State<IssueCardScreen> {
  late final Future<List<({LandlordPropertyDTO property, LandlordRoomDTO room})>> _rooms = _loadRooms();
  final _nameCtrl = TextEditingController();
  LandlordRoomDTO? _room;
  DateTime? _dob;
  DateTime _expiry = DateTime(DateTime.now().year + 1, DateTime.now().month, DateTime.now().day);
  Uint8List? _photo;
  Map<String, dynamic>? _reader;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _inspect();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<List<({LandlordPropertyDTO property, LandlordRoomDTO room})>> _loadRooms() async {
    final props = await PropertyAPI.getDashboardData();
    return [
      for (final p in props)
        for (final r in p.rooms)
          if (r.currentTenant != null) (property: p, room: r),
    ];
  }

  Future<void> _inspect() async {
    try {
      final r = await SmartCardAPI.inspectReader();
      if (mounted) setState(() => _reader = r);
    } catch (e) {
      if (mounted) setState(() => _reader = {'error': e.toString()});
    }
  }

  Future<void> _newBlank() async {
    setState(() => _busy = true);
    try {
      await SmartCardAPI.newBlankCard();
      await _inspect();
      if (mounted) CardDialogs.toast(context, 'Đã tạo & cắm thẻ trắng (giả lập)');
    } catch (e) {
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    // Thu nhỏ ngay khi chọn: ảnh 12MP (~4MB) -> ≤800px (~80KB) => upload nhanh, RAM thấp
    final x = await ImagePicker().pickImage(source: source, maxWidth: 800, maxHeight: 800, imageQuality: 80);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _submit() async {
    if (_room == null || _photo == null) {
      CardDialogs.toast(context, 'Hãy chọn phòng và ảnh chân dung', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await SmartCardAPI.issue(
        roomId: _room!.id,
        photoBytes: _photo!,
        holderName: _nameCtrl.text,
        dateOfBirth: _dob,
        expiryDate: _expiry,
      );
      if (!mounted) return;
      CardDialogs.toast(context, 'Cấp thẻ thành công');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.green, foregroundColor: Colors.white, title: const Text('Cấp thẻ thông minh')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _readerCard(),
            const SizedBox(height: 12),
            FutureBuilder(
              future: _rooms,
              builder: (context, snap) {
                if (snap.hasError) return Text('Lỗi tải phòng: ${snap.error}', style: const TextStyle(color: Colors.red));
                if (!snap.hasData) return const LinearProgressIndicator();
                final rooms = snap.data!;
                if (rooms.isEmpty) return const Text('Không có phòng nào đang có người thuê.');
                return DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _room?.id,
                  decoration: const InputDecoration(labelText: 'Phòng / người thuê', border: OutlineInputBorder()),
                  items: [
                    for (final e in rooms)
                      DropdownMenuItem(
                        value: e.room.id,
                        child: Text('${e.property.name} • P.${e.room.roomNumber} • ${e.room.currentTenant!.fullName}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    final r = rooms.firstWhere((e) => e.room.id == id).room;
                    setState(() {
                      _room = r;
                      _nameCtrl.text = r.currentTenant!.fullName;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Họ tên in trên thẻ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('Ngày sinh'),
              subtitle: Text(CardDialogs.date(_dob)),
              trailing: const Icon(Icons.cake),
              onTap: () async {
                final p = await showDatePicker(context: context, initialDate: _dob ?? DateTime(2000), firstDate: DateTime(1900), lastDate: DateTime.now());
                if (p != null) setState(() => _dob = p);
              },
            ),
            ListTile(
              title: const Text('Hạn sử dụng'),
              subtitle: Text(CardDialogs.date(_expiry)),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final p = await showDatePicker(context: context, initialDate: _expiry, firstDate: DateTime.now(), lastDate: DateTime(2100));
                if (p != null) setState(() => _expiry = p);
              },
            ),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? const Icon(Icons.person, size: 48, color: Colors.grey)
                    : Image.memory(_photo!, fit: BoxFit.cover, cacheWidth: (96 * MediaQuery.devicePixelRatioOf(context)).round()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  OutlinedButton.icon(onPressed: () => _pickPhoto(ImageSource.gallery), icon: const Icon(Icons.photo), label: const Text('Chọn ảnh')),
                  OutlinedButton.icon(onPressed: () => _pickPhoto(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Chụp ảnh')),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size.fromHeight(48)),
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: const Text('Ghi thẻ & lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readerCard() {
    final r = _reader;
    String text;
    Color color = Colors.blueGrey;
    if (r == null) {
      text = 'Đang kiểm tra đầu đọc...';
    } else if (r['error'] != null) {
      text = r['error'].toString();
      color = Colors.red;
    } else if (r['registered'] == true) {
      text = 'Thẻ ${r['cardUid']} ĐÃ được cấp (phòng ${r['roomNumber'] ?? '—'}, ${r['status']}).\n'
          'Cấp lại sẽ ghi đè thông tin trên thẻ này.';
      color = Colors.orange;
    } else {
      text = 'Thẻ trắng sẵn sàng: ${r['cardUid']}';
      color = Colors.green;
    }
    return Card(
      child: ListTile(
        leading: Icon(Icons.nfc, color: color),
        title: const Text('Đầu đọc thẻ'),
        subtitle: Text(text, style: TextStyle(color: color)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Kiểm tra lại', icon: const Icon(Icons.refresh), onPressed: _inspect),
          IconButton(tooltip: 'Thẻ trắng mới (giả lập)', icon: const Icon(Icons.add_card), onPressed: _newBlank),
        ]),
      ),
    );
  }
}
