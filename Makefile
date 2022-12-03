
project:=Sunday
comma:=,

default: clean build-test-all

clean:
	rm -rf TestResults
	rm -rf .derived-data

make-test-results-dir:
	mkdir -p TestResults

define buildtest
	xcodebuild -scheme $(project)-Package -derivedDataPath .derived-data/$(1) -resultBundleVersion 3 -resultBundlePath ./TestResults/$(1) -destination '$(2)' -enableCodeCoverage=YES -enableAddressSanitizer=YES -enableThreadSanitizer=YES -enableUndefinedBehaviorSanitizer=YES test
endef

build-test-macos:
	$(call buildtest,macOS,platform=macOS)

build-test-ios:
	$(call buildtest,iOS,platform=iOS Simulator$(comma)name=iPhone 13)

build-test-tvos:
	$(call buildtest,tvOS,platform=tvOS Simulator$(comma)name=Apple TV)

build-test-all: build-test-macos build-test-ios build-test-tvos

format:	
	swiftformat --config .swiftformat Sources/ Tests/

lint: make-test-results-dir
	swiftlint lint --reporter html > TestResults/lint.html

view_lint: lint
	open TestResults/lint.html
