{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE Safe #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
module Data.Dependent.Sum where

import Control.Applicative

import Data.Constraint.Extras
import Data.Type.Equality ((:~:) (..))

import Data.GADT.Show
import Data.GADT.Compare

import Data.Maybe (fromMaybe)

-- |A basic dependent sum type; the first component is a tag that specifies
-- the type of the second;  for example, think of a GADT such as:
--
-- > data Tag a where
-- >    AString :: Tag String
-- >    AnInt   :: Tag Int
--
-- Then, we have the following valid expressions of type @Applicative f => DSum Tag f@:
--
-- > AString ==> "hello!"
-- > AnInt   ==> 42
--
-- And we can write functions that consume @DSum Tag f@ values by matching,
-- such as:
--
-- > toString :: DSum Tag Identity -> String
-- > toString (AString :=> Identity str) = str
-- > toString (AnInt   :=> Identity int) = show int
--
-- By analogy to the (key => value) construction for dictionary entries in
-- many dynamic languages, we use (key :=> value) as the constructor for
-- dependent sums.  The :=> and ==> operators have very low precedence and
-- bind to the right, so if the @Tag@ GADT is extended with an additional
-- constructor @Rec :: Tag (DSum Tag Identity)@, then @Rec ==> AnInt ==> 3 + 4@
-- is parsed as would be expected (@Rec ==> (AnInt ==> (3 + 4))@) and has type
-- @DSum Identity Tag@.  Its precedence is just above that of '$', so
-- @foo bar $ AString ==> "eep"@ is equivalent to @foo bar (AString ==> "eep")@.
data DSum tag f = forall a. !(tag a) :=> f a

infixr 1 :=>, ==>

(==>) :: Applicative f => tag a -> a -> DSum tag f
k ==> v = k :=> pure v

instance forall tag f. (GShow tag, Has' Show tag f) => Show (DSum tag f) where
    showsPrec p (tag :=> value) = showParen (p >= 10)
        ( gshowsPrec 0 tag
        . showString " :=> "
        . has' @Show @f tag (showsPrec 1 value)
        )

instance forall tag f. (GRead tag, Has' Read tag f) => Read (DSum tag f) where
    readsPrec p = readParen (p > 1) $ \s ->
        concat
            [ getGReadResult withTag $ \tag ->
                [ (tag :=> val, rest'')
                | (val, rest'') <- has' @Read @f tag (readsPrec 1 rest')
                ]
            | (withTag, rest) <- greadsPrec p s
            , let (con, rest') = splitAt 5 rest
            , con == " :=> "
            ]

instance forall tag f. (GEq tag, Has' Eq tag f) => Eq (DSum tag f) where
    (t1 :=> x1) == (t2 :=> x2)  = fromMaybe False $ do
        Refl <- geq t1 t2
        return $ has' @Eq @f t1 (x1 == x2)

instance forall tag f. (GCompare tag, Has' Eq tag f, Has' Ord tag f) => Ord (DSum tag f) where
    compare (t1 :=> x1) (t2 :=> x2)  = case gcompare t1 t2 of
        GLT -> LT
        GGT -> GT
        GEQ -> has' @Ord @f t1 (x1 `compare` x2)