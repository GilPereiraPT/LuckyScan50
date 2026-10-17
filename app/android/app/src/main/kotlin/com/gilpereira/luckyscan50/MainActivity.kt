package com.gilpereira.luckyscan50

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.Rect
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
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
    private val decoders = mutableMapOf<String, BitmapRegionDecoder>()
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
                                requireNotNull(call.argument<Number>("scale")).toDouble(),
                                call.argument<Number>("deskewDegrees")?.toDouble() ?: 0.0,
                                call.argument<Boolean>("contrast") ?: false
                            )
                            "luminance" -> luminance(requireNotNull(call.argument<String>("session")))
                            "rotate" -> rotate(
                                requireNotNull(call.argument<String>("session")),
                                requireNotNull(call.argument<Number>("turns")).toInt()
                            )
                            "dispose" -> {
                                val id = call.argument<String>("session")
                                decoders.remove(id)?.recycle()
                                sessions.remove(id)?.deleteRecursively()
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

    private fun luminance(session: String): Map<String, Any> {
        val input = File(requireNotNull(sessions[session]), "upright.png")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(input.path, bounds)
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1024) sample *= 2
        val bitmap = requireNotNull(BitmapFactory.decodeFile(input.path,
            BitmapFactory.Options().apply { inSampleSize = sample }))
        try {
            val pixels = IntArray(bitmap.width * bitmap.height)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            val gray = ByteArray(pixels.size) { i ->
                val color = pixels[i]
                (((color shr 16 and 255) * 77 + (color shr 8 and 255) * 150 +
                    (color and 255) * 29) shr 8).toByte()
            }
            return mapOf("width" to bitmap.width, "height" to bitmap.height, "pixels" to gray)
        } finally { bitmap.recycle() }
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

    @Suppress("DEPRECATION")
    private fun crop(session: String, left: Double, top: Double, right: Double, bottom: Double,
                     scale: Double, deskewDegrees: Double, contrast: Boolean): String {
        require(listOf(left, top, right, bottom, scale, deskewDegrees).all { it.isFinite() })
        require(scale == 1.0 || scale == 2.0)
        require(kotlin.math.abs(deskewDegrees) <= 15.0)
        val directory = requireNotNull(sessions[session]) { "Unknown crop session" }
        val decoder = decoders.getOrPut(session) {
            requireNotNull(BitmapRegionDecoder.newInstance(File(directory, "upright.png").path, false))
        }
        val bitmaps = mutableListOf<Bitmap>()
        try {
            val x = floor(left).toInt().coerceIn(0, decoder.width - 1)
            val y = floor(top).toInt().coerceIn(0, decoder.height - 1)
            val endX = ceil(right).toInt().coerceIn(x + 1, decoder.width)
            val endY = ceil(bottom).toInt().coerceIn(y + 1, decoder.height)
            require((endX - x).toLong() * (endY - y) * scale * scale <= 16000000)
            var image = requireNotNull(decoder.decodeRegion(Rect(x, y, endX, endY), null))
            bitmaps.add(image)
            if (kotlin.math.abs(deskewDegrees) > 0.05) {
                val matrix = Matrix().apply { setRotate(-deskewDegrees.toFloat()) }
                image = Bitmap.createBitmap(image, 0, 0, image.width, image.height, matrix, true)
                bitmaps.add(image)
                val opaque = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
                Canvas(opaque).apply {
                    drawColor(android.graphics.Color.WHITE)
                    drawBitmap(image, 0f, 0f, null)
                }
                image = opaque
                bitmaps.add(image)
            }
            if (contrast) {
                val adjusted = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
                val filter = ColorMatrixColorFilter(ColorMatrix(floatArrayOf(
                    1.4f,0f,0f,0f,-51f, 0f,1.4f,0f,0f,-51f,
                    0f,0f,1.4f,0f,-51f, 0f,0f,0f,1f,0f)))
                Canvas(adjusted).drawBitmap(image, 0f, 0f, Paint().apply { colorFilter = filter })
                image = adjusted
                bitmaps.add(image)
            }
            if (scale != 1.0) {
                image = Bitmap.createScaledBitmap(image, (image.width * scale).toInt(), (image.height * scale).toInt(), true)
                bitmaps.add(image)
            }
            val output = File(directory, "cell-${UUID.randomUUID()}.png")
            output.outputStream().use { require(image.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            return output.path
        } finally {
            bitmaps.distinct().forEach { it.recycle() }
        }
    }

    override fun onDestroy() {
        worker.execute {
            decoders.values.forEach { it.recycle() }
            decoders.clear()
            sessions.values.forEach { it.deleteRecursively() }
            sessions.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }
}
