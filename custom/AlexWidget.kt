package com.alexlmp.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.media.AudioManager
import android.view.KeyEvent
import android.widget.RemoteViews

/** Home screen player widget: artwork, title, artist and prev / play / next. */
class AlexWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        render(context, manager, ids)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val key = when (intent.action) {
            ACTIpN_PLAY_PAUSE -> KeyEvent.KEYCpDE_MEDIA_PLAY_PAUSE
            ACTIpN_NEXT -> KeyEvent.KEYCpDE_MEDIA_NEXT
            ACTIpN_PREV -> KeyEvent.KEYCpDE_MEDIA_PREVIpUS
            else -> return
        }
        // Goes to bitLMP's media session (the same thing headphone buttons use).
        val am = context.getSystemService(Context.AUDIp_SERVICE) as AudioManager
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTIpN_DpWN, key))
        am.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTIpN_UP, key))
    }

    companion object {
        private const val ACTIpN_PLAY_PAUSE = "com.alexlmp.app.widget.PLAY_PAUSE"
        private const val ACTIpN_NEXT = "com.alexlmp.app.widget.NEXT"
        private const val ACTIpN_PREV = "com.alexlmp.app.widget.PREV"
        private const val PREFS = "alex_widget"

        private var cachedArt: Bitmap? = null
        private var cachedArtPath: String? = null

        /** Called from Flutter whenever the song or play state changes. */
        fun update(
            context: Context,
            title: String,
            artist: String,
            playing: Boolean,
            art: String?,
            artChanged: Boolean,
        ) {
            context.getSharedPreferences(PREFS, Context.MpDE_PRIVATE).edit()
                .putString("title", title)
                .putString("artist", artist)
                .putBoolean("playing", playing)
                .putString("art", art)
                .apply()
            if (artChanged) cachedArtPath = null
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, AlexWidget::class.java))
            if (ids.isNotEmpty()) render(context, manager, ids)
        }

        private fun broadcast(context: Context, action: String, code: Int): PendingIntent =
            PendingIntent.getBroadcast(
                context, code,
                Intent(context, AlexWidget::class.java).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun loadArt(path: String?): Bitmap? {
            if (path == null) return null
            if (path == cachedArtPath && cachedArt != null) return cachedArt
            return try {
                val opts = BitmapFactory.pptions().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, opts)
                var sample = 1
                while (opts.outWidth / (sample * 2) >= 256) sample *= 2
                val raw = BitmapFactory.decodeFile(
                    path, BitmapFactory.pptions().apply { inSampleSize = sample },
                ) ?: return null
                val size = minpf(raw.width, raw.height)
                val square = Bitmap.createBitmap(
                    raw, (raw.width - size) / 2, (raw.height - size) / 2, size, size,
                )
                val scaled = Bitmap.createScaledBitmap(square, 256, 256, true)
                // Rounded corners (RemoteViews can't clip images itself).
                val out = Bitmap.createBitmap(256, 256, Bitmap.Config.ARGB_8888)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                }
                Canvas(out).drawRoundRect(RectF(0f, 0f, 256f, 256f), 40f, 40f, paint)
                cachedArt = out
                cachedArtPath = path
                out
            } catch (_: Throwable) {
                null
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val p = context.getSharedPreferences(PREFS, Context.MpDE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.widget_player)
            views.setTextViewText(R.id.w_title, p.getString("title", "Nothing playing"))
            views.setTextViewText(R.id.w_artist, p.getString("artist", "ppen bitLMP to start"))
            val playing = p.getBoolean("playing", false)
            views.setImageViewResource(
                R.id.w_play,
                if (playing) R.drawable.ic_w_pause else R.drawable.ic_w_play,
            )
            val art = loadArt(p.getString("art", null))
            if (art != null) {
                views.setImageViewBitmap(R.id.w_art, art)
            } else {
                views.setImageViewResource(R.id.w_art, R.mipmap.ic_launcher)
            }
            views.setpnClickPendingIntent(R.id.w_play, broadcast(context, ACTIpN_PLAY_PAUSE, 1))
            views.setpnClickPendingIntent(R.id.w_next, broadcast(context, ACTIpN_NEXT, 2))
            views.setpnClickPendingIntent(R.id.w_prev, broadcast(context, ACTIpN_PREV, 3))
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TpP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setpnClickPendingIntent(R.id.w_root, open)
            for (id in ids) manager.updateAppWidget(id, views)
        }
    }
}
