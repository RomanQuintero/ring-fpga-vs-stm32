"""Export exact runtime reference, requantization thresholds and test vectors."""
from pathlib import Path
import json
import numpy as np

ROOT = Path(__file__).resolve().parent
d = np.load(ROOT / 'pong_mlp_int8.npz')
f = np.load(ROOT / 'pong_mlp.npz')
for name, shape, dtype in [('W1',(5,16),'int8'),('B1',(16,),'int32'),
                           ('W2',(16,3),'int8'),('B2',(3,),'int32')]:
    assert d[name].shape == shape and d[name].dtype == dtype
# Verify the supplied header against every model constant.
import re
header = (ROOT / 'pong_weights.svh').read_text()
for name in ('W1','B1','W2','B2'):
    block = header.split(' ' + name + ' ')[1].split(';')[0]
    values = [int(sign + value) for sign, value in re.findall(r"(-?)\d+'sd(\d+)", block)]
    assert values == d[name].ravel().tolist(), name

bound = int(np.max(np.abs(d['B1'].astype(np.int64)) +
                   128 * np.abs(d['W1'].astype(np.int64)).sum(axis=0)))
domain = np.arange(bound + 1, dtype=np.int64)
rounded = np.clip(np.round(domain * d['SH']), 0, 127).astype(np.int64)
thresholds = [int(np.flatnonzero(rounded >= q)[0]) for q in range(1,128)]
assert np.array_equal(np.searchsorted(thresholds, domain, side='right'), rounded)
(ROOT / 'pong_requant.svh').write_text(
    '// Exact thresholds for numpy float64 multiply + round-to-even, fixed exported SH.\n'
    'localparam logic signed [31:0] HQ_THRESHOLD [1:127] = \'{\n    ' +
    ', '.join("32'sd" + str(v) for v in thresholds) + '\n};\n')

def infer(x):
    a1 = x.astype(np.int32) @ d['W1'].astype(np.int32) + d['B1']
    h = np.clip(np.round(np.maximum(a1,0) * d['SH']),0,127).astype(np.int8)
    a2 = h.astype(np.int32) @ d['W2'].astype(np.int32) + d['B2']
    return a1, h, a2, np.argmax(a2,axis=1)

x = np.clip(np.round(f['X_test'] * d['SX']),-127,127).astype(np.int8)
a1,h,a2,pred = infer(x)
assert int(np.maximum(a1,0).max()) == 18670
assert float(d['SH']) == 127.0 / 18670
# Extra full INT8 domain corner cases and deterministic random inputs.
import itertools
corners = np.array(list(itertools.product([-128,0,127], repeat=5)),dtype=np.int8)
random = np.random.default_rng(42).integers(-128,128,(10000,5),dtype=np.int16).astype(np.int8)
all_x = np.concatenate([x,corners,random])
_,all_h,all_a2,actions = infer(all_x)
with (ROOT / 'vectors.txt').open('w') as out:
    for xi,hi,oi,action in zip(all_x,all_h,all_a2,actions):
        out.write(' '.join(map(str,[*xi,*hi,*oi,action])) + '\n')
report = dict(real_test_vectors=len(x),corner_vectors=len(corners),random_vectors=len(random),
              total_vectors=len(all_x),requant_domain_checked=bound+1,
              int8_accuracy=float(np.mean(pred == f['y_test'])),SH=float(d['SH']),
              accumulator1_bound=bound,
              accumulator2_bound=int(np.max(np.abs(d['B2'].astype(np.int64))+
                 127*np.abs(d['W2'].astype(np.int64)).sum(axis=0))))
(ROOT / 'reference_report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
