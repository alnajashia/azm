package com.alnajashia.azm.challenges

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import io.flutter.FlutterInjector
import java.util.concurrent.ConcurrentHashMap

/** Tetris challenge sounds (Batch I-C, item 2): a port of Dechainer's
 * `TetrisSounds` (Apache-2.0). The 8 sounds are the same synthesis
 * recipe (tone / arpeggio at 22,050 Hz, same durations, frequencies,
 * decays and noise mixes), but the WAVs are pre-generated at
 * implementation time and bundled as Flutter assets — so this class
 * loads them from the asset bundle instead of synthesising them into
 * the cache dir at runtime. SoundPool, max 4 streams, played only
 * when the ringer mode is normal, like the original. */
enum class TetrisSound(val fileName: String, val volume: Float) {
    MOVE("move.wav", 0.25f),
    ROTATE("rotate.wav", 0.35f),
    LOCK("lock.wav", 0.5f),
    HARD_DROP("hard_drop.wav", 0.7f),
    CLEAR("clear.wav", 0.55f),
    CLEAR_BIG("clear_big.wav", 0.6f),
    LEVEL_UP("level_up.wav", 0.55f),
    TOP_OUT("top_out.wav", 0.5f);
}

class TetrisSounds(private val context: Context) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(4)
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        .build()
    private val ids = ConcurrentHashMap<TetrisSound, Int>()
    private val audioManager = context.getSystemService(AudioManager::class.java)

    @Volatile
    private var released = false

    /** Loads all 8 sounds from the Flutter asset bundle. Idempotent. */
    fun load() {
        if (released) return
        val loader = FlutterInjector.instance().flutterLoader()
        for (sound in TetrisSound.entries) {
            if (released) return
            if (ids.containsKey(sound)) continue
            val assetPath = loader.getLookupKeyForAsset(
                "sounds/tetris/${sound.fileName}",
            )
            runCatching {
                context.assets.openFd(assetPath).use { fd ->
                    pool.load(fd, 1)
                }
            }.onSuccess { ids[sound] = it }
        }
    }

    fun play(sound: TetrisSound) {
        if (released || audioManager?.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val id = ids[sound] ?: return
        pool.play(id, sound.volume, sound.volume, 1, 0, 1f)
    }

    fun release() {
        released = true
        pool.release()
    }
}
