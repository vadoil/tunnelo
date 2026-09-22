package com.hiddify.hiddify.bg

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import com.hiddify.hiddify.Settings

/**
 * Будильник-сторож: раз в несколько минут проверяет, жив ли туннель.
 *
 * Сторож внутри приложения работает, пока жив его процесс. Если систему
 * прижало по памяти и она убила приложение целиком, поднять туннель некому:
 * START_STICKY помогает не всегда — после второго падения подряд Android
 * перестаёт перезапускать сервис (проверено на эмуляторе 22.09.2026).
 *
 * Будильник живёт отдельно от процесса и переживает его смерть. Разбудили —
 * смотрим намерение человека: выключал ли он туннель кнопкой. Не выключал —
 * поднимаем сервис и просим его запустить ядро самостоятельно, как после
 * перезагрузки телефона.
 *
 * Старт из фона Android 12+ разрешает не всегда, поэтому отказ — не беда:
 * ловим его и ждём следующего будильника или открытия приложения. Настоящая
 * гарантия на Android одна — «Постоянный VPN» в системных настройках.
 */
class WatchdogReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CHECK) return
        schedule(context)
        if (!Settings.startedByUser) {
            Log.d(TAG, "туннель выключен кнопкой — не трогаем")
            return
        }
        try {
            Settings.startCoreAfterStartingService = true
            BoxService.start()
            Log.d(TAG, "поднимаю туннель по будильнику")
        } catch (e: Exception) {
            // Чаще всего это ForegroundServiceStartNotAllowedException: система
            // не дала стартовать из фона. Молчим и ждём следующего будильника.
            Log.w(TAG, "сервис из фона не поднялся: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "A/Watchdog"
        private const val ACTION_CHECK = "com.hiddify.hiddify.WATCHDOG_CHECK"
        private const val INTERVAL_MS = 5 * 60 * 1000L

        private fun pending(context: Context): PendingIntent {
            val intent = Intent(context, WatchdogReceiver::class.java).setAction(ACTION_CHECK)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            return PendingIntent.getBroadcast(context, 0, intent, flags)
        }

        /** Поставить следующую проверку. Неточный будильник: точность здесь не
         *  нужна, а точные на Android 13+ требуют отдельного разрешения. */
        fun schedule(context: Context) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val at = SystemClock.elapsedRealtime() + INTERVAL_MS
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    manager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pending(context))
                } else {
                    manager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pending(context))
                }
            } catch (e: Exception) {
                Log.w(TAG, "будильник не поставлен: ${e.message}")
            }
        }

        /** Человек выключил туннель кнопкой — сторож больше не нужен. */
        fun cancel(context: Context) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            try {
                manager.cancel(pending(context))
            } catch (e: Exception) {
                Log.w(TAG, "будильник не снят: ${e.message}")
            }
        }
    }
}
