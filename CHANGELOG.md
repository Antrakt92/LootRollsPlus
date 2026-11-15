# Changelog

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
