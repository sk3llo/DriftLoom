package net.driftloom.app.platform

import org.koin.core.annotation.Singleton

@Singleton(binds = [BuildInfo::class])
class IOSBuildInfo : BuildInfo {
    override val isDebug: Boolean = false
}
