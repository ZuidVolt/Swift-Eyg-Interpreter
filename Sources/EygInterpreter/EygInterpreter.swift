//  EygInterpreter.swift
//  Created by mechanical translation of JS source

import Foundation

// MARK: – AST -----------------------------------------------------------------

/// Discriminated union for the surface syntax (full IR).
public indirect enum Expr: Sendable, Codable {
    case variable(String)                    // "v"
    case lambda(param: String, body: Expr)   // "f"
    case apply(fn: Expr, arg: Expr)          // "a"
    case `let`(name: String, value: Expr, then: Expr) // "l"
    case vacant                              // "z"

    case binary(String)                      // "x"
    case int(Int)                            // "i"
    case string(String)                      // "s"

    case tail                                // "ta"
    case cons                                // "c"
    case empty                               // "u"

    case extend(String)                      // "e"
    case select(String)                      // "g"
    case overwrite(String)                   // "o"

    case tag(String)                         // "t"
    case `case`(tag: String)                 // "m"
    case noCases                             // "n"

    case perform(String)                     // "p"
    case handle(label: String, handler: Expr, body: Expr) // "h"
    case builtin(String)                     // "b"

    case resume(continuation: Resume)        // internal continuation literal

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case type = "0"
        case label = "l"
        case value = "v"
        case body  = "b"
        case function = "f"
        case argument = "a"
        case name = "l_name"
        case then = "t"
        case comment = "c"
        case tag = "l_tag"
        case cid = "l_cid"
        case project = "p"
        case release = "r"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(String.self, forKey: .type)

        switch t {
        case "v": self = .variable(try c.decode(String.self, forKey: .label))
        case "f":
            let p = try c.decode(String.self, forKey: .label)
            let b = try c.decode(Expr.self, forKey: .body)
            self = .lambda(param: p, body: b)
        case "a":
            let fn = try c.decode(Expr.self, forKey: .function)
            let arg = try c.decode(Expr.self, forKey: .argument)
            self = .apply(fn: fn, arg: arg)
        case "l":
            let n = try c.decode(String.self, forKey: .name)
            let v = try c.decode(Expr.self, forKey: .value)
            let t = try c.decode(Expr.self, forKey: .then)
            self = .let(name: n, value: v, then: t)
        case "x": self = .binary(try c.decode(String.self, forKey: .value))
        case "i": self = .int(try c.decode(Int.self, forKey: .value))
        case "s": self = .string(try c.decode(String.self, forKey: .value))
        case "ta": self = .tail
        case "c":  self = .cons
        case "u":  self = .empty
        case "z":  _ = try c.decode(String.self, forKey: .comment); self = .vacant
        case "e": self = .extend(try c.decode(String.self, forKey: .label))
        case "g": self = .select(try c.decode(String.self, forKey: .label))
        case "o": self = .overwrite(try c.decode(String.self, forKey: .label))
        case "t": self = .tag(try c.decode(String.self, forKey: .label))
        case "m": self = .case(tag: try c.decode(String.self, forKey: .tag))
        case "n": self = .noCases
        case "p": self = .perform(try c.decode(String.self, forKey: .label))
        case "h":
            let l = try c.decode(String.self, forKey: .label)
            let h = try c.decode(Expr.self, forKey: .body)
            let b = try c.decode(Expr.self, forKey: .body)
            self = .handle(label: l, handler: h, body: b)
        case "b": self = .builtin(try c.decode(String.self, forKey: .label))
        case "#": _ = try c.decode(String.self, forKey: .cid); self = .builtin("CID_STUB")
        case "resume": self = .resume(continuation: try c.decode(Resume.self, forKey: .body))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown IR type '\(t)'"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .variable(l): try c.encode("v", forKey: .type); try c.encode(l, forKey: .label)
        case let .lambda(p,b):
            try c.encode("f", forKey: .type)
            try c.encode(p, forKey: .label)
            try c.encode(b, forKey: .body)
        case let .apply(fn,arg):
            try c.encode("a", forKey: .type)
            try c.encode(fn, forKey: .function)
            try c.encode(arg, forKey: .argument)
        case let .let(n,v,t):
            try c.encode("l", forKey: .type)
            try c.encode(n, forKey: .name)
            try c.encode(v, forKey: .value)
            try c.encode(t, forKey: .then)
        case let .binary(v): try c.encode("x", forKey: .type); try c.encode(v, forKey: .value)
        case let .int(v):    try c.encode("i", forKey: .type); try c.encode(v, forKey: .value)
        case let .string(v): try c.encode("s", forKey: .type); try c.encode(v, forKey: .value)
        case .tail: try c.encode("ta", forKey: .type)
        case .cons: try c.encode("c",  forKey: .type)
        case .empty: try c.encode("u", forKey: .type)
        case .vacant: try c.encode("z", forKey: .type); try c.encode("", forKey: .comment)
        case let .extend(l): try c.encode("e", forKey: .type); try c.encode(l, forKey: .label)
        case let .select(l): try c.encode("g", forKey: .type); try c.encode(l, forKey: .label)
        case let .overwrite(l): try c.encode("o", forKey: .type); try c.encode(l, forKey: .label)
        case let .tag(l): try c.encode("t", forKey: .type); try c.encode(l, forKey: .label)
        case let .case(t): try c.encode("m", forKey: .type); try c.encode(t, forKey: .tag)
        case .noCases: try c.encode("n", forKey: .type)
        case let .perform(l): try c.encode("p", forKey: .type); try c.encode(l, forKey: .label)
        case let .handle(l,h,b):
            try c.encode("h", forKey: .type)
            try c.encode(l, forKey: .label)
            try c.encode(h, forKey: .body)
            try c.encode(b, forKey: .body)
        case let .builtin(i): try c.encode("b", forKey: .type); try c.encode(i, forKey: .label)
        case let .resume(r): try c.encode("resume", forKey: .type); try c.encode(r, forKey: .body)
        }
    }
}

// MARK: – Resume & Codable helpers --------------------------------------------

public struct Resume: Sendable, Codable {
    let frames: Stack<Cont>
    /// Resume the captured continuation with a payload.
    public func invoke(_ payload: Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let sm = StateMachine(src: .variable("_"))
                await sm.setValue(payload)
                await sm.setStack(frames)
                await sm.setIsValue(true)
                while true {
                    try await sm.step()
                    let (isVal, empty, val) = await (sm.isValue, sm.stack.isEmpty, sm.value)
                    if isVal, empty { continuation.resume(returning: val!); return }
                }
            }
        }
    }
}

// MARK: – Runtime stack -------------------------------------------------------

public typealias Env = [String: Value]

/// A single continuation frame.
public enum Cont: Sendable, Codable {
    case assign(name: String, then: Expr, env: Env)
    case arg(Expr, Env)
    case apply(Value)
    case call(Value)
    case delimit(label: String, handler: Value)
}

/// Immutable stack used for continuations and partial applications.
public struct Stack<Element: Sendable>: Sendable, Codable
where Element: Codable {
    private indirect enum Link: Sendable, Codable { case empty; case node(Element, Link) }
    private let root: Link
    private init(_ root: Link) { self.root = root }
    public init() { self.init(.empty) }
    public static var empty: Stack { .init() }
    public var isEmpty: Bool { if case .empty = root { true } else { false } }
    public var peek: Element? { if case let .node(v, _) = root { v } else { nil } }
    public func push(_ e: Element) -> Stack { Stack(.node(e, root)) }
    public func pop() -> Stack { if case let .node(_, n) = root { Stack(n) } else { self } }
    public func reversed() -> [Element] {
        var out: [Element] = []
        var cur = root
        while case let .node(v, next) = cur { out.append(v); cur = next }
        return out
    }
}

// MARK: – Value (runtime) -----------------------------------------------------

public indirect enum Value: Sendable {
    case int(Int)
    case string(String)
    case closure(param: String, body: Expr, env: Env)
    case partial(arity: Int, applied: Stack<Value>, impl: Builtin)
    case tagged(tag: String, inner: Value)
    case record([String: Value])
    case empty
    case tail
    case resume(Resume)
}

// MARK: – Value Codable (only the parts we can encode)
extension Value: Codable {
    private enum CodingKeys: String, CodingKey {
        case int, string, closure, tagged, record, empty, tail
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch c.allKeys.first {
        case .int:    self = .int(try c.decode(Int.self, forKey: .int))
        case .string: self = .string(try c.decode(String.self, forKey: .string))
        case .closure:
            var n = try c.nestedUnkeyedContainer(forKey: .closure)
            let p = try n.decode(String.self)
            let b = try n.decode(Expr.self)
            let e = try n.decode(Env.self)
            self = .closure(param: p, body: b, env: e)
        case .tagged:
            var n = try c.nestedUnkeyedContainer(forKey: .tagged)
            let tag = try n.decode(String.self)
            let inner = try n.decode(Value.self)
            self = .tagged(tag: tag, inner: inner)
        case .record: self = .record(try c.decode([String: Value].self, forKey: .record))
        case .empty:  self = .empty
        case .tail:   self = .tail
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Value contains non-codable Builtin/Resume"))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .int(i):      try c.encode(i, forKey: .int)
        case let .string(s):   try c.encode(s, forKey: .string)
        case let .closure(p,b,e):
            var n = c.nestedUnkeyedContainer(forKey: .closure)
            try n.encode(p); try n.encode(b); try n.encode(e)
        case let .tagged(t,i):
            var n = c.nestedUnkeyedContainer(forKey: .tagged)
            try n.encode(t); try n.encode(i)
        case let .record(r):   try c.encode(r, forKey: .record)
        case .empty:           try c.encode(true, forKey: .empty)
        case .tail:            try c.encode(true, forKey: .tail)
        default: break // partial & resume skipped for now
        }
    }
}

// MARK: – Interpreter --------------------------------------------------------

/// Thrown when evaluation reaches an effect that is not handled.
public struct UnhandledEffect: Error, Sendable {
    let label: String
    let payload: Value
}

/// All built-ins are just Swift closures.
public typealias Builtin = @Sendable (inout StateMachine, [Value]) async throws -> Void

/// Mutable interpreter state isolated in an actor.
public actor StateMachine {
    var value: Value?
    var env: Env = [:]
    var stack: Stack<Cont> = .empty
    var control: Expr
    var isValue: Bool = false

    init(src: Expr) { control = src }

    // MARK: helpers
    public func setValue(_ v: Value) { value = v; isValue = true }
    fileprivate func setStack(_ s: Stack<Cont>) { stack = s }
    fileprivate func setIsValue(_ b: Bool) { isValue = b }
    func setExpression(_ e: Expr) { control = e; isValue = false }
    func lookup(_ name: String) throws -> Value {
        guard let v = env[name] else { throw UnhandledEffect(label: "UndefinedVariable", payload: .string(name)) }
        return v
    }
    func push(_ k: Cont) { stack = stack.push(k) }

    // MARK: step
    func step() async throws {
        if isValue { try await apply() } else { try await eval() }
    }
    private func applyBuiltin(_ impl: Builtin, _ args: [Value]) async throws {
        var myself = self
        try await impl(&myself, args)
        value = await myself.value
        env = await myself.env
        stack = await myself.stack
        control = await myself.control
        isValue = await myself.isValue
    }

    // MARK: eval
    private func eval() async throws {
        switch control {
        case .variable(let name): setValue(try lookup(name))
        case let .lambda(p, b): setValue(.closure(param: p, body: b, env: env))
        case let .apply(fn, arg): push(.arg(arg, env)); setExpression(fn)
        case let .let(name, val, then): push(.assign(name: name, then: then, env: env)); setExpression(val)
        case .vacant: throw UnhandledEffect(label: "NotImplemented", payload: .empty)
        case .binary(let bits): setValue(.string(bits))
        case .int(let bits): setValue(.int(bits))
        case .string(let bits): setValue(.string(bits))
        case .tail: setValue(.tail)
        case .cons: setValue(.partial(arity: 2, applied: .empty, impl: consBuiltin))
        case .empty: setValue(.empty)
        case let .extend(label): setValue(.partial(arity: 2, applied: .empty, impl: extendBuiltin(label: label)))
        case let .select(label): setValue(.partial(arity: 1, applied: .empty, impl: selectBuiltin(label: label)))
        case let .overwrite(label): setValue(.partial(arity: 2, applied: .empty, impl: overwriteBuiltin(label: label)))
        case let .tag(label): setValue(.partial(arity: 1, applied: .empty, impl: tagBuiltin(label: label)))
        case let .case(tag): setValue(.partial(arity: 3, applied: .empty, impl: caseBuiltin(tag: tag)))
        case .noCases: setValue(.partial(arity: 1, applied: .empty, impl: noCasesBuiltin))
        case let .perform(label): setValue(.partial(arity: 1, applied: .empty, impl: performBuiltin(label: label)))
        case let .handle(label, _, body): push(.delimit(label: label, handler: try await interpret(body))); setValue(.closure(param: "_", body: body, env: env))
        case .builtin(let id):
            guard let entry = builtinTable[id] else { throw UnhandledEffect(label: "UndefinedBuiltin", payload: .string(id)) }
            setValue(.partial(arity: entry.arity, applied: .empty, impl: entry.fn))
        case let .resume(cont): setValue(.resume(cont))
        }
    }

    // MARK: apply
    private func apply() async throws {
        guard let v = value else { return }
        guard let k = stack.peek else { return }
        stack = stack.pop()
        switch k {
        case let .assign(name, then, savedEnv):
            env = savedEnv; env[name] = v; setExpression(then)
        case let .arg(expr, savedEnv):
            push(.apply(v)); env = savedEnv; setExpression(expr)
        case let .apply(fnVal): try await call(fn: fnVal, arg: v)
        case let .call(argVal): try await call(fn: v, arg: argVal)
        case .delimit: break
        }
    }

    // MARK: call
    func call(fn: Value, arg: Value) async throws {
        switch fn {
        case let .closure(p, b, savedEnv):
            env = savedEnv; env[p] = arg; setExpression(b)
        case let .partial(arity, applied, impl):
            let newApplied = applied.push(arg)
            if newApplied.reversed().count == arity {
                try await applyBuiltin(impl, newApplied.reversed())
            } else {
                setValue(.partial(arity: arity, applied: newApplied, impl: impl))
            }
        case let .tagged(tag: "Resume", inner):
            guard case let .record(r) = inner, r["k"] != nil else { fatalError() }
            setValue(arg)
        default:
            throw UnhandledEffect(label: "NotAFunction", payload: fn)
        }
    }
}

// MARK: – Public entry point --------------------------------------------------

public func interpret(_ e: Expr) async throws -> Value {
    let sm = StateMachine(src: e)
    while true {
        try await sm.step()
        let (isVal, empty, val) = await (sm.isValue, sm.stack.isEmpty, sm.value)
        if isVal && empty { return val! }
    }
}

// MARK: – Built-ins -----------------------------------------------------------

private let consBuiltin: Builtin = { state, args in
    guard case var .record(r) = args[1] else { fatalError() }
    r["head"] = args[0]
    await state.setValue(.record(r))
}

private func extendBuiltin(label: String) -> Builtin {
    return { state, args in
        guard case var .record(r) = args[1] else { fatalError() }
        r[label] = args[0]
        await state.setValue(.record(r))
    }
}

private func selectBuiltin(label: String) -> Builtin {
    return { state, args in
        guard case let .record(r) = args[0], let v = r[label] else {
            throw UnhandledEffect(label: "MissingLabel", payload: .string(label))
        }
        await state.setValue(v)
    }
}

private func overwriteBuiltin(label: String) -> Builtin {
    return { state, args in
        guard case var .record(r) = args[1] else { fatalError() }
        r[label] = args[0]
        await state.setValue(.record(r))
    }
}

private func tagBuiltin(label: String) -> Builtin {
    return { state, args in await state.setValue(.tagged(tag: label, inner: args[0])) }
}

private func caseBuiltin(tag: String) -> Builtin {
    return { state, args in
        let branch = args[0], otherwise = args[1], value = args[2]
        guard case let .tagged(t, inner) = value else {
            throw UnhandledEffect(label: "NotTagged", payload: value)
        }
        try await (t == tag ? state.call(fn: branch, arg: inner) : state.call(fn: otherwise, arg: value))
    }
}

private let noCasesBuiltin: Builtin = { _, args in
    print(args[0])
    throw UnhandledEffect(label: "NoCasesMatched", payload: args[0])
}

private func performBuiltin(label: String) -> Builtin {
    return { state, args in
        let payload = args[0]
        var stackCopy = await state.stack
        while !stackCopy.isEmpty {
            let k = stackCopy.peek!
            stackCopy = stackCopy.pop()
            if case let .delimit(l, _) = k, l == label {
                let resume = Resume(frames: stackCopy)
                let effectRecord: Value = .record(["Resume": .resume(resume), "payload": payload])
                throw UnhandledEffect(label: label, payload: effectRecord)
            }
        }
        throw UnhandledEffect(label: label, payload: payload)
    }
}

// MARK: – Builtin registry ----------------------------------------------------

public let builtinTable: [String: (arity: Int, fn: Builtin)] = [
    "equal": (
        arity: 2,
        fn: { state, args in
            let eq = "\(args[0])" == "\(args[1])"
            await state.setValue(eq ? .tagged(tag: "True", inner: .empty) : .tagged(tag: "False", inner: .empty))
        }
    ),
    "print": (
        arity: 1,
        fn: { state, args in
            let msg = "\(args[0])"
            print(msg)
            await state.setValue(.string(msg))
        }
    ),
    "fix": (
        arity: 1,
        fn: { state, args in
            let builder = args[0]
            await state.push(.call(builder))
            await state.push(.call(.partial(arity: 2, applied: .empty, impl: builtinTable["fixed"]!.fn)))
            await state.setValue(builder)
        }
    ),
    "fixed": (
        arity: 2,
        fn: { state, args in
            let builder = args[0]
            let arg = args[1]
            await state.push(.call(arg))
            await state.push(.call(.partial(arity: 2, applied: .empty, impl: builtinTable["fixed"]!.fn)))
            await state.setValue(builder)
        }
    ),
    "int_compare": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else { fatalError() }
            let tag = a < b ? "Lt" : (a > b ? "Gt" : "Eq")
            await state.setValue(.tagged(tag: tag, inner: .empty))
        }
    ),
    "int_add": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else { fatalError() }
            await state.setValue(.int(a + b))
        }
    ),
    "int_subtract": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else { fatalError() }
            await state.setValue(.int(a - b))
        }
    ),
    "int_multiply": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else { fatalError() }
            await state.setValue(.int(a * b))
        }
    ),
    "int_divide": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else { fatalError() }
            await state.setValue(b == 0 ? .tagged(tag: "Error", inner: .empty) : .tagged(tag: "Ok", inner: .int(a / b)))
        }
    ),
    "int_absolute": (
        arity: 1,
        fn: { state, args in
            guard case let .int(a) = args[0] else { fatalError() }
            await state.setValue(.int(abs(a)))
        }
    ),
    "int_parse": (
        arity: 1,
        fn: { state, args in
            guard case let .string(str) = args[0] else { fatalError() }
            if let n = Int(str) {
                await state.setValue(.tagged(tag: "Ok", inner: .int(n)))
            } else {
                await state.setValue(.tagged(tag: "Error", inner: .empty))
            }
        }
    ),
    "int_to_string": (
        arity: 1,
        fn: { state, args in
            guard case let .int(a) = args[0] else { fatalError() }
            await state.setValue(.string(String(a)))
        }
    ),
    "string_append": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0], case let .string(b) = args[1] else { fatalError() }
            await state.setValue(.string(a + b))
        }
    ),
    "string_split": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0], case let .string(b) = args[1] else { fatalError() }
            let parts = a.split(separator: Character(b), omittingEmptySubsequences: false).map(String.init)
            var dict: [String: Value] = ["head": .string(parts.first ?? "")]
            dict["tail"] = .record(parts.dropFirst().reduce(into: [:]) { $0["\(UUID())"] = .string($1) })
            await state.setValue(.record(dict))
        }
    ),
    "string_length": (
        arity: 1,
        fn: { state, args in
            guard case let .string(a) = args[0] else { fatalError() }
            await state.setValue(.int(a.count))
        }
    ),
    "list_fold": (
        arity: 3,
        fn: { state, args in
            guard case let .record(list) = args[0], case let .record(initState) = args[1], case .closure = args[2] else { fatalError() }
            let values = Array(list.values)
            guard !values.isEmpty else { await state.setValue(.record(initState)); return }
            let head = values[0]
            let tail = Array(values.dropFirst())
            await state.push(.call(args[2]))
            await state.push(.call(.partial(arity: 3, applied: .empty, impl: builtinTable["list_fold"]!.fn)))
            await state.push(.call(.record(tail.reduce(into: initState) { $0["\(UUID())"] = $1 })))
            await state.push(.call(head))
            await state.setValue(args[2])
        }
    )
]

// MARK: – Public helpers for JSON round-trip ---------------------------------

public enum IRDecoder {
    public static func decode(_ data: Data) throws -> Expr { try JSONDecoder().decode(Expr.self, from: data) }
}

public enum IREncoder {
    public static func encode(_ expr: Expr) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(expr)
    }
}
