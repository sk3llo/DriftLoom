// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Interface text from this package's string catalog; the English text is the key.
func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Display names for values stored by their English raw value (preferences, files), which must not change.
public protocol LocalizedRawValue: RawRepresentable where RawValue == String {}
public extension LocalizedRawValue {
    var title: String { String(localized: String.LocalizationValue(rawValue), bundle: .module) }
}
extension HomeSection: LocalizedRawValue {}
extension YouTubeKiosk: LocalizedRawValue {}
extension SearchFilter: LocalizedRawValue {}
extension ChannelTab: LocalizedRawValue {}
extension SearchOrder: LocalizedRawValue {}
extension SearchDate: LocalizedRawValue {}
extension SearchDuration: LocalizedRawValue {}
extension DownloadNetwork: LocalizedRawValue {}
extension FeedPeriod: LocalizedRawValue {}
extension SubtitleSize: LocalizedRawValue {}
extension QueueRepeat: LocalizedRawValue {}
extension SoundCloudSearchFilter: LocalizedRawValue {}
