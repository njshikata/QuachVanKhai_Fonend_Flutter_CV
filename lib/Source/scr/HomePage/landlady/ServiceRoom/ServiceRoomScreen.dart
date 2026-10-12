// Đường dẫn: lib/Source/scr/HomePage/landlady/Tab/ServiceRoom/ServiceRoomScreen.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qlpt_frontend/Source/api/Property/PropertyAPI.dart';
import 'package:qlpt_frontend/Source/api/Property/PropertyDTO.dart';
import 'package:qlpt_frontend/Source/api/ServiceRoom/ServiceRoomAPI.dart';
import 'package:qlpt_frontend/Source/api/ServiceRoom/ServiceRoomDTO.dart';

class ServiceRoomScreen extends StatefulWidget {
  const ServiceRoomScreen({super.key});

  @override
  State<ServiceRoomScreen> createState() => _ServiceRoomScreenState();
}

class _ServiceRoomScreenState extends State<ServiceRoomScreen> {
  // Thay vì dùng FlatRoomItem, ta sẽ lưu giữ toàn bộ danh sách Khu Trọ gốc
  List<LandlordPropertyDTO> _allProperties = [];
  List<LandlordPropertyDTO> _displayProperties = [];
  bool _isLoading = true;
  String _errorMessage = '';

  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'ALL';

  final formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  // Mảng lưu trạng thái chốt số/thanh toán của từng phòng để tô màu Khu Trọ
  // Key: roomId, Value: RoomBillingSummary
  Map<int, RoomBillingSummary> _roomBillingMap = {};

  @override
  void initState() {
    super.initState();
    _fetchPropertiesAndBillingInfo();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Lấy dữ liệu danh sách khu trọ + đồng thời fetch luôn trạng thái hóa đơn của các phòng đang thuê
  Future<void> _fetchPropertiesAndBillingInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final properties = await PropertyAPI.getDashboardData();

      Map<int, RoomBillingSummary> tempMap = {};
      for (var p in properties) {
        for (var r in p.rooms) {
          if (r.status == 'RENTED') {
            try {
              var summary = await ServiceRoomAPI.getRoomBillingSummary(r.id!);
              tempMap[r.id!] = summary;
            } catch (e) {
              // Bỏ qua lỗi lẻ tẻ của từng phòng
            }
          }
        }
      }

      // THÊM ĐIỀU KIỆN MỞ RỘNG: if (mounted)
      if (mounted) {
        setState(() {
          _allProperties = properties;
          _roomBillingMap = tempMap;
          _isLoading = false;
          _applyFilter();
        });
      }
    } catch (e) {
      // THÊM ĐIỀU KIỆN MỞ RỘNG: if (mounted)
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll("Exception: ", "");
          _isLoading = false;
        });
        _showSnackBar("Lỗi tải dữ liệu: $_errorMessage", Colors.red);
      }
    }
  }

  Future<void> _refreshBillingOnly() async {
    Map<int, RoomBillingSummary> tempMap = Map.from(_roomBillingMap);
    for (var p in _allProperties) {
      for (var r in p.rooms) {
        if (r.status == 'RENTED') {
          try {
            var summary = await ServiceRoomAPI.getRoomBillingSummary(r.id!);
            tempMap[r.id!] = summary;
          } catch (e) {
            // ...
          }
        }
      }
    }

    // THÊM ĐIỀU KIỆN MỞ RỘNG: if (mounted)
    if (mounted) {
      setState(() {
        _roomBillingMap = tempMap;
      });
    }
  }

  void _applyFilter() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      // Clone lại mảng gốc để filter
      List<LandlordPropertyDTO> filteredProperties = [];

      for (var property in _allProperties) {
        // Lọc các phòng bên trong Khu trọ
        List<LandlordRoomDTO> matchedRooms = property.rooms.where((room) {
          bool matchesSearch = room.roomNumber.toLowerCase().contains(query) || property.name.toLowerCase().contains(query);
          if (!matchesSearch) return false;

          if (_filterType == 'RENTED' && room.status != 'RENTED') return false;
          if (_filterType == 'AVAILABLE' && room.status != 'AVAILABLE') return false;

          return true;
        }).toList();

        // Nếu Khu trọ có ít nhất 1 phòng thỏa mãn điều kiện, ta đưa Khu trọ đó vào danh sách hiển thị
        if (matchedRooms.isNotEmpty) {
          // Tạo một property giả chỉ chứa những phòng đã lọc
          filteredProperties.add(
              LandlordPropertyDTO(
                  id: property.id,
                  name: property.name,
                  address: property.address,
                  rooms: matchedRooms
              )
          );
        }
      }

      _displayProperties = filteredProperties;
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ================= DIALOG LỊCH SỬ HÓA ĐƠN =================
  void _showInvoiceHistory(int roomId) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return StatefulBuilder(
              builder: (context, setHistoryState) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.85,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: FutureBuilder<List<InvoiceHistoryResponse>>(
                      future: ServiceRoomAPI.getInvoiceHistory(roomId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text("Lỗi: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
                        }

                        List<InvoiceHistoryResponse> historyList = snapshot.data ?? [];

                        return Column(
                          children: [
                            const SizedBox(height: 16),
                            Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                            const SizedBox(height: 16),
                            const Text("Lịch Sử Hóa Đơn", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const Divider(height: 30),

                            if (historyList.isEmpty)
                              const Expanded(child: Center(child: Text("Chưa có hóa đơn nào cho phòng này!"))),

                            if (historyList.isNotEmpty)
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: historyList.length,
                                  itemBuilder: (ctx, index) {
                                    var invoice = historyList[index];
                                    bool isPaid = invoice.status == 'PAID';

                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(color: isPaid ? Colors.green.shade200 : Colors.red.shade200, width: 1.5)
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text("Kỳ hóa đơn: ${invoice.billingCycle}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(color: isPaid ? Colors.green : Colors.red, borderRadius: BorderRadius.circular(6)),
                                                  child: Text(isPaid ? "Đã thu" : "Đang nợ", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                )
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text("Chốt số: ${invoice.readingDate ?? '---'} | Hạn nộp: ${invoice.dueDate ?? '---'}"),
                                            Text("Sử dụng: ${invoice.electricUsage ?? 0} điện - ${invoice.waterUsage ?? 0} nước", style: TextStyle(color: Colors.grey.shade700)),
                                            const Divider(),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(formatCurrency.format(invoice.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                                if (!isPaid)
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                                    onPressed: () {
                                                      showDialog(
                                                          context: context,
                                                          builder: (ctxConfirm) => AlertDialog(
                                                            title: const Text("Xác nhận thu tiền mặt?"),
                                                            content: const Text("Xác nhận khách đã đóng đủ số tiền này bằng tiền mặt?"),
                                                            actions: [
                                                              TextButton(onPressed: () => Navigator.pop(ctxConfirm), child: const Text("Hủy")),
                                                              ElevatedButton(
                                                                  onPressed: () async {
                                                                    Navigator.pop(ctxConfirm);
                                                                    try {
                                                                      await ServiceRoomAPI.confirmCashPayment(invoice.invoiceId);
                                                                      _showSnackBar("Thu tiền thành công!", Colors.green);
                                                                      setHistoryState(() {});
                                                                      _refreshBillingOnly(); // Load lại data bên ngoài
                                                                    } catch (e) {
                                                                      _showSnackBar(e.toString(), Colors.red);
                                                                    }
                                                                  },
                                                                  child: const Text("Xác nhận")
                                                              )
                                                            ],
                                                          )
                                                      );
                                                    },
                                                    child: const Text("Thu Tiền Mặt", style: TextStyle(color: Colors.white)),
                                                  )
                                              ],
                                            ),
                                          ],
                                        ),
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
    );
  }

  void _showServiceBottomSheet(int roomId, String roomNumber, String propertyName, double roomPrice) {
    Key futureBuilderKey = UniqueKey();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {

              Future<RoomBillingSummary?> loadSummary() async {
                try {
                  return await ServiceRoomAPI.getRoomBillingSummary(roomId);
                } catch (e) {
                  _showSnackBar(e.toString(), Colors.red);
                  return null;
                }
              }

              void reloadData() {
                setModalState(() {
                  futureBuilderKey = UniqueKey();
                });
                _refreshBillingOnly();
              }

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: DraggableScrollableSheet(
                    initialChildSize: 0.8,
                    minChildSize: 0.5,
                    maxChildSize: 0.95,
                    expand: false,
                    builder: (_, controller) {
                      return FutureBuilder<RoomBillingSummary?>(
                        key: futureBuilderKey,
                        future: loadSummary(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
                          }
                          if (!snapshot.hasData) {
                            return const Center(child: Text("Không tải được dữ liệu dịch vụ."));
                          }

                          RoomBillingSummary summary = snapshot.data!;
                          bool isPaid = summary.isPaidThisMonth;
                          bool hasTenant = summary.tenantName != "Phòng trống";
                          bool isBilled = summary.totalAmount > 0; // Ktra xem đã chốt số hay chưa
                          double grandTotal = isBilled ? summary.totalAmount : roomPrice;

                          return Column(
                            children: [
                              const SizedBox(height: 16),
                              Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text("$propertyName - P.$roomNumber", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                                  const SizedBox(width: 10),
                                  // NÚT LỊCH SỬ HÓA ĐƠN
                                  IconButton(
                                    icon: const Icon(Icons.history_edu, color: Colors.orange),
                                    tooltip: "Lịch sử hóa đơn",
                                    onPressed: () => _showInvoiceHistory(roomId),
                                  )
                                ],
                              ),
                              const SizedBox(height: 10),

                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 20),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  // Nếu chưa chốt hóa đơn HOẶC đã chốt nhưng chưa nộp -> Đỏ
                                  color: hasTenant ? ((isPaid && isBilled) ? Colors.green.shade50 : Colors.red.shade50) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: hasTenant ? ((isPaid && isBilled) ? Colors.green.shade300 : Colors.red.shade300) : Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: hasTenant ? ((isPaid && isBilled) ? Colors.green : Colors.red) : Colors.grey,
                                      child: Icon(hasTenant ? ((isPaid && isBilled) ? Icons.check : Icons.warning_amber) : Icons.person_off, color: Colors.white),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(summary.tenantName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),

                                          if (hasTenant && isBilled)
                                            Text("Hóa đơn tháng này: ${formatCurrency.format(grandTotal)}", style: const TextStyle(fontSize: 13, color: Colors.black87)),

                                          Text(
                                            hasTenant
                                                ? (isBilled
                                                ? (isPaid ? "Đã thanh toán đủ" : "Đang nợ tiền hóa đơn")
                                                : "Phòng này CHƯA CHỐT SỐ tháng này!")
                                                : "Chưa có người thuê",
                                            style: TextStyle(color: hasTenant ? ((isPaid && isBilled) ? Colors.green.shade700 : Colors.red.shade700) : Colors.grey, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              const Divider(height: 25),

                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Chi tiết các khoản phí:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                      onPressed: () => _showRecordUtilityDialog(context, roomId, summary, roomPrice, reloadData),
                                      icon: const Icon(Icons.bolt, size: 18, color: Colors.white),
                                      label: const Text("Chốt Số & Ra Bill", style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),

                              Expanded(
                                child: ListView(
                                  controller: controller,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  children: [
                                    Card(
                                      elevation: 0,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      color: Colors.blue.shade50,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.blue.shade200)),
                                      child: ListTile(
                                        leading: const Icon(Icons.home, color: Colors.blueAccent),
                                        title: const Text("Tiền thuê phòng", style: TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: const Text("Phí cố định hàng tháng", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                        trailing: Text(
                                          formatCurrency.format(roomPrice),
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent),
                                        ),
                                      ),
                                    ),
                                    if (summary.services.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 20),
                                        child: Center(child: Text("Phòng chưa cài đặt thêm dịch vụ.", style: TextStyle(color: Colors.grey.shade500))),
                                      ),

                                    ...summary.services.map((service) {
                                      String subtitleText = "Đơn giá: ${formatCurrency.format(service.appliedPrice)} / ${service.unit}";
                                      String trailingText = "";

                                      if (service.serviceName.toLowerCase() == 'điện' && summary.electricUsage != null) {
                                        subtitleText += "\nSử dụng: ${summary.electricUsage} ${service.unit}";
                                        trailingText = formatCurrency.format(summary.electricTotal ?? 0);
                                      }
                                      else if (service.serviceName.toLowerCase() == 'nước' && summary.waterUsage != null) {
                                        subtitleText += "\nSử dụng: ${summary.waterUsage} ${service.unit}";
                                        trailingText = formatCurrency.format(summary.waterTotal ?? 0);
                                      }

                                      return Card(
                                        elevation: 0,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
                                        child: ListTile(
                                          leading: Icon(
                                            service.serviceName.toLowerCase().contains('điện') || service.serviceName.toLowerCase().contains('nước')
                                                ? Icons.electric_meter
                                                : Icons.room_service,
                                            color: Colors.blueAccent,
                                          ),
                                          title: Text(service.serviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          subtitle: Text(
                                              subtitleText,
                                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4)
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (trailingText.isNotEmpty)
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 8.0),
                                                  child: Text(trailingText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 20),
                                                onPressed: () => _showEditPriceDialog(context, service, reloadData),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                                                onPressed: () => _confirmDeleteService(context, service.roomServiceId, reloadData),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),

                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.green.shade300, width: 1.5),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("TỔNG CỘNG THÁNG NÀY:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                    Text(formatCurrency.format(grandTotal), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Colors.green.shade700)),
                                  ],
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                    onPressed: () => _showAddServiceDialog(context, roomId, reloadData),
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                                    label: const Text("Thêm dịch vụ khác", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                ),
                              )
                            ],
                          );
                        },
                      );
                    }
                ),
              );
            }
        );
      },
    );
  }

  // ================= DIALOG LẬP HÓA ĐƠN VÀ CHỐT SỐ =================
  void _showRecordUtilityDialog(BuildContext context, int roomId, RoomBillingSummary summary, double currentRoomPrice, VoidCallback refreshBottomSheet) {
    RoomServiceResponse? elecService;
    RoomServiceResponse? waterService;

    for (var s in summary.services) {
      if (s.serviceName.toLowerCase().contains('điện')) elecService = s;
      if (s.serviceName.toLowerCase().contains('nước')) waterService = s;
    }

    final roomPriceController = TextEditingController(text: currentRoomPrice.toStringAsFixed(0));
    final elecPriceController = TextEditingController(text: elecService?.appliedPrice.toStringAsFixed(0) ?? '4000');
    final waterPriceController = TextEditingController(text: waterService?.appliedPrice.toStringAsFixed(0) ?? '25000');

    final oldElecController = TextEditingController(text: summary.lastElectricity?.toString() ?? '');
    final newElecController = TextEditingController();
    final oldWaterController = TextEditingController(text: summary.lastWater?.toString() ?? '');
    final newWaterController = TextEditingController();

    final now = DateTime.now();
    String currentMonthYear = "${now.month.toString().padLeft(2, '0')}-${now.year}";
    final cycleController = TextEditingController(text: currentMonthYear);

    DateTime readingDate = now;
    DateTime dueDate = now.add(const Duration(days: 30));

    bool isReset = false;
    XFile? selectedImage;
    final picker = ImagePicker();

    String formatDateForApi(DateTime date) => "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
    String formatDisplay(DateTime date) => "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: const Text("Lập Hóa Đơn & Chốt Số", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: cycleController,
                        decoration: const InputDecoration(labelText: "Kỳ hóa đơn (MM-YYYY)"),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("📅 Ngày chốt số:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(context: context, initialDate: readingDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                                    if (picked != null) setStateDialog(() => readingDate = picked);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(6)),
                                    child: Text(formatDisplay(readingDate)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("⏳ Hạn nộp tiền:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13)),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(context: context, initialDate: dueDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                                    if (picked != null) setStateDialog(() => dueDate = picked);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(border: Border.all(color: Colors.red.shade200), borderRadius: BorderRadius.circular(6)),
                                    child: Text(formatDisplay(dueDate)),
                                  ),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                      const Divider(height: 30, thickness: 1),

                      const Text("🏠 Tiền thuê phòng (Cố định):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      TextField(
                        controller: roomPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: "Nhập giá phòng", prefixText: "₫ "),
                      ),
                      const SizedBox(height: 16),

                      const Text("⚡ Điện (kWh):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: oldElecController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Số cũ"))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: newElecController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Số mới"))),
                        ],
                      ),
                      TextField(
                        controller: elecPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Giá điện / kWh", prefixText: "₫ ", isDense: true),
                      ),
                      const SizedBox(height: 16),

                      const Text("💧 Nước (Khối):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: oldWaterController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Số cũ"))),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(controller: newWaterController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Số mới"))),
                        ],
                      ),
                      TextField(
                        controller: waterPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Giá nước / Khối", prefixText: "₫ ", isDense: true),
                      ),
                      const SizedBox(height: 12),

                      CheckboxListTile(
                        title: const Text("Đồng hồ quay vòng (Reset)?", style: TextStyle(fontSize: 13)),
                        value: isReset,
                        onChanged: (val) => setStateDialog(() => isReset = val ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),

                      const SizedBox(height: 10),
                      const Text("📷 Ảnh minh chứng công tơ:", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black87),
                            onPressed: () async {
                              final pickedFile = await picker.pickImage(source: ImageSource.camera);
                              if (pickedFile != null) setStateDialog(() => selectedImage = pickedFile);
                            },
                            icon: const Icon(Icons.camera_alt),
                            label: const Text("Chụp ảnh"),
                          ),
                          const SizedBox(width: 10),
                          if (selectedImage != null)
                            const Text("Đã chụp ✓", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                          else
                            const Text("Chưa có ảnh!", style: TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () async {
                    if (selectedImage == null) {
                      _showSnackBar("Bắt buộc phải chụp ảnh công tơ!", Colors.red);
                      return;
                    }

                    String oldE = oldElecController.text.trim();
                    String newE = newElecController.text.trim();
                    String oldW = oldWaterController.text.trim();
                    String newW = newWaterController.text.trim();

                    if (oldE.isEmpty || newE.isEmpty || oldW.isEmpty || newW.isEmpty) {
                      _showSnackBar("Vui lòng nhập đầy đủ số điện/nước!", Colors.red);
                      return;
                    }

                    Navigator.pop(ctx);

                    try {
                      RecordUtilityRequest req = RecordUtilityRequest(
                        billingCycle: cycleController.text.trim(),
                        readingDate: formatDateForApi(readingDate),
                        dueDate: formatDateForApi(dueDate),
                        newRoomPrice: double.tryParse(roomPriceController.text.trim()),
                        newElecPrice: double.tryParse(elecPriceController.text.trim()),
                        newWaterPrice: double.tryParse(waterPriceController.text.trim()),
                        oldElectricity: int.tryParse(oldE) ?? 0,
                        newElectricity: int.tryParse(newE) ?? 0,
                        oldWater: int.tryParse(oldW) ?? 0,
                        newWater: int.tryParse(newW) ?? 0,
                        isMeterReset: isReset,
                      );

                      UtilityReadingResponse res = await ServiceRoomAPI.recordUtility(roomId, req, selectedImage!);

                      _showSnackBar("Đã lưu Hóa Đơn! Tổng cộng: ${formatCurrency.format(res.grandTotal)}", Colors.green);
                      refreshBottomSheet();
                    } catch (e) {
                      _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
                    }
                  },
                  child: const Text("Lưu Hóa Đơn", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _showAddServiceDialog(BuildContext context, int roomId, VoidCallback refreshBottomSheet) async {
    List<CatalogResponse> catalog = [];
    try {
      catalog = await ServiceRoomAPI.getCatalog();
    } catch (e) {
      _showSnackBar(e.toString(), Colors.red);
      return;
    }

    if (!context.mounted) return;

    int? selectedServiceId;
    final priceController = TextEditingController();

    showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
              builder: (ctx, setStateDialog) {
                return AlertDialog(
                  title: const Text("Thêm Dịch Vụ", style: TextStyle(color: Colors.blueAccent)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(labelText: "Chọn loại dịch vụ", border: OutlineInputBorder()),
                        items: catalog.map((s) => DropdownMenuItem(value: s.id, child: Text("${s.name} (${s.unit})"))).toList(),
                        onChanged: (val) {
                          setStateDialog(() {
                            selectedServiceId = val;
                            priceController.text = catalog.firstWhere((e) => e.id == val).defaultPrice.toStringAsFixed(0);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Giá áp dụng (VNĐ)", border: OutlineInputBorder()),
                      )
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      onPressed: () async {
                        if (selectedServiceId == null) {
                          _showSnackBar("Vui lòng chọn dịch vụ", Colors.orange);
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          AssignRequest req = AssignRequest(serviceId: selectedServiceId!, customPrice: double.tryParse(priceController.text));
                          String msg = await ServiceRoomAPI.assignService(roomId, req);
                          _showSnackBar(msg, Colors.green);
                          refreshBottomSheet();
                        } catch (e) {
                          _showSnackBar(e.toString().replaceAll("Exception: ", ""), Colors.red);
                        }
                      },
                      child: const Text("Thêm", style: TextStyle(color: Colors.white)),
                    )
                  ],
                );
              }
          );
        }
    );
  }

  void _showEditPriceDialog(BuildContext context, RoomServiceResponse service, VoidCallback refreshBottomSheet) {
    final priceController = TextEditingController(text: service.appliedPrice.toStringAsFixed(0));
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("Đổi giá ${service.serviceName}"),
          content: TextField(
            controller: priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Giá mới (VNĐ)", border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  String msg = await ServiceRoomAPI.updateCustomPrice(service.roomServiceId, double.tryParse(priceController.text));
                  _showSnackBar(msg, Colors.green);
                  refreshBottomSheet();
                } catch (e) {
                  _showSnackBar(e.toString(), Colors.red);
                }
              },
              child: const Text("Lưu"),
            )
          ],
        )
    );
  }

  void _confirmDeleteService(BuildContext context, int roomServiceId, VoidCallback refreshBottomSheet) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Hủy Dịch Vụ?", style: TextStyle(color: Colors.red)),
          content: const Text("Bạn có chắc muốn xóa dịch vụ này khỏi phòng?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  String msg = await ServiceRoomAPI.removeService(roomServiceId);
                  _showSnackBar(msg, Colors.green);
                  refreshBottomSheet();
                } catch (e) {
                  _showSnackBar(e.toString(), Colors.red);
                }
              },
              child: const Text("Xóa", style: TextStyle(color: Colors.white)),
            )
          ],
        )
    );
  }

  // ================= UI DANH SÁCH NHÓM THEO KHU TRỌ =================
  Widget _buildPropertyList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
    if (_errorMessage.isNotEmpty) return Center(child: Text("Lỗi: $_errorMessage", style: const TextStyle(color: Colors.red)));
    if (_displayProperties.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.home_work, size: 80, color: Colors.grey.shade300), const SizedBox(height: 16), const Text("Không tìm thấy khu trọ / phòng nào", style: TextStyle(color: Colors.grey))]));

    return RefreshIndicator(
      onRefresh: _fetchPropertiesAndBillingInfo,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 10, bottom: 90, left: 16, right: 16),
        itemCount: _displayProperties.length,
        itemBuilder: (context, propertyIndex) {
          final property = _displayProperties[propertyIndex];

          // Kiểm tra xem trong khu trọ này có phòng nào (đang thuê) mà CÒN NỢ hoặc CHƯA CHỐT SỐ không?
          bool hasDebtOrUnbilled = false;
          for (var r in property.rooms) {
            if (r.status == 'RENTED') {
              var summary = _roomBillingMap[r.id];
              if (summary == null || summary.totalAmount == 0 || !summary.isPaidThisMonth) {
                hasDebtOrUnbilled = true;
                break; // Chỉ cần 1 phòng vi phạm là đỏ cả khu
              }
            }
          }

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                // TÔ ĐỎ KHU TRỌ NẾU CÓ PHÒNG NỢ / CHƯA CHỐT SỐ
                side: BorderSide(color: hasDebtOrUnbilled ? Colors.red.shade300 : Colors.blue.shade200, width: 1.5)
            ),
            child: ExpansionTile(
              initiallyExpanded: true, // Mặc định mở
              backgroundColor: hasDebtOrUnbilled ? Colors.red.shade50 : Colors.white,
              collapsedBackgroundColor: hasDebtOrUnbilled ? Colors.red.shade50 : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: CircleAvatar(
                backgroundColor: hasDebtOrUnbilled ? Colors.red.shade100 : Colors.blue.shade50,
                child: Icon(Icons.maps_home_work, color: hasDebtOrUnbilled ? Colors.red : Colors.blueAccent),
              ),
              title: Text(
                  property.name,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: hasDebtOrUnbilled ? Colors.red.shade700 : Colors.black87)
              ),
              subtitle: Text(property.address, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),

              // ================= HIỂN THỊ DANH SÁCH TỪNG PHÒNG =================
              children: property.rooms.map((room) {
                bool isRented = room.status == 'RENTED';
                double roomPrice = double.tryParse(room.basePrice.toString()) ?? 0.0;

                // Trạng thái cụ thể của từng phòng
                var roomSum = _roomBillingMap[room.id];
                bool roomHasDebtOrUnbilled = isRented && (roomSum == null || roomSum.totalAmount == 0 || !roomSum.isPaidThisMonth);

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), // Khoảng cách giữa các phòng
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300, width: 1), // VIỀN BỌC QUANH PHÒNG
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 3, offset: const Offset(0, 2))
                      ]
                  ),
                  child: ListTile(
                    // BẤM VÀO BẤT CỨ ĐÂU CỦA PHÒNG NÀY ĐỀU SẼ MỞ BOTTOM SHEET
                    onTap: () => _showServiceBottomSheet(room.id!, room.roomNumber, property.name, roomPrice),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: isRented ? (roomHasDebtOrUnbilled ? Colors.red.shade50 : Colors.green.shade50) : Colors.grey.shade100,
                      child: Icon(Icons.meeting_room, color: isRented ? (roomHasDebtOrUnbilled ? Colors.red : Colors.green) : Colors.grey),
                    ),
                    title: Text("Phòng ${room.roomNumber}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(
                        isRented
                            ? (roomSum == null ? "Đang tải..." : (roomSum.totalAmount == 0 ? "Chưa chốt số" : (roomSum.isPaidThisMonth ? "Đã thanh toán" : "Đang nợ tiền")))
                            : "Phòng trống",
                        style: TextStyle(color: isRented ? (roomHasDebtOrUnbilled ? Colors.red : Colors.green) : Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)
                    ),
                    trailing: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: isRented ? Colors.blueAccent : Colors.grey,
                          side: BorderSide(color: isRented ? Colors.blueAccent : Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                      ),
                      // Nút Cài đặt cũng giữ nguyên chức năng mở
                      onPressed: () => _showServiceBottomSheet(room.id!, room.roomNumber, property.name, roomPrice),
                      child: const Text("Cài đặt", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
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
                        hintText: "Tìm phòng/khu trọ...",
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
                          DropdownMenuItem(value: 'RENTED', child: Text("Đang thuê", style: TextStyle(color: Colors.blueAccent))),
                          DropdownMenuItem(value: 'AVAILABLE', child: Text("Phòng trống", style: TextStyle(color: Colors.grey))),
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
          Expanded(child: _buildPropertyList()),
        ],
      ),
    );
  }
}