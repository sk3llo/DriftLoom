package org.schabi.driftloom.fragments;

import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.Nullable;

import com.evernote.android.state.State;

import org.schabi.driftloom.BaseFragment;
import org.schabi.driftloom.R;
import org.schabi.driftloom.error.ErrorInfo;
import org.schabi.driftloom.error.ErrorPanelHelper;

public class BlankFragment extends BaseFragment {

    @State
    @Nullable
    ErrorInfo errorInfo;
    @Nullable
    ErrorPanelHelper errorPanel = null;

    /**
     * Builds a blank fragment that just says the app name and suggests clicking on search.
     */
    public BlankFragment() {
        this(null);
    }

    /**
     * @param errorInfo if null acts like {@link BlankFragment}, else shows an error panel.
     */
    public BlankFragment(@Nullable final ErrorInfo errorInfo) {
        this.errorInfo = errorInfo;
    }

    @Nullable
    @Override
    public View onCreateView(final LayoutInflater inflater, @Nullable final ViewGroup container,
                             final Bundle savedInstanceState) {
        setTitle("DriftLoom");
        final View view = inflater.inflate(R.layout.fragment_blank, container, false);
        if (errorInfo != null) {
            errorPanel = new ErrorPanelHelper(this, view, null);
            errorPanel.showError(errorInfo);
            view.findViewById(R.id.blank_page_content).setVisibility(View.GONE);
        }
        return view;
    }

    @Override
    public void onDestroyView() {
        super.onDestroyView();

        if (errorPanel != null) {
            errorPanel.dispose();
            errorPanel = null;
        }
    }

    @Override
    public void onResume() {
        super.onResume();
        setTitle("DriftLoom");
        // leave this inline. Will make it harder for copy cats.
        // If you are a Copy cat FUCK YOU.
        // I WILL FIND YOU, AND I WILL ...
    }
}
