import EygInterpreter
import Foundation

struct Runner {
    static func main() async throws {
        // Locate the examples folder inside the built bundle
        let bundle = Bundle.module
        guard let exampleDir = bundle.url(forResource: "examples", withExtension: nil) else {
            fatalError("Resource folder 'examples' not found")
        }

        let files = try FileManager.default
            .contentsOfDirectory(at: exampleDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else { fatalError("No .json files in \(exampleDir.path)") }

        for file in files {
            let data = try Data(contentsOf: file)
            let expr = try IRDecoder.decode(data)

            let result = try await interpret(expr)
            // clean string output
            switch result {
            case .string(let s): print("\(file.lastPathComponent) →", s)
            case .int(let i): print("\(file.lastPathComponent) →", i)
            default: print("\(file.lastPathComponent) →", result)
            }
        }
    }
}

try! await Runner.main()
