/*
 * Voice Chat View
 * 纯语音 AI 对话界面（不需要 Meta 眼镜）
 */

import SwiftUI

struct VoiceChatView: View {
    @StateObject private var viewModel: OmniRealtimeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showConversation = true
    @State private var hasDisconnected = false  // 防止重复断开

    init(apiKey: String) {
        self._viewModel = StateObject(wrappedValue: OmniRealtimeViewModel(apiKey: apiKey))
    }

    var body: some View {
        ZStack {
            // 渐变背景
            LinearGradient(
                colors: [
                    AppColors.voiceChat.opacity(0.3),
                    AppColors.voiceChat.opacity(0.1),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 8)

                // Conversation history
                if showConversation {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.conversationHistory) { message in
                                    VoiceChatBubble(message: message)
                                        .id(message.id)
                                }

                                // Current AI response (streaming)
                                if !viewModel.currentTranscript.isEmpty {
                                    VoiceChatBubble(
                                        message: ConversationMessage(
                                            role: .assistant,
                                            content: viewModel.currentTranscript
                                        )
                                    )
                                    .id("current")
                                }
                            }
                            .padding()
                        }
                        .onChange(of: viewModel.conversationHistory.count) { _ in
                            if let lastMessage = viewModel.conversationHistory.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: viewModel.currentTranscript) { _ in
                            withAnimation {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // 未展开对话时显示语音波形动画
                    Spacer()
                    VoiceWaveAnimation(isActive: viewModel.isRecording || viewModel.isSpeaking)
                    Spacer()
                }

                // Controls
                controlsView
            }
        }
        .onAppear {
            // 自动连接并开始录音
            viewModel.connect()

            // 延迟启动录音，等待连接完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if viewModel.isConnected && !hasDisconnected {
                    viewModel.startRecording()
                }
            }
        }
        .onDisappear {
            disconnectIfNeeded()
        }
    }
    
    // 安全断开连接
    private func disconnectIfNeeded() {
        guard !hasDisconnected else { return }
        hasDisconnected = true
        viewModel.disconnect()
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(NSLocalizedString("home.voicechat.title", comment: "Voice Chat title"))
                .font(AppTypography.headline)
                .foregroundColor(.white)

            Spacer()

            // Hide/show conversation button
            Button {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showConversation.toggle()
                }
            } label: {
                Image(systemName: showConversation ? "waveform" : "text.bubble.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
            }

            // Connection status
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(viewModel.isConnected ? NSLocalizedString("liveai.connected", comment: "Connected") : NSLocalizedString("liveai.connecting", comment: "Connecting"))
                    .font(AppTypography.caption)
                    .foregroundColor(.white)
            }

            // Speaking indicator
            if viewModel.isSpeaking {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                    Text(NSLocalizedString("liveai.speaking", comment: "AI speaking"))
                        .font(AppTypography.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(Color.black.opacity(0.5))
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: AppSpacing.md) {
            // Recording status with animated indicator
            HStack(spacing: AppSpacing.sm) {
                if viewModel.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                .scaleEffect(1.5)
                                .opacity(0.5)
                        )
                    Text(NSLocalizedString("liveai.listening", comment: "Listening"))
                        .font(AppTypography.body)
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 12, height: 12)
                    Text(NSLocalizedString("liveai.stop", comment: "Stopped"))
                        .font(AppTypography.body)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                    .fill(Color.black.opacity(0.4))
            )

            // Stop button
            Button {
                disconnectIfNeeded()
                dismiss()
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                    Text(NSLocalizedString("liveai.stop", comment: "Stop"))
                        .font(AppTypography.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(AppCornerRadius.lg)
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.bottom, AppSpacing.lg)
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Voice Chat Bubble

struct VoiceChatBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if message.role == .assistant {
                        Image(systemName: "waveform.circle.fill")
                            .font(.caption)
                            .foregroundColor(AppColors.voiceChat)
                    }

                    Text(message.role == .user ? "你" : "AI")
                        .font(AppTypography.caption)
                        .foregroundColor(.white.opacity(0.6))

                    if message.role == .user {
                        Image(systemName: "person.circle.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                Text(message.content)
                    .font(AppTypography.body)
                    .foregroundColor(.white)
                    .padding(AppSpacing.md)
                    .background(
                        message.role == .user
                            ? Color.white.opacity(0.2)
                            : AppColors.voiceChat.opacity(0.3)
                    )
                    .cornerRadius(AppCornerRadius.lg)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Voice Wave Animation

struct VoiceWaveAnimation: View {
    let isActive: Bool
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [AppColors.voiceChat, AppColors.voiceChat.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 6, height: isActive ? waveHeight(for: index) : 20)
                    .animation(
                        isActive
                            ? Animation.easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1)
                            : .default,
                        value: isActive
                    )
            }
        }
        .frame(height: 60)
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [30, 50, 60, 50, 30]
        return heights[index]
    }
}
