import AppKit

// 入口：菜单栏应用，accessory 策略不占 Dock
// main.swift 顶层代码不在 MainActor 上，用 assumeIsolated 桥接（实际运行于主线程）
if CommandLine.arguments.contains("--self-test") {
    let failures = MainActor.assumeIsolated {
        SelfTest.run()
    }
    exit(failures)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated {
    AppDelegate()
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
