//  EygInterpreter.swift
//  Created by mechanical translation of JS source

import Foundation

// MARK: – AST -----------------------------------------------------------------

/// Discriminated union for the surface syntax (full IR).
public indirect enum Expr: Sendable, Codable {
    case variable(String)  // "v"
    case lambda(param: String, body: Expr)  // "f"
    case apply(fn: Expr, arg: Expr)  // "a"
    case `let`(name: String, value: Expr, then: Expr)  // "l"
    case vacant(comment: String)  // "z"

    case binary([UInt8])  // "x"
    case int(Int)  // "i"
    case string(String)  // "s"

    case tail  // "ta"
    case cons  // "c"
    case empty  // "u"

    case extend(String)  // "e"
    case select(String)  // "g"
    case overwrite(String)  // "o"

    case tag(String)  // "t"
    case `case`(tag: String)  // "m"
    case noCases  // "n"

    case perform(String)  // "p"
    case handle(label: String, handler: Expr, body: Expr)  // "h"
    case shallowHandle(label: String, handler: Expr, body: Expr)  // "hs"
    case builtin(String)  // "b"

    case resume(continuation: Resume)  // internal continuation literal
    case reference(cid: String, project: String?, release: Int?)

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case type = "0"
        case label = "l"  // generic “label” key
        case value = "v"
        case body = "b"
        case handler = "h"
        case function = "f"
        case argument = "a"
        case name = "n"  // was "l" can't use the same string in enun
        case then = "t"
        case comment = "c"
        case tag = "m"  // was "l" can't use the same string in enun
        case cid = "cid"
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
        case "l":  // let
            let n = try c.decode(String.self, forKey: .label)
            let v = try c.decode(Expr.self, forKey: .value)
            let t = try c.decode(Expr.self, forKey: .then)
            self = .let(name: n, value: v, then: t)
        case "m":
            self = .case(tag: try c.decode(String.self, forKey: .label))
        case "x":
            let b64 = try c.decode(String.self, forKey: .value)
            guard let data = Data(base64Encoded: b64) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: c,
                    debugDescription: "Invalid base64 for binary")
            }
            self = .binary([UInt8](data))
        case "i": self = .int(try c.decode(Int.self, forKey: .value))
        case "s": self = .string(try c.decode(String.self, forKey: .value))
        case "ta": self = .tail
        case "c": self = .cons
        case "u": self = .empty
        case "z":
            let comment = try c.decode(String.self, forKey: .comment)
            self = .vacant(comment: comment)
        case "e": self = .extend(try c.decode(String.self, forKey: .label))
        case "g": self = .select(try c.decode(String.self, forKey: .label))
        case "o": self = .overwrite(try c.decode(String.self, forKey: .label))
        case "t": self = .tag(try c.decode(String.self, forKey: .label))
        case "n": self = .noCases
        case "p": self = .perform(try c.decode(String.self, forKey: .label))
        case "h":
            let l = try c.decode(String.self, forKey: .label)
            let h = try c.decode(Expr.self, forKey: .handler)
            let b = try c.decode(Expr.self, forKey: .body)
            self = .handle(label: l, handler: h, body: b)
        case "hs":
            let l = try c.decode(String.self, forKey: .label)
            let h = try c.decode(Expr.self, forKey: .handler)
            let b = try c.decode(Expr.self, forKey: .body)
            self = .shallowHandle(label: l, handler: h, body: b)
        case "b": self = .builtin(try c.decode(String.self, forKey: .label))
        case "#":
            let cid = try c.decode(String.self, forKey: .cid)
            let proj = try c.decodeIfPresent(String.self, forKey: .project)
            let rel = try c.decodeIfPresent(Int.self, forKey: .release)
            self = .reference(cid: cid, project: proj, release: rel)
        case "resume": self = .resume(continuation: try c.decode(Resume.self, forKey: .body))
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown IR type '\(t)'"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .variable(l):
            try c.encode("v", forKey: .type)
            try c.encode(l, forKey: .label)
        case let .lambda(p, b):
            try c.encode("f", forKey: .type)
            try c.encode(p, forKey: .label)
            try c.encode(b, forKey: .body)
        case let .apply(fn, arg):
            try c.encode("a", forKey: .type)
            try c.encode(fn, forKey: .function)
            try c.encode(arg, forKey: .argument)
        case let .let(n, v, t):
            try c.encode("l", forKey: .type)
            try c.encode(n, forKey: .label)
            try c.encode(v, forKey: .value)
            try c.encode(t, forKey: .then)
        case let .binary(bytes):
            try c.encode("x", forKey: .type)
            let data = Data(bytes)
            try c.encode(data.base64EncodedString(), forKey: .value)
        case let .int(v):
            try c.encode("i", forKey: .type)
            try c.encode(v, forKey: .value)
        case let .string(v):
            try c.encode("s", forKey: .type)
            try c.encode(v, forKey: .value)
        case .tail: try c.encode("ta", forKey: .type)
        case .cons: try c.encode("c", forKey: .type)
        case .empty: try c.encode("u", forKey: .type)
        case let .vacant(comment):
            try c.encode("z", forKey: .type)
            try c.encode(comment, forKey: .comment)
        case let .extend(l):
            try c.encode("e", forKey: .type)
            try c.encode(l, forKey: .label)
        case let .select(l):
            try c.encode("g", forKey: .type)
            try c.encode(l, forKey: .label)
        case let .overwrite(l):
            try c.encode("o", forKey: .type)
            try c.encode(l, forKey: .label)
        case let .tag(l):
            try c.encode("t", forKey: .type)
            try c.encode(l, forKey: .label)
        case let .case(t):
            try c.encode("m", forKey: .type)
            try c.encode(t, forKey: .label)
        case .noCases: try c.encode("n", forKey: .type)
        case let .perform(l):
            try c.encode("p", forKey: .type)
            try c.encode(l, forKey: .label)
        case let .handle(l, h, b):
            try c.encode("h", forKey: .type)
            try c.encode(l, forKey: .label)
            try c.encode(h, forKey: .handler)
            try c.encode(b, forKey: .body)
        case let .shallowHandle(l, h, b):
            try c.encode("hs", forKey: .type)
            try c.encode(l, forKey: .label)
            try c.encode(h, forKey: .handler)
            try c.encode(b, forKey: .body)
        case let .builtin(i):
            try c.encode("b", forKey: .type)
            try c.encode(i, forKey: .label)
        case let .resume(r):
            try c.encode("resume", forKey: .type)
            try c.encode(r, forKey: .body)
        case let .reference(cid, proj, rel):
            try c.encode("#", forKey: .type)
            try c.encode(cid, forKey: .cid)
            try c.encodeIfPresent(proj, forKey: .project)
            try c.encodeIfPresent(rel, forKey: .release)
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
                    if isVal, empty {
                        continuation.resume(returning: val!)
                        return
                    }
                }
            }
        }
    }
}

extension Resume: Equatable, Hashable {
    public static func == (lhs: Resume, rhs: Resume) -> Bool { lhs.frames == rhs.frames }
    public func hash(into hasher: inout Hasher) { hasher.combine(frames) }
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

extension Cont: Equatable, Hashable {
    public static func == (lhs: Cont, rhs: Cont) -> Bool {
        switch (lhs, rhs) {
        case let (.assign(n1, t1, e1), .assign(n2, t2, e2)):
            return n1 == n2 && t1 == t2 && e1 == e2
        case let (.arg(e1, env1), .arg(e2, env2)):
            return e1 == e2 && env1 == env2
        case let (.apply(v1), .apply(v2)): return v1 == v2
        case let (.call(v1), .call(v2)): return v1 == v2
        case let (.delimit(l1, h1), .delimit(l2, h2)):
            return l1 == l2 && h1 == h2
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .assign(n, t, e):
            hasher.combine(0)
            hasher.combine(n)
            hasher.combine(t)
            hasher.combine(e)
        case let .arg(e, env):
            hasher.combine(1)
            hasher.combine(e)
            hasher.combine(env)
        case let .apply(v):
            hasher.combine(2)
            hasher.combine(v)
        case let .call(v):
            hasher.combine(3)
            hasher.combine(v)
        case let .delimit(l, h):
            hasher.combine(4)
            hasher.combine(l)
            hasher.combine(h)
        }
    }
}

/// Immutable stack used for continuations and partial applications.
public struct Stack<Element: Sendable>: Sendable, Codable
where Element: Codable & Hashable & Equatable {

    private indirect enum Link: Sendable, Codable, Hashable, Equatable {
        case empty
        case node(Element, Link)

        static func == (lhs: Link, rhs: Link) -> Bool {
            switch (lhs, rhs) {
            case (.empty, .empty): return true
            case let (.node(l1, n1), .node(l2, n2)): return l1 == l2 && n1 == n2
            default: return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .empty: hasher.combine(0)
            case let .node(v, n):
                hasher.combine(1)
                hasher.combine(v)
                hasher.combine(n)
            }
        }
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

extension Stack: Equatable, Hashable where Element: Equatable & Hashable {
    public static func == (lhs: Stack, rhs: Stack) -> Bool { lhs.root == rhs.root }
    public func hash(into hasher: inout Hasher) { hasher.combine(root) }
}

// MARK: – Value (runtime) -----------------------------------------------------

extension Expr: Equatable {
    public static func == (lhs: Expr, rhs: Expr) -> Bool {
        switch (lhs, rhs) {
        case let (.variable(l1), .variable(l2)): return l1 == l2
        case let (.lambda(p1, b1), .lambda(p2, b2)): return p1 == p2 && b1 == b2
        case let (.apply(fn1, arg1), .apply(fn2, arg2)): return fn1 == fn2 && arg1 == arg2
        case let (.let(n1, v1, t1), .let(n2, v2, t2)): return n1 == n2 && v1 == v2 && t1 == t2
        case (.vacant, .vacant): return true
        case let (.binary(v1), .binary(v2)): return v1 == v2
        case let (.int(v1), .int(v2)): return v1 == v2
        case let (.string(v1), .string(v2)): return v1 == v2
        case (.tail, .tail): return true
        case (.cons, .cons): return true
        case (.empty, .empty): return true
        case let (.extend(l1), .extend(l2)): return l1 == l2
        case let (.select(l1), .select(l2)): return l1 == l2
        case let (.overwrite(l1), .overwrite(l2)): return l1 == l2
        case let (.tag(l1), .tag(l2)): return l1 == l2
        case let (.case(t1), .case(t2)): return t1 == t2
        case (.noCases, .noCases): return true
        case let (.perform(l1), .perform(l2)): return l1 == l2
        case let (.handle(l1, h1, b1), .handle(l2, h2, b2)): return l1 == l2 && h1 == h2 && b1 == b2
        case let (.builtin(i1), .builtin(i2)): return i1 == i2
        case let (.resume(r1), .resume(r2)): return r1 == r2
        default: return false
        }
    }
}

extension Expr: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .variable(l):
            hasher.combine(0)
            hasher.combine(l)
        case let .lambda(p, b):
            hasher.combine(1)
            hasher.combine(p)
            hasher.combine(b)
        case let .apply(fn, arg):
            hasher.combine(2)
            hasher.combine(fn)
            hasher.combine(arg)
        case let .let(n, v, t):
            hasher.combine(3)
            hasher.combine(n)
            hasher.combine(v)
            hasher.combine(t)
        case .vacant: hasher.combine(4)
        case let .binary(v):
            hasher.combine(5)
            hasher.combine(v)
        case let .int(v):
            hasher.combine(6)
            hasher.combine(v)
        case let .string(v):
            hasher.combine(7)
            hasher.combine(v)
        case .tail: hasher.combine(8)
        case .cons: hasher.combine(9)
        case .empty: hasher.combine(10)
        case let .extend(l):
            hasher.combine(11)
            hasher.combine(l)
        case let .select(l):
            hasher.combine(12)
            hasher.combine(l)
        case let .overwrite(l):
            hasher.combine(13)
            hasher.combine(l)
        case let .tag(l):
            hasher.combine(14)
            hasher.combine(l)
        case let .case(t):
            hasher.combine(15)
            hasher.combine(t)
        case .noCases: hasher.combine(16)
        case let .perform(l):
            hasher.combine(17)
            hasher.combine(l)
        case let .handle(l, h, b):
            hasher.combine(18)
            hasher.combine(l)
            hasher.combine(h)
            hasher.combine(b)
        case let .shallowHandle(l, h, b):
            hasher.combine(19)
            hasher.combine(l)
            hasher.combine(h)
            hasher.combine(b)
        case let .builtin(i):
            hasher.combine(20)
            hasher.combine(i)
        case let .resume(r):
            hasher.combine(21)
            hasher.combine(r)
        case let .reference(cid, proj, rel):
            hasher.combine(22)
            hasher.combine(cid)
            hasher.combine(proj)
            hasher.combine(rel)
        }
    }
}

public indirect enum Value: Sendable, Equatable, Hashable {
    case int(Int)
    case string(String)
    case closure(param: String, body: Expr, env: Env)
    case partial(arity: Int, applied: Stack<Value>, impl: Builtin)
    case tagged(tag: String, inner: Value)
    case record([String: Value])
    case list(List)  // NEW
    case empty
    case tail
    case binary([UInt8])
    case resume(Resume)

    // Needed for Hashable (Builtin is not Hashable; we only compare identity)
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case let (.int(a), .int(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.closure(p1, b1, e1), .closure(p2, b2, e2)):
            return p1 == p2 && b1 == b2 && e1 == e2
        case let (.partial(ar1, ap1, _), .partial(ar2, ap2, _)):
            return ar1 == ar2 && ap1 == ap2
        case let (.tagged(t1, i1), .tagged(t2, i2)):
            return t1 == t2 && i1 == i2
        case let (.record(r1), .record(r2)):
            return r1 == r2
        case let (.list(l1), .list(l2)):
            return l1 == l2
        case (.empty, .empty): return true
        case (.tail, .tail): return true
        case let (.binary(b1), .binary(b2)): return b1 == b2
        case (.resume, .resume): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .int(i): hasher.combine(i)
        case let .string(s): hasher.combine(s)
        case let .closure(p, b, _):
            hasher.combine(p)
            hasher.combine(b)
        case let .partial(ar, ap, _):
            hasher.combine(ar)
            hasher.combine(ap)
        case let .tagged(t, i):
            hasher.combine(t)
            hasher.combine(i)
        case let .record(r): hasher.combine(r)
        case let .list(l): hasher.combine(l)
        case .empty: hasher.combine(0)
        case .tail: hasher.combine(1)
        case let .binary(b): hasher.combine(b)
        case .resume: hasher.combine(3)
        }
    }
}

// MARK: – Value Codable (only the parts we can encode)
extension Value: Codable {
    private enum CodingKeys: String, CodingKey {
        case int, string, closure, tagged, record, list, empty, tail, binary
        case partial, resume
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch c.allKeys.first {
        case .int: self = .int(try c.decode(Int.self, forKey: .int))
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
        case .list: self = .list(List(try c.decode([Value].self, forKey: .list)))
        case .empty: self = .empty
        case .tail: self = .tail
        case .binary: self = .binary(try c.decode([UInt8].self, forKey: .binary))
        case .partial:
            var n = try c.nestedUnkeyedContainer(forKey: .partial)
            let arity = try n.decode(Int.self)
            let applied = try n.decode(Stack<Value>.self)
            let name = try n.decode(String.self)
            guard let entry = builtinTable[name] else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown builtin \(name)"))
            }
            self = .partial(arity: arity, applied: applied, impl: entry.fn)
        case .resume:
            self = .resume(try c.decode(Resume.self, forKey: .resume))
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Value contains non-codable Builtin/Resume"))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .int(i): try c.encode(i, forKey: .int)
        case let .string(s): try c.encode(s, forKey: .string)
        case let .closure(p, b, e):
            var n = c.nestedUnkeyedContainer(forKey: .closure)
            try n.encode(p)
            try n.encode(b)
            try n.encode(e)
        case let .tagged(t, i):
            var n = c.nestedUnkeyedContainer(forKey: .tagged)
            try n.encode(t)
            try n.encode(i)
        case let .record(r): try c.encode(r, forKey: .record)
        case let .list(l):
            try c.encode(l.array, forKey: .list)
        case .empty: try c.encode(true, forKey: .empty)
        case .tail: try c.encode(true, forKey: .tail)
        case let .binary(b):
            try c.encode(b, forKey: .binary)
        case let .resume(r):
            try c.encode(r, forKey: .resume)
        case .partial: break
        }
    }
}

// MARK: – Ordered List (drop-in replacement for [String:Value] tails)
public struct List: Sendable, Equatable, Codable, CustomStringConvertible, Hashable {
    private let impl: [Value]  // simple array gives cheap Equatable

    public init(_ elements: [Value] = []) { impl = elements }
    public var array: [Value] { impl }

    // Cons / Tail helpers
    public static let empty = List()
    public var isEmpty: Bool { impl.isEmpty }
    public func cons(_ head: Value) -> List { List([head] + impl) }
    public var head: Value? { impl.first }
    public var tail: List? { impl.isEmpty ? nil : List(Array(impl.dropFirst())) }

    // MARK: Codable already works via [Value]

    public var description: String { impl.description }
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
    var unhandled: UnhandledEffect?

    init(src: Expr) { control = src }

    // MARK: helpers
    public func setValue(_ v: Value) {
        value = v
        isValue = true
    }
    fileprivate func setStack(_ s: Stack<Cont>) { stack = s }
    fileprivate func setIsValue(_ b: Bool) { isValue = b }

    func resume(_ value: Value) {
        setValue(value)
        unhandled = nil
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

    func setUnhandled(_ e: UnhandledEffect) { unhandled = e }

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
        case let .apply(fn, arg):
            push(.arg(arg, env))
            setExpression(fn)
        case let .let(name, val, then):
            push(.assign(name: name, then: then, env: env))
            setExpression(val)
        case .vacant: throw UnhandledEffect(label: "NotImplemented", payload: .empty)
        case .binary(let bytes): setValue(.binary(bytes))
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
        case let .handle(label, handler, body):
            push(.delimit(label: label, handler: .closure(param: "_", body: handler, env: env)))
            setExpression(body)
        case let .shallowHandle(label, handler, body):
            push(.delimit(label: label, handler: .closure(param: "_", body: handler, env: env)))
            setExpression(body)
        case .builtin(let id):
            guard let entry = builtinTable[id] else {
                throw UnhandledEffect(label: "UndefinedBuiltin", payload: .string(id))
            }
            setValue(.partial(arity: entry.arity, applied: .empty, impl: entry.fn))
        case let .resume(cont): setValue(.resume(cont))
        case let .reference(cid, _, _):
            setValue(.string(cid))
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
        case let .apply(fnVal): try await call(fn: fnVal, arg: v)
        case let .call(argVal): try await call(fn: v, arg: argVal)
        case .delimit:
            // 6. Push the frame back; it is needed for recursive performs
            push(k)
            return
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
            guard case let .record(r) = inner,
                let resumeVal = r["k"],
                case let .resume(resume) = resumeVal
            else { fatalError("Malformed Resume") }
            let result = try await resume.invoke(arg)
            setValue(result)
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
    guard case let .list(tail) = args[1] else {
        throw UnhandledEffect(label: "TypeMismatch", payload: .string("cons expects list as second arg"))
    }
    await state.setValue(.list(tail.cons(args[0])))
}

private func extendBuiltin(label: String) -> Builtin {
    return { state, args in
        guard case var .record(r) = args[1] else {
            throw UnhandledEffect(label: "TypeMismatch", payload: .string("extend expects record as second arg"))
        }
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
        guard case var .record(r) = args[1] else {
            throw UnhandledEffect(label: "TypeMismatch", payload: .string("overwrite expects record as second arg"))
        }
        r[label] = args[0]
        await state.setValue(.record(r))
    }
}

private func tagBuiltin(label: String) -> Builtin {
    return { state, args in await state.setValue(.tagged(tag: label, inner: args[0])) }
}

private func caseBuiltin(tag: String) -> Builtin {
    return { state, args in
        let branch = args[0]
        let otherwise = args[1]
        let value = args[2]
        guard case let .tagged(t, inner) = value else {
            throw UnhandledEffect(label: "NotTagged", payload: value)
        }
        try await (t == tag ? state.call(fn: branch, arg: inner) : state.call(fn: otherwise, arg: value))
    }
}

private let noCasesBuiltin: Builtin = { _, args in
    throw UnhandledEffect(label: "NoCasesMatched", payload: args[0])
}

private func performBuiltin(label: String) -> Builtin {
    return { state, args in
        let payload = args[0]

        // Walk the stack from the top
        var cursor = await state.stack
        var handler: Value?

        while let frame = cursor.peek {
            if case let .delimit(l, h) = frame, l == label {
                handler = h
                break
            }
            cursor = cursor.pop()
        }

        guard let handler = handler else {
            // 1. Suspend instead of throwing
            await state.setIsValue(false)
            await state.setUnhandled(UnhandledEffect(label: label, payload: payload))
            return
        }

        // 2. Push the continuation *before* calling the handler
        let resume = Resume(frames: cursor)
        await state.push(.call(.resume(resume)))
        await state.setValue(handler)  // handler receives *only* the payload
    }
}

// MARK: – Builtin registry ----------------------------------------------------

public let builtinTable: [String: (arity: Int, fn: Builtin)] = [
    "equal": (
        arity: 2,
        fn: { state, args in
            func deepEqual(_ a: Value, _ b: Value) -> Bool {
                switch (a, b) {
                case let (.int(x), .int(y)): return x == y
                case let (.string(x), .string(y)): return x == y
                case let (.tagged(t1, i1), .tagged(t2, i2)):
                    return t1 == t2 && deepEqual(i1, i2)
                case let (.record(r1), .record(r2)):
                    return r1.count == r2.count && r1.allSatisfy { k, v in deepEqual(v, r2[k] ?? .empty) }
                case let (.list(l1), .list(l2)):
                    return l1.array.count == l2.array.count && zip(l1.array, l2.array).allSatisfy(deepEqual)
                case (.empty, .empty), (.tail, .tail):
                    return true
                default: return false
                }
            }
            await state.setValue(
                deepEqual(args[0], args[1])
                    ? .tagged(tag: "True", inner: .empty)
                    : .tagged(tag: "False", inner: .empty))
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
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_compare expects two ints"))
            }
            let tag = a < b ? "Lt" : (a > b ? "Gt" : "Eq")
            await state.setValue(.tagged(tag: tag, inner: .empty))
        }
    ),
    "int_add": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_add expects two ints"))
            }
            await state.setValue(.int(a + b))
        }
    ),
    "int_subtract": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_subtract expects two ints"))
            }
            await state.setValue(.int(a - b))
        }
    ),
    "int_multiply": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_multiply expects two ints"))
            }
            await state.setValue(.int(a * b))
        }
    ),
    "int_divide": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_divide expects two ints"))
            }
            await state.setValue(b == 0 ? .tagged(tag: "Error", inner: .empty) : .tagged(tag: "Ok", inner: .int(a / b)))
        }
    ),
    "int_absolute": (
        arity: 1,
        fn: { state, args in
            guard case let .int(a) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_absolute expects an int"))
            }
            await state.setValue(.int(abs(a)))
        }
    ),
    "int_parse": (
        arity: 1,
        fn: { state, args in
            guard case let .string(str) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_parse expects a string"))
            }
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
            guard case let .int(a) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_to_string expects an int"))
            }
            await state.setValue(.string(String(a)))
        }
    ),
    "string_append": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0], case let .string(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("string_append expects two strings"))
            }
            await state.setValue(.string(a + b))
        }
    ),
    "string_split": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0], case let .string(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("string_split expects two strings"))
            }
            let parts = a.split(separator: Character(b), omittingEmptySubsequences: false).map(String.init)
            let head = parts.first ?? ""
            let tail = List(parts.dropFirst().map(Value.string))
            await state.setValue(.record(["head": .string(head), "tail": .list(tail)]))
        }
    ),
    "string_split_once": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0], case let .string(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("string_split_once expects two strings"))
            }
            if let range = a.range(of: b) {
                let pre = String(a[..<range.lowerBound])
                let post = String(a[range.upperBound...])
                await state.setValue(.tagged(tag: "Ok", inner: .record(["pre": .string(pre), "post": .string(post)])))
            } else {
                await state.setValue(.tagged(tag: "Error", inner: .empty))
            }
        }
    ),
    "string_length": (
        arity: 1,
        fn: { state, args in
            guard case let .string(a) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("string_length expects a string"))
            }
            await state.setValue(.int(a.count))
        }
    ),
    "list_fold": (
        arity: 3,
        fn: { state, args in
            guard case let .list(l) = args[0],
                case let .closure(p, b, e) = args[2]
            else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("list_fold expects a list and a closure"))
            }
            if l.isEmpty {
                await state.setValue(args[1])
            } else {
                let head = l.head!
                let tail = l.tail!
                await state.push(.call(.closure(param: p, body: b, env: e)))
                await state.push(.call(.list(tail)))
                await state.push(.call(args[1]))
                await state.push(.call(head))
                await state.setValue(.closure(param: p, body: b, env: e))
            }
        }
    ),
    "list_pop": (
        arity: 1,
        fn: { state, args in
            guard case let .list(l) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("list_pop expects list"))
            }
            if l.isEmpty {
                await state.setValue(.tagged(tag: "Error", inner: .empty))
            } else {
                let head = l.head!
                let tail = l.tail!
                await state.setValue(
                    .tagged(
                        tag: "Ok",
                        inner: .record([
                            "head": head,
                            "tail": .list(tail)
                        ])))
            }
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

public func exec(_ e: Expr, extrinsic: [String: @Sendable (Value) async throws -> Value]) async throws -> Value {
    let sm = StateMachine(src: e)
    while true {
        do {
            try await sm.step()
        } catch let eff as UnhandledEffect {
            guard let handler = extrinsic[eff.label] else { throw eff }
            let v = try await handler(eff.payload)
            await sm.resume(v)
            continue
        }

        let (isVal, empty, val) = await (sm.isValue, sm.stack.isEmpty, sm.value)
        if isVal && empty { return val! }
    }
}
