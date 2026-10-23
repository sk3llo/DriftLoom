package org.schabi.driftloom.views;

import android.content.Context;
import android.util.AttributeSet;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.widget.AppCompatEditText;

import org.schabi.driftloom.util.DriftLoomTextViewHelper;
import org.schabi.driftloom.util.external_communication.ShareUtils;

/**
 * An {@link AppCompatEditText} which uses {@link ShareUtils#shareText(Context, String, String)}
 * when sharing selected text by using the {@code Share} command of the floating actions.
 *
 * <p>
 * This class allows DriftLoom to show Android share sheet instead of EMUI share sheet when sharing
 * text from {@link AppCompatEditText} on EMUI devices.
 * </p>
 */
public class DriftLoomEditText extends AppCompatEditText {

    public DriftLoomEditText(@NonNull final Context context) {
        super(context);
    }

    public DriftLoomEditText(@NonNull final Context context, @Nullable final AttributeSet attrs) {
        super(context, attrs);
    }

    public DriftLoomEditText(@NonNull final Context context,
                           @Nullable final AttributeSet attrs,
                           final int defStyleAttr) {
        super(context, attrs, defStyleAttr);
    }

    @Override
    public boolean onTextContextMenuItem(final int id) {
        if (id == android.R.id.shareText) {
            DriftLoomTextViewHelper.shareSelectedTextWithShareUtils(this);
            return true;
        }
        return super.onTextContextMenuItem(id);
    }
}
