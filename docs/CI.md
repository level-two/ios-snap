# CI Setup (GitHub Actions)

```yaml
name: ios-snap
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s "/Applications/Xcode.app"
      - name: Build CLI
        run: swift build -c release
      - name: Self‑tests
        run: |
          mkdir -p screens
          Scripts/selftest.sh
      - name: Upload Screens
        uses: actions/upload-artifact@v4
        with:
          name: screens
          path: screens
```

Tips:
- Pre‑create a simulator for speed, or let the tool create on demand.
- Cache DerivedData if builds are heavy.

