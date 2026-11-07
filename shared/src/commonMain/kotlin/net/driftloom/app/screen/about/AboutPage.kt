/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.screen.about

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.PreviewLightDark
import androidx.compose.ui.tooling.preview.PreviewWrapper
import net.driftloom.app.BuildConfig
import net.driftloom.app.Constants
import net.driftloom.app.composable.about.LinkListItem
import net.driftloom.app.model.Link
import net.driftloom.app.platform.ShareHandler
import net.driftloom.app.preview.ThemePreviewProvider
import net.driftloom.app.theme.iconTVDPI
import net.driftloom.app.theme.logoBackground
import net.driftloom.app.theme.spaceLarge
import net.driftloom.app.theme.spaceXSmall
import net.driftloom.app.theme.spaceXXSmall
import driftloom.shared.generated.resources.Res
import driftloom.shared.generated.resources.app_tagline
import driftloom.shared.generated.resources.contribution_encouragement
import driftloom.shared.generated.resources.contribution_title
import driftloom.shared.generated.resources.help_action
import driftloom.shared.generated.resources.help_description
import driftloom.shared.generated.resources.help_title
import driftloom.shared.generated.resources.ic_brand
import driftloom.shared.generated.resources.privacy_summary
import driftloom.shared.generated.resources.privacy_policy_title
import driftloom.shared.generated.resources.read_privacy_policy
import driftloom.shared.generated.resources.upstream_action
import driftloom.shared.generated.resources.upstream_description
import driftloom.shared.generated.resources.upstream_title
import driftloom.shared.generated.resources.view_on_github
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.resources.stringResource
import org.koin.compose.koinInject

@Composable
fun AboutPage(shareHandler: ShareHandler = koinInject()) {
    AboutPageContent(
        onOpenUrl = { url -> shareHandler.openUrlInBrowser(url) }
    )
}

@Composable
fun AboutPageContent(
    links: List<Link> = defaultLinks(),
    onOpenUrl: (url: String) -> Unit = {}
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = WindowInsets.navigationBars.asPaddingValues(),
        verticalArrangement = Arrangement.spacedBy(spaceXXSmall)
    ) {
        // Page Header
        item {
            Column(
                modifier = Modifier
                    .padding(spaceLarge)
                    .fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Image(
                    modifier = Modifier
                        .requiredSize(iconTVDPI)
                        .clip(CircleShape)
                        .background(color = logoBackground),
                    painter = painterResource(Res.drawable.ic_brand),
                    contentDescription = BuildConfig.APP_NAME
                )
                Spacer(modifier = Modifier.height(spaceXSmall))
                Text(
                    text = BuildConfig.APP_NAME,
                    style = MaterialTheme.typography.titleLarge,
                    textAlign = TextAlign.Center
                )
                Text(
                    text = BuildConfig.VERSION_NAME,
                    style = MaterialTheme.typography.titleMedium,
                    textAlign = TextAlign.Center
                )
                Text(
                    modifier = Modifier.fillMaxWidth(),
                    text = stringResource(Res.string.app_tagline),
                    textAlign = TextAlign.Center
                )
            }
        }

        // Links about DriftLoom
        items(items = links, key = { link -> link.url }) { link ->
            LinkListItem(
                link = link,
                onAction = { onOpenUrl(link.url) }
            )
        }
    }
}

@Composable
private fun defaultLinks() = listOf(
    Link(
        title = stringResource(Res.string.help_title),
        description = stringResource(Res.string.help_description),
        action = stringResource(Res.string.help_action),
        url = Constants.URL_ISSUES
    ),
    Link(
        title = stringResource(Res.string.contribution_title),
        description = stringResource(Res.string.contribution_encouragement),
        action = stringResource(Res.string.view_on_github),
        url = Constants.URL_GITHUB
    ),
    Link(
        title = stringResource(Res.string.upstream_title),
        description = stringResource(Res.string.upstream_description),
        action = stringResource(Res.string.upstream_action),
        url = Constants.URL_NEWPIPE
    ),
    Link(
        title = stringResource(Res.string.privacy_policy_title),
        description = stringResource(Res.string.privacy_summary),
        action = stringResource(Res.string.read_privacy_policy),
        url = Constants.URL_PRIVACY
    )
)

@PreviewWrapper(ThemePreviewProvider::class)
@PreviewLightDark
@Composable
private fun AboutPagePreview() {
    AboutPageContent()
}
