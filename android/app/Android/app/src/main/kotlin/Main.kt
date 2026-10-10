package piru.module

import skip.lib.*
import skip.model.*
import skip.foundation.*
import skip.ui.*

import android.Manifest
import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.MaterialTheme
import androidx.core.app.ActivityCompat

internal val logger: SkipLogger = SkipLogger(subsystem = "piru.module", category = "Piru")

private typealias AppRootView = PiruRootView
private typealias AppDelegate = PiruAppDelegate

/// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
open class AndroidAppMain: Application {
    constructor() {
    }

    override fun onCreate() {
        super.onCreate()
        logger.info("starting app")
        ProcessInfo.launch(applicationContext)
        AppDelegate.shared.onInit()
        AndroidPlatform.watchTimeZone(applicationContext)
    }

    companion object {
    }
}

/// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
open class MainActivity: AppCompatActivity {
    constructor() {
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        logger.info("starting activity")
        UIApplication.launch(this)
        AndroidDocuments.register(this)
        AndroidBackupFolder.register(this)
        enableEdgeToEdge()

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }

        AppDelegate.shared.onLaunch()

        // Example of requesting permissions on startup.
        // These must match the permissions in the AndroidManifest.xml file.
        //let permissions = listOf(
        //    Manifest.permission.ACCESS_COARSE_LOCATION,
        //    Manifest.permission.ACCESS_FINE_LOCATION
        //    Manifest.permission.CAMERA,
        //    Manifest.permission.WRITE_EXTERNAL_STORAGE,
        //)
        //let requestTag = 1
        //ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
    }

    override fun onStart() {
        logger.info("onStart")
        super.onStart()
    }

    override fun onResume() {
        super.onResume()
        AppDelegate.shared.onResume()
    }

    override fun onPause() {
        super.onPause()
        AppDelegate.shared.onPause()
    }

    override fun onStop() {
        super.onStop()
        AppDelegate.shared.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        AppDelegate.shared.onDestroy()
    }

    override fun onLowMemory() {
        super.onLowMemory()
        AppDelegate.shared.onLowMemory()
    }

    override fun onRestart() {
        logger.info("onRestart")
        super.onRestart()
    }

    override fun onSaveInstanceState(outState: android.os.Bundle): Unit = super.onSaveInstanceState(outState)

    override fun onRestoreInstanceState(bundle: android.os.Bundle) {
        // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
        logger.info("onRestoreInstanceState")
        super.onRestoreInstanceState(bundle)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        logger.info("onRequestPermissionsResult: ${requestCode}")
    }

    companion object {
    }
}

@Composable
internal fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f

    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }

    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(
            statusBarStyle = style,
            navigationBarStyle = style
        )
        onDispose { }
    }
}

@Composable
internal fun PresentationRootView(context: ComposeContext) {
    val colorScheme = if (isSystemInDarkTheme()) ColorScheme.dark else ColorScheme.light
    // Set around PresentationRoot, which builds the MaterialTheme from it: set inside, it
    // arrives after the theme exists, and Android 12+ wallpaper colors win.
    Material3ColorScheme({ colors, isDark -> piruMaterialColors(colors, isDark) }) {
    PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
        SyncSystemBarsWithTheme()
        val contentContext = ctx.content()
        Box(modifier = ctx.modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AppRootView().Compose(context = contentContext)
        }
    }
    }
}


/// Material's color slots in Piru's own colors, as the iOS app shows them. Without this the
/// bars, fields and tab indicator take Android 12+ wallpaper colors. Light: the piru skin's
/// white page, iOS's grouped grays and the text-safe accent (#AD365B). Dark: the black page
/// and #111111 cards. surfaceTint is a neutral gray, so elevated surfaces (the tab bar, a
/// scrolled header, menus) read as iOS's gray bars rather than pure page color.
internal fun piruMaterialColors(colors: androidx.compose.material3.ColorScheme, isDark: Boolean): androidx.compose.material3.ColorScheme {
    val c = { argb: Long -> androidx.compose.ui.graphics.Color(argb) }
    return if (isDark) colors.copy(
        primary = c(0xFFF57896), onPrimary = c(0xFF000000),
        secondaryContainer = c(0xFF3A1622), onSecondaryContainer = c(0xFFF57896),
        background = c(0xFF000000), onBackground = c(0xFFFFFFFF),
        surface = c(0xFF000000), onSurface = c(0xFFFFFFFF), surfaceTint = c(0xFFC7C7CC),
        surfaceVariant = c(0xFF1C1C1E), onSurfaceVariant = c(0xFF98989F),
        surfaceContainerLowest = c(0xFF000000), surfaceContainerLow = c(0xFF111111),
        surfaceContainer = c(0xFF1C1C1E), surfaceContainerHigh = c(0xFF2C2C2E),
        surfaceContainerHighest = c(0xFF3A3A3C),
        outline = c(0xFF545458), outlineVariant = c(0xFF38383A),
    ) else colors.copy(
        primary = c(0xFFAD365B), onPrimary = c(0xFFFFFFFF),
        secondaryContainer = c(0xFFFBE3EA), onSecondaryContainer = c(0xFFAD365B),
        background = c(0xFFFFFFFF), onBackground = c(0xFF000000),
        surface = c(0xFFFFFFFF), onSurface = c(0xFF000000), surfaceTint = c(0xFF8E8E93),
        surfaceVariant = c(0xFFF2F2F7), onSurfaceVariant = c(0xFF6C6C70),
        surfaceContainerLowest = c(0xFFFFFFFF), surfaceContainerLow = c(0xFFF7F7F8),
        surfaceContainer = c(0xFFF7F7F8), surfaceContainerHigh = c(0xFFF2F2F7),
        surfaceContainerHighest = c(0xFFE9E9EE),
        outline = c(0xFFC6C6C8), outlineVariant = c(0xFFE5E5EA),
    )
}
