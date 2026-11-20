// Đường dẫn: lib/Source/scr/HomePage/landlady/LandladyScreen.dart

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/perf/PerfLabScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Narbar_Flotter/Flooler.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/Narbar_Flotter/Narbar.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/ServiceRoom/ServiceRoomScreen.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/landlady/SmartCard/SmartCardScreen.dart';
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

  final List<String> _titles = const [
    "Danh sách Nhà Trọ",
    "Quản Lý Dịch Vụ",
    "Quản Lý Người Dùng",
    "Thẻ Thông Minh",
    "Cài Đặt Hệ Thống"
  ];

  // Khởi tạo 1 lần duy nhất trong initState để không bị tạo mới lại khi build()
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const DashboardPropertiScreen(),
      const ServiceRoomScreen(),
      const ManageUserScreen(),
      const SmartCardScreen(embedded: true),
      _buildSettingsTab(),
    ];
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
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
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfLabScreen())),
            icon: const Icon(Icons.speed),
            label: const Text("Hiệu năng & Demo"),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          ),
          const SizedBox(height: 16),
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
    return Scaffold(
      appBar: Navbar(title: _titles[_selectedIndex]),
      // IndexedStack giúp giữ nguyên state và vị trí cuộn của các tab
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Footer(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}