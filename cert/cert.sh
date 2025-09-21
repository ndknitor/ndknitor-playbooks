#!/bin/bash

# Paths for the CA key and certificate
CA_KEY="./ca-key.pem"
CA_CERT="./ca.pem"
CA_CSR="./ca-csr.json"
CA_CONFIG="./ca-config.json"

# File that contains the list of servers (format: domain,ip)
SERVER_LIST="./servers.txt"

# Output directory for server certificates and keys
OUTPUT_DIR="certificates"


# # Check if cfssl is installed
# if ! command -v cfssl &> /dev/null
# then
#     echo "cfssl is not installed. Downloading..."
#     curl -Lo ./cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssl_1.6.5_linux_amd64
#     chmod +x ./cfssl
#     echo "cfssl installed successfully."
# else
#     echo "cfssl is already installed."
# fi

# # Check if cfssljson is installed
# if ! command -v cfssljson &> /dev/null
# then
#     echo "cfssljson is not installed. Downloading..."
#     curl -Lo ./cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.5/cfssljson_1.6.5_linux_amd64
#     chmod +x ./cfssljson
#     echo "cfssljson installed successfully."
# else
#     echo "cfssljson is already installed."
# fi


# Check if CA key and cert exist, and generate them if they don't
if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
    echo "CA key or certificate not found, generating new CA..."

    # Generate CA key and certificate
    cfssl genkey -initca "$CA_CSR" | cfssljson -bare ca
    mv ca-key.pem "$CA_KEY"
    mv ca.pem "$CA_CERT"
    echo "CA key and certificate generated at $CA_KEY and $CA_CERT"
fi

# Loop through the server list and generate certificates
while IFS=',' read -r common_name ip_address
do
    SERVER_DIR="$OUTPUT_DIR/$common_name"

    # Check if the server's certificate folder exists
    if [ -d "$SERVER_DIR" ]; then
        echo "Skipping $common_name, certificates already exist in $SERVER_DIR"
        continue
    fi

    echo "Generating certificate for $common_name ($ip_address)..."

    # Create a folder for each server inside the output directory
    mkdir -p "$SERVER_DIR"

    # Replace placeholders in the CSR template with the actual values
    sed "s/{{common_name}}/$common_name/g; s/{{ip_address}}/$ip_address/g" server-csr-template.json > "$SERVER_DIR/$common_name-csr.json"

    # Generate the private key and CSR for the server
    cfssl genkey "$SERVER_DIR/$common_name-csr.json" | cfssljson -bare "$SERVER_DIR/$common_name"

    # Sign the CSR with the CA to create the server certificate
    cfssl sign -ca="$CA_CERT" -ca-key="$CA_KEY" -config="$CA_CONFIG" "$SERVER_DIR/$common_name.csr" | cfssljson -bare "$SERVER_DIR/$common_name"

    echo "Certificate and key for $common_name stored in $SERVER_DIR"

done < "$SERVER_LIST"