# Training, quantization and HDL export

Existing scripts and model files. `quant.py` was renamed to `quantize.py` without changing its contents. Model NPZ files in the original ML and FPGA folders agree by SHA-256.

Run from this directory with Python, NumPy and scikit-learn:

```powershell
python train.py
python quantize.py
python export_hdl.py
```

Training replaces the local model; it is unnecessary for running RING or simulating the included models. The network is 5→16→3; an original training-script print label incorrectly says 5→8→3, while its actual matrices contain 16 hidden neurons.

`export_hdl.py` writes `pong_weights.svh` here. Before integrating a new model, inspect its scales and weights, then update `../fpga/rtl/pong_weights.svh`, regenerate requantization/vectors and repeat equivalence and timing checks. Packaging does not retrain or change the model.
