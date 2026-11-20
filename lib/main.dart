import 'package:flutter/foundation.dart'; // Thư viện an toàn dùng để check nền tảng
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:qlpt_frontend/Source/scr/servicesGG/NotificationService.dart';
import 'Source/scr/Login/LoginScreen.dart';
import 'Source/perf/PerfFlags.dart';
import 'Source/perf/PerfMonitor.dart';
import 'Source/perf/PerfOverlay.dart';
import 'Source/perf/real/RealBench.dart';
import 'Source/perf/real/RestartBench.dart';

import 'firebase_options.dart';

void main() async {
  // 1. Bắt buộc có dòng này
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Kiểm tra nền tảng an toàn (Không dùng dart:io nữa)
  bool isWindowsOrLinux = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux);

  try {
    if (!isWindowsOrLinux) {
      // Nếu là Web, Android, iOS, macOS -> Khởi tạo Firebase bình thường
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 3. Chỉ khởi tạo Push Notification trên App (Android/iOS) để Web không bị kẹt
      if (!kIsWeb) {
        await NotificationService.init();
        print("Đã khởi tạo Firebase và Notification (Mobile) thành công!");
      } else {
        print("Đang chạy trên Web. Tạm thời tắt Local Notification để tránh lỗi.");
      }
    } else {
      // Nếu là Windows/Linux -> Bỏ qua Firebase
      print("Đang chạy trên Windows/Linux. Tạm thời vô hiệu hóa Firebase.");
    }
  } catch (e) {
    print("Lỗi khởi tạo hệ thống: $e");
  }

  // Cấu hình bật/tắt tối ưu + bảng FPS/RAM (màn "Hiệu năng & Demo")
  await PerfFlags.load();
  // Lưu mọi phiên đo (tự động + thủ công) để vẽ biểu đồ so sánh
  await RealBench.init();
  await RestartBench.prepareBoot(); // Bài đo "tắt hẳn app rồi bật lại": đặt chế độ CHƯA/ĐÃ tối ưu cho lượt này

  // 4. Chạy ứng dụng
  runApp(const MyApp());
  RestartBench.resumeAfterBoot(); // Nếu đang trong bài đo: tự mở màn cần đo, đo, rồi chuyển lượt kế
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: PerfMonitor.navigatorKey,
      builder: (context, child) => PerfOverlayHost(child: BenchBanner(child: child ?? const SizedBox.shrink())),
      title: 'Quản Lý Phòng Trọ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}