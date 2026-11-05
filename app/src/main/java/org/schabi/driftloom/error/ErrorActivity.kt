/*
 * SPDX-FileCopyrightText: 2015-2026 NewPipe contributors <https://newpipe.net>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package org.schabi.driftloom.error

import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Menu
import android.view.MenuItem
import android.view.View
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.IntentCompat
import androidx.core.net.toUri
import com.grack.nanojson.JsonWriter
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import org.schabi.driftloom.BuildConfig
import org.schabi.driftloom.R
import org.schabi.driftloom.databinding.ActivityErrorBinding
import org.schabi.driftloom.util.Localization
import org.schabi.driftloom.util.ThemeHelper
import org.schabi.driftloom.util.external_communication.ShareUtils
import org.schabi.driftloom.util.text.setTextWithLinks

/**
 * This activity is used to show error details and allow reporting them in various ways.
 * Use [ErrorUtil.openActivity] to correctly open this activity.
 */
class ErrorActivity : AppCompatActivity() {
    private lateinit var errorInfo: ErrorInfo
    private lateinit var currentTimeStamp: String

    private lateinit var binding: ActivityErrorBinding

    private val contentCountryString: String
        get() = Localization.getPreferredContentCountry(this).countryCode

    private val contentLanguageString: String
        get() = Localization.getPreferredLocalization(this).localizationCode

    private val appLanguage: String
        get() = Localization.getAppLocale().toString()

    private val osString: String
        get() {
            val name = System.getProperty("os.name")!!
            val osBase = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Build.VERSION.BASE_OS.ifEmpty { "Android" }
            } else {
                "Android"
            }
            return "$name $osBase ${Build.VERSION.RELEASE} - ${Build.VERSION.SDK_INT}"
        }

    // /////////////////////////////////////////////////////////////////////
    // Activity lifecycle
    // /////////////////////////////////////////////////////////////////////

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        ThemeHelper.setDayNightMode(this)
        ThemeHelper.setTheme(this)

        binding = ActivityErrorBinding.inflate(layoutInflater)
        setContentView(binding.getRoot())

        setSupportActionBar(binding.toolbarLayout.toolbar)
        supportActionBar?.apply {
            setDisplayHomeAsUpEnabled(true)
            setTitle(R.string.error_report_title)
            setDisplayShowTitleEnabled(true)
        }

        errorInfo = IntentCompat.getParcelableExtra(intent, ERROR_INFO, ErrorInfo::class.java)!!

        // important add guru meditation
        addGuruMeditation()
        // print current time, as zoned ISO8601 timestamp
        currentTimeStamp = ZonedDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)

        // DriftLoom has no crash-report mailbox; reports go to GitHub issues.
        binding.errorReportEmailButton.visibility = View.GONE

        binding.errorReportCopyButton.setOnClickListener { _ ->
            ShareUtils.copyToClipboard(this, buildMarkdown())
        }

        binding.errorReportGitHubButton.setOnClickListener { _ ->
            openPrivacyPolicyDialog(this, "GITHUB")
        }

        // normal bugreport
        buildInfo(errorInfo)
        binding.errorMessageView.setTextWithLinks(errorInfo.getMessage(this))
        binding.errorView.text = formErrorText(errorInfo.stackTraces)

        // print stack trace once again for debugging:
        errorInfo.stackTraces.forEach { Log.e(TAG, it) }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.error_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> {
                onBackPressed()
                true
            }

            R.id.menu_item_share_error -> {
                ShareUtils.shareText(
                    applicationContext,
                    getString(R.string.error_report_title),
                    buildJson()
                )
                true
            }

            else -> false
        }
    }

    private fun openPrivacyPolicyDialog(context: Context, action: String) {
        AlertDialog.Builder(context)
            .setIcon(android.R.drawable.ic_dialog_alert)
            .setTitle(R.string.privacy_policy_title)
            .setMessage(R.string.start_accept_privacy_policy)
            .setCancelable(false)
            .setNeutralButton(R.string.read_privacy_policy) { _, _ ->
                ShareUtils.openUrlInApp(context, context.getString(R.string.privacy_policy_url))
            }
            .setPositiveButton(R.string.accept) { _, _ ->
                if (action == "GITHUB") { // a new issue on GitHub, prefilled with this report
                    ShareUtils.openUrlInApp(this, buildIssueUrl())
                }
            }
            .setNegativeButton(R.string.decline, null)
            .show()
    }

    private fun formErrorText(stacktrace: Array<String>): String {
        val separator = "-------------------------------------"
        return stacktrace.joinToString(separator + "\n", separator + "\n", separator)
    }

    private fun buildInfo(info: ErrorInfo) {
        binding.errorInfoLabelsView.text = getString(R.string.info_labels)

        val text = info.userAction.message + "\n" +
            info.request + "\n" +
            contentLanguageString + "\n" +
            contentCountryString + "\n" +
            appLanguage + "\n" +
            info.getServiceName() + "\n" +
            currentTimeStamp + "\n" +
            packageName + "\n" +
            BuildConfig.VERSION_NAME + "\n" +
            osString

        binding.errorInfosView.text = text
    }

    private fun buildJson(): String {
        try {
            return JsonWriter.string()
                .`object`()
                .value("user_action", errorInfo.userAction.message)
                .value("request", errorInfo.request)
                .value("content_language", contentLanguageString)
                .value("content_country", contentCountryString)
                .value("app_language", appLanguage)
                .value("service", errorInfo.getServiceName())
                .value("package", packageName)
                .value("version", BuildConfig.VERSION_NAME)
                .value("os", osString)
                .value("time", currentTimeStamp)
                .array("exceptions", errorInfo.stackTraces.toList())
                .value("user_comment", binding.errorCommentBox.getText().toString())
                .end()
                .done()
        } catch (exception: Exception) {
            Log.e(TAG, "Error while erroring: Could not build json", exception)
        }

        return ""
    }

    private fun buildMarkdown(): String {
        try {
            return buildString(1024) {
                val userComment = binding.errorCommentBox.text.toString()
                if (userComment.isNotEmpty()) {
                    appendLine(userComment)
                }

                // basic error info
                appendLine("## Exception")
                appendLine("* __User Action:__ ${errorInfo.userAction.message}")
                appendLine("* __Request:__ ${errorInfo.request}")
                appendLine("* __Content Country:__ $contentCountryString")
                appendLine("* __Content Language:__ $contentLanguageString")
                appendLine("* __App Language:__ $appLanguage")
                appendLine("* __Service:__ ${errorInfo.getServiceName()}")
                appendLine("* __Timestamp:__ $currentTimeStamp")
                appendLine("* __Package:__ $packageName")
                appendLine("* __Service:__ ${errorInfo.getServiceName()}")
                appendLine("* __Version:__ ${BuildConfig.VERSION_NAME}")
                appendLine("* __OS:__ $osString")

                // Collapse all logs to a single paragraph when there are more than one
                // to keep the GitHub issue clean.
                if (errorInfo.stackTraces.size > 1) {
                    append("<details><summary><b>Exceptions (")
                    append(errorInfo.stackTraces.size)
                    append(")</b></summary><p>\n")
                }

                // add the logs
                errorInfo.stackTraces.forEachIndexed { index, stacktrace ->
                    append("<details><summary><b>Crash log ")
                    if (errorInfo.stackTraces.size > 1) {
                        append(index + 1)
                    }
                    append("</b>")
                    append("</summary><p>\n")
                    append("\n```\n${stacktrace}\n```\n")
                    append("</details>\n")
                }

                // make sure to close everything
                if (errorInfo.stackTraces.size > 1) {
                    append("</p></details>\n")
                }

                append("<hr>\n")
            }
        } catch (exception: Exception) {
            Log.e(TAG, "Error while erroring: Could not build markdown", exception)
            return ""
        }
    }

    /**
     * The repository's "Report from the app" issue form (.github/ISSUE_TEMPLATE/app_report.yml), with its
     * fields filled in by id. The repository only accepts template issues, so a plain `body=` link would
     * lose the text. Long crash logs are shortened to keep the link within what browsers and GitHub accept.
     */
    private fun buildIssueUrl(): String {
        val message = errorInfo.getMessage(this).toString().replace('\n', ' ')
        val summary = if (message.length > 80) message.take(77) + "…" else message
        val title = "[Android] ${errorInfo.userAction.message}" +
            if (summary.isNotBlank()) ": $summary" else ""
        val details = listOf(
            "Area" to errorInfo.userAction.message,
            "Request" to errorInfo.request,
            "Service" to errorInfo.getServiceName(),
            "App" to "${BuildConfig.VERSION_NAME} ($packageName)",
            "OS" to osString,
            "App language" to appLanguage,
            "Content language" to contentLanguageString,
            "Content country" to contentCountryString,
            "Time" to currentTimeStamp
        ).joinToString("\n", "| | |\n|---|---|\n") { (name, value) ->
            "| $name | ${value.replace("|", "\\|").replace('\n', ' ')} |"
        } + "\n\n<sub>Sent from DriftLoom's error screen.</sub>"
        val comment = binding.errorCommentBox.text.toString()
        val log = errorInfo.stackTraces.joinToString("\n\n")
        var limit = 4000
        while (true) {
            val error = if (log.length > limit) log.take(limit) + "…" else log
            val url = ERROR_GITHUB_ISSUE_URL.toUri().buildUpon()
                .appendQueryParameter("template", "app_report.yml")
                .appendQueryParameter("title", title)
                .apply { if (comment.isNotBlank()) appendQueryParameter("what-happened", comment) }
                .appendQueryParameter("error", error)
                .appendQueryParameter("details", details)
                .build().toString()
            if (url.length <= MAX_ISSUE_URL_LENGTH || limit <= 100) return url
            limit /= 2
        }
    }

    private fun addGuruMeditation() {
        // just an easter egg
        var text = binding.errorSorryView.text.toString()
        text += "\n" + getString(R.string.guru_meditation)
        binding.errorSorryView.text = text
    }

    companion object {
        // LOG TAGS
        private val TAG = ErrorActivity::class.java.toString()

        // BUNDLE TAGS
        const val ERROR_INFO = "error_info"

        private const val ERROR_GITHUB_ISSUE_URL = "https://github.com/sk3llo/DriftLoom/issues/new"
        private const val MAX_ISSUE_URL_LENGTH = 7000
    }
}
