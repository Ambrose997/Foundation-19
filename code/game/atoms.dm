/atom
	var/level = 2
	var/atom_flags = ATOM_FLAG_NO_TEMP_CHANGE
	var/list/blood_DNA
	var/was_bloodied
	var/blood_color
	var/last_bumped = 0
	var/pass_flags = 0
	var/throwpass = 0
	var/germ_level = GERM_LEVEL_AMBIENT // The higher the germ level, the more germ on the atom.
	var/simulated = TRUE //filter for actions - used by lighting overlays
	var/fluorescent // Shows up under a UV light.
	var/datum/reagents/reagents // chemical contents.
	var/list/climbers
	var/climb_speed_mult = 1
	var/init_flags = EMPTY_BITFIELD
	var/list/orbiters = null
	var/datum/scp/SCP //For SCP's

	///Value used to increment ex_act() if reactionary_explosions is on
	var/explosion_block = 0

	/// How this atom should react to having its pathfinding blocking checked
	var/can_astar_pass = CANPATHINGPASS_DENSITY

/atom/New(loc, ...)
	//atom creation method that preloads variables at creation
	if(GLOB.use_preloader && (src.type == GLOB._preloader.target_path))//in case the instanciated atom is creating other atoms in New()
		GLOB._preloader.load(src)

	var/do_initialize = SSatoms.atom_init_stage
	var/list/created = SSatoms.created_atoms
	if(do_initialize > INITIALIZATION_INSSATOMS_LATE)
		args[1] = do_initialize == INITIALIZATION_INNEW_MAPLOAD
		if(SSatoms.InitAtom(src, args))
			//we were deleted
			return
	else if(created)
		var/list/argument_list
		if(length(args) > 1)
			argument_list = args.Copy(2)
		if(argument_list || do_initialize == INITIALIZATION_INSSATOMS_LATE)
			created[src] = argument_list

	if(atom_flags & ATOM_FLAG_CLIMBABLE)
		verbs += /atom/proc/climb_on

//Called after New if the map is being loaded. mapload = TRUE
//Called from base of New if the map is not being loaded. mapload = FALSE
//This base must be called or derivatives must set initialized to TRUE
//must not sleep
//Other parameters are passed from New (excluding loc)
//Must return an Initialize hint. Defined in __DEFINES/subsystems.dm

/atom/proc/Initialize(mapload, ...)
	SHOULD_CALL_PARENT(TRUE)

	if(atom_flags & ATOM_FLAG_INITIALIZED)
		crash_with("Warning: [src]([type]) initialized multiple times!")
	atom_flags |= ATOM_FLAG_INITIALIZED

	if (IsAbstract())
		log_debug("Abstract atom [type] created!")
		return INITIALIZE_HINT_QDEL

	if(light_max_bright && light_outer_range)
		update_light()

	if(opacity)
		updateVisibility(src)
		var/turf/T = loc
		if(istype(T))
			T.RecalculateOpacity()

	if(health_max)
		health_current = health_max

	return INITIALIZE_HINT_NORMAL

//called if Initialize returns INITIALIZE_HINT_LATELOAD
/atom/proc/LateInitialize()
	return

/atom/Destroy()
	QDEL_NULL(reagents)
	. = ..()

/**
 * An atom has entered this atom's contents
 *
 * Default behaviour is to send the [COMSIG_ATOM_ENTERED]
 */
/atom/Entered(atom/movable/enterer, atom/old_loc)
	SEND_SIGNAL(src, COMSIG_ENTERED, enterer, old_loc)

/**
 * An atom has exited this atom's contents
 *
 * Default behaviour is to send the [COMSIG_ATOM_EXITED]
 */
/atom/Exited(atom/movable/exitee, atom/new_loc)
	SEND_SIGNAL(src, COMSIG_EXITED, exitee, new_loc)

/atom/proc/reveal_blood()
	return

/atom/proc/MayZoom()
	return TRUE

/atom/proc/assume_air(datum/gas_mixture/giver)
	return null

/atom/proc/remove_air(amount)
	return null

/atom/proc/return_air()
	if(loc)
		return loc.return_air()
	else
		return null

//return flags that should be added to the viewer's sight var.
//Otherwise return a negative number to indicate that the view should be cancelled.
/atom/proc/check_eye(user as mob)
	if (istype(user, /mob/living/silicon/ai)) // WHYYYY
		return 0
	return -1

//Return flags that may be added as part of a mobs sight
/atom/proc/additional_sight_flags()
	return 0

/atom/proc/additional_see_invisible()
	return 0

/atom/proc/on_reagent_change()
	return

/atom/proc/on_color_transfer_reagent_change()
	return

/atom/proc/Bumped(AM as mob|obj)
	return

// Convenience proc to see if a container is open for chemistry handling
// returns true if open
// false if closed
/atom/proc/is_open_container()
	return atom_flags & ATOM_FLAG_OPEN_CONTAINER

/*//Convenience proc to see whether a container can be accessed in a certain way.

	proc/can_subract_container()
		return flags & EXTRACT_CONTAINER

	proc/can_add_container()
		return flags & INSERT_CONTAINER
*/

/atom/proc/CheckExit()
	return 1

// If you want to use this, the atom must have the PROXMOVE flag, and the moving
// atom must also have the PROXMOVE flag currently to help with lag. ~ ComicIronic
/atom/proc/HasProximity(atom/movable/AM as mob|obj)
	return

/atom/proc/emp_act(severity)
	return

/atom/proc/set_density(new_density)
	if(density != new_density)
		density = !!new_density

/atom/proc/bullet_act(obj/item/projectile/P, def_zone)
	P.on_hit(src, 0, def_zone)
	. = 0

/atom/proc/in_contents_of(container)//can take class or object instance as argument
	if(ispath(container))
		if(istype(src.loc, container))
			return 1
	else if(src in container)
		return 1
	return

/*
 *	atom/proc/search_contents_for(path,list/filter_path=null)
 * Recursevly searches all atom contens (including contents contents and so on).
 *
 * ARGS: path - search atom contents for atoms of this type
 *	   list/filter_path - if set, contents of atoms not of types in this list are excluded from search.
 *
 * RETURNS: list of found atoms
 */

/atom/proc/search_contents_for(path,list/filter_path=null)
	var/list/found = list()
	for(var/atom/A in src)
		if(istype(A, path))
			found += A
		if(filter_path)
			var/pass = 0
			for(var/type in filter_path)
				pass |= istype(A, type)
			if(!pass)
				continue
		if(A.contents.len)
			found += A.search_contents_for(path,filter_path)
	return found

// A type overriding /examine() should either return the result of ..() or return TRUE if not calling ..()
// Calls to ..() should generally not supply any arguments and instead rely on BYOND's automatic argument passing
// There is no need to check the return value of ..(), this is only done by the calling /examinate() proc to validate the call chain
/atom/proc/examine(mob/user, distance, infix = "", suffix = "")
	//This reformat names to get a/an properly working on item descriptions when they are bloody
	var/f_name = "\a [src][infix]."
	if(blood_color && !istype(src, /obj/effect/decal))
		if(gender == PLURAL)
			f_name = "some "
		else
			f_name = "a "
		f_name += "<font color ='[blood_color]'>stained</font> [name][infix]!"

	to_chat(user, "[icon2html(src, user)] That's [f_name] [suffix]")
	to_chat(user, desc)
	if(health_max)
		examine_damage_state(user)
	return TRUE

// called by mobs when e.g. having the atom as their machine, pulledby, loc (AKA mob being inside the atom) or buckled var set.
// see code/modules/mob/mob_movement.dm for more.
/atom/proc/relaymove()
	return

/atom/proc/set_icon_state(new_icon_state)
	if(has_extension(src, /datum/extension/base_icon_state))
		var/datum/extension/base_icon_state/bis = get_extension(src, /datum/extension/base_icon_state)
		bis.base_icon_state = new_icon_state
		update_icon()
	else
		icon_state = new_icon_state

/atom/proc/SetName(new_name)
	var/old_name = name
	if(old_name != new_name)
		name = new_name

		//TODO: de-shitcodify
		if(has_extension(src, /datum/extension/labels))
			var/datum/extension/labels/L = get_extension(src, /datum/extension/labels)
			name = L.AppendLabelsToName(name)

/atom/proc/update_icon()
	on_update_icon(arglist(args))

/atom/proc/on_update_icon()
	return

/atom/proc/ex_act()
	return

/atom/proc/emag_act(remaining_charges, mob/user, emag_source)
	return EMAG_NO_ACT

/atom/proc/fire_act(datum/gas_mixture/air, exposed_temperature, exposed_volume)
	return

/atom/proc/melt()
	return

/atom/proc/lava_act()
	visible_message(SPAN_DANGER("\The [src] sizzles and melts away, consumed by the lava!"))
	playsound(src, 'sounds/effects/flare_start.ogg', 100, 3)
	qdel(src)
	. = TRUE

/atom/proc/hitby(atom/movable/AM, datum/thrownthing/TT)//already handled by throw impact
	if(isliving(AM))
		var/mob/living/M = AM
		M.apply_damage(TT.speed*5, BRUTE)

//returns 1 if made bloody, returns 0 otherwise
/atom/proc/add_blood(mob/living/carbon/human/M as mob)
	if(atom_flags & ATOM_FLAG_NO_BLOOD)
		return 0

	if(!blood_DNA || !istype(blood_DNA, /list))	//if our list of DNA doesn't exist yet (or isn't a list) initialise it.
		blood_DNA = list()

	was_bloodied = 1
	blood_color = COLOR_BLOOD_HUMAN
	if(istype(M))
		if (!istype(M.dna, /datum/dna))
			M.dna = new /datum/dna(null)
			M.dna.real_name = M.real_name
		M.check_dna()
		blood_color = M.species.get_blood_colour(M)
	. = 1
	return 1

/mob/living/proc/handle_additional_vomit_reagents(obj/effect/decal/cleanable/vomit/vomit)
	vomit.reagents.add_reagent(/datum/reagent/acid/stomach, 5)

/atom/proc/clean(clean_forensics = TRUE)
	SHOULD_CALL_PARENT(TRUE)
	if(!simulated)
		return
	fluorescent = 0
	germ_level = 0
	blood_color = null
	gunshot_residue = null
	if(istype(blood_DNA, /list))
		blood_DNA = null
		return TRUE
	return FALSE
/atom/proc/get_global_map_pos()
	if (!islist(GLOB.global_map) || !length(GLOB.global_map))
		return
	var/cur_x = null
	var/cur_y = null
	var/list/y_arr = null
	for(cur_x=1,cur_x<=GLOB.global_map.len,cur_x++)
		y_arr = GLOB.global_map[cur_x]
		cur_y = list_find(y_arr, src.z)
		if(cur_y)
			break
//	log_debug("X = [cur_x]; Y = [cur_y]")

	if(cur_x && cur_y)
		return list("x"=cur_x,"y"=cur_y)
	else
		return 0

/atom/proc/checkpass(passflag)
	return pass_flags&passflag

/atom/proc/isinspace()
	if(isspaceturf(get_turf(src)))
		return 1
	else
		return 0


// Show a message to all mobs and objects in sight of this atom
// Use for objects performing visible actions
// message is output to anyone who can see, e.g. "The [src] does something!"
// blind_message (optional) is what blind people will hear e.g. "You hear something!"
/atom/proc/visible_message(message, blind_message, range = world.view, checkghosts = null, list/exclude_objs = null, list/exclude_mobs = null)
	set waitfor = FALSE
	var/turf/T = get_turf(src)
	var/list/mobs = list()
	var/list/objs = list()
	get_mobs_and_objs_in_view_fast(T,range, mobs, objs, checkghosts)

	for(var/o in objs)
		var/obj/O = o
		if (exclude_objs?.len && (O in exclude_objs))
			exclude_objs -= O
			continue
		O.show_message(message, VISIBLE_MESSAGE, blind_message, AUDIBLE_MESSAGE)

	for(var/m in mobs)
		var/mob/M = m
		if (exclude_mobs?.len && (M in exclude_mobs))
			exclude_mobs -= M
			continue
		if((M.see_invisible >= invisibility) && M.can_see(src))
			M.show_message(message, VISIBLE_MESSAGE, blind_message, AUDIBLE_MESSAGE)
		else if(blind_message)
			M.show_message(blind_message, AUDIBLE_MESSAGE)

// Show a message to all mobs and objects in earshot of this atom
// Use for objects performing audible actions
// message is the message output to anyone who can hear.
// deaf_message (optional) is what deaf people will see.
// hearing_distance (optional) is the range, how many tiles away the message can be heard.
/atom/proc/audible_message(message, deaf_message, hearing_distance = world.view, checkghosts = null, list/exclude_objs = null, list/exclude_mobs = null)
	var/turf/T = get_turf(src)
	var/list/mobs = list()
	var/list/objs = list()
	get_mobs_and_objs_in_view_fast(T, hearing_distance, mobs, objs, checkghosts)

	for(var/m in mobs)
		var/mob/M = m
		if (exclude_mobs?.len && (M in exclude_mobs))
			exclude_mobs -= M
			continue
		M.show_message(message,2,deaf_message,1)

	for(var/o in objs)
		var/obj/O = o
		if (exclude_objs?.len && (O in exclude_objs))
			exclude_objs -= O
			continue
		O.show_message(message,2,deaf_message,1)

/atom/movable/proc/dropInto(atom/destination)
	while(istype(destination))
		var/atom/drop_destination = destination.onDropInto(src)
		if(!istype(drop_destination) || drop_destination == destination)
			return forceMove(destination)
		destination = drop_destination
	return forceMove(null)

/atom/proc/onDropInto(atom/movable/AM)
	return // If onDropInto returns null, then dropInto will forceMove AM into us.

/atom/movable/onDropInto(atom/movable/AM)
	return loc // If onDropInto returns something, then dropInto will attempt to drop AM there.

/atom/proc/InsertedContents()
	return contents

//all things climbable

/atom/attack_hand(mob/user)
	..()
	if(LAZYLEN(climbers) && !(user in climbers))
		user.visible_message(SPAN_WARNING("[user.name] shakes \the [src]."), \
					SPAN_NOTICE("You shake \the [src]."))
		object_shaken()

// Called when hitting the atom with a grab.
// Will skip attackby() and afterattack() if returning TRUE.
/atom/proc/grab_attack(obj/item/grab/G)
	return FALSE

/atom/proc/climb_on()

	set name = "Climb"
	set desc = "Climbs onto an object."
	set category = "Object"
	set src in oview(1)

	do_climb(usr)

/atom/proc/can_climb(mob/living/user, post_climb_check=FALSE, check_silicon=TRUE)
	if (!(atom_flags & ATOM_FLAG_CLIMBABLE) || !can_touch(user, check_silicon) || (!post_climb_check && climbers && (user in climbers)))
		return 0

	if (!user.ClimbCheck(src)) // Mob specific climb check
		return 0

	if (!user.Adjacent(src))
		to_chat(user, SPAN_DANGER("You can't climb there, the way is blocked."))
		return 0

	var/obj/occupied = turf_is_crowded(user)
	//because Adjacent() has exceptions for windows, those must be handled here
	if(!occupied && istype(src, /obj/structure/wall_frame))
		var/original_dir = get_dir(src, user.loc)
		var/progress_dir = original_dir
		for(var/atom/A in loc.contents)
			if(A.atom_flags & ATOM_FLAG_CHECKS_BORDER)
				var/obj/structure/window/W = A
				if(istype(W))
					//progressively check if a window matches the X or Y component of the dir, if collision, set the dir bit off
					if(W.is_fulltile() || (progress_dir &= ~W.dir) == 0) //if dir components are 0, fully blocked on diagonal
						occupied = A
						break
		//if true, means one dir was blocked and bit set off, so check the unblocked
		if(progress_dir != original_dir && progress_dir != 0)
			var/turf/here = get_turf(src)
			if(!here.Adjacent_free_dir(user, progress_dir))
				to_chat(user, SPAN_DANGER("You can't climb there, the way is blocked."))
				return FALSE

	if(occupied)
		to_chat(user, SPAN_DANGER("There's \a [occupied] in the way."))
		return 0
	return 1

/atom/proc/can_touch(mob/user, check_silicon=TRUE)
	if (!user)
		return 0
	if(!Adjacent(user))
		return 0
	if (user.restrained() || user.buckled)
		to_chat(user, SPAN_NOTICE("You need your hands and legs free for this."))
		return 0
	if (user.incapacitated())
		return 0
	if (check_silicon && issilicon(user))
		to_chat(user, SPAN_NOTICE("You need hands for this."))
		return 0
	return 1

/atom/proc/turf_is_crowded(atom/ignore)
	var/turf/T = get_turf(src)
	if(!istype(T))
		return 0
	for(var/atom/A in T.contents)
		if(ignore && ignore == A)
			continue
		if(A.atom_flags & ATOM_FLAG_CLIMBABLE)
			continue
		if(A.density && !(A.atom_flags & ATOM_FLAG_CHECKS_BORDER)) //ON_BORDER structures are handled by the Adjacent() check.
			return A
	return 0

/atom/proc/do_climb(mob/living/user, check_silicon=TRUE)
	if (!can_climb(user, check_silicon=check_silicon))
		return 0

	add_fingerprint(user)
	user.visible_message(SPAN_WARNING("\The [user] starts climbing onto \the [src]!"))
	LAZYOR(climbers,user)

	if(!do_after(user,(issmall(user) ? MOB_CLIMB_TIME_SMALL : MOB_CLIMB_TIME_MEDIUM) * climb_speed_mult, src, bonus_percentage = 25))
		LAZYREMOVE(climbers,user)
		return 0

	if(!can_climb(user, post_climb_check=1, check_silicon=check_silicon))
		LAZYREMOVE(climbers,user)
		return 0

	var/target_turf = get_turf(src)

	//climbing over border objects like railings
	if((atom_flags & ATOM_FLAG_CHECKS_BORDER) && get_turf(user) == target_turf)
		target_turf = get_step(src, dir)

	user.forceMove(target_turf)

	if (get_turf(user) == target_turf)
		user.visible_message(SPAN_WARNING("\The [user] climbs onto \the [src]!"))
	LAZYREMOVE(climbers,user)
	return 1

/atom/proc/object_shaken()
	for(var/mob/living/M in climbers)
		M.Weaken(1)
		to_chat(M, SPAN_DANGER("You topple as you are shaken off \the [src]!"))
		climbers.Cut(1,2)

	for(var/mob/living/M in get_turf(src))
		if(M.lying) return //No spamming this on people.

		M.Weaken(3)
		to_chat(M, SPAN_DANGER("You topple as \the [src] moves under you!"))

		if(prob(25))

			var/damage = rand(15,30)
			var/mob/living/carbon/human/H = M
			if(!istype(H))
				to_chat(H, SPAN_DANGER("You land heavily!"))
				M.adjustBruteLoss(damage)
				return

			var/obj/item/organ/external/affecting
			var/list/limbs = BP_ALL_LIMBS //sanity check, can otherwise be shortened to affecting = pick(BP_ALL_LIMBS)
			if(limbs.len)
				affecting = H.get_organ(pick(limbs))

			if(affecting)
				to_chat(M, SPAN_DANGER("You land heavily on your [affecting.name]!"))
				affecting.take_external_damage(damage, 0)
				if(affecting.parent)
					affecting.parent.add_autopsy_data("Misadventure", damage)
			else
				to_chat(H, SPAN_DANGER("You land heavily!"))
				H.adjustBruteLoss(damage)

			H.UpdateDamageIcon()
			H.updatehealth()
	return

/atom/MouseDrop_T(mob/target, mob/user)
	var/mob/living/H = user
	if(istype(H) && can_climb(H) && target == user)
		do_climb(target)
	else
		return ..()

/atom/proc/get_color()
	return isnull(color) ? COLOR_WHITE : color

/atom/proc/set_color(color)
	src.color = color

/atom/proc/get_cell()
	return

/atom/proc/slam_into(mob/living/L)
	L.Weaken(2)
	L.visible_message(SPAN_WARNING("\The [L] [pick("ran", "slammed")] into \the [src]!"))
	playsound(L, SFX_PUNCH, 25, 1, FALSE)
	show_sound_effect(L.loc, L)

/**
 * This proc is called when an atom in our contents has it's [Destroy][/atom/proc/Destroy] called
 */
/atom/proc/handle_atom_del(atom/deleting_atom)
	return

/// Return TRUE if things should be dropped onto this atom
/atom/proc/AllowDrop()
	return FALSE

///Where atoms should drop if taken from this atom
/atom/proc/drop_location()
	var/atom/location = loc
	if(!location)
		return null
	return location.AllowDrop() ? location : location.drop_location()

/**
 * This proc is used for telling whether something can pass by this atom in a given direction, for use by the pathfinding system.
 *
 * Trying to generate one long path across the station will call this proc on every single object on every single tile that we're seeing if we can move through, likely
 * multiple times per tile since we're likely checking if we can access said tile from multiple directions, so keep these as lightweight as possible.
 *
 * For turfs this will only be used if pathing_pass_method is TURF_PATHING_PASS_PROC
 *
 * Arguments:
 * * ID- An ID card representing what access we have (and thus if we can open things like airlocks or windows to pass through them). The ID card's physical location does not matter, just the reference
 * * to_dir- What direction we're trying to move in, relevant for things like directional windows that only block movement in certain directions
 * * caller- The movable we're checking pass flags for, if we're making any such checks
 * * no_id: When true, doors with public access will count as impassible
 *
 * IMPORTANT NOTE: /turf/proc/LinkBlockedWithAccess assumes that overrides of CanAStarPass will always return true if density is FALSE
 * If this is NOT you, ensure you edit your can_astar_pass variable. Check __DEFINES/path.dm
 **/
/atom/proc/CanPathingPass(obj/item/card/id/ID, to_dir, atom/movable/caller, no_id = FALSE)
	/*
	if(caller && (caller.pass_flags & pass_flags_self))
		return TRUE
	*/
	. = !density

/**
 * Hook for running code when a dir change occurs
 *
 * Not recommended to use, listen for the [COMSIG_ATOM_DIR_CHANGE] signal instead (sent by this proc)
 */
/atom/proc/setDir(newdir)
	//SHOULD_CALL_PARENT(TRUE)
	var/olddir = dir
	if (SEND_SIGNAL(src, COMSIG_ATOM_PRE_DIR_CHANGE, dir, newdir) & COMPONENT_ATOM_BLOCK_DIR_CHANGE)
		newdir = dir
		return
	dir = newdir
	SEND_SIGNAL(src, COMSIG_ATOM_DIR_CHANGE, olddir, dir)

/// Updates the description of the atom
/atom/proc/update_desc(updates=ALL)
	SHOULD_CALL_PARENT(TRUE)
	return SEND_SIGNAL(src, COMSIG_ATOM_UPDATE_DESC, updates)
