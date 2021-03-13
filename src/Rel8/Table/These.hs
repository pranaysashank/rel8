{-# language DataKinds #-}
{-# language DeriveFunctor #-}
{-# language DerivingStrategies #-}
{-# language FlexibleContexts #-}
{-# language FlexibleInstances #-}
{-# language MultiParamTypeClasses #-}
{-# language NamedFieldPuns #-}
{-# language StandaloneKindSignatures #-}
{-# language TupleSections #-}
{-# language TypeFamilies #-}
{-# language UndecidableInstances #-}

module Rel8.Table.These
  ( TheseTable(..)
  , theseTable, thisTable, thatTable, thoseTable
  , isThisTable, isThatTable, isThoseTable, hasHereTable, hasThereTable
  )
where

-- base
import Data.Bifunctor ( Bifunctor, bimap )
import Data.Functor.Identity ( runIdentity )
import Data.Kind ( Type )
import Prelude hiding ( undefined )

-- rel8
import Rel8.Expr ( Expr )
import Rel8.Expr.Bool ( (&&.), not_ )
import Rel8.Expr.Null ( isNonNull )
import Rel8.Kind.Nullability ( Nullability( NonNullable ), nullabilitySing )
import Rel8.Schema.Context ( DB )
import Rel8.Schema.Context.Nullify
  ( Nullifiable, NullifiableEq
  , encodeTag, decodeTag
  , nullifier, unnullifier
  )
import Rel8.Schema.HTable.Identity ( HIdentity(..) )
import Rel8.Schema.HTable.Maybe ( HMaybeTable(..) )
import Rel8.Schema.HTable.Nullify ( hnullify, hunnullify )
import Rel8.Schema.HTable.These ( HTheseTable(..) )
import Rel8.Schema.Recontextualize ( Recontextualize )
import Rel8.Table
  ( Table, Columns, Context, fromColumns, toColumns
  , Compatible
  )
import Rel8.Table.Lifted
  ( Table1, Columns1, ConstrainContext1, fromColumns1, toColumns1
  , Table2, Columns2, ConstrainContext2, fromColumns2, toColumns2
  )
import Rel8.Table.Maybe
import Rel8.Table.Undefined ( undefined )
import Rel8.Type ( typeInformation )

-- semigroupoids
import Data.Functor.Apply ( Apply, (<.>) )
import Data.Functor.Bind ( Bind, (>>-) )


type TheseTable :: Type -> Type -> Type
data TheseTable a b = TheseTable
  { here :: MaybeTable a
  , there :: MaybeTable b
  }
  deriving stock Functor


instance Bifunctor TheseTable where
  bimap f g (TheseTable a b) = TheseTable (fmap f a) (fmap g b)


instance (Table a, Context a ~ DB, Semigroup a) => Apply (TheseTable a) where
  fs <.> as = TheseTable
    { here = here fs <> here as
    , there = there fs <.> there as
    }


instance (Table a, Context a ~ DB, Semigroup a) => Applicative (TheseTable a)
 where
  pure = thatTable
  (<*>) = (<.>)


instance (Table a, Context a ~ DB, Semigroup a) => Bind (TheseTable a) where
  TheseTable here1 ma >>- f = case ma >>- f' of
    mtb -> TheseTable
      { here = maybeTable here1 ((here1 <>) . fst) mtb
      , there = snd <$> mtb
      }
    where
      f' a = case f a of
        TheseTable here2 mb -> (here2,) <$> mb


instance (Table a, Context a ~ DB, Semigroup a) => Monad (TheseTable a) where
  (>>=) = (>>-)


instance
  ( Table a
  , Context a ~ DB
  , Semigroup a
  , Table b
  , Context b ~ DB
  , Semigroup b
  ) => Semigroup (TheseTable a b)
 where
  a <> b = TheseTable
    { here = here a <> here b
    , there = there a <> there b
    }


instance Table2 TheseTable where
  type Columns2 TheseTable = HTheseTable
  type ConstrainContext2 TheseTable = Nullifiable

  toColumns2 f g TheseTable {here, there} = HTheseTable
    { hhere = case here of
        MaybeTable {tag, table} -> HMaybeTable
          { htag = HIdentity $
              encodeTag "hasHere" nullabilitySing typeInformation tag
          , htable = hnullify (nullifier "Here" (isNonNull tag)) (f table)
          }
    , hthere = case there of
        MaybeTable {tag, table} -> HMaybeTable
          { htag = HIdentity $
              encodeTag "hasThere" nullabilitySing typeInformation tag
          , htable = hnullify (nullifier "There" (isNonNull tag)) (g table)
          }
    }

  fromColumns2 f g HTheseTable {hhere, hthere} = TheseTable
    { here = case hhere of
        HMaybeTable {htag, htable} -> MaybeTable
          { tag
          , table = f $ runIdentity $
              hunnullify
                (\a -> pure . unnullifier "Here" (isNonNull tag) a)
                htable
          }
          where
            tag = decodeTag "hasHere" nullabilitySing typeInformation $
              unHIdentity htag
    , there = case hthere of
        HMaybeTable {htag, htable} -> MaybeTable
          { tag
          , table = g $ runIdentity $
              hunnullify
                (\a -> pure . unnullifier "There" (isNonNull tag) a)
                htable
          }
          where
            tag = decodeTag "hasThere" nullabilitySing typeInformation $
              unHIdentity htag
    }


instance Table a => Table1 (TheseTable a) where
  type Columns1 (TheseTable a) = HTheseTable (Columns a)
  type ConstrainContext1 (TheseTable a) = NullifiableEq (Context a)

  toColumns1 = toColumns2 toColumns
  fromColumns1 = fromColumns2 fromColumns


instance (Table a, Table b, Compatible a b, Nullifiable (Context a)) =>
  Table (TheseTable a b)
 where
  type Columns (TheseTable a b) = HTheseTable (Columns a) (Columns b)
  type Context (TheseTable a b) = Context a

  toColumns = toColumns2 toColumns toColumns
  fromColumns = fromColumns2 fromColumns fromColumns


instance
  ( Nullifiable from
  , Nullifiable to
  , Recontextualize from to a1 b1
  , Recontextualize from to a2 b2
  ) =>
  Recontextualize from to (TheseTable a1 a2) (TheseTable b1 b2)


isThisTable :: TheseTable a b -> Expr 'NonNullable Bool
isThisTable a = hasHereTable a &&. not_ (hasThereTable a)


isThatTable :: TheseTable a b -> Expr 'NonNullable Bool
isThatTable a = not_ (hasHereTable a) &&. hasThereTable a


isThoseTable :: TheseTable a b -> Expr 'NonNullable Bool
isThoseTable a = hasHereTable a &&. hasThereTable a


hasHereTable :: TheseTable a b -> Expr 'NonNullable Bool
hasHereTable TheseTable {here} = isJustTable here


hasThereTable :: TheseTable a b -> Expr 'NonNullable Bool
hasThereTable TheseTable {there} = isJustTable there


thisTable :: (Table b, Context b ~ DB) => a -> TheseTable a b
thisTable a = TheseTable (justTable a) nothingTable


thatTable :: (Table a, Context a ~ DB) => b -> TheseTable a b
thatTable b = TheseTable nothingTable (justTable b)


thoseTable :: a -> b -> TheseTable a b
thoseTable a b = TheseTable (justTable a) (justTable b)


theseTable :: (Table c, Context c ~ DB)
  => (a -> c) -> (b -> c) -> (a -> b -> c) -> TheseTable a b -> c
theseTable f g h TheseTable {here, there} =
  maybeTable
    (maybeTable undefined f here)
    (\b -> maybeTable (g b) (`h` b) here)
    there
