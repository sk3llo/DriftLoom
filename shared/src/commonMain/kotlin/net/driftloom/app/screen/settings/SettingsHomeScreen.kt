/*
* SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
* SPDX-License-Identifier: GPL-3.0-or-later
*/

package net.driftloom.app.screen.settings

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.PreviewLightDark
import androidx.compose.ui.tooling.preview.PreviewWrapper
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import net.driftloom.app.composable.PreferenceRow
import net.driftloom.app.composable.TopAppBar
import net.driftloom.app.navigation.Navigator
import net.driftloom.app.preview.ThemePreviewProvider
import net.driftloom.app.screen.settings.model.SettingsCategory
import net.driftloom.app.screen.settings.model.SettingsCategoryType
import net.driftloom.app.viewmodel.settings.SettingsViewModel
import driftloom.shared.generated.resources.Res
import driftloom.shared.generated.resources.ic_search
import driftloom.shared.generated.resources.search
import driftloom.shared.generated.resources.settings
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.stringResource
import org.koin.compose.koinInject
import org.koin.compose.viewmodel.koinViewModel

@Composable
fun SettingsHomeScreen(
    navigator: Navigator = koinInject(),
    viewModel: SettingsViewModel = koinViewModel()
) {
    val categories by viewModel.categories.collectAsStateWithLifecycle()

    SettingsHomeScreenContent(
        categories = categories.map { type ->
            SettingsCategory(
                title = type.title,
                icon = type.icon,
                // TODO: Replace with a Destination once sub-screens are migrated
                onClick = {}
            )
        },
        onNavigateUp = { navigator.navigateUp() }
    )
}

@Composable
fun SettingsHomeScreenContent(
    categories: List<SettingsCategory> = SettingsCategoryType.entries.map { type ->
        SettingsCategory(title = type.title, icon = type.icon)
    },
    onNavigateUp: () -> Unit = {},
    onSearchClick: () -> Unit = {}
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = stringResource(Res.string.settings),
                onNavigateUp = onNavigateUp,
                actions = {
                    IconButton(onClick = onSearchClick) {
                        Icon(
                            painter = painterResource(Res.drawable.ic_search),
                            contentDescription = stringResource(Res.string.search)
                        )
                    }
                }
            )
        }
    ) { paddingValues ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = paddingValues.calculateTopPadding()),
            contentPadding = WindowInsets.navigationBars.asPaddingValues()
        ) {
            items(items = categories) { category ->
                PreferenceRow(
                    title = stringResource(category.title),
                    icon = painterResource(category.icon),
                    onClick = category.onClick
                )
            }
        }
    }
}

@PreviewWrapper(ThemePreviewProvider::class)
@PreviewLightDark
@Composable
private fun SettingsHomeScreenPreview() {
    SettingsHomeScreenContent()
}
