package im.sush.zree

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * PAT storage. Prefers Keystore-backed EncryptedSharedPreferences and falls
 * back to ordinary preferences if the platform keystore misbehaves.
 */
class TokenStore(private val context: Context) {
    private val plain = context.getSharedPreferences("zree", Context.MODE_PRIVATE)

    private val encrypted: android.content.SharedPreferences? by lazy {
        runCatching {
            val key = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            EncryptedSharedPreferences.create(
                context,
                "zree-secure",
                key,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }.onFailure { Log.w("Zree", "keystore unavailable, storing PAT in plain prefs", it) }
            .getOrNull()
    }

    fun get(): String? =
        (encrypted ?: plain).getString(KEY, null).also {
            // migrate a value left in plain prefs
            if (it != null) plain.edit().remove(KEY).apply()
        }

    fun save(token: String) {
        (encrypted ?: plain).edit().putString(KEY, token).apply()
        if (encrypted != null) plain.edit().remove(KEY).apply()
    }

    companion object {
        private const val KEY = "gitToken"
    }
}
