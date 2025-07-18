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

        // example implementation of converting JSON to Expr for hello world example only
        func toExpr(_ any: Any) -> Expr {
            guard let dict = any as? [String: Any] else { fatalError() }
            switch dict["0"] as? String {
            case "a": return .apply(fn: toExpr(dict["f"]!), arg: toExpr(dict["a"]!))
            case "s": return .string(dict["v"]! as! String)
            case "i": return .int(dict["v"]! as! Int)
            case "b": return .builtin(dict["l"]! as! String)
            case "c": return .cons
            case "u": return .empty
            default: fatalError("Unsupported IR node")
            }
        }

        for file in files {
            let data = try Data(contentsOf: file)
            let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let expr = toExpr(raw)

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
