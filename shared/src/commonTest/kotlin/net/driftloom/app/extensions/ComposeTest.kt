/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.extensions

import com.russhwolf.settings.MapSettings
import com.russhwolf.settings.Settings
import org.koin.dsl.module

/**
 * Base class for Compose UI tests, letting each platform pick the test runner it needs.
 */
expect abstract class ComposeTest()

/**
 * Koin module providing the given settings.
 *
 * Tests must not declare their own `single<Settings>` definitions: the Koin compiler plugin's
 * compile-safety markers only differ in the contributed type, so several such definitions clash
 * when the Kotlin/Native test klib is serialized ("Different declarations with the same
 * signatures").
 */
fun settingsModule(settings: Settings = MapSettings()) = module {
    single<Settings> { settings }
}
