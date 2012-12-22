{-# LANGUAGE CPP #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
#ifdef TRUSTWORTHY
{-# LANGUAGE Trustworthy #-}
#endif
----------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens.Fold
-- Copyright   :  (C) 2012 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  provisional
-- Portability :  Rank2Types
--
-- A @'Fold' s a@ is a generalization of something 'Foldable'. It allows
-- you to extract multiple results from a container. A 'Foldable' container
-- can be characterized by the behavior of
-- @foldMap :: ('Foldable' t, 'Monoid' m) => (a -> m) -> t a -> m@.
-- Since we want to be able to work with monomorphic containers, we could
-- generalize this signature to @forall m. 'Monoid' m => (a -> m) -> s -> m@,
-- and then decorate it with 'Accessor' to obtain
--
-- @type 'Fold' s a = forall m. 'Monoid' m => 'Getting' m s s a a@
--
-- Every 'Getter' is a valid 'Fold' that simply doesn't use the 'Monoid'
-- it is passed.
--
-- In practice the type we use is slightly more complicated to allow for
-- better error messages and for it to be transformed by certain
-- 'Applicative' transformers.
--
-- Everything you can do with a 'Foldable' container, you can with with a 'Fold' and there are
-- combinators that generalize the usual 'Foldable' operations here.
----------------------------------------------------------------------------
module Control.Lens.Fold
  (
  -- * Folds
    Fold
  , (^..)
  , (^?)
  , (^?!)
  , preview, previews
  , preuse, preuses
  , has, hasn't
  -- ** Building Folds
  , folding
  , folded
  , unfolded
  , iterated
  , filtered
  , backwards
  , repeated
  , replicated
  , cycled
  , takingWhile
  , droppingWhile
  -- ** Folding
  , foldMapOf, foldOf
  , foldrOf, foldlOf
  , toListOf
  , anyOf, allOf
  , andOf, orOf
  , productOf, sumOf
  , traverseOf_, forOf_, sequenceAOf_
  , mapMOf_, forMOf_, sequenceOf_
  , asumOf, msumOf
  , concatMapOf, concatOf
  , elemOf, notElemOf
  , lengthOf
  , nullOf, notNullOf
  , firstOf, lastOf
  , maximumOf, minimumOf
  , maximumByOf, minimumByOf
  , findOf
  , foldrOf', foldlOf'
  , foldr1Of, foldl1Of
  , foldrMOf, foldlMOf

  -- * Indexed Folds
  , IndexedFold
  , (^@..)
  , (^@?)
  , (^@?!)

  -- ** Consuming Indexed Folds
  , ifoldMapOf
  , ifoldrOf
  , ifoldlOf
  , ianyOf
  , iallOf
  , itraverseOf_
  , iforOf_
  , imapMOf_
  , iforMOf_
  , iconcatMapOf
  , ifindOf
  , ifoldrOf'
  , ifoldlOf'
  , ifoldrMOf
  , ifoldlMOf
  , itoListOf

  -- ** Converting to Folds
  , withIndicesOf
  , indicesOf

  -- ** Building Indexed Folds
  , ifiltering
  , itakingWhile
  , idroppingWhile

  -- ** Storing Folds
  , ReifiedFold(..)
  , ReifiedIndexedFold(..)

  -- * Deprecated
  , headOf
  ) where

import Control.Applicative as Applicative
import Control.Applicative.Backwards
import Control.Lens.Classes
import Control.Lens.Getter
import Control.Lens.Internal
import Control.Lens.Internal.Composition
import Control.Lens.Lens
import Control.Monad
import Control.Monad.Reader
import Control.Monad.State
import Data.Foldable as Foldable
import Data.Maybe
import Data.Monoid
import Data.Profunctor

-- $setup
-- >>> import Control.Lens
-- >>> import Data.List.Lens
-- >>> import Debug.SimpleReflect.Expr
-- >>> import Debug.SimpleReflect.Vars as Vars hiding (f,g)
-- >>> let f :: Expr -> Expr; f = Debug.SimpleReflect.Vars.f
-- >>> let g :: Expr -> Expr; g = Debug.SimpleReflect.Vars.g

{-# ANN module "HLint: ignore Eta reduce" #-}
{-# ANN module "HLint: ignore Use camelCase" #-}

infixl 8 ^.., ^?, ^?!, ^@.., ^@?, ^@?!

--------------------------
-- Folds
--------------------------

-- | A 'Fold' describes how to retrieve multiple values in a way that can be composed
-- with other lens-like constructions.
--
-- A @'Fold' s a@ provides a structure with operations very similar to those of the 'Foldable'
-- typeclass, see 'foldMapOf' and the other 'Fold' combinators.
--
-- By convention, if there exists a 'foo' method that expects a @'Foldable' (f a)@, then there should be a
-- @fooOf@ method that takes a @'Fold' s a@ and a value of type @s@.
--
-- A 'Getter' is a legal 'Fold' that just ignores the supplied 'Monoid'
--
-- Unlike a 'Control.Lens.Traversal.Traversal' a 'Fold' is read-only. Since a 'Fold' cannot be used to write back
-- there are no lens laws that apply.
type Fold s a = forall f. (Gettable f, Applicative f) => (a -> f a) -> s -> f s


-- | Obtain a 'Fold' by lifting an operation that returns a foldable result.
--
-- This can be useful to lift operations from @Data.List@ and elsewhere into a 'Fold'.
--
-- >>> [1,2,3,4]^..folding tail
-- [2,3,4]
folding :: (Foldable f, Applicative g, Gettable g) => (s -> f a) -> LensLike g s t a b
folding sfa agb = coerce . traverse_ agb . sfa
{-# INLINE folding #-}

-- | Obtain a 'Fold' from any 'Foldable'.
--
-- >>> Just 3^..folded
-- [3]
--
-- >>> Nothing^..folded
-- []
--
-- >>> [(1,2),(3,4)]^..folded.both
-- [1,2,3,4]
folded :: Foldable f => Fold (f a) a
folded f = coerce . getFolding . foldMap (Folding #. f)
{-# INLINE folded #-}

-- | Fold by repeating the input forever.
--
-- @'repeat' ≡ 'toListOf' 'repeated'@
--
-- >>> 5^..taking 20 repeated
-- [5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5]
repeated :: Fold a a
repeated f a = as where as = f a *> as
{-# INLINE repeated #-}

-- | A fold that replicates its input @n@ times.
--
-- @'replicate' n ≡ 'toListOf' ('replicated' n)@
--
-- >>> 5^..replicated 20
-- [5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5]
replicated :: Int -> Fold a a
replicated n0 f a = go n0 where
  m = f a
  go 0 = noEffect
  go n = m *> go (n - 1)
{-# INLINE replicated #-}

-- | Transform a fold into a fold that loops over its elements over and over.
--
-- >>> [1,2,3]^..taking 7 (cycled traverse)
-- [1,2,3,1,2,3,1]
cycled :: (Applicative f, Gettable f) => LensLike f s t a b -> LensLike f s t a b
cycled l f a = as where as = l f a *> as
{-# INLINE cycled #-}

-- | Build a fold that unfolds its values from a seed.
--
-- @'Prelude.unfoldr' ≡ 'toListOf' . 'unfolded'@
--
-- >>> 10^..unfolded (\b -> if b == 0 then Nothing else Just (b, b-1))
-- [10,9,8,7,6,5,4,3,2,1]
unfolded :: (b -> Maybe (a, b)) -> Fold b a
unfolded f g b0 = go b0 where
  go b = case f b of
    Just (a, b') -> g a *> go b'
    Nothing      -> noEffect
{-# INLINE unfolded #-}

-- | @x ^. 'iterated' f@ Return an infinite fold of repeated applications of @f@ to @x@.
--
-- @'toListOf' ('iterated' f) a ≡ 'iterate' f a@
iterated :: (a -> a) -> Fold a a
iterated f g a0 = go a0 where
  go a = g a *> go (f a)
{-# INLINE iterated #-}

-- | Obtain a 'Fold' that can be composed with to filter another 'Lens', 'Control.Lens.Iso.Iso', 'Getter', 'Fold' (or 'Control.Lens.Traversal.Traversal')
--
-- Note: This is /not/ a legal 'Control.Lens.Traversal.Traversal', unless you are very careful not to invalidate the predicate on the target.
--
-- As a counter example, consider that given @evens = 'filtered' 'even'@ the second 'Control.Lens.Traversal.Traversal' law is violated:
--
-- @'over' evens 'succ' '.' 'over' evens 'succ' /= 'over' evens ('succ' '.' 'succ')@
--
-- So, in order for this to qualify as a legal 'Traversal' you can only use it for actions that preserve the result of the predicate!
--
-- @'filtered' :: (a -> 'Bool') -> 'Fold' a a@
filtered :: Applicative f => (a -> Bool) -> LensLike' f a a
filtered p f a
  | p a       = f a
  | otherwise = pure a
{-# INLINE filtered #-}

-- | Obtain a 'Fold' by taking elements from another 'Fold', 'Lens', 'Control.Lens.Iso.Iso', 'Getter' or 'Control.Lens.Traversal.Traversal' while a predicate holds.
--
-- @'takeWhile' p ≡ 'toListOf' ('takingWhile' p 'folded')@
--
-- >>> toListOf (takingWhile (<=3) folded) [1..]
-- [1,2,3]
takingWhile :: (Gettable f, Applicative f)
            => (a -> Bool)
            -> Getting (Endo (f s)) s s a a
            -> LensLike f s s a a
takingWhile p l f = foldrOf l (\a r -> if p a then f a *> r else noEffect) noEffect
{-# INLINE takingWhile #-}


-- | Obtain a 'Fold' by dropping elements from another 'Fold', 'Lens', 'Control.Lens.Iso.Iso', 'Getter' or 'Control.Lens.Traversal.Traversal' while a predicate holds.
--
-- @'dropWhile' p ≡ 'toListOf' ('droppingWhile' p 'folded')@
--
-- >>> toListOf (droppingWhile (<=3) folded) [1..6]
-- [4,5,6]
--
-- >>> toListOf (droppingWhile (<=3) folded) [1,6,1]
-- [6,1]
droppingWhile :: (Gettable f, Applicative f)
              => (a -> Bool)
              -> Getting (Endo (f s, f s)) s s a a
              -> LensLike f s s a a
droppingWhile p l f = fst . foldrOf l (\a r -> let s = f a *> snd r in (if p a then fst r else s, s)) (noEffect, noEffect)
{-# INLINE droppingWhile #-}

--------------------------
-- Fold/Getter combinators
--------------------------

-- |
-- @'Data.Foldable.foldMap' = 'foldMapOf' 'folded'@
--
-- @'foldMapOf' ≡ 'views'@
--
-- @
-- 'foldMapOf' ::             'Getter' s a           -> (a -> r) -> s -> r
-- 'foldMapOf' :: 'Monoid' r => 'Fold' s a             -> (a -> r) -> s -> r
-- 'foldMapOf' ::             'Simple' 'Lens' s a      -> (a -> r) -> s -> r
-- 'foldMapOf' ::             'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r) -> s -> r
-- 'foldMapOf' :: 'Monoid' r => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r) -> s -> r
-- 'foldMapOf' :: 'Monoid' r => 'Simple' 'Control.Lens.Prism.Prism' s a     -> (a -> r) -> s -> r
-- @
foldMapOf :: Getting r s t a b -> (a -> r) -> s -> r
foldMapOf l f = runAccessor #. l (Accessor #. f)
{-# INLINE foldMapOf #-}

-- |
-- @'Data.Foldable.fold' = 'foldOf' 'folded'@
--
-- @'foldOf' ≡ 'view'@
--
-- @
-- 'foldOf' ::             'Getter' s m           -> s -> m
-- 'foldOf' :: 'Monoid' m => 'Fold' s m             -> s -> m
-- 'foldOf' ::             'Simple' 'Lens' s m      -> s -> m
-- 'foldOf' ::             'Simple' 'Control.Lens.Iso.Iso' s m       -> s -> m
-- 'foldOf' :: 'Monoid' m => 'Simple' 'Control.Lens.Traversal.Traversal' s m -> s -> m
-- 'foldOf' :: 'Monoid' m => 'Simple' 'Control.Lens.Prism.Prism' s m     -> s -> m
-- @
foldOf :: Getting a s t a b -> s -> a
foldOf l = runAccessor #. l Accessor
{-# INLINE foldOf #-}

-- |
-- Right-associative fold of parts of a structure that are viewed through a 'Lens', 'Getter', 'Fold' or 'Control.Lens.Traversal.Traversal'.
--
-- @'Data.Foldable.foldr' ≡ 'foldrOf' 'folded'@
--
-- @
-- 'foldrOf' :: 'Getter' s a           -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf' :: 'Fold' s a             -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf' :: 'Simple' 'Lens' s a      -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf' :: 'Simple' 'Control.Lens.Prism.Prism' s a     -> (a -> r -> r) -> r -> s -> r
-- @
foldrOf :: Getting (Endo r) s t a b -> (a -> r -> r) -> r -> s -> r
foldrOf l f z t = appEndo (foldMapOf l (Endo #. f) t) z
{-# INLINE foldrOf #-}

-- |
-- Left-associative fold of the parts of a structure that are viewed through a 'Lens', 'Getter', 'Fold' or 'Control.Lens.Traversal.Traversal'.
--
-- @'Data.Foldable.foldl' ≡ 'foldlOf' 'folded'@
--
-- @
-- 'foldlOf' :: 'Getter' s a           -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf' :: 'Fold' s a             -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf' :: 'Simple' 'Lens' s a      -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf' :: 'Simple' 'Control.Lens.Prism.Prism' s a     -> (r -> a -> r) -> r -> s -> r
-- @
foldlOf :: Getting (Dual (Endo r)) s t a b -> (r -> a -> r) -> r -> s -> r
foldlOf l f z t = appEndo (getDual (foldMapOf l (Dual #. Endo #. flip f) t)) z
{-# INLINE foldlOf #-}

-- | Extract a list of the targets of a 'Fold'. See also ('^..').
--
-- @
-- 'Data.Foldable.toList' ≡ 'toListOf' 'folded'
-- ('^..') ≡ 'flip' 'toListOf'
-- @

-- >>> toListOf both ("hello","world")
-- ["hello","world"]
--
-- @
-- 'toListOf' :: 'Getter' s a           -> s -> [a]
-- 'toListOf' :: 'Fold' s a             -> s -> [a]
-- 'toListOf' :: 'Simple' 'Lens' s a      -> s -> [a]
-- 'toListOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> [a]
-- 'toListOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> [a]
-- 'toListOf' :: 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> [a]
-- @
toListOf :: Getting (Endo [a]) s t a b -> s -> [a]
toListOf l = foldrOf l (:) []
-- toListOf l = foldMapOf l return
{-# INLINE toListOf #-}

-- |
--
-- A convenient infix (flipped) version of 'toListOf'.
--
-- >>> [[1,2],[3]]^..traverse.traverse
-- [1,2,3]
--
-- >>> (1,2)^..both
-- [1,2]
--
-- @
-- 'Data.Foldable.toList' xs ≡ xs '^..' 'folded'
-- ('^..') ≡ 'flip' 'toListOf'
-- @
--
-- @
-- ('^..') :: s -> 'Getter' s a           -> [a]
-- ('^..') :: s -> 'Fold' s a             -> [a]
-- ('^..') :: s -> 'Simple' 'Lens' s a      -> [a]
-- ('^..') :: s -> 'Simple' 'Control.Lens.Iso.Iso' s a       -> [a]
-- ('^..') :: s -> 'Simple' 'Control.Lens.Traversal.Traversal' s a -> [a]
-- ('^..') :: s -> 'Simple' 'Control.Lens.Prism.Prism' s a     -> [a]
-- @
(^..) :: s -> Getting (Endo [a]) s t a b -> [a]
s ^.. l = toListOf l s
{-# INLINE (^..) #-}

-- | Returns 'True' if every target of a 'Fold' is 'True'.
--
-- >>> andOf both (True,False)
-- False
-- >>> andOf both (True,True)
-- True
--
-- @'Data.Foldable.and' ≡ 'andOf' 'folded'@
--
-- @
-- 'andOf' :: 'Getter' s 'Bool'           -> s -> 'Bool'
-- 'andOf' :: 'Fold' s 'Bool'             -> s -> 'Bool'
-- 'andOf' :: 'Simple' 'Lens' s 'Bool'      -> s -> 'Bool'
-- 'andOf' :: 'Simple' 'Control.Lens.Iso.Iso' s 'Bool'       -> s -> 'Bool'
-- 'andOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s 'Bool' -> s -> 'Bool'
-- 'andOf' :: 'Simple' 'Control.Lens.Prism.Prism' s 'Bool'     -> s -> 'Bool'
-- @
andOf :: Getting All s t Bool b -> s -> Bool
andOf l = getAll #. foldMapOf l All
{-# INLINE andOf #-}

-- | Returns 'True' if any target of a 'Fold' is 'True'.
--
-- >>> orOf both (True,False)
-- True
-- >>> orOf both (False,False)
-- False
--
-- @'Data.Foldable.or' ≡ 'orOf' 'folded'@
--
-- @
-- 'orOf' :: 'Getter' s 'Bool'           -> s -> 'Bool'
-- 'orOf' :: 'Fold' s 'Bool'             -> s -> 'Bool'
-- 'orOf' :: 'Simple' 'Lens' s 'Bool'      -> s -> 'Bool'
-- 'orOf' :: 'Simple' 'Control.Lens.Iso.Iso' s 'Bool'       -> s -> 'Bool'
-- 'orOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s 'Bool' -> s -> 'Bool'
-- 'orOf' :: 'Simple' 'Control.Lens.Prism.Prism' s 'Bool'     -> s -> 'Bool'
-- @
orOf :: Getting Any s t Bool b -> s -> Bool
orOf l = getAny #. foldMapOf l Any
{-# INLINE orOf #-}

-- | Returns 'True' if any target of a 'Fold' satisfies a predicate.
--
-- >>> anyOf both (=='x') ('x','y')
-- True
-- >>> import Data.Data.Lens
-- >>> anyOf biplate (== "world") (((),2::Int),"hello",("world",11))
-- True
--
-- @'Data.Foldable.any' ≡ 'anyOf' 'folded'@
--
-- @
-- 'anyOf' :: 'Getter' s a               -> (a -> 'Bool') -> s -> 'Bool'
-- 'anyOf' :: 'Fold' s a                 -> (a -> 'Bool') -> s -> 'Bool'
-- 'anyOf' :: 'Simple' 'Lens' s a      -> (a -> 'Bool') -> s -> 'Bool'
-- 'anyOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> 'Bool') -> s -> 'Bool'
-- 'anyOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> 'Bool') -> s -> 'Bool'
-- 'anyOf' :: 'Simple' 'Control.Lens.Prism.Prism' s a     -> (a -> 'Bool') -> s -> 'Bool'
-- @
anyOf :: Getting Any s t a b -> (a -> Bool) -> s -> Bool
anyOf l f = getAny #. foldMapOf l (Any #. f)
{-# INLINE anyOf #-}

-- | Returns 'True' if every target of a 'Fold' satisfies a predicate.
--
-- >>> allOf both (>=3) (4,5)
-- True
-- >>> allOf folded (>=2) [1..10]
-- False
--
-- @'Data.Foldable.all' ≡ 'allOf' 'folded'@
--
-- @
-- 'allOf' :: 'Getter' s a           -> (a -> 'Bool') -> s -> 'Bool'
-- 'allOf' :: 'Fold' s a             -> (a -> 'Bool') -> s -> 'Bool'
-- 'allOf' :: 'Simple' 'Lens' s a      -> (a -> 'Bool') -> s -> 'Bool'
-- 'allOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> 'Bool') -> s -> 'Bool'
-- 'allOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> 'Bool') -> s -> 'Bool'
-- 'allOf' :: 'Simple' 'Control.Lens.Prism.Prism' s a     -> (a -> 'Bool') -> s -> 'Bool'
-- @
allOf :: Getting All s t a b -> (a -> Bool) -> s -> Bool
allOf l f = getAll #. foldMapOf l (All #. f)
{-# INLINE allOf #-}

-- | Calculate the product of every number targeted by a 'Fold'
--
-- >>> productOf both (4,5)
-- 20
-- >>> productOf folded [1,2,3,4,5]
-- 120
--
-- @'Data.Foldable.product' ≡ 'productOf' 'folded'@
--
-- @
-- 'productOf' ::          'Getter' s a           -> s -> a
-- 'productOf' :: 'Num' a => 'Fold' s a             -> s -> a
-- 'productOf' ::          'Simple' 'Lens' s a      -> s -> a
-- 'productOf' ::          'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> a
-- 'productOf' :: 'Num' a => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> a
-- 'productOf' :: 'Num' a => 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> a
-- @
productOf :: Getting (Product a) s t a b -> s -> a
productOf l = getProduct #. foldMapOf l Product
{-# INLINE productOf #-}

-- | Calculate the sum of every number targeted by a 'Fold'.
--
-- >>> sumOf both (5,6)
-- 11
-- >>> sumOf folded [1,2,3,4]
-- 10
-- >>> sumOf (folded.both) [(1,2),(3,4)]
-- 10
-- >>> import Data.Data.Lens
-- >>> sumOf biplate [(1::Int,[]),(2,[(3::Int,4::Int)])] :: Int
-- 10
--
-- @'Data.Foldable.sum' ≡ 'sumOf' 'folded'@
--
-- @
-- 'sumOf' '_1' :: (a, b) -> a
-- 'sumOf' ('folded' . '_1') :: ('Foldable' f, 'Num' a) => f (a, b) -> a
-- @
--
-- @
-- 'sumOf' ::          'Getter' s a           -> s -> a
-- 'sumOf' :: 'Num' a => 'Fold' s a             -> s -> a
-- 'sumOf' ::          'Simple' 'Lens' s a      -> s -> a
-- 'sumOf' ::          'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> a
-- 'sumOf' :: 'Num' a => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> a
-- 'sumOf' :: 'Num' a => 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> a
-- @
sumOf :: Getting (Sum a) s t a b -> s -> a
sumOf l = getSum #. foldMapOf l Sum
{-# INLINE sumOf #-}

-- | Traverse over all of the targets of a 'Fold' (or 'Getter'), computing an 'Applicative' (or 'Functor') -based answer,
-- but unlike 'Control.Lens.Traversal.traverseOf' do not construct a new structure. 'traverseOf_' generalizes
-- 'Data.Foldable.traverse_' to work over any 'Fold'.
--
-- When passed a 'Getter', 'traverseOf_' can work over any 'Functor', but when passed a 'Fold', 'traverseOf_' requires
-- an 'Applicative'.
--
-- >>> traverseOf_ both putStrLn ("hello","world")
-- hello
-- world
--
-- @'Data.Foldable.traverse_' ≡ 'traverseOf_' 'folded'@
--
-- @
-- 'traverseOf_' '_2' :: 'Functor' f => (c -> f r) -> (d, c) -> f ()
-- 'traverseOf_' 'Data.Either.Lens.traverseLeft' :: 'Applicative' f => (a -> f b) -> 'Either' a c -> f ()
-- @
--
-- The rather specific signature of 'traverseOf_' allows it to be used as if the signature was any of:
--
-- @
-- 'traverseOf_' :: 'Functor' f     => 'Getter' s a           -> (a -> f r) -> s -> f ()
-- 'traverseOf_' :: 'Applicative' f => 'Fold' s a             -> (a -> f r) -> s -> f ()
-- 'traverseOf_' :: 'Functor' f     => 'Simple' 'Lens' s a      -> (a -> f r) -> s -> f ()
-- 'traverseOf_' :: 'Functor' f     => 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> f r) -> s -> f ()
-- 'traverseOf_' :: 'Applicative' f => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> f r) -> s -> f ()
-- 'traverseOf_' :: 'Applicative' f => 'Simple' 'Control.Lens.Prism.Prism' s a     -> (a -> f r) -> s -> f ()
-- @
traverseOf_ :: Functor f => Getting (Traversed f) s t a b -> (a -> f r) -> s -> f ()
traverseOf_ l f = getTraversed #. foldMapOf l (Traversed #. void . f)
{-# INLINE traverseOf_ #-}

-- | Traverse over all of the targets of a 'Fold' (or 'Getter'), computing an 'Applicative' (or 'Functor') -based answer,
-- but unlike 'Control.Lens.Traversal.forOf' do not construct a new structure. 'forOf_' generalizes
-- 'Data.Foldable.for_' to work over any 'Fold'.
--
-- When passed a 'Getter', 'forOf_' can work over any 'Functor', but when passed a 'Fold', 'forOf_' requires
-- an 'Applicative'.
--
-- @'for_' ≡ 'forOf_' 'folded'@
--
-- The rather specific signature of 'forOf_' allows it to be used as if the signature was any of:
--
-- @
-- 'forOf_' :: 'Functor' f     => 'Getter' s a           -> s -> (a -> f r) -> f ()
-- 'forOf_' :: 'Applicative' f => 'Fold' s a             -> s -> (a -> f r) -> f ()
-- 'forOf_' :: 'Functor' f     => 'Simple' 'Lens' s a      -> s -> (a -> f r) -> f ()
-- 'forOf_' :: 'Functor' f     => 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> (a -> f r) -> f ()
-- 'forOf_' :: 'Applicative' f => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> (a -> f r) -> f ()
-- 'forOf_' :: 'Applicative' f => 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> (a -> f r) -> f ()
-- @
forOf_ :: Functor f => Getting (Traversed f) s t a b -> s -> (a -> f r) -> f ()
forOf_ = flip . traverseOf_
{-# INLINE forOf_ #-}

-- | Evaluate each action in observed by a 'Fold' on a structure from left to right, ignoring the results.
--
-- @'sequenceA_' ≡ 'sequenceAOf_' 'folded'@
--
-- @
-- 'sequenceAOf_' :: 'Functor' f     => 'Getter' s (f a)           -> s -> f ()
-- 'sequenceAOf_' :: 'Applicative' f => 'Fold' s (f a)             -> s -> f ()
-- 'sequenceAOf_' :: 'Functor' f     => 'Simple' 'Lens' s (f a)      -> s -> f ()
-- 'sequenceAOf_' :: 'Functor' f     => 'Simple' 'Iso' s (f a)       -> s -> f ()
-- 'sequenceAOf_' :: 'Applicative' f => 'Simple' 'Control.Lens.Traversal.Traversal' s (f a) -> s -> f ()
-- 'sequenceAOf_' :: 'Applicative' f => 'Simple' 'Control.Lens.Prism.Prism' s (f a)     -> s -> f ()
-- @
sequenceAOf_ :: Functor f => Getting (Traversed f) s t (f a) b -> s -> f ()
sequenceAOf_ l = getTraversed #. foldMapOf l (Traversed #. void)
{-# INLINE sequenceAOf_ #-}

-- | Map each target of a 'Fold' on a structure to a monadic action, evaluate these actions from left to right, and ignore the results.
--
-- @'Data.Foldable.mapM_' ≡ 'mapMOf_' 'folded'@
--
-- @
-- 'mapMOf_' :: 'Monad' m => 'Getter' s a           -> (a -> m r) -> s -> m ()
-- 'mapMOf_' :: 'Monad' m => 'Fold' s a             -> (a -> m r) -> s -> m ()
-- 'mapMOf_' :: 'Monad' m => 'Simple' 'Lens' s a      -> (a -> m r) -> s -> m ()
-- 'mapMOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> m r) -> s -> m ()
-- 'mapMOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> m r) -> s -> m ()
-- 'mapMOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Prism.Prism' s a     -> (a -> m r) -> s -> m ()
-- @
mapMOf_ :: Monad m => Getting (Sequenced m) s t a b -> (a -> m r) -> s -> m ()
mapMOf_ l f = getSequenced #. foldMapOf l (Sequenced #. liftM skip . f)
{-# INLINE mapMOf_ #-}

-- | 'forMOf_' is 'mapMOf_' with two of its arguments flipped.
--
-- @'Data.Foldable.forM_' ≡ 'forMOf_' 'folded'@
--
-- @
-- 'forMOf_' :: 'Monad' m => 'Getter' s a           -> s -> (a -> m r) -> m ()
-- 'forMOf_' :: 'Monad' m => 'Fold' s a             -> s -> (a -> m r) -> m ()
-- 'forMOf_' :: 'Monad' m => 'Simple' 'Lens' s a      -> s -> (a -> m r) -> m ()
-- 'forMOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> (a -> m r) -> m ()
-- 'forMOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> (a -> m r) -> m ()
-- 'forMOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> (a -> m r) -> m ()
-- @
forMOf_ :: Monad m => Getting (Sequenced m) s t a b -> s -> (a -> m r) -> m ()
forMOf_ = flip . mapMOf_
{-# INLINE forMOf_ #-}

-- | Evaluate each monadic action referenced by a 'Fold' on the structure from left to right, and ignore the results.
--
-- @'Data.Foldable.sequence_' ≡ 'sequenceOf_' 'folded'@
--
-- @
-- 'sequenceOf_' :: 'Monad' m => 'Getter' s (m a)           -> s -> m ()
-- 'sequenceOf_' :: 'Monad' m => 'Fold' s (m a)             -> s -> m ()
-- 'sequenceOf_' :: 'Monad' m => 'Simple' 'Lens' s (m a)      -> s -> m ()
-- 'sequenceOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Iso.Iso' s (m a)       -> s -> m ()
-- 'sequenceOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Traversal.Traversal' s (m a) -> s -> m ()
-- 'sequenceOf_' :: 'Monad' m => 'Simple' 'Control.Lens.Prism.Prism' s (m a)     -> s -> m ()
-- @
sequenceOf_ :: Monad m => Getting (Sequenced m) s t (m a) b -> s -> m ()
sequenceOf_ l = getSequenced #. foldMapOf l (Sequenced #. liftM skip)
{-# INLINE sequenceOf_ #-}

-- | The sum of a collection of actions, generalizing 'concatOf'.
--
-- @'asum' ≡ 'asumOf' 'folded'@
--
-- @
-- 'asumOf' :: 'Alternative' f => 'Getter' s a           -> s -> f a
-- 'asumOf' :: 'Alternative' f => 'Fold' s a             -> s -> f a
-- 'asumOf' :: 'Alternative' f => 'Simple' 'Lens' s a      -> s -> f a
-- 'asumOf' :: 'Alternative' f => 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> f a
-- 'asumOf' :: 'Alternative' f => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> f a
-- 'asumOf' :: 'Alternative' f => 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> f a
-- @
asumOf :: Alternative f => Getting (Endo (f a)) s t (f a) b -> s -> f a
asumOf l = foldrOf l (<|>) Applicative.empty
{-# INLINE asumOf #-}

-- | The sum of a collection of actions, generalizing 'concatOf'.
--
-- @'msum' ≡ 'msumOf' 'folded'@
--
-- @
-- 'msumOf' :: 'MonadPlus' m => 'Getter' s a           -> s -> m a
-- 'msumOf' :: 'MonadPlus' m => 'Fold' s a             -> s -> m a
-- 'msumOf' :: 'MonadPlus' m => 'Simple' 'Lens' s a      -> s -> m a
-- 'msumOf' :: 'MonadPlus' m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> m a
-- 'msumOf' :: 'MonadPlus' m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> m a
-- 'msumOf' :: 'MonadPlus' m => 'Simple' 'Control.Lens.Prism.Prism' s a     -> s -> m a
-- @
msumOf :: MonadPlus m => Getting (Endo (m a)) s t (m a) b -> s -> m a
msumOf l = foldrOf l mplus mzero
{-# INLINE msumOf #-}

-- | Does the element occur anywhere within a given 'Fold' of the structure?
--
-- >>> elemOf both "hello" ("hello","world")
-- True
--
-- @'elem' ≡ 'elemOf' 'folded'@
--
-- @
-- 'elemOf' :: 'Eq' a => 'Getter' s a           -> a -> s -> 'Bool'
-- 'elemOf' :: 'Eq' a => 'Fold' s a             -> a -> s -> 'Bool'
-- 'elemOf' :: 'Eq' a => 'Simple' 'Lens' s a      -> a -> s -> 'Bool'
-- 'elemOf' :: 'Eq' a => 'Simple' 'Control.Lens.Iso.Iso' s a       -> a -> s -> 'Bool'
-- 'elemOf' :: 'Eq' a => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> a -> s -> 'Bool'
-- 'elemOf' :: 'Eq' a => 'Simple' 'Control.Lens.Prism.Prism' s a     -> a -> s -> 'Bool'
-- @
elemOf :: Eq a => Getting Any s t a b -> a -> s -> Bool
elemOf l = anyOf l . (==)
{-# INLINE elemOf #-}

-- | Does the element not occur anywhere within a given 'Fold' of the structure?
--
-- @'notElem' ≡ 'notElemOf' 'folded'@
--
-- @
-- 'notElemOf' :: 'Eq' a => 'Getter' s a           -> a -> s -> 'Bool'
-- 'notElemOf' :: 'Eq' a => 'Fold' s a             -> a -> s -> 'Bool'
-- 'notElemOf' :: 'Eq' a => 'Simple' 'Control.Lens.Iso.Iso' s a       -> a -> s -> 'Bool'
-- 'notElemOf' :: 'Eq' a => 'Simple' 'Lens' s a      -> a -> s -> 'Bool'
-- 'notElemOf' :: 'Eq' a => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> a -> s -> 'Bool'
-- 'notElemOf' :: 'Eq' a => 'Simple' 'Control.Lens.Prism.Prism' s a     -> a -> s -> 'Bool'
-- @
notElemOf :: Eq a => Getting All s t a b -> a -> s -> Bool
notElemOf l = allOf l . (/=)
{-# INLINE notElemOf #-}

-- | Map a function over all the targets of a 'Fold' of a container and concatenate the resulting lists.
--
-- @'concatMap' ≡ 'concatMapOf' 'folded'@
--
-- @
-- 'concatMapOf' :: 'Getter' s a           -> (a -> [r]) -> s -> [r]
-- 'concatMapOf' :: 'Fold' s a             -> (a -> [r]) -> s -> [r]
-- 'concatMapOf' :: 'Simple' 'Lens' s a      -> (a -> [r]) -> s -> [r]
-- 'concatMapOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> [r]) -> s -> [r]
-- 'concatMapOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> [r]) -> s -> [r]
-- @
concatMapOf :: Getting [r] s t a b -> (a -> [r]) -> s -> [r]
concatMapOf l ces = runAccessor #. l (Accessor #. ces)
{-# INLINE concatMapOf #-}

-- | Concatenate all of the lists targeted by a 'Fold' into a longer list.
--
-- >>> concatOf both ("pan","ama")
-- "panama"
--
-- @
-- 'concat' ≡ 'concatOf' 'folded'
-- 'concatOf' ≡ 'view'
-- @
--
-- @
-- 'concatOf' :: 'Getter' s [r]           -> s -> [r]
-- 'concatOf' :: 'Fold' s [r]             -> s -> [r]
-- 'concatOf' :: 'Simple' 'Control.Lens.Iso.Iso' s [r]       -> s -> [r]
-- 'concatOf' :: 'Simple' 'Lens' s [r]      -> s -> [r]
-- 'concatOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s [r] -> s -> [r]
-- @
concatOf :: Getting [r] s t [r] b -> s -> [r]
concatOf = view
{-# INLINE concatOf #-}

-- |
-- Note: this can be rather inefficient for large containers.
--
-- @'length' ≡ 'lengthOf' 'folded'@
--
-- >>> lengthOf _1 ("hello",())
-- 1
--
-- @'lengthOf' ('folded' . 'folded') :: 'Foldable' f => f (g a) -> 'Int'@
--
-- @
-- 'lengthOf' :: 'Getter' s a           -> s -> 'Int'
-- 'lengthOf' :: 'Fold' s a             -> s -> 'Int'
-- 'lengthOf' :: 'Simple' 'Lens' s a      -> s -> 'Int'
-- 'lengthOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Int'
-- 'lengthOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Int'
-- @
lengthOf :: Getting (Sum Int) s t a b -> s -> Int
lengthOf l = getSum #. foldMapOf l (\_ -> Sum 1)
{-# INLINE lengthOf #-}

-- | Perform a safe 'head' of a 'Fold' or 'Control.Lens.Traversal.Traversal' or retrieve 'Just' the result
-- from a 'Getter' or 'Lens'.
--
-- When using a 'Control.Lens.Traversal.Traversal' as a partial 'Control.Lens.Lens.Lens', or a 'Fold' as a partial 'Getter' this can be a convenient
-- way to extract the optional value.
--
-- @('^?') ≡ 'flip' 'preview'@
--
-- @
-- ('^?') :: s -> 'Getter' s a           -> 'Maybe' a
-- ('^?') :: s -> 'Fold' s a             -> 'Maybe' a
-- ('^?') :: s -> 'Simple' 'Lens' s a      -> 'Maybe' a
-- ('^?') :: s -> 'Simple' 'Control.Lens.Iso.Iso' s a       -> 'Maybe' a
-- ('^?') :: s -> 'Simple' 'Control.Lens.Traversal.Traversal' s a -> 'Maybe' a
-- @
(^?) :: s -> Getting (First a) s t a b -> Maybe a
a ^? l = getFirst (foldMapOf l (First #. Just) a)
{-# INLINE (^?) #-}

-- | Perform an *UNSAFE* 'head' of a 'Fold' or 'Control.Lens.Traversal.Traversal' assuming that it is there.
--
-- @
-- ('^?!') :: s -> 'Getter' s a           -> a
-- ('^?!') :: s -> 'Fold' s a             -> a
-- ('^?!') :: s -> 'Simple' 'Lens' s a      -> a
-- ('^?!') :: s -> 'Simple' 'Control.Lens.Iso.Iso' s a       -> a
-- ('^?!') :: s -> 'Simple' 'Control.Lens.Traversal.Traversal' s a -> a
-- @
(^?!) :: s -> Getting (First a) s t a b -> a
a ^?! l = fromMaybe (error "(^?!): empty Fold") $ getFirst (foldMapOf l (First #. Just) a)
{-# INLINE (^?!) #-}

-- | Retrieve the 'First' entry of a 'Fold' or 'Control.Lens.Traversal.Traversal' or retrieve 'Just' the result
-- from a 'Getter' or 'Lens'.
--
-- @
-- 'firstOf' :: 'Getter' s a           -> s -> 'Maybe' a
-- 'firstOf' :: 'Fold' s a             -> s -> 'Maybe' a
-- 'firstOf' :: 'Simple' 'Lens' s a      -> s -> 'Maybe' a
-- 'firstOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Maybe' a
-- 'firstOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Maybe' a
-- @
firstOf :: Getting (First a) s t a b -> s -> Maybe a
firstOf l = getFirst #. foldMapOf l (First #. Just)
{-# INLINE firstOf #-}

-- | Retrieve the 'Last' entry of a 'Fold' or 'Control.Lens.Traversal.Traversal' or retrieve 'Just' the result
-- from a 'Getter' or 'Lens'.
--
-- @
-- 'lastOf' :: 'Getter' s a           -> s -> 'Maybe' a
-- 'lastOf' :: 'Fold' s a             -> s -> 'Maybe' a
-- 'lastOf' :: 'Simple' 'Lens' s a      -> s -> 'Maybe' a
-- 'lastOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Maybe' a
-- 'lastOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Maybe' a
-- @
lastOf :: Getting (Last a) s t a b -> s -> Maybe a
lastOf l = getLast #. foldMapOf l (Last #. Just)
{-# INLINE lastOf #-}

-- |
-- Returns 'True' if this 'Fold' or 'Control.Lens.Traversal.Traversal' has no targets in the given container.
--
-- Note: 'nullOf' on a valid 'Control.Lens.Iso.Iso', 'Lens' or 'Getter' should always return 'False'
--
-- @'null' ≡ 'nullOf' 'folded'@
--
-- This may be rather inefficient compared to the 'null' check of many containers.
--
-- >>> nullOf _1 (1,2)
-- False
--
-- @'nullOf' ('folded' '.' '_1' '.' 'folded') :: 'Foldable' f => f (g a, b) -> 'Bool'@
--
-- @
-- 'nullOf' :: 'Getter' s a           -> s -> 'Bool'
-- 'nullOf' :: 'Fold' s a             -> s -> 'Bool'
-- 'nullOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Bool'
-- 'nullOf' :: 'Simple' 'Lens' s a      -> s -> 'Bool'
-- 'nullOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Bool'
-- @
nullOf :: Getting All s t a b -> s -> Bool
nullOf l = getAll #. foldMapOf l (\_ -> All False)
{-# INLINE nullOf #-}


-- |
-- Returns 'True' if this 'Fold' or 'Control.Lens.Traversal.Traversal' has any targets in the given container.
--
-- Note: 'notNullOf' on a valid 'Control.Lens.Iso.Iso', 'Lens' or 'Getter' should always return 'True'
--
-- @'null' ≡ 'notNullOf' 'folded'@
--
-- This may be rather inefficient compared to the @'not' . 'null'@ check of many containers.
--
-- >>> notNullOf _1 (1,2)
-- True
--
-- @'notNullOf' ('folded' '.' '_1' '.' 'folded') :: 'Foldable' f => f (g a, b) -> 'Bool'@
--
-- @
-- 'notNullOf' :: 'Getter' s a           -> s -> 'Bool'
-- 'notNullOf' :: 'Fold' s a             -> s -> 'Bool'
-- 'notNullOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Bool'
-- 'notNullOf' :: 'Simple' 'Lens' s a      -> s -> 'Bool'
-- 'notNullOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Bool'
-- @
notNullOf :: Getting Any s t a b -> s -> Bool
notNullOf l = getAny #. foldMapOf l (\_ -> Any True)
{-# INLINE notNullOf #-}

-- |
-- Obtain the maximum element (if any) targeted by a 'Fold' or 'Control.Lens.Traversal.Traversal'
--
-- Note: maximumOf on a valid 'Control.Lens.Iso.Iso', 'Lens' or 'Getter' will always return 'Just' a value.
--
-- @'maximum' ≡ 'fromMaybe' ('error' \"empty\") '.' 'maximumOf' 'folded'@
--
-- @
-- 'maximumOf' ::          'Getter' s a           -> s -> 'Maybe' a
-- 'maximumOf' :: 'Ord' a => 'Fold' s a             -> s -> 'Maybe' a
-- 'maximumOf' ::          'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Maybe' a
-- 'maximumOf' ::          'Simple' 'Lens' s a      -> s -> 'Maybe' a
-- 'maximumOf' :: 'Ord' a => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Maybe' a
-- @
maximumOf :: Getting (Max a) s t a b -> s -> Maybe a
maximumOf l = getMax . foldMapOf l Max
{-# INLINE maximumOf #-}

-- |
-- Obtain the minimum element (if any) targeted by a 'Fold' or 'Control.Lens.Traversal.Traversal'
--
-- Note: minimumOf on a valid 'Control.Lens.Iso.Iso', 'Lens' or 'Getter' will always return 'Just' a value.
--
-- @'minimum' ≡ 'Data.Maybe.fromMaybe' ('error' \"empty\") '.' 'minimumOf' 'folded'@
--
-- @
-- 'minimumOf' ::          'Getter' s a           -> s -> 'Maybe' a
-- 'minimumOf' :: 'Ord' a => 'Fold' s a             -> s -> 'Maybe' a
-- 'minimumOf' ::          'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Maybe' a
-- 'minimumOf' ::          'Simple' 'Lens' s a      -> s -> 'Maybe' a
-- 'minimumOf' :: 'Ord' a => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Maybe' a
-- @
minimumOf :: Getting (Min a) s t a b -> s -> Maybe a
minimumOf l = getMin . foldMapOf l Min
{-# INLINE minimumOf #-}

-- |
-- Obtain the maximum element (if any) targeted by a 'Fold', 'Control.Lens.Traversal.Traversal', 'Lens', 'Control.Lens.Iso.Iso',
-- or 'Getter' according to a user supplied ordering.
--
-- @'Data.Foldable.maximumBy' cmp ≡ 'Data.Maybe.fromMaybe' ('error' \"empty\") '.' 'maximumByOf' 'folded' cmp@
--
-- @
-- 'maximumByOf' :: 'Getter' s a           -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'maximumByOf' :: 'Fold' s a             -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'maximumByOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'maximumByOf' :: 'Simple' 'Lens' s a      -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'maximumByOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- @
maximumByOf :: Getting (Endo (Maybe a)) s t a b -> (a -> a -> Ordering) -> s -> Maybe a
maximumByOf l cmp = foldrOf l step Nothing where
  step a Nothing  = Just a
  step a (Just b) = Just (if cmp a b == GT then a else b)
{-# INLINE maximumByOf #-}

-- |
-- Obtain the minimum element (if any) targeted by a 'Fold', 'Control.Lens.Traversal.Traversal', 'Lens', 'Control.Lens.Iso.Iso'
-- or 'Getter' according to a user supplied ordering.
--
-- @'minimumBy' cmp ≡ 'Data.Maybe.fromMaybe' ('error' \"empty\") '.' 'minimumByOf' 'folded' cmp@
--
-- @
-- 'minimumByOf' :: 'Getter' s a           -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'minimumByOf' :: 'Fold' s a             -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'minimumByOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'minimumByOf' :: 'Simple' 'Lens' s a      -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- 'minimumByOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> a -> 'Ordering') -> s -> 'Maybe' a
-- @
minimumByOf :: Getting (Endo (Maybe a)) s t a b -> (a -> a -> Ordering) -> s -> Maybe a
minimumByOf l cmp = foldrOf l step Nothing where
  step a Nothing  = Just a
  step a (Just b) = Just (if cmp a b == GT then b else a)
{-# INLINE minimumByOf #-}

-- | The 'findOf' function takes a 'Lens' (or 'Control.Lens.Getter.Getter', 'Control.Lens.Iso.Iso', 'Control.Lens.Fold.Fold', or 'Control.Lens.Traversal.Traversal'),
-- a predicate and a structure and returns the leftmost element of the structure
-- matching the predicate, or 'Nothing' if there is no such element.
--
-- @
-- 'findOf' :: 'Getter' s a           -> (a -> 'Bool') -> s -> 'Maybe' a
-- 'findOf' :: 'Fold' s a             -> (a -> 'Bool') -> s -> 'Maybe' a
-- 'findOf' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> 'Bool') -> s -> 'Maybe' a
-- 'findOf' :: 'Simple' 'Lens' s a      -> (a -> 'Bool') -> s -> 'Maybe' a
-- 'findOf' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> 'Bool') -> s -> 'Maybe' a
-- @
findOf :: Getting (First a) s t a b -> (a -> Bool) -> s -> Maybe a
findOf l p = getFirst #. foldMapOf l step where
  step a
    | p a       = First (Just a)
    | otherwise = First Nothing
{-# INLINE findOf #-}

-- |
-- A variant of 'foldrOf' that has no base case and thus may only be applied
-- to lenses and structures such that the lens views at least one element of
-- the structure.
--
-- @
-- 'foldr1Of' l f ≡ 'Prelude.foldr1' f '.' 'toListOf' l
-- 'Data.Foldable.foldr1' ≡ 'foldr1Of' 'folded'
-- @
--
-- @
-- 'foldr1Of' :: 'Getter' s a           -> (a -> a -> a) -> s -> a
-- 'foldr1Of' :: 'Fold' s a             -> (a -> a -> a) -> s -> a
-- 'foldr1Of' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> a -> a) -> s -> a
-- 'foldr1Of' :: 'Simple' 'Lens' s a      -> (a -> a -> a) -> s -> a
-- 'foldr1Of' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> a -> a) -> s -> a
-- @
foldr1Of :: Getting (Endo (Maybe a)) s t a b -> (a -> a -> a) -> s -> a
foldr1Of l f xs = fromMaybe (error "foldr1Of: empty structure")
                            (foldrOf l mf Nothing xs) where
  mf x Nothing = Just x
  mf x (Just y) = Just (f x y)
{-# INLINE foldr1Of #-}

-- | A variant of 'foldlOf' that has no base case and thus may only be applied to lenses and structures such
-- that the lens views at least one element of the structure.
--
-- @
-- 'foldl1Of' l f ≡ 'Prelude.foldl1Of' l f . 'toList'
-- 'Data.Foldable.foldl1' ≡ 'foldl1Of' 'folded'
-- @
--
-- @
-- 'foldl1Of' :: 'Getter' s a           -> (a -> a -> a) -> s -> a
-- 'foldl1Of' :: 'Fold' s a             -> (a -> a -> a) -> s -> a
-- 'foldl1Of' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> a -> a) -> s -> a
-- 'foldl1Of' :: 'Simple' 'Lens' s a      -> (a -> a -> a) -> s -> a
-- 'foldl1Of' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> a -> a) -> s -> a
-- @
foldl1Of :: Getting (Dual (Endo (Maybe a))) s t a b -> (a -> a -> a) -> s -> a
foldl1Of l f xs = fromMaybe (error "foldl1Of: empty structure") (foldlOf l mf Nothing xs) where
  mf Nothing y = Just y
  mf (Just x) y = Just (f x y)
{-# INLINE foldl1Of #-}

-- | Strictly fold right over the elements of a structure.
--
-- @'Data.Foldable.foldr'' ≡ 'foldrOf'' 'folded'@
--
-- @
-- 'foldrOf'' :: 'Getter' s a           -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf'' :: 'Fold' s a             -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf'' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf'' :: 'Simple' 'Lens' s a      -> (a -> r -> r) -> r -> s -> r
-- 'foldrOf'' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r -> r) -> r -> s -> r
-- @
foldrOf' :: Getting (Dual (Endo (r -> r))) s t a b -> (a -> r -> r) -> r -> s -> r
foldrOf' l f z0 xs = foldlOf l f' id xs z0
  where f' k x z = k $! f x z
{-# INLINE foldrOf' #-}

-- | Fold over the elements of a structure, associating to the left, but strictly.
--
-- @'Data.Foldable.foldl'' ≡ 'foldlOf'' 'folded'@
--
-- @
-- 'foldlOf'' :: 'Getter' s a           -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf'' :: 'Fold' s a             -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf'' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf'' :: 'Simple' 'Lens' s a      -> (r -> a -> r) -> r -> s -> r
-- 'foldlOf'' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (r -> a -> r) -> r -> s -> r
-- @
foldlOf' :: Getting (Endo (r -> r)) s t a b -> (r -> a -> r) -> r -> s -> r
foldlOf' l f z0 xs = foldrOf l f' id xs z0
  where f' x k z = k $! f z x
{-# INLINE foldlOf' #-}

-- | Monadic fold over the elements of a structure, associating to the right,
-- i.e. from right to left.
--
-- @'Data.Foldable.foldrM' ≡ 'foldrMOf' 'folded'@
--
-- @
-- 'foldrMOf' :: 'Monad' m => 'Getter' s a           -> (a -> r -> m r) -> r -> s -> m r
-- 'foldrMOf' :: 'Monad' m => 'Fold' s a             -> (a -> r -> m r) -> r -> s -> m r
-- 'foldrMOf' :: 'Monad' m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r -> m r) -> r -> s -> m r
-- 'foldrMOf' :: 'Monad' m => 'Simple' 'Lens' s a      -> (a -> r -> m r) -> r -> s -> m r
-- 'foldrMOf' :: 'Monad' m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r -> m r) -> r -> s -> m r
-- @
foldrMOf :: Monad m
         => Getting (Dual (Endo (r -> m r))) s t a b
         -> (a -> r -> m r) -> r -> s -> m r
foldrMOf l f z0 xs = foldlOf l f' return xs z0
  where f' k x z = f x z >>= k
{-# INLINE foldrMOf #-}

-- | Monadic fold over the elements of a structure, associating to the left,
-- i.e. from left to right.
--
-- @'Data.Foldable.foldlM' ≡ 'foldlMOf' 'folded'@
--
-- @
-- 'foldlMOf' :: 'Monad' m => 'Getter' s a           -> (r -> a -> m r) -> r -> s -> m r
-- 'foldlMOf' :: 'Monad' m => 'Fold' s a             -> (r -> a -> m r) -> r -> s -> m r
-- 'foldlMOf' :: 'Monad' m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> (r -> a -> m r) -> r -> s -> m r
-- 'foldlMOf' :: 'Monad' m => 'Simple' 'Lens' s a      -> (r -> a -> m r) -> r -> s -> m r
-- 'foldlMOf' :: 'Monad' m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (r -> a -> m r) -> r -> s -> m r
-- @
foldlMOf :: Monad m
         => Getting (Endo (r -> m r)) s t a b
         -> (r -> a -> m r) -> r -> s -> m r
foldlMOf l f z0 xs = foldrOf l f' return xs z0
  where f' x k z = f z x >>= k
{-# INLINE foldlMOf #-}

-- | Check to see if this 'Fold' or 'Traversal' matches 1 or more entries
--
-- >>> has (element 0) []
-- False
--
-- >>> has _left (Left 12)
-- True
--
-- >>> has _right (Left 12)
-- False
--
-- This will always return True for a 'Lens' or 'Getter'
--
-- >>> has _1 ("hello","world")
-- True
--
-- @
-- 'has' :: 'Getter' s a           -> s -> 'Bool'
-- 'has' :: 'Fold' s a             -> s -> 'Bool'
-- 'has' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Bool'
-- 'has' :: 'Simple' 'Lens' s a      -> s -> 'Bool'
-- 'has' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Bool'
-- @
has :: Getting Any s t a b -> s -> Bool
has l = getAny #. views l (\_ -> Any True)
{-# INLINE has #-}

-- | Check to see if this 'Fold' or 'Traversal' has no matches.
--
-- >>> hasn't _left (Right 12)
-- True
--
-- >>> hasn't _left (Left 12)
-- False
hasn't :: Getting All s t a b -> s -> Bool
hasn't l = getAll #. views l (\_ -> All False)
{-# INLINE hasn't #-}

-- | Useful for storing folds in containers.
newtype ReifiedFold s a = ReifyFold { reflectFold :: Fold s a }

------------------------------------------------------------------------------
-- Preview
------------------------------------------------------------------------------

-- | Retrieve the first value targeted by a 'Fold' or 'Control.Lens.Traversal.Traversal' (or 'Just' the result
-- from a 'Getter' or 'Lens'). See also ('^?').
--
-- @'Data.Maybe.listToMaybe' '.' 'toList' ≡ 'preview' 'folded'@
--
-- This is usually applied in the reader monad @(->) s@.
--
-- @
-- 'preview' :: 'Getter' s a           -> s -> 'Maybe' a
-- 'preview' :: 'Fold' s a             -> s -> 'Maybe' a
-- 'preview' :: 'Simple' 'Lens' s a      -> s -> 'Maybe' a
-- 'preview' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> s -> 'Maybe' a
-- 'preview' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> s -> 'Maybe' a
-- @
--
-- However, it may be useful to think of its full generality when working with
-- a monad transformer stack:
--
-- @
-- 'preview' :: MonadReader s m => 'Getter' s a           -> m ('Maybe' a)
-- 'preview' :: MonadReader s m => 'Fold' s a             -> m ('Maybe' a)
-- 'preview' :: MonadReader s m => 'Simple' 'Lens' s a      -> m ('Maybe' a)
-- 'preview' :: MonadReader s m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> m ('Maybe' a)
-- 'preview' :: MonadReader s m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> m ('Maybe' a)
-- @
preview :: MonadReader s m => Getting (First a) s t a b -> m (Maybe a)
preview l = asks (getFirst #. foldMapOf l (First #. Just))
{-# INLINE preview #-}

-- | Retrieve a function of the first value targeted by a 'Fold' or
-- 'Control.Lens.Traversal.Traversal' (or 'Just' the result from a 'Getter' or 'Lens').
--
-- This is usually applied in the reader monad @(->) s@.
--
-- @
-- 'previews' :: 'Getter' s a           -> (a -> r) -> s -> 'Maybe' a
-- 'previews' :: 'Fold' s a             -> (a -> r) -> s -> 'Maybe' a
-- 'previews' :: 'Simple' 'Lens' s a      -> (a -> r) -> s -> 'Maybe' a
-- 'previews' :: 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r) -> s -> 'Maybe' a
-- 'previews' :: 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r) -> s -> 'Maybe' a
-- @
--
-- However, it may be useful to think of its full generality when working with
-- a monad transformer stack:
--
-- @
-- 'previews' :: MonadReader s m => 'Getter' s a           -> (a -> r) -> m ('Maybe' r)
-- 'previews' :: MonadReader s m => 'Fold' s a             -> (a -> r) -> m ('Maybe' r)
-- 'previews' :: MonadReader s m => 'Simple' 'Lens' s a      -> (a -> r) -> m ('Maybe' r)
-- 'previews' :: MonadReader s m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r) -> m ('Maybe' r)
-- 'previews' :: MonadReader s m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r) -> m ('Maybe' r)
-- @
previews :: MonadReader s m => Getting (First r) s t a b -> (a -> r) -> m (Maybe r)
previews l f = asks (getFirst #. foldMapOf l (First #. Just . f))
{-# INLINE previews #-}


------------------------------------------------------------------------------
-- Preuse
------------------------------------------------------------------------------

-- | Retrieve the first value targeted by a 'Fold' or 'Control.Lens.Traversal.Traversal' (or 'Just' the result
-- from a 'Getter' or 'Lens') into the current state.
--
-- @
-- 'preuse' :: MonadState s m => 'Getter' s a           -> m ('Maybe' a)
-- 'preuse' :: MonadState s m => 'Fold' s a             -> m ('Maybe' a)
-- 'preuse' :: MonadState s m => 'Simple' 'Lens' s a      -> m ('Maybe' a)
-- 'preuse' :: MonadState s m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> m ('Maybe' a)
-- 'preuse' :: MonadState s m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> m ('Maybe' a)
-- @
preuse :: MonadState s m => Getting (First a) s t a b -> m (Maybe a)
preuse l = gets (getFirst #. foldMapOf l (First #. Just))
{-# INLINE preuse #-}

-- | Retrieve a function of the first value targeted by a 'Fold' or
-- 'Control.Lens.Traversal.Traversal' (or 'Just' the result from a 'Getter' or 'Lens') into the current state.
--
-- @
-- 'preuses' :: MonadState s m => 'Getter' s a           -> (a -> r) -> m ('Maybe' r)
-- 'preuses' :: MonadState s m => 'Fold' s a             -> (a -> r) -> m ('Maybe' r)
-- 'preuses' :: MonadState s m => 'Simple' 'Lens' s a      -> (a -> r) -> m ('Maybe' r)
-- 'preuses' :: MonadState s m => 'Simple' 'Control.Lens.Iso.Iso' s a       -> (a -> r) -> m ('Maybe' r)
-- 'preuses' :: MonadState s m => 'Simple' 'Control.Lens.Traversal.Traversal' s a -> (a -> r) -> m ('Maybe' r)
-- @
preuses :: MonadState s m => Getting (First r) s t a b -> (a -> r) -> m (Maybe r)
preuses l f = gets (getFirst #. foldMapOf l (First #. Just . f))
{-# INLINE preuses #-}

------------------------------------------------------------------------------
-- Profunctors
------------------------------------------------------------------------------


-- | This allows you to traverse the elements of a pretty much any lens-like construction in the opposite order.
--
-- This will preserve indexes on indexed types and will give you the elements of a (finite) 'Control.Lens.Fold.Fold' or 'Control.Lens.Traversal.Traversal' in the opposite order.
--
-- This has no practical impact on a 'Getter', 'Control.Lens.Setter.Setter', 'Lens' or 'Control.Lens.Iso.Iso'.
--
-- /NB:/ To write back through an 'Control.Lens.Iso.Iso', you want to use 'Control.Lens.Isomorphic.from'.
-- Similarly, to write back through an 'Control.Lens.Prism.Prism', you want to use 'Control.Lens.Prism.remit'.
backwards :: (Profunctor p, Profunctor q) => Overloading p q (Backwards f) s t a b -> Overloading p q f s t a b
backwards l f = rmap forwards (l (rmap Backwards f))
{-# INLINE backwards #-}

------------------------------------------------------------------------------
-- Indexed Folds
------------------------------------------------------------------------------

-- | Every 'IndexedFold' is a valid 'Control.Lens.Fold.Fold'.
type IndexedFold i s a = forall p f.
  (Indexable i p, Applicative f, Gettable f) => p a (f a) -> s -> f s

-- |
-- Fold an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' by mapping indices and values to an arbitrary 'Monoid' with access
-- to the @i@.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldMapOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldMapOf' l ≡ 'ifoldMapOf' l '.' 'const'@
--
-- @
-- 'ifoldMapOf' ::             'IndexedGetter' i a s          -> (i -> s -> m) -> a -> m
-- 'ifoldMapOf' :: 'Monoid' m => 'IndexedFold' i a s            -> (i -> s -> m) -> a -> m
-- 'ifoldMapOf' ::             'Control.Lens.Lens.IndexedLens'' i a s      -> (i -> s -> m) -> a -> m
-- 'ifoldMapOf' :: 'Monoid' m => 'Control.Lens.Traversal.IndexedTraversal'' i a s -> (i -> s -> m) -> a -> m
-- @
ifoldMapOf :: IndexedGetting i m s t a b -> (i -> a -> m) -> s -> m
ifoldMapOf l f = runAccessor #. withIndex l (\i -> Accessor #. f i)
{-# INLINE ifoldMapOf #-}

-- |
-- Right-associative fold of parts of a structure that are viewed through an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' with
-- access to the @i@.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldrOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldrOf' l ≡ 'ifoldrOf' l '.' 'const'@
--
-- @
-- 'ifoldrOf' :: 'IndexedGetter' i s a          -> (i -> a -> r -> r) -> r -> s -> r
-- 'ifoldrOf' :: 'IndexedFold' i s a            -> (i -> a -> r -> r) -> r -> s -> r
-- 'ifoldrOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> r -> r) -> r -> s -> r
-- 'ifoldrOf' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> r -> r) -> r -> s -> r
-- @
ifoldrOf :: IndexedGetting i (Endo r) s t a b -> (i -> a -> r -> r) -> r -> s -> r
ifoldrOf l f z t = appEndo (ifoldMapOf l (\i -> Endo #. f i) t) z
{-# INLINE ifoldrOf #-}

-- |
-- Left-associative fold of the parts of a structure that are viewed through an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' with
-- access to the @i@.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldlOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldlOf' l ≡ 'ifoldlOf' l '.' 'const'@
--
-- @
-- 'ifoldlOf' :: 'IndexedGetter' i s a          -> (i -> r -> a -> r) -> r -> s -> r
-- 'ifoldlOf' :: 'IndexedFold' i s a            -> (i -> r -> a -> r) -> r -> s -> r
-- 'ifoldlOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> r -> a -> r) -> r -> s -> r
-- 'ifoldlOf' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> r -> a -> r) -> r -> s -> r
-- @
ifoldlOf :: IndexedGetting i (Dual (Endo r)) s t a b -> (i -> r -> a -> r) -> r -> s -> r
ifoldlOf l f z t = appEndo (getDual (ifoldMapOf l (\i -> Dual #. Endo #. flip (f i)) t)) z
{-# INLINE ifoldlOf #-}

-- |
-- Return whether or not any element viewed through an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal'
-- satisfy a predicate, with access to the @i@.
--
-- When you don't need access to the index then 'Control.Lens.Fold.anyOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.anyOf' l ≡ 'ianyOf' l '.' 'const'@
--
-- @
-- 'ianyOf' :: 'IndexedGetter' i s a          -> (i -> a -> 'Bool') -> s -> 'Bool'
-- 'ianyOf' :: 'IndexedFold' i s a            -> (i -> a -> 'Bool') -> s -> 'Bool'
-- 'ianyOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> 'Bool') -> s -> 'Bool'
-- 'ianyOf' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> 'Bool') -> s -> 'Bool'
-- @
ianyOf :: IndexedGetting i Any s t a b -> (i -> a -> Bool) -> s -> Bool
ianyOf l f = getAny #. ifoldMapOf l (\i -> Any #. f i)
{-# INLINE ianyOf #-}

-- |
-- Return whether or not all elements viewed through an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal'
-- satisfy a predicate, with access to the @i@.
--
-- When you don't need access to the index then 'Control.Lens.Fold.allOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.allOf' l ≡ 'iallOf' l '.' 'const'@
--
-- @
-- 'iallOf' :: 'IndexedGetter' i s a          -> (i -> a -> 'Bool') -> s -> 'Bool'
-- 'iallOf' :: 'IndexedFold' i s a            -> (i -> a -> 'Bool') -> s -> 'Bool'
-- 'iallOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> 'Bool') -> s -> 'Bool'
-- 'iallOf' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> 'Bool') -> s -> 'Bool'
-- @
iallOf :: IndexedGetting i All s t a b -> (i -> a -> Bool) -> s -> Bool
iallOf l f = getAll #. ifoldMapOf l (\i -> All #. f i)
{-# INLINE iallOf #-}

-- |
-- Traverse the targets of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' with access to the @i@, discarding the results.
--
-- When you don't need access to the index then 'Control.Lens.Fold.traverseOf_' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.traverseOf_' l ≡ 'Control.Lens.Traversal.itraverseOf' l '.' 'const'@
--
-- @
-- 'itraverseOf_' :: 'Functor' f     => 'IndexedGetter' i s a          -> (i -> a -> f r) -> s -> f ()
-- 'itraverseOf_' :: 'Applicative' f => 'IndexedFold' i s a            -> (i -> a -> f r) -> s -> f ()
-- 'itraverseOf_' :: 'Functor' f     => 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> f r) -> s -> f ()
-- 'itraverseOf_' :: 'Applicative' f => 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> f r) -> s -> f ()
-- @
itraverseOf_ :: Functor f => IndexedGetting i (Traversed f) s t a b -> (i -> a -> f r) -> s -> f ()
itraverseOf_ l f = getTraversed #. ifoldMapOf l (\i -> Traversed #. void . f i)
{-# INLINE itraverseOf_ #-}

-- |
-- Traverse the targets of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' with access to the index, discarding the results
-- (with the arguments flipped).
--
-- @'iforOf_' ≡ 'flip' '.' 'itraverseOf_'@
--
-- When you don't need access to the index then 'Control.Lens.Fold.forOf_' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.forOf_' l a ≡ 'iforOf_' l a '.' 'const'@
--
-- @
-- 'iforOf_' :: 'Functor' f     => 'IndexedGetter' i s a          -> s -> (i -> a -> f r) -> f ()
-- 'iforOf_' :: 'Applicative' f => 'IndexedFold' i s a            -> s -> (i -> a -> f r) -> f ()
-- 'iforOf_' :: 'Functor' f     => 'Control.Lens.Lens.IndexedLens'' i s a      -> s -> (i -> a -> f r) -> f ()
-- 'iforOf_' :: 'Applicative' f => 'Control.Lens.Traversal.IndexedTraversal'' i s a -> s -> (i -> a -> f r) -> f ()
-- @
iforOf_ :: Functor f => IndexedGetting i (Traversed f) s t a b -> s -> (i -> a -> f r) -> f ()
iforOf_ = flip . itraverseOf_
{-# INLINE iforOf_ #-}

-- |
-- Run monadic actions for each target of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' with access to the index,
-- discarding the results.
--
-- When you don't need access to the index then 'Control.Lens.Fold.mapMOf_' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.mapMOf_' l ≡ 'Control.Lens.Setter.imapMOf' l '.' 'const'@
--
-- @
-- 'imapMOf_' :: 'Monad' m => 'IndexedGetter' i s a          -> (i -> a -> m r) -> s -> m ()
-- 'imapMOf_' :: 'Monad' m => 'IndexedFold' i s a            -> (i -> a -> m r) -> s -> m ()
-- 'imapMOf_' :: 'Monad' m => 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> m r) -> s -> m ()
-- 'imapMOf_' :: 'Monad' m => 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> m r) -> s -> m ()
-- @
imapMOf_ :: Monad m => IndexedGetting i (Sequenced m) s t a b -> (i -> a -> m r) -> s -> m ()
imapMOf_ l f = getSequenced #. ifoldMapOf l (\i -> Sequenced #. liftM skip . f i)
{-# INLINE imapMOf_ #-}

-- |
-- Run monadic actions for each target of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' with access to the index,
-- discarding the results (with the arguments flipped).
--
-- @'iforMOf_' ≡ 'flip' '.' 'imapMOf_'@
--
-- When you don't need access to the index then 'Control.Lens.Fold.forMOf_' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.forMOf_' l a ≡ 'Control.Lens.Traversal.iforMOf' l a '.' 'const'@
--
-- @
-- 'iforMOf_' :: 'Monad' m => 'IndexedGetter' i s a          -> s -> (i -> a -> m r) -> m ()
-- 'iforMOf_' :: 'Monad' m => 'IndexedFold' i s a            -> s -> (i -> a -> m r) -> m ()
-- 'iforMOf_' :: 'Monad' m => 'Control.Lens.Lens.IndexedLens'' i s a      -> s -> (i -> a -> m r) -> m ()
-- 'iforMOf_' :: 'Monad' m => 'Control.Lens.Traversal.IndexedTraversal'' i s a -> s -> (i -> a -> m r) -> m ()
-- @
iforMOf_ :: Monad m => IndexedGetting i (Sequenced m) s t a b -> s -> (i -> a -> m r) -> m ()
iforMOf_ = flip . imapMOf_
{-# INLINE iforMOf_ #-}

-- |
-- Concatenate the results of a function of the elements of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal'
-- with access to the index.
--
-- When you don't need access to the index then 'Control.Lens.Fold.concatMapOf'  is more flexible in what it accepts.
--
-- @
-- 'Control.Lens.Fold.concatMapOf' l ≡ 'iconcatMapOf' l '.' 'const'
-- 'iconcatMapOf' ≡ 'ifoldMapOf'
-- @
--
-- @
-- 'iconcatMapOf' :: 'IndexedGetter' i s a          -> (i -> a -> [r]) -> s -> [r]
-- 'iconcatMapOf' :: 'IndexedFold' i s a            -> (i -> a -> [r]) -> s -> [r]
-- 'iconcatMapOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> [r]) -> s -> [r]
-- 'iconcatMapOf' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> [r]) -> s -> [r]
-- @
iconcatMapOf :: IndexedGetting i [r] s t a b -> (i -> a -> [r]) -> s -> [r]
iconcatMapOf = ifoldMapOf
{-# INLINE iconcatMapOf #-}

-- | The 'findOf' function takes an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal', a predicate that is also
-- supplied the index, a structure and returns the left-most element of the structure
-- matching the predicate, or 'Nothing' if there is no such element.
--
-- When you don't need access to the index then 'Control.Lens.Fold.findOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.findOf' l ≡ 'ifindOf' l '.' 'const'@
--
-- @
-- 'ifindOf' :: 'IndexedGetter' s a          -> (i -> a -> 'Bool') -> s -> 'Maybe' (i, a)
-- 'ifindOf' :: 'IndexedFold' s a            -> (i -> a -> 'Bool') -> s -> 'Maybe' (i, a)
-- 'ifindOf' :: 'Control.Lens.Lens.IndexedLens'' s a      -> (i -> a -> 'Bool') -> s -> 'Maybe' (i, a)
-- 'ifindOf' :: 'Control.Lens.Traversal.IndexedTraversal'' s a -> (i -> a -> 'Bool') -> s -> 'Maybe' (i, a)
-- @
ifindOf :: IndexedGetting i (First (i, a)) s t a b -> (i -> a -> Bool) -> s -> Maybe (i, a)
ifindOf l p = getFirst #. ifoldMapOf l step where
  step i a
    | p i a     = First $ Just (i, a)
    | otherwise = First Nothing
{-# INLINE ifindOf #-}

-- | /Strictly/ fold right over the elements of a structure with an index.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldrOf'' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldrOf'' l ≡ 'ifoldrOf'' l '.' 'const'@
--
-- @
-- 'ifoldrOf'' :: 'IndexedGetter' i s a          -> (i -> a -> r -> r) -> r -> s -> r
-- 'ifoldrOf'' :: 'IndexedFold' i s a            -> (i -> a -> r -> r) -> r -> s -> r
-- 'ifoldrOf'' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> r -> r) -> r -> s -> r
-- 'ifoldrOf'' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> r -> r) -> r -> s -> r
-- @
ifoldrOf' :: IndexedGetting i (Dual (Endo (r -> r))) s t a b -> (i -> a -> r -> r) -> r -> s -> r
ifoldrOf' l f z0 xs = ifoldlOf l f' id xs z0
  where f' i k x z = k $! f i x z
{-# INLINE ifoldrOf' #-}

-- | Fold over the elements of a structure with an index, associating to the left, but /strictly/.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldlOf'' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldlOf'' l ≡ 'ifoldlOf'' l '.' 'const'@
--
-- @
-- 'ifoldlOf'' :: 'IndexedGetter' i s a            -> (i -> r -> a -> r) -> r -> s -> r
-- 'ifoldlOf'' :: 'IndexedFold' i s a              -> (i -> r -> a -> r) -> r -> s -> r
-- 'ifoldlOf'' :: 'Control.Lens.Lens.IndexedLens'' i s a        -> (i -> r -> a -> r) -> r -> s -> r
-- 'ifoldlOf'' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a   -> (i -> r -> a -> r) -> r -> s -> r
-- @
ifoldlOf' :: IndexedGetting i (Endo (r -> r)) s t a b -> (i -> r -> a -> r) -> r -> s -> r
ifoldlOf' l f z0 xs = ifoldrOf l f' id xs z0
  where f' i x k z = k $! f i z x
{-# INLINE ifoldlOf' #-}

-- | Monadic fold right over the elements of a structure with an index.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldrMOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldrMOf' l ≡ 'ifoldrMOf' l '.' 'const'@
--
-- @
-- 'ifoldrMOf' :: 'Monad' m => 'IndexedGetter' i s a          -> (i -> a -> r -> m r) -> r -> s -> r
-- 'ifoldrMOf' :: 'Monad' m => 'IndexedFold' i s a            -> (i -> a -> r -> m r) -> r -> s -> r
-- 'ifoldrMOf' :: 'Monad' m => 'Control.Lens.Lens.IndexedLens'' i s a      -> (i -> a -> r -> m r) -> r -> s -> r
-- 'ifoldrMOf' :: 'Monad' m => 'Control.Lens.Traversal.IndexedTraversal'' i s a -> (i -> a -> r -> m r) -> r -> s -> r
-- @
ifoldrMOf :: Monad m => IndexedGetting i (Dual (Endo (r -> m r))) s t a b -> (i -> a -> r -> m r) -> r -> s -> m r
ifoldrMOf l f z0 xs = ifoldlOf l f' return xs z0
  where f' i k x z = f i x z >>= k
{-# INLINE ifoldrMOf #-}

-- | Monadic fold over the elements of a structure with an index, associating to the left.
--
-- When you don't need access to the index then 'Control.Lens.Fold.foldlMOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.foldlMOf' l ≡ 'ifoldlMOf' l '.' 'const'@
--
-- @
-- 'ifoldlOf'' :: 'Monad' m => 'IndexedGetter' i s a            -> (i -> r -> a -> m r) -> r -> s -> r
-- 'ifoldlOf'' :: 'Monad' m => 'IndexedFold' i s a              -> (i -> r -> a -> m r) -> r -> s -> r
-- 'ifoldlOf'' :: 'Monad' m => 'Control.Lens.Lens.IndexedLens'' i s a        -> (i -> r -> a -> m r) -> r -> s -> r
-- 'ifoldlOf'' :: 'Monad' m => 'Control.Lens.Traversal.IndexedTraversal'' i s a   -> (i -> r -> a -> m r) -> r -> s -> r
-- @
ifoldlMOf :: Monad m => IndexedGetting i (Endo (r -> m r)) s t a b -> (i -> r -> a -> m r) -> r -> s -> m r
ifoldlMOf l f z0 xs = ifoldrOf l f' return xs z0
  where f' i x k z = f i z x >>= k
{-# INLINE ifoldlMOf #-}

-- | Extract the key-value pairs from a structure.
--
-- When you don't need access to the indices in the result, then 'Control.Lens.Fold.toListOf' is more flexible in what it accepts.
--
-- @'Control.Lens.Fold.toListOf' l ≡ 'map' 'fst' '.' 'itoListOf' l@
--
-- @
-- 'itoListOf' :: 'IndexedGetter' i s a          -> s -> [(i,a)]
-- 'itoListOf' :: 'IndexedFold' i s a            -> s -> [(i,a)]
-- 'itoListOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> s -> [(i,a)]
-- 'itoListOf' :: 'Control.Lens.Traversal.IndexedTraversal'' i s a -> s -> [(i,a)]
-- @
itoListOf :: IndexedGetting i (Endo [(i,a)]) s t a b -> s -> [(i,a)]
itoListOf l = ifoldrOf l (\i a -> ((i,a):)) []
{-# INLINE itoListOf #-}

-- | An infix version of 'itoListOf'

-- @
-- ('^@..') :: s -> 'IndexedGetter' i s a          -> [(i,a)]
-- ('^@..') :: s -> 'IndexedFold' i s a            -> [(i,a)]
-- ('^@..') :: s -> 'Control.Lens.Lens.IndexedLens'' i s a      -> [(i,a)]
-- ('^@..') :: s -> 'Control.Lens.Traversal.IndexedTraversal'' i s a -> [(i,a)]
-- @
(^@..) :: s -> IndexedGetting i (Endo [(i,a)]) s t a b -> [(i,a)]
s ^@.. l = ifoldrOf l (\i a -> ((i,a):)) [] s

-- | Perform a safe 'head' (with index) of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' or retrieve 'Just' the index and result
-- from an 'IndexedGetter' or 'IndexedLens'.
--
-- When using a 'Control.Lens.Traversal.IndexedTraversal' as a partial 'Control.Lens.Lens.IndexedLens', or an 'IndexedFold' as a partial 'IndexedGetter' this can be a convenient
-- way to extract the optional value.
--
-- @
-- ('^@?') :: s -> 'IndexedGetter' i s a           -> 'Maybe' (i, a)
-- ('^@?') :: s -> 'IndexedFold' i s a             -> 'Maybe' (i, a)
-- ('^@?') :: s -> 'IndexedLens'' i s a      -> 'Maybe' (i, a)
-- ('^@?') :: s -> 'Control.Lens.Iso.Iso'' i s a       -> 'Maybe' (i, a)
-- ('^@?') :: s -> 'Control.Lens.Traversal.Traversal'' i s a -> 'Maybe' (i, a)
-- @
(^@?) :: s -> IndexedGetting i (First (i, a)) s t a b -> Maybe (i, a)
s ^@? l = getFirst $ ifoldMapOf l (\i a -> First (Just (i,a))) s
{-# INLINE (^@?) #-}

-- | Perform an *UNSAFE* 'head' (with index) of an 'IndexedFold' or 'Control.Lens.Traversal.IndexedTraversal' assuming that it is there.
--
-- @
-- ('^@?!') :: s -> 'IndexedGetter' i s a           -> (i, a)
-- ('^@?!') :: s -> 'IndexedFold' i s a             -> (i, a)
-- ('^@?!') :: s -> 'Lens'' i s a      -> (i, a)
-- ('^@?!') :: s -> 'Control.Lens.Iso.Iso'' i s a       -> (i, a)
-- ('^@?!') :: s -> 'Control.Lens.Traversal.Traversal'' i s a -> (i, a)
-- @
(^@?!) :: s -> IndexedGetting i (First (i, a)) s t a b -> (i, a)
s ^@?! l = fromMaybe (error "(^@?!): empty Fold") $ getFirst $ ifoldMapOf l (\i a -> First (Just (i,a))) s
{-# INLINE (^@?!) #-}

-------------------------------------------------------------------------------
-- Converting to Folds
-------------------------------------------------------------------------------

-- | Transform an indexed fold into a fold of both the indices and the values.
--
-- @
-- 'withIndicesOf' :: 'IndexedFold' i s a            -> 'Control.Lens.Fold.Fold' s (i, a)
-- 'withIndicesOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> 'Control.Lens.Fold.Getter' s (i, a)
-- 'withIndicesOf' :: 'Control.Lens.Lens.IndexedTraversal'' i s a -> 'Control.Lens.Fold.Fold' s (i, a)
-- @
--
-- All 'Control.Lens.Fold.Fold' operations are safe, and comply with the laws. However:
--
-- Passing this an 'Control.Lens.Traversal.IndexedTraversal' will still allow many
-- 'Control.Lens.Traversal.Traversal' combinators to type check on the result, but the result
-- can only be legally traversed by operations that do not edit the indices.
--
-- @
-- 'withIndicesOf' :: 'Control.Lens.Traversal.IndexedTraversal' i s t a b -> 'Control.Lens.Traversal.Traversal' s t (i, a) (j, b)
-- @
--
-- Change made to the indices will be discarded.
withIndicesOf :: Functor f => IndexedLensLike (Indexed i) f s t a b -> LensLike f s t (i, a) (j, b)
withIndicesOf l f = l @~ \i c -> snd <$> f (i,c)
{-# INLINE withIndicesOf #-}

-- | Transform an indexed fold into a fold of the indices.
--
-- @
-- 'indicesOf' :: 'IndexedFold' i s a            -> 'Control.Lens.Fold.Fold' s i
-- 'indicesOf' :: 'Control.Lens.Lens.IndexedLens'' i s a      -> 'Control.Lens.Fold.Getter' s i
-- 'indicesOf' :: 'Control.Lens.Lens.IndexedTraversal'' i s a -> 'Control.Lens.Fold.Fold' s i
-- @
indicesOf :: Gettable f => IndexedLensLike (Indexed i) f s t a a -> LensLike f s t i j
indicesOf l f = l @~ const . coerce . f
{-# INLINE indicesOf #-}

-------------------------------------------------------------------------------
-- Converting to Folds
-------------------------------------------------------------------------------

-- | Obtain an 'IndexedFold' by filtering an 'Control.Lens.Lens.IndexedLens', 'IndexedGetter', or 'IndexedFold'.
--
-- When passed an 'Control.Lens.Traversal.IndexedTraversal', sadly the result is /not/ a legal 'Control.Lens.Traversal.IndexedTraversal'.
--
-- See 'Control.Lens.Fold.filtered' for a related counter-example.
ifiltering :: (Applicative f, Indexable i p)
           => (i -> a -> Bool)
           -> (Indexed i a (f a) -> s -> f t)
           -> IndexedLensLike p f s t a a
ifiltering p l f = l @~ \ i c -> if p i c then indexed f i c else pure c
{-# INLINE ifiltering #-}


-- | Obtain an 'IndexedFold' by taking elements from another
-- 'IndexedFold', 'Control.Lens.Lens.IndexedLens',
-- 'IndexedGetter' or 'Control.Lens.Traversal.IndexedTraversal'
-- while a predicate holds.
itakingWhile :: (Gettable f, Applicative f, Indexable i p)
             => (i -> a -> Bool)
             -> IndexedGetting i (Endo (f s)) s s a a
             -> IndexedLensLike' p f s a
itakingWhile p l f =
  ifoldrOf l (\i a r -> if p i a then indexed f i a *> r else noEffect) noEffect
{-# INLINE itakingWhile #-}


-- | Obtain an 'IndexedFold' by dropping elements from another 'IndexedFold', 'Control.Lens.Lens.IndexedLens', 'IndexedGetter' or 'Control.Lens.Traversal.IndexedTraversal' while a predicate holds.
idroppingWhile :: (Gettable f, Applicative f, Indexable i p)
              => (i -> a -> Bool)
              -> IndexedGetting i (Endo (f s, f s)) s s a a
              -> IndexedLensLike' p f s a
idroppingWhile p l f =
  fst . ifoldrOf l
                 (\i a r -> let s = indexed f i a *> snd r in if p i a then (fst r, s) else (s, s))
                 (noEffect, noEffect)
{-# INLINE idroppingWhile #-}

------------------------------------------------------------------------------
-- Reifying Indexed Folds
------------------------------------------------------------------------------

-- | Useful for storage.
newtype ReifiedIndexedFold i s a =
  ReifyIndexedFold { reflectIndexedFold :: IndexedFold i s a }

------------------------------------------------------------------------------
-- Deprecated
------------------------------------------------------------------------------

-- | A deprecated alias for 'firstOf'
headOf :: Getting (First a) s t a b -> s -> Maybe a
headOf l = getFirst #. foldMapOf l (First #. Just)
{-# INLINE headOf #-}
{-# DEPRECATED headOf "`headOf' will be removed in 3.8. (Use `preview' or `firstOf')" #-}

------------------------------------------------------------------------------
-- Misc.
------------------------------------------------------------------------------

skip :: a -> ()
skip _ = ()
{-# INLINE skip #-}

