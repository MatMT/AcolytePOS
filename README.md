# AcolytePOS

Flutter POS for parish / youth snacks — natural-language orders + giant **vuelto**.

Works **offline** (local Spanish parser). Optional Gemini via `--dart-define=GEMINI_API_KEY=...`.

## Run

```bash
flutter pub get
flutter run
```

With Gemini:

```bash
flutter run --dart-define=GEMINI_API_KEY=YOUR_KEY
```

## Demo phrases

- `2 semitas y un café, me pagaron con uno de 5`
- `una soda y un churro, pagué con 2`
- `3 cafés y pan, con un billete de 5`
