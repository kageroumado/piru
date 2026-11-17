// The Android side of file transfer (Android/Platform/Documents+Android.swift): the Storage
// Access Framework's open and create pickers behind `.fileImporter`/`.fileExporter`, and the
// share chooser behind ShareSheet, sending files as content:// URIs from a FileProvider.
// Results go back to Swift through the bridged AndroidDocumentResults.
package piru.module

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File
import java.lang.ref.WeakReference

class AndroidDocuments {
    /// CreateDocument fixes its MIME type at registration; this one reads it per launch.
    private class CreateAnyDocument : ActivityResultContracts.CreateDocument("application/octet-stream") {
        var mimeType = "application/octet-stream"

        override fun createIntent(context: Context, input: String): Intent =
            super.createIntent(context, input).setType(mimeType)
    }

    companion object {
        private var activity: WeakReference<ComponentActivity>? = null
        private var openLauncher: ActivityResultLauncher<Array<String>>? = null
        private var createLauncher: ActivityResultLauncher<String>? = null
        private val createContract = CreateAnyDocument()
        private var pendingExport: File? = null

        /// Registers the pickers, which Android allows only while the activity is created.
        @JvmStatic
        fun register(activity: ComponentActivity) {
            this.activity = WeakReference(activity)
            openLauncher = activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                imported(activity, uri)
            }
            createLauncher = activity.registerForActivityResult(createContract) { uri ->
                exported(activity, uri)
            }
        }

        /// Opens the document picker for the given MIME types (comma-separated). The chosen
        /// document is copied into the cache and its path handed to Swift.
        @JvmStatic
        fun openDocument(mimeTypes: String): Boolean {
            val launcher = openLauncher ?: return false
            val types = mimeTypes.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            launcher.launch(if (types.isEmpty()) arrayOf("*/*") else types.toTypedArray())
            return true
        }

        /// Opens the save picker for a new document named `filename`, then writes the file at
        /// `sourcePath` into the document the user creates.
        @JvmStatic
        fun createDocument(filename: String, mimeType: String, sourcePath: String): Boolean {
            val launcher = createLauncher ?: return false
            pendingExport = File(sourcePath)
            createContract.mimeType = mimeType
            launcher.launch(filename)
            return true
        }

        /// Sends a copy of the file at `path` through the share chooser. The copy lives in the
        /// cache's share folder, apart from the caller's file, so the caller may delete its own
        /// as soon as this returns while the receiving app is still reading.
        @JvmStatic
        fun shareFile(path: String, mimeType: String): Boolean {
            val activity = activity?.get() ?: return false
            return shareFileFrom(activity, path, mimeType)
        }

        /// Sends a copy of the file at `path` through the share chooser opened from `activity`.
        @JvmStatic
        fun shareFileFrom(activity: Activity, path: String, mimeType: String): Boolean {
            return try {
                val source = File(path)
                val folder = File(activity.cacheDir, "share").apply { mkdirs() }
                pruneShares(folder)
                val copy = File(folder, source.name)
                source.copyTo(copy, overwrite = true)
                val uri = FileProvider.getUriForFile(activity, activity.packageName + ".files", copy)
                val send = Intent(Intent.ACTION_SEND)
                    .setType(mimeType)
                    .putExtra(Intent.EXTRA_STREAM, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                send.clipData = ClipData.newRawUri(source.name, uri)
                // Piru takes files sent to it (AndroidIncomingFiles), so it would list itself.
                val chooser = Intent.createChooser(send, null).putExtra(
                    Intent.EXTRA_EXCLUDE_COMPONENTS,
                    arrayOf(ComponentName(activity.packageName, "piru.module.MainActivity")),
                )
                activity.startActivity(chooser)
                true
            } catch (error: Exception) {
                android.util.Log.e("Piru", "share failed", error)
                false
            }
        }

        /// Sends text through the share chooser.
        @JvmStatic
        fun shareText(text: String): Boolean {
            val activity = activity?.get() ?: return false
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
            activity.startActivity(Intent.createChooser(send, null))
            return true
        }

        /// Shared copies older than a day have long been read.
        private fun pruneShares(folder: File) {
            val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000
            folder.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
        }

        private fun imported(activity: ComponentActivity, uri: Uri?) {
            if (uri == null) {
                AndroidDocumentResults.shared.didImport(null, null)
                return
            }
            Thread {
                val result = try {
                    val folder = File(activity.cacheDir, "imports").apply { mkdirs() }
                    val target = File(folder, displayName(activity, uri))
                    val input = activity.contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("The document could not be opened.")
                    input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
                    Pair(target.absolutePath, null)
                } catch (error: Exception) {
                    Pair(null, error.localizedMessage ?: error.toString())
                }
                activity.runOnUiThread { AndroidDocumentResults.shared.didImport(result.first, result.second) }
            }.start()
        }

        private fun exported(activity: ComponentActivity, uri: Uri?) {
            val source = pendingExport
            pendingExport = null
            if (uri == null || source == null) {
                AndroidDocumentResults.shared.didExport(null, null)
                return
            }
            Thread {
                val failure = try {
                    val output = activity.contentResolver.openOutputStream(uri, "wt")
                        ?: throw IllegalStateException("The document could not be written.")
                    output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
                    null
                } catch (error: Exception) {
                    error.localizedMessage ?: error.toString()
                }
                activity.runOnUiThread {
                    AndroidDocumentResults.shared.didExport(if (failure == null) uri.toString() else null, failure)
                }
            }.start()
        }

        private fun displayName(context: Context, uri: Uri): String {
            val name = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
            // A name is only a file name here: no path separators reach the cache folder.
            return (name ?: "document").replace('/', '_').ifEmpty { "document" }
        }
    }
}
