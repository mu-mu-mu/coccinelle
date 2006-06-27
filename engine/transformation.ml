open Common open Commonop

open Ograph_extended

module A = Ast_cocci
module B = Ast_c

module F = Control_flow_c


(******************************************************************************)
(* todo:
 
 must do some try, for instance when f(...,X,Y,...) have to test the transfo for all
  the combinaitions (and if multiple transfo possible ? pb ? 
 => the type is to return a   expression option ? use some combinators to help ?

 for some nodes I dont have all the info, for instance for } 
  I need to modify the node of the start, it is where the info is.
  Same for Else
 
*)
(******************************************************************************)

type ('a, 'b) transformer = 'a -> 'b -> Ast_c.metavars_binding -> 'b

exception NoMatch 

type sequence_processing_style = Ordered | Unordered

(******************************************************************************)

let rec (transform_re_node: (Ast_cocci.rule_elem, Control_flow_c.node) transformer) = fun re (node, nodestr) -> 
  fun binding -> 

  match re, node with
  (* rene cant have found that a state containing a fake/exit/... should be transformed *)
  | _, F.Enter | _, F.Exit -> raise Impossible
  | _, F.Fake -> raise Impossible 
  | _, F.CaseNode _ -> raise Impossible
  | _, F.TrueNode | _, F.FalseNode | _, F.AfterNode | _, F.FallThroughNode -> raise Impossible

  | _, F.NestedFunCall _ -> raise Todo

  | A.SeqStart _mcode, F.StartBrace (level, statement) -> 
      pr2 "transformation: dont handle yet braces well. I pass them";
      F.StartBrace (level, statement), nodestr

  | A.SeqEnd _mcode, F.EndBrace level -> 
     (* problematic *)
      pr2 "transformation: dont handle yet braces well. I pass them";
      F.EndBrace (level), nodestr

  (* todo?: it can match a MetaStmt too !! and we have to get all the
     concerned nodes
   *)
  | _, F.StartBrace _ | _, F.EndBrace _  -> raise NoMatch

  | re, F.Statement st -> Control_flow_c.Statement (transform_re_st  re st  binding), nodestr
  | re, F.Declaration decl -> 
      F.Declaration (transform_de_decl re decl  binding), nodestr

  | re, F.HeadFunc funcdef -> 
      let (idb, typb, stob, compoundb, (infoidb, iistob, iicpb)) = funcdef in
      let (retb, paramsb, isvaargs, (iidotsb, iiparensb)) = typb in

      (match re with
      | A.FunHeader (stoa, ida, oparen, paramsa, cparen)  ->

          
          let stob' = (match stoa with None -> stob | Some x -> raise Todo) in
          let iistob' = iistob in (* todo *)

          let (idb', infoidb') = transform_ident ida (idb, [infoidb])   binding in

          let iiparensb' = tag_symbols [oparen;cparen] iiparensb binding in


          let seqstyle = (match paramsa with A.DOTS _ -> Ordered | A.CIRCLES _ -> Unordered | A.STARS _ -> raise Todo) in
          let paramsb' = transform_params seqstyle (A.undots paramsa) paramsb    binding in


          if isvaargs then raise Todo;
          let iidotsb' = iidotsb in (* todo *)

          let typb' = (retb, paramsb', isvaargs, (iidotsb', iiparensb')) in
          Control_flow_c.HeadFunc (idb', typb' , stob', compoundb, (List.hd infoidb', iistob', iicpb)), nodestr

      | _ -> raise NoMatch
      )




(* ------------------------------------------------------------------------------ *)

and (transform_re_st: (Ast_cocci.rule_elem, Ast_c.statement) transformer)  = fun re st -> 
  fun binding -> 

  match re, st with
  (* this is done in transform_re_node, or transform_re_decl *)
  | A.FunHeader _, _ -> raise Impossible 
  | A.Decl _, _ -> raise Impossible 
  | A.SeqStart _, _ -> raise Impossible 
  | A.SeqEnd _, _ -> raise Impossible 

  (* cas general: a Meta can match everything *)
  (* todo: if stb is a compound ? *)
  | A.MetaStmt ((ida,_,i1)),  stb -> raise Todo

  | A.MetaStmtList _, _ -> raise Todo

  | A.ExprStatement (ea, i1), (B.ExprStatement (Some eb), ii) -> 
      let ii' = tag_symbols [i1] ii  binding in
      B.ExprStatement (Some (transform_e_e ea eb  binding)), ii'

  | A.IfHeader (i1,i2, ea, i3), (B.Selection (B.If (eb, st1b, st2b)), ii) -> 
      let ii' = tag_symbols [i1;i2;i3] ii binding in
      B.Selection (B.If (transform_e_e ea eb  binding, st1b, st2b)), ii'

  | A.Else _, _ -> raise Todo

  | A.WhileHeader (_, _, ea, _), (B.Iteration  (B.While (eb, stb)), ii) -> 
      raise Todo

  | A.ForHeader (_, _, ea1opt, _, ea2opt, _, ea3opt, _), (B.Iteration  (B.For ((eb1opt,_), (eb2opt,_), (eb3opt,_), stb)), ii) -> 
      raise Todo


  | A.DoHeader _, (B.Iteration  (B.DoWhile (eb, stb)), ii) -> raise Todo
  | A.WhileTail _, _ -> raise Todo


  | A.Return _, (B.Jump (B.Return), ii) -> raise Todo
  | A.ReturnExpr _, (B.Jump (B.ReturnExpr e), ii) -> raise Todo




  (* It is important to put this case before the one that follows, cos
     want to transform a switch, even if cocci does not have a switch statement,
     because we may have put an Exp, and so have to transform the expressions
     inside the switch.
   *)
  | A.Exp exp, statement -> 
      (* todo?: assert have done something  statement' <> statement *)
      statement +> Visitor_c.visitor_statement_k_s { Visitor_c.default_visitor_c_continuation_s with
        Visitor_c.kexpr_s = (fun (k,_) e -> 
          let e' = k e in (* go inside first *)
          try transform_e_e exp e'   binding 
          with NoMatch -> e'
          )
          }

  | _, (B.ExprStatement (Some ec) , ii)                                     -> raise NoMatch
  | _, (B.Selection  (B.If (eb, st1b, st2b)), ii)                           -> raise NoMatch
  | _, (B.Iteration  (B.While (eb, stb)), ii)                               -> raise NoMatch
  | _, (B.Iteration  (B.For ((eb1opt,_), (eb2opt,_), (eb3opt,_), stb)), ii) -> raise NoMatch
  | _, (B.Iteration  (B.DoWhile (eb, stb)), ii)                             -> raise NoMatch
  | _, (B.Jump (B.Return), ii)                                              -> raise NoMatch
  | _, (B.Jump (B.ReturnExpr e), ii)                                        -> raise NoMatch

  | _, (B.Compound _, ii) -> raise Todo (* or Impossible ? *)

  | _, (B.ExprStatement None, ii) -> raise Todo

  (* have not a counter part in coccinelle, for the moment *)
  | _, (B.Labeled _, ii)              -> raise Impossible
  | _, (B.Asm , ii)                   -> raise Impossible
  | _, (B.Selection (B.Switch _), ii) -> raise Impossible
  | _, (B.Jump (B.Goto _), ii)        -> raise Impossible
  | _, (B.Jump (B.Break), ii)         -> raise Impossible
  | _, (B.Jump (B.Continue), ii)      -> raise Impossible

(* ------------------------------------------------------------------------------ *)

and (transform_de_decl: (Ast_cocci.rule_elem, Ast_c.declaration) transformer) = fun re decl -> 
  fun binding -> 
  match re, decl with
  | A.Decl (A.UnInit (typa, ida, ptvirga)), 
    (B.DeclList ([var], (iisto, iiptvirgb ))) -> 

      let iiptvirgb' = tag_symbols [ptvirga] [iiptvirgb] binding  in
      (match var with
      | (Some (idb, None, iidb), typb, stob), iivirg -> 
          let typb' = transform_ft_ft typa typb  binding in
          let (idb', iidb') = transform_ident ida (idb, [iidb])  binding in
          
          let var' = (Some (idb', None, List.hd iidb'), typb', stob), iivirg in
          B.DeclList ([var'], (iisto, List.hd iiptvirgb'))
          
      | _ -> raise Todo
      )
  | _ -> raise Todo
  
(* ------------------------------------------------------------------------------ *)

and (transform_e_e: (Ast_cocci.expression, Ast_c.expression) transformer) = fun ep ec -> 
  fun binding -> 
  
  match ep, ec with
  (* general case: a MetaExpr can match everything *)
  | A.MetaExpr ((ida,_,i1),_typeopt),  expb -> 
     (* get binding, assert =*=,  distribute info in i1 *)
      let v = binding +> List.assoc (ida : string) in
      (match v with
      | B.MetaExpr expa -> 
          if (expa =*= Ast_c.al_expr expb)
          then
            distribute_minus_plus_e i1 expb   binding
          else raise NoMatch
      | _ -> raise Impossible
      )

  | A.MetaConst _, _ -> raise Todo
  | A.MetaErr _, _ -> raise Todo
      
  | A.Ident ida,                ((B.Ident idb) , typ,ii) ->
      let (idb', ii') = transform_ident ida (idb, ii)   binding in
      (B.Ident idb', typ,ii')


  | A.Constant ((A.Int ia),i1,mc1) ,                ((B.Constant (B.Int ib) , typ,ii)) when ia =$= ib ->  
        let ii' = tag_symbols [ "fake", i1, mc1  ] ii binding in
        B.Constant (B.Int ib), typ,ii'
  | A.Constant ((A.Char ia),i1,mc1) ,                ((B.Constant (B.Char (ib,chartype)) , typ,ii)) when ia =$= ib ->  
        let ii' = tag_symbols [ "fake", i1, mc1  ] ii binding in
        B.Constant (B.Char (ib, chartype)), typ,ii'
  | A.Constant ((A.String ia),i1,mc1) ,                ((B.Constant (B.String (ib,stringtype)) , typ,ii)) when ia =$= ib ->  
        let ii' = tag_symbols [ "fake", i1, mc1 ] ii binding in
        B.Constant (B.String (ib, stringtype)), typ,ii'
  | A.Constant ((A.Float ia),i1,mc1) ,                ((B.Constant (B.Float (ib,ftyp)) , typ,ii)) when ia =$= ib ->  
        let ii' = tag_symbols [ "fake", i1, mc1  ] ii binding in
        B.Constant (B.Float (ib,ftyp)), typ,ii'


  | A.FunCall (ea, i2, eas, i3),  (B.FunCall (eb, ebs), typ,ii) -> 
      let ii' = tag_symbols [i2;i3] ii  binding in
      let eas' = A.undots eas in
      let seqstyle = (match eas with A.DOTS _ -> Ordered | A.CIRCLES _ -> Unordered | A.STARS _ -> raise Todo)  in
      
      B.FunCall (transform_e_e ea eb binding,  transform_arguments seqstyle eas' ebs   binding), typ,ii'


  | A.Assignment (ea1, (opa,_,_), ea2),   (B.Assignment (eb1, opb, eb2), typ,ii) -> 
      raise Todo
  | A.CondExpr (ea1, _, ea2opt, _, ea3), (B.CondExpr (eb1, eb2, eb3), typ,ii) -> 
      raise Todo

  | A.Postfix (ea, (opa,_,_)), (B.Postfix (eb, opb), typ,ii) -> 
      raise Todo
  | A.Infix (ea, (opa,_,_)), (B.Infix (eb, opb), typ,ii) -> 
      raise Todo
  | A.Unary (ea, (opa,_,_)), (B.Unary (eb, opb), typ,ii) -> 
      raise Todo


  | A.Binary (ea1, (opa,i1,mc1), ea2), (B.Binary (eb1, opb, eb2), typ,ii) -> 
      if (Pattern.equal_binaryOp opa opb)
      then 
        let ii' = tag_symbols ["fake", i1, mc1] ii binding in
        B.Binary (transform_e_e ea1 eb1   binding, opb,  transform_e_e ea2 eb2  binding),  typ, ii'
      else raise NoMatch


  | A.ArrayAccess (ea1, _, ea2, _), (B.ArrayAccess (eb1, eb2), typ,ii) -> 
      raise Todo
  | A.RecordAccess (ea, _, ida), (B.RecordAccess (eb, idb), typ,ii) ->
  raise Todo



  | A.RecordPtAccess (ea, fleche, ida), (B.RecordPtAccess (eb, idb), typ, ii) -> 
      (match ii with
      | [i1;i2] -> 
          let (idb', i2') = transform_ident ida (idb, [i2])   binding in
          let i1' = tag_symbols [fleche] [i1] binding in
          B.RecordPtAccess (transform_e_e ea eb binding, idb'), typ, i1' ++ i2'

      | _ -> raise Impossible
      )

  | A.Cast (_, typa, _, ea), (B.Cast (typb, eb), typ,ii) -> 
    raise Todo

  | A.Paren (_, ea, _), (B.ParenExpr (eb), typ,ii) -> 
    raise Todo

  | A.NestExpr _, _ -> raise Todo


  | A.MetaExprList _, _   -> raise Impossible (* only in arg lists *)

  | A.EComma _, _   -> raise Impossible (* can have EComma only in arg lists *)

  (* todo: in fact can also have the Edots family inside nest, as in if(<... x ... y ...>) *)
  | A.Edots _, _    -> raise Impossible (* can have EComma only in arg lists *)

  | A.Ecircles _, _ -> raise Impossible (* can have EComma only in arg lists *)
  | A.Estars _, _   -> raise Impossible (* can have EComma only in arg lists *)


  | A.DisjExpr eas, eb -> 
      raise Todo

  | A.MultiExp _, _ 
  | A.UniqueExp _,_
  | A.OptExp _,_ -> raise Todo


  (* because of Exp, cant put a raise Impossible,  have to put a raise NoMatch *)
  | _, (B.Ident idb , typ, ii) -> raise NoMatch
  | _, (B.Constant (B.String (sb, _)), typ,ii)     -> raise NoMatch
  | _, (B.Constant (B.Char   (sb, _)), typ,ii)   -> raise NoMatch
  | _, (B.Constant (B.Int    (sb)), typ,ii)     -> raise NoMatch
  | _, (B.Constant (B.Float  (sb, ftyp)), typ,ii) -> raise NoMatch
  | _, (B.FunCall (eb1, ebs), typ,ii) ->  raise NoMatch
  | _, (B.Assignment (eb1, opb, eb2), typ,ii) ->  raise NoMatch
  | _, (B.CondExpr (eb1, eb2, eb3), typ,ii) -> raise NoMatch
  | _, (B.Postfix (eb, opb), typ,ii) -> raise NoMatch
  | _, (B.Infix (eb, opb), typ,ii) -> raise NoMatch
  | _, (B.Unary (eb, opb), typ,ii) -> raise NoMatch
  | _, (B.Binary (eb1, opb, eb2), typ,ii) -> raise NoMatch 
  | _, (B.ArrayAccess (eb1, eb2), typ,ii) -> raise NoMatch
  | _, (B.RecordAccess (eb, idb), typ,ii) -> raise NoMatch
  | _, (B.RecordPtAccess (eb, idb), typ,ii) -> raise NoMatch
  | _, (B.Cast (typb, eb), typ,ii) -> raise NoMatch
  | _, (B.ParenExpr (eb), typ,ii) -> raise NoMatch


  (* have not a counter part in coccinelle, for the moment *)
  | _, (B.Sequence _,_,_) -> raise NoMatch
  | _, (B.SizeOfExpr _,_,_) -> raise NoMatch
  | _, (B.SizeOfType _,_,_) -> raise NoMatch

  | _, (B.StatementExpr _,_,_) -> raise NoMatch  (* todo ? *)
  | _, (B.Constructor,_,_) -> raise NoMatch
  | _, (B.NoExpr,_,_) -> raise NoMatch
  | _, (B.MacroCall _,_,_) -> raise NoMatch
  | _, (B.MacroCall2 _,_,_) -> raise NoMatch





(* ------------------------------------------------------------------------------ *)

and (transform_arguments: sequence_processing_style -> (Ast_cocci.expression list, ((Ast_c.expression, Ast_c.fullType * (Ast_c.storage * Ast_c.il)) Common.either * Ast_c.il) list) transformer)  = fun seqstyle eas ebs ->
  fun binding -> 
    (* TODO and when have dots ? *)
    match eas, ebs with
    | [], [] -> []

    | [ea], [Left eb, ii] -> 
        assert (null ii);
        [Left (transform_e_e ea eb binding),  []]

    | A.EComma i1::ea::eas,  (Left eb, ii)::ebs -> 
        let ii' = tag_symbols [i1] ii   binding in
        (Left (transform_e_e  ea eb binding), ii')::transform_arguments seqstyle eas ebs   binding
       
    | ea::eas,  (Left eb, ii)::ebs -> 
        assert (null ii);
        (Left (transform_e_e  ea eb binding), [])::transform_arguments seqstyle eas ebs   binding
    | _ -> raise Impossible


and (transform_params: sequence_processing_style -> (Ast_cocci.parameterTypeDef list, ((Ast_c.parameterTypeDef * Ast_c.il) list)) transformer) = fun seqstyle pas pbs ->
  fun binding -> 
    match pas, pbs with
    | [], [] -> []
    | [pa], [pb, ii] -> 
        assert (null ii);
        [transform_param pa pb binding, ii]
    | A.PComma i1::pa::pas, (pb, ii)::pbs -> 
        let ii' = tag_symbols [i1] ii binding in
        (transform_param pa pb binding, ii')::transform_params seqstyle pas pbs  binding

    | pa::pas, (pb, ii)::pbs -> 
        assert (null ii);
        ((transform_param pa pb binding),[])::transform_params seqstyle pas pbs binding

    | _ -> raise Impossible

and (transform_param: (Ast_cocci.parameterTypeDef, (Ast_c.parameterTypeDef)) transformer) = fun pa pb  -> 
  fun binding -> 
    match pa, pb with
    | A.Param (ida, typa), ((hasreg, idb, typb, (iihasreg, iidb))) -> 

        let (idb', iidb') = transform_ident ida (idb, [iidb])   binding in
        let typb' = transform_ft_ft typa typb binding in
        ((hasreg, idb', typb', (iihasreg, List.hd iidb'))) 
        
        
    | A.PComma _, _ -> raise Impossible
    | _ -> raise Todo

(* ------------------------------------------------------------------------------ *)
and (transform_ft_ft: (Ast_cocci.fullType, Ast_c.fullType) transformer) = fun typa typb -> 
  fun binding -> 
    match (typa,typb) with
    | (A.Type(cv,ty1),((qu,il),ty2)) ->
        (* TODO handle qualifier *)
        let typb' = transform_t_t ty1 typb  binding in
        typb'
    | _ -> raise Todo   


and (transform_t_t: (Ast_cocci.typeC, Ast_c.fullType) transformer) = fun typa typb -> 
  fun binding -> 
    match typa, typb with
      (* cas general *)
    | A.MetaType ida,  typb -> raise Todo
    | A.BaseType ((basea,i1,mc1), signaopt),   (qu, (B.BaseType baseb, ii)) -> 
       (* In ii there is a list, sometimes of length 1 or 2 or 3.
          And even if in baseb we have a Signed Int, that does not mean
          that ii is of length 2, cos Signed is the default, so
          if in signa we have Signed explicitely ? we cant "accrocher" this
          mcode to something :( 
          TODO
        *)

	let _transform_sign signa signb = 
          (match signa, signb with
          (* iso on sign, if not mentioned then free.  tochange? *)
          | None, _ -> []
          | Some (a,i1,mc1),  b -> 
              if Pattern.equal_sign a b
              then raise Todo
              else raise NoMatch
          ) in
        
        let qu' = qu in (* todo ? or done in transform_ft_ft ? *)
        qu', 
	(match basea, baseb with
        |  A.VoidType,  B.Void -> assert (signaopt = None); 
            let ii' = tag_symbols ["fake",i1,mc1] ii binding in
            (B.BaseType B.Void, ii')
	| A.CharType,  B.IntType B.CChar -> 
            let ii' = tag_symbols ["fake",i1,mc1] ii binding in
            (B.BaseType (B.IntType B.CChar), ii')
	| A.ShortType, B.IntType (B.Si (signb, B.CShort)) ->
            raise Todo
	| A.IntType,   B.IntType (B.Si (signb, B.CInt))   ->
            if List.length ii = 1 
            then 
              let ii' = tag_symbols ["fake",i1,mc1] ii binding in
              (B.BaseType (B.IntType (B.Si (signb, B.CInt))), ii')
                  
            else raise Todo
	| A.LongType,  B.IntType (B.Si (signb, B.CLong))  ->
            raise Todo
	| A.FloatType, B.FloatType (B.CFloat) -> 
            raise Todo
	| A.DoubleType, B.FloatType (B.CDouble) -> 
            raise Todo

        | _ -> raise NoMatch
            

        )
    | A.Pointer (typa, imult),            (qu, (B.Pointer typb, ii)) -> 
        let ii' = tag_symbols [imult] ii binding in
        let typb' = transform_ft_ft typa typb  binding in
        (qu, (B.Pointer typb', ii'))
        
    | A.Array (typa, _, eaopt, _), (qu, (B.Array (ebopt, typb), _)) -> 
        raise Todo
    | A.StructUnionName((sa,i1,mc1), (sua,i2,mc2)), (qu, (B.StructUnionName ((sb,level), sub), ii)) -> 
        if Pattern.equal_structUnion  sua sub && sa =$= sb
        then
          let ii' = tag_symbols ["fake",i2,mc2; sa,i1,mc1] ii  binding in
          (qu, (B.StructUnionName ((sb,level), sub), ii'))
        else raise NoMatch
        

    | A.TypeName (sa,i1,mc1),  (qu, (B.TypeName sb, ii)) ->
        if sa =$= sb
        then
          let ii' = tag_symbols [sa,i1,mc1] ii binding in
          qu, (B.TypeName sb, ii')
        else raise NoMatch
        
        

    | _ -> raise NoMatch

        


(* ------------------------------------------------------------------------------ *)

and (transform_ident: (Ast_cocci.ident, (string * Ast_c.il)) transformer) = fun ida (idb, ii) -> 
  fun binding -> 
    match ida, idb with
    | A.Id (sa,i1,mc1), sb when sa =$= sb -> 
        let ii' = tag_symbols [sa, i1, mc1] ii binding in
        idb, ii'

    | A.MetaId (ida,i1,mc1), sb -> 
      (* get binding, assert =*=,  distribute info in i1 *)
        let v = binding +> List.assoc (ida : string) in
      (match v with
      | B.MetaId sa -> 
          if(sa =$= sb) 
          then
            let ii' = tag_symbols [sa, i1, mc1] ii binding in
            idb, ii'
          else raise NoMatch
      | _ -> raise Impossible
      )
        
    | _ -> raise Todo



(******************************************************************************)

and (tag_symbols: (string Ast_cocci.mcode) list -> Ast_c.il -> Ast_c.metavars_binding -> Ast_c.il) = 
  fun xs ys binding ->
  assert (List.length xs = List.length ys);
  zip xs ys +> List.map (fun ((s1,_,x),   (s2, (oldmcode, oldenv))) -> 
    (* assert s1 = s2 ? no more cos now have some "fake" string *)
    (s2, (x, binding)))


and distribute_minus_plus_e mcode  expr binding = 
  match mcode with
  | Ast_cocci.MINUS (any_xxs) -> 
      distribute_minus_plus_e_apply_op 
        (minusize_token, add_left (any_xxs, binding), nothing_right)
        expr
  | Ast_cocci.CONTEXT (any_befaft) -> 
        (match any_befaft with
        | Ast_cocci.NOTHING -> expr

        | Ast_cocci.BEFORE xxs -> 
            distribute_minus_plus_e_apply_op
              (no_minusize, add_left (xxs, binding), nothing_right)
              expr
        | Ast_cocci.AFTER xxs ->  
            distribute_minus_plus_e_apply_op
              (no_minusize, nothing_left, add_right (xxs, binding))
              expr
        | Ast_cocci.BEFOREAFTER (xxs, yys) -> 
            distribute_minus_plus_e_apply_op
              (no_minusize, add_left (xxs, binding) , add_right (xxs, binding))
              expr
        )
  | Ast_cocci.PLUS -> raise Impossible

(* Could do the minus more easily by extending visitor_c.ml and adding a function applied
   to every mcode. But as I also need to do the add_left and add_right, which
   requires to do a different thing for each case, I have not defined this not-so-useful
   visitor.
*)
(* op = minusize operator, lop = stuff to do on the left, rop = stuff to do on the right *)
and distribute_minus_plus_e_apply_op (op, lop, rop) expr = 
  let rec aux (op, lop, rop) expr = match expr with
  | Ast_c.Constant (Ast_c.Int i),  typ,[i1] -> 
      Ast_c.Constant (Ast_c.Int i),  typ,[i1 +> op +> lop +> rop]
  | Ast_c.Ident s,  typ,[i1] -> 
      Ast_c.Ident s,  typ,[i1 +> op +> lop +> rop] 
  | Ast_c.FunCall (e, xs), typ,[i2;i3] -> 
      let xs' = xs +> List.map (function 
        | (Left e, ii) -> 
            Left (aux (op, nothing_left, nothing_right) e),
            (ii +> List.map op)
        | (Right e, ii) -> raise Todo
        ) in
       let e' =aux (op, lop, nothing_right) e in
        Ast_c.FunCall (e', xs'), typ,[i2 +> op; i3 +> op +> rop]

  | Ast_c.RecordPtAccess (e, id), typ, [i1;i2] -> 
      let e' = aux (op, lop, nothing_right) e in
      Ast_c.RecordPtAccess (e', id), typ, [i1 +> op; i2 +> op +> rop]
      
  | x -> raise Todo

  in aux (op, lop, rop) expr


  
and (minusize_token: Ast_c.info -> Ast_c.info) = fun (s, (mcode,env))  -> 
  let mcode' =
    match mcode with
    | Ast_cocci.CONTEXT (Ast_cocci.NOTHING) -> Ast_cocci.MINUS ([])
    | _ -> failwith "have already minused this token"
  in
  (s, (mcode', env))



and add_left (xxs, binding) = fun (s, (mcode,env))  -> 
  let mcode' = 
    match mcode with
    | Ast_cocci.MINUS ([]) -> Ast_cocci.MINUS (xxs)
    | Ast_cocci.MINUS (_) -> failwith "have already added stuff on this token"

    | Ast_cocci.CONTEXT (Ast_cocci.NOTHING) -> 
        Ast_cocci.CONTEXT (Ast_cocci.BEFORE xxs)
    | Ast_cocci.CONTEXT (Ast_cocci.AFTER yys) -> 
        Ast_cocci.CONTEXT (Ast_cocci.BEFOREAFTER (xxs, yys))
    | _ -> raise Impossible

  in
  s, (mcode', binding)


and add_right (yys, binding) = fun (s,(mcode,env))  -> 
  let mcode' = 
    match mcode with
    | Ast_cocci.MINUS ([]) -> 
        Ast_cocci.MINUS (yys)
    | Ast_cocci.MINUS (_) -> failwith "have already added stuff on this token"


    | Ast_cocci.CONTEXT (Ast_cocci.NOTHING) -> 
        Ast_cocci.CONTEXT (Ast_cocci.AFTER yys)
    | Ast_cocci.CONTEXT (Ast_cocci.BEFORE xxs) -> 
        Ast_cocci.CONTEXT (Ast_cocci.BEFOREAFTER (xxs, yys))
    | _ -> raise Impossible
  in
  s, (mcode', binding)


and no_minusize x = x
and nothing_right x = x
and nothing_left  x = x




(******************************************************************************)
(* Entry points *)

let rec (transform: 
       Lib_engine.transformation_info ->
       (Control_flow_c.node, Control_flow_c.edge) ograph_extended -> 
       (Control_flow_c.node, Control_flow_c.edge) ograph_extended
    ) = fun xs cflow -> 

     let cflow' = 
      (* find the node, transform, update the node,    and iter for all elements *)
      xs +> List.fold_left (fun acc (nodei, binding, rule_elem) -> 
        let node  = acc#nodes#assoc nodei in (* subtil: not cflow#nodes but acc#nodes *)
        pr2 "transform one node";
        let node' = transform_re_node rule_elem node binding in
        (* assert that have done something *)
        (* assert (not (node =*= node')); *)
        acc#replace_node (nodei, node')
        ) cflow
     in
     cflow'

