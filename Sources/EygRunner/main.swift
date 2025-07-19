//
//  Sources/EygRunner/main.swift
//  Effect-only runner – no built-ins, easy to extend.
//

import EygInterpreter
import Foundation

// MARK: - Extrinsic side-effect handlers -------------------------------------

private let extrinsic: [String: @Sendable (Value) async throws -> Value] = [
    "print": { payload in
        let text = switch payload {
        case .string(let s): s
        default:              "\(payload)"
        }
        print(text, terminator: "")
        return .record([:])   // empty record = “done”
    },

    // Future handlers go below:
    // "log": { payload in … return … }
]

// MARK: - Runner -------------------------------------------------------------


struct Runner {
    static func main() async {
        guard let examplesDir = Bundle.module.url(forResource: "examples", withExtension: nil) else {
            fatalError("Resource folder ‘examples’ not found")
        }

        let files = (try? FileManager.default
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
                let expr   = try IRDecoder.decode(Data(contentsOf: file))
                let result = try await exec(expr, extrinsic: extrinsic)
                print("\(file.lastPathComponent) → \(result)")
            } catch {
                print("\(file.lastPathComponent) → ERROR: \(error)")
            }
        }

        print("\n---- Finished")
    }
}

await Runner.main()
