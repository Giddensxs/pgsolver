open Basics;;
open Paritygame;;
open Solvers;;
open Univsolve;;
open Transformations;;
open Tcsset;;
open Tcsarray;;
open Tcslist;;
open Tcsstrings;;
open Tcsbasedata;;
open Tcsgraph;;
open Tcsmaths;;
open Arg;;
open Tcsargs;;


let array_max a less = ArrayUtils.max_elt (fun x y -> if less x y then -1 else 1) a
let list_max a less = ListUtils.max_elt (fun x y -> if less x y then -1 else 1) a


let enable_exp_bit_count = ref false

let last_exp_bit_count = ref 0

let get_last_exp_bit_count _ = !last_exp_bit_count

let last_iteration_count = ref 0

let get_last_iteration_count _ = !last_iteration_count

let _strat_impr_callback = ref None


type node_valuation = int * int TreeSet.t * int

type game_valuation = node_valuation array

type initial_strategy_fun = paritygame -> strategy

type node_total_ordering_fun = paritygame -> int -> int -> int

type 'a improvement_policy_fun = paritygame -> node_total_ordering_fun -> 'a -> strategy -> game_valuation -> strategy * 'a

let format_node_valuation (a, b, c) =
    let t = TreeSet.fold (fun el s -> s ^ (string_of_int el) ^", ") b "" in
    (string_of_int a) ^ " [" ^ t ^ "] " ^ (string_of_int c)

let format_game_valuation valu =
    let s = ref "" in
    for i = 0 to Array.length valu - 1 do
        s := !s ^ format_node_valuation valu.(i) ^ "\n"
    done;
    !s

let flip f x y = f y x

let tuple_total_ordering cmp f (x, r) (y, s) =
	let c = cmp x y in
	if c = 0 then f r s else c

let node_total_ordering_by_position _ i j =
	compare i j

let node_total_ordering_by_priority_and_position game i j =
	tuple_total_ordering compare compare (pg_get_pr game i, i) (pg_get_pr game j, j)

let relevance_total_ordering game node_total_ordering i j =
	tuple_total_ordering compare (node_total_ordering game) (pg_get_pr game i, i) (pg_get_pr game j, j)

let reward_total_ordering game node_total_ordering i j =
	let ri = reward 0 (pg_get_pr game i) in
	let rj = reward 0 (pg_get_pr game j) in
	let c = compare ri rj in
	if c != 0 then c
	else node_total_ordering game (if ri mod 2 = 0 then i else j) (if ri mod 2 = 0 then j else i)

let initial_strategy_by_first_edge game =
	Array.init (Array.length game) (fun i ->
		let (pr, pl, tr, _) = game.(i) in
		if (pr < 0) || (pl = 1) || (Array.length tr = 0) then -1 else tr.(0)
	)

let initial_strategy_by_last_edge game =
	Array.init (Array.length game) (fun i ->
		let (pr, pl, tr, _) = game.(i) in
		if (pr < 0) || (pl = 1) || (Array.length tr = 0) then -1 else tr.(Array.length tr - 1)
	)

let initial_strategy_by_random_edge game =
	Random.self_init ();
	Array.init (Array.length game) (fun i ->
		let (pr, pl, tr, _) = game.(i) in
		if (pr < 0) || (pl = 1) || (Array.length tr = 0) then -1 else tr.(Random.int (Array.length tr))
	)

let initial_strategy_by_best_reward game =
	Array.init (Array.length game) (fun i ->
		let (pr, pl, tr, _) = game.(i) in
		if (pr < 0) || (pl = 1) || (Array.length tr = 0) then -1
		else array_max tr (fun i j -> reward_total_ordering game node_total_ordering_by_position i j <= 0)
	)

let empty_descending_relevance_ordered_set game node_total_ordering =
	TreeSet.empty (flip (relevance_total_ordering game node_total_ordering))

let node_valuation_ordering game node_total_ordering (u, p, e) (v, q, f) =
    let is_odd x = pg_get_pr game x mod 2 = 1 in
    let is_even x = pg_get_pr game x mod 2 = 0 in
	let cycle_ordering = reward_total_ordering game node_total_ordering in
	let length_ordering (u, e) (v, f) =
		if e = f then 0
		else if ((is_odd v) && e < f) || ((is_even v) && e > f) then -1 else 1 in
	let path_ordering p q =
		let r = TreeSet.sym_diff p q in
		if TreeSet.cardinal r = 0 then 0
		else let w = TreeSet.min_elt r in
		     if ((is_even w) && TreeSet.mem w q) || ((is_odd w) && TreeSet.mem w p) then -1 else 1
    in
    tuple_total_ordering cycle_ordering
    	                 (tuple_total_ordering path_ordering length_ordering)
    	                 (u, (p, (u, e))) (v, (q, (v, f)))

let node_valuation_total_ordering game node_total_ordering valu x y =
	tuple_total_ordering (node_valuation_ordering game node_total_ordering)
						 (node_total_ordering game)
						 (valu.(x), x) (valu.(y), y)

let best_decision_by_ordering game ordering v =
	let ordering x y = ordering x y >= 0 in
    let (_, pl, tr, _) = game.(v) in
    array_max tr (fun x y -> if pl = 1 then ordering x y else ordering y x)

let best_decision_by_valuation_ordering game node_total_ordering valu v =
	best_decision_by_ordering game (node_valuation_total_ordering game node_total_ordering valu) v

let strategy_improvable game node_total_ordering strat valu =
    ArrayUtils.exists strat (fun i j ->
        (pg_get_pl game i = 0) &&
        (node_valuation_ordering game node_total_ordering valu.(j)
        						 valu.(best_decision_by_valuation_ordering game node_total_ordering valu i) < 0)
    )

let winning_regions game valu =
    Array.init (Array.length valu) (fun i ->
        let (v, _, _) = valu.(i) in
        pg_get_pr game v mod 2
    )

let winning_strategies game node_total_ordering strat valu =
    Array.init (Array.length valu) (fun i ->
        let (v, _, _) = valu.(i) in
        let winner = pg_get_pr game v mod 2 in
        let player = pg_get_pl game i in
        if winner = player
        then if player = 0 then strat.(i)
             else best_decision_by_valuation_ordering game node_total_ordering valu i
        else -1
    )

let evaluate_strategy game node_total_ordering strat =
	let n = Array.length game in
	let graph = paritygame_to_dynamic_paritygame_by_strategy game strat in
	let asc_rew = DynamicGraph.add_cmp (reward_total_ordering game node_total_ordering) graph in
	let rel_ord = relevance_total_ordering game node_total_ordering in
	let des_rel = DynamicGraph.add_cmp (flip rel_ord) graph in
	let valu = Array.make n (-1, empty_descending_relevance_ordered_set game node_total_ordering, 0) in

	DynamicGraph.iter_by (fun v ->
		let (w, _, _) = valu.(v) in
		if (w = -1) && (DynamicGraph.depth_find v (fun u -> rel_ord u v <= 0)
		                                          (fun u -> DynamicGraph.has_edge u v graph)
		                                          graph) then (
			let graph' = DynamicGraph.sub_graph_by_node_closure v (fun u f -> TreeSet.iter f (DynamicGraph.get_node_pred u graph)) graph in
			let del_other_edges x m =
				TreeSet.iter (fun y ->
					if not (TreeSet.mem y m) then DynamicGraph.del_edge x y graph'
				) (DynamicGraph.get_node_succ x graph')
			in
			DynamicGraph.iter (fun u _ -> valu.(u) <- (v, empty_descending_relevance_ordered_set game node_total_ordering, 0)) graph';
			DynamicGraph.iter_by (fun u ->
				if rel_ord u v > 0 then (
					if pg_get_pr game u mod 2 = 0 then (
						let m = GraphUtils.build_reachability_set (v, (fun x -> TreeSet.to_iterator (TreeSet.filter ((!=) u) (DynamicGraph.get_node_pred x graph')))) in
						DynamicGraph.iter (fun q _ ->
							if not (TreeSet.mem q m)
							then let (a, b, c) = valu.(q) in
								 valu.(q) <- (a, TreeSet.add u b, c)
						) graph';
						del_other_edges u m;
						TreeSet.iter (fun q -> del_other_edges q m) m
					)
					else (
						let m = GraphUtils.build_reachability_set (u, (fun x -> TreeSet.to_iterator (TreeSet.filter ((!=) v) (DynamicGraph.get_node_pred x graph')))) in
						TreeSet.iter (fun q ->
							let (a, b, c) = valu.(q) in
							valu.(q) <- (a, TreeSet.add u b, c)
						) m;
						TreeSet.iter (fun x ->
							if not (x = u) then del_other_edges x m
						) m
					)
				)
			) des_rel graph';
			let f n i = let (p0, p1, _) = valu.(n) in valu.(n) <- (p0, p1, i) in
			if pg_get_pr game v mod 2 = 0
            then GraphUtils.iterate_with_maximal_distance_single_loop (v, (fun x -> TreeSet.to_iterator (DynamicGraph.get_node_pred x graph')),
                                                                       (fun x -> TreeSet.to_iterator (DynamicGraph.get_node_succ x graph'))) f
            else GraphUtils.iterate_with_minimal_distance (v, (fun x -> TreeSet.to_iterator (DynamicGraph.get_node_pred x graph'))) f;
			DynamicGraph.iter (fun u _ -> DynamicGraph.del_node u graph) graph'
		)
	) asc_rew graph;
	valu

let compute_counter_strategy game strategy = 
	let valu = evaluate_strategy game node_total_ordering_by_position strategy in
	Array.init (Array.length valu) (fun i ->
		if pg_get_pl game i = 0
		then -1
		else best_decision_by_valuation_ordering game node_total_ordering_by_position valu i
	)

let less_valuation val_comp v u =
	let res = ref false in
	let fin = ref false in
	let n = Array.length v in
	let i = ref 0 in
	while (!i < n) && (not !fin) do
		let c = val_comp v.(!i) u.(!i) in
		if c > 0 then (
			res := false;
			fin := true
		)
		else if c < 0 then (
			res := true
		);
		incr i
	done;
	!res

(* TEST *)
(*
let format_game_state game valu =

    let lookup_node s =
        let check i =
            match (pg_get_desc game i) with
                None -> false
            |   Some t -> s=t
        in
        let i = ref 0 in
        let n = Array.length game in
        while (!i < n) && (not (check !i)) do
            incr i
        done;
        if !i < n then Some !i else None
    in

    let l = ref [] in
    let i = ref (-1) in
    let go = ref true in

   *)
let format_game_state game valu =

    let lookup_node s =
        let check i =
            match (pg_get_desc game i) with
                None -> false
            |   Some t -> s=t
        in
        let i = ref 0 in
        let n = Array.length game in
        while (!i < n) && (not (check !i)) do
            incr i
        done;
        if !i < n then Some !i else None
    in

    let l = ref [] in
    let i = ref (-1) in
    let go = ref true in

	if lookup_node "e0" = None then (
	    let u0 = lookup_node "k0" in
	    match u0 with
	    	Some d -> (
			    let (_, vald, _) = valu.(d) in
			    while !go do
			    	incr i;
			    	match (lookup_node ("k" ^ string_of_int !i)) with
			    		Some e -> (
			    			l := (if TreeSet.mem e vald then 1 else 0)::!l
			    		)
			    	|	None -> go := false
			    done
			   )
		|	_ -> ()
	)
	else (
	    while !go do
	    	incr i;
	    	match (lookup_node ("e" ^ string_of_int !i)) with
	    		Some e -> (
	    			match (lookup_node ("d(0,0,0)")) with
	    				Some _ -> (
		                let go2 = ref true in
		                let j = ref 0 in
		                let k = ref (-1) in
		                let pass = ref true in
		                while !go2 && !pass do
		                    incr k;
		                    match (lookup_node ("d(" ^ string_of_int !i ^ ","^string_of_int !j^","^string_of_int !k^ ")")) with
		                    	Some d -> (
		                    		let (_, vald, _) = valu.(d) in
		                    		pass := TreeSet.mem e vald;
		                    		go2 := !pass
		                    	)
		                    |	_ -> (
		                    	if !k = 0 then go2 := false else (k := -1; incr j)
		                    )
		                done;
		            	l := (if !pass then 1 else 0)::!l
	    				)
	    			|	None -> (
						match (lookup_node "d0") with
							Some _ -> (
								let pass = ref false in
								(
								match (lookup_node ("d" ^ string_of_int !i)) with
									Some d -> (
										let (_, vald, _) = valu.(d) in
										pass := TreeSet.mem e vald;
									)
								|	_ -> ();
								);
								l := (if !pass then 1 else 0)::!l
							)
						|	None -> (
		                let go2 = ref true in
		                let j = ref (-1) in
		                let pass = ref true in
		                while !go2 && !pass do
		                    incr j;
		                    match (lookup_node ("d(" ^ string_of_int !i ^ ","^string_of_int !j^ ")")) with
		                    	Some d -> (
		                    		let (_, vald, _) = valu.(d) in
		                    		pass := TreeSet.mem e vald;
		                    		go2 := !pass
		                    	)
		                    |	_ -> go2 := false
		                done;
		            	l := (if !pass then 1 else 0)::!l
		            ))
	    		)
	    	|	_ -> go := false
	    done
	);

(*
    let l' = ref [] in
    let i = ref (-1) in
    let go = ref true in

    while !go do
    	incr i;
    	match (lookup_node ("e" ^ string_of_int !i), lookup_node ("h" ^ string_of_int !i)) with
    		(Some e, Some h) -> (
    			let (_, vale, _) = valu.(e) in
	    		l' := (if TreeSet.mem h vale then 1 else 0)::!l'
    		)
    	|	_ -> go := false;
    done;

    let upl = ref [] in
    let i = ref (-1) in
    let go = ref true in

    while !go do
    	incr i;
    	match (lookup_node ("k" ^ string_of_int !i)) with
    		Some k -> (
    			let (_, valk, _) = valu.(k) in
    			let x = ref (0) in
    			let j = ref !i in
    			let go2 = ref true in
    			while !go2 do
    				incr j;
    				match (lookup_node ("f" ^ string_of_int !j)) with
    					Some f -> (
    						if TreeSet.mem f valk then (
    							x := !j;
    							go2 := false
    						)
    					)
    				| _ -> go2 := false
    			done;
    			upl := (!i, !x)::!upl
    		)
    	|	_ -> go := false
    done;
*)
     let v = ref 0 in

    let u = List.map (fun b ->
    	v := 2 * !v;
    	if b=1 then incr v;
    	if b=1 then "1" else "0"
    ) !l in
(*
    let w = List.map (fun (_, h) ->
    	string_of_int h
    ) !upl in

    let l = ref [] in
    let i = ref (-1) in
    let go = ref true in
    while !go do
    	incr i;
    	match (lookup_node ("f" ^ string_of_int !i)) with
    		Some f -> l := (!i, f)::!l
    	|	None -> go := false
    done;

    let cmp = (fun (_, f) (_, f') -> (node_valuation_ordering game (node_total_ordering_by_position) valu.(f') valu.(f))) in
    let a = Array.of_list !l in
    Array.sort cmp a;
    let s = ListUtils.format (fun (i, _) -> string_of_int i) (Array.to_list a) in

    let s' = ListUtils.format string_of_int !l' in

    (("[" ^ String.concat "," u ^ "]" ^ " / [" ^ String.concat "," w ^ "]" ^ " / " ^ s ^ " / " ^ s'), !v)
*)
    (("[" ^ String.concat "," u ^ "]"), !v)


let transform_game_state_list l =
	let t = ref [] in
	let l = ref l in
	let v = ref (-1) in
	while !l != [] do
		let (s, v') = List.hd !l in
		l := List.tl !l;
		if (!v < 0) || (v' < !v) then (
			v := v';
			t := (s, v')::!t
		)
	done;
	!t


(* TEST *)


let strategy_improvement (game: paritygame)
						 (init_strat: initial_strategy_fun)
						 (node_compare: node_total_ordering_fun)
						 (impr_policy: 'a improvement_policy_fun)
						 (impr_policy_init: 'a)
						 (check_policy: bool)
						 (ident: string) =

    let msg_tagged v = message_autotagged v (fun _ -> ident) in
    let msg_tagged_nl v = message_autotagged_newline v (fun _ -> ident) in
    let msg_plain = message in

    msg_tagged 2 (fun _ -> "Starting strategy improvement algorithm\n");
    if !verbosity > 2 then (
	    msg_tagged_nl 3 (fun _ -> "Considering game:\n" ^ game_to_string game ^ "\n")
	);

	let impr_data = ref impr_policy_init in
	let improve x y =
		let (strat, impr) = impr_policy game node_compare !impr_data x y in
		impr_data := impr;
		strat
	in
	let evaluate = evaluate_strategy game node_compare in
	let improvable = strategy_improvable game node_compare in

    let counter = ref 0 in

	let strat = ref (init_strat game) in
    let valu = ref (evaluate !strat) in

	let rec get_desc game o i =
		match pg_get_desc game i with Some s -> s | None -> ""
	in
    let show_eval _ =
        if !verbosity > 2 then (

            let g = subgame_by_edge_pred game (fun u v -> (!strat).(u) = -1 || (!strat).(u) = v) in
            for i = 0 to Array.length game - 1 do
                pg_set_desc g i (Some (string_of_int i ^ " : " ^ format_node_valuation (!valu).(i)))
            done;
(*            msg_tagged_nl 3 (fun _ -> "\nMade valuation:\n" ^ game_to_string g ^ "\n"); *)

			let myfmt game strat =
				let a =	Array.mapi (fun i j -> if (j >= 0) && (Array.length (pg_get_tr game i) > 1) then get_desc game i i ^ "->" ^ get_desc game j j else "") strat in
				let b = List.filter (fun s -> not (s = "" || s = "->")) (Array.to_list a) in
				ListUtils.format (fun s -> s) (List.sort compare b)
			in
            msg_tagged_nl 3 (fun _ -> "0-Strategy: " ^ myfmt game !strat ^ "\n");
			let strat' = Array.mapi (fun i j ->
				if j < 0 then best_decision_by_valuation_ordering game node_compare !valu i else -1
			) !strat in
            msg_tagged_nl 3 (fun _ -> "1-Strategy: " ^ myfmt game strat' ^ "\n");
			let impr = ref [] in
			Array.iteri (fun i j ->
				if j != -1 then Array.iter (fun k ->
					if node_valuation_ordering game node_compare !valu.(j) !valu.(k) < 0
					then impr := (i,k)::!impr
				) (pg_get_tr game i)
			) !strat;
			msg_tagged_nl 3 (fun _ -> "Improvement-Arena: " ^ ListUtils.format (fun (i,j) -> get_desc game i i ^ "->" ^ get_desc game j j) (List.sort compare !impr) ^ "\n")
        )
    in
	let show_changed oldstrat newstrat =
		if !verbosity > 2 then (
			let l = ref [] in
			Array.iteri (fun i j ->
				if newstrat.(i) != j then l := (i,j,newstrat.(i))::!l
			) oldstrat;
			msg_tagged_nl 3 (fun _ -> "Strategy-Change: " ^ ListUtils.format (fun (i,j,k) -> get_desc game i i ^ "->" ^ get_desc game j j ^ "/" ^ get_desc game k k) (List.sort compare !l) ^ "\n")
		)
	in

	(* TEST *)
	let old = ref (-1) in
	let t = ref "" in
	let l = ref [] in
	(* TEST *)

    while (improvable !strat !valu) do
    	show_eval ();
        incr counter;

        msg_tagged 2 (fun _ -> "Iteration: " ^ string_of_int !counter ^ "\r");
		
		(
		match !_strat_impr_callback with
			None -> ()
		|	Some c -> c !strat !counter
		);

        (* TEST *)
        if !enable_exp_bit_count then (
            let (s, v) = format_game_state game !valu in
            let s = string_of_int !counter ^ " : " ^ s in
			msg_tagged_nl 3 (fun _ -> "\nIteration: " ^ s ^ "\n");
            if (!old != v) || (!t <> s) then l := (s, v)::!l;
            t := s;
            old := v
        );
        (* TEST *)

		let old = !strat in
        strat := improve !strat !valu;
		show_changed old !strat;
        let valu' = evaluate !strat in
        if check_policy && (not (less_valuation (node_valuation_ordering game node_compare) !valu valu')) then (
	        valu := valu';
        	show_eval ();
        	failwith "valuation improvement failure"
        );
        valu := valu'
    done;

    incr counter;
	(
	match !_strat_impr_callback with
		None -> ()
	|	Some c -> c !strat !counter
	);
    
    (* TEST *)
    if !enable_exp_bit_count then (
        let (s, v) = format_game_state game !valu in
        let s = string_of_int !counter ^ " : " ^ s in
		msg_tagged_nl 3 (fun _ -> "\nIteration: " ^ s ^ "\n");
        if (!old != v) || (!t <> s) then l := (s, v)::!l;
        t := s;
        old := v
    );
    (* TEST *)

    show_eval ();
    last_iteration_count := !counter;

    msg_plain 2 (fun _ -> "\n");

    (*TEST*)
    if !enable_exp_bit_count then (

        (*
        List.iter (fun (s, v) -> msg_tagged 2 (fun _ -> s ^ " = " ^ string_of_int v ^ "\n")) (List.rev !l);
        *)

        let l = transform_game_state_list !l in

        (*
        List.iter (fun (s, v) -> msg_tagged 2 (fun _ -> s ^ " = " ^ string_of_int v ^ "\n")) l;
        *)

        last_exp_bit_count := List.length l;
        msg_tagged 2 (fun _ -> "Bit Rounds: " ^ string_of_int !last_exp_bit_count ^ "\n")
    );
    (*TEST*)

	(winning_regions game !valu, winning_strategies game node_compare !strat !valu)




let strategy_improvement' (game: paritygame)
						  (init_strat: initial_strategy_fun)
						  (node_compare: node_total_ordering_fun)
						  (impr_policy: 'a improvement_policy_fun)
						  (impr_policy_init: 'a)
						  (check_policy: bool)
						  (ident: string) =
	let game' = alternating_transformation game true in
	let game'' = cheap_escape_cycles_transformation game' false in
	let (sol'', strat'') = strategy_improvement game'' init_strat node_compare impr_policy impr_policy_init check_policy ident in
	let sol = Array.init (Array.length game') (fun i -> sol''.(i)) in
	let strat = Array.init (Array.length game') (fun i -> strat''.(i)) in
	let (sol', strat') = alternating_revertive_restriction game game' sol strat in
	for i = 0 to Array.length game - 1 do
		let (_, pl, _, _) = game.(i) in
		if sol'.(i) != pl then strat'.(i) <- -1
	done;
	(sol', strat');;

let strategy_improvement'' (game: paritygame)
						  (init_strat: initial_strategy_fun)
						  (node_compare: node_total_ordering_fun)
						  (impr_policy: 'a improvement_policy_fun)
						  (impr_policy_init: (paritygame -> 'a))
						  (check_policy: bool)
						  (ident: string) =
	let game' = cheap_escape_cycles_transformation game false in
	let (sol', strat') = strategy_improvement game' init_strat node_compare impr_policy (impr_policy_init game') check_policy ident in
	let sol = Array.init (Array.length game) (fun i -> sol'.(i)) in
	let strat = Array.init (Array.length game) (fun i -> strat'.(i)) in
	(sol, strat);;

let improvement_policy_no_user_data imprpolicy = fun g o u s v -> (imprpolicy g o s v, u);;




let strategy_improvement_by_policy game impr_policy impr_policy_init check_policy ident =
	strategy_improvement' game initial_strategy_by_last_edge node_total_ordering_by_position impr_policy impr_policy_init check_policy ident




let subsolvermap = ref TreeMap.empty_def;;

let register_sub_solver solver_func identifier abbreviation description =
	if TreeMap.mem identifier !subsolvermap
	then failwith ("Solver `" ^ identifier ^ "' already registered!\n")
	else subsolvermap := TreeMap.add identifier (solver_func, abbreviation, description) !subsolvermap;;

let mem_sub_solver identifier = TreeMap.mem identifier !subsolvermap;;

let find_sub_solver identifier = TreeMap.find identifier !subsolvermap;;

let enum_sub_solvers it = TreeMap.iter (fun i (f, a, d) -> it f i a d) !subsolvermap;;

let fold_sub_solvers fo b = TreeMap.fold (fun i (f, a, d) x -> fo f i a d x) !subsolvermap b;;



let improvement_policy_optimize_all_locally game node_total_ordering old_strategy valu =
	Array.mapi (fun i j ->
		if j = -1 then -1
		else let k = best_decision_by_valuation_ordering game node_total_ordering valu i in
			 if node_valuation_ordering game node_total_ordering valu.(j) valu.(k) < 0
			 then k
			 else j
	) old_strategy

let strategy_improvement_optimize_all_locally_policy game =
	strategy_improvement game initial_strategy_by_best_reward node_total_ordering_by_position (improvement_policy_no_user_data improvement_policy_optimize_all_locally) () false "STRIMPR_LOCOPT";;


register_sub_solver
	(fun g -> universal_solve (universal_solve_init_options_verbose !universal_solve_global_options) strategy_improvement_optimize_all_locally_policy g)
	"switchall" "sa" "standard switch all policy iteration";;




module CommandLine = struct
  let solve = ref (fun g -> universal_solve (universal_solve_init_options_verbose !universal_solve_global_options) strategy_improvement_optimize_all_locally_policy g)
  
  let speclist _ = fold_sub_solvers (fun solve' ident abbrev desc t ->
                          (["--" ^ ident; "-" ^ abbrev], Unit (fun _ -> solve := solve'), "\n     " ^ desc)::t) []
  
  let parse s = 
  	SimpleArgs.parsearr s (speclist ()) (fun _ -> ()) "Policy Iteration Algorithm\n" SimpleArgs.argprint_help SimpleArgs.argprint_bad;
  	!solve

end ;;


open CommandLine ;;



let _ = register_solver_factory (fun s -> parse s) "policyiter" "pi" "use policy iteration (see additional args)";;

