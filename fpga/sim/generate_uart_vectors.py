"""Independent exact rational input adapter + unchanged NumPy INT8 network."""
from pathlib import Path
from fractions import Fraction
import numpy as np
root=Path(__file__).resolve().parent
d=np.load(root/'pong_mlp_int8.npz')
def adapt(side,v):
    bx,by,vx,vy,own,opp,w,h,ph=v
    vals=[Fraction(w-bx if side=='L' else bx,w),Fraction(by,h),
          Fraction(-vx if side=='L' else vx,540),Fraction(vy,540),Fraction(own,h)]
    return np.array([max(-127,min(127,round(a*127))) for a in vals],dtype=np.int8)
def action(x):
    a=x.astype(np.int32)@d['W1'].astype(np.int32)+d['B1']
    h=np.clip(np.round(np.maximum(a,0)*d['SH']),0,127).astype(np.int32)
    o=h@d['W2'].astype(np.int32)+d['B2']
    return ['UP','STAY','DOWN'][int(np.argmax(o))]
cases=[]
for side in ['L','R']:
    for own in [40,240,440]:
        for by in [30,240,450]:
            cases.append((side,[424,by,-440,310,own,200,960,480,80]))
cases += [('R',[1,1,270,-270,1,0,254,254,80]),
          ('L',[959,479,-540,540,479,240,960,480,80]),
          ('R',[-2147483648,2147483647,-2147483648,2147483647,240,0,960,480,80]),
          ('L',[-2147483648,0,-2147483648,0,240,0,2147483647,480,80])]
rng=np.random.default_rng(15)
for i in range(16):
    cases.append(('L' if i%2 else 'R',[int(rng.integers(0,961)),int(rng.integers(0,481)),
     int(rng.integers(-540,541)),int(rng.integers(-540,541)),int(rng.integers(40,441)),240,960,480,80]))
with (root/'uart_vectors.txt').open('w') as f:
    for i,(side,v) in enumerate(cases):
        tick=9223372036854775807 if i==0 else 638950000000000000+i*2
        x=adapt(side,v)
        f.write('STATE,1,'+str(tick)+','+side+','+','.join(map(str,v))+'\n')
        f.write(f'ACT,1,{tick},{action(x)}\n')
        f.write(' '.join(map(str,x))+'\n')
print(f'Generated {len(cases)} STATE/ACT pairs')
