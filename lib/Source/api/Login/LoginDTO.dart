// 1. Dữ liệu gửi lên khi Đăng nhập (Request)
class LoginRequest {
  String email;
  String password;
  String? fcmToken; // THÊM TRƯỜNG NÀY ĐỂ NHẬN TOKEN FCM

  LoginRequest({required this.email, required this.password, this.fcmToken});

  // Chuyển Object thành chuỗi JSON để gửi qua HTTP
  Map<String, dynamic> toJson() {
    return {
      "email": email,
      "password": password,
      "fcmToken": fcmToken, // ĐƯA VÀO JSON
    };
  }
}

// 2. Dữ liệu nhận về sau khi Đăng nhập thành công (Response)
class LoginResponse {
  String token;
  String type;
  String email;
  String role;
  String fullName;

  LoginResponse({
    required this.token,
    required this.type,
    required this.email,
    required this.role,
    required this.fullName,
  });

  // Chuyển chuỗi JSON từ Spring Boot thành Object Dart
  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] ?? '',
      type: json['type'] ?? 'Bearer',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      fullName: json['fullName'] ?? '',
    );
  }
}