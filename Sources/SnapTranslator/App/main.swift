import AppKit

// 入口：支持普通应用（Dock 图标）和菜单栏驻留两种模式
// 默认以 .regular 启动显示 Dock 图标和菜单栏应用名，可通过设置切换为 .accessory 纯菜单栏
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
// 默认使用 .regular 激活策略（Dock 图标 + 顶部菜单栏应用名）
app.setActivationPolicy(.regular)
app.run()
