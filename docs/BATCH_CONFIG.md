# Batch Config

YAML schema for `ios-snap batch --config <file.yml>`.

## Schema
```yaml
scenes:               # required
  - id: <string>      # arbitrary label for reporting
    imports: [<string>]
    expr: <string>    # snippet-mode only
    scene: <string>   # registry-mode only
    project: <path.xcodeproj>     # Phase K: optional
    workspace: <path.xcworkspace> # Phase K: optional
    dep_schemes: [<string>]       # Phase K: optional list of schemes to prebuild/link
    packages: [<path>]            # Phase K: optional list of SwiftPM package roots
    products: [<string>]          # Phase K: optional list of SwiftPM product names
    variants:         # required (≥1)
      - device: <string>
        udid: <string>             # optional, overrides device
        appearance: <light|dark|auto>
        content_size: <XS|...>
        locale: <xx-YY>
        region: <REGION>
        orientation: <portrait|landscape>
        background: <#RRGGBB|clear>
        status_bar: <string>
        wait: <float>
        scale: <2|3>
        size: "W x H"            # optional absolute points
        out: <path.png>           # required
        project: <path.xcodeproj>     # Phase K: optional override
        workspace: <path.xcworkspace> # Phase K: optional override
        dep_schemes: [<string>]       # Phase K: optional override
        packages: [<path>]            # Phase K: optional override
        products: [<string>]          # Phase K: optional override

global:              # optional defaults
  appearance: dark
  content_size: L
  wait: 0.25
```

## Validation Rules
- Each variant must specify `out` and either `device` or `udid`.
- For snippet scenes: provide `imports` + `expr` or `snippet`.
- For registry scenes: provide `scene`.

## Notes
- Paths in `imports`, `snippet`, `project`, `workspace`, `packages`, and `out` expand `~` and resolve relative to the directory containing the config file.
- `global` defaults merge into each scene/variant before invoking the render pipeline.
- Use `ios-snap batch --continue-on-error` to run remaining variants after a failure; the exit code reflects the first failure.
- `Examples/Snapshots.yml` demonstrates a mixed snippet/registry batch targeting the `screens/` output directory.
- `Examples/ExternalDeps/Batch.yml` showcases building an Xcode framework (`dep_schemes`) and SwiftPM package (`packages` + `products`) before rendering.

