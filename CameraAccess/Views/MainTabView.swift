/*
 * Main Tab View
 * 主 Tab 导航视图
 */

import SwiftUI

struct MainTabView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var wearablesViewModel: WearablesViewModel

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home - Feature entry
            TurboMetaHomeView(streamViewModel: streamViewModel, wearablesViewModel: wearablesViewModel)
                .tabItem {
                    Label(NSLocalizedString("tab.home", comment: "Home tab"), systemImage: "house.fill")
                }
                .tag(0)

            // Records
            RecordsView()
                .tabItem {
                    Label(NSLocalizedString("tab.records", comment: "Records tab"), systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            // Gallery
            GalleryView()
                .tabItem {
                    Label(NSLocalizedString("tab.gallery", comment: "Gallery tab"), systemImage: "photo.on.rectangle")
                }
                .tag(2)

            // Settings
            SettingsView(streamViewModel: streamViewModel)
                .tabItem {
                    Label(NSLocalizedString("tab.settings", comment: "Settings tab"), systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(AppColors.primary)
    }
}
