# onchain_proto

Dart code generators for the OnChain ecosystem, plus the proto-compiler
runtime shared by the per-chain builders.

## Generators (`lib/`)

| Input | Generator | Output |
|---|---|---|
| Protocol Buffers (`.proto`) | `lib/proto/` (`ProtoCompiler`, `ProtoCodegenTarget`, `ProtoPackageWriter`) | Dart message classes with JSON + binary serialization |
| OpenAPI 3.x / OpenRPC 1.x (`.json`) | `lib/open_api/openapi_generator.dart` (`generate(...)`; OpenRPC is normalized via `openrpcToOpenapi` first) | Immutable models (`class`), `sealed` unions, real `enum`s, `typedef` aliases, per-endpoint request wrappers |
| Candid (`.did`, Internet Computer) | `lib/did_gen/` (`generateCandid(...)`) | `src/types.dart` + `src/queries.dart` / `src/updates.dart` per `.did` file |

Import the one you need directly, e.g.:

```dart
import 'package:onchain_proto/open_api/openapi_generator.dart';
import 'package:onchain_proto/did_gen/did.dart';
import 'package:onchain_proto/onchain_proto.dart'; // proto compiler runtime
```

## Examples (`example/`)

Bundled specs under `example/specs/` (`openapi/`, `did/`) with a batch
harness:

```sh
dart run example/generate_example.dart        # all specs
dart run example/generate_example.dart inch   # one spec
```

Outputs go to `example/generated/<stem>/types.dart` (OpenAPI) and
`example/generated/did/` (Candid). The OpenAPI outputs analyze clean.
The DID outputs target the On_chain ICP runtime
(`package:on_chain/icp/...` via `--types-import`, same as
`On_chain/did/builder.dart`), so `example/generated/did/**` is excluded
from `dart analyze`; it exists to prove the generator runs.

## Per-chain builders (outside this package)

These consume the runtime above and stay in their own repos:

- `On_chain/proto/{sui,tron,hedera}/builder.dart` + `On_chain/did/builder.dart`
- `cosmos_sdk/proto/builder.dart`
- `zcash_dart/proto/builder.dart`
