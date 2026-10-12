// Đường dẫn: lib/Source/scr/HomePage/landlady/Add_Room_Screen.dart

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/Property/LandlordManage/LandlordManageAPI.dart';
import 'package:qlpt_frontend/Source/api/Property/LandlordManage/LandlordManageDTO.dart';
// Đã sửa lại đường dẫn import chuẩn

class AddRoomScreen extends StatefulWidget {
  final int propertyId;
  final String propertyName;

  const AddRoomScreen({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  @override
  State<AddRoomScreen> createState() => _AddRoomScreenState();
}

class _AddRoomScreenState extends State<AddRoomScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _roomNumberController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _amenitiesController = TextEditingController();

  bool _isLoading = false;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; });

    try {
      var request = CreateRoomRequest(
        propertyId: widget.propertyId,
        roomNumber: _roomNumberController.text.trim(),
        area: double.parse(_areaController.text.trim()),
        maxCapacity: int.parse(_capacityController.text.trim()),
        basePrice: double.parse(_priceController.text.trim()),
        amenities: _amenitiesController.text.trim(),
      );

      String resultMsg = await LandlordManageAPI.createRoom(request);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(resultMsg, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        // Cắt bỏ chữ "Exception: " của Dart để lấy thông báo chuẩn từ Backend (Ví dụ: "Lỗi: Số phòng [101] đã tồn tại...")
        String errorMsg = e.toString().replaceAll("Exception: ", "");

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(errorMsg, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blueAccent),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Vui lòng nhập $label';
          if (isNumber && double.tryParse(value) == null) return 'Phải là chữ số hợp lệ';
          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text("Thêm phòng - ${widget.propertyName}",
            style: const TextStyle(color: Colors.white, fontSize: 18)
        ),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Đang thêm phòng cho khu trọ:\n👉 ${widget.propertyName}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
              ),
              const SizedBox(height: 20),

              _buildTextField(controller: _roomNumberController, label: "Số / Tên phòng (VD: 101)", icon: Icons.meeting_room),

              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _areaController, label: "Diện tích (m2)", icon: Icons.straighten, isNumber: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildTextField(controller: _capacityController, label: "Số người tối đa", icon: Icons.group, isNumber: true)),
                ],
              ),

              _buildTextField(controller: _priceController, label: "Giá phòng (VNĐ/Tháng)", icon: Icons.attach_money, isNumber: true),
              _buildTextField(controller: _amenitiesController, label: "Tiện ích (VD: Điều hòa, Máy giặt)", icon: Icons.kitchen),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _submitForm,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("TẠO PHÒNG TRỌ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}