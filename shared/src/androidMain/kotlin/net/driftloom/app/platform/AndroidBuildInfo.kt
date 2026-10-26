/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.platform

import android.content.Context
import android.content.pm.ApplicationInfo
import org.koin.core.annotation.Singleton

@Singleton(binds = [BuildInfo::class])
class AndroidBuildInfo(private val context: Context) : BuildInfo {

    override val isDebug: Boolean =
        context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
}
