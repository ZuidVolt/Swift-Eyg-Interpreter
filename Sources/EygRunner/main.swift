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
        do {
            let inputData = FileHandle.standardInput.readDataToEndOfFile()
            let source = try IRDecoder.decode(inputData)
            // print("Decoded: \(source)")
            let result = try await exec(source, extrinsic: extrinsic)
            print("\(result)")
        } catch {
            print("ERROR: \(error)")
        }
    }
}

await Runner.main()
