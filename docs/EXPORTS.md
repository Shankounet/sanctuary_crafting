# sanctuary_crafting v2.16.0 — public exports

Façade: `server/hooks/exports.lua`. Old names kept (`AddCraftingHook`, `HasBlueprint`, `LearnBlueprint`, `GetMastery`, `GetStation`, `OpenCraftingForPlayer`, `GetRecipe`, `GetRecipesForCategory`, `IsCrafting`).

`LearnRecipe` is **SERVER only**. It is not a client bypass of `learnBlueprint` (that callback is gated: item use **or** admin).

Events (also `CraftingCore.On` / `AddCraftingHook`): `craftStarted`, `craftCompleted`, `craftCancelled`, `recipeLearned`, `blueprintLearned`, `recipeMastered`, `stationUpgraded`, `stationBroken`. Resource event name: `sanctuary_crafting:<name>`.

---

## 1. OpenStation

| | |
|--|--|
| **Side** | server (+ client alias) |
| **Params** | `src: number`, `benchKey: string` |
| **Return** | `nil` |

Opens the existing player craft NUI for a resolved bench (`world:…` / `placed:…`).

```lua
exports.sanctuary_crafting:OpenStation(source, 'world:scrap_1')
```

---

## 2. OpenRecipe

| | |
|--|--|
| **Side** | server |
| **Params** | `src: number`, `recipeId: string` |
| **Return** | `ok: boolean`, `reason?: string` |

Finds the nearest matching station and opens it, selecting the recipe.

```lua
local ok, err = exports.sanctuary_crafting:OpenRecipe(source, 'bandage_basic')
```

---

## 3. AddRecipe

| | |
|--|--|
| **Side** | server |
| **Params** | `recipe: table`, `src?: number` |
| **Return** | `ok: boolean`, `version: number|string` |

SQL overlay upsert. `version += 1`, `RecipeRegistry.Rebuild`. Does not dump the config pack.

```lua
local ok, ver = exports.sanctuary_crafting:AddRecipe({
    id = 'metal_plate', label = 'Plaque', category = 'scrap', station = 'scrap',
    ingredients = { { item = 'scrap_metal', count = 5 } },
    result = { item = 'metal_plate', count = 1 }, duration = 8000,
}, src)
```

---

## 4. RemoveRecipe

| | |
|--|--|
| **Side** | server |
| **Params** | `recipeId: string`, `src?: number` |
| **Return** | `ok: boolean`, `version: number|string` |

**Soft-disable** (`sanctuary_recipes.disabled = 1`). In-flight crafts keep their snapshot.

```lua
exports.sanctuary_crafting:RemoveRecipe('metal_plate', src)
```

---

## 5. GetRecipe

| | |
|--|--|
| **Side** | server |
| **Params** | `id: string` |
| **Return** | `table|nil` (merged Config + overlay, not disabled) |

```lua
local r = exports.sanctuary_crafting:GetRecipe('metal_plate')
```

---

## 6. GetRecipes

| | |
|--|--|
| **Side** | server |
| **Params** | `filter?: { station?: string, category?: string }` |
| **Return** | `table[]` |

```lua
local list = exports.sanctuary_crafting:GetRecipes({ station = 'scrap' })
```

---

## 7. CanCraft

| | |
|--|--|
| **Side** | server |
| **Params** | `src, recipeId, benchKey, batch?` |
| **Return** | `ok: boolean`, `reason?: string`, `args?: table` |

Same gates as `validateStart` (no consume).

```lua
local ok, reason = exports.sanctuary_crafting:CanCraft(src, 'metal_plate', benchKey, 1)
```

---

## 8. StartCraft

| | |
|--|--|
| **Side** | server |
| **Params** | `src, recipeId, benchKey, batch?` |
| **Return** | `{ ok, craftId?, reason? }` |

Locks player+station, validates, `CraftingMaterials` take, **snapshots recipe+version**, unlocks.

```lua
local res = exports.sanctuary_crafting:StartCraft(src, 'metal_plate', benchKey, 1)
```

---

## 9. CancelCraft

| | |
|--|--|
| **Side** | server |
| **Params** | `src, craftId, reason?` |
| **Return** | `ok: boolean`, `reason?: string` |

```lua
exports.sanctuary_crafting:CancelCraft(src, craftId, 'export')
```

---

## 10. GetQueue

| | |
|--|--|
| **Side** | server |
| **Params** | `src: number` |
| **Return** | `entries[]` |

```lua
local q = exports.sanctuary_crafting:GetQueue(src)
```

---

## 11. FollowRecipe

| | |
|--|--|
| **Side** | server |
| **Params** | `src, recipeId` |
| **Return** | `ok: boolean`, `reason?: string` |

Pins / follows via Survival Book (v2.14 follow unchanged).

```lua
exports.sanctuary_crafting:FollowRecipe(src, 'metal_plate')
```

---

## 12. UnfollowRecipe

| | |
|--|--|
| **Side** | server |
| **Params** | `src, recipeId` |
| **Return** | `ok: boolean`, `reason?: string` |

```lua
exports.sanctuary_crafting:UnfollowRecipe(src, 'metal_plate')
```

---

## 13. IsRecipeKnown

| | |
|--|--|
| **Side** | server |
| **Params** | `src, recipeId` |
| **Return** | `boolean` |

```lua
if exports.sanctuary_crafting:IsRecipeKnown(src, 'metal_plate') then end
```

---

## 14. LearnRecipe

| | |
|--|--|
| **Side** | **SERVER only** |
| **Params** | `src, recipeId` |
| **Return** | `ok: boolean`, `reason?: string` |

Grants knowledge/blueprint from another resource. **Not** a client NUI bypass (`learnBlueprint` callback is admin/item gated).

```lua
-- other resource, server:
exports.sanctuary_crafting:LearnRecipe(src, 'metal_plate')
```

---

## 15. GetRecipeMastery

| | |
|--|--|
| **Side** | server |
| **Params** | `src, recipeId` |
| **Return** | `number` (0–MaxMastery). Not global XP — `CraftingSkills` remains sole XP/level SoT. |

```lua
local m = exports.sanctuary_crafting:GetRecipeMastery(src, 'metal_plate')
```

---

## 16. GetStationState

| | |
|--|--|
| **Side** | server |
| **Params** | `benchKey: string`, `src?: number` |
| **Return** | snapshot table (`level`, `condition`, `temp`, `modules`, `queue`, …) or `nil` |

```lua
local snap = exports.sanctuary_crafting:GetStationState('placed:12', src)
```

---

## Events

| Event | When |
|-------|------|
| `craftStarted` | Interactive craft registered |
| `craftCompleted` | Rewards granted |
| `craftCancelled` | Cancel / disconnect refund path |
| `recipeLearned` | Knowledge granted (also `blueprintLearned`) |
| `recipeMastered` | Mastery crosses threshold |
| `stationUpgraded` | Placed bench level++ |
| `stationBroken` | Condition crosses BrokenStop |

```lua
exports.sanctuary_crafting:AddCraftingHook('craftCompleted', function(src, craft, given)
    -- HTTP / Discord belongs here, not in the pipeline
end)
```
