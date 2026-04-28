import CodexBarCore
import Foundation

enum CopilotAccountReconciler {
    enum Action: Equatable {
        case add(label: String, token: String, identity: ProviderTokenAccountIdentity)
        case update(accountID: UUID, label: String, token: String, identity: ProviderTokenAccountIdentity)
    }

    static func reconcile(
        existing accounts: [ProviderTokenAccount],
        newToken: String,
        newIdentity: ProviderTokenAccountIdentity,
        label: String)
        -> Action
    {
        if let matched = accounts.first(where: { $0.identity?.stableID == newIdentity.stableID }) {
            return .update(accountID: matched.id, label: label, token: newToken, identity: newIdentity)
        }
        return .add(label: label, token: newToken, identity: newIdentity)
    }
}
