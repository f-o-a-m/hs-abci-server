module SimpleStorage.Test.HandlersSpec where

import           Control.Lens                         (to, (&), (.~), (^.))
import           Control.Lens.Wrapped                 (_Unwrapped', _Wrapped')
import           Data.ByteArray.Base64String          (Base64String)
import qualified Data.ByteArray.Base64String          as Base64
import           Data.Int                             (Int32)
import           Data.ProtoLens                       (defMessage)
import           Data.ProtoLens.Encoding              (encodeMessage)
import           Data.Proxy
import           Data.Serialize                       (decode, encode)
import           Data.Text                            (pack)
import           Network.ABCI.Server.App              (Request (..),
                                                       Response (..))
import qualified Network.ABCI.Types.Messages.Request  as Req
import qualified Network.ABCI.Types.Messages.Response as Resp
import           SimpleStorage.Application            (AppConfig, makeAppConfig,
                                                       runHandler)
import           SimpleStorage.Handlers               (deliverTxH, queryH)
import qualified SimpleStorage.Modules.SimpleStorage  as SS
import           SimpleStorage.Types                  (UpdateCountTx (..))
import           Tendermint.SDK.Logger.Katip
import           Tendermint.SDK.Router                (serve)
import           Tendermint.SDK.Store                 (rawKey)
import           Test.Hspec
import           Test.QuickCheck


spec :: Spec
spec = beforeAll beforeAction $ do
  describe "SimpleStorage E2E - via handlers" $ do
    let serveRoutes = serve (Proxy :: Proxy SS.Api) SS.server
    it "Can update count and make sure it increments" $ \cfg -> do
      genUsername <- pack . getPrintableString <$> generate arbitrary
      genCount    <- abs <$> generate arbitrary
      let
        handleDeliver = runHandler cfg . deliverTxH
        handleQuery = runHandler cfg . queryH serveRoutes
        updateTx = (defMessage ^. _Unwrapped') { updateCountTxUsername = genUsername
                                               , updateCountTxCount = genCount
                                               }
        encodedUpdateTx = Base64.fromBytes $ encodeMessage (updateTx ^. _Wrapped')
      (ResponseDeliverTx deliverResp) <- handleDeliver
        (  RequestDeliverTx
        $  defMessage
        ^. _Unwrapped'
        &  Req._deliverTxTx
        .~ encodedUpdateTx
        )
      (deliverResp ^. Resp._deliverTxCode) `shouldBe` 0
      -- TODO: check for logs
      (ResponseQuery queryResp) <- handleQuery
        ( RequestQuery $ defMessage ^. _Unwrapped'
            & Req._queryPath .~ "simple_storage/count"
            & Req._queryData  .~ SS.CountKey ^. rawKey . to Base64.fromBytes
        )
      let foundCount = queryResp ^. Resp._queryValue . to decodeCount
      foundCount `shouldBe` genCount

beforeAction :: IO AppConfig
beforeAction = mkLogConfig "handler-spec" "SimpleStorage" >>= makeAppConfig

encodeCount :: Int32 -> Base64String
encodeCount = Base64.fromBytes . encode

decodeCount :: Base64String -> Int32
decodeCount = (\(Right a) -> a) . decode . Base64.toBytes
