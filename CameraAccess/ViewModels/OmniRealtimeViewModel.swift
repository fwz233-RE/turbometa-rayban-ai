/*
 * Omni Realtime ViewModel
 * Manages real-time multimodal conversation with AI
 */

import Foundation
import SwiftUI
import AVFoundation

@MainActor
class OmniRealtimeViewModel: ObservableObject {

    // Published state
    @Published var isConnected = false
    @Published var isRecording = false
    @Published var isSpeaking = false
    @Published var currentTranscript = ""
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var errorMessage: String?
    @Published var showError = false

    // Service
    private var omniService: OmniRealtimeService
    private let apiKey: String

    // Video frame
    private var currentVideoFrame: UIImage?
    private var isImageSendingEnabled = false // 是否已启用图片发送（第一次音频后）
    private var isActive = true // 视图是否活跃
    
    // 自动重连
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var shouldAutoReconnect = true  // 是否应该自动重连
    private var wasRecording = false  // 重连前是否在录音

    init(apiKey: String) {
        self.apiKey = apiKey
        self.omniService = OmniRealtimeService(apiKey: apiKey)
        setupCallbacks()
    }

    // MARK: - Setup

    private func setupCallbacks() {
        omniService.onConnected = { [weak self] in
            Task { @MainActor in
                self?.isConnected = true
            }
        }

        omniService.onFirstAudioSent = { [weak self] in
            Task { @MainActor in
                print("✅ [OmniVM] 收到第一次音频发送回调，启用图片发送")
                // 延迟1秒后启用图片发送能力（确保音频已到达）
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.isImageSendingEnabled = true
                    print("📸 [OmniVM] 图片发送已启用，等待用户语音触发")
                }
            }
        }

        omniService.onSpeechStarted = { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = true

                // 用户语音触发模式：检测到用户开始说话时，发送一帧图片
                if let strongSelf = self,
                   strongSelf.isImageSendingEnabled,
                   let frame = strongSelf.currentVideoFrame {
                    print("🎤📸 [OmniVM] 检测到用户语音，发送当前视频帧")
                    strongSelf.omniService.sendImageAppend(frame)
                }
            }
        }

        omniService.onSpeechStopped = { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
            }
        }

        omniService.onTranscriptDelta = { [weak self] delta in
            Task { @MainActor in
                print("📝 [OmniVM] AI回复片段: \(delta)")
                self?.currentTranscript += delta
            }
        }

        omniService.onUserTranscript = { [weak self] userText in
            Task { @MainActor in
                guard let self = self else { return }
                print("💬 [OmniVM] 保存用户语音: \(userText)")
                self.conversationHistory.append(
                    ConversationMessage(role: .user, content: userText)
                )
            }
        }

        omniService.onTranscriptDone = { [weak self] fullText in
            Task { @MainActor in
                guard let self = self else { return }
                // 使用累积的currentTranscript，因为done事件可能不包含text字段
                let textToSave = fullText.isEmpty ? self.currentTranscript : fullText
                guard !textToSave.isEmpty else {
                    print("⚠️ [OmniVM] AI回复为空，跳过保存")
                    return
                }
                print("💬 [OmniVM] 保存AI回复: \(textToSave)")
                self.conversationHistory.append(
                    ConversationMessage(role: .assistant, content: textToSave)
                )
                self.currentTranscript = ""
            }
        }

        omniService.onAudioDone = { [weak self] in
            Task { @MainActor in
                // Audio playback complete
            }
        }

        omniService.onError = { [weak self] error in
            Task { @MainActor in
                guard let self = self, self.isActive else {
                    print("⚠️ [OmniVM] 忽略错误（视图已关闭）: \(error)")
                    return
                }
                
                // 检查是否是连接断开错误
                let isDisconnectError = error.contains("连接已断开") || 
                                        error.contains("Socket") ||
                                        error.contains("WebSocket") ||
                                        error.contains("1007")
                
                if isDisconnectError && self.shouldAutoReconnect && self.reconnectAttempts < self.maxReconnectAttempts {
                    self.reconnectAttempts += 1
                    print("🔄 [OmniVM] 检测到连接断开，尝试重连... (尝试 \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")
                    
                    // 保存当前录音状态
                    self.wasRecording = self.isRecording
                    self.isConnected = false
                    self.isRecording = false
                    
                    // 延迟后重连
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self, self.isActive, self.shouldAutoReconnect else { return }
                        print("🔄 [OmniVM] 执行重连...")
                        self.reconnect()
                    }
                    return
                }
                
                // 其他错误或重连失败，显示给用户
                if !self.isConnected {
                    print("⚠️ [OmniVM] 忽略错误（未连接）: \(error)")
                    return
                }
                
                self.errorMessage = error
                self.showError = true
            }
        }
        
        // 新增：监听断开事件
        omniService.onDisconnected = { [weak self] reason in
            Task { @MainActor in
                guard let self = self, self.isActive else { return }
                print("🔌 [OmniVM] 收到断开回调: \(reason)")
                
                // 如果是意外断开且应该重连
                if self.isConnected && self.shouldAutoReconnect && self.reconnectAttempts < self.maxReconnectAttempts {
                    self.reconnectAttempts += 1
                    print("🔄 [OmniVM] 意外断开，尝试重连... (尝试 \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")
                    
                    self.wasRecording = self.isRecording
                    self.isConnected = false
                    self.isRecording = false
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self, self.isActive, self.shouldAutoReconnect else { return }
                        self.reconnect()
                    }
                } else {
                    self.isConnected = false
                    self.isRecording = false
                }
            }
        }
    }
    
    // MARK: - Reconnect
    
    private func reconnect() {
        // 重新创建 service 并设置回调
        omniService = OmniRealtimeService(apiKey: apiKey)
        setupCallbacks()
        omniService.connect()
        
        // 等待连接成功后恢复录音
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.isConnected, self.wasRecording else { return }
            print("🔄 [OmniVM] 重连成功，恢复录音")
            self.startRecording()
            self.reconnectAttempts = 0  // 重置重连计数
        }
    }

    // MARK: - Connection

    func connect() {
        omniService.connect()
    }

    func disconnect() {
        // 禁用自动重连
        shouldAutoReconnect = false
        
        // 标记视图不活跃，防止后续错误回调
        isActive = false
        
        // Save conversation before disconnecting
        saveConversation()

        stopRecording()
        omniService.disconnect()
        isConnected = false
        isImageSendingEnabled = false
    }

    private func saveConversation() {
        // Only save if there's meaningful conversation
        guard !conversationHistory.isEmpty else {
            print("💬 [OmniVM] 无对话内容，跳过保存")
            return
        }

        let record = ConversationRecord(
            messages: conversationHistory,
            aiModel: "qwen3-omni-flash-realtime",
            language: "zh-CN" // TODO: 从设置中获取
        )

        ConversationStorage.shared.saveConversation(record)
        print("💾 [OmniVM] 对话已保存: \(conversationHistory.count) 条消息")
    }

    // MARK: - Recording

    func startRecording() {
        guard isConnected else {
            print("⚠️ [OmniVM] 未连接，无法开始录音")
            errorMessage = "请先连接服务器"
            showError = true
            return
        }

        print("🎤 [OmniVM] 开始录音（语音触发模式）")
        omniService.startRecording()
        isRecording = true
    }

    func stopRecording() {
        print("🛑 [OmniVM] 停止录音")
        omniService.stopRecording()
        isRecording = false
    }

    // MARK: - Video Frames

    func updateVideoFrame(_ frame: UIImage) {
        currentVideoFrame = frame
    }

    // MARK: - Manual Mode (if needed)

    func sendMessage() {
        omniService.commitAudioBuffer()
    }

    // MARK: - Cleanup

    func dismissError() {
        showError = false
    }

    nonisolated deinit {
        Task { @MainActor [weak omniService] in
            omniService?.disconnect()
        }
    }
}

// MARK: - Conversation Message

struct ConversationMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
    }
}
