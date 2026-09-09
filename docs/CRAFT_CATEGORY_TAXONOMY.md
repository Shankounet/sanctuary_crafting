# Craft category taxonomy — design

## Principles

1. **Explicit classification** — each recipe has `craftCategoryUid` (+ optional `craftSubcategoryUid`).
2. **Do not auto-generate** from item labels, ox_inventory types, word tokens, old tags, ML Skills categories, or internal tech tags.
3. **ML Skills ≠ category** — skills unlock/XP only (`skillTree` / `requiredSkill` / XP).
4. **Station ≠ category** — `recipe.station` selects the bench; craft taxonomy is independent.
5. **Single source of truth** — after `normalizeRecipeClassification(recipe)` / `CraftTaxonomy.NormalizeRecipeClassification`, only `craftCategoryUid` / `craftSubcategoryUid` drive player UI grouping.
6. **Frontend never classifies by `label.contains`** — server sends `craftCategoryUid` / label / icon + subcategory.
7. **Indexes at load** — `CraftTaxonomy.recipesByCategory` / `recipesBySubcategory` (also `Config.RecipesByCraftCategory`) rebuilt in `RecipeRegistry.Rebuild`. Not filtered every frame.

## Default taxonomy (FR, configurable)

| uid | Label | Notes |
|-----|-------|-------|
| survie | Survie | sub: Eau, Abri, Feu |
| soins | Soins | Bandages, Médicaments, Anti-douleurs, Kits, Premiers soins |
| outils | Outils | Forge, Réparation |
| equipement | Équipement | Gadgets, Sacs, Appareils, Protections, Tech |
| construction | Construction | Fonderie, Décoration |
| mecanique | Mécanique | Pneumatiques, Entretien, Fluides/Stockage, Carrosserie, Customs |
| electricite | Électricité | (fix Electriciter) Éclairage, Batteries, Radio |
| armes | Armes | Corps à corps, Corps, Canons, Réparations |
| munitions | Munitions | |
| cuisine | Cuisine | Viandes, Poissons, Crustacés |
| agriculture | Agriculture | Pousses, Équipement agricole, Consommables |
| chimie | Chimie | Poudres |
| transport | Transport | Nautique, Navigation |
| divers | Divers | **Last resort** only |

Max ~14 mains. Manual `sortOrder`. No `"Toutes"` category — global view is a UI filter only.

## Player UI

- **Left rail**: main categories only + **counts**.
  - **Count policy**: number of recipes that pass current **non-category** filters (search, favoris, nouveaux, faisables, rareté, matériau). Category selection itself is excluded so counts stay stable while browsing. Documented in pipeline menu payload + this doc.
- **Tous**: global view control above the rail — **not** a craft category. Clicking an active category collapses back to Tous.
- **Subcategories**: chip strip under catalogue title when a main is selected (`Tous` + subcats).
- Favorites / Nouveaux / Faisables remain independent chips.
- **Mystery UNKNOWN**: still belongs to a craft category (??? card can show the main label); **subcategory hidden** if revealing. Search uses public fields / server `searchHaystack` only — never true names.

## Legacy fields

| Field | Status |
|-------|--------|
| `recipe.category` | Deprecated UI id from pack; kept for migration audit / soft mirror |
| `recipe.station` | Bench SoT |
| `GetRecipesForCategory(x)` | **Historical name** — filters by **station**, not craft taxonomy |
| `GetRecipesForCraftCategory` | Craft taxonomy index helper |
| `Config.RecipeCategories` | Flat compat mirror of `Config.CraftCategories` (no `all`) |

## Config entry points

- `config/categories.lua` — `Config.CraftCategories`, `CraftCategoryLegacyMap`, `CraftRecipeClassificationOverrides`
- `shared/craft_taxonomy.lua` — normalize, suggest, indexes, audit

See also: `docs/CRAFT_CATEGORY_ADMIN.md`, `docs/CRAFT_CATEGORY_MIGRATION.md`.
