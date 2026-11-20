// Đường dẫn: lib/Source/api/SmartCard/SmartCardDTO.dart

int? _int(dynamic v) => v == null ? null : (v is int ? v : int.tryParse(v.toString()));
DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// 1 trang dữ liệu (server trả Slice: không đếm tổng -> nhẹ DB, hợp cuộn vô hạn).
class PageResult<T> {
  final List<T> items;
  final int page;
  final bool hasNext;

  const PageResult({required this.items, required this.page, required this.hasNext});

  factory PageResult.fromJson(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    final raw = (json['items'] as List?) ?? const [];
    return PageResult(
      items: raw.map((e) => parse(Map<String, dynamic>.from(e as Map))).toList(growable: false),
      page: _int(json['page']) ?? 0,
      hasNext: json['hasNext'] == true,
    );
  }
}

class SmartCardItem {
  final int id;
  final String cardUid;
  final String? holderName;
  final int tenantId;
  final int roomId;
  final String? roomNumber;
  final String? propertyName;
  final String status;          // ACTIVE | LOCKED | REVOKED
  final DateTime? expiryDate;
  final bool expired;
  final int photoVersion;
  final bool photoAvailable;
  final String? photoUrl;
  final int infoVersion;
  final int? previousOwnerId;
  final DateTime? ownerChangedAt;
  final int? lastKnownBalance;
  final DateTime? lastSeenAt;

  const SmartCardItem({
    required this.id,
    required this.cardUid,
    this.holderName,
    required this.tenantId,
    required this.roomId,
    this.roomNumber,
    this.propertyName,
    required this.status,
    this.expiryDate,
    this.expired = false,
    this.photoVersion = 0,
    this.photoAvailable = false,
    this.photoUrl,
    this.infoVersion = 0,
    this.previousOwnerId,
    this.ownerChangedAt,
    this.lastKnownBalance,
    this.lastSeenAt,
  });

  /// Cache key gắn version: đổi ảnh => key mới => app tự tải ảnh mới, version cũ bị xóa.
  String get photoCacheKey => 'card-photo:$id:v$photoVersion';
  String get photoGroup => 'card-photo:$id';

  bool get isActive => status == 'ACTIVE';
  bool get isLocked => status == 'LOCKED';
  bool get isRevoked => status == 'REVOKED';

  factory SmartCardItem.fromJson(Map<String, dynamic> j) => SmartCardItem(
        id: _int(j['id'])!,
        cardUid: j['cardUid']?.toString() ?? '',
        holderName: j['holderName'],
        tenantId: _int(j['tenantId']) ?? 0,
        roomId: _int(j['roomId']) ?? 0,
        roomNumber: j['roomNumber'],
        propertyName: j['propertyName'],
        status: j['status']?.toString() ?? 'ACTIVE',
        expiryDate: _date(j['expiryDate']),
        expired: j['expired'] == true,
        photoVersion: _int(j['photoVersion']) ?? 0,
        photoAvailable: j['photoAvailable'] == true,
        photoUrl: j['photoUrl'],
        infoVersion: _int(j['infoVersion']) ?? 0,
        previousOwnerId: _int(j['previousOwnerId']),
        ownerChangedAt: _date(j['ownerChangedAt']),
        lastKnownBalance: _int(j['lastKnownBalance']),
        lastSeenAt: _date(j['lastSeenAt']),
      );

  SmartCardItem copyWith({String? status, int? lastKnownBalance, SmartCardItem? from}) {
    final s = from ?? this;
    return SmartCardItem(
      id: s.id,
      cardUid: s.cardUid,
      holderName: s.holderName,
      tenantId: s.tenantId,
      roomId: s.roomId,
      roomNumber: s.roomNumber,
      propertyName: s.propertyName,
      status: status ?? s.status,
      expiryDate: s.expiryDate,
      expired: s.expired,
      photoVersion: s.photoVersion,
      photoAvailable: s.photoAvailable,
      photoUrl: s.photoUrl,
      infoVersion: s.infoVersion,
      previousOwnerId: s.previousOwnerId,
      ownerChangedAt: s.ownerChangedAt,
      lastKnownBalance: lastKnownBalance ?? s.lastKnownBalance,
      lastSeenAt: s.lastSeenAt,
    );
  }
}

class SmartCardDetail {
  final SmartCardItem card;
  final String? tenantEmail;
  final DateTime? dateOfBirth;
  final DateTime? issuedDate;
  final DateTime? photoUpdatedAt;
  final DateTime? photoPurgedAt;

  const SmartCardDetail({required this.card, this.tenantEmail, this.dateOfBirth, this.issuedDate, this.photoUpdatedAt, this.photoPurgedAt});

  factory SmartCardDetail.fromJson(Map<String, dynamic> j) => SmartCardDetail(
        card: SmartCardItem.fromJson(Map<String, dynamic>.from(j['card'] as Map)),
        tenantEmail: j['tenantEmail'],
        dateOfBirth: _date(j['dateOfBirth']),
        issuedDate: _date(j['issuedDate']),
        photoUpdatedAt: _date(j['photoUpdatedAt']),
        photoPurgedAt: _date(j['photoPurgedAt']),
      );
}

class CardReadResult {
  final String? holderName, dateOfBirth, issuedDate, expiryDate, roomNumber, photoBase64;
  final int? balance, pinTriesRemaining;
  final bool matchesServer;

  const CardReadResult({this.holderName, this.dateOfBirth, this.issuedDate, this.expiryDate, this.roomNumber,
      this.photoBase64, this.balance, this.pinTriesRemaining, this.matchesServer = false});

  factory CardReadResult.fromJson(Map<String, dynamic> j) => CardReadResult(
        holderName: j['holderName'],
        dateOfBirth: j['dateOfBirth'],
        issuedDate: j['issuedDate'],
        expiryDate: j['expiryDate'],
        roomNumber: j['roomNumber'],
        photoBase64: j['photoBase64'],
        balance: _int(j['balance']),
        pinTriesRemaining: _int(j['pinTriesRemaining']),
        matchesServer: j['matchesServer'] == true,
      );
}

class WalletResult {
  final int balance;
  final int? amount;
  final bool macValid;
  final String? type;
  final int? transactionId;

  const WalletResult({required this.balance, this.amount, this.macValid = false, this.type, this.transactionId});

  factory WalletResult.fromJson(Map<String, dynamic> j) => WalletResult(
        balance: _int(j['balance']) ?? 0,
        amount: _int(j['amount']),
        macValid: j['macValid'] == true,
        type: j['type']?.toString(),
        transactionId: _int(j['transactionId']),
      );
}

/// Kết quả "gửi mã OTP": server đã gửi mã 6 số tới điện thoại người thuê.
class WalletOtpTicket {
  final String requestId;
  final String type;          // CREDIT | DEBIT
  final int amount;
  final int expiresInSeconds;
  final String? holderName, roomNumber, message;
  final bool pushSent;

  const WalletOtpTicket({required this.requestId, required this.type, required this.amount,
      this.expiresInSeconds = 300, this.holderName, this.roomNumber, this.message, this.pushSent = false});

  bool get isDebit => type == 'DEBIT';

  factory WalletOtpTicket.fromJson(Map<String, dynamic> j) => WalletOtpTicket(
        requestId: j['requestId']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        amount: _int(j['amount']) ?? 0,
        expiresInSeconds: _int(j['expiresInSeconds']) ?? 300,
        holderName: j['holderName']?.toString(),
        roomNumber: j['roomNumber']?.toString(),
        message: j['message']?.toString(),
        pushSent: j['pushSent'] == true,
      );
}

/// Mã xác nhận đang chờ – hiện trong app người thuê (phòng khi thông báo đẩy không tới).
class PendingOtp {
  final String requestId;
  final String type;
  final int amount;
  final String code;
  final String? source, roomNumber;
  final int secondsLeft;

  const PendingOtp({required this.requestId, required this.type, required this.amount, required this.code,
      this.source, this.roomNumber, required this.secondsLeft});

  bool get isCredit => type == 'CREDIT';
  String get typeLabel => isCredit ? 'Nạp tiền' : 'Thanh toán';

  factory PendingOtp.fromJson(Map<String, dynamic> j) => PendingOtp(
        requestId: j['requestId']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        amount: _int(j['amount']) ?? 0,
        code: j['code']?.toString() ?? '',
        source: j['source']?.toString(),
        roomNumber: j['roomNumber']?.toString(),
        secondsLeft: _int(j['secondsLeft']) ?? 0,
      );
}

class SwipeResult {
  final bool granted;
  final String message;
  final int? pinTriesRemaining;

  const SwipeResult({required this.granted, required this.message, this.pinTriesRemaining});

  factory SwipeResult.fromJson(Map<String, dynamic> j) => SwipeResult(
        granted: j['granted'] == true,
        message: j['message']?.toString() ?? '',
        pinTriesRemaining: _int(j['pinTriesRemaining']),
      );
}

class CardLogItem {
  final int id;
  final String action;
  final bool granted;
  final String? reason, deviceId, note;
  final DateTime? createdAt;

  const CardLogItem({required this.id, required this.action, required this.granted, this.reason, this.deviceId, this.note, this.createdAt});

  factory CardLogItem.fromJson(Map<String, dynamic> j) => CardLogItem(
        id: _int(j['id']) ?? 0,
        action: j['action']?.toString() ?? '',
        granted: j['granted'] == true,
        reason: j['reason'],
        deviceId: j['deviceId'],
        note: j['note'],
        createdAt: _date(j['createdAt']),
      );

  static const Map<String, String> actionLabels = {
    'DOOR_IN': 'Vào cổng',
    'DOOR_OUT': 'Ra cổng',
    'LOCKER_OPEN': 'Mở tủ bưu kiện',
    'ITEM_BORROW': 'Mượn vật dụng',
    'ITEM_RETURN': 'Trả vật dụng',
  };

  String get actionLabel => actionLabels[action] ?? action;
}

class CardTransactionItem {
  final int id;
  final String type;  // CREDIT | DEBIT
  final int amount;
  final int? balanceAfter;
  final bool macValid;
  final String? description;
  final DateTime? createdAt;

  const CardTransactionItem({required this.id, required this.type, required this.amount, this.balanceAfter,
      this.macValid = false, this.description, this.createdAt});

  bool get isCredit => type == 'CREDIT';

  factory CardTransactionItem.fromJson(Map<String, dynamic> j) => CardTransactionItem(
        id: _int(j['id']) ?? 0,
        type: j['type']?.toString() ?? '',
        amount: _int(j['amount']) ?? 0,
        balanceAfter: _int(j['balanceAfter']),
        macValid: j['macValid'] == true,
        description: j['description'],
        createdAt: _date(j['createdAt']),
      );
}

/// Lỗi API thẻ: kèm số lần nhập PIN còn lại (nếu chip báo).
class CardApiException implements Exception {
  final int statusCode;
  final String message;
  final int? pinTriesRemaining;

  CardApiException(this.statusCode, this.message, {this.pinTriesRemaining});

  @override
  String toString() =>
      pinTriesRemaining == null ? message : '$message\n(Còn $pinTriesRemaining lần thử – sai 5 lần thẻ sẽ bị khóa)';
}
