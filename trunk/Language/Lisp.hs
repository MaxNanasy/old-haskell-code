module Language.Lisp (main) where

import Language.Lisp.Monad
import Language.Lisp.Types

import Prelude hiding (read, print)

import Control.Monad

import Data.List
import Data.Maybe

import System.IO hiding (print)

mapLlist :: Function s -> OneParam s
mapLlist f (Cons aC dC) = do
  a <- f =<< readCell aC
  d <- mapLlist f =<< readCell dC
  cons a d
mapLlist _ Nil = return Nil
mapLlist _ _   = error "mapLlist: Not a list."

append :: TwoParam s
append Nil           ys = return ys
append (Cons xC xsC) ys = do
  x  <- readCell xC
  xs <- readCell xsC
  append xs ys >>= cons x
append _             _  = error "append: Not a list."

zipLlists :: TwoParam s
zipLlists Nil           _             = return Nil
zipLlists _             Nil           = return Nil
zipLlists (Cons xC xsC) (Cons yC ysC) = do
  x  <- readCell xC
  y  <- readCell yC
  xs <- readCell xsC
  ys <- readCell ysC
  pair <- cons x y
  rest <- zipLlists xs ys
  cons pair rest
zipLlists _             _             = error "zipLlists: Not a list."

lookupSymbol :: Environment s -> Object s -> Lisp s (Maybe (Cell s))
lookupSymbol env (Symbol name) = let
    lookupSymbol' :: Environment s -> Lisp s (Maybe (Cell s))
    lookupSymbol' Nil                 = return Nothing
    lookupSymbol' (Cons entryC restC) = do
                                   Cons keyC valueC <- readCell entryC
                                   (Symbol name')   <- readCell keyC
                                   if name == name' then return $ Just valueC else readCell restC >>= lookupSymbol'
    lookupSymbol' _                   = error "lookupSymbol: Environment is not a list."
  in do gEnv <- getGlobalEnvironment >>= readCell
        valueCM <- lookupSymbol' env
        case valueCM of
          Nothing -> lookupSymbol' gEnv
          Just _  -> return valueCM
lookupSymbol _   _             = error "lookupSymbol: Not a symbol."

eval :: Environment s -> OneParam s
eval env symbol@(Symbol name)     = lookupSymbol env symbol >>= maybe (error $ name ++ " not found.") readCell
eval env        (Cons funC argsC) = do
  fun <- eval env =<< readCell funC
  args <- readCell argsC
  case fun of
    SpecialOperator operator -> operator env args
    Function        function -> function =<< mapLlist (eval env) args
    Macro           macro    -> macro args >>= eval env
    _                        -> error "eval: Not a functional value."
eval _          x                 = return x

quote :: Environment s -> OneParam s
quote _ form = return form

lambda :: Environment s -> TwoParam s
lambda env params body = do
  (params', rest) <- deconstructLlist params
  let f args = do
        (args', Nil) <- deconstructLlist args
        env' <- case rest of
                     Nil -> zipLlists params' args' >>= (`append` env)
                     _   -> cons rest args          >>= (`cons`   env)
        eval env' body
  return (Function f)

defineFunction :: TwoParam s
defineFunction symbol value = do
  envC <- getGlobalEnvironment
  cons symbol value >>= push envC
  return value

car, cdr :: OneParam s
car (Cons aC _ ) = readCell aC
car _            = error "car: Not a cons."
cdr (Cons _  dC) = readCell dC
cdr _            = error "cdr: Not a cons."

cons :: TwoParam s
cons a d = liftM2 Cons (newCell a) (newCell d)

macroFunction :: OneParam s
macroFunction (Function f) = return $ Macro f
macroFunction _            = error "macro: Not a function."

apply :: TwoParam s
apply (Function f) args = f args
apply _            _    = error "apply: Not a function."

macroexpand1 :: TwoParam s
macroexpand1 (Macro macro) args = macro args
macroexpand1 _             _    = error "macroexpand-1: Not a macro."

deconstructLlist :: Object s -> Lisp s (Object s, Object s)
deconstructLlist (Cons aC dC) = do
  a <- readCell aC
  d <- readCell dC
  (xs, x)  <- deconstructLlist d
  d' <- cons a xs
  return (d', x)
deconstructLlist x            = return (Nil, x)

typeOf :: OneParam s
typeOf Function        {} = return $ Symbol "function"
typeOf Cons            {} = return $ Symbol "cons"
typeOf Nil                = return $ Symbol "nil"
typeOf SpecialOperator {} = return $ Symbol "special-operator"
typeOf Symbol          {} = return $ Symbol "symbol"
typeOf Macro           {} = return $ Symbol "macro"
typeOf Char            {} = return $ Symbol "char"

ifFunction :: ThreeParam s
ifFunction Nil (Function _) (Function e) = e Nil
ifFunction _   (Function t) (Function _) = t Nil
ifFunction _   _            _            = error "ifFunction: Not a function."

type OneParam s = Object s -> Lisp s (Object s)
oneParam :: String -> OneParam s -> Function s
oneParam fname f args =
  case args of
    Cons arg0C rest0C -> do
      rest0 <- readCell rest0C
      case rest0 of
        Nil -> do
          arg0 <- readCell arg0C
          f arg0
        _ -> error $ fname ++ ": Expected 1 argument; received more."
    _ -> error $ fname ++ ": Expected 1 argument; received 0."

type TwoParam s = Object s -> Object s -> Lisp s (Object s)
twoParam :: String -> TwoParam s -> Function s
twoParam fname f args =
  case args of
    Cons arg0C rest0C -> do
      rest0 <- readCell rest0C
      case rest0 of
        Cons arg1C rest1C -> do
          rest1 <- readCell rest1C
          case rest1 of
            Nil -> do
              arg0 <- readCell arg0C
              arg1 <- readCell arg1C
              f arg0 arg1
            _   -> error $ fname ++ ": Expected 2 arguments; received more."
        _ -> error $ fname ++ ": Expected 2 arguments; received 1."
    _ -> error $ fname ++ ": Expected 2 arguments; received 0."

type ThreeParam s = Object s -> Object s -> Object s -> Lisp s (Object s)
threeParam :: String -> ThreeParam s -> Function s
threeParam fname f args =
  case args of
    Cons arg0C rest0C -> do
      rest0 <- readCell rest0C
      case rest0 of
        Cons arg1C rest1C -> do
          rest1 <- readCell rest1C
          case rest1 of
            Cons arg2C rest2C -> do
              rest2 <- readCell rest2C
              case rest2 of
                Nil -> do
                  arg0 <- readCell arg0C
                  arg1 <- readCell arg1C
                  arg2 <- readCell arg2C
                  f arg0 arg1 arg2
                _ -> error $ fname ++ ": Expected 3 arguments; received more."
            _ -> error $ fname ++ ": Expected 3 arguments; received 2."
        _ -> error $ fname ++ ": Expected 2 arguments; received 1."
    _ -> error $ fname ++ ": Expected 2 arguments; received 0."

push :: Cell s -> OneParam s
push xsC x = do
  xs  <- readCell xsC
  xs' <- cons x xs
  writeCell xsC xs'
  return xs'

initializeGlobalEnvironment :: Lisp s ()
initializeGlobalEnvironment = do
  mapM_ (uncurry defineFunction)
            [ (Symbol "quote"        , SpecialOperator $ \ env -> oneParam "quote"  (quote  env)      )
            , (Symbol "lambda"       , SpecialOperator $ \ env -> twoParam "lambda" (lambda env)      )
            , (Symbol "macro"        , Function $ oneParam   "macro"         macroFunction            )
            , (Symbol "car"          , Function $ oneParam   "car"           car                      )
            , (Symbol "cdr"          , Function $ oneParam   "cdr"           cdr                      )
            , (Symbol "cons"         , Function $ twoParam   "cons"          cons                     )
            , (Symbol "type-of"      , Function $ oneParam   "type-of"       typeOf                   )
            , (Symbol "eval"         , Function $ oneParam   "eval"          (eval Nil)               )
            , (Symbol "macroexpand-1", Function $ twoParam   "macroexpand-1" macroexpand1             )
            , (Symbol "if-function"  , Function $ threeParam "if-function"   ifFunction               )
            , (Symbol "apply"        , Function $ twoParam   "apply"         apply                    )
            , (Symbol "append"       , Function $ twoParam   "append"        append                   )
            , (Symbol "define", Function $ twoParam   "define"        defineFunction                   )
            ]

main :: IO ()
main = getContents >>= putStr . run

runFile :: FilePath -> IO ()
runFile file = readFile file >>= putStr . run

run :: String -> String
run = snd . runLisp (initializeGlobalEnvironment >> repl)

repl :: Lisp s ()
repl = do
  form <- read
  case form of
    Symbol "END" -> return ()
    _            -> do
              result <- eval Nil form
              print result
              writeCharacter '\n'
              repl

isWhitespace :: Char -> Bool
isWhitespace = (`elem` " \t\n")

read :: Lisp s (Object s)
read = do
  c <- readCharacter
  case c of
      '\'' -> do 
        object <- read
        cons (Symbol "quote") =<< cons object Nil
      '(' -> do
        readDelimitedList ')' '.'
      '`' -> do
        object <- read
        cons (Symbol "quasiquote") =<< cons object Nil
      ',' -> do
        c' <- peekCharacter
        symbolName <- case c' of
          '@' -> readCharacter >> return "comma-splice"
          _   ->                  return "comma"
        form <- read
        cons (Symbol symbolName) =<< cons form Nil
      _ | isWhitespace      c -> read
        | isSymbolCharacter c -> do token <- readToken
                                    return $ Symbol $ c : token
        | otherwise           -> error $ "RAPE\nby #\\" ++ c : []

{-interpolateForm :: Object -> Object
interpolateForm form = interpolateForm' form Nil where
  interpolateForm' :: Object -> Object -> Object
  interpolateForm' (Cons (Symbol "comma"       ) (Cons form Nil)) k = Cons (Cons (Symbol "cons"  ) $ Cons form k) Nil
  interpolateForm' (Cons (Symbol "comma-splice") (Cons form Nil)) k = Cons (Cons (Symbol "append") $ Cons form k) Nil
  interpolateForm' (Cons a                       d              ) k = interpolateForm' a $ interpolateForm' d k
  interpolateForm' form                                           k = Cons (Cons (Symbol "cons"  ) $ Cons (Cons (Symbol "quote") $ Cons form Nil) k) Nil-}

skipWhitespace :: Lisp s ()
skipWhitespace = do
  c <- peekCharacter
  when (isWhitespace c) (readCharacter >> skipWhitespace)

isSymbolCharacter :: Char -> Bool
isSymbolCharacter = (`elem` ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ "+-*/")

readToken :: Lisp s String
readToken = do
  c <- peekCharacter
  if isSymbolCharacter c
    then do readCharacter
            token <- readToken
            return $ c : token
    else return ""

readDelimitedList :: Char -> Char -> Lisp s (Object s)
readDelimitedList c d = do
  skipWhitespace
  c' <- peekCharacter
  if c' == c
    then do readCharacter
            return Nil
    else if c' == d
         then do readCharacter
                 (Cons objectC _) <- readDelimitedList ')' '.'
                 readCell objectC
         else do object <- read
                 rest <- readDelimitedList c d
                 cons object rest

print :: OneParam s
print x = do
  case x of
    Function _ -> writeString "#<function>"
    Macro    _ -> writeString "#<macro>"
    Cons aC dC -> do
           a <- readCell aC
           d <- readCell dC
           let printNormally = do
                     (list, dot) <- deconstructLlist d
                     writeCharacter '('
                     print a
                     mapLlist (\ z -> writeCharacter ' ' >> print z) list
                     case dot of
                       Nil -> return ()
                       _   -> writeString " . " >> print dot >> return ()
                     writeCharacter ')'
           case d of
             Cons formC nilC -> do
                     nil <- readCell nilC
                     case nil of
                       Nil -> do
                         form <- readCell formC
                         case a of
                           Symbol "quote"        -> do
                                  writeCharacter '\''
                                  print form
                           Symbol "quasiquote"   -> do
                                  writeCharacter '`'
                                  print form
                           Symbol "comma"        -> do
                                  writeCharacter ','
                                  print form
                           Symbol "comma-splice" -> do
                                  writeString ",@"
                                  print form
                           _ -> printNormally >> return a
                         return ()
                       _  -> printNormally
             _ -> printNormally
    Nil          -> writeString "()"
    SpecialOperator _ -> writeString "#<special operator>"
    Symbol name  -> writeString name
    Char char    -> writeString "#\\" >> writeCharacter char
  return x
