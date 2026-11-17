package com.example.personalmanagement.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.example.personalmanagement.data.local.dao.InboxDao
import com.example.personalmanagement.data.local.entities.InboxItemEntity

@Database(
    entities = [
        InboxItemEntity::class
        // Additional entities (TaskEntity, NoteEntity, FinancialTransactionEntity)
    ],
    version = 1,
    exportSchema = true
)
abstract class AppRoomDatabase : RoomDatabase() {
    abstract fun inboxDao(): InboxDao
}
