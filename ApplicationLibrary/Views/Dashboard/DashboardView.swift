import Libbox
import Library
import SwiftUI

@MainActor
public struct DashboardView: View {
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
        @State private var isLoading = true
        @State private var systemExtensionInstalled = true
    #endif
    @AppStorage("accessKey") private var accessKey: String = ""

    public init() {}
        public var body: some View {
            viewBuilder {
                #if os(macOS)
                    if Variant.useSystemExtension {
                        viewBuilder {
                            if !systemExtensionInstalled {
                                FormView {
                                    InstallSystemExtensionButton {
                                        await reload()
                                    }
                                }
                            } else {
                                DashboardView0()
                            }
                        }.onAppear {
                            Task {
                                await reload()
                            }
                        }
                    } else {
                        DashboardView0()
                    }
                #else
                    DashboardView0()
                        .refreshable {
                            await reload()
                        }
                #endif
            }
            #if os(macOS)
                .onChangeCompat(of: controlActiveState) { newValue in
                    if newValue != .inactive {
                        if Variant.useSystemExtension {
                            if !isLoading {
                                Task {
                                    await reload()
                                }
                            }
                        }
                    }
                }
            #endif
        }

        #if os(macOS)
            private nonisolated func reload() async {
                let systemExtensionInstalled = await SystemExtension.isInstalled()
                await MainActor.run {
                    self.systemExtensionInstalled = systemExtensionInstalled
                    isLoading = false
                }
            }
        #else
            private func reload() async {
                do {
                    let urlString = "https://admin.ultunnel.ru/api/v1/get-users-proxy-servers-singbox?secretKey=\(accessKey)"

                    let fetchedData = try await fetchData(from: urlString)
                    guard !fetchedData.isEmpty else {
                        print("⚠ Нет новых конфигураций.")
                        return
                    }

                    for config in try await ProfileManager.list() {
                        try await ProfileManager.delete(config)
                    }

                    let configDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("configs")
                    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

                    for config in fetchedData {
                        let fileID = try await ProfileManager.nextID()
                        let configFile = configDirectory.appendingPathComponent("\(fileID).json")

                        let profileType: ProfileType = .local

                        let profile = Profile(
                            id: fileID,
                            name: config.name,
                            order: try await ProfileManager.nextOrder(),
                            type: profileType,
                            path: configFile.path
                        )

                        try config.content.write(to: configFile, atomically: true, encoding: .utf8)
                        try await ProfileManager.create(profile)
                    }

                } catch {
                    print("❌ Ошибка при обновлении профилей: \(error.localizedDescription)")
                }
            }


        #endif

    struct ConfigFileFromServer: Decodable {
        let content: String
        let name: String
    }

    struct ConfigWithServerName: Codable {
        let server: String
        let configs: [Config]

        enum CodingKeys: String, CodingKey {
            case server
            case configs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            server = try container.decode(String.self, forKey: .server)

            let rawConfigs = try container.decode([String].self, forKey: .configs)
            let decoder = JSONDecoder()
            configs = try rawConfigs.map { rawConfig in
                guard let data = rawConfig.data(using: .utf8) else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: container.codingPath,
                            debugDescription: "Invalid JSON string in configs"
                        )
                    )
                }
                return try decoder.decode(Config.self, from: data)
            }
        }
    }

    struct Config: Codable {
        let log: Log
        let dns: DNS
        let inbounds: [Inbound]?
        let outbounds: [Outbound]?
        let route: Route
    }

    struct Log: Codable {
        let level: String
    }

    struct DNS: Codable {
        let servers: [DNSServer]
    }

    struct DNSServer: Codable {
        let tag: String
        let address: String
    }

    struct Inbound: Codable {
        let type: String
        let tag: String
    }

    struct Outbound: Codable {
        let type: String
        let tag: String?
        let server: String?
        let serverPort: Int?
        let uuid: String?
        let systemInterface: String?
        let interfaceName: String?
        let localAddress: [String]?
        let privateKey: String?
        let peers: [String]?
        let peerPublicKey: String?
        let preSharedKey: String?
        let reserved: [String]?
        let workers: String?
        let mtu: Int?
        let network: String?
        let gso: String?
        let user: String?
        let password: String?
    }

    struct Route: Codable {
        let rules: [RouteRule]
    }

    struct RouteRule: Codable {
        let port: Int?
        let inbound: String?
        let outbound: String
    }
    
    private func fetchData(from urlString: String) async throws -> [ConfigFileFromServer] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            let decodedData = try decoder.decode([ConfigWithServerName].self, from: responseData)

            return decodedData.flatMap { serverConfig in
                serverConfig.configs.compactMap { jsonConfig in
                    let configData = try? JSONEncoder().encode(jsonConfig)
                    let jsonString = String(data: configData ?? Data(), encoding: .utf8) ?? ""

                    return ConfigFileFromServer(
                        content: jsonString,
                        name: "\(serverConfig.server)-\(jsonConfig.outbounds?.first?.type ?? "null")"
                    )
                }
            }
        } catch {
            print("❌ Ошибка при декодировании JSON: \(error)")
            throw error
        }
    }


    
    struct DashboardView0: View {
        @EnvironmentObject private var environments: ExtensionEnvironments

        var body: some View {
            if ApplicationLibrary.inPreview {
                ActiveDashboardView()
            } else if environments.extensionProfileLoading {
                ProgressView()
            } else if let profile = environments.extensionProfile {
                DashboardView1().environmentObject(profile)
            } else {
                FormView {
                    InstallProfileButton {
                        await environments.reload()
                    }
                }
            }
        }
    }

    struct DashboardView1: View {
        @Environment(\.openURL) var openURL
        @EnvironmentObject private var environments: ExtensionEnvironments
        @EnvironmentObject private var profile: ExtensionProfile
        @State private var alert: Alert?
        @State private var notStarted = false

        var body: some View {
            VStack {
                ActiveDashboardView()
            }
            .alertBinding($alert)
            .onChangeCompat(of: profile.status) { newValue in
                if newValue == .connected {
                    notStarted = false
                }
                if newValue == .disconnecting || newValue == .connected {
                    Task {
                        await checkServiceError()
                        if newValue == .connected {
                            await checkDeprecatedNotes()
                        }
                    }
                } else if newValue == .connecting {
                    notStarted = true
                } else if newValue == .disconnected {
                    if #available(iOS 16.0, macOS 13.0, tvOS 17.0, *) {
                        if notStarted {
                            Task {
                                await checkLastDisconnectError()
                            }
                        }
                    }
                }
            }
        }

        private nonisolated func checkDeprecatedNotes() async {
            do {
                let reports = try LibboxNewStandaloneCommandClient()!.getDeprecatedNotes()
                if reports.hasNext() {
                    await MainActor.run {
                        loopShowDeprecateNotes(reports)
                    }
                }
            } catch {
                await MainActor.run {
                    alert = Alert(error)
                }
            }
        }

        @MainActor
        private func loopShowDeprecateNotes(_ reports: any LibboxDeprecatedNoteIteratorProtocol) {
            if reports.hasNext() {
                let report = reports.next()!
                alert = Alert(
                    title: Text("Deprecated Warning"),
                    message: Text(report.message()),
                    primaryButton: .default(Text("Documentation")) {
                        openURL(URL(string: report.migrationLink)!)
                        Task.detached {
                            try await Task.sleep(nanoseconds: 300 * MSEC_PER_SEC)
                            await loopShowDeprecateNotes(reports)
                        }
                    },
                    secondaryButton: .cancel(Text("Ok")) {
                        Task.detached {
                            try await Task.sleep(nanoseconds: 300 * MSEC_PER_SEC)
                            await loopShowDeprecateNotes(reports)
                        }
                    }
                )
            }
        }

        private nonisolated func checkServiceError() async {
            var error: NSError?
            let message = LibboxReadServiceError(&error)
            if error != nil {
                return
            }
            await MainActor.run {
                alert = Alert(
                    title: Text("Service Error"), message: Text(message!.value))
            }
        }

        @available(iOS 16.0, macOS 13.0, tvOS 17.0, *)
        private nonisolated func checkLastDisconnectError() async {
            var myError: NSError
            do {
                try await profile.fetchLastDisconnectError()
                return
            } catch {
                myError = error as NSError
            }
            #if os(macOS)
                if myError.domain == "Library.FullDiskAccessPermissionRequired" {
                    await MainActor.run {
                        alert = Alert(
                            title: Text(
                                "Full Disk Access permission is required"),
                            message: Text(
                                "Please grant the permission for **SFMExtension**, then we can continue."
                            ),
                            primaryButton: .default(
                                Text("Authorize"), action: openFDASettings),
                            secondaryButton: .cancel()
                        )
                    }
                    return
                }
            #endif
            let message = myError.localizedDescription
            await MainActor.run {
                alert = Alert(title: Text("Service Error"), message: Text(message))
            }
        }

        #if os(macOS)

            private func openFDASettings() {
                if NSWorkspace.shared.open(
                    URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                    )!)
                {
                    return
                }
                if #available(macOS 13, *) {
                    NSWorkspace.shared.open(
                        URL(
                            fileURLWithPath:
                                "/System/Applications/System Settings.app"))
                } else {
                    NSWorkspace.shared.open(
                        URL(
                            fileURLWithPath:
                                "/System/Applications/System Preferences.app"))
                }
            }

        #endif
    }
}
