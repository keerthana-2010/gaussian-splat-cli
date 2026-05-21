# 🫧 Gaussian Splatting CLI Pipeline

> **Automated, headless pipeline to reconstruct real-world environments as 3D Gaussian Splats (.ply) — no GUI required.**

Built as part of an academic project at **TH OWL (Technische Hochschule Ostwestfalen-Lippe)** — *Gamification Innovation Lab, Winter Term 2025*.

The goal: photograph a real university campus → run one script → get a navigable 3D scene inside **Unreal Engine 5**.

---

## 🎯 What This Does

This pipeline automates the entire 3D Gaussian Splatting workflow from raw images to a game-engine-ready `.ply` file — entirely from the terminal, without any graphical interface. It was designed to run on high-performance GPU servers (we used a **NVIDIA DGX A100**) via SSH.

```
📷 Input Images
      │
      ▼
 COLMAP (SfM)       ←  Estimates camera positions for every image
      │
      ▼
 convert.py         ←  Prepares COLMAP output for Gaussian Splatting
      │
      ▼
 train.py           ←  Trains 3D Gaussians to represent the scene
      │
      ▼
 point_cloud.ply    ←  Your 3D Gaussian Splat, ready to view or import
      │
      ▼
 SuperSplat          ←  Browser-based cleanup & noise removal
      │
      ▼
 Unreal Engine 5    ←  Real-time interactive 3D environment
```

---

## ⚙️ Requirements

The script runs entirely inside Docker — no manual dependency installs needed on the host.

| Requirement  | Details                                                   |
|--------------|-----------------------------------------------------------|
| Host OS      | Linux (tested on Ubuntu 20.04+)                           | 
| GPU          | NVIDIA CUDA-capable — we used a **DGX A100**              |
| Docker       | Installed and running on the host                         |
| Docker Image | `nvcr.io/nvidia/pytorch:24.01-py3` (pulled automatically) |

Everything else — **COLMAP, PyTorch, CUDA submodules, plyfile, tqdm** — is installed automatically inside the container when the script runs.

---

## 🚀 Usage

### 1. Clone this repo
```bash
git clone https://github.com/keerthana-2010/gaussian-splatting-cli.git
cd gaussian-splatting-cli
```

### 2. Add your images
```bash
cp /path/to/your/images/* input/
```

> 💡 **Tip:** 30–300 overlapping images work best. Aim for ~80% overlap between consecutive shots.

### 3. Configure the script
Open `gaussian_splatting.sh` and update these variables at the top:

```bash
GPU_ID=0                          # Check free GPU with: nvidia-smi


### 4. Add your images
Place your input images at:
```
/workspace/gs_pipeline/my_scene/images/
```

### 5. Run the pipeline
```bash
bash gaussian_splatting.sh
```

The script handles everything automatically inside a Docker container:
- Clones/updates the GraphDeco Gaussian Splatting repo
- Installs COLMAP and all Python dependencies
- Runs COLMAP for camera pose estimation
- Trains the Gaussian Splatting model
- Copies the final `.ply` to a fixed output location

---

## 📂 Output

```
output/
└── point_cloud/
    └── iteration_30000/
        └── point_cloud.ply   ← Your 3D Gaussian Splat
```

**Training parameters used in this project:**

Dataset: ~6 GB (Detmold campus)
Resolution: scaled down by factor of 4 (--resolution 4)
Framework: Graphdeco GS on DGX A100

---

## ⚠️ A Note on COLMAP and GPU

You might wonder why COLMAP runs on **CPU** (`--no_gpu`) while the Gaussian Splatting training uses the GPU.

The reason: `apt install colmap` (which is how COLMAP is installed inside the Docker container) installs a **pre-built binary that does not include CUDA support**. GPU-accelerated COLMAP requires building from source with CUDA-enabled dependencies — which is a complex process on a shared server environment.

> The official COLMAP documentation confirms this: *"Packages from distribution repositories typically do NOT include CUDA support."*

At the time of running this project, GPU availability on the DGX server was also limited due to shared usage across users. Running COLMAP on CPU was therefore both the practical and correct choice for this environment. COLMAP's CPU performance is sufficient for feature extraction and matching — the GPU bottleneck is in the Gaussian Splatting training step, not COLMAP.

---

## 🖥️ Post-Processing with SuperSplat

After generating the `.ply`, we used **[SuperSplat](https://playcanvas.com/supersplat/editor)** (browser-based, no install) to:

- Visually inspect the reconstruction
- Remove floating artifacts and noise
- Export a clean `.ply` ready for Unreal Engine
- export with SH = 3 to get unreal engine compitable .ply file

---

## 🎮 Unreal Engine 5 Integration

The cleaned `.ply` was imported into **Unreal Engine 5.1.1** using the **[X3DGS Plugin](https://github.com/YHK-UEPlugins-Public/018_UEGaussianSplatting_Public)** to create a real-time, first-person navigable campus environment.

> **Note:** Use Unreal Engine 5.1.1 specifically — newer versions do not have stable `.ply` import support for Gaussian Splats at the time of this project.

Steps:
1. Install Unreal Engine 5.1.1 via Epic Games Launcher
2. Install the X3DGS plugin
3. Import your refined `.ply` file
4. Build your scene and add interactivity using the first-person template

---

## 🏫 Project Context

This pipeline was developed as part of the **Gamification Innovation Lab** module at TH OWL. The objective was to reconstruct the **InnovationSPIN building** on campus from GoPro footage, train a Gaussian Splat model, and integrate it into an interactive Unreal Engine experience.

Two pipelines were explored:

|             | Pipeline 1 (GUI)               | Pipeline 2 (This repo — CLI) |
|-------------|--------------------------------|------------------------------|
| Tools       | RealityScan + LichtFeld Studio |COLMAP + Graphdeco GS         |
| Environment | Local GPU (RTX 4060)           | DGX A100 Server (SSH)        |
| Dataset     | ~60 GB                         | ~6 GB                        |
| Automation  | Manual                         | Fully scripted               |
| Interface   | GUI                            | Headless / Terminal          |

**This repo implements Pipeline 2** — the automated, server-compatible, GUI-free workflow.

---

## 👩‍💻 Authors

 Keerthana Kothakapu Adamulla
 Nithya Kanakam 
 
---

## 📚 References

- Kerbl et al., *3D Gaussian Splatting for Real-Time Radiance Field Rendering*, SIGGRAPH 2023 — [Paper](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/) · [Code](https://github.com/graphdeco-inria/gaussian-splatting)
- [COLMAP](https://colmap.github.io/) — Structure-from-Motion and Multi-View Stereo
- [SuperSplat](https://playcanvas.com/supersplat/editor) — Browser-based Gaussian Splat viewer and editor
- [X3DGS Unreal Engine Plugin](https://github.com/YHK-UEPlugins-Public/018_UEGaussianSplatting_Public)

---

## 📄 License

For educational and research purposes. The 3D Gaussian Splatting framework is subject to its [original license](https://github.com/graphdeco-inria/gaussian-splatting/blob/main/LICENSE.md).
