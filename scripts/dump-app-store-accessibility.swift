import ApplicationServices
import AppKit
import CoreGraphics
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
let clickTarget: String? = CommandLine.arguments.contains("--click-retry") ? "Retry" :
    (CommandLine.arguments.contains("--click-continue") ? "Continue" :
    (CommandLine.arguments.contains("--click-not-now") ? "Not Now" :
    (CommandLine.arguments.contains("--click-install") ? "INSTALL_ACTION" : nil)))
var targetClicked = false

func press(_ element: AXUIElement) -> String {
    let action = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if action == .success { return "clicked_via_ax" }

    var positionResult: CFTypeRef?
    var sizeResult: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionResult) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeResult) == .success,
          let positionObject = positionResult,
          let sizeObject = sizeResult else { return "failed_\(action.rawValue)" }
    let positionValue = positionObject as! AXValue
    let sizeValue = sizeObject as! AXValue
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size) else {
        return "failed_\(action.rawValue)"
    }
    let center = CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2)
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) else {
        return "failed_\(action.rawValue)"
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return "clicked_via_pointer"
}

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

    let installLabels = ["Get", "Download", "Install", "Obter", "Baixar", "Instalar"]
    let isInstallTarget = installLabels.contains(where: { $0 == title || $0 == description || $0 == value })
    let isNamedTarget = [title, description, value].compactMap({ $0 }).contains(where: { $0 == clickTarget })
    let targetRoleMatches = role == (kAXButtonRole as String) ||
        (clickTarget == "Not Now" && role == (kAXStaticTextRole as String))
    if let clickTarget, !targetClicked, targetRoleMatches,
       (clickTarget == "INSTALL_ACTION" ? isInstallTarget : isNamedTarget) {
        let result = press(element)
        targetClicked = result.hasPrefix("clicked")
        print("UI_ACTION_\(clickTarget.uppercased().replacingOccurrences(of: "_ACTION", with: ""))=\(result)")
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
if let clickTarget, !targetClicked {
    print("UI_ACTION_\(clickTarget.uppercased())=button_not_found")
}
