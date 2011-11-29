(* Julien Verlaguet
 *
 * Copyright (C) 2011 Facebook
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
open Ast_php

module Int = struct type t = int let compare = (-) end
module ISet = Set.Make(Int)
module IMap = Map.Make(Int)
module A = Ast_php_simple

module PI = Parse_info

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
 * Ast_php to Ast_php_simple
 *)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(* pad: ?? *)
type env = (int * Ast_php_simple.stmt) list ref

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let opt f env x =
  match x with
  | None -> None
  | Some x -> Some (f env x)

let rec comma_list = function
  | [] -> []
  | Common.Left x  :: rl -> x :: comma_list rl
  | Common.Right _ :: rl -> comma_list rl

let rec comma_list_dots = function
  | [] -> []
  | Common.Left3 x :: rl -> x :: comma_list_dots rl
  | (Common.Middle3 _ | Common.Right3 _) :: rl -> comma_list_dots rl

let brace (_, x, _) = x

let stmt_of_token x =
  match x with
  | "\n" -> A.Newline
  | x -> A.Comment x

let make_env l =
  let l = List.map (fun (x, y) -> x, stmt_of_token y) l in
  let l = List.sort (fun (x, _) (y, _) -> y - x) l in
  ref l

let rec pop_env stack line =
  match !stack with
  | [] -> None
  | (x, v) :: rl when x >= line - 1 ->
      stack := rl;
      Some v
  | _ -> None

let info_of_stmt = function
  | ExprStmt (_, x)
  | EmptyStmt x
  | Block (x, _, _)
  | If (x, _, _, _, _)
  | IfColon (x, _, _, _, _, _, _, _)
  | While (x, _, _)
  | Do (x, _, _, _, _)
  | For (x, _, _, _, _, _, _, _, _)
  | Switch (x, _, _)
  | Foreach (x, _, _, _, _, _, _, _)
  | Break (x, _, _)
  | Continue (x, _, _)
  | Return (x, _, _)
  | Throw (x, _, _)
  | Try (x, _, _, _)
  | Echo (x, _, _)
  | Globals (x, _, _)
  | StaticVars (x, _, _)
  | InlineHtml (_, x)
  | Use (x, _, _)
  | Unset (x, _, _)
  | Declare (x, _, _)
  | TypedDeclaration (_, _, _, x)
  | DeclConstant (x, _, _, _, _) -> x

let line_of_stmt x = line_of_info (info_of_stmt x)

let rec top_comment env acc =
  match env with
  | [] -> acc
  | (_, x) :: rl -> x :: top_comment rl acc

let rec make_newlines l =
  let k = make_newlines in
  match l with
  | [] -> []
  | (_, _, "\n") :: (_, n, "\n") :: rl ->
     (n, "\n") :: k rl
  | (_, _, (" " | "\n")) :: rl -> k rl
  | (x, n, v) :: rl when Token_helpers_php.is_comment x -> (n, v) :: k rl
  | _ :: rl -> k rl

let make_token x =
  let info = Token_helpers_php.info_of_tok x in
  let line = Parse_info.line_of_info info in
  let str  = Ast_php.str_of_info info in
  x, line, str

let empty_env () = ref []

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let rec program tokens top_l acc =
  let tokens = List.map make_token tokens in
  let tokens = make_newlines tokens in
  let env = make_env tokens in
  let acc = List.fold_right (toplevel env) top_l acc in
  let acc = top_comment (List.rev !env) acc in
  acc

and toplevel env st acc =
  match st with
  | StmtList stmtl ->
      let acc = List.fold_right (stmt env) stmtl acc in
      acc
  | FinalDef _ -> acc
  | FuncDef fd -> A.FuncDef (func_def env fd) :: acc
  | ClassDef cd -> A.ClassDef (class_def env cd) :: acc
  | NotParsedCorrectly _ -> raise Common.Impossible

and stmt env st acc =
  let line = line_of_stmt st in
  match pop_env env line with
  | None -> stmt_ env st acc
  | Some x -> x :: stmt env st acc

and stmt_ env st acc =
  match st with
  | ExprStmt (e, _) ->
      let e = expr env e in
      A.Expr e :: acc
  | EmptyStmt _ -> A.Noop :: acc
  | Block (_, stdl, _) -> List.fold_right (stmt_and_def env) stdl acc
  | If (_, (_, e, _), st, il, io) ->
      let e = expr env e in
      let st = A.Block (stmt env st []) in
      let il = List.fold_right (if_elseif env) il (if_else env io) in
      A.If (e, st, il) :: acc
  | While (_, (_, e, _), cst) ->
      let cst = colon_stmt env cst in
      A.While (expr env e, cst) :: acc
  | Do (_, st, _, (_, e, _), _) ->
      A.Do (stmt env st [], expr env e) :: acc
  | For (_, _, e1, _, e2, _, e3, _, st) ->
      let st = colon_stmt env st in
      let e1 = for_expr env e1 in
      let e2 = for_expr env e2 in
      let e3 = for_expr env e3 in
      A.For (e1, e2, e3, st) :: acc
  | Switch (_, (_, e, _), scl) ->
      let e = expr env e in
      let scl = switch_case_list env scl in
      A.Switch (e, scl) :: acc
  | Foreach (_, _, e, _, fve, fao, _, cst) ->
      let e = expr env e in
      let fve = foreach_var_either env fve in
      let fao = opt foreach_arrow env fao in
      let cst = colon_stmt env cst in
      A.Foreach (e, fve, fao, cst) :: acc
  | Break (_, e, _) -> A.Break (opt expr env e) :: acc
  | Continue (_, eopt, _) -> A.Continue (opt expr env eopt) :: acc
  | Return (_, eopt, _) -> A.Return (opt expr env eopt) :: acc
  | Throw (_, e, _) -> A.Throw (expr env e) :: acc
  | Try (_, (_, stl, _), c, cl) ->
      let stl = List.fold_right (stmt_and_def env) stl [] in
      let c = catch env c in
      let cl = List.map (catch env) cl in
      A.Try (stl, c, cl) :: acc
  | Echo (tok, el, _) ->
      A.Expr (A.Call (A.Id ("echo", tok),
                     (List.map (expr env) (comma_list el)))) :: acc
  | Globals (_, gvl, _) -> A.Global (List.map (global_var env) (comma_list gvl)) :: acc
  | StaticVars (_, svl, _) ->
      A.StaticVars (List.map (static_var env) (comma_list svl)) :: acc
  | InlineHtml (s, _) -> A.InlineHtml s :: acc
  | Use (tok, fn, _) -> A.Expr (A.Call (A.Id ("use", tok),
                                       [A.String (use_filename env fn)])) :: acc
  | Unset (tok, (_, lp, _), e) ->
      let lp = comma_list lp in
      let lp = List.map (lvalue env) lp in
      A.Expr (A.Call (A.Id ("unset", tok), lp)) :: acc
  | DeclConstant _
  | Declare _ ->
      (* TODO failwith "stmt Declare" of tok * declare comma_list paren * colon_stmt *)
      acc
  | TypedDeclaration _ -> failwith "stmt TypedDeclaration" (* of hint_type * lvalue * (tok * expr) option * tok *)
  | IfColon _ -> failwith "This is old crazy stuff"


and use_filename env = function
  | UseDirect (s, _) -> s
  | UseParen (_, (s, _), _) -> s

and if_elseif env (_, (_, e, _), st) acc =
  let e = expr env e in
  let st = match stmt env st [] with [x] -> x | l -> A.Block l in
  A.If (e, st, acc)

and if_else env = function
  | None -> A.Noop
  | Some (_, (If _ as st)) ->
      (match stmt env st [] with
      | [x] -> x
      | l -> assert false)
  | Some (_, st) -> A.Block (stmt env st [])

and stmt_and_def env st acc =
  match st with
  | Stmt st -> stmt env st acc
  | FuncDefNested fd -> A.FuncDef (func_def env fd) :: acc
  | ClassDefNested cd -> A.ClassDef (class_def env cd) :: acc

and expr env = function
  | Sc sc -> scalar env sc
  | Lv lv -> lvalue env lv
  | Binary (e1, (bop, _), e2) ->
      let e1 = expr env e1 in
      let e2 = expr env e2 in
      A.Binop (bop, e1, e2)
  | Unary ((uop, _), e) ->
      let e = expr env e in
      A.Unop (uop, e)
  | Assign (e1, _, e2) -> A.Assign (None, lvalue env e1, expr env e2)
  | AssignOp (lv, (op, _), e) ->
      let op = assignOp env op in
      A.Assign (Some op, lvalue env lv, expr env e)
  | Postfix (v, (fop, _)) -> A.Postfix (fop, lvalue env v)
  | Infix ((fop, _), v) -> A.Infix (fop, lvalue env v)
  | CondExpr (e1, _, None, _, e3) ->
      let e = expr env e1 in
      A.CondExpr (e, e, expr env e3);
  | CondExpr (e1, _, Some e2, _, e3) ->
      A.CondExpr (expr env e1, expr env e2, expr env e3)
  | AssignList (_, (_, la, _), _, e) ->
      let la = comma_list la in
      let la = List.fold_right (list_assign env) la [] in
      let e = expr env e in
      A.Assign (None, A.List la, e)
  | ConsArray (_, (_, apl, _)) ->
      let apl = comma_list apl in
      let apl = List.map (array_pair env) apl in
      A.ConsArray apl
  | New (_, cn, args) ->
      let args =
        match args with
        | None -> []
        | Some (_, cl, _) -> List.map (argument env) (comma_list cl)
      in
      let cn = class_name_reference env cn in
      A.New (cn, args)
(*      failwith "expr New" (* of tok * class_name_reference * argument comma_list paren option *) *)
  | Clone (tok, e) ->
      A.Call (A.Id ("clone", tok), [expr env e])
  | AssignRef (e1, _, _, e2) ->
      let e1 = lvalue env e1 in
      let e2 = lvalue env e2 in
      A.Assign (None, e1, A.Ref e2)
  | AssignNew _ -> failwith "expr AssignNew" (* of lvalue * tok  * tok  * tok  * class_name_reference * argument comma_list paren option *)
  | Cast ((c, _), e) -> A.Cast (c, expr env e)
  | CastUnset _ -> failwith "expr CastUnset" (* of tok * expr  *)
  | InstanceOf (e, _, cn) ->
      let e = expr env e in
      let cn = class_name_reference env cn in
      A.InstanceOf (e, cn)
  | Eval (tok, (_, e, _)) -> A.Call (A.Id ("eval", tok), [expr env e])
  | Lambda ld ->
      A.Lambda (lambda_def env ld)
  | Exit (tok, e) ->
      let arg =
        match e with
        | None
        | Some (_, None, _) -> []
        | Some (_, Some e, _) -> [expr env e]
      in
      A.Call (A.Id ("exit", tok), arg)
  | At (tok, e) ->
      (* failwith "expr At" (* of tok  *) TODO look at this *)
      A.Id ("@", tok)
  | Print (tok, e) ->
      A.Call (A.Id ("print", tok), [expr env e])
  | BackQuote (tok, el, _) ->
      A.Call (A.Id ("exec", tok (* not really an exec token *)),
             [A.Guil (List.map (encaps env) el)])
(*      failwith "expr BackQuote" (* of tok * encaps list * tok *) *)
  | Include (tok, e) ->
      A.Call (A.Id ("include", tok), [expr env e])
  | IncludeOnce (tok, e) ->
      A.Call (A.Id ("include_once", tok), [expr env e])
  | Require (tok, e) ->
      A.Call (A.Id ("require", tok), [expr env e])
  | RequireOnce (tok, e) ->
      A.Call (A.Id ("require_once", tok), [expr env e])
  | Empty (tok, (_, lv, _)) ->
      A.Call (A.Id ("empty", tok), [lvalue env lv])
  | Isset (tok, (_, lvl, _)) ->
      A.Call (A.Id ("isset", tok), List.map (lvalue env) (comma_list lvl))
  | XhpHtml xhp -> A.Xhp (xhp_html env xhp)
  | Yield (tok, e) -> A.Call (A.Id ("yield", tok), [expr env e])
  | YieldBreak (tok, tok2) -> A.Call (A.Id ("yield", tok),
                                     [A.Id ("break", tok2)])
  | SgrepExprDots _ -> failwith "expr SgrepExprDots" (* of info *)
  | ParenExpr (_, e, _) -> expr env e

and lambda_def env ld =
  let _, params, _ = ld.l_params in
  let params = comma_list_dots params in
  let _, body, _ = ld.l_body in
  { A.f_ref = ld.l_ref <> None;
    A.f_name = ("_lambda", Ast_php.fakeInfo "_lambda");
    A.f_params = List.map (parameter env) params;
    A.f_return_type = None;
    A.f_body = List.fold_right (stmt_and_def env) body [];
  }

and scalar env = function
  | C cst -> constant env cst
  | ClassConstant (q, s) ->
      A.Class_get (A.Id (qualifier env q), A.Id (name env s))
  | Guil (_, el, _) -> A.Guil (List.map (encaps env) el)
  | HereDoc ({ PI.token = PI.OriginTok x; _ },
             el,
             { PI.token = PI.OriginTok y; _ }) ->
      A.HereDoc (x.PI.str, List.map (encaps env) el, y.PI.str)
  | HereDoc _ -> assert false

and constant env = function
  | Int (n, _) -> A.Int n
  | Double (n, _) -> A.Double n
  | String (s, _) -> A.String s
  | CName n -> A.Id (name env n)
  | PreProcess (cpp, tok) -> cpp_directive env tok cpp
  | XdebugClass _ -> failwith "stmt XdebugClass" (* of name * class_stmt list *)
  | XdebugResource -> failwith "stmt XdebugResource" (* *)

and cpp_directive env tok = function
  | Line      -> A.Id ("__LINE__", tok)
  | File      -> A.Id ("__FILE__", tok)
  | ClassC    -> A.Id ("__CLASS__", tok)
  | MethodC   -> A.Id ("__METHOD__", tok)
  | FunctionC -> A.Id ("__FUNCTION__", tok)
  | Dir -> A.Id ("__DIR__", tok)
  | TraitC -> A.Id ("__TRAIT__", tok)

and name env = function
  | Name (s, tok) -> s, tok
  | XhpName (tl, tok) ->
      (List.fold_right (fun x y -> x^":"^y) tl ""), tok

and dname = function
  | DName (s, tok) ->
      if s.[0] = '$' then (s, tok)
      else ("$"^s, tok)

and hint_type env = function
  | Hint q -> A.Hint (fst (class_name_or_selfparent env q))
  | HintArray _ -> A.HintArray

and qualifier env (cn, _) = class_name_or_selfparent env cn

and class_name_or_selfparent env = function
   | ClassName fqcn -> name env fqcn
   | Self tok -> ("self", tok)
   | Parent tok -> ("parent", tok)
   (* todo: late static binding *)
   | LateStatic tok -> ("static", tok)

and class_name_reference env = function
   | ClassNameRefStatic cn -> A.Id (class_name_or_selfparent env cn)
   | ClassNameRefDynamic (lv, []) -> lvalue env lv
   | ClassNameRefDynamic _ ->
       failwith "TODO ClassNameRefDynamic" (* of lvalue * obj_prop_access list *)

and lvalue env = function
  | Var (dn, scope) -> A.Id (dname dn)
  | This _ -> A.This
  | VArrayAccess (lv, (_, e, _)) ->
      let lv = lvalue env lv in
      let e = opt expr env e in
      A.Array_get (lv, e)
  | VArrayAccessXhp (e1, (_, e2, _)) ->
      let e1 = expr env e1 in
      let e2 = opt expr env e2 in
      A.Array_get (e1, e2)
  | VBrace (tok, (_, e, _)) ->
      A.Call (A.Id (("eval_var", tok)), [expr env e])
  | VBraceAccess (lv, (_, e, _)) ->
      A.Array_get (lvalue env lv, Some (expr env e))
  | Indirect (e, (Dollar tok)) ->
      A.Call (A.Id ("eval_var", tok), [lvalue env e])
  | VQualifier (q, v)  ->
      A.Class_get (A.Id (qualifier env q),
                  A.Call (A.Id ("eval_var", Ast_php.fakeInfo "eval_var"),
                               [lvalue env v]))
  | ClassVar (q, dn) -> A.Class_get (A.Id (qualifier env q), A.Id (dname dn))
  | FunCallSimple (f, (_, args, _)) ->
      let f = name env f in
      let args = comma_list args in
      let args = List.map (argument env) args in
      A.Call (A.Id f, args)
  | FunCallVar (q, lv, (_, argl, _)) ->
      let argl = comma_list argl in
      let argl = List.map (argument env) argl in
      let lv = lvalue env lv in
      let lv = match q with None -> lv | Some q -> A.Class_get (A.Id (qualifier env q), lv) in
      A.Call (lv, argl)
  | StaticMethodCallSimple (q, n, (_, args, _)) ->
      let f = A.Class_get (A.Id (qualifier env q), A.Id (name env n)) in
      let args = comma_list args in
      let args = List.map (argument env) args in
      A.Call (f, args)
  | MethodCallSimple (e, _, n, (_, args, _)) ->
      let f = lvalue env e in
      let f = A.Obj_get (f, A.Id (name env n)) in
      let args = comma_list args in
      let args = List.map (argument env) args in
      A.Call (f, args)
  | StaticMethodCallVar (lv, _, n, (_, args, _)) ->
      let f = A.Class_get (lvalue env lv, A.Id (name env n)) in
      let args = comma_list args in
      let args = List.map (argument env) args in
      A.Call (f, args)
  | StaticObjCallVar _ -> failwith "expr StaticObjCallVar" (* of lvalue * tok (* :: *) * lvalue * argument comma_list paren *)

  | ObjAccessSimple (lv, _, n) -> A.Obj_get (lvalue env lv, A.Id (name env n))
  | ObjAccess (lv, oa) ->
      let lv = lvalue env lv in
      obj_access env lv oa
  | DynamicClassVar (lv, _, lv2) ->
      A.Class_get (lvalue env lv, lvalue env lv2)


and obj_access env obj (_, objp, args) =
  let e = obj_property env obj objp in
  match args with
  | None -> e
  | Some (_, args, _) ->
      let args = comma_list args in
      let args = List.map (argument env) args in
      (* TODO CHECK THIS *)
      A.Call (e, args)

and obj_property env obj = function
  | ObjProp objd -> obj_dim env obj objd
  | ObjPropVar lv ->
      A.Call (A.Id ("ObjPropVar", Ast_php.fakeInfo "ObjPropVar"),
             [lvalue env lv])

and obj_dim env obj = function
  | OName n -> A.Obj_get (obj, A.Id(name env n))
  | OBrace (_, e, _) ->
      A.Obj_get (obj, expr env e)
  | OArrayAccess (x, (_, e, _)) ->
      let e = opt expr env e in
      let x = obj_dim env obj x in
      A.Array_get (x, e)
  | OBraceAccess _ -> failwith "TODO brace access"(*  of obj_dim * expr brace *)

and indirect env = function
  | Dollar _ -> failwith "expr Dollar" (* of tok *)

and argument env = function
  | Arg e -> expr env e
  | ArgRef (_, e) -> A.Ref (lvalue env e)

and class_def env c =
  let _, body, _ = c.c_body in
  { 
    A.c_type = class_type env c.c_type ;
    A.c_name = name env c.c_name;
    A.c_extends =
    (match c.c_extends with
    | None -> []
    | Some (_, x) -> [fst (name env x)]);
    A.c_implements =
    (match c.c_implements with None -> []
    | Some x -> interfaces env x);
    A.c_constants = List.fold_right (class_constants env) body [];
    A.c_variables = List.fold_right (class_variables env) body [];
    A.c_body = List.fold_right (class_body env) body [];
  }

and class_type env = function
  | ClassRegular _ -> A.ClassRegular
  | ClassFinal _ -> A.ClassFinal
  | ClassAbstract _ -> A.ClassAbstract
  | Interface _ -> A.Interface
  | Trait _ -> A.Trait

and interfaces env (_, intfs) =
  let intfs = comma_list intfs in
  List.map (fun x -> fst (name env x)) intfs

and class_constants env st acc =
  match st with
  | ClassConstants (_, cl, _) ->
      List.fold_right (
      fun (n, ss) acc ->
        (fst (name env n), static_scalar_affect env ss) :: acc
     ) (comma_list cl) acc
  | _ -> acc

and static_scalar_affect env (_, ss) = static_scalar env ss
and static_scalar env a = expr env a

and class_variables env st acc =
  match st with
  | ClassVariables (m, ht, cvl, _) ->
      let cvl = comma_list cvl in
      let m =
        match m with
        | NoModifiers _ -> []
        | VModifiers l -> List.map (fun (x, _) -> x) l
      in
      let vis = visibility env m in
      let static = static env m in
      let abstract = abstract env m in
      let final = final env m in
      let ht = opt hint_type env ht in
      let vars = List.map (
        fun (n, ss) ->
          fst (dname n), opt static_scalar_affect env ss
       ) cvl in
      let cv = {
        A.cv_final = final;
        A.cv_static = static;
        A.cv_abstract = abstract;
        A.cv_visibility = vis;
        A.cv_type = ht;
        A.cv_vars = vars;
        } in
      cv :: acc
  | _ -> acc

and visibility env = function
  | [] -> (* TODO CHECK *) A.Novis
  | Public :: _ -> A.Public
  | Private :: _ -> A.Private
  | Protected :: _ -> A.Protected
  | (Static | Abstract | Final) :: rl -> visibility env rl

and static env = function
  | [] -> false
  | Static :: _ -> true
  | _ :: rl -> static env rl

and abstract env = function
  | [] -> false
  | Abstract :: _ -> true
  | _ :: rl -> abstract env rl

and final env = function
  | [] -> false
  | Final :: _ -> true
  | _ :: rl -> final env rl

and class_body env st acc =
  match st with
  | Method md ->
      method_def env md :: acc
  | XhpDecl _ -> acc(* TODO failwith "TODO xhp decl" *)(* of xhp_decl *)
  | _ -> acc

and method_def env m =
  let _, params, _ = m.m_params in
  let params = comma_list_dots params in
  let mds = List.map (fun (x, _) -> x) m.m_modifiers in
    { A.m_visibility = visibility env mds;
      A.m_static = static env mds;
      A.m_final = final env mds;
      A.m_abstract = abstract env mds;
      A.m_ref = (match m.m_ref with None -> false | Some _ -> true);
      A.m_name = name env m.m_name;
      A.m_params = List.map (parameter env) params ;
      A.m_return_type = opt hint_type env m.m_return_type;
      A.m_body = method_body env m.m_body;
    }

and method_body env = function
  | AbstractMethod _ -> []
  | MethodBody (_, stl, _) ->
      List.fold_right (stmt_and_def env) stl []

and parameter env p =
  { A.p_type = opt hint_type env p.p_type;
    A.p_ref = p.p_ref <> None;
    A.p_name = dname p.p_name;
    A.p_default = opt static_scalar_affect env p.p_default;
  }

and func_def env f =
  let _, params, _ = f.f_params in
  let params = comma_list_dots params in
  let _, body, _ = f.f_body in
  { A.f_ref = f.f_ref <> None;
    A.f_name = name env f.f_name;
    A.f_params = List.map (parameter env) params;
    A.f_return_type = opt hint_type env f.f_return_type;
    A.f_body = List.fold_right (stmt_and_def env) body [];
  }

and xhp_html env = function
  | Xhp (tag, attrl, _, body, _) ->
      let tag, _ = tag in
      let attrl = List.map (xhp_attribute env) attrl in
      { A.xml_tag = tag;
        A.xml_attrs = attrl;
        A.xml_body = List.map (xhp_body env) body;
      }
  | XhpSingleton (tag, attrl, _) ->
      let tag, _ = tag in
      let attrl = List.map (xhp_attribute env) attrl in
      { A.xml_tag = tag;
        A.xml_attrs = attrl;
        A.xml_body = [];
      }

and xhp_attribute env ((n, _), _, v) =
  n, xhp_attr_value env v

and xhp_attr_value env = function
  | XhpAttrString (_, l, _) ->
      A.AttrString (List.map (encaps env) l)
  | XhpAttrExpr (_, e, _) ->
      A.AttrExpr (expr env e)
  | SgrepXhpAttrValueMvar _ -> assert false

and xhp_body env = function
  | XhpText (s, _) -> A.XhpText s
  | XhpExpr (_, e, _) -> A.XhpExpr (expr env e)
  | XhpNested xml -> A.XhpXml (xhp_html env xml)

and encaps env = function
  | EncapsString (s, _) -> A.EncapsString s
  | EncapsVar v -> A.EncapsVar (lvalue env v)
  | EncapsCurly (_, lv, _) -> A.EncapsCurly (lvalue env lv)
  | EncapsDollarCurly (_, lv, _) -> A.EncapsDollarCurly (lvalue env lv)
  | EncapsExpr (_, e, _) -> A.EncapsExpr (expr env e)

and array_pair env = function
  | ArrayExpr e -> A.Aval (expr env e)
  | ArrayRef (_, lv) -> A.Aval (A.Ref (lvalue env lv))
  | ArrayArrowExpr (e1, _, e2) -> A.Akval (expr env e1, expr env e2)
  | ArrayArrowRef (e1, _, _, lv) -> A.Akval (expr env e1, A.Ref (lvalue env lv))


and for_expr env el = List.map (expr env) (comma_list el)

and colon_stmt env = function
  | SingleStmt st -> stmt env st []
  | ColonStmt (_, stl, _, _) -> List.fold_right (stmt_and_def env) stl []
(*of tok (* : *) * stmt_and_def list * tok (* endxxx *) * tok (* ; *) *)

and switch_case_list env = function
  | CaseList (_, _, cl, _) -> List.map (case env) cl
  | CaseColonList _ -> failwith "What's that?"
(*      tok (* : *) * tok option (* ; *) * case list *
        tok (* endswitch *) * tok (* ; *) *)

and case env = function
  | Case (_, e, _, stl) ->
      let stl = List.fold_right (stmt_and_def env) stl [] in
      A.Case (expr env e, stl)
  | Default (_, _, stl) ->
      let stl = List.fold_right (stmt_and_def env) stl [] in
      A.Default stl

and foreach_arrow env (_, fv) = foreach_variable env fv
and foreach_variable env (r, lv) =
  let e = lvalue env lv in
  let e = if r <> None then A.Ref e else e in
  e

and foreach_var_either env = function
  | Common.Left fv -> foreach_variable env fv
  | Common.Right lv -> lvalue env lv

and catch env (_, (_, (fq, dn), _), (_, stdl, _)) =
  let stdl = List.fold_right (stmt_and_def env) stdl [] in
  let fq = name env fq in
  let dn = dname dn in
  fst fq, fst dn, stdl

and static_var env (x, e) =
  dname x, opt static_scalar_affect env e

and list_assign env x acc =
  match x with
  | ListVar lv -> (lvalue env lv) :: acc
  | ListList (_, (_, la, _)) ->
      let la = comma_list la in
      let la = List.fold_right (list_assign env) la [] in
      A.List la :: acc
  | ListEmpty -> acc

and assignOp env = function
  | AssignOpArith aop -> Arith aop
  | AssignConcat -> BinaryConcat

and global_var env = function
  | GlobalVar dn -> A.Id (dname dn)
  | GlobalDollar _ -> failwith "TODO GlobalDollar" (*of tok * r_variable *)
  | GlobalDollarExpr _ -> failwith "TODO GlobalDollarExpr" (* of tok * expr brace *)

let program_with_comments tokl ast =
  program tokl ast []

let program ast =
  program [] ast []
