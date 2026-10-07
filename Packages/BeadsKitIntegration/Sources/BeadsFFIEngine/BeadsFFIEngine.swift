// The same door the app uses (Beadster/Engine/BeadsBridge + FFIEngine), for the tests.
import BeadsFFI
import BeadsKit
import Foundation

public struct BeadsFFIEngine: BeadsEngine {
    public init() {}
    public func call(_ request: Data) -> Data {
        let text = String(decoding: request, as: UTF8.self)
        guard let out = text.withCString({ BeadsCall(UnsafeMutablePointer(mutating: $0)) }) else { return Data() }
        defer { BeadsFree(out) }
        return Data(String(cString: out).utf8)
    }
}
