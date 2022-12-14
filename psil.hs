-- TP-1  --- Implantation d'une sorte de Lisp          -*- coding: utf-8 -*-
--Ming-Xia Delvas 20104038
--François Corneau-Tremblay 20101907
{-# OPTIONS_GHC -Wall #-}

-- Ce fichier défini les fonctionalités suivantes:
-- - Analyseur lexical
-- - Analyseur syntaxique
-- - Pretty printer
-- - Implantation du langage

---------------------------------------------------------------------------
-- Importations de librairies et définitions de fonctions auxiliaires    --
---------------------------------------------------------------------------

import Text.ParserCombinators.Parsec -- Bibliothèque d'analyse syntaxique.
import Data.Char                -- Conversion de Chars de/vers Int et autres.
import System.IO                -- Pour stdout, hPutStr

---------------------------------------------------------------------------
-- La représentation interne des expressions de notre language           --
---------------------------------------------------------------------------
data Sexp = Snil                        -- La liste vide
          | Scons Sexp Sexp             -- Une paire
          | Ssym String                 -- Un symbole
          | Snum Int                    -- Un entier
          -- Génère automatiquement un pretty-printer et une fonction de
          -- comparaison structurelle.
          deriving (Show, Eq)

-- Exemples:
-- (+ 2 3)  ==  (((() . +) . 2) . 3)
--          ==>  Scons (Scons (Scons Snil (Ssym "+"))
--                            (Snum 2))
--                     (Snum 3)
--                   
-- (/ (* (- 68 32) 5) 9)
--     ==  (((() . /) . (((() . *) . (((() . -) . 68) . 32)) . 5)) . 9)
--     ==>
-- Scons (Scons (Scons Snil (Ssym "/"))
--              (Scons (Scons (Scons Snil (Ssym "*"))
--                            (Scons (Scons (Scons Snil (Ssym "-"))
--                                          (Snum 68))
--                                   (Snum 32)))
--                     (Snum 5)))
--       (Snum 9)

---------------------------------------------------------------------------
-- Analyseur lexical                                                     --
---------------------------------------------------------------------------

pChar :: Char -> Parser ()
pChar c = do { _ <- char c; return () }

-- Les commentaires commencent par un point-virgule et se terminent
-- à la fin de la ligne.
pComment :: Parser ()
pComment = do { pChar ';'; _ <- many (satisfy (\c -> not (c == '\n')));
                pChar '\n'; return ()
              }
-- N'importe quelle combinaison d'espaces et de commentaires est considérée
-- comme du blanc.
pSpaces :: Parser ()
pSpaces = do { _ <- many (do { _ <- space ; return () } <|> pComment); return () }

-- Un nombre entier est composé de chiffres.
integer     :: Parser Int
integer = do c <- digit
             integer' (digitToInt c)
          <|> do _ <- satisfy (\c -> (c == '-'))
                 n <- integer
                 return (- n)
    where integer' :: Int -> Parser Int
          integer' n = do c <- digit
                          integer' (10 * n + (digitToInt c))
                       <|> return n

pSymchar :: Parser Char
pSymchar    = alphaNum <|> satisfy (\c -> c `elem` "!@$%^&*_+-=:|/?<>")
pSymbol :: Parser Sexp
pSymbol= do { s <- many1 (pSymchar);
              return (case parse integer "" s of
                        Right n -> Snum n
                        _ -> Ssym s)
            }

---------------------------------------------------------------------------
-- Analyseur syntaxique                                                  --
---------------------------------------------------------------------------

-- La notation "'E" est équivalente à "(shorthand-quote E)"
-- La notation "`E" est équivalente à "(shorthand-backquote E)"
-- La notation ",E" est équivalente à "(shorthand-comma E)"
pQuote :: Parser Sexp
pQuote = do { c <- satisfy (\c -> c `elem` "'`,"); pSpaces; e <- pSexp;
              return (Scons
                      (Scons Snil
                             (Ssym (case c of
                                     ',' -> "shorthand-comma"
                                     '`' -> "shorthand-backquote"
                                     _   -> "shorthand-quote")))
                      e) }

-- Une liste (Tsil) est de la forme ( [e .] {e} )
pTsil :: Parser Sexp
pTsil = do _ <- char '('
           pSpaces
           (do { _ <- char ')'; return Snil }
            <|> do hd <- (do e <- pSexp
                             pSpaces
                             (do _ <- char '.'
                                 pSpaces
                                 return e
                              <|> return (Scons Snil e)))
                   pLiat hd)
    where pLiat :: Sexp -> Parser Sexp
          pLiat hd = do _ <- char ')'
                        return hd
                 <|> do e <- pSexp
                        pSpaces
                        pLiat (Scons hd e)

-- Accepte n'importe quel caractère: utilisé en cas d'erreur.
pAny :: Parser (Maybe Char)
pAny = do { c <- anyChar ; return (Just c) } <|> return Nothing

-- Une Sexp peut-être une liste, un symbol ou un entier.
pSexpTop :: Parser Sexp
pSexpTop = do { pTsil <|> pQuote <|> pSymbol
                <|> do { x <- pAny;
                         case x of
                           Nothing -> pzero
                           Just c -> error ("Unexpected char '" ++ [c] ++ "'")
                       }
              }

-- On distingue l'analyse syntaxique d'une Sexp principale de celle d'une
-- sous-Sexp: si l'analyse d'une sous-Sexp échoue à EOF, c'est une erreur de
-- syntaxe alors que si l'analyse de la Sexp principale échoue cela peut être
-- tout à fait normal.
pSexp :: Parser Sexp
pSexp = pSexpTop <|> error "Unexpected end of stream"

-- Une séquence de Sexps.
pSexps :: Parser [Sexp]
pSexps = do pSpaces
            many (do e <- pSexpTop
                     pSpaces
                     return e)

-- Déclare que notre analyseur syntaxique peut-être utilisé pour la fonction
-- générique "read".
instance Read Sexp where
    readsPrec _ s = case parse pSexp "" s of
                      Left _ -> []
                      Right e -> [(e,"")]

---------------------------------------------------------------------------
-- Sexp Pretty Printer                                                   --
---------------------------------------------------------------------------

showSexp' :: Sexp -> ShowS
showSexp' Snil = showString "()"
showSexp' (Snum n) = showsPrec 0 n
showSexp' (Ssym s) = showString s
showSexp' (Scons e1 e2) = showHead (Scons e1 e2) . showString ")"
    where showHead (Scons Snil e') = showString "(" . showSexp' e'
          showHead (Scons e1' e2')
            = showHead e1' . showString " " . showSexp' e2'
          showHead e = showString "(" . showSexp' e . showString " ."

-- On peut utiliser notre pretty-printer pour la fonction générique "show"
-- (utilisée par la boucle interactive de GHCi).  Mais avant de faire cela,
-- il faut enlever le "deriving Show" dans la déclaration de Sexp.
{-
instance Show Sexp where
    showsPrec p = showSexp'
-}

-- Pour lire et imprimer des Sexp plus facilement dans la boucle interactive
-- de Hugs/GHCi:
readSexp :: String -> Sexp
readSexp = read
showSexp :: Sexp -> String
showSexp e = showSexp' e ""

---------------------------------------------------------------------------
-- Représentation intermédiaire                                          --
---------------------------------------------------------------------------

type Var = String

data Ltype = Lint               -- Int
           | Lboo               -- Bool
           | Larw Ltype Ltype   -- τ₁ → τ₂
           | Ltup [Ltype]       -- tuple τ₁...τₙ
           deriving (Show, Eq)

data Lexp = Lnum Int                    -- Constante entière. Done.
          | Lvar Var                    -- Référence à une variable. Done.
          | Lhastype Lexp Ltype         -- Annotation de type. Done.
          | Lcall Lexp Lexp             -- Appel de fonction, avec un argument.
          | Lfun Var Lexp               -- Fonction anonyme prenant un argument.
          -- Déclaration d'une liste de variables qui peuvent être
          -- mutuellement récursives.
          | Llet [(Var, Lexp)] Lexp
          | Lif Lexp Lexp Lexp          -- Expression conditionelle.
          | Ltuple [Lexp]               -- Construction de tuple
          | Lfetch Lexp [Var] Lexp      -- lecture d'un tuple
          deriving (Show, Eq)


---------------------------------------------------------------------------
-- Conversion de Sexp à Lexp                                             --
---------------------------------------------------------------------------

sexp2list :: Sexp -> [Sexp]
sexp2list s = loop s []
    where
      loop (Scons hds tl) acc = loop hds (tl : acc)
      loop Snil acc = acc
      loop _ _ = error ("Improper list: " ++ show s)

-- Analyse une Sexp et construit une Lexp équivalente.
s2l :: Sexp -> Lexp
s2l (Snum n) = Lnum n
s2l (Ssym s) = Lvar s
s2l (se@(Scons _ _)) = case sexp2list se of
    (Ssym "hastype" : e : t : []) -> Lhastype (s2l e) (s2t t)
    (Ssym "call" : e1 : e2) -> case (e1:e2) of
                               [e1, e2] -> Lcall (s2l e1) (s2l e2)
    (Ssym "fun" : Ssym s : e) -> case e of
                                [e] -> Lfun s (s2l e)
    (Ssym "let" : Ssym s : e: []) -> Llet [(s, (s2l e))] (s2l e)
    (Ssym "if" : e1 : e2 : e3 : []) -> Lif (s2l e1) (s2l e2) (s2l e3) 
    (Ssym "tuple" : e) -> Ltuple (map s2l e)
    (Ssym "fetch" : Ssym s : e1 : e2) -> let f (x:y:xs) = case (x:y:xs) of
                                              [e1, e2] -> Lfetch (s2l e1)[s] (s2l e2)
					      [xs] -> Lfetch (s2l y)[s] (s2l xs)
					 in f e2
    _ -> error ("Unrecognized Psil expression: " ++ (showSexp se))
s2l se = error ("Unrecognized Psil expression: " ++ (showSexp se))

s2t :: Sexp -> Ltype
s2t (Ssym "Int") = Lint
s2t (Ssym "Bool") = Lboo
-- Larw contient retourne un ou plusieurs types 
s2t (se@(Scons _ _)) = case sexp2list se of
    (Ssym "Larw" : t1 : [t2]) -> Larw (s2t t1) (s2t t2)
    (Ssym "Ltup" : t) -> Ltup (map s2t t)
s2t s = error ("Unrecognized Psil type: " ++ (showSexp s))

---------------------------------------------------------------------------
-- Évaluateur                                                            --
---------------------------------------------------------------------------

-- Type des valeurs renvoyées par l'évaluateur.
data Value = Vnum Int
           | Vbool Bool
           | Vtuple [Value]
           | Vfun (Maybe String) (Value -> Value)

instance Show Value where
    showsPrec p (Vnum n) = showsPrec p n
    showsPrec p (Vbool b) = showsPrec p b
    showsPrec p (Vtuple vs) = showValues "[" vs
        where showValues _ [] = showString "]"
              showValues sep (v:vs')
                = showString sep . showsPrec p v . showValues " " vs'
    showsPrec _ (Vfun (Just n) _)
      = showString "<fun " . showString n . showString ">"
    showsPrec _ (Vfun Nothing _) = showString "<fun>"

type Env = [(Var, Value, Ltype)]

-- L'environnement initial qui contient les fonctions prédéfinies et leur type.
env0 :: Env
env0 = [prim "+"  (+) Vnum  Lint,
        prim "-"  (-) Vnum  Lint,
        prim "*"  (*) Vnum  Lint,
        prim "/"  div Vnum  Lint,
        prim "="  (==) Vbool Lboo,
        prim ">=" (>=) Vbool Lboo,
        prim "<=" (<=) Vbool Lboo]
       where prim name op cons typ
               = (name,
                  Vfun (Just name)
                       (\ (Vnum x) -> Vfun Nothing
                                          (\ (Vnum y) -> cons (x `op` y))),
                  Larw Lint (Larw Lint typ))

-- Point d'entrée de l'évaluation
eval :: Env -> Lexp -> Value
eval env e
  -- Extrait la liste des variables et la liste de leur valeurs,
  -- et ignore leurs types, qui n'est plus utile pendant l'évaluation.
  = eval2 (map (\(x,_,_) -> x) env) e (map (\(_,v,_) -> v) env)

e2lookup :: [Var] -> Var -> Int          -- Find position within environment
e2lookup env x = e2lookup' env 0
    where e2lookup' :: [Var] -> Int -> Int
          e2lookup' [] _ = error ("Variable inconnue: " ++ show x)
          e2lookup' (x':_) i | x == x' = i
          e2lookup' (_:xs) i = e2lookup' xs (i+1)

-------------- La fonction d'évaluation principale.  ------------------------
-- Au lieu de recevoir une liste de paires (Var, Val), on passe la liste
-- des noms de variables (`senv`) et la liste des valeurs correspondantes
-- (`venv`) séparément de manière à ce que (eval2 senv e) renvoie une
-- fonction qui a déjà fini d'utiliser `senv`.
eval2 :: [Var] -> Lexp -> ([Value] -> Value)
eval2 _    (Lnum n) = \_ -> Vnum n
eval2 senv (Lhastype e _) = eval2 senv e
eval2 senv (Lvar x)
  -- Calcule la position que la variable aura dans `venv`.
  = let i = e2lookup senv x
    -- Renvoie une fonction qui n'a plus besoin de charcher et comparer le nom.
    -- De cette manière, si la fonction renvoyée par (eval2 senv v) est appelée
    -- plusieurs fois, on aura fait la recherche dans `senv` une seule fois.
    in \venv -> venv !! i

eval2 senv (Lcall exp arg) = let func = eval2 senv exp in
                             let arg_eval = eval2 senv arg in
                             \venv -> case func venv of
                                      Vfun _ val ->
                                        let arg_val = arg_eval venv in
                                        val arg_val
                                      _ -> error "Can't call non-func"


eval2 _ _ = error "Not implemented yet"

---------------------------------------------------------------------------
-- Vérificateur de types                                                 --
---------------------------------------------------------------------------

type TEnv = [(Var, Ltype)]
type TypeError = String

-- Les valeurs ne servent à rien pendant la vérification de type,
-- donc extrait la partie utile de `env0`.
tenv0 :: TEnv
tenv0 = (map (\(x,_,t) -> (x,t)) env0)

tlookup :: [(Var, a)] -> Var -> a
tlookup [] x = error ("Variable inconnue: " ++ x)
tlookup ((x',t):_) x | x == x' = t
tlookup (_:env) x = tlookup env x

infer :: TEnv -> Lexp -> Ltype
infer _ (Lnum _) = Lint
infer tenv (Lvar x) = tlookup tenv x
infer _ (Lfun _ _)     = error "Can't infer type of `fun`"
infer _ (Lfetch _ _ _) = error "Can't infer type of `fetch`"
infer _ (Lif _ _ _)    = error "Can't infer type of `if`"

-- Infer for hastype. We take an expression and a type, if the infer type of
-- the expression matches the given type, we return it, otherwise, we raise
-- an error.
infer tenv (Lhastype exp t) = case check tenv exp t of
                                Nothing -> t
                                Just err -> error err

-- The type of a function is the same as the type of its return value.
infer tenv (Lcall e1 e2) = case infer tenv e1 of
                                (Larw t1 t2) -> case check tenv e2 t2 of
                                                    Nothing -> t2
                                                    Just err -> error err
                                _ -> error "Can't infer type of `call`, \
                                \ e1 is not of type t1 -> t2"

infer tenv (Llet vars e) = let nvars = map env_map vars in
                           let tenv' = concat [tenv, nvars] in
                               infer tenv' e
                           where env_map = (\(var, exp) ->
                                                (var, infer tenv exp))

infer tenv (Ltuple exps) = let ts = map (\exp -> infer tenv exp) exps in
                               Ltup ts

check :: TEnv -> Lexp -> Ltype -> Maybe TypeError
check tenv (Lfun x body) (Larw t1 t2) = check ((x,t1):tenv) body t2
check _ (Lfun _ _) t = Just ("Expected a function type: " ++ show t)
check tenv (Lif cond left right) t =
                            case check tenv cond Lboo of
                                Nothing -> case check tenv left t of
                                    Nothing -> case check tenv right t of
                                        Nothing -> Nothing
                                        Just err -> Just err
                                    Just err -> Just err
                                Just err -> Just err
check tenv (Lfetch tup vars exp) t = let tupt = infer tenv tup in
                                     case tupt of
                                     Ltup vars -> check tenv' exp t
                                     _ -> Just ("Expect a tuple of type:" ++
                                            show t)
                                     where varst = map (tlookup tenv) vars
                                           tenv' = concat [tenv, envvar]
                                           envvar = zip vars varst
					   
check tenv e t
  -- Essaie d'inférer le type et vérifie alors s'il correspond au
  -- type attendu.
  = let t' = infer tenv e
    in if t == t' then Nothing
       else Just ("Type mismatch: " ++ show t ++ " != " ++ show t')


---------------------------------------------------------------------------
-- Toplevel                                                              --
---------------------------------------------------------------------------

-- Lit un fichier contenant plusieurs Sexps, les évalues l'une après
-- l'autre, et renvoie la liste des valeurs obtenues.
run :: FilePath -> IO ()
run filename
  = do filestring <- readFile filename
       (hPutStr stdout)
           (let sexps s = case parse pSexps filename s of
                            Left _ -> [Ssym "#<parse-error>"]
                            Right es -> es
            in (concat
                (map (\ sexp -> let { ltyp = infer tenv0 lexp
                                   ; lexp = s2l sexp
                                   ; val = eval env0 lexp }
                               in "  " ++ show val
                                  ++ " : " ++ show ltyp ++ "\n")
                     (sexps filestring))))

sexpOf :: String -> Sexp
sexpOf = read

lexpOf :: String -> Lexp
lexpOf = s2l . sexpOf

typeOf :: String -> Ltype
typeOf = infer tenv0 . lexpOf

valOf :: String -> Value
valOf = eval env0 . lexpOf

main :: IO()
main = do
  run "tests.psil"
