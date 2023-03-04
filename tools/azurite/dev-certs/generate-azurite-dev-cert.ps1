# Note: assumes you have already install mkcert!

# install a local certificate authority (CA) in the root store (skipped if already installed)
mkcert -install

# create a certificate that is chained to the root CA above (and therefore trusted) 
mkcert -cert-file $PSScriptRoot/127.0.0.1.pem -key-file $PSScriptRoot/127.0.0.1-key.pem 127.0.0.1