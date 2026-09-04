# PERF_NUI — sanctuary_crafting v2.29.0

## Architecture

The Craft / Carnet NUI is **vanilla JS** (`web/dist/app.js`, `book.js`, `tracker.js`, `pins-hud.js`) — **not React**.
Do not introduce `React.memo` / `useMemo` / `react-window`. Equivalent patterns: avoid full DOM rebuilds, throttle timers, debounce search, lazy images, pause work when closed, cheaper CSS on lists.

## Before (v2.28.0 bottlenecks)

1. **`selectRecipe()` → `renderList()`** wiped `#recipe-grid` and rebuilt every recipe card + Favoris/Récents strips on every selection (largest lag source).
2. **Search** `#search` called `renderList()` on every keystroke (no debounce).
3. **`runProgress`** used `requestAnimationFrame` at ~60 fps for craft bar DOM writes.
4. **`setInterval(tickFilePanel, 500)`** ran forever, even with the craft menu closed.
5. **Favorite toggle** always called full `refresh()` → `getMenu` payload + full apply.
6. **Catalog images** loaded eagerly (`bindItemImg` without `loading=lazy`).
7. **CSS** stacked box-shadows / filters on every `.recipe-card` (expensive in dense grids).
8. **Audio** `new Audio()` per `playUi` / book SFX.
9. Book shell already stayed mounted (anti-flicker) — kept; late page paints could still run after close.

## After (v2.29.0 shipped)

| Area | Change |
|------|--------|
| Selection | `syncSelectionInList(id)` toggles `.selected` only; detail panel updates as before. Full `renderList()` only on filter/search/category/sort/data changes (or shortcut that clears filters). |
| Search | 200 ms debounce; immediate rebuild when cleared. |
| Progress | DOM paint throttled to ~10 Hz (`PROGRESS_HZ_MS = 100`); end timeout keeps `finishCraft` accurate even if menu closed; rAF cancelled when craft menu closed (tracker still owns visible progress). |
| Idle | `tickFilePanel` interval started on open / cleared on close; gated with `state.open`. Book `setPages` no-ops when `!state.open`. |
| Images | `loading=lazy` + `decoding=async` on catalog / fav / recent cards; detail image stays eager. `IMG_BASE` unchanged. |
| Favorites | `toggleFavoriteLocal` patches `state.favorites` from callback (`favored` + `favorites[]`); updates stars / fav strip without `getMenu`. |
| Filter memo | `filteredRecipes()` caches by filter+search+category+sort+rarity+material+recipesVersion+favorites. |
| CSS | Append-only v2.29.0 overrides: lighter shadows on non-selected cards, no backdrop-filter on cards, selected accent preserved. |
| Audio | Pooled / reused `Audio` elements in craft `playUi` and book `playBookSound`. |
| Lua | `toggleFavorite` returns `{ ok, favored, favorites }` for client patch. |

## Deferred / residual risks

- **Full catalog virtualization** (mount only viewport + buffer when `> ~48` recipes): deferred — layout has grouped strips (Favoris / Récents / Nouveaux / Catalogue) with fixed card sizing; risky without a dedicated scroll host pass. Prefer selection/debounce/progress first (done).
- **Lua inventory delta → recipe feasibility patch without `applyMenu` wipe**: delta path already exists client-side for inventory notify; full recipe feasibility patch without wipe not expanded in this pass.
- **Progress ticks**: confirmed no full recipe list on craft progress NUI messages (duration/step only).
- **Tracker / pins drag**: already persist position on `mouseup` / `pointerup` only (not every `mousemove`) — unchanged.
- **Book**: texture backgrounds remain CSS variables (`--mainPageTexture` etc.); not reassigned on page flip. Whole book shell stays mounted.

## Qualitative before/after

- Selecting a recipe: no full catalog DOM rebuild (class toggles + detail paint).
- Typing in search: at most one list rebuild per 200 ms.
- Craft bar: ~8–10 width/label updates per second while menu open; quiet when closed.
- Closed menu: no file-panel interval; book async paints dropped.

## Debug

Gate console noise behind `Config.Debug` / existing flags (unchanged). Avoid new always-on `console.log` in hot paths.
