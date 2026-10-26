package org.schabi.driftloom.player

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.android.exoplayer2.ExoPlaybackException
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.upstream.DataSpec
import com.google.android.exoplayer2.upstream.HttpDataSource
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.schabi.driftloom.MainActivity
import org.schabi.driftloom.player.mediaitem.MediaItemTag
import org.schabi.driftloom.player.playqueue.SinglePlayQueue
import org.schabi.driftloom.util.InfoCache
import org.schabi.driftloom.util.NavigationHelper
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfo

/**
 * Opt-in live regression: pass -e youtubePlaybackUrl URL when invoking the test runner.
 * The fallback's decision logic is covered by the JVM test YoutubeHlsFallbackTest.
 */
@RunWith(AndroidJUnit4::class)
class YoutubePlaybackRegressionTest {
    @Test
    fun videoRecoversFrom403At59Seconds() = checkPlayback(audioOnly = false)

    @Test
    fun backgroundAudioRecoversFrom403At59Seconds() = checkPlayback(audioOnly = true)

    private fun httpError(code: Int) = ExoPlaybackException.createForSource(
        HttpDataSource.InvalidResponseCodeException(
            code,
            "HTTP error",
            null,
            emptyMap(),
            DataSpec(Uri.parse("https://example.invalid/videoplayback")),
            byteArrayOf()
        ),
        PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS
    )

    private fun checkPlayback(audioOnly: Boolean) {
        val url = InstrumentationRegistry.getArguments().getString("youtubePlaybackUrl")
        assumeTrue("Live YouTube test requires an explicit URL", url != null)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val info = StreamInfo.getInfo(ServiceList.YouTube, url!!)
        assertTrue("This test needs an HLS alternative", info.hlsUrl.isNotEmpty())
        InfoCache.getInstance().putInfo(info.serviceId, info.url, info, InfoCache.Type.STREAM)
        val connected = CountDownLatch(1)
        var service: PlayerService? = null
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                service = (binder as PlayerService.LocalBinder).service
                connected.countDown()
            }
            override fun onServiceDisconnected(name: ComponentName) {
                service = null
            }
        }
        val bindIntent = Intent(context, PlayerService::class.java)
            .setAction(PlayerService.BIND_PLAYER_HOLDER_ACTION)
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        var bound = false
        try {
            val queue = SinglePlayQueue(info, 50_000)
            val intent = NavigationHelper.getPlayerIntent(
                context,
                PlayerService::class.java,
                queue,
                PlayerIntentType.AllOthers
            ).putExtra(Player.PLAYER_TYPE, if (audioOnly) PlayerType.AUDIO else PlayerType.MAIN)
            context.startForegroundService(intent)
            bound = context.bindService(bindIntent, connection, Context.BIND_AUTO_CREATE)
            assertTrue("Could not bind playback service", bound)
            assertTrue("Playback service did not connect", connected.await(20, TimeUnit.SECONDS))
            var injected = false
            var reachedTarget = false
            var lastPosition = 0L
            val deadline = SystemClock.elapsedRealtime() + 150_000
            while (SystemClock.elapsedRealtime() < deadline) {
                instrumentation.runOnMainSync {
                    val player = service?.player ?: return@runOnMainSync
                    val exo = player.exoPlayer ?: return@runOnMainSync
                    exo.volume = 0f
                    lastPosition = exo.currentPosition
                    if (!injected && player.isPlaying && lastPosition >= 55_000) {
                        // Inject the same HTTP exception as the device report. This exercises the
                        // real Player callback, queue reload, position recovery and HLS source.
                        exo.seekTo(59_000)
                        injected = true
                        player.onPlayerError(httpError(403))
                    }
                    if (injected && lastPosition >= 100_000 && player.isPlaying) {
                        assertEquals("Recovery skipped the queue item", 0, checkNotNull(player.playQueue).index)
                        assertEquals(info.url, player.currentStreamInfo.orElseThrow().url)
                        assertTrue(
                            "Expected HLS metadata after recovery",
                            MediaItemTag.from(exo.currentMediaItem).orElseThrow()
                                .maybeQuality.isEmpty
                        )
                        reachedTarget = true
                    }
                }
                Log.i("YoutubePlaybackRegression", "audioOnly=$audioOnly injected=$injected positionMs=$lastPosition")
                if (reachedTarget) break
                SystemClock.sleep(2000)
            }
            assertTrue("Playback never reached the injection point: $lastPosition", injected)
            assertTrue("Playback did not recover past 100 seconds: $lastPosition", reachedTarget)
        } finally {
            instrumentation.runOnMainSync { service?.destroyPlayerAndStopService() }
            if (bound) context.unbindService(connection)
            context.stopService(Intent(context, PlayerService::class.java))
            scenario.close()
        }
    }
}
