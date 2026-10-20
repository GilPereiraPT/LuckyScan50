package com.gilpereira.luckyscan50

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

/** Uses platform APIs, without adding another APK dependency. */
class NotificationBridge(private val activity: FlutterActivity) {
    private var pending: MethodChannel.Result? = null
    private val manager get() = activity.getSystemService(NotificationManager::class.java)

    fun enabled(): Boolean =
        (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) && manager.areNotificationsEnabled()

    fun request(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("permission_pending", "Pedido em curso.", null)
        } else if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
            pending = result
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 5040)
        } else {
            result.success(enabled())
        }
    }

    fun permissionResult(requestCode: Int) {
        if (requestCode == 5040) {
            pending?.success(enabled())
            pending = null
        }
    }

    fun settings() {
        activity.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName))
    }

    fun show(id: Int, category: String, title: String, body: String): Boolean {
        if (!enabled()) return false
        val labels = mapOf(
            "results" to "Resultados",
            "prizes" to "Prémios por levantar",
            "expiry" to "Prazos de levantamento"
        )
        val label = requireNotNull(labels[category])
        val channel = "luckyscan50_$category"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(channel, label, NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val intent = PendingIntent.getActivity(activity, 0,
            Intent(activity, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(activity, channel) else Notification.Builder(activity)
        manager.notify(id, builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(intent)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .build())
        return true
    }

    fun cancelAll() = manager.cancelAll()

    fun dispose() {
        pending?.error("activity_closed", "Pedido interrompido.", null)
        pending = null
    }
}
