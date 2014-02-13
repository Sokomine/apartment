
-- TODO: only one per player
-- TODO: names ought to be ids
apartment = {}


apartment.get_formspec = function( pos, placer )

	local meta  = minetest.get_meta(pos);
	local original_owner = meta:get_string( 'original_owner' );
	local          owner = meta:get_string(          'owner' );
	local          descr = meta:get_string(          'descr' );

	-- misconfigured
	if( not( original_owner ) or original_owner == '' ) then
		return 'field[text;;Panel misconfigured. Please dig and place again.] ';
	end

	-- if a name has been set
	if( descr and descr ~= '' ) then

		if( original_owner ~= owner and owner ~= '' ) then
			return 'size[6,3]'..
			'label[2.0,-0.3;Apartment \''..minetest.formspec_escape( descr )..'\']'..
			'label[0.5,1.0;This apartment is rented by]'..
			'label[3.0,1.0;'..tostring( owner )..'.]'..
			'button_exit[3,2.0;2,0.5;unrent;Move out]'..
			'button_exit[1,2.0;1,0.5;abort;OK]';
		end
		return 'size[6,3]'..
			'label[2.0,-0.3;Apartment \''..minetest.formspec_escape( descr )..'\']'..
			'label[0.5,1.0;Do you want to rent this]'..
			'label[3.0,1.0;apartment? It\'s free!]'..
			'button_exit[3,2.0;2,0.5;rent;Yes, rent it]'..
			'button_exit[1,2.0;1,0.5;abort;No.]';
	end

	-- defaults that fit to small appartments - change this if needed!
	local size_up    = 2;
	local size_down  = 1;
	local size_right = 1;
	local size_left  = 2;
	local size_front = 1;
	local size_back  = 7;

	-- show configuration formspec 
	if( not( owner ) or owner=='' or owner==original_owner ) then
		return 'size[7,7]'..
			'label[2.0,-0.3;Apartment Configuration]'..

			'label[0.5,0.5;Name or number for this apartment:]'..
			'field[5.0,1.0;2.0,0.5;descr;;'..tostring( descr )..']'..

			'label[0.5,1.2;The apartment shall extend]'..
			'label[3.3,1.2;this many blocks from here:]'..
			'label[0.5,1.4;(relative to this panel)]'..

			'label[1.3,3.5;left:]' ..'field[2.0,4.0;1.0,0.5;size_left;;' ..tostring( size_left  )..']'..
			'label[4.6,3.5;right]' ..'field[4.0,4.0;1.0,0.5;size_right;;'..tostring( size_right )..']'..
			'label[2.8,5.0;front]' ..'field[3.0,5.0;1.0,0.5;size_front;;'..tostring( size_front )..']'..
			'label[2.8,2.1;back:]' ..'field[3.0,3.0;1.0,0.5;size_back;;' ..tostring( size_back  )..']'..
			'label[5.8,2.1;up:]'   ..'field[6.0,3.0;1.0,0.5;size_up;;'   ..tostring( size_up    )..']'..
			'label[5.8,5.0;down]'  ..'field[6.0,5.0;1.0,0.5;size_down;;' ..tostring( size_down  )..']'..

			'button_exit[4,6.0;2,0.5;store;Store and offer]'..
			'button_exit[1,6.0;1,0.5;abort;Abort]';
	end
end



apartment.on_receive_fields = function(pos, formname, fields, player)

	local meta  = minetest.get_meta(pos);
	local pname = player:get_player_name();
	local original_owner = meta:get_string( 'original_owner' );
	local          owner = meta:get_string(          'owner' );
	local          descr = meta:get_string(          'descr' );

 	if( not( fields ) or fields.abort or not( original_owner ) or original_owner=='' or not( fields.quit )) then
		return;
	
	elseif( not( descr ) or descr=='' ) then

		-- only the player who placed the panel can configure it
		if( not( fields.store ) or pname ~= original_owner or pname ~= owner) then
			if( fields.descr and fields.descr ~= '') then
				minetest.chat_send_player( pname, 'Error: Only the owner of this panel can configure it.');
			end
			return;
		end

		local size_left  = tonumber( fields.size_left  or -1);
		local size_right = tonumber( fields.size_right or -1);
		local size_up    = tonumber( fields.size_up    or -1);
		local size_down  = tonumber( fields.size_down  or -1);
		local size_front = tonumber( fields.size_front or -1);
		local size_back  = tonumber( fields.size_back  or -1);

		-- have all fields been filled int?
		if(    not(fields.store)
		    or not(size_left    ) or size_left < 0 or size_left > 10
		    or not(size_right   ) or size_right< 0 or size_right> 10
		    or not(size_up      ) or size_up   < 0 or size_up   > 10
		    or not(size_down    ) or size_down < 0 or size_down > 10
		    or not(size_front   ) or size_front< 0 or size_front> 10
		    or not(size_back    ) or size_back < 0 or size_back > 10 
		    or not(fields.descr ) or fields.descr == '') then

			minetest.chat_send_player( pname, 'Error: Not all fields have been filled in or the area is too large.');
			return;
		end

		meta:set_int( 'size_up',     size_up    );
		meta:set_int( 'size_down',   size_down  );
		meta:set_int( 'size_right',  size_right );
		meta:set_int( 'size_left',   size_left  );
		meta:set_int( 'size_front',  size_front );
		meta:set_int( 'size_back',   size_back  );

		meta:set_string( 'descr',    fields.descr );
		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));

		minetest.chat_send_player( pname, 'Apartment \''..tostring( fields.descr )..'\' is ready for rental.');
		return;
	
	elseif( fields.rent and pname == original_owner ) then
		minetest.chat_send_player( pname, 'You cannot rent your own appartment. Dig the panel if you no longer want to rent it.');
		return;

	elseif( fields.rent and owner == pname ) then
		minetest.chat_send_player( pname, 'You have already rented this apartment.');
		return;

	elseif( fields.rent and owner ~= original_owner ) then
		minetest.chat_send_player( pname, 'Sorry, this apartment has already been rented to '..tostring( owner )..'.');
		return;

	-- actually rent the appartment
	elseif( fields.rent and not( apartment.rent( pos, pname ))) then
		minetest.chat_send_player( pname, 'Sorry. There was an internal error. Please try again later.');
		return;

	elseif( fields.rent ) then
		minetest.chat_send_player( pname, 'You have rented apartment \''..tostring( descr )..'\'. Enjoy your stay!');
		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));
		return;

	elseif( fields.unrent and owner ~= original_owner and owner==pname ) then
		if( not( apartment.rent( pos, original_owner ) )) then
			minetest.chat_send_player( pname, 'Something wrent wrong when giving back the apartment.');
			return;
		end
		minetest.chat_send_player( pname, 'You have ended your rent of apartment \''..tostring( descr )..'\'. It is free for others to rent again.');
		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));
		return;
	end
end


-- actually rent the apartment (if possible); return true on success
apartment.rent = function( pos, pname )
	local node  = minetest.env:get_node(pos);
	local meta  = minetest.get_meta(pos);
	local original_owner = meta:get_string( 'original_owner' );
	local          owner = meta:get_string(          'owner' );
	local          descr = meta:get_string(          'descr' );
	
	if( not( node ) or not( meta ) or not( original_owner ) or not( owner ) or not( descr )) then
		return false;
	end 

	local size_up    = meta:get_int( 'size_up' );
	local size_down  = meta:get_int( 'size_down' );
	local size_right = meta:get_int( 'size_right' );
	local size_left  = meta:get_int( 'size_left' );
	local size_front = meta:get_int( 'size_front' );
	local size_back  = meta:get_int( 'size_back' );

	if( not( size_up ) or not( size_down ) or not( size_right ) or not( size_left ) or not( size_front ) or not( size_back )) then
		return false;
	end

	local x1 = pos.x;
	local y1 = pos.y;
	local z1 = pos.z;
	local x2 = pos.x;
	local y2 = pos.y;
	local z2 = pos.z;

	if(     node.param2 == 0 ) then -- z gets larger

		x1 = x1 - size_left;      x2 = x2 + size_right;
		z1 = z1 - size_front;     z2 = z2 + size_back;

	elseif( node.param2 == 1 ) then -- x gets larger
		
		z1 = z1 - size_right;     z2 = z2 + size_left; 
		x1 = x1 - size_front;     x2 = x2 + size_back;

	elseif( node.param2 == 2 ) then	-- z gets smaller
		
		x1 = x1 - size_right;     x2 = x2 + size_left;  
		z1 = z1 - size_back;      z2 = z2 + size_front;

	elseif( node.param2 == 3 ) then -- x gets smaller
		
		z1 = z1 - size_left;      z2 = z2 + size_right;
		x1 = x1 - size_back;      x2 = x2 + size_front;

	end
	y1 = y1 - size_down;      y2 = y2 + size_up;  

	local px = x1;
	local py = x1;
	local pz = z1;
	for px = x1, x2 do
		for py = y1, y2 do
			for pz = z1, z2 do

				local m = minetest.get_meta( {x=px, y=py, z=pz});
				if( m ) then
					local s = m:get_string( 'owner' );
					-- doors are diffrent
					if( not( s ) or s=='' ) then
						s = m:get_string( 'doors_owner' );
					end
					-- change owner to the new player
					if( s and s ~= '' and (s==original_owner or s==owner)) then
						-- change the actual owner
						m:set_string( 'owner', pname );
						-- set a fitting infotext
						local itext = "Rented by "..pname;
						n = minetest.get_node( {x=px, y=py, z=pz} );
--minetest.chat_send_player( pname, n.name..' found');
						if( n.name == 'default:chest_locked' ) then
							itext = "Locked Chest (rented by "..pname..")";
						elseif( n.name == 'doors:door_steel_b_1' or n.name == 'doors:door_steel_t_1' 
						     or n.name == 'doors:door_steel_b_2' or n.name == 'doors:door_steel_t_2' ) then
							itext = "Apartment "..descr.." (rented by "..pname..")";
							-- doors use another meta text
							m:set_string( 'doors_owner', pname );
						elseif( n.name == "technic:iron_locked_chest" ) then
							itext = "Iron Locked Chest (rented by "..pname..")";
						elseif( n.name == "technic:copper_locked_chest" ) then
							itext = "Copper Locked Chest (rented by "..pname..")";
						elseif( n.name == "technic:gold_locked_chest" ) then
							itext = "Gold Locked Chest (rented by "..pname..")";
						end
						m:set_string( "infotext", itext );
					end
				end
			end
		end
	end
	return true;
end





minetest.register_node("apartment:apartment", {
	drawtype = "nodebox",
	description = "apartment management panel",
	tiles = {"default_chest_top.png^door_steel.png"},
	paramtype  = "light",
        paramtype2 = "facedir",
	light_source = LIGHT_MAX-1,
	groups = {cracky=2},
	node_box = {
		type = "fixed",
		fixed = {
					{-0.40, -0.4, 0.50, 0.40, 0.40, 0.30},
			}
	},
	selection_box = {
		type = "fixed",
		fixed = {
					{-0.40, -0.4, 0.50, 0.40, 0.40, 0.30},
			}
	},

	on_construct = function(pos)

               	local meta = minetest.env:get_meta(pos);
               	meta:set_string('infotext', 'Apartment Management Panel (unconfigured)');
		meta:set_string('original_owner', '' );
		meta:set_string('owner', '' );
		meta:set_string('descr', '' );
		meta:set_int( 'size_up',    0 );
		meta:set_int( 'size_down',  0 );
		meta:set_int( 'size_right', 0 );
		meta:set_int( 'size_left',  0 );
		meta:set_int( 'size_front', 0 );
		meta:set_int( 'size_back',  0 );
       	end,

	after_place_node = function(pos, placer)
		local meta  = minetest.get_meta(pos);
		local pname = (placer:get_player_name() or ""); 
		meta:set_string("original_owner", pname );
		meta:set_string("owner",          pname );
               	meta:set_string('infotext', 'Apartment Management Panel (owned by '..pname..')' );

                meta:set_string("formspec", apartment.get_formspec( pos, placer ));

        end,

	on_receive_fields = function( pos, formname, fields, player )
		return apartment.on_receive_fields(pos, formname, fields, player);
	end,

        can_dig = function(pos,player)

                local meta  = minetest.get_meta(pos);
		local owner = meta:get_string('owner');
		local original_owner = meta:get_string( 'original_owner' );
		local pname = player:get_player_name();

                if( original_owner and original_owner ~= pname ) then
			minetest.chat_send_player( pname, 'Sorry. Only the original owner of this apartment control panel can dig it.');
			return false;
		end

		if( original_owner and original_owner ~= owner and owner ~= '') then
			minetest.chat_send_player( pname, 'The apartment is currently rented to '..tostring( owner )..'. Please end that first.');
			return false;
		end

                return true;
        end,

})
