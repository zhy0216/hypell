module Hypell.Interpreter.OrderManager
  ( runOrderManagerPure
  ) where

import Data.Map.Strict qualified as Map
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll)
import Hypell.Effect.Exchange (Exchange, placeOrder)
import Hypell.Effect.OrderManager

runOrderManagerPure
  :: (Exchange :> es, State (Map.Map OrderId ManagedOrder) :> es)
  => Eff (OrderManager : es) a -> Eff es a
runOrderManagerPure = interpret_ $ \case
  SubmitOrder req -> do
    resp <- placeOrder req
    let oid = maybe 0 id (orspOrderId resp)
        status = case orspStatus resp of
          "resting" -> Open
          "filled"  -> Filled
          _         -> Rejected
    let mo = ManagedOrder oid req status (read "2026-01-01 00:00:00 UTC")
    modify $ Map.insert oid mo
    pure mo
  TrackOrder oid -> do
    orders <- get @(Map.Map OrderId ManagedOrder)
    pure $ maybe Cancelled moStatus (Map.lookup oid orders)
  CancelManaged oid ->
    modify $ Map.delete @OrderId @ManagedOrder oid
