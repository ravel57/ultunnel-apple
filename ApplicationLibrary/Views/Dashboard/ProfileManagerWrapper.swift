import Foundation
import SwiftUI

@MainActor
class ProfileManagerWrapper: ObservableObject {
    @Published var profileList: [Profile] = []  // Используем `Profile`, а не `ProfilePreview`

    func reloadProfiles(accessKey: String) async {
        do {
            await ProfileManager.reload(accessKey: accessKey) // Обновляем профили из API
            self.profileList = try await ProfileManager.list() // Получаем список профилей из базы
        } catch {
            print("Ошибка загрузки профилей: \(error.localizedDescription)")
        }
    }
}
