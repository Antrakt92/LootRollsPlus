# Changelog

## 1.3.4 — 22-Nov-2026 — Loot history and inspection fixes

- Recover missing drops and updated winners after incomplete loot history responses.
- Avoid inspecting the wrong player when names are ambiguous and discard expired inspection results.
- Recover player classes from linked names in Dungeon Quest Atlas history.
- Keep the expanded raid roster clear of loot prompts at the edge of the screen.
- Restore delayed Mastercraft disenchant estimates and recognize Chinese price labels.

## 1.3.3 — 20-Nov-2026 — Roll updates and equipment comparisons

- Recover live rolls and history after delayed game updates. Keep canceled rolls hidden when the live panel is toggled, and keep repeated chat results from spilling into the next roll for the same item.
- Preserve full player names when importing history and use them to find eligible group members for inspection.
- Retry equipment comparisons when inspection or item data is temporarily busy. Stack the two tooltips when the game window is too narrow to fit them side by side.

## 1.3.2 — 19-Nov-2026 — AddOns list

- Show Loot Rolls Plus under Antrakt92 in the in-game AddOns list.

## 1.3.1 — 18-Nov-2026 — Loot history and live panels

- Keep ambiguous names out of My wins and recover confirmed results when the game briefly returns incomplete or outdated loot data.
- Keep canceled rolls from reappearing and avoid inspecting a player by name when the game hides the winner's identity.
- Use verified player levels for live armor warnings and reposition roll panels when the game window changes size.
- Show when item data is unavailable instead of leaving the tooltip stuck on Loading.

## 1.3.0 — 17-Nov-2026 — My wins in History

- Filter a day's loot history to the items your current character won.

## 1.2.1 — 16-Nov-2026 — Roll results and panel placement

- Keep back-to-back rolls on identical items separate. Preserve known roll numbers when the game temporarily hides them and clear old numbers when the choice changes.
- Recover late winners in History after a reload, import older records even when the original history has gaps, and hide the scrollbar when all rows fit.
- Keep roll panels, expanded raid lists and equipment tooltips clear of nearby loot buttons and Pawn when space allows. Shorten the visible raid list on crowded screens while keeping every player accessible by scrolling.
- Refresh Mastercraft's disenchant estimate when item data finishes loading. Retry incomplete two-slot equipment checks for winners while preserving earlier gear if a known slot changed.

## 1.2.0 — 15-Nov-2026 — Equipment slots and roll tracking

- Click the equipped item tooltip to switch between two matching slots when both are known.
- Preserve saved equipment when the game confirms a roll. Label gear inspected now and retry the winner when an earlier Need inspection could not finish.
- Keep live votes and equipment attached to the right roll and player when events arrive late, rolls are canceled, or identical items drop together.
- Move live roll panels and equipment tooltips away from Pawn and nearby loot prompts when space allows. Use vertical space when neither side can fit the roll panel.

## 1.1.2 — 15-Nov-2026 — Loot roll panel placement

- Place live roll panels to the left of the loot prompt when there is room, leaving space for Pawn’s comparison on the right.
- Keep the expanded raid list beside the left panel or above or below it when space is tight.

## 1.1.1 — 15-Nov-2026 — Duplicate loot rolls

- Fix duplicate rows marked “Overlapping rolls” when the loot prompt and the game’s loot history report the same drop at different times.

## 1.1.0 — 15-Nov-2026 — Saved equipment comparisons

- Save matching equipment when a player who chooses Need or wins a recent drop can be inspected. Open the roll later in History to see the saved item.
- Open History and Options inside the roll window. Resize the window once and use the same height across all views.
- Restore a hidden window from Settings → AddOns → Loot Rolls Plus or with `/lrplus show`.
- Place warning dots next to the roll result and show the Loot Rolls Plus icon in game.

## 1.0.0 — 15-Nov-2026 — First Loot Rolls Plus release

- See Need, Greed and Pass as the game reports them. Party panels show individual choices, and raid panels open a scrollable breakdown for each drop.
- See class icons and colors, confirmed winners, and warning dots for unusual armor or equipment a class cannot use.
- Click a player in a live roll to see the item in the matching equipped slot. Click a saved roll for side-by-side item tooltips.
- Keep per-character loot history grouped by dungeon or raid visit. Import existing per-character history from Loot Rolls Inspector.
- Show available Vendor, Auctionator and Mastercraft values on the dropped item in comparisons.
- Preview group and raid panels with `/lrplus demo party` and `/lrplus demo raid`.

## Loot Rolls Inspector upstream history

## 1.2.2

### English
- Updated the interface version (16001) for the official launch client, so the addon no longer shows as "Incompatible".

### Español
- Actualizada la versión de interfaz (16001) para el cliente del lanzamiento oficial, para que el addon ya no aparezca como "Incompatible".

## 1.2.1

### English
- Fixed item icons not showing (question mark instead) since the official launch: the addon now uses the newer `C_Item` API, with the old functions kept as fallback.

### Español
- Corregido que los iconos de los objetos no aparecieran (salía una interrogación) desde el lanzamiento oficial: el addon usa ahora la API `C_Item`, manteniendo las funciones antiguas como alternativa.

## 1.2.0

### English
- New **Options** panel: open it with the "Options" button in the window or with `/lri config`.
- New option: hide the window automatically when you are not in a group (it shows again when you join a party or raid).
- Loot history is now saved **per character**. Settings (window position, options, days kept) are still shared across the account.
- Your existing history is moved to the first character you log in with after updating.
- Note: restart the game fully after updating (`/reload` is not enough).

### Español
- Nuevo panel de **Opciones**: se abre con el botón "Opciones" de la ventana o con `/lri config`.
- Nueva opción: ocultar la ventana automáticamente cuando no estás en grupo (vuelve a aparecer al entrar en un grupo o banda).
- El historial de loot ahora se guarda **por personaje**. Los ajustes (posición de la ventana, opciones, días guardados) siguen siendo comunes a toda la cuenta.
- El historial que ya tenías pasa al primer personaje con el que entres tras actualizar.
- Nota: reinicia el juego del todo tras actualizar (`/reload` no basta).

## 1.1.0
- Initial public release / Primera versión pública.
