module Hypell.Effect.Log
  ( Log
  , log
  , logDebug
  , logWarn
  , logError
  , runLog
  , mkLogAction
  ) where

import Prelude hiding (log)
import Colog.Core (LogAction(..))
import Control.Monad (when)
import qualified Data.Text
import Data.Text (Text)
import qualified Data.Text.IO as TIO
import Data.Time (getCurrentTime)
import Effectful
import Effectful.Dispatch.Static
import Hypell.Types (LogLevel(..))

data Log :: Effect
type instance DispatchOf Log = Static WithSideEffects
newtype instance StaticRep Log = Log (LogAction IO Text)

log :: Log :> es => Text -> Eff es ()
log msg = do
  Log (LogAction action) <- getStaticRep
  unsafeEff_ $ action msg

logDebug :: Log :> es => Text -> Eff es ()
logDebug = log . ("[DEBUG] " <>)

logWarn :: Log :> es => Text -> Eff es ()
logWarn = log . ("[WARN] " <>)

logError :: Log :> es => Text -> Eff es ()
logError = log . ("[ERROR] " <>)

runLog :: IOE :> es => LogAction IO Text -> Eff (Log : es) a -> Eff es a
runLog action = evalStaticRep (Log action)

mkLogAction :: LogLevel -> LogAction IO Text
mkLogAction minLevel = LogAction $ \msg -> do
  let msgLevel = parseLevel msg
  when (msgLevel >= minLevel) $ do
    t <- getCurrentTime
    TIO.putStrLn $ "[" <> tshow t <> "] " <> msg
  where
    tshow = Data.Text.pack . show
    parseLevel m
      | "[DEBUG]" `Data.Text.isPrefixOf` m = Debug
      | "[WARN]"  `Data.Text.isPrefixOf` m = Warn
      | "[ERROR]" `Data.Text.isPrefixOf` m = Error
      | otherwise                          = Info
