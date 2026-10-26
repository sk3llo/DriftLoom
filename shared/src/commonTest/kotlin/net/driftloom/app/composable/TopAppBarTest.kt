/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.composable

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.v2.runComposeUiTest
import kotlin.test.Test
import kotlin.test.assertTrue
import net.driftloom.app.extensions.ComposeTest
import net.driftloom.app.extensions.settingsModule
import net.driftloom.app.extensions.withKoin
import driftloom.shared.generated.resources.Res
import driftloom.shared.generated.resources.navigate_back
import driftloom.shared.generated.resources.title_activity_about
import org.jetbrains.compose.resources.getString
import org.jetbrains.compose.resources.stringResource

@OptIn(ExperimentalTestApi::class)
class TopAppBarTest : ComposeTest() {

    @Test
    fun testTopAppBarHasNoNavigationByDefault() = runComposeUiTest {
        withKoin(
            modules = listOf(settingsModule()),
            content = {
                TopAppBar()
            },
            onContent = {
                onNodeWithContentDescription(getString(Res.string.navigate_back))
                    .assertDoesNotExist()
            }
        )
    }

    @Test
    fun testTopAppBarCanHaveNavigation() = runComposeUiTest {
        var navigationBackClicked = false
        withKoin(
            modules = listOf(settingsModule()),
            content = {
                TopAppBar(
                    title = stringResource(Res.string.title_activity_about),
                    onNavigateUp = { navigationBackClicked = true }
                )
            },
            onContent = {
                onNodeWithText(getString(Res.string.title_activity_about)).assertIsDisplayed()
                onNodeWithContentDescription(getString(Res.string.navigate_back)).apply {
                    assertExists()
                    performClick()
                    assertTrue(navigationBackClicked)
                }
            }
        )
    }
}
