// MARK: – Builtin registry ----------------------------------------------------

public let builtinTable: [String: (arity: Int, fn: Builtin)] = [
    "equal": (
        arity: 2,
        fn: { state, args in
            func deepEqual(_ a: Value, _ b: Value) -> Bool {
                switch (a, b) {
                case let (.binary(b1), .binary(b2)): return b1 == b2
                case let (.int(x), .int(y)): return x == y
                case let (.string(x), .string(y)): return x == y
                case let (.tagged(t1, i1), .tagged(t2, i2)):
                    return t1 == t2 && deepEqual(i1, i2)
                case let (.record(r1), .record(r2)):
                    return r1.count == r2.count && r1.keys == r2.keys && r1.allSatisfy { k, v in deepEqual(v, r2[k]!) }
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
            await state.push(.call(builder, [:]))
            await state.push(
                .call(
                    .partial(
                        arity: 2, applied: .empty,
                        impl: builtinTable["fixed"]!.fn), [:]))
            await state.setValue(builder)
        }
    ),
    "fixed": (
        arity: 2,
        fn: { state, args in
            let builder = args[0]
            let arg = args[1]
            await state.push(.call(arg, [:]))
            await state.push(.call(.partial(arity: 2, applied: .empty, impl: builtinTable["fixed"]!.fn), [:]))
            await state.setValue(builder)
        }
    ),
    "int_compare": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_compare expects int for argument 1"))
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
                await state.push(.call(.closure(param: p, body: b, env: e), [:]))
                await state.push(.call(args[1], [:]))
                await state.push(.call(.list(tail), [:]))
                await state.push(.call(head, [:]))
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
