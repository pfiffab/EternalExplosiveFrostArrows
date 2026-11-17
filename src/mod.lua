print("Initializing Eternal Explosive Frost Arrows")

local EXPLOSIVE_PROJECTILE = "2e209031-85bf-4c0b-8aa2-0eb92e8c5bd7"
local EXPLOSIVE_BLAST_TEMPLATE = "33c000db-c758-4a33-915d-d11ac9d17f55"
local FROST_BLAST_TEMPLATE = "5337ddc5-7635-44f3-86fa-6c575f64afa0"
local EXPLOSIVE_TAG = "a2c14281-290e-4fa7-8785-bf339fb70bf7"
local ITEM_TYPE = "keen::ItemInfo"
local TEMPLATE_TYPE = "keen::ecs::TemplateResource"

-- Vanilla explosive donors correspond to the three Frost Arrow tiers by index.
local EXPLOSIVE_ARROWS = {
    "e39d3729-1228-4923-9b37-893873d3106f",
    "6388dda8-99a2-4d4d-bef6-cc56d8640fd6",
    "be44ab34-5a3a-43d4-a459-228c38117478"
}

local function find_config(configs, type_name)
    local found
    for index, entry in ipairs(configs) do
        if tostring(entry.type) == type_name then
            assert(not found, "Duplicate impact config: " .. type_name)
            found = index
        end
    end
    return found
end

local function find_component(components, type_name)
    local found
    for index, component in ipairs(components) do
        if tostring(component.type) == type_name then
            assert(not found, "Duplicate projectile component: " .. type_name)
            found = index
        end
    end
    return found
end

-- Find the Eternal Frost Arrow items by debugName, sorted by tier
local function find_frost_arrows()
    local ok, all = pcall(game.assets.get_resources_by_type, ITEM_TYPE)
    if not ok or type(all) ~= "table" then
        print("[Eternal Explosive Frost Arrows] get_resources_by_type failed: " .. tostring(all))
        return {}
    end

    local found = {}
    for k, v in pairs(all) do
        local guid
        for _, candidate in ipairs({ k, v }) do
            local s = tostring(candidate)
            if s:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then guid = s break end
        end
        if not guid then
            pcall(function() guid = tostring(v.data.objectId) end)
        end

        if guid then
            local ok2, res = pcall(game.assets.get_resource, guid, ITEM_TYPE, 0)
            if ok2 and res then
                local name = ""
                pcall(function() name = tostring(res.data.debugName) end)
                if name:find("Arrow_Magic_Ice_Eternal", 1, true) and not name:find("_icon", 1, true) then
                    local tier = tonumber(name:match("Ammo_T(%d+)_")) or 99
                    table.insert(found, { tier = tier, guid = guid, name = name, resource = res })
                end
            end
        end
    end

    table.sort(found, function(a, b) return a.tier < b.tier end)
    return found
end

local frost = find_frost_arrows()
print("[Eternal Explosive Frost Arrows] Found " .. #frost .. " frost arrow items")
for _, item in ipairs(frost) do print("  " .. item.name .. " = " .. item.guid) end

local explosive_projectile = game.assets.get_resource(EXPLOSIVE_PROJECTILE, TEMPLATE_TYPE, 0)
assert(explosive_projectile, "Missing explosive projectile template")
local explosive_components = explosive_projectile.data.components

local function apply_explosive_impact(frost_item)
    local projectile_guid = tostring(frost_item.resource.data.equipment.placedEntity)
    local frost_projectile = game.assets.get_resource(projectile_guid, TEMPLATE_TYPE, 0)
    assert(frost_projectile, "Missing frost projectile template for " .. frost_item.name)

    local frost_components = frost_projectile.data.components
    for _, component_type in ipairs({"keen::ecs::Impact", "keen::ecs::ImpactConfiguration"}) do
        local frost_index = find_component(frost_components, component_type)
        local explosive_index = find_component(explosive_components, component_type)
        assert(frost_index and explosive_index, "Missing " .. component_type .. " on projectile")

        local explosive_value = explosive_components[explosive_index].value
        if component_type == "keen::ecs::ImpactConfiguration" then
            local simple = {}
            local replaced_template = false

            for config_index, config in ipairs(explosive_value.configValues.simple) do
                if tostring(config.type) == "keen::impact::TemplateImpactConfig"
                    and tostring(config.value.value) == EXPLOSIVE_BLAST_TEMPLATE then
                    simple[config_index] = {
                        type = config.type,
                        value = {
                            value = FROST_BLAST_TEMPLATE,
                            locaTag = config.value.locaTag,
                            isSigned = config.value.isSigned,
                            valueFormat = config.value.valueFormat,
                            id = config.value.id,
                            configId = config.value.configId,
                            type = config.value.type,
                            configGuid = config.value.configGuid,
                            objectId = config.value.objectId
                        }
                    }
                    replaced_template = true
                else
                    simple[config_index] = config
                end
            end

            assert(replaced_template, "Explosive blast template reference not found")
            frost_components[frost_index].value = {
                configValues = {
                    simple = simple,
                    scaled = explosive_value.configValues.scaled
                },
                damageDistribution = explosive_value.damageDistribution,
                damageDistributionIsSet = explosive_value.damageDistributionIsSet
            }
        else
            frost_components[frost_index].value = explosive_value
        end
    end

    print("[Eternal Explosive Frost Arrows] Applied explosive impact to " .. frost_item.name
        .. " with frost blast template; retaining frost projectile " .. projectile_guid)
end

for index, entry in ipairs(frost) do
    local donor_guid = EXPLOSIVE_ARROWS[index]
    if donor_guid then
        local data = entry.resource.data
        local donor = game.assets.get_resource(donor_guid, ITEM_TYPE, 0)
        assert(donor, "Missing Explosive Arrow reference for tier " .. index)

        local dist = data.damageSetup.distribution
        if dist.magicalIceDamage == 0 or dist.magicalFireDamage ~= 0 then
            print("[Eternal Explosive Frost Arrows] WARNING: unexpected damage type on " .. entry.name
                .. " (ice=" .. tostring(dist.magicalIceDamage)
                .. ", fire=" .. tostring(dist.magicalFireDamage) .. ")")
        end

        local configs = data.impactValues.simple
        local donor_configs = donor.data.impactValues.simple

        local category_type = "keen::impact::AttackCategoryMaskConfig"
        local category = find_config(configs, category_type)
        local donor_category = find_config(donor_configs, category_type)
        if category and donor_category then
            configs[category] = donor_configs[donor_category]
        else
            print("[Eternal Explosive Frost Arrows] WARNING: no attack category config on " .. entry.name)
        end

        for _, field in ipairs({"woodDamage", "stoneDamage", "metalDamage"}) do
            dist[field] = donor.data.damageSetup.distribution[field]
        end

        local terrain_type = "keen::impact::DamageTerraformingSetupConfig"
        local donor_terrain = find_config(donor_configs, terrain_type)
        assert(donor_terrain, "Missing explosive terraforming config")
        local terrain = find_config(configs, terrain_type)
        if terrain then
            configs[terrain] = donor_configs[donor_terrain]
        else
            table.insert(configs, donor_configs[donor_terrain])
        end

        apply_explosive_impact(entry)

        local has_tag = false
        for _, tag in ipairs(data.tags) do
            if tostring(tag.tag) == EXPLOSIVE_TAG then has_tag = true break end
        end
        if not has_tag then
            table.insert(data.tags, { tag = EXPLOSIVE_TAG, nominator = 21, denominator = 1 })
        end
    end
end

print("Done Initializing Eternal Explosive Frost Arrows")