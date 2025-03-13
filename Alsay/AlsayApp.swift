//
//  AlsayApp.swift
//  Alsay
//
//  Created by Say Al on 2025/3/12.
//

import Cocoa
import Foundation

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
                
                delegate.translateText(text: selectedText, fromChinese: isChinese) { result in
                    delegate.showNotification(title: "翻译结果", subtitle: result ?? "翻译失败")
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
        let eventMask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
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
    
    var translationWindow: NSPanel?
    
    func showNotification(title: String, subtitle: String) {
        DispatchQueue.main.async { [weak self] in
            self?.showTranslationWindow(title: title, text: subtitle)
        }
    }
    
    func showTranslationWindow(title: String, text: String) {
        if translationWindow == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
                styleMask: [.titled, .closable, .resizable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.center()
            window.level = .floating
            window.isFloatingPanel = true
            window.worksWhenModal = true
            
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
            
            let copyButton = NSButton(frame: NSRect(x: 10, y: 10, width: 100, height: 30))
            copyButton.title = "复制"
            copyButton.bezelStyle = .rounded
            copyButton.target = self
            copyButton.action = #selector(copyTranslation)
            window.contentView?.addSubview(copyButton)
            
            translationWindow = window
        } else {
            translationWindow?.title = title
            if let scrollView = translationWindow?.contentView?.subviews.first as? NSScrollView,
               let textView = scrollView.documentView as? NSTextView {
                textView.string = text
            }
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
    }
}
