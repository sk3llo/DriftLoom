/*
 * SPDX-FileCopyrightText: 2025 NewPipe contributors <https://newpipe.net>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package org.schabi.driftloom.local.playlist

import android.content.Context
import org.schabi.driftloom.R
import org.schabi.driftloom.database.playlist.PlaylistStreamEntry
import org.schabi.driftloom.local.playlist.PlayListShareMode.JUST_URLS
import org.schabi.driftloom.local.playlist.PlayListShareMode.WITH_TITLES
import org.schabi.driftloom.local.playlist.PlayListShareMode.YOUTUBE_TEMP_PLAYLIST
import org.schabi.newpipe.extractor.exceptions.ParsingException
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeStreamLinkHandlerFactory

fun export(
    shareMode: PlayListShareMode,
    playlist: List<PlaylistStreamEntry>,
    context: Context
): String {
    return when (shareMode) {
        WITH_TITLES -> exportWithTitles(playlist, context)
        JUST_URLS -> exportJustUrls(playlist)
        YOUTUBE_TEMP_PLAYLIST -> exportAsYoutubeTempPlaylist(playlist)
    }
}

private fun exportWithTitles(playlist: List<PlaylistStreamEntry>, context: Context): String {
    return playlist.asSequence()
        .map { it.streamEntity }
        .map { entity ->
            context.getString(
                R.string.video_details_list_item,
                entity.title,
                entity.url
            )
        }
        .joinToString(separator = "\n")
}

private fun exportJustUrls(playlist: List<PlaylistStreamEntry>): String {
    return playlist.joinToString(separator = "\n") { it.streamEntity.url }
}

private fun exportAsYoutubeTempPlaylist(playlist: List<PlaylistStreamEntry>): String {
    val videoIDs = playlist.asReversed().asSequence()
        .mapNotNull { getYouTubeId(it.streamEntity.url) }
        .take(50) // YouTube limitation: temp playlists can't have more than 50 items
        .toList()
        .asReversed()
        .joinToString(separator = ",")

    return "https://www.youtube.com/watch_videos?video_ids=$videoIDs"
}

private val linkHandler: YoutubeStreamLinkHandlerFactory = YoutubeStreamLinkHandlerFactory.getInstance()

/**
 * Gets the video id from a YouTube URL.
 *
 * @param url YouTube URL
 * @return the video id
 */
private fun getYouTubeId(url: String): String? {
    return runCatching { linkHandler.getId(url) }.getOrNull()
}
