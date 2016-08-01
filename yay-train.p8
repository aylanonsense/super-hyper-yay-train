pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[
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
		col=flr((x+width/2)/6+1)
		x=6*(col-1)
	row=1 goes from z=0 to z=5
		row=flr(z/6)+1
		z=6*(row-1)
]]

-- vars
-- constants
anim_mult=6
camera_pan_rate=12
opposite_dirs={2,1,4,3}
hit_channels={"player","player_projectile","enemy","enemy_projectile","obstacle","pickup"}
-- system vars
scene="title_screen"
actual_frame=-1
-- game vars
bg_color=0
score=0
coin_count=0
life_count=4
game_frame=-1
transition_effect=nil
freeze_frames=0
slow_mo_frames=0
hit_resolution_frames=0
camera_pan_z=0
level=nil
world_num=1
level_num=1
min_level_row=nil
max_level_row=nil
player_entity=nil
entities={}
entities_by_hit_channel={}
spawned_entities={}
tiles={}

-- init methods
function reset_game_state()
	game_frame=-1
	freeze_frames=0
	slow_mo_frames=0
	hit_resolution_frames=0
	camera_pan_z=0
	min_level_row=nil
	max_level_row=nil
	player_entity=nil
	entities={}
	entities_by_hit_channel={}
	local i
	for i=1,#hit_channels do
		entities_by_hit_channel[hit_channels[i]]={}
	end
	spawned_entities={}
	tiles={}
end

function reload_level()
	level=levels[world_num][level_num]
	bg_color=level.bg_color
	check_for_row_load()
	local col=level.player_spawn[1]
	local row=level.player_spawn[2]
	local num_cars=level.player_spawn[3]
	local car=spawn_entity_at_tile("train_caboose",col,row-num_cars-1,3)
	local i
	for i=num_cars,1,-1 do
		car=spawn_entity_at_tile("train_car",col,row-i,3,{["next_car"]=car})
	end
	player_entity=spawn_entity_at_tile("train_engine",col,row,3,{["next_car"]=car})
end

function check_for_row_load()
	-- figure out which rows the user can see
	local min_viewable_row=1+flr((camera_pan_z-2)/6)
	-- figure out if we need to load more rows
	if max_level_row==nil or max_level_row<min_viewable_row+22 then
		min_level_row=max(1,min_viewable_row)
		max_level_row=min(min_viewable_row+22,#level.map)
		load_map_rows()
	end
end

function load_map_rows()
	-- load the map rows, reusing any we already have
	local temp={}
	if max_level_row>=min_level_row then
		for r=min_level_row,max_level_row do
			if tiles[r] then
				temp[r]=tiles[r]
			else
				temp[r]=load_map_row(r)
			end
		end
	end
	tiles=temp
end

function load_map_row(r)
	local tile_row={}
	local r2=#level.map-r+1
	-- for each column in the row...
	for c=1,#level.map[r2] do
		-- get the character for that column of that row
		local s=sub(level.map[r2],c,c)
		tile_row[c]=false
		-- if it is not blank...
		if s!=" " then
			-- create the tile
			local legend_entry=level.map_legend[s]
			if legend_entry[1] then
				local tile_def=tile_types[legend_entry[1]]
				local frame=flr(tile_def[1])
				local tile={
					["col"]=c,
					["row"]=r,
					["frame"]=frame,
					["is_flipped"]=tile_def[1]%1>0,
					["has_surface"]=fget(frame,0),
					["has_wall"]={}
				}
				local i
				for i=1,4 do
					tile.has_wall[i]=fget(frame,i)
				end
				if tile.is_flipped then
					tile.has_wall[1],tile.has_wall[2]=tile.has_wall[2],tile.has_wall[1]
				end
				tile_row[c]=tile
			end
			-- this may involve spawning an entity as well
			if legend_entry[2] then
				spawn_entity_at_tile(legend_entry[2],c,r,legend_entry[3],legend_entry[4])
			end
		end
	end
	return tile_row
end

function instantiate_entity(type)
	local def=entity_types[type]
	local entity={
		-- entity properties
		["type"]=type,
		["animation"]={},
		["hit_channel"]=def.hit_channel,
		["render_priority"]=def.render_priority or 0,
		["gravity"]=def.gravity or 0,
		["projectile_armor"]=def.projectile_armor or 0, -- -1=pierce through, 0=hit and stop, 1=deflect
		-- methods
		["init"]=def.init or noop,
		["pre_update"]=def.pre_update or noop,
		["update"]=def.update or noop,
		["on_hit"]=def.on_hit or noop,
		["on_hit_by"]=def.on_hit_by or noop,
		["on_destroyed"]=def.on_destroyed or noop,
		-- stateful fields
		["x"]=0,
		["y"]=0,
		["z"]=0,
		["vx"]=0,
		["vy"]=0,
		["vz"]=0,
		["facing"]=4,
		["is_alive"]=true,
		["is_mobile"]=true,
		["is_frozen"]=false,
		["wiggle_frames"]=0,
		["frames_to_death"]=def.frames_to_death or 0,
		["death_cause"]=nil,
		["has_hitbox"]=true,
		["has_hurtbox"]=true,
		["curr_anim"]="default",
		["curr_anim_frames"]=0,
		["curr_anim_loops"]=false
	}
	-- unpack animations
	local anim_name,anim
	local anims=def.animation
	if not anims.default then
		anims={["default"]=anims}
	end
	for anim_name,anim in pairs(anims) do
		entity.animation[anim_name]={
			anim.sides or anim,
			anim.sides or anim,
			anim.back or anim,
			anim.front or anim
		}
	end
	-- return the entity
	return entity
end

function spawn_entity_at_entity(type,entity,args)
	local new_entity=instantiate_entity(type,args or {})
	new_entity.x=entity.x
	new_entity.y=entity.y
	new_entity.z=entity.z
	new_entity.col=entity.col
	new_entity.row=entity.row
	new_entity.facing=entity.facing
	new_entity.init(new_entity,args)
	add(spawned_entities,new_entity)
	return new_entity
end

function spawn_entity_at_tile(type,col,row,facing,args)
	local entity=instantiate_entity(type,args or {})
	entity.x=6*col-6
	entity.z=6*row-7
	entity.col=col
	entity.row=row
	entity.facing=facing or 4
	entity.init(entity,args)
	add(spawned_entities,entity)
	return entity
end

function init_scene(next_scene)
	scene=next_scene
	actual_frame=-1
	if scene=="title_screen" then
		life_count=4
	elseif scene=="game" then
		world_num=1
		level_num=1
		actual_frame=-1
		life_count-=1
		reset_game_state()
		reload_level()
		freeze_frames=110
	elseif scene=="game_over" then
		transition_to_scene("title_screen",150)
	end
end

function _init()
	init_scene(scene)
end

-- update methods
function get_tile_under_entity(entity)
	if tiles[entity.row] and tiles[entity.row][entity.col] then
		return tiles[entity.row][entity.col]
	end
	return nil
end

function set_entity_anim(entity,anim_name,loops)
	entity.curr_anim=anim_name
	entity.curr_anim_frames=0
	entity.curr_anim_loops=loops or false
end

function pre_update_entity(entity)
	-- call the entity's pre-update method
	entity.pre_update(entity)
end

function update_entity(entity)
	if entity.is_frozen then
		return
	end

	-- update timers
	entity.wiggle_frames-=1
	entity.curr_anim_frames+=1

	-- check for action change
	if entity.curr_anim!="default" and not entity.curr_anim_loops and entity.curr_anim_frames>=6*#entity.animation[entity.curr_anim][entity.facing] then
		set_entity_anim(entity,"default")
	end

	-- apply gravity if the entity isn't supported by anything
	entity.vy-=entity.gravity
	local tile=get_tile_under_entity(entity)
	if tile and tile.has_surface and entity.y>=0 and entity.y+entity.vy<=0 then
		entity.y=0
		entity.vy=0
	end

	-- move the entity
	if entity.is_mobile then
		entity.x+=entity.vx
		entity.y+=entity.vy
		entity.z+=entity.vz
	end

	-- update the entity's col/row
	local update_frame=4
	if entity.hit_channel=="player" or entity.hit_channel=="player_projectile" then
		update_frame=5
	end
	if game_frame%6==update_frame or entity.vx>2 or entity.vx<-2 or entity.vz>2 or entity.vz<-2 then
		entity.col=1+flr(entity.x/6+0.5)
		entity.row=1+flr(entity.z/6+0.5)
	end
	tile=get_tile_under_entity(entity)
	if tile and tile.has_wall[entity.facing] then
		destroy_entity(entity,"wall")
	end

	-- call the entity's update method
	entity.update(entity)

	if entity.y<=-10 then
		entity.y=-9.9
		destroy_entity(entity,"fall")
	end

	-- kill entities that are slated to be killed
	if entity.frames_to_death>0 then
		entity.frames_to_death-=1
		if entity.frames_to_death==0 then
			entity.is_alive=false
			entity.on_destroyed(entity)
		end
	end
end

function destroy_entity(entity,cause)
	entity.death_cause=cause
	entity.has_hitbox=false
	entity.has_hurtbox=false
	if entity.animation.destroyed then
		set_entity_anim(entity,"destroyed")
		entity.frames_to_death=anim_mult*#entity.animation.destroyed[entity.facing]
	else
		entity.is_alive=false
		entity.on_destroyed(entity)
	end
end

function check_for_collisions(hitter_channel,hittee_channel)
	local i
	-- for each entity in the first list...
	for i=1,#entities_by_hit_channel[hitter_channel] do
		local j
		-- check against each entity in the second list...
		for j=1,#entities_by_hit_channel[hittee_channel] do
			if hitter_channel!=hittee_channel or i!=j then
				check_for_collision(entities_by_hit_channel[hitter_channel][i],entities_by_hit_channel[hittee_channel][j])
			end
		end
	end
end

function check_for_collision(hitter,hittee)
	if hitter.has_hitbox and hittee.has_hurtbox and hitter.col==hittee.col and hitter.row==hittee.row then
		-- todo need to update col and row!!
		if hitter.on_hit(hitter,hittee)!=false then
			hittee.on_hit_by(hittee,hitter)
		end
	end
end

function add_entity_to_game(entity)
	add(entities,entity)
	if entity.hit_channel then
		add(entities_by_hit_channel[entity.hit_channel],entity)
	end
end

function transition_to_scene(scene_name,delay)
	transition_effect={
		["color"]=0,
		["frames_left"]=20+(delay or 0),
		["is_reversed"]=false,
		["next_scene"]=scene_name
	}
end

function update_transition()
	transition_effect.frames_left-=1
	if transition_effect.frames_left<=0 then
		if not transition_effect.is_reversed then
			bg_color=transition_effect.color
			local next_scene=transition_effect.next_scene
			transition_effect={
				["color"]=0,
				["frames_left"]=25,
				["is_reversed"]=true
			}
			init_scene(next_scene)
		else
			transition_effect=nil
		end
	end
end

function update_game()
	-- the game may freeze or go into slow mo
	if freeze_frames>0 then
		freeze_frames-=1
		return
	end
	if slow_mo_frames>0 then
		slow_mo_frames-=1
		if actual_frame%3>0 then
			return
		end
	end

	game_frame+=1

	if hit_resolution_frames>0 then
		hit_resolution_frames-=1
		if hit_resolution_frames<=0 then
			local car=player_entity
			local last_living_car=car
			while car.next_car do
				if car.is_alive then
					last_living_car=car
				end
				car=car.next_car
			end
			last_living_car.next_car=car
			car.prev_car=last_living_car
			foreach(entities,function(entity)
				entity.is_frozen=false
			end)
		end
	-- pan the camera upwards and load rows
	elseif game_frame%camera_pan_rate==0 then
		camera_pan_z+=1
		check_for_row_load()
	end

	-- update entities
	foreach(entities,pre_update_entity)
	foreach(entities,update_entity)

	-- check for collisions (hitter_channel,hittee_channel)
	check_for_collisions("player_projectile","enemy_projectile")
	check_for_collisions("player_projectile","obstacle")
	check_for_collisions("player_projectile","enemy")
	check_for_collisions("enemy_projectile","obstacle")
	check_for_collisions("enemy_projectile","player")
	check_for_collisions("obstacle","player")
	check_for_collisions("enemy","player")
	check_for_collisions("obstacle","enemy")
	check_for_collisions("player","pickup")
	check_for_collisions("player","player")
end

function _update()
	-- tick tock
	actual_frame+=1
	-- if actual_frame%4>0 then
	-- 	return
	-- end

	if transition_effect then
		update_transition()
	end

	if scene=="title_screen" then
		if not transition_effect and btn(4) then
			transition_to_scene("game")
		end
	elseif scene=="game" then
		-- update the game state
		update_game()

		-- add spawned entities to the list of entities
		foreach(spawned_entities,add_entity_to_game)
		spawned_entities={}

		-- remove dead entities
		entities=filter_list(entities,is_alive_and_onscreen)
		local i
		for i=1,#hit_channels do
			entities_by_hit_channel[hit_channels[i]]=filter_list(entities_by_hit_channel[hit_channels[i]],is_alive_and_onscreen)
		end

		-- sort entities so that the draw method can render properly
		sort_list(entities,is_rendered_on_top)
	end
end

-- draw methods
function draw_entity(entity)
	-- draw debug tile outline under entity
	-- local left=6*entity.col-6
	-- local right=left+6-1
	-- local bottom=6*entity.row-5
	-- local top=bottom+6-1
	-- rect(left,-top,right,-bottom,12)
	-- pset(left,-bottom,7)

	local f=entity.curr_anim_frames
	local sprite_frame,is_flipped=find_curr_frame(entity.animation[entity.curr_anim][entity.facing],f)
	if entity.facing==1 then
		is_flipped=not is_flipped
	end
	local wiggle_x=0
	if entity.wiggle_frames>0 then
		wiggle_x=game_frame%2*2-1
	end
	spr(sprite_frame,entity.x-1+wiggle_x,-entity.z-entity.y-9,1,1,is_flipped)
end

function draw_tile(tile)
	spr(tile.frame,6*tile.col-7,-6*tile.row-2,1,1,tile.is_flipped)
end

function recursively_update_train_dir(car,dir)
	if car.next_car then
		recursively_update_train_dir(car.next_car,car.facing)
	end
	if not car.is_frozen then
		car.facing=dir
		car.vx,car.vz=dir_to_vec(dir)
	end
end

function draw_transition(color,frames_left,is_reversed)
	local y
	for y=0,128,6 do
		local x
		for x=0,128,6 do
			local size=min(max(0,5-frames_left+y/10-x/40),4)
			if is_reversed then
				size=4-size
			end
			if size>0 then
				circfill(x,y,size,color)
			end
		end
	end
end

function _draw()
	-- reset the canvas
	rectfill(0,0,127,127,bg_color)

	if scene=="title_screen" then
		-- draw title scene 
		local sprite_args={
			2,50,26,
			3,58,26,
			4,66,26,
			35,70,26,
			51,43,35,
			50,47,43,
			34,56,35,
			50,56,43,
			50,64,43,
			51,69,35,
			50,73,43,
			18,49,52,
			35,54,52,
			19,63,52,
			20,71,52
		}
		local i
		for i=1,#sprite_args,3 do
			spr(sprite_args[i],sprite_args[i+1],sprite_args[i+2])
		end
		spr(51,51,35,1,1,true)
		spr(34,64,35,1,1,true)
		spr(51,77,35,1,1,true)
		if actual_frame%24>6 then
			print("press z to start",32,97,7)
		end
	elseif scene=="game_over" then
		if actual_frame>30 then
			spr(21,60,66)
			spr(37,60,74)
		end
		if actual_frame>100 then
			print("game over",46,45,7)
		end
	elseif scene=="game" then
		-- reposition camera
		camera(-1,-128-camera_pan_z)

		-- draw the backgroubnd
		level.draw_bg()

		-- draw tiles
		if max_level_row>=min_level_row then
			local r
			for r=max_level_row,min_level_row,-1 do
				local c
				for c=1,#tiles[r] do
					if tiles[r][c] then
						draw_tile(tiles[r][c])
					end
				end
			end
		end

		-- draw entities
		foreach(entities,draw_entity)

		-- draw ui
		camera()
		rectfill(0,121,127,127,0)
		print(score,2,122,7)
		spr(36,37,120)
		spr(53,44,120)
		print(life_count,49,122,7)
		spr(52,75,120)
		spr(53,82,120)
		print(coin_count,87,122,7)
		print(world_num.."-"..level_num,115,122,7)

		-- draw level start ui
		if actual_frame<120 then
			rectfill(46,40,80,75,0)
			if actual_frame>37 then
				print("world "..world_num,50,43,7)
			end
			if actual_frame>47 then
				print("level "..level_num,50,49,7)
			end
			if actual_frame>57 then
				spr(36,56,55)
				spr(53,63,55)
				print(life_count,68,57,7)
			end
			if actual_frame>87 then
				-- go!
				spr(5,56,65)
				spr(6,64,65)
				if actual_frame>96 then
					spr(31,68,62)
				elseif actual_frame>93 then
					spr(30,68,62)
				elseif actual_frame>90 then
					spr(29,68,62)
				end
			end
		end
	end

	-- reset camera
	camera()

	-- draw transition effect
	if transition_effect then
		draw_transition(transition_effect.color,transition_effect.frames_left,transition_effect.is_reversed)
	end
end

-- helper methods
function noop() end

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
	end
	return 0,0
end

function find_curr_frame(frames,f)
	local x=frames[1+flr(f/anim_mult)%#frames]
	return flr(x),x%1>0 -- returns sprite_frame,is_flipped
end

function is_alive_and_onscreen(entity)
	if entity.x<-6 or entity.x>126 or entity.z<camera_pan_z-8 or entity.z>camera_pan_z+136 then
		entity.is_alive=false
	end
	return entity.is_alive
end

function filter_list(list,func)
	local l={}
	local i
	for i=1,#list do
		if func(list[i]) then
			add(l,list[i])
		end
	end
	return l
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

function is_rendered_on_top(a,b)
	if a.z<b.z then
		return true
	elseif a.z>b.z then
		return false
	elseif a.render_priority>b.render_priority then
		return true
	elseif a.render_priority<b.render_priority then
		return false
	end
	return a.x<b.x
end

-- data
entity_types={
	["train_engine"]={
		["hit_channel"]="player",
		["animation"]={["front"]={16},["back"]={32},["sides"]={0}},
		["gravity"]=0.25,
		["init"]=function(entity,args)
			entity.next_car=args.next_car
			entity.next_car.prev_car=entity
			entity.pressed_dir=0
			entity.next_pressed_dir=0
			entity.prev_btns={}
			entity.frames_to_shoot=0
		end,
		["pre_update"]=function(entity)
			-- handle inputs
			local held_dir=0
			local i
			for i=1,4 do
				local button_is_down=btn(i-1)
				if button_is_down then
					local is_proper_turn=i!=entity.facing and i!=opposite_dirs[entity.facing]
					if is_proper_turn then
						held_dir=i
					end
					if not entity.prev_btns[i] then
						if entity.pressed_dir==0 then
							if is_proper_turn then
								entity.pressed_dir=i
							end
						elseif i!=entity.pressed_dir and i!=opposite_dirs[entity.pressed_dir] then
							entity.next_pressed_dir=i
						end
					end
				end
				entity.prev_btns[i]=button_is_down
			end

			-- change directions
			if game_frame%6==0 then
				recursively_update_train_dir(entity.next_car,entity.facing)
				if not entity.is_frozen then
					if entity.pressed_dir!=0 then
						entity.facing=entity.pressed_dir
						entity.pressed_dir=entity.next_pressed_dir
						entity.next_pressed_dir=0
					elseif held_dir!=0 then
						entity.facing=held_dir
					end
					entity.vx,entity.vz=dir_to_vec(entity.facing)
				end
			end
		end,
		["update"]=function(entity)
			entity.frames_to_shoot-=1
			-- shoot lasers
			if btn(4) and entity.frames_to_shoot<=0 then
				spawn_entity_at_entity("train_laser",entity)
				entity.frames_to_shoot=15
			end
		end,
		["on_hit_by"]=function(entity)
			destroy_entity(entity)
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("explosion",entity)
			freeze_frames=15
			if life_count==0 then
				transition_to_scene("game_over",40)
			else
				transition_to_scene("game",40)
			end
			local car=entity.next_car
			local death_frames=2
			while car do
				car.is_mobile=false
				car.has_hurtbox=false
				car.has_hitbox=false
				car.frames_to_death=death_frames
				death_frames+=2
				car=car.next_car
			end
		end,
	},
	["train_car"]={
		["hit_channel"]="player",
		["animation"]={["front"]={49},["back"]={49},["sides"]={48}},
		["gravity"]=0.25,
		["init"]=function(entity,args)
			entity.next_car=args.next_car
			entity.next_car.prev_car=entity
		end,
		["on_hit_by"]=function(entity)
			destroy_entity(entity)
			freeze_frames=15
			-- freeze all entities
			foreach(entities,function(entity)
				entity.is_frozen=true
			end)
			-- destroy all cars after this car
			local car=entity.next_car
			local death_frames=2
			hit_resolution_frames=6
			while car.next_car do
				car.is_frozen=false
				car.is_mobile=false
				car.has_hurtbox=false
				car.has_hitbox=false
				car.frames_to_death=death_frames
				death_frames+=2
				car=car.next_car
				hit_resolution_frames+=6
			end
			hit_resolution_frames+=1
			-- now deal with the engine
			car.is_frozen=false
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("explosion",entity)
		end
	},
	["train_caboose"]={
		["hit_channel"]="player",
		["animation"]={["front"]={17},["back"]={33},["sides"]={1}},
		["gravity"]=0.25,
		["projectile_armor"]=1,
		["on_hit_by"]=function(entity)
			-- destroy_entity(entity)
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("explosion",entity)
		end
	},
	["train_laser"]={
		["hit_channel"]="player_projectile",
		["animation"]={["front"]={23,24,23,25},["back"]={23,24,23,25},["sides"]={7,8,7,9}},
		["init"]=function(entity)
			entity.vx,entity.vz=dir_to_vec(entity.facing,4)
		end,
		["on_hit"]=function(entity,hittee)
			if hittee.projectile_armor>=0 then
				destroy_entity(entity)
				if hittee.projectile_armor>0 then
					spawn_entity_at_entity("deflect",hittee)
					return false
				end
			end
		end
	},
	["tree"]={
		["hit_channel"]="obstacle",
		["animation"]={70},
		["on_hit_by"]=function(entity)
			destroy_entity(entity)
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("explosion",entity)
		end
	},
	["spear_thrower"]={
		["hit_channel"]="enemy",
		["animation"]={
			["default"]={74,74,75,75},
			["shooting"]={76,76,77,77,77},
			["destroyed"]={78,78}
		},
		["update"]=function(entity)
			if entity.curr_anim=="shooting" and entity.curr_anim_frames==12 then
				spawn_entity_at_entity("spear",entity)
			elseif game_frame%45==0 then
				set_entity_anim(entity,"shooting")
			end
		end,
		["on_hit_by"]=function(entity)
			entity.wiggle_frames=4
			destroy_entity(entity)
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("explosion",entity)
		end
	},
	["spear"]={
		["hit_channel"]="enemy_projectile",
		["animation"]={79},
		["init"]=function(entity)
			entity.vx=1
			if entity.facing==1 then
				entity.vx=-1
			end
		end,
		["on_hit"]=function(entity,hittee)
			if hittee.projectile_armor>=0 then
				destroy_entity(entity)
				if hittee.projectile_armor>0 then
					spawn_entity_at_entity("deflect",hittee)
					return false
				end
			end
		end,
		["on_hit_by"]=function(entity)
			spawn_entity_at_entity("poof",entity)
			destroy_entity(entity)
		end
	},
	["trap"]={
		["hit_channel"]="obstacle",
		["projectile_armor"]=-1,
		["animation"]={["default"]={119},["prepped"]={120},["triggered"]={121}},
		["render_priority"]=-1,
		["projectile_armor"]=1,
		["init"]=function(entity,args)
			entity.frames_to_trigger=0
			entity.has_hurtbox=false
		end,
		["update"]=function(entity)
			entity.frames_to_trigger-=1
			if entity.frames_to_trigger==0 then
				entity.has_hurtbox=true
				entity.render_priority=0
				set_entity_anim(entity,"triggered",true)
				spawn_entity_at_entity("dirt_blast",entity)
			end
		end,
		["on_hit"]=function(entity,hittee)
			if entity.curr_anim!="triggered" then
				entity.frames_to_trigger=5
				set_entity_anim(entity,"prepped",true)
				return false
			end
		end
	},
	["boulder"]={
		["hit_channel"]="obstacle",
		["animation"]={
			["default"]={71},
			["damaged"]={72},
			["destroyed"]={73}
		},
		["init"]=function(entity)
			entity.health=2
		end,
		["on_hit_by"]=function(entity)
			entity.health-=1
			entity.wiggle_frames=4
			if entity.health>0 then
				set_entity_anim(entity,"damaged",true)
			else
				destroy_entity(entity)
			end
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("dirt_blast",entity)
		end
	},
	["tall_grass"]={
		["hit_channel"]="obstacle",
		["projectile_armor"]=-1,
		["animation"]={90},
		["render_priority"]=1,
		["on_hit"]=function(entity,hittee)
			destroy_entity(entity)
			return false
		end,
		["on_hit_by"]=function(entity,hitter)
			destroy_entity(entity)
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("shredded_grass",entity)
		end
	},
	["shredded_grass"]={
		["animation"]={91,92},
		["render_priority"]=1,
		["frames_to_death"]=12
	},
	["coin"]={
		["hit_channel"]="pickup",
		["animation"]={57,58,59,60},
		["on_hit_by"]=function(entity)
			destroy_entity(entity)
		end,
		["on_destroyed"]=function(entity)
			spawn_entity_at_entity("coin_collect",entity)
		end
	},
	["coin_collect"]={
		["animation"]={57,61,62,63},
		["render_priority"]=1,
		["frames_to_death"]=24,
		["init"]=function(entity)
			coin_count+=1
			entity.vy=2
		end,
		["pre_update"]=function(entity)
			entity.vy=max(0,entity.vy-0.2)
		end
	},
	["explosion"]={
		["animation"]={12,13,14,15},
		["render_priority"]=1,
		["frames_to_death"]=24
	},
	["deflect"]={
		["animation"]={29,30,31},
		["render_priority"]=1,
		["frames_to_death"]=18
	},
	["poof"]={
		["animation"]={45,46,47},
		["render_priority"]=1,
		["frames_to_death"]=18
	},
	["dirt_blast"]={
		["animation"]={43,44},
		["render_priority"]=1,
		["frames_to_death"]=12,
		["init"]=function(entity)
			entity.vy=2
		end,
		["pre_update"]=function(entity)
			entity.vy=entity.vy-0.2
		end
	}
	-- ["clothesline"]
	-- ["clothes"]
	-- ["jump_pad"]
	-- ["falling_boulder_spawner"]
	-- ["falling_boulder"]
	-- ["damaging_impact"]
	-- ["friend"]
	-- ["friend_in_cart"]
	-- ["car_expander"]
	-- ["target_arrow"] 
	-- ["flying_clothes"] 
	-- ["friend_death"] 
}

tile_types={
	-- [tile_type]={frame}
	["grass"]={64},
	["stump"]={65},
	["dirt_mark"]={66},
	["bridge"]={82},
	["bridge_support_left"]={98},
	["bridge_support_right"]={98.5},
	["cliff_start"]={80},
	["cliff_middle"]={96},
	["cliff_end"]={112},
	["cliff_start_left"]={81},
	["cliff_start_right"]={81.5},
	["cliff_middle_left"]={97},
	["cliff_middle_right"]={97.5}
}

levels={
	{
		{
			["bg_color"]=15,
			["draw_bg"]=function()
				local min_cloud_row=flr((camera_pan_z-2)/6)-2
				local r
				for r=min_cloud_row,min_cloud_row+28 do
					if r%3==0 then
						local arg1=game_frame/30+20*r -- saves ten symbols
						local arg2=-6*r -- saves three symbols
						circfill(arg1%158-15,arg2,21,7)
						circfill((arg1-20)%158-15,arg2+r%10-5,16,7)
						circfill((arg1+20)%158-15,arg2-r%17+8,14,7)
					end
				end
			end,
			["player_spawn"]={8,8,6},
			["map_legend"]={
				-- [icon]={tile_type,entity_type,entity_facing,entity_args}
				["."]={"grass"},
				[","]={"dirt_mark"},
				["t"]={"stump","tree"},
				["="]={"bridge"},
				["("]={"bridge_support_left"},
				[")"]={"bridge_support_right"},
				["#"]={"cliff_start"},
				["*"]={"cliff_middle"},
				["~"]={"cliff_end"},
				["}"]={"cliff_start_left"},
				["{"]={"cliff_start_right"},
				["]"]={"cliff_middle_left"},
				["["]={"cliff_middle_right"},
				["s"]={"dirt_mark","spear_thrower",1},
				["o"]={"grass","coin"},
				["x"]={"dirt_mark","trap"},
				["g"]={"dirt_mark","tall_grass"},
				["b"]={"dirt_mark","boulder"}
			},
			["map"]={
				"      .......        ",
				"      .......        ",
				"      ###=###        ",
				"      ***=***        ",
				"         =           ",
				"         =    {.t    ",
				"ttt.====...bb.[..    ",
				"t.gg(  )b..oo.[s.    ",
				"..gg    tt.oo.[..====",
				"..gg    tt.oo.[.s()()",
				"..gg    ......[..    ",
				"##..====..ooo.[....} ",
				"**##(  )#.....[####] ",
				"~~**    *xxx........ ",
				"  ~~    ~####=###### ",
				"         ****=****** ",
				"         ~~~~=~~~~~~ ",
				"   .   =======       ",
				"   #   =()()()       ",
				" . * . ======        ",
				" # * # ======        ",
				" * ~ ~ ======        ",
				" *     ======        ",
				" *     ======        ",
				"       ======        ",
				"       ======        ",
				"       ======        ",
				"       ======        ",
				"       ======        "
			}
		}
	}
}

__gfx__
08880099008880000222002002022200222200000cccccc0cccc0ccc0000000000000000000000000000000000000000000000000000000000aaaa0080000008
8888808888888880288820800808882088880000cc7777ccc777cc7c00000000000000000000000000000000000ee00000099000000000000a0000a008000080
0929080808282800822080800808008082000000c7cccc7c7ccc7c7c00000000000000000000000000088000000ee0000098890000700700a000000a00000000
092989980828280008820080080802808800000087cc888c7cc87c780088880000aaaa000077770000088000000ee0000988889000077000a000000a00000000
298988880998990020080080080888008000000087888778788878780088880000aaaa000077770000088000000ee0000988889000077000a000000a00000000
5888899908888800822080822808000080220000878888787888788000000000000000000000000000088000000000000098890000700700a000000a00000000
0222222502222200088800088008000088880000887777888777887800000000000000000000000000000000000ee00000099000000000000a0000a008000080
025025050250250000000000000000000000000008888880888808880000000000000000000000000008800000000000000000000000000000aaaa0080000008
00888800008888002222200000200022202200200001100000000000000000000000000000000000000000000000000000000000000000000000000000000007
088888800888888088888000028200888088208000011000000000000000000000000000000000000aaaaaa0000000008000000800000000000000700c000070
0092290008822880008000000808200800808080001111000000000000088000000aa00000077000097778900000000008800880000770000000770000c00000
0292292000888800008000002828200800808080001111000000000000088000000aa00000077000097888900077770008000080007007000000c70000000000
0988889000922900008000008088800800808080001111000000000000088000000aa0000007700009778990007007000000000000700700007c000000000000
0989989000822800008000008000802820808280011111100000000000088000000aa00000077000097888900070070000000000000770000077000000000c00
025555200022220000800000800080888080088001111110000000000000000000000000000000000977789000777700080000800000000007000000070000c0
05555550005225000000000000000000000000000111111000000000000000000000000000000000000000000000000088800888000000000000000070000000
00099000008888000000008802222000000000001111111100000000000000000000000000000000000000000000000000000000000000000000000000000070
00888800088888800000088a088882000000000011aaaa1100000000000000000000000000000000000000000000000000000000000000000000077000000707
0888888008822880000088a908000800088800001a888a8100000000000000000000000000000000000000000000000000004000000000000000777707000070
009229000088880000008a980802280009290900aa88888a00000000000000000000000000000000000000000000400000000040007777000770077070700000
0292292000988900000889800888800209298800aa52525a00000000000000000000000000022000002222000000400004000000077777707777000007000000
08888880008888000008a9800808022808888900aa22225a00000000000000000000000000222200022222200040404000040000077777700770770000000070
08222280008888000008a80008008880025025000aaaaaa000000000000000000000000000022000002222000440400000000000007777000007777000000707
052002500052250000889888000000000000000000aaaa0000000000000000000000000000000000000000000000000000000000000000000000770000000070
00000000000000000089a80088880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000008888000089a80089a88000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
08989800009559000089a800089a880000000000000000000000000000000000000000000007a00000079000000990000009700000077000000aa00000a00a00
08555800008558000089a8000889a880000a9000000000000000000000000000000000000077a900000a9000009999000009a0000077770000a00a0000000000
08555800009559000089a80000889a8800aaa90007070000000000000000000000000000007aa900000a9000009999000009a0000077770000a00a0000000000
589898000088880000899800000889a8009aa9000070000000000000000000000000000000aaa900000a9000009999000009a0000077770000a00a0000000000
0222220000222200008880000000889a0009900007070000000000000000000000000000000a9000000a9000000990000009a00000077000000aa00000a00a00
02502500005225000000000000000889000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000003300000000000000000000d500000000000000000000000000000000000000000000000000000
0003000000000000000000000000000000000000000000000033330000d6dd0000d65d00d5d005d0010000000010000010116700001000000100000000000000
0bb3bbb00bbbbbb00fbfbfb0000000000000000000000000003333000d6ddd500d6d55d0d5500d5d00ccc00000ccc0004ccc467000ccc00000c1c10000000000
0bbbbbb00bb44bb00bfffff0000000000000000000000000033333300ddddd500dddd550550005550c11c1100ccccc00c11c11000ccccc000c17c71000006700
03b3bbb00b4ff4b00fffffb0000000000000000000000000031333300dd5d5500dd555d0005d00500cc7c7000c11c110cc7c70000c11c1100ceccce000444670
0b3bb3b00b4ff4b00bfffff0000000000000000000000000013131300d5ddd500d5d5d5000d550000ccccc000cc7c700ccccc0000ccccc100c11cc1000006700
0bbbb3b00bb44bb00fffffb0000000000000000000000000011113100dd5555005d5d5500055500001c1c1001ccccc101c1c100001c1c1100111c11000000000
0bbbbbb00bbbbbb00bfbfbf0000000000000000000000000001311000b5555b00b5555b0000000000110110011c1c11001100000011000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000003b3b3b00003003000003000000440000004400000044000
0000000000000000000000000000000000000000000000000000000000d6dd000055dd00005555000b3b33300030b30003030000000110000001100000011000
044444400400000009499990000000000000000000000000000000000d6d5d50055dddd00d55d55003b3b3b0030b30b030b00b00001411100001410000044100
044444400440000009994490000000000000000000000000000000000ddddd5005d5d6d00ddd5d500b333b3000b00b000b00b000000440010001400000044000
044424400444000009449990000000000000000000000000000000000dd5d5500555d6d00d6ddd5003b3b3b00005b00000000500000440000001400000044000
042424200442400009999940000000000000000000000000000000000d5dd550055dddd0056d5d500b3b3b30005030500000500500f44f0000f14f0000f44f00
0424242004442400099449900000000000000000000000000000000000d555000055dd0000dddd0003535350050305000030005000f44f0000f14f0000f44f00
02242220044422200999999000000000000000000000000000000000000000000000000000000000035353500030500003000000000ff0000001f000000ff000
00000000000000000000000000000000000000000000000000000000000000000000000000777700000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000007733770000000000000000000000000000000000000000000000000
0222222004424220044444400000000000000000000000000000000004777740047007400737737000f1800000f100000f000f000f000f000000880000082000
02222220044424200444000000000000000000000000000000000000077337700777777007377370000182000001200018888810188888100888820000888800
02222220044422200440000000000000000000000000000000000000073773700773377007733770000188000001800002888200028882000288880008888800
0222222004424220040000000000000000000000000000000000000007733770073773700777777000f1800000f1000008808800088088000880880002880000
02222220044424200200000000000000000000000000000000000000047777400473374004777740000128000001800008808800000000000880000000880000
02222220044422200f00000000000000000000000000000000000000045555400455554004555540000108000001800000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000747000000000000000000000000000000000000000000000000000
02f2f2f000000000000000000000000000000000000000000000000000000000000440000064677000f1900000f100000f000f000f000f000000990000094000
0f2f2f20000000000000000000000000000000000000000000000000004004000044440000040470000194000001400019999910199999100999940000999900
0ffffff0000000000000000000000000000000000000000000000000000440000004400007744000000199000001900004999400049994000499990009999900
0ffffff000000000000000000000000000000000000000000000000000044000004004000742200000f1900000f1000009909900099099000990990004990000
00f0f0f0000000000000000000000000000000000000000000000000004004000000000000040000000149000001900009909900000000000990000000990000
0f0f0f00000000000000000000000000000000000000000000000000000000000000000000000000000109000001900000000000000000000000000000000000
000bb000000bb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
003bb30000bbbb00000000000000bb0000000000000bbb0000000000000bb0000000000000000000000000000000000000000000000000000000000000000000
04bbbb40043bb3400000bb00000b3bb0000bbb0000b3b3b0003bb30000bbbb000000000000000000000000000000000000000000000000000000000000000000
0f4bb4f00f4334f00043bbb0004bbbe000b3b3b0003beb0000bbbb000b3bb3b00000000000000000000000000000000000000000000000000000000000000000
04333340b33bb33b0f43b3b00f4333000f3bbb000f33b30003f44f3003f44f300000000000000000000000000000000000000000000000000000000000000000
0b3bb3b0043bb34004f33bb004fb33000443334004433340044ff440044ff4400000000000000000000000000000000000000000000000000000000000000000
003bb300003333000f4b33000f4b330003bbbb3003bbbb3004f44f4004f44f400000000000000000000000000000000000000000000000000000000000000000
0030030000300300004b300000433000000bb000000bb000000ff000000ff0000000000000000000000000000000000000000000000000000000000000000000
0000cc000c00c9900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c19900c0c1e00000000000c000090000000000009900000000000000990000000000000000000000000000000000000000000000000000000000000000000
000cc990ccccc9e0000ccc000cccc9e000cccc00009ee90000cccc00000990000000000000000000000000000000000000000000000000000000000000000000
00cccc90cccccc9000c1c990ccc1c800001cc1000ceeeec000cccc0000cccc000000000000000000000000000000000000000000000000000000000000000000
00ccffc00cccffc00cccc990cc1cc9800c9999c00c9889c00cccccc000cccc000000000000000000000000000000000000000000000000000000000000000000
01ccffc00ccfffc00cc1ff90ccc1cc900cc99cc00cf99fc00cccccc00cccccc00000000000000000000000000000000000000000000000000000000000000000
01c9ff9001f9ff900ccfff000cccff000cffffc00cffffc00c1cc1c0cc1cc1cc0000000000000000000000000000000000000000000000000000000000000000
00949949009499490c1ff00000fff000000ff000000ff000000cc000000cc0000000000000000000000000000000000000000000000000000000000000000000
00900900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
009ff900095ff9500900009000000000090000900000000000000000050000500000000000000000000000000000000000000000000000000000000000000000
0059f950009959000f9009f09f009f000f9009f09f009f0009000090005005000000000000000000000000000000000000000000000000000000000000000000
4099590004598950099ff99009ff9990099ff99009ff999009900990099ff9900000000000000000000000000000000000000000000000000000000000000000
44599050440990000f59f9500d99599d0f59f9500d99599d099ff99009f99f900000000000000000000000000000000000000000000000000000000000000000
04f9990040f999000d99599d099585900d99599d09958590099999900f9999f00000000000000000000000000000000000000000000000000000000000000000
0f9999004f999900099595900d99999d099595900d99999d09999990099999900000000000000000000000000000000000000000000000000000000000000000
04490900044909000d99990d009999000d99990d0099990000999900009999000000000000000000000000000000000000000000000000000000000000000000
05500550000550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0e5ff5e0055ee5500000000000000000000000000001100000000000000110000000000000000000000000000000000000000000000000000000000000000000
005555000e5555e00055f50000f55110005ff5000055550000555500005555000000000000000000000000000000000000000000000000000000000000000000
00f55f0000ffff0005555f500f515ee005155150005ee50005555550001551000000000000000000000000000000000000000000000000000000000000000000
0ffffff00f5ff5f00ee51510055558800e5555e0055885500e5555e0055555500000000000000000000000000000000000000000000000000000000000000000
0f5ff5f00ffffff00ff5555005e555000ff11ff00ef55fe00ffffff00effffe00000000000000000000000000000000000000000000000000000000000000000
00ffff0000ffff000fff51100eefff000ffffff00ffffff00ffffff00ffffff00000000000000000000000000000000000000000000000000000000000000000
005005000050050000fff00000fff000000ff000000ff000000ff000000ff0000000000000000000000000000000000000000000000000000000000000000000
000000000000000000bbbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009a9a9a003b3b3b0
00bbbb0000bbbb00033bb33000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a9a99900b3b3330
0bbbbbb00b9bb9b00bbaabb00455454005354440044454400dcccdd00cd55d500dd555d0054544400000000000000000000000000000000009a9a9a003b3b3b0
3b9bb9b33bbbbbb333beeb330545545004345450054554500ccddcc00dccd5500555d55004445450000000000000000000000000000000000a999a900b333b30
3bbbbbb333baab333b3883b30455455004544450045545500cccccd00dcccd50055d5dd0045444500000000000000000000000000000000009a9a9a003b3b3b0
b3baab3b3b3993b33b3883b30555455005453530055555500ddccdd00cddcdd00d55555005454540000000000000000000000000000000000a9a9a900b3b3b30
b339933b0b3993b00b3993b00555554004545350055555500cddccc00ccddcd0055dd5d004545450000000000000000000000000000000000949494003535350
0bb00bb003b00b300b3003b00455545004445450055555500cccddd00cddccc005555d5004445450000000000000000000000000000000000949494003535350
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009009000030030
00baab0000b99b0000b88b00000000000010000000010000010886700001000000100000000000000000000000000000000000000aa887a00090a9000030b300
bb9bb9bbbbbaabbbb3beeb3b00000000000ccc00000ccc0044ccc467000ccc00000c1c1005444440000000000000000000000000aa888a7a090a90a0030b30b0
3bbbbbb33b9bb9b33bbaabb30000000000c11c1100ccccc00c11c11000ccccc000c17c7105454450000000000000000000000000a888aa7800a00a0000b00b00
bbbbbbbb3bbbbbb3b33bb33b0000000000cc7c7000c11c110cc7c70000c11c1100cfecce045d54400000000000000000000000008888aaa80004a0000005b000
b3bbbb3bb3bbbb3b3bbbbbb30000000000ccccc000cc7c700ccccc0000cccc2800c88c880d55454000000000000000000000000088aaaa880040904000503050
3b3333b33bb33bb333bbbb330000000000288820082ccc280828880000288888008288880555d4500000000000000000000000000aaaa8800409040005030500
03333330033333300333333000000000008808800888888800880000008800000000000005555d4000000000000000000000000000a888000090400000305000
00000000000000000bb3b00000000000000000000000000000000000000000000000000000000000000000000000000000000000088888800000900000003000
003bbb0000bbbb00bbb3bb0000000000099099000099099099099670009909900990940000000000000000000000000000000000888888880909000003030000
03bbb9b00bbb9bb0bbbbae00000000000949994000499940949994670049994009491c10000000000000000000000000000000008888888890a00a0030b00b00
33bbbba03bbbba90bbb3aee00000000000911c1100ccccc00911c11000ccccc000917c7100000000000000000000000000000000088888800a00a0000b00b000
33bbb9ab3bbb9a9b3bb3be800000000000cc7c7000c11c110cc7c70000c11c1100ceccce00000000000000000000000000000000050000500000040000000500
3b3bbb9033bbbb30b33b33800000000000ccccc000cc7c700ccccc0000ccccc100c11cc100000000000000000000000000000000444000440000400400005005
b333b330b333bb30b333bb9000000000001c1c1001ccccc101c1c100001c1c1100111c1100000000000000000000000000000000444444400090004000300050
0bb30bb00bb303b00bb303b00000000000110110011c1c1100110000001100000000000000000000000000000000000000000000044444000900000003000000
00000000000000000000000000022000000000000000000000000000000000000000000000000000000000000000000000000000008888000000000000000000
000000000000000000000000002222000880880000880880880886700088088008808200000000000000000000000000000000000888888000000000000bbb00
00077000000cc00006656560022222200828882000288820828882670028882008281c1000000000000000000000000000000000088888800500005002b253b0
0077770000cccc00064444600228822000811c1100ccccc00811c11000ccccc000817c7100000000000000000000000000000000008888004ff0005005352530
0077770000cccc00054444500288882000cc7c7000c11c110cc7c70000c11c1100ceccce0000000000000000000000000000000000500500444044ff02535230
00077000000cc000054444500888888000ccccc000cc7c700ccccc0000cccc4900c99c990000000000000000000000000000000004400440444444400b2523b0
0000000000000000054444500898998000499940094ccc4909499900004999990094999900000000000000000000000000000000044444002545452002323350
00000000000000000665446008889980009909900999999900990000009900000000000000000000000000000000000000000000004440000222220003533320
__gff__
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010000000000000000000000000008020100000000000000000000000000081a000000000000000000000000000000000000000000000000000000000000
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

