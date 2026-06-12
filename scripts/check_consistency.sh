#!/bin/bash
#
# check_consistency.sh — 双端镜像文件 / 共享路径的一致性校验
#
# 为什么需要：
#   1. Xcode 16 的 FileSystemSynchronizedRootGroup 不支持跨 target 共享源文件，
#      IPCAction.swift 在 MenuPlus/ 与 FinderExt/ 各放一份，只靠注释约定手动同步；
#      漂移会导致 IPC 协议不匹配而"静默失败"。
#   2. 共享配置路径同时出现在 Swift 常量（ExtensionSharedConfig.relativePath）
#      与两份 .entitlements 的 temporary-exception 数组里；任何一处改了而其余
#      没跟上，扩展读共享配置会被沙盒静默拒绝。
#
# 接入方式：主 App target 的 Run Script build phase（Compile Sources 之前）调用，
# 任何不一致直接让构建失败。也可手动执行：bash scripts/check_consistency.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAIN_IPC="$ROOT/MenuPlus/IPCAction.swift"
EXT_IPC="$ROOT/FinderExt/IPCAction.swift"
MAIN_ENTITLEMENTS="$ROOT/MenuPlus/MenuPlus.entitlements"
EXT_ENTITLEMENTS="$ROOT/FinderExt/FinderExt.entitlements"

# 输出带 "error:" 前缀，Xcode 构建日志会把它识别为红色错误行
fail() {
    echo "error: [check_consistency] $1" >&2
    exit 1
}

for f in "$MAIN_IPC" "$EXT_IPC" "$MAIN_ENTITLEMENTS" "$EXT_ENTITLEMENTS"; do
    [ -f "$f" ] || fail "文件不存在：$f"
done

# ---------------------------------------------------------------------------
# 校验 1：两份 IPCAction.swift 除文件头注释外逐字节一致
#
# 文件头注释块（开头连续的 // 注释/空行，内容含 target 名与互指路径）合法地
# 不同，剥掉后 diff；首个非注释行（import Foundation）起必须完全一致。
# ---------------------------------------------------------------------------
strip_header() {
    awk 'body { print; next } /^\/\// || /^[[:space:]]*$/ { next } { body = 1; print }' "$1"
}

if ! diff -u <(strip_header "$MAIN_IPC") <(strip_header "$EXT_IPC"); then
    fail "两份 IPCAction.swift 内容不一致（上方为 diff，- 为 MenuPlus 端，+ 为 FinderExt 端）。请逐字节同步两份文件后重试。"
fi

# ---------------------------------------------------------------------------
# 校验 2：ExtensionSharedConfig.relativePath 的目录部分与两份 entitlements 的
#         temporary-exception 路径一致
#
# Swift 常量是相对 home 的形式（无前导斜杠、含文件名）：
#     Library/Application Support/MenuPlus/extension-config.json
# entitlements 是目录形式（前导斜杠 + 尾斜杠）：
#     /Library/Application Support/MenuPlus/
# 两边各自规范化（去首尾斜杠、去文件名）后比较目录部分。
# ---------------------------------------------------------------------------
extract_swift_constant() {
    # 从 Swift 源码提取 static let <name> = "<value>" 的字符串字面量
    sed -n "s/^[[:space:]]*static let $1 = \"\(.*\)\"\$/\1/p" "$MAIN_IPC" | head -n 1
}

config_dir_name="$(extract_swift_constant configDirectoryName)"
config_file_name="$(extract_swift_constant configFileName)"
relative_path_template="$(extract_swift_constant relativePath)"

[ -n "$config_dir_name" ] || fail "无法从 $MAIN_IPC 提取 configDirectoryName"
[ -n "$config_file_name" ] || fail "无法从 $MAIN_IPC 提取 configFileName"
[ -n "$relative_path_template" ] || fail "无法从 $MAIN_IPC 提取 relativePath"

# 还原 Swift 字符串插值 \(configDirectoryName) / \(configFileName)
relative_path="$(printf '%s' "$relative_path_template" \
    | sed -e "s/\\\\(configDirectoryName)/$config_dir_name/g" \
          -e "s/\\\\(configFileName)/$config_file_name/g")"

case "$relative_path" in
    *'\('*) fail "relativePath 含未识别的字符串插值，请更新本脚本的还原逻辑：$relative_path" ;;
esac

# 目录部分 + 规范化（去首尾斜杠）
normalize_dir() {
    local p="$1"
    p="${p#/}"
    p="${p%/}"
    printf '%s' "$p"
}

expected_dir="$(normalize_dir "$(dirname "$relative_path")")"

read_exception_path() {
    /usr/libexec/PlistBuddy -c "Print :$2:0" "$1" 2>/dev/null || true
}

main_exception="$(read_exception_path "$MAIN_ENTITLEMENTS" "com.apple.security.temporary-exception.files.home-relative-path.read-write")"
ext_exception="$(read_exception_path "$EXT_ENTITLEMENTS" "com.apple.security.temporary-exception.files.home-relative-path.read-only")"

[ -n "$main_exception" ] || fail "主 App entitlements 缺少 temporary-exception read-write 路径：$MAIN_ENTITLEMENTS"
[ -n "$ext_exception" ] || fail "扩展 entitlements 缺少 temporary-exception read-only 路径：$EXT_ENTITLEMENTS"

main_dir="$(normalize_dir "$main_exception")"
ext_dir="$(normalize_dir "$ext_exception")"

# 注意：变量引用必须用 ${} 形式——后面紧跟全角字符（如 "）"）时，
# bash 会把多字节字符的首字节并入变量名，触发 set -u 的 unbound variable
if [ "$main_dir" != "$expected_dir" ]; then
    fail "主 App entitlements 的 exception 路径（${main_exception}）与 ExtensionSharedConfig.relativePath 的目录（/${expected_dir}/）不一致"
fi

if [ "$ext_dir" != "$expected_dir" ]; then
    fail "扩展 entitlements 的 exception 路径（${ext_exception}）与 ExtensionSharedConfig.relativePath 的目录（/${expected_dir}/）不一致"
fi

echo "[check_consistency] 通过：IPCAction.swift 双端一致；temporary-exception 路径 = /$expected_dir/"
