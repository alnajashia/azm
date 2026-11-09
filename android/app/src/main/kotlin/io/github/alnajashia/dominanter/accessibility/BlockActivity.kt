package io.github.alnajashia.dominanter.accessibility

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.github.alnajashia.dominanter.R

/**
 * Native full-screen block screen launched by [DominanterAccessibilityService].
 *
 * Flutter UI cannot be reliably presented from a background service (the
 * engine may not even be running), so — as in the original, which used one
 * native Activity per variant — this is a small native Activity with four
 * variants selected by [EXTRA_VARIANT]:
 *
 *  - `timeUp`        (extra: appName, limit minutes)
 *  - `outsideWindow` (extra: appName, windows as formatted strings)
 *  - `blockedWord`   (extra: word)
 *  - `reopening`     (extra: appName, limit = remaining seconds)
 *  - `generic`       (extra: appName)
 *
 * The only action offered is "go home" — there is deliberately no way to
 * dismiss the block into the blocked app.
 */
class BlockActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val variant = intent.getStringExtra(EXTRA_VARIANT) ?: VARIANT_GENERIC
        val appName = intent.getStringExtra(EXTRA_APP_NAME) ?: ""
        val (title, body) = when (variant) {
            VARIANT_TIME_UP -> getString(R.string.block_time_up_title) to
                getString(R.string.block_time_up_body, appName, intent.getIntExtra(EXTRA_LIMIT, 0))
            VARIANT_OUTSIDE_WINDOW -> getString(R.string.block_outside_window_title) to
                getString(
                    R.string.block_outside_window_body, appName,
                    intent.getStringArrayListExtra(EXTRA_WINDOWS)?.joinToString("\n") ?: "",
                )
            VARIANT_BLOCKED_WORD -> getString(R.string.block_word_title) to
                getString(R.string.block_word_body, intent.getStringExtra(EXTRA_WORD) ?: "")
            VARIANT_REOPENING -> getString(R.string.block_reopening_title) to
                getString(R.string.block_reopening_body, appName, intent.getIntExtra(EXTRA_LIMIT, 0))
            else -> getString(R.string.block_generic_title) to
                getString(R.string.block_generic_body, appName)
        }

        val padding = (32 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        layout.addView(TextView(this).apply {
            text = title
            textSize = 28f
            gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = body
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, padding / 2, 0, padding)
        })
        layout.addView(Button(this).apply {
            text = getString(R.string.block_go_home)
            setOnClickListener { goHome() }
        })
        setContentView(layout)
    }

    override fun onBackPressed() {
        // Back must not return into the blocked app.
        goHome()
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            },
        )
        finish()
    }

    companion object {
        const val EXTRA_VARIANT = "variant"
        const val EXTRA_APP_NAME = "appName"
        const val EXTRA_LIMIT = "limit"
        const val EXTRA_WORD = "word"
        const val EXTRA_WINDOWS = "windows"

        const val VARIANT_TIME_UP = "timeUp"
        const val VARIANT_OUTSIDE_WINDOW = "outsideWindow"
        const val VARIANT_BLOCKED_WORD = "blockedWord"
        const val VARIANT_REOPENING = "reopening"
        const val VARIANT_GENERIC = "generic"
    }
}

/** Shown after the F28 lockdown when the service is switched off unintentionally. */
class AccessibilityRequestActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = (32 * resources.displayMetrics.density).toInt()
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(padding, padding, padding, padding)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
        layout.addView(TextView(this).apply {
            text = getString(R.string.a11y_request_title)
            textSize = 24f
            gravity = Gravity.CENTER
        })
        layout.addView(TextView(this).apply {
            text = getString(R.string.a11y_request_body)
            textSize = 16f
            gravity = Gravity.CENTER
            setPadding(0, padding / 2, 0, padding)
        })
        layout.addView(Button(this).apply {
            text = getString(R.string.a11y_request_open_settings)
            setOnClickListener {
                startActivity(
                    Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    },
                )
                finish()
            }
        })
        setContentView(layout)
    }
}
