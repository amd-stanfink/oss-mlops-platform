#!/bin/bash

set -eoa pipefail

# Internal directory where to store platform settings
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PLATFORM_DIR="$SCRIPT_DIR/.platform"
PLATFORM_CONFIG="$PLATFORM_DIR/.config"

source $PLATFORM_CONFIG

LOG_LEVEL_TESTS="WARNING"

echo Cluster name set to: "$CLUSTER_NAME"
echo Host IP set to: "$HOST_IP"

file=$PLATFORM_CONFIG
key="DEPLOYMENT_OPTION"

# Ensure the file exists
if [ ! -f "$file" ]; then
    echo "File '$file' not found!"
    exit 1
fi

# Search for the key and extract the value
value=$(grep -E "^\s*$key\s*=" "$file" | sed -E "s/^\s*$key\s*=\s*(.*)/\1/")

# Check if a value was found
if [ -z "$value" ]; then
    echo "Key '$key' not found in '$file'."
    exit 1
else
    DEPLOYMENT_OPTION="$value"
fi

# Check if the kind cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
  echo
  echo "Kind cluster with name \"$CLUSTER_NAME\" already exists. It can be deleted with the following command: kind delete cluster --name $CLUSTER_NAME"
  while true; do
    read -p "Do you want to continue the installation on the existing cluster? (y/n): " choice
    case "$choice" in
        y|Y ) echo "Using existing kind cluster..."; break;;
        n|N ) exit 0 ;;
        * ) echo "Invalid response. Please enter y or n." ;;
        "" ) echo "Please enter a response." ;;
    esac
  done
else
    echo "Creating kind cluster..."
    /bin/bash "$SCRIPT_DIR/scripts/create_cluster.sh"
fi

kubectl cluster-info --context kind-$CLUSTER_NAME

# DEPLOY STACK
kubectl config use-context kind-$CLUSTER_NAME

# Build the kustomization and store the output in the temporary file
tmp_file=$(mktemp)
DEPLOYMENT_ROOT="$SCRIPT_DIR/deployment/envs/$DEPLOYMENT_OPTION"
echo "Deployment root set to: $DEPLOYMENT_ROOT"
echo
echo "Building manifests..."
kustomize build $DEPLOYMENT_ROOT > "$tmp_file"
echo "Manifests built successfully."
echo
echo "Applying resources..."
while true; do
  if kubectl apply -f "$tmp_file"; then
      echo "Resources successfully applied."
      rm "$tmp_file"
      break
  else
      echo
      echo "Retrying to apply resources."
      echo "Be patient, this might take a while... (Errors are expected until all resources are available!)"
      echo
      echo "Help:"
      echo "  If the errors persists, please check the pods status with: kubectl get pods --all-namespaces"
      echo "  All pods should be either in Running state, or ContainerCreating if they are still starting up."
      echo "  Check specific pod errors with: kubectl describe pod -n [NAMESPACE] [POD_NAME]"
      echo "  For further help, see the Troubleshooting section in setup.md"
      echo

      sleep 10
  fi
done

echo
echo "Installation completed!"
echo

exit 0
