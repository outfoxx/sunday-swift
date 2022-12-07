
project:=Sunday
comma:=,

default: clean build-test-all

clean:
	rm -rf TestResults
	rm -rf .derived-data

make-test-results-dir:
	mkdir -p TestResults

define buildtest
	set -o pipefail && xcodebuild -scheme $(project)-Package -derivedDataPath .derived-data/$(1) -resultBundleVersion 3 -resultBundlePath ./TestResults/$(1) -destination '$(2)' -enableCodeCoverage=YES -enableAddressSanitizer=YES -enableThreadSanitizer=YES -enableUndefinedBehaviorSanitizer=YES test | xcbeautify
endef

build-test-macos:
	$(call buildtest,macOS,platform=macOS)

build-test-ios:
	$(call buildtest,iOS,platform=iOS Simulator$(comma)name=iPhone 13)

build-test-tvos:
	$(call buildtest,tvOS,platform=tvOS Simulator$(comma)name=Apple TV)

build-test-watchos:
	$(call buildtest,watchOS,platform=watchOS Simulator$(comma)name=Apple Watch Series 7 (45mm))

build-test-all: build-test-macos build-test-ios build-test-tvos build-test-watchos

format:	
	swiftformat --config .swiftformat Sources/ Tests/

lint: make-test-results-dir
	swiftlint lint --reporter html > TestResults/lint.html

view_lint: lint
	open TestResults/lint.html
