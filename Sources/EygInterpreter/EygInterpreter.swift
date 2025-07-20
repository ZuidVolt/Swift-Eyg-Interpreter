//  EygInterpreter.swift

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

    case reference(cid: String, project: String?, release: Int?)
    case release(pkg: String, ver: Int, cid: String)

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case type = "0"
        case label = "l"
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
            let n = try c.decode(String.self, forKey: .name)
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
            let cid = try c.decode(String.self, forKey: .label)
            if let pkg = try c.decodeIfPresent(String.self, forKey: .project),
                let ver = try c.decodeIfPresent(Int.self, forKey: .release) {
                self = .release(pkg: pkg, ver: ver, cid: cid)
            } else {
                self = .reference(cid: cid, project: nil, release: nil)
            }
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
            try c.encode(n, forKey: .name)
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
        case let .reference(cid, proj, rel):
            try c.encode("#", forKey: .type)
            try c.encode(cid, forKey: .label)
            try c.encodeIfPresent(proj, forKey: .project)
            try c.encodeIfPresent(rel, forKey: .release)
        case let .release(pkg, ver, cid):
            try c.encode("#", forKey: .type)
            try c.encode(cid, forKey: .label)
            try c.encode(pkg, forKey: .project)
            try c.encode(ver, forKey: .release)
        }
    }
}

// MARK: – Resume & Codable helpers --------------------------------------------

public struct Resume: Sendable, Codable {
    let frames: Stack<Cont>
    let env: Env
    /// Resume the captured continuation with a payload.
    /// this doesn't handle potential infinite loops or stack overflow scenarios yet
    public func invoke(_ payload: Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            Task {
                let sm = StateMachine(src: .variable("_"))
                await sm.setValue(payload)
                await sm.setStack(frames)
                await sm.setEnv(env)
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
    public static func == (lhs: Resume, rhs: Resume) -> Bool { lhs.frames == rhs.frames && lhs.env == rhs.env }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(frames)
        hasher.combine(env)
    }
}

// MARK: – Runtime stack -------------------------------------------------------

public typealias Env = [String: Value]

/// A single continuation frame.
public enum Cont: Sendable, Codable {
    case assign(name: String, then: Expr, env: Env)
    case arg(Expr, Env)
    case apply(Value, Env)
    case call(Value, Env)
    case delimit(label: String, handler: Value, deep: Bool)
}

extension Cont: Equatable, Hashable {
    public static func == (lhs: Cont, rhs: Cont) -> Bool {
        switch (lhs, rhs) {
        case let (.assign(n1, t1, e1), .assign(n2, t2, e2)):
            return n1 == n2 && t1 == t2 && e1 == e2
        case let (.arg(e1, env1), .arg(e2, env2)):
            return e1 == e2 && env1 == env2
        case let (.apply(v1, e1), .apply(v2, e2)):
            return v1 == v2 && e1 == e2
        case let (.call(v1, e1), .call(v2, e2)):
            return v1 == v2 && e1 == e2
        case let (.delimit(l1, h1, _), .delimit(l2, h2, _)):
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
        case let .apply(v, e):
            hasher.combine(2)
            hasher.combine(v)
            hasher.combine(e)
        case let .call(v, e):
            hasher.combine(3)
            hasher.combine(v)
            hasher.combine(e)
        case let .delimit(l, h, _):
            hasher.combine(4)
            hasher.combine(l)
            hasher.combine(h)
        }
    }
}
// MARK: Stack
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
    public init(_ elements: [Element]) {
        self = elements.reversed().reduce(Stack.empty) { $0.push($1) }
    }
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
        case let (.vacant(c1), .vacant(c2)): return c1 == c2
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
        case let (.reference(cid1, proj1, rel1), .reference(cid2, proj2, rel2)):
            return cid1 == cid2 && proj1 == proj2 && rel1 == rel2
        case let (.release(pkg1, ver1, cid1), .release(pkg2, ver2, cid2)):
            return pkg1 == pkg2 && ver1 == ver2 && cid1 == cid2
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
        case let .vacant(c):
            hasher.combine(4)
            hasher.combine(c)
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
        case let .reference(cid, proj, rel):
            hasher.combine(22)
            hasher.combine(cid)
            hasher.combine(proj)
            hasher.combine(rel)
        case let .release(pkg, ver, cid):
            hasher.combine(23)
            hasher.combine(pkg)
            hasher.combine(ver)
            hasher.combine(cid)
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
    case list(List)
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
            // Note: We can't compare function implementations directly
            // This is a known limitation - partials with same arity/args but different impls will be equal
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
        case let (.resume(r1), .resume(r2)): return r1 == r2
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
        case let .resume(r):
            hasher.combine(3)
            hasher.combine(r)
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

// MARK: – Ordered List
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
    public var description: String { impl.description }
}

// MARK: – Interpreter --------------------------------------------------------

/// Thrown when evaluation reaches an effect that is not handled.
public struct UnhandledEffect: Error, Sendable {
    let label: String
    let payload: Value
}

extension UnhandledEffect {
    /// A factory function to create an UnhandledEffect.
    public static func create(label: String, payload: Value) -> UnhandledEffect {
        return UnhandledEffect(label: label, payload: payload)
    }
}

/// All built-ins are just Swift closures.
public typealias Builtin = @Sendable (isolated StateMachine, [Value]) async throws -> Void

/// Mutable interpreter state isolated in an actor.
public actor StateMachine {
    var value: Value?
    var env: Env = [:]
    var stack: Stack<Cont> = .empty
    var control: Expr
    var isValue: Bool = false
    var references: [String: Value] = [:]

    init(src: Expr) { control = src }

    // MARK: helpers
    public func setValue(_ v: Value) {
        value = v
        isValue = true
    }
    fileprivate func setStack(_ s: Stack<Cont>) { stack = s }
    fileprivate func setIsValue(_ b: Bool) { isValue = b }
    fileprivate func setEnv(_ e: Env) { env = e }

    func resume(_ value: Value) {
        setValue(value)
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
        case .tail: setValue(.list(.empty))
        case .cons: setValue(.partial(arity: 2, applied: .empty, impl: consBuiltin))
        case .empty: setValue(.record([:]))
        case let .extend(label): setValue(.partial(arity: 2, applied: .empty, impl: extendBuiltin(label: label)))
        case let .select(label): setValue(.partial(arity: 1, applied: .empty, impl: selectBuiltin(label: label)))
        case let .overwrite(label): setValue(.partial(arity: 2, applied: .empty, impl: overwriteBuiltin(label: label)))
        case let .tag(label): setValue(.partial(arity: 1, applied: .empty, impl: tagBuiltin(label: label)))
        case let .case(tag): setValue(.partial(arity: 3, applied: .empty, impl: caseBuiltin(tag: tag)))
        case .noCases: setValue(.partial(arity: 1, applied: .empty, impl: noCasesBuiltin))
        case let .perform(label): setValue(.partial(arity: 1, applied: .empty, impl: performBuiltin(label: label)))
        case let .handle(label, handler, body):
            push(
                .delimit(
                    label: label,
                    handler: .closure(param: "_", body: handler, env: env),
                    deep: true))
            setExpression(body)
        case let .shallowHandle(label, handler, body):
            push(
                .delimit(
                    label: label,
                    handler: .closure(param: "_", body: handler, env: env),
                    deep: false))
            setExpression(body)
        case .builtin(let id):
            guard let entry = builtinTable[id] else {
                throw UnhandledEffect(label: "UndefinedBuiltin", payload: .string(id))
            }
            setValue(.partial(arity: entry.arity, applied: .empty, impl: entry.fn))
        // TODO:  finish the reference / release implementation
        case let .reference(cid, _, _):
            guard let v = references[cid] else {
                throw UnhandledEffect(label: "UndefinedReference", payload: .string(cid))
            }
            setValue(v)
        case let .release(pkg, ver, cid):
            throw UnhandledEffect(
                label: "UndefinedRelease",
                payload: .record([
                    "package": .string(pkg),
                    "release": .int(ver),
                    "cid": .string(cid)
                ]))
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
            push(.apply(v, env))
            env = savedEnv
            setExpression(expr)
        case let .apply(fnVal, _):
            try await self.call(fn: fnVal, arg: v)
        case let .call(argVal, _):
            try await self.call(fn: v, arg: argVal)
        case let .delimit(lbl, h, deep):
            if deep { push(.delimit(label: lbl, handler: h, deep: true)) }
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
                try await impl(self, newApplied.reversed())
            } else {
                setValue(.partial(arity: arity, applied: newApplied, impl: impl))
            }

        case let .resume(cont):
            let result = try await cont.invoke(arg)
            setStack(cont.frames)
            setEnv(cont.env)
            setValue(result)
            setIsValue(true)

        default:
            throw UnhandledEffect(label: "NotAFunction", payload: fn)
        }
    }
}

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

// MARK: – Public entry point --------------------------------------------------

/// Execute an expression `e` in the interpreter.
///
/// - Parameters:
///   - e: The expression to evaluate.
///   - extrinsic: A dictionary mapping effect labels to asynchronous handlers.
///     When an effect with a matching label is raised, the corresponding handler
///     is invoked with the effect’s payload and its result is used to resume
///     evaluation.
/// - Returns: The final value produced by evaluating the expression.
/// - Throws: Any unhandled effect or runtime error encountered during evaluation.
public func exec(_ e: Expr, extrinsic: [String: @Sendable (Value) async throws -> Value] = [:]) async throws -> Value {
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

// alias for exec
public let interpret = exec

// MARK: – Built-ins -----------------------------------------------------------

private let consBuiltin: Builtin = { state, args in
    switch args[1] {
    case let .list(tail):
        state.setValue(.list(tail.cons(args[0])))
    case .tail, .empty:
        state.setValue(.list(List([args[0]])))  // empty list becomes singleton
    default:
        throw UnhandledEffect(label: "TypeMismatch", payload: .string("cons expects list/tail as second arg"))
    }
}

private func extendBuiltin(label: String) -> Builtin {
    return { state, args in
        var r: [String: Value]
        switch args[1] {
        case let .record(rec): r = rec
        case .empty: r = [:]
        default:
            throw UnhandledEffect(label: "TypeMismatch", payload: .string("extend expects record/empty as second arg"))
        }
        r[label] = args[0]
        state.setValue(.record(r))
    }
}

private func selectBuiltin(label: String) -> Builtin {
    return { state, args in
        let r: [String: Value]
        switch args[0] {
        case let .record(rec): r = rec
        case .empty: r = [:]
        default:
            throw UnhandledEffect(label: "TypeMismatch", payload: .string("select expects record/empty"))
        }
        guard let v = r[label] else {
            throw UnhandledEffect(label: "MissingLabel", payload: .string(label))
        }
        state.setValue(v)
    }
}

private func overwriteBuiltin(label: String) -> Builtin {
    return { state, args in
        var r: [String: Value]
        switch args[1] {
        case let .record(rec): r = rec
        case .empty: r = [:]
        default:
            throw UnhandledEffect(
                label: "TypeMismatch", payload: .string("overwrite expects record/empty as second arg"))
        }
        r[label] = args[0]
        state.setValue(.record(r))
    }
}

private func tagBuiltin(label: String) -> Builtin {
    return { state, args in state.setValue(.tagged(tag: label, inner: args[0])) }
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
        var frames = state.stack
        var collected: [Cont] = []
        var handler: Value?

        // Search for handler
        while let frame = frames.peek {
            frames = frames.pop()
            if case let .delimit(l, h, deep) = frame, l == label {
                handler = h
                if deep {
                    frames = frames.push(frame)
                }
                break
            }
            collected.append(frame)
        }

        if let handler = handler {
            // Create resume continuation
            var resumeStack = Stack<Cont>.empty
            for frame in collected.reversed() {
                resumeStack = resumeStack.push(frame)
            }
            let resume = Resume(frames: resumeStack, env: state.env)
            let resumeValue = Value.resume(resume)

            // Capture current environment for continuations
            let currentEnv = state.env

            // Push handler call with payload, then resume with result
            state.push(.call(resumeValue, currentEnv))
            state.push(.apply(payload, currentEnv))

            state.setValue(handler)
        } else {
            // Throw UnhandledEffect instead of setting unhandled
            throw UnhandledEffect(label: label, payload: payload)
        }
    }
}
