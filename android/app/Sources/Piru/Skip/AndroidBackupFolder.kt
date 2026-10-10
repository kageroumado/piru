// The Android side of folder backup (Android/Backup/FolderBackup+Android.swift): the Storage
// Access Framework's folder picker, a persisted grant on the folder the user picks, and the
// reads and writes of the backup file inside it. A cloud folder (Google Drive, Dropbox,
// Nextcloud, OneDrive) is written by its provider's own app, so Piru needs no network access.
// The picked folder goes back to Swift through the bridged AndroidBackupFolderResults; file
// calls are synchronous and run on the caller's thread, which Swift keeps off the main one.
package piru.module

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import java.io.File

class AndroidBackupFolder {
    companion object {
        private const val MIME_TYPE = "application/octet-stream"
        private const val PARTIAL_SUFFIX = ".partial"
        private const val GRANT = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION

        private var context: Context? = null
        private var pickLauncher: ActivityResultLauncher<Uri?>? = null

        /// Registers the folder picker, which Android allows only while the activity is created.
        @JvmStatic
        fun register(activity: ComponentActivity) {
            context = activity.applicationContext
            pickLauncher = activity.registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
                picked(activity, uri)
            }
        }

        /// Opens the folder picker.
        @JvmStatic
        fun pick(): Boolean {
            val launcher = pickLauncher ?: return false
            launcher.launch(null)
            return true
        }

        /// Whether Piru still holds its grant on the folder. The user can revoke it from the
        /// system settings, and uninstalling the provider's app revokes it too.
        @JvmStatic
        fun isAccessible(tree: String): Boolean {
            val context = context ?: return false
            val uri = Uri.parse(tree)
            return context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission }
        }

        /// Gives up the grant on a folder Piru no longer backs up to.
        @JvmStatic
        fun release(tree: String) {
            val context = context ?: return
            try {
                context.contentResolver.releasePersistableUriPermission(Uri.parse(tree), GRANT)
            } catch (error: SecurityException) {
                // Already gone.
            }
        }

        /// Whether the folder holds a file called `name`.
        @JvmStatic
        fun exists(tree: String, name: String): Boolean {
            val context = context ?: return false
            return try {
                child(context, Uri.parse(tree), name) != null
            } catch (error: Exception) {
                false
            }
        }

        /// Copies the file `name` in the folder to `destinationPath`. Returns null on success,
        /// else why it failed.
        @JvmStatic
        fun read(tree: String, name: String, destinationPath: String): String? {
            val context = context ?: return "unavailable"
            return try {
                val document = child(context, Uri.parse(tree), name)
                    ?: throw IllegalStateException("The backup file is missing from the folder.")
                val input = context.contentResolver.openInputStream(document)
                    ?: throw IllegalStateException("The backup file could not be opened.")
                input.use { stream -> File(destinationPath).outputStream().use { stream.copyTo(it) } }
                null
            } catch (error: Exception) {
                error.localizedMessage ?: error.toString()
            }
        }

        /// Writes the file at `sourcePath` into the folder as `name`. The bytes land in a
        /// `.partial` file first, so a write cut short leaves the previous backup whole; the
        /// partial then takes the backup's name, or, where the provider cannot rename, its
        /// bytes are copied over the backup and it is removed. Returns null on success, else
        /// why it failed.
        @JvmStatic
        fun write(tree: String, name: String, sourcePath: String): String? {
            val context = context ?: return "unavailable"
            val resolver = context.contentResolver
            return try {
                val treeUri = Uri.parse(tree)
                val source = File(sourcePath)
                val partialName = name + PARTIAL_SUFFIX
                child(context, treeUri, partialName)?.let { DocumentsContract.deleteDocument(resolver, it) }
                val partial = DocumentsContract.createDocument(resolver, folder(treeUri), MIME_TYPE, partialName)
                    ?: throw IllegalStateException("The folder refused a new file.")
                copy(context, source, partial)

                val existing = child(context, treeUri, name)
                val renamed = try {
                    existing?.let { DocumentsContract.deleteDocument(resolver, it) }
                    DocumentsContract.renameDocument(resolver, partial, name) != null
                } catch (error: Exception) {
                    // Providers that cannot rename throw, each its own exception.
                    false
                }
                if (!renamed) {
                    val target = child(context, treeUri, name)
                        ?: DocumentsContract.createDocument(resolver, folder(treeUri), MIME_TYPE, name)
                        ?: throw IllegalStateException("The folder refused a new file.")
                    copy(context, source, target)
                    DocumentsContract.deleteDocument(resolver, partial)
                }
                null
            } catch (error: Exception) {
                error.localizedMessage ?: error.toString()
            }
        }

        private fun picked(activity: ComponentActivity, uri: Uri?) {
            if (uri == null) {
                AndroidBackupFolderResults.shared.didPick(null, null)
                return
            }
            try {
                activity.contentResolver.takePersistableUriPermission(uri, GRANT)
            } catch (error: SecurityException) {
                AndroidBackupFolderResults.shared.didPick(null, null)
                return
            }
            AndroidBackupFolderResults.shared.didPick(uri.toString(), displayName(activity, uri))
        }

        private fun folder(tree: Uri): Uri =
            DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))

        /// The document called `name` directly inside the folder.
        private fun child(context: Context, tree: Uri, name: String): Uri? {
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            context.contentResolver.query(children, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getString(1) == name) {
                        return DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                    }
                }
            }
            return null
        }

        private fun copy(context: Context, source: File, target: Uri) {
            val output = context.contentResolver.openOutputStream(target, "wt")
                ?: throw IllegalStateException("The backup file could not be written.")
            output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
        }

        private fun displayName(context: Context, tree: Uri): String? =
            try {
                context.contentResolver.query(folder(tree), arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                    ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
            } catch (error: Exception) {
                null
            }
    }
}
