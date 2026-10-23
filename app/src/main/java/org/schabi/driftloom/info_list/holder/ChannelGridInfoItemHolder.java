package org.schabi.driftloom.info_list.holder;

import android.view.ViewGroup;

import org.schabi.driftloom.R;
import org.schabi.driftloom.info_list.InfoItemBuilder;

public class ChannelGridInfoItemHolder extends ChannelMiniInfoItemHolder {
    public ChannelGridInfoItemHolder(final InfoItemBuilder infoItemBuilder,
                                     final ViewGroup parent) {
        super(infoItemBuilder, R.layout.list_channel_grid_item, parent);
    }
}
