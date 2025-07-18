source := "Sources/"

format:
    swift-format -r {{source}} --in-place

lint: # this should only be run on compiled code (SwiftLint is designed to analyze valid source code that is compilable)
    swiftlint {{source}} --autocorrect --fix

check: format lint

clean:
    swift package clean

build:
    swift build

test:
    swift test

run:
    swift run EygRunner

run-release:
    swift run -c release EygRunner
