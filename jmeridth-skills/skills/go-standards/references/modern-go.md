# Modern Go Idioms

When the module's `go.mod` declares Go 1.26 or newer, every idiom below is available. `golangci-lint`'s `modernize` analyzer flags most of these on changed lines in CI, and `go fix ./...` rewrites them mechanically; `go fix -diff ./...` from a module prints what is left and exits non-zero if anything remains. Check the declared Go version before flagging an idiom the toolchain doesn't support yet.

If the repo's `.golangci.yml` disables the `newexpr` and `omitzero` modernizers, the pointer-helper rule below is enforced only by review, and the `omitzero` rewrite is deliberately not applied.

## `errors.AsType` Instead of `errors.As`

`errors.AsType[E](err)` returns the matched value and a boolean. It needs no pre-declared target variable, cannot panic on a bad target type, and uses a plain type assertion where `errors.As` uses reflection (about 7x faster, zero allocations).

✅ **Correct:**

```go
if re, ok := errors.AsType[*awshttp.ResponseError](err); ok {
    return re.HTTPStatusCode()
}
if _, ok := errors.AsType[*http.MaxBytesError](err); ok {
    http.Error(w, "body too large", http.StatusRequestEntityTooLarge)
}
```

❌ **Wrong:**

```go
var re *awshttp.ResponseError
if errors.As(err, &re) {
    return re.HTTPStatusCode()
}
```

**Leave alone:** the type parameter must satisfy `error`. An anonymous interface without `Error()`, such as `interface{ ExitStatus() int }`, does not compile as `AsType[interface{ ExitStatus() int }]`; keep `errors.As` there. Do not add `error` to the interface just to force the rewrite.

## `strings.Cut` Family Instead of `Split`/`Index` Arithmetic

Use `strings.Cut`, `CutPrefix`, `CutSuffix` (and the `bytes` equivalents) when a string is split once. Use `strings.SplitSeq` or `FieldsSeq` when the pieces are only ranged over, so no intermediate slice is built.

✅ **Correct:**

```go
name, _, _ := strings.Cut(tag, ",")
if rest, ok := strings.CutPrefix(key, prefix); ok { use(rest) }
for line := range strings.SplitSeq(string(body), "\n") { handle(line) }
```

❌ **Wrong:**

```go
name := strings.SplitN(tag, ",", 2)[0]
if strings.HasPrefix(key, prefix) { use(key[len(prefix):]) }
for _, line := range strings.Split(string(body), "\n") { handle(line) }
```

**Leave alone:** keep `strings.Split` when the slice itself is needed (indexed, measured with `len`, sorted, or passed on).

## `new(expr)` Instead of Pointer Helpers

Starting with [Go 1.26](https://go.dev/doc/go1.26#language), `new` accepts an expression and returns a pointer to a fresh variable initialized to its value. `new(true)` points to `true`; `new(false)` is a non-nil pointer to `false`. The existing `new(T)` form still allocates a zero-valued variable of type `T`. Check the governing `go.mod` and any applicable per-file Go version build constraint before using the expression form in a module that targets an earlier language version.

Use `new(expr)` for optional proto, SDK, and JSON fields instead of `proto.String(x)`, `github.Ptr(x)`, `aws.String(x)`, or a local `ptr` helper. Do not define new generic `func ptr[T any](v T) *T` helpers; delete a local one once its last call site is inlined. Preserve types: `new(10)` is `*int`, while `new(int32(10))` is `*int32`. Preserve aliasing: `new(x)` allocates a fresh variable and is not equivalent to `&x` when callers must share the original variable.

✅ **Correct:**

```go
req := &pb.Request{Name: new("x"), Limit: new(int32(10)), Force: new(true)}
```

❌ **Wrong:**

```go
func ptr[T any](v T) *T { return &v }

req := &pb.Request{Name: proto.String("x"), Limit: ptr(int32(10)), Force: github.Ptr(true)}
```

## Promoted Fields in Composite Literals

A struct literal may set a promoted field directly instead of nesting a literal for the embedded type. Flatten the literal when it only sets promoted fields.

✅ **Correct:**

```go
cfg := Config{Issuer: issuer, Audience: aud, Out: &buf}
```

❌ **Wrong:**

```go
cfg := Config{Impl: Impl{Issuer: issuer, Audience: aud, Out: &buf}}
```

**Leave alone:** when the nested literal is assigned to a variable or reused, or when a single-line nested literal contains a further nested literal (`ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{...}}`); rewrite those by hand or not at all.

## `slices.Backward` for Reverse Iteration

✅ **Correct:**

```go
for i, item := range slices.Backward(items) { visit(i, item) }
```

❌ **Wrong:**

```go
for i := len(items) - 1; i >= 0; i-- { visit(i, items[i]) }
```

The compiler inlines the iterator, so there is no runtime cost. Deleting `items[i]` inside the loop is safe in both forms because earlier indices are unaffected.

## `slices`, `maps`, and Builtins Instead of Hand-Written Loops

- Membership and lookup: `slices.Contains`, `slices.ContainsFunc`, `slices.Index`, `slices.IndexFunc`.
- Sorting: `slices.Sort`, `slices.SortFunc`, `slices.SortStableFunc` instead of `sort.Slice` (no reflection, no closure allocation).
- Map keys and values: `slices.Sorted(maps.Keys(m))`, `slices.Collect(maps.Values(m))`.
- Clamping: builtin `min`/`max` instead of if/else assignment.
- Wait groups: `wg.Go(func() { ... })` instead of `wg.Add(1)` plus a goroutine that defers `wg.Done()`.

## Do Not Rewrite `omitempty` to `omitzero` Mechanically

`omitzero` changes what is written on the wire for struct-typed fields such as `time.Time`. Make that change only as a deliberate, reviewed behavior change with a test; never as part of a modernization pass.

## Audit

Search `.go` files for:

- `errors\.As\(` — candidate for `errors.AsType` unless the target is an anonymous non-`error` interface.
- `SplitN\(.*, 2\)`, `Split\(.*\)\[0\]`, `HasPrefix\(.*\)\s*\{[^}]*\[len\(` — candidates for the `Cut` family.
- `func \w+\[T any\]\(v T\) \*T`, `proto\.(String|Bool|Int32|Int64)\(`, `\.Ptr\(` — candidates for `new(expr)`.
- `for \w+ := len\(.*\) - 1; .*--` — candidate for `slices.Backward`.
- `sort\.Slice\(` — candidate for `slices.SortFunc`.
- `omitzero` in a diff that also contains other mechanical rewrites — flag as an unintended behavior change.

Then run `go fix -diff ./...` from the module: an empty diff confirms nothing mechanical remains.
