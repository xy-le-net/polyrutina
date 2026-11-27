package com.example.polyrutina

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "polyrutina/downloads",
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val sourcePath = call.argument<String>("sourcePath")
            val fileName = call.argument<String>("fileName")
            if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                result.error("invalid_arguments", "A source path and file name are required", null)
                return@setMethodCallHandler
            }

            try {
                result.success(saveToDownloads(File(sourcePath), fileName))
            } catch (error: Exception) {
                result.error("save_failed", error.message, null)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun saveToDownloads(source: File, requestedName: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IOException("Public Downloads saving requires Android 10 or later")
        }
        if (!source.isFile || !source.canRead()) {
            throw IOException("The source file cannot be read")
        }

        val resolver = applicationContext.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/polyrutina/"
        val extension = requestedName.substringAfterLast('.', "")
        val stem = requestedName.substringBeforeLast('.', requestedName)
        var name = requestedName
        var suffix = 1
        while (downloadExists(collection, relativePath, name)) {
            name = if (extension.isEmpty()) {
                "${stem}_$suffix"
            } else {
                "${stem}_$suffix.$extension"
            }
            suffix++
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Could not create a file in Downloads")

        try {
            FileInputStream(source).use { input ->
                resolver.openOutputStream(uri)?.use { output ->
                    input.copyTo(output)
                } ?: throw IOException("Could not open the Downloads file")
            }
            val publishedValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, publishedValues, null, null)
            return name
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    private fun downloadExists(
        collection: Uri,
        relativePath: String,
        name: String,
    ): Boolean {
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection =
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND " +
                "${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        return contentResolver.query(
            collection,
            projection,
            selection,
            arrayOf(relativePath, name),
            null,
        )?.use { it.moveToFirst() } ?: false
    }
}
