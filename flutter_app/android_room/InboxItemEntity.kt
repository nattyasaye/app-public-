package com.example.personalmanagement.data.local.entities

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "inbox_items",
    indices = [
        Index(value = ["is_processed"]),
        Index(value = ["created_at"])
    ]
)
data class InboxItemEntity(
    @PrimaryKey
    val id: String, // UUID v4
    val raw_text: String,
    val category: String = "general", // task, idea, expense, note, general
    val is_processed: Boolean = false,
    val created_at: Long // Canonical UTC epoch milliseconds
)
