package com.example.qlpt_frontend

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kênh "qlpt/app": phục vụ bài đo "tắt hẳn app rồi bật lại" (Hồ sơ > Hiệu năng & Demo > So sánh trên app thật)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "qlpt/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "restart" -> {
                    result.success(null)
                    // Mở RestartActivity ở process riêng (":restart"), process đó sẽ kill process app hiện tại
                    // rồi mở lại app từ đầu = giống hệt người dùng vuốt tắt app rồi bấm icon mở lại.
                    val i = Intent(this, RestartActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        .putExtra(RestartActivity.EXTRA_PID, android.os.Process.myPid())
                    startActivity(i)
                    finishAffinity()
                }
                else -> result.notImplemented()
            }
        }
    }
}
