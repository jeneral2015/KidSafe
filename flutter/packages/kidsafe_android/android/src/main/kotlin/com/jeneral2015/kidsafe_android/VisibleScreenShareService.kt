package com.jeneral2015.kidsafe_android

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat

class VisibleScreenShareService : Service() {
  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val manager = getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(CHANNEL_ID, "KidSafe مشاركة الشاشة", NotificationManager.IMPORTANCE_LOW)
    manager.createNotificationChannel(channel)
    val notification = NotificationCompat.Builder(this, CHANNEL_ID)
      .setSmallIcon(android.R.drawable.ic_menu_view)
      .setContentTitle("KidSafe: مشاركة الشاشة ظاهرة")
      .setContentText("تم منح موافقة مشاركة الشاشة. يمكنك الإنهاء من KidSafe أو من عناصر Android النظامية.")
      .setOngoing(true)
      .build()
    startForeground(NOTIFICATION_ID, notification)
    return START_NOT_STICKY
  }

  override fun onBind(intent: Intent?): IBinder? = null

  companion object {
    private const val CHANNEL_ID = "kidsafe_screen_share"
    private const val NOTIFICATION_ID = 7401
  }
}
