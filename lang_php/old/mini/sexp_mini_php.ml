(* Yoann Padioleau
 *
 * Copyright (C) 2010 Facebook
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
open Common

(* generated by ocamltarzan with: camlp4o -o /tmp/yyy.ml -I pa/ pa_type_conv.cmo pa_sexp2_conv.cmo  pr_o.cmo /tmp/xxx.ml  *)

(* for binaryOp *)
open Ast_php
open Ast_mini_php

let rec sexp_of_phptype v = Conv.sexp_of_list sexp_of_phptypebis v
and sexp_of_phptypebis =
  function
  | TBool -> Sexp.Atom "TBool"
  | TNum -> Sexp.Atom "TNum"
  | TString -> Sexp.Atom "TString"
  | TArray(v1) -> 
      let v1 = sexp_of_phptype v1 in
      Sexp.List [Sexp.Atom "TArray"; v1]
  | TNull -> Sexp.Atom "TNull"
  | TVariant -> Sexp.Atom "TVariant"
  | TUnknown -> Sexp.Atom "TUnknown"
  | TypeVar v1 ->
      let v1 = Conv.sexp_of_string v1
      in Sexp.List [ Sexp.Atom "TypeVar"; v1 ]
  | (TRecord _|THash _|TUnit) -> raise Todo
 
let rec sexp_of_expr (v1, v2) =
  let v1 = sexp_of_exprbis v1
  and v2 = sexp_of_expr_info v2
  in Sexp.List [ v1; v2 ]
and sexp_of_expr_info { t = v_t } =
  let bnds = [] in
  let arg = sexp_of_phptype v_t in
  let bnd = Sexp.List [ Sexp.Atom "t"; arg ] in
  let bnds = bnd :: bnds in Sexp.List bnds
and sexp_of_exprbis =
  function
  | Bool v1 ->
      let v1 = Conv.sexp_of_bool v1 in Sexp.List [ Sexp.Atom "Bool"; v1 ]
  | Number v1 ->
      let v1 = Conv.sexp_of_string v1 in Sexp.List [ Sexp.Atom "Number"; v1 ]
  | String v1 ->
      let v1 = Conv.sexp_of_string v1 in Sexp.List [ Sexp.Atom "String"; v1 ]
  | Null ->
      Sexp.Atom "Null"
  | Var v1 ->
      let v1 = Conv.sexp_of_string v1 in Sexp.List [ Sexp.Atom "Var"; v1 ]
  | ArrayAccess ((v1, v2)) ->
      let v1 = sexp_of_expr v1
      and v2 = sexp_of_expr v2
      in Sexp.List [ Sexp.Atom "ArrayAccess"; v1; v2 ]
  | Assign ((v1, v2)) ->
      let v1 = sexp_of_expr v1
      and v2 = sexp_of_expr v2
      in Sexp.List [ Sexp.Atom "Assign"; v1; v2 ]
  | Binary ((v1, v2, v3)) ->
      let v1 = sexp_of_expr v1
      and v2 = sexp_of_binaryOp v2
      and v3 = sexp_of_expr v3
      in Sexp.List [ Sexp.Atom "Binary"; v1; v2; v3 ]
  | Funcall ((v1, v2)) ->
      let v1 = Conv.sexp_of_string v1
      and v2 = Conv.sexp_of_list sexp_of_expr v2
      in Sexp.List [ Sexp.Atom "Funcall"; v1; v2 ]
and sexp_of_stmt =
  function
  | ExprStmt v1 ->
      let v1 = sexp_of_expr v1 in Sexp.List [ Sexp.Atom "ExprStmt"; v1 ]
  | Echo v1 -> let v1 = sexp_of_expr v1 in Sexp.List [ Sexp.Atom "Echo"; v1 ]
  | If ((v1, v2, v3)) ->
      let v1 = sexp_of_expr v1
      and v2 = sexp_of_stmt v2
      and v3 = Conv.sexp_of_option sexp_of_stmt v3
      in Sexp.List [ Sexp.Atom "If"; v1; v2; v3 ]
  | While ((v1, v2)) ->
      let v1 = sexp_of_expr v1
      and v2 = sexp_of_stmt v2
      in Sexp.List [ Sexp.Atom "While"; v1; v2]
  | Block v1 ->
      let v1 = Conv.sexp_of_list sexp_of_stmt v1
      in Sexp.List [ Sexp.Atom "Block"; v1 ]
  | Return v1 ->
      let v1 = Conv.sexp_of_option sexp_of_expr v1 in 
      Sexp.List [ Sexp.Atom "Return"; v1 ]
and sexp_of_toplevel =
  function
  | FuncDef ((v1, v2, v3)) ->
      let v1 = Conv.sexp_of_string v1
      and v2 =
        Conv.sexp_of_list
          (fun (v1, v2) ->
             let v1 = Conv.sexp_of_string v1
             and v2 = Conv.sexp_of_option sexp_of_expr v2
             in Sexp.List [ v1; v2 ])
          v2
      and v3 = Conv.sexp_of_list sexp_of_stmt v3
      in Sexp.List [ Sexp.Atom "FuncDef"; v1; v2; v3 ]
  | StmtList v1 ->
      let v1 = Conv.sexp_of_list sexp_of_stmt v1
      in Sexp.List [ Sexp.Atom "StmtList"; v1 ]
and sexp_of_program v = Conv.sexp_of_list sexp_of_toplevel v


and sexp_of_binaryOp =
  function
  | Arith v1 ->
      let v1 = sexp_of_arithOp v1 in Sexp.List [ Sexp.Atom "Arith"; v1 ]
  | Logical v1 ->
      let v1 = sexp_of_logicalOp v1 in Sexp.List [ Sexp.Atom "Logical"; v1 ]
  | BinaryConcat -> Sexp.Atom "BinaryConcat"
and sexp_of_arithOp =
  function
  | Plus -> Sexp.Atom "Plus"
  | Minus -> Sexp.Atom "Minus"
  | Mul -> Sexp.Atom "Mul"
  | Div -> Sexp.Atom "Div"
  | Mod -> Sexp.Atom "Mod"
  | DecLeft -> Sexp.Atom "DecLeft"
  | DecRight -> Sexp.Atom "DecRight"
  | And -> Sexp.Atom "And"
  | Or -> Sexp.Atom "Or"
  | Xor -> Sexp.Atom "Xor"
and sexp_of_logicalOp =
  function
  | Inf -> Sexp.Atom "Inf"
  | Sup -> Sexp.Atom "Sup"
  | InfEq -> Sexp.Atom "InfEq"
  | SupEq -> Sexp.Atom "SupEq"
  | Eq -> Sexp.Atom "Eq"
  | NotEq -> Sexp.Atom "NotEq"
  | Identical -> Sexp.Atom "Identical"
  | NotIdentical -> Sexp.Atom "NotIdentical"
  | AndLog -> Sexp.Atom "AndLog"
  | OrLog -> Sexp.Atom "OrLog"
  | XorLog -> Sexp.Atom "XorLog"
  | AndBool -> Sexp.Atom "AndBool"
  | OrBool -> Sexp.Atom "OrBool"

  

(* pad addons *)
let string_of_program xs = 
  let sexp = sexp_of_program xs in
  let s = Sexp.to_string_hum sexp in
  s

let string_of_phptypebis x =
  Sexp.to_string_hum (sexp_of_phptypebis x)

let string_of_phptype x =
  Sexp.to_string_hum (sexp_of_phptype x)