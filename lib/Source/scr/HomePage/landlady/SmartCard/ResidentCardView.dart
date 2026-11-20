// Đường dẫn: lib/Source/scr/HomePage/landlady/SmartCard/ResidentCardView.dart
//
// Giao diện "thẻ cư dân" lớn (dùng chung chủ trọ + người thuê) và các khối dùng lại:
//  - ResidentCardView : hình thẻ có ảnh, họ tên, phòng, hạn, số dư, trạng thái.
//  - RecentPreview    : 5 dòng gần nhất + "Xem tất cả" (mở CardHistoryScreen phân trang đầy đủ).
//  - CardHistoryScreen: trang danh sách đầy đủ (PagedListView).

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart';
import 'package:qlpt_frontend/Source/cache/AppNetworkImage.dart';
import 'package:qlpt_frontend/Source/cache/MediaCachePolicy.dart';
import 'package:qlpt_frontend/Source/scr/Common/PagedListView.dart';

import 'CardDialogs.dart';

class ResidentCardView extends StatelessWidget {
  final SmartCardItem card;
  final DateTime? dateOfBirth;
  final String photoCacheKey;
  final String photoGroup;
  final VoidCallback? onChangePhoto;

  const ResidentCardView({
    super.key,
    required this.card,
    required this.photoCacheKey,
    required this.photoGroup,
    this.dateOfBirth,
    this.onChangePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final c = card;
    final inactive = !c.isActive || c.expired;
    final colors = inactive
        ? const [Color(0xFF546E7A), Color(0xFF90A4AE)]
        : const [Color(0xFF1B5E20), Color(0xFF43A047)];
    final statusText = c.expired ? 'Hết hạn' : CardDialogs.statusLabel(c.status);

    return AspectRatio(
      aspectRatio: 1.586, // tỉ lệ thẻ ngân hàng chuẩn ISO 7810
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 6))],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.apartment, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('THẺ CƯ DÂN', style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                child: Text(statusText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _photo(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.holderName ?? '—',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _line(Icons.meeting_room, 'Phòng ${c.roomNumber ?? '—'}'),
                    if (dateOfBirth != null) _line(Icons.cake, CardDialogs.date(dateOfBirth)),
                    _line(Icons.event, 'HSD ${CardDialogs.date(c.expiryDate)}'),
                  ]),
                ),
              ]),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Text(_groupUid(c.cardUid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5, color: Colors.white70, fontSize: 12)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                const Text('Số dư', style: TextStyle(fontSize: 11, color: Colors.white70)),
                Text(CardDialogs.money(c.lastKnownBalance), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _photo() => Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 2), borderRadius: BorderRadius.circular(10)),
          child: AppNetworkImage(
            url: card.photoUrl,
            cacheKey: photoCacheKey,
            width: 72,
            height: 90,
            borderRadius: BorderRadius.circular(8),
            tag: MediaCacheTag(group: photoGroup, ownerId: card.tenantId, roomId: card.roomId),
          ),
        ),
        if (onChangePhoto != null)
          Positioned(
            right: -8,
            bottom: -8,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onChangePhoto,
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.camera_alt, size: 16, color: Colors.green)),
              ),
            ),
          ),
      ]);

  static Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        ]),
      );

  /// "ABCDEF0123456789" -> "ABCD EF01 2345 6789"
  static String _groupUid(String uid) {
    final b = StringBuffer();
    for (var i = 0; i < uid.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(uid[i]);
    }
    return b.toString();
  }
}

/// Khối "gần đây": tải [previewSize] dòng đầu, có nút "Xem tất cả".
/// Đổi [refreshToken] để tải lại (VD sau khi quẹt thẻ / nạp tiền).
class RecentPreview<T> extends StatefulWidget {
  final String title;
  final IconData icon;
  final String emptyText;
  final Future<PageResult<T>> Function(int page, int size) fetch;
  final Widget Function(T item) tileBuilder;
  final int refreshToken;
  final int previewSize;

  const RecentPreview({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.fetch,
    required this.tileBuilder,
    this.refreshToken = 0,
    this.previewSize = 5,
  });

  @override
  State<RecentPreview<T>> createState() => _RecentPreviewState<T>();
}

class _RecentPreviewState<T> extends State<RecentPreview<T>> {
  late Future<PageResult<T>> _future = widget.fetch(0, widget.previewSize);

  @override
  void didUpdateWidget(covariant RecentPreview<T> old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken) _future = widget.fetch(0, widget.previewSize);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: FutureBuilder<PageResult<T>>(
          future: _future,
          builder: (context, snap) {
            final items = snap.data?.items ?? const [];
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const SizedBox(width: 12),
                Icon(widget.icon, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CardHistoryScreen<T>(
                        title: widget.title,
                        fetch: widget.fetch,
                        emptyText: widget.emptyText,
                        emptyIcon: widget.icon,
                        tileBuilder: widget.tileBuilder,
                      ),
                    ),
                  ),
                  child: const Text('Xem tất cả'),
                ),
              ]),
              if (snap.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Expanded(child: Text(snap.error.toString(), style: const TextStyle(color: Colors.redAccent))),
                    TextButton(
                      onPressed: () => setState(() => _future = widget.fetch(0, widget.previewSize)),
                      child: const Text('Thử lại'),
                    ),
                  ]),
                )
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(widget.emptyText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                )
              else
                for (final it in items) widget.tileBuilder(it),
            ]);
          },
        ),
      ),
    );
  }
}

/// Trang danh sách đầy đủ có phân trang.
class CardHistoryScreen<T> extends StatelessWidget {
  final String title;
  final Future<PageResult<T>> Function(int page, int size) fetch;
  final String emptyText;
  final IconData emptyIcon;
  final Widget Function(T item) tileBuilder;

  const CardHistoryScreen({
    super.key,
    required this.title,
    required this.fetch,
    required this.emptyText,
    required this.emptyIcon,
    required this.tileBuilder,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(backgroundColor: Colors.green, foregroundColor: Colors.white, title: Text(title)),
        body: PagedListView<T>(
          fetch: fetch,
          emptyText: emptyText,
          emptyIcon: emptyIcon,
          padding: const EdgeInsets.all(8),
          itemBuilder: (_, n, _) => tileBuilder(n.value),
        ),
      );
}

/// Nút thao tác vuông (icon + nhãn) cho lưới thao tác nhanh.
class CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const CardActionButton({super.key, required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? color : Colors.grey;
    return Material(
      color: c.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 26),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
