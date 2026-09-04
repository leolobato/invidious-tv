import SwiftUI
import InvidiousKit

/// Profile avatar in the navigation bar: Settings, quick profile switching and profile management.
struct ProfileToolbarModifier: ViewModifier {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var showSettings = false
    @State private var pushedRoute: Route?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            pushedRoute = .history
                        } label: {
                            Label("Watch History", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        Section(session.profile.name) {
                            ForEach(app.profiles.profiles.filter { $0.id != session.profile.id }) { profile in
                                Button {
                                    if (try? app.activate(profile)) == nil { app.deactivate() }
                                } label: {
                                    Label(profile.name, systemImage: "person.circle")
                                }
                            }
                            Button {
                                app.deactivate()
                            } label: {
                                Label("Manage Profiles", systemImage: "person.2")
                            }
                        }
                    } label: {
                        ProfileAvatar(profile: session.profile, size: 30)
                    }
                    .accessibilityLabel("Profile")
                }
            }
            .navigationDestination(item: $pushedRoute) { route in
                MobileRouteDestination(route: route)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(session: session)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
    }
}

extension View {
    func profileToolbar(session: ActiveSession) -> some View {
        modifier(ProfileToolbarModifier(session: session))
    }
}
