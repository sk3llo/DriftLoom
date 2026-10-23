/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

/**
 * Entry point for compose-related UI components on Desktop
 */
fun main() = application {
    Window(onCloseRequest = ::exitApplication, title = "DriftLoom") {
        App(onCloseRequest = ::exitApplication)
    }
}
