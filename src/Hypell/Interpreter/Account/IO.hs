module Hypell.Interpreter.Account.IO
  ( runAccountIO
  ) where

import Data.Aeson (Value, object, (.=), fromJSON, Result(Success), withObject, (.:))
import Data.Aeson.Types (parseMaybe, Parser)
import Data.Scientific (Scientific)
import Data.Text (Text, pack, unpack)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Api.Rest (RestClient, postInfo)
import Hypell.Effect.Account
import Hypell.Effect.Log (Log, log, logError)
import Hypell.Types
import Prelude hiding (log)
import Text.Read (readMaybe)

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
        _ -> do
          logError "GetBalances parse error"
          pure []

  GetUserTrades -> do
    log "Fetching user trades"
    let payload = object
          [ "type" .= ("userFills" :: Text)
          , "user" .= walletAddr
          ]
    result <- liftIO $ postInfo rc payload
    case result of
      Left err -> do
        logError $ "GetUserTrades failed: " <> pack err
        pure []
      Right val -> case parseFills val of
        trades -> pure trades

-- | Parse a Hyperliquid userFills response (an array of fill objects).
parseFills :: Value -> [UserTrade]
parseFills val = case fromJSON val :: Result [Value] of
  Success fills -> concatMap (maybe [] pure . parseFill) fills
  _             -> []

-- | Parse a single Hyperliquid fill object into a UserTrade.
-- Hyperliquid fields: coin, side, px (price string), sz (size string),
-- fee (string), time (epoch ms), oid (order id).
parseFill :: Value -> Maybe UserTrade
parseFill = parseMaybe $ withObject "Fill" $ \o -> do
  coin    <- Coin <$> (o .: "coin" :: Parser Text)
  side    <- o .: "side"
  pxText  <- o .: "px"   :: Parser Text
  szText  <- o .: "sz"   :: Parser Text
  feeText <- o .: "fee"  :: Parser Text
  epochMs <- o .: "time" :: Parser Int
  oid     <- o .: "oid"
  px  <- parseScientific pxText
  sz  <- parseScientific szText
  fee <- parseScientific feeText
  let t = posixSecondsToUTCTime (fromIntegral epochMs / 1000)
  pure UserTrade
    { utCoin    = coin
    , utSide    = side
    , utPrice   = px
    , utSize    = sz
    , utFee     = fee
    , utTime    = t
    , utOrderId = oid
    }

parseScientific :: Text -> Parser Scientific
parseScientific t = case readMaybe (unpack t) of
  Just n  -> pure n
  Nothing -> fail $ "Invalid number: " <> unpack t
