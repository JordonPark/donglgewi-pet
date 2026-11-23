package com.jordonpark.donglgewi

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.label.ImageLabeling
import com.google.mlkit.vision.label.defaults.ImageLabelerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "donglgewi/photos")
            .setMethodCallHandler { call, result ->
                if (call.method != "analyze") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path.isNullOrBlank()) {
                    result.error("invalid_path", "An image path is required.", null)
                    return@setMethodCallHandler
                }
                classifyPhoto(path, result)
            }
    }

    private fun classifyPhoto(path: String, result: MethodChannel.Result) {
        val image = try {
            InputImage.fromFilePath(applicationContext, Uri.fromFile(File(path)))
        } catch (_: Exception) {
            result.error("unreadable_image", "Could not open the image.", null)
            return
        }
        val classifier = ImageLabeling.getClient(
            ImageLabelerOptions.Builder().setConfidenceThreshold(0.55f).build()
        )
        classifier.process(image).addOnCompleteListener { task ->
            try {
                if (task.isSuccessful) {
                    result.success(task.result.sortedByDescending { it.confidence }.take(5).map { it.text })
                } else {
                    result.error("analysis_failed", "Image analysis failed.", null)
                }
            } finally {
                classifier.close()
            }
        }
    }
}
