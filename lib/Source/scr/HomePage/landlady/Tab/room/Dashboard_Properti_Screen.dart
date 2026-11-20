import 'dart:math' as math;
// Đường dẫn: lib/Source/scr/HomePage/landlady/Dashboard_Properti_Screen.dart

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/perf/PerfFlags.dart';
import 'package:qlpt_frontend/Source/perf/PerfMonitor.dart';
import 'package:intl/intl.dart';
import 'package:qlpt_frontend/Source/api/Property/LandlordManage/LandlordManageAPI.dart';
import 'package:qlpt_frontend/Source/api/Property/LandlordManage/LandlordManageDTO.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/addTotel/Add_Room_Screen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/addTotel/Add_rental_roomScreen.dart';

import '../../../../../api/Property/PropertyAPI.dart';
import '../../../../../api/Property/PropertyDTO.dart';
import '../../../../../api/Manage_User/Manage_User_API.dart';
import '../../../../../api/Manage_User/Manage_User_DTO.dart';

class DashboardPropertiScreen extends StatefulWidget {
  const DashboardPropertiScreen({super.key});

  @override
  State<DashboardPropertiScreen> createState() => _DashboardPropertiScreenState();
}

class _DashboardPropertiScreenState extends State<DashboardPropertiScreen> {
  late Future<List<LandlordPropertyDTO>> _futureProperties;
  // Bản gần nhất (từ database phụ hoặc lần tải trước) -> hiện ngay trong lúc chờ server, không màn hình trắng
  List<LandlordPropertyDTO>? _lastData;

  String _filterStatus = 'ALL';
  String _sortPrice = 'NONE';
  final Set<int> _collapsed = {}; // id các khu trọ đang thu gọn

  @override
  void initState() {
    super.initState();
    _loadData();
    PropertyAPI.cachedDashboard().then((cached) {
      if (mounted && cached != null && _lastData == null) setState(() => _lastData = cached);
    });
  }

  void _loadData() {
    setState(() {
      _futureProperties = PropertyAPI.getDashboardData().then((fresh) => _lastData = fresh);
    });
  }

  // HÀM TỰ CHẾ: Format tiền tệ nếu máy bạn lỗi package intl
  String formatCurrencyCustom(double amount) {
    String result = amount.toStringAsFixed(0);
    result = result.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    return '$result đ';
  }

  List<LandlordPropertyDTO>? _cacheSource;
  String _cacheKey = '';
  List<LandlordPropertyDTO> _cacheResult = const [];

  List<LandlordPropertyDTO> _processDataCached(List<LandlordPropertyDTO> source) {
    final key = '$_filterStatus|$_sortPrice';
    if (!identical(source, _cacheSource) || key != _cacheKey) {
      _cacheSource = source;
      _cacheKey = key;
      _cacheResult = _processData(source);
    }
    return _cacheResult;
  }

  // Lọc và sắp xếp dữ liệu
  List<LandlordPropertyDTO> _processData(List<LandlordPropertyDTO> sourceData) {
    List<LandlordPropertyDTO> result = [];
    for (var property in sourceData) {
      List<LandlordRoomDTO> filteredRooms = property.rooms.where((room) {
        if (_filterStatus == 'AVAILABLE' && room.status != 'AVAILABLE') return false;
        if (_filterStatus == 'RENTED' && room.status != 'RENTED') return false;
        return true;
      }).toList();

      if (_sortPrice == 'ASC') {
        filteredRooms.sort((a, b) => a.basePrice.compareTo(b.basePrice));
      } else if (_sortPrice == 'DESC') {
        filteredRooms.sort((a, b) => b.basePrice.compareTo(a.basePrice));
      }

      if (_filterStatus == 'ALL' || filteredRooms.isNotEmpty) {
        result.add(LandlordPropertyDTO(id: property.id, name: property.name, address: property.address, rooms: filteredRooms));
      }
    }
    return result;
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  // =========================================================================
  // POPUP 1: THÊM NGƯỜI VÀO PHÒNG TRỐNG (ĐÃ FIX LỖI LOAD USER & NULL SAFETY)
  // =========================================================================
  void _showAddTenantDialog(BuildContext context, LandlordRoomDTO room) async {
    // 1. Hiển thị vòng xoay Loading để UI không bị đơ khi gọi API
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
    );

    List<ManageUserDTO> allUsers = [];

    try {
      // 2. Gọi đồng thời cả 2 API để tiết kiệm thời gian
      final results = await Future.wait([
        ManageUserAPI.getAllUsers(),
        PropertyAPI.getDashboardData(),
      ]);

      allUsers = results[0] as List<ManageUserDTO>;
      List<LandlordPropertyDTO> freshProperties = results[1] as List<LandlordPropertyDTO>;

      // 3. Quét danh sách khách ĐANG THUÊ
      Set<String> rentedPhones = {};
      for (var property in freshProperties) {
        for (var r in property.rooms) {
          if (r.status == 'RENTED' && r.currentTenant != null) {
            // Đã fix lỗi unconditionally invoked: Thêm dấu ? và fallback chuỗi rỗng
            String phone = r.currentTenant!.phoneNumber?.trim() ?? "";
            if (phone.isNotEmpty) rentedPhones.add(phone);
          }
        }
      }

      // 4. Lọc danh sách khách CHƯA CÓ TRỌ & XỬ LÝ TRÙNG LẶP
      Set<String> seenEmails = {}; // Dùng để chặn trùng Email gây crash Dropdown

      allUsers = allUsers.where((user) {
        // Đã fix lỗi unconditionally invoked: Thêm dấu ? và fallback chuỗi rỗng
        String userPhone = user.phoneNumber?.trim() ?? "";
        String userEmail = user.email?.trim() ?? "";

        // Bỏ qua user nếu không có email hoặc email bị trùng
        if (userEmail.isEmpty || seenEmails.contains(userEmail)) return false;

        // Bỏ qua user nếu số điện thoại này đang có trong danh sách đang thuê
        if (userPhone.isNotEmpty && rentedPhones.contains(userPhone)) return false;

        seenEmails.add(userEmail); // Đánh dấu email này đã được đưa vào danh sách
        return true;
      }).toList();

    } catch (e) {
      if (mounted) Navigator.pop(context); // Tắt Loading
      _showSnackBar("Lỗi tải danh sách: $e", Colors.red);
      return;
    }

    if (!context.mounted) return;
    Navigator.pop(context); // Tắt Loading khi đã load xong dữ liệu

    if (allUsers.isEmpty) {
      _showSnackBar("Tất cả khách hàng đều đã có trọ hoặc danh sách trống!", Colors.orange);
      return;
    }

    String? selectedTenantEmail;
    final depositController = TextEditingController(text: "0");
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateBuilder) {
          return AlertDialog(
            title: Text("Thêm khách vào P.${room.roomNumber}", style: const TextStyle(color: Colors.blueAccent)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "Chọn Khách Thuê", border: OutlineInputBorder()),
                    items: allUsers.map((user) {
                      return DropdownMenuItem<String>(
                        value: user.email, // Nhờ Set seenEmails ở trên, chắc chắn value này là duy nhất
                        child: Text("${user.fullName}\n${user.phoneNumber}", overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) => setStateBuilder(() => selectedTenantEmail = val),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: depositController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Tiền cọc (VNĐ)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  ListTile(
                    title: const Text("Ngày dọn vào:"),
                    subtitle: Text("${selectedDate.day}/${selectedDate.month}/${selectedDate.year}"),
                    trailing: const Icon(Icons.calendar_month, color: Colors.blueAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setStateBuilder(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () async {
                  if (selectedTenantEmail == null) {
                    _showSnackBar("Vui lòng chọn khách thuê!", Colors.orange);
                    return;
                  }

                  Navigator.pop(context); // Đóng Dialog

                  String formattedDate = "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}";
                  DateTime endDate = DateTime(selectedDate.year + 1, selectedDate.month, selectedDate.day);
                  String formattedEndDate = "${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";

                  try {
                    AssignTenantRequest req = AssignTenantRequest(
                      roomId: room.id!,
                      tenantEmail: selectedTenantEmail!,
                      deposit: double.parse(depositController.text.trim().isEmpty ? "0" : depositController.text.trim()),
                      startDate: formattedDate,
                      endDate: formattedEndDate,
                    );

                    String msg = await LandlordManageAPI.assignTenant(req);
                    _showSnackBar(msg, Colors.green);
                    _loadData();
                  } catch (e) {
                    _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
                  }
                },
                child: const Text("TẠO HỢP ĐỒNG", style: TextStyle(color: Colors.white)),
              )
            ],
          );
        });
      },
    );
  }

  // =========================================================================
  // POPUP 2: SỬA HOẶC XÓA PHÒNG
  // =========================================================================
  void _showEditRoomDialog(BuildContext context, LandlordRoomDTO room) {
    final numController = TextEditingController(text: room.roomNumber);
    final priceController = TextEditingController(text: room.basePrice.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Cấu hình P.${room.roomNumber}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: numController, decoration: const InputDecoration(labelText: "Tên/Số phòng")),
              const SizedBox(height: 10),
              TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Giá phòng (VNĐ)")),
            ],
          ),
          actions: [
            // NÚT XÓA PHÒNG
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Đóng popup sửa
                // Mở cảnh báo Xóa
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Cảnh báo", style: TextStyle(color: Colors.red)),
                    content: Text("Bạn có chắc chắn muốn xóa vĩnh viễn P.${room.roomNumber} không?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          try {
                            String msg = await LandlordManageAPI.deleteRoom(room.id!);
                            _showSnackBar(msg, Colors.green);
                            _loadData();
                          } catch (e) {
                            _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
                          }
                        },
                        child: const Text("Xác nhận Xóa", style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                );
              },
              child: const Text("XÓA PHÒNG", style: TextStyle(color: Colors.red)),
            ),

            // NÚT LƯU THAY ĐỔI
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  UpdateRoomRequest req = UpdateRoomRequest(
                    roomNumber: numController.text.trim(),
                    basePrice: double.parse(priceController.text.trim()),
                  );
                  String msg = await LandlordManageAPI.updateRoom(room.id!, req);
                  _showSnackBar(msg, Colors.green);
                  _loadData();
                } catch (e) {
                  _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
                }
              },
              child: const Text("LƯU", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // =========================================================================
  // POPUP 3: HIỂN THỊ CHI TIẾT KHI BẤM VÀO PHÒNG TRONG LƯỚI
  // =========================================================================
  void _showRoomDetailBottomSheet(BuildContext context, LandlordRoomDTO room) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Phòng ${room.roomNumber}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                  Chip(
                    label: Text(room.status == 'AVAILABLE' ? "Trống" : "Đã thuê", style: const TextStyle(color: Colors.white)),
                    backgroundColor: room.status == 'AVAILABLE' ? Colors.green : Colors.orange,
                  ),
                ],
              ),
              const Divider(height: 30),
              Text("💰 Giá thuê: ${formatCurrencyCustom(room.basePrice)} / Tháng", style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 10),

              // NẾU PHÒNG ĐÃ THUÊ -> HIỆN THÔNG TIN KHÁCH VÀ NÚT ĐUỔI KHÁCH
              if (room.status == 'RENTED' && room.currentTenant != null) ...[
                Text("👤 Khách thuê: ${room.currentTenant!.fullName}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text("📞 SĐT: ${room.currentTenant!.phoneNumber}", style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Đóng BottomSheet
                      // Hiện cảnh báo xác nhận trả phòng
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Xác nhận Trả phòng", style: TextStyle(color: Colors.orange)),
                          content: Text("Xác nhận chấm dứt hợp đồng và trả P.${room.roomNumber} về trạng thái trống?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                try {
                                  String msg = await LandlordManageAPI.removeTenant(room.id!);
                                  _showSnackBar(msg, Colors.green);
                                  _loadData();
                                } catch (e) {
                                  _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
                                }
                              },
                              child: const Text("Xác nhận", style: TextStyle(color: Colors.white)),
                            )
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_remove),
                    label: const Text("TRẢ PHÒNG / ĐUỔI KHÁCH"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ]

              // NẾU PHÒNG TRỐNG -> HIỆN NÚT SỬA VÀ THÊM NGƯỜI
              else ...[
                const Text("👤 Khách thuê: Chưa có", style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditRoomDialog(context, room);
                        },
                        icon: const Icon(Icons.edit, color: Colors.blueAccent),
                        label: const Text("SỬA"),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddTenantDialog(context, room);
                        },
                        icon: const Icon(Icons.person_add),
                        label: const Text("THÊM NGƯỜI"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.blueAccent,
        icon: const Icon(Icons.add_home, color: Colors.white),
        label: const Text("Thêm Khu Trọ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddRentalRoomScreen()),
          );
          if (result == true) _loadData();
        },
      ),
      body: Column(
        children: [
          // ================= THANH LỌC & SẮP XẾP =================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filterStatus,
                        isExpanded: true,
                        icon: const Icon(Icons.filter_alt_outlined, color: Colors.blueAccent, size: 20),
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text("Tất cả phòng")),
                          DropdownMenuItem(value: 'AVAILABLE', child: Text("Phòng trống")),
                          DropdownMenuItem(value: 'RENTED', child: Text("Đã có khách")),
                        ],
                        onChanged: (value) => setState(() => _filterStatus = value!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortPrice,
                        isExpanded: true,
                        icon: const Icon(Icons.sort, color: Colors.blueAccent, size: 20),
                        style: const TextStyle(fontSize: 14, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'NONE', child: Text("Giá: Mặc định")),
                          DropdownMenuItem(value: 'ASC', child: Text("Thấp đến Cao")),
                          DropdownMenuItem(value: 'DESC', child: Text("Cao đến Thấp")),
                        ],
                        onChanged: (value) => setState(() => _sortPrice = value!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ================= DANH SÁCH KHU TRỌ =================
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadData();
                await _futureProperties;
              },
              child: FutureBuilder<List<LandlordPropertyDTO>>(
                future: _futureProperties,
                builder: (context, snapshot) {
                  final waiting = snapshot.connectionState == ConnectionState.waiting;
                  final source = waiting ? _lastData : snapshot.data;
                  if (waiting && source == null) return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
                  if (snapshot.hasError) return Center(child: Text("Lỗi: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                  if (source == null || source.isEmpty) return const Center(child: Text("Bạn chưa có khu trọ nào. Hãy thêm mới!"));

                  List<LandlordPropertyDTO> displayProperties = _processDataCached(source);
                  if (displayProperties.isEmpty) return const Center(child: Text("Không có phòng nào thỏa mãn điều kiện lọc."));

                  if (!PerfFlags.listBuilder.value) return _buildLegacyList(displayProperties);
                  return _buildSliverList(displayProperties);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== CHƯA TỐI ƯU (giữ để so sánh khi tắt "ListView.builder" trong Hiệu năng & Demo) =====
  // GridView(shrinkWrap) trong mỗi item ListView: khu nào lướt tới là build + layout TẤT CẢ phòng của khu đó 1 lúc.
  Widget _buildLegacyList(List<LandlordPropertyDTO> displayProperties) {
    return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: displayProperties.length + 1,
                    itemBuilder: (context, index) {
                      if (index == displayProperties.length) return const SizedBox(height: 80);

                      final property = displayProperties[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.home_work, color: Colors.white)),
                            title: Text(property.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            subtitle: Text(property.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("Tổng: ${property.rooms.length} phòng", style: const TextStyle(fontWeight: FontWeight.bold)),
                                        TextButton.icon(
                                          onPressed: () async {
                                            final result = await Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => AddRoomScreen(propertyId: property.id, propertyName: property.name)),
                                            );
                                            if (result == true) _loadData();
                                          },
                                          icon: const Icon(Icons.add, color: Colors.blueAccent, size: 20),
                                          label: const Text("Thêm phòng", style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    if (property.rooms.isEmpty)
                                      const Padding(padding: EdgeInsets.all(16.0), child: Text("Chưa có phòng nào", style: TextStyle(color: Colors.grey)))
                                    else
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.5,
                                        ),
                                        itemCount: property.rooms.length,
                                        itemBuilder: (context, roomIndex) {
                                          PerfCounters.itemBuilds++; // Đếm để so sánh với bản tối ưu
                                          final room = property.rooms[roomIndex];
                                          final isAvailable = room.status == 'AVAILABLE';

                                          return InkWell(
                                            onTap: () => _showRoomDetailBottomSheet(context, room),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: isAvailable ? Colors.green.shade50 : Colors.orange.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: isAvailable ? Colors.green.shade300 : Colors.orange.shade300, width: 1.5),
                                              ),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(room.roomNumber, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isAvailable ? Colors.green.shade800 : Colors.orange.shade800)),
                                                  const SizedBox(height: 4),
                                                  Icon(isAvailable ? Icons.check_circle_outline : Icons.person, size: 16, color: isAvailable ? Colors.green.shade700 : Colors.orange.shade700),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
  }

  // ===== TỐI ƯU: "làm phẳng" mọi khu trọ thành MỘT ListView.builder duy nhất =====
  // Danh sách dòng: [header khu 1, dòng 3 phòng, dòng 3 phòng, ..., header khu 2, ...].
  // ListView.builder chỉ build các dòng đang hiện trên màn hình, kể cả header.
  //
  // Vì sao không dùng CustomScrollView với mỗi khu 1 SliverGrid (cách làm trước đó)?
  //  - 50 khu = 100 sliver: viewport phải layout lại cả 100 sliver trong MỖI khung hình khi cuộn.
  //  - Header của cả 50 khu (SliverToBoxAdapter) bị build ngay lúc mở màn, dù chưa nhìn thấy.
  //  Đo trên dữ liệu thật (4.000 phòng), cách đó giật 34% khung hình, còn bản cũ chỉ 3%.
  //  Bộ "So sánh trên app thật" đã phát hiện vấn đề này.
  static const int _cols = 3;
  // Mỗi item = 4 dòng (12 phòng). Đo trên app thật: 1 dòng/item làm ListView phải tạo item mới gần như MỖI khung hình
  // khi cuộn + quá nhiều lớp vẽ nhỏ -> giật 29-39%. Gộp 4 dòng: ít item, ít lớp vẽ, vẫn chỉ build phần đang thấy.
  static const int _rowsPerItem = 4;

  Widget _buildSliverList(List<LandlordPropertyDTO> displayProperties) {
    // Mỗi phần tử: (khu trọ, -1 = header | -2 = "chưa có phòng" | k = dòng bắt đầu từ phòng thứ k)
    final rows = <(LandlordPropertyDTO, int)>[];
    for (final property in displayProperties) {
      rows.add((property, -1));
      if (_collapsed.contains(property.id)) continue;
      if (property.rooms.isEmpty) {
        rows.add((property, -2));
      } else {
        for (var k = 0; k < property.rooms.length; k += _cols * _rowsPerItem) {
          rows.add((property, k));
        }
      }
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final (property, k) = rows[index];
        if (k == -1) {
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 16, bottom: 8),
            child: _propertyHeader(property, !_collapsed.contains(property.id)),
          );
        }
        if (k == -2) {
          return const Padding(
              padding: EdgeInsets.all(16.0), child: Center(child: Text("Chưa có phòng nào", style: TextStyle(color: Colors.grey))));
        }
        // Tối đa 4 dòng × 3 ô phòng (giữ đúng kích thước ô như GridView cũ: tỉ lệ 1.5, cách nhau 10)
        final end = math.min(k + _cols * _rowsPerItem, property.rooms.length);
        return Column(children: [
          for (var r = k; r < end; r += _cols)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                for (var c = 0; c < _cols; c++) ...[
                  if (c > 0) const SizedBox(width: 10),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1.5,
                      child: r + c < end ? _countedCell(property.rooms[r + c]) : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ]),
            ),
        ]);
      },
    );
  }

  Widget _countedCell(LandlordRoomDTO room) {
    PerfCounters.itemBuilds++;
    return _roomCell(room);
  }

  Widget _propertyHeader(LandlordPropertyDTO property, bool expanded) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            onTap: () => setState(() => expanded ? _collapsed.add(property.id) : _collapsed.remove(property.id)),
            leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.home_work, color: Colors.white)),
            title: Text(property.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text(property.address, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Tổng: ${property.rooms.length} phòng", style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => AddRoomScreen(propertyId: property.id, propertyName: property.name)),
                    );
                    if (result == true) _loadData();
                  },
                  icon: const Icon(Icons.add, color: Colors.blueAccent, size: 20),
                  label: const Text("Thêm phòng", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomCell(LandlordRoomDTO room) {
    final isAvailable = room.status == 'AVAILABLE';
    return InkWell(
      onTap: () => _showRoomDetailBottomSheet(context, room),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: isAvailable ? Colors.green.shade50 : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isAvailable ? Colors.green.shade300 : Colors.orange.shade300, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(room.roomNumber, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isAvailable ? Colors.green.shade800 : Colors.orange.shade800)),
            const SizedBox(height: 4),
            Icon(isAvailable ? Icons.check_circle_outline : Icons.person, size: 16, color: isAvailable ? Colors.green.shade700 : Colors.orange.shade700),
          ],
        ),
      ),
    );
  }

}