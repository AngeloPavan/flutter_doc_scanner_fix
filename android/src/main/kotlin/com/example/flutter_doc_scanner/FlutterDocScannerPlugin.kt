package com.example.flutter_doc_scanner

import android.app.Activity
import android.content.IntentSender
import android.net.Uri
import androidx.annotation.NonNull
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.InputStream

class FlutterDocScannerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private val REQUEST_CODE_SCAN = 213312
    private lateinit var resultChannel: MethodChannel.Result

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_doc_scanner")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        if (call.method == "scanDocument") {
            this.resultChannel = result
            activity?.let {
                scanDocument()
            } ?: result.error("NO_ACTIVITY", "Activity is null", null)
        } else {
            result.notImplemented()
        }
    }

    private fun scanDocument() {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()

        val scanner = GmsDocumentScanning.getClient(options)
        val task: Task<IntentSender>? = activity?.let { scanner.getStartScanIntent(it) }

        task?.addOnSuccessListener { intentSender ->
            try {
                activity?.startIntentSenderForResult(
                    intentSender,
                    REQUEST_CODE_SCAN,
                    null,
                    0,
                    0,
                    0,
                    null
                )
            } catch (e: Exception) {
                resultChannel.error("SCAN_ERROR", "Failed to start document scanner", e.message)
            }
        }?.addOnFailureListener { e ->
            resultChannel.error("SCAN_FAILED", "Document scanning failed", e.message)
        }
    }

    private fun readBytesFromUri(uri: Uri?): ByteArray? {
        if (activity == null || uri == null) return null
        return try {
            val inputStream: InputStream? = activity!!.contentResolver.openInputStream(uri)
            inputStream?.readBytes()
        } catch (e: Exception) {
            null
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addActivityResultListener { requestCode, resultCode, data ->
        if (requestCode == REQUEST_CODE_SCAN && resultCode == Activity.RESULT_OK) {
            val scanningResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
            val pages = scanningResult?.pages ?: emptyList()

            // Prepara la lista di ByteArray
            val imagesBytes = ArrayList<ByteArray>(pages.size)
            for (page in pages) {
                page.imageUri?.let { uri ->
                    readBytesFromUri(uri)?.let { bytes ->
                        imagesBytes.add(bytes)
                    }
                }
            }

            // Torniamo la lista al Dart side
            resultChannel.success(imagesBytes)
            true
        } else false
    }
}

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }
}