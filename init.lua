
--[[
    The apartment mod allows players to rent a place with locked objects in
    - the ownership of the locked objects is transfered to the player who
    rented the apartment.

    Copyright (C) 2014 Sokomine

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.


  Version: 1.3 
  Autor:   Sokomine
  Date:    12.02.14
--]]    

-- Changelog:
-- 15.06.14 Added abm to turn apartment:apartment into either apartment:apartment_free or apartment:apartment_occupied
--          so that it becomes visible weather an apartment is free or not 
-- 15.05.14 Added diffrent panel for occupied apartments. Added textures created by VanessaE.
-- 24.02.14 Buildings can now be removed again (dig the spawn chest)
-- 25.02.14 Buildings can now be saved. Just prefix the apartment name with save_as_
--          start_pos and end_pos of apartments are now saved (necessary for the above mentioned save function).
--          Building spawner chest is now working.
-- 22.02.14 Added code for spawning several apartments at the same time. 
-- 18.02.14 Added support for further nodes (shops, travelnet, ..).
--          Cleaned up formspec that contains apartment information.
--          Introduced diffrent categories so that i.e. a shop and an apartment can be rented at the same time.
-- 16.02.14 Removed MAX_LIGHT var and set to fixed value.
-- 16.02.14 Only descriptions and ownership of known objects are changed.
--          When digging the panel, the descriptions are reset.
-- 14.02.14 Improved formspecs, messages and descriptions of rented and vacant items.
--          Players with the apartment_unrent priv can now throw other players out of apartments. 
--          Apartment names have to be uniq.
--          Each player can only rent one apartment at a time.
--          Added /aphome command

minetest.register_privilege("apartment_unrent", { description = "allows to throw players out of apartments they have rented", give_to_singleplayer = false});

apartment = {}

dofile(minetest.get_modpath("apartment")..'/handle_schematics.lua');

-- will contain information about all apartments of the server in the form:
-- { apartment_descr = { pos={x=0,y=0,z=0}, original_owner='', owner=''}
apartment.apartments = {};

-- set to false if you do not like your players
apartment.enable_aphome_command = true;

-- TODO: save and restore ought to be library functions and not implemented in each individual mod!
-- called whenever an apartment is added or removed
apartment.save_data = function()

   local data = minetest.serialize( apartment.apartments );
   local path = minetest.get_worldpath().."/apartment.data";

   local file = io.open( path, "w" );
   if( file ) then
      file:write( data );
      file:close();
   else
      print("[Mod apartment] Error: Savefile '"..tostring( path ).."' could not be written.");
   end
end


apartment.restore_data = function()

   local path = minetest.get_worldpath().."/apartment.data";

   local file = io.open( path, "r" );
   if( file ) then
      local data = file:read("*all");
      apartment.apartments = minetest.deserialize( data );
      file:close();
   else
      print("[Mod apartment] Error: Savefile '"..tostring( path ).."' not found.");
   end
end




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

		local size_txt = 'textarea[0.0,0.8;6.5,1.2;info;;'..minetest.formspec_escape(
					'It extends '..
					(meta:get_string("size_right") or '?')..' m to the right, '..
					(meta:get_string("size_left" ) or '?')..' m to the left, '..
					(meta:get_string("size_up"   ) or '?')..' m up, '..
					(meta:get_string("size_down" ) or '?')..' m down,\n'..
					(meta:get_string("size_back" ) or '?')..' m in front of you and '..
					(meta:get_string("size_front") or '?')..' m behind you. '..
					'It has been built by\n'..(original_owner or '?')..
					'. Building category: '..tostring( meta:get_string('category'))..'.')..']';

		if( original_owner ~= owner and owner ~= '' ) then
			return 'size[6.5,3]'..
			'label[2.0,-0.3;Apartment \''..minetest.formspec_escape( descr )..'\']'..
			size_txt..
			'label[0.5,1.7;This apartment is rented by:]'..
			'label[3.5,1.7;'..tostring( owner )..']'..
			'button_exit[3,2.5;2,0.5;unrent;Move out]'..
			'button_exit[1,2.5;1,0.5;abort;OK]';
		end
		return 'size[6,3]'..
			'label[2.0,-0.3;Apartment \''..minetest.formspec_escape( descr )..'\']'..
			size_txt..
			'label[0.3,1.8;Do you want to rent this]'..
			'label[3.0,1.8;apartment? It\'s free!]'..
			'button_exit[3,2.5;2,0.5;rent;Yes, rent it]'..
			'button_exit[1,2.5;1,0.5;abort;No.]';
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
			'field[5.0,0.9;2.0,0.5;descr;;'..tostring( descr )..']'..

			'label[0.5,0.8;Category (i.e. house, shop):]'..
			'field[5.0,1.4;2.0,0.5;category;;apartment]'..

			'label[0.5,1.7;The apartment shall extend]'..
			'label[3.4,1.7;this many blocks from here:]'..
			'label[0.5,2.1;(relative to this panel)]'..

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
	local       category = meta:get_string(       'category' );

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
		    or not(fields.category )
		    or not(fields.descr ) or fields.descr == '') then

			minetest.chat_send_player( pname, 'Error: Not all fields have been filled in or the area is too large.');
			return;
		end

		-- avoid duplicate names
		if( apartment.apartments[ fields.descr ] ) then
			minetest.chat_send_player( pname, 'Error: An apartment by that name exists already (name: '..fields.descr..').'..
				'Please choose a diffrent name/id.');
			return;
		end
			
		meta:set_int( 'size_up',     size_up    );
		meta:set_int( 'size_down',   size_down  );
		meta:set_int( 'size_right',  size_right );
		meta:set_int( 'size_left',   size_left  );
		meta:set_int( 'size_front',  size_front );
		meta:set_int( 'size_back',   size_back  );

		meta:set_string( 'descr',    fields.descr );
		meta:set_string( 'category', fields.category );

		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));

		apartment.rent( pos, original_owner, nil, player );

		apartment.apartments[ fields.descr ] = { pos={x=pos.x, y=pos.y, z=pos.z}, original_owner = original_owner, owner='', category = fields.category,
		                                         start_pos = apartment.apartments[ fields.descr ].start_pos,
		                                         end_pos   = apartment.apartments[ fields.descr ].end_pos  };
		apartment.save_data();

		minetest.chat_send_player( pname, 'Apartment \''..tostring( fields.descr )..'\' (category: '..tostring( fields.category )..') is ready for rental.');

		-- this way, schematics can be created
		if( minetest.check_player_privs(pname, {apartment_unrent=true})
		    and string.sub( fields.descr, 1, string.len( 'save_as_' ))=='save_as_') then

			local filename = string.sub( fields.descr, string.len( 'save_as' )+2);
			if( filename and filename ~= '' ) then
				-- param2 needs to be translated init initial rotation as well
				local node = minetest.get_node( pos );
				if(     node.param2 == 0 ) then
					filename = filename..'_0_90';
				elseif( node.param2 == 3 ) then
					filename = filename..'_0_180';
				elseif( node.param2 == 1 ) then
					filename = filename..'_0_0';
				elseif( node.param2 == 2 ) then
					filename = filename..'_0_270';
				end
				filename = minetest.get_modpath("apartment")..'/schems/'..filename..'.mts';
				-- really save it with probability_list and slice_prob_list both as nil
				minetest.create_schematic( apartment.apartments[ fields.descr ].start_pos,
				                           apartment.apartments[ fields.descr ].end_pos,
				                           nil, filename, nil);
				minetest.chat_send_player( pname, 'Created schematic \''..tostring( filename )..'\' for use with the apartment spawner. Saved from '..
						           minetest.serialize(  apartment.apartments[ fields.descr ].start_pos )..' to '..
						           minetest.serialize(  apartment.apartments[ fields.descr ].end_pos )..'.');
			end
		end
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
	elseif( fields.rent ) then

		if( not( apartment.apartments[ descr ] )) then
			minetest.chat_send_player( pname, 'Error: This apartment is not registered. Please un-rent it and ask the original buildier '..
				'to dig and place this panel again.');
			return;
		end
			
		-- make sure only one apartment can be rented at a time
		for k,v in pairs( apartment.apartments ) do
			if( v and v.owner and v.owner==pname 
				and v.category and category and v.category == category) then
				minetest.chat_send_player( pname, 'Sorry. You can only rent one apartment per category at a time. You have already '..
					'rented apartment '..k..'.');
				return;
			end
		end

		if( not( apartment.rent( pos, pname, nil, player ))) then
			minetest.chat_send_player( pname, 'Sorry. There was an internal error. Please try again later.');
			return;
		end

		minetest.chat_send_player( pname, 'You have rented apartment \''..tostring( descr )..'\'. Enjoy your stay!');
		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));
		return;

	elseif( fields.unrent and owner ~= original_owner and owner==pname ) then
		if( not( apartment.rent( pos, original_owner, nil, player ) )) then
			minetest.chat_send_player( pname, 'Something went wrong when giving back the apartment.');
			return;
		end
		minetest.chat_send_player( pname, 'You have ended your rent of apartment \''..tostring( descr )..'\'. It is free for others to rent again.');
		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));
		return;

	-- someone else tries to throw the current owner out
	elseif( fields.unrent and owner ~= original_owner and owner ~= pname ) then
		if( not( minetest.check_player_privs(pname, {apartment_unrent=true}))) then
			minetest.chat_send_player( pname, 'You do not have the privilelge to throw other people out of apartments they have rented.');
			return;
		end
		if( not( apartment.rent( pos, original_owner, nil, player ) )) then
			minetest.chat_send_player( pname, 'Something went wrong when giving back the apartment.');
			return;
		end
		minetest.chat_send_player( pname, 'Player '..owner..' has been thrown out of the apartment. It can now be rented by another player.');
		meta:set_string( 'formspec', apartment.get_formspec( pos, player ));
	end
end


-- actually rent the apartment (if possible); return true on success
-- the "actor" field is only for such cases in which an object is needed for update functiones (i.e. travelnet)
apartment.rent = function( pos, pname, oldmetadata, actor )
	local node  = minetest.env:get_node(pos);
	local meta  = minetest.get_meta(pos);
	local original_owner = meta:get_string( 'original_owner' );
	local          owner = meta:get_string(          'owner' );
	local          descr = meta:get_string(          'descr' );
	
	if( oldmetadata ) then
		original_owner = oldmetadata.fields[ "original_owner" ];
		owner          = oldmetadata.fields[ "owner" ];
		descr          = oldmetadata.fields[ "descr" ];
		meta           = {};
	end

	if( not( node ) or not( meta ) or not( original_owner ) or not( owner ) or not( descr )) then
		return false;
	end 

	local size_up    = 0;
	local size_down  = 0;
	local size_right = 0;
	local size_left  = 0;
	local size_front = 0;
	local size_back  = 0;
	if( not( oldmetadata )) then
		size_up    = meta:get_int( 'size_up' );
		size_down  = meta:get_int( 'size_down' );
		size_right = meta:get_int( 'size_right' );
		size_left  = meta:get_int( 'size_left' );
		size_front = meta:get_int( 'size_front' );
		size_back  = meta:get_int( 'size_back' );
	else
		size_up     = tonumber(oldmetadata.fields[ "size_up"    ]);
		size_down   = tonumber(oldmetadata.fields[ "size_down"  ]);
		size_right  = tonumber(oldmetadata.fields[ "size_right" ]);
		size_left   = tonumber(oldmetadata.fields[ "size_left"  ]);
		size_front  = tonumber(oldmetadata.fields[ "size_front" ]);
		size_back   = tonumber(oldmetadata.fields[ "size_back"  ]);
	end

	if( not( size_up ) or not( size_down ) or not( size_right ) or not( size_left ) or not( size_front ) or not( size_back )) then
		return false;
	end

	local rented_by = 'rented by '..pname;
	if( pname == original_owner ) then
		rented_by = '- vacant -';
	elseif( pname == '' ) then
		rented_by = 'owned by '..original_owner;
	end
	-- else we might run into trouble if we use it in formspecs
	local original_descr = descr;
 	descr = minetest.formspec_escape( descr );

	local x1 = pos.x;
	local y1 = pos.y;
	local z1 = pos.z;
	local x2 = pos.x;
	local y2 = pos.y;
	local z2 = pos.z;

	if( oldmetadata and oldmetadata.param2 ) then
		node.param2 = oldmetadata.param2;
	end

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

	if( not( apartment.apartments[ original_descr ] )) then
		apartment.apartments[ original_descr ] = {};
	end
	apartment.apartments[ original_descr ].start_pos   = {x=x1, y=y1, z=z1};
	apartment.apartments[ original_descr ].end_pos     = {x=x2, y=y2, z=z2};

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
					if ( not s or s == '' )then
					   s = original_owner
					end
					-- change owner to the new player
					if( s and s ~= '' and (s==original_owner or s==owner)) then
						-- change the actual owner
						-- set a fitting infotext
						local itext = 'Object in Ap. '..descr..' ('..rented_by..')';
						local n = minetest.get_node( {x=px, y=py, z=pz} );
						if( n.name == 'default:chest_locked' ) then
							if( pname == '' ) then
								itext = "Locked Chest (owned by "..original_owner..")";
							else
								itext = "Locked Chest in Ap. "..descr.." ("..rented_by..")";
							end
						elseif( n.name == 'doors:door_steel_b_1' or n.name == 'doors:door_steel_t_1'
							   or n.name == 'doors:door_steel_a' or n.name == 'doors:door_steel_b'
						     or n.name == 'doors:door_steel_b_2' or n.name == 'doors:door_steel_t_2' ) then
							if( pname=='' ) then
								itext = "Locked Door (owned by "..original_owner..")";
							elseif( pname==original_owner ) then
								itext = "Apartment "..descr.." (vacant)";
							else
								itext = "Apartment "..descr.." ("..rented_by..")";
							end
							-- doors use another meta text
							m:set_string( 'doors_owner', pname );
						elseif( n.name == "locked_sign:sign_wall_locked" ) then
							itext =  "\"\" ("..rented_by..")";

						-- only change the one panel that controls this apartment - not any others in the way
						elseif((n.name == 'apartment:apartment_free' and px==pos.x and py==pos.y and pz==pos.z)
						     or(n.name == 'apartment:apartment_occupied' and px==pos.x and py==pos.y and pz==pos.z)) then
							if( pname==original_owner ) then
								itext = "Rent apartment "..descr.." here by right-clicking this panel!";
							else
								itext = "Apartment rental control panel for apartment "..descr.." ("..rented_by..")";
							end

						elseif( n.name == "technic:iron_locked_chest" ) then
							if( pname=='' ) then
								itext = "Iron Locked Chest (owned by "..original_owner..")";
							else
								itext = "Iron Locked Chest in Ap. "..descr.." ("  ..rented_by..")";
							end
						elseif( n.name == "technic:copper_locked_chest" ) then
							if( pname=='' ) then
								itext = "Copper Locked Chest (owned by "..original_owner..")";
							else
								itext = "Copper Locked Chest in Ap. "..descr.." ("..rented_by..")";
							end
						elseif( n.name == "technic:gold_locked_chest" ) then
							if( pname=='' ) then
								itext = "Gold Locked Chest (owned by "..original_owner..")";
							else
								itext = "Gold Locked Chest in Ap. "..descr.." ("  ..rented_by..")";
							end

						elseif( n.name == "inbox:empty" ) then
							if( pname=='' ) then
								itext = original_owner.."'s Mailbox";
							else
								itext = pname.."'s Mailbox";
							end
						elseif( n.name == "locks:shared_locked_chest") then
							itext = "Shared locked chest ("..rented_by..")";
						elseif( n.name == "locks:shared_locked_furnace"
						     or n.name == "locks:shared_locked_furnace_active") then
							itext = "Shared locked furnace ("..rented_by..")";
						elseif( n.name == "locks:shared_locked_sign_wall") then
							itext = "Shared locked sign ("..rented_by..")";
						elseif( n.name == "locks:door"
						     or n.name == "locks:door_top_1"
						     or n.name == "locks:door_top_2"
						     or n.name == "locks:door_bottom_1"
						     or n.name == "locks:door_bottom_2") then
							itext = "Shared locked door ("..rented_by..")";

						elseif( n.name == "chests_0gb_us:shared" ) then
							itext = "Shared Chest ("..rented_by..")";
						elseif( n.name == "chests_0gb_us:secret" ) then
							itext = "Secret Chest ("..rented_by..")";
						elseif( n.name == "chests_0gb_us:dropbox") then
							itext = "Dropbox ("..rented_by..")";

						elseif( n.name == "itemframes:frame" ) then
							itext = "Item frame ("..rented_by..")";
						elseif( n.name == "itemframes:pedestral" ) then
							itext = "Pedestral frame ("..rented_by..")";


						-- money mod - shop and barter shop; admin shops do not change ownership
						elseif( n.name == "money:shop" ) then
							if(     m:get_string('infotext')=="Untuned Shop" 
							     or m:get_string('infotext')=="Detuned Shop"
							     or not( m:get_string('shopname' ))
							     or m:get_string('infotext')=="Untuned Shop (owned by "..(m:get_string('owner') or "")..")") then
								itext = "Untuned Shop ("..rented_by..")";
							else
								itext = "Shop \""..m:get_string('shopname').."\" ("..rented_by..")";
							end
						elseif( n.name == "money:barter_shop" ) then
							if(     m:get_string('infotext')=="Untuned Barter Shop" 
							     or m:get_string('infotext')=="Detuned Barter Shop"
							     or not( m:get_string('shopname' ))
							     or m:get_string('infotext')=="Untuned Barter Shop (owned by "..(m:get_string('owner') or "")..")") then
								itext = "Untuned Barter Shop ("..rented_by..")";
							else
								itext = "Barter Shop \""..m:get_string('shopname').."\" ("..rented_by..")";
							end
						
						elseif( n.name == "currency:safe") then
							itext = "Safe ("..rented_by..")";
						elseif( n.name == "currency:shop") then
						   itext = "Exchange shop ("..rented_by..")";
						   
						elseif( n.name == "bitchange:bank" ) then
							itext = "Bank ("..rented_by..")";
						elseif( n.name == "bitchange:moneychanger" ) then
							itext = "Moneychanger  ("..rented_by..")";
						elseif( n.name == "bitchange:warehouse" ) then
						   itext = "Warehouse ("..rented_by..")";
						elseif (n.name == "smartshop:shop") then
						   itext = "Shop " .. rented_by
						   m:set_int("creative", 0)
						   m:set_int("type",1)
						elseif( n.name == "bitchange:shop" ) then
							if( m:get_string('title') and m:get_string('title') ~= '' ) then
								itext = "Exchange shop \""..( m:get_string('title')).."\" ("..rented_by..")";
							else
								itext = "Exchange shop ("..rented_by..")";
							end

						elseif( n.name == "vendor:vendor"
						     or n.name == "vendor:depositor") then
							if( pname == '' ) then
								m:set_string( 'owner',    original_owner );
							else
								m:set_string( 'owner',    pname );
							end
							vendor.refresh( {x=px, y=py, z=pz}, nil);
							-- everything has been set alrady
							itext = '';

						-- un-configure the travelnet
						elseif( n.name == "travelnet:travelnet"
						     or n.name == "travelnet:elevator"
						     or n.name == "locked_travelnet:elevator"
						     or n.name == "locked_travelnet:travelnet" ) then
						   
							local oldmetadata = { fields = {
								owner           = m:get_string('owner'),
								station_name    = m:get_string('station_name'),
								station_network = m:get_string('station_network') }};
								 
							-- the old box has to be removed from the network
							travelnet.remove_box( {x=px, y=py, z=pz},  nil, oldmetadata, actor );
							if( pname == '' ) then
								m:set_string( 'owner',    original_owner );
							else
								m:set_string( 'owner',    pname );
							end
							-- prepare the box with new input formspec etc.
							minetest.registered_nodes[ n.name ].after_place_node({x=px, y=py, z=pz}, actor, nil);
							itext = '';


						else
							itext = '';
						end
						-- only set ownership of nodes the mod knows how to handle
						if( itext ) then
							m:set_string( "infotext", itext );
							if( pname == '' ) then
								m:set_string( 'owner',    original_owner );
							else
								m:set_string( 'owner',    pname );
							end
						end
					end
				end
			end
		end
	end

	-- here, we need the original descr again
	if( apartment.apartments[ original_descr ] ) then
		if( original_owner == pname ) then
			apartment.apartments[ original_descr ].owner = '';
		else
			apartment.apartments[ original_descr ].owner = pname;
		end
		apartment.save_data();
	end

	if( not( oldmetadata) ) then
		if(     (owner == '' or original_owner==pname)
		    and (node.name ~= 'apartment:apartment_free')) then
			minetest.swap_node( pos, {name='apartment:apartment_free', param2 = node.param2} );
		elseif( (node.name ~= 'apartment:apartment_occupied')
		    and (original_owner ~= pname)) then
			minetest.swap_node( pos, {name='apartment:apartment_occupied', param2 = node.param2} );
		end
	end
	return true;
end



apartment.on_construct = function(pos)
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
end


apartment.after_place_node = function(pos, placer)
		local meta  = minetest.get_meta(pos);
		local pname = (placer:get_player_name() or ""); 
		meta:set_string("original_owner", pname );
		meta:set_string("owner",          pname );
               	meta:set_string('infotext', 'Apartment Management Panel (owned by '..pname..')' );

                meta:set_string("formspec", apartment.get_formspec( pos, placer ));
end


apartment.can_dig = function(pos,player)

                local meta  = minetest.get_meta(pos);
		local owner = meta:get_string('owner');
		local original_owner = meta:get_string( 'original_owner' );
		local pname = player:get_player_name();

		if( not( original_owner  ) or original_owner == '' ) then
			return true;
		end

                if( original_owner ~= pname ) then
			minetest.chat_send_player( pname, 'Sorry. Only the original owner of this apartment control panel can dig it.');
			return false;
		end

		if( original_owner ~= owner ) then
			minetest.chat_send_player( pname, 'The apartment is currently rented to '..tostring( owner )..'. Please end that first.');
			return false;
		end

                return true;
end


apartment.after_dig_node = function(pos, oldnode, oldmetadata, digger)

		if( not( oldmetadata ) or oldmetadata=="nil" or not(oldmetadata.fields)) then
			minetest.chat_send_player( digger:get_player_name(), "Error: Could not find information about the apartment panel that is to be removed.");
			return;
		end

		local descr = oldmetadata.fields[ "descr" ];
		if( apartment.apartments[ descr ] ) then

			-- actually remove the apartment
			oldmetadata.param2 = oldnode.param2;
			apartment.rent( pos, '', oldmetadata, digger );
			apartment.apartments[ descr ] = nil;
			apartment.save_data();
			minetest.chat_send_player( digger:get_player_name(), "Removed apartment "..descr.." successfully.");
		end
end




minetest.register_node("apartment:apartment_free", {
	drawtype = "nodebox",
	description = "apartment management panel",
---	tiles = {"default_chest_top.png^door_steel.png"},
	tiles = {"default_steel_block.png","default_steel_block.png","default_steel_block.png","default_steel_block.png",
			"default_steel_block.png","apartment_controls_vacant.png","default_steel_block.png"},
	paramtype  = "light",
        paramtype2 = "facedir",
	light_source = 14,
	groups = {cracky=2,not_in_creative_inventory=1},
	node_box = {
		type = "fixed",
		fixed = {
					{ -0.5+(1/16), -0.5+(1/16), 0.5, 0.5-(1/16), 0.5-(1/16), 0.30},

			}
	},
	selection_box = {
		type = "fixed",
		fixed = {
					{ -0.5+(1/16), -0.5+(1/16), 0.5, 0.5-(1/16), 0.5-(1/16), 0.30},
			}
	},

	on_construct = function(pos)
		return apartment.on_construct( pos );
       	end,

	after_place_node = function(pos, placer)
		return apartment.after_place_node( pos, placer );
        end,

	on_receive_fields = function( pos, formname, fields, player )
		return apartment.on_receive_fields(pos, formname, fields, player);
	end,

        can_dig = function(pos,player)
		return apartment.can_dig( pos, player );
        end,

	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		return apartment.after_dig_node( pos, oldnode, oldmetadata, digger );
	end,

})


-- this one is not in the creative inventory
minetest.register_node("apartment:apartment_occupied", {
	drawtype = "nodebox",
	description = "apartment management panel",
---	tiles = {"default_chest_top.png^door_steel.png"},
	tiles = {"default_steel_block.png","default_steel_block.png","default_steel_block.png","default_steel_block.png",
			"default_steel_block.png","apartment_controls_occupied.png","default_steel_block.png"},
	paramtype  = "light",
        paramtype2 = "facedir",
	light_source = 14,
	groups = {cracky=2, not_in_creative_inventory=1 },
	node_box = {
		type = "fixed",
		fixed = {
					{ -0.5+(1/16), -0.5+(1/16), 0.5, 0.5-(1/16), 0.5-(1/16), 0.30},

			}
	},
	selection_box = {
		type = "fixed",
		fixed = {
					{ -0.5+(1/16), -0.5+(1/16), 0.5, 0.5-(1/16), 0.5-(1/16), 0.30},
			}
	},

	on_construct = function(pos)
		return apartment.on_construct( pos );
       	end,

	after_place_node = function(pos, placer)
		return apartment.after_place_node( pos, placer );
        end,

	on_receive_fields = function( pos, formname, fields, player )
		return apartment.on_receive_fields(pos, formname, fields, player);
	end,

        can_dig = function(pos,player)
		return apartment.can_dig( pos, player );
        end,

	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		return apartment.after_dig_node( pos, oldnode, oldmetadata, digger );
	end,

})


if( apartment.enable_aphome_command ) then
   minetest.register_chatcommand("aphome", {
	params = "<category>",
	description = "Teleports you back to the apartment you rented.",
	privs = {},
	func = function(name, param)

			if( not( name )) then
				return;
			end
			local category;
			if (not param or param == "") then
			   category = 'apartment'
			else
			   category = param
			end
			local player = minetest.env:get_player_by_name(name);

			for k,v in pairs( apartment.apartments ) do
				-- found the apartment the player rented
				if( v and v.owner and v.owner==name and v.category == category) then
					player:moveto( v.pos, false);
					minetest.chat_send_player(name, "Welcome back to your apartment "..k..".");
					return;
				end
			end
			
			minetest.chat_send_player(name, "Please rent a "..category.." first.");
                end
   })
end



-- old version of the node - will transform into _free or _occupied
minetest.register_node("apartment:apartment", {
	drawtype = "nodebox",
	description = "apartment management panel (transition state)",
---	tiles = {"default_chest_top.png^door_steel.png"},
	tiles = {"default_steel_block.png","default_steel_block.png","default_steel_block.png","default_steel_block.png",
			"default_steel_block.png","apartment_controls_vacant.png","default_steel_block.png"},
	paramtype  = "light",
        paramtype2 = "facedir",
	light_source = 14,
	groups = {cracky=2,not_in_creative_inventory=1},
	node_box = {
		type = "fixed",
		fixed = {
					{ -0.5+(1/16), -0.5+(1/16), 0.5, 0.5-(1/16), 0.5-(1/16), 0.30},

			}
	},
	selection_box = {
		type = "fixed",
		fixed = {
					{ -0.5+(1/16), -0.5+(1/16), 0.5, 0.5-(1/16), 0.5-(1/16), 0.30},
			}
	},
})

minetest.register_abm({
	nodenames = {"apartment:apartment"},
	interval = 60,
	chance = 1,
	action = function(pos, node)

		local node  = minetest.get_node( pos );
		local meta  = minetest.get_meta( pos );
		local owner          = meta:get_string( 'owner' );
		local original_owner = meta:get_string( 'original_owner' );

		if(     owner == '' or original_owner==owner ) then
				minetest.swap_node( pos, {name='apartment:apartment_free', param2 = node.param2} );
		else 
				minetest.swap_node( pos, {name='apartment:apartment_occupied', param2 = node.param2} );
		end
	end
})

minetest.register_abm({
      -- handle duplicates
      nodenames= {"apartment:apartment_free" },
      interval = 1,
      chance = 1,
      action = function(pos,node)
	 local meta  = minetest.get_meta( pos );
	 local name  = meta:get_string('descr');
--	 minetest.chat_send_all(name)
	 if apartment.apartments[name] and apartment.apartments[name].pos and ( apartment.apartments[name].pos.x ~= pos.x
					     or apartment.apartments[name].pos.y ~= pos.y or apartment.apartments[name].pos.z ~= pos.z ) then
	    -- duplicate name
	    old = apartment.apartments[name]
	    local number = name:match('%d+$')
	    if number then
	       n = name:sub(1,-tostring(number):len()-1)..tostring(number+1)
	    else
	       n = name..' 1'
	    end
--	    minetest.chat_send_all(n)
	    meta:set_string('descr', n)
	    meta:set_string('formspec', apartment.get_formspec(pos, ""))
	    if not apartment.apartments[ n ] then
	       apartment.apartments[ n ] = { pos={x=pos.x, y=pos.y, z=pos.z}, original_owner = old.original_owner, owner='', category = old.category,
						     start_pos = old.start_pos,
						     end_pos   = old.end_pos  };
	    end
	 end
      end
})

-- give each player an apartment upon joining the server --
local apartment_give_player = minetest.setting_getbool("apartment_give_newplayer") or true;
if apartment_give_player then
   minetest.register_on_newplayer(function(player)
	 for k,v in pairs( apartment.apartments ) do
	    if (v.owner == '' and v.category == 'apartment') then
	       
	       local meta = minetest.get_meta( v.pos );
	       local node = minetest.get_node( v.pos );
	       if node.name == "ignore" then -- deal with unloaded nodes.
		  minetest.get_voxel_manip():read_from_map(v.pos, v.pos)
		  node = minetest.get_node(v.pos)
	       end
	       if (node.name == 'apartment:apartment_free' and apartment.rent( v.pos, player:get_player_name(), nil, player )) then
		  player:moveto( v.pos, false);
		  meta:set_string( 'formspec', apartment.get_formspec( v.pos, player ));
		  minetest.chat_send_player(player:get_player_name(),"Welcome to your new apartment. You can return here by saying '/aphome'")
		  break
	       elseif node.name == 'apartment:apartment_occupied' then -- Possible case of database corruption...
		  apartment.apartments[k] = nil
	       end
	    end
	 end
   end)
end
-- upon server start, read the savefile
apartment.restore_data();
