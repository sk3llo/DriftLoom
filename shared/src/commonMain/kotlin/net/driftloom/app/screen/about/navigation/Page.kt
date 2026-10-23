/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.screen.about.navigation

import driftloom.shared.generated.resources.Res
import driftloom.shared.generated.resources.tab_about
import driftloom.shared.generated.resources.tab_licenses
import org.jetbrains.compose.resources.StringResource

/**
 * Possible pages to show in about screen
 */
enum class Page(val localizedTitle: StringResource) {
    ABOUT(Res.string.tab_about),
    LICENSE(Res.string.tab_licenses)
}
