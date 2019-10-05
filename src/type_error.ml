(**************************************************************************)
(*     Sail                                                               *)
(*                                                                        *)
(*  Copyright (c) 2013-2017                                               *)
(*    Kathyrn Gray                                                        *)
(*    Shaked Flur                                                         *)
(*    Stephen Kell                                                        *)
(*    Gabriel Kerneis                                                     *)
(*    Robert Norton-Wright                                                *)
(*    Christopher Pulte                                                   *)
(*    Peter Sewell                                                        *)
(*    Alasdair Armstrong                                                  *)
(*    Brian Campbell                                                      *)
(*    Thomas Bauereiss                                                    *)
(*    Anthony Fox                                                         *)
(*    Jon French                                                          *)
(*    Dominic Mulligan                                                    *)
(*    Stephen Kell                                                        *)
(*    Mark Wassell                                                        *)
(*                                                                        *)
(*  All rights reserved.                                                  *)
(*                                                                        *)
(*  This software was developed by the University of Cambridge Computer   *)
(*  Laboratory as part of the Rigorous Engineering of Mainstream Systems  *)
(*  (REMS) project, funded by EPSRC grant EP/K008528/1.                   *)
(*                                                                        *)
(*  Redistribution and use in source and binary forms, with or without    *)
(*  modification, are permitted provided that the following conditions    *)
(*  are met:                                                              *)
(*  1. Redistributions of source code must retain the above copyright     *)
(*     notice, this list of conditions and the following disclaimer.      *)
(*  2. Redistributions in binary form must reproduce the above copyright  *)
(*     notice, this list of conditions and the following disclaimer in    *)
(*     the documentation and/or other materials provided with the         *)
(*     distribution.                                                      *)
(*                                                                        *)
(*  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS''    *)
(*  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED     *)
(*  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A       *)
(*  PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR   *)
(*  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,          *)
(*  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT      *)
(*  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF      *)
(*  USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND   *)
(*  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,    *)
(*  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT    *)
(*  OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF    *)
(*  SUCH DAMAGE.                                                          *)
(**************************************************************************)

open Util
open Ast
open Ast_util
open Type_check

type suggestion =
  | Suggest_add_constraint of n_constraint
  | Suggest_none

let analyze_unresolved_quant locals ncs = function
  | QI_aux (QI_constraint nc, _) ->
     let gen_kids = List.filter is_kid_generated (KidSet.elements (tyvars_of_constraint nc)) in
     if gen_kids = [] then
       Suggest_add_constraint nc
     else
       (* If there are generated kind-identifiers in the constraint,
          we don't want to make a suggestion based on them, so try to
          look for generated kid free nexps in the set of constraints
          that are equal to the generated identifier. This often
          occurs due to how the type-checker introduces new type
          variables. *)
       let is_subst v = function
         | NC_aux (NC_equal (Nexp_aux (Nexp_var v', _), nexp), _)
              when Kid.compare v v' = 0 && not (KidSet.exists is_kid_generated (tyvars_of_nexp nexp)) ->
            [(v, nexp)]
         | NC_aux (NC_equal (nexp, Nexp_aux (Nexp_var v', _)), _)
              when Kid.compare v v' = 0 && not (KidSet.exists is_kid_generated (tyvars_of_nexp nexp)) ->
            [(v, nexp)]
         | _ -> []
       in
       let substs = List.concat (List.map (fun v -> List.concat (List.map (fun nc -> is_subst v nc) ncs)) gen_kids) in
       let nc = List.fold_left (fun nc (v, nexp) -> constraint_subst v (arg_nexp nexp) nc) nc substs in
       if not (KidSet.exists is_kid_generated (tyvars_of_constraint nc)) then
         Suggest_add_constraint nc
       else
         (* If we have a really anonymous type-variable, try to find a
            regular variable that corresponds to it. *)
         let is_linked v = function
           | (id, (Immutable, (Typ_aux (Typ_app (ty_id, [A_aux (A_nexp (Nexp_aux (Nexp_var v', _)), _)]), _) as typ)))
                when Id.compare ty_id (mk_id "atom") = 0 && Kid.compare v v' = 0 ->
              [(v, nid id, typ)]
           | (id, (mut, typ)) ->
              []
         in
         let substs = List.concat (List.map (fun v -> List.concat (List.map (fun nc -> is_linked v nc) (Bindings.bindings locals))) gen_kids) in
         let nc = List.fold_left (fun nc (v, nexp, _) -> constraint_subst v (arg_nexp nexp) nc) nc substs in
         if not (KidSet.exists is_kid_generated (tyvars_of_constraint nc)) then
           Suggest_none
         else
           Suggest_none

  | QI_aux (QI_id _, _) | QI_aux (QI_constant _, _) ->
     Suggest_none

let message_of_type_error =
  let open Error_format in
  let rec msg = function
    | Err_because (err, l', err') ->
       Seq [msg err;
            Line "This error occured because of a previous error:";
            Location (l', msg err')]

    | Err_mapping (forwards_err, backwards_err) ->
       Seq [Line "Forwards mapping failed because:";
            With ((fun ppf -> { ppf with indent = ppf.indent ^ Util.("| " |> yellow |> clear) }), Seq [msg forwards_err]);
            Line "Backwards mapping failed because:";
            With ((fun ppf -> { ppf with indent = ppf.indent ^ Util.("| " |> yellow |> clear) }), Seq [msg backwards_err])]

    | Err_other str -> Line str

    | Err_no_overloading (id, errs) ->
       Seq [Line ("No overloading for " ^ string_of_id id ^ ", tried:");
            List (List.map (fun (id, err) -> string_of_id id, msg err) errs)]

    | Err_unresolved_quants (id, quants, locals, ncs) ->
       Seq [Line ("Could not resolve quantifiers for " ^ string_of_id id);
            Line (bullet ^ " " ^ Util.string_of_list ("\n" ^ bullet ^ " ") string_of_quant_item quants)]

    | Err_subtype (typ1, typ2, _, vars) ->
       let vars = KBindings.bindings vars in
       let vars = List.filter (fun (v, _) -> KidSet.mem v (KidSet.union (tyvars_of_typ typ1) (tyvars_of_typ typ2))) vars in
       With ((fun ppf -> { ppf with loc_color = Util.yellow }),
             Seq (Line (string_of_typ typ1 ^ " is not a subtype of " ^ string_of_typ typ2)
                  :: List.map (fun (kid, l) -> Location (l, Line (string_of_kid kid ^ " bound here"))) vars))

  | Err_no_num_ident id ->
     Line ("No num identifier " ^ string_of_id id)

  | Err_no_casts (exp, typ_from, typ_to, trigger, reasons) ->
     let coercion =
       Line ("Tried performing type coercion from " ^ string_of_typ typ_from
             ^ " to " ^ string_of_typ typ_to
             ^ " on " ^ string_of_exp exp)
     in
     Seq ([coercion; Line "Coercion failed because:"; msg trigger]
          @ if not (reasons = []) then
              Line "Possible reasons:" :: List.map msg reasons
            else
              [])

  | Err_pattern_id id ->
     Line ("Type of identifier " ^ string_of_id id ^ " could not be inferred in pattern")
  in
  msg

let string_of_type_error err =
  let open Error_format in
  let b = Buffer.create 20 in
  format_message (message_of_type_error err) (buffer_formatter b);
  Buffer.contents b

let rec collapse_errors = function
  | (Err_no_overloading (_, errs) as no_collapse) ->
     let errs = List.map (fun (_, err) -> collapse_errors err) errs in
     let interesting = function
       | Err_other _ -> false
       | Err_no_casts _ -> false
       | _ -> true
     in
     begin match List.filter interesting errs with
     | err :: errs ->
        let fold_equal msg err =
          match msg, err with
          | Some msg, Err_no_overloading _ -> Some msg
          | Some msg, Err_no_casts _ -> Some msg
          | Some msg, err when msg = string_of_type_error err -> Some msg
          | _, _ -> None
        in
        begin match List.fold_left fold_equal (Some (string_of_type_error err)) errs with
        | Some _ -> err
        | None -> no_collapse
        end
     | [] -> no_collapse
     end
  | Err_because (err1, l, err2) as no_collapse ->
     let err1 = collapse_errors err1 in
     let err2 = collapse_errors err2 in
     if string_of_type_error err1 = string_of_type_error err2 then
       err1
     else
       Err_because (err1, l, err2)
  | err -> err

let check : 'a. Env.t -> 'a defs -> tannot defs * Env.t =
  fun env defs ->
  try Type_check.check env defs with
  | Type_error (env, l, err) ->
     Interactive.env := env;
     raise (Reporting.err_typ l (string_of_type_error err))
