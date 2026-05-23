#!/bin/bash

# Constants
DPU_IP="10.13.36.46"     
USERNAME="ubuntu"         
IMAGE_NAME="simple_fwd_vnf"
IMAGE_FILE="${IMAGE_NAME//[:\/]/_}.tar"

# Step 1: Build the Docker image
echo "[*] Building Docker image '$IMAGE_NAME'..."
docker build -t "$IMAGE_NAME" .

# Step 2: Save the image to a tarball
echo "[*] Saving Docker image '$IMAGE_NAME' to '$IMAGE_FILE'..."
docker save "$IMAGE_NAME" -o "$IMAGE_FILE"

# Step 3: Copy the tarball to the DPU
echo "[*] Copying image to DPU at $DPU_IP..."
scp "$IMAGE_FILE" "$USERNAME@$DPU_IP:~/"

# Step 4: Load the image into Docker on the DPU and remove tar
echo "[*] Loading image on DPU and cleaning up..."
ssh "ubuntu@$DPU_IP" "docker load -i ~/$IMAGE_FILE && rm ~/$IMAGE_FILE"

# Cleanup local tar file
rm "$IMAGE_FILE"

echo "[✓] Docker image '$IMAGE_NAME' deployed to DPU at $DPU_IP"
