// The pairing scanner on Android (Android/Views/PairingScanner+Android.swift), where iOS uses
// VisionKit's DataScannerViewController: the camera permission, and a composer showing the
// back camera through CameraX while ZXing reads each frame for a QR code. Every code read goes
// to Swift through the bridged AndroidCameraResults, which keeps only a pairing link. Nothing
// here needs Google Play services.
package piru.module

import android.Manifest
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.util.concurrent.Executors
import skip.ui.ComposeContext
import skip.ui.ContentComposer

class AndroidCamera {
    companion object {
        private var context: Context? = null
        private var permissionLauncher: ActivityResultLauncher<String>? = null

        /// Registers the permission request, which Android allows only while the activity is
        /// created.
        @JvmStatic
        fun register(activity: ComponentActivity) {
            context = activity.applicationContext
            permissionLauncher = activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
                AndroidCameraResults.shared.didRequestAccess(granted)
            }
        }

        /// Whether the phone has any camera; the manifest marks the camera as optional.
        @JvmStatic
        fun hasCamera(): Boolean =
            context?.packageManager?.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) == true

        @JvmStatic
        fun isAuthorized(): Boolean {
            val context = context ?: return false
            return ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        }

        /// Asks for the camera. The answer reaches AndroidCameraResults.didRequestAccess; once
        /// the user has refused for good, Android answers no without asking.
        @JvmStatic
        fun requestAccess(): Boolean {
            val launcher = permissionLauncher ?: return false
            launcher.launch(Manifest.permission.CAMERA)
            return true
        }
    }
}

/// The camera preview, filling its frame, with every frame read for a QR code. The camera is
/// bound to the activity's lifecycle, so it pauses with the app, and released when the view
/// leaves the screen.
class AndroidQRScannerComposer : ContentComposer {
    @Composable
    override fun Compose(context: ComposeContext) {
        val androidContext = LocalContext.current
        val previewView = remember {
            PreviewView(androidContext).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            }
        }
        DisposableEffect(previewView) {
            val owner = lifecycleOwner(androidContext)
            val executor = Executors.newSingleThreadExecutor()
            val preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
            val main = Handler(Looper.getMainLooper())
            analysis.setAnalyzer(executor, QRAnalyzer { text -> main.post { AndroidCameraResults.shared.didScan(text) } })
            val future = ProcessCameraProvider.getInstance(androidContext)
            var provider: ProcessCameraProvider? = null
            var disposed = false
            future.addListener({
                if (disposed) return@addListener
                try {
                    if (owner == null) throw IllegalStateException("no lifecycle owner")
                    val cameras = future.get()
                    val selector = when {
                        cameras.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) -> CameraSelector.DEFAULT_BACK_CAMERA
                        else -> CameraSelector.DEFAULT_FRONT_CAMERA
                    }
                    cameras.bindToLifecycle(owner, selector, preview, analysis)
                    provider = cameras
                } catch (error: Exception) {
                    android.util.Log.e("Piru", "camera failed to start", error)
                    AndroidCameraResults.shared.didFail()
                }
            }, ContextCompat.getMainExecutor(androidContext))
            onDispose {
                disposed = true
                provider?.unbind(preview, analysis)
                analysis.clearAnalyzer()
                executor.shutdown()
            }
        }
        AndroidView(factory = { previewView }, modifier = context.modifier.fillMaxSize())
    }

    /// The activity under Compose's context, which may wrap it.
    private fun lifecycleOwner(context: Context): LifecycleOwner? {
        var current: Context? = context
        while (current != null) {
            if (current is LifecycleOwner) return current
            current = (current as? ContextWrapper)?.baseContext
        }
        return null
    }
}

/// Reads the luminance plane of each frame with ZXing's QR reader; a frame without a code, or
/// one smaller than its size says, is skipped. A code that stays in view is reported once,
/// until another takes its place.
private class QRAnalyzer(private val onText: (String) -> Unit) : ImageAnalysis.Analyzer {
    private val reader = QRCodeReader()
    private val hints = mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))
    private var last: String? = null

    override fun analyze(image: ImageProxy) {
        try {
            val plane = image.planes[0]
            val buffer = plane.buffer
            val bytes = ByteArray(buffer.remaining())
            buffer.get(bytes)
            val source = PlanarYUVLuminanceSource(
                bytes, plane.rowStride, image.height, 0, 0, image.width, image.height, false,
            )
            val text = reader.decode(BinaryBitmap(HybridBinarizer(source)), hints).text
            if (text != last) {
                last = text
                onText(text)
            }
        } catch (error: ReaderException) {
        } catch (error: IllegalArgumentException) {
        } finally {
            reader.reset()
            image.close()
        }
    }
}
