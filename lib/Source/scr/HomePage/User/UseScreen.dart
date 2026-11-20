// Đường dẫn: lib/Source/scr/HomePage/User/UserScreen.dart

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/api/User/Total/UserAPI.dart';
import 'package:qlpt_frontend/Source/api/User/Total/UserDTO.dart';
import 'package:qlpt_frontend/Source/api/User/Pay/PayAPI.dart';
import 'package:qlpt_frontend/Source/api/User/Pay/PayDTO.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/User/UseInforScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/User/Card/MyCardScreen.dart';
import 'package:qlpt_frontend/Source/cache/AppNetworkImage.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';

class UserScreen extends StatefulWidget {
  const UserScreen({super.key});

  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  int _currentIndex = 0; // Quản lý Tab dưới cùng
  final formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  MyRoomResponse? _myRoom;
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    // Hiện ngay thông tin phòng lưu trong máy, sau đó đồng bộ với server (ETag)
    UserAPI.cachedMyRoom().then((cached) {
      if (mounted && cached != null && _myRoom == null) {
        setState(() {
          _myRoom = cached;
          _isLoading = false;
        });
      }
    });
    _fetchMyRoom();

    // --- KHỞI TẠO LẮNG NGHE FCM Ở ĐÂY ---
    _setupFCMListener();
  }

  // --- HÀM LẮNG NGHE FCM ---
  // --- HÀM LẮNG NGHE FCM ---
  void _setupFCMListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("UserScreen nhận được FCM: ${message.notification?.title}");

      if (message.notification?.title == "Thanh toán tự động thành công" ||
          message.notification?.title == "Thanh toán thành công" ||
          message.notification?.title == "Cập nhật giá dịch vụ" ||
          message.notification?.title == "Hóa đơn mới") {

        // CHỈ ĐÓNG KHI CÓ POPUP/DIALOG ĐANG MỞ (Tránh lỗi văng hẳn ra ngoài UserScreen)
        bool isPopupOpen = ModalRoute.of(context)?.isCurrent != true;
        if (isPopupOpen && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        // 2. Hiển thị thông báo trên màn hình
        _showSnackBar("🎉 ${message.notification?.body}", Colors.green);

        // 3. Cập nhật lại thông tin phòng
        _fetchMyRoom();

        // GHI CHÚ: Nếu đang mở danh sách hóa đơn, nó sẽ không tự load lại (vì modal là 1 route độc lập).
        // Bạn cần kéo xuống tắt bảng hóa đơn đi và bật lại thì API getMyInvoices mới được gọi.
      }
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  }

  // Gọi API lấy thông tin phòng đang thuê
  Future<void> _fetchMyRoom() async {
    setState(() {
      _isLoading = _myRoom == null; // Đã có dữ liệu cũ thì giữ nguyên trên màn hình, khỏi vòng xoay
      _errorMessage = "";
    });
    try {
      var room = await UserAPI.getMyRoomInfo();
      if (!mounted) return;
      setState(() {
        _myRoom = room;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
    }
  }

  // ================= HÀM XEM ẢNH CÔNG TƠ (ĐÃ SỬA CHUẨN CHO APK & MÁY ẢO) =================
  void _showMeterImageDialog(String imageUrl) async {
    // 1. Lấy JWT Token phòng trường hợp Backend bắt xác thực khi tải ảnh
    String? token = await Security.getToken();

    // 2. Chuẩn hóa URL: Thay http://localhost:8080 bằng đúng baseUrl hiện tại của App
    String fixedUrl = imageUrl.trim();
    if (fixedUrl.contains("http://localhost:8080")) {
      fixedUrl = fixedUrl.replaceAll("http://localhost:8080", ApiTotal.baseUrl);
    } else if (!fixedUrl.startsWith("http")) {
      fixedUrl = "${ApiTotal.baseUrl}${fixedUrl.startsWith('/') ? '' : '/'}$fixedUrl";
    }

    print("========== ĐANG TẢI ẢNH CÔNG TƠ ==========");
    print("URL gốc: $imageUrl");
    print("URL sau khi xử lý: $fixedUrl");

    if (!mounted) return;

    showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16))
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Ảnh minh chứng", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, color: Colors.white),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: InteractiveViewer(
                    panEnabled: true,
                    boundaryMargin: const EdgeInsets.all(20),
                    minScale: 0.5,
                    maxScale: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      // Ảnh cache trên đĩa (≤90 ngày), giải mã theo bề rộng màn hình thay vì ảnh gốc
                      child: AppNetworkImage(
                        url: fixedUrl,
                        authenticated: false,
                        // Truyền kèm Header xác thực và bỏ qua cảnh báo nếu dùng Ngrok
                        extraHeaders: {
                          if (token != null) "Authorization": "Bearer $token",
                          "ngrok-skip-browser-warning": "true",
                        },
                        fit: BoxFit.contain,
                        placeholder: (context) => const SizedBox(
                          height: 300,
                          child: Center(child: CircularProgressIndicator(color: Colors.green)),
                        ),
                        errorBuilder: (context, error) {
                          print("-> LỖI TẢI ẢNH CÔNG TƠ: $error");
                          return SizedBox(
                            height: 220,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                                  const SizedBox(height: 10),
                                  const Text("Không thể tải ảnh công tơ", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    fixedUrl,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Đóng", style: TextStyle(color: Colors.green, fontSize: 16)),
                ),
                const SizedBox(height: 8)
              ],
            ),
          );
        }
    );
  }

  // ================= HÀM XỬ LÝ THANH TOÁN =================
  void _showPaymentDialog(int invoiceId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      VietQRResponse qrData = await PayAPI.getVietQR(invoiceId);

      if (!mounted) return;
      Navigator.pop(context);

      String qrImageUrl = qrData.qrUrl;
      if (qrImageUrl.contains("http://localhost:8080")) {
        qrImageUrl = qrImageUrl.replaceAll("http://localhost:8080", ApiTotal.baseUrl);
      }

      if (!mounted) return;
      showDialog(
          context: context,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade500,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Thanh toán hóa đơn", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.close, color: Colors.white),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text("Quét mã QR bằng ứng dụng ngân hàng", style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 16),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AppNetworkImage(
                        url: qrImageUrl,
                        authenticated: false,
                        height: 250,
                        width: 250,
                        fit: BoxFit.cover,
                        placeholder: (context) => const SizedBox(
                          height: 250, width: 250,
                          child: Center(child: CircularProgressIndicator(color: Colors.orange)),
                        ),
                        errorBuilder: (context, error) => const SizedBox(
                          height: 250, width: 250,
                          child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Column(
                        children: [
                          _buildPaymentDetailRow("Ngân hàng:", qrData.bankId ?? "---"),
                          _buildPaymentDetailRow("Số tài khoản:", qrData.accountNo ?? "---"),
                          _buildPaymentDetailRow("Chủ thẻ:", qrData.accountName ?? "---"),
                          _buildPaymentDetailRow("Số tiền:", formatCurrency.format(qrData.amount), color: Colors.red),
                          _buildPaymentDetailRow("Nội dung:", qrData.transferContent ?? "---", color: Colors.blue),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    const Text("Lưu ý: Chuyển đúng nội dung để hệ thống tự động xác nhận",
                        style: TextStyle(color: Colors.red, fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          }
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
    }
  }

  Widget _buildPaymentDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value, textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color ?? Colors.black87)),
          ),
        ],
      ),
    );
  }

  // ================= UI BOTTOM SHEET: LỊCH SỬ HÓA ĐƠN =================
  void _showInvoiceHistory() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: FutureBuilder<List<MyInvoiceResponse>>(
                future: UserAPI.getMyInvoices(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.green));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text("Lỗi: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                  }

                  List<MyInvoiceResponse> invoices = snapshot.data ?? [];

                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                      const SizedBox(height: 16),
                      const Text("Hóa Đơn Của Tôi", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
                      const Divider(height: 30),

                      if (invoices.isEmpty)
                        const Expanded(child: Center(child: Text("Bạn chưa có hóa đơn nào!"))),

                      if (invoices.isNotEmpty)
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: invoices.length,
                            itemBuilder: (ctx, index) {
                              var inv = invoices[index];
                              bool isPaid = inv.status == 'PAID';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: isPaid ? Colors.green.shade300 : Colors.red.shade300, width: 1.5)
                                ),
                                child: ExpansionTile(
                                  backgroundColor: isPaid ? Colors.green.shade50 : Colors.red.shade50,
                                  collapsedBackgroundColor: isPaid ? Colors.green.shade50 : Colors.red.shade50,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  leading: CircleAvatar(
                                    backgroundColor: isPaid ? Colors.green : Colors.red,
                                    child: Icon(isPaid ? Icons.check : Icons.warning_amber, color: Colors.white),
                                  ),
                                  title: Text("Kỳ ${inv.billingCycle}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                  subtitle: Text(
                                    "Hạn nộp: ${inv.dueDate ?? '---'}\nTổng tiền: ${formatCurrency.format(inv.totalAmount)}",
                                    style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.bold),
                                  ),
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)), border: Border(top: BorderSide(color: Colors.grey.shade300))),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text("CHỈ SỐ TIÊU THỤ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("⚡ Điện:"),
                                              Text("Cũ: ${inv.oldElectricity} - Mới: ${inv.newElectricity} = ${inv.electricUsage} kWh", style: const TextStyle(fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("Thành tiền:"),
                                              Text(formatCurrency.format(inv.electricTotal), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                                            ],
                                          ),
                                          const Divider(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("💧 Nước:"),
                                              Text("Cũ: ${inv.oldWater} - Mới: ${inv.newWater} = ${inv.waterUsage} Khối", style: const TextStyle(fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text("Thành tiền:"),
                                              Text(formatCurrency.format(inv.waterTotal), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                            ],
                                          ),
                                          const Divider(),
                                          const Text("DỊCH VỤ KHÁC", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                          const SizedBox(height: 8),
                                          if (inv.extraServices.isEmpty) const Text("Không có dịch vụ thêm."),
                                          ...inv.extraServices.map((srv) => Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text("🔹 ${srv.serviceName}:"),
                                              Text(formatCurrency.format(srv.appliedPrice), style: const TextStyle(fontWeight: FontWeight.bold)),
                                            ],
                                          )).toList(),

                                          const SizedBox(height: 16),
                                          const Divider(),

                                          // HÀNG NÚT BẤM DƯỚI CÙNG
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: [
                                              // Nút xem ảnh
                                              if (inv.meterImageUrl != null && inv.meterImageUrl!.isNotEmpty)
                                                OutlinedButton.icon(
                                                  onPressed: () {
                                                    _showMeterImageDialog(inv.meterImageUrl!);
                                                  },
                                                  icon: const Icon(Icons.image, color: Colors.blue, size: 18),
                                                  label: const Text("Ảnh công tơ", style: TextStyle(color: Colors.blue)),
                                                  style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(color: Colors.blue),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                                  ),
                                                ),

                                              // NÚT THANH TOÁN (Chỉ hiện khi chưa thanh toán)
                                              if (!isPaid)
                                                ElevatedButton.icon(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                    _showPaymentDialog(inv.invoiceId!);
                                                  },
                                                  icon: const Icon(Icons.qr_code_2, color: Colors.white, size: 18),
                                                  label: const Text("Thanh toán", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.orange.shade500,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                                  ),
                                                )
                                            ],
                                          )
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                }
            ),
          );
        }
    );
  }

  // ================= GIAO DIỆN CHÍNH (TAB 1) =================
  Widget _buildHomeTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.green));
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 80, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.red)
              ),
            ),
          ],
        ),
      );
    }

    if (_myRoom == null) {
      return const Center(child: Text("Không có dữ liệu phòng."));
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Phòng bạn đang thuê:", style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green.shade600, Colors.green.shade400]),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("P.${_myRoom!.roomNumber}", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Icon(Icons.meeting_room, size: 40, color: Colors.white70),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_myRoom!.propertyName, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(_myRoom!.propertyAddress ?? "Chưa cập nhật địa chỉ", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const Divider(color: Colors.white54, height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Giá phòng gốc:", style: TextStyle(color: Colors.white, fontSize: 14)),
                    Text(formatCurrency.format(_myRoom!.basePrice), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),
          ),

          const SizedBox(height: 30),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.orange.shade500,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 4,
            ),
            onPressed: _showInvoiceHistory,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text("XEM HÓA ĐƠN & THANH TOÁN", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= GIAO DIỆN CÁ NHÂN (TAB 2) =================
  Widget _buildProfileTab() {
    return const UseInforScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? "Quản Lý Tiền Trọ" : (_currentIndex == 1 ? "Thẻ của tôi" : "Cá Nhân"), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.green,
        elevation: 0,
        centerTitle: true,
      ),
      body: _currentIndex == 0 ? _buildHomeTab() : (_currentIndex == 1 ? const MyCardScreen() : _buildProfileTab()),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.green,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Phòng của tôi"),
          BottomNavigationBarItem(icon: Icon(Icons.credit_card), label: "Thẻ của tôi"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Cá nhân"),
        ],
      ),
    );
  }
}