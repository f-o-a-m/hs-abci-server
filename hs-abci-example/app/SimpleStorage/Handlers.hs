module SimpleStorage.Handlers where

import           Control.Lens                         (to, (&), (.~), (^.))
import           Data.ByteArray                       (convert)
import           Data.Default.Class                   (def)
import           Network.ABCI.Server.App              (MessageType (..),
                                                       Request (..),
                                                       Response (..))
import qualified Network.ABCI.Types.Messages.Request  as Req
import qualified Network.ABCI.Types.Messages.Response as Resp
import           SimpleStorage.Application            (Handler)
import           SimpleStorage.Modules.SimpleStorage  as SS
import           SimpleStorage.Types                  (AppTxMessage (..),
                                                       UpdateCountTx (..),
                                                       decodeAppTxMessage)
import           Tendermint.SDK.Application
import           Tendermint.SDK.Events                (flushEventBuffer)
import           Tendermint.SDK.Router

echoH
  :: Request 'MTEcho
  -> Handler (Response 'MTEcho)
echoH (RequestEcho echo) =
  pure . ResponseEcho $ def & Resp._echoMessage .~ echo ^. Req._echoMessage

flushH
  :: Request 'MTFlush
  -> Handler (Response 'MTFlush)
flushH = defaultHandler

infoH
  :: Request 'MTInfo
  -> Handler (Response 'MTInfo)
infoH = defaultHandler

setOptionH
  :: Request 'MTSetOption
  -> Handler (Response 'MTSetOption)
setOptionH = defaultHandler

-- TODO: this one might be useful for initializing to 0
-- instead of doing that manually in code
initChainH
  :: Request 'MTInitChain
  -> Handler (Response 'MTInitChain)
initChainH = defaultHandler

queryH
  :: QueryApplication Handler
  -> Request 'MTQuery
  -> Handler (Response 'MTQuery)
queryH serveRoutes (RequestQuery query) = do
  queryResp <- serveRoutes query
  pure $ ResponseQuery  queryResp

beginBlockH
  :: Request 'MTBeginBlock
  -> Handler (Response 'MTBeginBlock)
beginBlockH = defaultHandler

-- only checks to see if the tx parses
checkTxH
  :: Request 'MTCheckTx
  -> Handler (Response 'MTCheckTx)
checkTxH (RequestCheckTx checkTx) = pure . ResponseCheckTx $
  case decodeAppTxMessage $ checkTx ^. Req._checkTxTx . to convert of
    Left _                   ->  def & Resp._checkTxCode .~ 1
    Right (ATMUpdateCount _) -> def & Resp._checkTxCode .~ 0

deliverTxH
  :: Request 'MTDeliverTx
  -> Handler (Response 'MTDeliverTx)
deliverTxH (RequestDeliverTx deliverTx) = do
  case decodeAppTxMessage $ deliverTx ^. Req._deliverTxTx . to convert of
    Left _ -> return . ResponseDeliverTx $
      def & Resp._deliverTxCode .~ 1
    Right (ATMUpdateCount updateCountTx) -> do
      let count = SS.Count $ updateCountTxCount updateCountTx
      putCount count
      events <- flushEventBuffer
      return $ ResponseDeliverTx $ 
        def & Resp._deliverTxCode .~ 0
            & Resp._deliverTxEvents .~ events

endBlockH
  :: Request 'MTEndBlock
  -> Handler (Response 'MTEndBlock)
endBlockH = defaultHandler

commitH
  :: Request 'MTCommit
  -> Handler (Response 'MTCommit)
commitH = defaultHandler
