//
//  AlsayApp.swift
//  Alsay
//
//  Created by Say Al on 2025/3/12.
//

import Cocoa
import Foundation
import UserNotifications

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    let notificationCenter = UNUserNotificationCenter.current()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        checkAccessibilityPermissions()
        setupEventTap()
        setupNotifications()
    }
    
    func setupNotifications() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("通知权限请求失败: \(error.localizedDescription)")
            }
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
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)
        )
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { [weak self] _, _, event, _ in
                if event.type == .leftMouseUp || event.type == .rightMouseUp {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let text = self?.getSelectedText() {
                            self?.translateText(text: text) { result in
                                self?.showNotification(title: "翻译结果", subtitle: result ?? "翻译失败")
                            }
                        }
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil)
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func showNotification(title: String, subtitle: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = subtitle
        
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                          content: content,
                                          trigger: nil)
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("通知发送失败: \(error.localizedDescription)")
            }
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
            ["role": "system", "content": "你是一个翻译助手，请将用户输入的文本翻译成中文。只需要返回翻译结果，不要加任何解释。"],
            ["role": "user", "content": text]
        ]
        
        let body: [String: Any] = [
            "model": "glm-4-plus",
            "messages": messages,
            "stream": false
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(nil)
                return
            }
            completion(content)
        }.resume()
    }
    // MARK: - App Entry Point
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
