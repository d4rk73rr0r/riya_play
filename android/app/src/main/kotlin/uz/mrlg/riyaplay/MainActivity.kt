package uz.mrlg.riyaplay

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File

/**
 * Publishes finished downloads into the shared Movies/ collection.
 *
 * Since Android 10 (scoped storage) an app cannot write into /sdcard/Movies
 * with plain file I/O — the supported route is MediaStore. Note that raw
 * path writes to a *pending* MediaStore entry don't work either: the FUSE
 * layer rejects opening the `.pending-…` placeholder it creates (EEXIST),
 * so the bytes have to be streamed through the resolver's OutputStream.
 * Dart therefore downloads to app-private storage and hands the finished
 * file here to be copied across and indexed, which is what makes it show up
 * in the Gallery and file managers.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "uz.mrlg.riyaplay/media_store"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToMovies" -> saveToMovies(
                        call.argument<String>("sourcePath"),
                        call.argument<String>("fileName"),
                        result
                    )
                    "startDownloadService" -> {
                        DownloadService.start(
                            this,
                            call.argument<String>("title") ?: "Yuklab olish",
                            call.argument<String>("status") ?: ""
                        )
                        result.success(null)
                    }
                    "updateDownloadService" -> {
                        DownloadService.update(
                            this,
                            call.argument<String>("title") ?: "Yuklab olish",
                            call.argument<String>("status") ?: "",
                            call.argument<Int>("progress") ?: -1
                        )
                        result.success(null)
                    }
                    "stopDownloadService" -> {
                        DownloadService.stop(this)
                        result.success(null)
                    }
                    "getFreeBytes" -> result.success(freeBytes())
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallPermissionSettings" -> {
                        openInstallPermissionSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Usable free space on the volume holding app-private storage, which is
     * where a download is assembled before being published. Uses the
     * *available* count rather than the free one: the tail of a filesystem is
     * reserved for root and an app can't actually write into it.
     */
    private fun freeBytes(): Long =
        try {
            StatFs(filesDir.absolutePath).availableBytes
        } catch (e: Exception) {
            -1L
        }

    /**
     * Can this app hand an APK to the system installer?
     *
     * `REQUEST_INSTALL_PACKAGES` in the manifest is not enough: since API 26
     * the user must also allow "Install unknown apps" for this specific app,
     * and that switch can be turned off again at any time. Without it the
     * installer refuses the file, so the OTA flow has to ask first.
     */
    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** Opens the per-app "Install unknown apps" screen for this package. */
    private fun openInstallPermissionSettings() {
        try {
            val intent =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    )
                } else {
                    Intent(Settings.ACTION_SECURITY_SETTINGS)
                }
            startActivity(intent)
        } catch (e: Exception) {
            // Ba'zi qurilmalarda bu ekran yo'q — umumiy sozlamalarga tushamiz.
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS))
            } catch (_: Exception) {
            }
        }
    }

    /** Moves [sourcePath] into Movies/RiyaPlay and returns the public path. */
    private fun saveToMovies(
        sourcePath: String?,
        fileName: String?,
        result: MethodChannel.Result
    ) {
        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("BAD_ARGS", "sourcePath yoki fileName bo'sh", null)
            return
        }
        val source = File(sourcePath)
        if (!source.exists()) {
            result.error("NO_SOURCE", "Vaqtinchalik fayl topilmadi", null)
            return
        }

        try {
            val publicPath =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    copyViaMediaStore(source, fileName)
                } else {
                    copyLegacy(source, fileName)
                }
            source.delete()
            result.success(publicPath)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    private fun copyViaMediaStore(source: File, fileName: String): String {
        val relativePath = "${Environment.DIRECTORY_MOVIES}/RiyaPlay"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeTypeFor(fileName))
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val uri = contentResolver.insert(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values
        ) ?: throw IllegalStateException("MediaStore yozuvi yaratilmadi")

        try {
            contentResolver.openOutputStream(uri).use { output ->
                requireNotNull(output) { "Yozish oqimi ochilmadi" }
                source.inputStream().use { input -> input.copyTo(output) }
            }
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            throw e
        }

        contentResolver.update(
            uri,
            ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
            null,
            null
        )
        return "/sdcard/$relativePath/$fileName"
    }

    private fun copyLegacy(source: File, fileName: String): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            "RiyaPlay"
        )
        if (!dir.exists()) dir.mkdirs()
        val target = File(dir, fileName)
        source.inputStream().use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        // Gallereyada darhol ko'rinishi uchun indekslatamiz.
        MediaScannerConnection.scanFile(
            this, arrayOf(target.absolutePath), arrayOf(mimeTypeFor(fileName)), null
        )
        return target.absolutePath
    }

    private fun mimeTypeFor(fileName: String): String = when {
        fileName.endsWith(".mp4", true) -> "video/mp4"
        // .m4s — remux qilinmagan fMP4 (fragmented MP4) oqimi.
        fileName.endsWith(".m4s", true) -> "video/mp4"
        fileName.endsWith(".mkv", true) -> "video/x-matroska"
        fileName.endsWith(".webm", true) -> "video/webm"
        else -> "video/mp2t" // .ts — HLS segmentlaridan yig'ilgan fayl
    }
}
