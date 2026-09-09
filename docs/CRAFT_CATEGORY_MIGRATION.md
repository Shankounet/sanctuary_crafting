# Migration report — craft category taxonomy
Generated for sanctuary_crafting craftCategoryUid rewrite.
## Policy
- **No silent migrate** in admin: preview → confirm for bulk move / apply suggestions.
- Runtime `normalizeRecipeClassification` sets SoT `craftCategoryUid` / `craftSubcategoryUid`.
- Invalid category → player **Divers** + admin warning.
- Auto-suggest is **admin-only** (never auto-truth).

## Old category → count → suggested new
| Legacy `recipe.category` | Count | Suggested `Category>Sub` | Samples |
|---|---:|---|---|
| `sprouts` | 44 | `agriculture>pousses` | craft_WEAPON_SWORD_01, craft_aloevera_sprout, craft_mustard_sprout, craft_peas_sprout |
| `melee` | 41 | `armes>melee` | craft_WEAPON_KHANKNIFEMET, craft_WEAPON_MODERNAXE, craft_WEAPON_NPDS_SURV_DAGGER, craft_WEAPON_FURY_SAMSWORD |
| `tools` | 37 | `outils>-` | craft_WEAPON_WRENCHKNIFE, craft_shovel, craft_WEAPON_PICKAXE, craft_WEAPON_HATFOU |
| `fish` | 28 | `cuisine>poissons` | craft_cut_fish_fish, craft_cut_fish_flyfish, craft_cut_fish_bluefish, craft_cut_fish_eelfish |
| `decoration` | 25 | `construction>decoration` | craft_barbeque, craft_chair, craft_sofa, craft_coffeemachine |
| `bandages` | 23 | `soins>bandages` | craft_iode, craft_crafted_gauze, craft_field_dressing, craft_elastic_bandage |
| `weapons` | 22 | `armes>-` | craft_smallboat, craft_WEAPON_COMBATPISTOL, craft_WEAPON_HEAVYPISTOL, craft_WEAPON_PISTOL |
| `weapon_repair` | 21 | `armes>reparation` | craft_WEAPON_COMBATPISTOL_repair, craft_WEAPON_HEAVYPISTOL_repair, craft_WEAPON_PISTOL_repair, craft_WEAPON_KHANREV_repair |
| `radio` | 12 | `electricite>radio` | craft_circuit_imprime, craft_battery_weak, craft_battery, craft_radio |
| `appliances` | 11 | `equipement>appareils` | craft_v_res_tt_fridge, craft_water_table, craft_WEAPON_HUNTERHATCHET, craft_WEAPON_BLADEDBAT |
| `paint` | 11 | `mecanique>carrosserie` | craft_suspension_d, craft_suspension_s, craft_brake_d, craft_brake_s |
| `cooker` | 10 | `cuisine>-` | craft_canned_corn, craft_canned_rabbit, craft_canned_fish, craft_canned_chicken_peas |
| `artisan_prod` | 8 | `agriculture>-` | craft_ruche_table, craft_plant_table, craft_drying_crate, craft_fermenter |
| `repair_kits` | 7 | `outils>reparation` | craft_extras_controller, craft_engine_repair_kit, craft_body_repair_kit, craft_hqm-window |
| `weapon_body` | 7 | `armes>corps` | craft_devhub_attachment_flashlight1, craft_devhub_attachment_suppressor1, craft_devhub_attachments_tint, craft_devhub_attachment_clip1 |
| `shellfish` | 6 | `cuisine>crustaces` | craft_cut_crusta_bluecrab, craft_cut_crusta_dungenesscrab, craft_cut_crusta_redcrab, craft_cut_crusta_rockcrab |
| `all` | 6 | `divers>-` | craft_WEAPON_SCANNER, craft_bicycle_tire, craft_bolthead_x3, craft_ammo-arrow-titanium |
| `smelting` | 6 | `construction>fonderie` | craft_adfurnace_table, craft_util_table, craft_manche, craft_alliage |
| `meats` | 5 | `cuisine>viandes` | craft_packaged_chicken_chicken_carcasse, craft_rabbit_meat_rabbit_carcasse, craft_doe_meat_doe_carcass, craft_raw_meat_boar_carcasse |
| `powders` | 5 | `survie>eau` | craft_dough, craft_black_powder, craft_medium_water_tank, craft_large_water_tank |
| `gadgets` | 4 | `equipement>gadgets` | craft_binoculars, craft_med_kit, craft_ticket_soin, craft_ticket_soin__survie |
| `lamps` | 4 | `electricite>eclairage` | craft_backpack_small, craft_backpack_medium, craft_backpack_large, craft_backpack_big |
| `weapon_barrel` | 4 | `armes>canons` | craft_goldfish, craft_pistol_barrel, craft_bzzz_weapon_sawnoff_d, craft_rifle_barrel |
| `batteries` | 4 | `electricite>batteries` | craft_6v_battery, craft_12v_battery, craft_24v_battery, craft_chest3 |
| `med_kits` | 4 | `soins>kits` | craft_schemas_pistolet, craft_schemas_fusil_a_pompe, craft_schemas_fusil_d_assaut, craft_chest2 |
| `ammo` | 4 | `munitions>-` | craft_ammo_9, craft_ammo_44, craft_ammo_shotgun, craft_ammo_rifle |
| `bags` | 3 | `equipement>sacs` | craft_freezebag, craft_tarponfish, craft_killerwhale |
| `electricity` | 3 | `electricite>-` | craft_tc, craft_capture_kit, craft_epinglecheveux |
| `painkillers` | 3 | `mecanique>pneumatiques` | craft_chambre_air, craft_kit_entretien_velo, craft_vehicle_gps |
| `techno` | 2 | `equipement>tech` | craft_pegasus_carrier, craft_armstrong_carrier |
| `armor` | 2 | `equipement>protections` | craft_pegasus_light_repair_plate, armstrong_elite_repair_plate |
| `consumables` | 2 | `agriculture>consommables` | craft_fertilizer, craft_soil |
| `tickets` | 1 | `divers>-` | craft_radway |
| `farm_equipment` | 1 | `agriculture>equipement` | craft_sprinkler |
| `tires` | 1 | `equipement>-` | craft_cosmetics |
| `vehicle_customs` | 1 | `mecanique>customs` | craft_portable_garage |
| `survie` | 1 | `survie>-` | craft_gloves |

## Example overrides (brief)
- `craft_smallboat` (Petit Bateau): `weapons` → `transport>nautique`
- `craft_chambre_air` (Chambre Air): `painkillers` → `mecanique>pneumatiques`
- `craft_kit_entretien_velo` (Kit Entretien Velo): `painkillers` → `mecanique>entretien`
- `craft_vehicle_gps` (Vehicle Gps): `painkillers` → `transport>navigation`
- `craft_bandage` (Bandage): `bandages` → `soins>bandages`
- `craft_black_powder` (Black Powder): `powders` → `chimie>poudres`

## New main categories
- `survie`: 4 recipes
- `soins`: 28 recipes
- `outils`: 43 recipes
- `equipement`: 22 recipes
- `construction`: 31 recipes
- `mecanique`: 15 recipes
- `electricite`: 23 recipes
- `armes`: 94 recipes
- `munitions`: 4 recipes
- `cuisine`: 50 recipes
- `agriculture`: 55 recipes
- `chimie`: 1 recipes
- `transport`: 2 recipes
- `divers`: 7 recipes
