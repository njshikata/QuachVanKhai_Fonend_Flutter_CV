// Đường dẫn: lib/Source/scr/Common/PagedListView.dart
//
// DANH SÁCH CUỘN VÔ HẠN DÙNG CHUNG
//  - ListView.builder: chỉ build các dòng đang hiện trên màn hình (dòng cuộn khỏi màn hình được giải phóng).
//  - ScrollController: còn cách cuối danh sách ~400px thì tự tải trang tiếp theo (page/size).
//  - Mỗi item bọc trong 1 ValueNotifier: sửa 1 item (khóa thẻ, đổi số dư...) chỉ rebuild đúng dòng đó,
//    KHÔNG setState cả danh sách.
//
// Chế độ so sánh (PerfFlags, chốt lúc mở màn hình):
//  - listBuilder = false  -> SingleChildScrollView + Column: build TẤT CẢ các dòng.
//  - paging = false       -> tải hết mọi trang ngay từ đầu.
//  - itemNotifier = false -> 1 item đổi là setState cả danh sách.

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart' show PageResult;
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';
import 'package:qlpt_frontend/Source/perf/PerfMonitor.dart';

typedef PageFetcher<T> = Future<PageResult<T>> Function(int page, int size);
typedef NotifierItemBuilder<T> = Widget Function(BuildContext context, ValueNotifier<T> item, int index);

class PagedListView<T> extends StatefulWidget {
  final PageFetcher<T> fetch;
  final NotifierItemBuilder<T> itemBuilder;
  final int pageSize;
  final String emptyText;
  final IconData emptyIcon;
  final EdgeInsetsGeometry padding;
  final double? itemExtent; // Biết trước chiều cao dòng -> Flutter khỏi đo từng dòng (cuộn mượt hơn)
  final int unpagedPageSize; // Khi tắt phân trang: kích thước mỗi lần tải (server thẻ giới hạn 50)

  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.pageSize = 20,
    this.emptyText = 'Chưa có dữ liệu',
    this.emptyIcon = Icons.inbox_outlined,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 88),
    this.itemExtent,
    this.unpagedPageSize = 50,
  });

  @override
  PagedListViewState<T> createState() => PagedListViewState<T>();
}

class PagedListViewState<T> extends State<PagedListView<T>> {
  static const double _loadMoreThreshold = 400;

  final ScrollController _controller = ScrollController();
  final List<ValueNotifier<T>> _items = [];
  int _nextPage = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0; // Bỏ kết quả của request cũ khi đã refresh

  // Chốt cấu hình lúc mở màn hình
  late final bool _useBuilder = PerfFlags.listBuilder.value;
  late final bool _usePaging = PerfFlags.paging.value;
  late final bool _useItemNotifier = PerfFlags.itemNotifier.value;

  List<ValueNotifier<T>> get items => List.unmodifiable(_items);
  ScrollController get scrollController => _controller;
  bool get hasMore => _hasNext;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _loading = true; // Lần đầu: hiện vòng xoay ngay, không setState trong initState
    _loadMore(initial: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _disposeItems();
    super.dispose();
  }

  void _disposeItems() {
    for (final n in _items) {
      if (!_useItemNotifier) n.removeListener(_rebuildAll);
      n.dispose();
    }
  }

  // Chế độ KHÔNG tối ưu: 1 item đổi -> vẽ lại toàn bộ danh sách
  void _rebuildAll() {
    if (mounted) setState(() {});
  }

  ValueNotifier<T> _wrap(T e) {
    final n = ValueNotifier<T>(e);
    if (!_useItemNotifier) n.addListener(_rebuildAll);
    return n;
  }

  /// Tải lại từ đầu (kéo để làm mới / sau khi thêm mới).
  Future<void> refresh() async {
    _generation++;
    _disposeItems();
    setState(() {
      _items.clear();
      _nextPage = 0;
      _hasNext = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  void _onScroll() {
    if (!_usePaging || !_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - _loadMoreThreshold) _loadMore();
  }

  Future<void> _loadMore({bool initial = false}) async {
    if (!initial) {
      if (_loading || !_hasNext) return;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final gen = _generation;
    try {
      if (!_usePaging) {
        // KHÔNG tối ưu: tải tuần tự mọi trang rồi mới hiển thị
        final all = <T>[];
        var page = 0;
        while (true) {
          final r = await widget.fetch(page++, widget.unpagedPageSize);
          if (!mounted || gen != _generation) return;
          all.addAll(r.items);
          if (!r.hasNext) break;
        }
        setState(() {
          _items.addAll(all.map(_wrap));
          _hasNext = false;
          _loading = false;
        });
        return;
      }

      final page = await widget.fetch(_nextPage, widget.pageSize);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.items.map(_wrap));
        _hasNext = page.hasNext;
        _nextPage++;
        _loading = false;
      });
      // Trang đầu chưa đủ lấp màn hình -> tải tiếp (không có sự kiện cuộn để kích hoạt)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients && _controller.position.maxScrollExtent <= 0 && _hasNext) _loadMore();
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Widget _buildItem(BuildContext context, int index) {
    PerfCounters.itemBuilds++;
    return widget.itemBuilder(context, _items[index], index);
  }

  @override
  Widget build(BuildContext context) {
    final showFooter = _loading || _error != null;
    final count = _items.length + (showFooter ? 1 : 0);

    Widget list;
    if (_items.isEmpty && !_loading && _error == null) {
      list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Icon(widget.emptyIcon, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(child: Text(widget.emptyText, style: TextStyle(color: Colors.grey.shade600))),
        ],
      );
    } else if (!_useBuilder) {
      // KHÔNG tối ưu: build toàn bộ dòng cùng lúc
      list = SingleChildScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++) _buildItem(context, i),
            if (showFooter) _footer(),
          ],
        ),
      );
    } else {
      list = ListView.builder(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        itemExtent: showFooter ? null : widget.itemExtent,
        itemCount: count,
        itemBuilder: (context, index) {
          if (index >= _items.length) return _footer();
          return _buildItem(context, index);
        },
      );
    }

    return RefreshIndicator(onRefresh: refresh, child: list);
  }

  Widget _footer() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_error.toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
            TextButton.icon(onPressed: () => _loadMore(), icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
          ],
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
    );
  }
}
