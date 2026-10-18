# Test dependencies are isolated from distributable APKs

The production `app/pubspec.yaml` does not contain `integration_test`, SQLite FFI,
or private photograph assets. All normal unit/widget tests run with `flutter test`.

The native SQLite persistence regression needs the desktop FFI implementation:

```sh
python3 tools/run_flutter_qa.py host
```

Real OCR acceptance requires an Android device and the two original photographs:

```sh
python3 tools/run_flutter_qa.py android --device DEVICE_ID \
  --photos /private/receipts --evidence /private/receipt-real-evidence.json
```

That directory must contain `vertical.jpg` and `rotated.jpg`. Missing files fail;
unit tests never count as real ML Kit acceptance. Expected numbers are used only
for scoring. The existing test checks both actual OCR outputs and the Android form.

The runner copies app sources to a temporary workspace, adds **only** the required
QA dependency and, for Android, private test assets. It never modifies the source
manifest, app lockfile, production dependencies or distributed APK. Temporary files
are removed on exit. Do not run this command to produce distributable artifacts.
Private photographs are never committed. Evidence contains recognized text, so
review it before sharing. Android tests require the same SDK/JDK as the app.

QA lockfiles pin their separate dependency graphs. To update one intentionally,
remove that QA lockfile and run its test command; review the newly generated lock.
