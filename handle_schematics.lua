
local handle_schematics = {}

-- node name used to indicate where the building will eventually be placed
handle_schematics.SCAFFOLDING = 'random_buildings:support';

handle_schematics.AUTODECAY   = 'apartment:autodecay';

handle_schematics.ENABLE_SLOW_DECAY = false


minetest.register_privilege("apartment_spawn", { description = "allows you to spawn apartments", give_to_singleplayer = false});


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
handle_schematics.update_nodes = function( start_pos, end_pos, on_constr, after_place_node, placer, extra_params )

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
				 'doors:door_steel_t_1','doors:door_steel_t_2',
				 'doors:door_steel_a', 'doors:door_steel_b'});
		for _, p in ipairs( doornodes ) do
			local node = minetest.get_node( p );
			local meta = minetest.get_meta( p );
			if( not( node ) or not( node.name )) then
				-- do nothing
			elseif( node.name=='doors:door_steel_t_1' or node.name=='doors:door_steel_t_2') then
				-- replace top of old steel doors with new node
				minetest.swap_node( p, {name='doors:door_hidden', param2=node.param2} );
			else
				-- set the new owner
				meta:set_string("doors_owner", player_name );
				meta:set_string("infotext", "Owned by "..player_name)
				if(     node.name == 'doors:door_steel_b_1' ) then
					minetest.swap_node( p, {name='doors:door_steel_a', param2=nod3.param2});
				elseif( node.name == 'doors:door_steel_b_2' ) then
					minetest.swap_node( p, {name='doors:door_steel_b', param2=node.param2});
				end
			end
		end


		-- prepare apartment rental panels
		local nodes = minetest.find_nodes_in_area( start_pos, end_pos, {'apartment:apartment'} );
		if( extra_params and extra_params.apartment_type and extra_params.apartment_name ) then
			for _, p in ipairs(nodes ) do
				local meta  = minetest.get_meta( p );
				meta:set_string( 'original_owner', player_name );
		
				-- lua can't count variables of this type on its own...
				local nr = 1;
				for _, _ in pairs( apartment.apartments ) do
					nr = nr+1;
				end
				--  this depends on relative position and param2 of the formspec
				local fields = {
					quit=true, store=true,
	
					size_up    = math.abs(  end_pos.y - p.y-1),
					size_down  = math.abs(start_pos.y - p.y),
	
					norm_right = math.abs(  end_pos.x - p.x-1),
					norm_left  = math.abs(start_pos.x - p.x),
					norm_back  = math.abs(  end_pos.z - p.z-1),
					norm_front = math.abs(start_pos.z - p.z),
	
					category   = extra_params.apartment_type,
					-- numbering them all seems best
					descr      = extra_params.apartment_name
				}; 
	
				-- up and down are independent of rotation
				fields.size_up   = math.abs(  end_pos.y - p.y-1);
				fields.size_down = math.abs(start_pos.y - p.y);
	
				local node = minetest.get_node( p );
				if(     node.param2 == 0 ) then -- z gets larger
					fields.size_left  = fields.norm_left;  fields.size_right = fields.norm_right;
					fields.size_back  = fields.norm_back;  fields.size_front = fields.norm_front;
	
				elseif( node.param2 == 1 ) then -- x gets larger
					fields.size_left  = fields.norm_back;  fields.size_right = fields.norm_front;
					fields.size_back  = fields.norm_right; fields.size_front = fields.norm_left; 
	
				elseif( node.param2 == 2 ) then -- z gets smaller
					fields.size_left  = fields.norm_right; fields.size_right = fields.norm_left;
					fields.size_back  = fields.norm_front; fields.size_front = fields.norm_back;
	
				elseif( node.param2 == 3 ) then -- x gets smaller
					fields.size_left  = fields.norm_front; fields.size_right = fields.norm_back; 
					fields.size_back  = fields.norm_left;  fields.size_front = fields.norm_right;
				end
	
				-- configure and prepare the apartment
				apartment.on_receive_fields( p, nil, fields, placer);
			end
		end
	end
end


-- this is lua...it doesn't contain the basic functions
handle_schematics.table_contains = function( table, value )
	local i = 1;
	local v;
	for i, v in ipairs( table ) do
		if( v==value ) then
			return true;
		end
	end
	return false;
end


handle_schematics.place_schematic = function( pos, param2, path, mirror, replacement_function, replacement_param, placer, do_copies, extra_params )

	local node = minetest.env:get_node( pos );
	if( not( node ) or not( node.param2 ) or node.name=="air") then
		if( not( param2 )) then
			return false;
		end
		node = {name="", param2 = param2 };
	end

	local building_data = handle_schematics.analyze_mts_file( path );
	if( not( building_data ) or not( building_data.size )) then
		if( placer ) then
			minetest.chat_send_player( placer:get_player_name(), 'Could not place schematic. Please check the filename.');
		end
		return;
	end
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


	-- it is possible that replacements require calls to on_constr/after_place_node
	-- and that the nodes that are introduced through replacements where not present in the original schematic
	local all_replacements = {};
	for i, v in ipairs( replacements ) do
		table.insert( all_replacements, v[2] );
	end
	if( replacement_param and replacement_param.even and replacement_param.odd ) then
		for i, v in ipairs( replacement_param.even ) do
			table.insert( all_replacements, v[2] );
		end
		for i, v in ipairs( replacement_param.odd  ) do
			table.insert( all_replacements, v[2] );
		end
	end
	for i, v in ipairs( all_replacements ) do
			
		if( minetest.registered_nodes[ v ] and minetest.registered_nodes[ v ].on_construct
		  and not(handle_schematics.table_contains( building_data.on_constr, v ))) then
			table.insert( building_data.on_constr, v );
		end
		-- some nodes need after_place_node to be called for initialization
		if( minetest.registered_nodes[ v ] and minetest.registered_nodes[ v ].after_place_node
		  and not(handle_schematics.table_contains( building_data.after_place_node, v ))) then
			table.insert( building_data.after_place_node, v );
		end
	end


	-- apartments need a name if they are to be configured
	if( extra_params and not( extra_params.apartment_type )) then
		extra_params.apartment_type = 'apartment';
	end

	-- actually place the schematic
	if( not( do_copies ) or not( do_copies.h ) or not( do_copies.v )) then
		minetest.place_schematic( position_data.start_pos, path..'.mts', tostring(position_data.rotate), replacements, force_place );

		handle_schematics.update_nodes( position_data.start_pos, position_data.end_pos,
								building_data.on_constr, building_data.after_place_node, placer,
								extra_params );
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


				local key = '';
				local val = {};
				local p_end = {x=(p.x+position_data.max.x), y=(p.y+position_data.max.y), z=(p.z+position_data.max.z)};
				
				for key,val in pairs( apartment.apartments ) do
					if( val and val.pos 
					    and (val.pos.x >= p.x) and (val.pos.x <= p_end.x)
					    and (val.pos.y >= p.y) and (val.pos.y <= p_end.y)
					    and (val.pos.z >= p.z) and (val.pos.z <= p_end.z)) then

-- TODO: add FAIL if the apartment is still rented
						if( placer ) then
							minetest.chat_send_player( placer:get_player_name(), 'Removing Apartment '..tostring( key )..
								' (new usage for that place). Position: '..minetest.serialize( val.pos ));
						end
						print( 'Removing Apartment '..tostring( key )..' (new usage for that place). Position: '..minetest.serialize( val.pos ));
						apartment.apartments[ key ] = nil;
					end
				end
				-- switch replacements between houses
				if( i%2==0 ) then
					minetest.place_schematic( p, path..'.mts', tostring(position_data.rotate), replacements_even, force_place );
				else
					minetest.place_schematic( p, path..'.mts', tostring(position_data.rotate), replacements_odd,  force_place );
				end

				-- generate apartment name
				if( extra_params and extra_params.apartment_type and extra_params.apartment_house_name ) then
					local nr = i-1;
					local apartment_name = '';

					-- find the first free number for an apartment with this apartment_house_name
					while( nr < 99 and apartment_name == '' ) do
						nr = nr+1;
						apartment_name = extra_params.apartment_house_name..' '..tostring(j);
						if( nr < 10 ) then
							apartment_name = apartment_name..'0'..tostring(nr);
						elseif( nr<100 ) then
							apartment_name = apartment_name..tostring(nr);
						else
							apartment_name = '';
						end

						-- avoid duplicates
						if( apartment.apartments[ apartment_name ] ) then
							apartment_name = '';
						end
					end
					if( apartment_name ) then
						extra_params.apartment_name = apartment_name;
					else
						extra_params.apartment_name = nil;
						extra_params.apartment_type = nil;
					end

				end
				-- replacements_even/replacements_odd ought to affect only DECORATIVE nodes - and none that have on_construct/after_place_node!
				handle_schematics.update_nodes( p, {x=p.x+position_data.max.x, y=p.y+position_data.max.y, z=p.z+position_data.max.z},
								building_data.on_constr, building_data.after_place_node, placer, extra_params );

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
	return {start_pos = position_data.start_pos, end_pos = position_data.end_pos };
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
		if( handle_schematics.ENABLE_SLOW_DECAY ) then
			table.insert( replacements, { v, handle_schematics.AUTODECAY })
		else
			table.insert( replacements, { v, 'air' })
		end
	end
	return replacements;
end



handle_schematics.update_apartment_spawner_formspec = function( pos )
	
	local meta  = minetest.get_meta( pos );

	if( not( meta ) or not( meta:get_string('path')) or meta:get_string('path')=='') then
		return 'size[9,7]'..
			'label[2.0,-0.3;Apartment Spawner]'..
			'label[0.5,0.5;Load schematic from file:]'..
			'field[5.0,0.9;4.0,0.5;path;;apartment_4x11_0_180]'..
			'label[0.5,1.5;Name for this apartment house:]'..
			'field[5.0,1.9;4.0,0.5;apartment_house_name;;Enter house name]'..
			'label[0.5,2.0;Category (i.e. house, shop):]'..
			'field[5.0,2.4;4.0,0.5;apartment_type;;apartment]'..
			'label[0.5,2.5;Horizontal copies (to the left):]'..
			'field[5.0,2.9;0.5,0.5;h;;1]'..
			'label[0.5,3.0;Vertical copies (upwards):]'..
			'field[5.0,3.4;0.5,0.5;v;;1]'..
			'label[0.5,3.5;Replace clay in 1st building:]'..
			'field[5.0,3.9;4.0,0.5;replacement_1;;default:sandstonebrick]'..
			'label[0.5,4.0;Replace clay in 2nd building:]'..
			'field[5.0,4.4;4.0,0.5;replacement_2;;default:brick]'..
			'button_exit[4,6.0;2,0.5;store;Spawn building]'..
			'button_exit[1,6.0;1,0.5;abort;Abort]';
	end
	return 'size[9,7]'..
			'label[2.0,-0.3;Information about the spawned Apartment]'..
			'label[0.5,0.5;The schematic was loaded from:]'..
			'label[5.0,0.5;'..tostring( meta:get_string('path'))..']'..
			'label[0.5,1.5;Name for this apartment house:]'..
			'label[5.0,1.5;'..tostring( meta:get_string('apartment_house_name'))..']'..
			'label[0.5,2.0;Category (i.e. house, shop):]'..
			'label[5.0,2.0;'..tostring( meta:get_string('apartment_type'))..']'..
			'label[0.5,2.5;Horizontal copies (to the left):]'..
			'label[5.0,2.5;'..tostring( meta:get_string('h'))..']'..
			'label[0.5,3.0;Vertical copies (upwards):]'..
			'label[5.0,3.0;'..tostring( meta:get_string('v'))..']'..
			'label[0.5,3.5;Replace clay in 1st building:]'..
			'label[5.0,3.5;'..tostring( meta:get_string('replacement_1'))..']'..
			'label[0.5,4.0;Replace clay in 2nd building:]'..
			'label[5.0,4.0;'..tostring( meta:get_string('replacement_2'))..']'..
			'label[0.5,4.5;This building was spawned by:]'..
			'label[5.0,4.5;'..tostring( meta:get_string('placed_by'))..']'..
			'button_exit[4,6.0;2,0.5;store;Remove building]'..
			'button_exit[1,6.0;1,0.5;abort;OK]';
end


handle_schematics.on_receive_fields = function(pos, formname, fields, sender)

	local meta  = minetest.get_meta( pos );

	if( not( sender )) then
		return;
	end

	pname = sender:get_player_name();
	if( not( minetest.check_player_privs(pname, {apartment_spawn=true}))) then
		minetest.chat_send_player( pname, 'You do not have the necessary privileges.');
		return;
	end

	if( meta and (not( meta:get_string('path')) or meta:get_string('path')=='') and fields.store) then

		--  check if all params have been supplied
		if(  not( fields.path )
		  or not( fields.apartment_house_name ) or not( fields.apartment_type )
		  or not( fields.h )                    or not( fields.v )
		  or not( fields.replacement_1 )        or not( fields.replacement_2 )) then
			minetest.chat_send_player( pname, 'Please fill all fields with information.');
			return;
		end

		fields.h = tonumber( fields.h );
		if( fields.h < 1 or fields.h > 20 ) then
			fields.h = 1;
		end
		fields.h = tostring( fields.h );
		fields.v = tonumber( fields.v );
		if( fields.v < 1 or fields.v > 20 ) then
			fields.v = 1;
		end
		fields.v = tostring( fields.v );

		meta:set_string('path',                 fields.path );
		meta:set_string('apartment_house_name', fields.apartment_house_name );
		meta:set_string('apartment_type',       fields.apartment_type );
		meta:set_string('h',                    fields.h );
		meta:set_string('v',                    fields.v );
		meta:set_string('replacement_1',        fields.replacement_1 );
		meta:set_string('replacement_2',        fields.replacement_2 );
		meta:set_string('placed_by',            pname );

		meta:set_string('formspec',             handle_schematics.update_apartment_spawner_formspec( pos ));
		minetest.chat_send_player( pname, 'Placing building '..tostring( fields.path ));

		local path = minetest.get_modpath("apartment")..'/schems/'..fields.path;
		local mirror = 0;
		local replacement_function = nil;
		local replacement_param    = { odd={{'default:clay',fields.replacement_1}},
					      even={{'default:clay',fields.replacement_2}}};

		local res = {};
		res = handle_schematics.place_schematic( pos, nil, path, mirror,
				replacement_function, replacement_param,
				sender, {h=fields.h,v=fields.v},
				{ apartment_type = fields.apartment_type, apartment_house_name = fields.apartment_house_name})
		if( res and res.start_pos ) then
			meta:set_string('start_pos', minetest.serialize( res.start_pos ));
			meta:set_string('end_pos',   minetest.serialize( res.end_pos ));
		end
		return;
	end
	-- TODO
	minetest.chat_send_player( pname, 'Dig this spawner in order to remove the building.');
end



minetest.register_node("apartment:build_chest", {
	description = "Apartment spawner",
	tiles = {"default_chest_top.png", "default_chest_top.png", "default_chest_top.png",
		"default_chest_top.png", "default_chest_top.png", "apartment_controls_vacant.png"},
	paramtype2 = "facedir",
	groups = {snappy=2,choppy=2,oddly_breakable_by_hand=2},
	legacy_facedir_simple = true,

	after_place_node = function(pos, placer, itemstack)
		local meta  = minetest.get_meta( pos );
		meta:set_string('formspec', handle_schematics.update_apartment_spawner_formspec( pos ));
        end,

	on_receive_fields = function( pos, formname, fields, sender )
		handle_schematics.on_receive_fields(pos, formname, fields, sender)
	end,

	-- if the building chest is removed, remove the building as well - and place nodes looking like leaves and autodecaying in order
 	-- to indicate where the building has been
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local meta  = minetest.get_meta( pos );

		if( oldmetadata and oldmetadata.fields and oldmetadata.fields.path ) then

			local replacement_function = handle_schematics.replacement_function_decay;
			local replacement_param    = nil;
			local path = minetest.get_modpath("apartment")..'/schems/'..oldmetadata.fields.path;

			minetest.chat_send_player( digger:get_player_name(), 'Removing building '..tostring( oldmetadata.fields.path ));
			handle_schematics.place_schematic( pos, oldnode.param2, path, 0,
			                                   replacement_function, replacement_param, digger,
			                                   {h=oldmetadata.fields.h,v=oldmetadata.fields.v} )
		end
	end,

	-- check if digging is allowed
	can_dig = function(pos,player)	

		if( not( player )) then
			return false;
		end
		local pname = player:get_player_name();
		if( not( minetest.check_player_privs(pname, {apartment_unrent=true}))) then
			minetest.chat_send_player( pname, 'You do not have the apartment_unrent priv which is necessary to dig this node.');
			return false;
		end
		local meta  = minetest.get_meta( pos );
		local old_placer = meta:get_string('placed_by');
		if( old_placer and old_placer ~= '' and old_placer ~= pname ) then
			minetest.chat_send_player( pname, 'Only '..tostring( old_placer )..' can dig this node.');
			return false;
		end
		return true;
	end,

})


if handle_schematics.ENABLE_SLOW_DECAY  then
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
end
