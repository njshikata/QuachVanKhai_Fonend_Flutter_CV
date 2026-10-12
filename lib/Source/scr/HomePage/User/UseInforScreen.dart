// Đường dẫn: lib/Source/scr/HomePage/User/UseInforScreen.dart

import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/api/User/Infor/InforAPI.dart';
import 'package:qlpt_frontend/Source/api/User/Infor/InforDTO.dart';
import 'package:qlpt_frontend/Source/scr/Login/LoginScreen.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';

class UseInforScreen extends StatefulWidget {
  const UseInforScreen({super.key});

  @override
  State<UseInforScreen> createState() => _UseInforScreenState();
}

class _UseInforScreenState extends State<UseInforScreen> {

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfileResponse>(
      future: InforAPI.getMyProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.green));
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text("Lỗi tải thông tin:\n${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
            ),
          );
        }

        UserProfileResponse? profile = snapshot.data;
        if (profile == null) {
          return const Center(child: Text("Không có thông tin cá nhân."));
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Khối Avatar
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green.shade200, width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.green.shade100,
                      child: Text(
                        profile.fullName.isNotEmpty ? profile.fullName[0].toUpperCase() : "U",
                        style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(profile.fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                  child: const Text("Khách Thuê", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),

                const SizedBox(height: 30),

                // Khối Thông tin
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow(Icons.email_outlined, "Email liên hệ", profile.email),
                      const Divider(height: 1),
                      _buildInfoRow(Icons.phone_android, "Số điện thoại", profile.phoneNumber),
                      const Divider(height: 1),
                      _buildInfoRow(Icons.badge_outlined, "CCCD / CMND", profile.identityNumber ?? "Chưa cập nhật"),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Nút Đăng xuất
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.red.shade400,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      await Security.logout();
                      if (context.mounted) {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text("ĐĂNG XUẤT", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}