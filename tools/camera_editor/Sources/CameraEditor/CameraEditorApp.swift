import SwiftUI
import AppKit

/// Ejecutar esta app como ejecutable puro de Swift Package Manager (sin
/// bundle .app ni Info.plist) hace que macOS la registre como proceso de
/// solo-fondo: el proceso arranca pero nunca se activa ni muestra ventana,
/// tanto con `swift run` como al lanzarla desde Xcode sobre el paquete SPM.
/// Forzamos la política de activación "regular" para que se comporte como
/// una app normal en primer plano.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct CameraEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
    }
}
