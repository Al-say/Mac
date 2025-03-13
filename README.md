# Alsay - Mac翻译工具

一个基于智普清言API的Mac翻译工具，支持中英双向翻译。

## 功能特点

- 双击选中文本自动翻译
- 支持中英双向翻译
- 自动识别文本语言
- 长文本支持独立窗口显示
- 支持复制翻译结果

## 安装使用

1. 从[Releases](https://github.com/Al-say/Mac/releases)下载最新版本
2. 将应用拖入应用程序文件夹
3. 首次运行时需要授予以下权限：
   - 辅助功能权限（用于获取选中文本）
   - 通知权限（用于显示翻译结果）

## 开发配置

1. 克隆仓库：
```bash
git clone https://github.com/Al-say/Mac.git
```

2. 配置API密钥：
   - 复制`Alsay/Config.swift.example`为`Alsay/Config.swift`
   - 在`Config.swift`中填入您的API密钥

3. 配置GitHub Actions密钥：
   - 在仓库设置中添加Secret: `ZHIPUAI_API_KEY`
   - 值为您的智普清言API密钥

## 使用方法

1. 选中要翻译的文本
2. 在选中文本区域双击
3. 自动识别语言并翻译：
   - 中文文本翻译为英文
   - 英文文本翻译为中文
4. 根据文本长度：
   - 短文本：通知形式显示
   - 长文本：独立窗口显示

## 技术栈

- Swift 5
- Cocoa Framework
- UserNotifications Framework
- 智普清言 GLM-4-Plus 模型

## 贡献指南

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启Pull Request

## 许可证

[MIT License](LICENSE)
