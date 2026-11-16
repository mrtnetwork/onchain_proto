## 0.3.0
- Unified OpenAPI/OpenRPC generator (latest, incl. `openrpcToOpenapi`) now lives at `lib/open_api/openapi_generator.dart`; removed stale `open_rpc.dart` split and `lib/new/` duplicates.
- DID client (`did_gen`): fixed `onResponse` for `List` / list-of-objects — `decodeOneTyped` results are now normalized with `valueAsList` and converted element-wise instead of `as`-casting (which throws); vec-of-class args now encode via `candidValue`; anonymous nested records resolve to their lifted class ctype.
- Package scope is now proto + OpenAPI/OpenRPC + Candid; bundled runnable specs under `example/specs/` with `example/generate_example.dart`.

## 0.2.0
- Update dependencies.


## 0.1.0
- Initial version.
