//
//  TemplateProvider.swift
//  MenuPlus
//
//  按模板类型提供"新建文件"的初始内容。
//  Office 三件套不是空文件能伪装的格式（zip + 最小 OOXML 包结构），
//  故由 scripts/generate_office_templates.py 预生成合法模板放入 bundle，
//  创建时直接拷贝其字节内容。
//

import Foundation

enum TemplateProvider {
    static func content(for template: FileTemplate) throws -> Data {
        switch template {
        case .markdown:
            // 空内容即合法 Markdown
            return Data()
        case .rtf:
            // TextEdit 可打开的最小 RTF 结构；ansicpg936 预声明简体中文代码页
            return Data("{\\rtf1\\ansi\\ansicpg936 }".utf8)
        case .word:
            return try bundledTemplate(withExtension: "docx")
        case .excel:
            return try bundledTemplate(withExtension: "xlsx")
        case .powerpoint:
            return try bundledTemplate(withExtension: "pptx")
        }
    }

    /// 读取 bundle 内预生成的 Office 模板。
    /// MenuPlus/Templates/ 经 FileSystemSynchronizedRootGroup 打包后被平铺到
    /// Resources/ 根目录（构建产物已实测确认），故按根目录查找。
    private static func bundledTemplate(withExtension ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: "Template", withExtension: ext) else {
            throw NSError(
                domain: "MenuPlus.TemplateProvider",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "应用内缺少模板资源 Template.\(ext)，请重新安装 MenuPlus"]
            )
        }
        return try Data(contentsOf: url)
    }
}
