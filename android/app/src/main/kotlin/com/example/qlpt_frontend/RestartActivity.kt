package com.example.qlpt_frontend

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Chạy ở process riêng (":restart"), khai báo trong AndroidManifest.
 * 1. Kill process app cũ: mọi RAM, cache trong bộ nhớ, Flutter engine đều mất (khởi động lạnh thật sự).
 * 2. Chờ SETTLE_MS cho máy thu hồi xong RAM của process cũ (lượt trước có thể dùng 600MB), để lượt sau
 *    không bị chậm oan. Khoảng chờ này được TRỪ khỏi số đo bên Dart (RestartBench._settleMs).
 * 3. Mở lại app bằng đúng intent của icon trên màn hình chính.
 * 4. Tự thoát process ":restart".
 */
class RestartActivity : Activity() {
    companion object {
        const val EXTRA_PID = "pid"
        const val SETTLE_MS = 1500L
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pid = intent.getIntExtra(EXTRA_PID, -1)
        if (pid > 0) android.os.Process.killProcess(pid)
        Thread.sleep(SETTLE_MS)
        val launch = packageManager.getLaunchIntentForPackage(packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(launch)
        finish()
        Runtime.getRuntime().exit(0)
    }
}
