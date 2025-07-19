//  Sources/EygRunner/main.swift
//  Effect-driven two-path runner:
//  1. Built-in path (hello.json) – uses builtin "print".
//  2. Effect path (*-payload-side-effect.json) – handled by extrinsic map.

import EygInterpreter
import Foundation

// === Extrinsic effect handlers (platform-specific) ==========================
private let printHandler: @Sendable (Value) async throws -> Value = { payload in
    switch payload {
    case .string(let s):
        print(s, terminator: "")
    default:
        print(payload, terminator: "")
    }
    return .record([:])
}

// Map of *effect labels* → handler closures
private let extrinsic: [String: @Sendable (Value) async throws -> Value] = [
    "print": printHandler
]

// === Runner ================================================================
struct Runner {
    static func main() async {
        let bundle = Bundle.module
        guard let exampleDir = bundle.url(forResource: "examples", withExtension: nil) else {
            fatalError("Resource folder 'examples' not found")
        }

        let files =
            (try? FileManager.default
            .contentsOfDirectory(at: exampleDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let expr = try IRDecoder.decode(data)

                if file.lastPathComponent.contains("-payload-side-effect") {
                    // Effect path – use exec with extrinsic handlers
                    let result = try await exec(expr, extrinsic: extrinsic)
                    print("\(file.lastPathComponent) →", result)
                } else {
                    // Built-in path – use plain interpret
                    let result = try await interpret(expr)
                    print("\(file.lastPathComponent) →", result)
                }
            } catch {
                print("⚠️  Skipped \(file.lastPathComponent): \(error)")
            }
        }
    }
}

// === Entry point ===========================================================
struct Main {
    static func main() async {
        await Runner.main()
    }
}

await Main.main()
