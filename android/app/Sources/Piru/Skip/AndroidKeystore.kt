// The key that seals the app's keychain files (Android/Platform/Security+Android.swift): an
// AES-256 key generated inside the Android Keystore, hardware-backed where the phone has the
// hardware, which never leaves it. A sealed item is the 12-byte GCM nonce, then the
// ciphertext and its tag, with the item's name as associated data.
package piru.module

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class AndroidKeystore {
    companion object {
        private const val ALIAS = "piru.keychain.v1"
        private const val NONCE_BYTES = 12
        private const val TAG_BITS = 128

        @Synchronized
        private fun key(): SecretKey {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(
                KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            return generator.generateKey()
        }

        /// `plaintext` sealed under the Keystore key; null when the Keystore refuses.
        @JvmStatic
        fun seal(plaintext: ByteArray, label: String): ByteArray? = try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            cipher.updateAAD(label.toByteArray(Charsets.UTF_8))
            cipher.iv + cipher.doFinal(plaintext)
        } catch (error: Exception) {
            android.util.Log.e("Piru", "keystore seal failed", error)
            null
        }

        /// What `seal` sealed with the same label; null for anything else.
        @JvmStatic
        fun open(sealed: ByteArray, label: String): ByteArray? = try {
            if (sealed.size < NONCE_BYTES + TAG_BITS / 8) {
                null
            } else {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, sealed, 0, NONCE_BYTES))
                cipher.updateAAD(label.toByteArray(Charsets.UTF_8))
                cipher.doFinal(sealed, NONCE_BYTES, sealed.size - NONCE_BYTES)
            }
        } catch (error: Exception) {
            android.util.Log.e("Piru", "keystore open failed", error)
            null
        }
    }
}
