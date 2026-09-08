package com.peilink.app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val pickPeiRequest = 2601
    private val savePeiRequest = 2602
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "peilink/external_url"
        ).setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.arguments as? String
            if (url.isNullOrBlank()) {
                result.error("INVALID_URL", "URL is empty", null)
                return@setMethodCallHandler
            }
            try {
                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                result.success(true)
            } catch (error: Exception) {
                result.error("OPEN_FAILED", error.message, null)
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "peilink/pei_file"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pickPeiFile(result)
                "save" -> savePeiFile(call.arguments as? Map<*, *>, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickPeiFile(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("BUSY", "Another file request is active", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("application/octet-stream", "application/json")
            )
        }
        startActivityForResult(intent, pickPeiRequest)
    }

    private fun savePeiFile(arguments: Map<*, *>?, result: MethodChannel.Result) {
        if (pendingSaveResult != null) {
            result.error("BUSY", "Another file request is active", null)
            return
        }
        val bytes = arguments?.get("bytes") as? ByteArray
        val name = arguments?.get("name") as? String
        if (bytes == null || name.isNullOrBlank()) {
            result.error("INVALID_FILE", "Missing file data", null)
            return
        }
        pendingSaveResult = result
        pendingSaveBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        startActivityForResult(intent, savePeiRequest)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            pickPeiRequest -> finishPick(resultCode, data?.data)
            savePeiRequest -> finishSave(resultCode, data?.data)
        }
    }

    private fun finishPick(resultCode: Int, uri: Uri?) {
        val result = pendingPickResult ?: return
        pendingPickResult = null
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw IllegalStateException("Cannot read selected file")
            var name = "角色.pei"
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use {
                if (it.moveToFirst()) name = it.getString(0) ?: name
            }
            result.success(mapOf("name" to name, "bytes" to bytes))
        } catch (error: Exception) {
            result.error("READ_FAILED", error.message, null)
        }
    }

    private fun finishSave(resultCode: Int, uri: Uri?) {
        val result = pendingSaveResult ?: return
        val bytes = pendingSaveBytes
        pendingSaveResult = null
        pendingSaveBytes = null
        if (resultCode != RESULT_OK || uri == null || bytes == null) {
            result.success(false)
            return
        }
        try {
            contentResolver.openOutputStream(uri, "w")?.use { it.write(bytes) }
                ?: throw IllegalStateException("Cannot write selected file")
            result.success(true)
        } catch (error: Exception) {
            result.error("WRITE_FAILED", error.message, null)
        }
    }
}
