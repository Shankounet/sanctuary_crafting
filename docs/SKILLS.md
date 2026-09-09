# Skills / XP — ml_skills (sole unlock provider)

`sanctuary_crafting` uses **ml_skills** as the **only** runtime source of unlocks, XP, and levels via the central bridge:

- `server/integrations/ml_skills.lua` → `Skills.*` (pcall + cache)
- `server/integrations/crafting_skills.lua` → thin `CraftingSkills.*` facade for existing call sites

**sanctuary_skilltree** and **DevHub** are **not** used for recipe unlock checks.

Craft mastery, recipes, stations, queues, energy, tools, and craft UI stay in sanctuary_crafting. Do **not** replace this craft system with ml_crafting.

## Ensure order (`server.cfg`)

```text
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_inventory
ensure ox_target
ensure ml_skills              -- BEFORE craft
ensure sanctuary_crafting
```

Soft dependency: `GetResourceState('ml_skills')` + `Config.SkillIntegration.failClosed`.

## Config

```lua
Config.SkillIntegration = {
  enabled = true,
  provider = 'ml_skills',
  failClosed = true,   -- skill-gated recipes stay locked if ml_skills down
  cache = true,        -- per-player UnlockedCache; opening craft = local lookups
  xpOn = 'collect',    -- XP on collect (offline-safe); not on Fabriquer click
  -- CategoryMapping = { survival = 'survie' }, -- optional
}

Config.Skills = {
  enabled = true,
  resource = 'ml_skills',
  defaultCategory = 'engineer',
  BypassRequirements = true, -- labs only; keep false in production
  BypassAce = 'sanctuary.crafting.bypassskills',
}
```

`Config.StationOutput.XpOn` follows `SkillIntegration.xpOn` when set.

## Official exports (DO NOT invert)

Server:

| Bridge | ml_skills |
|--------|-----------|
| `Skills.HasUnlockedSkill(src, cat, uid)` | `HasUnlockedSkill(categoryUid, skillUid, source)` |
| `Skills.AddXp(src, cat, amount)` | `AddXp(categoryUid, amount, source)` |
| `Skills.GetLevel` | `GetPlayerLevel(categoryUid, source)` (fallback `GetLevel`) |
| `Skills.GetUnlockedSkills` | `GetUnlockedSkills(source)` / `(categoryUid, source)` |
| Admin trees | `GetSkillTrees()` / `GetConfig()` |

Client:

- Feedback: `HasUnlockedSkill(categoryUid, skillUid)` — if `GetPlayerData()` nil → **loading/unknown**, not locked
- Open tree: `OpenSkillTree(categoryUid)` — **no** invented focus-node export

## Recipe schema

```lua
-- Free craft
requiredSkill = nil

-- Single requirement (level AND unlock when both set)
requiredSkill = { category = 'survival', uid = 'bandage_basic', level = 1 }

-- Multi
requiredSkills = {
  mode = 'all', -- or 'any'
  skills = {
    { category = 'survival', uid = 'field_dressing' },
    { category = 'medic', uid = 'sterile_wrap', level = 2 },
  },
}

skillVisibility = 'visible_locked'       -- default: shown, FABRIQUER disabled
             -- | 'hidden_until_unlocked' -- omitted from menu while locked
             -- | 'mystery_until_unlocked' -- shown as ??? until unlock (secure strip)
             -- | 'discovered_locked'     -- visible once discovered, still locked
-- mysteryMode = 'full' | 'recipe_only'   -- FULL hides skill name; RECIPE_ONLY shows category

skillXp = { category = 'survival', amount = 10 } -- category defaults to requiredSkill.category
-- or legacy: xp = { category = 'survival', amount = 10 }
```

### Migration

On load, `SkillTree.NormalizeRecipe` maps:

- `skillTree` / `requiredSkillTree` / `requireLevel` / `requireSkill` / `hideIfSkillLocked`
- → `requiredSkill` + `skillVisibility`

Uncertain DevHub/SST-only fields → log `UNMAPPED RECIPE SKILL`, **no** dangerous auto-rewrite.

### Bandage example

```lua
{
  id = 'bandage',
  label = 'Bandage de fortune',
  category = 'medical',
  station = 'medical',
  ingredients = { { item = 'cloth', count = 2 } },
  result = { item = 'bandage', count = 1 },
  duration = 5000,
  requiredSkill = { category = 'survival', uid = 'bandage_basic', level = 1 },
  skillVisibility = 'visible_locked',
  skillXp = { amount = 8 }, -- category → survival from requiredSkill
}
```

1. Publish skill `bandage_basic` under ml_skills category UID matching `Config.SkillCategories.survival.categoryUid` (default `survie`).
2. Ensure `ml_skills` before `sanctuary_crafting`.
3. Player without the skill sees **VERROUILLÉ** / “Connaissance non apprise” + **VOIR DANS LES SAVOIRS**.
4. After unlock (`ml_skills:server:skillUnlocked`), cache updates and craft UI refreshes without 200 export calls.
5. XP granted once on **collect** (`xpGranted` flag).

## Unlock boolean (strict)

`Skills.HasUnlockedSkill` calls **only** `exports.ml_skills:HasUnlockedSkill(categoryUid, skillUid, source)`.

- Success requires `pcall ok` **and** `result == true`. Anything else (error, nil, non-boolean) → **false** (fail closed).
- Cache keys are **only** `categoryUid:skillUid` from `GetUnlockedSkills` (no bare `skillUid`, no category-wide `true`).
- Rebuild on `playerLoaded` / clear on `playerUnloaded`. Stale positives are healed when the live export returns non-true.

### FacingSkill / NUI

- `normalizeSkillRequirements(recipe)` is the **data-source** unique list (dedupe key `provider:categoryUid:skillUid`, never label alone).
- Merges `requiredSkill` + `requiredSkills` + migrated `skillTree` / `require*`; **ignores** SST/DevHub/sanctuary leftovers (admin log, not OR’d into gates).
- `FacingSkill` sets each `skills[].unlocked` with the same strict check and **reconciles** with `CheckRecipeRequirement`: never ✓ when lockReason is `craft_skill_required` / `skill_locked`.
- NUI shows ✓ only when `unlocked === true`. `"Tous requis"` / plural title only if **2+ distinct** skills after normalize.

Debug: `Config.SkillIntegration.debug = true` and `/craftskilldebug [recipeId]`.

### DEBUG — give materials (labs)

`Config.Debug.GiveMaterials = true` (default `false`) + admin (`Validation.IsAdmin` / ACE) shows **GIVE MATÉRIAUX** near FABRIQUER. Server loads the recipe by id and `AddItem`s only missing ingredients (tools if inventory items). Does not grant the result, unlock ML skills, or bypass skill gates. Log: `[Craft][Debug] give materials src=… recipe=…`.

## Cache

Per-player `UnlockedCache[src]` keyed `categoryUid:skillUid` via `GetUnlockedSkills` on load.

Events (**AddEventHandler**, not RegisterNetEvent — local server events):

- `ml_skills:server:playerLoaded` → rebuild cache
- `ml_skills:server:skillUnlocked` → update cache + `sanctuary_crafting:client:recipeSkillUpdated`
- `ml_skills:server:playerUnloaded` → clear cache (character switch)

Hot restart / ensure: rebuild for online players. Opening craft with ~200 recipes = **cache lookups**, not 200 exports.

Levels cached; refreshed after our `AddXp`.

## Gate order (`CheckRecipeGates` / pipeline)

enabled → station → specialization → ML level → ML unlock → blueprint → tools → materials → queue → other

Reasons: `skill_locked` / `craft_skill_required`, `skill_level_low` / `craft_level_required`, `skills_unavailable`, `missing_blueprint`, …

NUI `skillState` is **display only** — server authoritative. Never trust client `unlocked=true`.

Visual priority: `LOCKED_SKILL` > `LOCKED_LEVEL` > `LOCKED_BLUEPRINT` > `MISSING_TOOL` > `MISSING_MATERIALS` > `CRAFTABLE`.

Missing skill → **VERROUILLÉ** (never PRESQUE).

## UI

- SAVOIR REQUIS / level / ✓ or ✕
- Locked: FABRIQUER disabled + “Connaissance non apprise” + **VOIR DANS LES SAVOIRS** → `OpenSkillTree(categoryUid)`
- Search still finds `visible_locked`
- Favorites/follow OK
- Carnet: objectif `Apprendre X dans Survie`
- On open, if ML data not loaded → “Chargement des savoirs...” briefly (no flash-all-locked)

## Admin

- `/craftskillcheck` — ml_skills started, categories count, gated recipes, valid/invalid mappings
- `/craftskilldebug [recipeId]` — dump categoryUid/skillUid, raw HasUnlockedSkill, normalized, cache key/value, GetUnlockedSkills membership
- Callback `sanctuary_crafting:adminMlSkills` — GetSkillTrees + health (editor open / refresh only)
- Button concept: **RAFRAÎCHIR ML SKILLS** → refresh labels; block save on invalid skill unless manual mode

## Test checklist

- [ ] Locked recipe: cannot craft; VERROUILLÉ; CTA opens OpenSkillTree
- [ ] Unlock hot path: skillUnlocked → cache → recipeSkillUpdated → craftable
- [ ] Level gate: skill_level_low / craft_level_required
- [ ] Visibility: visible_locked / hidden_until_unlocked / discovered_locked
- [ ] Reconnect: cache rebuild on playerLoaded
- [ ] Character switch: playerUnloaded clears cache
- [ ] Hot restart ml_skills / craft: caches rebuild
- [ ] ml_skills stopped: failClosed locks gated; free recipes work
- [ ] Unknown skill uid: startup log; invalid mapping in /craftskillcheck
- [ ] XP once on collect; no double XP (xpGranted)
- [ ] Cache perf: 200 recipes menu without per-recipe export storm
- [ ] Anti-cheat: client unlocked=true ignored; server CheckRecipeGates

## Residuals

Comments/docs may mention historical SST/DevHub. Runtime unlock path is **ml_skills only** through `Skills.*`.
