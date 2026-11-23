import SwiftUI

/// GlideCut 设置窗口（V1.0.1）。
///
/// 布局要点：
/// - 恢复最初的顶部展示：App 图标 + 标题 + 副标题 + 运行状态徽标。
/// - 单页固定布局，无 ScrollView，不需要滚轮操作。
/// - 通用 / 修饰键 / 权限 / 关于四个分区统一加边框突出。
/// - 关于区：版本 / 系统要求 / 开发者 + 四张居中二维码（微信赞赏 / 支付宝 / 联系作者 / 关注抖音）
///   + 作者邮箱一键复制 + 免责提示。
/// - 窗口高度按内容收缩，消除底部空白。
/// - 所有 API 兼容 macOS 13.0。
struct SettingsView: View {
    @ObservedObject var controller: EventController
    @StateObject private var settings = SettingsStore.shared
    @ObservedObject private var permissions = PermissionsMonitor.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 720, height: 762)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { permissions.refresh() }
    }

    // MARK: - 顶部展示（恢复原样）

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("GlideCut")
                    .font(.system(size: 20, weight: .semibold))
                Text("settings.subtitle", tableName: "Localizable")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// 当前运行状态徽标。
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(controller.isListening ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(controller.isListening ? "status.active" : "status.inactive",
                 tableName: "Localizable")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(controller.isListening ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - 内容（单页，无滚动，高度贴合）

    private var content: some View {
        VStack(spacing: 10) {
            generalSection
            modifierSection
            permissionSection
            aboutSection
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 通用

    private var generalSection: some View {
        SettingsCard(title: "settings.section.general", symbol: "slider.horizontal.3") {
            VStack(spacing: 6) {
                SettingToggleRow(
                    title: "settings.feature.enabled",
                    desc: "settings.feature.desc",
                    isOn: controller.isListeningBinding
                )

                Divider()

                SettingToggleRow(
                    title: "settings.launchAtLogin",
                    desc: "settings.launchAtLogin.desc",
                    isOn: $settings.launchAtLogin
                )
            }
        }
    }

    // MARK: - 修饰键

    private var modifierSection: some View {
        SettingsCard(title: "settings.section.modifier", symbol: "command") {
            VStack(spacing: 6) {
                ModifierRow(
                    title: "settings.zoom.modifier",
                    desc: "settings.zoom.desc",
                    selection: $settings.zoomModifier,
                    options: modifierOptions
                )

                Divider()

                ModifierRow(
                    title: "settings.pan.modifier",
                    desc: "settings.pan.desc",
                    selection: $settings.panModifier,
                    options: panModifierOptions
                )

                if settings.hasConflict {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 10))
                        Text("settings.modifier.conflict", tableName: "Localizable")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 权限

    private var permissionSection: some View {
        SettingsCard(title: "settings.section.permission", symbol: "checkmark.shield") {
            VStack(spacing: 6) {
                PermissionRow(
                    title: "settings.permission.inputMonitoring",
                    granted: permissions.hasInputMonitoring
                )
                PermissionRow(
                    title: "settings.permission.accessibility",
                    granted: permissions.hasAccessibility
                )

                if !permissions.isReady {
                    HStack(spacing: 8) {
                        if !permissions.hasInputMonitoring {
                            Button("settings.permission.grantInput") {
                                PermissionStatus.openInputMonitoringSettings()
                            }
                            .controlSize(.small)
                        }
                        if !permissions.hasAccessibility {
                            Button("settings.permission.grantAccessibility") {
                                PermissionStatus.openAccessibilitySettings()
                            }
                            .controlSize(.small)
                        }
                        Spacer()
                        Button("settings.permission.refresh") { permissions.refresh() }
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - 关于 GlideCut

    private var aboutSection: some View {
        SettingsCard(title: "settings.section.about.title", symbol: "info.circle") {
            VStack(spacing: 9) {
                // 信息行居中
                HStack(spacing: 22) {
                    AboutInfoRow(label: "about.currentVersion", value: AboutMetadata.displayVersion)
                    AboutInfoRow(label: "settings.os.label", value: AboutMetadata.osRequirement)
                    AboutInfoRow(label: "about.developer", value: AboutMetadata.developer)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Divider()

                // 四张二维码：微信赞赏 / 支付宝 / 联系作者 / 关注抖音，居中排版
                HStack(alignment: .top, spacing: 20) {
                    QRCodeCell(imageName: "QRReward", title: "about.qr.reward")
                    QRCodeCell(imageName: "QRAlipay", title: "about.qr.alipay")
                    QRCodeCell(imageName: "QRWechat", title: "about.qr.contact")
                    QRCodeCell(imageName: "QRDouyin", title: "about.qr.douyin")
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // 作者邮箱一键复制
                EmailCopyRow(email: AboutMetadata.email)

                Divider()

                // 免责 / 使用提示
                Text("settings.about.intro", tableName: "Localizable")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                // 恢复默认设置（右对齐）
                HStack {
                    Spacer()
                    Button {
                        settings.restoreDefaults()
                    } label: {
                        Text("settings.restoreDefaults", tableName: "Localizable")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    /// 缩放的修饰键选项（不含纯 Shift，避免与 FCP 原生行为冲突）。
    private var modifierOptions: [ModifierState] {
        [.command, .option, .control, [.command, .shift], [.option, .shift], [.control, .shift]]
    }

    /// 水平平移的修饰键选项。
    /// - Shift：保持 FCP 原生行为，推荐。
    /// - Option/Control：由辅助功能驱动平移。
    private var panModifierOptions: [ModifierState] {
        [.shift, .option, .control]
    }
}

// MARK: - 元信息

/// 关于区展示信息。与安装包版本保持一致，显示 V1.0.1。
private enum AboutMetadata {
    static let displayVersion = "V1.0.1"
    static let osRequirement = "MacOS 13.0+"
    static let developer = "CCstudio"
    static let email = "keyframecc@foxmail.com"
}

// MARK: - 复用组件

/// 设置分组卡片：统一加边框突出。
private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(title, tableName: "Localizable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.30), lineWidth: 1)
                    )
            )
        }
    }
}

/// 带说明的开关行。
private struct SettingToggleRow: View {
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title, tableName: "Localizable")
                    .font(.system(size: 13, weight: .medium))
                Text(desc, tableName: "Localizable")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(minHeight: 32)
    }
}

/// 修饰键选择行。
private struct ModifierRow: View {
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
    @Binding var selection: ModifierState
    let options: [ModifierState]
    var unavailable: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title, tableName: "Localizable")
                    .font(.system(size: 13, weight: .medium))
                Text(desc, tableName: "Localizable")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { state in
                    Text(state.description).tag(state)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 132)
            .disabled(unavailable)
        }
        .frame(minHeight: 34)
        .opacity(unavailable ? 0.55 : 1.0)
    }
}

/// 权限状态行。
private struct PermissionRow: View {
    let title: LocalizedStringKey
    let granted: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
                .font(.system(size: 12))
            Text(title, tableName: "Localizable")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(granted ? "permission.granted" : "permission.denied", tableName: "Localizable")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(minHeight: 20)
    }
}

/// 关于页键值行。
private struct AboutInfoRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label, tableName: "Localizable")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }
}

/// 二维码单元格。
private struct QRCodeCell: View {
    let imageName: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let image = NSImage(named: imageName) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(width: 92, height: 92)
            .background(Color.white)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )

            Text(title, tableName: "Localizable")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

/// 作者邮箱一键复制行。
/// 说明：本环境不支持 SwiftUI 宏插件的沙盒展开，故用无状态的 NSButton 实现复制，
/// 避免引入新的 @State/@Published 宏展开。点击即把邮箱写入系统剪贴板。
private struct EmailCopyRow: View {
    let email: String

    var body: some View {
        HStack(spacing: 8) {
            Text("about.email.label", tableName: "Localizable")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(email)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
            CopyButton(email: email)
                .frame(width: 74, height: 20)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// 用 AppKit 的 NSButton 承载复制动作，绕开 SwiftUI 宏展开限制。
private struct CopyButton: NSViewRepresentable {
    let email: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: NSLocalizedString("about.email.copy", comment: ""),
                              target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        button.target = CopyTarget.shared
        button.action = #selector(CopyTarget.copyEmail(_:))
        button.identifier = NSUserInterfaceItemIdentifier(email)
        button.toolTip = NSLocalizedString("about.email.copy.help", comment: "")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(email)
    }
}

/// 复制动作目标：从按钮 identifier 取邮箱并写入剪贴板。
private final class CopyTarget: NSObject {
    static let shared = CopyTarget()

    @objc func copyEmail(_ sender: NSButton) {
        let value = sender.identifier?.rawValue ?? ""
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
