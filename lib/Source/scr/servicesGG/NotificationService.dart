// lib/Source/security/NotificationService.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// 1. PHẢI THÊM HÀM NÀY NẰM NGOÀI CLASS (Hàm Top-level)
// Dùng để xử lý thông báo khi app đang chạy ngầm hoặc đã bị tắt
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Đảm bảo Firebase được khởi tạo trong môi trường nền
  await Firebase.initializeApp();
  print("Đã nhận thông báo dưới nền: ${message.messageId}");
}

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // Gọi hàm chạy nền
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Người dùng đã cấp quyền nhận thông báo');

      const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(android: androidInit);
      await _localNotifications.initialize(initSettings);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Nhận thông báo khi đang mở app: ${message.notification?.title}");
        if (message.notification != null) {
          _showLocalNotification(message.notification!);
        }
      });
    }
  }

  static void _showLocalNotification(RemoteNotification notification) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'qlpt_channel',
      'Thông báo Quản lý phòng trọ',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      platformDetails,
    );
  }
}