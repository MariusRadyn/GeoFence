package limitless.iot.trinity

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val downloadsChannel = "limitless.iot.trinity/downloads"
    private val excelMime =
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                val openAfterSave = call.argument<Boolean>("openAfterSave") ?: true
                if (fileName.isNullOrBlank() || bytes == null) {
                    result.error("invalid_args", "fileName and bytes are required", null)
                    return@setMethodCallHandler
                }

                try {
                    val saved = saveToDownloads(fileName, bytes)
                    if (openAfterSave) {
                        try {
                            openUri(saved.uri)
                        } catch (_: Exception) {
                            // File is saved; opening is best-effort if no Excel app is installed.
                        }
                    }
                    result.success(saved.displayPath)
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
            }
    }

    private data class SavedFile(val displayPath: String, val uri: Uri)

    private fun saveToDownloads(fileName: String, bytes: ByteArray): SavedFile {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, excelMime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Unable to create Downloads entry")

            resolver.openOutputStream(uri)?.use { output ->
                output.write(bytes)
            } ?: throw IllegalStateException("Unable to open Downloads stream")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return SavedFile("Download/$fileName", uri)
        }

        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        val file = File(dir, fileName)
        FileOutputStream(file).use { output -> output.write(bytes) }
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        return SavedFile(file.absolutePath, uri)
    }

    private fun openUri(uri: Uri) {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, excelMime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val chooser = Intent.createChooser(intent, "Open wages report").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(chooser)
    }
}
