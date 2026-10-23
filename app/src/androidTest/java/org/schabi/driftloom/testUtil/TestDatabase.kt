package org.schabi.driftloom.testUtil

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertSame
import org.schabi.driftloom.DriftLoomDatabase
import org.schabi.driftloom.database.AppDatabase

class TestDatabase {
    companion object {
        fun createReplacingDriftLoomDatabase(): AppDatabase {
            val database = Room.inMemoryDatabaseBuilder(
                ApplicationProvider.getApplicationContext(),
                AppDatabase::class.java
            )
                .allowMainThreadQueries()
                .build()

            val databaseField = DriftLoomDatabase::class.java.getDeclaredField("databaseInstance")
            databaseField.isAccessible = true
            databaseField.set(DriftLoomDatabase::class, database)

            assertSame(
                "Mocking database failed!",
                database,
                DriftLoomDatabase.getInstance(ApplicationProvider.getApplicationContext())
            )

            return database
        }
    }
}
