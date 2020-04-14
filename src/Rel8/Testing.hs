{-# language Arrows #-}
{-# language DataKinds #-}
{-# language DeriveAnyClass #-}
{-# language DeriveGeneric #-}
{-# language FlexibleInstances #-}
{-# language GADTs #-}
{-# language MultiParamTypeClasses #-}
{-# language PolyKinds #-}
{-# language ScopedTypeVariables #-}
{-# language TemplateHaskell #-}
{-# language TypeApplications #-}
{-# language TypeFamilies #-}
{-# language TypeSynonymInstances #-}
{-# language TypeInType #-}

{-# options -fplugin=RecordDotPreprocessor #-}

module Rel8.Testing where

import Control.Arrow ( arr, returnA )
import Database.PostgreSQL.Simple (Connection)
import GHC.Generics ( Generic )
import Rel8
import Rel8.Null

data MyTable = MyTable { columnA :: Bool, columnB :: Int } -- Adding this will fail, as 'Maybe Int' has no schema: , columnC :: Maybe Int }
  deriving (Generic, Table)


myTable :: Schema MyTable
myTable = Schema{ tableName = "my_table", schema = genericColumns }


dotTestColumnA :: Query x (Expr Bool)
dotTestColumnA = fmap (.columnA) (each myTable)


dotTestColumnB :: Query x (Expr Int)
dotTestColumnB = fmap (.columnB) (each myTable)


-- dotTestColumnC :: Expr (Maybe Int)
-- dotTestColumnC = fmap (.columnC) (each myTable)


selectTest :: Connection -> IO [MyTable]
selectTest c = select c ( each myTable )


data Part = Part { mfrId :: Int, description :: Null String }
  deriving (Generic, Table)

part :: Schema Part
part = Schema "part" genericColumns


allMfrIds :: Query x (Expr Int)
allMfrIds = fmap (.mfrId) (each part)


descs :: Query x (Expr (Null String))
descs = fmap (.description) (each part)


-- First we define our table type. Unlike all database libraries that I'm aware
-- of, there is nothing special here. The only thing we have to do is derive
-- a Table instance, which can be done generically.

data User = User { username :: String, email :: String }
  deriving (Generic, Table)


-- To be able to SELECT this table, we need to provide a schema. This can be
-- done generically, provided our type is just a product of single columns.

userSchema :: Schema User
userSchema =
  Schema { tableName = "user", schema = genericColumns }


-- This lets us construct a query that selects all users:

users :: Query x (Expr User)
users = each userSchema


-- Note that our Query produces 'Expr User', rather than just 'User'. Unlike
-- other Expr types in other libraries, expressions aren't limited to just
-- being single columns, so Expr User is a two-column expression, and that's
-- perfectly fine.

-- Expr's have a 'HasField' instance, so we can also project single columns
-- just using normal Haskell:

userNames :: Query (Expr User) (Expr String)
userNames = arr (.username)


-- We can run this to IO, too.
fetchUsers :: Connection -> IO [User]
fetchUsers c = select c users


leftJoinTest :: Query x (Expr (Maybe User))
leftJoinTest = proc _ -> do
  user1 <- each userSchema -< ()
  optional (proc _user1 -> do
    user2 <- each userSchema -< ()
    where_ -< lit False
    returnA -< user2) -< user1
