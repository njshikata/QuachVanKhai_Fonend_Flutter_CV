// Đường dẫn: lib/Source/api/API_total.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/asymmetric/api.dart';
import 'package:qlpt_frontend/Source/security/Security.dart';

class ApiTotal {
  // IP máy chạy backend khi dùng ĐIỆN THOẠI THẬT. Truyền lúc chạy, khỏi sửa code:
  //   flutter run --dart-define=API_HOST=192.168.1.5   (hoặc 127.0.0.1 kèm "adb reverse tcp:8080 tcp:8080")
  static const String physicalDeviceIP = String.fromEnvironment('API_HOST');

  // Khóa Public Key chuẩn X.509 (OpenSSL generated - Khớp 100% với Private Key bên dưới)
  static const String _rawPublicKey =
      "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAk4kLuC4HHJPFGn0oO930xw7jf4jJ64drNpRb0WrP1V71a6JCkpfusYIWYRsO4msbus8VqskMkXh1mZaEPs/OG/26vav63MHLRDSNOw8ng99OAeoI2mHuA8LcZD6kb+XkbQ3tGrCN8hqkGYzgL6cvHxbTV9MqNZxNru2brkd5QQgSPZLKhk8MTYgQxoX2Ml4yHCy5AASDjdAOlrhgTjpo/gw2oK+zx/GJHqGuIU50qVPVWclDBf31MxIx3JvRJO+VHpYE5JCOXZ8pFpjU/QB8upPMsQpJ0Nc16Obn+hOkk3YliWt0A9FAhiGfUZcMhG2D6mGV8+/Ai22BFtqE3Y9EFQIDAQAB";

  static enc.Encrypter? _cachedEncrypter;

  static enc.Encrypter get _encrypter {
    if (_cachedEncrypter == null) {
      final String cleanKey = _rawPublicKey.replaceAll(RegExp(r'\s+'), '');
      final String formattedKey =
          "-----BEGIN PUBLIC KEY-----\n$cleanKey\n-----END PUBLIC KEY-----";
      final parser = enc.RSAKeyParser();
      final RSAPublicKey publicKey = parser.parse(formattedKey) as RSAPublicKey;
      _cachedEncrypter = enc.Encrypter(enc.RSA(publicKey: publicKey));
    }
    return _cachedEncrypter!;
  }

  static String get baseUrl {
    if (physicalDeviceIP.isNotEmpty) return "http://$physicalDeviceIP:8080";
    if (kIsWeb) return "http://localhost:8080";
    if (Platform.isAndroid) return "http://10.0.2.2:8080";
    if (Platform.isIOS) return "http://127.0.0.1:8080";
    return "http://localhost:8080";
  }

  static Map<String, String> get publicHeaders {
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final encrypted = _encrypter.encrypt(timestamp);
    final String safePayload = encrypted.base64.replaceAll(RegExp(r'\s+'), '');

    return {
      "Content-Type": "application/json; charset=UTF-8",
      "X-App-RSA-Payload": safePayload,
    };
  }

  static Future getAuthHeaders() async {
    final headers = Map<String, String>.from(publicHeaders);
    String? token = await Security.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}