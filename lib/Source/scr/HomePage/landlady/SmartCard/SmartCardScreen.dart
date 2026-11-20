// Đường dẫn: lib/Source/scr/HomePage/landlady/SmartCard/SmartCardScreen.dart
//
// DANH SÁCH THẺ THÔNG MINH (chủ trọ)
//  - PagedListView: ListView.builder + ScrollController phân trang (20 thẻ/trang).
//  - Mỗi dòng là 1 ValueListenableBuilder: khóa/mở thẻ hay sửa ở màn chi tiết chỉ rebuild đúng dòng đó.
//  - Ảnh: AppNetworkImage 48x48 -> chỉ giải mã ~144px thay vì ảnh gốc.

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardAPI.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart';
import 'package:qlpt_frontend/Source/cache/AppNetworkImage.dart';
import 'package:qlpt_frontend/Source/cache/MediaCachePolicy.dart';
import 'package:qlpt_frontend/Source/scr/Common/PagedListView.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Narbar_Flotter/Narbar.dart';

import 'CardDialogs.dart';
import 'IssueCardScreen.dart';
import 'SmartCardDetailScreen.dart';

class SmartCardScreen extends StatefulWidget {
  /// true = nằm trong tab "Thẻ" ở thanh dưới của LandladyScreen (không có AppBar riêng).
  final bool embedded;

  const SmartCardScreen({super.key, this.embedded = false});

  @override
  State<SmartCardScreen> createState() => _SmartCardScreenState();
}

class _SmartCardScreenState extends State<SmartCardScreen> {
  final GlobalKey<PagedListViewState<SmartCardItem>> _listKey = GlobalKey();
  String? _status; // null = tất cả

  static const Map<String?, String> _filters = {
    null: 'Tất cả',
    'ACTIVE': 'Hoạt động',
    'LOCKED': 'Đang khóa',
    'REVOKED': 'Đã thu hồi',
  };

  Future<PageResult<SmartCardItem>> _fetch(int page, int size) async {
    final result = await SmartCardAPI.list(page: page, size: size, status: _status);
    // Theo dõi chủ phòng để dọn cache ảnh của chủ cũ sau 30 ngày
    for (final c in result.items) {
      if (c.isRevoked) continue;
      MediaCachePolicy.onRoomOwner(
        roomId: c.roomId,
        currentOwnerId: c.tenantId,
        previousOwnerId: c.previousOwnerId,
        ownerChangedAt: c.ownerChangedAt,
      );
    }
    return result;
  }

  Future<void> _showReader() async {
    try {
      final r = await SmartCardAPI.readerStatus();
      if (!mounted) return;
      final cards = (r['virtualCards'] as List?)?.join(', ') ?? '—';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đầu đọc thẻ (Card Bridge)'),
          content: Text('Chế độ: ${r['mode']}\n'
              'Có thẻ: ${r['cardPresent'] == true ? 'Có' : 'Không'}\n'
              'Khe: ${r['slot'] ?? '—'}\n'
              'Card UID: ${r['cardUid'] ?? '—'}\n'
              'PIN còn: ${r['pinTriesRemaining'] ?? '—'} lần\n'
              'Thẻ ảo: $cards'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
        ),
      );
    } catch (e) {
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
    }
  }

  Future<void> _toggleLock(ValueNotifier<SmartCardItem> item) async {
    final c = item.value;
    final next = c.isLocked ? 'ACTIVE' : 'LOCKED';
    try {
      item.value = await SmartCardAPI.setStatus(c.id, next); // Chỉ dòng này rebuild
      if (mounted) CardDialogs.toast(context, next == 'LOCKED' ? 'Đã khóa thẻ' : 'Đã mở khóa thẻ');
    } catch (e) {
      if (mounted) CardDialogs.toast(context, e.toString(), error: true);
    }
  }

  void _setFilter(String? v) {
    if (v == _status) return;
    setState(() => _status = v);
    _listKey.currentState?.refresh();
  }

  /// Thanh lọc trạng thái + nút đầu đọc (dùng khi nhúng trong tab, thay cho AppBar).
  Widget _toolbar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final e in _filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) => _setFilter(e.key),
                    ),
                  ),
              ]),
            ),
          ),
          IconButton(tooltip: 'Đầu đọc thẻ', icon: const Icon(Icons.nfc), onPressed: _showReader),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final list = PagedListView<SmartCardItem>(
      key: _listKey,
      fetch: _fetch,
      emptyText: 'Chưa cấp thẻ nào',
      emptyIcon: Icons.credit_card_off,
      itemBuilder: (context, item, index) => ValueListenableBuilder<SmartCardItem>(
        valueListenable: item,
        builder: (context, c, _) => _CardTile(
          card: c,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SmartCardDetailScreen(item: item)),
          ),
          onToggleLock: c.isRevoked ? null : () => _toggleLock(item),
        ),
      ),
    );
    final fab = FloatingActionButton.extended(
      heroTag: 'issue-card',
      onPressed: () async {
        final created = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const IssueCardScreen()));
        if (created == true) _listKey.currentState?.refresh();
      },
      icon: const Icon(Icons.add_card),
      label: const Text('Cấp thẻ'),
    );
    if (widget.embedded) {
      return Scaffold(
        floatingActionButton: fab,
        body: Column(children: [_toolbar(), Expanded(child: list)]),
      );
    }
    return Scaffold(
      appBar: Navbar(
        title: 'Thẻ thông minh',
        actions: [
          IconButton(tooltip: 'Đầu đọc thẻ', icon: const Icon(Icons.nfc, color: Colors.white), onPressed: _showReader),
          PopupMenuButton<String?>(
            tooltip: 'Lọc trạng thái',
            icon: const Icon(Icons.filter_list, color: Colors.white),
            initialValue: _status,
            onSelected: _setFilter,
            itemBuilder: (_) => _filters.entries
                .map((e) => PopupMenuItem<String?>(value: e.key, child: Text(e.value)))
                .toList(),
          ),
        ],
      ),
      floatingActionButton: fab,
      body: list,
    );
  }
}

class _CardTile extends StatelessWidget {
  final SmartCardItem card;
  final VoidCallback onTap;
  final VoidCallback? onToggleLock;

  const _CardTile({required this.card, required this.onTap, this.onToggleLock});

  @override
  Widget build(BuildContext context) {
    final color = CardDialogs.statusColor(card.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: AppNetworkImage(
          url: card.photoUrl,
          cacheKey: card.photoCacheKey,
          width: 48,
          height: 48,
          borderRadius: BorderRadius.circular(24),
          tag: MediaCacheTag(group: card.photoGroup, ownerId: card.tenantId, roomId: card.roomId),
        ),
        title: Text(card.holderName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          'Phòng ${card.roomNumber ?? '—'} • ${card.propertyName ?? ''}\n'
          'HSD: ${CardDialogs.date(card.expiryDate)}${card.expired ? ' (hết hạn)' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(CardDialogs.statusLabel(card.status), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            if (onToggleLock != null)
              InkWell(
                onTap: onToggleLock,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(card.isLocked ? Icons.lock_open : Icons.lock_outline, size: 20, color: Colors.blueGrey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
