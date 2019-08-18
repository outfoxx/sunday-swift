

project:=Sunday
comma:=,

clean:
	rm -rf TestResults

define buildtest
	xcodebuild -scheme $(project)-Package -resultBundleVersion 3 -resultBundlePath ./TestResults/$(1) -destination '$(2)' test
endef

build-test-all:	
	$(call buildtest,macOS,platform=macOS)
	$(call buildtest,iOS,platform=iOS Simulator$(comma)OS=13.0$(comma)name=iPhone 8)
	$(call buildtest,tvOS,platform=tvOS Simulator$(comma)OS=13.0$(comma)name=Apple TV)
