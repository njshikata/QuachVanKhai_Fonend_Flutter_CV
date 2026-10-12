// lib/Source/api/User/Pay/PayDTO.dart

class VietQRResponse {
  final int? invoiceId;
  final String qrUrl;
  final String? bankId;
  final String? accountNo;
  final String? accountName;
  final double amount;
  final String? transferContent;

  VietQRResponse({
    this.invoiceId,
    required this.qrUrl,
    this.bankId,
    this.accountNo,
    this.accountName,
    required this.amount,
    this.transferContent,
  });

  factory VietQRResponse.fromJson(Map<String, dynamic> json) {
    return VietQRResponse(
      invoiceId: json['invoiceId'],
      qrUrl: json['qrUrl'] ?? '',
      bankId: json['bankId'],
      accountNo: json['accountNo'],
      accountName: json['accountName'],
      amount: (json['amount'] ?? 0).toDouble(),
      transferContent: json['transferContent'],
    );
  }
}