import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

// MARK: - Catalog

@Test
func `copilot catalog entry exists`() {
    let support = TokenAccountSupportCatalog.support(for: .copilot)
    #expect(support != nil)
    #expect(support?.requiresManualCookieSource == false)
    #expect(support?.cookieName == nil)
}

@Test
func `copilot catalog entry uses environment injection`() {
    let support = TokenAccountSupportCatalog.support(for: .copilot)
    guard let support else {
        Issue.record("Copilot catalog entry missing")
        return
    }
    if case let .environment(key) = support.injection {
        #expect(key == "COPILOT_API_TOKEN")
    } else {
        Issue.record("Expected .environment injection, got cookieHeader")
    }
}

@Test
func `copilot env override uses correct key`() {
    let override = TokenAccountSupportCatalog.envOverride(for: .copilot, token: "gh_abc")
    #expect(override == ["COPILOT_API_TOKEN": "gh_abc"])
}

// MARK: - GitHub Identity Fetch Models

@Test
func `GitHub user identity response parses stable fields`() throws {
    let json = #"{"login": "testuser", "id": 123, "name": "Test User"}"#
    let user = try JSONDecoder().decode(CopilotGitHubUserIdentity.self, from: Data(json.utf8))

    #expect(user.id == 123)
    #expect(user.login == "testuser")
    #expect(user.name == "Test User")
    #expect(user.tokenAccountIdentity.stableID == "github-user:123")
    #expect(user.tokenAccountIdentity.username == "testuser")
}

@Test
func `GitHub user identity response parses nullable name`() throws {
    let json = #"{"login": "minimaluser", "id": 456, "name": null}"#
    let user = try JSONDecoder().decode(CopilotGitHubUserIdentity.self, from: Data(json.utf8))

    #expect(user.id == 456)
    #expect(user.login == "minimaluser")
    #expect(user.name == nil)
}

@Test
func `GitHub user identity response requires id and login`() {
    let missingID = #"{"login": "testuser"}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CopilotGitHubUserIdentity.self, from: Data(missingID.utf8))
    }

    let missingLogin = #"{"id": 123}"#
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(CopilotGitHubUserIdentity.self, from: Data(missingLogin.utf8))
    }
}

// MARK: - Account Reconciliation

@Test
func `copilot reconciler updates matching stable identity`() {
    let accountID = UUID()
    let identity = ProviderTokenAccountIdentity(stableID: "github-user:1", username: "octo", displayName: nil)
    let existing = ProviderTokenAccount(
        id: accountID,
        label: "renamed account",
        token: "old",
        addedAt: 1,
        lastUsed: nil,
        identity: identity)

    let action = CopilotAccountReconciler.reconcile(
        existing: [existing],
        newToken: "new",
        newIdentity: identity,
        label: "octo (Pro)")

    #expect(action == .update(accountID: accountID, label: "octo (Pro)", token: "new", identity: identity))
}

@Test
func `copilot reconciler appends same label with different identity`() {
    let existing = ProviderTokenAccount(
        id: UUID(),
        label: "octo",
        token: "old",
        addedAt: 1,
        lastUsed: nil,
        identity: ProviderTokenAccountIdentity(stableID: "github-user:1", username: "octo", displayName: nil))
    let newIdentity = ProviderTokenAccountIdentity(stableID: "github-user:2", username: "octo", displayName: nil)

    let action = CopilotAccountReconciler.reconcile(
        existing: [existing],
        newToken: "new",
        newIdentity: newIdentity,
        label: "octo")

    #expect(action == .add(label: "octo", token: "new", identity: newIdentity))
}

// MARK: - API Key Fallback

@MainActor
struct CopilotAPIKeyFallbackTests {
    @Test
    func `ensure loader preserves config token`() {
        let settings = Self.makeSettingsStore(suite: "copilot-api-key-loader")
        settings.copilotAPIToken = "gh_token_123"

        settings.ensureCopilotAPITokenLoaded()

        #expect(settings.copilotAPIToken == "gh_token_123")
        #expect(settings.tokenAccounts(for: .copilot).isEmpty)
    }

    @Test
    func `config token remains when token accounts already exist`() {
        let settings = Self.makeSettingsStore(suite: "copilot-api-key-with-accounts")
        settings.copilotAPIToken = "gh_token_old"
        settings.addTokenAccount(provider: .copilot, label: "existing", token: "gh_token_existing")

        settings.ensureCopilotAPITokenLoaded()

        #expect(settings.tokenAccounts(for: .copilot).count == 1)
        #expect(settings.copilotAPIToken == "gh_token_old")
        #expect(settings.tokenAccounts(for: .copilot).first?.label == "existing")
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        SettingsStore(
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}

// MARK: - Environment Precedence

@MainActor
struct CopilotEnvironmentPrecedenceTests {
    @Test
    func `token account overrides config API key`() throws {
        let settings = Self.makeSettingsStore(suite: "copilot-env-override")
        settings.copilotAPIToken = "old_config_token"
        settings.addTokenAccount(provider: .copilot, label: "new", token: "new_account_token")

        let account = try #require(settings.selectedTokenAccount(for: .copilot))
        let override = TokenAccountOverride(provider: .copilot, account: account)
        let env = ProviderRegistry.makeEnvironment(
            base: [:],
            provider: .copilot,
            settings: settings,
            tokenOverride: override)

        #expect(env["COPILOT_API_TOKEN"] == "new_account_token")
    }

    @Test
    func `config API key used when no token accounts`() {
        let settings = Self.makeSettingsStore(suite: "copilot-env-config-only")
        settings.copilotAPIToken = "config_token"

        let env = ProviderRegistry.makeEnvironment(
            base: [:],
            provider: .copilot,
            settings: settings,
            tokenOverride: nil)

        #expect(env["COPILOT_API_TOKEN"] == "config_token")
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        SettingsStore(
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
    }
}
