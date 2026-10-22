package com.gilpereira.luckyscan50

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Credentials encrypted at rest with a non-exportable Android Keystore key. */
class PrivateAppStorage(context: Context) {
    private val preferences = context.getSharedPreferences("private_app_services", Context.MODE_PRIVATE)
    private val alias = "luckyscan50.app-services.v1"
    private val allowed = setOf("ownerToken", "ownerInstall", "metricsToken")

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = store.getKey(alias, null)
        if (existing is SecretKey) return existing
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        }.generateKey()
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            val name = requireNotNull(call.argument<String>("key"))
            require(name in allowed)
            when (call.method) {
                "read" -> {
                    val stored = preferences.getString(name, null)
                    if (stored == null) { result.success(null); return }
                    val parts = stored.split(":")
                    require(parts.size == 2)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                    result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                }
                "write" -> {
                    val value = requireNotNull(call.argument<String>("value"))
                    require(value.length <= 1024)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key())
                    val stored = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                        Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
                    check(preferences.edit().putString(name, stored).commit())
                    result.success(null)
                }
                "delete" -> { check(preferences.edit().remove(name).commit()); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("private_storage_unavailable", "Armazenamento privado indisponível.", null)
        }
    }
}
