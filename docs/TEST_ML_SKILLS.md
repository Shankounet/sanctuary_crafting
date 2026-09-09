See docs/SKILLS.md § Test checklist.


## Mystery visibility checklist (v2.31)

1. Set a gated recipe to `mystery_until_unlocked` (e.g. Petit Bateau `craft_smallboat`).
2. Player **without** skill: catalogue shows darker `???` card + silhouette (no big padlock); search by true name finds nothing.
3. Click card → fiche: `Connaissance inconnue`, description mystery, `INGRÉDIENTS ???`, CTA opens `OpenSkillTree(categoryUid)` only.
4. Favorites on mystery → blocked toast; Follow/pin OK as Savoir inconnu.
5. Unlock skill in ml_skills (no restart): only linked recipes refresh; brief reveal animation; full label/ings appear.
6. `hidden_until_unlocked` still omits locked recipes; `visible_locked` still shows real label locked.
7. Admin preview: Inconnu / Découvert / Appris; MYSTERY badge only in admin.
8. With ml_skills stopped + failClosed: mystery stays UNKNOWN; free crafts still work.
9. Regression: FacingSkill ✓ only when `HasUnlockedSkill == true`; Debug Give Materials still admin-gated.

