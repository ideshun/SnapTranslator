import Foundation

/// 细粒度引擎熔断器：
/// - 语向级错误（如 Apple 未安装俄语包）仅熔断 `(providerID, source, target)`，不误杀中英等正常语向
/// - 服务级错误（超时/401/429/网络中断）熔断整个 `providerID`
/// - 支持在用户修改 Key / 代理 / 引擎设置时调用 `resetAll()` 立即恢复
public final class EngineBreaker: @unchecked Sendable {
    public static let shared = EngineBreaker()

    public let cooldown: TimeInterval
    private let lock = NSLock()
    private var blockedUntil: [String: Date] = [:]

    public init(cooldown: TimeInterval = 60) {
        self.cooldown = cooldown
    }

    private func pairKey(_ providerID: String, source: Language?, target: Language) -> String {
        "\(providerID)|\(source?.rawValue ?? "auto")->\(target.rawValue)"
    }

    private func globalKey(_ providerID: String) -> String {
        "\(providerID)|*"
    }

    public func isBlocked(_ providerID: String, source: Language?, target: Language, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let keys = [globalKey(providerID), pairKey(providerID, source: source, target: target)]
        for key in keys {
            if let until = blockedUntil[key] {
                if until > now {
                    return true
                } else {
                    blockedUntil.removeValue(forKey: key)
                }
            }
        }
        return false
    }

    public func recordFailure(
        _ providerID: String,
        source: Language?,
        target: Language,
        languagePairScoped: Bool = false,
        now: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }
        let key = languagePairScoped
            ? pairKey(providerID, source: source, target: target)
            : globalKey(providerID)
        blockedUntil[key] = now.addingTimeInterval(cooldown)
    }

    public func recordSuccess(_ providerID: String, source: Language?, target: Language) {
        lock.lock()
        defer { lock.unlock() }
        blockedUntil.removeValue(forKey: globalKey(providerID))
        blockedUntil.removeValue(forKey: pairKey(providerID, source: source, target: target))
    }

    public func resetAll() {
        lock.lock()
        defer { lock.unlock() }
        blockedUntil.removeAll()
    }
}
