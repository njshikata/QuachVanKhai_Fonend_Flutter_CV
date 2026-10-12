// Đường dẫn: lib/Source/api/User/Total/InforDTO.dart

class UserProfileResponse {
  int id;
  String email;
  String fullName;
  String phoneNumber;
  String? identityNumber;
  String? avatarUrl;
  String role;
  String status;

  UserProfileResponse({
    required this.id,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    this.identityNumber,
    this.avatarUrl,
    required this.role,
    required this.status,
  });

  factory UserProfileResponse.fromJson(Map<String, dynamic> json) {
    return UserProfileResponse(
      id: json['id'],
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? 'Chưa cập nhật tên',
      phoneNumber: json['phoneNumber'] ?? 'Chưa cập nhật SĐT',
      identityNumber: json['identityNumber'],
      avatarUrl: json['avatarUrl'],
      role: json['role'] ?? 'TENANT',
      status: json['status'] ?? 'ACTIVE',
    );
  }
}