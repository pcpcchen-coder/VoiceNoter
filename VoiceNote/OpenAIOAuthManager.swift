import Foundation
import AuthenticationServices
import AppKit

/// 管理 OpenAI OAuth 登入、自動續期、token 儲存與取得
@MainActor
final class OpenAIOAuthManager: NSObject, ObservableObject {
    static let shared = OpenAIOAuthManager()

    @Published private(set) var accessToken: String? = nil
    private var refreshToken: String? = nil

    /// 是否自動在 401 Unauthorized 時重新授權，預設為 false
    /// - Note: 這是設定頁可控的選項，使用者可自行開關
    @Published var autoReauthOn401: Bool = false

    @Published var clientID: String = ""
    @Published var redirectURI: String = ""
    private let scope = "openid email offline_access"

    private let clientIDStoreKey = "openai_client_id"
    private let redirectURIStoreKey = "openai_redirect_uri"
    /// OpenAI OAuth 授權頁面 URL
    private let authURL = "https://auth.openai.com/authorize"
    /// OpenAI OAuth 取得 token 的 API URL
    private let tokenURL = "https://auth.openai.com/token"

    private let tokenStoreKey = "openai_access_token"
    private let refreshStoreKey = "openai_refresh_token"
    private let autoReauthStoreKey = "openai_auto_reauth_on_401"

    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        loadToken()
        loadAutoReauthSetting()
        loadOAuthConfig()
    }

    var isOAuthConfigured: Bool {
        !clientID.isEmpty && !redirectURI.isEmpty
    }

    private func loadOAuthConfig() {
        let defaults = UserDefaults.standard
        clientID = defaults.string(forKey: clientIDStoreKey) ?? ""
        redirectURI = defaults.string(forKey: redirectURIStoreKey) ?? ""
    }

    func saveOAuthConfig() {
        let defaults = UserDefaults.standard
        defaults.set(clientID, forKey: clientIDStoreKey)
        defaults.set(redirectURI, forKey: redirectURIStoreKey)
    }

    private func loadAutoReauthSetting() {
        let defaults = UserDefaults.standard
        self.autoReauthOn401 = defaults.bool(forKey: autoReauthStoreKey)
    }

    /// 設定是否自動在 401 Unauthorized 時重新授權
    /// - Parameter enabled: true 表示啟用自動重新授權，false 表示停用
    /// - Note: 這是設定頁可控的選項，使用者可自行開關
    public func setAutoReauthOn401(_ enabled: Bool) {
        autoReauthOn401 = enabled
        let defaults = UserDefaults.standard
        defaults.setValue(enabled, forKey: autoReauthStoreKey)
        print("⚙️ 設定 autoReauthOn401 為 \(enabled)")
    }

    /// 確保使用者已登入，若尚未登入則啟動登入流程
    func ensureLoginIfNeeded() async {
        if accessToken == nil {
            await login()
        }
    }

    /// 啟動 OAuth 登入流程，使用 ASWebAuthenticationSession 進行授權
    func login() async {
        guard let url = makeAuthURL() else {
            print("⚠️ 無法建立授權 URL，請檢查 clientID 與 redirectURI")
            return
        }
        guard let callbackScheme = URL(string: redirectURI)?.scheme else {
            print("⚠️ 無法解析 redirectURI 的 scheme")
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            if let error = error {
                print("❌ ASWebAuthenticationSession 發生錯誤: \(error.localizedDescription)")
                return
            }
            guard let callbackURL = callbackURL else {
                print("❌ 未收到 callback URL")
                return
            }
            guard let code = self?.extractCode(from: callbackURL) else {
                print("❌ 無法從 callback URL 中解析出 code")
                return
            }
            Task {
                await self?.exchangeCodeForToken(code: code)
            }
        }
        session.presentationContextProvider = self
        self.authSession = session
        if !session.start() {
            print("❌ 無法啟動 ASWebAuthenticationSession")
        } else {
            print("➡️ 已啟動授權視窗，請完成登入流程")
        }
    }

    /// 使用取得的授權 code 換取 access token（及 refresh token）
    private func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: tokenURL) else {
            print("⚠️ tokenURL 格式錯誤")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let params = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectURI)&client_id=\(clientID)"
        req.httpBody = params.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let responseString = String(data: data, encoding: .utf8) ?? "<empty>"
                print("❌ Token 交換失敗，HTTP Status: \(httpResponse.statusCode)，回應：\(responseString)")
                return
            }
            if let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let at = dict["access_token"] as? String {
                    self.accessToken = at
                    saveToken()
                    print("✅ 取得 Access Token")
                } else {
                    print("❌ 回應中無 access_token")
                }
                if let rt = dict["refresh_token"] as? String {
                    self.refreshToken = rt
                    saveToken()
                    print("✅ 取得 Refresh Token")
                }
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "<empty>"
                print("❌ 無法解析 token 回應，資料: \(responseString)")
            }
        } catch {
            print("❌ Token 交換時發生錯誤: \(error.localizedDescription)")
        }
    }

    /// 建立授權頁面 URL，包含必要參數
    private func makeAuthURL() -> URL? {
        var comps = URLComponents(string: authURL)
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "prompt", value: "login"), // 強制每次登入皆需輸入帳密
        ]
        return comps?.url
    }

    /// 從 URL 中擷取授權 code
    private func extractCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }

    /// 將 token 儲存至 UserDefaults
    private func saveToken() {
        let defaults = UserDefaults.standard
        defaults.setValue(accessToken, forKey: tokenStoreKey)
        defaults.setValue(refreshToken, forKey: refreshStoreKey)
        print("💾 Token 已儲存")
    }

    /// 從 UserDefaults 載入 token
    private func loadToken() {
        let defaults = UserDefaults.standard
        accessToken = defaults.string(forKey: tokenStoreKey)
        refreshToken = defaults.string(forKey: refreshStoreKey)
        if accessToken != nil {
            print("🔑 載入已存在的 Access Token")
        }
    }

    /// 強制重新登入，通常用於設定頁面手動重新授權
    /// - Note: 建議從設定頁面呼叫此方法以重新授權 OAuth
    public func reauthorize() async {
        print("🔄 手動觸發重新授權")
        await login()
    }

    /// 清除本地儲存的 accessToken 與 refreshToken，重置認證狀態
    /// - Note: 建議從設定頁面呼叫此方法以重置授權資訊
    public func clearTokens() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: tokenStoreKey)
        defaults.removeObject(forKey: refreshStoreKey)
        accessToken = nil
        refreshToken = nil
        print("🧹 已清除本地儲存的 Token")
    }

    /// 手動覆寫 accessToken，通常用於設定頁面輸入或貼上 token
    /// - Parameter token: 新的 accessToken 字串
    /// - Note: 呼叫後會同步儲存並更新狀態
    public func setAccessToken(_ token: String?) {
        self.accessToken = token
        saveToken()
        print("✏️ 手動設定 Access Token")
    }

    /// 靜態方法：處理 API 回傳錯誤，若為認證錯誤 (401)，且 autoReauthOn401 為 true，會自動觸發重新登入流程
    /// - Parameter error: API 請求錯誤或回應錯誤
    /// - Note: 可在 API 呼叫失敗時呼叫此方法進行錯誤判斷與處理，並由設定頁控制是否啟用自動重新授權
    public static func handleAPIError(_ error: Error) async {
        let manager = shared
        if let urlError = error as? URLError {
            print("⚠️ 網路錯誤: \(urlError.localizedDescription)")
            return
        }
        if let apiError = error as? NSError,
           apiError.domain == NSURLErrorDomain,
           apiError.code == 401 {
            if manager.autoReauthOn401 {
                print("🔒 偵測到 401 Unauthorized，且 autoReauthOn401 為 true，嘗試自動重新登入")
                await manager.login()
            } else {
                print("🔒 偵測到 401 Unauthorized，但 autoReauthOn401 為 false，未自動重新登入")
            }
            return
        }
        // 若 error 是 HTTPURLResponse 狀態錯誤可額外處理，這裡示範通用判斷
        if let urlError = error as? NSError,
           let responseCode = urlError.userInfo[NSLocalizedDescriptionKey] as? Int,
           responseCode == 401 {
            if manager.autoReauthOn401 {
                print("🔒 偵測到 401 Unauthorized，且 autoReauthOn401 為 true，嘗試自動重新登入")
                await manager.login()
            } else {
                print("🔒 偵測到 401 Unauthorized，但 autoReauthOn401 為 false，未自動重新登入")
            }
            return
        }
        // 其他錯誤
        print("⚠️ API 錯誤但非授權錯誤: \(error.localizedDescription)")
    }
}

extension OpenAIOAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? ASPresentationAnchor()
    }
}
