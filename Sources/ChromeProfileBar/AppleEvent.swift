import Foundation

/// "core" -> 'core'
func fourCC(_ s: String) -> FourCharCode {
    s.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
}

struct AppleEventError: Error, CustomStringConvertible {
    let code: Int
    var description: String { "Apple Event error \(code)" }
}

/// Minimal raw Apple Events sent to one process by pid, so another app with the same
/// bundle ID (e.g. an automation Chrome) is never targeted. Avoids OSAKit/JavaScriptCore.
struct AppleEventTarget {
    let pid: pid_t

    // MARK: Object specifiers

    static func specifier(want: String, form: String, data: NSAppleEventDescriptor,
                          from container: NSAppleEventDescriptor = .null()) -> NSAppleEventDescriptor {
        let spec = NSAppleEventDescriptor.record()
        spec.setDescriptor(NSAppleEventDescriptor(typeCode: fourCC(want)), forKeyword: fourCC("want"))
        spec.setDescriptor(NSAppleEventDescriptor(enumCode: fourCC(form)), forKeyword: fourCC("form"))
        spec.setDescriptor(data, forKeyword: fourCC("seld"))
        spec.setDescriptor(container, forKeyword: fourCC("from"))
        return spec.coerce(toDescriptorType: fourCC("obj "))!
    }

    static func property(_ code: String, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: "prop", form: "prop", data: NSAppleEventDescriptor(typeCode: fourCC(code)), from: container)
    }

    static func every(_ cls: String) -> NSAppleEventDescriptor {
        var all = fourCC("all ")
        let ordinal = NSAppleEventDescriptor(descriptorType: fourCC("abso"), bytes: &all, length: 4)!
        return specifier(want: cls, form: "indx", data: ordinal)
    }

    static func element(_ cls: String, index: Int) -> NSAppleEventDescriptor {
        specifier(want: cls, form: "indx", data: NSAppleEventDescriptor(int32: Int32(index)))
    }

    static func element(_ cls: String, id: String) -> NSAppleEventDescriptor {
        specifier(want: cls, form: "ID  ", data: NSAppleEventDescriptor(string: id))
    }

    // MARK: Commands

    @discardableResult
    func send(_ eventClass: String, _ eventID: String,
              _ params: [String: NSAppleEventDescriptor] = [:]) throws -> NSAppleEventDescriptor? {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: fourCC(eventClass), eventID: fourCC(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: -1, transactionID: 0)  // kAutoGenerateReturnID, kAnyTransactionID
        for (key, value) in params { event.setParam(value, forKeyword: fourCC(key)) }
        let reply = try event.sendEvent(options: [.waitForReply], timeout: 3)
        if let err = reply.paramDescriptor(forKeyword: fourCC("errn")), err.int32Value != 0 {
            throw AppleEventError(code: Int(err.int32Value))
        }
        return reply.paramDescriptor(forKeyword: fourCC("----"))
    }

    func get(_ spec: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor? {
        try send("core", "getd", ["----": spec])
    }

    func set(_ spec: NSAppleEventDescriptor, to value: NSAppleEventDescriptor) throws {
        try send("core", "setd", ["----": spec, "data": value])
    }

    func activate() throws {
        try send("misc", "actv")
    }
}

extension NSAppleEventDescriptor {
    /// Items of a list reply as strings ("" for missing values).
    var strings: [String] {
        guard numberOfItems > 0 else { return [] }
        return (1...numberOfItems).map { atIndex($0)?.stringValue ?? "" }
    }
}
