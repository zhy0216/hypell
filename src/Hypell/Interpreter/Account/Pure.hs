module Hypell.Interpreter.Account.Pure
  ( runAccountPure
  ) where

import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.Account

runAccountPure
  :: State [TokenBalance] :> es
  => Eff (Account : es) a -> Eff es a
runAccountPure = interpret_ $ \case
  GetBalances   -> get
  GetUserTrades -> pure []
