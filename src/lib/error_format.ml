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

let rec skip_lines in_chan = function
  | n when n <= 0 -> ()
  | n -> ignore (input_line in_chan); skip_lines in_chan (n - 1)

let rec read_lines in_chan = function
  | n when n <= 0 -> []
  | n ->
     let l = input_line in_chan in
     let ls = read_lines in_chan (n - 1) in
     l :: ls

type formatter = {
    indent : string;
    endline : string -> unit;
    loc_color : string -> string
  }

let err_formatter = {
    indent = "";
    endline = prerr_endline;
    loc_color = Util.red
  }

let buffer_formatter b = {
    indent = "";
    endline = (fun str -> Buffer.add_string b (str ^ "\n"));
    loc_color = Util.red
  }

let format_endline str ppf = ppf.endline (ppf.indent ^ (Str.global_replace (Str.regexp_string "\n") ("\n" ^ ppf.indent) str))

let underline_single color cnum_from cnum_to =
  if (cnum_from + 1) >= cnum_to then
    Util.(String.make cnum_from ' ' ^ clear (color "^"))
  else
    Util.(String.make cnum_from ' ' ^ clear (color ("^" ^ String.make (cnum_to - cnum_from - 2) '-' ^ "^")))

let format_code_single' prefix fname in_chan lnum cnum_from cnum_to contents ppf =
  skip_lines in_chan (lnum - 1);
  let line = input_line in_chan in
  let line_prefix = string_of_int lnum ^ Util.(clear (cyan " |")) in
  let blank_prefix = String.make (String.length (string_of_int lnum)) ' ' ^ Util.(clear (ppf.loc_color " |")) in
  format_endline (Printf.sprintf "%s[%s]:%d:%d-%d" prefix Util.(fname |> cyan |> clear) lnum cnum_from cnum_to) ppf;
  format_endline (line_prefix ^ line) ppf;
  format_endline (blank_prefix ^ underline_single ppf.loc_color cnum_from cnum_to) ppf;
  contents { ppf with indent = blank_prefix ^ " " }

let underline_double_from color cnum_from eol =
  Util.(String.make cnum_from ' ' ^ clear (color ("^" ^ String.make (eol - cnum_from - 1) '-')))

let underline_double_to color cnum_to =
  if cnum_to = 0 then
    Util.(clear (color "^"))
  else
    Util.(clear (color (String.make (cnum_to - 1) '-' ^ "^")))

let format_code_double' prefix fname in_chan lnum_from cnum_from lnum_to cnum_to contents ppf =
  skip_lines in_chan (lnum_from - 1);
  let line_from = input_line in_chan in
  skip_lines in_chan (lnum_to - lnum_from - 1);
  let line_to = input_line in_chan in
  let line_to_prefix = string_of_int lnum_to ^ Util.(clear (cyan " |")) in
  let line_from_padding = String.make (String.length (string_of_int lnum_to) - String.length (string_of_int lnum_from)) ' ' in
  let line_from_prefix = string_of_int lnum_from ^ line_from_padding ^ Util.(clear (cyan " |")) in
  let blank_prefix = String.make (String.length (string_of_int lnum_to)) ' ' ^ Util.(clear (ppf.loc_color " |")) in
  format_endline (Printf.sprintf "%s[%s]:%d:%d-%d:%d" prefix Util.(fname |> cyan |> clear) lnum_from cnum_from lnum_to cnum_to) ppf;
  format_endline (line_from_prefix ^ line_from) ppf;
  format_endline (blank_prefix ^ underline_double_from ppf.loc_color cnum_from (String.length line_from)) ppf;
  format_endline (line_to_prefix ^ line_to) ppf;
  format_endline (blank_prefix ^ underline_double_to ppf.loc_color cnum_to) ppf;
  contents { ppf with indent = blank_prefix ^ " " }

let format_code_single_fallback prefix fname lnum cnum_from cnum_to contents ppf =
  let blank_prefix = String.make (String.length (string_of_int lnum)) ' ' ^ Util.(clear (ppf.loc_color " |")) in
  format_endline (Printf.sprintf "%s[%s]:%d:%d-%d" prefix Util.(fname |> cyan |> clear) lnum cnum_from cnum_to) ppf;
  contents { ppf with indent = blank_prefix ^ " " }
  
let format_code_single prefix fname lnum cnum_from cnum_to contents ppf =
  try
    let in_chan = open_in fname in
    begin
      try format_code_single' prefix fname in_chan lnum cnum_from cnum_to contents ppf; close_in in_chan
      with
      | _ ->
         format_code_single_fallback prefix fname lnum cnum_from cnum_to contents ppf;
         close_in_noerr in_chan
    end
  with
  | _ -> format_code_single_fallback prefix fname lnum cnum_from cnum_to contents ppf

let format_code_double_fallback prefix fname lnum_from cnum_from lnum_to cnum_to contents ppf =
  let blank_prefix = String.make (String.length (string_of_int lnum_to)) ' ' ^ Util.(clear (ppf.loc_color " |")) in
  format_endline (Printf.sprintf "%s[%s]:%d:%d-%d:%d" prefix Util.(fname |> cyan |> clear) lnum_from cnum_from lnum_to cnum_to) ppf;
  contents { ppf with indent = blank_prefix ^ " " }
       
let format_code_double prefix fname lnum_from cnum_from lnum_to cnum_to contents ppf =
  try
    let in_chan = open_in fname in
    begin
      try format_code_double' prefix fname in_chan lnum_from cnum_from lnum_to cnum_to contents ppf; close_in in_chan
      with
      | _ ->
         format_code_double_fallback prefix fname lnum_from cnum_from lnum_to cnum_to contents ppf;
         close_in_noerr in_chan
    end
  with
  | _ -> format_code_double_fallback prefix fname lnum_from cnum_from lnum_to cnum_to contents ppf

let format_pos prefix p1 p2 contents ppf =
  let open Lexing in
  if p1.pos_lnum == p2.pos_lnum
  then format_code_single prefix p1.pos_fname p1.pos_lnum (p1.pos_cnum - p1.pos_bol) (p2.pos_cnum - p2.pos_bol) contents ppf
  else format_code_double prefix p1.pos_fname p1.pos_lnum (p1.pos_cnum - p1.pos_bol) p2.pos_lnum (p2.pos_cnum - p2.pos_bol) contents ppf

let rec format_loc prefix l contents =
  match l with
  | Parse_ast.Unknown -> contents
  | Parse_ast.Range (p1, p2) -> format_pos prefix p1 p2 contents
  | Parse_ast.Unique (_, l) -> format_loc prefix l contents
  | Parse_ast.Documented (_, l) -> format_loc prefix l contents
  | Parse_ast.Generated l ->
     fun ppf -> (format_endline "Code generated nearby:" ppf; format_loc prefix l contents ppf)

type message =
  | Location of string * Parse_ast.l * message
  | Line of string
  | List of (string * message) list
  | Seq of message list
  | With of (formatter -> formatter) * message

let bullet = Util.(clear (blue "*"))

let rec format_message msg ppf =
  match msg with
  | Location (prefix, l, msg) ->
     format_loc prefix l (format_message msg) ppf
  | Line str ->
     format_endline str ppf
  | Seq messages ->
     List.iter (fun msg -> format_message msg ppf) messages
  | List list ->
     let format_list_item ppf (header, msg) =
       format_endline (Util.(clear (blue "*")) ^ " " ^ header) ppf;
       format_message msg { ppf with indent = ppf.indent ^ "   " }
     in
     List.iter (format_list_item ppf) list
  | With (f, msg) -> format_message msg (f ppf)
