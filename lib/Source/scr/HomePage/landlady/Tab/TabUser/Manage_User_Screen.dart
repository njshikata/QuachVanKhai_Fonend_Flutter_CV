// Đường dẫn: lib/Source/scr/HomePage/landlady/Tab/TabUser/Manage_User_Screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qlpt_frontend/Source/api/Manage_User/Manage_User_API.dart';
import 'package:qlpt_frontend/Source/api/Manage_User/Manage_User_DTO.dart';
import 'package:qlpt_frontend/Source/api/Register/Register_API.dart';
import 'package:qlpt_frontend/Source/api/Register/Register_DTO.dart';
import 'package:qlpt_frontend/Source/api/ServiceRoom/ServiceRoomAPI.dart';
import 'package:qlpt_frontend/Source/api/ServiceRoom/ServiceRoomDTO.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';
import 'package:qlpt_frontend/Source/perf/PerfMonitor.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
// TODO: Kiểm tra lại đường dẫn import file LoginScreen bên dưới xem đúng với project của bạn chưa
import 'package:qlpt_frontend/Source/scr/Login/LoginScreen.dart';

class ManageUserScreen extends StatefulWidget {
  const ManageUserScreen({super.key});

  @override
  State<ManageUserScreen> createState() => _ManageUserScreenState();
}

class _ManageUserScreenState extends State<ManageUserScreen> {
  List<ManageUserDTO> _users = [];
  List<ManageUserDTO> _displayUsers = [];
  bool _isLoading = true;
  String _errorMessage = '';

  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'ALL';

  final formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final users = await ManageUserAPI.getAllUsers();
      setState(() {
        _users = users;
        _isLoading = false;
        _applyFilter();
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception: ", "");
        _isLoading = false;
      });
      _showSnackBar("Lỗi tải dữ liệu: $_errorMessage", Colors.red);
    }
  }

  void _applyFilter() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _displayUsers = _users.where((user) {
        bool matchesSearch = (user.fullName?.toLowerCase().contains(query) ?? false) ||
            (user.phoneNumber?.contains(query) ?? false);
        if (!matchesSearch) return false;

        bool hasRooms = user.rentedRooms != null && user.rentedRooms!.isNotEmpty;

        if (_filterType == 'NO_ROOM') return !hasRooms;
        if (_filterType == 'PAID') return hasRooms && user.rentedRooms!.every((room) => room.isPaidThisMonth == true);
        if (_filterType == 'UNPAID') return hasRooms && user.rentedRooms!.any((room) => room.isPaidThisMonth == false);

        return true;
      }).toList();
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ===========================================================================
  // TÍNH NĂNG MỚI: XEM LỊCH SỬ THUÊ NHÀ (THAY THẾ XÓA)
  // ===========================================================================
  void _showUserHistory(ManageUserDTO user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: FutureBuilder<List<TenantHistory>>(
            future: ManageUserAPI.getUserHistory(user.id!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.orange));
              }
              if (snapshot.hasError) {
                return Center(child: Text("Lỗi: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
              }

              List<TenantHistory> historyList = snapshot.data ?? [];

              return Column(
                children: [
                  const SizedBox(height: 16),
                  Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                  const SizedBox(height: 16),
                  Text("Lịch Sử Thuê: ${user.fullName}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
                  const Divider(height: 30),

                  if (historyList.isEmpty)
                    const Expanded(child: Center(child: Text("Khách này chưa từng thuê phòng nào!"))),

                  if (historyList.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: historyList.length,
                        itemBuilder: (ctx, index) {
                          var history = historyList[index];
                          bool isActive = history.contractStatus == 'ACTIVE';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isActive ? Colors.green.shade300 : Colors.grey.shade400, width: 1.5)
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("🏠 ${history.propertyName} - P.${history.roomNumber}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(color: isActive ? Colors.green : Colors.grey, borderRadius: BorderRadius.circular(6)),
                                        child: Text(isActive ? "Đang thuê" : "Đã trả phòng", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                    ],
                                  ),
                                  const Divider(),
                                  Text("📅 Từ: ${history.startDate ?? '---'}   Đến: ${history.endDate ?? '---'}", style: TextStyle(color: Colors.grey.shade700)),
                                  const SizedBox(height: 4),
                                  Text("💰 Đặt cọc: ${formatCurrency.format(history.depositAmount)}", style: const TextStyle(fontWeight: FontWeight.w500)),

                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: history.unpaidInvoices! > 0 ? Colors.red.shade50 : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: history.unpaidInvoices! > 0 ? Colors.red.shade200 : Colors.blue.shade200)
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Tổng hóa đơn đã lập: ${history.totalInvoices}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text("Đã thu:", style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                                            Text(formatCurrency.format(history.totalPaidAmount), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                        if (history.unpaidInvoices! > 0) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text("Còn nợ (${history.unpaidInvoices} hóa đơn):", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                              Text(formatCurrency.format(history.totalUnpaidAmount), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ]
                                      ],
                                    ),
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showUserDialog({ManageUserDTO? existingUser}) {
    final bool isEditMode = existingUser != null;
    final nameController = TextEditingController(text: existingUser?.fullName ?? '');
    final emailController = TextEditingController(text: existingUser?.email ?? '');
    final phoneController = TextEditingController(text: existingUser?.phoneNumber ?? '');
    final cccdController = TextEditingController(text: existingUser?.identityCard ?? '');

    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isEditMode ? "Sửa thông tin Khách" : "Thêm Khách mới", style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: InputDecoration(labelText: "Họ và tên", prefixIcon: const Icon(Icons.person, color: Colors.blueAccent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 12),
                TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: "Số điện thoại", prefixIcon: const Icon(Icons.phone, color: Colors.blueAccent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 12),
                TextField(controller: cccdController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "CCCD / CMND", prefixIcon: const Icon(Icons.badge, color: Colors.blueAccent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                const SizedBox(height: 12),
                TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: "Email đăng nhập", prefixIcon: const Icon(Icons.email, color: Colors.blueAccent), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    enabled: !isEditMode
                ),
                if (!isEditMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: "Mật khẩu đăng nhập",
                      prefixIcon: const Icon(Icons.lock, color: Colors.blueAccent),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                if (nameController.text.trim().isEmpty || emailController.text.trim().isEmpty || phoneController.text.trim().isEmpty) {
                  _showSnackBar("Vui lòng điền đầy đủ các thông tin bắt buộc!", Colors.red);
                  return;
                }

                if (!isEditMode && passwordController.text.trim().isEmpty) {
                  _showSnackBar("Vui lòng nhập mật khẩu cho tài khoản mới!", Colors.red);
                  return;
                }

                Navigator.pop(context);

                try {
                  if (isEditMode) {
                    ManageUserDTO userDTO = ManageUserDTO(
                      id: existingUser.id,
                      fullName: nameController.text.trim(),
                      email: emailController.text.trim(),
                      phoneNumber: phoneController.text.trim(),
                      identityCard: cccdController.text.trim(),
                      role: existingUser.role ?? 'TENANT',
                      status: existingUser.status ?? 'ACTIVE',
                    );
                    await ManageUserAPI.updateUser(existingUser.id!, userDTO);
                    _showSnackBar("Cập nhật thành công!", Colors.green);
                  } else {
                    RegisterRequest request = RegisterRequest(
                      email: emailController.text.trim(),
                      password: passwordController.text.trim(),
                      fullName: nameController.text.trim(),
                      phoneNumber: phoneController.text.trim(),
                      identityNumber: cccdController.text.trim(),
                    );
                    await RegisterAPI.registerUser(request);
                    _showSnackBar("Thêm khách mới thành công!", Colors.green);
                  }
                  _fetchUsers();
                } catch (e) {
                  _showSnackBar("Lỗi: ${e.toString().replaceAll("Exception: ", "")}", Colors.red);
                }
              },
              child: Text(isEditMode ? "CẬP NHẬT" : "LƯU TÀI KHOẢN", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showUserDetailsBottomSheet(ManageUserDTO user) {
    bool hasRooms = user.rentedRooms != null && user.rentedRooms!.isNotEmpty;
    bool isUnpaid = hasRooms && user.rentedRooms!.any((room) => room.isPaidThisMonth == false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.only(left: 24, right: 24, top: 16),
                child: ListView(
                  controller: controller,
                  children: [
                    Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 20),

                    CircleAvatar(
                      radius: 45,
                      backgroundColor: hasRooms ? (isUnpaid ? Colors.red.shade100 : Colors.green.shade100) : Colors.grey.shade200,
                      child: Text(
                          user.fullName != null && user.fullName!.isNotEmpty ? user.fullName![0].toUpperCase() : 'U',
                          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: hasRooms ? (isUnpaid ? Colors.red.shade700 : Colors.green.shade700) : Colors.grey.shade700)
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(child: Text(user.fullName ?? 'Chưa cập nhật tên', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87))),
                    const SizedBox(height: 6),

                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: hasRooms ? (isUnpaid ? Colors.red : Colors.green) : Colors.grey, borderRadius: BorderRadius.circular(12)),
                        child: Text(hasRooms ? (isUnpaid ? "Đang nợ tiền phòng" : "Đã thanh toán đủ") : "Khách tự do", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const Divider(height: 30),

                    _buildDetailRow(Icons.phone, "Số điện thoại", user.phoneNumber ?? "Chưa có"),
                    _buildDetailRow(Icons.email, "Email", user.email ?? "Chưa có"),
                    _buildDetailRow(Icons.badge, "CCCD / CMND", user.identityCard ?? "Chưa cập nhật"),
                    const SizedBox(height: 16),

                    if (hasRooms)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Danh sách phòng đang thuê:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                          const SizedBox(height: 10),
                          ...user.rentedRooms!.map((room) {
                            return FutureBuilder<RoomBillingSummary>(
                                future: ServiceRoomAPI.getRoomBillingSummary(room.roomId ?? 0),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: Colors.blueAccent)));
                                  }
                                  if (snapshot.hasError) return _buildRoomCardFallback(room);
                                  if (snapshot.hasData) return _buildDetailedRoomCard(snapshot.data!);
                                  return const SizedBox();
                                }
                            );
                          }),
                        ],
                      ),

                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () {
                              Navigator.pop(context);
                              _showUserDialog(existingUser: user);
                            },
                            icon: const Icon(Icons.edit, color: Colors.blueAccent),
                            label: const Text("Chỉnh sửa", style: TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () {
                              Navigator.pop(context);
                              _showUserHistory(user);
                            },
                            icon: const Icon(Icons.history),
                            label: const Text("Xem Lịch Sử", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildDetailedRoomCard(RoomBillingSummary summary) {
    bool isRoomPaid = summary.isPaidThisMonth;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRoomPaid ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isRoomPaid ? Colors.green.shade200 : Colors.red.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("🏠 ${summary.propertyName} P.${summary.roomNumber}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: isRoomPaid ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(6)),
                child: Text(isRoomPaid ? "Đã đóng" : "Chưa đóng", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const Divider(),
          const Text("Chi tiết chi phí:", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 6),

          ...summary.services.map((svc) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("• ${svc.serviceName} (${svc.unit}):", style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                  Text(formatCurrency.format(svc.appliedPrice), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                ],
              ),
            );
          }),

          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("TỔNG CỘNG:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
              Text(formatCurrency.format(summary.totalAmount), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isRoomPaid ? Colors.green.shade700 : Colors.red.shade700)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildRoomCardFallback(dynamic room) {
    bool isRoomPaid = room.isPaidThisMonth == true;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isRoomPaid ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isRoomPaid ? Colors.green.shade200 : Colors.red.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("🏠 ${room.propertyName ?? 'Khu trọ'} P.${room.roomNumber}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text("💰 Giá thuê: ${formatCurrency.format(room.price ?? 0)}/tháng", style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text("🏷️ Tháng này: "),
              Text(isRoomPaid ? "Đã đóng" : "Chưa đóng", style: TextStyle(color: isRoomPaid ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.bold))
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 20),
          const SizedBox(width: 12),
          Text("$title: ", style: const TextStyle(fontSize: 15, color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text("Có lỗi xảy ra:\n$_errorMessage", textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchUsers, child: const Text("Thử lại"))
          ],
        ),
      );
    }

    if (_displayUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text("Không tìm thấy khách hàng nào", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    // 1 dòng khách thuê (dùng chung cho 2 chế độ bên dưới)
    Widget tileAt(BuildContext context, int index) {
          PerfCounters.itemBuilds++; // Đếm số dòng phải build (so sánh Column vs ListView.builder)
          final user = _displayUsers[index];

          bool hasRooms = user.rentedRooms != null && user.rentedRooms!.isNotEmpty;
          bool isUnpaid = false;
          if (hasRooms) {
            isUnpaid = user.rentedRooms!.any((room) => room.isPaidThisMonth == false);
          }

          Color borderColor = Colors.grey.shade300;
          Color bgColor = Colors.white;
          Color avatarBgColor = Colors.grey.shade100;
          Color avatarTextColor = Colors.grey.shade600;

          if (hasRooms) {
            if (isUnpaid) {
              borderColor = Colors.red.shade300;
              bgColor = Colors.red.shade50;
              avatarBgColor = Colors.red.shade100;
              avatarTextColor = Colors.red.shade700;
            } else {
              borderColor = Colors.green.shade300;
              bgColor = Colors.green.shade50;
              avatarBgColor = Colors.green.shade100;
              avatarTextColor = Colors.green.shade700;
            }
          }

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderColor, width: 1.2)),
            color: bgColor,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showUserDetailsBottomSheet(user),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: avatarBgColor,
                      child: Text(
                        user.fullName != null && user.fullName!.isNotEmpty ? user.fullName![0].toUpperCase() : 'U',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: avatarTextColor),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName ?? 'Chưa cập nhật tên', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(
                              children: [
                                Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text(user.phoneNumber ?? 'Không có SĐT', style: TextStyle(color: Colors.grey.shade700, fontSize: 13))
                              ]
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasRooms)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: isUnpaid ? Colors.red : Colors.green, borderRadius: BorderRadius.circular(6)),
                            child: Text(isUnpaid ? "Chưa đóng" : "Đã đóng", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          )
                        else
                          Text("Khách tự do", style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic)),

                        const SizedBox(height: 8),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        }

    const pad = EdgeInsets.only(top: 10, bottom: 90, left: 16, right: 16);
    if (!PerfFlags.listBuilder.value) {
      // CHƯA TỐI ƯU (để so sánh): Column build TẤT CẢ khách thuê cùng lúc
      return RefreshIndicator(
        onRefresh: _fetchUsers,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pad,
          child: Column(children: [for (var i = 0; i < _displayUsers.length; i++) tileAt(context, i)]),
        ),
      );
    }
    // TỐI ƯU: ListView.builder chỉ build các dòng đang hiện trên màn hình
    return RefreshIndicator(
      onRefresh: _fetchUsers,
      child: ListView.builder(padding: pad, itemCount: _displayUsers.length, itemBuilder: tileAt),
    );
  }

  // ================= XỬ LÝ ĐĂNG XUẤT =================
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Xác nhận đăng xuất", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: const Text("Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng không?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              Navigator.pop(ctx); // Đóng hộp thoại

              // 1. Xóa token
              await Security.logout();

              if (!mounted) return;

              // 2. Chuyển hướng & Xóa lịch sử điều hướng
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
              );
            },
            child: const Text("Đăng xuất", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      // ================= THÊM APPBAR =================
      appBar: AppBar(
        title: const Text("Quản lý Khách thuê", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          IconButton(
            tooltip: "Đăng xuất",
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _handleLogout,
          ),
        ],
      ),
      // ===============================================
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text("Thêm User", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _showUserDialog(),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 4, offset: const Offset(0, 3))]),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300, width: 0.5)),
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: "Tìm tên, SĐT...",
                        hintStyle: TextStyle(fontSize: 14, color: Colors.grey),
                        prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300, width: 0.5)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filterType,
                        isExpanded: true,
                        icon: const Icon(Icons.filter_list, color: Colors.blueAccent, size: 20),
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text("Tất cả")),
                          DropdownMenuItem(value: 'UNPAID', child: Text("Chưa đóng", style: TextStyle(color: Colors.red))),
                          DropdownMenuItem(value: 'PAID', child: Text("Đã đóng", style: TextStyle(color: Colors.green))),
                          DropdownMenuItem(value: 'NO_ROOM', child: Text("Khách tự do")),
                        ],
                        onChanged: (value) {
                          setState(() => _filterType = value!);
                          _applyFilter();
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildUserList()),
        ],
      ),
    );
  }
}