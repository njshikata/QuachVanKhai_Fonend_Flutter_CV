// Đường dẫn: lib/Source/api/Property/PropertyDTO.dart

// 1. DTO Khách thuê
class LandlordTenantDTO {
  final int id;
  final String fullName;
  final String phoneNumber;
  final String email;

  LandlordTenantDTO({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.email,
  });

  factory LandlordTenantDTO.fromJson(Map<String, dynamic> json) {
    return LandlordTenantDTO(
      id: json['id'] ?? 0,
      fullName: json['fullName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'] ?? '',
    );
  }
}

// 2. DTO Phòng trọ
class LandlordRoomDTO {
  final int id;
  final String roomNumber;
  final double basePrice;
  final String status;
  final LandlordTenantDTO? currentTenant; // Có thể null nếu phòng trống

  LandlordRoomDTO({
    required this.id,
    required this.roomNumber,
    required this.basePrice,
    required this.status,
    this.currentTenant,
  });

  factory LandlordRoomDTO.fromJson(Map<String, dynamic> json) {
    return LandlordRoomDTO(
      id: json['id'] ?? 0,
      roomNumber: json['roomNumber'] ?? '',
      basePrice: (json['basePrice'] ?? 0).toDouble(),
      status: json['status'] ?? 'UNKNOWN',
      currentTenant: json['currentTenant'] != null
          ? LandlordTenantDTO.fromJson(json['currentTenant'])
          : null,
    );
  }
}

// 3. DTO Khu trọ (Bọc ngoài cùng)
class LandlordPropertyDTO {
  final int id;
  final String name;
  final String address;
  final List<LandlordRoomDTO> rooms;

  LandlordPropertyDTO({
    required this.id,
    required this.name,
    required this.address,
    required this.rooms,
  });

  factory LandlordPropertyDTO.fromJson(Map<String, dynamic> json) {
    var roomList = json['rooms'] as List? ?? [];
    List<LandlordRoomDTO> roomsData = roomList.map((i) => LandlordRoomDTO.fromJson(i)).toList();

    return LandlordPropertyDTO(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      rooms: roomsData,
    );
  }
}