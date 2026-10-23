/*
 * SPDX-FileCopyrightText: 2026 NewPipe e.V. <https://newpipe-ev.de>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

package net.driftloom.app.preview

import androidx.compose.ui.tooling.preview.PreviewParameterProvider
import net.driftloom.app.model.Developer
import net.driftloom.app.model.Library

/**
 * Preview provider for composable working with [Library]
 */
class LibraryPreviewProvider : PreviewParameterProvider<Library> {

    override val values: Sequence<Library>
        get() = sequenceOf(
            Library(
                id = "net.driftloom.extractor",
                name = "DriftLoom Extractor",
                developers = listOf(
                    Developer(
                        name = "Team DriftLoom",
                        organisationUrl = "https://newpipe.net/"
                    )
                ),
                licenses = listOf("GPL-3.0-or-later"),
                website = "https://github.com/TeamNewPipe/NewPipeExtractor/"
            )
        )
}
