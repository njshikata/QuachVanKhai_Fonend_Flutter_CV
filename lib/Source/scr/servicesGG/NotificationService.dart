// lib/Source/security/NotificationService.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:qlpt_frontend/Source/api/API_total.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';

// 1. PHẢI THÊM HÀM NÀY NẰM NGOÀI CLASS (Hàm Top-level)
// Dùng để xử lý thông báo khi app đang chạy ngầm hoặc đã bị tắt
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Đảm bảo Firebase được khởi tạo trong môi trường nền
  await Firebase.initializeApp();
  print("Đã nhận thông báo dưới nền: ${message.messageId}");
}

class NotificationService {
  // ĐÃ SỬA: Thay .getInstance() thành .instance
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

      String? token = await _firebaseMessaging.getToken();
      print("FCM Token: $token");

      if (token != null) {
        await _sendTokenToServer(token);
      }

      _firebaseMessaging.onTokenRefresh.listen(_sendTokenToServer);

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

  static Future<void> _sendTokenToServer(String fcmToken) async {
    try {
      String? userToken = await Security.getToken();
      if (userToken == null) return;

      final url = Uri.parse('${ApiTotal.baseUrl}/api/tenant/fcm-token');

      await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $userToken",
        },
        body: jsonEncode({"fcmToken": fcmToken}),
      );
      print("Đã gửi FCM Token lên server thành công");
    } catch (e) {
      print("Lỗi khi gửi FCM Token: $e");
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