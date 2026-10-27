// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Interface text from this package's string catalog; the English text is the key.
func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }
