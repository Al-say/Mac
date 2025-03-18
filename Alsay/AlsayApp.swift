//
//  AlsayApp.swift
//  Alsay
//
//  Created by Say Al on 2025/3/12.
//

import Cocoa
import Foundation

private var isMouseDown = false
private var lastMouseUpTime: TimeInterval = 0
private let selectionDelay: TimeInterval = 0.1  // 选择文本后等待翻译的时间

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }
    
    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    
    switch event.type {
    case .leftMouseDown:
        isMouseDown = true
    case .leftMouseUp:
        isMouseDown = false
        let currentTime = ProcessInfo.processInfo.systemUptime
        lastMouseUpTime = currentTime
        
        // 延迟一小段时间后检查是否有选中的文本
        DispatchQueue.main.asyncAfter(deadline: .now() + selectionDelay) {
            let checkTime = ProcessInfo.processInfo.systemUptime
            // 确保这是最近的鼠标释放事件
            guard checkTime - lastMouseUpTime >= selectionDelay else { return }
            
            if let selectedText = delegate.getSelectedText(), !selectedText.isEmpty {
                // 检测是否包含中文字符
                let isChinese = selectedText.unicodeScalars.contains { scalar in
                    // CJK统一汉字
                    (0x4E00...0x9FFF).contains(scalar.value) ||
                    // CJK扩展A区
                    (0x3400...0x4DBF).contains(scalar.value) ||
                    // CJK扩展B区
                    (0x20000...0x2A6DF).contains(scalar.value) ||
                    // 中文标点
                    (0x3000...0x303F).contains(scalar.value)
                }
                
                print("选中文本: \(selectedText)")
                print("是否包含中文: \(isChinese)")
                
                // 直接开始翻译
                delegate.translateText(text: selectedText, fromChinese: isChinese) { result in
                    if let result = result {
                        DispatchQueue.main.async {
                            delegate.showNotification(title: "翻译结果", text: result)
                        }
                    }
                }
            }
        }
    default:
        break
    }
    
    return Unmanaged.passRetained(event)
}

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    var eventTapRunLoopSource: CFRunLoopSource?
    private var isTranslatingFromChinese: Bool = false
    private var lastTranslation: String?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        checkAccessibilityPermissions()
        setupEventTap()
        setupNotificationCenter()
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanupEventTap()
    }
    
    func setupNotificationCenter() {
        let center = NSUserNotificationCenter.default
        center.delegate = self
    }
    
    // 允许显示通知，即使应用在前台
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    // 处理通知操作
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if notification.actionButtonTitle == "复制" {
            if let translatedText = lastTranslation {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(translatedText, forType: .string)
            }
        }
    }
    
    func showNotification(title: String, text: String) {
        lastTranslation = text
        
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = text
        notification.hasActionButton = true
        notification.actionButtonTitle = "复制"
        notification.soundName = nil  // 不播放声音
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "译"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "测试API", action: #selector(testAPI), keyEquivalent: "t"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc func testAPI() {
        translateText(text: "测试", fromChinese: true) { result in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if result != nil {
                    alert.messageText = "API测试成功"
                    alert.informativeText = "翻译服务工作正常"
                } else {
                    alert.messageText = "API测试失败"
                    alert.informativeText = "无法连接到翻译服务，请检查API密钥和网络连接"
                    alert.alertStyle = .warning
                }
                alert.runModal()
            }
        }
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("需要辅助功能权限")
            return
        }
    }
    
    func setupEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr)
        
        if let tap = eventTap {
            eventTapRunLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            if let runLoopSource = eventTapRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }
    
    func cleanupEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        eventTapRunLoopSource = nil
    }
    
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        Thread.sleep(forTimeInterval: 0.1)
        let selectedText = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        if let original = original {
            pasteboard.setString(original, forType: .string)
        }
        return selectedText
    }
    
    func translateText(text: String, fromChinese: Bool, completion: @escaping (String?) -> Void) {
        let apiKey = Config.apiKey
        let url = URL(string: Config.apiEndpoint)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("开始翻译，方向: \(fromChinese ? "中译英" : "英译中")")
        let systemPrompt = fromChinese ?
            "You are a translator. Translate the Chinese text into English. Keep it natural and idiomatic. Maintain paragraph structure. Do not add any explanations or formatting." :
            "你是一个翻译助手。请将用户输入的文本翻译成中文。要准确、通顺、符合中文表达习惯。保持原文的段落结构。不要添加解释或额外格式。"
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]
        
        let body: [String: Any] = [
            "model": "glm-4-plus",
            "messages": messages,
            "stream": false,
            "temperature": 0.3,
            "max_tokens": 8000,
            "top_p": 0.7
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("API请求失败: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("服务器响应错误")
                completion(nil)
                return
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("API错误: \(message)")
                } else {
                    print("服务器响应错误: \(httpResponse.statusCode)")
                }
                completion(nil)
                return
            }
            
            do {
                guard let data = data,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let firstChoice = choices.first,
                      let message = firstChoice["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    print("解析响应数据失败")
                    completion(nil)
                    return
                }
                completion(content)
            } catch {
                print("JSON解析失败: \(error.localizedDescription)")
                completion(nil)
            }
        }.resume()
    }
    
    // 保持对delegate的强引用
    private static var sharedDelegate: AppDelegate!
    
    static func main() {
        let app = NSApplication.shared
        sharedDelegate = AppDelegate()
        app.delegate = sharedDelegate
        app.run()
    }
    
    deinit {
        cleanupEventTap()
    }
}
