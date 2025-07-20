//
//  Sources/EygRunner/main.swift
//  Effect-only runner – no built-ins, easy to extend.
//

import EygInterpreter
import Foundation

// MARK: - Extrinsic side-effect handlers -------------------------------------

private let extrinsic: [String: @Sendable (Value) async throws -> Value] = [
    "print": { payload in
        let text: String
        switch payload {
        case .string(let s): text = s
        default: text = "\(payload)"
        }
        print(text)
        return .record([:])
    },
    "Log": { payload in
        guard let printHandler = extrinsic["print"] else {
            throw UnhandledEffect.create(label: "MissingPrintHandler", payload: payload)
        }
        return try await printHandler(payload)
    }
]

// MARK: - Runner -------------------------------------------------------------

struct Runner {
    static func main() async {
        guard let examplesDir = Bundle.module.url(forResource: "examples", withExtension: nil) else {
            fatalError("Resource folder ‘examples’ not found")
        }

        let files =
            (try? FileManager.default
            .contentsOfDirectory(at: examplesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        if files.isEmpty {
            print("---- No JSON examples found")
            return
        }

        print("---- Running \(files.count) example(s) via extrinsic handlers\n")

        for file in files {
            do {
                let expr = try IRDecoder.decode(Data(contentsOf: file))
                print("Decoded: \(expr)")

                let result = try await exec(expr, extrinsic: extrinsic)
                print("Raw result: \(result)")
                print("\(file.lastPathComponent) → \(result)")
            } catch {
                print("\(file.lastPathComponent) → ERROR: \(error)")
            }
        }

        print("\n---- Finished")
    }
}

await Runner.main()
