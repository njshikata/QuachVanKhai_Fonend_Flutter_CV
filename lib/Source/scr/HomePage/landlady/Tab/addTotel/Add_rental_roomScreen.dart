// Đường dẫn: lib/Source/scr/HomePage/landlady/Add_rental_roomScreen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/Property/LandlordManage/LandlordManageAPI.dart';
import 'package:qlpt_frontend/Source/api/Property/LandlordManage/LandlordManageDTO.dart';

class AddRentalRoomScreen extends StatefulWidget {
  const AddRentalRoomScreen({super.key});

  @override
  State<AddRentalRoomScreen> createState() => _AddRentalRoomScreenState();
}

class _AddRentalRoomScreenState extends State<AddRentalRoomScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _rulesController = TextEditingController();
  final TextEditingController _billingDayController = TextEditingController();
  final TextEditingController _deadlineDayController = TextEditingController();

  bool _isLoading = false;

  List<dynamic> _provinces = [];
  List<dynamic> _districts = [];
  List<dynamic> _wards = [];

  int? _selectedProvinceCode;
  int? _selectedDistrictCode;
  int? _selectedWardCode;

  String _selectedProvinceName = "";
  String _selectedDistrictName = "";
  String _selectedWardName = "";

  @override
  void initState() {
    super.initState();
    _fetchProvinces();
  }

  // ==================== DÙNG API PHỔ BIẾN NHẤT (OPEN-API) ====================
  Future<void> _fetchProvinces() async {
    try {
      final response = await http.get(Uri.parse('https://provinces.open-api.vn/api/p/'));
      if (response.statusCode == 200) {
        setState(() {
          _provinces = jsonDecode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải Tỉnh/Thành: $e");
    }
  }

  Future<void> _fetchDistricts(int provinceCode) async {
    try {
      final response = await http.get(Uri.parse('https://provinces.open-api.vn/api/p/$provinceCode?depth=2'));
      if (response.statusCode == 200) {
        setState(() {
          _districts = jsonDecode(utf8.decode(response.bodyBytes))['districts'];
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải Quận/Huyện: $e");
    }
  }

  Future<void> _fetchWards(int districtCode) async {
    try {
      final response = await http.get(Uri.parse('https://provinces.open-api.vn/api/d/$districtCode?depth=2'));
      if (response.statusCode == 200) {
        setState(() {
          _wards = jsonDecode(utf8.decode(response.bodyBytes))['wards'];
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải Phường/Xã: $e");
    }
  }
  // ===========================================================================

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; });

    try {
      String fullAddress = "${_streetController.text.trim()}, $_selectedWardName, $_selectedDistrictName, $_selectedProvinceName";

      var request = CreatePropertyRequest(
        name: _nameController.text.trim(),
        address: fullAddress,
        description: _descriptionController.text.trim(),
        rules: _rulesController.text.trim(),
        billingDay: int.parse(_billingDayController.text.trim()),
        paymentDeadlineDay: int.parse(_deadlineDayController.text.trim()),
      );

      String resultMsg = await LandlordManageAPI.createProperty(request);

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
    bool isRequired = true,
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
          if (isRequired && (value == null || value.trim().isEmpty)) {
            return 'Vui lòng nhập $label';
          }
          if (isNumber && value != null && value.isNotEmpty) {
            int? num = int.tryParse(value);
            if (num == null || num < 1 || num > 31) {
              return 'Phải là số từ 1 đến 31';
            }
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required IconData icon,
    required int? value,
    required List<dynamic> items,
    required Function(int?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blueAccent),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        value: value,
        items: items.map((item) {
          return DropdownMenuItem<int>(
            value: item['code'],
            child: Text(item['name'], overflow: TextOverflow.ellipsis),
          );
        }).toList(),
        onChanged: onChanged,
        validator: (val) => val == null ? 'Vui lòng chọn $label' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Thêm Khu Trọ Mới", style: TextStyle(color: Colors.white)),
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
              const Text(
                "Thông tin cơ bản",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const SizedBox(height: 16),

              _buildTextField(controller: _nameController, label: "Tên khu trọ (VD: Trọ Cầu Giấy)", icon: Icons.home),

              const Text(
                "Địa chỉ Khu Trọ",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const SizedBox(height: 10),

              _buildDropdown(
                label: "Tỉnh / Thành phố",
                icon: Icons.map,
                value: _selectedProvinceCode,
                items: _provinces,
                onChanged: (val) {
                  setState(() {
                    _selectedProvinceCode = val;
                    _selectedProvinceName = _provinces.firstWhere((p) => p['code'] == val)['name'];
                    _selectedDistrictCode = null;
                    _selectedWardCode = null;
                    _districts = [];
                    _wards = [];
                  });
                  _fetchDistricts(val!);
                },
              ),

              _buildDropdown(
                label: "Quận / Huyện",
                icon: Icons.location_city,
                value: _selectedDistrictCode,
                items: _districts,
                onChanged: (val) {
                  setState(() {
                    _selectedDistrictCode = val;
                    _selectedDistrictName = _districts.firstWhere((d) => d['code'] == val)['name'];
                    _selectedWardCode = null;
                    _wards = [];
                  });
                  _fetchWards(val!);
                },
              ),

              _buildDropdown(
                label: "Phường / Xã",
                icon: Icons.holiday_village,
                value: _selectedWardCode,
                items: _wards,
                onChanged: (val) {
                  setState(() {
                    _selectedWardCode = val;
                    _selectedWardName = _wards.firstWhere((w) => w['code'] == val)['name'];
                  });
                },
              ),

              _buildTextField(
                  controller: _streetController,
                  label: "Số nhà, tên ngõ/đường",
                  icon: Icons.edit_road
              ),

              const Divider(height: 30),

              Row(
                children: [
                  Expanded(child: _buildTextField(controller: _billingDayController, label: "Ngày chốt tiền (1-31)", icon: Icons.calendar_month, isNumber: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _buildTextField(controller: _deadlineDayController, label: "Hạn đóng (1-31)", icon: Icons.warning_amber, isNumber: true)),
                ],
              ),

              _buildTextField(controller: _descriptionController, label: "Mô tả (Không bắt buộc)", icon: Icons.description, isRequired: false),
              _buildTextField(controller: _rulesController, label: "Nội quy (Không bắt buộc)", icon: Icons.rule, isRequired: false),

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
                      : const Text("LƯU KHU TRỌ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}