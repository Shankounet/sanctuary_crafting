# sanctuary_crafting v2.0.0

Plateforme de **craft post-apocalyptique** pour FiveM (ESX Legacy + ox_lib / ox_inventory / ox_target / oxmysql).

**ml_skills** (Micio Mods) est la **seule** source de compétences / XP / niveaux. Aucun XP craft parallèle.

UI NUI : thème industriel sombre moderne (pas « rusty »), accent `#9a8866`, layout 3 colonnes (recettes · détail · file/arbre/courses), recherche, filtres, favoris, raisons de verrouillage ✓/✕, mode compact, micro-interactions courtes.

---

## Installation

1. Placez la ressource dans `resources/[local]/sanctuary_crafting`.
2. Importez `sql/sanctuary_crafting.sql` (ou laissez la ressource créer les tables au boot).
3. Ajoutez les items bancs / blueprint dans ox_inventory (ci-dessous).
4. `server.cfg` :

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure es_extended
ensure ml_skills          # optionnel mais recommandé
ensure sanctuary_crafting
```

---

## Architecture

```
sanctuary_crafting/
├── config.lua                 # base + distances + anti-exploit + recettes vides
├── config/features.lua        # flags de tous les systèmes (implémentés)
├── config/examples.lua        # 9 recettes d’exemple
├── shared/                    # utils, UUID craftId, types de bancs
├── integrations/
│   ├── ml_skills.lua          # CraftingSkills.* → API ml_skills
│   ├── permissions.lua        # CraftingPermissions.CanUseStation
│   └── power.lua              # CraftingPower.HasPower / CanRunRecipe
├── core/                      # boot, hooks registry
├── security/                  # rate-limit, distance, CanCarry, admin
├── recipes/                   # registry + validation schéma
├── stations/                  # monde + SQL + levels/upgrades/modules
├── crafting/pipeline.lua      # craftId, start/complete/cancel, inventaire
├── blueprints/                # Learn/Has/Forget + SQL + item
├── tools/ quality/ mastery/
├── queue/ projects/ reverse/
├── favorites/ shopping/ tree/
├── dismantle/ hooks/
├── client/                    # benches, place, NUI bridge, craft fallback ox_lib
├── web/dist/                  # NUI (html/css/js)
├── locales/fr.lua + en.lua
└── sql/
```

Ordre de chargement serveur (fxmanifest) : **shared → integrations → core → security/recipes → stations → systèmes → pipeline → hooks**.

---

## Sécurité craft (`craftId`)

1. Client envoie **intent** uniquement (`recipeId`, `benchKey`, `batch`).
2. Serveur valide : station, distance, permissions, power, niveau station, **gates ml_skills**, blueprint, outils, ingrédients, `CanCarry`.
3. Ingrédients retirés au **start** (configurable) → génération **UUID `craftId`** + `craftUID`.
4. Client termine **uniquement** avec `craftId` (one-shot). Anti-speedhack (floor durée).
5. Cancel / disconnect : refund selon `Config.Crafting` (dont refund partiel).
6. Rate-limit + `MaxConcurrentCrafts`.

---

## CraftingSkills / ml_skills

Fichier : `integrations/ml_skills.lua`.

| Wrapper | API réelle |
|---------|------------|
| `CraftingSkills.AddXP` | `AddXp(categoryUid, amount, source)` |
| `CraftingSkills.GetLevel` | `GetPlayerLevel(categoryUid?, source)` |
| `CraftingSkills.HasRequiredLevel` | level ≥ requis |
| `CraftingSkills.HasSkill` | `HasUnlockedSkill(categoryUid?, skillUid, source)` |
| `CraftingSkills.GetCategoryBonus` | `GetTotalCategoryBonus(categoryUid, source)` |

Soft-fail : `pcall` + `GetResourceState`.  
**Si la recette a `requireLevel` / `requireSkill` et ml_skills est down → craft refusé** (`craft_skills_unavailable`). Pas de bypass silencieux.

La **maîtrise de recette** (`Config.Mastery`) est locale (SQL) et **n’est pas** un XP global : ml_skills reste la seule source d’XP de compétences.

---

## Feature flags (`config/features.lua`)

Tous les modules sont **implémentés**. Les flags activent/désactivent le comportement :

| Flag | Rôle |
|------|------|
| `Config.Blueprints.Enabled` | Learn/Forget + gates + item |
| `Config.Quality.Enabled` | metadata `quality` + `craftedBy` / `craftUID` |
| `Config.Tools.Enabled` | durabilité outils |
| `Config.Byproducts.Enabled` | sous-produits chance |
| `Config.Batch.Enabled` | lots |
| `Config.Queue.Enabled` | file + offline timestamps |
| `Config.Projects.Enabled` | projets multi-contributeurs |
| `Config.Dismantling.Enabled` | démontage + yield ml_skills |
| `Config.Mastery.Enabled` | maîtrise par recette |
| `Config.Tags` + `Substitution` | tags + substituts d’ingrédients |
| `Config.ReverseEngineering` | analyse item → blueprint |
| `Config.ShoppingList` | liste courses serveur |
| `Config.Stations.UpgradesEnabled` | levels / modules |
| `Config.Power.Enabled` | pont énergie (sinon always-on) |
| `Config.Noise.Enabled` | event bruit |
| `Config.UI.UseNui` | NUI (sinon menu ox_lib) |

---

## Schéma recette

```lua
{
  id = 'ex_metal_plate',
  label = 'Plaque de métal',
  category = 'scrap', -- scrap|medical|weapons|survival|mechanic
  tags = { 'metal' },
  ingredients = {
    { item = 'scrap_metal', count = 5, substitutes = { 'metal_ore' } },
  },
  result = { item = 'metal_plate', count = 1 },
  duration = 6000,
  xp = { category = 'crafting', amount = 10 }, -- ml_skills only
  requireLevel = 1,
  requireSkill = 'crafting_basic',
  requireBlueprint = 'bp_xxx',
  requireTool = { item = 'hand_saw', durabilityCost = 5 },
  quality = true,
  byproducts = { { item = 'slag', count = 1, chance = 0.5 } },
  batchMax = 5,
  queueable = true,
  stationLevel = 1,
  powerCost = 0,
  noiseLevel = 1,
  dismantle = false,
  dismantleYields = { ... },
}
```

9 exemples : `config/examples.lua` (`Config.LoadExampleRecipes`).

---

## NUI

- Accent `#9a8866`, fond sombre industriel.
- 3 colonnes : liste (search/filtres/favoris) · détail (locks, batch, craft/queue) · file / arbre / courses.
- Mode compact, Escape pour fermer.
- Perf : CSS léger, pas de libs lourdes, callbacks NUI ciblés.

Désactiver : `Config.UI.UseNui = false` → menu ox_lib.

---

## Items ox_inventory (bancs + blueprint)

```lua
['scrap_bench'] = { label = 'Établi de ferraille', weight = 5000, stack = false, close = true,
  server = { export = 'sanctuary_crafting.useBenchItem' } },
['medical_bench'] = { label = 'Table médicale', weight = 5000, stack = false, close = true,
  server = { export = 'sanctuary_crafting.useBenchItem' } },
['weapons_bench'] = { label = 'Banc d\'armement', weight = 5000, stack = false, close = true,
  server = { export = 'sanctuary_crafting.useBenchItem' } },
['survival_bench'] = { label = 'Atelier de survie', weight = 5000, stack = false, close = true,
  server = { export = 'sanctuary_crafting.useBenchItem' } },
['mechanic_bench'] = { label = 'Atelier mécanique', weight = 5000, stack = false, close = true,
  server = { export = 'sanctuary_crafting.useBenchItem' } },
['blueprint_scroll'] = { label = 'Schéma', weight = 50, stack = false, close = true,
  server = { export = 'sanctuary_crafting.useBlueprintItem' } },
```

Les items des 9 exemples (`scrap_metal`, `metal_plate`, etc.) sont à déclarer selon votre économie.

---

## Exports / events / hooks

```lua
exports.sanctuary_crafting:GetRecipe(id)
exports.sanctuary_crafting:GetRecipesForCategory(cat)
exports.sanctuary_crafting:HasBlueprint(src, bpId)
exports.sanctuary_crafting:LearnBlueprint(src, bpId)
exports.sanctuary_crafting:GetMastery(src, recipeId)
exports.sanctuary_crafting:GetStation(key)
exports.sanctuary_crafting:OpenCraftingForPlayer(src, benchKey)
exports.sanctuary_crafting:AddCraftingHook('craftCompleted', function(src, craft, given) end)
```

Events : `sanctuary_crafting:noise`, hooks `craftStarted` / `craftCompleted` / `craftCancelled` / `blueprintLearned` / `stationUpgraded` / …

---

## Bancs

- **Monde** : `Config.WorldBenches` + sync client + ox_target.
- **Placeables** : item → preview → SQL `sanctuary_placed_benches` (level + modules).
- Upgrade / modules via callbacks si `Stations.UpgradesEnabled`.

Commande admin : `/placeworldbench [category]` (ACE `sanctuary.crafting.admin`).

---

## Licence

Sanctuary / Shankounet — usage serveur privé.
