package org.schabi.driftloom.util.text;

import android.content.Context;
import android.view.View;

import androidx.annotation.NonNull;

import org.schabi.driftloom.util.NavigationHelper;
import org.schabi.driftloom.util.external_communication.ShareUtils;

final class HashtagLongPressClickableSpan extends LongPressClickableSpan {

    @NonNull
    private final Context context;
    @NonNull
    private final String parsedHashtag;
    private final int relatedInfoServiceId;

    HashtagLongPressClickableSpan(@NonNull final Context context,
                                  @NonNull final String parsedHashtag,
                                  final int relatedInfoServiceId) {
        this.context = context;
        this.parsedHashtag = parsedHashtag;
        this.relatedInfoServiceId = relatedInfoServiceId;
    }

    @Override
    public void onClick(@NonNull final View view) {
        NavigationHelper.openSearch(context, relatedInfoServiceId, parsedHashtag);
    }

    @Override
    public void onLongClick(@NonNull final View view) {
        ShareUtils.copyToClipboard(context, parsedHashtag);
    }
}
