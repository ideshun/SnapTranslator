import AppKit

if CommandLine.arguments.contains("--self-test") {
    let failures = MainActor.assumeIsolated {
        SelfTest.run()
    }
    exit(failures)
}

if CommandLine.arguments.contains("--translate") {
    let code = MainActor.assumeIsolated {
        TranslateDiag.run(arguments: CommandLine.arguments)
    }
    exit(code)
}

if CommandLine.arguments.contains("--ui-diag") {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    delegate.applicationDidFinishLaunching(
        Notification(name: Notification.Name("SnapTranslatorUIDiag"))
    )
    let code = MainActor.assumeIsolated { delegate.runUIDiagnostic() }
    exit(code)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated {
    AppDelegate()
}
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
