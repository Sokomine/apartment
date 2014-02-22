
local handle_schematics = {}

-- node name used to indicate where the building will eventually be placed
handle_schematics.SCAFFOLDING = 'random_buildings:support';

handle_schematics.AUTODECAY   = 'apartment:autodecay';

-- taken from https://github.com/MirceaKitsune/minetest_mods_structures/blob/master/structures_io.lua (Taokis Sructures I/O mod)
-- gets the size of a structure file
-- nodenames: contains all the node names that are used in the schematic
-- on_constr: lists all the node names for which on_construct has to be called after placement of the schematic
handle_schematics.analyze_mts_file = function( path )
	local size = { x = 0, y = 0, z = 0, version = 0 }
	local version = 0;

	local file = io.open(path..'.mts', "r")
	if (file == nil) then
		return nil
	end

	-- thanks to sfan5 for this advanced code that reads the size from schematic files
	local read_s16 = function(fi)
		return string.byte(fi:read(1)) * 256 + string.byte(fi:read(1))
	end

	local function get_schematic_size(f)
		-- make sure those are the first 4 characters, otherwise this might be a corrupt file
		if f:read(4) ~= "MTSM" then
			return nil
		end
		-- advance 2 more characters
		local version = read_s16(f); --f:read(2)
		-- the next characters here are our size, read them
		return read_s16(f), read_s16(f), read_s16(f), version
	end

	size.x, size.y, size.z, size.version = get_schematic_size(file)
	
	-- read the slice probability for each y value that was introduced in version 3
	if( size.version >= 3 ) then
		-- the probability is not very intresting for buildings so we just skip it
		file:read( size.y );
	end


	-- this list is not yet used for anything
	local nodenames = {};
	-- this list is needed for calling on_construct after place_schematic
	local on_constr = {};
	-- nodes that require after_place_node to be called
	local after_place_node = {};

	-- after that: read_s16 (2 bytes) to find out how many diffrent nodenames (node_name_count) are present in the file
	local node_name_count = read_s16( file );

	for i = 1, node_name_count do

		-- the length of the next name
		local name_length = read_s16( file );
		-- the text of the next name
		local name_text   = file:read( name_length );

		table.insert( nodenames, name_text );
		-- in order to get this information, the node has to be defined and loaded
		if( minetest.registered_nodes[ name_text ] and minetest.registered_nodes[ name_text ].on_construct) then
			table.insert( on_constr, name_text );
		end
		-- some nodes need after_place_node to be called for initialization
		if( minetest.registered_nodes[ name_text ] and minetest.registered_nodes[ name_text ].after_place_node) then
			table.insert( after_place_node, name_text );
		end
	end

	file.close(file)

	local rotated = 0;
	local burried = 0;
	local parts = path:split('_');
	if( parts and #parts > 2 ) then
		if( parts[#parts]=="0" or parts[#parts]=="90" or parts[#parts]=="180" or parts[#parts]=="270" ) then
			rotated = tonumber( parts[#parts] );
			burried = tonumber( parts[ #parts-1 ] );
			if( not( burried ) or burried>20 or burried<0) then
				burried = 0;
			end
		end
	end
	return { size = { x=size.x, y=size.y, z=size.z}, nodenames = nodenames, on_constr = on_constr, after_place_node = after_place_node, rotated=rotated, burried=burried };
end


-- depending on the orientation (param2) of the build chest, the start position of the building may have to be moved;
-- this function makes sure that the building will always extend to the right and in front of the build chest
handle_schematics.translate_param2_to_rotation = function( param2, mirror, start_pos, orig_max, rotated, burried  )

	local max = {x=orig_max.x, y=orig_max.y, z=orig_max.z};
	-- if the schematic has been saved in a rotated way, swapping x and z may be necessary
	if( rotated==90 or rotated==270) then
		max.x = orig_max.z;
		max.z = orig_max.x;
	end

	-- the building may have a cellar or something alike
	if( burried > 0 ) then
		start_pos.y = start_pos.y - burried;
	end

	-- make sure the building always extends forward and to the right of the player
	local rotate = 0;
	if(     param2 == 0 ) then rotate = 270; if( mirror==1 ) then start_pos.x = start_pos.x - max.x + max.z; end -- z gets larger
	elseif( param2 == 1 ) then rotate =   0;    start_pos.z = start_pos.z - max.z; -- x gets larger  
	elseif( param2 == 2 ) then rotate =  90;    start_pos.z = start_pos.z - max.x;
	                       if( mirror==0 ) then start_pos.x = start_pos.x - max.z; -- z gets smaller 
	                       else                 start_pos.x = start_pos.x - max.x; end
	elseif( param2 == 3 ) then rotate = 180;    start_pos.x = start_pos.x - max.x; -- x gets smaller 
	end

	if(     param2 == 1 or param2 == 0) then
		start_pos.z = start_pos.z + 1;
	elseif( param2 == 1 or param2 == 2 ) then
		start_pos.x = start_pos.x + 1;
	end
	if( param2 == 1 ) then
		start_pos.x = start_pos.x + 1;
	end

	rotate = rotate + rotated;
	-- make sure the rotation does not reach or exceed 360 degree
	if( rotate >= 360 ) then
		rotate = rotate - 360;
	end
	-- rotate dimensions when needed
	if( param2==0 or param2==2) then
		local tmp = max.x;
		max.x = max.z;
		max.z = tmp;
	end

	return { rotate=rotate, start_pos = {x=start_pos.x, y=start_pos.y, z=start_pos.z},
				end_pos   = {x=(start_pos.x+max.x-1), y=(start_pos.y+max.y-1), z=(start_pos.z+max.z-1) },
				max       = {x=max.x, y=max.y, z=max.z}};
end



-- call on_construct and after_place_node for nodes that require it;
-- set up steel doors in a usable way;
-- set up apartments from the apartment mod;
-- placer is the player who initialized the placement of the schematic (placer will be passed on to after_place_node etc)
handle_schematics.update_nodes = function( start_pos, end_pos, on_constr, after_place_node, placer )

	local p={};
	local i=0;
	local v=0;
	-- call on_construct for all the nodes that require it
	for i, v in ipairs( on_constr ) do

		-- there are only very few nodes which need this special treatment
		local nodes = minetest.find_nodes_in_area( start_pos, end_pos, v);

		for _, p in ipairs( nodes ) do
			minetest.registered_nodes[ v ].on_construct( p );
		end
	end

	if( placer ) then
		for i, v in ipairs( after_place_node ) do

			-- there are only very few nodes which need this special treatment
				local nodes = minetest.find_nodes_in_area( start_pos, end_pos, v);

				for _, p in ipairs( nodes ) do
					minetest.registered_nodes[ v ].after_place_node( p, placer, nil, nil );
				end
		 end

		local player_name = placer:get_player_name();

		-- steel doors are annoying because the cannot be catched with the functions above
		local doornodes = minetest.find_nodes_in_area( start_pos, end_pos,
				{'doors:door_steel_b_1','doors:door_steel_b_2',
				 'doors:door_steel_t_1','doors:door_steel_t_2'});
		for _, p in ipairs( doornodes ) do
			local meta = minetest.get_meta( p );
			meta:set_string("doors_owner", player_name );
			meta:set_string("infotext", "Owned by "..player_name)
		end

		-- prepare apartment rental panels
		local nodes = minetest.find_nodes_in_area( start_pos, end_pos, {'apartment:apartment'} );
		for _, p in ipairs(nodes ) do
			local meta  = minetest.get_meta( p );
			meta:set_string( 'original_owner', player_name );
	
			-- lua can't count variables of this type on its own...
			local nr = 1;
			for _, _ in pairs( apartment.apartments ) do
				nr = nr+1;
			end
			-- TODO: this depends on relative position and param2 of the formspec
			local fields = {
				quit=true, store=true,
				size_left=2, size_right=1, size_up=2, size_down=1, size_front=1, size_back=6,
				category='apartment',
				-- numbering them all seems best
				descr='Apartment #'..tostring( nr ) };

			-- configure and prepare the apartment
			apartment.on_receive_fields( p, nil, fields, placer);
		end

	end
end


handle_schematics.place_schematic = function( pos, param2, path, mirror, replacement_function, replacement_param, placer, do_copies )

	local node = minetest.env:get_node( pos );
	if( not( node ) or not( node.param2 ) or node.name=="air") then
		if( not( param2 )) then
			return false;
		end
		node = {name="", param2 = param2 };
	end

	local building_data = handle_schematics.analyze_mts_file( path );
	local position_data = handle_schematics.translate_param2_to_rotation( node.param2, mirror, pos, building_data.size, building_data.rotated, building_data.burried );

	local replacements = {};
	if( replacement_function ) then
		replacements = replacement_function( building_data.nodenames, replacement_param );
	elseif( replacement_param and not replacement_param.even ) then
		replacements = replacement_param;
	end
		

	local force_place = true;
	-- when building scaffolding, do not replace anything yet
	if( replacement_function and replacement_function == handle_schematics.replacement_function_scaffolding ) then
		force_place = false;
	end

	table.insert( building_data.on_constr,        'default:chest' );
	-- actually place the schematic
	if( not( do_copies ) or not( do_copies.h ) or not( do_copies.v )) then
		minetest.place_schematic( position_data.start_pos, path..'.mts', tostring(position_data.rotate), replacements, force_place );

		handle_schematics.update_nodes( position_data.start_pos, position_data.end_pos,
								building_data.on_constr, building_data.after_place_node, placer );
	else
		-- place multiple copies
		local vector = {h=-1,v=1};
		if( node.param2 == 0 or node.param2 == 3) then --node.param2 == 1 or node.param2 == 3 ) then
			vector.h = 1;
		end
			
		-- it looks best if every second house is built out of another material
		local replacements_even = replacements;
		local replacements_odd  = replacements;
		if( replacement_param and replacement_param.even and replacement_param.odd ) then
			replacements_even = replacement_param.even;
			replacements_odd  = replacement_param.odd;
		end
	
		local p = {x=position_data.start_pos.x , y=position_data.start_pos.y, z=position_data.start_pos.z };
		for j=1,do_copies.v do
			p.x = position_data.start_pos.x;	
			p.z = position_data.start_pos.z;
			for i=1,do_copies.h do -- horizontal copies			
				-- switch replacements between houses
				if( i%2==0 ) then
					minetest.place_schematic( p, path..'.mts', tostring(position_data.rotate), replacements_even, force_place );
				else
					minetest.place_schematic( p, path..'.mts', tostring(position_data.rotate), replacements_odd,  force_place );
				end

				handle_schematics.update_nodes( p, {x=p.x+position_data.max.x, y=p.y+position_data.max.y*j, z=p.z+position_data.max.z},
								building_data.on_constr, building_data.after_place_node, placer );

				if( node.param2 == 0 or node.param2 == 2 ) then 
					p.x = p.x + vector.h*position_data.max.x; 
				else
					p.z = p.z + vector.h*position_data.max.z; 
				end
			end
			p.y = p.y + vector.v*position_data.max.y;
		end

		if( node.param2 == 0 or node.param2 == 2 ) then 
			position_data.end_pos.x = position_data.start_pos.x + vector.h*position_data.max.x*do_copies.h;
		else
			position_data.end_pos.z = position_data.start_pos.z + vector.h*position_data.max.z*do_copies.v;
		end
		position_data.end_pos.y = position_data.start_pos.y + vector.v*position_data.max.y*do_copies.v;
	end
end



-- replace all nodes with scaffolding ones so that the player can see where the real building will be placed
handle_schematics.replacement_function_scaffolding = function( nodenames )

	local replacements = {};
	for _,v in ipairs( nodenames ) do
		table.insert( replacements, { v, handle_schematics.SCAFFOLDING })
	end
	return replacements;
end


-- places nodes that look like leaves at the positions where the building was;
-- those nodes will decay using an abm;
-- this gradual disappearance of the building helps to understand the player what
--    just happend (=building was removed) and where it happened
handle_schematics.replacement_function_decay = function( nodenames )

	local replacements = {};
	for _,v in ipairs( nodenames ) do
		table.insert( replacements, { v, handle_schematics.AUTODECAY })
	end
	return replacements;
end

local filename = "apartment_4x10_0_270";
--local filename = "apartment_4x6_0_90";

minetest.register_node("apartment:build_chest", {
	description = "Apartment spawner",
	tiles = {"default_chest_side.png", "default_chest_top.png^door_steel.png", "default_chest_side.png",
		"default_chest_side.png", "default_chest_side.png", "default_chest_lock.png^door_steel.png"},
	paramtype2 = "facedir",
	groups = {snappy=2,choppy=2,oddly_breakable_by_hand=2},
	legacy_facedir_simple = true,

	after_place_node = function(pos, placer, itemstack)

-- TODO: check if placement is allowed; read parameters (how many? what to replace? which schematic?) etc.
--		local path = minetest.get_modpath("apartment")..'/schems/apartment_4x6_0_90';
		local path = minetest.get_modpath("apartment")..'/schems/'..filename;
		local mirror = 0;
		local replacement_function = nil;
		local replacement_param    = { odd={{'default:clay','default:sandstonebrick'},
							{'inbox:empty','default:chest'},
							{'travelnet:travelnet','default:furnace'},
							{'stairs:slab_junglewood','stairs:slab_wood'},
							{'stairs:stair_junglewood','stairs:stair_wood'}},
					      even={{'default:clay','default:brick'},
							{'inbox:empty','default:chest'},
							{'travelnet:travelnet','default:furnace'},
							{'stairs:slab_junglewood','stairs:slab_wood'},
							{'stairs:stair_junglewood','stairs:stair_wood'}}};

--		replacement_param    = { odd={{'default:clay','default:desert_stone'},{'stairs:slab_junglewood','stairs:slab_sandstone'},{'stairs:stair_junglewood','stairs:stair_sandstone'}},
--					      even={{'default:clay','default:desert_stone'},{'stairs:slab_junglewood','stairs:slab_sandstone'},{'stairs:stair_junglewood','stairs:stair_sandstone'}}};

		minetest.chat_send_player( placer:get_player_name(), 'Placing building '..tostring( path ));

		minetest.chat_send_player( placer:get_player_name(), 'Placing building '..tostring( path ));
		handle_schematics.place_schematic( pos, nil, path, mirror, replacement_function, replacement_param, placer, {h=8,v=6} )
        end,

	-- if the building chest is removed, remove the building as well - and place nodes looking like leaves and autodecaying in order
 	-- to indicate where the building has been
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local path = minetest.get_modpath("apartment")..'/schems/'..filename;
		local mirror = 0;
		local replacement_function = handle_schematics.replacement_function_decay;
		local replacement_param    = nil;

		minetest.chat_send_player( digger:get_player_name(), 'Removing building '..tostring( path ));
		handle_schematics.place_schematic( pos, oldnode.param2, path, mirror, replacement_function, replacement_param, digger, {h=8,v=6} )
		
	end,
-- TODO: check if digging is allowed

})

--	local p1={x=position_data.start_pos.x, y=position_data.start_pos.y, z=position_data.start_pos.z };
--	local p2={x=position_data.end_pos.x,   y=position_data.end_pos.y,   z=position_data.end_pos.z };
--	minetest.set_node( {x=p1.x, y=p1.y, z=p1.z }, {name='wool:red'} );
--	minetest.set_node( {x=p1.x, y=p1.y, z=p2.z }, {name='wool:red'} );
--	minetest.set_node( {x=p2.x, y=p1.y, z=p1.z }, {name='wool:red'} );
--	minetest.set_node( {x=p2.x, y=p2.y, z=p2.z }, {name='wool:red'} );

minetest.register_node( handle_schematics.AUTODECAY, {
        description = "decaying building",
        drawtype = "allfaces_optional",
        visual_scale = 1.3,
        tiles = {"default_leaves.png"},
        paramtype = "light",
        waving = 1,
        is_ground_content = false,
        groups = {snappy=3},
})

minetest.register_abm({
        nodenames = {handle_schematics.AUTODECAY},
        -- A low interval and a high inverse chance spreads the load
        interval = 2,
        chance = 3,
	action = function(p0, node, _, _)
		minetest.remove_node( p0 );
	end
})
