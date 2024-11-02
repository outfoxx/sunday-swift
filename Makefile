
project:=Sunday
comma:=,

default: clean build-test-all

check-tools:
	@which xcbeautify || (echo "xcbeautify is required. run 'make install-tools'" && exit 1)

install-tools:
	brew install xcbeautify

clean:
	@rm -rf TestResults
	@rm -rf .derived-data

make-test-results-dir:
	mkdir -p TestResults

define buildtest
	rm -rf ./TestResults/$(1)
	set -o pipefail && \
		xcodebuild -scheme $(project)-Package \
		-derivedDataPath .derived-data/$(1) -resultBundleVersion 3 -resultBundlePath ./TestResults/$(1) -destination '$(2)' \
		-enableCodeCoverage=YES -enableAddressSanitizer=YES -enableThreadSanitizer=YES -enableUndefinedBehaviorSanitizer=YES \
		-clonedSourcePackagesDirPath ${PWD}/.xcode-pkgs -packageCachePath ${PWD}/.xcode-pkgs/_cache_ \
		-skipMacroValidation \
		test | xcbeautify
endef

build-test-macos: check-tools
	$(call buildtest,macos,platform=macOS)

build-test-ios: check-tools
	$(call buildtest,ios,platform=iOS Simulator$(comma)name=iPhone 16)

build-test-tvos: check-tools
	$(call buildtest,tvos,platform=tvOS Simulator$(comma)name=Apple TV)

build-test-watchos: check-tools
	$(call buildtest,watchos,platform=watchOS Simulator$(comma)name=Apple Watch Series 10 (46mm))

build-test-visionos: check-tools
	$(call buildtest,visionos,platform=visionOS Simulator$(comma)name=Apple Vision Pro)

build-test-all: build-test-macos build-test-ios build-test-tvos build-test-watchos

format:	
	swiftformat --config .swiftformat Sources/ Tests/

lint: make-test-results-dir
	swiftlint lint --reporter html > TestResults/lint.html

view_lint: lint
	open TestResults/lint.html
