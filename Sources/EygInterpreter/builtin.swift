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
            state.setValue(
                deepEqual(args[0], args[1])
                    ? .tagged(tag: "True", inner: .empty)
                    : .tagged(tag: "False", inner: .empty))
        }
    ),
    "fix": (
        arity: 1,
        fn: { state, args in
            let builder = args[0]

            // Create the fixed partial with builder already applied
            let fixedPartial = Value.partial(
                arity: 2,
                applied: Stack([builder]),
                impl: builtinTable["fixed"]!.fn
            )

            // Push the fixed partial to be called
            state.push(.call(fixedPartial, state.env))
            // Set builder as the function to call
            state.setValue(builder)
        }
    ),
    "fixed": (
        arity: 2,
        fn: { state, args in
            let builder = args[0]
            let arg = args[1]

            // Create the fixed partial with builder already applied
            let fixedPartial = Value.partial(
                arity: 2,
                applied: Stack([builder]),
                impl: builtinTable["fixed"]!.fn
            )

            // Push the argument to be consumed by builder
            state.push(.call(arg, state.env))
            // Push the fixed partial as the second argument to builder
            state.push(.call(fixedPartial, state.env))
            // Set builder as the function to call
            state.setValue(builder)
        }
    ),
    "int_compare": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_compare expects int for argument 1"))
            }
            let tag = a < b ? "Lt" : (a > b ? "Gt" : "Eq")
            state.setValue(.tagged(tag: tag, inner: .empty))
        }
    ),
    "int_add": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_add expects two ints"))
            }
            state.setValue(.int(a + b))
        }
    ),
    "int_subtract": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_subtract expects two ints"))
            }
            state.setValue(.int(a - b))
        }
    ),
    "int_multiply": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_multiply expects two ints"))
            }
            state.setValue(.int(a * b))
        }
    ),
    "int_divide": (
        arity: 2,
        fn: { state, args in
            guard case let .int(a) = args[0], case let .int(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_divide expects two ints"))
            }
            state.setValue(b == 0 ? .tagged(tag: "Error", inner: .empty) : .tagged(tag: "Ok", inner: .int(a / b)))
        }
    ),
    "int_absolute": (
        arity: 1,
        fn: { state, args in
            guard case let .int(a) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_absolute expects an int"))
            }
            state.setValue(.int(abs(a)))
        }
    ),
    "int_parse": (
        arity: 1,
        fn: { state, args in
            guard case let .string(str) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_parse expects a string"))
            }
            if let n = Int(str) {
                state.setValue(.tagged(tag: "Ok", inner: .int(n)))
            } else {
                state.setValue(.tagged(tag: "Error", inner: .empty))
            }
        }
    ),
    "int_to_string": (
        arity: 1,
        fn: { state, args in
            guard case let .int(a) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("int_to_string expects an int"))
            }
            state.setValue(.string(String(a)))
        }
    ),
    "string_append": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0], case let .string(b) = args[1] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("string_append expects two strings"))
            }
            state.setValue(.string(a + b))
        }
    ),
    "string_split": (
        arity: 2,
        fn: { state, args in
            guard case let .string(a) = args[0],
                case let .string(b) = args[1]
            else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_split expects two strings")
                )
            }
            let parts = a.components(separatedBy: b)
            let head = parts.first ?? ""
            let tail = List(parts.dropFirst().map(Value.string))
            state.setValue(.record(["head": .string(head), "tail": .list(tail)]))
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
                state.setValue(.tagged(tag: "Ok", inner: .record(["pre": .string(pre), "post": .string(post)])))
            } else {
                state.setValue(.tagged(tag: "Error", inner: .empty))
            }
        }
    ),
    "string_length": (
        arity: 1,
        fn: { state, args in
            guard case let .string(a) = args[0] else {
                throw UnhandledEffect(label: "TypeMismatch", payload: .string("string_length expects a string"))
            }
            state.setValue(.int(a.count))
        }
    ),
    "list_fold": (
        arity: 3,
        fn: { state, args in
            guard case let .list(l) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("list_fold expects a list as first argument")
                )
            }

            if l.isEmpty {
                state.setValue(args[1])
            } else {
                let head = l.head!
                let tail = l.tail!
                let nextFold = Value.partial(
                    arity: 3,
                    applied: Stack([.list(tail), args[2]]),
                    impl: builtinTable["list_fold"]!.fn
                )
                state.push(.call(nextFold, state.env))
                state.push(.call(args[1], state.env))
                state.push(.call(head, state.env))
                state.setValue(args[2])
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
                state.setValue(.tagged(tag: "Error", inner: .empty))
            } else {
                let head = l.head!
                let tail = l.tail!
                state.setValue(
                    .tagged(
                        tag: "Ok",
                        inner: .record([
                            "head": head,
                            "tail": .list(tail)
                        ])))
            }
        }
    ),
    "string_replace": (
        arity: 3,
        fn: { state, args in
            guard case let .string(str) = args[0],
                case let .string(from) = args[1],
                case let .string(to) = args[2]
            else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_replace expects three strings")
                )
            }
            let result = str.replacingOccurrences(of: from, with: to)
            state.setValue(.string(result))
        }
    ),

    "string_uppercase": (
        arity: 1,
        fn: { state, args in
            guard case let .string(str) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_uppercase expects a string")
                )
            }
            state.setValue(.string(str.uppercased()))
        }
    ),

    "string_lowercase": (
        arity: 1,
        fn: { state, args in
            guard case let .string(str) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_lowercase expects a string")
                )
            }
            state.setValue(.string(str.lowercased()))
        }
    ),

    "string_starts_with": (
        arity: 2,
        fn: { state, args in
            guard case let .string(str) = args[0],
                case let .string(prefix) = args[1]
            else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_starts_with expects two strings")
                )
            }
            state.setValue(
                str.hasPrefix(prefix) ? .tagged(tag: "True", inner: .empty) : .tagged(tag: "False", inner: .empty))
        }
    ),

    "string_ends_with": (
        arity: 2,
        fn: { state, args in
            guard case let .string(str) = args[0],
                case let .string(suffix) = args[1]
            else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_ends_with expects two strings")
                )
            }
            state.setValue(
                str.hasSuffix(suffix) ? .tagged(tag: "True", inner: .empty) : .tagged(tag: "False", inner: .empty))
        }
    ),

    // Binary data handling
    "string_to_binary": (
        arity: 1,
        fn: { state, args in
            guard case let .string(str) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_to_binary expects a string")
                )
            }
            state.setValue(.binary(Array(str.utf8)))
        }
    ),

    "string_from_binary": (
        arity: 1,
        fn: { state, args in
            guard case let .binary(bytes) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("string_from_binary expects binary data")
                )
            }
            if let str = String(bytes: bytes, encoding: .utf8) {
                state.setValue(.string(str))
            } else {
                state.setValue(.tagged(tag: "Error", inner: .empty))
            }
        }
    ),

    "binary_from_integers": (
        arity: 1,
        fn: { state, args in
            guard case let .list(list) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("binary_from_integers expects a list")
                )
            }
            var bytes: [UInt8] = []
            for value in list.array {
                guard case let .int(i) = value, i >= 0 && i <= 255 else {
                    throw UnhandledEffect(
                        label: "TypeMismatch",
                        payload: .string("binary_from_integers list must contain integers between 0 and 255")
                    )
                }
                bytes.append(UInt8(i))
            }
            state.setValue(.binary(bytes))
        }
    ),

    "binary_fold": (
        arity: 3,
        fn: { state, args in
            guard case let .binary(bytes) = args[0] else {
                throw UnhandledEffect(
                    label: "TypeMismatch",
                    payload: .string("binary_fold expects binary data as first argument")
                )
            }
            if bytes.isEmpty {
                state.setValue(args[1])
            } else {
                let head = bytes[0]
                let tail = Array(bytes.dropFirst())
                let nextFold = Value.partial(
                    arity: 3,
                    applied: Stack([.binary(tail), args[2]]),
                    impl: builtinTable["binary_fold"]!.fn
                )
                state.push(.call(nextFold, state.env))
                state.push(.call(args[1], state.env))
                state.push(.call(.int(Int(head)), state.env))
                state.setValue(args[2])
            }
        }
    )
]
