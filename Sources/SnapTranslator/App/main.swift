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

// 翻译链路诊断模式：SnapTranslator --translate "文本" [--to <语言代码>]
if CommandLine.arguments.contains("--translate") {
    let code = MainActor.assumeIsolated {
        TranslateDiag.run(arguments: CommandLine.arguments)
    }
    exit(code)
}

// 界面诊断模式：SnapTranslator --ui-diag
// 构造测试图走真实 截图→OCR→翻译 管线，逐页签离屏渲染面板并提取 PDF 文本，
// 验证各页签文本内容是否真正进入渲染（用于定位「面板不显示内容」类问题）
if CommandLine.arguments.contains("--ui-diag") {
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    _ = delegate.applicationDidFinishLaunching(
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
// 默认使用 .regular 激活策略（Dock 图标 + 顶部菜单栏应用名）
app.setActivationPolicy(.regular)
app.run()
