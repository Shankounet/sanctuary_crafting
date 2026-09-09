# Mystery / unknown recipe visibility

`ml_skills` remains the **only** unlock source of truth (`HasUnlockedSkill`, failClosed from PR #98).
This feature only changes **what the player sees** while a skill gate is locked.

## Player visual states

| State | When | Catalogue |
|-------|------|-----------|
| **UNKNOWN** | `skillVisibility = mystery_until_unlocked` + skill locked | `???`, mystery silhouette (not a padlock), darker incomplete contour, clickable |
| **DISCOVERED_LOCKED** | `visible_locked` / `discovered_locked` + skill locked | Real label/image, cannot craft |
| **UNLOCKED / APPRIS** | Skill unlocked (or no skill gate) | Full data; craftable if other gates ok |

French copy (player):

- Title: `???`
- Subtitle: `Connaissance inconnue`
- Description: `Cette fabrication reste inconnue.`
- Ingredients: `INGRÉDIENTS ???`
- CTA: `VOIR DANS LES SAVOIRS →` → client `OpenSkillTree(categoryUid)` only (no invented node focus)

## skillVisibility modes

- `visible_locked` (default) — shown locked with real data
- `hidden_until_unlocked` — omitted from menu while locked
- `mystery_until_unlocked` — shown as UNKNOWN ???
- `discovered_locked` — real label/image, locked until unlock

Optional `mysteryMode`:

- `full` — hide skill name too (default for secrets / `mystery_until_unlocked`)
- `recipe_only` — show SAVOIR REQUIS category label (default for normal progression)

## Server security — BuildRecipeViewForPlayer

`CraftingPipeline.BuildRecipeViewForPlayer` / `MysteryView.FinalizePlayerEntry` strip secrets for UNKNOWN:

**Not sent:** true label, description, ingredients, duration, XP, tools, output item metadata, skill uid (full mode).

**Sent:** `recipeId`, `state='unknown'`, `displayLabel='???'`, `displayImage='mystery'`, `canCraft=false`, `canOpenSkillTree`, category uid/label as allowed by `mysteryMode`.

Search uses `searchHaystack` built from public display fields only (never true names while unknown).

Favorites: blocked by default while fully unknown (`Config.Favorites.BlockUnknown` / `Config.Mystery.BlockFavoritesWhenUnknown`).
Follow/pin: allowed; label **Savoir inconnu**.

## Reveal

Index `categoryUid:skillUid` → `recipeIds` (`MysteryView.RecipeIdsForSkill`).
On `ml_skills:server:skillUnlocked`, payload includes `recipeIds` + `revealMs` (~280ms).
NUI refreshes and applies a light CSS reveal (`mystery-reveal`) — no resource restart.

## Admin

Recipe editor: visibility picker + mysteryMode + optional player-state preview (**Inconnu / Découvert / Appris**).
Admin-only **MYSTERY** badge never appears on player UI.

## Petit Bateau → mystery

Recipe id: `craft_smallboat` (import). Already set in `config/recipes_import.lua`:

```lua
skillVisibility = 'mystery_until_unlocked',
mysteryMode = 'full',
requireSkill = 'skill_139',
requireSkillCategory = 'survie',
```

Or via `/craftadmin`: open `craft_smallboat` → skillVisibility `mystery_until_unlocked` → Enregistrer.

## Config

```lua
Config.Mystery = {
  Enabled = true,
  defaultModeForSecrets = 'full',
  defaultModeForProgression = 'recipe_only',
  BlockFavoritesWhenUnknown = true,
  RevealMs = 280,
}
Config.Favorites = { BlockUnknown = true }
```

## Constraints

- Do not weaken strict `HasUnlockedSkill` / `failClosed`
- Do not break `Config.Debug.GiveMaterials`
- Vanilla `web/dist` is the NUI source
