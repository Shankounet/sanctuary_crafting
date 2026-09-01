# sanctuary_crafting

Ressource FiveM d’**ateliers de craft post-apocalyptiques** (ferraille, médical de fortune, armement, survie).

Stack : **ESX Legacy**, **ox_lib**, **ox_inventory**, **ox_target**, **oxmysql**, intégration optionnelle **ml_skills** (Micio Mods).

Les recettes ne sont **pas** fournies : remplissez `Config.Recipes` selon votre économie.

---

## Installation

1. Clonez / placez le dossier dans `resources/[local]/sanctuary_crafting` (ou équivalent).
2. Importez `sql/sanctuary_crafting.sql` (ou laissez la ressource créer la table au démarrage).
3. Ajoutez les items bancs dans `ox_inventory` (voir ci-dessous).
4. `server.cfg` — ordre recommandé :

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure es_extended
ensure ml_skills          # optionnel
ensure sanctuary_crafting
```

5. `ensure sanctuary_crafting` puis redémarrez ou `refresh` + `ensure`.

---

## Items ox_inventory (bancs placeables uniquement)

Ajoutez dans `ox_inventory/data/items.lua` :

```lua
['scrap_bench'] = {
    label = 'Établi de ferraille',
    weight = 5000,
    stack = false,
    close = true,
    description = 'Atelier de craft — ferraille (placé au sol)',
    server = { export = 'sanctuary_crafting.useBenchItem' },
},
['medical_bench'] = {
    label = 'Table médicale de fortune',
    weight = 5000,
    stack = false,
    close = true,
    description = 'Atelier de craft — médical',
    server = { export = 'sanctuary_crafting.useBenchItem' },
},
['weapons_bench'] = {
    label = 'Banc d\'armement',
    weight = 5000,
    stack = false,
    close = true,
    description = 'Atelier de craft — pièces d\'armes',
    server = { export = 'sanctuary_crafting.useBenchItem' },
},
['survival_bench'] = {
    label = 'Atelier de survie',
    weight = 5000,
    stack = false,
    close = true,
    description = 'Atelier de craft — survie',
    server = { export = 'sanctuary_crafting.useBenchItem' },
},
```

Les noms doivent correspondre aux clés de `Config.PlaceableItems`.  
Les items de recettes (ingrédients / résultats) sont **à vous** : déclarez-les dans ox_inventory comme d’habitude.

---

## Configuration

Fichier principal : `config.lua`.

| Clé | Rôle |
|-----|------|
| `Config.WorldBenches` | Bancs fixes (coords, heading, category, model) |
| `Config.Recipes` | Liste des recettes (vide par défaut) |
| `Config.PlaceableItems` | Lien item → catégorie / modèle |
| `Config.Skills` | ml_skills on/off, catégories, réduction durée |
| `Config.RateLimitMs` | Anti-spam craft |
| `Config.InteractDistance` / `CraftCancelDistance` | Distances |
| `Config.AdminAce` / `AdminGroups` | Droits admin |

### Schéma d’une recette

```lua
Config.Recipes = {
    {
        id = 'exemple_plaque',
        label = 'Plaque de métal',
        category = 'scrap', -- scrap | medical | weapons | survival
        ingredients = {
            { item = 'scrap_metal', count = 5 },
        },
        result = { item = 'metal_plate', count = 1 },
        duration = 8000, -- ms
        xp = { category = 'crafting', amount = 15 }, -- optionnel
        requireLevel = 1,        -- optionnel
        requireSkill = 'crafting_basic', -- optionnel (UID ml_skills)
    },
}
```

Catégorie de la recette = **type de banc** requis.

---

## ml_skills (optionnel)

Docs : https://miciomods.it/docs/ml-skills-developer

- Soft-fail : si `ml_skills` n’est pas `started`, les exports sont ignorés (pcall + `GetResourceState`).
- XP après craft réussi : `AddXp(categoryUid, amount, source)`.
- Gates : `requireLevel` → `GetPlayerLevel` ; `requireSkill` → `HasUnlockedSkill`.
- Réduction durée : `GetTotalCategoryBonus('crafting', src)` (plafond `maxCraftTimeReduction`).

Créez dans ml_skills les catégories `crafting` et `survival` (ou adaptez `Config.Skills.craftingCategory` / `survivalCategory`), plus les UID de skills référencés dans vos recettes.

---

## Fonctionnement

- **Bancs monde** : spawn client depuis `Config.WorldBenches` + `ox_target` → menu craft.
- **Bancs placeables** : usage de l’item → preview raycast → serveur retire l’item, insert SQL, sync à tous. Récupération propriétaire / admin.
- **Craft** : callback `startCraft` (distance, rate-limit, skills, ingrédients) → progress `ox_lib` client → `completeCraft` (re-checks, `RemoveItem`, `AddItem`, XP). Annulation si move / cancel.

Commande admin (si activée) : `/placeworldbench [scrap|medical|weapons|survival]` — prévisualise un prop et imprime les coords à coller dans `Config.WorldBenches`.

ACE : `add_ace group.admin sanctuary.crafting.admin allow`

---

## Arborescence

```
sanctuary_crafting/
├── fxmanifest.lua
├── config.lua
├── shared/          utils, types de bancs
├── client/          targets, menu, progress, placement
├── server/          craft, benches SQL, ml_skills, validation
├── sql/
├── locales/fr.lua
└── README.md
```

---

## Licence / auteur

Sanctuary / Shankounet — usage serveur privé.
