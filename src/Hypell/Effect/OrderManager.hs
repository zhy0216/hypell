module Hypell.Effect.OrderManager
  ( OrderManager(..)
  , ManagedOrder(..)
  , submitOrder
  , trackOrder
  , cancelManaged
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Data.Time (UTCTime)
import Hypell.Types

data ManagedOrder = ManagedOrder
  { moId        :: OrderId
  , moRequest   :: OrderRequest
  , moStatus    :: OrderStatus
  , moCreatedAt :: UTCTime
  } deriving stock (Eq, Show)

data OrderManager :: Effect where
  SubmitOrder   :: OrderRequest -> OrderManager m ManagedOrder
  TrackOrder    :: OrderId -> OrderManager m OrderStatus
  CancelManaged :: OrderId -> OrderManager m ()

makeEffect ''OrderManager
