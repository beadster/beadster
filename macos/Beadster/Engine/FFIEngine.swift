// BeadsKit's engine in the app: beads' Go code through BeadsBridge.
import BeadsKit
import Foundation

struct FFIEngine: BeadsEngine {
    func call(_ request: Data) -> Data {
        Data(BeadsBridge.call(String(decoding: request, as: UTF8.self)).utf8)
    }
}
