# AcolytePOS AI — UI mock spec

Source: HTML/Tailwind prototype pasted by Mateo (Parroquia San Juan Bosco kiosk). Not a running Flutter screen — implement in `lib/main.dart`.

## Layout (top → bottom)
1. **Header** — AcolytePOS + green pill `AI Activo`; subtitle `Parroquia San Juan Bosco - Kiosco Parroquial`
2. **AI bar** — orange Dictar/mic button + NL text field (Asistente IA)
3. **Catalog** — label `Tocar para Sumar (+1)` + count badge; **2×2 large cards**:
   - Semita de Piña $0.40
   - Café Caliente $0.50
   - Soda / Gaseosa $0.75
   - Churro / Snack $0.35
   Each card shows live `Cant` and +1
4. **Payment card** — `Total a Cobrar` | `Pagó con`
5. **Tender row** — Exacto, $1, $2, $5, $10
6. **Vuelto panel** (dark green) — `Entregar Cambio / Vuelto` + giant amount; optional bill/coin breakdown
7. **Actions** — `Confirmar Venta y Cobrar` (primary); `Nueva Orden` (secondary)

## Colors
- Surface `#f7f9fb`
- Primary `#00236f` / container `#1e3a8a`
- Secondary (mic/tender accent) `#904d00` / `#fe932c`
- Tertiary (vuelto) `#003120` / `#004a32` with light fixed text

## Scope
Venta Rápida only. Bottom nav (Caja, Historial, Config IA) is post-MVP — do not block on it.

## Logic to keep
Local Spanish NL parser (no API key); optional Gemini via `--dart-define=GEMINI_API_KEY=...`.
