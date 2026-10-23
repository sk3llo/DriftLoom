/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app

import androidx.compose.runtime.Composable
import net.driftloom.app.di.KoinApp
import net.driftloom.app.navigation.Destination
import net.driftloom.app.navigation.NavDisplay
import net.driftloom.app.navigation.navModule
import net.driftloom.app.theme.AppTheme
import org.koin.compose.KoinApplication
import org.koin.plugin.module.dsl.koinConfiguration

/**
 * Entry point for the multiplatform compose application
 * @param startDestination Starting destination for the app; defaults to about
 * @param onCloseRequest Callback to close the app
 * @param withKoin Additional logic to execute after initialising Koin and setting content
 */
@Composable
fun App(
    startDestination: Destination = Destination.About,
    onCloseRequest: () -> Unit,
    withKoin: @Composable () -> Unit = {}
) {
    KoinApplication(
        configuration = koinConfiguration<KoinApp>(
            appDeclaration = {
                modules(navModule())
            }
        )
    ) {
        AppTheme {
            NavDisplay(
                startDestination = startDestination,
                onCloseRequest = onCloseRequest
            )
            withKoin()
        }
    }
}
