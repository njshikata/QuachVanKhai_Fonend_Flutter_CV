import 'package:flutter/material.dart';

class Navbar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const Navbar({super.key, required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18, // Thu nhỏ chữ xuống một chút để vừa màn hình
        ),
        overflow: TextOverflow.ellipsis, // Nếu chữ dài quá sẽ tự biến thành "..."
        maxLines: 1, // Ép chữ chỉ nằm trên 1 dòng duy nhất
      ),
      backgroundColor: Colors.blueAccent,
      centerTitle: true,
      elevation: 0,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}