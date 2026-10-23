package org.schabi.driftloom.player.helper;

import androidx.annotation.Nullable;

import com.google.android.exoplayer2.PlaybackException;
import com.google.android.exoplayer2.source.MediaSource;
import com.google.android.exoplayer2.upstream.HttpDataSource;

import org.schabi.newpipe.extractor.ServiceList;
import org.schabi.newpipe.extractor.stream.StreamInfo;
import org.schabi.newpipe.extractor.stream.StreamType;
import org.schabi.driftloom.player.mediaitem.StreamInfoTag;
import org.schabi.driftloom.player.playqueue.PlayQueueItem;

import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;

/** Tries an alternative YouTube transport once per queue entry after a media HTTP 403. */
public final class YoutubeHlsFallback {
    private final PlayerDataSource dataSource;
    // Keep the selection when the player changes between foreground and background, without
    // retaining entries which have been removed from the queue.
    private final Set<PlayQueueItem> enabledItems =
            Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));

    public YoutubeHlsFallback(final PlayerDataSource dataSource) {
        this.dataSource = dataSource;
    }

    public boolean tryEnable(final PlayQueueItem item, final StreamInfo info,
                             final PlaybackException error) {
        if (info.getServiceId() != ServiceList.YouTube.getServiceId()
                || info.getStreamType() != StreamType.VIDEO_STREAM
                || info.getHlsUrl() == null || info.getHlsUrl().isEmpty()
                || enabledItems.contains(item)) {
            return false;
        }
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause instanceof HttpDataSource.InvalidResponseCodeException) {
                final HttpDataSource.InvalidResponseCodeException httpError =
                        (HttpDataSource.InvalidResponseCodeException) cause;
                if (httpError.responseCode == 403) {
                    enabledItems.add(item);
                    return true;
                }
                return false;
            }
        }
        return false;
    }

    @Nullable
    public MediaSource resolve(final PlayQueueItem item, final StreamInfo info) {
        if (!enabledItems.contains(item) || info.getHlsUrl() == null
                || info.getHlsUrl().isEmpty()) {
            return null;
        }
        return dataSource.getYoutubeHlsMediaSourceFactory().createMediaSource(
                StreamInfoTag.of(info).asMediaItem().buildUpon()
                        .setUri(info.getHlsUrl()).build());
    }
}
