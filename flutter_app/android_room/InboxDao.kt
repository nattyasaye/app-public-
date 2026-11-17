package com.example.personalmanagement.data.local.dao

import androidx.room.*
import com.example.personalmanagement.data.local.entities.InboxItemEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface InboxDao {
    @Query("SELECT * FROM inbox_items WHERE is_processed = 0 ORDER BY created_at DESC")
    fun watchUnprocessedItems(): Flow<List<InboxItemEntity>>

    @Query("SELECT * FROM inbox_items ORDER BY created_at DESC")
    suspend fun getAllItems(): List<InboxItemEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertItem(item: InboxItemEntity)

    @Query("UPDATE inbox_items SET is_processed = 1 WHERE id = :id")
    suspend fun markProcessed(id: String)

    @Query("DELETE FROM inbox_items WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("SELECT * FROM inbox_items WHERE raw_text LIKE '%' || :query || '%' ORDER BY created_at DESC")
    suspend fun searchInbox(query: String): List<InboxItemEntity>
}
