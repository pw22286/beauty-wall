import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case operationFailed(operation: String, status: OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .operationFailed(let operation, let status):
            return "钥匙串\(operation)失败（\(status)）"
        }
    }
}

final class KeychainStore {
    static let shared = KeychainStore()
    
    private let service = "com.wang.beauty-wall.credentials.v2"
    
    private init() {}
    
    func string(for account: String, allowAuthenticationUI: Bool = false) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        query[kSecUseAuthenticationUI as String] = allowAuthenticationUI
            ? kSecUseAuthenticationUIAllow
            : kSecUseAuthenticationUIFail
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound || status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    func set(_ value: String, for account: String, allowAuthenticationUI: Bool = true) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try delete(account: account, allowAuthenticationUI: allowAuthenticationUI)
            return
        }
        
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        query[kSecUseAuthenticationUI as String] = allowAuthenticationUI
            ? kSecUseAuthenticationUIAllow
            : kSecUseAuthenticationUIFail
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.operationFailed(operation: "写入", status: addStatus)
            }
            return
        }
        
        guard status == errSecSuccess else {
            throw KeychainStoreError.operationFailed(operation: "更新", status: status)
        }
    }
    
    private func delete(account: String, allowAuthenticationUI: Bool) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        query[kSecUseAuthenticationUI as String] = allowAuthenticationUI
            ? kSecUseAuthenticationUIAllow
            : kSecUseAuthenticationUIFail
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.operationFailed(operation: "删除", status: status)
        }
    }
}
