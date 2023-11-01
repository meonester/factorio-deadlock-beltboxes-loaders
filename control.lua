local STACK_SIZE = settings.startup['deadlock-stack-size'].value

-- work with directions
local opposite = {
	[defines.direction.north] = defines.direction.south,
	[defines.direction.south] = defines.direction.north,
	[defines.direction.east] = defines.direction.west,
	[defines.direction.west] = defines.direction.east,
}
local dir2vector = {
	[defines.direction.north] = {x=0, y=-1},
	[defines.direction.south] = {x=0, y=1},
	[defines.direction.east] = {x=1, y=0},
	[defines.direction.west] = {x=-1, y=0},
}

-- add vectors
local function add_vectors(v1, v2)
	return {v1.x + v2.x, v1.y + v2.y}
end

-- return single neighbour in specified direction
local function check_adjecent_in_direction(entity, target, direction)
	local entities = entity.surface.find_entities_filtered{type = target.type,  position = add_vectors(entity.position, dir2vector[direction])}
	for _, item in pairs(entities) do
		if item == target then return {target} end
	end
	return {}
end

-- return all entities 1 tile away in specified direction
local function get_adjecent_entities_in_direction(entity, direction)
	return entity.surface.find_entities_filtered{ position = add_vectors(entity.position, dir2vector[direction]) }
end

local function get_adjecent_loaders(entity)
	local position = entity.position
	local box = entity.prototype.selection_box
	local area = {
	  {position.x + box.left_top.x-1, position.y + box.left_top.y-1},
	  {position.x + box.right_bottom.x + 1, position.y + box.right_bottom.y + 1}
	}
	return entity.surface.find_entities_filtered{type='loader-1x1', area=area, force=entity.force}
  end

-- does any entity in list have an inventory we can work with
local function any_loadable(entities)
	for _,entity in pairs(entities) do
		--log('\n' .. entity.name .. ' ' .. serpent.block(entity.type))
		if entity.get_inventory(defines.inventory.chest) or
			entity.get_inventory(defines.inventory.furnace_source) or
			entity.get_inventory(defines.inventory.assembling_machine_input) or
			entity.get_inventory(defines.inventory.lab_input) or
			entity.get_inventory(defines.inventory.rocket_silo_rocket)
		then return true end
	end
	return false
end

-- belt facing detection
local function any_belt_facing(entities, direction)
	for _,entity in pairs(entities) do
		if (entity.type == 'transport-belt' or
			entity.type == 'underground-belt' or
			entity.type == 'splitter' or
			entity.type == 'loader-1x1') and
			entity.direction == direction
		then return true end
	end
	return false
end

-- if there's a belt behind, mode follows the direction of the belt
-- else if there's a belt ahead, stop
-- else if there's an inventory behind but not ahead, turn around
-- else if there's an inventory ahead but not behind, turn around and switch mode
-- else if no inventories and a belt ahead, turn around; also switch mode if belt is facing towards
local function on_built_entity(event)
	local built = event.created_entity
	-- invalid build? don't bother with faked 'revived' property from pre-1.0 Nanobots/Bluebuild, those shenanigans can only be passed in script_raised_* events now
    -- also no need to check entity type since we can filter for it on the event handler
	if not built or not built.valid then
		return
	end

	local snap2inv = settings.get_player_settings(game.players[event.player_index])['deadlock-loaders-snap-to-inventories'].value
	local snap2belt = settings.get_player_settings(game.players[event.player_index])['deadlock-loaders-snap-to-belts'].value
	-- no need to check anything if configs are off
	if not snap2inv and not snap2belt then
		return
	end

	if not event.revived and built.type == 'loader-1x1' then

		local loader = built;
		local belt_side_direction = loader.direction
		-- if loader in input mode, switch
		if loader.loader_type == 'input' then belt_side_direction = opposite[loader.direction] end

		local belt_end_entities = get_adjecent_entities_in_direction(loader, belt_side_direction)
		local loading_end_entities = get_adjecent_entities_in_direction(loader, opposite[belt_side_direction])

		if snap2belt and any_belt_facing(belt_end_entities, loader.direction) then
			-- belt on belt side, same direction
		elseif snap2belt and any_belt_facing(belt_end_entities, opposite[loader.direction]) then
			-- belt on belt side, opposite direction
			loader.rotate( {by_player = event.player_index} )
		elseif snap2inv and any_loadable(loading_end_entities) then
			-- inventory on loading side
			if any_belt_facing(belt_end_entities, opposite[loader.direction]) then
				loader.rotate( {by_player = event.player_index} )
			end
		elseif snap2inv and any_loadable(belt_end_entities) then
			-- inventory on belt side
			loader.direction = opposite[loader.direction]
			if any_belt_facing(loading_end_entities, opposite[loader.direction]) then
				loader.rotate( {by_player = event.player_index} )
			end
		elseif snap2belt and any_belt_facing(loading_end_entities, loader.direction) then
			-- belt on loading on belt side, same direction
			loader.direction = opposite[loader.direction]
			loader.rotate( {by_player = event.player_index} )
		elseif snap2belt and any_belt_facing(loading_end_entities, opposite[loader.direction]) then
			-- belt on loading on belt side, opposite direction
			loader.direction = opposite[loader.direction]
		end
		--loader.surface.create_entity{name='flying-text', position={loader.position.x-.25, loader.position.y-.5}, text = '^', color = {g=1}}

	elseif not event.revived then
		-- this part tries to switch direction and/or rotate loader if something was placed next to it

		local loaders = get_adjecent_loaders(built)
		for _, loader in pairs(loaders) do

			local belt_side_direction = loader.direction
			-- if loader in input mode, switch
			if loader.loader_type == 'input' then belt_side_direction = opposite[loader.direction] end

			local belt_end_entity = check_adjecent_in_direction(loader, built, belt_side_direction)
			local loading_end_entity = check_adjecent_in_direction(loader, built, opposite[belt_side_direction])

			if snap2belt and any_belt_facing(belt_end_entity, loader.direction) then
				-- belt on belt side, same direction
			elseif snap2belt and any_belt_facing(belt_end_entity, opposite[loader.direction]) then
				-- belt on belt side, opposite direction
				loader.rotate( {by_player = event.player_index} )
			elseif snap2inv and any_loadable(loading_end_entity) then
				-- inventory on loading side
				belt_end_entity = get_adjecent_entities_in_direction(loader, belt_side_direction)
				if any_belt_facing(belt_end_entity, opposite[loader.direction]) then
					loader.rotate( {by_player = event.player_index} )
				end
			elseif snap2inv and any_loadable(belt_end_entity) then
				-- inventory on belt side
				loader.direction = opposite[loader.direction]

				loading_end_entity = get_adjecent_entities_in_direction(loader, opposite[belt_side_direction])
				if any_belt_facing(loading_end_entity, opposite[loader.direction]) then
					loader.rotate( {by_player = event.player_index} )
				end
			elseif snap2belt and any_belt_facing(loading_end_entity, loader.direction) then
				-- belt on loading on belt side, same direction
				loader.direction = opposite[loader.direction]
				loader.rotate( {by_player = event.player_index} )
			elseif snap2belt and any_belt_facing(loading_end_entity, opposite[loader.direction]) then
				-- belt on loading on belt side, opposite direction
				loader.direction = opposite[loader.direction]
			end
			--loader.surface.create_entity{name='flying-text', position={loader.position.x-.25, loader.position.y-.5}, text = '*', color = {r=1}}
		end
	end
end

local built_event_filters = {
	{filter = 'type', type = 'loader-1x1'},
	{filter = 'type', type = 'transport-belt'},
	{filter = 'type', type = 'underground-belt'},
	{filter = 'type', type = 'splitter'},
	{filter = 'type', type = 'container'},
	{filter = 'type', type = 'assembling-machine'},
	{filter = 'type', type = 'furnace'},
	{filter = 'type', type = 'lab'},
}
script.on_event(defines.events.on_built_entity, on_built_entity, built_event_filters)

-- auto-unstacking by ownlyme
local function auto_unstack(item_name, item_count, sending_inventory, receiving_inventory)
	-- item_name: The name of the stacked item which should be unstacked
	-- item_count: The number of items that should be unstacked
	-- sending_inventory: the inventory that contains the stacked item
	-- receiving_inventory: the inventory that receives the unstacked items
	if string.sub(item_name, 1, 15) == 'deadlock-stack-' then
		-- attempt to auto-unstack
		-- try to add a stack worth of the source item to the inventory
		local add_count = STACK_SIZE
		-- if the base item's stack size is lower than the configured STACK_SIZE then
		-- this should reward the lower of the two
		local prototype = game.item_prototypes[string.sub(item_name, 16)]
		if STACK_SIZE > prototype.stack_size then
			add_count = prototype.stack_size
		end
		local inserted = receiving_inventory.insert({
			name = string.sub(item_name, 16),
			count = add_count * item_count,
		})

		local partial_inserted = inserted % add_count
		-- if player inventory is nearly full it may happen that just 8 items are inserted with add_count==5
		-- partial inserted then will be 3
		if partial_inserted > 0 then
			receiving_inventory.remove({
				name = string.sub(item_name, 16),
				count = partial_inserted,
			})
		end
		-- now remove the inserted items in their stacked variant. With the example above this is 1 stacked item
		local full_stack_inserted = math.floor(inserted / add_count)
		if full_stack_inserted > 0 then
			sending_inventory.remove({
				name = item_name,
				count = full_stack_inserted,
			})
		end
	end
end

local inventories_to_check = {
	defines.inventory.chest,
	defines.inventory.furnace_source,
	defines.inventory.furnace_result,
	defines.inventory.cargo_wagon,
	defines.inventory.assembling_machine_input,
	defines.inventory.assembling_machine_output,
	defines.inventory.robot_cargo,
}
local function try_unstacking(entity, inventory_type, player_inventory)
	local mined_entity_inventory = entity.get_inventory(inventory_type)
	if mined_entity_inventory then
		for item_name, item_count in pairs(mined_entity_inventory.get_contents()) do
			auto_unstack(item_name, item_count, mined_entity_inventory, player_inventory)
		end
	end
end

local function on_pre_player_mined_item(event)
	local player_inventory = game.players[event.player_index].get_main_inventory()

	for i, v in ipairs(inventories_to_check) do
		try_unstacking(event.entity, v, player_inventory)
	end
end
local function on_picked_up_item(event)
	local player_inventory = game.players[event.player_index].get_main_inventory()
	auto_unstack(event.item_stack.name, event.item_stack.count, player_inventory, player_inventory)
end
local function on_player_mined_entity(event)
	local player_inventory = game.players[event.player_index].get_main_inventory()
	for item_name, item_count in pairs(event.buffer.get_contents()) do
		auto_unstack(item_name, item_count, event.buffer, player_inventory)
	end
end
-- conditionally register based on the state of the setting so it's not costing any performance when disabled
local function on_load(event)
	if settings.startup['deadlock-stacking-auto-unstack'].value then
		script.on_event(defines.events.on_picked_up_item, on_picked_up_item) -- works on items that are picked up with f key
		script.on_event(defines.events.on_player_mined_item, on_picked_up_item) -- works on items which are directly mined from the ground
		script.on_event(defines.events.on_player_mined_entity, on_player_mined_entity) -- works on mined belts that carry items
		script.on_event(defines.events.on_pre_player_mined_item, on_pre_player_mined_item) -- works on mined entities with inventories that carry items
	end
end
script.on_load(on_load)
script.on_init(on_load)

local function on_configuration_changed(config)
	-- scan the forces' technologies for any of our loaders or beltboxes that should be
	-- unlocked but aren't, likely due to the mod adding them just being added to the save
	for _, force in pairs(game.forces) do
		for tech_name, tech_table in pairs(force.technologies) do
			if tech_table.researched then
				-- find any beltboxes or loaders or stacks in effects and unlock
				for _, effect_table in ipairs(tech_table.effects) do
					if effect_table.type == 'unlock-recipe' and (string.find(game.recipe_prototypes[effect_table.recipe].order, '%-deadlock%-') or string.find(game.recipe_prototypes[effect_table.recipe].name, 'deadlock%-')) then
						force.recipes[effect_table.recipe].enabled = true
					end
				end
			end
		end
	end
end
script.on_configuration_changed(on_configuration_changed)
