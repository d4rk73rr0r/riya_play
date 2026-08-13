package uz.mrlg.riyaplay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Keeps a download alive while the screen is off.
 *
 * Without a foreground service Android puts the process under Doze a short
 * while after the screen locks and severs its network access — downloads
 * died mid-way with "Failed host lookup" because even DNS stopped
 * resolving. A `dataSync` foreground service is the supported way to tell
 * the platform this work must keep running, and the ongoing notification is
 * what buys that exemption.
 */
class DownloadService : android.app.Service() {
    companion object {
        private const val channelId = "riyaplay_downloads"
        private const val notificationId = 1001

        const val extraTitle = "title"
        const val extraProgress = "progress"
        const val extraStatus = "status"

        fun start(context: Context, title: String, status: String) {
            val intent = Intent(context, DownloadService::class.java).apply {
                putExtra(extraTitle, title)
                putExtra(extraStatus, status)
                putExtra(extraProgress, 0)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, title: String, status: String, progress: Int) {
            val intent = Intent(context, DownloadService::class.java).apply {
                putExtra(extraTitle, title)
                putExtra(extraStatus, status)
                putExtra(extraProgress, progress)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(extraTitle) ?: "Yuklab olish"
        val status = intent?.getStringExtra(extraStatus) ?: ""
        val progress = intent?.getIntExtra(extraProgress, 0) ?: 0

        createChannel()
        startForeground(notificationId, buildNotification(title, status, progress))
        // Tizim servisni o'ldirsa qayta tiklamaymiz — yuklashni Dart tomoni
        // boshqaradi va u ham to'xtagan bo'ladi.
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(channelId) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                channelId,
                "Yuklab olishlar",
                NotificationManager.IMPORTANCE_LOW // Ovozsiz
            )
        )
    }

    private fun buildNotification(
        title: String,
        status: String,
        progress: Int
    ): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

        return builder
            .setContentTitle(title)
            .setContentText(status)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .apply {
                if (progress in 0..100) setProgress(100, progress, false)
                else setProgress(0, 0, true) // Noaniq (remux/saqlash bosqichi)
            }
            .build()
    }
}
