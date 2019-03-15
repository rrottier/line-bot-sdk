{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE TypeOperators     #-}

module Line.Bot.ClientSpec (spec) where

import           Control.Arrow                    (left)
import           Control.Monad.Trans.Reader       (runReaderT)
import           Data.Aeson                       (Value)
import           Data.Aeson.QQ
import           Data.ByteString                  as B (stripPrefix)
import           Data.Text
import           Data.Text.Encoding
import           Line.Bot.Client                  hiding (runLine)
import           Line.Bot.Client.Auth
import           Line.Bot.Endpoints               (ChannelAuth)
import           Line.Bot.Types
import           Network.HTTP.Client              (defaultManagerSettings,
                                                   newManager)
import           Network.HTTP.Types               (hAuthorization)
import           Network.Wai                      (Request, requestHeaders)
import           Network.Wai.Handler.Warp         (Port, withApplication)
import           Servant
import           Servant.Client
import           Servant.Client.Core.Reexport
import           Servant.Server                   (Context (..))
import           Servant.Server.Experimental.Auth (AuthHandler, AuthServerData,
                                                   mkAuthHandler)
import           Test.Hspec
import           Test.Hspec.Expectations.Contrib
import           Test.Hspec.Wai

type instance AuthServerData ChannelAuth = ChannelToken

-- a dummy auth handler that returns the channel access token
authHandler :: AuthHandler Request ChannelToken
authHandler = mkAuthHandler $ \request -> do
  case lookup hAuthorization (requestHeaders request) >>= B.stripPrefix "Bearer " of
    Nothing -> throwError $ err401 { errBody = "Bad" }
    Just t  -> return $ ChannelToken $ decodeUtf8 t

serverContext :: Context '[AuthHandler Request ChannelToken]
serverContext = authHandler :. EmptyContext

type API =
       ChannelAuth :> "v2" :> "bot" :> "profile" :> "1" :> Get '[JSON] Value
  :<|> ChannelAuth :> "v2" :> "bot" :> "group" :> "1" :> "member" :> "1" :> Get '[JSON] Value

testProfile :: Value
testProfile = [aesonQQ|
  {
      displayName: "LINE taro",
      userId: "U4af4980629...",
      pictureUrl: "https://obs.line-apps.com/...",
      statusMessage: "Hello, LINE!"
  }
|]

withPort :: Port -> (ClientEnv -> IO a) -> IO a
withPort port app = do
  manager <- newManager defaultManagerSettings
  app $ mkClientEnv manager $ BaseUrl Http "localhost" port ""

runLine :: Line a -> Port -> IO (Either ServantError a)
runLine comp port = withPort port $ runClientM $ runReaderT comp "fake"

app :: Application
app = serveWithContext (Proxy :: Proxy API) serverContext $
       (\_ -> return testProfile)
  :<|> (\_ -> return testProfile)

spec :: Spec
spec = describe "Line client" $ do
  it "should return user profile" $ do
    withApplication (pure app) $ \port -> do
      runLine (getProfile "1") port >>= \x -> x `shouldSatisfy` isRight

  it "should return group user profile" $ do
    withApplication (pure app) $ \port -> do
      runLine (getGroupMemberProfile "1" "1") port >>= \x -> x `shouldSatisfy` isRight