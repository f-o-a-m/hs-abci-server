module Nameservice.Handlers where

import           Control.Lens                         (to, (&), (.~), (^.))
import qualified Data.ByteArray.Base64String          as Base64
import           Data.Default.Class                   (def)
import           Nameservice.Application              (compileToBaseApp, router)
import           Network.ABCI.Server.App              (App (..),
                                                       MessageType (..),
                                                       Request (..),
                                                       Response (..))
import qualified Network.ABCI.Types.Messages.Request  as Req
import qualified Network.ABCI.Types.Messages.Response as Resp
import           Polysemy                             (Sem)
import           Polysemy.Error                       (catch)
import           Tendermint.SDK.Application           (defaultHandler)
import           Tendermint.SDK.BaseApp               (BaseApp)
import           Tendermint.SDK.Codec                 (HasCodec (..))
import           Tendermint.SDK.Errors                (AppError, SDKError (..),
                                                       deliverTxAppError,
                                                       throwSDKError)
import           Tendermint.SDK.Events                (withEventBuffer)
import           Tendermint.SDK.Query                 (QueryApplication)

echoH
  :: Request 'MTEcho
  -> Sem BaseApp (Response 'MTEcho)
echoH (RequestEcho echo) =
  pure . ResponseEcho $ def & Resp._echoMessage .~ echo ^. Req._echoMessage

flushH
  :: Request 'MTFlush
  -> Sem BaseApp (Response 'MTFlush)
flushH = defaultHandler

infoH
  :: Request 'MTInfo
  -> Sem BaseApp (Response 'MTInfo)
infoH = defaultHandler

setOptionH
  :: Request 'MTSetOption
  -> Sem BaseApp (Response 'MTSetOption)
setOptionH = defaultHandler

-- TODO: this one might be useful for initializing to 0
-- instead of doing that manually in code
initChainH
  :: Request 'MTInitChain
  -> Sem BaseApp (Response 'MTInitChain)
initChainH = defaultHandler

queryH
  :: QueryApplication (Sem BaseApp)
  -> Request 'MTQuery
  -> Sem BaseApp (Response 'MTQuery)
queryH serveRoutes (RequestQuery query) = do
  queryResp <- serveRoutes query
  pure $ ResponseQuery  queryResp

beginBlockH
  :: Request 'MTBeginBlock
  -> Sem BaseApp (Response 'MTBeginBlock)
beginBlockH = defaultHandler

-- only checks to see if the tx parses
checkTxH
  :: Request 'MTCheckTx
  -> Sem BaseApp (Response 'MTCheckTx)
checkTxH = defaultHandler--(RequestCheckTx checkTx) =

 --   pure . ResponseCheckTx $
 -- case decodeAppTxMessage $ checkTx ^. Req._checkTxTx . to convert of
 --   Left _                   ->  def & Resp._checkTxCode .~ 1
 --   Right (ATMUpdateCount _) -> def & Resp._checkTxCode .~ 0

deliverTxH
  :: Request 'MTDeliverTx
  -> Sem BaseApp (Response 'MTDeliverTx) -- Sem BaseApp (Response 'MTDeliverTx)
deliverTxH (RequestDeliverTx deliverTx) =
  let tryToRespond = do
        tx <- either (throwSDKError . ParseError) return $
          decode $ deliverTx ^. Req._deliverTxTx . to Base64.toBytes
        events <- withEventBuffer . compileToBaseApp $ router tx
        return $ ResponseDeliverTx $
          def & Resp._deliverTxCode .~ 0
              & Resp._deliverTxEvents .~ events
  in tryToRespond `catch` \(err :: AppError) ->
       return . ResponseDeliverTx $ def & deliverTxAppError .~ err


  --case decodeAppTxMessage $ deliverTx ^. Req._deliverTxTx . to convert of
  --  Left _ -> return . ResponseDeliverTx $
  --    def & Resp._deliverTxCode .~ 1
  --  Right (ATMUpdateCount updateCountTx) -> do
  --    let count = SS.Count $ updateCountTxCount updateCountTx
  --    events <- withEventBuffer $ putCount count
  --    return $ ResponseDeliverTx $
  --      def & Resp._deliverTxCode .~ 0
  --          & Resp._deliverTxEvents .~ events

endBlockH
  :: Request 'MTEndBlock
  -> Sem BaseApp (Response 'MTEndBlock)
endBlockH = defaultHandler

commitH
  :: Request 'MTCommit
  -> Sem BaseApp (Response 'MTCommit)
commitH = defaultHandler

nameserviceApp :: QueryApplication (Sem BaseApp) -> App (Sem BaseApp)
nameserviceApp serveRoutes = App $ \case
  msg@(RequestEcho _) -> echoH msg
  msg@(RequestFlush _) -> flushH msg
  msg@(RequestInfo _) -> infoH msg
  msg@(RequestSetOption _) -> setOptionH msg
  msg@(RequestInitChain _) -> initChainH msg
  msg@(RequestQuery _) -> queryH serveRoutes msg
  msg@(RequestBeginBlock _) -> beginBlockH msg
  msg@(RequestCheckTx _) -> checkTxH msg
  msg@(RequestDeliverTx _) -> deliverTxH msg
  msg@(RequestEndBlock _) -> endBlockH msg
  msg@(RequestCommit _) -> commitH msg
