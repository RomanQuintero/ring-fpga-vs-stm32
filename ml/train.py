# train.py
import numpy as np
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score

SEED = 42
N = 100_000

rng = np.random.default_rng(SEED)

# Estado normalizado del juego:
# ball_x, ball_y, ball_vx, ball_vy, paddle_y
ball_x   = rng.uniform(0.0, 1.0, N)
ball_y   = rng.uniform(0.0, 1.0, N)
ball_vx  = rng.uniform(-1.0, 1.0, N)
ball_vy  = rng.uniform(-1.0, 1.0, N)
paddle_y = rng.uniform(0.0, 1.0, N)

X = np.column_stack([
    ball_x,
    ball_y,
    ball_vx,
    ball_vy,
    paddle_y
]).astype(np.float32)

# ---------------------------------------------------------
# "Profesor"
# ---------------------------------------------------------
# La pala está en x = 1.
# Estimamos dónde estará Y cuando la pelota llegue allí.
#
# Primera aproximación deliberadamente sencilla:
# si la pelota viene hacia la pala, anticipamos.
# si se aleja, seguimos aproximadamente su Y actual.
# ---------------------------------------------------------

target_y = ball_y.copy()

towards_paddle = ball_vx > 0.05

time_to_paddle = np.zeros(N)
time_to_paddle[towards_paddle] = (
    (1.0 - ball_x[towards_paddle])
    / ball_vx[towards_paddle]
)

target_y[towards_paddle] = (
    ball_y[towards_paddle]
    + ball_vy[towards_paddle] * time_to_paddle[towards_paddle]
)

# Rebote aproximado entre 0 y 1.
# triangular wave: ...0→1→0→1...
target_y = np.mod(target_y, 2.0)
target_y = np.where(target_y > 1.0, 2.0 - target_y, target_y)

DEAD_ZONE = 0.08

# 0 = UP
# 1 = STAY
# 2 = DOWN
y = np.ones(N, dtype=np.int64)

y[target_y < paddle_y - DEAD_ZONE] = 0
y[target_y > paddle_y + DEAD_ZONE] = 2

# ---------------------------------------------------------
# Train / test
# ---------------------------------------------------------

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.20,
    random_state=SEED,
    stratify=y
)

model = MLPClassifier(
    hidden_layer_sizes=(16,),
    activation="relu",
    solver="adam",
    max_iter=300,
    random_state=SEED
)

model.fit(X_train, y_train)

pred = model.predict(X_test)

print(f"Accuracy: {accuracy_score(y_test, pred):.4f}")
print()
print(classification_report(
    y_test,
    pred,
    target_names=["UP", "STAY", "DOWN"]
))

# ---------------------------------------------------------
# Export
# ---------------------------------------------------------

np.savez(
    "pong_mlp.npz",
    W1=model.coefs_[0],
    B1=model.intercepts_[0],
    W2=model.coefs_[1],
    B2=model.intercepts_[1],
    X_test=X_test,
    y_test=y_test,
)

print("Architecture:")
print("  5 -> 8 -> 3")
print()

print("W1:", model.coefs_[0].shape)
print("B1:", model.intercepts_[0].shape)
print("W2:", model.coefs_[1].shape)
print("B2:", model.intercepts_[1].shape)

print("\nSaved: pong_mlp.npz")