# SwiftEygInterpreter 🏃‍♂️

> A **Swift 6.1** implementation of the **EYG** language interpreter — a complete port of the tiny JavaScript interpreter that powers [eyg.run](https://eyg.run/).

This is my Swift translation of the [JavaScript Interpreter for EYG](https://github.com/CrowdHailer/eyg-lang/blob/main/packages/javascript_interpreter/src/interpreter.mjs).

> **This is a passion project created purely for fun and learning purposes.**
> **NOT FOR PRODUCTION USE** — experimental, unfinished, and may be unpredictable.
> **USE AT YOUR OWN RISK** — no support, warranties, or stability promises.

For production-ready EYG interpreters, use the official implementations at [eyg.run](https://eyg.run/).

## 🚀 Quick Start

```bash
# Clone & run
git clone <this repo>
cd SwiftEygInterpreter
swift run EygRunner
# Expected output:
# string("Hello, Eyg!")
# hello.json → string("Hello, Eyg!")
```

## What is Built

A **Swift 6.1 port** of the EYG interpreter:

- **Same IR** → identical semantics to the JavaScript, Gleam, and Go implementations
- **Same builtins** → compatible effects & data types
- **Same guarantees** → never crashes, deterministic, managed effects
- **Native performance** → Swift’s compiled performance advantages

## Differences from the JavaScript implementation

| Topic | JavaScript | Swift |
|-------|------------|-------|
| **Concurrency** | Synchronous & single-threaded | Actor-based state management |
| **Error Handling** | Flags errors via a `break` property | Throws structured `UnhandledEffect` errors |
| **Effects & Continuations** | Uses a `Resume` class | Throws `UnhandledEffect` (some features *work-in-progress*) |
| **Built-ins** | Synchronous, state-tied | Async closures with defined arity |
| **Immutability** | Relies on the `immutable` library | uses Swift value types |

## 🧠 What is EYG?

EYG guarantees programs never crash by checking them ahead-of-time — no type annotations required.

| Feature | What it means |
|---------|---------------|
| **Predictable** | Deterministic programs; immutable dependencies; no hidden side-effects |
| **Useful** | Programs are independent of the machine they run on |
| **Confident** | Sound type system using row typing; validated ahead-of-time |
| **Tiny IR** | AST with ~20 node types; easy to re-implement (as this Swift port proves) |
| **Algebraic Effects** | Extensible Records, Unions, and Algebraic Effects |

## 🔧 Key Technical Features

### Row Typing
EYG’s type system uses **row typing** — a proven mathematical foundation providing structural typing with extensibility guarantees.

### Algebraic Effects
Serialize program states when an effect is raised → seamless upgrades & crash-free execution. Use `perform` to declare effects and `handle` to manage them.

### Structural Editor Integration
Treats code as a structured tree (not flat text) → more reliable program manipulation.

## 📁 Project Structure

```
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

let interpreter = EygInterpreter()
let result = interpreter.execute(program)
```

## 🔌 Extending the Interpreter

### Adding New Effects

1. Register a new entry in `builtinTable`
2. Provide a handler implementation
3. Use `perform`/`handle` in your EYG programs

**Example — adding a `File.Read` effect:**

```swift
// In your builtin table
"File.Read": { path in
    try String(contentsOfFile: path)
}
```

> This is a personal project! While I’m not actively seeking contributions, feel free to:
> 1. Check the official EYG implementations for serious work
> 2. Fork and experiment
> 3. Remember — this is just for fun, no pressure!

## 📚 Resources

- **Language Website**: [eyg.run](https://eyg.run/) (the real thing!)
- **Original Implementation**: [eyg-lang](https://github.com/CrowdHailer/eyg-lang)
- **Specification**: Available at [eyg.run](https://eyg.run/)

## 📄 License

Licensed under the [GNU General Public License v3.0](LICENSE).

---

> **This is a fun hobby project exploring language implementation!** 🎉
> While the EYG ecosystem offers serious tools for safe, predictable programming, this Swift interpreter is just for entertainment and learning.
> For production-ready tools, check out the official implementations at [eyg.run](https://eyg.run/).
> **Happy coding!** 🚀
