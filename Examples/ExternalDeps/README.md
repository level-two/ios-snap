# External Dependency Demos

These examples exercise the `--dep-scheme` and `--package/--product` flags introduced in Phase K.

## Layout

- `FrameworkDemo/` — Xcode framework project (`FrameworkDemo.framework`) with a simple SwiftUI view.
- `PackageDemo/` — SwiftPM package (`PackageFeature` dynamic library) that exports a SwiftUI view.
- `Snippets/` — Snippet files used by ios-snap to render the demo views.
- `Batch.yml` — Batch configuration that renders both demos in one run.

## Usage

Render the framework view:

```bash
ios-snap render \
  --device 'iPhone 15' \
  --snippet Examples/ExternalDeps/Snippets/FrameworkDemoSnapshot.swift \
  --project Examples/ExternalDeps/FrameworkDemo/FrameworkDemo.xcodeproj \
  --dep-scheme FrameworkDemo \
  --out screens/framework-demo.png
```

Render the SwiftPM package view:

```bash
ios-snap render \
  --device 'iPhone 15' \
  --snippet Examples/ExternalDeps/Snippets/PackageDemoSnapshot.swift \
  --package Examples/ExternalDeps/PackageDemo \
  --product PackageFeature \
  --out screens/package-demo.png
```

Batch both demos:

```bash
ios-snap batch --config Examples/ExternalDeps/Batch.yml
```

> The commands above assume `screens/` exists in the repo root (created during earlier phases).
