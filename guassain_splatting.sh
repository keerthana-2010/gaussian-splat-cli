#!/bin/bash
# =============================================================================
# gaussian_splatting.sh
# =============================================================================
# Automated headless pipeline for 3D Gaussian Splatting on a DGX server.
# Developed at TH OWL — Gamification Innovation Lab, Winter Term 2025.
#
# What this script does:
#   1. Spins up a GPU-enabled Docker container (NVIDIA PyTorch image)
#   2. Installs all dependencies inside the container (COLMAP, GS submodules)
#   3. Runs COLMAP to estimate camera poses from input images
#   4. Trains the 3D Gaussian Splatting model (Kerbl et al., SIGGRAPH 2023)
#   5. Copies the final .ply splat file to a fixed output location
#
# Usage:
#   1. Run `nvidia-smi` on the DGX server to find a free GPU
#   2. Set GPU_ID below to that GPU number
#   3. Place your images in: /workspace/gs_pipeline/my_scene/images
#   4. bash gaussian_splatting.sh
#
# Authors: Nithya Kanakam, Keerthana Kothakapu Adamulla
# =============================================================================

set -euo pipefail
# Stop the script immediately if:
#   - any command fails
#   - an undefined variable is used
#   - any command in a pipeline fails

# =============================================================================
# CONFIGURATION — update these before running
# =============================================================================

# Run `nvidia-smi` first to check which GPU is free.
# Replace GPU_ID with the free GPU number on the DGX server.
# Example: GPU_ID=3 means Docker will use GPU 3.
GPU_ID=0

# Host directory mounted into the Docker container.
WORKSPACE="/data/pool/(your_username)"

# Main project directory inside the Docker container.
PIPELINE_DIR="/workspace/gs_pipeline"

# Scene directory containing the input images.
# Images must be placed inside: /workspace/gs_pipeline/my_scene/images
SCENE_DIR="${PIPELINE_DIR}/my_scene"

# Directory where GraphDeco training results will be saved.
OUTPUT_DIR="${PIPELINE_DIR}/outputs/my_scene_r4_new"

# Final copied PLY file location for easier access.
FINAL_PLY="${PIPELINE_DIR}/outputs/my_scene_final.ply"

# Docker container name, including the selected GPU ID.
CONTAINER_NAME="gs_train_gpu${GPU_ID}"

# NVIDIA PyTorch Docker image — provides CUDA, PyTorch, and GPU support out of the box.
DOCKER_IMAGE="nvcr.io/nvidia/pytorch:24.01-py3"

# =============================================================================
# STEP 1: Start Docker Container
# =============================================================================

echo "  GPU         →  $GPU_ID"
echo "  Workspace   →  $WORKSPACE"
echo "  Scene dir   →  $SCENE_DIR"
echo "  Output dir  →  $OUTPUT_DIR"
echo ""
echo "──────────────────────────────────────────────────"

# Remove any existing container with the same name to avoid conflicts.
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

echo "  Starting Docker container on GPU ${GPU_ID}..."

# Start the GPU-enabled Docker container and mount the workspace directory.
# Everything from here runs inside the container.
docker run --rm -it \
  --gpus "device=${GPU_ID}" \
  --name "${CONTAINER_NAME}" \
  -v "${WORKSPACE}:/workspace" \
  "${DOCKER_IMAGE}" \
  bash -lc "

# Stop execution inside the container if any command fails.
set -euo pipefail

# =============================================================================
# STEP 2: Setup — Clone / Update Gaussian Splatting Repo
# =============================================================================

cd /workspace
mkdir -p gs_pipeline/outputs
cd gs_pipeline

echo ''
echo '  [1/5] Setting up Gaussian Splatting repository...'

# Clone the official GraphDeco Gaussian Splatting repo if not already present.
# If it exists, pull the latest changes and update submodules.
if [ ! -d gaussian-splatting ]; then
  git clone https://github.com/graphdeco-inria/gaussian-splatting --recursive
else
  cd gaussian-splatting
  git pull
  git submodule update --init --recursive
  cd ..
fi

cd gaussian-splatting
echo '     Repository ready.'

# =============================================================================
# STEP 3: Install Dependencies
# =============================================================================

echo ''
echo '🔧  [2/5] Installing dependencies...'

# Install system packages — COLMAP is required for camera pose estimation.
apt update
DEBIAN_FRONTEND=noninteractive apt install -y colmap git wget bzip2

# Verify PyTorch, CUDA, and GPU availability inside the container.
python -c \"import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.version.cuda); print('GPU available:', torch.cuda.is_available())\"

# Upgrade pip and install required Python build tools.
python -m pip install --upgrade pip setuptools wheel ninja

# Install Python dependencies for the Gaussian Splatting pipeline.
python -m pip install plyfile tqdm

# Install GraphDeco CUDA submodules:
#   simple-knn         — nearest-neighbour operations during training
#   diff-gaussian-rasterization — differentiable Gaussian renderer (core of GS)
python -m pip install --no-build-isolation submodules/simple-knn
python -m pip install --no-build-isolation submodules/diff-gaussian-rasterization

echo '     Dependencies installed.'

# =============================================================================
# STEP 4: COLMAP — Camera Pose Estimation (Structure-from-Motion)
# =============================================================================

echo ''
echo '🗺️   [3/5] Running COLMAP (Structure-from-Motion)...'

# Validate that input images exist before starting reconstruction.
if [ ! -d '${SCENE_DIR}/images' ]; then
  echo 'ERROR: No images found at ${SCENE_DIR}/images'
  echo 'Place your input images there and re-run the script.'
  exit 1
fi

# Run COLMAP in offscreen mode — required on headless servers with no display.
export QT_QPA_PLATFORM=offscreen

# Convert the image dataset into the COLMAP format expected by GraphDeco.
# --no_gpu disables GPU for COLMAP to avoid compatibility issues on the server.
python convert.py \
  -s '${SCENE_DIR}' \
  --no_gpu

echo '    COLMAP reconstruction complete.'

# =============================================================================
# STEP 5: Train the Gaussian Splatting Model
# =============================================================================

echo ''
echo '  [4/5] Training 3D Gaussian Splatting model...'
echo '    ⏳  This is the long step — monitor progress in the logs below.'
echo '    ℹ️   --resolution 4 reduces image resolution by 4x to fit GPU memory.'
echo ''

# Train the Gaussian Splatting model.
# Inside Docker, the selected host GPU is always exposed as CUDA device 0.
# --resolution 4: downscales input images by 4x (required for large datasets on the DGX server)
CUDA_VISIBLE_DEVICES=0 python train.py \
  -s '${SCENE_DIR}' \
  -m '${OUTPUT_DIR}' \
  --resolution 4

echo '     Training complete.'

# =============================================================================
# STEP 6: Export — Copy Final .ply to Fixed Location
# =============================================================================

echo ''
echo '  [5/5] Exporting final .ply file...'

# Find the latest generated point_cloud.ply inside the training output folder.
LATEST_PLY=\$(find '${OUTPUT_DIR}/point_cloud' -name 'point_cloud.ply' | sort -V | tail -n 1)

# Exit if no .ply file was generated (training may have failed silently).
if [ -z \"\$LATEST_PLY\" ]; then
  echo 'ERROR: No point_cloud.ply was generated. Check training logs above.'
  exit 1
fi

# Copy to a fixed, easy-to-find location for upload to SuperSplat or Unreal Engine.
cp \"\$LATEST_PLY\" '${FINAL_PLY}'

# =============================================================================
# DONE
# =============================================================================

echo ''
echo ' Complete!                   
echo ''
echo '  Final .ply saved at:'
echo '  ${FINAL_PLY}'
echo ''
