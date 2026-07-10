import SwiftUI

@main
struct CameraEditorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
    }
}
