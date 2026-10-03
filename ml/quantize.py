import numpy as np

d = np.load("pong_mlp.npz")

W1 = d["W1"]
B1 = d["B1"]
W2 = d["W2"]
B2 = d["B2"]
X  = d["X_test"]
y  = d["y_test"]

# --------------------------------------------------
# FLOAT reference
# sklearn MLP: X @ W + B
# --------------------------------------------------

Hf = np.maximum(0.0, X @ W1 + B1)
Of = Hf @ W2 + B2
pred_float = np.argmax(Of, axis=1)

# --------------------------------------------------
# Fixed-point quantization
#
# Inputs: Q7-ish signed int8, scale 127
# W1/W2: symmetric int8
# Hidden activations are requantized to int8 [0,127]
# Accumulators/biases: int32
# --------------------------------------------------

SX = 127.0

SW1 = 127.0 / np.max(np.abs(W1))
W1q = np.round(W1 * SW1).astype(np.int8)

Xq = np.clip(
    np.round(X * SX),
    -127, 127
).astype(np.int8)

# Layer 1 accumulator scale = SX * SW1
B1q = np.round(B1 * SX * SW1).astype(np.int32)

acc1 = (
    Xq.astype(np.int32) @ W1q.astype(np.int32)
    + B1q
)

# ReLU
acc1 = np.maximum(acc1, 0)

# Requantize hidden layer dynamically to [0,127]
max_h = np.max(acc1)

SH = 127.0 / max_h if max_h > 0 else 1.0

Hq = np.clip(
    np.round(acc1 * SH),
    0, 127
).astype(np.int8)

# Effective real scale represented by Hq:
# real_hidden = Hq / (SH * SX * SW1)
hidden_real_scale = SH * SX * SW1

# Layer 2
SW2 = 127.0 / np.max(np.abs(W2))
W2q = np.round(W2 * SW2).astype(np.int8)

# acc2 scale = hidden_real_scale * SW2
B2q = np.round(
    B2 * hidden_real_scale * SW2
).astype(np.int32)

acc2 = (
    Hq.astype(np.int32) @ W2q.astype(np.int32)
    + B2q
)

pred_int = np.argmax(acc2, axis=1)

# --------------------------------------------------
# Results
# --------------------------------------------------

float_accuracy = np.mean(pred_float == y)
int_accuracy   = np.mean(pred_int == y)
agreement      = np.mean(pred_float == pred_int)

print(f"Float accuracy:        {float_accuracy:.4%}")
print(f"INT8 accuracy:         {int_accuracy:.4%}")
print(f"Float/INT8 agreement:  {agreement:.4%}")

print()
print(f"Different decisions:   {np.sum(pred_float != pred_int)} / {len(X)}")

print()
print("Scales:")
print("SX =", SX)
print("SW1 =", SW1)
print("SH =", SH)
print("SW2 =", SW2)

np.savez(
    "pong_mlp_int8.npz",
    W1=W1q,
    B1=B1q,
    W2=W2q,
    B2=B2q,
    SX=SX,
    SW1=SW1,
    SH=SH,
    SW2=SW2,
)

print("\nSaved: pong_mlp_int8.npz")