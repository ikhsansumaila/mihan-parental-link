package com.mihan.parentallink

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore

/**
 * Layar kirim pesan ke orang tua. Bisa dibuka dari layar kunci (overlay GuardService).
 * Selama layar ini tampil, overlay disembunyikan (lihat [GuardService.setComposing]) supaya keyboard
 * bisa dipakai. Keluar / pindah aplikasi / lewat 3 menit → overlay kembali.
 */
class MessageActivity : Activity() {
    companion object {
        const val MAX_LEN = 300
        private const val MIN_INTERVAL_MS = 30_000L
        private const val MAX_OPEN_MS = 3 * 60_000L
        private val PRESETS = listOf(
            "Boleh minta tambahan waktu?",
            "Aku perlu HP untuk tugas sekolah.",
            "Tolong telepon aku.",
            "Aku sudah selesai belajar.",
        )

        fun open(c: Context) {
            c.startActivity(Intent(c, MessageActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }

        /** Kirim pesan ke `devices/{id}/messages`. Firestore mengantre otomatis kalau offline. */
        fun send(c: Context, text: String, done: (ok: Boolean, msg: String) -> Unit) {
            val id = Prefs.deviceId(c) ?: return done(false, "HP belum terhubung ke orang tua.")
            val wait = Prefs.lastMessageAt(c) + MIN_INTERVAL_MS - System.currentTimeMillis()
            if (wait > 0) return done(false, "Tunggu ${wait / 1000 + 1} detik sebelum kirim pesan lagi.")
            if (FirebaseAuth.getInstance().currentUser == null) return done(false, "Belum login. Coba lagi nanti.")
            try {
                if (FirebaseApp.getApps(c).isEmpty()) FirebaseApp.initializeApp(c)
            } catch (e: Exception) {
                return done(false, "Gagal: ${e.message}")
            }
            Prefs.setLastMessageAt(c, System.currentTimeMillis())
            val main = Handler(Looper.getMainLooper())
            var finished = false
            fun finish(ok: Boolean, msg: String) = main.post { if (!finished) { finished = true; done(ok, msg) } }

            FirebaseFirestore.getInstance().collection("devices").document(id).collection("messages")
                .add(hashMapOf("text" to text.take(MAX_LEN), "createdAt" to FieldValue.serverTimestamp(), "read" to false))
                .addOnSuccessListener { finish(true, "Pesan terkirim ke orang tua.") }
                .addOnFailureListener { e ->
                    Log.w("MihanMsg", "send failed", e)
                    Prefs.setLastMessageAt(c, 0)
                    finish(false, "Gagal mengirim: ${e.message}")
                }
            // Offline: tulisan sudah tersimpan di antrean lokal, terkirim otomatis saat online.
            main.postDelayed({ finish(true, "Belum ada internet. Pesan akan terkirim otomatis saat online.") }, 6_000)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var input: EditText
    private lateinit var info: TextView
    private val buttons = mutableListOf<Button>()

    private fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)

        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(32), dp(24), dp(24))
        }
        col.addView(TextView(this).apply {
            text = "Kirim pesan ke orang tua"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.DEFAULT_BOLD
        })
        col.addView(TextView(this).apply {
            text = "Pilih pesan cepat atau tulis sendiri."
            setPadding(0, dp(4), 0, dp(16))
        })
        for (p in PRESETS) {
            col.addView(Button(this).apply {
                text = p
                isAllCaps = false
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                setOnClickListener { submit(p) }
                buttons += this
            }, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        input = EditText(this).apply {
            hint = "Tulis pesan…"
            minLines = 2
            filters = arrayOf(InputFilter.LengthFilter(MAX_LEN))
        }
        col.addView(input, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = dp(16) })
        info = TextView(this).apply { setPadding(0, dp(8), 0, dp(8)) }
        col.addView(info)

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.END }
        row.addView(Button(this).apply {
            text = "Tutup"
            setOnClickListener { finish() }
        })
        row.addView(Button(this).apply {
            text = "Kirim"
            setOnClickListener {
                val t = input.text.toString().trim()
                if (t.isEmpty()) info.text = "Tulis pesan dulu." else submit(t)
            }
            buttons += this
        })
        col.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        setContentView(ScrollView(this).apply { addView(col) })
        // Batas waktu supaya layar ini tidak dipakai untuk "kabur" dari layar kunci.
        handler.postDelayed({ finish() }, MAX_OPEN_MS)
    }

    private fun submit(text: String) {
        buttons.forEach { it.isEnabled = false }
        info.setTextColor(Color.GRAY)
        info.text = "Mengirim…"
        send(this, text) { ok, msg ->
            if (isFinishing || isDestroyed) return@send
            info.setTextColor(if (ok) Color.parseColor("#1E7B3A") else Color.parseColor("#B3261E"))
            info.text = msg
            if (ok) {
                input.setText("")
                handler.postDelayed({ finish() }, 1_800)
            } else {
                buttons.forEach { it.isEnabled = true }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        GuardService.setComposing(true)
    }

    override fun onPause() {
        super.onPause()
        GuardService.setComposing(false)
        // Pindah ke aplikasi lain / Home → tutup, supaya kembali harus lewat layar kunci.
        if (LockState.decision.locked) finish()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
