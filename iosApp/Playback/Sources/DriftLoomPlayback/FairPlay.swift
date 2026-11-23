// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import Foundation

/// SoundCloud's FairPlay playback, following its own web player: the application certificate is fetched
/// from the license URL, the content ID is the `skd://` URI from the stream, and the license comes back
/// for the stream's own `licenseAuthToken`. It only decrypts inside AVPlayer — nothing is saved.
final class FairPlayLicense: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private let licenseURL: URL
    private let token: String
    private var certificate: Data?
    private var loading: Task<Data, Error>?

    init(licenseURL: URL, token: String) { self.licenseURL = licenseURL; self.token = token }

    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url?.scheme == "skd" else { return false }
        Task { [weak self] in
            guard let self else { return }
            do { try await self.answer(request) } catch {
                request.finishLoading(with: error)
            }
        }
        return true
    }

    private func answer(_ request: AVAssetResourceLoadingRequest) async throws {
        guard let url = request.request.url, let dataRequest = request.dataRequest,
              let assetID = url.host, !assetID.isEmpty, assetID.count <= 200 else { throw PlaybackError.protectedStream }
        let certificate = try await certificate()
        guard let identifier = assetID.data(using: .utf8) else { throw PlaybackError.protectedStream }
        let spc = try request.streamingContentKeyRequestData(forApp: certificate, contentIdentifier: identifier)
        var licenseRequest = URLRequest(url: licenseURL)
        licenseRequest.httpMethod = "POST"
        licenseRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        licenseRequest.setValue(token, forHTTPHeaderField: "license-token")
        licenseRequest.httpBody = Data(("spc=" + spc.base64EncodedString() + "&assetId=" + assetID).utf8)
        let (data, response) = try await URLSession.shared.data(for: licenseRequest)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty, data.count <= 100_000,
              let key = Data(base64Encoded: data) ?? data.first.flatMap({ $0 == 0x3c ? nil : data }) else { throw PlaybackError.protectedStream }
        dataRequest.respond(with: key)
        request.finishLoading()
    }

    private func certificate() async throws -> Data {
        if let certificate { return certificate }
        if let loading { return try await loading.value }
        let url = licenseURL
        let task = Task { () -> Data in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 100, data.count < 100_000 else { throw PlaybackError.protectedStream }
            return data
        }
        loading = task
        do { let data = try await task.value; certificate = data; return data } catch { loading = nil; throw error }
    }
}

enum FairPlayAsset {
    /// The HLS asset with its key requests redirected to `handler`, so AVPlayer can license the stream.
    static func make(url: URL, handler: FairPlayLicense) -> AVURLAsset {
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(handler, queue: DispatchQueue(label: "DriftLoom.FairPlay"))
        return asset
    }
}
