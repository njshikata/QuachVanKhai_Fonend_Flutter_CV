// Đường dẫn: lib/Source/api/User/Card/MyCardDTO.dart
//
// Người thuê dùng chung model với phía chủ trọ (cùng response từ server) -> export lại cho gọn import.
export 'package:qlpt_frontend/Source/api/SmartCard/SmartCardDTO.dart'
    show SmartCardItem, SmartCardDetail, PageResult, CardLogItem, CardTransactionItem, CardApiException, PendingOtp;
