//  Sources/EygRunner/main.swift
//  Two-path loader:
//  1. hello.json  – uses the built-in “print” and runs immediately.
//  2. *-payload-side-effect.json – tries the effect wrapper; on failure
//     it is caught instead of crashing so we can fix it later.

import EygInterpreter
import Foundation

// --- Extrinsic handler (only used for effect-based I/O) --------------------
private let printHandler: @Sendable (Value) async throws -> Value = { message in
    switch message {
    case .string(let s):
        print(s, terminator: "")
    default:
        print(message, terminator: "")
    }
    return .record([:])
}

// --- Mapping for the *effect* path -----------------------------------------
private let extrinsic: [String: @Sendable (Value) async throws -> Value] = [
    "print": printHandler
]

struct Runner {
    static func main() async {               // ← no longer throws
        let bundle = Bundle.module
        guard let exampleDir = bundle.url(forResource: "examples", withExtension: nil) else {
            fatalError("Resource folder 'examples' not found")
        }

        let files = (try? FileManager.default
            .contentsOfDirectory(at: exampleDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let expr = try IRDecoder.decode(data)

                // ---------- CHOOSE PATH ------------------------------------------
                // 1. Files named *-payload-side-effect.json are **effect** programs
                if file.lastPathComponent.contains("-payload-side-effect") {
                    // TODO: handler body must be pure OR we need extrinsic support
                    let wrapper = Expr.shallowHandle(
                        label: "print",
                        handler: Expr.lambda(param: "_", body: .empty),
                        body: expr)
                    let result = try await exec(wrapper, extrinsic: ["print": printHandler])
                    print("\(file.lastPathComponent) →", result)
                } else {
                    // 2. All other files (hello.json) are assumed to use built-ins
                    let result = try await interpret(expr)
                    print("\(file.lastPathComponent) →", result)
                }
            } catch {
                // swallow every file-level error
                print("⚠️  Skipped \(file.lastPathComponent): \(error)")
            }
        }
    }
}

// Non-throwing top-level entry
struct Main {
    static func main() async {
        await Runner.main()
    }
}

// Entry point for the application
await Main.main()
