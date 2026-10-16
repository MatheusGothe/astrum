import AppKit
import ApplicationServices
import Foundation
import ImageIO
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

let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.AppStore").first
let root = app.map { AXUIElementCreateApplication($0.processIdentifier) }

func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Void) {
    visit(element)
    for child in children(element) { walk(child, visit) }
}

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--redact-fields" {
    let path = CommandLine.arguments[2]
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fputs("Could not load screenshot for redaction\n", stderr)
        exit(3)
    }
    let imageWidth = image.width
    let imageHeight = image.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
    let context = pixels.withUnsafeMutableBytes { bytes -> CGContext? in
        guard let base = bytes.baseAddress else { return nil }
        return CGContext(data: base, width: imageWidth, height: imageHeight, bitsPerComponent: 8,
                         bytesPerRow: imageWidth * 4, space: colorSpace,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    guard let context else {
        fputs("Could not create screenshot redaction context\n", stderr)
        exit(3)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    let ocr = VNRecognizeTextRequest()
    ocr.recognitionLevel = .accurate
    do {
        try VNImageRequestHandler(cgImage: image).perform([ocr])
    } catch {
        fputs("Could not inspect screenshot for sensitive text\n", stderr)
        exit(3)
    }
    for observation in ocr.results ?? [] {
        guard let recognized = observation.topCandidates(1).first?.string, recognized.contains("@") else { continue }
        let box = observation.boundingBox.insetBy(dx: -0.012, dy: -0.008)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: box.minX * CGFloat(imageWidth), y: box.minY * CGFloat(imageHeight),
                            width: box.width * CGFloat(imageWidth), height: box.height * CGFloat(imageHeight)))
    }
    guard let redactedImage = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fputs("Could not encode redacted screenshot\n", stderr)
        exit(3)
    }
    CGImageDestinationAddImage(destination, redactedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        fputs("Could not save redacted screenshot\n", stderr)
        exit(3)
    }
    let verify = VNRecognizeTextRequest()
    verify.recognitionLevel = .accurate
    do {
        guard let redactedSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let redacted = CGImageSourceCreateImageAtIndex(redactedSource, 0, nil) else { throw NSError(domain: "redaction", code: 4) }
        try VNImageRequestHandler(cgImage: redacted).perform([verify])
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

guard let app, let root else {
    fputs("App Store process not found\n", stderr)
    exit(2)
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
func verticalPosition(_ element: AXUIElement) -> CGFloat {
    guard let positionObject = getAttribute(element, kAXPositionAttribute as String) else { return -1 }
    var point = CGPoint.zero
    return AXValueGetValue(positionObject as! AXValue, .cgPoint, &point) ? point.y : -1
}
// The App Store search box is also an AXTextField. The credential field is in
// the centered sign-in sheet, lower on screen than the search box.
guard let input = fields.max(by: { verticalPosition($0) < verticalPosition($1) }) else {
    print("AUTH_RESULT=field_not_present; stage=\(mode == "--email" ? "email" : "password_or_2fa")")
    exit(4)
}

func click(_ point: CGPoint) -> Bool {
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else { return false }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    return true
}

func postUnicode(_ text: String) {
    let units = Array(text.utf16)
    for start in stride(from: 0, to: units.count, by: 16) {
        let chunk = Array(units[start..<min(start + 16, units.count)])
        chunk.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: base)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: base)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}

guard let positionObject = getAttribute(input, kAXPositionAttribute as String),
      let sizeObject = getAttribute(input, kAXSizeAttribute as String) else {
    print("AUTH_RESULT=field_position_unavailable")
    exit(5)
}
var fieldPoint = CGPoint.zero
var fieldSize = CGSize.zero
guard AXValueGetValue(positionObject as! AXValue, .cgPoint, &fieldPoint),
      AXValueGetValue(sizeObject as! AXValue, .cgSize, &fieldSize),
      click(CGPoint(x: fieldPoint.x + fieldSize.width / 2, y: fieldPoint.y + fieldSize.height / 2)) else {
    print("AUTH_RESULT=field_focus_failed")
    exit(5)
}
Thread.sleep(forTimeInterval: 0.3)
let selectAllDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)
selectAllDown?.flags = .maskCommand
selectAllDown?.post(tap: .cghidEventTap)
let selectAllUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: false)
selectAllUp?.flags = .maskCommand
selectAllUp?.post(tap: .cghidEventTap)
postUnicode(value)
Thread.sleep(forTimeInterval: 0.7)
let valueConfirmed = (getAttribute(input, kAXValueAttribute as String) as? String) == value
print("AUTH_FIELD_VALUE_CONFIRMED=\(valueConfirmed)")
if emailMode && !valueConfirmed {
    print("AUTH_RESULT=email_field_value_not_confirmed; refusing_to_submit")
    exit(7)
}
let preferred = mode == "--email" ? ["Continue", "Sign In", "Sign in", "Entrar"] : ["Sign In", "Sign in", "Entrar"]
func press(_ element: AXUIElement) -> Bool {
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
        let enabled = getAttribute(button, kAXEnabledAttribute as String) as? Bool
        if enabled == false { continue }
        if press(button) { clicked = true; break }
    }
}
guard clicked else {
    print("AUTH_RESULT=submit_button_not_found")
    exit(6)
}
print("AUTH_RESULT=\(mode == "--email" ? "email_submitted" : "password_submitted")")
