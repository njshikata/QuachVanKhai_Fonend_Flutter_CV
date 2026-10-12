// Đường dẫn: lib/Source/api/User/UserDTO.dart

class MyRoomResponse {
  int roomId;
  String propertyName;
  String roomNumber;
  String? propertyAddress;
  double basePrice;

  MyRoomResponse({
    required this.roomId,
    required this.propertyName,
    required this.roomNumber,
    this.propertyAddress,
    required this.basePrice,
  });

  factory MyRoomResponse.fromJson(Map<String, dynamic> json) {
    return MyRoomResponse(
      roomId: json['roomId'],
      propertyName: json['propertyName'] ?? 'Khu trọ',
      roomNumber: json['roomNumber'] ?? '',
      propertyAddress: json['propertyAddress'],
      basePrice: json['basePrice'] != null ? double.parse(json['basePrice'].toString()) : 0.0,
    );
  }
}

class ServiceDetail {
  String serviceName;
  double appliedPrice;

  ServiceDetail({required this.serviceName, required this.appliedPrice});

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    return ServiceDetail(
      serviceName: json['serviceName'] ?? '',
      appliedPrice: json['appliedPrice'] != null ? double.parse(json['appliedPrice'].toString()) : 0.0,
    );
  }
}

class MyInvoiceResponse {
  int invoiceId;
  String billingCycle;
  String? dueDate;
  double totalAmount;
  String status;
  String? meterImageUrl;

  int oldElectricity;
  int newElectricity;
  int electricUsage;
  double electricTotal;

  int oldWater;
  int newWater;
  int waterUsage;
  double waterTotal;

  List<ServiceDetail> extraServices;

  MyInvoiceResponse({
    required this.invoiceId,
    required this.billingCycle,
    this.dueDate,
    required this.totalAmount,
    required this.status,
    this.meterImageUrl,
    required this.oldElectricity,
    required this.newElectricity,
    required this.electricUsage,
    required this.electricTotal,
    required this.oldWater,
    required this.newWater,
    required this.waterUsage,
    required this.waterTotal,
    required this.extraServices,
  });

  factory MyInvoiceResponse.fromJson(Map<String, dynamic> json) {
    var list = json['extraServices'] as List?;
    List<ServiceDetail> extraServicesList = list != null ? list.map((i) => ServiceDetail.fromJson(i)).toList() : [];

    return MyInvoiceResponse(
      invoiceId: json['invoiceId'],
      billingCycle: json['billingCycle'] ?? '',
      dueDate: json['dueDate'],
      totalAmount: json['totalAmount'] != null ? double.parse(json['totalAmount'].toString()) : 0.0,
      status: json['status'] ?? 'UNPAID',
      meterImageUrl: json['meterImageUrl'],

      oldElectricity: json['oldElectricity'] ?? 0,
      newElectricity: json['newElectricity'] ?? 0,
      electricUsage: json['electricUsage'] ?? 0,
      electricTotal: json['electricTotal'] != null ? double.parse(json['electricTotal'].toString()) : 0.0,

      oldWater: json['oldWater'] ?? 0,
      newWater: json['newWater'] ?? 0,
      waterUsage: json['waterUsage'] ?? 0,
      waterTotal: json['waterTotal'] != null ? double.parse(json['waterTotal'].toString()) : 0.0,

      extraServices: extraServicesList,
    );
  }
}