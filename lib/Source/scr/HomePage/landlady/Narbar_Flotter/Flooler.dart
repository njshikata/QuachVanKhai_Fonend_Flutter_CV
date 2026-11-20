import 'package:flutter/material.dart';

class Footer extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const Footer({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      selectedItemColor: Colors.blueAccent, // Màu khi được chọn
      unselectedItemColor: Colors.grey,     // Màu khi không được chọn
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed, // 5 mục -> giữ nguyên nền, không bị kiểu "shifting"
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.apartment),
          label: 'Nhà trọ',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_customize),
          label: 'Dịch vụ',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people_alt),
          label: 'Người dùng',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.credit_card),
          label: 'Thẻ',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Cài đặt',
        ),
      ],
    );
  }
}