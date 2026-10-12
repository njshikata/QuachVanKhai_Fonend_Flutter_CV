// Đường dẫn: lib/Source/api/Manage_User/Manage_User_DTO.dart

class RentedRoomInfo {
  int? roomId;
  String? propertyName;
  String? roomNumber;
  double? price;
  bool? isPaidThisMonth;

  RentedRoomInfo({
    this.roomId,
    this.propertyName,
    this.roomNumber,
    this.price,
    this.isPaidThisMonth
  });

  factory RentedRoomInfo.fromJson(Map<String, dynamic> json) {
    return RentedRoomInfo(
      roomId: json['roomId'],
      propertyName: json['propertyName'],
      roomNumber: json['roomNumber'],
      price: json['price'] != null ? double.parse(json['price'].toString()) : null,
      isPaidThisMonth: json['isPaidThisMonth'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'propertyName': propertyName,
      'roomNumber': roomNumber,
      'price': price,
      'isPaidThisMonth': isPaidThisMonth,
    };
  }
}

// === LỚP DỮ LIỆU MỚI: DÙNG ĐỂ CHỨA LỊCH SỬ KHÁCH THUÊ ===
class TenantHistory {
  int? contractId;
  String? propertyName;
  String? roomNumber;
  String? startDate;
  String? endDate;
  String? contractStatus; // ACTIVE, EXPIRED, TERMINATED
  double? depositAmount;
  int? totalInvoices;
  int? unpaidInvoices;
  double? totalPaidAmount;
  double? totalUnpaidAmount;

  TenantHistory({
    this.contractId,
    this.propertyName,
    this.roomNumber,
    this.startDate,
    this.endDate,
    this.contractStatus,
    this.depositAmount,
    this.totalInvoices,
    this.unpaidInvoices,
    this.totalPaidAmount,
    this.totalUnpaidAmount,
  });

  factory TenantHistory.fromJson(Map<String, dynamic> json) {
    return TenantHistory(
      contractId: json['contractId'],
      propertyName: json['propertyName'],
      roomNumber: json['roomNumber'],
      startDate: json['startDate'],
      endDate: json['endDate'],
      contractStatus: json['contractStatus'],
      depositAmount: json['depositAmount'] != null ? double.parse(json['depositAmount'].toString()) : 0.0,
      totalInvoices: json['totalInvoices'] ?? 0,
      unpaidInvoices: json['unpaidInvoices'] ?? 0,
      totalPaidAmount: json['totalPaidAmount'] != null ? double.parse(json['totalPaidAmount'].toString()) : 0.0,
      totalUnpaidAmount: json['totalUnpaidAmount'] != null ? double.parse(json['totalUnpaidAmount'].toString()) : 0.0,
    );
  }
}

class ManageUserDTO {
  int? id;
  String? fullName;
  String? email;
  String? phoneNumber;
  String? identityCard;
  String? role;
  String? status;
  List<RentedRoomInfo>? rentedRooms;

  ManageUserDTO({
    this.id,
    this.fullName,
    this.email,
    this.phoneNumber,
    this.identityCard,
    this.role,
    this.status,
    this.rentedRooms,
  });

  factory ManageUserDTO.fromJson(Map<String, dynamic> json) {
    var list = json['rentedRooms'] as List?;
    List<RentedRoomInfo>? roomsList = list != null
        ? list.map((i) => RentedRoomInfo.fromJson(i)).toList()
        : null;

    return ManageUserDTO(
      id: json['id'],
      fullName: json['fullName'],
      email: json['email'],
      phoneNumber: json['phoneNumber'],
      identityCard: json['identityCard'],
      role: json['role'],
      status: json['status'],
      rentedRooms: roomsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'phoneNumber': phoneNumber,
      'identityCard': identityCard,
      'role': role,
      'status': status,
    };
  }
}