

project:=Sunday
comma:=,

clean:
	rm -rf TestResults

define buildtest
	xcodebuild -scheme $(project)-Package -resultBundleVersion 3 -resultBundlePath ./TestResults/$(1) -destination '$(2)' test
endef

build-test-macos:
	$(call buildtest,macOS,platform=macOS)

build-test-ios:
	$(call buildtest,iOS,platform=iOS Simulator$(comma)name=iPhone 12)

build-test-tvos:
	$(call buildtest,tvOS,platform=tvOS Simulator$(comma)name=Apple TV)

build-test-all: build-test-macos build-test-ios build-test-tvos
