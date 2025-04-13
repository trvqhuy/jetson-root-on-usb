#!/bin/bash

# Define tasks as an associative array
declare -A TASKS=(
  ["Install system dependencies"]="Installing apt packages|for i in {1..3}; do sudo apt-get update && break; sleep 1; done && sudo apt-get install -y \
    python3-pip python3-virtualenv \
    libjpeg-dev libopenblas-base libopenmpi-dev libomp-dev \
    build-essential cmake gfortran libatlas-base-dev \
    chromium-chromedriver firefox \
    libtiff5-dev libavcodec-dev libavformat-dev libswscale-dev \
    libgtk2.0-dev libcanberra-gtk* libxvidcore-dev libx264-dev \
    libgtk-3-dev libhdf5-serial-dev libqtgui4 libqtwebkit4 libqt4-test \
    libdc1394-22-dev libsm6 libxext6 libxrender-dev python3-matplotlib"
  ["Install Python build tools"]="Upgrading pip + tools|python3 -m pip install --upgrade pip setuptools wheel Cython"
  ["Install scientific libraries"]="Installing NumPy, SciPy, PyBind11|python3 -m pip install numpy==1.19.5 scipy==1.5.4 pybind11==2.6.2"
  ["Install ML & CV libraries"]="Installing sklearn, scikit-image, tqdm, pillow|python3 -m pip install scikit-learn==0.24.2 scikit-image==0.17.2 tqdm==4.62.3 pillow==8.4.0"
  ["Install EasyOCR"]="Installing EasyOCR|python3 -m pip install easyocr==1.4"
  ["Install web stack"]="Installing FastAPI, Uvicorn, etc.|python3 -m pip install fastapi==0.70.0 uvicorn[standard]==0.17.0 slowapi==0.1.5 \
    requests==2.27.1 python-dotenv==0.20.0 selenium==3.141.0"
  ["Check OpenCV CUDA support"]="Checking OpenCV CUDA|python3 -c 'import cv2; print(\"🚀 CUDA available:\", cv2.cuda.getCudaEnabledDeviceCount() > 0)'"
)