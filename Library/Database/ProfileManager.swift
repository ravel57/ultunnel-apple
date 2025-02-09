import Foundation
import GRDB

public enum ProfileManager {

    public nonisolated static func create(_ profile: Profile) async throws {
        profile.order = try await nextOrder()
        try await Database.sharedWriter.write { db in
            try profile.insert(db, onConflict: .fail)
        }
    }

    public nonisolated static func get(_ profileID: Int64) async throws -> Profile? {
        try await Database.sharedWriter.read { db in
            try Profile.fetchOne(db, id: profileID)
        }
    }

    public nonisolated static func get(by profileName: String) async throws -> Profile? {
        try await Database.sharedWriter.read { db in
            try Profile.filter(Column("name") == profileName).fetchOne(db)
        }
    }

    public nonisolated static func delete(_ profile: Profile) async throws {
        _ = try await Database.sharedWriter.write { db in
            try profile.delete(db)
        }
    }

    public nonisolated static func delete(by id: Int64) async throws {
        _ = try await Database.sharedWriter.write { db in
            try Profile.deleteOne(db, id: id)
        }
    }

    public nonisolated static func delete(_ profileList: [Profile]) async throws -> Int {
        try await Database.sharedWriter.write { db in
            try Profile.deleteAll(db, keys: profileList.map {
                ["id": $0.id!]
            })
        }
    }

    public nonisolated static func delete(by id: [Int64]) async throws -> Int {
        try await Database.sharedWriter.write { db in
            try Profile.deleteAll(db, ids: id)
        }
    }

    public nonisolated static func update(_ profile: Profile) async throws {
        _ = try await Database.sharedWriter.write { db in
            try profile.updateChanges(db)
        }
    }

    public nonisolated static func update(_ profileList: [Profile]) async throws {
        // TODO: batch update
        try await Database.sharedWriter.write { db in
            for profile in profileList {
                try profile.updateChanges(db)
            }
        }
    }

    public nonisolated static func list() async throws -> [Profile] {
        try await Database.sharedWriter.read { db in
            try Profile.all().order(Column("order").asc).fetchAll(db)
        }
    }

    public nonisolated static func listRemote() async throws -> [Profile] {
        try await Database.sharedWriter.read { db in
            try Profile.filter(Column("type") == ProfileType.remote.rawValue).order(Column("order").asc).fetchAll(db)
        }
    }

    public nonisolated static func listAutoUpdateEnabled() async throws -> [Profile] {
        try await Database.sharedWriter.read { db in
            try Profile.filter(Column("autoUpdate") == true).order(Column("order").asc).fetchAll(db)
        }
    }

    public nonisolated static func nextID() async throws -> Int64 {
        try await Database.sharedWriter.read { db in
            if let lastProfile = try Profile.select(Column("id")).order(Column("id").desc).fetchOne(db) {
                return lastProfile.id! + 1
            } else {
                return 1
            }
        }
    }

    public nonisolated static func nextOrder() async throws -> UInt32 {
        try await Database.sharedWriter.read { db in
            try UInt32(Profile.fetchCount(db))
        }
    }

    public nonisolated static func createProfileFile(profile: Profile, jsonData: String) async throws {
        let configDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            print("✅ Директория configs создана в App Group: \(configDirectory.path)")
        } catch {
            print("❌ Ошибка при создании директории: \(error.localizedDescription)")
            return
        }
        let fileID = try await ProfileManager.nextID()
        let configFilePath = configDirectory.appendingPathComponent("\(fileID).json")
        do {
            try jsonData.write(to: configFilePath, atomically: true, encoding: .utf8)
            print("✅ Файл успешно записан в App Group: \(configFilePath.path)")
            try FileManager.default.setAttributes([
                .posixPermissions: 0o644,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ], ofItemAtPath: configFilePath.path)
            print("✅ Разрешения изменены на 644 (чтение/запись для всех)")
        } catch {
            print("❌ Ошибка при записи файла или изменении прав: \(error.localizedDescription)")
            return
        }
        if !FileManager.default.isReadableFile(atPath: configFilePath.path) {
            print("⚠ Файл \(configFilePath.path) НЕ доступен для чтения! Проверьте права доступа.")
        } else {
            print("✅ Файл доступен для чтения.")
        }
        try await ProfileManager.create(profile)
        print("✅ Профиль успешно сохранен в базе данных")
    }

    public static func reload(accessKey: String) async {
        do {
            let urlString = "https://admin.ultunnel.ru/api/v1/get-users-proxy-servers-singbox?secretKey=\(accessKey)"
            let fetchedData = try await fetchData(from: urlString)
            guard !fetchedData!.isEmpty else {
                print("⚠ Нет новых конфигураций.")
                return
            }
            for config in try await ProfileManager.list() {
                try await ProfileManager.delete(config)
            }
            let configDirectory = FilePath.sharedDirectory.appendingPathComponent("configs")
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

            for config in fetchedData! {
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
                try await ProfileManager.createProfileFile(profile: profile, jsonData: config.content)
            }
        } catch {
            print("❌ Ошибка при обновлении профилей: \(error.localizedDescription)")
        }
    }

    struct ConfigFileFromServer {
        let content: String
        let name: String
    }

    private static func fetchData(from urlString: String) async throws -> [ConfigFileFromServer]? {
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
            guard let jsonObject = try? JSONSerialization.jsonObject(with: responseData, options: []) as? [[String: Any]] else {
                throw URLError(.cannotParseResponse)
            }
            let parsedConfigs = jsonObject.compactMap { jsonDict -> [ConfigFileFromServer]? in
                guard let configsArray = jsonDict["configs"] as? [String] else {
                    return nil
                }
                return configsArray.compactMap { jsonString -> ConfigFileFromServer? in
                    guard let jsonData = jsonString.data(using: .utf8),
                          let configDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                        return nil
                    }
                    guard let outbounds = configDict["outbounds"] as? [[String: Any]] else { return nil }
                    let outboundType = outbounds.first?["type"] as? String ?? "null"

                    return ConfigFileFromServer(
                        content: dictionaryToJSONString(configDict) ?? "{}",
                        name: "\(jsonDict["server"] ?? "unknown")-\(outboundType)"
                    )
                }
            }.flatMap { $0 }
            return parsedConfigs
        } catch {
            throw error
        }
    }

    private static func dictionaryToJSONString(_ dictionary: [String: Any]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: .prettyPrinted) else {
            return nil
        }
        return String(data: jsonData, encoding: .utf8)
    }

}
