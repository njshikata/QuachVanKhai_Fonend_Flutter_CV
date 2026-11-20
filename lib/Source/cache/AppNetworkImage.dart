// Đường dẫn: lib/Source/cache/AppNetworkImage.dart
//
// Widget ảnh mạng dùng chung cho TOÀN APP (thay Image.network):
//  - cached_network_image + AppCacheManager: ảnh tải 1 lần, lần sau đọc từ đĩa.
//  - memCacheWidth/memCacheHeight = kích thước hiển thị x devicePixelRatio:
//    ảnh 1080x1440 hiển thị 48x48 chỉ được giải mã ~144px -> RAM giảm hàng chục lần.
//    (Chỉ đặt 1 chiều để giữ đúng tỉ lệ ảnh; nếu biết cả 2 chiều thì đặt chiều theo width.)
//  - cacheKey có version -> đổi ảnh trên server là đổi key, không bao giờ hiện ảnh cũ.
//  - Server trả 204 (ảnh hết hạn lưu trữ) -> hiện placeholder.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';

import 'AppCacheManager.dart';
import 'MediaCachePolicy.dart';

class AppNetworkImage extends StatefulWidget {
  final String? url;              // URL tuyệt đối hoặc đường dẫn "/api/..."
  final String? cacheKey;         // Mặc định = url
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool authenticated;       // Gắn JWT + handshake (ảnh API riêng tư)
  final Map<String, String>? extraHeaders;
  final MediaCacheTag? tag;
  final int? decodeWidth;         // Ép kích thước giải mã khi không biết width hiển thị
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final IconData fallbackIcon;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.authenticated = true,
    this.extraHeaders,
    this.tag,
    this.decodeWidth,
    this.placeholder,
    this.errorBuilder,
    this.fallbackIcon = Icons.person,
  });

  /// Chuẩn hóa URL: đường dẫn tương đối hoặc "http://localhost:8080" -> baseUrl hiện tại (emulator/thiết bị thật).
  static String resolve(String url) {
    var u = url.trim();
    if (u.startsWith('http://localhost:8080')) return u.replaceFirst('http://localhost:8080', ApiTotal.baseUrl);
    if (u.startsWith('http')) return u;
    return '${ApiTotal.baseUrl}${u.startsWith('/') ? '' : '/'}$u';
  }

  // Header dùng chung ~30s (handshake server chấp nhận lệch 60s) -> tránh đọc SharedPreferences cho từng ảnh
  static Future<Map<String, String>>? _sharedHeaders;
  static DateTime _sharedHeadersAt = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<Map<String, String>> _authHeaders() {
    final now = DateTime.now();
    if (_sharedHeaders == null || now.difference(_sharedHeadersAt) > const Duration(seconds: 30)) {
      _sharedHeadersAt = now;
      _sharedHeaders = ApiTotal.getAuthHeaders().then((h) {
        final m = Map<String, String>.from(h as Map);
        m.remove('Content-Type');
        return m;
      });
    }
    return _sharedHeaders!;
  }

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

class _AppNetworkImageState extends State<AppNetworkImage> {
  Future<Map<String, String>>? _headers;

  @override
  void initState() {
    super.initState();
    MediaCachePolicy.ensureCleaned();
    _prepareHeaders();
  }

  @override
  void didUpdateWidget(covariant AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey) _prepareHeaders();
  }

  void _prepareHeaders() {
    _headers = widget.authenticated
        ? AppNetworkImage._authHeaders().then((h) => {...h, ...?widget.extraHeaders})
        : Future.value({...?widget.extraHeaders});
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url;
    Widget child;
    if (url == null || url.isEmpty) {
      child = _fallback(context);
    } else {
      child = FutureBuilder<Map<String, String>>(
        future: _headers,
        builder: (context, snap) {
          if (!snap.hasData) return _loading(context);
          return _buildCached(context, AppNetworkImage.resolve(url), snap.data!);
        },
      );
    }
    child = SizedBox(width: widget.width, height: widget.height, child: child);
    if (widget.borderRadius != null) child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    return child;
  }

  Widget _buildCached(BuildContext context, String resolvedUrl, Map<String, String> headers) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int? memW;
    int? memH;
    if (widget.width != null && widget.width!.isFinite) {
      memW = (widget.width! * dpr).round();
    } else if (widget.height != null && widget.height!.isFinite) {
      memH = (widget.height! * dpr).round();
    } else {
      memW = widget.decodeWidth ?? (MediaQuery.sizeOf(context).width * dpr).round();
    }
    final key = widget.cacheKey ?? resolvedUrl;

    // ===== Chế độ so sánh (PerfFlags) =====
    if (!PerfFlags.imageResize.value) {
      memW = null; // Giải mã nguyên ảnh gốc vào RAM
      memH = null;
    }
    if (!PerfFlags.imageDiskCache.value) {
      // Image.network: không cache đĩa, mỗi lần mở app tải lại từ server
      return Image.network(
        resolvedUrl,
        headers: headers,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: memW,
        cacheHeight: memH,
        loadingBuilder: (context, child, progress) => progress == null ? child : _loading(context),
        errorBuilder: (context, error, _) =>
            widget.errorBuilder != null ? widget.errorBuilder!(context, error) : _fallback(context),
      );
    }

    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      cacheKey: key,
      cacheManager: AppCacheManager.instance,
      httpHeaders: headers,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: memW,
      memCacheHeight: memH,
      fadeInDuration: const Duration(milliseconds: 150),
      imageBuilder: (context, provider) {
        MediaCachePolicy.track(key, widget.tag);
        return Image(image: provider, width: widget.width, height: widget.height, fit: widget.fit, gaplessPlayback: true);
      },
      placeholder: (context, _) => _loading(context),
      errorWidget: (context, _, error) =>
          widget.errorBuilder != null ? widget.errorBuilder!(context, error) : _fallback(context),
    );
  }

  Widget _loading(BuildContext context) {
    if (widget.placeholder != null) return widget.placeholder!(context);
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _fallback(BuildContext context) {
    final size = [widget.width, widget.height].whereType<double>().fold<double>(48, (a, b) => a < b ? a : b);
    return Container(
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(widget.fallbackIcon, color: Colors.grey, size: size * 0.55),
    );
  }
}
