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
      roomId: int.tryParse(json['roomId']?.toString() ?? '0') ?? 0,
      propertyName: json['propertyName']?.toString() ?? 'Khu trọ',
      roomNumber: json['roomNumber']?.toString() ?? '',
      propertyAddress: json['propertyAddress']?.toString(),
      basePrice: double.tryParse(json['basePrice']?.toString() ?? '0') ?? 0.0,
    );
  }
}

class ServiceDetail {
  String serviceName;
  double appliedPrice;

  ServiceDetail({required this.serviceName, required this.appliedPrice});

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    return ServiceDetail(
      serviceName: json['serviceName']?.toString() ?? '',
      appliedPrice: double.tryParse(json['appliedPrice']?.toString() ?? '0') ?? 0.0,
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
    List<ServiceDetail> extraServicesList = list != null
        ? list.map((i) => ServiceDetail.fromJson(i)).toList()
        : [];

    return MyInvoiceResponse(
      // Dùng tryParse an toàn cho mọi kiểu dữ liệu trả về (String hay Int đều được)
      invoiceId: int.tryParse(json['invoiceId']?.toString() ?? '0') ?? 0,
      billingCycle: json['billingCycle']?.toString() ?? '',
      dueDate: json['dueDate']?.toString(),
      totalAmount: double.tryParse(json['totalAmount']?.toString() ?? '0') ?? 0.0,
      status: json['status']?.toString() ?? 'UNPAID',
      meterImageUrl: json['meterImageUrl']?.toString(),

      oldElectricity: int.tryParse(json['oldElectricity']?.toString() ?? '0') ?? 0,
      newElectricity: int.tryParse(json['newElectricity']?.toString() ?? '0') ?? 0,
      electricUsage: int.tryParse(json['electricUsage']?.toString() ?? '0') ?? 0,
      electricTotal: double.tryParse(json['electricTotal']?.toString() ?? '0') ?? 0.0,

      oldWater: int.tryParse(json['oldWater']?.toString() ?? '0') ?? 0,
      newWater: int.tryParse(json['newWater']?.toString() ?? '0') ?? 0,
      waterUsage: int.tryParse(json['waterUsage']?.toString() ?? '0') ?? 0,
      waterTotal: double.tryParse(json['waterTotal']?.toString() ?? '0') ?? 0.0,

      extraServices: extraServicesList,
    );
  }
}