# Native runtime

The Swift wrapper retains its existing streaming and cancellation interface.
The native Apple Silicon library is built from Gradium Phonon 0.6.0, revision
`95bf24d1ca5e94f0f62abe588b1ccb6f093bcc9c`, with the merged sentence-grouping
change from [upstream pull request 326](https://github.com/gradium-ai/xn-ptts/pull/326).
Gradium's Core ML attention-window, activation and decoder-configuration
corrections are included. No model checkpoint or voice tensors were retrained.

- [Upstream source](https://github.com/gradium-ai/xn-ptts/tree/95bf24d1ca5e94f0f62abe588b1ccb6f093bcc9c)
- Source tarball SHA256: `0c49b01bc003ee4d71d13d1b01de7d16ffd1bf2609646e55c7f2d58c5da9f266`
- PR 326 patch SHA256: `bbfb91b866b84c0c11917b00cb5215159ac431f63cdbefd3095a7ee46ea9bbf2`
- XCframework archive SHA256: `8dbd8723ae41da9a7ae05579d8f6dc42b95fe322f2b55089d7fc7fef182f5349`

The library contains arm64 macOS and iOS device slices, built with Rust 1.98.1
from the locked dependency graph. Build `ptts-ffi` for
`aarch64-apple-darwin` and `aarch64-apple-ios`, then use `xcodebuild
-create-xcframework` with `ptts-ffi/include/ptts.h` and a `PhononCore` module map.
The supported deployment targets remain macOS 15 and iOS 18.

The multilingual Core ML export uses 200-token prefill, 50-token sentence
grouping, context 1200, maximum 859 frames and Mimi window 250. The tokenizer
and voice tensors are unchanged. Keep `bundle.json` with the model resources;
its file hashes and original accented display names must be preserved. Stored
voice filenames remain ASCII to survive installation across filesystems.

Local wrapper changes verify and stage bundled models before replacement,
restore the previous directory if the replacement move fails, and preserve a
matching export's compiled cache. They do not change the public speech API.
Upstream and dependency licence notices are in `Resources/Licenses`.
