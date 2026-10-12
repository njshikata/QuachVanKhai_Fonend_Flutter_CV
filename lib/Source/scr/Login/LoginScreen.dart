import 'package:flutter/material.dart';
import 'package:qlpt_frontend/Source/scr/HomePage/User/UseScreen.dart';
import '../../api/Login/LoginAPI.dart';
import '../../security/Security.dart';
import '../HomePage/landlady/landladyScreen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Các Controller để lấy dữ liệu từ Text Field
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isPasswordVisible = false; // Trạng thái ẩn/hiện mật khẩu
  bool _isLoading = false; // Trạng thái đang gọi API (Hiển thị loading)
  String _errorMessage = ""; // Chứa thông báo lỗi từ Server

  // Hàm xử lý khi bấm nút Đăng Nhập
  Future<void> _handleLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    // Validate dữ liệu trống
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Vui lòng nhập đầy đủ Email và Mật khẩu!";
      });
      return;
    }

    // Bắt đầu Loading
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    // Gọi API từ thư mục API
    String result = await LoginAPI.login(email, password);

    // Dừng Loading
    setState(() {
      _isLoading = false;
    });

    if (result == "SUCCESS") {
      // Đăng nhập thành công, lấy quyền (Role) để điều hướng
      String? role = await Security.getRole();

      // Kiểm tra widget còn tồn tại trước khi dùng BuildContext (chuẩn Flutter lints)
      if (!context.mounted) return;

      // Hiển thị thông báo đăng nhập thành công
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Đăng nhập thành công với quyền $role!"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Điều hướng dựa trên Role
      if (role == "LANDLORD") {
        // Dùng pushReplacement để xóa màn hình Login khỏi ngăn xếp (bấm Back không quay lại được)
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LandladyScreen())
        );
      } else if (role == "TENANT") {
        // --- SỬA Ở ĐÂY: Điều hướng sang UserScreen ---
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const UserScreen())
        );
      }

    } else {
      // Đăng nhập thất bại (Sai pass, lỗi mạng...), hiển thị lỗi lên UI
      setState(() {
        _errorMessage = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView( // Giúp cuộn màn hình khi bàn phím bật lên
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, // Căng ngang các widget
            children: [
              const SizedBox(height: 40),

              // 1. Tiêu đề Logo
              const Icon(Icons.home_work_rounded, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 16),
              const Text(
                "Quản Lý Phòng Trọ",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Đăng nhập để tiếp tục",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 50),

              // 2. Ô nhập Email
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email",
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. Ô nhập Mật khẩu (Có nút ẩn/hiện)
              TextField(
                controller: _passwordController,
                obscureText: !_isPasswordVisible,
                decoration: InputDecoration(
                  labelText: "Mật khẩu",
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 4. Quên mật khẩu
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // TODO: Mở trang quên mật khẩu
                  },
                  child: const Text("Quên mật khẩu?"),
                ),
              ),

              // 5. Hiển thị Lỗi (Nếu có)
              if (_errorMessage.isNotEmpty) ...[
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 10),

              // 6. Nút Đăng nhập
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                      : const Text(
                    "ĐĂNG NHẬP",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 7. Chuyển sang Đăng ký
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Chưa có tài khoản?"),
                  TextButton(
                    onPressed: () {
                      // TODO: Mở trang Đăng ký
                    },
                    child: const Text(
                      "Đăng ký ngay",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}