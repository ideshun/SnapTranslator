import Foundation
import os

/// 分模块结构化日志（基于 Unified Logging / os.Logger，零第三方依赖）
public enum AppLogger {
    private static let subsystem = "com.deshun.snaptranslator"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let ocr = Logger(subsystem: subsystem, category: "ocr")
    public static let translation = Logger(subsystem: subsystem, category: "translation")
    public static let render = Logger(subsystem: subsystem, category: "render")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
}
