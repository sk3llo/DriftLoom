package org.schabi.driftloom.ktx

import android.content.SharedPreferences

fun SharedPreferences.getStringSafe(key: String, defValue: String): String {
    return getString(key, null) ?: defValue
}
