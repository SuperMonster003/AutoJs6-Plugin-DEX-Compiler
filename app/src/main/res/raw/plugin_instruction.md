# AutoJs6 DEX Compiler

This plugin compiles one normalized JAR with D8 8.13.17 and returns a bounded ZIP containing contiguous `classes*.dex` entries.

The plugin requires host build 5270 or later and Android API 24 or later.

Safety and operational limits:

- Only the same-signature AutoJs6 host may bind the compiler service.
- The input size, SHA-256, ZIP framing, entry paths, compression ratios, and class files are checked again before compilation.
- Output is limited to 16 MiB and 64 contiguous indexed DEX entries.
- Cancellation stops output publication, but D8 may continue until its current compilation returns.
- The host independently validates the returned DEX ZIP before caching or loading it.
- The plugin requests no storage or network permission.
