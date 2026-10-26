/*
* SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
* SPDX-License-Identifier: GPL-3.0-or-later
*/

package net.driftloom.app.screen.settings

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.v2.runComposeUiTest
import net.driftloom.app.extensions.ComposeTest
import net.driftloom.app.extensions.settingsModule
import net.driftloom.app.extensions.withKoin
import net.driftloom.app.screen.settings.model.SettingsCategory
import kotlin.test.Test
import kotlin.test.assertTrue
import driftloom.shared.generated.resources.Res
import driftloom.shared.generated.resources.ic_headset
import driftloom.shared.generated.resources.settings
import driftloom.shared.generated.resources.settings_category_video_audio_title
import org.jetbrains.compose.resources.getString

@OptIn(ExperimentalTestApi::class)
class SettingsHomeScreenTest : ComposeTest() {

    @Test
    fun testTitleAndCategoriesRender() = runComposeUiTest {
        withKoin(
            modules = listOf(settingsModule()),
            content = { SettingsHomeScreenContent() },
            onContent = {
                onNodeWithText(getString(Res.string.settings)).assertIsDisplayed()
                onNodeWithText(getString(Res.string.settings_category_video_audio_title))
                    .assertIsDisplayed()
            }
        )
    }

    @Test
    fun testCategoryClickFires() = runComposeUiTest {
        var clicked = false
        val categories = listOf(
            SettingsCategory(
                title = Res.string.settings_category_video_audio_title,
                icon = Res.drawable.ic_headset,
                onClick = { clicked = true }
            )
        )
        withKoin(
            modules = listOf(settingsModule()),
            content = { SettingsHomeScreenContent(categories = categories) },
            onContent = {
                onNodeWithText(getString(Res.string.settings_category_video_audio_title))
                    .performClick()
                assertTrue(clicked)
            }
        )
    }
}
