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
frame_skip=1 --1 means no skips
wipe_frames=0
actual_frame=0
is_paused=false
is_drawing=true
-- game vars
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
effects={}
tiles={}
directives={}


-- init
function reset()
	-- system vars
	frame_skip=1
	wipe_frames=0
	actual_frame=0
	is_paused=false
	is_drawing=true
	-- game vars
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
	effects={}
	tiles={}
	directives={}
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
	spawn_entity_at_tile("train_caboose",col,row-1-num_cars,3,{})
	local i
	for i=num_cars,1,-1 do
		spawn_entity_at_tile("train_car",col,row-i,3,{})
	end
	player_entity=spawn_entity_at_tile("train_engine",col,row,3,{})

	-- add entities to scene
	add_all(entities,spawned_entities)
	spawned_entities={}
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
		end
	end
	return tile_row
end

function instantiate_entity(type)
	local def=entity_library[type]
	local entity={
		-- entity properties
		["type"]=type,
		["width"]=def.width,
		["depth"]=def.depth,
		["has_grid_movement"]=def.has_grid_movement or false,
		["hit_channel"]=def.hit_channel,
		["hittable_by"]=def.hittable_by,
		["frame_offset"]=def.frame_offset or 0,
		["animation"]={},
		-- methods
		["init"]=def.init or noop,
		["pre_move_update"]=def.pre_move_update or noop,
		["update"]=def.update or noop,
		["on_hit"]=def.on_hit or noop,
		["on_hit_by"]=def.on_hit_by or noop,
		["on_hit_wall"]=def.on_hit_wall or noop,
		["on_fall_off"]=def.on_fall_off or noop,
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
		["is_on_grid"]=def.is_on_grid or false,
		["is_alive"]=true,
		["has_hitbox"]=true,
		["has_hurtbox"]=true,
		["action"]="default",
		["action_frames"]=0,
		["wiggle_frames"]=0,
		["frames_alive"]=0,
		["frames_to_death"]=0,
		["death_effect"]=nil,
		["death_effect_args"]=nil
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
	for action,anim in pairs(def.animation) do
		entity.animation[action]={
			anim["sides"] or anim,
			anim["sides"] or anim,
			anim["back"] or anim,
			anim["front"] or anim
		}
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
		["width"]=def.width,
		["depth"]=def.depth,
		["frame_offset"]=def.frame_offset or 0,
		["animation"]=def.animation,
		-- methods
		["init"]=def.init or noop,
		["update"]=def.update or noop,
		-- stateful fields
		["x"]=0,
		["y"]=0,
		["z"]=0,
		["is_alive"]=true,
		["frames_alive"]=0,
		["frames_to_death"]=def.frames_to_death or 0
	}
	return effect
end

function spawn_effect_at_tile(type,col,row,init_args)
	local effect=instantiate_effect(type)
	effect.x=tile_size*(col-1)+(tile_size-effect.width)/2
	effect.z=tile_size*(row-1)+(tile_size-effect.depth)/2
	effect.init(effect,init_args)
	add(effects,effect)
	return effects
end

function spawn_effect_at_pos(type,x,z,init_args)
	local effect=instantiate_effect(type)
	effect.x=x
	effect.z=z
	effect.init(effect,init_args)
	add(effects,effect)
	return effect
end

function spawn_effect_centered_at_pos(type,x,z,init_args)
	local effect=instantiate_effect(type)
	effect.x=x-effect.width/2
	effect.z=z-effect.depth/2
	effect.init(effect,init_args)
	add(effects,effect)
	return effect
end

function spawn_effect_centered_on_entity(type,entity,init_args)
	local effect=instantiate_effect(type)
	effect.x=entity.x+entity.width/2-effect.width/2
	effect.z=entity.z+entity.y+entity.depth/2-effect.depth/2
	effect.init(effect,init_args)
	add(effects,effect)
	return effect
end

function _init()
	reset()
	load_level(1)
end


-- update
function update_entity(entity)
	-- update timers
	entity.frames_alive+=1
	entity.action_frames+=1
	if entity.action!="default" and entity.action_frames>=anim_mult*#entity.animation[entity.action][entity.facing] then
		set_entity_action(entity,"default")
	end
	if entity.frames_to_death>0 then
		entity.frames_to_death-=1
		if entity.frames_to_death<=0 then
			if entity.death_effect then
				spawn_effect_centered_on_entity(entity.death_effect,entity,entity.death_effect_args)
			end
			entity.is_alive=false
			return
		end
	end
	if entity.wiggle_frames>0 then
		entity.wiggle_frames-=1
	end

	-- the entity may want to adjust its velocity
	entity.pre_move_update(entity)

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
		entity.is_on_grid=true
		entity.y=0
		entity.vy=0
	end

	-- entities that fall too far are dead
	if entity.y<-10 then
		spawn_effect_centered_on_entity("poof",entity,{})
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
	-- update timers
	effect.frames_alive+=1
	if effect.frames_to_death>0 then
		effect.frames_to_death-=1
		if effect.frames_to_death<=0 then
			effect.is_alive=false
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

function set_entity_action(entity,action)
	entity.action=action
	entity.action_frames=0
end

function is_alive(x)
	return x["is_alive"]
end

function check_for_collision(entity1,entity2)
	local are_overlapping=false
	if entity1.is_on_grid and entity2.is_on_grid then
		if entity1.col==entity2.col and entity1.row==entity2.row then
			are_overlapping=true
		end
	elseif entities_are_overlapping(entity1,entity2) then
		are_overlapping=true
	end
	if are_overlapping then
		local entity1_is_hit=(entity2.has_hitbox and entity1.has_hurtbox and list_has_value(entity1.hittable_by,entity2.hit_channel))
		local entity2_is_hit=(entity1.has_hitbox and entity2.has_hurtbox and list_has_value(entity2.hittable_by,entity1.hit_channel))
		if entity1_is_hit then
			entity2.on_hit(entity2,entity1)
		end
		if entity2_is_hit then
			entity1.on_hit(entity1,entity2)
			entity2.on_hit_by(entity2,entity1)
		end
		if entity1_is_hit then
			entity1.on_hit_by(entity1,entity2)
		end
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

function destroy_entity(entity,wiggle_frames,death_effect,death_effect_args)
	entity.has_hurtbox=false
	entity.has_hitbox=false
	if entity.animation.destroyed then
		if entity.action!="destroyed" then
			set_entity_action(entity,"destroyed")
			entity.frames_to_death=anim_mult*#entity.animation[entity.action][entity.facing]
			entity.wiggle_frames=wiggle_frames or 0
			entity.death_effect=death_effect
			entity.death_effect_args=death_effect_args
		end
	else
		entity.is_alive=false
		if death_effect then
			spawn_effect_centered_on_entity(death_effect,entity,death_effect_args)
		end
	end
end

function _update()
	-- simulation will not update while paused
	actual_frame+=1
	if actual_frame%frame_skip!=0 or is_paused then
		return
	end

	-- when the player is kiled, we have some freeze frames!
	if player_entity!=nil and not player_entity.is_alive then
		player_entity=nil
		freeze_frames+=5
		frame_skip=3
		wipe_frames=75
	end

	-- after the screen wipe, we reset the level
	if player_entity==nil and wipe_frames<=0 then
		reset()
		load_level(1)
	end

	-- freeze grames cause us to skip a chunk of frames
	if freeze_frames>0 then
		freeze_frames-=1
		return
	end

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

	-- update entities/effects
	foreach(entities,update_entity)
	foreach(effects,update_effect)

	-- add new entities to the game
	add_all(entities,spawned_entities)
	spawned_entities={}

	-- check for collisions
	for i=1,#entities do
		local j
		for j=i+1,#entities do
			check_for_collision(entities[i],entities[j])
		end
	end

	-- kill entities/effects that go out of bound
	foreach(entities,kill_if_out_of_bounds)
	foreach(effects,kill_if_out_of_bounds)

	-- cull dead entities/effects
	entities=filter_list(entities,is_alive)
	effects=filter_list(effects,is_alive)

	game_frame+=1
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
	-- draw sprite
	do
		local left=entity.x
		local right=left+entity.width-1
		local bottom=entity.z+entity.y
		local top=bottom+entity.depth-1
		if draw_sprites then
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
			rect(left,-top,right,-bottom,10)
			pset(left,-bottom,7)
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
		if not fget(tile.frames[f],0) then
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

	-- sort entities so that they are properly layered
	sort_list(entities,is_rendered_on_top)

	-- draw entities
	foreach(entities,draw_entity)

	-- draw directives (commands for the train)
	foreach(directives,draw_directive)

	-- draw effects
	foreach(effects,draw_effect)

	-- draw screen wipe effects (~20 frames)
	if wipe_frames>0 then
		local f = 20-wipe_frames
		camera()
		local r
		for r=0,128,6 do
			local c
			for c=0,128,6 do
				local size=min(max(0,f-c/10+r/30),4)
				if size>0 then
					circfill(c,r,size,0)
				end
			end
		end
		wipe_frames-=1
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

function dir_to_vec(dir)
	if dir==1 then
		return -1,0
	elseif dir==2 then
		return 1,0
	elseif dir==3 then
		return 0,1
	elseif dir==4 then
		return 0,-1
	else
		return 0,0
	end
end

function entities_are_overlapping(a,b)
	local a_left=a.x
	local a_right=a_left+a.width-1
	local a_bottom=a.z+a.y
	local a_top=a_bottom+a.depth-1
	local b_left=b.x
	local b_right=b_left+b.width-1
	local b_bottom=b.z+b.y
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
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="player",
		["hittable_by"]={"debris"},
		["animation"]={
			["default"]={["front"]={1},["back"]={2},["sides"]={0}}
		},
		["gravity"]=0.15,
		["has_grid_movement"]=true,
		["grid_move_pattern"]={1,1,1,1,1,1},
		["tile_update_frame"]=2,
		["init"]=function(entity,args)
			entity.frames_between_shots=15
			entity.frames_to_shot=entity.frames_between_shots
		end,
		["pre_move_update"]=function(entity)
			if entity.move_frames_left<=0 then
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
				destroy_entity(entity,0,"explosion")
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			if not godmode then
				destroy_entity(entity,0,"explosion")
			end
		end
	},
	["train_car"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="player",
		["hittable_by"]={"debris"},
		["animation"]={
			["default"]={["front"]={19},["back"]={19},["sides"]={3}}
		},
		["gravity"]=0.15,
		["has_grid_movement"]=true,
		["grid_move_pattern"]={1,1,1,1,1,1},
		["tile_update_frame"]=2,
		["init"]=function(entity,args)
			add(directives,{
				["x"]=entity.x,
				["z"]=entity.z,
				["type"]="move",
				["dir"]=entity.facing,
				["is_alive"]=true
			})
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
		end,
		["on_hit_wall"]=function(entity)
			destroy_entity(entity,0,"explosion")
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,0,"explosion")
		end
	},
	["train_caboose"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="player",
		["hittable_by"]={"debris"},
		["animation"]={
			["default"]={["front"]={17},["back"]={18},["sides"]={16}}
		},
		["gravity"]=0.15,
		["has_grid_movement"]=true,
		["grid_move_pattern"]={1,1,1,1,1,1},
		["tile_update_frame"]=2,
		["init"]=function(entity,args)
			add(directives,{
				["x"]=entity.x,
				["z"]=entity.z,
				["type"]="move",
				["dir"]=entity.facing,
				["is_alive"]=true
			})
		end,
		["pre_move_update"]=function(entity)
			local i
			for i=1,#directives do
				if directives[i].x==entity.x and directives[i].z==entity.z then
					if directives[i].type=="move" then
						move_entity_on_grid(entity,directives[i].dir)
					end
					directives[i].is_alive=false
				end
			end
			directives=filter_list(directives,is_alive)
		end,
		["update"]=function(entity)
		end,
		["on_hit_wall"]=function(entity)
			destroy_entity(entity,0,"explosion")
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,0,"explosion")
		end
	},
	["shrub"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="debris",
		["hittable_by"]={"player_projectile","enemy_projectile"},
		["animation"]={
			["default"]={12}
		},
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,0,"explosion")
		end
	},
	["coin"]={
		["width"]=4,
		["depth"]=4,
		["is_on_grid"]=true,
		["hit_channel"]="pickup",
		["hittable_by"]={"player"},
		["animation"]={
			["default"]={32,33,34,35}
		},
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,0,"coin_pickup")
		end
	},
	["spear-thrower"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="enemy",
		["hittable_by"]={"player_projectile"},
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
			destroy_entity(entity,5,"explosion")
		end
	},
	["player_bullet"]={
		["width"]=4,
		["depth"]=4,
		["hit_channel"]="player_projectile",
		["hittable_by"]={},
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
			destroy_entity(entity)
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end
	},
	["spear"]={
		["width"]=4,
		["depth"]=4,
		["hit_channel"]="enemy_projectile",
		["hittable_by"]={},
		["animation"]={
			["default"]={69}
		},
		["init"]=function(entity,args)
			entity.vx=args.vx
			entity.vz=args.vz
		end,
		["on_hit"]=function(entity,hittee)
			destroy_entity(entity)
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end
	},
	["clothesline"]={
		["width"]=6,
		["depth"]=6,
		["hit_channel"]="debris",
		["hittable_by"]={"player_projectile","enemy_projectile"},
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
			destroy_entity(entity,0,"poof")
		end
	},
	["clothes"]={
		["width"]=6,
		["depth"]=6,
		["hit_channel"]="details",
		["hittable_by"]={"player","player_projectile","enemy_projectile"},
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
				destroy_entity(entity,0,"flying_clothes",{["frame_offset"]=entity.frame_offset})
			elseif entity.prev_neighbor!=nil and not entity.prev_neighbor.is_alive then
				destroy_entity(entity,0,"flying_clothes",{["frame_offset"]=entity.frame_offset})
			end
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,0,"flying_clothes",{["frame_offset"]=entity.frame_offset})
		end
	}
}

effect_library={
	["coin_pickup"]={
		["width"]=6,
		["depth"]=6,
		["frames_to_death"]=20,
		["animation"]={32,48,49,50},
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
		["width"]=6,
		["depth"]=6,
		["frames_to_death"]=20,
		["animation"]={51,52,53,54}
	},
	["poof"]={
		["width"]=6,
		["depth"]=6,
		["frames_to_death"]=15,
		["animation"]={36,37,38}
	},
	["flying_clothes"]={
		["width"]=6,
		["depth"]=6,
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
		["player_spawn"]={8,5,2}, --col,row,num_cars
		["entity_list"]={
			-- type,col,row,facing,init_args
			{"coin",3,15,3},
			{"coin",3,16,3},
			{"coin",3,17,3},
			{"coin",11,13,3},
			{"coin",11,16,3},
			{"coin",11,17,3},
			{"coin",12,13,3},
			{"coin",12,16,3},
			{"coin",12,17,3},
			{"coin",13,13,3},
			{"coin",13,16,3},
			{"coin",13,17,3},
			{"shrub",9,15,3},
			{"shrub",9,16,3},
			{"shrub",10,15,3},
			{"shrub",10,16,3},
			{"shrub",17,19,3},
			{"shrub",1,17,3},
			{"shrub",1,18,3},
			{"shrub",2,18,3},
			{"shrub",3,18,3},
			{"spear-thrower",17,16,1},
			{"spear-thrower",10,19,2},
			{"clothesline",12,18,3,{["length"]=4}},
			{"clothesline",4,14,2,{["length"]=4}}
		},
		["tile_library"]={
			-- icon={frames,is_flipped,is_solid,{right_wall,left_wall,bottom_wall,top_wall}}
			["."]={{7},false,true}, -- grass
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
			["o"]={{8},false,true} -- tree stump
		},
		["tile_map"]={
			"      .......        ",
			"      ###=###        ",
			"      ***=***        ",
			"         =           ",
			"         =    {.o    ",
			"ooo.====......[..    ",
			"o...(  )......[..    ",
			"....    oo....[..====",
			"....    oo....[..()()",
			"....    ......[..    ",
			"##..====......[....} ",
			"**##(  )#.....[####] ",
			"~~**    *........... ",
			"  ~~    ~####=###### ",
			"         ****=****** ",
			"         ~~~~=~~~~~~ ",
			"   .   =======       ",
			"   #   =()()()       ",
			" . * . =             ",
			" # * # =             ",
			" * ~ ~ =             ",
			" *     =             ",
			" *     =             "
		}
	}
}
__gfx__
08880099008888000009900000000000000000000000000000000000000000000000000000000000000000000000000000033000000000000000000000000000
88888088088888800088880000000000000000000000000000000000000300000000000000000000000000000000000000333300000000000000000000000000
092908080092290008888880089898000007700000088000000aa0000bb3bbb00bbbbbb009499990000000000000000000333300000000000000000000000000
092989980292292000922900085558000007700000088000000aa0000bbbbbb00bb44bb009994490000000000000000003333330000000000000000000000000
298988880988889002922920085558000007700000088000000aa00003b3bbb00b4ff4b009449990000000000000000003133330000000000000000000000000
588889990989989008888880589898000007700000088000000aa0000b3bb3b00b4ff4b009999940000000000000000001313130000000000000000000000000
022222250255552008222280022222000000000000000000000000000bbbb3b00bb44bb009944990000000000000000001111310000000000000000000000000
025025050555555005200250025025000000000000000000000000000bbbbbb00bbbbbb009999990000000000000000000131100000000000000000000000000
00888000008888000088880000000000000000000000000000000000000000000000000000000000000000000000000000000000000440000004400000044000
88888880088888800888888000888800000000000000000000000000000000000000000000000000000000000000000000000000000110000001100000011000
08282800088228800882288000955900000000000000000000000000044444400400000004444440000000000000000000000000001411100001410000044100
08282800008888000088880000855800007777000088880000aaaa00044444400440000004440000000000000000000000000000000440010001400000044000
09989900009229000098890000955900007777000088880000aaaa00044424400444000004400000000000000000000000000000000440000001400000044000
0888880000822800008888000088880000000000000000000000000004242420044240000400000000000000000000000000000000f44f0000f14f0000f44f00
0222220000222200008888000022220000000000000000000000000004242420044424000200000000000000000000000000000000f44f0000f14f0000f44f00
0250250000522500005225000052250000000000000000000000000002242220044422200f000000000000000000000000000000000ff0000001f000000ff000
00000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000077000000707000000000000000000000000000000000000000000000000000000000000000000000000
0007a00000079000000990000009700000000000000077770700007002222220044242200000000000008800000820000f000f000f000f0000f1800000f10000
0077a900000a9000009999000009a000007777000770077070700000022222200444242000000000088882000088880018888810188888100001820000012000
007aa900000a9000009999000009a000077777707777000007000000022222200444222000000000028888000888880002888200028882000001880000018000
00aaa900000a9000009999000009a0000777777007707700000000700222222004424220000000000880880002880000088088000880880000f1800000f10000
000a9000000a9000000990000009a000007777000007777000000707022222200444242000000000088000000088000008808800000000000001280000018000
00000000000000000000000000000000000000000000770000000070022222200444222000000000000000000000000000000000000000000001080000018000
000000000000000000000000000000000000000000aaaa0080000008000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000099000000000000a0000a008000080000000000000000000000000000000000000000000000000000000000000000000000000
00077000000aa00000a00a000098890000700700a000000a0000000002f2f2f0000000000000000000009900000940000f000f000f000f0000f1900000f10000
0077770000a00a00000000000988889000077000a000000a000000000f2f2f200000000000000000099994000099990019999910199999100001940000014000
0077770000a00a00000000000988889000077000a000000a000000000ffffff00000000000000000049999000999990004999400049994000001990000019000
0077770000a00a00000000000098890000700700a000000a000000000ffffff000000000000000000990990004990000099099000990990000f1900000f10000
00077000000aa00000a00a0000099000000000000a0000a00800008000f0f0f00000000000000000099000000099000009909900000000000001490000019000
000000000000000000000000000000000000000000aaaa00800000080f0f0f000000000000000000000000000000000000000000000000000001090000019000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00100000000100000101167000010000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000ccc00000ccc0044ccc467000ccc00000c1c100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00c11c1100ccccc00c11c11000ccccc000c17c710000670000000000000000000000000000000000000000000000000000000000000000000000000000000000
00cc7c7000c11c110cc7c70000c11c1100ceccce0044467000000000000000000000000000000000000000000000000000000000000000000000000000000000
00ccccc000cc7c700ccccc0000ccccc100c11cc10000670000000000000000000000000000000000000000000000000000000000000000000000000000000000
001c1c1001ccccc101c1c100001c1c1100111c110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00110110011c1c110011000000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000bbbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00bbbb0000bbbb00033bb33000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0bbbbbb00b9bb9b00bbaabb00455454005354440044454400dcccdd00cd55d500dd555d005454440054444400000000000000000000000000000000000000000
3b9bb9b33bbbbbb333beeb330545545004345450054554500ccddcc00dccd5500555d55004445450054544500000000000000000000000000000000000000000
3bbbbbb333baab333b3883b30455455004544450045545500cccccd00dcccd50055d5dd004544450045d54400000000000000000000000000000000000000000
b3baab3b3b3993b33b3883b30555455005453530055555500ddccdd00cddcdd00d555550054545400d5545400000000000000000000000000000000000000000
b339933b0b3993b00b3993b00555554004545350055555500cddccc00ccddcd0055dd5d0045454500555d4500000000000000000000000000000000000000000
0bb00bb003b00b300b3003b00455545004445450055555500cccddd00cddccc005555d500444545005555d400000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00baab0000b99b0000b88b0000000000001000000001000001088670000100000010000000000000000000000000000000000000000000000000000000000000
bb9bb9bbbbbaabbbb3beeb3b00000000000ccc00000ccc0044ccc467000ccc00000c1c1000000000000000000000000000000000000000000000000000000000
3bbbbbb33b9bb9b33bbaabb30000000000c11c1100ccccc00c11c11000ccccc000c17c7100000000000000000000000000000000000000000000000000000000
bbbbbbbb3bbbbbb3b33bb33b0000000000cc7c7000c11c110cc7c70000c11c1100cfecce00000000000000000000000000000000000000000000000000000000
b3bbbb3bb3bbbb3b3bbbbbb30000000000ccccc000cc7c700ccccc0000cccc2800c88c8800000000000000000000000000000000000000000000000000000000
3b3333b33bb33bb333bbbb330000000000288820082ccc2808288800002888880082888800000000000000000000000000000000000000000000000000000000
03333330033333300333333000000000008808800888888800880000008800000000000000000000000000000000000000000000000000000000000000000000
00000000000000000bb3b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
003bbb0000bbbb00bbb3bb0000000000099099000099099099099670009909900990940000000000000000000000000000000000000000000000000000000000
03bbb9b00bbb9bb0bbbbae00000000000949994000499940949994670049994009491c1000000000000000000000000000000000000000000000000000000000
33bbbba03bbbba90bbb3aee00000000000911c1100ccccc00911c11000ccccc000917c7100000000000000000000000000000000000000000000000000000000
33bbb9ab3bbb9a9b3bb3be800000000000cc7c7000c11c110cc7c70000c11c1100ceccce00000000000000000000000000000000000000000000000000000000
3b3bbb9033bbbb30b33b33800000000000ccccc000cc7c700ccccc0000ccccc100c11cc100000000000000000000000000000000000000000000000000000000
b333b330b333bb30b333bb9000000000001c1c1001ccccc101c1c100001c1c1100111c1100000000000000000000000000000000000000000000000000000000
0bb30bb00bb303b00bb303b00000000000110110011c1c1100110000001100000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000222200088088000088088088088670008808800880820000000000000000000000000000000000000000000000000000000000
00077000000cc00006656560022222200828882000288820828882670028882008281c1000000000000000000000000000000000000000000000000000000000
0077770000cccc00064444600228822000811c1100ccccc00811c11000ccccc000817c7100000000000000000000000000000000000000000000000000000000
0077770000cccc00054444500288882000cc7c7000c11c110cc7c70000c11c1100ceccce00000000000000000000000000000000000000000000000000000000
00077000000cc000054444500888888000ccccc000cc7c700ccccc0000cccc4900c99c9900000000000000000000000000000000000000000000000000000000
0000000000000000054444500898998000499940094ccc4909499900004999990094999900000000000000000000000000000000000000000000000000000000
00000000000000000665446008889980009909900999999900990000009900000000000000000000000000000000000000000000000000000000000000000000
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

