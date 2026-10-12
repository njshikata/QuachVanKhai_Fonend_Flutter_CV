// Đường dẫn: lib/Source/api/Manage/LandlordManageDTO.dart

// 1. Gửi lên khi tạo Khu trọ
class CreatePropertyRequest {
  String name;
  String address;
  String? description;
  String? rules;
  int billingDay;
  int paymentDeadlineDay;

  CreatePropertyRequest({
    required this.name,
    required this.address,
    this.description,
    this.rules,
    required this.billingDay,
    required this.paymentDeadlineDay,
  });

  Map<String, dynamic> toJson() => {
    "name": name,
    "address": address,
    "description": description,
    "rules": rules,
    "billingDay": billingDay,
    "paymentDeadlineDay": paymentDeadlineDay,
  };
}

// 2. Gửi lên khi tạo 1 Phòng lẻ
class CreateRoomRequest {
  int propertyId;
  String roomNumber;
  double area;
  int maxCapacity;
  double basePrice;
  String amenities;

  CreateRoomRequest({
    required this.propertyId,
    required this.roomNumber,
    required this.area,
    required this.maxCapacity,
    required this.basePrice,
    required this.amenities,
  });

  Map<String, dynamic> toJson() => {
    "propertyId": propertyId,
    "roomNumber": roomNumber,
    "area": area,
    "maxCapacity": maxCapacity,
    "basePrice": basePrice,
    "amenities": amenities,
  };
}

// 3. Gửi lên khi Thêm khách thuê vào phòng (Tạo hợp đồng)
// Đã sửa lại chuẩn với Backend: tenantId và depositAmount
// 3. Gửi lên khi Thêm khách thuê vào phòng (Tạo hợp đồng)
class AssignTenantRequest {
  int roomId;           // Cần id phòng
  String tenantEmail;   // Backend dùng Email để tìm user
  String startDate;     // Định dạng chuẩn: "YYYY-MM-DD"
  String endDate;       // Ngày hết hạn hợp đồng
  double deposit;       // Tiền cọc

  AssignTenantRequest({
    required this.roomId,
    required this.tenantEmail,
    required this.startDate,
    required this.endDate,
    required this.deposit,
  });

  Map<String, dynamic> toJson() => {
    "roomId": roomId,
    "tenantEmail": tenantEmail,
    "startDate": startDate,
    "endDate": endDate,
    "deposit": deposit, // Backend dùng tên biến là deposit
  };
}

// 4. Gửi lên khi Tạo phòng hàng loạt theo tầng
class CreateMultipleRoomsRequest {
  int propertyId;
  int numberOfFloors;
  int roomsPerFloor;
  double area;
  int maxCapacity;
  double basePrice;
  String amenities;

  CreateMultipleRoomsRequest({
    required this.propertyId,
    required this.numberOfFloors,
    required this.roomsPerFloor,
    required this.area,
    required this.maxCapacity,
    required this.basePrice,
    required this.amenities,
  });

  Map<String, dynamic> toJson() => {
    "propertyId": propertyId,
    "numberOfFloors": numberOfFloors,
    "roomsPerFloor": roomsPerFloor,
    "area": area,
    "maxCapacity": maxCapacity,
    "basePrice": basePrice,
    "amenities": amenities,
  };
}

// 5. Gửi lên khi Sửa phòng (Các trường có thể null nếu không muốn sửa)
class UpdateRoomRequest {
  String? roomNumber;
  double? area;
  int? maxCapacity;
  double? basePrice;
  String? amenities;
  String? status; // "AVAILABLE", "RENTED", "MAINTENANCE"

  UpdateRoomRequest({
    this.roomNumber,
    this.area,
    this.maxCapacity,
    this.basePrice,
    this.amenities,
    this.status,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (roomNumber != null) data['roomNumber'] = roomNumber;
    if (area != null) data['area'] = area;
    if (maxCapacity != null) data['maxCapacity'] = maxCapacity;
    if (basePrice != null) data['basePrice'] = basePrice;
    if (amenities != null) data['amenities'] = amenities;
    if (status != null) data['status'] = status;
    return data;
  }
}