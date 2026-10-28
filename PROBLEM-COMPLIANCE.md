# RFC 9457 standard members

`GenericProblem` and regenerated custom Problems ignore null and wrong JSON categories for `type`, `title`, `status`, `detail`, and `instance`. Normalization runs before decoding, validation, defaults, and registered subtype selection. Correctly typed semantic errors remain errors; fractional status values are never truncated.

`Problem.title` and `Problem.status` are now optional. Update custom conformances, initializers, status helpers, and code that assumed these values were present. Standalone `{}` decodes to `about:blank` with absent optional members. Encoders omit absent standard members while preserving empty title/detail strings and nullable extension values.

`ProblemDecoding.normalized(_:)` provides a scoped decoder view for generated/custom implementations. It forwards the configured decoder, coding path, and user info for real values, and leaves nested extension decoders unchanged. `ProblemDecoding.contextualJSON` preserves extension numeric lexemes when HTTP transport supplies absent status and about:blank titles. A valid body status takes precedence over HTTP status. GenericProblem's dictionary-based initializers now throw to preserve correctly typed decoding failures.

## URI representation

`type: String` and `instance: String?` preserve the original URI reference, including empty and relative references. `typeURI: URL?` and `instanceURI: URL?` provide Foundation URL convenience views when a reference is representable. These accessors return nil for empty references. A URL-taking `GenericProblem` initializer remains available as a convenience. Update custom conformances and code that used URL-specific members to use the optional accessors.

Regenerated Problems require Sunday Swift 2.0.0-beta.18 or later. The companion Generator adopts String URI storage and optional title/status. Ordinary models and extension validation retain their authored behavior.

Reference: [RFC 9457 §3.1](https://www.rfc-editor.org/rfc/rfc9457.html#section-3.1).
