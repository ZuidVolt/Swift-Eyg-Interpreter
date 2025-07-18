//  EygInterpreter.swift
//  Created by mechanical translation of JS source

import Foundation

// MARK: – AST -----------------------------------------------------------------

/// Discriminated union for the surface syntax.
public indirect enum Expr: Sendable {
    case variable(String)  // VAR   "v"
    case lambda(param: String, body: Expr)  // LAMBDA "f"
    case apply(fn: Expr, arg: Expr)  // APPLY "a"
    case `let`(name: String, value: Expr, then: Expr)  // LET "l"
    case vacant  // VACANT "z"

    case binary(String)  // "x"
    case int(Int)  // "i"
    case string(String)  // "s"

    case tail  // TAIL "ta"
    case cons  // CONS "c"

    case empty  // EMPTY "u"
    case extend(String)  // EXTEND "e"
    case select(String)  // SELECT "g"
    case overwrite(String)  // OVERWRITE "o"

    case tag(String)  // TAG "t"
    case `case`(tag: String)  // CASE "m"
    case noCases  // NOCASES "n"

    case perform(String)  // PERFORM "p"
    case handle(label: String, handler: Expr, body: Expr)  // HANDLE "h"

    case builtin(String)  // BUILTIN "b"
}

// MARK: – Runtime values ------------------------------------------------------

/// Everything that can sit on the runtime stack.
public indirect enum Value: Sendable {
    case int(Int)
    case string(String)
    case closure(param: String, body: Expr, env: Env)
    case partial(arity: Int, applied: Stack<Value>, impl: Builtin)
    case tagged(tag: String, inner: Value)
    case record([String: Value])
    case empty
    case tail
}

/// A single environment frame is just a dictionary.
public typealias Env = [String: Value]

/// A continuation frame.
indirect enum Cont: Sendable {
    case assign(name: String, then: Expr, env: Env)
    case arg(Expr, Env)
    case apply(Value)  // already evaluated function
    case call(Value)  // already evaluated argument
    case delimit(label: String, handler: Value)
}

/// A minimal immutable stack.
public struct Stack<Element: Sendable>: Sendable {
    private indirect enum Link: Sendable {
        case empty
        case node(Element, Link)
    }
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
        while case let .node(v, next) = cur {
            out.append(v)
            cur = next
        }
        return out
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
    public func setValue(_ v: Value) {
        value = v
        isValue = true
    }
    func setExpression(_ e: Expr) {
        control = e
        isValue = false
    }
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
        var myself = self  // mutable copy
        try await impl(&myself, args)
        // copy back mutable state
        value = await myself.value
        env = await myself.env
        stack = await myself.stack
        control = await myself.control
        isValue = await myself.isValue
    }

    // MARK: eval
    private func eval() async throws {
        switch control {
        case .variable(let name):
            setValue(try lookup(name))

        case let .lambda(p, b):
            setValue(.closure(param: p, body: b, env: env))

        case let .apply(fn, arg):
            push(.arg(arg, env))
            setExpression(fn)

        case let .let(name, val, then):
            push(.assign(name: name, then: then, env: env))
            setExpression(val)

        case .vacant:
            throw UnhandledEffect(label: "NotImplemented", payload: .empty)

        case .binary(let bits):
            setValue(.string(bits))  // TODO: distinguish later
        case .int(let bits):
            setValue(.int(bits))
        case .string(let bits):
            setValue(.string(bits))

        case .tail:
            setValue(.tail)

        case .cons:
            setValue(.partial(arity: 2, applied: .empty, impl: consBuiltin))

        case .empty:
            setValue(.empty)

        case let .extend(label):
            setValue(.partial(arity: 2, applied: .empty, impl: extendBuiltin(label: label)))

        case let .select(label):
            setValue(.partial(arity: 1, applied: .empty, impl: selectBuiltin(label: label)))

        case let .overwrite(label):
            setValue(.partial(arity: 2, applied: .empty, impl: overwriteBuiltin(label: label)))

        case let .tag(label):
            setValue(.partial(arity: 1, applied: .empty, impl: tagBuiltin(label: label)))

        case let .case(tag):
            setValue(.partial(arity: 3, applied: .empty, impl: caseBuiltin(tag: tag)))

        case .noCases:
            setValue(.partial(arity: 1, applied: .empty, impl: noCasesBuiltin))

        case let .perform(label):
            setValue(.partial(arity: 1, applied: .empty, impl: performBuiltin(label: label)))

        case let .handle(label, _, body):
            push(.delimit(label: label, handler: try await interpret(body)))
            setValue(.closure(param: "_", body: body, env: env))

        case .builtin(let id):
            guard let entry = builtinTable[id] else {
                throw UnhandledEffect(label: "UndefinedBuiltin", payload: .string(id))
            }
            setValue(.partial(arity: entry.arity, applied: .empty, impl: entry.fn))
        }
    }

    // MARK: apply
    private func apply() async throws {
        guard let v = value else { return }
        guard let k = stack.peek else { return }
        stack = stack.pop()

        switch k {
        case let .assign(name, then, savedEnv):
            env = savedEnv
            env[name] = v
            setExpression(then)

        case let .arg(expr, savedEnv):
            push(.apply(v))
            env = savedEnv
            setExpression(expr)

        case let .apply(fnVal):
            try await call(fn: fnVal, arg: v)

        case let .call(argVal):
            try await call(fn: v, arg: argVal)

        case .delimit:
            break  // handled by perform
        }
    }

    // MARK: call
    func call(fn: Value, arg: Value) async throws {
        switch fn {
        case let .closure(p, b, savedEnv):
            env = savedEnv
            env[p] = arg
            setExpression(b)

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
        let (isVal, stackEmpty, val) = await (sm.isValue, sm.stack.isEmpty, sm.value)
        if isVal && stackEmpty { return val! }
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
    return { state, args in
        await state.setValue(.tagged(tag: label, inner: args[0]))
    }
}

private func caseBuiltin(tag: String) -> Builtin {
    return { state, args in
        let branch = args[0]
        let otherwise = args[1]
        let value = args[2]
        guard case let .tagged(t, inner) = value else {
            throw UnhandledEffect(label: "NotTagged", payload: value)
        }
        if t == tag {
            try await state.call(fn: branch, arg: inner)
        } else {
            try await state.call(fn: otherwise, arg: value)
        }
    }
}

private let noCasesBuiltin: Builtin = { _, args in
    print(args[0])
    throw UnhandledEffect(label: "NoCasesMatched", payload: args[0])
}

private func performBuiltin(label: String) -> Builtin {
    return { state, args in
        let lift = args[0]
        var stack = await state.stack
        var reversed: [Cont] = []

        while !stack.isEmpty {
            let k = stack.peek!
            stack = stack.pop()
            reversed.append(k)
            if case let .delimit(l, _) = k, l == label {
                await state.setValue(.tagged(tag: "Resume", inner: .record(["k": .string("TODO")])))
                return
            }
        }

        throw UnhandledEffect(label: label, payload: lift)
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
            let tag: String
            if a < b { tag = "Lt" } else if a > b { tag = "Gt" } else { tag = "Eq" }
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
            guard case let .record(list) = args[0], case let .record(initState) = args[1], case .closure = args[2]
            else { fatalError() }
            let values = list.values.map { $0 }
            guard !values.isEmpty else {
                await state.setValue(.record(initState))
                return
            }
            var tail = values
            let head = tail.removeFirst()
            await state.push(.call(args[2]))
            await state.push(.call(.partial(arity: 3, applied: .empty, impl: builtinTable["list_fold"]!.fn)))
            await state.push(.call(.record(initState)))
            await state.push(.call(head))
            await state.setValue(args[2])
        }
    )
]
