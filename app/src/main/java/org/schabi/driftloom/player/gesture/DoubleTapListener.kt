package org.schabi.driftloom.player.gesture

interface DoubleTapListener {
    fun onDoubleTapStarted(portion: DisplayPortion)
    fun onDoubleTapProgressDown(portion: DisplayPortion)
    fun onDoubleTapFinished()
}
