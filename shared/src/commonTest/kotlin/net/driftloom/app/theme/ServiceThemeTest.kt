/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.theme

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.v2.runComposeUiTest
import com.russhwolf.settings.MapSettings
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import net.driftloom.app.Constants.KEY_STREAMING_SERVICE
import net.driftloom.app.extensions.ComposeTest
import net.driftloom.app.extensions.settingsModule
import net.driftloom.app.extensions.withKoin

@OptIn(ExperimentalTestApi::class)
class ServiceThemeTest : ComposeTest() {

    @Test
    fun testDefaultServiceIsYouTube() = runComposeUiTest {
        withKoin(
            modules = listOf(settingsModule()),
            content = {
                assertEquals(currentService(), Service.YOUTUBE)
            }
        )
    }

    @Test
    fun testServiceSwitchingWorks() = runComposeUiTest {
        withKoin(
            modules = listOf(settingsModule(MapSettings(KEY_STREAMING_SERVICE to "PeerTube"))),
            content = {
                assertNotEquals(currentService(), Service.YOUTUBE)
                assertEquals(currentService(), Service.PEERTUBE)
            }
        )
    }
}
