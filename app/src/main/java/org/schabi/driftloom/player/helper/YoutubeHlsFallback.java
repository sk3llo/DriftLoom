package org.schabi.driftloom.player.helper;

import android.net.Uri;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.google.android.exoplayer2.PlaybackException;
import com.google.android.exoplayer2.offline.StreamKey;
import com.google.android.exoplayer2.source.MediaSource;
import com.google.android.exoplayer2.source.hls.HlsMediaSource;
import com.google.android.exoplayer2.source.hls.playlist.DefaultHlsPlaylistParserFactory;
import com.google.android.exoplayer2.source.hls.playlist.HlsMediaPlaylist;
import com.google.android.exoplayer2.source.hls.playlist.HlsMultivariantPlaylist;
import com.google.android.exoplayer2.source.hls.playlist.HlsPlaylist;
import com.google.android.exoplayer2.source.hls.playlist.HlsPlaylistParserFactory;
import com.google.android.exoplayer2.upstream.HttpDataSource;
import com.google.android.exoplayer2.upstream.ParsingLoadable;

import org.schabi.newpipe.extractor.ServiceList;
import org.schabi.newpipe.extractor.stream.StreamInfo;
import org.schabi.newpipe.extractor.stream.StreamType;
import org.schabi.driftloom.player.mediaitem.StreamInfoTag;
import org.schabi.driftloom.player.playqueue.PlayQueueItem;

import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.WeakHashMap;

/**
 * Tries an alternative YouTube transport after a media HTTP 403.
 *
 * <p>Each queue entry gets one switch to HLS. If the HLS source is rejected as well (typically
 * because the cached stream info, and with it the manifest URL, expired), the entry gets one more
 * attempt with freshly extracted info before the error is treated as a source error.</p>
 */
public final class YoutubeHlsFallback {
    public enum Recovery {
        /** Not a recoverable YouTube 403: handle the error as before. */
        NONE,
        /** Switch this queue entry to its HLS stream. */
        USE_HLS,
        /** The HLS stream was rejected too: extract the stream info again and retry once. */
        REFRESH_HLS
    }

    private final PlayerDataSource dataSource;
    // Keep the selection when the player changes between foreground and background, without
    // retaining entries which have been removed from the queue.
    private final Set<PlayQueueItem> enabledItems =
            Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));
    private final Set<PlayQueueItem> refreshedItems =
            Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));

    public YoutubeHlsFallback(final PlayerDataSource dataSource) {
        this.dataSource = dataSource;
    }

    @NonNull
    public Recovery onHttpError(final PlayQueueItem item, final StreamInfo info,
                                final PlaybackException error) {
        if (info.getServiceId() != ServiceList.YouTube.getServiceId()
                || info.getStreamType() != StreamType.VIDEO_STREAM
                || info.getHlsUrl() == null || info.getHlsUrl().isEmpty()
                || !isForbidden(error)) {
            return Recovery.NONE;
        }
        if (enabledItems.add(item)) {
            return Recovery.USE_HLS;
        }
        if (refreshedItems.add(item)) {
            return Recovery.REFRESH_HLS;
        }
        return Recovery.NONE;
    }

    public boolean isEnabled(@Nullable final PlayQueueItem item) {
        return item != null && enabledItems.contains(item);
    }

    /**
     * Returns the entry to its regular streams, e.g. after the user picked a quality explicitly.
     * A later 403 can switch it to HLS again.
     *
     * @param item the queue entry to reset
     */
    public void disable(@Nullable final PlayQueueItem item) {
        if (item != null) {
            enabledItems.remove(item);
            refreshedItems.remove(item);
        }
    }

    /**
     * @param item      the queue entry being resolved
     * @param info      its stream info
     * @param audioOnly whether only the audio is played; the lowest video variant is then
     *                  selected, since disabling the video renderer doesn't stop HLS from
     *                  downloading the variant's video segments
     * @return the HLS source if this entry uses the fallback, otherwise {@code null}
     */
    @Nullable
    public MediaSource resolve(final PlayQueueItem item, final StreamInfo info,
                               final boolean audioOnly) {
        if (!enabledItems.contains(item) || info.getHlsUrl() == null
                || info.getHlsUrl().isEmpty()) {
            return null;
        }
        final HlsMediaSource.Factory factory = dataSource.getYoutubeHlsMediaSourceFactory();
        if (audioOnly) {
            factory.setPlaylistParserFactory(new LowestVariantParserFactory());
        }
        return factory.createMediaSource(StreamInfoTag.of(info).asMediaItem().buildUpon()
                .setUri(info.getHlsUrl()).build());
    }

    private static boolean isForbidden(final PlaybackException error) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause instanceof HttpDataSource.InvalidResponseCodeException) {
                return ((HttpDataSource.InvalidResponseCodeException) cause).responseCode == 403;
            }
        }
        return false;
    }

    /**
     * Keeps only the lowest-bitrate variant of a multivariant playlist, together with all of its
     * alternative audio renditions.
     *
     * @param playlist the parsed multivariant playlist
     * @return the filtered playlist, or the same one if there is nothing to choose from
     */
    @NonNull
    static HlsMultivariantPlaylist keepLowestVariant(
            @NonNull final HlsMultivariantPlaylist playlist) {
        if (playlist.variants.size() <= 1) {
            return playlist;
        }
        int lowest = 0;
        for (int i = 1; i < playlist.variants.size(); i++) {
            if (playlist.variants.get(i).format.bitrate
                    < playlist.variants.get(lowest).format.bitrate) {
                lowest = i;
            }
        }
        final List<StreamKey> keys = new ArrayList<>();
        keys.add(new StreamKey(HlsMultivariantPlaylist.GROUP_INDEX_VARIANT, lowest));
        for (int i = 0; i < playlist.audios.size(); i++) {
            keys.add(new StreamKey(HlsMultivariantPlaylist.GROUP_INDEX_AUDIO, i));
        }
        return playlist.copy(keys);
    }

    private static final class LowestVariantParserFactory implements HlsPlaylistParserFactory {
        private final HlsPlaylistParserFactory base = new DefaultHlsPlaylistParserFactory();

        @NonNull
        @Override
        public ParsingLoadable.Parser<HlsPlaylist> createPlaylistParser() {
            final ParsingLoadable.Parser<HlsPlaylist> parser = base.createPlaylistParser();
            return (final Uri uri, final InputStream inputStream) -> {
                final HlsPlaylist playlist = parser.parse(uri, inputStream);
                return playlist instanceof HlsMultivariantPlaylist
                        ? keepLowestVariant((HlsMultivariantPlaylist) playlist) : playlist;
            };
        }

        @NonNull
        @Override
        public ParsingLoadable.Parser<HlsPlaylist> createPlaylistParser(
                @NonNull final HlsMultivariantPlaylist multivariantPlaylist,
                @Nullable final HlsMediaPlaylist previousMediaPlaylist) {
            return base.createPlaylistParser(multivariantPlaylist, previousMediaPlaylist);
        }
    }
}
