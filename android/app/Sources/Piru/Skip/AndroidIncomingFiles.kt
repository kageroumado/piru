// A share from another phone (a `.pirushare` opened from Files, Quick Share or a messenger, or
// sent to Piru from a share sheet) arrives as a content:// URI that only this intent may read.
// MainActivity hands each intent here before SkipUI's onOpenURL sees it: the file is copied into
// the cache's Inbox folder and the intent becomes a view of that copy, which ShareInbox reads as
// it reads an iOS Inbox file, and deletes once read.
package piru.module

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import java.io.File
import java.util.UUID

class AndroidIncomingFiles {
    companion object {
        /// ShareEnvelope.maxFileBytes: a larger file is not a share, and is not read.
        private const val MAX_BYTES = 4_000_000

        /// `intent`, or for a file sent to the app, a view intent for a copy of it. A file that
        /// cannot be read, or is too large, becomes an empty copy, which the inbox reports as a
        /// damaged share rather than the file going nowhere.
        @JvmStatic
        fun route(context: Context, intent: Intent): Intent {
            // Never pass on a file:// URI another app sent: it would make Piru read, and then
            // delete, a path of the sender's choosing inside Piru's own storage. The one file
            // URI that may reach onOpenURL is a copy this router made, which MainActivity
            // forwards to the task's root.
            intent.data?.takeIf { it.scheme == "file" }?.let { uri ->
                return if (isOwnCopy(context, uri)) intent else Intent(Intent.ACTION_MAIN)
            }
            val uri = incomingFile(intent) ?: return intent
            val copy = copy(context, uri)
            return Intent(Intent.ACTION_VIEW, Uri.fromFile(copy))
        }

        /// Whether `uri` resolves, after `..` and symlinks, to a file inside the Inbox folder.
        private fun isOwnCopy(context: Context, uri: Uri): Boolean {
            val path = uri.path ?: return false
            return runCatching {
                File(path).canonicalFile.startsWith(File(context.cacheDir, "Inbox").canonicalFile)
            }.getOrDefault(false)
        }

        private fun incomingFile(intent: Intent): Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.takeIf { it.scheme == "content" }
            Intent.ACTION_SEND -> runCatching {
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
            }.getOrNull()?.takeIf { it.scheme == "content" }
            else -> null
        }

        private fun copy(context: Context, uri: Uri): File {
            val inbox = File(context.cacheDir, "Inbox")
            // ShareInbox deletes each file it reads; the folders around them, and any copy a
            // killed process never read, go a day later.
            val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000
            inbox.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.deleteRecursively() }
            val folder = File(inbox, UUID.randomUUID().toString()).apply { mkdirs() }
            val target = File(folder, fileName(context, uri))
            val bytes = runCatching {
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    val buffer = java.io.ByteArrayOutputStream()
                    val chunk = ByteArray(64 * 1024)
                    while (buffer.size() <= MAX_BYTES) {
                        val read = stream.read(chunk)
                        if (read < 0) break
                        buffer.write(chunk, 0, read)
                    }
                    if (buffer.size() > MAX_BYTES) null else buffer.toByteArray()
                }
            }.getOrNull()
            target.writeBytes(bytes ?: ByteArray(0))
            return target
        }

        /// The sender's file name when it is a share's, else a share's name: the inbox takes a
        /// file by its extension, and messengers sometimes rename what they pass on.
        private fun fileName(context: Context, uri: Uri): String {
            val name = runCatching {
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            }.getOrNull()?.replace('/', '_')
            return if (name != null && name.lowercase().endsWith(".pirushare")) name else "Received.pirushare"
        }
    }
}
