package org.schabi.driftloom.settings.export

import android.content.Context
import java.nio.file.Path
import kotlin.io.path.div

/**
 * Locates specific files of DriftLoom based on the home directory of the app.
 */
class BackupFileLocator(context: Context) {
    companion object {
        const val FILE_NAME_DB = "driftloom.db"

        @Deprecated(
            "Serializing preferences with Java's ObjectOutputStream is vulnerable to injections",
            replaceWith = ReplaceWith("FILE_NAME_JSON_PREFS")
        )
        const val FILE_NAME_SERIALIZED_PREFS = "driftloom.settings"
        const val FILE_NAME_JSON_PREFS = "preferences.json"

        /** Entry names written to backups, kept compatible with NewPipe and the iOS importer. */
        const val ZIP_ENTRY_DB = "newpipe.db"

        @Deprecated(
            "Serializing preferences with Java's ObjectOutputStream is vulnerable to injections",
            replaceWith = ReplaceWith("FILE_NAME_JSON_PREFS")
        )
        const val ZIP_ENTRY_SERIALIZED_PREFS = "newpipe.settings"

        /**
         * Entry names accepted on import. Backups made by earlier DriftLoom builds use the
         * driftloom.* names; NewPipe backups (and current exports) use the newpipe.* names.
         */
        val ZIP_ENTRIES_DB = listOf(FILE_NAME_DB, ZIP_ENTRY_DB)

        @Suppress("DEPRECATION")
        val ZIP_ENTRIES_SERIALIZED_PREFS =
            listOf(FILE_NAME_SERIALIZED_PREFS, ZIP_ENTRY_SERIALIZED_PREFS)
    }

    val db: Path = context.getDatabasePath(FILE_NAME_DB).toPath()
    val dbJournal: Path = db.resolveSibling("$FILE_NAME_DB-journal")
    val dbShm: Path = db.resolveSibling("$FILE_NAME_DB-shm")
    val dbWal: Path = db.resolveSibling("$FILE_NAME_DB-wal")
}
