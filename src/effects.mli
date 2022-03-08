(****************************************************************************)
(*     Sail                                                                 *)
(*                                                                          *)
(*  Sail and the Sail architecture models here, comprising all files and    *)
(*  directories except the ASL-derived Sail code in the aarch64 directory,  *)
(*  are subject to the BSD two-clause licence below.                        *)
(*                                                                          *)
(*  The ASL derived parts of the ARMv8.3 specification in                   *)
(*  aarch64/no_vector and aarch64/full are copyright ARM Ltd.               *)
(*                                                                          *)
(*  Copyright (c) 2013-2021                                                 *)
(*    Kathyrn Gray                                                          *)
(*    Shaked Flur                                                           *)
(*    Stephen Kell                                                          *)
(*    Gabriel Kerneis                                                       *)
(*    Robert Norton-Wright                                                  *)
(*    Christopher Pulte                                                     *)
(*    Peter Sewell                                                          *)
(*    Alasdair Armstrong                                                    *)
(*    Brian Campbell                                                        *)
(*    Thomas Bauereiss                                                      *)
(*    Anthony Fox                                                           *)
(*    Jon French                                                            *)
(*    Dominic Mulligan                                                      *)
(*    Stephen Kell                                                          *)
(*    Mark Wassell                                                          *)
(*    Alastair Reid (Arm Ltd)                                               *)
(*                                                                          *)
(*  All rights reserved.                                                    *)
(*                                                                          *)
(*  This work was partially supported by EPSRC grant EP/K008528/1 <a        *)
(*  href="http://www.cl.cam.ac.uk/users/pes20/rems">REMS: Rigorous          *)
(*  Engineering for Mainstream Systems</a>, an ARM iCASE award, EPSRC IAA   *)
(*  KTF funding, and donations from Arm.  This project has received         *)
(*  funding from the European Research Council (ERC) under the European     *)
(*  Union’s Horizon 2020 research and innovation programme (grant           *)
(*  agreement No 789108, ELVER).                                            *)
(*                                                                          *)
(*  This software was developed by SRI International and the University of  *)
(*  Cambridge Computer Laboratory (Department of Computer Science and       *)
(*  Technology) under DARPA/AFRL contracts FA8650-18-C-7809 ("CIFV")        *)
(*  and FA8750-10-C-0237 ("CTSRD").                                         *)
(*                                                                          *)
(*  Redistribution and use in source and binary forms, with or without      *)
(*  modification, are permitted provided that the following conditions      *)
(*  are met:                                                                *)
(*  1. Redistributions of source code must retain the above copyright       *)
(*     notice, this list of conditions and the following disclaimer.        *)
(*  2. Redistributions in binary form must reproduce the above copyright    *)
(*     notice, this list of conditions and the following disclaimer in      *)
(*     the documentation and/or other materials provided with the           *)
(*     distribution.                                                        *)
(*                                                                          *)
(*  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS''      *)
(*  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED       *)
(*  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A         *)
(*  PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR     *)
(*  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,            *)
(*  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT        *)
(*  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF        *)
(*  USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND     *)
(*  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,      *)
(*  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT      *)
(*  OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF      *)
(*  SUCH DAMAGE.                                                            *)
(****************************************************************************)

(** In Sail, we need to distinguish between pure and impure
   (side-effecting) functions. This is because there are few places,
   such as top-level let-bindings and loop termination measures where
   side effects must clearly be forbidden. This module implements
   inference for which functions are pure and which are effectful, and
   checking the above purity restrictions. *)

open Ast
open Ast_defs
open Ast_util

(** A function is side-effectful if it throws an exception, can exit
   abnormally (either via an assertion failing or an explicit exit
   statement), contains a (possibly) incomplete pattern match, or
   touches a register. Finally, it is transitively side-effectful if
   it calls another function doing any of the above. *)
type side_effect

module EffectSet : sig
  include Set.S with type elt = side_effect
end

(* Note we intentionally keep the side effect type abstract, and
   expose some functions on effect sets based on what we actually
   need. *)
     
val throws : EffectSet.t -> bool

val pure : EffectSet.t -> bool

val effectful : EffectSet.t -> bool

(** Outcome identifiers correspond to the set of user-defined prompt
   monad constructors in the concurrency interface, replacing the
   various ad-hoc rmem, wmem, barrier, and so on effects in previous
   Sail versions. For example, using the concurrency interface in the Sail
   library, the equivalent to checking for the wmem effect would be:

   has_outcome (mk_id "sail_mem_write_request") effects
   *)
val has_outcome : id -> EffectSet.t -> bool

type side_effect_info = {
    functions : EffectSet.t Bindings.t;
    letbinds : EffectSet.t Bindings.t
  }

val function_is_pure : id -> side_effect_info -> bool
                      
val infer_side_effects : Type_check.tannot ast -> side_effect_info

(** Checks constraints on side effects, raising an error if they are
   violated. Currently these are that termination measures and
   top-level letbindings must be pure. *)
val check_side_effects : side_effect_info -> Type_check.tannot ast -> unit

val copy_function_effect : id -> side_effect_info -> id -> side_effect_info
  
(** Previous code mostly assumes that side effect info is attached to
   nodes in the AST. To keep this code working, this rewrite pass
   attaches effect info into to the AST. Note that the effect info is
   simplified in its annotated form - it just becomes a boolean
   representing effectful/non-effectful *)
val rewrite_attach_effects : side_effect_info -> Type_check.tannot ast -> Type_check.tannot ast