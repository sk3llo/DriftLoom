/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app

import androidx.compose.ui.window.ComposeUIViewController

fun mainViewController() = ComposeUIViewController {
    App(
        onCloseRequest = {}
    )
}
