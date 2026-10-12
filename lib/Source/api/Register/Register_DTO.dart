// Đường dẫn: lib/Source/api/Login/Register_DTO.dart

class RegisterRequest {
  String email;
  String password;
  String fullName;
  String phoneNumber;
  String identityNumber; // CCCD / CMND

  RegisterRequest({
    required this.email,
    required this.password,
    required this.fullName,
    required this.phoneNumber,
    required this.identityNumber,
  });

  // Ép dữ liệu thành JSON để bắn xuống Backend
  Map<String, dynamic> toJson() => {
    "email": email,
    "password": password,
    "fullName": fullName,
    "phoneNumber": phoneNumber,
    "identityNumber": identityNumber,
  };
}