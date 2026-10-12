// Đường dẫn: lib/Source/scr/HomePage/landlady/LandladyScreen.dart

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Narbar_Flotter/Flooler.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Narbar_Flotter/Narbar.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/ServiceRoom/ServiceRoomScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/room/Dashboard_Properti_Screen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Tab/TabUser/Manage_User_Screen.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';
import '../../Login/LoginScreen.dart';

class LandladyScreen extends StatefulWidget {
  const LandladyScreen({super.key});

  @override
  State<LandladyScreen> createState() => _LandladyScreenState();
}

class _LandladyScreenState extends State<LandladyScreen> {
  int _selectedIndex = 0;

  // ĐÃ CẬP NHẬT 4 TIÊU ĐỀ
  final List<String> _titles = [
    "Danh sách Nhà Trọ",
    "Quản Lý Dịch Vụ",     // Tab mới
    "Quản Lý Người Dùng",  // Bị đẩy xuống số 3
    "Cài Đặt Hệ Thống"
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildSettingsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.settings, size: 80, color: Colors.grey),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () async {
              await Security.logout();
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text("Đăng xuất", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ĐÃ CẬP NHẬT 4 MÀN HÌNH TƯƠNG ỨNG
    final List<Widget> screens = [
      const DashboardPropertiScreen(),
      const ServiceRoomScreen(),       // Màn hình Dịch vụ ở vị trí index = 1
      const ManageUserScreen(),
      _buildSettingsTab(),
    ];

    return Scaffold(
      appBar: Navbar(title: _titles[_selectedIndex]),
      body: screens[_selectedIndex],
      bottomNavigationBar: Footer(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}