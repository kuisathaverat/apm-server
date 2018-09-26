set -e
export GOPATH=$WORKSPACE
export PATH=$PATH:$GOPATH/bin
eval "$(gvm 1.10.3)"
echo "Installing hey-apm dependencies and running unit tests..."
go get -v -u github.com/golang/dep/cmd/dep
dep ensure -v
SKIP_EXTERNAL=1 SKIP_STRESS=1 go test -v ./...
echo "Fetching apm-server and installing latest go-licenser and mage..."
APM_SERVER_DIR=$GOPATH/src/github.com/elastic/apm-server
if [ ! -d "$APM_SERVER_DIR" ] ; then
    git clone git@github.com:elastic/apm-server.git "$APM_SERVER_DIR"
else
    (cd "$APM_SERVER_DIR" && git pull git@github.com:elastic/apm-server.git)
fi
go get -v -u github.com/elastic/go-licenser
go get -v -u github.com/magefile/mage
(cd $GOPATH/src/github.com/magefile/mage && go run bootstrap.go)
echo "Running apm-server stress tests..."
set +x
VAULT_TOKEN=$( curl -s -X POST -H "Content-Type: application/json" -L -d "{\"role_id\":\"$VAULT_ROLE_ID_HEY_APM\",\"secret_id\":\"$VAULT_SECRET_ID_HEY_APM\"}" $VAULT_ADDR/v1/auth/approle/login | jq -r '.auth.client_token' )
CLOUD_DATA=$( curl -s -L -H "X-Vault-Token:$VAULT_TOKEN" $VAULT_ADDR/v1/secret/apm-team/ci/apm-server-benchmark-cloud )
unset VAULT_TOKEN VAULT_SECRET_ID_HEY_APM VAULT_ROLE_ID_HEY_APM
CLOUD_USERNAME=$( echo $CLOUD_DATA | jq '.data.user' | tr -d '"' )
CLOUD_PASSWORD=$( echo $CLOUD_DATA | jq '.data.password' | tr -d '"' )
CLOUD_ADDR=$( echo $CLOUD_DATA | jq '.data.url' | tr -d '"' )
ELASTICSEARCH_URL=$CLOUD_ADDR ELASTICSEARCH_USR=$CLOUD_USERNAME ELASTICSEARCH_PWD=$CLOUD_PASSWORD go test -timeout 2h  -v github.com/elastic/hey-apm/server/client
set -x