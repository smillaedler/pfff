(* Julien Verlaguet, Yoann Padioleau
 *
 * Copyright (C) 2011, 2012 Facebook
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

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* A (real) Abstract Syntax Tree for PHP, not a Concrete Syntax Tree
 * as in ast_php.ml.
 *
 * This file contains a simplified PHP abstract syntax tree. The original
 * PHP syntax tree (ast_php.ml) is good for code refactoring or
 * code visualization; the type used matches exactly the source. However,
 * for other algorithms, the nature of the AST makes the code a bit
 * redundant. Hence the idea of a SimpleAST which is the
 * original AST where certain constructions have been factorized
 * or even removed.
 *
 * Here is a list of the simplications/factorizations:
 *  - no purely syntactical tokens in the AST like parenthesis, brackets,
 *    braces, angles, commas, semicolons, antislash, etc. No ParenExpr. 
 *    No FinalDef. No NotParsedCorrectly. The only token information kept 
 *    is for identifiers for error reporting. See wrap() below.
 *
 *  - support for old syntax is removed. No IfColon, ColonStmt,
 *    CaseColonList.
 *  - support for extra tools is removed. No XdebugXxx, SgrepXxx.
 *  - support for features we don't really use in our code is removed
 *    e.g. unset cast. No Use, UseDirect, UseParen. No CastUnset.
 *    Also no StaticObjCallVar. Also no NamespaceBracketDef.
 *  - some known directives like 'declare(ticks=1);' or 'declare(strict=1);'
 *    are skipped because they don't have a useful semantic for
 *    the abstract interpreter or the type inference engine. No Declare.
 *
 *  - sugar is removed, no ArrayLong vs ArrayShort, no InlineHtml,
 *    no HereDoc, no EncapsXxx, no XhpSingleton (but kept Xhp), no
 *    implicit fields via constructor parameters.
 *  - some builtins, for instance 'echo', are transformed in "__builtin__echo".
 *    See builtin() below.
 *  - no include/require, they are transformed in call
 *    to __builtin__require (maybe not a good idea)
 *  - some special keywords, for instance 'self', are transformed in
 *    "__special__self". See special() below.
 *
 *  - a simpler stmt type; no extra toplevel and stmt_and_def types,
 *    no FuncDefNested, no ClassDefNested. No StmtList.
 *  - a simpler expr type; no lvalue vs expr vs static_scalar vs attribute
 *    (update: now static_scalar = expr = lvalue also in ast_php.ml).
 *    Also no scalar. No Sc, no C. No Lv. Pattern matching constants
 *    is simpler:  | Sc (C (String ...)) -> ... becomes just | String -> ....
 *    Also no arg type. No Arg, ArgRef. Also no xhp_attr_value type.
 *    No XhpAttrString, XhpAttrExpr.
 *  - no EmptyStmt, it is transformed in an empty Block
 *  - a simpler If. 'elseif' are transformed in nested If, and empty 'else'
 *    in an empty Block.
 *  - a simpler Foreach, foreach_var_either and foreach_arrow are transformed
 *    into expressions (maybe not good idea)

 *  - some special constructs like AssignRef were transformed into
 *    composite calls to Assign and Ref. Same for AssignList, AssignNew.
 *    Same for arguments passed by reference, no Arg, ArgRef.
 *    Same for refs in arrays, no ArrayRef, ArrayArrowRef. Also no ListVar,
 *    ListList, ListEmpty. More orthogonal.

 *  - a unified Call. No FunCallSimple, FunCallVar, MethodCallSimple,
 *    StaticMethodCallSimple, StaticMethodCallVar
 *    (update: same in ast_php.ml now)
 *  - a unified Array_get. No VArrayAccess, VArrayAccessXhp,
 *    VBraceAccess, OArrayAccess, OBraceAccess
 *    (update: same in ast_php.ml now)
 *  - unified Class_get and Obj_get instead of lots of duplication in
 *    many constructors, e.g. no ClassConstant in a separate scalar type,
 *    no retarded obj_prop_access/obj_dim types,
 *    no OName, CName, ObjProp, ObjPropVar, ObjAccessSimple vs ObjAccess,
 *    no ClassNameRefDynamic, no VQualifier, ClassVar, DynamicClassVar,
 *    etc.
 *    (update: same in ast_php.ml now)
 *  - unified eval_var, some constructs were transformed into calls to
 *    "eval_var" builtin, e.g. no GlobalDollar, no VBrace, no Indirect.
 *
 *  - a simpler 'name' for identifiers, xhp names and regular names are merged,
 *    the special keyword self/parent/static are merged,
 *    so the complex Id (XName [QI (Name "foo")]) becomes just Id ["foo"].
 *  - ...
 *
 * todo:
 *  - support for generics of hack
 *  - more XHP class declaration e.g. children, @required, etc?
 *  - less: factorize more? string vs Guil vs xhp?
 *)

(*****************************************************************************)
(* The AST related types *)
(*****************************************************************************)

(* The wrap is to get position information for certain elements in the AST.
 * It can be None when we want to optimize things and have a very
 * small marshalled AST. See Ast_php_simple.build.store_position flag.
 * Right now with None the marshalled AST for www is 190MB instead of
 * 380MB.
 *)
type 'a wrap = 'a * Ast_php.tok option

type ident = string wrap
type var = string wrap

(* The keyword 'namespace' can be in a leading position. The special
 * ident 'ROOT' can also be leading.
 *)
type qualified_ident = ident list

type name = qualified_ident

(* ------------------------------------------------------------------------- *)
(* Program *)
(* ------------------------------------------------------------------------- *)

type program = stmt list

(* ------------------------------------------------------------------------- *)
(* Statement *)
(* ------------------------------------------------------------------------- *)
and stmt =
  | Expr of expr

  | Block of stmt list

  | If of expr * stmt * stmt
  | Switch of expr * case list

  (* pad: not sure why we use stmt list instead of just stmt like for If *)
  | While of expr * stmt list
  | Do of stmt list * expr
  | For of expr list * expr list * expr list * stmt list
  (* 'foreach ($xs as $k)' or 'foreach ($xs as $k => $v)'
   * so the second and third expr are almost always a Var
   *)
  | Foreach of expr * expr * expr option * stmt list

  | Return of expr option
  | Break of expr option | Continue of expr option

  | Throw of expr
  | Try of stmt list * catch * catch list

  (* only at toplevel in most of our code *)
  | ClassDef of class_def
  | FuncDef of func_def
  (* only at toplevel *)
  | ConstantDef of constant_def
  | TypeDef of type_def
  (* the qualified_ident below can not have a leading '\' *)
  | NamespaceDef of qualified_ident

  (* Note that there is no LocalVars constructor. Variables in PHP are
   * declared when they are first assigned. *)
  | StaticVars of (var * expr option) list
  (* expr is most of the time a simple variable name *)
  | Global of expr list

  and case =
    | Case of expr * stmt list
    | Default of stmt list

  (* catch(Exception $exn) { ... } => ("Exception", "$exn", [...]) *)
  and catch = hint_type  * var * stmt list

(* ------------------------------------------------------------------------- *)
(* Expression *)
(* ------------------------------------------------------------------------- *)

(* lvalue and expr has been mixed in this AST, but an lvalue should be
 * an expr restricted to: Var $var, Array_get, Obj_get, Class_get, List.
 *)
and expr =
  (* booleans are really just Int in PHP :( *)
  | Int of string
  | Double of string
  (* PHP has no first-class functions so entities are sometimes passed
   * as strings so the string wrap below can actually correspond to a
   * 'Id name' sometimes. Some magic functions like param_post() also
   * introduce entities (variables) via strings.
   *)
  | String of string wrap

  (* Id is valid for "entities" (functions, classes, constants). Id is also
   * used for class methods/fields/constants. It Can also contain 
   * "self/parent" or "static". It can be "true", "false", "null" and many
   * other builtin constants. See builtin() and special() below.
   *
   * todo: For field name, if in the code they are referenced like $this->fld,
   * we should prepend a $ to fld to match their definition.
   *
   *)
  | Id of name

   (* Var used to be merged with Id. But then we were doing lots of
    * 'when Ast.is_variable name' so maybe better to have Id and Var
    * (at the same time OCaml does not differentiate Id from Var).
    * The string contains the '$'.
    *)
  | Var of var

  (* when None it means add to the end when used in lvalue position *)
  | Array_get of expr * expr option

  (* often transformed in Var "$this" in the analysis *)
  | This of string wrap
  (* Unified method/field access.
   * ex: $o->foo() ==> Call(Obj_get(Var "$o", Id "foo"), [])
   * ex: A::foo()  ==> Call(Class_get(Id "A", Id "foo"), [])
   * note that Id can be "self", "parent", "static".
   *)
  | Obj_get of expr * expr
  | Class_get of expr * expr

  | New of expr * expr list
  | InstanceOf of expr * expr

  (* pad: could perhaps be at the statement level? The left expr
   * must be an lvalue (e.g. a variable).
   *)
  | Assign of Ast_php.binaryOp option * expr * expr
  (* really a destructuring tuple let; always used as part of an Assign *)
  | List of expr list

  | Call of expr * expr list

  (* todo? transform into Call (builtin ...) ? *)
  | Infix of Ast_php.fixOp * expr
  | Postfix of Ast_php.fixOp * expr
  | Binop of Ast_php.binaryOp * expr * expr
  | Unop of Ast_php.unaryOp * expr
  | Guil of expr list

  (* $y =& $x is transformed into an Assign(Var "$y", Ref (Var "$x")). In
   * PHP refs are always used in an Assign context.
   *)
  | Ref of expr

  | ConsArray of expr option * array_value list
  | Collection of name * array_value list
  | Xhp of xml

  | CondExpr of expr * expr * expr
  | Cast of Ast_php.ptype * expr

  (* yeah! PHP 5.3 is becoming a real language *)
  | Lambda of func_def

  and map_kind =
    | Map
    | StableMap
  and array_value =
    | Aval of expr
    | Akval of expr * expr
  and vector_value = expr
  and map_value = expr * expr

  (* pad: do we need that? could convert into something more basic *)
  and xhp =
    | XhpText of string
    | XhpExpr of expr
    | XhpXml of xml

    and xml = {
      xml_tag: ident;
      xml_attrs: (ident * xhp_attr) list;
      xml_body: xhp list;
    }
     and xhp_attr = expr

(* ------------------------------------------------------------------------- *)
(* Types *)
(* ------------------------------------------------------------------------- *)

and hint_type =
 | Hint of name (* todo: add the generics *)
 | HintArray
 | HintQuestion of hint_type
 | HintTuple of hint_type list
 | HintCallback of hint_type list * (hint_type option)

and class_name = hint_type

(* ------------------------------------------------------------------------- *)
(* Definitions *)
(* ------------------------------------------------------------------------- *)

(* The func_def type below is actually used both for functions and methods.
 *
 * For methods, a few names are specials:
 *  - __construct, __destruct
 *  - __call, __callStatic
 *)
and func_def = {
  (* "_lambda" when used for lambda, see also AnonLambda for f_kind below *)
  f_name: ident;
  f_kind: function_kind;

  f_params: parameter list;
  f_return_type: hint_type option;
  (* functions returning a ref are rare *)
  f_ref: bool;
  (* only for methods; always empty for functions *)
  m_modifiers: modifier list;
  (* only for lambdas (could also abuse parameter) *)
  l_uses: (bool (* is_ref *) * var) list;
  f_attrs: attribute list;

  f_body: stmt list;
}
   and function_kind =
     | Function
     | AnonLambda
     | Method

   and parameter = {
     p_type: hint_type option;
     p_ref: bool;
     p_name: var;
     p_default: expr option;
     p_attrs: attribute list;
   }

  (* for methods, and below for fields too *)
  and modifier = Ast_php.modifier

  (* normally either an Id or Call with only static arguments *)
  and attribute = expr

and constant_def = {
  cst_name: ident;
  (* normally a static scalar *)
  cst_body: expr;
}

and class_def = {
  (* for XHP classes it's x:frag (and not :x:frag), see string_of_xhp_tag *)
  c_name: ident;
  c_kind: class_kind;

  c_extends: class_name option;
  c_implements: class_name list;
  c_uses: class_name list; (* traits *)

  c_attrs: attribute list;
  (* xhp attributes. less: other xhp decl, e.g. children, @required, etc *)
  c_xhp_fields: class_var list; 
  c_xhp_attr_inherit: class_name list;
  c_constants: constant_def list;
  c_variables: class_var list;
  c_methods: method_def list;
}

  and class_kind =
    (* todo: put Final, Abstract as modifier list in class_def *)
    | ClassRegular | ClassFinal | ClassAbstract
    | Interface
    | Trait

  and class_var = {
    (* note that the name will contain a $ *)
    cv_name: var;
    cv_type: hint_type option;
    cv_value: expr option;
    cv_modifiers: modifier list;
  }
  and method_def = func_def

and type_def = {
  t_name: ident;
  t_kind: type_def_kind;
}
  and type_def_kind =
  | Alias of hint_type
  | Newtype of hint_type
 (* with tarzan *)

(* ------------------------------------------------------------------------- *)
(* Any *)
(* ------------------------------------------------------------------------- *)
type any =
  | Program of program
  | Stmt of stmt
  | Expr2 of expr
  | Param of parameter
 (* with tarzan *)

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let unwrap x = fst x
let wrap s = s, Some (Ast_php.fakeInfo s)

(* builtin() is used for:
 *  - 'eval', and implicitly generated eval/reflection like functions:
 *     "eval_var" (e.g. for echo $$x, echo ${"x"."y"}),
 *  - 'clone',
 *  - 'exit', 'yield', 'yield_break'
 *  - 'unset', 'isset', 'empty'
 *     http://php.net/manual/en/function.unset.php
 *     http://php.net/manual/en/function.empty.php
 *  - 'echo', 'print',
 *  - '@', '`',
 *  - 'include', 'require', 'include_once', 'require_once'.
 *  -  __LINE__/__FILE/__DIR/__CLASS/__TRAIT/__FUNCTION/__METHOD/
 *
 * See also pfff/data/php_stdlib/pfff.php which declares those builtins.
 * See also tests/php/semantic/ for example of uses of those builtins.
 *
 * coupling: if modify the string, git grep it because it's probably
 *  used in patterns too.
 *)
let builtin x = "__builtin__" ^ x
(* for 'self'/'parent', 'static', 'lambda', 'namespace', root namespace '\' *)
let special x = "__special__" ^ x

(* AST helpers *)
let has_modifier cv = List.length cv.cv_modifiers > 0
let is_static modifiers  = List.mem Ast_php.Static  modifiers
let is_private modifiers = List.mem Ast_php.Private modifiers

(* old: Common.join ":" xs, but then webpage and :webpage are considered
 * DUPE by codegraph, so simpler to prepend this <
 *)
let string_of_xhp_tag xs = "<" ^ Common.join ":" xs ^ ">"

let str_of_ident (s, _) = s
let tok_of_ident (s, x) =
  match x with
  | None -> failwith (Common.spf "no token information for %s" s)
  | Some tok -> tok

let str_of_name = function
  | [id] -> str_of_ident id
  | _ -> failwith "no namespace support yet"
let tok_of_name = function
  | [id] -> tok_of_ident id
  | _ -> failwith "no namespace support yet"

(* we sometimes need to remove the '$' prefix *)
let remove_first_char s =
  String.sub s 1 (String.length s - 1)

let str_of_class_name x =
  match x with
  | Hint (name) -> str_of_name name
  | _ -> raise Common.Impossible

let name_of_class_name x =
  match x with
  | Hint ([name]) -> name
  | Hint _ -> failwith "no namespace support yet"
  | _ -> raise Common.Impossible
