package io.github.alnajashia.dominanter.accessibility

import android.content.Context
import android.graphics.Bitmap
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

/**
 * Wraps the bundled NSFW classifier (MobileNetV2, GantMan/nsfw_model —
 * MIT License; see `assets/models/NSFW_MODEL_NOTICE.txt` for source and
 * attribution). Model I/O: 224x224 RGB float32 input normalized to
 * [0, 1]; softmax output over [drawings, hentai, neutral, porn, sexy],
 * in that alphabetical order (the Keras `flow_from_directory` class
 * ordering used to train the model, confirmed by the model release's
 * own `class_labels.txt`).
 *
 * Fully on-device: the interpreter is local, the bitmap never leaves
 * the process, and this class performs no I/O beyond reading the
 * bundled asset.
 *
 * Not thread-safe: callers must serialize calls to [predict] (the
 * accessibility service runs it on a single-thread executor).
 */
class NsfwContentDetector(context: Context) {

    companion object {
        private const val MODEL_PATH = "models/nsfw_model.tflite"
        const val INPUT_SIZE = 224
        private const val BYTES_PER_CHANNEL = 4 // float32
        val LABELS = listOf("drawings", "hentai", "neutral", "porn", "sexy")
    }

    private val interpreter: Interpreter = Interpreter(
        loadModelFile(context),
        Interpreter.Options().apply { setNumThreads(2) },
    )

    // Reused across calls to avoid per-frame allocations/GC pressure.
    private val inputBuffer: ByteBuffer = ByteBuffer
        .allocateDirect(INPUT_SIZE * INPUT_SIZE * 3 * BYTES_PER_CHANNEL)
        .order(ByteOrder.nativeOrder())
    private val output = Array(1) { FloatArray(LABELS.size) }
    private val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)

    private fun loadModelFile(context: Context): MappedByteBuffer {
        context.assets.openFd(MODEL_PATH).use { fd ->
            FileInputStream(fd.fileDescriptor).use { stream ->
                return stream.channel.map(
                    FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength,
                )
            }
        }
    }

    /**
     * Runs the classifier on [bitmap] and returns the softmax scores in
     * [LABELS] order. Runs inference synchronously on the calling
     * thread — invoke from a background executor. [bitmap] must be
     * software-backed (not [Bitmap.Config.HARDWARE]), and ideally
     * already cropped to the media element of interest — the model
     * expects the subject to fill the frame, so classifying a full app
     * screenshot dilutes it with UI chrome and hurts accuracy.
     */
    fun predict(bitmap: Bitmap): FloatArray {
        val scaled = if (bitmap.width == INPUT_SIZE && bitmap.height == INPUT_SIZE) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)
        }

        scaled.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
        if (scaled !== bitmap) scaled.recycle()

        inputBuffer.rewind()
        for (pixel in pixels) {
            inputBuffer.putFloat(((pixel shr 16) and 0xFF) / 255f)
            inputBuffer.putFloat(((pixel shr 8) and 0xFF) / 255f)
            inputBuffer.putFloat((pixel and 0xFF) / 255f)
        }

        interpreter.run(inputBuffer, output)
        return output[0].copyOf()
    }

    /**
     * Sum of the scores for [categories] (label names, see [LABELS])
     * from a [predict] result — the combined signal used to decide
     * blocking.
     */
    fun unsafeScore(scores: FloatArray, categories: Set<String>): Float {
        var sum = 0.0
        for (category in categories) {
            val index = LABELS.indexOf(category)
            if (index >= 0) sum += scores[index]
        }
        return sum.toFloat()
    }

    fun close() {
        interpreter.close()
    }
}
