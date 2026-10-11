"""Create independent NumPy reference from existing training code and weights."""
import ast
from pathlib import Path
import re
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
source = ast.parse((ROOT / 'python/train_model.py').read_text(encoding='utf-8-sig'))
func = next(n for n in source.body if isinstance(n, ast.FunctionDef) and n.name == 'extract_features')
scope = {'np': np}
exec(compile(ast.Module(body=[func], type_ignores=[]), 'train_model.py', 'exec'), scope)
header = (ROOT / 'esp32/fall_detection_esp32/model_weights.h').read_text(encoding='utf-8-sig')


def weight(name, shape):
    match = re.search(r'static const float\s+' + name + r'\[[^=]+?=\s*(\{.*?\});', header, re.S)
    return np.array(ast.literal_eval(match[1].replace('{', '[').replace('}', ']')
                                    .replace('f', '')), dtype=np.float64).reshape(shape)


mean, std = weight('FEATURE_MEAN', (30,)), weight('FEATURE_STD', (30,))
w1, b1 = weight('W1', (30, 16)), weight('BIAS1', (16,))
w2, b2 = weight('W2', (16, 8)), weight('BIAS2', (8,))
w3, b3 = weight('W3', (8, 5)), weight('BIAS3', (5,))
windows = np.load(ROOT / 'data/synthetic_imu_data.npz')['X'].astype(np.float32)
# Include constant/near-constant inputs that expose unstable variance formulas.
extra = np.zeros((2, 50, 6), dtype=np.float32)
extra[0, :, 2] = 1
extra[1] = 0.00001
windows = np.concatenate((windows, extra))
with Path(sys.argv[1]).open('wb') as f:
    for window in windows:
        features = scope['extract_features'](window.astype(np.float64))
        normalized = (features - mean) / std
        h1 = np.maximum(0, normalized @ w1 + b1)
        h2 = np.maximum(0, h1 @ w2 + b2)
        logits = h2 @ w3 + b3
        probs = np.exp(logits - logits.max())
        probs /= probs.sum()
        for array in (window, features, normalized, [probs.argmax(), probs.max()]):
            f.write(np.asarray(array, dtype='<f4').tobytes())
print('Reference windows:', len(windows))
