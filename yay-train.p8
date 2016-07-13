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
frame_skip=1 --1 means no skips
min_tile_row_lead=2
max_tile_row_lead=8
entity_spawn_row_lead=0
opposite_dirs={2,1,4,3}
-- system vars
actual_frame=0
is_paused=false
is_drawing=true
draw_sprites=true
draw_debug_shapes=false
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
		local init_args=level.entity_list[i][4] or {}
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
		["death_effect"]=nil
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
	load_level(1)
end


-- update
function update_entity(entity)
	-- update timers
	entity.frames_alive+=1
	entity.action_frames+=1
	if entity.action!="default" and entity.action_frames>anim_mult*#entity.animation[entity.action][entity.facing] then
		set_entity_action(entity,"default")
	end
	if entity.frames_to_death>0 then
		entity.frames_to_death-=1
		if entity.frames_to_death<=0 then
			if entity.death_effect then
				spawn_effect_centered_on_entity(entity.death_effect,entity,{})
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

function destroy_entity(entity,wiggle_frames,death_effect)
	entity.has_hurtbox=false
	entity.has_hitbox=false
	if entity.animation.destroyed then
		set_entity_action(entity,"destroyed")
		entity.frames_to_death=anim_mult*#entity.animation[entity.action][entity.facing]
		entity.wiggle_frames=wiggle_frames or 0
		entity.death_effect=death_effect
	else
		entity.is_alive=false
		if death_effect then
			spawn_effect_centered_on_entity(death_effect,entity,{})
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
	end

	-- freeze grames cause us to skip a chunk of frames
	if freeze_frames>0 then
		freeze_frames-=1
		return
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
			spr(frame,left+wiggle-4+entity.width/2,-top-5+entity.depth/2,1,1,flipped,false)
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
		spr(frame,left-4+effect.width/2,-top-5+effect.depth/2)
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
	if draw_debug_shapes then
		rectfill(0,0,127,127,1)
	else
		rectfill(0,0,127,127,0)
	end
	camera(0,-127)

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


-- data
entity_library={
	["train_engine"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="player",
		["hittable_by"]={"debris"},
		["animation"]={
			["default"]={["front"]={2},["back"]={3},["sides"]={1}}
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
		end,
		["on_hit_wall"]=function(entity)
			destroy_entity(entity,0,"explosion")
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity,0,"explosion")
		end
	},
	["train_car"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="player",
		["hittable_by"]={"debris"},
		["animation"]={
			["default"]={["front"]={5},["back"]={5},["sides"]={4}}
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
			["default"]={["front"]={7},["back"]={8},["sides"]={6}}
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
			["default"]={69}
		},
		["on_hit_by"]=function(entity,hitter)
			entity.is_alive=false
			entity.has_hurtbox=false
			entity.has_hitbox=false
			spawn_effect_centered_on_entity("explosion",entity,{})
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
			entity.is_alive=false
			entity.has_hurtbox=false
			entity.has_hitbox=false
			spawn_effect_centered_on_entity("coin_pickup",hitter,{})
		end
	},
	["turret"]={
		["width"]=6,
		["depth"]=6,
		["is_on_grid"]=true,
		["hit_channel"]="enemy",
		["hittable_by"]={"player_projectile"},
		["animation"]={
			["default"]={
				["front"]={22,22,22,23,23,23},
				["back"]={38,38,38,39,39,39},
				["sides"]={54,54,54,55,55,55}
			},
			["shooting"]={
				["front"]={22,23,22,23,24,24,24,22},
				["back"]={38,39,38,39,40,40,40,38},
				["sides"]={54,55,54,55,56,56,56,54}
			},
			["destroyed"]={
				["front"]={24,24},
				["back"]={40,40},
				["sides"]={56,56}
			}
		},
		["init"]=function(entity,args)
			entity.frames_between_shots=60
			entity.frames_to_shot=entity.frames_between_shots
			entity.shoot_frame=20
		end,
		["pre_move_update"]=function(entity)
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
				local bullet=spawn_entity_centered_at_pos("enemy_bullet",entity.x+entity.width/2,entity.z+entity.depth/2,entity.facing,{
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
				["front"]={14,13,14,15},
				["back"]={14,13,14,15},
				["sides"]={30,29,30,31}
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
	["enemy_bullet"]={
		["width"]=4,
		["depth"]=4,
		["hit_channel"]="enemy_projectile",
		["hittable_by"]={},
		["animation"]={
			["default"]={27,10}
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
		["animation"]={87,88,89,90}
	},
	["poof"]={
		["width"]=6,
		["depth"]=6,
		["frames_to_death"]=15,
		["animation"]={103,104,105}
	}
}

levels={
	{
		["player_spawn"]={8,5,2}, --col,row,num_cars
		["entity_list"]={
			-- type,col,row,facing
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
			{"turret",18,16,1},
			{"turret",10,20,4}
		},
		["tile_library"]={
			-- icon={frames,is_flipped,is_solid,{right_wall,left_wall,bottom_wall,top_wall}}
			["."]={{64},false,true}, -- grass
			["="]={{66},false,true}, -- bridge
			["("]={{82},false}, -- bridge supports
			[")"]={{82},true}, -- bridge supports
			["#"]={{80},false,false,{false,false,true,false}}, -- cliff
			["*"]={{96},false}, -- cliff end
			["]"]={{97},false,false,{true,false,true,true}}, -- side cliff
			["["]={{97},true,false,{false,true,true,true}}, -- side cliff
			["}"]={{81},false}, -- side cliff end
			["{"]={{81},true}, -- side cliff end
			["o"]={{65},false,true} -- tree stump
		},
		["tile_map"]={
			"         =           ",
			"         =           ",
			"         =           ",
			"         =    {.o    ",
			"ooo.====......[..    ",
			"o...(  )......[..    ",
			"....    oo....[..====",
			"....    oo....[..()()",
			"##..====......[....} ",
			"**##(  )#.....[####] ",
			"  **    *........... ",
			"         ####=###### ",
			"         ****=****** ",
			"             =       ",
			"             =       ",
			"       =======       ",
			"       =()()()       ",
			"       =             ",
			"       =             ",
			"       =             ",
			"       =             ",
			"       =             "
		}
	}
}
__gfx__
00000000088800990088880000099000000000000000000000888000008888000088880000000000000000000000000000000000000000000000000000000000
00000000888880880888888000888800000000000088880088888880088888800888888000011000000000000000000000000000000000000000000000000000
000000000929080800922900088888800898980000955900082828000882288008822880001ee1000007700000000000000000000007700000088000000aa000
000000000929899802922920009229000855580000855800082828000088880000888800012eee100077770000077000000000000007700000088000000aa000
0000000029898888098888900292292008555800009559000998990000922900009889000122ee100077770000077000000000000007700000088000000aa000
000000005888899909899890088888805898980000888800088888000082280000888800012222100007700000000000000000000007700000088000000aa000
00000000022222250255552008222280022222000022220002222200002222000088880000122100000000000000000000000000000000000000000000000000
00000000025025050555555005200250025025000052250002502500005225000052250000011000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000bbbb0000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000bbbb0000bbbb00033bb33000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000bbbbbb00b9bb9b00bbaabb00455454005354440000cc00000000000000000000000000000000000
0000000000000000000000000000000000000000000000003b9bb9b33bbbbbb333beeb33054554500434545000cccc0000000000007777000088880000aaaa00
0000000000000000000000000000000000000000000000003bbbbbb333baab333b3883b3045545500454445000cccc0000000000007777000088880000aaaa00
000000000000000000000000000000000000000000000000b3baab3b3b3993b33b3883b30555455005453530000cc00000000000000000000000000000000000
000000000000000000000000000000000000000000000000b339933b0b3993b00b3993b005555540045453500000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000bb00bb003b00b300b3003b004555450044454500000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000baab0000b99b0000b88b0000e00000000000000003000000000000000000000000000000000000
0007a0000007900000099000000970000000000000000000bb9bb9bbbbbaabbbb3beeb3b0ee00000044454400bb3bbb00dcccdd00cd55d500dd555d005454440
0077a900000a9000009999000009a00000000000000000003bbbbbb33b9bb9b33bbaabb30ee0ff00054554500bbbbbb00ccddcc00dccd5500555d55004445450
007aa900000a9000009999000009a0000000000000000000bbbbbbbb3bbbbbb3b33bb33b00eeff000455455003b3bbb00cccccd00dcccd50055d5dd004544450
00aaa900000a9000009999000009a0000000000000000000b3bbbb3bb3bbbb3b3bbbbbb30e4efe00055555500b3bb3b00ddccdd00cddcdd00d55555005454540
000a9000000a9000000990000009a00000000000000000003b3333b33bb33bb333bbbb330ee4ee00055555500bbbb3b00cddccc00ccddcd0055dd5d004545450
00000000000000000000000000000000000000000000000003333330033333300333333000eee000055555500bbbbbb00cccddd00cddccc005555d5004445450
00000000000000000000000000000000000000000000000000000000000000000bb3b00000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000003bbb0000bbbb00bbb3bb0000e00000000000000000000000000000000000000000000000000000
00077000000aa00000a00a0000000000000000000000000003bbb9b00bbb9bb0bbbbae000ee00000011111c00dcccdd00d555550055555d00544444005454440
0077770000a00a000000000000000000000000000000000033bbbba03bbbba90bbb3aee00ee0ff0001c111100ccddcc00cdd55500555d5500545445004445450
0077770000a00a000000000000000000000000000000000033bbb9ab3bbb9a9b3bb3be8000eeeff00c111cc00cccccd00dccd550055d5550045d544004544450
0077770000a00a00000000000000000000000000000000003b3bbb9033bbbb30b33b338000e4e400011111100ddccdd00cddc5500d5555500d55454005454540
00077000000aa00000a00a00000000000000000000000000b333b330b333bb30b333bb9000eefe0001cc11100cddccc00ccddc500555d5d00555d45004545450
0000000000000000000000000000000000000000000000000bb30bb00bb303b00bb303b0000ee0000111cc100cccddd00cddccd005555d5005555d4004445450
00000000000000000000000000000000000000000003300000000000000220000000000000000000000000000000000000000000000000000000000000000000
00030000000000000000000000000000000000000033330000000000002222000000000000000000000000000000000000000000000000000000000000000000
0bb3bbb00bbbbbb00949999000000000000000000033330006656560022222200000000000000000000000000000000000000000000000000000000000000000
0bbbbbb00bb44bb00999449000000000000000000333333006444460022882200000000000000000000000000000000000000000000000000000000000000000
03b3bbb00b4ff4b00944999000000000000000000313333005444450028888200000000000000000000000000000000000000000000000000000000000000000
0b3bb3b00b4ff4b00999994000000000000000000131313005444450088888800000000000000000000000000000000000000000000000000000000000000000
0bbbb3b00bb44bb00994499000000000000000000111131005444450089899800000000000000000000000000000000000000000000000000000000000000000
0bbbbbb00bbbbbb00999999000000000000000000013110006654460088899800000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000033000000000000000000000aaaa00800000080000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000033330000099000000000000a0000a0080000800000000000000000000000000000000000000000
044444400400000004444440000000000000000000000000003333000098890000700700a000000a000000000000000000000000000000000000000000000000
044444400440000004440000000000000000000000000000033333300988889000077000a000000a000000000000000000000000000000000000000000000000
044444400444000004400000000000000000000000000000031333300988889000077000a000000a000000000000000000000000000000000000000000000000
024242400442400004000000000000000000000000000000013131300098890000700700a000000a000000000000000000000000000000000000000000000000
0424242004442400020000000000000000000000000000000111131000099000000000000a0000a0080000800000000000000000000000000000000000000000
02222220044422200000000000000000000000000000000000131100000000000000000000aaaa00800000080000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000077000000707000000000000000000000000000000000000000000000000
022222200442422000000000000000000b3333b00000000000000000000000000000777707000070000000000000000000000000000000000000000000000000
02222220044424200000000000000000033333300000000000000000007777000770077070700000000000000000000000000000000000000000000000000000
00202020044422200000000000000000033333300000000000000000077777707777000007000000000000000000000000000000000000000000000000000000
02020200044242200000000000000000013131300000000000000000077777700770770000000070000000000000000000000000000000000000000000000000
00000000044424200000000000000000011313100000000000000000007777000007777000000707000000000000000000000000000000000000000000000000
000000000444222000000000000000000b1111b00000000000000000000000000000770000000070000000000000000000000000000000000000000000000000
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

