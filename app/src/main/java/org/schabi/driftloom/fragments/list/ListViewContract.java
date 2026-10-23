package org.schabi.driftloom.fragments.list;

import org.schabi.driftloom.fragments.ViewContract;

public interface ListViewContract<I, N> extends ViewContract<I> {
    void showListFooter(boolean show);

    void handleNextItems(N result);
}
