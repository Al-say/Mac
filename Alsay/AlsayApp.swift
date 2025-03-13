//
//  AlsayApp.swift
//  Alsay
//
//  Created by Say Al on 2025/3/12.
//

import Cocoa
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var eventTap: CFMachPort?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        checkAccessibilityPermissions()
        setupEventTap()
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
            callback: eventCallback,
            userInfo: nil)
        
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

let eventCallback: CGEventTapCallBack = { _, _, event, _ in
    if event.type == .leftMouseUp || event.type == .rightMouseUp {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let text = getSelectedText() {
                translateText(text: text) { result in
                    showNotification(title: "翻译结果", subtitle: result ?? "翻译失败")
                }
            }
        }
    }
    return Unmanaged.passRetained(event)
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
    let apiKey = "YOUR_API_KEY" // 替换为实际API密钥
    let url = URL(string: "https://api.智普清言.com/v1/translate")! // 替换为实际API端点
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let body: [String: Any] = ["text": text, "target_lang": "zh"]
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    
    URLSession.shared.dataTask(with: request) { data, _, _ in
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["translated_text"] as? String else {
            completion(nil)
            return
        }
        completion(result)
    }.resume()
}

func showNotification(title: String, subtitle: String) {
    let notification = NSUserNotification()
    notification.title = title
    notification.informativeText = subtitle
    NSUserNotificationCenter.default.deliver(notification)
}

// 启动应用
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
