{-# language DefaultSignatures #-}
{-# language FlexibleInstances #-}
{-# language MultiParamTypeClasses #-}
{-# language RoleAnnotations #-}
{-# language ScopedTypeVariables #-}
{-# language TypeApplications #-}
{-# language TypeFamilies #-}
{-# language UndecidableInstances #-}

module Rel8.Expr where

import Data.Coerce
import Data.Int
import Data.Kind
import Data.String
import Data.Text ( Text, unpack )
import qualified Opaleye.Internal.HaskellDB.PrimQuery as Opaleye
import Rel8.Column
import Rel8.Table
import Rel8.ZipLeaves


-- | Typed SQL expressions
newtype Expr ( m :: Type -> Type ) ( a :: Type ) =
  Expr { toPrimExpr :: Opaleye.PrimExpr }


type role Expr representational representational


instance Table ( Expr m a ) where
  type ExprIn ( Expr m a ) = Expr m


instance ( IsString a, DBType a ) => IsString ( Expr m a ) where
  fromString =
    lit . fromString


instance {-# overlaps #-} ( IsString a, DBType a ) => IsString ( Expr m ( Maybe a ) ) where
  fromString =
    lit . Just . fromString


-- | The class of all Haskell types that can be represented as expressiosn
-- in a database. There should be an instance of @DBType@ for all column
-- types in your database schema (e.g., @int@, @timestamptz@, etc).
--
-- Rel8 comes with stock instances for all default types in PostgreSQL.
class DBType ( a :: Type ) where
  -- | Lift a Haskell value into a literal SQL expression.
  lit :: a -> Expr m a

  default lit :: Show a => a -> Expr m a
  lit = unsafeCoerceExpr . lit . show


instance DBType a => DBType ( Maybe a ) where
  lit =
    maybe ( Expr ( Opaleye.ConstExpr Opaleye.NullLit ) ) ( unsafeCoerceExpr .  lit )


instance DBType Bool where
  lit =
    Expr . Opaleye.ConstExpr . Opaleye.BoolLit


instance DBType Int32 where
  lit =
    Expr . Opaleye.ConstExpr . Opaleye.IntegerLit . fromIntegral


instance DBType Int64 where
  lit =
    Expr . Opaleye.ConstExpr . Opaleye.IntegerLit . fromIntegral


instance DBType Text where
  lit =
    unsafeCoerceExpr . lit . unpack


instance DBType String where
  lit =
    Expr . Opaleye.ConstExpr . Opaleye.StringLit


instance a ~ b => ZipLeaves ( Expr m a ) ( Expr n b ) ( Expr m ) ( Expr n ) where
  type CanZipLeaves ( Expr m a ) ( Expr n b ) c =
    c a

  zipLeaves _ f e1 e2 =
    toColumn <$> f ( C e1 ) ( C e2 )


-- | The SQL @AND@ operator.
(&&.) :: Expr m Bool -> Expr m Bool -> Expr m Bool
(&&.) ( Expr a ) ( Expr b ) =
    Expr ( Opaleye.BinExpr (Opaleye.:&&) a b )


-- | The SQL @OR@ operator.
(||.) :: Expr m Bool -> Expr m Bool -> Expr m Bool
(||.) ( Expr a ) ( Expr b ) =
    Expr ( Opaleye.BinExpr (Opaleye.:||) a b )


-- | The SQL @NOT@ operator.
not_ :: Expr m Bool -> Expr m Bool
not_ ( Expr a ) =
  Expr ( Opaleye.UnExpr Opaleye.OpNot a )


-- | Use Haskell's 'Coercible' type class to witness that two types
-- are actually compatible in the SQL expressions they produce.
coerceExpr :: forall b a m. Coercible a b => Expr m a -> Expr m b
coerceExpr e =
  const
    ( unsafeCoerceExpr e )
    ( coerce @a @b undefined )


unsafeCoerceExpr :: Expr m a -> Expr m b
unsafeCoerceExpr ( Expr x ) = Expr x


-- | The @Function@ type class is an implementation detail that allows
-- @dbFunction@ to be polymorphic in the number of arguments it consumes.
class Function arg res where
  -- | Build a function of multiple arguments.
  applyArgument :: ( [ Opaleye.PrimExpr ] -> Opaleye.PrimExpr ) -> arg -> res


instance arg ~ Expr m a => Function arg ( Expr m res ) where
  applyArgument mkExpr ( Expr a ) =
    Expr ( mkExpr [ a ] )


instance ( arg ~ Expr m a, Function args res ) => Function arg ( args -> res ) where
  applyArgument f ( Expr a ) =
    applyArgument ( f . ( a : ) )


{-| Construct an n-ary function that produces an 'Expr' that when called runs a
SQL function.

For example, if we have a SQL function @foo(x, y, z)@, we can represent this
in Rel8 with:

@
foo :: Expr m Int32 -> Expr m Int32 -> Expr m Bool -> Expr m Text
foo = dbFunction "foo"
@

-}
dbFunction :: Function args result => String -> args -> result
dbFunction =
  applyArgument . Opaleye.FunExpr


{-| Construct a function call for functions with no arguments.

As an example, we can call the database function @now()@ by using
@nullaryFunction@:

@
now :: Expr m UTCTime
now = nullaryFunction "now"
@

-}
nullaryFunction :: DBType a => String -> Expr m a
nullaryFunction = nullaryFunction_forAll


nullaryFunction_forAll :: forall a m. DBType a => String -> Expr m a
nullaryFunction_forAll name =
  const ( Expr ( Opaleye.FunExpr name [] ) ) ( lit @a undefined )
