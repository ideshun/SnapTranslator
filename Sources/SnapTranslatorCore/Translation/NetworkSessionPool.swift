import Foundation

/// 线程安全的 URLSession 池：
/// - 未启用代理时直接复用 `URLSession.shared`
/// - 启用代理时按 `EngineProxySettings` 复用同一会话，代理变更时主动 `finishTasksAndInvalidate()`
///   释放旧会话连接池，彻底消除旧版每次翻译新建并泄漏 ephemeral URLSession 的问题
public final class NetworkSessionPool: @unchecked Sendable {
    public static let shared = NetworkSessionPool()

    private let lock = NSLock()
    private var cachedProxy: EngineProxySettings?
    private var cachedSession: URLSession?

    public init() {}

    public func session(for proxy: EngineProxySettings?) -> URLSession {
        guard let proxy, proxy.isValid, let port = proxy.port else {
            return .shared
        }

        lock.lock()
        defer { lock.unlock() }

        if cachedProxy == proxy, let existing = cachedSession {
            return existing
        }

        // 代理变更时安全回收旧会话
        cachedSession?.finishTasksAndInvalidate()

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = engineTimeoutSeconds
        config.timeoutIntervalForResource = engineTimeoutSeconds * 2
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: proxy.host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: proxy.host,
            kCFNetworkProxiesHTTPSPort as String: port,
        ]
        let session = URLSession(configuration: config)
        cachedProxy = proxy
        cachedSession = session
        return session
    }

    public func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cachedSession?.finishTasksAndInvalidate()
        cachedSession = nil
        cachedProxy = nil
    }
}
