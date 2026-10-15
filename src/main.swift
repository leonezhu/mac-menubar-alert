// MenuBarAlert —— 在 macOS 菜单栏（右上角状态栏）显示可配置的警示语
//
// 配置文件：~/.menubar-alert.json（保存后 2 秒内自动生效）
// 日志文件：~/Library/Logs/MenuBarAlert.log
// 构建：./build.sh        安装到 ~/Applications：./install.sh
// 自检：MenuBarAlert --print   打印当前应显示的菜单栏文字后退出

import AppKit
import Foundation

let home = NSHomeDirectory()
let configPath = home + "/.menubar-alert.json"
let launchAgentLabel = "local.menubar-alert"
let launchAgentPath = home + "/Library/LaunchAgents/" + launchAgentLabel + ".plist"
let logPath = home + "/Library/Logs/MenuBarAlert.log"

// MARK: - 日志

func logLine(_ message: String) {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
    guard let data = ("[\(fmt.string(from: Date()))] \(message)\n").data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: logPath)
    if let handle = try? FileHandle(forWritingTo: url) {
        defer { try? handle.close() }
        _ = handle.seekToEndOfFile()
        handle.write(data)
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 配置

struct AlertConfig {
    var prefix: String
    var phrases: [String]
    var intervalSeconds: Double
    var rotate: Bool

    static let fallback = AlertConfig(prefix: "⚠️",
                                      phrases: ["今天最重要的一件事是什么？", "先确认，再动手"],
                                      intervalSeconds: 20,
                                      rotate: false)
}

extension AlertConfig: Codable {
    enum CodingKeys: String, CodingKey { case prefix, phrases, intervalSeconds, rotate }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AlertConfig.fallback
        self.init(prefix: decode(container, .prefix, defaults.prefix),
                  phrases: decode(container, .phrases, defaults.phrases),
                  intervalSeconds: decode(container, .intervalSeconds, defaults.intervalSeconds),
                  rotate: decode(container, .rotate, defaults.rotate))
    }
}

/// 单个字段缺失或类型不对时退回默认值，避免用户手改 JSON 时整个配置失效。
private func decode<T: Decodable>(_ container: KeyedDecodingContainer<AlertConfig.CodingKeys>,
                                  _ key: AlertConfig.CodingKeys,
                                  _ fallback: T) -> T {
    // 注意：Swift 5 起 `try?` 会把 decodeIfPresent 的 T? 压平成 T?（缺字段与解码失败都得到 nil）
    if let value = try? container.decodeIfPresent(T.self, forKey: key) {
        return value
    }
    return fallback
}

func normalize(_ raw: AlertConfig) -> AlertConfig {
    var result = raw
    let cleaned = result.phrases
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    result.phrases = cleaned.isEmpty ? AlertConfig.fallback.phrases : cleaned
    if result.intervalSeconds < 2 { result.intervalSeconds = 2 }
    return result
}

@discardableResult
func saveConfig(_ config: AlertConfig) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(config) else { return false }
    return (try? data.write(to: URL(fileURLWithPath: configPath), options: .atomic)) != nil
}

/// 返回 (配置, 提示)。配置为 nil 表示读取失败，调用方应沿用上一次的配置。
func loadConfigFromDisk(createIfMissing: Bool) -> (AlertConfig?, String?) {
    let manager = FileManager.default
    guard manager.fileExists(atPath: configPath) else {
        guard createIfMissing else { return (nil, "配置文件不存在") }
        let ok = saveConfig(AlertConfig.fallback)
        return (AlertConfig.fallback, ok ? "未找到配置文件，已生成默认配置：\(configPath)"
                                        : "未找到配置文件，且无法写入默认配置：\(configPath)")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let decoded = try JSONDecoder().decode(AlertConfig.self, from: data)
        return (normalize(decoded), nil)
    } catch {
        return (nil, "配置解析失败，继续沿用上一次的配置：\(error.localizedDescription)")
    }
}

func configModificationDate() -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: configPath))?[.modificationDate] as? Date
}

// MARK: - 小工具

func runCommand(_ launchPath: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    do {
        try process.run()
    } catch {
        logLine("命令启动失败：\(launchPath) \(arguments.joined(separator: " ")) —— \(error)")
    }
}

func launchAgentPlist(executablePath: String) -> String {
    let escaped = executablePath
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>\(launchAgentLabel)</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(escaped)</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>ProcessType</key>
        <string>Interactive</string>
    </dict>
    </plist>

    """
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var config = AlertConfig.fallback
    private var phraseIndex = 0
    private var rotationTimer: Timer?
    private var watchTimer: Timer?
    private var knownConfigDate: Date?

    private let headerItem = NSMenuItem(title: "当前：", action: nil, keyEquivalent: "")
    private let nextItem = NSMenuItem(title: "下一条警示语", action: nil, keyEquivalent: "")
    private let rotateItem = NSMenuItem(title: "多条自动轮播", action: nil, keyEquivalent: "")
    private let launchItem = NSMenuItem(title: "开机自动启动", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        buildMenu(for: item)

        apply(loadConfigFromDisk(createIfMissing: true), reason: "启动")
        knownConfigDate = configModificationDate()
        startRotation()
        startWatchingConfigFile()
        logLine("已启动，配置文件：\(configPath)")

        // 启动 1.5 秒后自检：确认状态栏项目确实被系统显示出来
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let item = self.statusItem else { return }
            let width = item.button?.frame.width ?? 0
            logLine("自检：状态栏项目可见=\(item.isVisible)，宽度=\(String(format: "%.1f", width))pt，文字=\(self.currentTitle())")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logLine("已退出")
    }

    // MARK: 显示

    private func currentTitle() -> String {
        guard !config.phrases.isEmpty else { return "（未配置警示语）" }
        let index = min(max(phraseIndex, 0), config.phrases.count - 1)
        let phrase = config.phrases[index]
        return config.prefix.isEmpty ? phrase : config.prefix + " " + phrase
    }

    private func applyTitle() {
        let title = currentTitle()
        statusItem?.button?.title = title
        statusItem?.button?.toolTip = title
        headerItem.title = "当前：\(title)"
    }

    private func apply(_ result: (AlertConfig?, String?), reason: String) {
        let loadedNew = result.0 != nil
        if let loaded = result.0 {
            config = loaded
        }
        if let note = result.1 {
            logLine("\(reason)：\(note)")
        }
        if phraseIndex >= config.phrases.count { phraseIndex = 0 }
        applyTitle()
        refreshMenuState()
        if loadedNew {
            logLine("\(reason)：已载入 \(config.phrases.count) 条警示语，轮播=\(config.rotate)，间隔=\(Int(config.intervalSeconds))s，当前显示「\(currentTitle())」")
        }
    }

    // MARK: 轮播与热加载

    private func startRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard config.rotate, config.phrases.count > 1, config.intervalSeconds > 0 else { return }
        let timer = Timer(timeInterval: config.intervalSeconds, repeats: true) { [weak self] _ in
            guard let self = self, !self.config.phrases.isEmpty else { return }
            self.phraseIndex = (self.phraseIndex + 1) % self.config.phrases.count
            self.applyTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    private func startWatchingConfigFile() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reloadIfConfigChanged()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func reloadIfConfigChanged() {
        guard let date = configModificationDate() else { return }
        guard date != knownConfigDate else { return }
        knownConfigDate = date
        phraseIndex = 0  // 手改配置后从头一条开始显示
        apply(loadConfigFromDisk(createIfMissing: false), reason: "配置变更")
        startRotation()
    }

    // MARK: 菜单

    private func buildMenu(for item: NSStatusItem) {
        let menu = NSMenu()

        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(nextItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "编辑警示语…", action: #selector(editConfigFile), keyEquivalent: "e"))
        menu.addItem(NSMenuItem(title: "显示配置文件位置", action: #selector(revealConfigFile), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: "重新加载配置", action: #selector(reloadNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(rotateItem)
        menu.addItem(launchItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        for entry in menu.items where entry.action != nil {
            entry.target = self
        }
        rotateItem.action = #selector(toggleRotate)
        nextItem.action = #selector(showNextPhrase)
        launchItem.action = #selector(toggleLaunchAtLogin)
        for entry in [rotateItem, nextItem, launchItem] {
            entry.target = self
        }

        item.menu = menu
    }

    private func refreshMenuState() {
        headerItem.title = "当前：\(currentTitle())"
        rotateItem.state = config.rotate ? .on : .off
        rotateItem.isEnabled = config.phrases.count > 1
        nextItem.isHidden = config.phrases.count <= 1
        launchItem.state = FileManager.default.fileExists(atPath: launchAgentPath) ? .on : .off
    }

    // MARK: 菜单动作

    @objc private func showNextPhrase() {
        guard !config.phrases.isEmpty else { return }
        phraseIndex = (phraseIndex + 1) % config.phrases.count
        applyTitle()
        refreshMenuState()
    }

    @objc private func editConfigFile() {
        if !FileManager.default.fileExists(atPath: configPath) { _ = saveConfig(config) }
        runCommand("/usr/bin/open", ["-e", configPath])
    }

    @objc private func revealConfigFile() {
        if !FileManager.default.fileExists(atPath: configPath) { _ = saveConfig(config) }
        runCommand("/usr/bin/open", ["-R", configPath])
    }

    @objc private func reloadNow() {
        phraseIndex = 0
        apply(loadConfigFromDisk(createIfMissing: true), reason: "手动重新加载")
        knownConfigDate = configModificationDate()
        startRotation()
    }

    @objc private func toggleRotate() {
        config.rotate.toggle()
        _ = saveConfig(config)
        knownConfigDate = configModificationDate()
        refreshMenuState()
        startRotation()
        logLine("多条自动轮播 = \(config.rotate)")
    }

    @objc private func toggleLaunchAtLogin() {
        let manager = FileManager.default
        if manager.fileExists(atPath: launchAgentPath) {
            runCommand("/bin/launchctl", ["unload", launchAgentPath])
            do {
                try manager.removeItem(atPath: launchAgentPath)
                logLine("已关闭开机自启")
            } catch {
                logLine("删除 LaunchAgent 失败：\(error)")
            }
        } else {
            let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
            let directory = (launchAgentPath as NSString).deletingLastPathComponent
            try? manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            do {
                try launchAgentPlist(executablePath: executable)
                    .write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
                runCommand("/bin/launchctl", ["load", launchAgentPath])
                logLine("已开启开机自启：\(launchAgentPath)")
            } catch {
                logLine("写入 LaunchAgent 失败：\(error)")
            }
        }
        refreshMenuState()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - 入口

if CommandLine.arguments.contains("--print") {
    let result = loadConfigFromDisk(createIfMissing: true)
    if let loaded = result.0, let first = loaded.phrases.first {
        print(loaded.prefix.isEmpty ? first : loaded.prefix + " " + first)
        exit(0)
    }
    FileHandle.standardError.write(((result.1 ?? "配置不可用") + "\n").data(using: .utf8)!)
    exit(1)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
