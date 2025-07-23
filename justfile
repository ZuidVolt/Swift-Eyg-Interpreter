source := "Sources/"

format:
    swift-format -r -p {{source}} --in-place

lint: # this should only be run on compiled code (SwiftLint is designed to analyze valid source code that is compilable)
    swift-format lint -r -p {{source}}
    swiftlint {{source}} --autocorrect --fix

check: format lint

clean:
    swift package clean

build-runner:
    swift build -c release --product EygRunner

hello-example:
    cat Sources/EygRunnerTest/examples/hello.json | .build/arm64-apple-macosx/release/EygRunner

test:
    swift test

run:
    swift run EygRunnerTest

release:
    swift run -c release EygRunnerTest \
    -Xswiftc -whole-module-optimization \
    -Xswiftc -cross-module-optimization \
    -Xcc -march=native \
    -mtune=native \
    -Xcc -O3
