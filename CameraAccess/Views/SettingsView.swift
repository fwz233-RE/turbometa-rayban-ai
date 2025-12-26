/*
 * Settings View
 * 个人中心 - 设备管理和设置
 */

import SwiftUI
import MWDATCore

struct SettingsView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel

    @State private var showModelSettings = false
    @State private var showLanguageSettings = false
    @State private var selectedModel = "qwen3-omni-flash-realtime"
    @State private var selectedLanguage = "zh-CN" // 默认中文

    init(streamViewModel: StreamSessionViewModel) {
        self.streamViewModel = streamViewModel
    }

    var body: some View {
        NavigationView {
            List {
                // 设备管理
                Section {
                    // 连接状态
                    HStack {
                        Image(systemName: "eye.circle.fill")
                            .foregroundColor(AppColors.primary)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ray-Ban Meta")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.textPrimary)
                            Text(streamViewModel.hasActiveDevice ? "已连接" : "未连接")
                                .font(AppTypography.caption)
                                .foregroundColor(streamViewModel.hasActiveDevice ? .green : AppColors.textSecondary)
                        }

                        Spacer()

                        // 连接状态指示器
                        Circle()
                            .fill(streamViewModel.hasActiveDevice ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.vertical, AppSpacing.sm)

                    // 设备信息
                    if streamViewModel.hasActiveDevice {
                        InfoRow(title: "设备状态", value: "在线")

                        if streamViewModel.isStreaming {
                            InfoRow(title: "视频流", value: "活跃")
                        } else {
                            InfoRow(title: "视频流", value: "未启动")
                        }

                        // TODO: 从 SDK 获取更多设备信息
                        // InfoRow(title: "电量", value: "85%")
                        // InfoRow(title: "固件版本", value: "v20.0")
                    }
                } header: {
                    Text("设备管理")
                }

                // AI 设置
                Section {
                    Button {
                        showModelSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(AppColors.accent)
                            Text("模型设置")
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text(selectedModel)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Button {
                        showLanguageSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(AppColors.translate)
                            Text("输出语言")
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Text(languageDisplayName(selectedLanguage))
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                } header: {
                    Text("AI 设置")
                }

                // 关于
                Section {
                    InfoRow(title: "版本", value: "1.0.0")
                    InfoRow(title: "SDK 版本", value: "0.3.0")
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showModelSettings) {
                ModelSettingsView(selectedModel: $selectedModel)
            }
            .sheet(isPresented: $showLanguageSettings) {
                LanguageSettingsView(selectedLanguage: $selectedLanguage)
            }
        }
    }

    private func languageDisplayName(_ code: String) -> String {
        switch code {
        case "zh-CN": return "中文"
        case "en-US": return "English"
        case "ja-JP": return "日本語"
        case "ko-KR": return "한국어"
        case "es-ES": return "Español"
        case "fr-FR": return "Français"
        default: return "中文"
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
            Text(value)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}


// MARK: - Model Settings

struct ModelSettingsView: View {
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss

    let models = [
        "qwen3-omni-flash-realtime",
        "qwen3-omni-standard-realtime"
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(models, id: \.self) { model in
                        Button {
                            selectedModel = model
                        } label: {
                            HStack {
                                Text(model)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedModel == model {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("选择模型")
                } footer: {
                    Text("当前使用: \(selectedModel)")
                }
            }
            .navigationTitle("模型设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Language Settings

struct LanguageSettingsView: View {
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) private var dismiss

    let languages = [
        ("zh-CN", "中文"),
        ("en-US", "English"),
        ("ja-JP", "日本語"),
        ("ko-KR", "한국어"),
        ("es-ES", "Español"),
        ("fr-FR", "Français")
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(languages, id: \.0) { lang in
                        Button {
                            selectedLanguage = lang.0
                        } label: {
                            HStack {
                                Text(lang.1)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedLanguage == lang.0 {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("选择输出语言")
                } footer: {
                    Text("AI 将使用该语言进行语音输出和文字回复")
                }
            }
            .navigationTitle("输出语言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
