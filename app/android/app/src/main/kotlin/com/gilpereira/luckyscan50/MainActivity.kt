package com.gilpereira.luckyscan50

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.floor

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val sessions = mutableMapOf<String, File>()
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "luckyscan50/receipt_crops")
            .setMethodCallHandler { call, result ->
                worker.execute {
                    try {
                        val response: Any? = when (call.method) {
                            "prepare" -> prepare(requireNotNull(call.argument<String>("path")))
                            "crop" -> crop(
                                requireNotNull(call.argument<String>("session")),
                                requireNotNull(call.argument<Number>("left")).toDouble(),
                                requireNotNull(call.argument<Number>("top")).toDouble(),
                                requireNotNull(call.argument<Number>("right")).toDouble(),
                                requireNotNull(call.argument<Number>("bottom")).toDouble(),
                                requireNotNull(call.argument<Number>("scale")).toDouble()
                            )
                            "rotate" -> rotate(
                                requireNotNull(call.argument<String>("session")),
                                requireNotNull(call.argument<Number>("turns")).toInt()
                            )
                            "dispose" -> {
                                sessions.remove(call.argument<String>("session"))?.deleteRecursively()
                                null
                            }
                            else -> throw IllegalArgumentException("Unsupported crop operation")
                        }
                        runOnUiThread { result.success(response) }
                    } catch (error: Exception) {
                        // Do not send receipt text, file paths or private pixels to logs.
                        runOnUiThread { result.error("receipt_crop_failed", error.javaClass.simpleName, null) }
                    } catch (error: OutOfMemoryError) {
                        runOnUiThread { result.error("receipt_crop_memory", "Image exceeds memory budget", null) }
                    }
                }
            }
    }

    private fun prepare(path: String): Map<String, Any> {
        val input = File(path).canonicalFile
        require(input.isFile) { "Image not found" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(input.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 &&
            bounds.outWidth.toLong() * bounds.outHeight <= 32000000L) { "Image size unsupported" }
        val directory = File(cacheDir, "receipt-pass-${UUID.randomUUID()}")
        require(directory.mkdirs())
        var source: Bitmap? = null
        var upright: Bitmap? = null
        try {
            source = requireNotNull(BitmapFactory.decodeFile(input.path))
            val matrix = Matrix()
            when (ExifInterface(input.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            }
            val normalized = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            upright = normalized
            val output = File(directory, "upright.png")
            output.outputStream().use { require(normalized.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            val id = directory.name
            sessions[id] = directory
            return mapOf("session" to id, "path" to output.path, "width" to normalized.width, "height" to normalized.height)
        } catch (error: Throwable) {
            directory.deleteRecursively()
            throw error
        } finally {
            if (upright !== source) upright?.recycle()
            source?.recycle()
        }
    }

    private fun rotate(session: String, turns: Int): Map<String, Any> {
        require(turns in 1..3)
        val previous = requireNotNull(sessions[session])
        val source = requireNotNull(BitmapFactory.decodeFile(File(previous, "upright.png").path))
        var rotated: Bitmap? = null
        val directory = File(cacheDir, "receipt-pass-${UUID.randomUUID()}")
        require(directory.mkdirs())
        try {
            val matrix = Matrix().apply { setRotate(turns * 90f) }
            val image = Bitmap.createBitmap(source, 0, 0, source.width, source.height, matrix, true)
            rotated = image
            val output = File(directory, "upright.png")
            output.outputStream().use { require(image.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            sessions[directory.name] = directory
            return mapOf("session" to directory.name, "path" to output.path, "width" to image.width, "height" to image.height)
        } catch (error: Throwable) {
            directory.deleteRecursively()
            throw error
        } finally {
            if (rotated !== source) rotated?.recycle()
            source.recycle()
        }
    }

    private fun crop(session: String, left: Double, top: Double, right: Double, bottom: Double, scale: Double): String {
        require(listOf(left, top, right, bottom, scale).all { it.isFinite() })
        require(scale == 1.0 || scale == 2.0)
        val directory = requireNotNull(sessions[session]) { "Unknown crop session" }
        val source = requireNotNull(BitmapFactory.decodeFile(File(directory, "upright.png").path))
        var part: Bitmap? = null
        var resized: Bitmap? = null
        try {
            val x = floor(left).toInt().coerceIn(0, source.width - 1)
            val y = floor(top).toInt().coerceIn(0, source.height - 1)
            val endX = ceil(right).toInt().coerceIn(x + 1, source.width)
            val endY = ceil(bottom).toInt().coerceIn(y + 1, source.height)
            require((endX - x).toLong() * (endY - y) * scale * scale <= 16000000)
            part = Bitmap.createBitmap(source, x, y, endX - x, endY - y)
            val outputBitmap = if (scale == 1.0) part else Bitmap.createScaledBitmap(part,
                (part.width * scale).toInt(), (part.height * scale).toInt(), true)
            resized = outputBitmap
            val output = File(directory, "row-${UUID.randomUUID()}.png")
            output.outputStream().use { require(outputBitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            return output.path
        } finally {
            if (resized !== part && resized !== source) resized?.recycle()
            if (part !== source) part?.recycle()
            source.recycle()
        }
    }

    override fun onDestroy() {
        worker.execute {
            sessions.values.forEach { it.deleteRecursively() }
            sessions.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }
}
