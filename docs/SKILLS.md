# Skills / XP — sanctuary_skilltree (Phase 4)

`sanctuary_crafting` uses **sanctuary_skilltree** as the sole runtime skill / XP / level source via `CraftingSkills` (`server/integrations/crafting_skills.lua`).

DevHub (`devhub_skillTree`) is **not required** once skilltree is started. Phase 3 player migration (`/skillsadmin` → Migration DevHub) stays a separate operator step.

## Ensure order (`server.cfg`)

```text
ensure oxmysql
ensure ox_lib
ensure es_extended
ensure ox_inventory
ensure ox_target
ensure sanctuary_skilltree   -- BEFORE craft
ensure sanctuary_crafting
```

Optional transitional fallback: keep `devhub_skillTree` started and set `Config.SkillSystem = 'auto'` (prefers sanctuary when both up).

## Config

| Key | Meaning |
|-----|---------|
| `Config.SkillSystem` | `'sanctuary'` (default Phase 4) \| `'devhub'` \| `'auto'` |
| `Config.Skills.resource` | Preferred resource name (`sanctuary_skilltree`) |
| `Config.Skills.fallbackResource` | DevHub name for auto/devhub modes |
| `Config.SkillCategories.*.categoryUid` | Must match **published** Sanctuary category UIDs |

Recipe gate shape unchanged:

```lua
skillTree = { category = 'medic', requiredLevel = 10, requiredSkill = 'some_talent_uid' }
-- category = KEY (survival/medic/engineer/gunsmith); resolve via SkillCategories
xp = { category = 'engineer', amount = 15 }
```

## Exports used (sanctuary_skilltree)

Read: `getPlayerLevel`, `getPlayerXp`, `getPlayerTotalXp`, `getPlayerPoints`, `getPlayerGlobalStats`, `hasUnlockedSkill`, `getUnlockedSkills`, `getCategories`, `getCategory`, `getSkills`, `getSkill`

Mutate (server only): `addXp` (craft complete), optional `addPoints` if `Config.Skills.AwardPoints`

Arg order on Sanctuary: `(srcOrId, categoryUid, …)` — craft adapters handle this; do not call DevHub order against Sanctuary.

## Carnet

Progression is **read-only**: French labels + **Niveau** + **XP actuel** (+ total if known) + known talent labels. Never UIDs, never invented %. If next-level progress unavailable: `Niveau X` + current XP only (`web/dist/book.js` `msSkillLines`).

## Hard rules

- No `ml_skills`
- No auto `AddItem` on craft complete (SORTIE manual recover)
- `addXp` server-only via skilltree
- No NUI redesign; queue / FIFO / SORTIE unchanged
- Specialty icons / PRESQUE–NON FAISABLE stay accurate (labels from skilltree defs)

## Residual risks

- `categoryUid` mismatch after Phase 3 if Sanctuary trees use different UIDs than `Config.SkillCategories` — fix config or remap publish UIDs.
- Until Phase 3 migration runs, players may have empty Sanctuary progress (gates fail closed unless `BypassRequirements`).
- DevHub fallback arg-order path remains for labs only; do not dual-write XP.


## Recipe unlocks (tech progression)

When a published skilltree node lists `meta.recipeIds`, that recipe is **gated**.

`CraftingSkills.CheckRecipeGates` calls `exports.sanctuary_skilltree:canAccessRecipe` after level/talent gates:

- Ungated recipes (not in skilltree map) → accessible (other gates still apply).
- Gated + skill unlocked → accessible.
- Gated + skill locked → `craft_recipe_locked` (NUI: **VOIR DANS L'ARBRE**).

Facing payload adds `lockKind=skilltree_recipe`, `skilltreeSkillLabel`, `openSkilltree`.

Ensure `sanctuary_skilltree` starts **before** `sanctuary_crafting`.
