module Hypell.Effect.Account
  ( Account(..)
  , getBalances
  , getUserTrades
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data Account :: Effect where
  GetBalances   :: Account m [TokenBalance]
  GetUserTrades :: Account m [UserTrade]

makeEffect ''Account
