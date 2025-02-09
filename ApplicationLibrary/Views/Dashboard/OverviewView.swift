import Foundation
import Libbox
import Library
import SwiftUI

@MainActor
public struct OverviewView: View {
    @Environment(\.selection) private var selection
    @EnvironmentObject private var environments: ExtensionEnvironments
    @EnvironmentObject private var profile: ExtensionProfile
    @Binding private var profileList: [ProfilePreview]
    @Binding private var selectedProfileID: Int64
    @Binding private var systemProxyAvailable: Bool
    @Binding private var systemProxyEnabled: Bool
    @State private var alert: Alert?
    @State private var reasserting = false
    @State private var forceUpdate = false
    
    @AppStorage("accessKey") private var accessKey: String = ""
    
    private var selectedProfileIDLocal: Binding<Int64> {
        $selectedProfileID.withSetter { newValue in
            reasserting = true
            Task { [self] in
                await switchProfile(newValue)
            }
        }
    }
    
    public init(_ profileList: Binding<[ProfilePreview]>, _ selectedProfileID: Binding<Int64>, _ systemProxyAvailable: Binding<Bool>, _ systemProxyEnabled: Binding<Bool>) {
        _profileList = profileList
        _selectedProfileID = selectedProfileID
        _systemProxyAvailable = systemProxyAvailable
        _systemProxyEnabled = systemProxyEnabled
    }
    
    public var body: some View {
        VStack {
            if forceUpdate {
                EmptyView()
            }
            if ApplicationLibrary.inPreview || profile.status.isConnected {
                ExtensionStatusView()
                ClashModeView()
            }
            if profileList.isEmpty {
                ScrollView {
                    VStack {
                        Spacer()
                        Text("Empty profiles")
                            .font(.title)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .refreshable {
                    await ProfileManager.reload(accessKey: accessKey)
                    do {
                        let profiles: [Profile] = try await ProfileManager.list()
                        let profilePreviews: [ProfilePreview] = profiles.map { ProfilePreview($0) }
                        await MainActor.run {
                            profileList = profilePreviews
                            forceUpdate.toggle()
                        }
                    } catch {
                        await MainActor.run {
                            alert = Alert(title: Text("Ошибка"), message: Text(error.localizedDescription))
                        }
                    }
                }
            } else {
                FormView {
                    #if os(iOS) || os(tvOS)
                    StartStopButton()
                    if ApplicationLibrary.inPreview || profile.status.isConnectedStrict, systemProxyAvailable {
                        Toggle("HTTP Proxy", isOn: $systemProxyEnabled)
                            .onChangeCompat(of: systemProxyEnabled) { newValue in
                                Task {
                                    await setSystemProxyEnabled(newValue)
                                }
                            }
                    }
                    Section("Profile") {
                        Picker(selection: selectedProfileIDLocal) {
                            ForEach(profileList, id: \.id) { profile in
//                                Picker(profile.name, selection: selectedProfileIDLocal) {
//                                    Text("").tag(profile.id)
                                Text(profile.name).tag(profile.id)
                            }
                        } label: {}
                            .pickerStyle(.inline)
                    }
                    #elseif os(macOS)
                    if ApplicationLibrary.inPreview || profile.status.isConnectedStrict, systemProxyAvailable {
                        Toggle("HTTP Proxy", isOn: $systemProxyEnabled)
                            .onChangeCompat(of: systemProxyEnabled) { newValue in
                                Task {
                                    await setSystemProxyEnabled(newValue)
                                }
                            }
                    }
                    Section("Profile") {
                        ForEach(profileList, id: \.id) { profile in
                            Picker(profile.name, selection: selectedProfileIDLocal) {
                                Text("").tag(profile.id)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                    #endif
                }
            }
        }
        .alertBinding($alert)
        .disabled(!ApplicationLibrary.inPreview && (!profile.status.isSwitchable || reasserting))
        .refreshable {
            await ProfileManager.reload(accessKey: accessKey)
            do {
                let profiles: [Profile] = try await ProfileManager.list()
                let profilePreviews: [ProfilePreview] = profiles.map { ProfilePreview($0) }
                await MainActor.run {
                    profileList = profilePreviews
                    forceUpdate.toggle()
                }
            } catch {
                await MainActor.run {
                    alert = Alert(title: Text("Ошибка"), message: Text(error.localizedDescription))
                }
            }
        }
    }

    private func switchProfile(_ newProfileID: Int64) async {
        await SharedPreferences.selectedProfileID.set(newProfileID)
        environments.selectedProfileUpdate.send()
        if profile.status.isConnected {
            do {
                try await serviceReload()
            } catch {
                alert = Alert(error)
            }
        }
        reasserting = false
    }

    private nonisolated func serviceReload() async throws {
        try LibboxNewStandaloneCommandClient()!.serviceReload()
    }

    private nonisolated func setSystemProxyEnabled(_ isEnabled: Bool) async {
        do {
            try LibboxNewStandaloneCommandClient()!.setSystemProxyEnabled(isEnabled)
            await SharedPreferences.systemProxyEnabled.set(isEnabled)
        } catch {
            await MainActor.run {
                alert = Alert(error)
            }
        }
    }
}
