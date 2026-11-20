# Native runtime

The Swift wrapper retains its existing streaming and cancellation interface.
The native Apple Silicon library is built from Gradium Phonon 0.6.0, revision
`95bf24d1ca5e94f0f62abe588b1ccb6f093bcc9c`, with the merged sentence-grouping
change from [upstream pull request 326](https://github.com/gradium-ai/xn-ptts/pull/326).
Gradium's Core ML attention-window, activation and decoder-configuration
corrections are included. No model checkpoint or voice tensors were retrained.

- [Upstream source](https://github.com/gradium-ai/xn-ptts/tree/95bf24d1ca5e94f0f62abe588b1ccb6f093bcc9c)
- Source tarball SHA256: `0c49b01bc003ee4d71d13d1b01de7d16ffd1bf2609646e55c7f2d58c5da9f266`
- PR 326 diff SHA256: `94709891e40ba8cd47a48dd73eea69910a844abcefb9d0ba1dc1254ccabadfa1`
- Apply `ptts-english-sterling.patch` after PR 326 to correct UK currency in
  English speech and include the preprocessing regression tests.
- XCframework archive SHA256: `f796c41924fedc4d034912410e169ed0f0b1b5b7061c808a0e5bcdfef5950e57`

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
