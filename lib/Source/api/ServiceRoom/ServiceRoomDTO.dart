// Đường dẫn: lib/Source/api/ServiceRoom/ServiceRoomDTO.dart

class CatalogResponse {
  int id;
  String name;
  String unit;
  double defaultPrice;

  CatalogResponse({required this.id, required this.name, required this.unit, required this.defaultPrice});

  factory CatalogResponse.fromJson(Map<String, dynamic> json) {
    return CatalogResponse(
      id: json['id'],
      name: json['name'],
      unit: json['unit'],
      defaultPrice: double.parse(json['defaultPrice'].toString()),
    );
  }
}

class RoomServiceResponse {
  int roomServiceId;
  int serviceId;
  String serviceName;
  String unit;
  double defaultPrice;
  double? customPrice;
  double appliedPrice;

  RoomServiceResponse({
    required this.roomServiceId, required this.serviceId, required this.serviceName,
    required this.unit, required this.defaultPrice, this.customPrice, required this.appliedPrice,
  });

  factory RoomServiceResponse.fromJson(Map<String, dynamic> json) {
    return RoomServiceResponse(
      roomServiceId: json['roomServiceId'],
      serviceId: json['serviceId'],
      serviceName: json['serviceName'],
      unit: json['unit'],
      defaultPrice: double.parse(json['defaultPrice'].toString()),
      customPrice: json['customPrice'] != null ? double.parse(json['customPrice'].toString()) : null,
      appliedPrice: double.parse(json['appliedPrice'].toString()),
    );
  }
}

class RoomBillingSummary {
  int roomId;
  String propertyName;
  String roomNumber;
  String tenantName;
  String tenantPhone;
  bool isPaidThisMonth;
  String billingCycle;
  double totalAmount;

  int? electricUsage;
  double? electricTotal;
  int? waterUsage;
  double? waterTotal;

  // Số cũ để tự động điền vào form chốt số
  int? lastElectricity;
  int? lastWater;

  List<RoomServiceResponse> services;

  RoomBillingSummary({
    required this.roomId, required this.propertyName, required this.roomNumber,
    required this.tenantName, required this.tenantPhone, required this.isPaidThisMonth,
    required this.billingCycle, required this.totalAmount,
    this.electricUsage, this.electricTotal, this.waterUsage, this.waterTotal,
    this.lastElectricity, this.lastWater,
    required this.services,
  });

  factory RoomBillingSummary.fromJson(Map<String, dynamic> json) {
    var list = json['services'] as List?;
    List<RoomServiceResponse> serviceList = list != null ? list.map((i) => RoomServiceResponse.fromJson(i)).toList() : [];

    return RoomBillingSummary(
      roomId: json['roomId'],
      propertyName: json['propertyName'] ?? 'Khu trọ',
      roomNumber: json['roomNumber'] ?? '',
      tenantName: json['tenantName'] ?? 'Phòng trống',
      tenantPhone: json['tenantPhone'] ?? '',
      isPaidThisMonth: json['isPaidThisMonth'] ?? false,
      billingCycle: json['billingCycle'] ?? '',
      totalAmount: json['totalAmount'] != null ? double.parse(json['totalAmount'].toString()) : 0.0,

      electricUsage: json['electricUsage'],
      electricTotal: json['electricTotal'] != null ? double.parse(json['electricTotal'].toString()) : null,
      waterUsage: json['waterUsage'],
      waterTotal: json['waterTotal'] != null ? double.parse(json['waterTotal'].toString()) : null,
      lastElectricity: json['lastElectricity'],
      lastWater: json['lastWater'],

      services: serviceList,
    );
  }
}

// LỚP DỮ LIỆU LỊCH SỬ HÓA ĐƠN
class InvoiceHistoryResponse {
  int invoiceId;
  String billingCycle;
  String? readingDate;
  String? dueDate;
  double totalAmount;
  String status;
  String? meterImageUrl;
  int? electricUsage;
  int? waterUsage;

  InvoiceHistoryResponse({
    required this.invoiceId, required this.billingCycle, this.readingDate, this.dueDate,
    required this.totalAmount, required this.status, this.meterImageUrl,
    this.electricUsage, this.waterUsage,
  });

  factory InvoiceHistoryResponse.fromJson(Map<String, dynamic> json) {
    return InvoiceHistoryResponse(
      invoiceId: json['invoiceId'],
      billingCycle: json['billingCycle'] ?? '',
      readingDate: json['readingDate'],
      dueDate: json['dueDate'],
      totalAmount: double.parse(json['totalAmount'].toString()),
      status: json['status'] ?? 'UNPAID',
      meterImageUrl: json['meterImageUrl'],
      electricUsage: json['electricUsage'],
      waterUsage: json['waterUsage'],
    );
  }
}

class AssignRequest {
  int serviceId;
  double? customPrice;

  AssignRequest({required this.serviceId, this.customPrice});

  Map<String, dynamic> toJson() => {
    'serviceId': serviceId,
    'customPrice': customPrice,
  };
}

class RecordUtilityRequest {
  String billingCycle;
  String? readingDate;
  String? dueDate;
  double? newRoomPrice;
  double? newElecPrice;
  double? newWaterPrice;
  int oldElectricity;
  int newElectricity;
  int oldWater;
  int newWater;
  bool isMeterReset;

  RecordUtilityRequest({
    required this.billingCycle,
    this.readingDate,
    this.dueDate,
    this.newRoomPrice,
    this.newElecPrice,
    this.newWaterPrice,
    required this.oldElectricity,
    required this.newElectricity,
    required this.oldWater,
    required this.newWater,
    required this.isMeterReset,
  });

  Map<String, dynamic> toJson() => {
    'billingCycle': billingCycle,
    'readingDate': readingDate,
    'dueDate': dueDate,
    'newRoomPrice': newRoomPrice,
    'newElecPrice': newElecPrice,
    'newWaterPrice': newWaterPrice,
    'oldElectricity': oldElectricity,
    'newElectricity': newElectricity,
    'oldWater': oldWater,
    'newWater': newWater,
    'isMeterReset': isMeterReset,
  };
}

class UtilityReadingResponse {
  String billingCycle;
  int electricUsage;
  double electricTotal;
  int waterUsage;
  double waterTotal;
  double grandTotal;
  String? meterImageUrl;

  UtilityReadingResponse({
    required this.billingCycle,
    required this.electricUsage,
    required this.electricTotal,
    required this.waterUsage,
    required this.waterTotal,
    required this.grandTotal,
    this.meterImageUrl,
  });

  factory UtilityReadingResponse.fromJson(Map<String, dynamic> json) {
    return UtilityReadingResponse(
      billingCycle: json['billingCycle'] ?? '',
      electricUsage: json['electricUsage'] ?? 0,
      electricTotal: double.parse(json['electricTotal'].toString()),
      waterUsage: json['waterUsage'] ?? 0,
      waterTotal: double.parse(json['waterTotal'].toString()),
      grandTotal: double.parse(json['grandTotal'].toString()),
      meterImageUrl: json['meterImageUrl'],
    );
  }
}