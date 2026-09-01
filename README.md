# sanctuary_crafting v2.1.3

Plateforme de **craft post-apocalyptique** pour FiveM (ESX Legacy + ox_lib / ox_inventory / ox_target / oxmysql).

**ml_skills** (Micio Mods) est la **seule** source de compétences / XP / niveaux. Aucun XP craft parallèle.

UI NUI **premium** (v2.1.3) : atelier survivant reconstruit (métal usé, laiton terni `#9a8866`, pas Fallout / pas cyberpunk). **Craft** = banc de production 3 colonnes (polish densité PC). **Carnet** = journal / dossier de terrain (identité séparée). Micro-interactions 100–180 ms. **Callbacks NUI inchangés.**

---


## Notes de version

### v2.1.3 — Craft UI polish
Polish UX / art direction de l’**atelier craft** (`web/dist/style.css`, `app.js`, `index.html`) sans redesign architecture (3 colonnes, cartes, détail droit, File/Arbre/Courses).

- Colonne gauche un peu plus étroite, catégories compactes, File/Arbre/Courses mieux présentés (file industrielle / plan technique / checklist récup).
- Cartes recettes : image un peu plus grande, hiérarchie nom, tags techniques (OPÉRATIONNEL / MANQUANT / VERROUILLÉ), favori discret, hover premium.
- Panneau droit : identité (image, nom, catégorie, rareté, description) puis blocs techniques ; lignes « — » masquées ; spécialisation ✓/✕ ; skill ml_skills (nom, niveau actuel/requis, barre) ; matériaux image + owned/required.
- FABRIQUER désactivé mais lisible + une raison primaire ; tooltips obligatoires sur icônes latérales.
- Direction artistique atelier survivant (grain métal, rivets, stencils STATION/RECIPE INDEX, codes recette) — **Book inchangé** (reste dossier / journal via `book.css` / `book.js`).
- Enrichissement NUI additif dans `buildRecipeEntry` (`owned`, `playerSkillLevel`, `hasSpecialization`, `description`) — **aucun rename** de callbacks (`close`, `refresh`, `craft`, `complete`, `cancel`, `favorite`, `queue`, `queueList`, `queueCollect`, `shopping`, `shoppingClear`, `tree`, `notify`, book*).

### v2.1.2 — Identité visuelle Carnet (Book ≠ Craft)
Refonte UI/UX du **Carnet de survie** (`web/dist/book.js` + `book.css` + mount HTML) : journal technique / dossier personnel, pas un clone du banc craft.

- **Craft** = atelier / production : chrome industriel plus tranché, layout 3 colonnes (liste · détail · file).
- **Book** = carnet / field dossier : spine + grain papier subtil, sidebar app (icônes + labels), pages riches qui changent fortement par onglet (widgets dashboard, cartes compétences, dossiers projets/plans, codex silhouettes, contacts, timeline…).
- Accent partagé `#9a8866`, univers sombre premium — **structure et ressenti distincts** pour que le joueur sache immédiatement dans quelle app il est.
- Modules navigables alignés sur `Config.Book` (Journal + Terrain). **Callbacks NUI book préservés** : `bookClose`, `bookDashboard`, `bookModule`, `bookAction`, `bookToggleHud`, `bookPinRecipe`, `bookObjectiveRecipe`, `bookOpenFromCraft` ; messages `bookOpen` / `bookClose` / `bookPins` / `bookEvent`.

### v2.1.1 — UI premium
Refonte visuelle complète de l’UI craft (`web/dist`) : grille de cartes, fiche détail enrichie, navigation/filtres à gauche, file/arbre/courses redesignés. **Aucun changement** des callbacks NUI / ponts Lua (`close`, `refresh`, `craft`, `complete`, `cancel`, `favorite`, `queue`, `queueList`, `queueCollect`, `shopping`, `shoppingClear`, `tree`, `notify`, book*).

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
├── config.lua                 # base + distances + anti-exploit + Skills pack
├── config/features.lua        # flags de tous les systèmes (implémentés)
├── config/categories.lua      # Config.RecipeCategories (IDs propres FR)
├── config/recipes_import.lua  # pack recettes Alex (DevHub → sanctuary)
├── config/world_benches.lua   # bancs monde (Shared.Craftings)
├── config/community_projects.lua
├── config/examples.lua        # 9 recettes d’exemple (OFF si import)
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
├── web/sounds/                # SFX .ogg (click/success/error/blueprint)
├── locales/fr.lua + en.lua    # parité complète
├── book/                      # Carnet de survie (Survival Book)
├── config/book.lua            # Config.Book.* modules
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
| `CraftingSkills.HasRequiredLevel` | level ≥ requis (ou bypass test) |
| `CraftingSkills.HasSkill` | `HasUnlockedSkill(...)` (ou bypass test) |
| `CraftingSkills.GetCategoryBonus` | `GetTotalCategoryBonus(categoryUid, source)` |
| `CraftingSkills.ShouldBypassRequirements` | mode test (voir ci-dessous) |

Soft-fail : `pcall` + `GetResourceState`.  
**Si la recette a `requireLevel` / `requireSkill` et ml_skills est down → craft refusé** (`craft_skills_unavailable`), **sauf** mode test (bypass).

La **maîtrise de recette** (`Config.Mastery`) est locale (SQL) et **n’est pas** un XP global : ml_skills reste la seule source d’XP de compétences.

### Mode test sans skills

> **NE JAMAIS activer `BypassRequirements` sur un serveur public / production.**  
> Réservé au debug, aux labs et aux tests de recettes / carnet.

```lua
Config.Skills = {
  -- ...
  BypassRequirements = false,                          -- OFF par défaut (prod)
  BypassAce = 'sanctuary.crafting.bypassskills',       -- optionnel
  BypassAlsoSkipXP = false,                            -- false = tenter AddXp si ml_skills up
  BypassNotify = false,                                -- ou Config.Debug → notify ox_lib 1×
}
```

Comportement :

| Condition | Effet |
|-----------|--------|
| `BypassRequirements = true` | **Tous** les joueurs sautent `requireLevel` / `requireSkill` (pipeline + book « can craft ») |
| `BypassRequirements = false` + ACE `BypassAce` (ou `Config.AdminGroups` / `AdminAce` via `Validation.IsAdmin`) | Ces joueurs seulement sautent les gates |
| Bonus durée craft | Soft-fail inchangé (pas de bonus si ml_skills down) |
| XP | Toujours via `CraftingSkills.AddXP` → ml_skills ; pas d’XP parallèle. Si `BypassAlsoSkipXP = true`, n’appelle pas AddXp sous bypass |
| Sécurité | Ingrédients, station, distance, rate-limit, `craftId` : **inchangés** |

Notify (une fois / session) au **démarrage d’un craft** (pipeline ou file) si `Config.Debug` ou `Config.Skills.BypassNotify`.

server.cfg (exemple ACE per-admin) :

```cfg
add_ace group.admin sanctuary.crafting.bypassskills allow
```

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
| `Config.Power.Enabled` | pont énergie + `ExternalBridge` (sinon always-on ; fallback `power_cell`) |
| `Config.Noise.Enabled` | event bruit |
| `Config.UI.UseNui` | NUI (sinon menu ox_lib) |
| `Config.UI.Sounds` | SFX NUI (WebAudio + `.ogg`), `Enabled` / `Volume` / `Files` |

---

## Schéma recette

```lua
{
  id = 'ex_metal_plate',
  label = 'Plaque de métal',
  category = 'weapons', -- UI RecipeCategories (ammo|weapons|…)
  station = 'armurier', -- banc / Shared.Crafts key (requis pour le pack import)
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
  -- Multi-étapes (même craftId) :
  steps = {
    { label = 'Découpe', ingredients = { { item = 'scrap_metal', count = 3 } }, duration = 4000 },
    { label = 'Assemblage', ingredients = { { item = 'cloth', count = 1 } }, duration = 4000 },
  },
  -- OU chaîne de recettes (réponse complete.chainNext, même craftUID) :
  chain = { 'ex_reinforced_plate' },
}
```

9 exemples : `config/examples.lua` (`Config.LoadExampleRecipes = true` pour forcer). `ex_cut_pipe` démo `steps[]`.

---

## Import recettes (pack Alex / DevHub)

Conversion **non 1:1** depuis `Shared.Categories` / `Shared.Crafts` / `Shared.Craftings` / `Shared.CommunityProjects`.

### Fichiers

| Fichier | Contenu |
|---------|---------|
| `config/categories.lua` | `Config.RecipeCategories` — IDs propres (`ammo`, `weapons`, …), labels FR |
| `config/recipes_import.lua` | **379** recettes → `Config.Recipes` + `Config.RecipesByStation` |
| `config/world_benches.lua` | **19** bancs monde (coords serveur conservées) |
| `config/community_projects.lua` | 2 projets communautaires |

`Config.LoadImportedRecipes` vaut `true` par défaut. Les exemples démo sont **désactivés** (`LoadExampleRecipes` seulement si forcé à `true`).

### Mapping catégories UI

`category_1775…` → ids propres : `ammo`, `weapons`, `repair_kits`, `weapon_body`, `weapon_barrel`, `powders`, `weapon_repair`, `bandages`, `painkillers`, `remedies`, `med_kits`, `tickets`, `electricity`, `lamps`, `gadgets`, `radio`, `appliances`, `vehicle_customs`, `batteries`, `paint`, `tires`, `melee`, `tools`, `smelting`, `armor`, `sprouts`, `farm_equipment`, `consumables`, `meats`, `fish`, `shellfish`, `bags`, `artisan_prod` (+ extras pack : `decoration`, `cooker`, `techno`, `survie`).

### Stations (18)

`ingenieur`, `tailleur`, `boucherie`, `medical`, `forgeron`, `manche_forgeron`, `agriculture`, `mecano`, `schema`, `accessoires`, `fonderie_forgeron`, `decoration`, `munition`, `cuisine`, `reparation_forgeron`, `construction`, `survie`, `armurier`.

Une recette a `category` (filtre UI) **et** `station` (banc). Le pipeline matche `recipe.station` (ou `category` pour les exemples) avec `bench.category`.

### Skills ml_skills (catégories exactes du pack)

`ingenieur`, `survie`, `agriculture`, `medecin`, `forgeron`, `mechanic`, `armurier`.

Listées dans `Config.Skills.categories`. XP = `requiredLevelCategory` + `craftXP`. Skill = premier `skillTreeRequirements`.

### BypassRequirements (rappel)

> **NE JAMAIS activer `Config.Skills.BypassRequirements` sur un serveur public / production.**

Réservé aux labs / tests de recettes. Voir section « Mode test sans skills ».

### Ce qui n’est PAS importé

- `customRequirements.handler` (remplacé par `tools` / `requireTool` pour `WEAPON_WRENCHKNIFE`)
- `cameraOffset` / `PropDefaults` / tables `camera` (commentées éventuellement)
- Invented ml_skills exports — uniquement les wrappers `CraftingSkills.*` existants

### Bancs `type = "coords"`

Pas de spawn prop : zone `ox_target` au point. Les autres bancs spawnent `model`/`prop` (string → `joaat` client).

---

## NUI

- Accent `#9a8866`, fond sombre industriel.
- 3 colonnes : liste (search/filtres/favoris) · détail (locks, batch, craft/queue) · file / arbre / courses.
- Mode compact, Escape pour fermer.
- Perf : CSS léger, pas de libs lourdes, callbacks NUI ciblés.
- **SFX** (optionnels) : WebAudio beep + placeholders `web/sounds/{click,success,error,blueprint}.ogg`.
  Désactiver : `Config.UI.Sounds.Enabled = false`.

Désactiver NUI : `Config.UI.UseNui = false` → menu ox_lib.

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

### Items des 9 recettes d'exemple (`config/examples.lua`)

À déclarer selon votre économie (labels / poids libres) :

| Item | Rôle (exemples) |
|------|-----------------|
| `scrap_metal` | ingrédient de base |
| `metal_plate` | résultat / ingrédient |
| `reinforced_plate` | résultat skill-gated |
| `cloth` | médical / survie / steps |
| `plastic` | masque filtrant |
| `filter_mask` | résultat blueprint |
| `hand_saw` | outil (durabilité) |
| `cut_pipe` | résultat multi-steps |
| `alcohol` | médical |
| `medkit_basic` | résultat qualité |
| `repair_kit` | résultat mechanic |
| `metal_ingot` | fonte |
| `slag` / `coal_dust` | byproducts |
| `gunpowder` / `brass` | presse munitions |
| `ammo_9mm` | résultat queue/machine |
| `weapon_pistol` | démontage (source) |
| `weapon_parts` / `spring` | yields démontage |
| `power_cell` | module station (fallback Power) |

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

## Power (`Config.Power`)

- `Enabled = false` → toujours alimenté.
- `Enabled = true` → résolution :
  1. **Pont externe** `Config.Power.ExternalBridge = { resource, export }` (ou `fn`)
  2. Fallback modules station : `power_cell` / `generator` (`FallbackModules`)
  3. Bancs monde : `powered ~= false`
- Exports : `SetPowerBridge(fn)`, `HasStationPower(station, recipe?)`

```lua
Config.Power = {
  Enabled = true,
  ExternalBridge = { resource = 'my_power_grid', export = 'HasStationPower' },
  FallbackModules = { 'power_cell', 'generator' },
}
```

## Multi-étapes / chaîne

- **`recipe.steps[]`** : étapes séquentielles d'ingrédients ; le serveur avance sous le **même `craftId`** (`complete` → `{ advanced=true, stepIndex, duration }`).
- **`recipe.chain`** : après complete final, réponse `chainNext` (+ `craftUID` stable) pour enchaîner une autre recette / projet.
- Cancel / disconnect : refund de tout `removedHistory` (toutes les étapes consommées).

## Polish v2 leftovers (fermés)

- [x] Exécuteur multi-étapes (`steps[]` / `chain`)
- [x] SFX NUI (WebAudio + `.ogg`, `Config.UI.Sounds`)
- [x] Parité `locales/en.lua` ↔ `fr.lua`
- [x] Pont `Config.Power.ExternalBridge` + fallback `power_cell`
- [x] README items exemples + gaps documentés
- [x] Nil-guards pipeline + `fxmanifest` fichiers `web/sounds/*.ogg`

**ml_skills** reste la seule source XP via `CraftingSkills` (pas d'XP craft parallèle).


---

## Carnet de survie (Survival Book)

Manuel de terrain **personnel** (dossier technique sombre, accent `#9a8866`) — pas un wiki omniscient, pas de cliché « rusty Fallout ».

### Principes

- **ml_skills** = seule vérité XP/niveaux via `CraftingSkills` (**lecture seule** dans le carnet). Aucune table XP parallèle.
- Réutilise recettes / stations / blueprints / file / projets du craft — **pas** de duplication `Config.Recipes`.
- Connaissance **par découverte** : ressources inconnues → `???`. **Pas de GPS**. Pas de niveaux/licences/inventaires exacts des autres joueurs (tiers artisans qualitatifs seulement).
- Serveur valide : découvertes, contacts, objectifs, pins, notes, commandes.
- NUI **lazy-load** par module (`Config.Book.*.Enabled`).

### Activation

`config/book.lua` → `Config.Book.Enabled = true` (+ flags par module : Dashboard, Progression, NextUnlocks, Objectives, Pins, Shopping, CraftTree, Resources, Discoveries, Blueprints, Artisans, Network, Orders, Projects, Notes, Search, Suggestions, CanCraft, Workshop, Maintenance, Productions, Notifications, History, Stats).

### Item ox_inventory

```lua
['survival_book'] = {
  label = 'Carnet de survie',
  weight = 200,
  stack = false,
  close = true,
  description = 'Manuel de terrain personnel — craft, objectifs, réseau.',
  -- CLIENT export = ouverture NUI fiable (recommandé)
  client = { export = 'sanctuary_crafting.useSurvivalBook' },
  -- SERVER export = fallback TriggerClientEvent (optionnel si client est défini)
  -- server = { export = 'sanctuary_crafting.useSurvivalBook' },
},
```

**Important :** sans cet item dans `ox_inventory/data/items.lua`, utiliser le carnet depuis l’inventaire ne fera **rien**. Test rapide hors item : commande client `/carnet`.

Ouvrir aussi : `exports.sanctuary_crafting:OpenSurvivalBook(src, 'dashboard')` (serveur) ou export client `OpenSurvivalBook`.

### Architecture

```
book/
├── client/book.lua          # open/close NUI, mini HUD pins, ox_target meet
└── server/
    ├── db.lua               # tables minimales
    ├── core.lua             # discoveries, objectives, pins, notes, artisans, orders, history
    ├── services.lua         # shopping récursif, suggestions, progression RO, dashboard…
    ├── api.lua              # callbacks lazy-load
    ├── bridge.lua           # hooks craftCompleted / blueprintLearned
    └── main.lua             # item export + exports publics
web/dist/book.js + book.css  # UI dossier / journal (≠ craft atelier)
config/book.lua              # Config.Book.*
```

### SQL (minimal)

`sanctuary_book_player`, `_objectives`, `_pins`, `_notes`, `_discovered_resources`, `_artisans`, `_history`, `_orders` — **aucun** stockage XP ml_skills.

### Exports / events book

```lua
exports.sanctuary_crafting:OpenSurvivalBook(src, page?)
exports.sanctuary_crafting:DiscoverResource(src, item, label?, reason?)
exports.sanctuary_crafting:HasDiscoveredResource(src, item)
exports.sanctuary_crafting:AddObjective(src, title, kind?, payload?)
exports.sanctuary_crafting:PinRecipe(src, recipeId)
exports.sanctuary_crafting:AddArtisanContact(src, { contactId, displayName, specialty?, tier?, source? })
```

Events : `sanctuary_crafting:book:resourceDiscovered`, `book:artisanMet`, `book:objectiveCompleted`.

Shopping smart : expansion récursive des intermédiaires craftables, crédit inventaire (pas de double-compte), garde anti-cycle (`Config.Book.Shopping.MaxDepth`).

Commandes craft : **pas de téléport d'items** (`Orders.AllowTeleport` forcé false) — échange RP / physique.


## Licence

Sanctuary / Shankounet — usage serveur privé.
