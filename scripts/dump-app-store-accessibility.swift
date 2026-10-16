import ApplicationServices
import AppKit
import Foundation

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success,
          let value = result else { return nil }
    if let text = value as? String { return text }
    if let text = value as? NSAttributedString { return text.string }
    return nil
}

guard let app = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.apple.AppStore"
).first else {
    fputs("App Store process not found\n", stderr)
    exit(2)
}

let root = AXUIElementCreateApplication(app.processIdentifier)
var visited = 0
let maxNodes = 2500
let maxDepth = 14
let shouldClickRetry = CommandLine.arguments.contains("--click-retry")
var retryClicked = false

func dump(_ element: AXUIElement, _ depth: Int) {
    guard visited < maxNodes, depth <= maxDepth else { return }
    visited += 1

    let role = stringAttribute(element, kAXRoleAttribute as String) ?? "?"
    let title = stringAttribute(element, kAXTitleAttribute as String)
    let description = stringAttribute(element, kAXDescriptionAttribute as String)
    let value = stringAttribute(element, kAXValueAttribute as String)
    let label = [title, description, value]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " | ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")

    if !label.isEmpty || role == (kAXButtonRole as String) || role == (kAXTextFieldRole as String) {
        print("\(String(repeating: "  ", count: depth))\(role)\(label.isEmpty ? "" : ": " + label)")
    }

    if shouldClickRetry, !retryClicked, role == (kAXButtonRole as String),
       [title, description, value].compactMap({ $0 }).contains(where: { $0 == "Retry" }) {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        retryClicked = result == .success
        print("RETRY_ACTION=\(result == .success ? "clicked" : "failed_\(result.rawValue)")")
    }

    var childrenResult: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenResult) == .success,
          let children = childrenResult as? [AXUIElement] else { return }
    for child in children {
        dump(child, depth + 1)
        if visited >= maxNodes { break }
    }
}

dump(root, 0)
print("AX_DUMP_NODES=\(visited)")
if shouldClickRetry && !retryClicked {
    print("RETRY_ACTION=button_not_found")
}
