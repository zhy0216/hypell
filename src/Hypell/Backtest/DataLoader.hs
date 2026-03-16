module Hypell.Backtest.DataLoader
  ( OHLCVBar(..)
  , loadCsvTrades
  , loadJsonTrades
  , ohlcvToEvents
  , tradesToEvents
  ) where

import Data.Aeson (eitherDecodeFileStrict)
import Data.ByteString.Lazy qualified as BL
import Data.Csv
  ( FromNamedRecord(..), (.:), decodeByName )
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Data.Time.Format (parseTimeM, defaultTimeLocale)
import Data.Vector qualified as V
import GHC.Generics (Generic)
import Hypell.Types

-- ---------------------------------------------------------------------------
-- OHLCV bar type
-- ---------------------------------------------------------------------------

data OHLCVBar = OHLCVBar
  { ohlcvCoin   :: Coin
  , ohlcvTime   :: UTCTime
  , ohlcvOpen   :: Scientific
  , ohlcvHigh   :: Scientific
  , ohlcvLow    :: Scientific
  , ohlcvClose  :: Scientific
  , ohlcvVolume :: Scientific
  } deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- CSV trade loader
-- CSV format: time,coin,side,price,size
-- ---------------------------------------------------------------------------

data CsvTradeRow = CsvTradeRow
  { csvTime  :: Text
  , csvCoin  :: Text
  , csvSide  :: Text
  , csvPrice :: Scientific
  , csvSize  :: Scientific
  } deriving stock (Generic)

instance FromNamedRecord CsvTradeRow where
  parseNamedRecord r =
    CsvTradeRow
      <$> r .: "time"
      <*> r .: "coin"
      <*> r .: "side"
      <*> r .: "price"
      <*> r .: "size"

loadCsvTrades :: FilePath -> IO (Either String [MarketEvent])
loadCsvTrades path = do
  bs <- BL.readFile path
  case decodeByName bs of
    Left  err        -> pure $ Left err
    Right (_, rows)  ->
      let results = map rowToTrade (V.toList rows)
          errs    = [ e | Left e <- results ]
          trades  = [ t | Right t <- results ]
      in if null errs
           then pure $ Right (tradesToEvents trades)
           else pure $ Left (unlines errs)

rowToTrade :: CsvTradeRow -> Either String Trade
rowToTrade row = do
  t    <- parseTime (T.unpack (csvTime row))
  side <- parseSide (csvSide row)
  pure Trade
    { trdCoin  = Coin (csvCoin row)
    , trdSide  = side
    , trdPrice = csvPrice row
    , trdSize  = csvSize row
    , trdTime  = t
    }

parseTime :: String -> Either String UTCTime
parseTime s =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%Z" s of
    Just t  -> Right t
    Nothing ->
      case parseTimeM True defaultTimeLocale "%Y-%m-%d %H:%M:%S" s of
        Just t  -> Right t
        Nothing -> Left $ "Cannot parse time: " <> s

parseSide :: Text -> Either String Side
parseSide "buy"  = Right Buy
parseSide "sell" = Right Sell
parseSide "B"    = Right Buy
parseSide "A"    = Right Sell
parseSide s      = Left $ "Unknown side: " <> T.unpack s

-- ---------------------------------------------------------------------------
-- JSON trade loader
-- Expects a JSON array of Trade objects matching the Trade FromJSON instance
-- ---------------------------------------------------------------------------

loadJsonTrades :: FilePath -> IO (Either String [MarketEvent])
loadJsonTrades path = do
  result <- eitherDecodeFileStrict path
  pure $ fmap tradesToEvents result

-- ---------------------------------------------------------------------------
-- Group trades into one TradeUpdate per timestamp, preserving order
-- ---------------------------------------------------------------------------

tradesToEvents :: [Trade] -> [MarketEvent]
tradesToEvents = map (TradeUpdate . (:[])) 

-- ---------------------------------------------------------------------------
-- OHLCV bar → synthetic trade events
-- Expansion order: open → low → high → close
-- This ensures both buy and sell limit orders can be triggered within a bar.
-- ---------------------------------------------------------------------------

ohlcvToEvents :: [OHLCVBar] -> [MarketEvent]
ohlcvToEvents = concatMap barToEvents

barToEvents :: OHLCVBar -> [MarketEvent]
barToEvents bar =
  let coin = ohlcvCoin bar
      t    = ohlcvTime bar
      mk p side = TradeUpdate
        [ Trade
            { trdCoin  = coin
            , trdSide  = side
            , trdPrice = p
            , trdSize  = ohlcvVolume bar / 4
            , trdTime  = t
            }
        ]
  in [ mk (ohlcvOpen  bar) Buy
     , mk (ohlcvLow   bar) Sell
     , mk (ohlcvHigh  bar) Buy
     , mk (ohlcvClose bar) Buy
     ]
