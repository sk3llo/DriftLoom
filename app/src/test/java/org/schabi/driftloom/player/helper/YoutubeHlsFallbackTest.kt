package org.schabi.driftloom.player.helper

import android.net.Uri
import com.google.android.exoplayer2.Format
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.PlaybackException
import com.google.android.exoplayer2.source.hls.HlsMediaSource
import com.google.android.exoplayer2.source.hls.playlist.HlsMultivariantPlaylist
import com.google.android.exoplayer2.upstream.DataSpec
import com.google.android.exoplayer2.upstream.HttpDataSource
import java.io.IOException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyString
import org.mockito.MockedStatic
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.schabi.driftloom.player.helper.YoutubeHlsFallback.Recovery
import org.schabi.driftloom.player.playqueue.PlayQueueItem
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamType

class YoutubeHlsFallbackTest {
    private lateinit var uri: MockedStatic<Uri>
    private lateinit var dataSource: PlayerDataSource
    private lateinit var factory: HlsMediaSource.Factory
    private lateinit var fallback: YoutubeHlsFallback

    @Before
    fun setUp() {
        // android.jar only contains stubs in JVM tests
        uri = mockStatic(Uri::class.java)
        uri.`when`<Uri> { Uri.parse(anyString()) }.thenAnswer { mock(Uri::class.java) }
        dataSource = mock(PlayerDataSource::class.java)
        factory = mock(HlsMediaSource.Factory::class.java)
        `when`(dataSource.youtubeHlsMediaSourceFactory).thenReturn(factory)
        `when`(factory.createMediaSource(any(MediaItem::class.java)))
            .thenReturn(mock(HlsMediaSource::class.java))
        fallback = YoutubeHlsFallback(dataSource)
    }

    @After
    fun tearDown() {
        uri.close()
    }

    @Test
    fun `A 403 switches the queue entry to HLS once and then refreshes once`() {
        val info = youtubeInfo()
        val item = PlayQueueItem(info)
        assertEquals(Recovery.NONE, fallback.onHttpError(item, info, httpError(404)))
        assertFalse(fallback.isEnabled(item))

        assertEquals(Recovery.USE_HLS, fallback.onHttpError(item, info, httpError(403)))
        assertTrue(fallback.isEnabled(item))
        assertEquals(
            "An expired HLS URL gets one retry with fresh info",
            Recovery.REFRESH_HLS,
            fallback.onHttpError(item, info, httpError(403))
        )
        assertEquals(
            "A failed refreshed HLS source must not loop",
            Recovery.NONE,
            fallback.onHttpError(item, info, httpError(403))
        )
    }

    @Test
    fun `Each queue entry gets its own attempt`() {
        val info = youtubeInfo()
        val first = PlayQueueItem(info)
        val second = PlayQueueItem(info)
        assertEquals(Recovery.USE_HLS, fallback.onHttpError(first, info, httpError(403)))
        assertFalse(fallback.isEnabled(second))
        assertEquals(Recovery.USE_HLS, fallback.onHttpError(second, info, httpError(403)))
    }

    @Test
    fun `Only YouTube videos with an HLS stream are eligible`() {
        val live = youtubeInfo().apply { streamType = StreamType.LIVE_STREAM }
        assertEquals(Recovery.NONE, fallback.onHttpError(PlayQueueItem(live), live, httpError(403)))

        val noHls = youtubeInfo().apply { hlsUrl = "" }
        assertEquals(Recovery.NONE, fallback.onHttpError(PlayQueueItem(noHls), noHls, httpError(403)))

        val other = StreamInfo(
            ServiceList.SoundCloud.serviceId,
            URL,
            URL,
            StreamType.VIDEO_STREAM,
            "fixture",
            "Regression fixture",
            0
        ).apply { hlsUrl = HLS_URL }
        assertEquals(Recovery.NONE, fallback.onHttpError(PlayQueueItem(other), other, httpError(403)))
    }

    @Test
    fun `Disabling restores the regular streams and allows a later fallback`() {
        val info = youtubeInfo()
        val item = PlayQueueItem(info)
        fallback.onHttpError(item, info, httpError(403))
        fallback.onHttpError(item, info, httpError(403))

        fallback.disable(item)
        assertFalse(fallback.isEnabled(item))
        assertNull(fallback.resolve(item, info, false))
        assertEquals(Recovery.USE_HLS, fallback.onHttpError(item, info, httpError(403)))
    }

    @Test
    fun `Only enabled entries resolve to the HLS source`() {
        val info = youtubeInfo()
        val item = PlayQueueItem(info)
        assertNull(fallback.resolve(item, info, false))
        verify(factory, never()).createMediaSource(any(MediaItem::class.java))

        fallback.onHttpError(item, info, httpError(403))
        assertNotNull(fallback.resolve(item, info, false))
        verify(factory, never()).setPlaylistParserFactory(any())

        assertNotNull(fallback.resolve(item, info, true))
        verify(factory).setPlaylistParserFactory(any())
    }

    @Test
    fun `Audio-only playback keeps the lowest variant and all audio renditions`() {
        val playlist = HlsMultivariantPlaylist(
            "https://example.invalid/master.m3u8",
            emptyList(),
            listOf(variant(2_000_000), variant(150_000), variant(800_000)),
            emptyList(),
            listOf(rendition("en"), rendition("de")),
            emptyList(),
            emptyList(),
            null,
            null,
            false,
            emptyMap(),
            emptyList()
        )

        val filtered = YoutubeHlsFallback.keepLowestVariant(playlist)
        assertEquals(1, filtered.variants.size)
        assertEquals(150_000, filtered.variants[0].format.bitrate)
        assertEquals(2, filtered.audios.size)

        val single = HlsMultivariantPlaylist(
            "https://example.invalid/master.m3u8",
            emptyList(),
            listOf(variant(800_000)),
            emptyList(),
            emptyList(),
            emptyList(),
            emptyList(),
            null,
            null,
            false,
            emptyMap(),
            emptyList()
        )
        assertSame(single, YoutubeHlsFallback.keepLowestVariant(single))
    }

    private fun youtubeInfo() = StreamInfo(
        ServiceList.YouTube.serviceId,
        URL,
        URL,
        StreamType.VIDEO_STREAM,
        "11-9ZaYiTPE",
        "Regression fixture",
        0
    ).apply { hlsUrl = HLS_URL }

    private fun variant(bitrate: Int) = HlsMultivariantPlaylist.Variant(
        mock(Uri::class.java),
        Format.Builder().setPeakBitrate(bitrate).build(),
        null,
        "audio",
        null,
        null
    )

    private fun rendition(language: String) = HlsMultivariantPlaylist.Rendition(
        mock(Uri::class.java),
        Format.Builder().setLabel(language).build(),
        "audio",
        language
    )

    private fun httpError(code: Int): PlaybackException {
        // Creating a real PlaybackException reads android.os.SystemClock
        val error = mock(PlaybackException::class.java)
        val cause: IOException = HttpDataSource.InvalidResponseCodeException(
            code,
            "HTTP error",
            null,
            emptyMap(),
            DataSpec(mock(Uri::class.java)),
            byteArrayOf()
        )
        `when`(error.cause).thenReturn(cause)
        return error
    }

    companion object {
        private const val URL = "https://www.youtube.com/watch?v=11-9ZaYiTPE"
        private const val HLS_URL = "https://example.invalid/master.m3u8"
    }
}
