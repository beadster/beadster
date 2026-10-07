// The one door to beads' Go code (BeadsFFI): JSON in, JSON out, the C string freed here.
// BeadsKit (K1-K4) builds typed calls on top of it.
import BeadsFFI

enum BeadsBridge {
    static func call(_ request: String) -> String {
        guard let out = request.withCString({ BeadsCall(UnsafeMutablePointer(mutating: $0)) }) else {
            return #"{"error":{"code":"beads","message":"BeadsCall returned nothing"}}"#
        }
        defer { BeadsFree(out) }
        return String(cString: out)
    }
}
