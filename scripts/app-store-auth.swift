import AppKit
import ApplicationServices
import Foundation
import Vision

func getAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func role(_ element: AXUIElement) -> String {
    (getAttribute(element, kAXRoleAttribute as String) as? String) ?? ""
}

func subrole(_ element: AXUIElement) -> String {
    (getAttribute(element, kAXSubroleAttribute as String) as? String) ?? ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (getAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.AppStore").first else {
    fputs("App Store process not found\n", stderr)
    exit(2)
}
let root = AXUIElementCreateApplication(app.processIdentifier)

func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Void) {
    visit(element)
    for child in children(element) { walk(child, visit) }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--redact-fields" {
    let path = CommandLine.arguments[2]
    guard let image = NSImage(contentsOfFile: path),
          let bitmap = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Could not load screenshot for redaction\n", stderr)
        exit(3)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let imageWidth = CGFloat(bitmap.pixelsWide)
    let imageHeight = CGFloat(bitmap.pixelsHigh)
    let ocr = VNRecognizeTextRequest()
    ocr.recognitionLevel = .accurate
    do {
        try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([ocr])
    } catch {
        fputs("Could not inspect screenshot for sensitive text\n", stderr)
        exit(3)
    }
    for observation in ocr.results ?? [] {
        guard let recognized = observation.topCandidates(1).first?.string, recognized.contains("@") else { continue }
        let box = observation.boundingBox.insetBy(dx: -0.012, dy: -0.008)
        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: box.minX * imageWidth, y: box.minY * imageHeight,
                                  width: box.width * imageWidth, height: box.height * imageHeight)).fill()
    }
    walk(root) { element in
        let elementRole = role(element)
        let label = [
            getAttribute(element, kAXTitleAttribute as String) as? String,
            getAttribute(element, kAXDescriptionAttribute as String) as? String,
            getAttribute(element, kAXValueAttribute as String) as? String,
        ].compactMap { $0 }.joined(separator: " ")
        let isInput = elementRole == (kAXTextFieldRole as String) || elementRole == "AXSecureTextField"
        guard isInput || label.contains("@") else { return }
        guard let positionObject = getAttribute(element, kAXPositionAttribute as String),
              let sizeObject = getAttribute(element, kAXSizeAttribute as String) else { return }
        let positionValue = positionObject as! AXValue
        let sizeValue = sizeObject as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &point), AXValueGetValue(sizeValue, .cgSize, &size) else { return }
        NSColor.black.setFill()
        // Also cover accessible input frames; OCR masking above independently catches visible email text.
        NSBezierPath(rect: NSRect(x: point.x, y: imageHeight - point.y - size.height, width: size.width, height: size.height)).fill()
    }
    do {
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
        fputs("Could not save redacted screenshot\n", stderr)
        exit(3)
    }
    NSGraphicsContext.restoreGraphicsState()
    let verify = VNRecognizeTextRequest()
    verify.recognitionLevel = .accurate
    do {
        try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([verify])
    } catch {
        fputs("Could not verify screenshot redaction\n", stderr)
        exit(4)
    }
    if (verify.results ?? []).contains(where: { $0.topCandidates(1).first?.string.contains("@") == true }) {
        fputs("Sensitive text remains visible; refusing screenshot artifact\n", stderr)
        exit(5)
    }
    print("SCREENSHOT_FIELDS_REDACTED=true")
    exit(0)
}

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: app-store-auth.swift --email|--password\n", stderr)
    exit(2)
}
let mode = CommandLine.arguments[1]
let environmentKey = mode == "--email" ? "APP_STORE_APPLE_ID" : "APP_STORE_APPLE_PASSWORD"
let emailMode = mode == "--email"
guard (mode == "--email" || mode == "--password"),
      let value = ProcessInfo.processInfo.environment[environmentKey], !value.isEmpty else {
    fputs("Required App Store credential is missing\n", stderr)
    exit(2)
}

var fields: [AXUIElement] = []
var buttons: [AXUIElement] = []
walk(root) { element in
    let isTextField = role(element) == (kAXTextFieldRole as String)
    let isSecure = subrole(element) == "AXSecureTextField"
    if isTextField && (emailMode ? !isSecure : isSecure) { fields.append(element) }
    if role(element) == (kAXButtonRole as String) { buttons.append(element) }
}
func width(_ element: AXUIElement) -> CGFloat {
    guard let sizeObject = getAttribute(element, kAXSizeAttribute as String) else { return 0 }
    var size = CGSize.zero
    return AXValueGetValue(sizeObject as! AXValue, .cgSize, &size) ? size.width : 0
}
guard let input = fields.max(by: { width($0) < width($1) }) else {
    print("AUTH_RESULT=field_not_present; stage=\(mode == "--email" ? "email" : "password_or_2fa")")
    exit(4)
}
let setResult = AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, value as CFTypeRef)
guard setResult == .success else {
    print("AUTH_RESULT=field_set_failed; code=\(setResult.rawValue)")
    exit(5)
}
let preferred = mode == "--email" ? ["Continue", "Sign In", "Sign in", "Entrar"] : ["Sign In", "Sign in", "Entrar"]
func press(_ element: AXUIElement) -> Bool {
    if AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
    guard let positionObject = getAttribute(element, kAXPositionAttribute as String),
          let sizeObject = getAttribute(element, kAXSizeAttribute as String) else { return false }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionObject as! AXValue, .cgPoint, &point),
          AXValueGetValue(sizeObject as! AXValue, .cgSize, &size),
          let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                             mouseCursorPosition: CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2), mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                           mouseCursorPosition: CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2), mouseButton: .left) else { return false }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
}
var clicked = false
for name in preferred where !clicked {
    for button in buttons where (getAttribute(button, kAXTitleAttribute as String) as? String) == name {
        if press(button) { clicked = true; break }
    }
}
guard clicked else {
    print("AUTH_RESULT=submit_button_not_found")
    exit(6)
}
print("AUTH_RESULT=\(mode == "--email" ? "email_submitted" : "password_submitted")")
