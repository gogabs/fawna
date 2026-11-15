# Emissor do bambu (recursos/amb_bambu.ogg): madeira oca batendo, gerada por código.
# Uso: python tools/sons_recursos.py (precisa de numpy, scipy, soundfile e ffmpeg).
import numpy as np,soundfile as sf,subprocess,os
from scipy.signal import butter,sosfilt
SR=48000; OUT=os.path.join(os.path.dirname(__file__),'..','assets','sounds','recursos'); os.makedirs(OUT,exist_ok=True)
import json

def bp(x,lo,hi,o=2): return sosfilt(butter(o,[lo,hi],'bp',fs=SR,output='sos'),x)
def rajada(rng,dur,lo,hi,crack=1.0):
    """uma rajada de folhas: ruído filtrado com envelope irregular + estalinhos"""
    n=int(dur*SR); t=np.arange(n)/SR
    w=bp(rng.standard_normal(n),lo,hi)
    k=max(4,int(dur*40)); e=np.abs(rng.standard_normal(k))**1.5
    e=np.interp(np.arange(n),np.linspace(0,n,k),e); e=np.convolve(e,np.ones(int(SR*.004))/int(SR*.004),'same')
    sw=np.sin(np.pi*np.clip(t/dur,0,1))**1.5
    y=w*e*sw
    # estalinhos de folha seca
    for _ in range(int(dur*18*crack)):
        i=rng.integers(0,n-300); m=rng.integers(40,200)
        c=bp(rng.standard_normal(m),rng.uniform(2500,5000),rng.uniform(6000,10000))*np.linspace(1,0,m)**2
        y[i:i+m]+=c*rng.uniform(.5,2.5)*sw[i]
    return y
def cama(rng,dur,lo=900,hi=5500):
    n=int(dur*SR); w=bp(rng.standard_normal(n),lo,hi)
    k=int(dur*6)+3; m=np.interp(np.arange(n),np.linspace(0,n,k),rng.uniform(.3,1,k)); return w*m
def gota(f0=900,f1=2300,dur=.22,rng=None):
    """pingo ascendente: senóide com glissando exponencial subindo e envelope curto (como gota ao contrário)"""
    n=int(dur*SR); t=np.arange(n)/SR; f=f0*(f1/f0)**(t/dur)
    ph=2*np.pi*np.cumsum(f)/SR; y=np.sin(ph)+.25*np.sin(2*ph)
    env=np.minimum(1,t/.006)*np.exp(-t/(dur*.38)); return y*env
def norm_act(y,db):
    b=y[:len(y)//480*480].reshape(-1,480); e=np.sqrt((b**2).mean(1)); e=e[e>e.max()*.1]
    return y*10**(db/20)/(np.sqrt((e**2).mean())+1e-9)
def save(name,y,peak=-1):
    p=np.abs(y).max()
    if p>10**(peak/20): y=y*10**(peak/20)/p
    w=f'{OUT}/{name}.wav'; sf.write(w,y.astype(np.float32),SR)
    subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-y','-i',w,'-c:a','libvorbis','-q:a','5',f'{OUT}/{name}.ogg'],check=True); os.remove(w); return name+'.ogg'
def loopfix(y,L,xf=SR):  # dobra o excedente e emenda por crossfade
    y=y.copy(); out=y[:L].copy(); ex=y[L:L+xf]; t=np.linspace(0,np.pi/2,len(ex))
    out[:len(ex)]=out[:len(ex)]*np.sin(t)+ex*np.cos(t); return out
def cena(seed,dur,n,lo,hi,rmin,rmax,bed=0,ping=None,crack=1.0):
    rng=np.random.default_rng(seed); L=int(dur*SR); y=np.zeros(L+3*SR)
    for _ in range(n):
        d=rng.uniform(rmin,rmax); r=rajada(rng,d,lo,hi,crack); i=int(rng.uniform(0,dur)*SR); y[i:i+len(r)]+=r*rng.uniform(.5,1)
    y=loopfix(y,L,SR*2)
    if bed: 
        b=cama(rng,dur+2,lo*.8,hi*.7); b=loopfix(np.pad(b,(0,SR*2)),L,SR*2); y=y/ (np.sqrt((y**2).mean())+1e-9)+bed*b/(np.sqrt((b**2).mean())+1e-9)
    if ping:
        g=np.zeros(L+SR)
        for t,f0,f1 in ping:
            x=gota(f0,f1); a=int(t*SR); g[a:a+len(x)]+=x
        gn=g[:L]; gn[:SR//2]+=0
        y=y/(np.sqrt((y**2).mean())+1e-9)*0.35+g[:L]*0.5
        y[:len(g[L:])]+=g[L:]*.5*0   # sem cauda além do fim
    return y

def toc(f0,dec,rng,bright=1.0):
    n=int(SR*dec*6); t=np.arange(n)/SR; y=np.zeros(n)
    # modos de tubo/barra livre (madeira oca), levemente desafinados
    for r,a,d in [(1,1,1),(2.76,.45*bright,.55),(5.40,.18*bright,.3),(1.5,.12,.7)]:
        f=f0*r*rng.uniform(.99,1.01); y+=a*np.sin(2*np.pi*f*t+rng.uniform(0,6))*np.exp(-t/(dec*d))
    # clique de ataque: ruído curto filtrado
    k=int(SR*.004); cl=rng.standard_normal(k)*np.linspace(1,0,k)**2
    cl=sosfilt(butter(2,[f0*2,min(f0*9,20000)],'bp',fs=SR,output='sos'),cl)
    y[:k]+=cl*.6*bright
    y*=np.minimum(1,t/0.0008)
    return y/np.abs(y).max()
def variante(seed,dur,pitches,dec,bright,rate,vento):
    rng=np.random.default_rng(seed); L=int(dur*SR); y=np.zeros(L+SR*2)
    t=rng.uniform(.2,1.0)
    while t<dur:
        # um grupo: dois colmos batendo, 1 a 4 tocs
        nk=rng.choice([1,2,2,3,3,4]); tt=t; amp=rng.uniform(.35,1)
        for k in range(nk):
            f0=pitches[rng.integers(len(pitches))]*rng.uniform(.98,1.02)
            x=toc(f0,dec*rng.uniform(.8,1.2),rng,bright)*amp*rng.uniform(.6,1)
            i=int(tt*SR); y[i:i+len(x)]+=x[:len(y)-i]; tt+=rng.uniform(.05,.18); amp*=rng.uniform(.6,.95)
        t+=rng.exponential(1/rate)+.4
    # dobra o que passou do fim para o começo (loop sem emenda)
    y[:len(y)-L]+=y[L:]; y=y[:L]
    if vento:
        w=rng.standard_normal(L); w=sosfilt(butter(2,[150,900],'bp',fs=SR,output='sos'),w)
        m=np.convolve(rng.standard_normal(L//4800+3),np.ones(3)/3,'same'); m=np.interp(np.arange(L),np.linspace(0,L,len(m)),m)
        m=(m-m.min())/(m.max()-m.min()+1e-9); w*=0.3+0.7*m
        # emenda do vento: crossfade circular
        k=SR; w[:k]=w[:k]*np.linspace(0,1,k)+w[-k:]*np.linspace(1,0,k)
        y+=w/np.sqrt((w**2).mean())*np.sqrt((y**2).mean())*vento
    y=sosfilt(butter(1,90,'hp',fs=SR,output='sos'),y)
    return y
def salvar(nome,y,rms_db=-30):
    y=y*10**(rms_db/20)/np.sqrt((y**2).mean()); p=np.abs(y).max()
    if p>.89: y*=.89/p
    w=f'{OUT}/{nome}.wav'; sf.write(w,y.astype(np.float32),SR)
    subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-y','-i',w,'-c:a','libvorbis','-q:a','5',f'{OUT}/{nome}.ogg'],check=True); os.remove(w)
salvar('amb_bambu',variante(1,30,[420,505,560,640],.07,1.0,.45,0))

# Emissor do arbusto com frutas (recursos/amb_frutas.ogg): farfalhar contínuo
# baixinho com gotinhas ascendentes frequentes, simbolizando a frutinha.
rng = np.random.default_rng(42); dur = 30
ts = np.sort(rng.uniform(1, dur - 2, 9))
while np.min(np.diff(ts)) < 1.6:
    ts = np.sort(rng.uniform(1, dur - 2, 9))
ping = [(float(t), float(rng.uniform(800, 1500)), float(rng.uniform(2000, 3400))) for t in ts]
y = cena(3, dur, 8, 1200, 6500, .6, 1.5, bed=.8, ping=ping, crack=.8)
y = y * 10 ** (-37 / 20) / (np.sqrt((y ** 2).mean()) + 1e-9)
save('amb_frutas', y)
