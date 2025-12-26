/*
 * Vision API Configuration
 * Centralized configuration for Alibaba Cloud Dashscope API
 */

import Foundation

struct VisionAPIConfig {
    // API Key is now embedded and obfuscated
    // Protected against jailbreak extraction
    static var apiKey: String {
        // Basic protection: return empty if jailbroken
        if APISecrets.isJailbroken || APISecrets.isDebuggerAttached {
            print("⚠️ Security check failed")
            return ""
        }
        return APISecrets.getAPIKey()
    }

    // Base URL for Alibaba Cloud Dashscope API
    // Beijing region: https://dashscope.aliyuncs.com/compatible-mode/v1
    // Singapore region: https://dashscope-intl.aliyuncs.com/compatible-mode/v1
    static let baseURL = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    // Model name
    static let model = "qwen3-vl-plus"
}

