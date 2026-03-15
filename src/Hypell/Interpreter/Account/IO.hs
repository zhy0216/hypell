module Hypell.Interpreter.Account.IO
  ( runAccountIO
  ) where

import Data.Aeson (object, (.=), fromJSON, Result(..))
import Data.Text (Text, pack)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Api.Rest (RestClient, postInfo)
import Hypell.Effect.Account
import Hypell.Effect.Log (Log, log, logError)
import Hypell.Types () -- instances only
import Prelude hiding (log)

-- | IO interpreter for the Account effect.
-- Uses RestClient for HTTP info queries.
runAccountIO
  :: (IOE :> es, Log :> es)
  => RestClient -> Text
  -> Eff (Account : es) a -> Eff es a
runAccountIO rc walletAddr = interpret_ $ \case
  GetBalances -> do
    log "Fetching balances"
    let payload = object
          [ "type" .= ("spotClearinghouseState" :: Text)
          , "user" .= walletAddr
          ]
    result <- liftIO $ postInfo rc payload
    case result of
      Left err -> do
        logError $ "GetBalances failed: " <> pack err
        pure []
      Right val -> case fromJSON val of
        Success bals -> pure bals
        Error err -> do
          logError $ "GetBalances parse error: " <> pack err
          pure []

  GetUserTrades -> do
    log "GetUserTrades: not yet implemented"
    pure []  -- TODO: implement user trades query
