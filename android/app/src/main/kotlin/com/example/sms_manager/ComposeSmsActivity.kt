package com.example.sms_manager

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class ComposeSmsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Forward the intent to MainActivity
        val forwardIntent = Intent(this, MainActivity::class.java).apply {
            action = intent.action
            data = intent.data
            if (intent.extras != null) {
                putExtras(intent.extras!!)
            }
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(forwardIntent)
        finish()
    }
}
