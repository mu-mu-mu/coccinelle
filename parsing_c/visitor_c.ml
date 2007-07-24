open Common open Commonop


open Ast_c
module F = Control_flow_c

(*****************************************************************************)
(* Functions to visit both the Ast and the CFG *)
(*****************************************************************************)


(* Visitor based on continuation. Cleaner than the one based on mutable 
 * pointer functions. src: based on a (vague) idea from remy douence.
 * 
 * 
 * 
 * Diff with Julia's visitor ? She does:
 * 
 * let ident r k i =
 *  ...
 * let expression r k e =
 *  ... 
 *   ... (List.map r.V0.combiner_expression expr_list) ...
 *  ...
 * let res = V0.combiner bind option_default 
 *   mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
 *   donothing donothing donothing donothing
 *   ident expression typeC donothing parameter declaration statement
 *   donothing in
 * ...
 * collect_unitary_nonunitary
 *   (List.concat (List.map res.V0.combiner_top_level t))
 * 
 * 
 * 
 * So she has to remember at which position you must put the 'expression'
 * function. I use record which is easier. 
 * 
 * When she calls recursively, her res.V0.combiner_xxx does not take bigf
 * in param whereas I do 
 *   | F.Decl decl -> Visitor_c.vk_decl bigf decl 
 * And with the record she gets, she does not have to do my
 * multiple defs of function such as 'let al_type = V0.vk_type_s bigf'
 * 
 * The code of visitor.ml is cleaner with julia because mutual recursive calls
 * are clean such as ... 'expression e' ... and not  'f (k, bigf) e'
 * or 'vk_expr bigf e'.
 * 
 * So it is very dual:
 * - I give a record but then I must handle bigf.
 * - She gets a record, and gives a list of function
 * 
 *) 

 
(* old: first version (only visiting expr) 

let (iter_expr:((expression -> unit) -> expression -> unit) -> expression -> unit)
 = fun f expr ->
  let rec k e = 
    match e with
    | Constant c -> ()
    | FunCall  (e, es)         ->  f k e; List.iter (f k) es
    | CondExpr (e1, e2, e3)    -> f k e1; f k e2; f k e3
    | Sequence (e1, e2)        -> f k e1; f k e2;
    | Assignment (e1, op, e2)  -> f k e1; f k e2;
        
    | Postfix  (e, op) -> f k e
    | Infix    (e, op) -> f k e
    | Unary    (e, op) -> f k e
    | Binary   (e1, op, e2) -> f k e1; f k  e2;
        
    | ArrayAccess    (e1, e2) -> f k e1; f k e2;
    | RecordAccess   (e, s) -> f k e
    | RecordPtAccess (e, s) -> f k e

    | SizeOfExpr  e -> f k e
    | SizeOfType  t -> ()
    | _ -> failwith "to complete"

  in f k expr

let ex1 = Sequence (Sequence (Constant (Ident "1"), Constant (Ident "2")), 
                             Constant (Ident "4"))
let test = 
  iter_expr (fun k e ->  match e with
  | Constant (Ident x) -> Common.pr2 x
  | rest -> k rest
  ) ex1 
==> 
1
2
4

*)

(*****************************************************************************)
(* Side effect style visitor *)
(*****************************************************************************)

(* Visitors for all langage concept,  not just for expression.
 * 
 * Note that I don't visit necesserally in the order of the token
 * found in the original file. So don't assume such hypothesis!
 *)
type visitor_c = 
 { 
   kexpr:      (expression  -> unit) * visitor_c -> expression  -> unit;
   kstatement: (statement   -> unit) * visitor_c -> statement   -> unit;
   ktype:      (fullType    -> unit) * visitor_c -> fullType    -> unit;

   kdecl:      (declaration -> unit) * visitor_c -> declaration -> unit;
   kdef:       (definition  -> unit) * visitor_c -> definition  -> unit; 
   kini:       (initialiser  -> unit) * visitor_c -> initialiser  -> unit; 

   kinfo: (info -> unit) * visitor_c -> info -> unit;

   (* CFG *)
   knode: (F.node -> unit) * visitor_c -> F.node -> unit;
   (* Ast *)
   kprogram: (toplevel -> unit) * visitor_c -> toplevel -> unit;
 } 

let default_visitor_c = 
  { kexpr =      (fun (k,_) e  -> k e);
    kstatement = (fun (k,_) st -> k st);
    ktype      = (fun (k,_) t  -> k t);
    kdecl      = (fun (k,_) d  -> k d);
    kdef       = (fun (k,_) d  -> k d);
    kini       = (fun (k,_) ie  -> k ie);
    kinfo      = (fun (k,_) ii  -> k ii);
    knode      = (fun (k,_) n  -> k n);
    kprogram      = (fun (k,_) p  -> k p);
  } 

let rec vk_expr = fun bigf expr ->
  let iif ii = vk_ii bigf ii in

  let rec exprf e = bigf.kexpr (k,bigf) e
  and k ((e,typ), ii) = 
    iif ii;
    match e with
    | Ident (s) -> ()
    | Constant (c) -> ()
    | FunCall  (e, es)         -> 
        exprf e;  
        es +> List.iter (fun (e, ii) -> 
          iif ii;
          vk_argument bigf e
          );
    | CondExpr (e1, e2, e3)    -> 
        exprf e1; do_option (exprf) e2; exprf e3
    | Sequence (e1, e2)        -> exprf e1; exprf e2;
    | Assignment (e1, op, e2)  -> exprf e1; exprf e2;
        
    | Postfix  (e, op) -> exprf e
    | Infix    (e, op) -> exprf e
    | Unary    (e, op) -> exprf e
    | Binary   (e1, op, e2) -> exprf e1; exprf  e2;
        
    | ArrayAccess    (e1, e2) -> exprf e1; exprf e2;
    | RecordAccess   (e, s) -> exprf e
    | RecordPtAccess (e, s) -> exprf e

    | SizeOfExpr  (e) -> exprf e
    | SizeOfType  (t) -> vk_type bigf t
    | Cast    (t, e) -> vk_type bigf t; exprf e

    (* old: | StatementExpr (((declxs, statxs), is)), is2 -> 
     *          List.iter (vk_decl bigf) declxs; 
     *          List.iter (vk_statement bigf) statxs 
     *)
    | StatementExpr ((statxs, is)) -> 
        iif is;
        statxs +> List.iter (vk_statement bigf);

    (* TODO, we will certainly have to then do a special visitor for 
     * initializer 
     *)
    | Constructor (t, initxs) -> 
        vk_type bigf t;
        initxs +> List.iter (fun (ini, ii) -> 
          vk_ini bigf ini;
          vk_ii bigf ii;
        ) 
          
    | ParenExpr (e) -> exprf e


  in exprf expr

and vk_argument = fun bigf arg -> 
  let rec do_action = function 
    | (ActMisc ii) -> vk_ii bigf ii
  in
  match arg with
  | Left e -> (vk_expr bigf) e
  | Right (ArgType param) -> vk_param bigf param
  | Right (ArgAction action) -> do_action action




and vk_statement = fun bigf st -> 
  let iif ii = vk_ii bigf ii in

  let rec statf x = bigf.kstatement (k,bigf) x 
  and k st = 
    let (unwrap_st, ii) = st in
    iif ii;
    match unwrap_st with
    | Labeled (Label (s, st)) -> statf  st;
    | Labeled (Case  (e, st)) -> vk_expr bigf e; statf st;
    | Labeled (CaseRange  (e, e2, st)) -> 
        vk_expr bigf e; vk_expr bigf e2; statf st;
    | Labeled (Default st) -> statf st;

    | Compound statxs -> statxs +> List.iter (vk_statement bigf)
    | ExprStatement (eopt) -> do_option (vk_expr bigf) eopt;

    | Selection  (If (e, st1, st2)) -> 
        vk_expr bigf e; statf st1; statf st2;
    | Selection (Ifdef (st1s, st2s)) -> 
        st1s +> List.iter (vk_statement bigf);
        st2s +> List.iter (vk_statement bigf)
    | Selection  (Switch (e, st)) -> 
        vk_expr bigf e; statf st;
    | Iteration  (While (e, st)) -> 
        vk_expr bigf e; statf st;
    | Iteration  (DoWhile (st, e)) -> statf st; vk_expr bigf e; 
    | Iteration  (For ((e1opt,i1), (e2opt,i2), (e3opt,i3), st)) -> 
        statf (ExprStatement (e1opt),i1); 
        statf (ExprStatement (e2opt),i2); 
        statf (ExprStatement (e3opt),i3); 
        statf st;

    | Iteration  (MacroIteration (s, es, st)) -> 
        es +> List.iter (fun (e, ii) -> 
          iif ii;
          vk_argument bigf e
          );
        statf st;
          
    | Jump (Goto s) -> ()
    | Jump ((Continue|Break|Return)) -> ()
    | Jump (ReturnExpr e) -> vk_expr bigf e;
    | Jump (GotoComputed e) -> vk_expr bigf e;

    | Decl decl -> vk_decl bigf decl 
    | Asm asmbody -> vk_asmbody bigf asmbody
    | NestedFunc def -> vk_def bigf def
    | MacroStmt -> ()

  in statf st

and vk_asmbody = fun bigf (string_list, colon_list) -> 
  let iif ii = vk_ii bigf ii in

  iif string_list;
  colon_list +> List.iter (fun (Colon xs, ii)  -> 
    iif ii;
    xs +> List.iter (fun (x,iicomma) -> 
      iif iicomma;
      (match x with
      | ColonMisc, ii -> iif ii 
      | ColonExpr e, ii -> 
          vk_expr bigf e;
          iif ii
      )
    ))

and vk_type = fun bigf t -> 
  let iif ii = vk_ii bigf ii in

  let rec typef x = bigf.ktype (k, bigf) x 
  and k t = 
    let (q, t) = t in
    let (unwrap_q, iiq) = q in
    let (unwrap_t, iit) = t in
    iif iiq;
    iif iit;
    match unwrap_t with
    | BaseType _ -> ()
    | Pointer t -> typef t
    | Array (eopt, t) -> 
        do_option (vk_expr bigf) eopt;
        typef t 
    | FunctionType (returnt, paramst) -> 
        typef returnt;
        (match paramst with
        | (ts, (b,iihas3dots)) -> 
            iif iihas3dots;
            ts +> List.iter (fun (param,iicomma) -> 
              vk_param bigf param;
              iif iicomma;
              
            )
        )

    | Enum  (sopt, enumt) -> 
        enumt +> List.iter (fun (((s, eopt),ii_s_eq), iicomma) -> 
          iif ii_s_eq; iif iicomma;
          eopt +> do_option (vk_expr bigf)
          );    
        
    | StructUnion (sopt, _su, fields) -> 
        vk_struct_fields bigf fields

    | StructUnionName (s, structunion) -> ()
    | EnumName  s -> ()

    | TypeName (s) -> ()

    | ParenType t -> typef t
    | TypeOfExpr e -> vk_expr bigf e
    | TypeOfType t -> typef t

  in typef t

and vk_decl = fun bigf d -> 
  let iif ii = vk_ii bigf ii in

  let f = bigf.kdecl in 
  let rec k decl = 
    match decl with 
    | DeclList (xs,ii) -> iif ii; List.iter aux xs 
    | MacroDecl ((s, args),ii) -> 
        iif ii;
        args +> List.iter (fun (e, ii) -> 
          iif ii;
          vk_argument bigf e
          );

        
  and aux ((var, t, sto), iicomma) = 
    iif iicomma;
    vk_type bigf t;
    var +> do_option (fun ((s, ini), ii_s_ini) -> 
      iif ii_s_ini;
      ini +> do_option (vk_ini bigf)
        );
  in f (k, bigf) d 

and vk_ini = fun bigf ini -> 
  let iif ii = vk_ii bigf ii in

  let rec inif x = bigf.kini (k, bigf) x 
  and k (ini, iini) = 
    iif iini;
    match ini with
    | InitExpr e -> vk_expr bigf e
    | InitList initxs -> 
        initxs +> List.iter (fun (ini, ii) -> 
          inif ini;
          iif ii;
        ) 
    | InitDesignators (xs, e) -> 
        xs +> List.iter (vk_designator bigf);
        inif e

    | InitFieldOld (s, e) -> inif e
    | InitIndexOld (e1, e) ->
        vk_expr bigf e1; inif e

  in inif ini


and vk_designator = fun bigf design -> 
  let iif ii = vk_ii bigf ii in
  let (designator, ii) = design in
  iif ii;
  match designator with
  | DesignatorField s -> ()
  | DesignatorIndex e -> vk_expr bigf e
  | DesignatorRange (e1, e2) -> vk_expr bigf e1; vk_expr bigf e2

and vk_struct_fields = fun bigf fields -> 
  let iif ii = vk_ii bigf ii in

  fields +> List.iter (fun (xfield, ii) -> 
    iif ii;
    match xfield with 
    | FieldDeclList onefield_multivars -> 
        onefield_multivars +> List.iter (fun (field, iicomma) ->
          iif iicomma;
          match field with
          | Simple (s, t), ii -> iif ii; vk_type bigf t;
          | BitField (sopt, t, expr), ii -> 
              iif ii;
              vk_expr bigf expr;
              vk_type bigf t 
        )
    | EmptyField -> ()
  )



and vk_def = fun bigf d -> 
  let iif ii = vk_ii bigf ii in

  let f = bigf.kdef in
  let rec k d = 
    match d with
    | (s, (returnt, (paramst, (b, iib))), sto, statxs), ii -> 
        iif ii;
        iif iib;
        vk_type bigf returnt;
        paramst +> List.iter (fun (param,iicomma) -> 
          vk_param bigf param;
          iif iicomma;
        );
        statxs +> List.iter (vk_statement bigf)
  in f (k, bigf) d 




and vk_program = fun bigf p -> 
  let f = bigf.kprogram in
  let iif ii =  vk_ii bigf ii in
  let rec k p = 
    match p with
    | Declaration decl -> (vk_decl bigf decl)
    | Definition def -> (vk_def bigf def)
    | EmptyDef ii -> iif ii
    | MacroTop (s, xs, ii) -> 
          xs +> List.iter (fun (elem, iicomma) -> 
            vk_argument bigf elem; iif iicomma
          );
          iif ii
          
    | Include ((s, ii), h_rel_pos) -> iif ii;
    | Define ((s,ii), (defkind, defval)) -> 
        iif ii;
        vk_define_kind bigf defkind;
        vk_define_val bigf defval

    | NotParsedCorrectly ii -> iif ii
    | FinalDef info -> vk_info bigf info
  in f (k, bigf) p

and vk_define_kind bigf defkind = 
  match defkind with
  | DefineVar -> ()
  | DefineFunc (params, ii) -> 
      vk_ii bigf ii;
      params +> List.iter (fun ((s,iis), iicomma) -> 
        vk_ii bigf iis;
        vk_ii bigf iicomma;
      )

and vk_define_val bigf defval = 
  match defval with
  | DefineExpr e -> 
      vk_expr bigf e
  | DefineStmt stmt -> vk_statement bigf stmt
  | DefineDoWhileZero (stmt, ii) -> 
      vk_statement bigf stmt;
      vk_ii bigf ii
  | DefineFunction def -> vk_def bigf def
  | DefineType ty -> vk_type bigf ty
  | DefineText (s, ii) -> vk_ii bigf ii
  | DefineEmpty -> ()

        

(* ------------------------------------------------------------------------ *)
(* Now keep fullstatement inside the control flow node, 
 * so that can then get in a MetaStmtVar the fullstatement to later
 * pp back when the S is in a +. But that means that 
 * Exp will match an Ifnode even if there is no such exp
 * inside the condition of the Ifnode (because the exp may
 * be deeper, in the then branch). So have to not visit
 * all inside a node anymore.
 * 
 * update: j'ai choisi d'accrocher au noeud du CFG à la
 * fois le fullstatement et le partialstatement et appeler le 
 * visiteur que sur le partialstatement.
 *)

and vk_node = fun bigf node -> 
  let iif ii = vk_ii bigf ii in
  let infof info = vk_info bigf info in

  let f = bigf.knode in
  let rec k n = 
    match F.unwrap n with

    | F.FunHeader ((idb, (rett, (paramst,(isvaargs,iidotsb))), stob),ii) ->
        vk_type bigf rett;
        paramst +> List.iter (fun (param, iicomma) ->
          vk_param bigf param;
          iif iicomma;
        );


    | F.Decl decl -> vk_decl bigf decl 
    | F.ExprStatement (st, (eopt, ii)) ->  
        iif ii;
        eopt +> do_option (vk_expr bigf)

    | F.IfHeader (_, (e,ii)) 
    | F.SwitchHeader (_, (e,ii))
    | F.WhileHeader (_, (e,ii))
    | F.DoWhileTail (e,ii) -> 
        iif ii;
        vk_expr bigf e

    | F.ForHeader (_st, (((e1opt,i1), (e2opt,i2), (e3opt,i3)), ii)) -> 
        iif i1; iif i2; iif i3;
        iif ii;
        e1opt +> do_option (vk_expr bigf);
        e2opt +> do_option (vk_expr bigf);
        e3opt +> do_option (vk_expr bigf);
    | F.MacroIterHeader (_s, ((s,es), ii)) -> 
        iif ii;
        es +> List.iter (fun (e, ii) -> 
          iif ii;
          vk_argument bigf e
        );
        
    | F.ReturnExpr (_st, (e,ii)) -> iif ii; vk_expr bigf e
        
    | F.Case  (_st, (e,ii)) -> iif ii; vk_expr bigf e
    | F.CaseRange (_st, ((e1, e2),ii)) -> 
        iif ii; vk_expr bigf e1; vk_expr bigf e2


    | F.CaseNode i -> ()

    | F.DefineExpr e  -> vk_expr bigf e
    | F.DefineType ft  -> vk_type bigf ft
    | F.DefineHeader ((s,ii), (defkind))  -> 
        iif ii;
        vk_define_kind bigf defkind;

    | F.DefineDoWhileZeroHeader (((),ii)) -> iif ii

    | F.Include ((s, ii),h_rel_pos) -> iif ii

    | F.Ifdef (st, ((),ii)) -> iif ii

    | F.Break    (st,((),ii)) -> iif ii
    | F.Continue (st,((),ii)) -> iif ii
    | F.Default  (st,((),ii)) -> iif ii
    | F.Return   (st,((),ii)) -> iif ii
    | F.Goto  (st, (s,ii)) -> iif ii
    | F.Label (st, (s,ii)) -> iif ii
    | F.EndStatement iopt -> do_option infof iopt
    | F.DoHeader (st, info) -> infof info
    | F.Else info -> infof info
    | F.SeqEnd (i, info) -> infof info
    | F.SeqStart (st, i, info) -> infof info

    | F.MacroStmt (st, ((),ii)) -> iif ii
    | F.Asm (st, (asmbody,ii)) -> 
        iif ii;
        vk_asmbody bigf asmbody

    | (
        F.TopNode|F.EndNode|
        F.ErrorExit|F.Exit|F.Enter|
        F.FallThroughNode|F.AfterNode|F.FalseNode|F.TrueNode|
        F.Fake
      ) -> ()



  in
  f (k, bigf) node

(* ------------------------------------------------------------------------ *)
and vk_info = fun bigf info -> 
  let rec infof ii = bigf.kinfo (k, bigf) ii
  and k i = ()
  in
  infof info

and vk_ii = fun bigf ii -> 
  List.iter (vk_info bigf) ii


and vk_param = fun bigf (((b, s, t), ii_b_s)) ->  
  let iif ii = vk_ii bigf ii in
  iif ii_b_s;
  vk_type bigf t


let vk_args_splitted = fun bigf args_splitted -> 
  let iif ii = vk_ii bigf ii in
  args_splitted +> List.iter (function  
  | Left arg -> vk_argument bigf arg
  | Right ii -> iif ii
  )


let vk_define_params_splitted = fun bigf args_splitted -> 
  let iif ii = vk_ii bigf ii in
  args_splitted +> List.iter (function  
  | Left (s, iis) -> vk_ii bigf iis
  | Right ii -> iif ii
  )



let vk_params_splitted = fun bigf args_splitted -> 
  let iif ii = vk_ii bigf ii in
  args_splitted +> List.iter (function  
  | Left arg -> vk_param bigf arg
  | Right ii -> iif ii
  )


let vk_cst = fun bigf (cst, ii) -> 
  let iif ii = vk_ii bigf ii in
  iif ii;
  (match cst with
  | Left cst -> ()
  | Right s -> ()
  )


  

(*****************************************************************************)
(* "syntetisized attributes" style *)
(*****************************************************************************)
type 'a inout = 'a -> 'a 

(* _s for synthetizized attributes 
 *
 * Note that I don't visit necesserally in the order of the token
 * found in the original file. So don't assume such hypothesis!
 *)
type visitor_c_s = { 
  kexpr_s:      (expression inout * visitor_c_s) -> expression inout;
  kstatement_s: (statement  inout * visitor_c_s) -> statement  inout;
  ktype_s:      (fullType   inout * visitor_c_s) -> fullType   inout;
  kini_s:  (initialiser  inout * visitor_c_s) -> initialiser inout; 

  kdecl_s: (declaration  inout * visitor_c_s) -> declaration inout;
  kdef_s:  (definition   inout * visitor_c_s) -> definition  inout; 

  kprogram_s: (toplevel inout * visitor_c_s) -> toplevel inout;
  knode_s: (F.node inout * visitor_c_s) -> F.node inout;

  kinfo_s: (info inout * visitor_c_s) -> info inout;
 } 

let default_visitor_c_s = 
  { kexpr_s =      (fun (k,_) e  -> k e);
    kstatement_s = (fun (k,_) st -> k st);
    ktype_s      = (fun (k,_) t  -> k t);
    kdecl_s      = (fun (k,_) d  -> k d);
    kdef_s       = (fun (k,_) d  -> k d);
    kini_s       = (fun (k,_) d  -> k d);
    kprogram_s   = (fun (k,_) p  -> k p);
    knode_s      = (fun (k,_) n  -> k n);
    kinfo_s      = (fun (k,_) i  -> k i);
  } 

let rec vk_expr_s = fun bigf expr ->
  let iif ii = vk_ii_s bigf ii in
  let rec exprf e = bigf.kexpr_s  (k, bigf) e
  and k e = 
    let ((unwrap_e, typ), ii) = e in
    (* don't analyse optional type
     * old:  typ +> map_option (vk_type_s bigf) in 
     *)
    let typ' = typ in 
    let e' = 
      match unwrap_e with
      | Ident (s) -> Ident (s)
      | Constant (c) -> Constant (c)
      | FunCall  (e, es)         -> 
          FunCall (exprf e,
                  es +> List.map (fun (e,ii) -> 
                    vk_argument_s bigf e, iif ii
                  ))
            
      | CondExpr (e1, e2, e3)    -> CondExpr (exprf e1, fmap exprf e2, exprf e3)
      | Sequence (e1, e2)        -> Sequence (exprf e1, exprf e2)
      | Assignment (e1, op, e2)  -> Assignment (exprf e1, op, exprf e2)
          
      | Postfix  (e, op) -> Postfix (exprf e, op)
      | Infix    (e, op) -> Infix   (exprf e, op)
      | Unary    (e, op) -> Unary   (exprf e, op)
      | Binary   (e1, op, e2) -> Binary (exprf e1, op, exprf e2)
          
      | ArrayAccess    (e1, e2) -> ArrayAccess (exprf e1, exprf e2)
      | RecordAccess   (e, s) -> RecordAccess     (exprf e, s) 
      | RecordPtAccess (e, s) -> RecordPtAccess   (exprf e, s) 

      | SizeOfExpr  (e) -> SizeOfExpr   (exprf e)
      | SizeOfType  (t) -> SizeOfType (vk_type_s bigf t)
      | Cast    (t, e) ->  Cast   (vk_type_s bigf t, exprf e)

      | StatementExpr (statxs, is) -> 
          StatementExpr (
            statxs +> List.map (vk_statement_s bigf),
            iif is)
      | Constructor (t, initxs) -> 
          Constructor 
            (vk_type_s bigf t, 
            (initxs +> List.map (fun (ini, ii) -> 
              vk_ini_s bigf ini, vk_ii_s bigf ii) 
            ))
                      
      | ParenExpr (e) -> ParenExpr (exprf e)

    in
    (e', typ'), (iif ii)
  in exprf expr

and vk_argument_s bigf argument = 
  let iif ii = vk_ii_s bigf ii in
  let rec do_action = function 
    | (ActMisc ii) -> ActMisc (iif ii)
  in
  (match argument with
  | Left e -> Left (vk_expr_s bigf e)
  | Right (ArgType param) ->    Right (ArgType (vk_param_s bigf param))
  | Right (ArgAction action) -> Right (ArgAction (do_action action))
  )






and vk_statement_s = fun bigf st -> 
  let rec statf st = bigf.kstatement_s (k, bigf) st 
  and k st = 
    let (unwrap_st, ii) = st in
    let st' = 
      match unwrap_st with
      | Labeled (Label (s, st)) -> 
          Labeled (Label (s, statf st))
      | Labeled (Case  (e, st)) -> 
          Labeled (Case  ((vk_expr_s bigf) e , statf st))
      | Labeled (CaseRange  (e, e2, st)) -> 
          Labeled (CaseRange  ((vk_expr_s bigf) e, 
                              (vk_expr_s bigf) e2, 
                              statf st))
      | Labeled (Default st) -> Labeled (Default (statf st))
      | Compound statxs -> 
          Compound (statxs +> List.map (vk_statement_s bigf))
      | ExprStatement (None) ->  ExprStatement (None)
      | ExprStatement (Some e) -> ExprStatement (Some ((vk_expr_s bigf) e))
      | Selection (If (e, st1, st2)) -> 
          Selection  (If ((vk_expr_s bigf) e, statf st1, statf st2))
      | Selection (Ifdef (st1s, st2s)) -> 
          Selection  (Ifdef 
                         (st1s +> List.map (vk_statement_s bigf),
                         st2s +> List.map (vk_statement_s bigf)))
      | Selection (Switch (e, st))   -> 
          Selection  (Switch ((vk_expr_s bigf) e, statf st))
      | Iteration (While (e, st))    -> 
          Iteration  (While ((vk_expr_s bigf) e, statf st))
      | Iteration (DoWhile (st, e))  -> 
          Iteration  (DoWhile (statf st, (vk_expr_s bigf) e))
      | Iteration (For ((e1opt,i1), (e2opt,i2), (e3opt,i3), st)) -> 
          let e1opt' = statf (ExprStatement (e1opt),i1) in
          let e2opt' = statf (ExprStatement (e2opt),i2) in
          let e3opt' = statf (ExprStatement (e3opt),i3) in
          (match (e1opt', e2opt', e3opt') with
          | ((ExprStatement x1,i1), (ExprStatement x2,i2), ((ExprStatement x3,i3))) -> 
              Iteration (For ((x1,i1), (x2,i2), (x3,i3), statf st))
          | x -> failwith "cant be here if iterator keep ExprStatement as is"
         )

      | Iteration  (MacroIteration (s, es, st)) -> 
          Iteration 
            (MacroIteration
                (s,
                es +> List.map (fun (e, ii) -> 
                  vk_argument_s bigf e, vk_ii_s bigf ii
                ), 
                statf st
                ))

            
      | Jump (Goto s) -> Jump (Goto s)
      | Jump (((Continue|Break|Return) as x)) -> Jump (x)
      | Jump (ReturnExpr e) -> Jump (ReturnExpr ((vk_expr_s bigf) e))
      | Jump (GotoComputed e) -> Jump (GotoComputed (vk_expr_s bigf e));

      | Decl decl -> Decl (vk_decl_s bigf decl)
      | Asm asmbody -> Asm (vk_asmbody_s bigf asmbody)
      | NestedFunc def -> NestedFunc (vk_def_s bigf def)
      | MacroStmt -> MacroStmt
    in
    st', vk_ii_s bigf ii
  in statf st

and vk_asmbody_s = fun bigf (string_list, colon_list) -> 
  let  iif ii = vk_ii_s bigf ii in

  iif string_list,
  colon_list +> List.map (fun (Colon xs, ii) -> 
    Colon 
      (xs +> List.map (fun (x, iicomma) -> 
        (match x with
        | ColonMisc, ii -> ColonMisc, iif ii 
        | ColonExpr e, ii -> ColonExpr (vk_expr_s bigf e), iif ii
        ), iif iicomma
      )), 
    iif ii 
  )
    
  


and vk_type_s = fun bigf t -> 
  let rec typef t = bigf.ktype_s (k,bigf) t
  and iif ii = vk_ii_s bigf ii
  and k t = 
    let (q, t) = t in
    let (unwrap_q, iiq) = q in
    let q' = unwrap_q in     (* todo? a visitor for qualifier *)
    let (unwrap_t, iit) = t in
    let t' = 
      match unwrap_t with
      | BaseType x -> BaseType x
      | Pointer t  -> Pointer (typef t)
      | Array (eopt, t) -> Array (fmap (vk_expr_s bigf) eopt, typef t) 
      | FunctionType (returnt, paramst) -> 
          FunctionType 
            (typef returnt, 
            (match paramst with
            | (ts, (b, iihas3dots)) -> 
                (ts +> List.map (fun (param,iicomma) -> 
                  (vk_param_s bigf param, iif iicomma)),
                (b, iif iihas3dots))
            ))

      | Enum  (sopt, enumt) -> 
          Enum (sopt,
               enumt +> List.map (fun (((s, eopt),ii_s_eq), iicomma) -> 
                 ((s, fmap (vk_expr_s bigf) eopt), iif ii_s_eq),
                 iif iicomma
               )
          )
      | StructUnion (sopt, su, fields) -> 
          StructUnion (sopt, su, vk_struct_fields_s bigf fields)


      | StructUnionName (s, structunion) -> StructUnionName (s, structunion)
      | EnumName  s -> EnumName  s
      | TypeName s -> TypeName s

      | ParenType t -> ParenType (typef t)
      | TypeOfExpr e -> TypeOfExpr (vk_expr_s bigf e)
      | TypeOfType t -> TypeOfType (typef t)
    in
    (q', iif iiq), 
  (t', iif iit)


  in typef t

and vk_decl_s = fun bigf d -> 
  let f = bigf.kdecl_s in 
  let iif ii = vk_ii_s bigf ii in
  let rec k decl = 
    match decl with
    | DeclList (xs, ii) -> 
        DeclList (List.map aux xs,   iif ii)
    | MacroDecl ((s, args),ii) -> 
        MacroDecl 
          ((s, 
           args +> List.map (fun (e,ii) -> vk_argument_s bigf e, iif ii)
           ),
          iif ii)


  and aux ((var, t, sto), iicomma) = 
    ((var +> map_option (fun ((s, ini), ii_s_ini) -> 
      (s, ini +> map_option (fun init -> vk_ini_s bigf init)),
      iif ii_s_ini
    )
    ),
    vk_type_s bigf t, 
    sto),
  iif iicomma

  in f (k, bigf) d 

and vk_ini_s = fun bigf ini -> 
  let rec inif ini = bigf.kini_s (k,bigf) ini
  and k ini = 
    let (unwrap_ini, ii) = ini in
    let ini' = 
      match unwrap_ini with
      | InitExpr e -> InitExpr (vk_expr_s bigf e)
      | InitList initxs -> 
          InitList (initxs +> List.map (fun (ini, ii) -> 
            inif ini, vk_ii_s bigf ii) 
          )


      | InitDesignators (xs, e) -> 
          InitDesignators 
            (xs +> List.map (vk_designator_s bigf),
            inif e 
            )

    | InitFieldOld (s, e) -> InitFieldOld (s, inif e)
    | InitIndexOld (e1, e) -> InitIndexOld (vk_expr_s bigf e1, inif e)

    in ini', vk_ii_s bigf ii
  in inif ini


and vk_designator_s = fun bigf design -> 
  let iif ii = vk_ii_s bigf ii in
  let (designator, ii) = design in
  (match designator with
  | DesignatorField s -> DesignatorField s
  | DesignatorIndex e -> DesignatorIndex (vk_expr_s bigf e)
  | DesignatorRange (e1, e2) -> 
      DesignatorRange (vk_expr_s bigf e1, vk_expr_s bigf e2)
  ), iif ii




and vk_struct_fields_s = fun bigf fields -> 

  let iif ii = vk_ii_s bigf ii in

  fields +> List.map (fun (xfield, iiptvirg) -> 
    
    (match xfield with
    | FieldDeclList onefield_multivars -> 
        FieldDeclList (
          onefield_multivars +> List.map (fun (field, iicomma) ->
            (match field with
            | Simple (s, t), iis -> Simple (s, vk_type_s bigf t), iif iis
            | BitField (sopt, t, expr), iis -> 
                BitField (sopt, vk_type_s bigf t, vk_expr_s bigf expr), 
                iif iis
            ), iif iicomma
          )
        )
    | EmptyField -> EmptyField
    ), iif iiptvirg
  )


and vk_def_s = fun bigf d -> 
  let f = bigf.kdef_s in
  let iif ii = vk_ii_s bigf ii in
  let rec k d = 
    match d with
    | (s, (returnt, (paramst, (b, iib))), sto, statxs), ii  -> 
        (s, 
        (vk_type_s bigf returnt, 
        (paramst +> List.map (fun (param, iicomma) ->
          (vk_param_s bigf param, iif iicomma)
        ), 
        (b, iif iib))), 
        sto, 
        statxs +> List.map (vk_statement_s bigf) 
        ),
        iif ii

  in f (k, bigf) d 

and vk_program_s = fun bigf p -> 
  let f = bigf.kprogram_s in
  let iif ii = vk_ii_s bigf ii in
  let iif ii =  iif ii in
  let rec k p = 
    match p with
    | Declaration decl -> Declaration (vk_decl_s bigf decl)
    | Definition def -> Definition (vk_def_s bigf def)
    | EmptyDef ii -> EmptyDef (iif ii)
    | MacroTop (s, xs, ii) -> 
        MacroTop
          (s, 
          xs +> List.map (fun (elem, iicomma) -> 
            vk_argument_s bigf elem, iif iicomma
          ),
          iif ii
          )
    | Include ((s, ii), h_rel_pos) -> Include ((s, iif ii), h_rel_pos)
    | Define ((s,ii), (defkind, defval)) -> 
        Define ((s, iif ii), 
               (vk_define_kind_s bigf defkind, vk_define_val_s bigf defval))

    | NotParsedCorrectly ii -> NotParsedCorrectly (iif ii)
    | FinalDef info -> FinalDef (vk_info_s bigf info)
  in f (k, bigf) p

and vk_define_kind_s  = fun bigf defkind -> 
  match defkind with
  | DefineVar -> DefineVar 
  | DefineFunc (params, ii) -> 
      DefineFunc 
        (params +> List.map (fun ((s,iis),iicomma) -> 
          ((s, vk_ii_s bigf iis), vk_ii_s bigf iicomma)
        ),
        vk_ii_s bigf ii
        )


and vk_define_val_s = fun bigf x -> 
  let iif ii = vk_ii_s bigf ii in
  match x with
  | DefineExpr e  -> DefineExpr (vk_expr_s bigf e)
  | DefineStmt st -> DefineStmt (vk_statement_s bigf st)
  | DefineDoWhileZero (st,ii) -> 
      DefineDoWhileZero (vk_statement_s bigf st, iif ii)
  | DefineFunction def -> DefineFunction (vk_def_s bigf def)
  | DefineType ty -> DefineType (vk_type_s bigf ty)
  | DefineText (s, ii) -> DefineText (s, iif ii)
  | DefineEmpty -> DefineEmpty
  

and vk_info_s = fun bigf info -> 
  let rec infof ii = bigf.kinfo_s (k, bigf) ii
  and k i = i
  in
  infof info

and vk_ii_s = fun bigf ii -> 
  List.map (vk_info_s bigf) ii

(* ------------------------------------------------------------------------ *)
and vk_node_s = fun bigf node -> 
  let iif ii = vk_ii_s bigf ii in
  let infof info = vk_info_s bigf info  in

  let rec nodef n = bigf.knode_s (k, bigf) n
  and k node = 
    F.rewrap node (
    match F.unwrap node with
    | F.FunHeader ((idb, (rett, (paramst,(isvaargs,iidotsb))), stob),ii) ->
        F.FunHeader 
          ((idb,
           (vk_type_s bigf rett,
           (paramst +> List.map (fun (param, iicomma) ->
             (vk_param_s bigf param, iif iicomma)
           ), (isvaargs,iif iidotsb))), stob),iif ii)
          
          
    | F.Decl declb -> F.Decl (vk_decl_s bigf declb)
    | F.ExprStatement (st, (eopt, ii)) ->  
        F.ExprStatement (st, (eopt +> map_option (vk_expr_s bigf), iif ii))
          
    | F.IfHeader (st, (e,ii))     -> 
        F.IfHeader    (st, (vk_expr_s bigf e, iif ii))
    | F.SwitchHeader (st, (e,ii)) -> 
        F.SwitchHeader(st, (vk_expr_s bigf e, iif ii))
    | F.WhileHeader (st, (e,ii))  -> 
        F.WhileHeader (st, (vk_expr_s bigf e, iif ii))
    | F.DoWhileTail (e,ii)  -> 
        F.DoWhileTail (vk_expr_s bigf e, iif ii)

    | F.ForHeader (st, (((e1opt,i1), (e2opt,i2), (e3opt,i3)), ii)) -> 
        F.ForHeader (st,
                    (((e1opt +> Common.map_option (vk_expr_s bigf), iif i1),
                     (e2opt +> Common.map_option (vk_expr_s bigf), iif i2),
                     (e3opt +> Common.map_option (vk_expr_s bigf), iif i3)),
                    iif ii))

    | F.MacroIterHeader (st, ((s,es), ii)) -> 
        F.MacroIterHeader
          (st,
          ((s, es +> List.map (fun (e, ii) -> vk_argument_s bigf e, iif ii)),
          iif ii))

          
    | F.ReturnExpr (st, (e,ii)) -> 
        F.ReturnExpr (st, (vk_expr_s bigf e, iif ii))
        
    | F.Case  (st, (e,ii)) -> F.Case (st, (vk_expr_s bigf e, iif ii))
    | F.CaseRange (st, ((e1, e2),ii)) -> 
        F.CaseRange (st, ((vk_expr_s bigf e1, vk_expr_s bigf e2), iif ii))

    | F.CaseNode i -> F.CaseNode i

    | F.DefineHeader((s,ii), (defkind)) -> 
        F.DefineHeader ((s, iif ii), (vk_define_kind_s bigf defkind))

    | F.DefineExpr e -> F.DefineExpr (vk_expr_s bigf e)
    | F.DefineType ft -> F.DefineType (vk_type_s bigf ft)
    | F.DefineDoWhileZeroHeader ((),ii) -> 
        F.DefineDoWhileZeroHeader ((),iif ii)

    | F.Include ((s, ii), h_rel_pos) -> F.Include ((s, iif ii), h_rel_pos)
    | F.Ifdef (st, ((),ii)) -> F.Ifdef (st, ((),iif ii))

    | F.MacroStmt (st, ((),ii)) -> F.MacroStmt (st, ((),iif ii))
    | F.Asm (st, (body,ii)) -> F.Asm (st, (vk_asmbody_s bigf body,iif ii))

    | F.Break    (st,((),ii)) -> F.Break    (st,((),iif ii))
    | F.Continue (st,((),ii)) -> F.Continue (st,((),iif ii))
    | F.Default  (st,((),ii)) -> F.Default  (st,((),iif ii))
    | F.Return   (st,((),ii)) -> F.Return   (st,((),iif ii))
    | F.Goto  (st, (s,ii)) -> F.Goto  (st, (s,iif ii))
    | F.Label (st, (s,ii)) -> F.Label (st, (s,iif ii))
    | F.EndStatement iopt -> F.EndStatement (map_option infof iopt)
    | F.DoHeader (st, info) -> F.DoHeader (st, infof info)
    | F.Else info -> F.Else (infof info)
    | F.SeqEnd (i, info) -> F.SeqEnd (i, infof info)
    | F.SeqStart (st, i, info) -> F.SeqStart (st, i, infof info)

    | (
        (
          F.TopNode|F.EndNode|
          F.ErrorExit|F.Exit|F.Enter|
          F.FallThroughNode|F.AfterNode|F.FalseNode|F.TrueNode|
          F.Fake
        ) as x) -> x


    )
  in
  nodef node
  
(* ------------------------------------------------------------------------ *)
and vk_param_s = fun bigf ((b, s, t), ii_b_s) -> 
  let iif ii = vk_ii_s bigf ii in
  ((b, s, vk_type_s bigf t), iif ii_b_s)
        
let vk_args_splitted_s = fun bigf args_splitted -> 
  let iif ii = vk_ii_s bigf ii in
  args_splitted +> List.map (function  
  | Left arg -> Left (vk_argument_s bigf arg)
  | Right ii -> Right (iif ii)
  )


let vk_params_splitted_s = fun bigf args_splitted -> 
  let iif ii = vk_ii_s bigf ii in
  args_splitted +> List.map (function  
  | Left arg -> Left (vk_param_s bigf arg)
  | Right ii -> Right (iif ii)
  )

let vk_define_params_splitted_s = fun bigf args_splitted -> 
  let iif ii = vk_ii_s bigf ii in
  args_splitted +> List.map (function  
  | Left (s, iis) -> Left (s, vk_ii_s bigf iis)
  | Right ii -> Right (iif ii)
  )

let vk_cst_s = fun bigf (cst, ii) -> 
  let iif ii = vk_ii_s bigf ii in
  (match cst with
  | Left cst -> Left cst 
  | Right s -> Right s
  ), iif ii
