$LLAMACPP_REPO=".\llama.cpp"
$INSTALL_DIR="E:\llama.cpp"

Set-Location $LLAMACPP_REPO
git pull

Write-Host "Configuring build ..."
cmake -B build `
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" `
    -DCMAKE_CUDA_ARCHITECTURES="61;86" `
    -DGGML_NATIVE=OFF `
    -DGGML_CUDA=ON

Write-Host "Building ..."
cmake --build build --config Release --parallel
Write-Host "Build completed."

Write-Host "Installing ..."
cmake --install build --config Release
Write-Host "Installation completed."

Write-Host "Cleaning up build ..."
Remove-Item -Recurse -Force .\build
Write-Host "Clean up complete."