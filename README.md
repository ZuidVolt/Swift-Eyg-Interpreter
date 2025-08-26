# Swift-Eyg-Interpreter

A **Swift** implementation of the **EYG** language interpreter

This interpreter is based on the [JavaScript Interpreter for EYG](https://github.com/CrowdHailer/eyg-lang/blob/main/packages/javascript_interpreter/src/interpreter.mjs).

> **This is a passion project created purely for fun and learning purposes.**
> **NOT FOR PRODUCTION USE** — experimental, unfinished, and may be unpredictable.
> **USE AT YOUR OWN RISK** — no support, warranties, or stability promises.

For production-ready EYG interpreters, use the official implementations at [eyg.run](https://eyg.run/).

## Quick Start

```bash
# Clone & run
git clone https://github.com/ZuidVolt/Swift-Eyg-Interpreter.git
cd SwiftEygInterpreter
swift run EygRunner
# Expected output:
# Decoded: apply(fn: EygInterpreter.Expr.perform("print"), arg: EygInterpreter.Expr.string("Hello, Eyg!"))
# Hello, Eyg!
# Raw result: record([:])
# hello.json → record([:])
```

## Differences from the JavaScript implementation

| Topic | JavaScript | Swift |
|-------|------------|-------|
| **Concurrency** | Synchronous & single-threaded | Async actor-based state management |
| **Error Handling** | Sets a break property on state | Throws structured `UnhandledEffect` errors |
| **Effects & Continuations** | Uses `Resume` for internal handlers, sets break for extrinsic effects | Uses `Resume` for internal handlers, throws `UnhandledEffect` for extrinsic effects |
| **Built-ins** | Synchronous functions tied to state | Async closures with defined arity |
| **Immutability** | Uses `immutable` library | Uses Swift value types and custom immutable `Stack` |

## What is EYG?

EYG guarantees programs never crash by checking them ahead-of-time — no type annotations required.

| Feature | What it means |
|---------|---------------|
| **Predictable** | Deterministic programs; immutable dependencies; no hidden side-effects |
| **Useful** | Programs are independent of the machine they run on |
| **Confident** | Sound type system using row typing; validated ahead-of-time |
| **Tiny IR** | AST with ~20 node types; easy to re-implement (as this Swift port proves) |
| **Algebraic Effects** | Extensible Records, Unions, and Algebraic Effects |

## Key Technical Features

### Row Typing

EYG’s type system uses **row typing** — a proven mathematical foundation providing structural typing with extensibility guarantees.

### Algebraic Effects

Serialize program states when an effect is raised → seamless upgrades & crash-free execution. Use `perform` to declare effects and `handle` to manage them.

### Structural Editor Integration

Treats code as a structured tree (not flat text) → more reliable program manipulation.

## Project Structure

```txt
SwiftEygInterpreter/
├── Package.swift                 # Swift Package Manager config
├── Sources/
│   ├── EygInterpreter/          # Core interpreter library
│   └── EygRunner/               # Executable runner
│       └── examples/            # Sample EYG programs
└── README.md
```

## 📖 Usage Examples


### Embedding in Applications

```swift
import EygInterpreter

// Provide your own effect handlers
let extrinsic: [String: @Sendable (Value) async throws -> Value] = [
    "print": { payload in
        let text: String
        switch payload {
        case .string(let s): text = s
        default: text = "\(payload)"
        }
        print(text)
        return .record([:])
    }
]

// Decode and run a program
let expr = try IRDecoder.decode(programData)
let result = try await exec(expr, extrinsic: extrinsic)
```

## Resources

- **Language Website**: [eyg.run](https://eyg.run/) (the real thing!)
- **EYG Source**: [eyg-lang](https://github.com/CrowdHailer/eyg-lang)
- **Specification**: Available at [eyg spec](https://github.com/CrowdHailer/eyg-lang/tree/main/spec)

## License

Licensed under the [GNU General Public License v3.0](LICENSE).

---
