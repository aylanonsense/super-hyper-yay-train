pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[
notes
coordinates:
	    +z +y
	     ^ ^
	     |/
	-x<-- -->+x
	    /|
	   v v
	 -y -z
directions:
	1=facing left, showing sides (-x)
	2=facing right, showing sides (+x)
	3=facing up, showing back (+z)
	4=facing down, showing front (-z)
positions:
	entity.x is the left side of the entity (left < right)
	entity.x+entity.width-1 is the right side of the entity
	entity.z is the bottom of the entity (bottom < top)
	entity.z+entity.depth-1 is the top of the entity
	entity.y is the height above (or below) the ground
tiles:
	col=1 goes from x=0 to x=5
		col=flr((x+width/2)/tile_size+1)
		x=tile_size*(col-1)
	row=1 goes from z=0 to z=5
		row=flr(z/tile_size)+1
		z=tile_size*(row-1)
]]


-- vars
-- constants
tile_size=6
anim_mult=5
min_tile_row_lead=2
max_tile_row_lead=8
entity_spawn_row_lead=0
opposite_dirs={2,1,4,3}
camera_pan_freq=6
draw_sprites=true
draw_debug_shapes=false
godmode=false
-- system vars
curr_game_mode='title_screen' -- title_screen / game
-- game vars
frame_skip=1 --1 means no skips
wipe_frames=0
is_unwiping=false
actual_frame=0
is_paused=false
is_drawing=true
is_handling_train_car_hit=false
train_car_to_kill=nil
game_frame=0
freeze_frames=0
camera_pan_z=0
-- input vars
held_dir=0
pressed_dir=0
prev_btns={}
-- level vars
level=nil
top_row=nil
bottom_row=nil
prev_loaded_entity_row=0
-- game objects
player_entity=nil
entities={}
spawned_entities={}
player_entities={}
player_projectile_entities={}
enemy_entities={}
enemy_projectile_entities={}
terrain_entities={}
obstacle_entities={}
pickup_entities={}
effects={}
tiles={}
directives={}


-- init
function reset()
	-- game vars
	frame_skip=1
	wipe_frames=0
	is_unwiping=false
	actual_frame=0
	is_paused=false
	is_drawing=true
	is_handling_train_car_hit=false
	train_car_to_kill=nil
	game_frame=0
	freeze_frames=0
	camera_pan_z=0
	-- input vars
	held_dir=0
	pressed_dir=0
	prev_btns={}
	-- level vars
	level=nil
	top_row=nil
	bottom_row=nil
	prev_loaded_entity_row=0
	-- game objects
	player_entity=nil
	entities={}
	spawned_entities={}
	player_entities={}
	player_projectile_entities={}
	enemy_entities={}
	enemy_projectile_entities={}
	terrain_entities={}
	obstacle_entities={}
	pickup_entities={}
	effects={}
	tiles={}
	directives={}
end

function add_spawned_entities()
	for i=1,#spawned_entities do
		local chan=spawned_entities[i].hit_channel
		local entity=spawned_entities[i]
		add(entities,entity)
		if chan=="player" then
			add(player_entities,entity)
		elseif chan=="player_projectile" then
			add(player_projectile_entities,entity)
		elseif chan=="enemy" then
			add(enemy_entities,entity)
		elseif chan=="enemy_projectile" then
			add(enemy_projectile_entities,entity)
		elseif chan=="terrain" then
			add(terrain_entities,entity)
		elseif chan=="obstacle" then
			add(obstacle_entities,entity)
		elseif chan=="pickup" then
			add(pickup_entities,entity)
		end
	end
	spawned_entities={}
end

function load_level(l)
	level=levels[l]

	-- create tiles
	check_for_tile_load()

	-- create entities
	check_for_entity_load()

	--create player entities
	local col=level.player_spawn[1]
	local row=level.player_spawn[2]
	local num_cars=level.player_spawn[3]
	local next_car=spawn_entity_at_tile("train_caboose",col,row-1-num_cars,3,{
		["add_directive"]=true
	})
	local i
	for i=num_cars,1,-1 do
		next_car=spawn_entity_at_tile("train_car",col,row-i,3,{
			["next_car"]=next_car,
			["add_directive"]=true
		})
	end
	player_entity=spawn_entity_at_tile("train_engine",col,row,3,{
		["next_car"]=next_car,
		["is_immobile"]=false
	})

	-- add entities to scene
	add_spawned_entities()
end

function check_for_entity_load()
	local max_view_row=flr((camera_pan_z+128)/tile_size)+1
	local first_row=prev_loaded_entity_row+1
	local last_row=max_view_row+entity_spawn_row_lead
	if last_row>0 and first_row<=last_row then
		local r
		for r=first_row,last_row do
			load_entity_row(r)
		end
		prev_loaded_entity_row=last_row
	end
end

function load_entity_row(r)
	local i
	for i=1,#level.entity_list do
		local type=level.entity_list[i][1]
		local col=level.entity_list[i][2]
		local row=level.entity_list[i][3]
		local facing=level.entity_list[i][4]
		local init_args=level.entity_list[i][5] or {}
		if row==r then
			spawn_entity_at_tile(type,col,row,facing,init_args)
		end
	end
end

function check_for_tile_load()
	-- figure out which rows the user can see
	local min_view_row=flr(camera_pan_z/tile_size)+1
	local max_view_row=flr((camera_pan_z+128)/tile_size)+1

	-- figure out if we need to load more rows
	if bottom_row==nil or top_row==nil or (top_row<max_view_row+min_tile_row_lead and top_row<#level.tile_map) then
		bottom_row=max(1,min_view_row)
		top_row=max(1,min(#level.tile_map,max_view_row+max_tile_row_lead))
		load_tiles()
	end
end

function load_tiles()
	-- load the tile rows, reusing any we can use
	local temp={}
	for r=bottom_row,top_row do
		if tiles[r] then
			temp[r]=tiles[r]
		else
			temp[r]=load_tile_row(r)
		end
	end
	tiles=temp
end

function load_tile_row(r)
	local tile_row={}
	local data_row=#level.tile_map-r+1
	for c=1,#level.tile_map[data_row] do
		local s=sub(level.tile_map[data_row],c,c)
		if s==" " then
			tile_row[c]=false
		else
			tile_row[c]={
				["col"]=c,
				["row"]=r,
				["frames"]=level.tile_library[s][1],
				["flipped"]=level.tile_library[s][2],
				["is_solid"]=level.tile_library[s][3] or false,
				["has_wall"]=level.tile_library[s][4] or {false,false,false,false}
			}
			if level.tile_library[s][5] then
				spawn_entity_at_tile(level.tile_library[s][5][1],c,r,level.tile_library[s][5][2],level.tile_library[s][5][3])
			end
		end
	end
	return tile_row
end

function instantiate_entity(type)
	local def=entity_library[type]
	local entity={
		-- entity properties
		["type"]=type,
		["width"]=def.width or 6,
		["depth"]=def.depth or 6,
		["has_grid_movement"]=def.has_grid_movement or false,
		["hit_channel"]=def.hit_channel,
		["frame_offset"]=def.frame_offset or 0,
		["animation"]=nil,
		["render_priority"]=def.render_priority or 0,
		["projectile_armor"]=def.projectile_armor or 0,
		["casts_shadows"]=def.casts_shadows!=false,
		-- methods
		["init"]=def.init or noop,
		["pre_move_update"]=def.pre_move_update or noop,
		["update"]=def.update or noop,
		["on_hit"]=def.on_hit or noop,
		["on_hit_by"]=def.on_hit_by or noop,
		["on_hit_wall"]=def.on_hit_wall or noop,
		["on_hit_ground"]=def.on_hit_ground or noop,
		["on_fall_off"]=def.on_fall_off or noop,
		["pre_destroyed"]=def.pre_destroyed or noop,
		["destroyed"]=def.destroyed or noop,
		-- stateful fields
		["x"]=0,
		["y"]=0,
		["z"]=0,
		["vx"]=0,
		["vy"]=0,
		["vz"]=0,
		["gravity"]=def.gravity or 0,
		["col"]=0,
		["row"]=0,
		["facing"]=1,
		["is_on_grid"]=def.is_on_grid!=false,
		["is_alive"]=true,
		["is_frozen"]=false,
		["has_hitbox"]=true,
		["has_hurtbox"]=true,
		["action"]="default",
		["action_frames"]=0,
		["action_loops"]=true,
		["wiggle_frames"]=0,
		["freeze_frames"]=0,
		["frames_alive"]=0,
		["frames_to_death"]=def.frames_to_death or 0,
		["death_cause"]=nil
	}
	-- some additional props for grid-moving entities
	if entity.has_grid_movement then
		entity.grid_move_pattern=def.grid_move_pattern
		entity.tile_update_frame=def.tile_update_frame --1 = at very end, #pattern = at very start
		-- stateful fields
		entity.move_dir=0
		entity.move_frames_left=0
	end
	-- unpack animations for each action
	local action
	local anim
	if def.animation!=nil then
		entity.animation={}
		for action,anim in pairs(def.animation) do
			entity.animation[action]={
				anim["sides"] or anim,
				anim["sides"] or anim,
				anim["back"] or anim,
				anim["front"] or anim
			}
		end
	end
	-- return the entity
	return entity
end

function spawn_entity_at_tile(type,col,row,facing,init_args)
	local entity=instantiate_entity(type)
	entity.x=tile_size*(col-1)+(tile_size-entity.width)/2
	entity.z=tile_size*(row-1)+(tile_size-entity.depth)/2
	entity.col=col
	entity.row=row
	entity.facing=facing or 4
	entity.init(entity,init_args)
	add(spawned_entities,entity)
	return entity
end

function spawn_entity_at_pos(type,x,z,facing,init_args)
	local entity=instantiate_entity(type)
	entity.x=x
	entity.z=z
	entity.col=flr((entity.x+entity.width/2)/tile_size+1)
	entity.row=flr(entity.z/tile_size)+1
	entity.facing=facing or 4
	entity.init(entity,init_args)
	add(spawned_entities,entity)
	return entity
end

function spawn_entity_centered_at_pos(type,x,z,facing,init_args)
	local entity=instantiate_entity(type)
	entity.x=x-entity.width/2
	entity.z=z-entity.depth/2
	entity.col=flr((entity.x+entity.width/2)/tile_size+1)
	entity.row=flr(entity.z/tile_size)+1
	entity.facing=facing or 4
	entity.init(entity,init_args)
	add(spawned_entities,entity)
	return entity
end

function instantiate_effect(type)
	local def=effect_library[type]
	local effect={
		-- effect properties
		["type"]=type,
		["width"]=def.width or 6,
		["depth"]=def.depth or 6,
		["frame_offset"]=def.frame_offset or 0,
		["animation"]=def.animation,
		-- methods
		["init"]=def.init or noop,
		["update"]=def.update or noop,
		["destroyed"]=def.destroyed or noop,
		-- stateful fields
		["x"]=0,
		["y"]=0,
		["z"]=0,
		["is_alive"]=true,
		["is_frozen"]=false,
		["frames_alive"]=0,
		["frames_to_death"]=def.frames_to_death or 0
	}
	return effect
end

-- function spawn_effect_at_tile(type,col,row,init_args)
-- 	local effect=instantiate_effect(type)
-- 	effect.x=tile_size*(col-1)+(tile_size-effect.width)/2
-- 	effect.z=tile_size*(row-1)+(tile_size-effect.depth)/2
-- 	effect.init(effect,init_args)
-- 	add(effects,effect)
-- 	return effects
-- end

-- function spawn_effect_at_pos(type,x,z,init_args)
-- 	local effect=instantiate_effect(type)
-- 	effect.x=x
-- 	effect.z=z
-- 	effect.init(effect,init_args)
-- 	add(effects,effect)
-- 	return effect
-- end

-- function spawn_effect_centered_at_pos(type,x,z,init_args)
-- 	local effect=instantiate_effect(type)
-- 	effect.x=x-effect.width/2
-- 	effect.z=z-effect.depth/2
-- 	effect.init(effect,init_args)
-- 	add(effects,effect)
-- 	return effect
-- end

function spawn_effect_centered_on(type,parent,init_args)
	local effect=instantiate_effect(type)
	effect.x=parent.x+parent.width/2-effect.width/2
	effect.z=parent.z+parent.y+parent.depth/2-effect.depth/2
	effect.init(effect,init_args)
	add(effects,effect)
	return effect
end

function _init()
	-- curr_game_mode='game'
	-- reset()
	-- load_level(1)
	local next_car=spawn_entity_at_tile("train_caboose",6,-12,2,{
		["add_directive"]=false
	})
	local i
	for i=1,9 do
		next_car=spawn_entity_at_tile("train_car",6+i,-12,2,{
			["next_car"]=next_car,
			["add_directive"]=false
		})
		next_car.friend=spawn_entity_at_pos("friend_in_cart",next_car.x,next_car.z,next_car.facing,{
			["friend_type"]=flr(rnd(4))
		})
	end
	player_entity=spawn_entity_at_tile("train_engine",16,-12,2,{
		["next_car"]=next_car,
		["is_immobile"]=true
	})
end


-- update
function update_entity(entity)
	if entity.is_frozen then
		return
	elseif entity.freeze_frames>0 then
		entity.freeze_frames-=1
		return
	end

	-- update timers
	entity.frames_alive+=1
	entity.action_frames+=1
	if not entity.action_loops and entity.animation!=nil and entity.action_frames>=anim_mult*#entity.animation[entity.action][entity.facing] then
		set_entity_action(entity,"default",true)
	end
	if entity.frames_to_death>0 then
		entity.frames_to_death-=1
		if entity.frames_to_death<=0 then
			entity.is_alive=false
			entity.destroyed(entity,entity.death_cause)
			return
		end
	end
	if entity.wiggle_frames>0 then
		entity.wiggle_frames-=1
	end

	-- the entity may want to adjust its velocity
	entity.pre_move_update(entity)
	if entity.is_frozen or entity.freeze_frames>0 then
		return
	end

	-- entities on the grid have special movement logic
	if entity.is_on_grid and entity.has_grid_movement then
		entity.vx=0
		entity.vz=0
		if entity.move_frames_left>0 then
			local dist=entity.grid_move_pattern[entity.move_frames_left]
			local dx
			local dz
			dx,dz=dir_to_vec(entity.move_dir)
			entity.vx+=dx*dist
			entity.vz+=dz*dist
			if entity.move_frames_left==entity.tile_update_frame then
				entity.col+=dx
				entity.row+=dz
				--check for fall-off
				local tile=get_tile(entity.col,entity.row)
				if tile!=nil and tile.has_wall[entity.move_dir] then
					entity.on_hit_wall(entity)
				elseif tile==nil or not tile.is_solid then
					entity.is_on_grid=false
					entity.move_frames_left=0
					entity.on_fall_off(entity)
				end
			end
			entity.move_frames_left-=1
		end
	end

	-- move entity
	if not entity.is_on_grid then
		entity.vy-=entity.gravity
	end
	local prev_y=entity.y
	entity.x+=entity.vx
	entity.y+=entity.vy
	entity.z+=entity.vz

	-- entity might fall onto the grid
	local tile=get_tile(entity.col,entity.row)
	if not entity.is_on_grid and entity.vy<0 and entity.y<=0 and prev_y>=0 and tile!=nil and tile.is_solid then
		if entity.on_hit_ground(entity)!=false then
			entity.is_on_grid=true
			entity.y=0
			entity.vy=0
			-- align x and z to the grid (hopefully col/row are almost what they should be)
			entity.x=tile_size*(entity.col-1)
			entity.z=tile_size*(entity.row-1)
		end
	end

	-- entities that fall too far are dead
	if entity.y<-10 then
		spawn_effect_centered_on("poof",entity)
		entity.is_alive=false
	end

	-- update the tile's col and row
	if not entity.is_on_grid then
		entity.col=flr((entity.x+entity.width/2)/tile_size+1)
		entity.row=flr(entity.z/tile_size)+1
	end

	-- the entity might want to do some revisions post-move
	entity.update(entity)
end

function update_effect(effect)
	if effect.is_frozen then
		return
	end

	-- update timers
	effect.frames_alive+=1
	if effect.frames_to_death>0 then
		effect.frames_to_death-=1
		if effect.frames_to_death<=0 then
			effect.is_alive=false
			effect.destroyed(effect)
			return
		end
	end

	-- call the effect's update method
	effect.update(effect)
end

function move_entity_on_grid(entity,dir)
	entity.move_frames_left=#entity.grid_move_pattern
	entity.move_dir=dir
	entity.facing=dir
end

function is_entity_moving_on_grid(entity)
	return entity.move_frames_left>0
end

function set_entity_action(entity,action,loops)
	entity.action=action
	entity.action_frames=0
	entity.action_loops=loops or false
end

function is_alive(x)
	return x.is_alive
end

function freeze(x)
	x.is_frozen=true
end

function unfreeze(x)
	x.is_frozen=false
end

function check_for_collisions(hitters,hittees)
	local i
	for i=1,#hitters do
		local j
		for j=1,#hittees do
			check_for_collision(hitters[i],hittees[j])
		end
	end
end

function check_for_collision(hitter,hittee)
	if hitter.has_hitbox and hittee.has_hurtbox then
		-- if hitter.is_on_grid and hittee.is_on_grid then
			if hitter.col==hittee.col and hitter.row==hittee.row then
				if hitter.on_hit(hitter,hittee)!=false then
					hittee.on_hit_by(hittee,hitter)
				end
			end
		-- elseif entities_are_overlapping(hitter,hittee) then
			-- if hitter.on_hit(hitter,hittee)!=false then
				-- hittee.on_hit_by(hittee,hitter)
			-- end
		-- end
	end
end

function get_tile(col,row)
	if tiles[row] and tiles[row][col] then
		return tiles[row][col]
	end
	return nil
end

function get_tile_frame(col,row)
	local tile=get_tile(col,row)
	if tile==nil then
		return nil
	end
	local f=flr(game_frame/anim_mult)%#tile.frames+1
	return tile.frames[f]
end

function kill_if_out_of_bounds(obj)
	local left=obj.x
	local right=left+obj.width-1
	local bottom=obj.z+obj.y
	local top=bottom+obj.depth-1
	if right<0 or left>128 or top<camera_pan_z then
		obj.is_alive=false
	end
end

function destroy_entity(entity,cause)
	entity.has_hurtbox=false
	entity.has_hitbox=false
	if entity.animation!=nil and entity.animation.destroyed then
		if entity.action!="destroyed" then
			set_entity_action(entity,"destroyed")
			entity.frames_to_death=anim_mult*#entity.animation[entity.action][entity.facing]
			entity.death_cause=cause
			entity.pre_destroyed(entity,cause)
		end
	else
		entity.death_cause=cause
		entity.pre_destroyed(entity,cause)
		entity.is_alive=false
		entity.destroyed(entity,cause)
	end
end

function handle_train_car_hit(entity)
	freeze_frames=5
	is_handling_train_car_hit=true
	train_car_to_kill=entity
	foreach(entities,freeze)
	foreach(effects,freeze)
	local car=player_entity
	while car!=nil do
		car.has_hurtbox=false
		car=car.next_car
	end
	add(directives,{
		["x"]=entity.x,
		["z"]=entity.z,
		["type"]="resume_play",
		["is_alive"]=true
	})
end

function _update()
	-- simulation will not update while paused
	actual_frame+=1

	-- wipes still continue
	if wipe_frames>0 then
		wipe_frames-=1
		if wipe_frames<=0 and not is_unwiping then
			if curr_game_mode=='title_screen' then
				reset()
				curr_game_mode='game'
				load_level(1)
				wipe_frames=25
				is_unwiping=true
			elseif curr_game_mode=='game' and (player_entity==nil or not player_entity.is_alive) then
				reset()
				load_level(1)
				wipe_frames=25
				is_unwiping=true
			end
		end
	end

	if actual_frame%frame_skip!=0 or is_paused then
		return
	end

	-- freeze frames cause us to skip a chunk of frames
	if freeze_frames>0 then
		freeze_frames-=1
		return
	end
	-- after the screen wipe, we reset the level
	if curr_game_mode=='title_screen' then
		if btn(4) and wipe_frames<=0 then -- Z
			wipe_frames=25
			is_unwiping=false
		end
	elseif curr_game_mode=='game' then
		if player_entity==nil then
			if train_car_to_kill!=nil then
				destroy_entity(train_car_to_kill)
				train_car_to_kill=train_car_to_kill.next_car
			end
		-- when the player is killed, we have some freeze frames!
		elseif not player_entity.is_alive then
			local car=player_entity.next_car
			while car!=nil do
				car.has_hurtbox=false
				car=car.next_car
			end
			train_car_to_kill=player_entity.next_car
			player_entity=nil
			freeze_frames+=5
			frame_skip=3
			wipe_frames=75
			is_unwiping=false
		end

		if is_handling_train_car_hit then
			if train_car_to_kill.type=="train_caboose" then
				unfreeze(train_car_to_kill)
			else
				destroy_entity(train_car_to_kill)
				train_car_to_kill=train_car_to_kill.next_car
				freeze_frames=1
			end
		else
			-- the camera slowly pans upwards
			if game_frame%camera_pan_freq==0 then
				camera_pan_z+=1
			end

			-- handle inputs
			held_dir=0
			local curr_btns={}
			local i
			for i=1,4 do
				curr_btns[i]=btn(i-1)
				if curr_btns[i] and player_entity!=nil and i!=player_entity.move_dir and i!=opposite_dirs[player_entity.move_dir] then
					held_dir=i
					if not prev_btns[i] and pressed_dir==0 then
						pressed_dir=i
					end
				end
			end
		end
	end

	-- update entities/effects
	foreach(entities,update_entity)
	foreach(effects,update_effect)

	if curr_game_mode=='game' then
		if is_handling_train_car_hit then
			if train_car_to_kill!=nil and train_car_to_kill.type=="train_caboose" then
				update_entity(train_car_to_kill)
			end
		else
			-- check for collisions (hitter-->hittee)
			check_for_collisions(player_projectile_entities,obstacle_entities)
			check_for_collisions(player_projectile_entities,enemy_projectile_entities)
			check_for_collisions(player_projectile_entities,enemy_entities)

			check_for_collisions(enemy_projectile_entities,obstacle_entities)
			check_for_collisions(enemy_projectile_entities,player_entities)

			check_for_collisions(terrain_entities,enemy_entities)
			check_for_collisions(obstacle_entities,enemy_entities)
			check_for_collisions(player_projectile_entities,enemy_entities)

			check_for_collisions(player_entities,pickup_entities)
			check_for_collisions(terrain_entities,player_entities)
			check_for_collisions(obstacle_entities,player_entities)
			check_for_collisions(enemy_entities,player_entities)
			check_for_collisions(enemy_projectile_entities,player_entities)

			if player_entity!=nil and player_entity.is_on_grid then
				local i
				local car=player_entity.next_car
				while car!=nil do
					check_for_collision(car,player_entity)
					car=car.next_car
				end
			end
		end
	elseif curr_game_mode=='title_screen' then
		local car=player_entity
		local bounce=game_frame
		while car!=nil do
			car.y=-3+1.5*cos(bounce/32)
			car=car.next_car
			bounce-=3
		end
	end

	if not is_handling_train_car_hit then
		game_frame+=1
	end

	-- add new entities to the game
	add_spawned_entities()

	if curr_game_mode=='game' then
		-- kill entities/effects that go out of bound
		foreach(entities,kill_if_out_of_bounds)
		foreach(effects,kill_if_out_of_bounds)
	end

	-- cull dead entities/effects
	entities=filter_list(entities,is_alive)
	effects=filter_list(effects,is_alive)
	player_entities=filter_list(player_entities,is_alive)
	player_projectile_entities=filter_list(player_projectile_entities,is_alive)
	enemy_entities=filter_list(enemy_entities,is_alive)
	enemy_projectile_entities=filter_list(enemy_projectile_entities,is_alive)
	terrain_entities=filter_list(terrain_entities,is_alive)
	obstacle_entities=filter_list(obstacle_entities,is_alive)
	pickup_entities=filter_list(pickup_entities,is_alive)

	-- resume play once the caboose is caught up
	if curr_game_mode=='game' and is_handling_train_car_hit and train_car_to_kill==nil then
		is_handling_train_car_hit=false
		foreach(entities,unfreeze)
		foreach(effects,unfreeze)
	end
end


-- draw
function draw_entity(entity)
	-- outline tile the entity is on
	if draw_debug_shapes then
		local left=tile_size*(entity.col-1)
		local right=left+tile_size-1
		local bottom=tile_size*(entity.row-1)
		local top=bottom+tile_size-1
		rect(left,-top,right,-bottom,12)
		pset(left,-bottom,7)
	end
	do
		local left=entity.x
		local right=left+entity.width-1
		local bottom=entity.z
		local top=bottom+entity.depth-1
		-- draw shadow
		if entity.y>0 and entity.casts_shadows and curr_game_mode=='game' then
			local shadow_frame=28
			if entity.y>10 then
				shadow_frame=27
			end
			spr(shadow_frame,left-4+entity.width/2,-top-5+entity.depth/2,1,1,false,false)
		end
		-- draw sprite
		bottom+=entity.y
		top+=entity.y
		if draw_sprites and entity.animation!=nil then
			local f = entity.action_frames
			if entity.action=="default" then
				f = game_frame
			end
			local anim=entity.animation[entity.action][entity.facing]
			local frame=anim[flr(f/anim_mult)%#anim+1]
			local flipped=(entity.facing==1)
			local wiggle=0
			if entity.wiggle_frames>0 then
				wiggle=2*(game_frame%2)-1
			end
			spr(frame+entity.frame_offset,left+wiggle-4+entity.width/2,-top-5+entity.depth/2,1,1,flipped,false)
		end
		-- draw hitbox
		if draw_debug_shapes then
			if entity.is_on_grid then
				rect(left,-top,right,-bottom,10)
				pset(left,-bottom,7)
			else
				rect(left,-top,right,-bottom,14)
				pset(left,-bottom,7)
			end
		end
	end
end


function draw_effect(effect)
	-- draw sprite
	local left=effect.x
	local right=left+effect.width-1
	local bottom=effect.z+effect.y
	local top=bottom+effect.depth-1
	if draw_sprites then
		local f = effect.frames_alive
		local anim=effect.animation
		local frame=anim[flr(f/anim_mult)%#anim+1]
		spr(frame+effect.frame_offset,left-4+effect.width/2,-top-5+effect.depth/2)
	end
	-- draw hitbox
	if draw_debug_shapes then
		rect(left,-top,right,-bottom,2)
		pset(left,-bottom,7)
	end
end

function draw_tile(tile)
	local left=tile_size*(tile.col-1)
	local right=left+tile_size-1
	local bottom=tile_size*(tile.row-1)
	local top=bottom+tile_size-1
	local f=flr(game_frame/anim_mult)%#tile.frames+1
	if draw_debug_shapes then
		if not tile.is_solid then
			rectfill(left,-top,right,-bottom,5)
		elseif (tile.col+tile.row)%2==0 then
			rectfill(left,-top,right,-bottom,6)
		else
			rectfill(left,-top,right,-bottom,13)
		end
	end
	if draw_sprites then
		spr(tile.frames[f],left-1,-top-2,1,1,tile.flipped,false)
	end
end

function draw_directive(directive)
	if draw_debug_shapes then
		local left=directive.x
		local right=left+5-1
		local bottom=directive.z
		local top=bottom+5-1
		if directive.type=="move" then
			if directive.dir==1 then
				rectfill(left+0,-top+2,left+0,-bottom-2,14)
				rectfill(left+1,-top+1,left+1,-bottom-1,14)
				rectfill(left+2,-top+0,left+2,-bottom-0,14)
			elseif directive.dir==2 then
				rectfill(left+2,-top+2,left+2,-bottom-2,14)
				rectfill(left+1,-top+1,left+1,-bottom-1,14)
				rectfill(left+0,-top+0,left+0,-bottom-0,14)
			elseif directive.dir==3 then
				rectfill(left+2,-bottom-2,right-2,-bottom-2,14)
				rectfill(left+1,-bottom-1,right-1,-bottom-1,14)
				rectfill(left+0,-bottom-0,right-0,-bottom-0,14)
			elseif directive.dir==4 then
				rectfill(left+2,-bottom-0,right-2,-bottom-0,14)
				rectfill(left+1,-bottom-1,right-1,-bottom-1,14)
				rectfill(left+0,-bottom-2,right-0,-bottom-2,14)
			end
		else
			rectfill(left,-top,right,-bottom,14)
		end
	end
end

function is_rendered_on_top(a,b)
	if a.z<b.z then
		return true
	elseif a.z>b.z then
		return false
	elseif a.render_priority>b.render_priority then
		return true
	elseif a.render_priority<b.render_priority then
		return false
	elseif a.y>b.y then
		return true
	elseif a.y<b.y then
		return false
	elseif a.x<b.x then
		return true
	end
	return false
end

function _draw()
	if not is_drawing then
		return
	end


	-- reset background
	camera()
	rectfill(0,0,127,127,0)
	if curr_game_mode=='game' then
		rectfill(0,0,127,127,level.bg_color)
		camera(-1,-127-camera_pan_z)

		-- draw clouds
		level.draw_bg()

		-- draw tiles
		local r
		for r=top_row,bottom_row,-1 do
			local c
			for c=1,#tiles[r] do
				if tiles[r][c] then
					draw_tile(tiles[r][c])
				end
			end
		end
	elseif curr_game_mode=='title_screen' then
		-- super
		spr(202,50,25)
		spr(203,58,25)
		spr(204,66,25)
		spr(205,70,25)

		-- y...
		spr(218,43,35)
		spr(218,51,35,1,1,true)
		spr(234,47,43)

		-- ...a...
		spr(219,56,35)
		spr(219,64,35,1,1,true)
		spr(234,56,43)
		spr(234,64,43)

		-- ...y
		spr(218,69,35)
		spr(218,77,35,1,1,true)
		spr(234,73,43)

		-- train
		spr(250,49,52)
		spr(205,54,52)
		spr(251,63,52)
		spr(252,71,52)

		if game_frame%26>4 or wipe_frames>0 then
			print("press z to start",32,97,7)
		end
	end

	-- sort entities so that they are properly layered
	sort_list(entities,is_rendered_on_top)

	-- draw entities
	foreach(entities,draw_entity)

	-- draw directives (commands for the train)
	foreach(directives,draw_directive)

	-- draw effects
	foreach(effects,draw_effect)

	-- draw UI
	if curr_game_mode=='game' then
		camera()
		print("hbxbss",1,1,7)
	end

	-- draw screen wipe effects (20 frames)
	if wipe_frames>0 then
		draw_wipe(22-wipe_frames,is_unwiping)
	end
end

function draw_wipe(f,is_reversed) -- 0 to 20 (-1 is empty, 21 is full)
	camera()
	local r
	for r=0,128,6 do
		local c
		for c=0,128,6 do
			local size=min(max(0,f-4-c/10+r/30),4)
			if is_reversed then
				size=4-size
			end
			if size>0 then
				circfill(c,r,size,0)
			end
		end
	end
end


-- helper methods
function noop() end

function list_has_value(list,val)
	local _
	local v
	for _,v in pairs(list) do
		if v==val then
			return true
		end
	end
	return false
end

function sort_list(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

function filter_list(list,func)
	local i
	local l={}
	for i=1,#list do
		if func(list[i],i,list) then
			add(l,list[i])
		end
	end
	return l
end

function add_all(list,list2)
	local i
	for i=1,#list2 do
		add(list,list2[i])
	end
	return list
end

function dir_to_vec(dir,mult)
	mult=mult or 1
	if dir==1 then
		return -mult,0
	elseif dir==2 then
		return mult,0
	elseif dir==3 then
		return 0,mult
	elseif dir==4 then
		return 0,-mult
	else
		return 0,0
	end
end

function entities_are_overlapping(a,b)
	local a_left=a.x
	local a_right=a_left+a.width-1
	local a_bottom=a.z -- +a.y
	local a_top=a_bottom+a.depth-1
	local b_left=b.x
	local b_right=b_left+b.width-1
	local b_bottom=b.z -- +b.y
	local b_top=b_bottom+b.depth-1
	return rects_are_overlapping(a_left,a_bottom,a_right,a_top,b_left,b_bottom,b_right,b_top)
end

function rects_are_overlapping(x1,y1,x2,y2,x3,y3,x4,y4)
	-- assumes x1 < x2, y1 < y2, x3 < x4, y3 < y4
	if x2 < x3 or x4 < x1 or y2 < y3 or y4 < y1 then
		return false
	end
	return true
end

function exit_and_print(lines)
	is_paused=true
	is_drawing=fale
	camera()
	cls()
	local i
	color(8)
	for i=1,#lines do
		print(lines[i])
	end
end


-- data
entity_library={
	["train_engine"]={
		["hit_channel"]="player",
		["animation"]={
			["default"]={["front"]={1},["back"]={2},["sides"]={0}}
		},
		["gravity"]=0.15,
		["has_grid_movement"]=true,
		["grid_move_pattern"]={1,1,1,1,1,1},
		["tile_update_frame"]=2,
		["init"]=function(entity,args)
			entity.is_immobile=args.is_immobile
			entity.frames_between_shots=15
			entity.frames_to_shot=entity.frames_between_shots
			entity.next_car=args.next_car
		end,
		["pre_move_update"]=function(entity)
			if entity.move_frames_left<=0 and not entity.is_immobile then
				local dir=entity.facing
				if pressed_dir!=0 then
					dir=pressed_dir
					pressed_dir=0
				elseif held_dir!=0 then
					dir=held_dir
				end
				move_entity_on_grid(entity,dir)
				add(directives,{
					["x"]=entity.x,
					["z"]=entity.z,
					["type"]="move",
					["dir"]=entity.move_dir,
					["is_alive"]=true
				})
			end
		end,
		["update"]=function(entity)
			if entity.frames_to_shot==0 then
				if btn(4) then
					entity.frames_to_shot=entity.frames_between_shots
					local vx
					local vz
					vx,vz=dir_to_vec(entity.facing)
					local bullet=spawn_entity_centered_at_pos("player_bullet",entity.x+entity.width/2,entity.z+entity.depth/2,entity.facing,{
						["vx"]=4*vx,
						["vz"]=4*vz
					})
				end
			else
				entity.frames_to_shot-=1
			end
			if godmode then
				entity.y=0
				entity.vy=0
				entity.is_on_grid=true
			end
		end,
		["on_hit_wall"]=function(entity)
			if not godmode then
				destroy_entity(entity)
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			if not godmode then
				destroy_entity(entity)
			end
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("explosion",entity)
		end
	},
	["train_car"]={
		["hit_channel"]="player",
		["animation"]={
			["default"]={["front"]={19},["back"]={19},["sides"]={3}}
		},
		["gravity"]=0.15,
		["has_grid_movement"]=true,
		["grid_move_pattern"]={1,1,1,1,1,1},
		["tile_update_frame"]=2,
		["init"]=function(entity,args)
			if args.add_directive then
				add(directives,{
					["x"]=entity.x,
					["z"]=entity.z,
					["type"]="move",
					["dir"]=entity.facing,
					["is_alive"]=true
				})
			end
			entity.friend=nil
			entity.next_car=args.next_car
		end,
		["pre_move_update"]=function(entity)
			local i
			for i=1,#directives do
				if directives[i].x==entity.x and directives[i].z==entity.z then
					if directives[i].type=="move" then
						move_entity_on_grid(entity,directives[i].dir)
					end
				end
			end
		end,
		["update"]=function(entity)
			if entity.friend!=nil then
				entity.friend.x=entity.x
				entity.friend.y=entity.y+3
				entity.friend.z=entity.z
				entity.friend.facing=entity.facing
			end
		end,
		["on_hit_wall"]=function(entity)
			destroy_entity(entity)
		end,
		["on_hit_by"]=function(entity,hitter)
			handle_train_car_hit(entity)
		end,
		["destroyed"]=function(entity,cause)
			if entity.friend!=nil then
				destroy_entity(entity.friend)
			end
			spawn_effect_centered_on("explosion",entity)
		end
	},
	["train_caboose"]={
		["hit_channel"]="player",
		["animation"]={
			["default"]={["front"]={17},["back"]={18},["sides"]={16}}
		},
		["gravity"]=0.15,
		["has_grid_movement"]=true,
		["grid_move_pattern"]={1,1,1,1,1,1},
		["tile_update_frame"]=2,
		["projectile_armor"]=1,
		["init"]=function(entity,args)
			if args.add_directive then
				add(directives,{
					["x"]=entity.x,
					["z"]=entity.z,
					["type"]="move",
					["dir"]=entity.facing,
					["is_alive"]=true
				})
			end
			entity.next_car=nil
		end,
		["pre_move_update"]=function(entity)
			local i
			for i=1,#directives do
				if directives[i].x==entity.x and directives[i].z==entity.z then
					if directives[i].type=="move" then
						move_entity_on_grid(entity,directives[i].dir)
					elseif directives[i].type=="resume_play" then
						freeze(entity)
						train_car_to_kill=nil
						-- reassociate the cars to the right next cars
						local car=player_entity
						while car.next_car!=nil do
							car.has_hurtbox=true
							if not car.next_car.is_alive or car.next_car.frames_to_death>0 then
								car.next_car=entity
							end
							car=car.next_car
						end
						freeze_frames=2
					end
					directives[i].is_alive=false
				end
			end
			directives=filter_list(directives,is_alive)
		end,
		["on_hit_wall"]=function(entity)
			-- destroy_entity(entity)
		end,
		["on_hit_by"]=function(entity,hitter)
			-- destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("explosion",entity)
		end
	},
	["shrub"]={
		["hit_channel"]="obstacle",
		["animation"]={
			["default"]={26}
		},
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("explosion",entity)
		end
	},
	["coin"]={
		["hit_channel"]="pickup",
		["animation"]={
			["default"]={32,33,34,35}
		},
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("coin_pickup",entity)
		end
	},
	["spear-thrower"]={
		["hit_channel"]="enemy",
		["animation"]={
			["default"]={64,64,64,65,65,65},
			["shooting"]={66,66,66,67,67,67},
			["destroyed"]={68}
		},
		["init"]=function(entity,args)
			entity.frames_between_shots=60
			entity.frames_to_shot=entity.frames_between_shots
			entity.shoot_frame=15
		end,
		["update"]=function(entity)
			if entity.frames_to_shot<=0 and entity.action=="default" then
				set_entity_action(entity,"shooting")
				entity.frames_to_shot=entity.frames_between_shots
			else
				entity.frames_to_shot-=1
			end
			if entity.action=="shooting" and entity.action_frames==entity.shoot_frame then
				local vx
				local vz
				vx,vz=dir_to_vec(entity.facing)
				local bullet=spawn_entity_centered_at_pos("spear",entity.x+entity.width/2,entity.z+entity.depth/2,entity.facing,{
					["vx"]=vx,
					["vz"]=vz
				})
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("explosion",entity)
		end
	},
	["player_bullet"]={
		["width"]=4,
		["depth"]=4,
		["is_on_grid"]=false,
		["hit_channel"]="player_projectile",
		["animation"]={
			["default"]={
				["front"]={5,4,5,6},
				["back"]={5,4,5,6},
				["sides"]={21,20,21,22}
			}
		},
		["init"]=function(entity,args)
			entity.vx=args.vx
			entity.vz=args.vz
		end,
		["on_hit"]=function(entity,hittee)
			if hittee.projectile_armor>=0 then
				destroy_entity(entity)
				if hittee.projectile_armor>0 then
					spawn_effect_centered_on("deflected",hittee)
					return false
				end
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end
	},
	["spear"]={
		["width"]=4,
		["depth"]=4,
		["is_on_grid"]=false,
		["hit_channel"]="enemy_projectile",
		["animation"]={
			["default"]={69}
		},
		["init"]=function(entity,args)
			entity.vx=args.vx
			entity.vz=args.vz
		end,
		["on_hit"]=function(entity,hittee)
			if hittee.projectile_armor>=0 then
				destroy_entity(entity)
				if hittee.projectile_armor>0 then
					spawn_effect_centered_on("deflected",hittee)
					return false
				end
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,"projectile")
		end,
		["destroyed"]=function(entity,cause)
			if cause=="projectile" then
				spawn_effect_centered_on("poof",entity)
			end
		end
	},
	["clothesline"]={
		["hit_channel"]="obstacle",
		["animation"]={
			["default"]={["front"]={30},["back"]={31},["sides"]={29}}
		},
		["init"]=function(entity,args)
			if entity.facing==2 or entity.facing==3 then
				local i
				local prev=entity
				for i=1,args.length do
					local clothes
					if entity.facing==3 then
						clothes=spawn_entity_at_tile("clothes",entity.col,entity.row+i,2)
					else
						clothes=spawn_entity_at_tile("clothes",entity.col+i,entity.row,4)
					end
					prev.next_neighbor=clothes
					clothes.prev_neighbor=prev
					prev=clothes
				end
				local other_line
				if entity.facing==3 then
					other_line=spawn_entity_at_tile("clothesline",entity.col,entity.row+args.length+1,4)
				else
					other_line=spawn_entity_at_tile("clothesline",entity.col+args.length+1,entity.row,1)
				end
				prev.next_neighbor=other_line
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("poof",entity)
		end
	},
	["clothes"]={
		["hit_channel"]="obstacle",
		["projectile_armor"]=-1,
		["animation"]={
			["default"]={
				["front"]={44,44,44,44,44,45,45,44,44,44,45,45},
				["back"]={44,44,44,44,44,45,45,44,44,44,45,45},
				["sides"]={46,46,46,46,47,47,46,46,47,47,47,47}
			}
		},
		["init"]=function(entity,args)
			if (entity.col+entity.row)%2==0 then
				entity.frame_offset=16
			end
			entity.next_neighbor=nil
			entity.prev_neighbor=nil
		end,
		["update"]=function(entity)
			if entity.next_neighbor!=nil and not entity.next_neighbor.is_alive then
				destroy_entity(entity)
			elseif entity.prev_neighbor!=nil and not entity.prev_neighbor.is_alive then
				destroy_entity(entity)
			end
		end,
		["on_hit"]=function(entity,hittee)
			destroy_entity(entity)
			return false
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("flying_clothes",entity,{["frame_offset"]=entity.frame_offset})
		end
	},
	["tall_grass"]={
		["hit_channel"]="obstacle",
		["projectile_armor"]=-1,
		["render_priority"]=1,
		["animation"]={
			["default"]={41}
		},
		["init"]=function(entity,args)
		end,
		["on_hit"]=function(entity,hittee)
			destroy_entity(entity)
			return false
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["destroyed"]=function(entity,cause)
			spawn_effect_centered_on("shredded_grass",entity)
		end
	},
	["trap"]={
		["hit_channel"]="obstacle",
		["projectile_armor"]=-1,
		["animation"]={
			["default"]={11},
			["prepped"]={12},
			["triggered"]={13}
		},
		["render_priority"]=-1,
		["init"]=function(entity,args)
			entity.frames_to_trigger=0
		end,
		["update"]=function(entity)
			if entity.frames_to_trigger>0 then
				entity.frames_to_trigger-=1
				if entity.frames_to_trigger<=0 then
					entity.has_hitbox=true
					entity.render_priority=0
					entity.projectile_armor=1
					set_entity_action(entity,"triggered",true)
					spawn_effect_centered_on("dirt_blast",entity)
				end
			end
		end,
		["on_hit"]=function(entity,hittee)
			if entity.action!="triggered" then
				entity.frames_to_trigger=5
				set_entity_action(entity,"prepped",true)
				return false
			end
		end
	},
	["jump_pad"]={
		["hit_channel"]="terrain",
		["animation"]={
			["default"]={112},
			["bounce"]={113,114}
		},
		["render_priority"]=-1,
		["on_hit"]=function(entity,hittee)
			if hittee.y==0 then
				hittee.vy=2.1
				hittee.is_on_grid=false
				hittee.move_frames_left=0
				hittee.on_fall_off(hittee)
				if entity.action!="bounce" then
					set_entity_action(entity,"bounce")
				end
			end
			return false
		end
	},
	["boulder"]={
		["hit_channel"]="obstacle",
		["animation"]={
			["default"]={96},
			["damaged"]={97},
			["destroyed"]={98}
		},
		["init"]=function(entity)
			entity.hp=2
		end,
		["on_hit_by"]=function(entity,hitter)
			entity.hp-=1
			spawn_effect_centered_on("dirt_blast",entity)
			if entity.hp==1 then
				set_entity_action(entity,"damaged",true)
				entity.wiggle_frames=5
			elseif entity.hp==0 then
				entity.wiggle_frames=5
				destroy_entity(entity)
			end
		end
	},
	["falling_boulder_spawner"]={
		["hit_channel"]=nil,
		["animation"]=nil,
		["casts_shadows"]=false,
		["init"]=function(entity)
			entity.frames_between_spawns=80
			entity.frames_to_spawn=entity.frames_between_spawns
		end,
		["update"]=function(entity)
			entity.frames_to_spawn-=1
			if entity.frames_to_spawn<=0 then
				entity.frames_to_spawn=entity.frames_between_spawns
				spawn_entity_at_tile("falling_boulder",entity.col,entity.row,entity.facing)
			end
		end
	},
	["falling_boulder"]={
		["hit_channel"]="obstacle",
		["is_on_grid"]=false,
		["animation"]={
			["default"]={99,100,101}
		},
		["gravity"]=0.02,
		["init"]=function(entity)
			entity.has_hitbox=false
			entity.has_hurtbox=false
			entity.vx,entity.vz=dir_to_vec(entity.facing,0.4)
			entity.y=24
		end,
		["on_hit_ground"]=function(entity)
			entity.y=0
			if entity.vy<0 then
				entity.vy=1
				spawn_effect_centered_on("dirt_blast",entity)
				spawn_entity_at_tile("damaging_impact",entity.col,entity.row)
			end
			return false
		end
	},
	["damaging_impact"]={
		["hit_channel"]="terrain",
		["animation"]={
			["default"]={104,105}
		},
		["render_priority"]=2,
		["frames_to_death"]=10,
		["init"]=function(entity)
			entity.has_hurtbox=false
		end
	},
	["friend"]={
		["hit_channel"]="pickup",
		["animation"]={
			["default"]={128,128,129,129}
		},
		["init"]=function(entity,args)
			entity.friend_type=args.friend_type
			entity.frame_offset=16*entity.friend_type
			spawn_effect_centered_on("target_arrow",entity,{
				["parent"]=entity
			})
		end,
		["on_hit_by"]=function(entity,hitter)
			if hitter.type=="train_car" and hitter.friend==nil then
				destroy_entity(entity)
				hitter.friend=spawn_entity_at_pos("friend_in_cart",hitter.x,hitter.z,hitter.facing,{
					["friend_type"]=entity.friend_type
				})
			end
		end
	},
	["friend_in_cart"]={
		["hit_channel"]=nil,
		["casts_shadows"]=false,
		["animation"]={
			["default"]={
				["front"]={132,132,133,133},
				["back"]={134,134,135,135},
				["sides"]={130,130,131,131}
			}
		},
		["init"]=function(entity,args)
			entity.friend_type=args.friend_type
			entity.frame_offset=16*entity.friend_type
		end,
		["destroyed"]=function(entity)
			spawn_effect_centered_on("friend_death",entity,{
				["friend_type"]=entity.friend_type
			})
		end
	},
	["car_expander"]={
		["hit_channel"]="pickup",
		["animation"]={
			["default"]={86}
		},
		["on_hit_by"]=function(entity,hitter)
			if hitter.next_car!=nil then
				destroy_entity(entity)
				local next_car=hitter.next_car
				local new_car=spawn_entity_at_pos("train_car",next_car.x,next_car.z,hitter.facing,{
					["next_car"]=next_car
				})
				new_car.y=next_car.y
				new_car.vx=next_car.vx
				new_car.vy=next_car.vy
				new_car.vz=next_car.vz
				new_car.col=next_car.col
				new_car.row=next_car.row
				new_car.move_dir=next_car.move_dir
				new_car.move_frames_left=next_car.move_frames_left
				new_car.is_on_grid=next_car.is_on_grid
				hitter.next_car=new_car
				-- and finally, freeze everything after the new car
				while next_car!=nil do
					next_car.freeze_frames+=#next_car.grid_move_pattern
					next_car=next_car.next_car
				end
			end
		end
	}
}

effect_library={
	["target_arrow"]={
		["animation"]={56,56,56,57,57,57},
		["init"]=function(effect,args)
			effect.parent=args.parent
		end,
		["update"]=function(effect)
			effect.x=effect.parent.x
			effect.y=effect.parent.y+8
			effect.z=effect.parent.z
			effect.is_alive=effect.parent.is_alive
		end,
	},
	["coin_pickup"]={
		["animation"]={32,48,49,50},
		["frames_to_death"]=20,
		["init"]=function(effect,args)
			effect.vy=2
		end,
		["update"]=function(effect)
			if effect.vy>0 then
				effect.y+=effect.vy
				effect.vy-=0.2
			end
		end
	},
	["explosion"]={
		["animation"]={51,52,53,54},
		["frames_to_death"]=20
	},
	["poof"]={
		["animation"]={36,37,38},
		["frames_to_death"]=15
	},
	["flying_clothes"]={
		["animation"]={42,42,42,42,43,43,43,42,42,42,43,43},
		["init"]=function(effect,args)
			effect.vx=0.4
			effect.vy=-0.1
			effect.frame_offset=args.frame_offset
		end,
		["update"]=function(effect)
			effect.vx+=rnd(0.1)-0.05
			effect.vy+=rnd(0.1)-0.05
			if game_frame%55>45 then
				effect.vx+=0.05
				effect.vy+=0.02
			end
			effect.x+=effect.vx
			effect.y+=effect.vy
		end
	},
	["dirt_blast"]={
		["animation"]={14,15,15},
		["frames_to_death"]=15,
		["init"]=function(effect,args)
			effect.vx=0.2
			effect.vy=1.6
		end,
		["update"]=function(effect)
			effect.vy-=0.1
			effect.x+=effect.vx
			effect.y+=effect.vy
		end
	},
	["shredded_grass"]={
		["animation"]={120,121,121},
		["frames_to_death"]=15
	},
	["deflected"]={
		["animation"]={115,116,117},
		["frames_to_death"]=15
	},
	["friend_death"]={
		["animation"]={129},
		["frames_to_death"]=20,
		["init"]=function(effect,args)
			effect.friend_type=args.friend_type
			effect.frame_offset=16*effect.friend_type
			effect.vy=1
		end,
		["update"]=function(effect)
			effect.vy-=0.1
			effect.y+=effect.vy
		end,
		["destroyed"]=function(effect)
			spawn_effect_centered_on("poof",effect)
		end
	}
}

levels={
	{
		["bg_color"]=15,
		["draw_bg"]=function()
			local min_view_row=flr(camera_pan_z/tile_size)+1
			local max_view_row=flr((camera_pan_z+128)/tile_size)+1
			local r
			for r=min_view_row-3,max_view_row+3 do
				if r%3==0 then
					circfill((game_frame/30+20*r)%158-15,-r*tile_size,21,7)
					circfill((game_frame/30+20*r-20)%158-15,-r*tile_size+r%10-5,16,7)
					circfill((game_frame/30+20*r+20)%158-15,-r*tile_size-r%17+8,14,7)
				end
			end
		end,
		["player_spawn"]={12,12,8}, --col,row,num_cars
		["entity_list"]={
			-- type,col,row,facing,init_args
			-- {"coin",3,15},
			-- {"coin",3,16},
			-- {"coin",3,17},
			-- {"coin",11,13},
			-- {"coin",11,16},
			-- {"coin",11,17},
			-- {"coin",12,13},
			-- {"coin",12,16},
			-- {"coin",12,17},
			-- {"coin",13,13},
			-- {"coin",13,16},
			-- {"coin",13,17},
			{"spear-thrower",21,16,1},
			{"spear-thrower",21,18,1},
			{"spear-thrower",21,20,1},
			-- {"spear-thrower",10,19,2},
			-- {"clothesline",12,18,3,{["length"]=7}},
			-- {"clothesline",4,14,2,{["length"]=7}},
			-- {"falling_boulder_spawner",17,14,1},

			{"friend",4,10,4,{["friend_type"]=0}},
			{"friend",6,10,4,{["friend_type"]=1}},
			{"friend",8,10,4,{["friend_type"]=2}},
			{"friend",10,10,4,{["friend_type"]=3}},
			{"friend",5,13,4,{["friend_type"]=0}},
			{"friend",7,13,4,{["friend_type"]=1}},
			{"friend",9,13,4,{["friend_type"]=2}},
			{"friend",11,13,4,{["friend_type"]=3}},
			{"car_expander",16,13},
			{"car_expander",16,14},
			{"car_expander",16,15},
			{"car_expander",16,16},
			{"car_expander",17,13},
			{"car_expander",17,14},
			{"car_expander",17,15},
			{"car_expander",17,16},
			{"car_expander",18,13},
			{"car_expander",18,14},
			{"car_expander",18,15},
			{"car_expander",18,16},
		},
		["tile_library"]={
			-- icon={tile_frames,tile_is_flipped,tile_is_solid,{right_wall,left_wall,bottom_wall,top_wall},{entity_type,entity_facing,entity_args}}
			["."]={{7},false,true}, -- grass
			[","]={{9},false,true}, -- grass/dirt
			["="]={{9},false,true}, -- bridge
			["("]={{25},false}, -- bridge supports
			[")"]={{25},true}, -- bridge supports
			["#"]={{23},false,false,{false,false,true,false}}, -- cliff
			["*"]={{39},false}, -- cliff end
			["~"]={{55},false}, -- cliff very end
			["]"]={{40},false,false,{true,false,true,true}}, -- side cliff
			["["]={{40},true,false,{false,true,true,true}}, -- side cliff
			["}"]={{24},false}, -- side cliff end
			["{"]={{24},true}, -- side cliff end
			["o"]={{8},false,true,nil,{"shrub"}}, -- shrub
			["x"]={{10},false,true,nil,{"trap"}}, -- trap
			["j"]={{10},false,true,nil,{"jump_pad"}}, -- jump pad
			["b"]={{10},false,true,nil,{"boulder"}}, -- boulder
			["t"]={{10},false,true,nil,{"tall_grass"}}, -- tall grass

			["d"]={{70},false},
			["e"]={{71},false},
			["f"]={{87},false},
			["g"]={{103},false},
			["h"]={{119},false}
		},
		["tile_map"]={
			"  ,,,,              ",
			",,,,,,,,,,,       ,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,  ,,,,,,,,,,,,,,",
			",,,,,  ,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,",
			",,,,,,,,,,,,,,,,,,,,,"
			-- "      .......        ",
			-- "      ###=###        ",
			-- "..... ***=***        ",
			-- ".....    =           ",
			-- ".....    =    {.o    ",
			-- "ooo.====tttttt[..    ",
			-- "o...(  )tttttt[..    ",
			-- "xx..e   oobbtt[..====",
			-- "xx..f   oo.ttt[..()()",
			-- "xx..f   tttttt[..    ",
			-- "##..====ttt.j.[....} ",
			-- "**##(  )#.....[####] ",
			-- "~~**f   *xxx......dde",
			-- "  ~~g   ~####=######f",
			-- "    h    ****=******f",
			-- "         ~~~~=~~~~~~g",
			-- "   .   =======      h",
			-- "   #   =()()()       ",
			-- " . * . =             ",
			-- " # * # =             ",
			-- " * ~ ~ =             ",
			-- " *     =             ",
			-- " *     =             "
		}
	}
}
__gfx__
08880099008888000009900000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000000000000
88888088088888800088880000000000000000000000000000000000000300000000000000000000000000000000000000000000007470000000000000000000
092908080092290008888880089898000007700000088000000aa0000bb3bbb00bbbbbb0094999900fbfbfb00000000000044000006467700000000000004000
092989980292292000922900085558000007700000088000000aa0000bbbbbb00bb44bb0099944900bfffff00040040000444400000404700000400000000040
298988880988889002922920085558000007700000088000000aa00003b3bbb00b4ff4b0094499900fffffb00004400000044000077440000000400004000000
588889990989989008888880589898000007700000088000000aa0000b3bb3b00b4ff4b0099999400bfffff00004400000400400074220000040404000040000
022222250255552008222280022222000000000000000000000000000bbbb3b00bb44bb0099449900fffffb00040040000000000000400000440400000000000
025025050555555005200250025025000000000000000000000000000bbbbbb00bbbbbb0099999900bfbfbf00000000000000000000000000000000000000000
00888000008888000088880000000000000000000000000000000000000000000000000000000000000330000000000000000000000440000004400000044000
88888880088888800888888000888800000000000000000000000000000000000000000000000000003333000000000000000000000110000001100000011000
08282800088228800882288000955900000000000000000000000000044444400400000004444440003333000000000000000000001411100001410000044100
08282800008888000088880000855800007777000088880000aaaa00044444400440000004440000033333300000000000000000000440010001400000044000
09989900009229000098890000955900007777000088880000aaaa00044424400444000004400000031333300002200000222200000440000001400000044000
0888880000822800008888000088880000000000000000000000000004242420044240000400000001313130002222000222222000f44f0000f14f0000f44f00
0222220000222200008888000022220000000000000000000000000004242420044424000200000001111310000220000022220000f44f0000f14f0000f44f00
0250250000522500005225000052250000000000000000000000000002242220044422200f000000001311000000000000000000000ff0000001f000000ff000
00000000000000000000000000000000000000000000000000000070000000000000000003b3b3b0000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000007700000070700000000000000000b3b3330000000000000000000000000000000000000000000000000
0007a000000790000009900000097000000000000000777707000070022222200442422003b3b3b000008800000820000f000f000f000f0000f1800000f10000
0077a900000a9000009999000009a00000777700077007707070000002222220044424200b333b30088882000088880018888810188888100001820000012000
007aa900000a9000009999000009a000077777707777000007000000022222200444222003b3b3b0028888000888880002888200028882000001880000018000
00aaa900000a9000009999000009a00007777770077077000000007002222220044242200b3b3b300880880002880000088088000880880000f1800000f10000
000a9000000a9000000990000009a000007777000007777000000707022222200444242003535350088000000088000008808800000000000001280000018000
00000000000000000000000000000000000000000000770000000070022222200444222003535350000000000000000000000000000000000001080000018000
000000000000000000000000000000000000000000aaaa0080000008000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000099000000000000a0000a0080000800000000000000000000ee000000000000000000000000000000000000000000000000000
00077000000aa00000a00a000098890000700700a000000a0000000002f2f2f000088000000ee00000009900000940000f000f000f000f0000f1900000f10000
0077770000a00a00000000000988889000077000a000000a000000000f2f2f2000088000000ee000099994000099990019999910199999100001940000014000
0077770000a00a00000000000988889000077000a000000a000000000ffffff0000880000eeeeee0049999000999990004999400049994000001990000019000
0077770000a00a00000000000098890000700700a000000a000000000ffffff00888888000eeee000990990004990000099099000990990000f1900000f10000
00077000000aa00000a00a0000099000000000000a0000a00800008000f0f0f000888800000ee000099000000099000009909900000000000001490000019000
000000000000000000000000000000000000000000aaaa00800000080f0f0f000008800000000000000000000000000000000000000000000001090000019000
00000000000000000000000000000000000000000000000000000000000000000000000009900990000000000000000000000000000700000000000000000000
0010000000010000010116700001000000100000000000000000000000000000000000000999999000ddd000003333007000000700f700000aaaaaa00aaaaaa0
000ccc00000ccc0044ccc467000ccc00000c1c1000000000044444400000000000000000e499994e0ddddd00035eee30f722227f00ff70000977799009799990
00c11c1100ccccc00c11c11000ccccc000c17c7100006700024242400000000000000000eee7e7ee0dd7d7003522e223f788887f008f77800978789009789990
00cc7c7000c11c110cc7c70000c11c1100ceccce004446700cccccc00cc00000000000000ee6e6e00dd6d6d035eeeee3f788887f008f87800977889009789990
00ccccc000cc7c700ccccc0000ccccc100c11cc1000067000cccccc00cccc000000000000eeeeee00dddddd0358222830f8888f00008f8700978799009777890
001c1c1001ccccc101c1c100001c1c1100111c11000000000cccccc00ccccc00000000000288882002888820052eee20008888000000fff00989889009988890
00110110011c1c11001100000011000000000000000000000bbbbbb00ccccc000000000008800880088008800530053000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000bb000000000000000000000000000000000000000000000000000
0000000000444400004444000044440000333300003333000aaaaaa00000000000000000003bb30000dddd0000dddd0000dddd0000dddd000aaaaaa00aaaaaa0
00000000044ccc40044ccc40044eee40033eee30035eee300977789000cccc000000000004bbbb4007ccc700007979000d7eeed000777b000779779007999790
00ee0ee04433c3344411c1144422e2243322e2233522e2230978889000cccc0000000000044bb4400717c710074747400e78eee00b7373b00787878007879780
0000000044ceeec444ccccc444eeeee433eeeee335eeeee30977899000cccc000000000004f33f4007171710074747400e78eee00b7733b00787878007878780
000eee0044e222e444c111c44482228435822283358222830978889000cccc00000000000b4ff4b0017171c0074947400e7778e00b737bb00789878008787890
00e000e0042eee20041ccc10042eee20052eee20052eee200977789000cccc000000000000344300001c11000049940000e88800003b33000889988009898890
0000000004400440044004400440044005500550053005300000000000cccc000000000000300300000000000000000000000000000000000000000000000000
00000000000000000d50000000000000000000000000000000000000000000000000000000000000000bbb000000000000000000088888800088880000000000
00d6dd0000d65d00d5d005d000d6dd000055dd00005555000000000000000000000000008000000800bb33b0000000000aa887a0888888880888888000000000
0d6ddd500d6d55d0d5500d5d0d6d5d50055dddd00d55d5500000000000cccc000000000008800880044bbbb000000000aa888a7a888888880888888000000000
0ddddd500dddd550550005550ddddd5005d5d6d00ddd5d500000000000cccc00007777000800008044433bb000000000a888aa78088888800088880000000000
0dd5d5500dd555d0005d00500dd5d5500555d6d00d6ddd500000000000cfcf00007007000000000044433300000000008888aaa8050000500050050000000000
0d5ddd500d5d5d5000d550000d5dd550055dddd0056d5d500000000000cccc000070070000000000444333300000000088aaaa88444000440440044000000000
0dd5555005d5d5500055500000d555000055dd0000dddd000000000000fcfc000077770008000080044bb330000000000aaaa880444444400444440000000000
0b5555b00b5555b0000000000000000000000000000000000000000000cfcf0000000000888008880003b0000000000000a88800044444000044400000000000
0000000000000000007777000000000000000000000000070000000000000000000300300000300000bbbb0000bbbb0000000000000000000000000000000000
00000000000000000773377000000000000000700c00007000000000000000000030b300030300000bbbbbb00bbbbbb000000000000000000000000000000000
047777400470074007377370000770000000770000c000000000000000ffff00030b30b030b00b0003bbbb30433bb33405000050050000500000000000000000
077337700777777007377370007007000000c700000000000000000000ffff0000b00b000b00b0000344443043bbbb344ff000504ff000500000000000000000
07377370077337700773377000700700007c0000000000000000000000f0f0000005b0000000050004f44f40443bb344444044ff444044ff0000000000000000
077337700737737007777770000770000077000000000c0000000000000f0f000050305000005005344ff4434433334444444440444444400000000000000000
0477774004733740047777400000000007000000070000c00000000000000000050305000030005034f44f4303bbbb3025454520254545200000000000000000
0455554004555540045555400000000000000000700000000000000000f0f0000030500003000000004ff4000300003002222200022222000000000000000000
000bb000000bb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000bbbb000044440000bbbb0000000000
003bb30000bbbb00000000000000bb0000000000000bbb0000000000000bb000000000000000000000000000000000000bbbbbb0044444400bbbbbb000355300
04bbbb40043bb3400000bb00000b3bb0000bbb0000b3b3b0003bb30000bbbb0000000000000000000000000000000000433bb3344444444403bbbb3003555530
0f4bb4f00f4334f00043bbb0004bbbe000b3b3b0003beb0000bbbb000b3bb3b00000000000000000000000000000000043bbbb34444554440344443003444430
04333340b33bb33b0f43b3b00f4333000f3bbb000f33b30003f44f3003f44f3000000000000000000000000000000000443bb3444455554404f44f4004f44f40
0b3bb3b0043bb34004f33bb004fb33000443334004433340044ff440044ff440000000000000000000000000000000000433334004355340344ff443044ff440
003bb300003333000f4b33000f4b330003bbbb3003bbbb3004f44f4004f44f400000000000000000000000000000000003bbbb3005bbbb5034f44f4304f44f40
0030030000300300004b300000433000000bb000000bb000000ff000000ff000000000000000000000000000000000003000000300000000004ff400004ff400
0000cc000c00c9900000000000000000000000000000000000000000000000000000000000000000000000000000000000cccc00c0c99c0c00cccc0000cccc00
000c19900c0c1e00000000000c0000900000000000099000000000000009900000000000000000000000000000000000001cc100c09ee90c00cccc0000cccc00
000cc990ccccc9e0000ccc000cccc9e000cccc00009ee90000cccc00000990000000000000000000000000000000000009cccc90c9e88e9c0cccccc00cccccc0
00cccc90cccccc9000c1c990ccc1c800001cc1000ceeeec000cccc0000cccc00000000000000000000000000000000000c9999c0c198891c0cccccc00cccccc0
00ccffc00cccffc00cccc990cc1cc9800c9999c00c9889c00cccccc000cccc000000000000000000000000000000000001f99f1cc1f99f1ccccccccccccccccc
01ccffc00ccfffc00cc1ff90ccc1cc900cc99cc00cf99fc00cccccc00cccccc000000000000000000000000000000000c1ffff1c0cffffc0c1cccc1cc1cccc1c
01c9ff9001f9ff900ccfff000cccff000cffffc00cffffc00c1cc1c0cc1cc1cc00000000000000000000000000000000ccffffc000ffff00cc1cc1cccc1cc1cc
00949949009499490c1ff00000fff000000ff000000ff000000cc000000cc000000000000000000000000000000000000c0000c000000000c000000cc000000c
00900900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009000090000000000090090000900900
009ff900095ff950090000900000000009000090000000000000000005000050000000000000000000000000000000000f9009f09f009f00d09ff90dd09ff90d
0059f950009959000f9009f09f009f000f9009f09f009f00090000900050050000000000000000000000000000000000099ff99009ff99900999999009999990
4099590004598950099ff99009ff9990099ff99009ff999009900990099ff990000000000000000000000000000000000f59f9500d99599dd99ff99dd99ff99d
44599050440990000f59f9500d99599d0f59f9500d99599d099ff99009f99f90000000000000000000000000000000000d99599d099585900999999009999990
04f9990040f999000d99599d099585900d99599d09958590099999900f9999f000000000000000000000000000000000099595900d99999d009ff900009ff900
0f9999004f999900099595900d99999d099595900d99999d0999999009999990000000000000000000000000000000000d99990d009999000099f9000099f900
04490900044909000d99990d009999000d99990d0099990000999900009999000000000000000000000000000000000009000090090000900900009009000090
05500550000550000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffff0000ffff0000ffff0000ffff00
0e5ff5e0055ee550000000000000000000000000000110000000000000011000000000000000000000000000000000000f7ff7f00ffeeff00ffffff00ffffff0
005555000e5555e00055f50000f55110005ff500005555000055550000555500000000000000000000000000000000000f7f7ff00feeeef00f7ff7f00f7ff7f0
00f55f0000ffff0005555f500f515ee005155150005ee5000555555000155100000000000000000000000000000000000fff7ff004e77e400f7f7ff00f7f7ff0
0ffffff00f5ff5f00ee51510055558800e5555e0055885500e5555e0055555500000000000000000000000000000000004ffff400fe77ef004ff7f4004ff7f40
0f5ff5f00ffffff00ff5555005e555000ff11ff00ef55fe00ffffff00effffe0000000000000000000000000000000000f4444f00ff22ff00ffffff00ffffff0
00ffff0000ffff000fff51100eefff000ffffff00ffffff00ffffff00ffffff00000000000000000000000000000000000ffff0000ffff0000ffff0000ffff00
005005000050050000fff00000fff000000ff000000ff000000ff000000ff0000000000000000000000000000000000000000000000000000000000000000000
000000000000000000bbbb00000000000000000000000000000000000000000000000000000000000222002002022200222200000222200009a9a9a003b3b3b0
00bbbb0000bbbb00033bb33000000000000000000000000000000000000000000000000000000000288820800808882088880000088882000a9a99900b3b3330
0bbbbbb00b9bb9b00bbaabb00455454005354440044454400dcccdd00cd55d500dd555d0054544408220808008080080820000000800080009a9a9a003b3b3b0
3b9bb9b33bbbbbb333beeb330545545004345450054554500ccddcc00dccd5500555d55004445450088200800808028088000000080228000a999a900b333b30
3bbbbbb333baab333b3883b30455455004544450045545500cccccd00dcccd50055d5dd0045444502008008008088800800000000888800209a9a9a003b3b3b0
b3baab3b3b3993b33b3883b30555455005453530055555500ddccdd00cddcdd00d55555005454540822080822808000080220000080802280a9a9a900b3b3b30
b339933b0b3993b00b3993b00555554004545350055555500cddccc00ccddcd0055dd5d004545450088800088008000088880000080088800949494003535350
0bb00bb003b00b300b3003b00455545004445450055555500cccddd00cddccc005555d5004445450000000000000000000000000000000000949494003535350
00000000000000000000000000000000000000000000000000000000000000000000000000000000888800000000008800000000000000000009009000030030
00baab0000b99b0000b88b000000000000100000000100000108867000010000001000000000000089a880000000088a00000000000000000090a9000030b300
bb9bb9bbbbbaabbbb3beeb3b00000000000ccc00000ccc0044ccc467000ccc00000c1c1005444440089a8800000088a90000000000000000090a90a0030b30b0
3bbbbbb33b9bb9b33bbaabb30000000000c11c1100ccccc00c11c11000ccccc000c17c71054544500889a88000008a98000000000000000000a00a0000b00b00
bbbbbbbb3bbbbbb3b33bb33b0000000000cc7c7000c11c110cc7c70000c11c1100cfecce045d544000889a880008898000000000000000000004a0000005b000
b3bbbb3bb3bbbb3b3bbbbbb30000000000ccccc000cc7c700ccccc0000cccc2800c88c880d554540000889a80008a98000000000000000000040904000503050
3b3333b33bb33bb333bbbb330000000000288820082ccc280828880000288888008288880555d4500000889a0008a80000000000000000000409040005030500
03333330033333300333333000000000008808800888888800880000008800000000000005555d40000008890088988800000000000000000090400000305000
00000000000000000bb3b000000000000000000000000000000000000000000000000000000000000089a8000000000000000000000000000000900000003000
003bbb0000bbbb00bbb3bb00000000000990990000990990990996700099099009909400000000000089a8000000000000000000000000000909000003030000
03bbb9b00bbb9bb0bbbbae00000000000949994000499940949994670049994009491c10000000000089a80000000000000000000000000090a00a0030b00b00
33bbbba03bbbba90bbb3aee00000000000911c1100ccccc00911c11000ccccc000917c71000000000089a8000000000000000000000000000a00a0000b00b000
33bbb9ab3bbb9a9b3bb3be800000000000cc7c7000c11c110cc7c70000c11c1100ceccce000000000089a8000000000000000000000000000000040000000500
3b3bbb9033bbbb30b33b33800000000000ccccc000cc7c700ccccc0000ccccc100c11cc100000000008998000000000000000000000000000000400400005005
b333b330b333bb30b333bb9000000000001c1c1001ccccc101c1c100001c1c1100111c1100000000008880000000000000000000000000000090004000300050
0bb30bb00bb303b00bb303b00000000000110110011c1c1100110000001100000000000000000000000000000000000000000000000000000900000003000000
00000000000000000000000000022000000000000000000000000000000000000000000000000000222220000020002220220020000000000000000000000000
000000000000000000000000002222000880880000880880880886700088088008808200000000008888800002820088808820800000000000000000000bbb00
00077000000cc00006656560022222200828882000288820828882670028882008281c1000000000008000000808200800808080000000000000000002b253b0
0077770000cccc00064444600228822000811c1100ccccc00811c11000ccccc000817c7100000000008000002828200800808080000000000000000005352530
0077770000cccc00054444500288882000cc7c7000c11c110cc7c70000c11c1100ceccce00000000008000008088800800808080000000000000000002535230
00077000000cc000054444500888888000ccccc000cc7c700ccccc0000cccc4900c99c990000000000800000800080282080828000000000000000000b2523b0
0000000000000000054444500898998000499940094ccc4909499900004999990094999900000000008000008000808880800880000000000000000002323350
00000000000000000665446008889980009909900999999900990000009900000000000000000000000000000000000000000000000000000000000003533320
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

