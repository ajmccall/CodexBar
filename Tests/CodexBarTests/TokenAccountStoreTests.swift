import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Test
func `ProviderTokenAccountData encoding`() throws {
    let now = Date().timeIntervalSince1970
    let account = ProviderTokenAccount(
        id: UUID(),
        label: "user@example.com",
        token: "test-token",
        addedAt: now,
        lastUsed: now)
    let data = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)

    let encoder = JSONEncoder()
    let encoded = try encoder.encode(data)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(ProviderTokenAccountData.self, from: encoded)

    #expect(decoded.version == 1)
    #expect(decoded.accounts.count == 1)
    #expect(decoded.accounts[0].label == "user@example.com")
    #expect(decoded.accounts[0].identity == nil)
    #expect(decoded.activeIndex == 0)
}

@Test
func `ProviderTokenAccountData decodes legacy account without identity`() throws {
    let json = #"""
    {
      "version": 1,
      "activeIndex": 0,
      "accounts": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "label": "legacy",
          "token": "token",
          "addedAt": 1,
          "lastUsed": null
        }
      ]
    }
    """#

    let decoded = try JSONDecoder().decode(ProviderTokenAccountData.self, from: Data(json.utf8))

    #expect(decoded.accounts.count == 1)
    #expect(decoded.accounts[0].identity == nil)
}

@Test
func `ProviderTokenAccount identity round trips`() throws {
    let account = ProviderTokenAccount(
        id: UUID(),
        label: "octocat",
        token: "token",
        addedAt: 1,
        lastUsed: nil,
        identity: ProviderTokenAccountIdentity(
            stableID: "github-user:123",
            username: "octocat",
            displayName: "Octo Cat"))
    let data = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)

    let encoded = try JSONEncoder().encode(data)
    let decoded = try JSONDecoder().decode(ProviderTokenAccountData.self, from: encoded)

    #expect(decoded.accounts[0].identity?.stableID == "github-user:123")
    #expect(decoded.accounts[0].identity?.username == "octocat")
    #expect(decoded.accounts[0].identity?.displayName == "Octo Cat")
}

@Test
func `FileTokenAccountStore round trip`() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("codexbar-token-accounts-test.json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let now = Date().timeIntervalSince1970
    let account = ProviderTokenAccount(
        id: UUID(),
        label: "user@example.com",
        token: "test-token",
        addedAt: now,
        lastUsed: nil)
    let data = ProviderTokenAccountData(version: 1, accounts: [account], activeIndex: 0)
    let store = FileTokenAccountStore(fileURL: fileURL)

    try store.storeAccounts([.claude: data])
    let loaded = try store.loadAccounts()

    #expect(loaded[.claude]?.accounts.count == 1)
    #expect(loaded[.claude]?.accounts[0].label == "user@example.com")
}
