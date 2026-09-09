# Admin — catégories de craft

## Recipe editor · CLASSEMENT

In `/craftadmin` recipe form:

- **Catégorie** → `craftCategoryUid`
- **Sous-catégorie** → `craftSubcategoryUid` (optional)
- **Suggérer** → admin-only suggestion from legacy map / overrides (**never auto-saved**)
- Station remains separate (bench)

Invalid / missing category normalizes to **Divers** for players; admin sees warning via `_craftCategoryInvalid`.

## Page CATÉGORIES DE CRAFT

Header button **CATÉGORIES DE CRAFT**:

1. **Create / rename / icon / order / accent** — runtime upsert (`craftadminUpsertCategory`). Persist desired defaults back into `config/categories.lua` for reboot durability.
2. **Sous-catégories** — `craftadminUpsertSubcategory`
3. **Audit migration** — old `recipe.category` → count → suggested `Category>Sub` (`craftadminTaxonomyAudit`)
4. **BULK MOVE** — paste recipe ids → pick Category>Sub → **Prévisualiser** then **Appliquer (confirm)**. No silent migrate.

## How admins reclassify

1. Open `/craftadmin` → select recipe → CLASSEMENT pickers → Enregistrer (overlay SQL).
2. Or **Suggérer** then review/edit then Enregistrer.
3. Or CATÉGORIES DE CRAFT → BULK MOVE (preview → confirm).
4. Or Apply suggestions API (`craftadminApplySuggestions`) with `confirm=true` after preview.

ML Skills unlocks and mystery visibility are unchanged. Debug GiveMaterials unchanged.
