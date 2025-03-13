//
//  AlsayApp.swift
//  Alsay
//
//  Created by Say Al on 2025/3/12.
//

import Cocoa
import Foundation
import UserNotifications

private var lastClickTime: TimeInterval = 0

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }
    
    let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
    
    // 处理双击
    if event.type == .leftMouseDown {
        let currentTime = ProcessInfo.processInfo.systemUptime
        if currentTime - lastClickTime < 0.5 { // 双击时间阈值
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let text = delegate.getSelectedText() {
                    delegate.translateText(text: text) { result in
                        delegate.showNotification(title: "翻译结果", subtitle: result ?? "翻译失败")
                    }
                }
            }
        }
        lastClickTime = currentTime
    }
    
    return Unmanaged.passRetained(event)
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    let notificationCenter = UNUserNotificationCenter.current()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        checkAccessibilityPermissions()
        requestNotificationPermission()
    }
    
    func requestNotificationPermission() {
        // 检查当前通知权限状态
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    self?.setupEventTap()
                case .denied:
                    self?.showNotificationDeniedAlert()
                case .notDetermined:
                    // 首次请求权限
                    self?.notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
                        DispatchQueue.main.async {
                            if granted {
                                self?.setupEventTap()
                            } else {
                                self?.showNotificationDeniedAlert()
                            }
                        }
                    }
                default:
                    self?.showNotificationDeniedAlert()
                }
            }
        }
    }
    
    func showNotificationDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "需要通知权限"
        alert.informativeText = "请在系统设置中允许通知权限，以便显示翻译结果。\n设置 -> 通知 -> Alsay"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
        }
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "译"
    }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            print("需要辅助功能权限")
            return
        }
    }
    
    func setupEventTap() {
        let eventMask = CGEventMask(
            (1 << CGEventType.leftMouseDown.rawValue)
        )
        
        // Store self as userInfo for the callback
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr)
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    var translationWindow: NSWindow?
    
    func showNotification(title: String, subtitle: String) {
        if subtitle.count > 100 {
            // 长文本使用窗口显示
            DispatchQueue.main.async { [weak self] in
                self?.showTranslationWindow(title: title, text: subtitle)
            }
        } else {
            // 短文本使用通知
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = subtitle
            content.categoryIdentifier = "translation"
            
            // 添加查看详情按钮
            let viewAction = UNNotificationAction(
                identifier: "view",
                title: "查看详情",
                options: .foreground
            )
            
            let category = UNNotificationCategory(
                identifier: "translation",
                actions: [viewAction],
                intentIdentifiers: [],
                options: []
            )
            
            notificationCenter.setNotificationCategories([category])
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            notificationCenter.add(request) { error in
                if let error = error {
                    print("通知发送失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func showTranslationWindow(title: String, text: String) {
        // 创建窗口
        if translationWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.center()
            
            // 创建文本视图
            let scrollView = NSScrollView(frame: window.contentView!.bounds)
            scrollView.hasVerticalScroller = true
            scrollView.autoresizingMask = [.width, .height]
            
            let textView = NSTextView(frame: scrollView.bounds)
            textView.autoresizingMask = [.width, .height]
            textView.isEditable = false
            textView.font = NSFont.systemFont(ofSize: 14)
            textView.string = text
            
            scrollView.documentView = textView
            window.contentView?.addSubview(scrollView)
            
            // 添加复制按钮
            let copyButton = NSButton(frame: NSRect(x: 10, y: 10, width: 100, height: 30))
            copyButton.title = "复制"
            copyButton.bezelStyle = .rounded
            copyButton.target = self
            copyButton.action = #selector(copyTranslation)
            window.contentView?.addSubview(copyButton)
            
            translationWindow = window
        }
        
        translationWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc func copyTranslation() {
        if let window = translationWindow,
           let scrollView = window.contentView?.subviews.first as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textView.string, forType: .string)
        }
    }
    
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let original = pasteboard.string(forType: .string)
        
        // 模拟复制操作
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
    
    func translateText(text: String, completion: @escaping (String?) -> Void) {
        let apiKey = Config.apiKey
        let url = URL(string: Config.apiEndpoint)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": "你是一个翻译助手。请将用户输入的文本翻译成中文。不要添加任何解释、标点符号或格式，只返回翻译结果。对于长文本，保持原文的段落结构。"],
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
    
    // MARK: - App Entry Point
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        // Release the retained self pointer
        if let runLoop = CFRunLoopGetCurrent() {
            CFRunLoopRemoveSource(runLoop, 
                CFMachPortCreateRunLoopSource(nil, eventTap!, 0),
                .commonModes)
        }
    }
}
